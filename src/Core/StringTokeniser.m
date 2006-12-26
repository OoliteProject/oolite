#import "StringTokeniser.h"

@implementation StringTokeniser : NSObject

// Initialise an instance of the string tokeniser to parse the given string
- (id)initWithString:(NSString*)string {
	const char* strPtr;
	self = [super init];
	stringToParse = [NSString stringWithString:string];
	strPtr = [stringToParse cString];
	cString = (char*)calloc(strlen(strPtr)+1, sizeof(char));
	strcpy(cString, strPtr);
	nextCharIdx = 0;
	lineNo = 1;
	return self;
}

- (void) dealloc {
	if (cString != 0x00)
		free(cString);

	if (tokenPtr != 0x00)
		free(tokenPtr);

	[super dealloc];
}

// Parse the next token and set the tokenType property appropriately
- (void)nextToken {
	int startWordIdx;
	int len;

	// Incrementing lineNo here so that errors caused by new lines don't get
	// reported on the line after the error, as would happen if lineNo was
	// incremented when the TT_EOL token is returned.
	if (tokenType == TT_EOL)
		lineNo++;

	if (nextCharIdx >= [stringToParse length]) {
		tokenType = TT_EOS;
		return;
	}

	// skip whitespace before next word or EOL
	while (cString[nextCharIdx] == 0x20 || cString[nextCharIdx] == 0x09) {
		nextCharIdx++;
		pushBackIdx = nextCharIdx;
		if (nextCharIdx >= [stringToParse length]) {
			tokenType = TT_EOS;
			return;
		}
	}

	if (cString[nextCharIdx] == 0x0A) {
		tokenType = TT_EOL;
		nextCharIdx++;
		pushBackIdx = nextCharIdx;
		return;
	}

	startWordIdx = nextCharIdx;
	pushBackIdx = nextCharIdx;
	while (cString[nextCharIdx] != 0x20 && cString[nextCharIdx] != 0x09 && cString[nextCharIdx] != 0x0A) {
		nextCharIdx++;
		if (nextCharIdx >= [stringToParse length]) {
			break;
		}
	}

	len = nextCharIdx - startWordIdx+1;
	tokenPtr = calloc(len, sizeof(char));
	strncpy(tokenPtr, &cString[startWordIdx], len-1);
	tokenWord = [NSString stringWithCString:tokenPtr];
	free(tokenPtr);
	tokenPtr = 0x00;
	tokenType = TT_WORD;

	return;
}

- (void)pushBack {
	nextCharIdx = pushBackIdx;
}

// Returns true once the entire string has been parsed
- (BOOL)reachedEOS {
	if (nextCharIdx >= [stringToParse length])
		return YES;

	return NO;
}

@end
