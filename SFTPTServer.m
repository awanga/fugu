/*
 * Copyright (c) 2003 Regents of The University of Michigan.
 * All Rights Reserved.  See COPYRIGHT.
 */

#import "SFTPTServer.h"
#import "SFTPController.h"
#import	"SFTPNode.h"
#import "NSArray(CreateArgv).h"
#import "NSString-UnknownEncoding.h"
#import "NSString(SSHAdditions).h"
#import "SFTPListingParser.h"

#include <errno.h>
#include <fcntl.h>
#include <unistd.h>
#include <string.h>
#include <sys/file.h>
#include <sys/ioctl.h>
#include <sys/param.h>
#include <sys/wait.h>
#include <sys/time.h>
#include <util.h>

#include "argcargv.h"
#include "fdwrite.h"

extern int	errno;
extern char	**environ;

/* Escape backslash and double-quote in src for use inside sftp "..." quoting.
 * Returns 0 on success, -1 if dst is too small. */
static int
sftpEscapeBytes( const char *src, size_t srclen, char *dst, size_t dstlen )
{
    size_t di = 0, si;
    for ( si = 0; si < srclen; si++ ) {
        unsigned char c = ( unsigned char )src[ si ];
        if ( c == '\\' || c == '"' ) {
            if ( di >= dstlen ) return( -1 );
            dst[ di++ ] = '\\';
        }
        if ( di >= dstlen ) return( -1 );
        dst[ di++ ] = src[ si ];
    }
    if ( di >= dstlen ) return( -1 );
    dst[ di ] = '\0';
    return( 0 );
}

@implementation SFTPTServer

int		cancelflag = 0;
pid_t		sftppid = 0;
int		connecting = 0;
int		connected = 0;
int		master = 0;

- ( id )init
{
    _currentTransferName = nil;
    _sftpRemoteObjectList = nil;
    
    return(( self = [ super init ] ) ? self : nil );
}

/* accessor methods */
- ( void )setCurrentTransferName: ( NSString * )name
{
    if ( _currentTransferName != nil ) {
	[ _currentTransferName release ];
	_currentTransferName = nil;
    }
    
    if ( name != nil ) {
	_currentTransferName = [[ NSString alloc ] initWithString: name ];
    } else {
	_currentTransferName = name;
    }
}

- ( NSString * )currentTransferName
{
    return( _currentTransferName );
}

- ( id )remoteObjectList
{
    return( _sftpRemoteObjectList );
}

- ( void )setRemoteObjectList: ( id )objectList
{
    if ( _sftpRemoteObjectList ) {
        [ _sftpRemoteObjectList release ];
        _sftpRemoteObjectList = nil;
    }
    if ( ! objectList ) {
        return;
    }
    
    _sftpRemoteObjectList = [ objectList retain ];
}
/* end accessor methods */

/* sftp/ftp output handler methods */
- ( BOOL )checkForPasswordPromptInBuffer: ( char * )buf
{
#ifdef notdef
    NSArray             *prompts = nil;
#endif /* notdef */
    BOOL                hasPrompt = NO;
    int                 i, pnum = 0;
    char                *prompts[] = { "password", "passphrase",
                                    "Password:", "PASSCODE:",
                                    "Password for ", "Passcode for ",
				    "CryptoCard Challenge" };
                                    
    if ( buf == NULL ) {
        return( NO );
    }
    
    pnum = ( sizeof( prompts ) / sizeof( prompts[ 0 ] ));
    for ( i = 0; i < pnum; i++ ) {
        if ( strstr( buf, prompts[ i ] ) != NULL ) {
            hasPrompt = YES;
            break;
        }
    }
    
#ifdef notdef
    /* someday we'll allow custom prompt checks */
#endif /* notdef */
    
    return( hasPrompt );
}

