/*
 * Copyright (c) 2003 Regents of The University of Michigan.
 * All Rights Reserved.  See COPYRIGHT.
 */

#import <AppKit/AppKit.h>

@interface NSAttributedString ( Ellipsis )

/*
 * Returns a copy of the receiver truncated with a trailing ellipsis
 * character if the rendered string exceeds the given pixel width,
 * or the receiver itself if it already fits.
 */
- ( NSAttributedString * )ellipsisAbbreviatedStringForWidth: ( double )width;

@end
