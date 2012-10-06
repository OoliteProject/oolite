/*

OOStringExpander.m


Oolite
Copyright (C) 2004-2012 Giles C Williams and contributors

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the impllied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
MA 02110-1301, USA.

*/

#import "OOStringExpander.h"
#import "Universe.h"
#import "OOJavaScriptEngine.h"
#import "OOCollectionExtractors.h"
#import "OOStringParsing.h"
#import "ResourceManager.h"


// Don't bother with syntax warnings in Deployment builds.
#define WARNINGS			(!defined(NDEBUG))


enum
{
	/*
		Total stack limit for strings being parsed (in UTF-16 code elements,
		i.e. units of 2 bytes), used recursively - for instance, if the root
		string takes 10,000 characters, any string it recurses into gets
		kStackAllocationLimit - 10,000. If the limit would be exceeded,
		the unexpanded string is returned instead.
		
		The limit is expected to be much higher than necessary for any practical
		string, and exists only to catch pathological behaviour without crashing.
	*/
	kStackAllocationLimit		= UINT16_MAX,
	
	/*
		Recursion limit, for much the same purpose. Without it, we crash about
		22,000 stack frames deep when trying to expand a = "[a]" on a Mac.
	*/
	kRecursionLimit				= 100
};


/*	OOStringExpansionContext
	
	Struct used to store context and caches for the entire string expansion
	operation, including recursive calls (so it can't contain anything pertaining
	to the specific string being expanded).
*/
typedef struct
{
	Random_Seed			seed;
	NSString			*systemName;
	NSDictionary		*overrides;
	NSDictionary		*legacyLocals;
	bool				isJavaScript;
	bool				convertBackslashN;
	
	NSString			*systemNameWithIan;	// Cache for %I
	NSString			*randomNameN;		// Cache for %N
	NSString			*randomNameR;		// Cache for %R
	NSArray				*systemDescriptions;// Cache for system_description, used for numbered keys.
	NSUInteger			sysDescCount;		// Count of systemDescriptions, valid after GetSystemDescriptions() called.
} OOStringExpansionContext;


static NSString *GetSystemName(OOStringExpansionContext *context);		// %H
static NSString *GetSystemNameIan(OOStringExpansionContext *context);	// %I
static NSString *GetRandomNameN(OOStringExpansionContext *context);		// %N
static NSString *GetRandomNameR(OOStringExpansionContext *context);		// %R
static NSArray *GetSystemDescriptions(OOStringExpansionContext *context);


static NSString *Expand(NSString *string, OOStringExpansionContext *context, NSUInteger sizeLimit, NSUInteger recursionLimit);

static NSString *ExpandKey(OOStringExpansionContext *context, const unichar *characters, NSUInteger size, NSUInteger idx, NSUInteger *replaceLength, NSUInteger sizeLimit, NSUInteger recursionLimit);
static NSString *ExpandDigitKey(OOStringExpansionContext *context, const unichar *characters, NSUInteger keyStart, NSUInteger keyLength, NSUInteger sizeLimit, NSUInteger recursionLimit);
static NSString *ExpandStringKey(OOStringExpansionContext *context, NSString *key, NSUInteger sizeLimit, NSUInteger recursionLimit);
static NSString *ExpandLegacyScriptSelectorKey(OOStringExpansionContext *context, NSString *key);
static NSMapTable *SpecialSubstitutionSelectors(void);
static SEL LookUpLegacySelector(NSString *key);

static NSString *ExpandPercentEscape(OOStringExpansionContext *context, const unichar *characters, NSUInteger size, NSUInteger idx, NSUInteger *replaceLength);
static NSString *ExpandSystemNameEscape(OOStringExpansionContext *context, const unichar *characters, NSUInteger size, NSUInteger idx, NSUInteger *replaceLength);

static void AppendCharacters(NSMutableString **result, const unichar *characters, NSUInteger start, NSUInteger end);

static NSString *NewRandomDigrams(void);
static NSString *OldRandomDigrams(void);


static void SyntaxIssue(OOStringExpansionContext *context, const char *function, const char *fileName, NSUInteger line, NSString *logMessageClass, NSString *prefix, NSString *format, ...)  OO_TAKES_FORMAT_STRING(7, 8);
#define SyntaxError(CONTEXT, CLASS, FORMAT, ...) SyntaxIssue(CONTEXT, OOLOG_FUNCTION_NAME, OOLOG_FILE_NAME, __LINE__, CLASS, OOLOG_WARNING_PREFIX, FORMAT, ## __VA_ARGS__)

