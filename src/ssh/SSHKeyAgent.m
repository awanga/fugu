/*
 * Copyright (c) 2003 Regents of The University of Michigan.
 * All Rights Reserved.  See COPYRIGHT.
 */

#import "SSHKeyAgent.h"
#import "NSString(SSHAdditions).h"
#import "NSArray(CreateArgv).h"

#include <errno.h>
#include <fcntl.h>
#include <unistd.h>
#include <string.h>
#include <sys/file.h>
#include <sys/param.h>
#include <sys/wait.h>
#include <util.h>

#include "argcargv.h"

extern char	**environ;

NSString * const SSHKeyAgentErrorDomain = @"SSHKeyAgentErrorDomain";

/* max times to retry a passphrase prompt before giving up */
#define SSHKEYAGENT_MAX_STRIKES	3

static NSError *
sshKeyAgentError( NSString *message )
{
    return( [ NSError errorWithDomain: SSHKeyAgentErrorDomain code: 1
                userInfo: [ NSDictionary dictionaryWithObject: message
                                forKey: NSLocalizedDescriptionKey ]] );
}

@implementation SSHKeyAgent

/*
 * Runs a short, non-interactive command to completion and returns its
 * combined stdout+stderr. Used for ssh-keygen -lf, ssh-add -l, ssh-add -d,
 * none of which ever prompt for input.
 */
+ ( NSString * )runCaptured: ( NSString * )binaryName args: ( NSArray * )args
                  exitStatus: ( int * )exitStatus
{
    NSString		*binPath = [ NSString pathForExecutable: binaryName ];
    char		executable[ MAXPATHLEN ];
    char		**execargs = NULL;
    int			efd[ 2 ];
    pid_t		pid;
    char		buf[ 4096 ];
    ssize_t		rr;
    NSMutableData	*outData;
    NSString		*result;
    int			status = -1;

    if ( exitStatus ) *exitStatus = -1;

    if ( binPath == nil || [ binPath length ] >= MAXPATHLEN ) {
        return( nil );
    }
    strcpy( executable, [ binPath UTF8String ] );

    NSMutableArray *argv = [ NSMutableArray arrayWithObject:
                [ NSString stringWithUTF8String: executable ]];
    [ argv addObjectsFromArray: args ];
    if ( [ argv createArgv: &execargs ] < 0 ) {
        return( nil );
    }

    if ( pipe( efd ) < 0 ) {
        free( execargs );
        return( nil );
    }

    switch (( pid = fork())) {
    case 0:
        if ( dup2( efd[ 1 ], 1 ) < 0 || dup2( efd[ 1 ], 2 ) < 0 ) {
            _exit( 2 );
        }
        ( void )close( efd[ 0 ] );
        ( void )close( efd[ 1 ] );
        execve( executable, execargs, environ );
        _exit( 2 );

    case -1:
        ( void )close( efd[ 0 ] );
        ( void )close( efd[ 1 ] );
        free( execargs );
        return( nil );

    default:
        break;
    }

    free( execargs );
    ( void )close( efd[ 1 ] );

    outData = [ NSMutableData data ];
    while (( rr = read( efd[ 0 ], buf, sizeof( buf ))) > 0 ) {
        [ outData appendBytes: buf length: rr ];
    }
    ( void )close( efd[ 0 ] );

    waitpid( pid, &status, 0 );
    if ( exitStatus ) *exitStatus = WIFEXITED( status ) ? WEXITSTATUS( status ) : -1;

    result = [[[ NSString alloc ] initWithData: outData encoding: NSUTF8StringEncoding ]
                autorelease ];
    return( result ? result : @"" );
}

/*
 * Runs a command that may interactively prompt for a passphrase over a PTY
 * (ssh-add <key>, ssh-keygen -t ...), feeding the given passphrase whenever
 * a "Enter passphrase" / "Enter same passphrase" prompt is seen, and
 * answering "y" to a ssh-keygen overwrite prompt (the caller is expected to
 * have already confirmed the overwrite with the user before calling this).
 * Bounded to SSHKEYAGENT_MAX_STRIKES bad-passphrase attempts.
 */
