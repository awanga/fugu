/*
 * Copyright (c) 2003 Regents of The University of Michigan.
 * All Rights Reserved.  See COPYRIGHT.
 */

#import <Cocoa/Cocoa.h>

/*
 * Blocking helpers around ssh-keygen / ssh-add. All process launches use
 * forkpty/execve with an explicit argv array; no shell is ever invoked.
 * Callers are responsible for dispatching these off the main queue.
 */
@interface SSHKeyAgent : NSObject

/*
 * Array of NSDictionary, one per public key found under ~/.ssh, each with keys:
 * "publicKeyPath", "privateKeyPath", "comment", "keyType", "fingerprint",
 * and "loadedInAgent" (NSNumber BOOL).
 */
+ ( NSArray * )discoverIdentities;

+ ( BOOL )addIdentityAtPath: ( NSString * )path
                 passphrase: ( NSString * )passphrase
                      error: ( NSError ** )error;

+ ( BOOL )removeIdentityAtPath: ( NSString * )path
                          error: ( NSError ** )error;

+ ( BOOL )generateKeyAtPath: ( NSString * )path
                        type: ( NSString * )type
                  passphrase: ( NSString * )passphrase
                       error: ( NSError ** )error;

@end
