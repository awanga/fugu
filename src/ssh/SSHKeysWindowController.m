/*
 * Copyright (c) 2003 Regents of The University of Michigan.
 * All Rights Reserved.  See COPYRIGHT.
 */

#import "SSHKeysWindowController.h"
#import "SSHKeyAgent.h"

static SSHKeysWindowController *_sharedController = nil;

@implementation SSHKeysWindowController

+ ( SSHKeysWindowController * )sharedController
{
    if ( _sharedController == nil ) {
        _sharedController = [[ self alloc ] init ];
    }
    return( _sharedController );
}

- ( id )init
{
    NSWindow	*window = [ self buildWindow ];

    if ( ! ( self = [ super initWithWindow: window ] )) {
        return( nil );
    }

    _identities = [[ NSMutableArray alloc ] init ];
    _queue = dispatch_queue_create( "com.umich.fugu.ssh-keys", DISPATCH_QUEUE_SERIAL );

    return( self );
}

- ( void )dealloc
{
    [ _identities release ];
    [ super dealloc ];
}

- ( NSWindow * )buildWindow
{
    NSRect	frame = NSMakeRect( 0, 0, 560, 380 );
    NSWindow	*window = [[ NSWindow alloc ]
                initWithContentRect: frame
                styleMask: ( NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                                | NSWindowStyleMaskResizable )
                backing: NSBackingStoreBuffered defer: NO ];
    NSView	*content = [ window contentView ];
    NSScrollView	*scroll;
    NSTableColumn	*col;
    NSButton	*generateButton;

    [ window setTitle: NSLocalizedString( @"SSH Keys", @"SSH Keys" ) ];
    [ window setReleasedWhenClosed: NO ];
    [ window center ];

    scroll = [[[ NSScrollView alloc ]
                initWithFrame: NSMakeRect( 20, 90, 520, 270 )] autorelease ];
    [ scroll setHasVerticalScroller: YES ];
    [ scroll setAutoresizingMask: ( NSViewWidthSizable | NSViewHeightSizable )];

    _tableView = [[ NSTableView alloc ] initWithFrame: [[ scroll contentView ] bounds ]];
    [ _tableView setDataSource: self ];
    [ _tableView setDelegate: self ];
    [ _tableView setAllowsMultipleSelection: NO ];
    [ _tableView setUsesAlternatingRowBackgroundColors: YES ];

    col = [[[ NSTableColumn alloc ] initWithIdentifier: @"keyType" ] autorelease ];
    [[ col headerCell ] setStringValue: NSLocalizedString( @"Type", @"Type" ) ];
    [ col setWidth: 80 ];
    [ _tableView addTableColumn: col ];

    col = [[[ NSTableColumn alloc ] initWithIdentifier: @"comment" ] autorelease ];
    [[ col headerCell ] setStringValue: NSLocalizedString( @"Comment", @"Comment" ) ];
    [ col setWidth: 180 ];
    [ _tableView addTableColumn: col ];

    col = [[[ NSTableColumn alloc ] initWithIdentifier: @"fingerprint" ] autorelease ];
    [[ col headerCell ] setStringValue: NSLocalizedString( @"Fingerprint", @"Fingerprint" ) ];
    [ col setWidth: 180 ];
    [ _tableView addTableColumn: col ];

    col = [[[ NSTableColumn alloc ] initWithIdentifier: @"loadedInAgent" ] autorelease ];
    [[ col headerCell ] setStringValue: NSLocalizedString( @"In Agent", @"In Agent" ) ];
    [ col setWidth: 60 ];
    [ _tableView addTableColumn: col ];

    [ scroll setDocumentView: _tableView ];
    [ _tableView release ];
    [ content addSubview: scroll ];

    generateButton = [[[ NSButton alloc ] initWithFrame: NSMakeRect( 20, 20, 170, 32 )] autorelease ];
    [ generateButton setTitle: NSLocalizedString( @"Generate New Key...", @"Generate New Key..." ) ];
    [ generateButton setBezelStyle: NSBezelStyleRounded ];
    [ generateButton setTarget: self ];
    [ generateButton setAction: @selector( generateNewKey: ) ];
    [ generateButton setAutoresizingMask: NSViewMaxXMargin | NSViewMaxYMargin ];
    [ content addSubview: generateButton ];

    _addToAgentButton = [[ NSButton alloc ] initWithFrame: NSMakeRect( 320, 20, 130, 32 )];
    [ _addToAgentButton setTitle: NSLocalizedString( @"Add to Agent", @"Add to Agent" ) ];
    [ _addToAgentButton setBezelStyle: NSBezelStyleRounded ];
    [ _addToAgentButton setTarget: self ];
    [ _addToAgentButton setAction: @selector( addSelectedToAgent: ) ];
    [ _addToAgentButton setAutoresizingMask: NSViewMinXMargin | NSViewMaxYMargin ];
    [ _addToAgentButton setEnabled: NO ];
    [ content addSubview: _addToAgentButton ];
    [ _addToAgentButton release ];

    _removeFromAgentButton = [[ NSButton alloc ] initWithFrame: NSMakeRect( 320, 20, 130, 32 )];
    [ _removeFromAgentButton setTitle: NSLocalizedString( @"Remove from Agent", @"Remove from Agent" ) ];
    [ _removeFromAgentButton setBezelStyle: NSBezelStyleRounded ];
    [ _removeFromAgentButton setTarget: self ];
    [ _removeFromAgentButton setAction: @selector( removeSelectedFromAgent: ) ];
    [ _removeFromAgentButton setAutoresizingMask: NSViewMinXMargin | NSViewMaxYMargin ];
    [ _removeFromAgentButton setHidden: YES ];
    [ content addSubview: _removeFromAgentButton ];
    [ _removeFromAgentButton release ];

    _busyIndicator = [[ NSProgressIndicator alloc ] initWithFrame: NSMakeRect( 460, 28, 16, 16 )];
    [ _busyIndicator setStyle: NSProgressIndicatorStyleSpinning ];
    [ _busyIndicator setDisplayedWhenStopped: NO ];
    [ _busyIndicator setAutoresizingMask: NSViewMinXMargin | NSViewMaxYMargin ];
    [ content addSubview: _busyIndicator ];
    [ _busyIndicator release ];

    return( [ window autorelease ] );
}