- ( BOOL )bufferContainsError: ( char * )buf
{
    BOOL                hasError = NO;
    int                 i, numerrs = 0;
    char                *errors[] = { "Permission denied",
                                    "Couldn't ", "Secure connection ",
                                    "No address associated with",
                                    "Connection refused",
                                    "Request for subsystem",
                                    "Cannot download",
                                    "ssh_exchange_identification",
                                    "Operation timed out",
                                    "no address associated with",
                                    "No route to host",
                                    "Network is unreachable",
                                    "Host is down",
                                    "REMOTE HOST IDENTIFICATION HAS CHANGED" };
                                    
    if ( buf == NULL ) {
        return( NO );
    }
                                    
    numerrs = ( sizeof( errors ) / sizeof( errors[ 0 ] ));
    for ( i = 0; i < numerrs; i++ ) {
        if ( strstr( buf, errors[ i ] ) != NULL ) {
            hasError = YES;
            break;
        }
    }
    
    return( hasError );
}

- ( BOOL )hasDirectoryListingFormInBuffer: ( char * )buf
{
    BOOL                hasDirListForm = NO;
    int                 i, numforms = 0;
    char                *lsforms[] = { "ls -l", "ls", "ls " };
    
    if ( buf == NULL ) {
        return( NO );
    }
    
    numforms = ( sizeof( lsforms ) / sizeof( lsforms[ 0 ] ));
    for ( i = 0; i < numforms; i++ ) {
        if ( strncmp( buf, lsforms[ i ], strlen( lsforms[ i ] )) == 0 ) {
            hasDirListForm = YES;
            break;
        }
    }
    
    return( hasDirListForm );
}

- ( BOOL )unknownHostKeyPromptInBuffer: ( char * )buf
{
    BOOL                isPrompt = NO;
    int                 i, numprompts = 0;
    char                *prompts[] = { "The authenticity of ",
                                        "Host key not found ",
					"differs from the key" };
                                        
    numprompts = ( sizeof( prompts ) / sizeof( prompts[ 0 ] ));
    for ( i = 0; i < numprompts; i++ ) {
        if ( strncmp( buf, prompts[ i ], strlen( prompts[ i ] )) == 0 ) {
            isPrompt = YES;
            break;
        }
    }
    
    return( isPrompt );
}

- ( void )parseTransferProgressString: ( char * )string isUploading: ( BOOL )uploading
	forController: ( id )controller
{
    int			tac, i, pc_index = -1;
    char		*tmp, **tav, *p;
    char		*t_rate, *t_amount, *t_eta;
    
    if (( tmp = strdup( string )) == NULL ) {
	perror( "strdup" );
	exit( 2 );
    }
    
    if (( tac = argcargv( tmp, &tav )) < 5 ) {
	/* not a transfer progress line we're interested in */
	free( tmp );
	return;
    }
    
    for ( i = ( tac - 1 ); i >= 0; i-- ) {
	if (( p = strrchr( tav[ i ], '%' )) != NULL ) {
	    /* found the %-done field */
	    pc_index = i;
	    p = '\0';
	    break;
	}
    }
    
    t_amount = tav[ pc_index + 1 ];
    t_rate = tav[ pc_index + 2 ];
    
    if ( pc_index == ( tac - 5 )) {
	t_eta = tav[ pc_index + 3 ];
    } else {
	t_eta = "--:--";
    }
    
    if ( uploading ) {
	double _val = strtod( tav[ pc_index ], NULL );
	NSString *_amount = [ NSString stringWithUTF8String: t_amount ];
	NSString *_rate   = [ NSString stringWithUTF8String: t_rate ];
	NSString *_eta    = [ NSString stringWithFormat: @"%s ETA", t_eta ];
	dispatch_async( dispatch_get_main_queue(), ^{
	    [ controller updateUploadProgressBarWithValue: _val
			amountTransfered: _amount
			transferRate: _rate
			ETA: _eta ];
	} );
    } else {
	double _val = strtod( tav[ pc_index ], NULL );
	NSString *_amount = [ NSString stringWithUTF8String: t_amount ];
	NSString *_rate   = [ NSString stringWithUTF8String: t_rate ];
	NSString *_eta    = [ NSString stringWithFormat: @"%s ETA", t_eta ];
	dispatch_async( dispatch_get_main_queue(), ^{
	    [ controller updateDownloadProgressBarWithValue: _val
			amountTransfered: _amount
			transferRate: _rate
			ETA: _eta ];
	} );
    }
    
    free( tmp );
}
/* end sftp/ftp output handler methods */

- ( pid_t )getSftpPid
{
    return( sftppid );
}

- ( int )atSftpPrompt
{
    return( atprompt );
}

