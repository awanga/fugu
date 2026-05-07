/*
 * Copyright (c) 2003 Regents of The University of Michigan.
 * All Rights Reserved.  See COPYRIGHT.
 */

#import <AppKit/AppKit.h>

#define FUGU_TMPDIR_PREFIX  "com.umich.fugu."

@interface NSFileManager(mktemp)

/*
 * Create a per-call temporary directory under NSTemporaryDirectory().
 * Template: NSTemporaryDirectory()/com.umich.fugu.XXXXXX
 * mkdtemp(3) guarantees mode 0700; the mode parameter is ignored and
 * retained only for API compatibility.
 * Returns the created path, or nil on failure.
 */
- ( NSString * )makeTemporaryDirectoryWithMode: ( mode_t )mode;

@end
