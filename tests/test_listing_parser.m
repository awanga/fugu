/*
 * Fixture tests for SFTPListingParserParseLine.
 * Build and run with:  make -C tests
 */

#import <Foundation/Foundation.h>
#include <string.h>
#include <sys/param.h>
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
    /* SEC-PARSE-3: filenames with embedded whitespace (fixed-column parser) */
    const char *spaces     = "-rw-r--r--    1 user group         123 Jan  1 00:00 file with spaces.txt\n";
    const char *dbl_space  = "-rw-r--r--    1 user group         123 Jan  1 00:00 file  double  space.txt\n";
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

    /* SEC-PARSE-3: single-space filename */
    r = SFTPListingParserParseLine(spaces);
    EXPECT_NOT_NIL("spaces", r);
    EXPECT_EQ("spaces.name", r[@"name"], @"file with spaces.txt");

    /* SEC-PARSE-3: double-space filename (was broken with whitespace tokenizer) */
    r = SFTPListingParserParseLine(dbl_space);
    EXPECT_NOT_NIL("dbl_space", r);
    EXPECT_EQ("dbl_space.name", r[@"name"], @"file  double  space.txt");

    /* ------ additional hostile filename fixtures (same session) ------ */

    /* leading-dash filename */
    r = SFTPListingParserParseLine(
            "-rwxr-xr-x    1 user group          45 Jan  1 00:00 -dangerous.sh\n");
    EXPECT_NOT_NIL("leading_dash", r);
    EXPECT_EQ("leading_dash.name", r[@"name"], @"-dangerous.sh");
    EXPECT_EQ("leading_dash.type", r[@"type"], @"file");

    /* double-quote embedded in filename */
    r = SFTPListingParserParseLine(
            "-rw-r--r--    1 user group         123 Jan  1 00:00 file\"name\".txt\n");
    EXPECT_NOT_NIL("quote_in_name", r);
    EXPECT_EQ("quote_in_name.name", r[@"name"], @"file\"name\".txt");

    /* bracket chars in filename */
    r = SFTPListingParserParseLine(
            "-rw-r--r--    1 user group         123 Jan  1 00:00 file[1].txt\n");
    EXPECT_NOT_NIL("bracket", r);
    EXPECT_EQ("bracket.name", r[@"name"], @"file[1].txt");

    /* zero-byte file */
    r = SFTPListingParserParseLine(
            "-rw-r--r--    1 user group           0 Jan  1 00:00 empty.txt\n");
    EXPECT_NOT_NIL("zero_size", r);
    EXPECT_EQ("zero_size.name", r[@"name"], @"empty.txt");
    EXPECT_EQ("zero_size.size", r[@"size"], @"0");

    /* large file (> 2^32 bytes) */
    r = SFTPListingParserParseLine(
            "-rw-r--r--    1 user group  10737418240 Jan  1 00:00 bigfile.iso\n");
    EXPECT_NOT_NIL("large_size", r);
    EXPECT_EQ("large_size.name", r[@"name"], @"bigfile.iso");
    EXPECT_EQ("large_size.size", r[@"size"], @"10737418240");

    /* year-style date (HH:MM replaced by year for files > 6 months old) */
    r = SFTPListingParserParseLine(
            "-rw-r--r--    1 user group         123 Jan  1  2020 oldfile.txt\n");
    EXPECT_NOT_NIL("year_date", r);
    EXPECT_EQ("year_date.name", r[@"name"], @"oldfile.txt");
    EXPECT_EQ("year_date.size", r[@"size"], @"123");

    /* UTF-8 filename: 日本語.txt (\xe6\x97\xa5\xe6\x9c\xac\xe8\xaa\x9e) */
    r = SFTPListingParserParseLine(
            "-rw-r--r--    1 user group         123 Jan  1 00:00 "
            "\xe6\x97\xa5\xe6\x9c\xac\xe8\xaa\x9e.txt\n");
    EXPECT_NOT_NIL("unicode", r);
    EXPECT_EQ("unicode.name", r[@"name"], @"日本語.txt");

    /* symlink with multi-hop appearance: only first " -> " is stripped */
    r = SFTPListingParserParseLine(
            "lrwxrwxrwx    1 user group           7 Jan  1 00:00 chain -> first -> second\n");
    EXPECT_NOT_NIL("sym_chain", r);
    EXPECT_EQ("sym_chain.name", r[@"name"], @"chain");
    EXPECT_EQ("sym_chain.type", r[@"type"], @"symbolic link");

    /* long filename (250 x chars) */
    {
        char long_name[256];
        memset(long_name, 'x', 250);
        long_name[250] = '\0';
        char long_line[512];
        snprintf(long_line, sizeof(long_line),
                 "-rw-r--r--    1 user group         123 Jan  1 00:00 %s\n", long_name);
        r = SFTPListingParserParseLine(long_line);
        EXPECT_NOT_NIL("long_name", r);
        EXPECT_EQ("long_name.name", r[@"name"], [NSString stringWithUTF8String:long_name]);
    }

    /* ------ error / nil cases (fresh session) ------ */
    SFTPListingParserReset();

    EXPECT_NIL("empty_str",   SFTPListingParserParseLine(""));
    EXPECT_NIL("just_nl",     SFTPListingParserParseLine("\n"));
    EXPECT_NIL("spaces_only", SFTPListingParserParseLine("     \n"));
    EXPECT_NIL("prompt2",     SFTPListingParserParseLine("sftp> "));

    /* line >= MAXPATHLEN*2 bytes (buffer overflow guard) */
    {
        char too_long[MAXPATHLEN * 2 + 8];
        memset(too_long, 'a', sizeof(too_long) - 1);
        too_long[sizeof(too_long) - 1] = '\0';
        EXPECT_NIL("too_long", SFTPListingParserParseLine(too_long));
    }

    [pool drain];

    if (failures == 0) {
        NSLog(@"All tests passed.");
        return 0;
    }
    NSLog(@"%d test(s) FAILED.", failures);
    return 1;
}
