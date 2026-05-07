/*
 * Copyright (c) 2003 Regents of The University of Michigan.
 * All Rights Reserved.  See COPYRIGHT.
 */

#import <Foundation/Foundation.h>

/*
 * Call reset() at the start of each directory listing to clear column state.
 * Then call parseLine() for each text line from the sftp ls output.
 * Returns nil for non-file lines (., .., sftp prompt, header lines, etc.).
 * Returned dictionary keys: name, NameAsRawBytes, perm, type, owner, group, size, date.
 */
void SFTPListingParserReset(void);
NSDictionary *SFTPListingParserParseLine(const char *line);
