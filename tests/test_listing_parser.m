/*
 * Fixture tests for SFTPListingParserParseLine.
 * Build and run with:  make -C tests
 */

#import <Foundation/Foundation.h>
#import "../SFTPListingParser.h"

static int failures = 0;

#define EXPECT_EQ(label, a, b) do { \
    if (![(a) isEqual:(b)]) { \
        NSLog(@"FAIL [%s]: expected %@ got %@", label, (b), (a)); \
        failures++; \
    } \
} while(0)

#define EXPECT_NIL(label, v) do { \
    if ((v) != nil) { \
        NSLog(@"FAIL [%s]: expected nil, got %@", label, (v)); \
        failures++; \
    } \
} while(0)

#define EXPECT_NOT_NIL(label, v) do { \
    if ((v) == nil) { \
        NSLog(@"FAIL [%s]: expected non-nil result", label); \
        failures++; \
    } \
} while(0)

int main(void) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

    /* A complete OpenSSH-style ls -la listing */
    const char *dot_line   = "drwxr-xr-x    2 user group        4096 Jan  1 00:00 .\n";
    const char *dotdot     = "drwxr-xr-x   10 user group        4096 Jan  1 00:00 ..\n";
    const char *file_line  = "-rw-r--r--    1 user group         123 Jan  1 00:00 normal.txt\n";
    const char *dir_line   = "drwxr-xr-x    2 user group        4096 Jan  1 00:00 subdir\n";
    const char *link_line  = "lrwxrwxrwx    1 user group           7 Jan  1 00:00 mylink -> target\n";
    /* SEC-PARSE-5: regular file whose name contains " -> " — must not be truncated */
    const char *arrow_file = "-rw-r--r--    1 user group         123 Jan  1 00:00 arrow -> notlink.txt\n";
    /* SEC-PARSE-3: filename with embedded spaces (single-space round-trip is correct) */
    const char *spaces     = "-rw-r--r--    1 user group         123 Jan  1 00:00 file with spaces.txt\n";
    /* sftp prompt line */
    const char *prompt     = "sftp> ";

    /* ------ test sequence: must process dot line first to set fncolumn ------ */
    SFTPListingParserReset();

    NSDictionary *r;

    /* dot and dotdot return nil */
    EXPECT_NIL("dot",    SFTPListingParserParseLine(dot_line));
    /* ".." is not filtered by the parser — browser layer handles it */
    r = SFTPListingParserParseLine(dotdot);
    EXPECT_NOT_NIL("dotdot", r);
    EXPECT_EQ("dotdot.name", r[@"name"], @"..");
    EXPECT_NIL("prompt", SFTPListingParserParseLine(prompt));

    /* normal file */
    r = SFTPListingParserParseLine(file_line);
    EXPECT_NOT_NIL("file", r);
    EXPECT_EQ("file.name",  r[@"name"],  @"normal.txt");
    EXPECT_EQ("file.type",  r[@"type"],  @"file");
    EXPECT_EQ("file.perm",  r[@"perm"],  @"-rw-r--r--");
    EXPECT_EQ("file.owner", r[@"owner"], @"user");
    EXPECT_EQ("file.group", r[@"group"], @"group");
    EXPECT_EQ("file.size",  r[@"size"],  @"123");

    /* directory */
    r = SFTPListingParserParseLine(dir_line);
    EXPECT_NOT_NIL("dir", r);
    EXPECT_EQ("dir.name", r[@"name"], @"subdir");
    EXPECT_EQ("dir.type", r[@"type"], @"directory");

    /* symlink: name stops at " -> " */
    r = SFTPListingParserParseLine(link_line);
    EXPECT_NOT_NIL("link", r);
    EXPECT_EQ("link.name", r[@"name"], @"mylink");
    EXPECT_EQ("link.type", r[@"type"], @"symbolic link");

    /* SEC-PARSE-5: regular file with " -> " in name — full name preserved */
    r = SFTPListingParserParseLine(arrow_file);
    EXPECT_NOT_NIL("arrow", r);
    EXPECT_EQ("arrow.name", r[@"name"], @"arrow -> notlink.txt");
    EXPECT_EQ("arrow.type", r[@"type"], @"file");

    /* SEC-PARSE-3: spaces in filename (single-space round-trip) */
    r = SFTPListingParserParseLine(spaces);
    EXPECT_NOT_NIL("spaces", r);
    EXPECT_EQ("spaces.name", r[@"name"], @"file with spaces.txt");

    [pool drain];

    if (failures == 0) {
        NSLog(@"All tests passed.");
        return 0;
    }
    NSLog(@"%d test(s) FAILED.", failures);
    return 1;
}
