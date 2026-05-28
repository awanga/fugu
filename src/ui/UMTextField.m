/*
 * Copyright (c) 2005 Regents of The University of Michigan.
 * All Rights Reserved.  See COPYRIGHT.
 */

#import "UMTextField.h"

@implementation UMTextField

- ( void )setDelegate: ( id )delegate
{
    _umTextFieldDelegate = delegate;
}

- ( id )delegate
{
    return( _umTextFieldDelegate );
}

- ( id )initWithFrame: ( NSRect )frame {
    self = [ super initWithFrame: frame ];
    _umTextFieldDelegate = nil;
    return( self );
}

- ( void )drawRect: ( NSRect )rect {
    [ super drawRect: rect ];
}

- ( void )awakeFromNib
{
    [ self registerForDraggedTypes: [ NSArray arrayWithObjects:
	    NSPasteboardTypeFileURL, NSPasteboardTypeURL, nil ]];
}

- ( NSDragOperation )draggingEntered: ( id <NSDraggingInfo> )sender
{
    NSPasteboard	*pb = [ sender draggingPasteboard ];

    if ( [ pb availableTypeFromArray: [ NSArray arrayWithObjects:
	    NSPasteboardTypeFileURL, NSPasteboardTypeURL, nil ]] == nil ) {
	return( NSDragOperationNone );
    }

    [ self setBackgroundColor: [ NSColor lightGrayColor ]];
    [ self setEditable: NO ];
    [ self setNeedsDisplay: YES ];

    return( NSDragOperationCopy );
}

- ( void )draggingExited: ( id <NSDraggingInfo> )sender
{
    [ self setBackgroundColor: [ NSColor controlBackgroundColor ]];
    [ self setEditable: YES ];
    [ self setNeedsDisplay: YES ];
}

- ( BOOL )performDragOperation: ( id <NSDraggingInfo> )sender
{
    NSPasteboard	*pb = [ sender draggingPasteboard ];
    NSString		*path = nil;

    NSArray *urls = [ pb readObjectsForClasses: [ NSArray arrayWithObject: [ NSURL class ]]
                                       options: nil ];
    if ( urls && [ urls count ] > 0 ) {
	NSURL *url = [ urls objectAtIndex: 0 ];
	path = [ url isFileURL ] ? [ url path ] : [ url absoluteString ];
    }

    if ( path == nil ) {
	return( NO );
    }

    [ self setStringValue: path ];
    [ self setEditable: YES ];
    [ self setBackgroundColor: [ NSColor controlBackgroundColor ]];
    [ self setNeedsDisplay: YES ];

    if ( [[ self delegate ] respondsToSelector:
	    @selector( umTextFieldContentsChanged: ) ] ) {
	[[ self delegate ] umTextFieldContentsChanged:
		[ NSDictionary dictionaryWithObjectsAndKeys:
		self, @"UMTextField",
		path, @"UMTextFieldString", nil ]];
    }

    return( YES );
}

@end
