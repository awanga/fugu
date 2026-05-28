/*
 * Copyright (c) 2003 Regents of The University of Michigan.
 * All Rights Reserved.  See COPYRIGHT.
 *
 * Placeholder implementation. Full rewrite with SecItemCopyMatching /
 * SecItemAdd is tracked in the Phase 7 keychain modernization task.
 */

#include "keychain.h"
#include <stdlib.h>

char *
getpwdfromkeychain( const char *server, const char *account, OSStatus *error )
{
    if ( error ) {
        *error = errSecItemNotFound;
    }
    return( NULL );
}

void
addpwdtokeychain( const char *server, const char *account, const char *password )
{
    /* stub — see Phase 7 */
}
