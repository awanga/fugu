/*
 * Copyright (c) 2003 Regents of The University of Michigan.
 * All Rights Reserved.  See COPYRIGHT.
 */

#import "NSAttributedString-Ellipsis.h"

@implementation NSAttributedString ( Ellipsis )

- ( NSAttributedString * )ellipsisAbbreviatedStringForWidth: ( double )width
{
    NSSize		sz = [ self size ];
    NSMutableAttributedString	*result;
    NSDictionary	*attrs;
    NSString		*ellipsis = @"…";
    NSAttributedString	*ellipsisAttr;
    double		ellipsisWidth;

    if ( sz.width <= width ) {
        return( self );
    }

    attrs = [ self length ] > 0 ? [ self attributesAtIndex: 0 effectiveRange: NULL ] : @{};
    ellipsisAttr = [[ NSAttributedString alloc ] initWithString: ellipsis attributes: attrs ];
    ellipsisWidth = [ ellipsisAttr size ].width;

    result = [[ NSMutableAttributedString alloc ] initWithAttributedString: self ];

    while ( [ result length ] > 0 && [ result size ].width + ellipsisWidth > width ) {
        [ result deleteCharactersInRange: NSMakeRange( [ result length ] - 1, 1 ) ];
    }

    [ result appendAttributedString: ellipsisAttr ];
    [ ellipsisAttr release ];

    return( [ result autorelease ] );
}

@end
