/*

OOStringExpander.m


Oolite
Copyright (C) 2004-2013 Giles C Williams and contributors

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
#import "PlayerEntityScriptMethods.h"

// Don't bother with syntax warnings in Deployment builds.
#define WARNINGS			(!defined(NDEBUG))

#define OO_EXPANDER_RANDOM	(context->useGoodRNG ? (Ranrot()&0xFF) : gen_rnd_number())

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
	bool				hasPercentR;		// Set to indicate we need an ExpandPercentR() pass.
	bool				useGoodRNG;
	
	NSString			*systemNameWithIan;	// Cache for %I
	NSString			*randomNameN;		// Cache for %N
	NSString			*randomNameR;		// Cache for %R
	NSArray				*systemDescriptions;// Cache for system_description, used for numbered keys.
	NSUInteger			sysDescCount;		// Count of systemDescriptions, valid after GetSystemDescriptions() called.
} OOStringExpansionContext;


/*	Accessors for lazily-instantiated caches in context.
*/
static NSString *GetSystemName(OOStringExpansionContext *context);		// %H
static NSString *GetSystemNameIan(OOStringExpansionContext *context);	// %I
static NSString *GetRandomNameN(OOStringExpansionContext *context);		// %N
static NSString *GetRandomNameR(OOStringExpansionContext *context);		// %R
static NSArray *GetSystemDescriptions(OOStringExpansionContext *context);

static void AppendCharacters(NSMutableString **result, const unichar *characters, NSUInteger start, NSUInteger end);

static NSString *NewRandomDigrams(OOStringExpansionContext *context);
static NSString *OldRandomDigrams(void);


// Various bits of expansion logic, each with a comment of its very own at the implementation.
static NSString *Expand(OOStringExpansionContext *context, NSString *string, NSUInteger sizeLimit, NSUInteger recursionLimit);

static NSString *ExpandKey(OOStringExpansionContext *context, const unichar *characters, NSUInteger size, NSUInteger idx, NSUInteger *replaceLength, NSUInteger sizeLimit, NSUInteger recursionLimit);
static NSString *ExpandDigitKey(OOStringExpansionContext *context, const unichar *characters, NSUInteger keyStart, NSUInteger keyLength, NSUInteger sizeLimit, NSUInteger recursionLimit);
static NSString *ExpandStringKey(OOStringExpansionContext *context, NSString *key, NSUInteger sizeLimit, NSUInteger recursionLimit);
static NSString *ExpandStringKeyOverride(OOStringExpansionContext *context, NSString *key);
static NSString *ExpandStringKeySpecial(OOStringExpansionContext *context, NSString *key);
static NSString *ExpandStringKeyKeyboardBinding(OOStringExpansionContext *context, NSString *key);
static NSMapTable *SpecialSubstitutionSelectors(void);
static NSString *ExpandStringKeyFromDescriptions(OOStringExpansionContext *context, NSString *key, NSUInteger sizeLimit, NSUInteger recursionLimit);
static NSString *ExpandStringKeyMissionVariable(OOStringExpansionContext *context, NSString *key);
static NSString *ExpandStringKeyLegacyLocalVariable(OOStringExpansionContext *context, NSString *key);
static NSString *ExpandLegacyScriptSelectorKey(OOStringExpansionContext *context, NSString *key);
static SEL LookUpLegacySelector(NSString *key);

static NSString *ExpandPercentEscape(OOStringExpansionContext *context, const unichar *characters, NSUInteger size, NSUInteger idx, NSUInteger *replaceLength);
static NSString *ExpandSystemNameEscape(OOStringExpansionContext *context, const unichar *characters, NSUInteger size, NSUInteger idx, NSUInteger *replaceLength);
static NSString *ExpandPercentR(OOStringExpansionContext *context, NSString *input);
#if WARNINGS
static void ReportWarningForUnknownKey(OOStringExpansionContext *context, NSString *key);
#endif


