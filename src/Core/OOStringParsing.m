/*

OOStringParsing.m

Oolite
Copyright (C) 2004-2010 Giles C Williams and contributors

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


static NSString * const kOOLogStringVectorConversion			= @"strings.conversion.vector";
static NSString * const kOOLogStringQuaternionConversion		= @"strings.conversion.quaternion";
static NSString * const kOOLogStringVecAndQuatConversion		= @"strings.conversion.vectorAndQuaternion";
static NSString * const kOOLogStringRandomSeedConversion		= @"strings.conversion.randomSeed";
static NSString * const kOOLogExpandDescriptionsRecursionLimitExceeded	= @"strings.expand.recursionLimit";
static NSString * const kOOLogDebugReplaceVariablesInString		= @"script.debug.replaceVariablesInString";

static NSString *OldRandomDigrams(void);
static NSString *NewRandomDigrams(void);


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
	
	int n_tokens = [tokens count];
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


NSString *ExpandDescriptionForSeed(NSString *text, Random_Seed seed)
{
	return ExpandDescriptionForSeedName(text, seed, nil);

}


NSString *ExpandDescriptionForSeedName(NSString *text, Random_Seed seed, NSString *name)
{
	// to enable variables to return strings that can be expanded (eg. @"[commanderName_string]")
	// we're going to loop until every expansion has been done!
	// but to check this does not infinitely recurse
	// we'll stop after 32 loops.

	if (text == nil)  return nil;
	
	int stack_check = 32;
	NSString	*old_desc = nil;
	NSString	*result = text;
	
	do
	{
		old_desc = result;
		result = ExpandDescriptionsWithLocalsForSystemSeedName(result, seed, nil, name);
	} while (--stack_check && ![result isEqual:old_desc]);
	
	if (!stack_check)
	{
		// If we get here, we broke the loop due to recursion; the resulting string will have [expansionKey]s in it.
		OOLogERR(kOOLogExpandDescriptionsRecursionLimitExceeded, @"exceeded recusion limit trying to expand description \"%@\"", text);
	}
	
	return result;
}


NSString *ExpandDescriptionForCurrentSystem(NSString *text)
{
	return ExpandDescriptionForSeed(text, [[PlayerEntity sharedPlayer] system_seed]);
}


NSString *ExpandDescriptionsWithLocalsForSystemSeed(NSString *text, Random_Seed seed, NSDictionary *locals)
{
	return ExpandDescriptionsWithLocalsForSystemSeedName(text, seed, locals, nil);
}


NSString *ExpandDescriptionsWithLocalsForSystemSeedName(NSString *text, Random_Seed seed, NSDictionary *locals, NSString *pName)
{
	return ExpandDescriptionsWithOverridesAndLocalsForSystemSeedName(text, seed, nil, locals, pName);
}


NSString *ExpandDescriptionsWithOverridesAndLocalsForSystemSeedName(NSString *text, Random_Seed seed, NSDictionary *overrides, NSDictionary *legacyLocals, NSString *pName)
{
	PlayerEntity		*player = [PlayerEntity sharedPlayer];
	NSMutableString		*partial = [[text mutableCopy] autorelease];
	NSMutableDictionary	*all_descriptions = [[[UNIVERSE descriptions] mutableCopy] autorelease];
	id					value = nil;
	NSString			*part = nil, *before = nil, *after = nil, *middle = nil;
	OOUInteger			sub, rnd, opt;
	OOUInteger			p1, p2;
	NSArray				*sysDesc = nil;
	NSArray				*sysDescItem = nil;
	OOUInteger			sysDescCount = 0, descItemCount;
	
	// always add player info when possible, they might be nested ( fixes berlios bug #16369 )
	// at startup shared_player hasn't got a ship yet, so check for that before adding the player info.
	if ([player commanderShip_string])
	{
		[all_descriptions setObject:[player commanderName_string] forKey:@"commander_name"];
		[all_descriptions setObject:[player commanderShip_string] forKey:@"commander_shipname"];
		[all_descriptions setObject:[player commanderShipDisplayName_string] forKey:@"commander_shipdisplayname"];
		[all_descriptions setObject:[player commanderRank_string] forKey:@"commander_rank"];
		[all_descriptions setObject:[player commanderLegalStatus_string] forKey:@"commander_legal_status"];
		[all_descriptions setObject:[NSString stringWithFormat:@"%@",[player commanderLegalStatus_number]] forKey:@"commander_bounty"];
	}
	[all_descriptions setObject:OOStringFromDeciCredits([player deciCredits], YES, NO) forKey:@"credits_number"];
	if (pName == nil)  pName = [UNIVERSE getSystemName:seed];
	
	while ([partial rangeOfString:@"["].location != NSNotFound)
	{
		p1 = [partial rangeOfString:@"["].location;
		// now either find the first occurrence of ']', or NSNotFound !
		p2 = [partial rangeOfString:@"]"].location;
		
		if (p2 == NSNotFound)
		{
			OOLogWARN(@"strings.expand", @"Cannot expand string without the closing bracket ( ] ).");
			break; // keep parsing the string for other tokens !
		}
		else 
		{
			p2++;
		}
		
		before = [partial substringWithRange:NSMakeRange(0, p1)];
		after = [partial substringWithRange:NSMakeRange(p2,[partial length] - p2)];
		middle = [partial substringWithRange:NSMakeRange(p1 + 1 , p2 - p1 - 2)];
		
		// Overrides override all else.
		part = ReplaceVariables(middle, NULL, overrides);
		
		// check all_descriptions for an array that's keyed to middle
		value = [all_descriptions objectForKey:middle];
		if ([value isKindOfClass:[NSArray class]] && [value count] > 0)
		{
			rnd = gen_rnd_number() % [value count];
			part = [value oo_stringAtIndex:rnd];
			if (part == nil)  part = @"";
		}
		else if ([value isKindOfClass:[NSString class]])
		{
			part = [all_descriptions objectForKey:middle];
		}
		else if ([[middle stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"0123456789"]] isEqual:@""])
		{
			part = @"";
			
			// if all characters are all from the set "0123456789" interpret it as a number in system_description array
			if (![middle isEqual:@""])
			{
				if (sysDesc == nil)
				{
					sysDesc = [all_descriptions oo_arrayForKey:@"system_description"];
					sysDescCount = [sysDesc count];
				}
				
				sub = [middle intValue];
				rnd = gen_rnd_number();
				
				if (sub < sysDescCount)
				{
					sysDescItem = [sysDesc oo_arrayAtIndex:sub];
					if (sysDescItem != nil)
					{
						descItemCount = [sysDescItem count];
						if (descItemCount == 5)
						{
							// Time-honoured Elite-compatible way for five items
							opt = 0;
							if (rnd >= 0x33) opt++;
							if (rnd >= 0x66) opt++;
							if (rnd >= 0x99) opt++;
							if (rnd >= 0xCC) opt++;
						}
						else
						{
							// General way
							opt = (rnd * descItemCount) / 256;
						}
						
						part = [sysDescItem objectAtIndex:opt];
					}
				}
			}
		}
		else
		{
			// do replacement of mission and local variables here instead.
			part = ReplaceVariables(middle, NULL, legacyLocals);
		}
		
		
		partial = [NSMutableString stringWithFormat:@"%@%@%@", before, part, after];
	}
	
	[partial replaceOccurrencesOfString:@"%H"
							 withString:pName
								options:NSLiteralSearch
								  range:NSMakeRange(0, [partial length])];
	
	[partial replaceOccurrencesOfString:@"%I"
							 withString:[NSString stringWithFormat:@"%@%@",pName, DESC(@"planetname-derivative-suffix")]
								options:NSLiteralSearch
								  range:NSMakeRange(0, [partial length])];
	
	[partial replaceOccurrencesOfString:@"%R"
							 withString:OldRandomDigrams()
								options:NSLiteralSearch
								  range:NSMakeRange(0, [partial length])];
	
	[partial replaceOccurrencesOfString:@"%N"
							 withString:NewRandomDigrams()
								options:NSLiteralSearch
								  range:NSMakeRange(0, [partial length])];
	
	
	// Now replace  all occurrences of %J000 to %J255 with the corresponding  system name. 
	
	NSRange foundToken, foundID;
	NSString *stringID=@"";
	char s;
	BOOL err=NO;
	int intVal;
	
    foundToken = [partial rangeOfString:@"%J"];
	
    while (foundToken.location != NSNotFound)
    {
		foundID=NSMakeRange(foundToken.location+2,3);
		if(foundID.location+3 > [partial length])
		{
			err = YES;
			stringID=[partial substringFromIndex:foundID.location];
		}
		else
		{
			stringID = [partial substringWithRange:foundID];
			// these 3 characters must be numerical: 000 to 255
			s=[stringID characterAtIndex:0];
			if (s < '0' || s > '2') err = YES;
			s=[stringID characterAtIndex:1];
			if (s < '0' || s > '9') err = YES;
			s=[stringID characterAtIndex:2];
			if (s < '0' || s > '9') err = YES;
			if (!err)
			{
				intVal = [stringID intValue];
				if ( intVal < 256 )
				{
					[partial	replaceOccurrencesOfString:[NSString stringWithFormat:@"%%J%@",stringID]
											 withString:[UNIVERSE getSystemName:[UNIVERSE systemSeedForSystemNumber:(OOSystemID)intVal]] 
												options:NSLiteralSearch range:NSMakeRange(0, [partial length])];
				}
				else
					err = YES;
			}
		}
		if (err)
		{
			static NSMutableSet *warned = nil;
			if (![warned containsObject:stringID])
			{
				OOLogWARN(@"strings.expand", @"'%%J%@' not a planetary system number - use %%Jxxx, where xxx is a number from 000 to 255",stringID);
				if (warned == nil)  warned = [[NSMutableSet alloc] init];
				[warned addObject:stringID];
			}
			err = NO; // keep parsing the string for other %J tokens!
		}
		
		if (foundID.location + 5 > [partial length])
		{
			foundToken.location=NSNotFound;
		}
		else
		{
			foundToken = [[partial substringFromIndex:foundID.location] rangeOfString:@"%J"];
			if (foundToken.location!=NSNotFound) foundToken.location += foundID.location;
		}
    }
	
	return partial; 
}


NSString *ExpandDescriptionsWithLocalsForCurrentSystem(NSString *text, NSDictionary *locals)
{
	return ExpandDescriptionsWithLocalsForSystemSeed(text, [[PlayerEntity sharedPlayer] system_seed], locals);
}


NSString *DescriptionForSystem(Random_Seed seed,NSString *name)
{
	seed_RNG_only_for_planet_description(seed);
	return ExpandDescriptionForSeedName(@"[system-description-string]", seed, name);
}


NSString *DescriptionForCurrentSystem(void)
{
	return DescriptionForSystem([[PlayerEntity sharedPlayer] system_seed], [UNIVERSE getSystemName:[[PlayerEntity sharedPlayer] system_seed]]);
}


NSString *ReplaceVariables(NSString *string, Entity *target, NSDictionary *localVariables)
{
	NSMutableString			*resultString = nil;
	NSMutableArray			*tokens = nil;
	NSEnumerator			*tokenEnum = nil;
	NSString				*token = nil;
	NSString				*replacement = nil;
	Entity					*effeciveTarget = nil;
	PlayerEntity			*player = nil;
	
	tokens = ScanTokensFromString(string);
	resultString = [NSMutableString stringWithString:string];
	player = [PlayerEntity sharedPlayer];
	if (target == nil) target = player;
	
	for (tokenEnum = [tokens objectEnumerator]; (token = [tokenEnum nextObject]); )
	{
		replacement = [player missionVariableForKey:token];
		if (replacement == nil)  replacement = [[localVariables objectForKey:token] description];
		if (replacement == nil)
		{
			if ([token hasSuffix:@"_number"] || [token hasSuffix:@"_bool"] || [token hasSuffix:@"_string"])
			{
				SEL value_selector = NSSelectorFromString(token);
				if ([target respondsToSelector:value_selector]) effeciveTarget = target;
				else if (target != player && [player respondsToSelector:value_selector]) effeciveTarget = player;
				else effeciveTarget = nil;
				
				if (effeciveTarget != nil)  replacement = [[effeciveTarget performSelector:value_selector] description];
			}
			else if ([token hasPrefix:@"["] && [token hasSuffix:@"]"])
			{
				replacement = ExpandDescriptionForCurrentSystem(token);
			}
		}
		
		if (replacement != nil) [resultString replaceOccurrencesOfString:token withString:replacement options:NSLiteralSearch range:NSMakeRange(0, [resultString length])];
	}

	OOLog(kOOLogDebugReplaceVariablesInString, @"EXPANSION: \"%@\" becomes \"%@\"", string, resultString);

	return resultString;
}


/*	Generates pseudo-random digram string using gen_rnd_number()
	(world-generation consistent PRNG), but misses some possibilities. Used
	for "%R" description string for backwards compatibility.
*/
static NSString *OldRandomDigrams(void)
{
	int i;
	int len = gen_rnd_number() & 3;	
	NSString*			digrams = [[UNIVERSE descriptions] objectForKey:@"digrams"];
	NSMutableString*	name = [NSMutableString stringWithCapacity:256];
	for (i = 0; i <=len; i++)
	{
		int x =  gen_rnd_number() & 0x3e;
		[name appendString:[digrams substringWithRange:NSMakeRange(x,2)]];
	}
	return [name capitalizedString]; 
}