#if WARNINGS
#define SyntaxWarning(CONTEXT, CLASS, FORMAT, ...) SyntaxIssue(CONTEXT, OOLOG_FUNCTION_NAME, OOLOG_FILE_NAME, __LINE__, CLASS, OOLOG_WARNING_PREFIX, FORMAT, ## __VA_ARGS__)
#else
#define SyntaxWarning(...) do {} while (0)
#endif


NSString *OOExpandDescriptionString(NSString *string, Random_Seed seed, NSDictionary *overrides, NSDictionary *legacyLocals, NSString *systemName, OOExpandOptions options)
{
	if (string == nil)  return nil;
	
	OOStringExpansionContext context =
	{
		.seed = seed,
		.systemName = [systemName retain],
		.overrides = [overrides retain],
		.legacyLocals = [legacyLocals retain],
		.isJavaScript = options & kOOExpandForJavaScript,
		.convertBackslashN = options & kOOExpandBackslashN,
	};
	
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSString *result = nil;
	@try
	{
		// TODO: profile caching the results. Would need to keep track of whether we've done something nondeterministic (array selection, %R etc).
		result = Expand(string, &context, kStackAllocationLimit, kRecursionLimit);
	}
	@finally
	{
		[context.systemName release];
		[context.overrides release];
		[context.legacyLocals release];
		[context.systemNameWithIan release];
		[context.randomNameN release];
		[context.randomNameR release];
		[context.systemDescriptions release];
	}
	
	result = [result copy];
	[pool release];
	return [result autorelease];
}


NSString *OOExpandKeyWithSeed(NSString *key, Random_Seed seed, NSString *systemName)
{
	if (key == nil)  return nil;
	
	/*	Key variants, including OOGenerateSystemDescription(), get their own
		"driver" for a minor efficiency bonus.
	*/
	OOStringExpansionContext context =
	{
		.seed = seed,
		.systemName = [systemName retain]
	};
	
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSString *result = nil;
	@try
	{
		result = ExpandStringKey(&context, key, kStackAllocationLimit, kRecursionLimit);
	}
	@finally
	{
		[context.systemName release];
		[context.systemNameWithIan release];
		[context.randomNameN release];
		[context.randomNameR release];
		[context.systemDescriptions release];
	}
	
	result = [result copy];
	[pool release];
	return [result autorelease];
}


NSString *OOExpandWithSeed(NSString *text, Random_Seed seed, NSString *name)
{
	return OOExpandDescriptionString(text, seed, nil, nil, name, kOOExpandNoOptions);
}


NSString *OOExpand(NSString *string)
{
	return OOExpandDescriptionString(string, [UNIVERSE systemSeed], nil, nil, nil, kOOExpandNoOptions);
}


NSString *OOExpandKey(NSString *key)
{
	return OOExpandKeyWithSeed(key, [UNIVERSE systemSeed], nil);
}


NSString *OOGenerateSystemDescription(Random_Seed seed, NSString *name)
{
	seed_RNG_only_for_planet_description(seed);
	return OOExpandKeyWithSeed(@"system-description-string", seed, name);
}


OOINLINE bool IsASCIIDigit(unichar c)
{
	return '0' <= c && c <= '9';
}