- ( void )showWindow: ( id )sender
{
    [ super showWindow: sender ];
    [ self reloadIdentities ];
}

- ( void )reloadIdentities
{
    [ _busyIndicator startAnimation: nil ];
    dispatch_async( _queue, ^{
        NSArray *found = [ SSHKeyAgent discoverIdentities ];
        dispatch_async( dispatch_get_main_queue(), ^{
            [ _identities setArray: found ];
            [ _tableView reloadData ];
            [ _busyIndicator stopAnimation: nil ];
            [ self updateButtonsForSelection ];
        });
    });
}

/* NSTableViewDataSource */

- ( NSInteger )numberOfRowsInTableView: ( NSTableView * )tableView
{
    return( [ _identities count ] );
}

- ( id )tableView: ( NSTableView * )tableView
        objectValueForTableColumn: ( NSTableColumn * )tableColumn row: ( NSInteger )row
{
    NSDictionary	*identity = [ _identities objectAtIndex: row ];
    NSString		*ident = [ tableColumn identifier ];

    if ( [ ident isEqualToString: @"loadedInAgent" ] ) {
        return( [[ identity objectForKey: @"loadedInAgent" ] boolValue ] ?
                NSLocalizedString( @"Yes", @"Yes" ) : @"" );
    }
    return( [ identity objectForKey: ident ] );
}

/* NSTableViewDelegate */

- ( void )tableViewSelectionDidChange: ( NSNotification * )notification
{
    [ self updateButtonsForSelection ];
}

- ( void )updateButtonsForSelection
{
    NSInteger	row = [ _tableView selectedRow ];
    BOOL	inAgent = NO;

    if ( row < 0 || row >= ( NSInteger )[ _identities count ] ) {
        [ _addToAgentButton setEnabled: NO ];
        [ _addToAgentButton setHidden: NO ];
        [ _removeFromAgentButton setHidden: YES ];
        return;
    }

    inAgent = [[[ _identities objectAtIndex: row ] objectForKey: @"loadedInAgent" ] boolValue ];
    [ _addToAgentButton setEnabled: YES ];
    [ _addToAgentButton setHidden: inAgent ];
    [ _removeFromAgentButton setHidden: ! inAgent ];
}

- ( NSDictionary * )selectedIdentity
{
    NSInteger	row = [ _tableView selectedRow ];

    if ( row < 0 || row >= ( NSInteger )[ _identities count ] ) return( nil );
    return( [ _identities objectAtIndex: row ] );
}

/* actions */

- ( IBAction )removeSelectedFromAgent: ( id )sender
{
    NSDictionary	*identity = [ self selectedIdentity ];
    NSString		*path;

    if ( identity == nil ) return;
    path = [ identity objectForKey: @"privateKeyPath" ];

    [ _busyIndicator startAnimation: nil ];
    dispatch_async( _queue, ^{
        NSError *error = nil;
        BOOL ok = [ SSHKeyAgent removeIdentityAtPath: path error: &error ];
        dispatch_async( dispatch_get_main_queue(), ^{
            [ _busyIndicator stopAnimation: nil ];
            if ( ! ok ) {
                [ self presentOperationError: error ];
            }
            [ self reloadIdentities ];
        });
    });
}

