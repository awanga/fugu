/*
 * Copyright (c) 2003 Regents of The University of Michigan.
 * All Rights Reserved.  See COPYRIGHT.
 */

#import <Cocoa/Cocoa.h>

/*
 * Self-contained SSH key management window. Built entirely in code rather
 * than loaded from a NIB: the rest of this app's UI lives in legacy
 * compiled NIB bundles with no .xib source to edit, and this window has
 * no existing layout to fit into or collide with.
 */
@interface SSHKeysWindowController : NSWindowController <NSTableViewDataSource, NSTableViewDelegate>
{
@private
    NSTableView		*_tableView;
    NSButton		*_addToAgentButton;
    NSButton		*_removeFromAgentButton;
    NSProgressIndicator	*_busyIndicator;
    NSMutableArray	*_identities;
    dispatch_queue_t	_queue;

    /* generate-key sheet, valid only while the sheet is up */
    NSPanel		*_generateSheet;
    NSPopUpButton	*_typePopup;
    NSTextField		*_nameField;
    NSSecureTextField	*_passField;
    NSSecureTextField	*_confirmField;
}

+ ( SSHKeysWindowController * )sharedController;
- ( void )showWindow: ( id )sender;

@end