- ( void )resetPromptState
{
    atprompt = 0;
}

- ( NSString * )retrieveUnknownHostKeyFromStream: ( FILE * )stream
{
    NSString            *key = @"";
    char                buf[ MAXPATHLEN * 2 ];
    
    if ( fgets( buf, MAXPATHLEN * 2, stream ) == NULL ) {
        NSLog( @"fgets: %s\n", strerror( errno ));
    } else if (( key = [ NSString stringWithUTF8String: buf ] ) == nil ) {
        key = @"";
    }
    
    return( key );
}

- ( NSMutableDictionary * )remoteObjectFromSFTPLine: ( char * )object
{
    return( (NSMutableDictionary *)SFTPListingParserParseLine( object ) );
}

- ( void )connectToServerWithParams: ( NSArray * )params
                fromController: ( SFTPController * )controller
{
    fd_set		readmask;
    struct winsize	win_size = { 24, 512, 0, 0 };
    FILE		*mf = NULL;
    int			rc, status, validpw = 0, threestrikes = 0;
    __block int		was_uploading = 0, was_downloading = 0, was_changing = 0, sethomedir = 0;
    __block int		was_removing = 0, was_renaming = 0, was_listing = 0;
    int			suppress_auth_log = 0;
    char		ttyname[ MAXPATHLEN ], **execargs;
    char		buf[ MAXPATHLEN * 2 ];
    NSArray		*argv = nil, *passedInArgs = [ params copy ];
    NSString    	*sftpBinary;

    atprompt = 0;
    remoteDirBuf = [[ NSString alloc ] init ];

    dispatch_async( dispatch_get_main_queue(), ^{ [ controller clearLog ]; } );

    if (( sftpBinary = [ NSString pathForExecutable: @"sftp" ] ) == nil ) {
	NSLog( @"Couldn't find sftp!" );
	[ passedInArgs release ];
	return;
    }

    argv = [ NSArray arrayWithObject: sftpBinary ];

    argv = [ argv arrayByAddingObjectsFromArray: passedInArgs ];
    rc = [ argv createArgv: &execargs ];

    [ passedInArgs release ];

    connecting = 1;
    {
        NSString *_log = [ NSString stringWithFormat: @"sftp launch path is %s.\n", execargs[ 0 ]];
        dispatch_async( dispatch_get_main_queue(), ^{ [ controller addToLog: _log ]; } );
    }

    dispatch_async( dispatch_get_main_queue(), ^{ [ controller updateHostList ]; } );	/* adds new host to pop-up list */
    dispatch_async( dispatch_get_main_queue(), ^{ [ controller setConnectedWindowTitle ]; } );

    switch (( sftppid = forkpty( &master, ttyname, NULL, &win_size ))) {
    case 0:
        execve( execargs[ 0 ], ( char ** )execargs, environ );
        NSLog( @"Couldn't launch sftp: %s", strerror( errno ));
        _exit( 2 );						/* shouldn't get here */

    case -1:
        NSLog( @"forkpty failed: %s", strerror( errno ));
        exit( 2 );

    default:
        break;
    }

    if ( fcntl( master, F_SETFL, O_NONBLOCK ) < 0 ) {	/* prevent master from blocking */
        NSLog( @"fcntl non-block failed: %s", strerror( errno ));
    }

    if (( mf = fdopen( master, "r+" )) == NULL ) {
        NSLog( @"failed to open file stream with fdopen: %s\n", strerror( errno ));
        return;
    }
    setvbuf( mf, NULL, _IONBF, 0 );

    {
        NSString *_log = [ NSString stringWithFormat: @"Slave terminal device is %s.\n", ttyname ];
        dispatch_async( dispatch_get_main_queue(), ^{ [ controller addToLog: _log ]; } );
    }
    {
        NSString *_log = [ NSString stringWithFormat: @"Master fd is %d.\n", master ];
        dispatch_async( dispatch_get_main_queue(), ^{ [ controller addToLog: _log ]; } );
    }

    for ( ;; ) {
        NSAutoreleasePool		*p = [[ NSAutoreleasePool alloc ] init ];
        remoteDirBuf = @"";

        FD_ZERO( &readmask );
        FD_SET( master, &readmask );

        switch( select( master + 1, &readmask, NULL, NULL, NULL )) {
        case -1:
            NSLog( @"select: %s", strerror( errno ));
            break;

        case 0:	/* timeout */
            continue;

        default:
            break;
        }

        if ( FD_ISSET( master, &readmask )) {
            if ( fgets(( char * )buf, MAXPATHLEN, mf ) == NULL ) {
                break;
            }
#ifdef DEBUG
            NSLog( @"buf: %s", ( char * )buf );
#endif /* DEBUG */

            if ( [ self checkForPasswordPromptInBuffer: buf ] && !validpw ) {
                if ( threestrikes > 0 ) {
                    dispatch_async( dispatch_get_main_queue(), ^{ [ controller passError ]; } );
                };
                if ( connecting ) {
                    NSString *_prompt = [ NSString stringWithUTF8String: ( char * )buf ];
                    dispatch_async( dispatch_get_main_queue(), ^{
                        [ controller requestPasswordWithPrompt: ( char * )[ _prompt UTF8String ]];
                    } );
                }
                suppress_auth_log = 1;
            } else if ( strstr(( char * )buf, "rename \"" ) != NULL ) {
                was_renaming = 1;
            } else if ( strstr(( char * )buf, "sftp> " ) != NULL ) {
                atprompt = 1;
                if ( !connected ) {
                    validpw++;
                    suppress_auth_log = 0;
                    dispatch_async( dispatch_get_main_queue(), ^{ [ controller showRemoteFiles ]; } );
                } else if ( !sethomedir ) {
                    dispatch_async( dispatch_get_main_queue(), ^{ [ controller getListing ]; } );
                    sethomedir++;
                } else if ( was_changing || was_renaming ) {
                    dispatch_async( dispatch_get_main_queue(), ^{ [ controller getListing ]; } );
                    was_changing = 0;
                    was_renaming = 0;
                } else {
                    dispatch_sync( dispatch_get_main_queue(), ^{
                        /* check to see if there's anything waiting to be uploaded */
                        if ( [[ controller uploadQ ] count ] ) {
                            NSDictionary	*dict = [[ controller uploadQ ] objectAtIndex: 0 ];

                            was_uploading = 1;
                            if ( [[ dict objectForKey: @"isdir" ] intValue ] ) {
                                NSString *safeRemote = [[ dict objectForKey: @"pathfrombase" ] sftpQuotedPath ];
                                if ( fdwrite( master, "mkdir \"%s\"\n",
                                             ( void * )[ safeRemote UTF8String ] ) < 0 ) {
                                    NSLog( @"Failed to send command: %s", strerror( errno ));
                                }
                            } else {
                                char		*p = " ";
                                NSString    *safeLocal, *safeRemote;

                                if ( [[ NSUserDefaults standardUserDefaults ]
                                                boolForKey: @"RetainFileTimestamp" ] ) {
                                    p = " -P ";
                                }

                                safeLocal  = [[ dict objectForKey: @"fullpath" ] sftpQuotedPath ];
                                safeRemote = [[ dict objectForKey: @"pathfrombase" ] sftpQuotedPath ];
                                if ( fdwrite( master, "put%s\"%s\" \"%s\"\n", p,
                                            ( void * )[ safeLocal UTF8String ],
                                            ( void * )[ safeRemote UTF8String ] ) < 0 ) {
                                    NSLog( @"Failed to send command: %s", strerror( errno ));
                                }
                            }

                            [ self setCurrentTransferName: [[[[ controller uploadQ ] objectAtIndex: 0 ]
                                        objectForKey: @"fullpath" ] lastPathComponent ]];
                            [ controller showUploadProgress ];
                            [ controller updateUploadProgress: 0 ];
                        } else if ( was_uploading ) {
                            was_uploading = 0;
                            [ self setCurrentTransferName: nil ];
                            [ controller updateUploadProgress: 0 ];
                        }

                        /* check download queue */
                        if ( [[ controller downloadQ ] count ] ) {
                            NSDictionary	*dict = [[ controller downloadQ ] objectAtIndex: 0 ];
                            NSString        *transferName = nil;
                            char		*p = " ";
                            char		remote[ MAXPATHLEN ] = { 0 };
                            size_t		len;

                            if ( [[ NSUserDefaults standardUserDefaults ]
                                            boolForKey: @"RetainFileTimestamp" ] ) {
                                p = " -P ";
                            }

                            if (( len = [(NSData*)[ dict objectForKey: @"rpath" ] length ] ) >= MAXPATHLEN ) {
                                /* XXX throw visible error */
                                NSLog( @"remote path too long" );
                                return;
                            }
                            memcpy( remote, [[ dict objectForKey: @"rpath" ] bytes ], len );

                            was_downloading = 1;
                            {
                                char        esc_remote[ MAXPATHLEN * 2 ];
                                NSString    *safeLpath;
                                if ( sftpEscapeBytes( remote, strlen( remote ),
                                                      esc_remote, sizeof( esc_remote ) ) < 0 ) {
                                    NSLog( @"remote path too long after escaping" );
                                    return;
                                }
                                safeLpath = [[ dict objectForKey: @"lpath" ] sftpQuotedPath ];
                                if ( fdwrite( master, "get%s\"%s\" \"%s\"\n", p, esc_remote,
                                        ( void * )[ safeLpath UTF8String ] ) < 0 ) {
                                    NSLog( @"Failed to send command: %s", strerror( errno ));
                                }
                            }

                            transferName = [ NSString stringWithBytesOfUnknownEncoding:
                                                    ( char * )[[ dict objectForKey: @"rpath" ] bytes ]
                                                    length: ( unsigned int )[( NSData * )[ dict objectForKey: @"rpath" ] length ]];
                            [ self setCurrentTransferName: [ transferName lastPathComponent ]];
                            NSString *_dlmsg = [ transferName lastPathComponent ];
                            [ controller showDownloadProgressWithMessage: ( char * )[ _dlmsg UTF8String ]];
                            [ controller removeFirstItemFromDownloadQ ];
                        } else if ( was_downloading ) {
                            was_downloading = 0;
                            [ controller finishedDownload ];
                            [ self setCurrentTransferName: nil ];
                        }

                        /* check remove queue */
                        if ( [[ controller removeQ ] count ] ) {
                            was_removing = 1;
                            [ controller deleteFirstItemFromRemoveQueue ];
                        } else if ( was_removing ) {
                            was_removing = 0;
                            [ controller getListing ];
                        } else if ( was_listing ) {
                            was_listing = 0;
                            [ controller finishedCommand ];
                        }
                    } );
                }
            } else {
                atprompt = 0;

                if ( strncmp(( char * )buf, "Permission denied, ",
                                strlen( "Permission denied, " )) == 0 ) {
                    suppress_auth_log = 0;
                    threestrikes++;
                } else if ( [ self bufferContainsError: buf ] ) {
                    NSString *_err = [ NSString stringWithUTF8String: buf ];
                    dispatch_async( dispatch_get_main_queue(), ^{ [ controller connectionError: _err ]; } );
                } else if ( [ self currentTransferName ] != nil ) {
                    if ( strstr(( char * )buf, [[ self currentTransferName ] UTF8String ] ) != NULL
                                && strrchr(( char * )buf, '%' ) != NULL ) {
                        if ( was_downloading ) {
                            [ self parseTransferProgressString: ( char * )buf
                                    isUploading: NO
                                    forController: controller ];
                        } else if ( was_uploading ) {
                            [ self parseTransferProgressString: ( char * )buf
                                    isUploading: YES
                                    forController: controller ];
                        }
                    }
                } else if ( strstr(( char * )buf, "passphrase for key" ) != NULL ) {
                    suppress_auth_log = 1;
                    threestrikes = 0;	/* if pubkey auth fails, password prompt will appear */
                    NSString *_prompt = [ NSString stringWithUTF8String: ( char * )buf ];
                    dispatch_async( dispatch_get_main_queue(), ^{
                        [ controller requestPasswordWithPrompt: ( char * )[ _prompt UTF8String ]];
                    } );
                } else if ( strstr(( char * )buf, "Changing owner on" ) != NULL
                        || strstr(( char * )buf, "Changing group on" )
                        || strstr(( char * )buf, "Changing mode on" )) {
                    NSString *_busymsg = [ NSString stringWithUTF8String: ( void * )buf ];
                    dispatch_async( dispatch_get_main_queue(), ^{
                        [ controller setBusyStatusWithMessage: _busymsg ];
                    } );
                    was_changing = 1;
                    if ( strstr(( char * )buf, "Couldn't " ) != NULL ) {
                        NSString *_sesserr = [ NSString stringWithUTF8String: ( void * )buf ];
                        dispatch_async( dispatch_get_main_queue(), ^{
                            [ controller sessionError: _sesserr ];
                        } );
                    }
                } else if ( [ self unknownHostKeyPromptInBuffer: buf ] ) {
                    NSMutableDictionary    *hostInfo = nil;

                    hostInfo = [ NSMutableDictionary dictionaryWithObjectsAndKeys:
                                [ NSString stringWithUTF8String: buf ], @"msg",
                                [ self retrieveUnknownHostKeyFromStream: mf ], @"key", nil ];

                    NSDictionary *_hostInfo = hostInfo;
                    dispatch_async( dispatch_get_main_queue(), ^{
                        [ controller getContinueQueryForUnknownHost: _hostInfo ];
                    } );
                } else if ( strstr(( char * )buf, "Removing " ) != NULL ) {
                    NSString *_busymsg = [ NSString stringWithUTF8String: ( char * )buf ];
                    dispatch_async( dispatch_get_main_queue(), ^{
                        [ controller setBusyStatusWithMessage: _busymsg ];
                    } );
                }
            }

            /* moved to separate if block: sometimes ls and sftp> occur in same buffer */
            if ( [ self hasDirectoryListingFormInBuffer: buf ] && connected ) {
                NSString *_log = [ NSString stringWithUTF8String: ( char * )buf ];
                dispatch_async( dispatch_get_main_queue(), ^{ [ controller addToLog: _log ]; } );
                was_listing = 1;
                [ self collectListingFromMaster: master fileStream: mf forController: controller ];
                memset( buf, '\0', strlen(( char * )buf ));
                id _items = [ self remoteObjectList ];
                dispatch_async( dispatch_get_main_queue(), ^{
                    [ controller loadRemoteBrowserWithItems: _items ];
                } );
                remoteDirBuf = @"";
            }

            if ( strstr(( char * )buf, "Remote working" ) != NULL ) {
                char		*p, *q, *tmp;

                tmp = strdup(( char * )buf );

                if (( q = strrchr( tmp, '\r' )) != NULL ) *q = '\0';

                p = strchr( tmp, '/' );

                NSString *_pwd = [ NSString stringWithBytesOfUnknownEncoding: p
                                                length: ( unsigned int )strlen( p ) ];
                dispatch_async( dispatch_get_main_queue(), ^{
                    [ controller setRemotePathPopUp: _pwd ];
                } );
                free( tmp );
            }

            if ( threestrikes >= 3 ) {
                dispatch_async( dispatch_get_main_queue(), ^{ [ controller cancelConnection: nil ]; } );
            }

            if ( buf[ 0 ] != '\0' && !suppress_auth_log ) {
                NSString *_log = [ NSString stringWithUTF8String: ( void * )buf ];
                dispatch_async( dispatch_get_main_queue(), ^{ [ controller addToLog: _log ]; } );
                memset( buf, '\0', strlen(( char * )buf ));
            } else if ( suppress_auth_log ) {
                memset( buf, '\0', strlen(( char * )buf ));
            }
        }

        [ p release ];
        p = nil;
        if ( cancelflag ) break;
    }

    sftppid = wait( &status );

    free( execargs );
    [ self setCurrentTransferName: nil ];
    [ remoteDirBuf release ];
    connected = 0;
    fclose( mf );   /* also closes the master fd */

    {
        NSString *_log = [ NSString stringWithUTF8String: ( void * )buf ];
        NSString *_logpid = [ NSString stringWithFormat: @"\nsftp task with pid %d ended.\n", sftppid ];
        dispatch_async( dispatch_get_main_queue(), ^{
            [ controller cleanUp ];
            [ controller addToLog: _log ];
            [ controller addToLog: _logpid ];
        } );
    }
    sftppid = 0;

    if ( WIFEXITED( status )) {
        dispatch_async( dispatch_get_main_queue(), ^{ [ controller addToLog: @"Normal exit\n" ]; } );
    } else if ( WIFSIGNALED( status )) {
        NSString *_siglog = [ NSString stringWithFormat: @"signal = %d\n", status ];
        dispatch_async( dispatch_get_main_queue(), ^{
            [ controller addToLog: @"WIFSIGNALED: " ];
            [ controller addToLog: _siglog ];
        } );
    } else if ( WIFSTOPPED( status )) {
        dispatch_async( dispatch_get_main_queue(), ^{ [ controller addToLog: @"WIFSTOPPED\n" ]; } );
    }
}

