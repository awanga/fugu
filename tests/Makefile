CC      = clang
CFLAGS  = -std=c99 -Wall -Wextra -Werror -Wno-sign-compare -fno-objc-arc
FUGU    = ..
BIN     = run_parser_tests

all: $(BIN)

$(BIN):
	$(CC) $(CFLAGS) -x objective-c -framework Foundation \
		-I$(FUGU)/src/sftp \
		-I$(FUGU)/src/extensions \
		-I$(FUGU)/src/util \
		$(FUGU)/src/util/argcargv.c \
		$(FUGU)/src/util/typeforchar.c \
		$(FUGU)/src/extensions/NSString-UnknownEncoding.m \
		$(FUGU)/src/extensions/NSString\(SSHAdditions\).m \
		$(FUGU)/src/sftp/SFTPListingParser.m \
		test_listing_parser.m \
		-o $@

test: $(BIN)
	./$(BIN)

clean:
	rm -f $(BIN)