/*	Generates pseudo-random digram string using gen_rnd_number()
	(world-generation consistent PRNG). Used for "%N" description string.
*/
static NSString *NewRandomDigrams(void)
{
	unsigned			i, length, count;
	NSString			*digrams = nil;
	NSMutableString		*name = nil;
	
	length = (gen_rnd_number() % 4) + 1;
	if ((gen_rnd_number() % 5) < ((length == 1) ? 3 : 1))  ++length;	// Make two-letter names rarer and 10-letter names happen sometimes
	digrams = [[UNIVERSE descriptions] objectForKey:@"digrams"];
	count = [digrams length] / 2;
	name = [NSMutableString stringWithCapacity:length * 2];
	
	for (i = 0; i != length; ++i)
	{
		[name appendString:[digrams substringWithRange:NSMakeRange((gen_rnd_number() % count) * 2, 2)]];
	}
	return [name capitalizedString];
}


// Similar to NewRandomDigrams(), but uses Ranrot() (the "really random" PRNG).
NSString *RandomDigrams(void)
{
	unsigned			i, length, count;
	NSString			*digrams = nil;
	NSMutableString		*name = nil;
	
	length = (Ranrot() % 4) + 1;
	if ((Ranrot() % 5) < ((length == 1) ? 3 : 1))  ++length;	// Make two-letter names rarer and 10-letter names happen sometimes
	digrams = [[UNIVERSE descriptions] objectForKey:@"digrams"];
	count = [digrams length] / 2;
	name = [NSMutableString stringWithCapacity:length * 2];
	
	for (i = 0; i != length; ++i)
	{
		[name appendString:[digrams substringWithRange:NSMakeRange((Ranrot() % count) * 2, 2)]];
	}
	return [name capitalizedString];
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
	NSString			*result = nil;
	unsigned long long	integerCredits = tenthsOfCredits / 10;
	unsigned long long	tenths = tenthsOfCredits % 10;
	
	if (includeDecimal)
	{
		result = [NSString stringWithFormat:@"%llu.%llu", integerCredits, tenths];
	}
	else
	{
		if (tenths >= 5)  integerCredits++;
		result = [NSString stringWithFormat:@"%llu", integerCredits];
	}
	
	// Append credits sybol if desired.
	if (includeSymbol)
	{
		result = [NSString stringWithFormat:DESC(@"@-credits"), result];
	}
	
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
	unsigned			i, count;
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
	OOUInteger i, length = [string length], ri = 0;
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
