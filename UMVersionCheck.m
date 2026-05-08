/*
 * Copyright (c) 2003 Regents of The University of Michigan.
 * All Rights Reserved.  See COPYRIGHT.
 */

#import "UMVersionCheck.h"

#include <CoreFoundation/CoreFoundation.h>

@implementation UMVersionCheck

/* needs to be multithreaded */
- ( NSDictionary * )retrieveVersionDictionary
{
    NSURL               *versionPlistURL = [ NSURL URLWithString: VERSION_URL ];
    NSDictionary        *versionPlist = nil;
    CFErrorRef          plistErr = NULL;

    NSError *fetchError = nil;
    NSData *httpData = [ NSData dataWithContentsOfURL: versionPlistURL
                                             options: NSDataReadingUncached
                                               error: &fetchError ];
    if ( httpData == nil ) {
        NSLog( @"Failed to retrieve data from URL: %@", fetchError );
        return( nil );
    }

    versionPlist = ( id )CFPropertyListCreateWithData( kCFAllocatorDefault,
                            ( CFDataRef )httpData,
                            kCFPropertyListImmutable, NULL, &plistErr );
    if ( versionPlist == nil ) {
        NSLog( @"Failed to convert data to property list: %@", plistErr );
        if ( plistErr ) CFRelease( plistErr );
        return( nil );
    }

    [ versionPlist autorelease ];
    return( versionPlist );
}

- ( void )checkForUpdates
{
    NSDictionary        *versionDictionary = nil;
    NSDictionary	*infoPlist = nil;
    double              current_version = 0;

    if (( versionDictionary = [ self retrieveVersionDictionary ] ) == nil ) {
        NSAlert *alert = [[ NSAlert alloc ] init ];
        [ alert setAlertStyle: NSAlertStyleWarning ];
        [ alert setMessageText: NSLocalizedString( @"An error occurred checking for updates.",
                                                   @"An error occurred checking for updates." )];
        [ alert setInformativeText: NSLocalizedString(
                    @"Please check to make sure that you are connected "
                    @"to the internet. If you are connected, and the "
                    @"problem persists, please contact the authors of Fugu.",
                    @"Please check to make sure that you are connected "
                    @"to the internet. If you are connected, and the "
                    @"problem persists, please contact the authors of Fugu." )];
        [ alert addButtonWithTitle: NSLocalizedString( @"OK", @"OK" )];
        [ alert runModal ];
        [ alert release ];
        return;
    }

    if (( infoPlist = [[ NSBundle mainBundle ] infoDictionary ] ) == nil ) {
        NSAlert *alert = [[ NSAlert alloc ] init ];
        [ alert setAlertStyle: NSAlertStyleCritical ];
        [ alert setMessageText: @"Failed to locate Info.plist" ];
        [ alert addButtonWithTitle: NSLocalizedString( @"OK", @"OK" )];
        [ alert runModal ];
        [ alert release ];
        return;
    }
    current_version = [[ infoPlist objectForKey: @"UMVersionNumber" ] doubleValue ];

    if ( [[ versionDictionary objectForKey: @"UMApplicationVersion" ] doubleValue ]
                <= current_version ) {
        NSAlert *alert = [[ NSAlert alloc ] init ];
        [ alert setAlertStyle: NSAlertStyleInformational ];
        [ alert setMessageText: [ NSString stringWithFormat:
                    NSLocalizedString( @"You have the current version of %@.",
                                       @"You have the current version of %@." ),
                    [ versionDictionary objectForKey: @"UMApplicationName" ]]];
        [ alert addButtonWithTitle: NSLocalizedString( @"OK", @"OK" )];
        [ alert runModal ];
        [ alert release ];
        return;
    }

    NSAlert *alert = [[ NSAlert alloc ] init ];
    [ alert setAlertStyle: NSAlertStyleInformational ];
    [ alert setMessageText: [ NSString stringWithFormat:
                NSLocalizedString( @"A new version of %@ is now available.",
                                   @"A new version of %@ is now available." ),
                [ versionDictionary objectForKey: @"UMApplicationName" ]]];
    [ alert setInformativeText: [ NSString stringWithFormat:
                NSLocalizedString( @"The latest version of %@ is %@. Click \"More Info\" "
                    @"to open a web page about the new release. Click "
                    @"\"Download\" to download the new version immediately.",
                    @"The latest version of %@ is %@. Click \"More Info\" "
                    @"to open a web page about the new release. Click "
                    @"\"Download\" to download the new version immediately." ),
                [ versionDictionary objectForKey: @"UMApplicationName" ],
                [ versionDictionary objectForKey: @"UMApplicationDisplayVersion" ]]];
    [ alert addButtonWithTitle: NSLocalizedString( @"More Info...", @"More Info..." )];
    [ alert addButtonWithTitle: NSLocalizedString( @"Download", @"Download" )];
    [ alert addButtonWithTitle: NSLocalizedString( @"Later", @"Later" )];
    NSModalResponse rc = [ alert runModal ];
    [ alert release ];

    switch ( rc ) {
    case NSAlertFirstButtonReturn:
        [[ NSWorkspace sharedWorkspace ] openURL:
                [ NSURL URLWithString:
                [ versionDictionary objectForKey:
                    @"UMApplicationInformationURL" ]]];
        break;
    case NSAlertSecondButtonReturn:
        [[ NSWorkspace sharedWorkspace ] openURL:
                [ NSURL URLWithString:
                [ versionDictionary objectForKey:
                    @"UMApplicationDirectDownloadURL" ]]];
        break;
    default:
        break;
    }
}

@end