/*	SyntaxWarning(context, logMessageClass, format, ...)
 	SyntaxError(context, logMessageClass, format, ...)
	
	Report warning or error for expansion syntax, including unknown keys.
	
	Warnings are reported as JS warnings or log messages (depending on the
	context->isJavaScript flag) if the relevant log message class is enabled.
	Warnings are completely disabled in Deployment builds.
	
	Errors are reported as JS warnings (not exceptions) or log messages (again
	depending on context->isJavaScript) in all configurations. Exceptions are
	not used to avoid breaking code that worked with the old expander, even if
	it was questionable.
	
	Errors that are not syntax or invalid keys are reported with OOLogERR().
*/
static void SyntaxIssue(OOStringExpansionContext *context, const char *function, const char *fileName, NSUInteger line, NSString *logMessageClass, NSString *prefix, NSString *format, ...)  OO_TAKES_FORMAT_STRING(7, 8);
#define SyntaxError(CONTEXT, CLASS, FORMAT, ...) SyntaxIssue(CONTEXT, OOLOG_FUNCTION_NAME, OOLOG_FILE_NAME, __LINE__, CLASS, OOLOG_WARNING_PREFIX, FORMAT, ## __VA_ARGS__)

#if WARNINGS
#define SyntaxWarning(CONTEXT, CLASS, FORMAT, ...) SyntaxIssue(CONTEXT, OOLOG_FUNCTION_NAME, OOLOG_FILE_NAME, __LINE__, CLASS, OOLOG_WARNING_PREFIX, FORMAT, ## __VA_ARGS__)
#else
#define SyntaxWarning(...) do {} while (0)
#endif