static NSString *Expand(NSString *string, OOStringExpansionContext *context, NSUInteger sizeLimit, NSUInteger recursionLimit)
{
	NSCParameterAssert(string != nil && context != NULL && sizeLimit <= kStackAllocationLimit);
	
	const NSUInteger size = [string length];
	
	// Avoid stack overflow.
	if (EXPECT_NOT(size > sizeLimit || recursionLimit == 0))  return string;
	sizeLimit -= size;
	recursionLimit--;
	
	// Nothing to expand in an empty string, and the size-1 thing below would be trouble.
	if (size == 0)  return string;
	
	unichar characters[size];
	[string getCharacters:characters range:(NSRange){ 0, size }];
	
	/*	Beginning of current range of non-special characters. If we encounter
		a substitution, we'll be copying from here forward.
	*/
	NSUInteger copyRangeStart = 0;
	
	// Mutable string for result if we perform any substitutions.
	NSMutableString *result = nil;
	
	/*	The iteration limit is size - 1 because every valid substitution is at
		least 2 characters long. This way, characters[idx + 1] is always valid.
	*/
	for (NSUInteger idx = 0; idx < size - 1; idx++)
	{
		/*	Main parsing loop. If, at the end of the loop, replacement != nil,
			we copy the characters from copyRangeStart to idx into the result,
			the insert replacement, and skip replaceLength characters forward
			(minus one, because idx is incremented by the loop.)
		*/
		NSString *replacement = nil;
		NSUInteger replaceLength;
		unichar thisChar = characters[idx];
		
		if (thisChar == '[')
		{
			replacement = ExpandKey(context, characters, size, idx, &replaceLength, sizeLimit, recursionLimit);
		}
		else if (thisChar == '%')
		{
			replacement = ExpandPercentEscape(context, characters, size, idx, &replaceLength);
		}
		else if (thisChar == ']')
		{
			SyntaxWarning(context, @"strings.expand.warning.unbalancedClosingBracket", @"Unbalanced ] in string.");
		}
		else if (thisChar == '\\' && context->convertBackslashN)
		{
			if (characters[idx + 1] == 'n')
			{
				replaceLength = 2;
				replacement = @"\n";
			}
		}
		else
		{
			// No token start character, so we definitely have no replacement.
			continue;
		}
		
		if (replacement != nil)
		{
			/*	If replacement string is "\x7F", eat the following character.
				This is used in system_description for the one empty string
				in [22].
			*/
			if ([replacement isEqualToString:@"\x7F"] && replaceLength < size)
			{
				replaceLength++;
				replacement = @"";
			}
			
			// Avoid copying if we're replacing the entire input string.
			if (copyRangeStart == 0 && replaceLength == size)
			{
				return replacement;
			}
			
			// Write the pending literal segment to result. This also allocates result if needed.
			AppendCharacters(&result, characters, copyRangeStart, idx);
			
			[result appendString:replacement];
			
			// Skip over replaced part and start a new literal segment.
			idx += replaceLength - 1;
			copyRangeStart = idx + 1;
		}
	}
	
	if (result != nil)
	{
		// Append any trailing literal segment.
		AppendCharacters(&result, characters, copyRangeStart, size);
		
		// Don't turn result immutable; doing it once at top level is sufficient.
		return result;
	}
	else
	{
		// No substitutions, return original string.
		return string;
	}
}


static NSString *ExpandKey(OOStringExpansionContext *context, const unichar *characters, NSUInteger size, NSUInteger idx, NSUInteger *replaceLength, NSUInteger sizeLimit, NSUInteger recursionLimit)
{
	NSCParameterAssert(context != NULL && characters != NULL && replaceLength != NULL);
	NSCParameterAssert(characters[idx] == '[');
	
	// Find the balancing close bracket.
	NSUInteger end, balanceCount = 1;
	bool allDigits = true;
	
	for (end = idx + 1; end < size && balanceCount > 0; end++)
	{
		if (characters[end] == ']')  balanceCount--;
		else
		{
			if (!IsASCIIDigit(characters[end]))  allDigits = false;
			if (characters[end] == '[')  balanceCount++;
		}
	}
	
	// Fail if no balancing bracket.
	if (EXPECT_NOT(balanceCount != 0))
	{
		SyntaxWarning(context, @"strings.expand.warning.unbalancedOpeningBracket", @"Unbalanced [ in string.");
		return nil;
	}
	
	*replaceLength = end - idx;
	NSUInteger keyStart = idx + 1, keyLength = *replaceLength - 2;
	
	if (EXPECT_NOT(keyLength == 0))
	{
		SyntaxWarning(context, @"strings.expand.warning.emptyKey", @"Invalid expansion code [] string. (To avoid this message, use %%[%%].)");
		return nil;
	}
	
	if (allDigits)
	{
		return ExpandDigitKey(context, characters, keyStart, keyLength, sizeLimit, recursionLimit);
	}
	else
	{
		NSString *key = [NSString stringWithCharacters:characters + keyStart length:keyLength];
		return ExpandStringKey(context, key, sizeLimit, recursionLimit);
	}
}


