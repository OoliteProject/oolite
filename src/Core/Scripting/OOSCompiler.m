/*

ScriptCompiler.m

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
#import "OOSTokenizer.h"

#define kOOLogUnconvertedNSLog @"unclassified.OOSCompiler"


@interface NSMutableString (OOScript)

- (void) replaceString:(NSString*)aString withString:(NSString*)otherString;
- (void) trimSpaces;

@end

@implementation NSMutableString (OOScript)

- (void) replaceString:(NSString*)aString withString:(NSString*)otherString
{
	[self replaceOccurrencesOfString:aString withString:otherString options:0 range:NSMakeRange(0,[self length])];
}

- (void) trimSpaces
{
	[self setString:[self stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]];
}

@end


/*
 * Preprocess the source read from the oos file.
 *
 * Strips blank lines and lines beginning with "//".
 * Strips leading and trailing whitespace off any lines that are left.
 *
 * Returns the processed source.
 */
NSString* preprocess(NSString* source) {
	int i;
	NSMutableString *processedSource = [NSMutableString stringWithString:source];
	// convert DOS and MAC EOLs to *NIX EOL (DOS EOL will create blank lines,
	// but these are filtered out in the loop)
	[processedSource replaceOccurrencesOfString:@"\r" withString:@"\n" options:NSLiteralSearch range:NSMakeRange(0, [processedSource length])];
	NSArray *lines = [processedSource componentsSeparatedByString:@"\n"];
	[processedSource setString:@""];

	for (i = 0; i < [lines count]; i++) {
		NSString* line = [(NSString*)[lines objectAtIndex:i] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
		if ([line length] == 0)
			continue;
		if ([line hasPrefix:@"//"])
			continue;

		[processedSource appendString:line];
		[processedSource appendString:@"\n"];
	}

	return [NSString stringWithString:processedSource];
}


NSDictionary* parseIf(OOSTokenizer* st) {
	NSMutableString *statement = [NSMutableString stringWithCapacity:80];
	NSMutableArray *conditions = [[NSMutableArray alloc] init];
	NSMutableArray *actions = [[NSMutableArray alloc] init];
	NSMutableDictionary *ifDict = [[NSMutableDictionary alloc] initWithCapacity:3];
	BOOL inElse = NO;

	[st nextToken];
	while (st->tokenType != TT_WORD) {
		if (st->tokenType == TT_EOS) {
			// end of the script - this is fine while looking for an "if"
			return nil;
		}

		[st nextToken];
	}

	if ([st->tokenWord isEqual:@"if"] != YES) {
		NSLog(@"ScriptCompiler: Error (line %d): expected \"if\", found %@", st->lineNo, st->tokenWord);
		return nil;
	}

	// parse the conditions
	while (1) {
		[st nextToken];
		if (st->tokenType == TT_EOL)
			continue;

		if (st->tokenType == TT_EOS) {
			NSLog(@"ScriptCompiler: Error (line %d): unexpected end of script", st->lineNo);
			return nil;
		}

		if ([st->tokenWord isEqual:@"then"] == YES) {
			[statement trimSpaces];
			[statement replaceString:@" = " withString:@" equal "];
			[statement replaceString:@" < " withString:@" lessthan "];
			[statement replaceString:@" > " withString:@" greaterthan "];

			NSString* c = [NSString stringWithString: statement];
			[conditions addObject:c];
			[statement setString:@""]; // is also used for the actions so needs to be cleared
			break; // got the then keyword so now parse the actions
		}

		if ([st->tokenWord isEqual:@"and"] == YES) {
			[statement trimSpaces];
			[statement replaceString:@" = " withString:@" equal "];
			[statement replaceString:@" < " withString:@" lessthan "];
			[statement replaceString:@" > " withString:@" greaterthan "];
			NSString* c = [NSString stringWithString: statement];
			[conditions addObject:c];
			[statement setString:@""];
			continue;
		}

		[statement appendString:st->tokenWord];
		[statement appendString:@" "];
	}

	[ifDict setObject:conditions forKey:@"conditions"];

	// parse the actions, including else and endif keywords
	while (1) {
		[st nextToken];
		if (st->tokenType == TT_EOL) { // marks the end of an action
			[statement trimSpaces];
			if ([statement length] > 0) {
				NSString* c = [NSString stringWithString: statement];
				[actions addObject:c];
				[statement setString:@""];
			}
			continue;
		}

		if (st->tokenType == TT_EOS) {
			NSLog(@"ScriptCompiler: Error (line %d): unexpected end of script, expected else or endif", st->lineNo);
			return nil;
		}

		if ([st->tokenWord isEqual:@"else"] == YES) {
			if (inElse == YES) {
				NSLog(@"ScriptCompiler: Error (line %d): already in \"else\" block", st->lineNo);
				return nil;
			}

			[ifDict setObject:actions forKey:@"do"];
			[statement setString:@""];
			actions = [[NSMutableArray alloc] init];
			inElse = YES;
			continue;
		}

		if ([st->tokenWord isEqual:@"endif"] == YES) {
			if (inElse == YES) {
				[ifDict setObject:actions forKey:@"else"];
			} else {
				[ifDict setObject:actions forKey:@"do"];
			}

			[statement setString:@""];
			break;
		}

		if ([st->tokenWord isEqual:@"if"] == YES) {
			[st pushBack];
			NSDictionary* ifDict = parseIf(st);
			if (ifDict != nil) {

				[actions addObject:ifDict];
			}
			else
				break; //if we read "if" and got nil back, there has certainly been an error so bail out

			continue;
		}

		[statement appendString:st->tokenWord];
		[statement appendString:@" "];
	}

	return ifDict;
}


NSDictionary* ParseOOSScripts(NSString* script) {
	NSString *processedScript = preprocess(script);
	OOSTokenizer *st = [[OOSTokenizer alloc] initWithString:processedScript];
	NSMutableDictionary *scriptDict = [[NSMutableDictionary alloc] initWithCapacity:10];
	NSDictionary *ifDict;
	NSMutableArray *ifStatements = [[NSMutableArray alloc] init];
	NSString *scriptName;

	while (st->tokenType != TT_EOS) {
		[st nextToken];
		if (st->tokenType == TT_EOL)
			continue;

		if (st->tokenType == TT_EOS)
			return nil;

		scriptName = [NSString stringWithString:st->tokenWord];
		while (st->tokenType != TT_EOS) {
			[st nextToken];
			if (st->tokenType == TT_EOL)
				continue;

			if ([st->tokenWord isEqual:@"if"] == YES) {
				[st pushBack];
				ifDict = parseIf(st);
				if (ifDict != nil) {
					[ifStatements addObject:ifDict];
				}
			} else {
				[scriptDict setObject:ifStatements forKey:scriptName];
				ifStatements = [[NSMutableArray alloc] init];
				[st pushBack];
				break;
			}
		}


	}

	return scriptDict;
}

#ifdef SC_TEST
int main (int argc, char** argv)
{
	int i;

	NSAutoreleasePool *arp = [[NSAutoreleasePool alloc] init];
	NSString *filename = [NSString stringWithCString:argv[1]];

	NSString *script = [NSString stringWithContentsOfFile:filename];
	NSDictionary *scriptDict = parseScripts(script);
	[scriptDict writeToFile:@"x.plist" atomically:YES];
	[arp release];
	return 0;
}
#endif