- ( void )collectListingFromMaster: ( int )master fileStream: ( FILE * )stream
            forController: ( SFTPController * )controller
{
    char                buf[ MAXPATHLEN * 2 ] = { 0 };
    char                tmp1[ MAXPATHLEN * 2 ], tmp2[ MAXPATHLEN * 2 ];
    size_t              len;
    int                 incomplete_line = 0;

    SFTPListingParserReset();
    fd_set              readmask;
    NSMutableDictionary *object = nil;
    NSMutableArray      *items = nil;
    
    /* make sure we're not buffering */
    setvbuf( stream, NULL, _IONBF, 0 );
    
    for ( ;; ) {
        FD_ZERO( &readmask );
        FD_SET( master, &readmask );
        if ( select( master + 1, &readmask, NULL, NULL, NULL ) < 0 ) {
            NSLog( @"select() returned a value less than zero" );
            return;
        }
        
        if ( FD_ISSET( master, &readmask )) {
            if ( fgets(( char * )buf, ( MAXPATHLEN * 2 ), stream ) == NULL ) {
                return;
            }

            if ( [ self bufferContainsError: buf ] ) {
                NSString *_err = [ NSString stringWithUTF8String: buf ];
                dispatch_async( dispatch_get_main_queue(), ^{ [ controller sessionError: _err ]; } );
                continue;
            }
#ifdef SSH_COM_SUPPORT
            if ( strstr( buf, "<Press any key" ) != NULL ) {
                /* SSH.com's sftp makes you hit a key to get to the prompt. Whee. */
                fdwrite( master, " " );
                continue;
            }
#endif /* SSH_COM_SUPPORT */
            
            /*
             * This is kind of nasty. We don't always get a full line
             * from the server in the 'ls' output, so we have to check
             * if that's the case, flag it, and append the rest of the 
             * text after the next read from the server. Yar!
             */
            len = strlen( buf );
            /* XXX should be modified to handle arbitrary chunks of line */
            if ( strncmp( "sftp>", buf, strlen( "sftp>" )) != 0 &&
                    buf[ len - 1 ] != '\n' ) {
                if ( strlen( buf ) >= sizeof( tmp1 )) {
                    NSLog( @"%s: too long", buf );
                    continue;
                }
                strcpy( tmp1, buf );
                incomplete_line = 1;
                continue;
            }
            if ( incomplete_line ) {
                /* we know this is safe because they're the same buf size */
                strcpy( tmp2, buf );
                memset( buf, '\0', sizeof( buf ));
                
                if ( snprintf( buf, sizeof( buf ), "%s%s", tmp1, tmp2 ) >= sizeof( buf )) {
                    NSLog( @"%s%s: too long", tmp1, tmp2 );
                    continue;
                }
                incomplete_line = 0;
            }
            
            if (( object = [ self remoteObjectFromSFTPLine: buf ] ) != nil ) {
                if ( items == nil ) {
                    items = [[[ NSMutableArray alloc ] init ] autorelease ];
                }
                [ items addObject: object ];
            }
            
            {
                NSString *_log = [ NSString stringWithBytesOfUnknownEncoding: buf
                                                    length: ( unsigned int )strlen( buf ) ];
                dispatch_async( dispatch_get_main_queue(), ^{ [ controller addToLog: _log ]; } );
            }
            if ( strstr( buf, "sftp>" ) != NULL ) {
                memset( buf, '\0', strlen( buf ));
                [ self setRemoteObjectList: items ];
                dispatch_async( dispatch_get_main_queue(), ^{ [ controller finishedCommand ]; } );
                return;
            }
        
            memset( buf, '\0', strlen(( char * )buf ));
        }
    }   
}

@end
