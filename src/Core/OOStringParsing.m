/*

OOStringParsing.m

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

#import "OOStringParsing.h"
#import "OOLogging.h"
#import "NSScannerOOExtensions.h"
#import "legacy_random.h"
#import "Universe.h"
#import "PlayerEntity.h"
#import "PlayerEntityLegacyScriptEngine.h"
#import "OOFunctionAttributes.h"
#import "OOCollectionExtractors.h"
#import "ResourceManager.h"

#import "OOJavaScriptEngine.h"
#import "OOJSEngineTimeManagement.h"


#define NSMakeRange(loc, len) ((NSRange){loc, len})


static NSString * const kOOLogStringVectorConversion			= @"strings.conversion.vector";
static NSString * const kOOLogStringQuaternionConversion		= @"strings.conversion.quaternion";
static NSString * const kOOLogStringVecAndQuatConversion		= @"strings.conversion.vectorAndQuaternion";
static NSString * const kOOLogStringRandomSeedConversion		= @"strings.conversion.randomSeed";


NSMutableArray *ScanTokensFromString(NSString *values)
{
	NSMutableArray			*result = nil;
	NSScanner				*scanner = nil;
	NSString				*token = nil;
	static NSCharacterSet	*space_set = nil;
	
	// Note: Shark suggests we're getting a lot of early exits, but testing showed a pretty steady 2% early exit rate.
	if (EXPECT_NOT(values == nil))  return [NSArray array];
	if (EXPECT_NOT(space_set == nil)) space_set = [[NSCharacterSet whitespaceAndNewlineCharacterSet] retain];
	
	result = [NSMutableArray array];
	scanner = [NSScanner scannerWithString:values];
	
	while (![scanner isAtEnd])
	{
		[scanner ooliteScanCharactersFromSet:space_set intoString:NULL];
		if ([scanner ooliteScanUpToCharactersFromSet:space_set intoString:&token])
		{
			[result addObject:token];
		}
	}
	
	return result;
}


BOOL ScanVectorFromString(NSString *xyzString, Vector *outVector)
{
	GLfloat					xyz[] = {0.0, 0.0, 0.0};
	int						i = 0;
	NSString				*error = nil;
	NSScanner				*scanner = nil;
	
	assert(outVector != NULL);
	if (xyzString == nil) return NO;
	
	if (!error) scanner = [NSScanner scannerWithString:xyzString];
	while (![scanner isAtEnd] && i < 3 && !error)
	{
		if (![scanner scanFloat:&xyz[i++]])  error = @"could not scan a float value.";
	}
	
	if (!error && i < 3)  error = @"found less than three float values.";
	
	if (!error)
	{
		*outVector = make_vector(xyz[0], xyz[1], xyz[2]);
		return YES;
	}
	else
	{
		 OOLogERR(kOOLogStringVectorConversion, @"cannot make vector from '%@': %@", xyzString, error);
		 return NO;
	}
}


BOOL ScanQuaternionFromString(NSString *wxyzString, Quaternion *outQuaternion)
{
	GLfloat					wxyz[] = {1.0, 0.0, 0.0, 0.0};
	int						i = 0;
	NSString				*error = nil;
	NSScanner				*scanner = nil;
	
	assert(outQuaternion != NULL);
	if (wxyzString == nil) return NO;
	
	if (!error) scanner = [NSScanner scannerWithString:wxyzString];
	while (![scanner isAtEnd] && i < 4 && !error)
	{
		if (![scanner scanFloat:&wxyz[i++]])  error = @"could not scan a float value.";
	}
	
	if (!error && i < 4)  error = @"found less than four float values.";
	
	if (!error)
	{
		outQuaternion->w = wxyz[0];
		outQuaternion->x = wxyz[1];
		outQuaternion->y = wxyz[2];
		outQuaternion->z = wxyz[3];
		quaternion_normalize(outQuaternion);
		return YES;
	}
	else
	{
		OOLogERR(kOOLogStringQuaternionConversion, @"cannot make quaternion from '%@': %@", wxyzString, error);
		return NO;
	}
}


BOOL ScanVectorAndQuaternionFromString(NSString *xyzwxyzString, Vector *outVector, Quaternion *outQuaternion)
{
	GLfloat					xyzwxyz[] = { 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0};
	int						i = 0;
	NSString				*error = nil;
	NSScanner				*scanner = nil;
	
	assert(outVector != NULL && outQuaternion != NULL);
	if (xyzwxyzString == nil) return NO;
	
	if (!error) scanner = [NSScanner scannerWithString:xyzwxyzString];
	while (![scanner isAtEnd] && i < 7 && !error)
	{
		if (![scanner scanFloat:&xyzwxyz[i++]])  error = @"Could not scan a float value.";
	}
	
	if (!error && i < 7)  error = @"Found less than seven float values.";
	
	if (error)
	{
		OOLogERR(kOOLogStringQuaternionConversion, @"cannot make vector and quaternion from '%@': %@", xyzwxyzString, error);
		return NO;
	}
	
	outVector->x = xyzwxyz[0];
	outVector->y = xyzwxyz[1];
	outVector->z = xyzwxyz[2];
	outQuaternion->w = xyzwxyz[3];
	outQuaternion->x = xyzwxyz[4];
	outQuaternion->y = xyzwxyz[5];
	outQuaternion->z = xyzwxyz[6];
	
	return YES;
}


Vector VectorFromString(NSString *xyzString, Vector defaultValue)
{
	Vector result;
	if (!ScanVectorFromString(xyzString, &result))  result = defaultValue;
	return result;
}


Quaternion QuaternionFromString(NSString *wxyzString, Quaternion defaultValue)
{
	Quaternion result;
	if (!ScanQuaternionFromString(wxyzString, &result))  result = defaultValue;
	return result;
}


NSString *StringFromPoint(NSPoint point)
{
	return [NSString stringWithFormat:@"%f %f", point.x, point.y];
}


NSPoint PointFromString(NSString *xyString)
{
	NSArray		*tokens = ScanTokensFromString(xyString);
	NSPoint		result = NSZeroPoint;
	
	NSUInteger n_tokens = [tokens count];
	if (n_tokens == 2)
	{
		result.x = [[tokens objectAtIndex:0] floatValue];
		result.y = [[tokens objectAtIndex:1] floatValue];
	}
	return result;
}


Random_Seed RandomSeedFromString(NSString *abcdefString)
{
	Random_Seed				result;
	int						abcdef[] = { 0, 0, 0, 0, 0, 0};
	int						i = 0;
	NSString				*error = nil;
	NSScanner				*scanner = [NSScanner scannerWithString:abcdefString];
	
	while (![scanner isAtEnd] && i < 6 && !error)
	{
		if (![scanner scanInt:&abcdef[i++]])  error = @"could not scan a int value.";
	}
	
	if (!error && i < 6)  error = @"found less than six int values.";
	
	if (!error)
	{
		result.a = abcdef[0];
		result.b = abcdef[1];
		result.c = abcdef[2];
		result.d = abcdef[3];
		result.e = abcdef[4];
		result.f = abcdef[5];
	}
	else
	{
		OOLogERR(kOOLogStringRandomSeedConversion, @"cannot make Random_Seed from '%@': %@", abcdefString, error);
		result = kNilRandomSeed;
	}
	
	return result;
}


NSString *StringFromRandomSeed(Random_Seed seed)
{
	return [NSString stringWithFormat: @"%d %d %d %d %d %d", seed.a, seed.b, seed.c, seed.d, seed.e, seed.f];
}


NSString *OOPadStringTo(NSString * string, float numSpaces)
{
	NSString		*result = string;
	numSpaces -= [result length];
	if (numSpaces>0)
	{
		result=[[@"" stringByPaddingToLength: numSpaces*2 withString: @" " startingAtIndex:0] stringByAppendingString: result];
	}
	return result;
}


NSString *OOStringFromDeciCredits(OOCreditsQuantity tenthsOfCredits, BOOL includeDecimal, BOOL includeSymbol)
{
	JSContext			*context = OOJSAcquireContext();
	JSObject			*global = [[OOJavaScriptEngine sharedEngine] globalObject];
	JSObject			*fakeRoot;
	jsval				method;
	jsval				rval;
	NSString			*result = nil;
	jsval				exception;
	BOOL				hadException;
	
	hadException = JS_GetPendingException(context, &exception);
	JS_ClearPendingException(context);
	
	if (JS_GetMethodById(context, global, OOJSID("formatCredits"), &fakeRoot, &method))
	{
		jsval args[3];
		if (JS_NewNumberValue(context, tenthsOfCredits * 0.1, &args[0]))
		{
			args[1] = OOJSValueFromBOOL(includeDecimal);
			args[2] = OOJSValueFromBOOL(includeSymbol);
			
			OOJSStartTimeLimiter();
			JS_CallFunctionValue(context, global, method, 3, args, &rval);
			OOJSStopTimeLimiter();
			
			result = OOStringFromJSValue(context, rval);
		}
	}
	
	if (hadException)  JS_SetPendingException(context, exception);
	
	OOJSRelinquishContext(context);
	
	if (EXPECT_NOT(result == nil))  result = [NSString stringWithFormat:@"%li", (long)(tenthsOfCredits) / 10];
	
	return result;
}


@implementation NSString (OOUtilities)

- (BOOL)pathHasExtension:(NSString *)extension
{
	return [[self pathExtension] caseInsensitiveCompare:extension] == NSOrderedSame;
}


- (BOOL)pathHasExtensionInArray:(NSArray *)extensions
{
	NSEnumerator	*extEnum = nil;
	NSString		*extension = nil;
	
	for (extEnum = [extensions objectEnumerator]; (extension = [extEnum nextObject]); )
	{
		if ([[self pathExtension] caseInsensitiveCompare:extension] == NSOrderedSame) return YES;
	}
	
	return NO;
}

@end


NSArray *ComponentsFromVersionString(NSString *string)
{
	NSArray				*stringComponents = nil;
	NSMutableArray		*result = nil;
	NSUInteger			i, count;
	int					value;
	id					component;
	
	stringComponents = [string componentsSeparatedByString:@" "];
	stringComponents = [[stringComponents objectAtIndex:0] componentsSeparatedByString:@"-"];
	stringComponents = [[stringComponents objectAtIndex:0] componentsSeparatedByString:@"."];
	count = [stringComponents count];
	result = [NSMutableArray arrayWithCapacity:count];
	
	for (i = 0; i != count; ++i)
	{
		component = [stringComponents objectAtIndex:i];
		if ([component respondsToSelector:@selector(intValue)])  value = MAX([component intValue], 0);
		else  value = 0;
		
		[result addObject:[NSNumber numberWithUnsignedInt:value]];
	}
	
	return result;
}


NSComparisonResult CompareVersions(NSArray *version1, NSArray *version2)
{
	NSEnumerator		*leftEnum = nil,
						*rightEnum = nil;
	NSNumber			*leftComponent = nil,
						*rightComponent = nil;
	unsigned			leftValue,
						rightValue;
	
	leftEnum = [version1 objectEnumerator];
	rightEnum = [version2 objectEnumerator];
	
	for (;;)
	{
		leftComponent = [leftEnum nextObject];
		rightComponent = [rightEnum nextObject];
		
		if (leftComponent == nil && rightComponent == nil)  break;	// End of both versions
		
		// We'll get 0 if the component is nil, which is what we want.
		leftValue = [leftComponent unsignedIntValue];
		rightValue = [rightComponent unsignedIntValue];
		
		if (leftValue < rightValue) return NSOrderedAscending;
		if (leftValue > rightValue) return NSOrderedDescending;
	}
	
	// If there was a difference, we'd have returned already.
	return NSOrderedSame;
}


NSString *ClockToString(double clock, BOOL adjusting)
{
	int				days, hrs, mins, secs;
	NSString		*format = nil;
	
	days = floor(clock / 86400.0);
	secs = floor(clock - days * 86400.0);
	hrs = floor(secs / 3600.0);
	secs %= 3600;
	mins = floor(secs / 60.0);
	secs %= 60;
	
	if (adjusting)  format = DESC(@"clock-format-adjusting");
	else  format = DESC(@"clock-format");
	
	return [NSString stringWithFormat:format, days, hrs, mins, secs];
}


#if DEBUG_GRAPHVIZ

// Workaround for Xcode auto-indent bug
static NSString * const kQuotationMark = @"\"";
static NSString * const kEscapedQuotationMark = @"\\\"";


NSString *EscapedGraphVizString(NSString *string)
{
	NSString * const srcStrings[] =
	{
		//Note: backslash must be first.
		@"\\", @"\"", @"\'", @"\r", @"\n", @"\t", nil
	};
	NSString * const subStrings[] =
	{
		//Note: must be same order.
		@"\\\\", @"\\\"", @"\\\'", @"\\r", @"\\n", @"\\t", nil
	};
	
	NSString * const *		src = srcStrings;
	NSString * const *		sub = subStrings;
	NSMutableString			*mutable = nil;
	NSString				*result = nil;
	
	mutable = [string mutableCopy];
	while (*src != nil)
	{
		[mutable replaceOccurrencesOfString:*src++
								 withString:*sub++
									options:0
									  range:NSMakeRange(0, [mutable length])];
	}
	
	if ([mutable length] == [string length])
	{
		result = string;
	}
	else
	{
		result = [[mutable copy] autorelease];
	}
	[mutable release];
	return result;
}


static BOOL NameIsTaken(NSString *name, NSSet *uniqueSet);

NSString *GraphVizTokenString(NSString *string, NSMutableSet *uniqueSet)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
	BOOL lastWasUnderscore = NO;
	NSUInteger i, length = [string length], ri = 0;
	unichar result[length];
	NSString *token = nil;
	
	if (length > 0)
	{
		// Special case for first char - can't be digit.
		unichar c = [string characterAtIndex:0];
		if (!isalpha(c))
		{
			c = '_';
			lastWasUnderscore = YES;
		}
		result[ri++] = c;
		
		for (i = 1; i < length; i++)
		{
			c = [string characterAtIndex:i];
			if (!isalnum(c))
			{
				if (lastWasUnderscore)  continue;
				c = '_';
				lastWasUnderscore = YES;
			}
			else
			{
				lastWasUnderscore = NO;
			}
			
			result[ri++] = c;
		}
		
		token = [NSString stringWithCharacters:result length:ri];
	}
	else
	{
		token = @"_";
	}
	
	if (NameIsTaken(token, uniqueSet))
	{
		if (!lastWasUnderscore)  token = [token stringByAppendingString:@"_"];
		NSString *uniqueToken = nil;
		unsigned uniqueID = 2;
		
		for (;;)
		{
			uniqueToken = [NSString stringWithFormat:@"%@%u", token, uniqueID];
			if (!NameIsTaken(uniqueToken, uniqueSet))  break;
		}
		token = uniqueToken;
	}
	[uniqueSet addObject:token];
	
	[token retain];
	[pool release];
	return [token autorelease];
}


static BOOL NameIsTaken(NSString *name, NSSet *uniqueSet)
{
	if ([uniqueSet containsObject:name])  return YES;
	
	static NSSet *keywords = nil;
	if (keywords == nil)  keywords = [[NSSet alloc] initWithObjects:@"node", @"edge", @"graph", @"digraph", @"subgraph", @"strict", nil];
	
	return [keywords containsObject:[name lowercaseString]];
}

#endif //DEBUG_GRAPHVIZ
