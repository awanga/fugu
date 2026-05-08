/*
 * Copyright (c) 2005 Regents of The University of Michigan.
 * All Rights Reserved.  See COPYRIGHT.
 */

#import "UMDragDropImageView.h"

/*
 * NSImageView subclass capable of accepting drops.
 * The image of the view is set to the icon of the
 * dropped file.
 */

@implementation UMDragDropImageView

- ( void )setDelegate: ( id )delegate
{
    _umDragDropImageViewDelegate = delegate;
}

- ( id )delegate
{
    return( _umDragDropImageViewDelegate );
}

- ( id )initWithFrame: ( NSRect )frame {
    self = [ super initWithFrame: frame ];
    _umDragDropImageViewDelegate = nil;
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

    return( NSDragOperationCopy );
}

- ( void )draggingExited: ( id <NSDraggingInfo> )sender
{
}

- ( BOOL )performDragOperation: ( id <NSDraggingInfo> )sender
{
    NSPasteboard	*pb = [ sender draggingPasteboard ];
    NSImage		*icon = nil;
    NSString		*path = nil;

    NSArray *urls = [ pb readObjectsForClasses: [ NSArray arrayWithObject: [ NSURL class ]]
                                       options: nil ];
    if ( !urls || [ urls count ] == 0 ) {
	return( NO );
    }

    NSURL *url = [ urls objectAtIndex: 0 ];
    path = [ url isFileURL ] ? [ url path ] : [ url absoluteString ];

    if ( [[ self delegate ] respondsToSelector:
	    @selector( dropImageViewChanged: ) ] ) {
	[[ self delegate ] dropImageViewChanged:
		[ NSDictionary dictionaryWithObjectsAndKeys:
		self, @"UMDragDropImageView",
		path, @"UMDragDropPath", nil ]];
    }

    icon = [[ NSWorkspace sharedWorkspace ] iconForFile: path ];

    [ self setImage: icon ];

    return( YES );
}

@end