// Expand a numeric key of the form [N] to a string from the system_description array in description.plist.
static NSString *ExpandDigitKey(OOStringExpansionContext *context, const unichar *characters, NSUInteger keyStart, NSUInteger keyLength, NSUInteger sizeLimit, NSUInteger recursionLimit)
{
	NSCParameterAssert(context != NULL && characters != NULL);
	
	NSUInteger keyValue = 0, idx;
	for (idx = keyStart; idx < (keyStart + keyLength); idx++)
	{
		NSCAssert2(IsASCIIDigit(characters[idx]), @"%s called with non-numeric key [%@].", __FUNCTION__, [NSString stringWithCharacters:characters + keyStart length:keyLength]);
		
		keyValue = keyValue * 10 + characters[idx] - '0';
	}
	
	// Retrieve selected system_description entry.
	NSArray *sysDescs = GetSystemDescriptions(context);
	NSArray *entry = [sysDescs oo_arrayAtIndex:keyValue];
	
	if (EXPECT_NOT(entry == nil))
	{
		if (keyValue >= context->sysDescCount)
		{
			SyntaxWarning(context, @"strings.expand.warning.outOfRangeKey", @"Out-of-range system description expansion key [%@] in string.", [NSString stringWithCharacters:characters + keyStart length:keyLength]);
		}
		else
		{
			// This is out of the scope of whatever triggered it, so shouldn't be a JS warning.
			OOLogERR(@"strings.expand.invalidData", @"descriptions.plist entry system_description must be an array of arrays of strings.");
		}
		return nil;
	}
	
	// Select a random sub-entry.
	NSUInteger selection, count = [entry count];
	NSUInteger rnd = gen_rnd_number();
	if (count == 5)
	{
		// Time-honoured Elite-compatible way for five items.
		if (rnd >= 0xCC)  selection = 4;
		else if (rnd >= 0x99)  selection = 3;
		else if (rnd >= 0x66)  selection = 2;
		else if (rnd >= 0x33)  selection = 1;
		else  selection = 0;
	}
	else
	{
		// General way.
		selection = (rnd * count) / 256;
	}
	
	// Look up and recursively expand string.
	NSString *string = [entry oo_stringAtIndex:selection];
	return Expand(string, context, sizeLimit, recursionLimit);
}


static NSString *ExpandStringKey(OOStringExpansionContext *context, NSString *key, NSUInteger sizeLimit, NSUInteger recursionLimit)
{
	NSCParameterAssert(context != NULL && key != nil);
	
	// Overrides have top priority.
	id value = [context->overrides objectForKey:key];
	if (value != nil)
	{
#if WARNINGS
		if (![value isKindOfClass:[NSString class]] && ![value isKindOfClass:[NSNumber class]])
		{
			SyntaxWarning(context, @"strings.expand.warning.invalidOverride", @"String expansion override value %@ for [%@] is not a string or number.", [value shortDescription], key);
		}
#endif
		return [value description];
	}
	
	// Specials override descriptions.plist.
	NSMapTable *specials = SpecialSubstitutionSelectors();
	SEL selector = NSMapGet(specials, key);
	if (selector != NULL)
	{
		value = [PLAYER performSelector:selector];
		if (value != nil)
		{
			NSCAssert2([value isKindOfClass:[NSString class]], @"Special string expansion [%@] expanded to %@, but expected a string.", key, [value shortDescription]);
			return value;
		}
	}
	
	// Now try descriptions.plist.
	value = [[UNIVERSE descriptions] objectForKey:key];
	if (value != nil)
	{
		if ([value isKindOfClass:[NSArray class]] && [value count] > 0)
		{
			NSUInteger rnd = gen_rnd_number() % [value count];
			value = [value oo_objectAtIndex:rnd];
		}
		
		if (![value isKindOfClass:[NSString class]])
		{
			// This is out of the scope of whatever triggered it, so shouldn't be a JS warning.
			OOLogERR(@"strings.expand.invalidData", @"String expansion value %@ for [%@] from descriptions.plist is not a string or number.", [value shortDescription], key);
			return nil;
		}
		
		// Expand recursively.
		return Expand(value, context, sizeLimit, recursionLimit);
	}
	
	// Try mission variables.
	if ([key hasPrefix:@"mission_"])
	{
		value = [PLAYER missionVariableForKey:key];
		if (value != nil)
		{
			return value;
		}
	}
	
	// Try legacy local variables.
	value = [context->legacyLocals objectForKey:key];
	if (value != nil)
	{
		return [value description];
	}
	
	// Try legacy script methods.
	value = ExpandLegacyScriptSelectorKey(context, key);
#if WARNINGS
	if (value == nil)
	{
		if ([key hasSuffix:@"_string"] || [key hasSuffix:@"_number"] || [key hasSuffix:@"_bool"])
		{
			// If it looks like a legacy script selector, assume it is.
			SyntaxError(context, @"strings.expand.invalidSelector", @"Unpermitted legacy script method [%@] in string.", key);
		}
		else
		{
			SyntaxWarning(context, @"strings.expand.warning.unknownExpansion", @"Unknown expansion key [%@] in string.", key);
		}
	}
#endif
	return value;
}


