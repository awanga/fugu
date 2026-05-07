/*
 * Copyright (c) 2003 Regents of The University of Michigan.
 * All Rights Reserved.  See COPYRIGHT.
 */

#import "SFTPListingParser.h"
#import "NSString-UnknownEncoding.h"
#import "NSString(SSHAdditions).h"

#include <ctype.h>
#include <stdlib.h>
#include <string.h>
#include <sys/param.h>

#include "argcargv.h"
#include "typeforchar.h"

static int fncolumn = -1;

void
SFTPListingParserReset( void )
{
    fncolumn = -1;
}

NSDictionary *
SFTPListingParserParseLine( const char *object )
{
    int                  j, tac, len = 0;
    int                  datecolumn = -1, ownercolumn = 2;
    char                 line[ MAXPATHLEN * 2 ] = { 0 };
    char                 *filename = NULL;
    char                 **targv;
    char                 *p;
    NSMutableDictionary  *infoDictionary = nil;
    NSString             *dateString = nil, *groupName = nil, *name = nil;
    NSData               *nameAsRawBytes = nil;

    if ( strncmp( object, "sftp> ", strlen( "sftp> " )) == 0 ) {
        return( nil );
    }

    if ( strlen( object ) >= sizeof( line )) {
        return( nil );
    }
    strcpy( line, object );

    if (( tac = argcargv( line, &targv )) <= 0 ) {
        return( nil );
    }

    /* Strip SSH.com-style trailing '*' from executable names */
    if ( tac > 0 ) {
        p = targv[ ( tac - 1 ) ];
        len = (int)strlen( p );
        if ( len > 1 && *targv[ 0 ] == '-' && p[ len - 1 ] == '*' ) {
            p[ len - 1 ] = '\0';
        }
    }

    /* SSH.com writes "dir:" before listing */
    if ( tac == 1 && strcmp( targv[ 0 ], ".:" ) == 0 ) {
        fncolumn = 8;
        return( nil );
    } else if ( tac == 1 ) {
        return( nil );
    }

    /* Find the filename column by locating the '.' entry */
    for ( j = 0; j < tac; j++ ) {
        if ( strcmp( targv[ j ], "." ) == 0 || strcmp( targv[ j ], "./" ) == 0 ) {
            fncolumn = j;
            break;
        }
    }

    if ( fncolumn == -1 ) {
        if ( isdigit( *targv[ 0 ] ) && strchr( targv[ 4 ], ':' ) != NULL ) {
            fncolumn = 5;
        } else if ( *targv[ 0 ] == 'd' || *targv[ 0 ] == '-' ) {
            if ( tac >= 9 ) {
                fncolumn = 8;
            }
        }
    }
    if ( fncolumn == -1 || fncolumn >= tac ) {
        return( nil );
    }

    /* Find datecolumn: scan backwards from fncolumn for alphabetic month token */
    for ( j = ( fncolumn - 1 ); j >= 0; j-- ) {
        if ( targv[ j ] != NULL && isalpha( *targv[ j ] )) {
            datecolumn = j;
            break;
        }
    }
    if ( datecolumn < 0 ) {
        if ( *targv[ 0 ] == '0' && strlen( targv[ 0 ] ) > 1
                                && strchr( targv[ 4 ], ':' ) == NULL
                                && fncolumn == 5 ) {
            datecolumn = ( fncolumn - 1 );
            ownercolumn = 1;
        }
    }
    if ( datecolumn >= tac || datecolumn < 0 ) {
        return( nil );
    }

    dateString = [ NSString stringWithUTF8String: targv[ datecolumn ]];
    for ( j = ( datecolumn + 1 ); j < fncolumn; j++ ) {
        dateString = [ NSString stringWithFormat: @"%@ %s", dateString, targv[ j ]];
    }
    infoDictionary = [[ NSMutableDictionary alloc ] init ];
    [ infoDictionary setObject: dateString forKey: @"date" ];

    if ( datecolumn >= 1 ) {
        [ infoDictionary setObject: [ NSString stringWithUTF8String:
                                        targv[ ( datecolumn - 1 ) ]]
                            forKey: @"size" ];
    }

    if ( fncolumn > 0 && tac >= ( fncolumn + 1 )) {
        if ( tac > ( fncolumn + 1 )) {
            if ( strstr( targv[ 0 ], "sftp>" ) != NULL ) {
                goto DOT_OR_DOTDOT;
            }

            for ( j = fncolumn; j < tac; j++ ) {
                len += ( (int)strlen( targv[ j ] ) + 1 );
            }

            if (( filename = ( char * )malloc( (size_t)len )) == NULL ) {
                [ infoDictionary release ];
                return( nil );
            }
            strlcpy( filename, targv[ fncolumn ], (size_t)len );

            {
                int islink = ( *targv[ 0 ] == 'l' );
                for ( j = fncolumn + 1; j < tac; j++ ) {
                    if ( islink && strcmp( targv[ j ], "->" ) == 0 ) {
                        break;
                    }
                    strlcat( filename, " ", (size_t)len );
                    strlcat( filename, targv[ j ], (size_t)len );
                }
            }

            nameAsRawBytes = [ NSData dataWithBytes: filename length: strlen( filename ) ];
            name = [ NSString stringWithBytesOfUnknownEncoding: filename
                                                    length: (unsigned)strlen( filename ) ];
            free( filename );
        } else {
            if ( strcmp( ".", targv[ fncolumn ] ) == 0
                    || strcmp( "./", targv[ fncolumn ] ) == 0 ) {
                goto DOT_OR_DOTDOT;
            }

            nameAsRawBytes = [ NSData dataWithBytes: targv[ fncolumn ]
                                length: strlen( targv[ fncolumn ] ) ];
            name = [ NSString stringWithBytesOfUnknownEncoding: targv[ fncolumn ]
                                            length: (unsigned)strlen( targv[ fncolumn ] ) ];
        }

        if (( datecolumn - 1 ) == 0 ) {
            [ infoDictionary setObject: @"N/A" forKey: @"owner" ];
            [ infoDictionary setObject: @"N/A" forKey: @"group" ];
            if ( [ name characterAtIndex: ( [ name length ] - 1 ) ] == '/' ) {
                [ infoDictionary setObject: @"d---------" forKey: @"perm" ];
                [ infoDictionary setObject: @"directory" forKey: @"type" ];
            } else {
                [ infoDictionary setObject: @"----------" forKey: @"perm" ];
                [ infoDictionary setObject: @"file" forKey: @"type" ];
            }
        } else if (( datecolumn - 1 ) > 1 ) {
            [ infoDictionary setObject: [ NSString stringWithUTF8String: targv[ ownercolumn ]]
                                    forKey: @"owner" ];
            groupName = [ NSString stringWithUTF8String: targv[ ( ownercolumn + 1 ) ]];
            for ( j = ( ownercolumn + 2 ); j < ( datecolumn - 1 ); j++ ) {
                groupName = [ NSString stringWithFormat: @"%@ %s", groupName, targv[ j ]];
            }
            [ infoDictionary setObject: groupName forKey: @"group" ];

            if (( datecolumn + 1 ) == fncolumn && *targv[ 0 ] == '0' ) {
                [ infoDictionary setObject:
                                    [[ NSString stringWithUTF8String: targv[ 0 ]]
                                        stringRepresentationOfOctalMode ]
                                    forKey: @"perm" ];
            } else {
                [ infoDictionary setObject: [ NSString stringWithUTF8String: targv[ 0 ]]
                                    forKey: @"perm" ];
            }
            [ infoDictionary setObject:
                [ NSString stringWithUTF8String:
                typeforchar( [[ infoDictionary objectForKey: @"perm" ] characterAtIndex: 0 ] ) ]
                            forKey: @"type" ];
        }
        [ infoDictionary setObject: name forKey: @"name" ];
        [ infoDictionary setObject: nameAsRawBytes forKey: @"NameAsRawBytes" ];
    }

    return( [ infoDictionary autorelease ] );

DOT_OR_DOTDOT:
    if ( infoDictionary ) {
        [ infoDictionary release ];
    }
    return( nil );
}
