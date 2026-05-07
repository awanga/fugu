/*
 * Copyright (c) 2003 Regents of The University of Michigan.
 * All Rights Reserved.  See COPYRIGHT.
 */

#ifndef KEYCHAIN_H
#define KEYCHAIN_H

#include <Security/Security.h>

#define _PASSWORD_LEN	256

/* Returns a malloc'd password string the caller must free(), or NULL on failure. */
char	*getpwdfromkeychain( const char *server, const char *account, OSStatus *error );
void	 addpwdtokeychain( const char *server, const char *account, const char *password );

#endif /* KEYCHAIN_H */