static NSString *ExpandLegacyScriptSelectorKey(OOStringExpansionContext *context, NSString *key)
{
	NSCParameterAssert(context != NULL && key != nil);
	
	// Treat expansion key as a legacy script selector, with whitelisting and aliasing.
	SEL selector = LookUpLegacySelector(key);
	
	if (selector != NULL)
	{
		return [[PLAYER performSelector:selector] description];
	}
	else
	{
		return nil;
	}
}


static NSMapTable *SpecialSubstitutionSelectors(void)
{
	/*
		Special substitution selectors:
		These substitution keys map to methods on the player entity. They
		have higher precedence than descriptions.plist entries, but lower
		than explicit overrides.
	*/
	
	static NSMapTable *specials = NULL;
	if (specials != NULL)  return specials;
	
	struct { NSString *key; SEL selector; } selectors[] =
	{
		{ @"commander_name", @selector(commanderName_string) },
		{ @"commander_shipname", @selector(commanderShip_string) },
		{ @"commander_shipdisplayname", @selector(commanderShipDisplayName_string) },
		{ @"commander_rank", @selector(commanderRank_string) },
		{ @"commander_legal_status", @selector(commanderLegalStatus_string) },
		{ @"commander_bounty", @selector(commanderBountyAsString) },
		{ @"credits_number", @selector(creditsFormattedForSubstitution) },
		{ @"_oo_legacy_credits_number", @selector(creditsFormattedForLegacySubstitution) }
	};
	unsigned i, count = sizeof selectors / sizeof *selectors;
	
	specials = NSCreateMapTable(NSObjectMapKeyCallBacks, NSNonOwnedPointerMapValueCallBacks, count);
	for (i = 0; i < count; i++)
	{
		NSMapInsertKnownAbsent(specials, selectors[i].key, selectors[i].selector);
	}
	
	return specials;
}


static SEL LookUpLegacySelector(NSString *key)
{
	SEL selector = NULL;
	static NSMapTable *selectorCache = NULL;
	
	// Try cache lookup.
	if (selectorCache != NULL)
	{
		selector = NSMapGet(selectorCache, key);
	}
	
	if (selector == NULL)
	{
		static NSDictionary *aliases = nil;
		static NSSet *whitelist = nil;
		if (whitelist == nil)
		{
			NSDictionary *whitelistDict = [ResourceManager whitelistDictionary];
			whitelist = [[NSSet alloc] initWithArray:[whitelistDict oo_arrayForKey:@"query_methods"]];
			aliases = [[whitelistDict oo_dictionaryForKey:@"query_method_aliases"] copy];
		}
		
		NSString *selectorName = [aliases oo_stringForKey:key];
		if (selectorName == nil)  selectorName = key;
		
		if ([whitelist containsObject:selectorName])
		{
			selector = NSSelectorFromString(selectorName);
			
			/*	This is an assertion, not a warning, because whitelist.plist is
				part of the game and cannot be overriden by OXPs. If there is an
				invalid selector in the whitelist, it's a game bug.
			*/
			NSCAssert1([PLAYER respondsToSelector:selector], @"Player does not respond to whitelisted query selector %@.", key);
		}
		
		if (selector != NULL)
		{
			// Add it to cache.
			if (selectorCache == NULL)
			{
				selectorCache = NSCreateMapTable(NSObjectMapKeyCallBacks, NSNonOwnedPointerMapValueCallBacks, [whitelist count]);
			}
			NSMapInsertKnownAbsent(selectorCache, key, selector);
		}
	}
	
	return selector;
}


