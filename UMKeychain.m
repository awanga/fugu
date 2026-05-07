/*
 * Copyright (c) 2008 Regents of The University of Michigan.
 * All Rights Reserved.  See COPYRIGHT.
 */

#import "UMKeychain.h"

#include <errno.h>
#include <stdlib.h>
#include <string.h>

@implementation UMKeychain

static UMKeychain	*defaultKeychain = nil;

- ( id )init
{
    self = [ super init ];
    _umKeychainRef = nil;
    return( self );
}

+ ( UMKeychain * )defaultKeychain
{
    if ( defaultKeychain == nil ) {
        defaultKeychain = [[ UMKeychain alloc ] init ];
    }
    return( defaultKeychain );
}

- ( void )setKeychainRef: ( SecKeychainRef )keychainRef
{
    if ( _umKeychainRef != NULL ) {
        CFRelease( _umKeychainRef );
    }
    _umKeychainRef = keychainRef;
}

- ( SecKeychainRef )keychainRef
{
    return( _umKeychainRef );
}

- ( NSString * )passwordForService: ( NSString * )service
        account: ( NSString * )account
        keychainItem: ( SecKeychainItemRef * )item
        error: ( OSStatus * )error
{
    NSMutableDictionary	*query = [ NSMutableDictionary dictionary ];

    [ query setObject: ( id )kSecClassGenericPassword forKey: ( id )kSecClass ];
    [ query setObject: service forKey: ( id )kSecAttrService ];
    [ query setObject: account forKey: ( id )kSecAttrAccount ];
    [ query setObject: ( id )kCFBooleanTrue forKey: ( id )kSecReturnData ];
    [ query setObject: ( id )kSecMatchLimitOne forKey: ( id )kSecMatchLimit ];
    if ( item != NULL ) {
        [ query setObject: ( id )kCFBooleanTrue forKey: ( id )kSecReturnRef ];
    }

    CFTypeRef   result = NULL;
    OSStatus    err = SecItemCopyMatching( ( CFDictionaryRef )query, &result );
    if ( error ) {
        *error = err;
    }
    if ( err != noErr || result == NULL ) {
        return( nil );
    }

    NSString    *password = nil;

    if ( item != NULL ) {
        /* Both kSecReturnData and kSecReturnRef requested: result is CFDictionary */
        CFDataRef pwData = CFDictionaryGetValue( ( CFDictionaryRef )result, kSecValueData );
        if ( pwData ) {
            password = [[[ NSString alloc ]
                        initWithBytes: CFDataGetBytePtr( pwData )
                               length: CFDataGetLength( pwData )
                             encoding: NSUTF8StringEncoding ] autorelease ];
        }
        CFTypeRef ref = CFDictionaryGetValue( ( CFDictionaryRef )result, kSecValueRef );
        *item = ( SecKeychainItemRef )( ref ? CFRetain( ref ) : NULL );
    } else {
        /* Only kSecReturnData requested: result is CFData */
        password = [[[ NSString alloc ]
                    initWithBytes: CFDataGetBytePtr( ( CFDataRef )result )
                           length: CFDataGetLength( ( CFDataRef )result )
                         encoding: NSUTF8StringEncoding ] autorelease ];
    }
    CFRelease( result );
    return( password );
}

- ( OSStatus )storePassword: ( NSString * )password
        forService: ( NSString * )service
        account: ( NSString * )account
        keychainItem: ( SecKeychainItemRef * )item
{
    NSData  *pwData = [ password dataUsingEncoding: NSUTF8StringEncoding ];
    NSMutableDictionary *attrs = [ NSMutableDictionary dictionary ];

    [ attrs setObject: ( id )kSecClassGenericPassword forKey: ( id )kSecClass ];
    [ attrs setObject: service forKey: ( id )kSecAttrService ];
    [ attrs setObject: account forKey: ( id )kSecAttrAccount ];
    [ attrs setObject: pwData forKey: ( id )kSecValueData ];
    if ( item != NULL ) {
        [ attrs setObject: ( id )kCFBooleanTrue forKey: ( id )kSecReturnRef ];
    }

    CFTypeRef   result = NULL;
    OSStatus    err = SecItemAdd( ( CFDictionaryRef )attrs, item ? &result : NULL );
    if ( err == noErr && item != NULL ) {
        *item = ( SecKeychainItemRef )result;
    }
    return( err );
}

- ( OSStatus )changePassword: ( NSString * )newPassword
        forKeychainItem: ( SecKeychainItemRef )item
{
    NSDictionary    *query = [ NSDictionary dictionaryWithObject: ( id )item
                                                         forKey: ( id )kSecValueRef ];
    NSDictionary    *attrs = [ NSDictionary dictionaryWithObject:
                                    [ newPassword dataUsingEncoding: NSUTF8StringEncoding ]
                                                          forKey: ( id )kSecValueData ];
    return( SecItemUpdate( ( CFDictionaryRef )query, ( CFDictionaryRef )attrs ));
}

@end
