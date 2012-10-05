/*

OOStringParsing.h

Various functions for interpreting values from strings.

Oolite
Copyright (C) 2004-2012 Giles C Williams and contributors

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
#import "OOMaths.h"
#import "OOTypes.h"
#import "legacy_random.h"

@class Entity;


// If set, use new faster string expander with saner (but not entirely backwards-compatible) semantics.
#define NEW_STRING_EXPANDER 1


NSMutableArray *ScanTokensFromString(NSString *values);

// Note: these functions will leave their out values untouched if they fail (and return NO). They will not log an error if passed a NULL string (but will return NO). This means they can be used to, say, read dictionary entries which might not exist. They also ignore any extra components in the string.
BOOL ScanVectorFromString(NSString *xyzString, Vector *outVector);
BOOL ScanQuaternionFromString(NSString *wxyzString, Quaternion *outQuaternion);
BOOL ScanVectorAndQuaternionFromString(NSString *xyzwxyzString, Vector *outVector, Quaternion *outQuaternion);

Vector VectorFromString(NSString *xyzString, Vector defaultValue);
Quaternion QuaternionFromString(NSString *wxyzString, Quaternion defaultValue);

NSString *StringFromPoint(NSPoint point);
NSPoint PointFromString(NSString *xyString);

Random_Seed RandomSeedFromString(NSString *abcdefString);
NSString *StringFromRandomSeed(Random_Seed seed);


NSString *ExpandDescriptionForSeed(NSString *text, Random_Seed seed, NSString *name);
NSString *ExpandDescriptionForCurrentSystem(NSString *text);

NSString *ExpandDescriptionsWithOptions(NSString *text, Random_Seed seed, NSDictionary *overrides, NSDictionary *locals, NSString *pName);

NSString *DescriptionForSystem(Random_Seed seed,NSString *name);
NSString *DescriptionForCurrentSystem(void);

// target and localVariables are optional; target will default to the player.
NSString *ReplaceVariables(NSString *string, Entity *target, NSDictionary *localVariables);

NSString *RandomDigrams(void);


NSString *OOStringFromDeciCredits(OOCreditsQuantity tenthsOfCredits, BOOL includeDecimal, BOOL includeSymbol);
OOINLINE NSString *OOStringFromIntCredits(OOCreditsQuantity integerCredits, BOOL includeSymbol)
{
	return OOStringFromDeciCredits(integerCredits * 10, NO, includeSymbol);
}

OOINLINE NSString *OOCredits(OOCreditsQuantity tenthsOfCredits)
{
	return OOStringFromDeciCredits(tenthsOfCredits, YES, YES);
}
OOINLINE NSString *OOIntCredits(OOCreditsQuantity integerCredits)
{
	return OOStringFromIntCredits(integerCredits, YES);
}

NSString *OOPadStringTo(NSString * string, float numSpaces);

@interface NSString (OOUtilities)

// Case-insensitive match of [self pathExtension]
- (BOOL)pathHasExtension:(NSString *)extension;
- (BOOL)pathHasExtensionInArray:(NSArray *)extensions;

@end


// Given a string of the form 1.2.3.4 (with arbitrarily many components), return an array of unsigned ints.
NSArray *ComponentsFromVersionString(NSString *string);

/*	Compare two arrays of unsigned int NSNumbers, as returned by
	ComponentsFromVersionString().
	
	Components are ordered from most to least significant, and a missing
	component is treated as 0. Thus "1.7" < "1.60", and "1.2.3.0" == "1.2.3".
*/
NSComparisonResult CompareVersions(NSArray *version1, NSArray *version2);


NSString *ClockToString(double clock, BOOL adjusting);


#if DEBUG_GRAPHVIZ
NSString *EscapedGraphVizString(NSString *string);

/*	GraphVizTokenString()
	Generate a C-style identifier. Sequences of invalid characters and
	underscores are replaced with single underscores. If uniqueSet is not nil,
	uniqueness is achieved by appending numbers if necessary.
	
	This can be used for any C-based langauge, but note that it excludes the
	case-insensitive GraphViz keywords node, edge, graph, digraph, subgraph
	and strict.
*/
NSString *GraphVizTokenString(NSString *string, NSMutableSet *uniqueSet);

#endif