static NSString *ExpandPercentEscape(OOStringExpansionContext *context, const unichar *characters, NSUInteger size, NSUInteger idx, NSUInteger *replaceLength)
{
	NSCParameterAssert(context != NULL && characters != NULL && replaceLength != NULL);
	NSCParameterAssert(characters[idx] == '%');
	
	// All %-escapes except %J are 2 characters.
	*replaceLength = 2;
	unichar selector = characters[idx + 1];
	
	switch (selector)
	{
		case 'H':
			return GetSystemName(context);
			
		case 'I':
			return GetSystemNameIan(context);
			
		case 'N':
			return GetRandomNameN(context);
			
		case 'R':
			return GetRandomNameR(context);
			
		case 'J':
			return ExpandSystemNameEscape(context, characters, size, idx, replaceLength);
			
		case '%':
			return @"%";
			
		case '[':
			return @"[";
			
		case ']':
			return @"]";
			
			/*	These are NSString formatting specifiers that occur in
				descriptions.plist. The '.' is for floating-point (g and f)
				specifiers that have field widths specified. No unadorned
				%f or %g is found in vanilla Oolite descriptions.plist.
				
				Ideally, these would be replaced with the caller formatting
				the value and passing it as an override - it would be safer
				and make descriptions.plist clearer - but it would be a big
				job and uglify the callers.
				-- Ahruman 2012-10-05
			*/
		case '@':
		case 'd':
		case '.':
			return nil;
			
		default:
			// Yay, percent signs!
			SyntaxWarning(context, @"strings.expand.warning.unknownPercentEscape", @"Unknown escape code in string: %%%lc. (To encode a %% sign without this warning, use %%%% - but prefer \"percent\" in prose writing.)", selector);
			
			return nil;
	}
}


// %J###
static NSString *ExpandSystemNameEscape(OOStringExpansionContext *context, const unichar *characters, NSUInteger size, NSUInteger idx, NSUInteger *replaceLength)
{
	NSCParameterAssert(context != NULL && characters != NULL && replaceLength != NULL);
	NSCParameterAssert(characters[idx + 1] == 'J');
	
	// A valid %J escape is always five characters including the three digits.
	*replaceLength = 5;
	
	#define kInvalidJEscapeMessage @"String escape code %%J must be followed by three integers."
	if (EXPECT_NOT(size - idx < 5))
	{
		// Too close to end of string to actually have three characters, let alone three digits.
		SyntaxError(context, @"strings.expand.invalidJEscape", kInvalidJEscapeMessage);
		return nil;
	}
	
	char hundreds = characters[idx + 2];
	char tens = characters[idx + 3];
	char units = characters[idx + 4];
	
	if (!(IsASCIIDigit(hundreds) && IsASCIIDigit(tens) && IsASCIIDigit(units)))
	{
		SyntaxError(context, @"strings.expand.invalidJEscape", kInvalidJEscapeMessage);
		return nil;
	}
	
	OOSystemID sysID = (hundreds - '0') * 100 + (tens - '0') * 10 + (units - '0');
	if (sysID > kOOMaximumSystemID)
	{
		SyntaxError(context, @"strings.expand.invalidJEscape.range", @"String escape code %%J%3u is out of range (must be less than %u).", sysID, kOOMaximumSystemID + 1);
		return nil;
	}
	
	return [UNIVERSE getSystemName:[UNIVERSE systemSeedForSystemNumber:sysID]];
}


static void AppendCharacters(NSMutableString **result, const unichar *characters, NSUInteger start, NSUInteger end)
{
	NSCParameterAssert(result != NULL && characters != NULL && start <= end);
	
	if (*result == nil)
	{
		// Ensure there is a string. We want this even if the range is empty.
		*result = [NSMutableString string];
	}
	
	if (start == end)  return;
	
	/*	What we want here is a method like -[NSMutableString
		appendCharacters:(unichar)characters length:(NSUInteger)length], which
		unfortunately doesn't exist. On Mac OS X, CoreFoundation provides an
		equivalent. For GNUstep, we have to use a temporary string.
		
		TODO: build the output string in a fixed-size stack buffer instead.
	*/
#if OOLITE_MAC_OS_X
	CFStringAppendCharacters((CFMutableStringRef)*result, characters + start, end - start);
#else
	NSString *temp = [[NSString alloc] initWithCharacters:characters + start length:end - start];
	[*result appendString:temp];
	[temp release];
#endif
}


