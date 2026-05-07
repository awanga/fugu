/*
 * Copyright (c) 2003 Regents of The University of Michigan.
 * All Rights Reserved.  See COPYRIGHT.
 */

#import "NSFileManager(mktemp).h"

#include <sys/types.h>
#include <sys/param.h>
#include <errno.h>

@implementation NSFileManager(mktemp)

- ( NSString * )makeTemporaryDirectoryWithMode: ( mode_t )mode
{
    (void)mode;         /* mkdtemp always creates with 0700 */
    NSString    *base = NSTemporaryDirectory();
    char        tmpl[ MAXPATHLEN ];

    if ( snprintf( tmpl, MAXPATHLEN, "%s" FUGU_TMPDIR_PREFIX "XXXXXX",
                   [ base fileSystemRepresentation ] ) >= MAXPATHLEN ) {
        return( nil );
    }
    if ( mkdtemp( tmpl ) == NULL ) {
        return( nil );
    }
    return( [ NSString stringWithUTF8String: tmpl ] );
}

@end