// MARK: -
// MARK: Public functions

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
		.useGoodRNG = options & kOOExpandGoodRNG,
	};
	
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSString *result = nil, *intermediate = nil;
	@try
	{
		// TODO: profile caching the results. Would need to keep track of whether we've done something nondeterministic (array selection, %R etc).
		intermediate = Expand(&context, string, kStackAllocationLimit, kRecursionLimit);
		if (!context.hasPercentR)
		{
			result = intermediate;
		}
		else
		{
			result = ExpandPercentR(&context, intermediate);
		}
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
	NSString *result = nil, *intermediate = nil;
	@try
	{
		intermediate = ExpandStringKey(&context, key, kStackAllocationLimit, kRecursionLimit);
		result = ExpandPercentR(&context, intermediate);
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


NSString *OOExpandKeyRandomized(NSString *key)
{
	OORandomState savedRandomState = OOSaveRandomState();
	OOSetReallyRandomRANROTAndRndSeeds();
	
	// N.b.: the systemSeed is used only to retrieve the system name, not for actual randomness.
	NSString *result = OOExpandKeyWithSeed(key, [UNIVERSE systemSeed], nil);
	
	OORestoreRandomState(savedRandomState);
	
	return result;
}


NSString *OOGenerateSystemDescription(Random_Seed seed, NSString *name)
{
	seed_RNG_only_for_planet_description(seed);
	return OOExpandKeyWithSeed(@"system-description-string", seed, name);
}


// MARK: -
// MARK: Guts


/*	Expand(context, string, sizeLimit, recursionLimit)
	
	Top-level expander. Expands all types of substitution in a string.
	
	<sizeLimit> is the remaining budget for stack allocation of read buffers.
	(Expand() is the only function that creates such buffers.) <recursionLimit>
	limits the number of recursive calls of Expand() that are permitted. If one
	of the limits would be exceeded, Expand() returns the input string unmodified.
*/
static NSString *Expand(OOStringExpansionContext *context, NSString *string, NSUInteger sizeLimit, NSUInteger recursionLimit)
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
		NSUInteger replaceLength = 0;
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


/*	ExpandKey(context, characters, size, idx, replaceLength, sizeLimit, recursionLimit)
	
	Expand a substitution key, i.e. a section surrounded by square brackets.
	On entry, <idx> is the offset to an opening bracket. ExpandKey() searches
	for the balancing closing bracket, and if it is found dispatches to either
	ExpandDigitKey() (for a key consisting only of digits) or ExpandStringKey()
	(for anything else).
*/
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
			if (!isdigit(characters[end]))  allDigits = false;
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


/*	ExpandDigitKey(context, characters, keyStart, keyLength, sizeLimit, recursionLimit
	
	Expand a key (as per ExpandKey()) consisting entirely of digits. <keyStart>
	and <keyLength> specify the range of characters containing the key.
	
	Digit-only keys are looked up in the system_description array in
	descriptions.plist, which is expected to contain only arrays of strings (no
	loose strings). When an array is retrieved, a string is selected from it
	at random and the result is expanded recursively by calling Expand().
*/
static NSString *ExpandDigitKey(OOStringExpansionContext *context, const unichar *characters, NSUInteger keyStart, NSUInteger keyLength, NSUInteger sizeLimit, NSUInteger recursionLimit)
{
	NSCParameterAssert(context != NULL && characters != NULL);
	
	NSUInteger keyValue = 0, idx;
	for (idx = keyStart; idx < (keyStart + keyLength); idx++)
	{
		NSCAssert2(isdigit(characters[idx]), @"%s called with non-numeric key [%@].", __FUNCTION__, [NSString stringWithCharacters:characters + keyStart length:keyLength]);
		
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
	NSUInteger rnd = OO_EXPANDER_RANDOM;
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
	return Expand(context, string, sizeLimit, recursionLimit);
}


/*	ExpandStringKey(context, key, sizeLimit, recursionLimit)
	
	Expand a key (as per ExpandKey()) which doesn't consist entirely of digits.
	Looks for the key in a number of different places in prioritized order.
*/
static NSString *ExpandStringKey(OOStringExpansionContext *context, NSString *key, NSUInteger sizeLimit, NSUInteger recursionLimit)
{
	NSCParameterAssert(context != NULL && key != nil);
	
	// Overrides have top priority.
	NSString *result = ExpandStringKeyOverride(context, key);
	
	// Specials override descriptions.plist.
	if (result == nil)  result = ExpandStringKeySpecial(context, key);

	// Now try descriptions.plist.
	if (result == nil)  result = ExpandStringKeyFromDescriptions(context, key, sizeLimit, recursionLimit);

	// For efficiency, descriptions.plist overrides keybindings.
	// OXPers should therefore avoid oolite_key_ description keys
	if (result == nil)  result = ExpandStringKeyKeyboardBinding(context, key);
	
	// Try mission variables.
	if (result == nil)  result = ExpandStringKeyMissionVariable(context, key);
	
	// Try legacy local variables.
	if (result == nil)  result = ExpandStringKeyLegacyLocalVariable(context, key);
	
	// Try legacy script methods.
	if (result == nil)  ExpandLegacyScriptSelectorKey(context, key);
	
#if WARNINGS
	// None of that worked, so moan a bit.
	if (result == nil)  ReportWarningForUnknownKey(context, key);
#endif
	
	return result;
}


/*	ExpandStringKeyOverride(context, key)
	
	Attempt to expand a key by retriving it from the overrides dictionary of
	the context (ultimately from OOExpandDescriptionString()). Overrides are
	used to provide context-specific expansions, such as "[self:name]" in
	comms messages, and can also be used from JavaScript.
	
	The main difference between overrides and legacy locals is priority.
*/
static NSString *ExpandStringKeyOverride(OOStringExpansionContext *context, NSString *key)
{
	NSCParameterAssert(context != NULL && key != nil);
	
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
	
	return nil;
}


/*	ExpandStringKeySpecial(context, key)
	
	Attempt to expand a key by matching a set of special expansion codes that
	call PlayerEntity methods but aren't legacy script methods. Also unlike
	legacy script methods, all these methods return strings.
*/
static NSString *ExpandStringKeySpecial(OOStringExpansionContext *context, NSString *key)
{
	NSCParameterAssert(context != NULL && key != nil);
	
	NSMapTable *specials = SpecialSubstitutionSelectors();
	SEL selector = NSMapGet(specials, key);
	if (selector != NULL)
	{
		NSCAssert2([PLAYER respondsToSelector:selector], @"Special string expansion selector %@ for [%@] is not implemented.", NSStringFromSelector(selector), key);
		
		NSString *result = [PLAYER performSelector:selector];
		if (result != nil)
		{
			NSCAssert2([result isKindOfClass:[NSString class]], @"Special string expansion [%@] expanded to %@, but expected a string.", key, [result shortDescription]);
			return result;
		}
	}
	
	return nil;
}


/*	ExpandStringKeyKeyboardBinding(context, key)
	
	Attempt to expand a key by matching it against the keybindings
*/
static NSString *ExpandStringKeyKeyboardBinding(OOStringExpansionContext *context, NSString *key)
{
	NSCParameterAssert(context != NULL && key != nil);
	if ([key hasPrefix:@"oolite_key_"])
	{
		NSString *binding = [key substringFromIndex:7];
		return [PLAYER keyBindingDescription:binding];
	}
	return nil;
}


/*	SpecialSubstitutionSelectors()
	
	Retrieve the mapping of special keys for ExpandStringKeySpecial() to
	selectors.
*/
static NSMapTable *SpecialSubstitutionSelectors(void)
{
	static NSMapTable *specials = NULL;
	if (specials != NULL)  return specials;
	
	struct { NSString *key; SEL selector; } selectors[] =
	{
		{ @"commander_name", @selector(commanderName_string) },
		{ @"commander_shipname", @selector(commanderShip_string) },
		{ @"commander_shipdisplayname", @selector(commanderShipDisplayName_string) },
		{ @"commander_rank", @selector(commanderRank_string) },
		{ @"commander_kills", @selector(commanderKillsAsString) },
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


/*	ExpandStringKeyFromDescriptions(context, key, sizeLimit, recursionLimit)
	
	Attempt to expand a key by looking it up in descriptions.plist. Matches
	may be single strings or arrays of strings. For arrays, one of the strings
	is selected at random.
	
	Matched strings are expanded recursively by calling Expand().
*/
static NSString *ExpandStringKeyFromDescriptions(OOStringExpansionContext *context, NSString *key, NSUInteger sizeLimit, NSUInteger recursionLimit)
{
	id value = [[UNIVERSE descriptions] objectForKey:key];
	if (value != nil)
	{
		if ([value isKindOfClass:[NSArray class]] && [value count] > 0)
		{
			NSUInteger rnd = OO_EXPANDER_RANDOM % [value count];
			value = [value oo_objectAtIndex:rnd];
		}
		
		if (![value isKindOfClass:[NSString class]])
		{
			// This is out of the scope of whatever triggered it, so shouldn't be a JS warning.
			OOLogERR(@"strings.expand.invalidData", @"String expansion value %@ for [%@] from descriptions.plist is not a string or number.", [value shortDescription], key);
			return nil;
		}
		
		// Expand recursively.
		return Expand(context, value, sizeLimit, recursionLimit);
	}
	
	return nil;
}


/*	ExpandStringKeyMissionVariable(context, key)
	
	Attempt to expand a key by matching it to a mission variable.
*/
static NSString *ExpandStringKeyMissionVariable(OOStringExpansionContext *context, NSString *key)
{
	if ([key hasPrefix:@"mission_"])
	{
		return [PLAYER missionVariableForKey:key];
	}
	
	return nil;
}


/*	ExpandStringKeyMissionVariable(context, key)
	
	Attempt to expand a key by matching it to a legacy local variable.
	
	The main difference between overrides and legacy locals is priority.
*/
static NSString *ExpandStringKeyLegacyLocalVariable(OOStringExpansionContext *context, NSString *key)
{
	return [[context->legacyLocals objectForKey:key] description];
}


/*	ExpandLegacyScriptSelectorKey(context, key)
	
	Attempt to expand a key by treating it as a legacy script query method and
	invoking it. Only whitelisted methods are permitted, and aliases are
	respected.
*/
static NSString *ExpandLegacyScriptSelectorKey(OOStringExpansionContext *context, NSString *key)
{
	NSCParameterAssert(context != NULL && key != nil);
	
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


/*	LookUpLegacySelector(key)
	
	If <key> is a whitelisted legacy script query method, or aliases to one,
	return the corresponding selector.
*/
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


#if WARNINGS
/*	ReportWarningForUnknownKey(context, key)
	
	Called when we fall through all the various ways of expanding string keys
	above. If the key looks like a legacy script query method, assume it is
	and report a bad selector. Otherwise, report it as an unknown key.
*/
static void ReportWarningForUnknownKey(OOStringExpansionContext *context, NSString *key)
{
	if ([key hasSuffix:@"_string"] || [key hasSuffix:@"_number"] || [key hasSuffix:@"_bool"])
	{
		SyntaxError(context, @"strings.expand.invalidSelector", @"Unpermitted legacy script method [%@] in string.", key);
	}
	else
	{
		SyntaxWarning(context, @"strings.expand.warning.unknownExpansion", @"Unknown expansion key [%@] in string.", key);
	}
}
#endif


/*	ExpandKey(context, characters, size, idx, replaceLength)
	
	Expand an escape code. <idx> is the index of the % sign introducing the
	escape code. Supported escape codes are:
		%H
		%I
		%N
		%R
		%J###, where ### are three digits
		%%
		%[
		%]
	
	In addition, the codes %@, %d and %. are ignored, because they're used
	with -[NSString stringWithFormat:] on strings that have already been
	expanded.
	
	Any other code results in a warning.
*/
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
			// to keep planet description generation consistent with earlier versions
			// this must be done after all other substitutions in a second pass.
			context->hasPercentR = true;
			return @"%R";
			
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
				job and uglify the callers without newfangled Objective-C
				dictionary literals.
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


/* ExpandPercentR(context, string) 
	 Replaces all %R in string with its expansion.
	 Separate to allow this to be delayed to the end of the string expansion
	 for compatibility with 1.76 expansion of %R in planet descriptions
*/
static NSString *ExpandPercentR(OOStringExpansionContext *context, NSString *input)
{
	NSRange containsR = [input rangeOfString:@"%R"];
	if (containsR.location == NSNotFound)
	{
		return input; // no %Rs to replace
	}
	NSString *percentR = GetRandomNameR(context);
	NSMutableString *output = [NSMutableString stringWithString:input];

	/* This loop should be completely unnecessary, but for some reason
	 * replaceOccurrencesOfString sometimes only replaces the first
	 * instance of %R if percentR contains the non-ASCII
	 * digrams-apostrophe character.  (I guess
	 * http://lists.gnu.org/archive/html/gnustep-dev/2011-10/msg00048.html
	 * this bug in GNUstep's implementation here, which is in 1.22) So
	 * to cover that case, if there are still %R in the string after
	 * replacement, try again. Affects things like thargoid curses, and
	 * particularly %Rful expansions of [nom]. Probably this can be
	 * tidied up once GNUstep 1.22 is ancient history, but that'll be a
	 * few years yet. - CIM 15/1/2013 */

	do {
		[output replaceOccurrencesOfString:@"%R" withString:percentR options:NSLiteralSearch range:NSMakeRange(0, [output length])];
	} while([output rangeOfString:@"%R"].location != NSNotFound);

	return [NSString stringWithString:output];
}


/*	ExpandSystemNameEscape(context, characters, size, idx, replaceLength)
	
	Expand a %J### code by looking up the corresponding system name in the
	current galaxy.
*/
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
	
	if (!(isdigit(hundreds) && isdigit(tens) && isdigit(units)))
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
		context->randomNameN = [NewRandomDigrams(context) retain];
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
	/* The only point of using %R is for world generation, so there's
	 * no point in checking the context */
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


/*	Generates pseudo-random digram string. Used for "%N" description string.
*/
static NSString *NewRandomDigrams(OOStringExpansionContext *context)
{
	unsigned length = (OO_EXPANDER_RANDOM % 4) + 1;
	if ((OO_EXPANDER_RANDOM % 5) < ((length == 1) ? 3 : 1))  ++length;	// Make two-letter names rarer and 10-letter names happen sometimes
	NSString *digrams = [[UNIVERSE descriptions] objectForKey:@"digrams"];
	NSUInteger count = [digrams length] / 2;
	NSMutableString *name = [NSMutableString stringWithCapacity:length * 2];
	
	for (unsigned i = 0; i != length; ++i)
	{
		[name appendString:[digrams substringWithRange:NSMakeRange((OO_EXPANDER_RANDOM % count) * 2, 2)]];
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