static NSString *GetSystemName(OOStringExpansionContext *context)
{
	NSCParameterAssert(context != NULL);
	
	if (context->systemName == nil)
	{
		context->systemName = [[UNIVERSE getSystemName:context->seed] retain];
	}
	
	return context->systemName;
}


static NSString *GetSystemNameIan(OOStringExpansionContext *context)
{
	NSCParameterAssert(context != NULL);
	
	if (context->systemNameWithIan == nil)
	{
		context->systemNameWithIan = [[GetSystemName(context) stringByAppendingString:DESC(@"planetname-derivative-suffix")] retain];
	}
	
	return context->systemNameWithIan;
}


static NSString *GetRandomNameN(OOStringExpansionContext *context)
{
	NSCParameterAssert(context != NULL);
	
	if (context->randomNameN == nil)
	{
		context->randomNameN = [NewRandomDigrams() retain];
	}
	
	return context->randomNameN;
}


static NSString *GetRandomNameR(OOStringExpansionContext *context)
{
	NSCParameterAssert(context != NULL);
	
	if (context->randomNameR == nil)
	{
		context->randomNameR = [OldRandomDigrams() retain];
	}
	
	return context->randomNameR;
}


static NSArray *GetSystemDescriptions(OOStringExpansionContext *context)
{
	NSCParameterAssert(context != NULL);
	
	if (context->systemDescriptions == nil)
	{
		context->systemDescriptions = [[[UNIVERSE descriptions] oo_arrayForKey:@"system_description"] retain];
		context->sysDescCount = [context->systemDescriptions count];
	}
	
	return context->systemDescriptions;
}


/*	Generates pseudo-random digram string using gen_rnd_number()
	(world-generation consistent PRNG), but misses some possibilities. Used
	for "%R" description string for backwards compatibility.
*/
static NSString *OldRandomDigrams(void)
{
	unsigned len = gen_rnd_number() & 3;
	NSString *digrams = [[UNIVERSE descriptions] objectForKey:@"digrams"];
	NSMutableString *name = [NSMutableString stringWithCapacity:256];
	
	for (unsigned i = 0; i <=len; i++)
	{
		unsigned x =  gen_rnd_number() & 0x3e;
		[name appendString:[digrams substringWithRange:NSMakeRange(x, 2)]];
	}
	
	return [name capitalizedString]; 
}


/*	Generates pseudo-random digram string using gen_rnd_number()
	(world-generation consistent PRNG). Used for "%N" description string.
*/
static NSString *NewRandomDigrams(void)
{
	unsigned length = (gen_rnd_number() % 4) + 1;
	if ((gen_rnd_number() % 5) < ((length == 1) ? 3 : 1))  ++length;	// Make two-letter names rarer and 10-letter names happen sometimes
	NSString *digrams = [[UNIVERSE descriptions] objectForKey:@"digrams"];
	unsigned count = [digrams length] / 2;
	NSMutableString *name = [NSMutableString stringWithCapacity:length * 2];
	
	for (unsigned i = 0; i != length; ++i)
	{
		[name appendString:[digrams substringWithRange:NSMakeRange((gen_rnd_number() % count) * 2, 2)]];
	}
	
	return [name capitalizedString];
}


// Similar to %N format code, but uses Ranrot() (the "really random" PRNG).
NSString *OORandomDigrams(void)
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


static void SyntaxIssue(OOStringExpansionContext *context, const char *function, const char *fileName, NSUInteger line, NSString *logMessageClass, NSString *prefix, NSString *format, ...)
{
	NSCParameterAssert(context != NULL);
	
	va_list args;
	va_start(args, format);
	
	if (OOLogWillDisplayMessagesInClass(logMessageClass))
	{
		if (context->isJavaScript)
		{
			/*	NOTE: syntax errors are reported as warnings when called from JS
				because we don't want to start throwing exceptions when the old
				expander didn't.
			*/
			JSContext *jsc = OOJSAcquireContext();
			OOJSReportWarningWithArguments(jsc, format, args);
			OOJSRelinquishContext(jsc);
		}
		else
		{
			format = [prefix stringByAppendingString:format];
			OOLogWithFunctionFileAndLineAndArguments(logMessageClass, function, fileName, line, format, args);
		}
	}
	
	va_end(args);
}
