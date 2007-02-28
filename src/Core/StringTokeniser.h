/*

StringTokeniser.h

Script Compiler for Oolite
Copyright (C) 2006 David Taylor

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
MA 02110-1301, USA.

*/

#import <Foundation/Foundation.h>

#define TT_WORD 1
#define TT_EOL 2
#define TT_EOS 3

@interface StringTokeniser : NSObject
{
@public
	// A local copy of the string to be parsed
	NSString* stringToParse;
	char* cString;

	// The zero based index of the next character to be parsed. 0 <= nextcharIdx < [stringToParse length]
	int nextCharIdx;

	// The index to go back to when a pushBack is issued
	int pushBackIdx;

	// Set to one of the TT_* constants after a call to nextToken
	int tokenType;

	// The line number currently being parsed
	int lineNo;

	// If tokenType is TT_WORD this contains a reference to the parsed word
	NSString* tokenWord;
	char* tokenPtr;
}

// Initialise an instance of the string tokeniser to parse the given string
- (id)initWithString:(NSString*)string;
- (void) dealloc;

// Parse the next token and set the tokenType property appropriately
- (void)nextToken;

// Push back the current token so the next call to nextToken returns
// the same one
- (void)pushBack;

// Returns true once the entire string has been parsed
- (BOOL)reachedEOS;

@end