- ( IBAction )addSelectedToAgent: ( id )sender
{
    NSDictionary	*identity = [ self selectedIdentity ];
    NSString		*path;
    NSString		*passphrase;

    if ( identity == nil ) return;
    path = [ identity objectForKey: @"privateKeyPath" ];

    passphrase = [ self promptForPassphraseWithMessage:
            NSLocalizedString( @"Enter the passphrase for this key, or leave it blank if it has none.",
                    @"Enter the passphrase for this key, or leave it blank if it has none." ) ];
    if ( passphrase == nil ) return; /* cancelled */

    [ _busyIndicator startAnimation: nil ];
    dispatch_async( _queue, ^{
        NSError *error = nil;
        BOOL ok = [ SSHKeyAgent addIdentityAtPath: path passphrase: passphrase error: &error ];
        dispatch_async( dispatch_get_main_queue(), ^{
            [ _busyIndicator stopAnimation: nil ];
            if ( ! ok ) {
                [ self presentOperationError: error ];
            }
            [ self reloadIdentities ];
        });
    });
}

- ( NSString * )promptForPassphraseWithMessage: ( NSString * )message
{
    NSAlert		*alert = [[[ NSAlert alloc ] init ] autorelease ];
    NSSecureTextField	*input = [[[ NSSecureTextField alloc ]
                        initWithFrame: NSMakeRect( 0, 0, 240, 24 )] autorelease ];

    [ alert setMessageText: NSLocalizedString( @"Passphrase", @"Passphrase" ) ];
    [ alert setInformativeText: message ];
    [ alert setAccessoryView: input ];
    [ alert addButtonWithTitle: NSLocalizedString( @"OK", @"OK" ) ];
    [ alert addButtonWithTitle: NSLocalizedString( @"Cancel", @"Cancel" ) ];
    [ alert.window setInitialFirstResponder: input ];

    if ( [ alert runModal ] != NSAlertFirstButtonReturn ) return( nil );

    return( [ input stringValue ] );
}

- ( void )presentOperationError: ( NSError * )error
{
    NSAlert	*alert = [[[ NSAlert alloc ] init ] autorelease ];

    [ alert setAlertStyle: NSAlertStyleWarning ];
    [ alert setMessageText: NSLocalizedString( @"Error", @"Error" ) ];
    [ alert setInformativeText: [ error localizedDescription ] ?:
            NSLocalizedString( @"The operation did not complete successfully.",
                    @"The operation did not complete successfully." ) ];
    [ alert addButtonWithTitle: NSLocalizedString( @"OK", @"OK" ) ];
    [ alert runModal ];
}

- ( IBAction )generateNewKey: ( id )sender
{
    [ self beginGenerateSheet ];
}

- ( void )beginGenerateSheet
{
    NSPanel		*sheet = [[ NSPanel alloc ]
                initWithContentRect: NSMakeRect( 0, 0, 360, 210 )
                styleMask: NSWindowStyleMaskTitled backing: NSBackingStoreBuffered defer: NO ];
    NSView		*content = [ sheet contentView ];
    NSTextField		*label;
    NSButton		*cancelButton, *generateButton;

    label = [ self sheetLabelWithFrame: NSMakeRect( 20, 172, 100, 17 )
                title: NSLocalizedString( @"Key Type:", @"Key Type:" ) ];
    [ content addSubview: label ];

    _typePopup = [[ NSPopUpButton alloc ] initWithFrame: NSMakeRect( 130, 168, 200, 26 )];
    [ _typePopup addItemWithTitle: @"ed25519" ];
    [ _typePopup addItemWithTitle: @"rsa" ];
    [ content addSubview: _typePopup ];

    label = [ self sheetLabelWithFrame: NSMakeRect( 20, 138, 100, 17 )
                title: NSLocalizedString( @"File Name:", @"File Name:" ) ];
    [ content addSubview: label ];

    _nameField = [[ NSTextField alloc ] initWithFrame: NSMakeRect( 130, 134, 200, 22 )];
    [ _nameField setStringValue: @"id_ed25519" ];
    [ content addSubview: _nameField ];

    label = [ self sheetLabelWithFrame: NSMakeRect( 20, 104, 100, 17 )
                title: NSLocalizedString( @"Passphrase:", @"Passphrase:" ) ];
    [ content addSubview: label ];

    _passField = [[ NSSecureTextField alloc ] initWithFrame: NSMakeRect( 130, 100, 200, 22 )];
    [ content addSubview: _passField ];

    label = [ self sheetLabelWithFrame: NSMakeRect( 20, 70, 100, 17 )
                title: NSLocalizedString( @"Confirm:", @"Confirm:" ) ];
    [ content addSubview: label ];

    _confirmField = [[ NSSecureTextField alloc ] initWithFrame: NSMakeRect( 130, 66, 200, 22 )];
    [ content addSubview: _confirmField ];

    cancelButton = [[[ NSButton alloc ] initWithFrame: NSMakeRect( 130, 20, 90, 32 )] autorelease ];
    [ cancelButton setTitle: NSLocalizedString( @"Cancel", @"Cancel" ) ];
    [ cancelButton setBezelStyle: NSBezelStyleRounded ];
    [ cancelButton setTarget: self ];
    [ cancelButton setAction: @selector( cancelGenerateSheet: ) ];
    [ content addSubview: cancelButton ];

    generateButton = [[[ NSButton alloc ] initWithFrame: NSMakeRect( 230, 20, 100, 32 )] autorelease ];
    [ generateButton setTitle: NSLocalizedString( @"Generate", @"Generate" ) ];
    [ generateButton setBezelStyle: NSBezelStyleRounded ];
    [ generateButton setKeyEquivalent: @"\r" ];
    [ generateButton setTarget: self ];
    [ generateButton setAction: @selector( commitGenerateSheet: ) ];
    [ content addSubview: generateButton ];

    [ _typePopup setTarget: self ];
    [ _typePopup setAction: @selector( generateSheetTypeChanged: ) ];

    _generateSheet = sheet;
    [[ self window ] beginSheet: sheet completionHandler: ^( NSModalResponse returnCode ) {}];
}

