CC      = clang
CFLAGS  = -std=c99 -Wall -Wextra -Werror -Wno-sign-compare -fno-objc-arc
FUGU    = ..
BIN     = run_parser_tests

all: $(BIN)

$(BIN):
	$(CC) $(CFLAGS) -x objective-c -framework Foundation \
		-I$(FUGU) \
		$(FUGU)/argcargv.c \
		$(FUGU)/typeforchar.c \
		$(FUGU)/NSString-UnknownEncoding.m \
		$(FUGU)/NSString\(SSHAdditions\).m \
		$(FUGU)/SFTPListingParser.m \
		test_listing_parser.m \
		-o $@

test: $(BIN)
	./$(BIN)

clean:
	rm -f $(BIN)