+ ( BOOL )runInteractive: ( NSString * )binaryName args: ( NSArray * )args
               passphrase: ( NSString * )passphrase
              failPattern: ( NSString * )failPattern
                    error: ( NSError ** )error
{
    NSString		*binPath = [ NSString pathForExecutable: binaryName ];
    char		executable[ MAXPATHLEN ];
    char		**execargs = NULL;
    char		ttyname[ MAXPATHLEN ];
    char		buf[ MAXPATHLEN ];
    int			masterfd, status;
    pid_t		pid;
    FILE		*mfp;
    fd_set		readmask;
    int			strikes = 0;
    BOOL		failed = NO;
    const char		*pass = passphrase ? [ passphrase UTF8String ] : "";

    if ( binPath == nil || [ binPath length ] >= MAXPATHLEN ) {
        if ( error ) *error = sshKeyAgentError(
                [ NSString stringWithFormat: @"Couldn't find %@.", binaryName ]);
        return( NO );
    }
    strcpy( executable, [ binPath UTF8String ] );

    NSMutableArray *argv = [ NSMutableArray arrayWithObject:
                [ NSString stringWithUTF8String: executable ]];
    [ argv addObjectsFromArray: args ];
    if ( [ argv createArgv: &execargs ] < 0 ) {
        if ( error ) *error = sshKeyAgentError( @"Failed to build argument list." );
        return( NO );
    }

    if (( pid = forkpty( &masterfd, ttyname, NULL, NULL )) < 0 ) {
        free( execargs );
        if ( error ) *error = sshKeyAgentError(
                [ NSString stringWithFormat: @"forkpty failed: %s", strerror( errno )]);
        return( NO );
    }

    if ( pid == 0 ) {
        execve( executable, execargs, environ );
        _exit( 2 );
    }

    free( execargs );

    if ( fcntl( masterfd, F_SETFL, O_NONBLOCK ) < 0 ) {
        /* non-fatal; select() still gates reads */
    }
    if (( mfp = fdopen( masterfd, "r" )) == NULL ) {
        ( void )close( masterfd );
        if ( error ) *error = sshKeyAgentError( @"fdopen failed." );
        return( NO );
    }
    setvbuf( mfp, NULL, _IONBF, 0 );

    for ( ;; ) {
        FD_ZERO( &readmask );
        FD_SET( masterfd, &readmask );
        if ( select( masterfd + 1, &readmask, NULL, NULL, NULL ) < 0 ) {
            break;
        }
        if ( ! FD_ISSET( masterfd, &readmask )) continue;
        if ( fgets( buf, MAXPATHLEN, mfp ) == NULL ) break;

        if ( strstr( buf, "Enter passphrase" ) != NULL
                || strstr( buf, "Enter same passphrase" ) != NULL ) {
            if ( strikes >= SSHKEYAGENT_MAX_STRIKES ) {
                /* give up rather than loop forever on a wrong passphrase */
                break;
            }
            if ( write( masterfd, pass, strlen( pass )) < 0 ) break;
            if ( write( masterfd, "\n", 1 ) < 0 ) break;
        } else if ( strstr( buf, "already exists" ) != NULL
                && strstr( buf, "Overwrite" ) != NULL ) {
            if ( write( masterfd, "y\n", 2 ) < 0 ) break;
        } else if ( strstr( buf, "Bad passphrase" ) != NULL
                || strstr( buf, "incorrect passphrase" ) != NULL ) {
            strikes++;
        } else if ( failPattern != nil
                && strstr( buf, [ failPattern UTF8String ] ) != NULL ) {
            failed = YES;
        }

        memset( buf, '\0', strlen( buf ));
    }

    fclose( mfp );
    waitpid( pid, &status, 0 );

    if ( failed || strikes >= SSHKEYAGENT_MAX_STRIKES
            || ! WIFEXITED( status ) || WEXITSTATUS( status ) != 0 ) {
        if ( error ) {
            *error = sshKeyAgentError( strikes >= SSHKEYAGENT_MAX_STRIKES ?
                    @"Too many incorrect passphrase attempts." :
                    @"The operation did not complete successfully." );
        }
        return( NO );
    }

    return( YES );
}