- ( NSTextField * )sheetLabelWithFrame: ( NSRect )frame title: ( NSString * )title
{
    NSTextField	*label = [[[ NSTextField alloc ] initWithFrame: frame ] autorelease ];

    [ label setEditable: NO ];
    [ label setBordered: NO ];
    [ label setDrawsBackground: NO ];
    [ label setSelectable: NO ];
    [ label setStringValue: title ];
    return( label );
}

- ( void )generateSheetTypeChanged: ( id )sender
{
    [ _nameField setStringValue: [ NSString stringWithFormat: @"id_%@",
                [ _typePopup titleOfSelectedItem ]]];
}

- ( void )endGenerateSheet
{
    [[ self window ] endSheet: _generateSheet ];
    [ _generateSheet release ];
    _generateSheet = nil;
    [ _typePopup release ]; _typePopup = nil;
    [ _nameField release ]; _nameField = nil;
    [ _passField release ]; _passField = nil;
    [ _confirmField release ]; _confirmField = nil;
}

- ( void )cancelGenerateSheet: ( id )sender
{
    [ self endGenerateSheet ];
}

- ( void )commitGenerateSheet: ( id )sender
{
    NSString		*type = [ _typePopup titleOfSelectedItem ];
    NSString		*name = [ _nameField stringValue ];
    NSString		*passphrase = [ _passField stringValue ];
    NSString		*path;
    NSFileManager	*fm = [ NSFileManager defaultManager ];

    if ( ! [ passphrase isEqualToString: [ _confirmField stringValue ]] ) {
        NSAlert *alert = [[[ NSAlert alloc ] init ] autorelease ];
        [ alert setAlertStyle: NSAlertStyleWarning ];
        [ alert setMessageText: NSLocalizedString( @"Passphrases don't match.",
                    @"Passphrases don't match." ) ];
        [ alert runModal ];
        return;
    }

    if ( ! [ name length ] ) return;

    path = [[ NSHomeDirectory() stringByAppendingPathComponent: @".ssh" ]
                stringByAppendingPathComponent: name ];

    [ self endGenerateSheet ];

    if ( [ fm fileExistsAtPath: path ] ) {
        NSAlert *overwrite = [[[ NSAlert alloc ] init ] autorelease ];
        [ overwrite setAlertStyle: NSAlertStyleWarning ];
        [ overwrite setMessageText: [ NSString stringWithFormat:
                    NSLocalizedString( @"\"%@\" already exists. Overwrite it?",
                        @"\"%@\" already exists. Overwrite it?" ), name ]];
        [ overwrite addButtonWithTitle: NSLocalizedString( @"Cancel", @"Cancel" ) ];
        [ overwrite addButtonWithTitle: NSLocalizedString( @"Overwrite", @"Overwrite" ) ];
        if ( [ overwrite runModal ] != NSAlertSecondButtonReturn ) return;
    }

    [ _busyIndicator startAnimation: nil ];
    dispatch_async( _queue, ^{
        NSError *error = nil;
        BOOL ok = [ SSHKeyAgent generateKeyAtPath: path type: type
                    passphrase: passphrase error: &error ];
        dispatch_async( dispatch_get_main_queue(), ^{
            [ _busyIndicator stopAnimation: nil ];
            if ( ! ok ) {
                [ self presentOperationError: error ];
            }
            [ self reloadIdentities ];
        });
    });
}

@end