+ ( NSArray * )discoverIdentities
{
    NSFileManager	*fm = [ NSFileManager defaultManager ];
    NSString		*sshDir = [ NSHomeDirectory() stringByAppendingPathComponent: @".ssh" ];
    NSArray		*entries;
    NSMutableArray	*identities = [ NSMutableArray array ];
    NSMutableSet	*agentFingerprints = [ NSMutableSet set ];
    NSString		*agentList;
    int			agentStatus = -1;

    entries = [ fm contentsOfDirectoryAtPath: sshDir error: NULL ];
    if ( entries == nil ) return( identities );

    agentList = [ self runCaptured: @"ssh-add" args: [ NSArray arrayWithObject: @"-l" ]
                        exitStatus: &agentStatus ];
    if ( agentStatus == 0 && agentList != nil ) {
        for ( NSString *line in [ agentList componentsSeparatedByString: @"\n" ]) {
            NSArray *fields = [ line componentsSeparatedByString: @" " ];
            if ( [ fields count ] >= 2 ) {
                [ agentFingerprints addObject: [ fields objectAtIndex: 1 ]];
            }
        }
    }

    for ( NSString *name in entries ) {
        NSString	*pubPath, *privPath, *comment = @"", *keyType = @"", *fingerprint = @"";
        NSString	*pubContents;
        NSArray		*pubFields;
        NSString	*info;
        int		infoStatus = -1;

        if ( ! [ name hasSuffix: @".pub" ] ) continue;

        pubPath = [ sshDir stringByAppendingPathComponent: name ];
        privPath = [ pubPath stringByDeletingPathExtension ];
        if ( ! [ fm fileExistsAtPath: privPath ] ) continue;

        pubContents = [ NSString stringWithContentsOfFile: pubPath
                                encoding: NSUTF8StringEncoding error: NULL ];
        pubFields = [[ pubContents stringByTrimmingCharactersInSet:
                        [ NSCharacterSet whitespaceAndNewlineCharacterSet ]]
                        componentsSeparatedByString: @" " ];
        if ( [ pubFields count ] >= 3 ) {
            comment = [ pubFields objectAtIndex: 2 ];
        }

        info = [ self runCaptured: @"ssh-keygen"
                        args: [ NSArray arrayWithObjects: @"-l", @"-f", pubPath, nil ]
                        exitStatus: &infoStatus ];
        if ( infoStatus == 0 && info != nil ) {
            NSArray *tav = [[ info stringByTrimmingCharactersInSet:
                        [ NSCharacterSet whitespaceAndNewlineCharacterSet ]]
                        componentsSeparatedByString: @" " ];
            if ( [ tav count ] >= 4 ) {
                fingerprint = [ tav objectAtIndex: 1 ];
                keyType = [[ tav lastObject ]
                        stringByTrimmingCharactersInSet:
                            [ NSCharacterSet characterSetWithCharactersInString: @"()" ]];
            }
        }

        [ identities addObject: [ NSDictionary dictionaryWithObjectsAndKeys:
                    pubPath, @"publicKeyPath",
                    privPath, @"privateKeyPath",
                    comment, @"comment",
                    keyType, @"keyType",
                    fingerprint, @"fingerprint",
                    [ NSNumber numberWithBool: [ agentFingerprints containsObject: fingerprint ]],
                        @"loadedInAgent",
                    nil ]];
    }

    return( identities );
}

+ ( BOOL )addIdentityAtPath: ( NSString * )path
                 passphrase: ( NSString * )passphrase
                      error: ( NSError ** )error
{
    return( [ self runInteractive: @"ssh-add" args: [ NSArray arrayWithObject: path ]
                passphrase: passphrase failPattern: nil error: error ] );
}

+ ( BOOL )removeIdentityAtPath: ( NSString * )path error: ( NSError ** )error
{
    int		status = -1;

    [ self runCaptured: @"ssh-add"
                args: [ NSArray arrayWithObjects: @"-d", path, nil ]
                exitStatus: &status ];

    if ( status != 0 ) {
        if ( error ) *error = sshKeyAgentError(
                @"Couldn't remove the identity from ssh-agent." );
        return( NO );
    }
    return( YES );
}

+ ( BOOL )generateKeyAtPath: ( NSString * )path
                        type: ( NSString * )type
                  passphrase: ( NSString * )passphrase
                       error: ( NSError ** )error
{
    NSArray *args = [ NSArray arrayWithObjects:
                @"-t", type, @"-f", path, @"-q", nil ];

    return( [ self runInteractive: @"ssh-keygen" args: args
                passphrase: passphrase
                failPattern: @"Saving key failed" error: error ] );
}

@end
