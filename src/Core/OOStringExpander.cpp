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

#include "OOCocoa.h"
#include "OOStringExpander.h"
#include "Universe.h"
#include "OOJavaScriptEngine.h"
#include "OOStringParsing.h"
#include "ResourceManager.h"
#include "PlayerEntityScriptMethods.h"
#include "PlayerEntity.h"
#include "OOCallByName.h"

#include <map>
#include <optional>
#include <set>
#include <string>
#include <string_view>

#include "oofnd/StdLib.hpp"
#include "oofnd/objc/OOAssert.h"
#include "oofnd/objc/OOException.h"
#include "oofnd/String.hpp"
#include "oofnd/PrintfFormat.h"

/*	The expansion engine works on UTF-16 code units, as it did on the Objective-C string's
	characters, held in std::u16string; an empty optional stands for nil (bead oo-3rb.61, proposed
	ADR-0034 decision 4). Text enters and leaves as UTF-8 (WTF-8, lossless: oo::utf8ToUtf16 /
	oo::utf16ToUtf8). The unmigrated callees (Universe, PlayerEntity, ResourceManager) and the log
	and JavaScript reports are converted at the call (bead oo-3il6).
*/
typedef std::u16string OOUnits;
typedef std::optional<std::u16string> OOMaybeUnits;

namespace {

OOUnits UnitsWithCharacters(const char16_t *characters, NSUInteger length);
NSUInteger FindUnits(const OOUnits &string, std::u16string_view target, NSUInteger from);
bool HasPrefix(const OOUnits &string, std::u16string_view prefix);
bool HasSuffix(const OOUnits &string, std::u16string_view suffix);

}	// namespace

// Don't bother with syntax warnings in Deployment builds.
#define WARNINGS			OOLITE_DEBUG

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
namespace {

struct OOStringExpansionContext
{
	Random_Seed			seed;
	OOMaybeUnits		systemName;
	oo::PList			overrides;			// a dictionary of mixed values; null: none (was nil)
	oo::PList			legacyLocals;		// a dictionary of mixed values; null: none (was nil)
	bool				isJavaScript;
	bool				convertBackslashN;
	bool				hasPercentR = false;		// Set to indicate we need an ExpandPercentR() pass.
	bool				useGoodRNG;
	bool				disallowPercentI = false;

	OOMaybeUnits		systemNameWithIan{};	// Cache for %I
	OOMaybeUnits		randomNameN{};		// Cache for %N
	OOMaybeUnits		randomNameR{};		// Cache for %R
	oo::PList			systemDescriptions{};	// Cache for system_description (an array), used for numbered keys; null: not loaded.
	NSUInteger			sysDescCount = 0;		// Count of systemDescriptions, valid after GetSystemDescriptions() called.
};

}	// namespace


namespace {

/*	Accessors for lazily-instantiated caches in context.
*/
OOMaybeUnits GetSystemName(OOStringExpansionContext *context);		// %H
OOMaybeUnits GetSystemNameIan(OOStringExpansionContext *context);	// %I
OOMaybeUnits GetRandomNameN(OOStringExpansionContext *context);		// %N
OOMaybeUnits GetRandomNameR(OOStringExpansionContext *context);		// %R
const oo::PList &GetSystemDescriptions(OOStringExpansionContext *context);

void AppendCharacters(OOMaybeUnits *result, const char16_t *characters, NSUInteger start, NSUInteger end);

OOUnits NewRandomDigrams(OOStringExpansionContext *context);
OOUnits OldRandomDigrams(void);


// Various bits of expansion logic, each with a comment of its very own at the implementation.
OOUnits Expand(OOStringExpansionContext *context, const OOUnits &string, NSUInteger sizeLimit, NSUInteger recursionLimit);

OOMaybeUnits ExpandKey(OOStringExpansionContext *context, const char16_t *characters, NSUInteger size, NSUInteger idx, NSUInteger *replaceLength, NSUInteger sizeLimit, NSUInteger recursionLimit);
OOMaybeUnits ExpandDigitKey(OOStringExpansionContext *context, const char16_t *characters, NSUInteger keyStart, NSUInteger keyLength, NSUInteger sizeLimit, NSUInteger recursionLimit);
OOMaybeUnits ExpandStringKey(OOStringExpansionContext *context, const OOUnits &key, NSUInteger sizeLimit, NSUInteger recursionLimit);
OOMaybeUnits ExpandStringKeyOverride(OOStringExpansionContext *context, const std::string &key);
OOMaybeUnits ExpandStringKeySpecial(OOStringExpansionContext *context, const std::string &key);
OOMaybeUnits ExpandStringKeyKeyboardBinding(OOStringExpansionContext *context, const OOUnits &key);
/*	Key -> method name tables, keyed by the key's UTF-8 (string equality). Were map tables with
	object keys and non-owned selector values (bead oo-3rb.20); never iterated. The value is the
	name the method is called by (oo::CallEntityByName): the selector was only ever read back as
	its name (bead oo-xu228).
*/
typedef std::map<std::string, std::string, std::less<>> OOSelectorTable;

const std::string *LookUpSelector(const OOSelectorTable *table, const std::string &key)
{
	if (table == NULL)  return nullptr;
	auto found = table->find(key);
	return (found != table->end()) ? &found->second : nullptr;
}

// A lookup's text, entering the UTF-16 engine (nullopt stays nullopt).
OOMaybeUnits UnitsFromOptional(const std::optional<std::string> &string);

const OOSelectorTable *SpecialSubstitutionSelectors(void);
OOMaybeUnits ExpandStringKeyFromDescriptions(OOStringExpansionContext *context, const std::string &key, NSUInteger sizeLimit, NSUInteger recursionLimit);
OOMaybeUnits ExpandStringKeyMissionVariable(OOStringExpansionContext *context, const OOUnits &key, const std::string &keyString);
OOMaybeUnits ExpandStringKeyLegacyLocalVariable(OOStringExpansionContext *context, const std::string &key);
OOUnits ValueText(const oo::PList &value);
OOMaybeUnits ExpandLegacyScriptSelectorKey(OOStringExpansionContext *context, const std::string &key);
const std::string *LookUpLegacySelector(const std::string &key);

OOMaybeUnits ExpandPercentEscape(OOStringExpansionContext *context, const char16_t *characters, NSUInteger size, NSUInteger idx, NSUInteger *replaceLength);
OOMaybeUnits ExpandSystemNameForGalaxyEscape(OOStringExpansionContext *context, const char16_t *characters, NSUInteger size, NSUInteger idx, NSUInteger *replaceLength);
OOMaybeUnits ExpandSystemNameEscape(OOStringExpansionContext *context, const char16_t *characters, NSUInteger size, NSUInteger idx, NSUInteger *replaceLength);
OOMaybeUnits ExpandPercentR(OOStringExpansionContext *context, const OOMaybeUnits &input);
#if WARNINGS
void ReportWarningForUnknownKey(OOStringExpansionContext *context, const OOUnits &key, const std::string &keyString);
#endif

OOMaybeUnits ApplyOperators(OOMaybeUnits string, const OOUnits &operatorsString);
OOMaybeUnits ApplyOneOperator(const OOMaybeUnits &string, const OOUnits &op, const OOMaybeUnits &param);


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
	
	Errors that are not syntax or invalid keys are reported with OO_LOG_ERR().
*/
void SyntaxIssue(OOStringExpansionContext *context, const char *function, const char *fileName, NSUInteger line, const char *logMessageClass, const char *prefix, const char *format, ...)  OO_PRINTF_FORMAT(7, 8);
void ReportJavaScriptWarning(ooscript::Context jsc, const char *format, ...)  __attribute__((format(printf, 2, 3)));
}	// namespace

// OOLOG_WARNING_PREFIX's text, as a C string.
#define kSyntaxIssuePrefix "----- WARNING: "

#define SyntaxError(CONTEXT, CLASS, FORMAT, ...) SyntaxIssue(CONTEXT, OOLOG_FUNCTION_NAME, OOLOG_FILE_NAME, __LINE__, CLASS, kSyntaxIssuePrefix, FORMAT, ## __VA_ARGS__)

#if WARNINGS
#define SyntaxWarning(CONTEXT, CLASS, FORMAT, ...) SyntaxIssue(CONTEXT, OOLOG_FUNCTION_NAME, OOLOG_FILE_NAME, __LINE__, CLASS, kSyntaxIssuePrefix, FORMAT, ## __VA_ARGS__)
#else
#define SyntaxWarning(...) do {} while (0)
#endif


// MARK: -
// MARK: Public functions

std::optional<std::string> cxx_OOExpandDescriptionString(Random_Seed seed, const std::string &string, const oo::PList &overrides, const oo::PList &legacyLocals, const std::optional<std::string> &systemName, OOExpandOptions options)
{
	OOStringExpansionContext context =
	{
		.seed = seed,
		.systemName = systemName.has_value() ? OOMaybeUnits(oo::utf8ToUtf16(*systemName)) : std::nullopt,
		.overrides = overrides,
		.legacyLocals = legacyLocals,
		.isJavaScript = (bool)(options & kOOExpandForJavaScript),
		.convertBackslashN = (bool)(options & kOOExpandBackslashN),
		.useGoodRNG = (bool)(options & kOOExpandGoodRNG)
	};

	// Avoid recursive %I expansion by pre-seeding cache with literal %I.
	if (options & kOOExpandDisallowPercentI) {
		context.systemNameWithIan = OOUnits(u"%I");
	}

	OORandomState savedRandomState;
	if (options & kOOExpandReseedRNG)
	{
		savedRandomState = OOSaveRandomState();
		OOSetReallyRandomRANROTAndRndSeeds();
	}

	std::optional<std::string> result;
	// Was an autorelease-pool block, kept as the C++ pool: what the expander calls by name may defer
	// a release (OOCallByName).
	{
		oo::AutoreleaseScope pool;	// was an Objective-C autorelease pool (oo-31u.8)
		// TODO: profile caching the results. Would need to keep track of whether we've done something nondeterministic (array selection, %R etc).
		// (The context's values are C++ now: nothing is left to release if an exception unwinds.)
		OOMaybeUnits intermediate;
		const OOUnits units = oo::utf8ToUtf16(string);
		if (options & kOOExpandKey)
		{
			intermediate = ExpandStringKey(&context, units, kStackAllocationLimit, kRecursionLimit);
		}
		else
		{
			intermediate = Expand(&context, units, kStackAllocationLimit, kRecursionLimit);
		}
		if (context.hasPercentR)
		{
			intermediate = ExpandPercentR(&context, intermediate);
		}
		if (intermediate.has_value())  result = oo::utf16ToUtf8(*intermediate);

		if (options & kOOExpandReseedRNG)
		{
			OORestoreRandomState(savedRandomState);
		}
	}
	return result;
}


std::optional<std::string> cxx_OOGenerateSystemDescription(Random_Seed seed, const std::optional<std::string> &name)
{
	seed_RNG_only_for_planet_description(seed);
	return cxx_OOExpandDescriptionString(seed, "system-description-string", oo::PList(), oo::PList(), name, kOOExpandKey);
}


Random_Seed OOStringExpanderDefaultRandomSeed(void)
{
	auto *manager = (UNIVERSE != nullptr ? UNIVERSE->getSystemManager() : nullptr);	// null: a zero seed, as a message to nil (auto: the expander harness stubs the class)
	return (manager != nullptr) ? manager->getRandomSeedForCurrentSystem() : Random_Seed{};
}


// MARK: -
// MARK: Guts

namespace {


/*	Expand(context, string, sizeLimit, recursionLimit)
	
	Top-level expander. Expands all types of substitution in a string.
	
	<sizeLimit> is the remaining budget for stack allocation of read buffers.
	(Expand() is the only function that creates such buffers.) <recursionLimit>
	limits the number of recursive calls of Expand() that are permitted. If one
	of the limits would be exceeded, Expand() returns the input string unmodified.
*/
OOUnits Expand(OOStringExpansionContext *context, const OOUnits &string, NSUInteger sizeLimit, NSUInteger recursionLimit)
{
	OOCParameterAssert(context != NULL && sizeLimit <= kStackAllocationLimit);

	const NSUInteger size = string.size();

	// Avoid stack overflow.
	if (EXPECT_NOT(size > sizeLimit || recursionLimit == 0))  return string;
	sizeLimit -= size;
	recursionLimit--;

	// Nothing to expand in an empty string, and the size-1 thing below would be trouble.
	if (size == 0)  return string;

	const char16_t *characters = string.data();

	/*	Beginning of current range of non-special characters. If we encounter
		a substitution, we'll be copying from here forward.
	*/
	NSUInteger copyRangeStart = 0;

	// Result, if we perform any substitutions.
	OOMaybeUnits result;

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
		OOMaybeUnits replacement;
		NSUInteger replaceLength = 0;
		uint16_t thisChar = characters[idx];
		
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
			SyntaxWarning(context, "strings.expand.warning.unbalancedClosingBracket", "%s", "Unbalanced ] in string.");
		}
		else if (thisChar == '\\' && context->convertBackslashN)
		{
			if (characters[idx + 1] == 'n')
			{
				replaceLength = 2;
				replacement = OOUnits(u"\n");
			}
		}
		else
		{
			// No token start character, so we definitely have no replacement.
			continue;
		}

		if (replacement.has_value())
		{
			/*	If replacement string is "\x7F", eat the following character.
				This is used in system_description for the one empty string
				in [22]. At the end of the string there is no following
				character, and nothing is eaten (bead oo-3rb.69, approved by
				Jon 2026-09-29: upstream tested replaceLength < size, which let
				idx + replaceLength pass size there and assert below).
			*/
			if (*replacement == u"\x7F" && replaceLength < size)
			{
				if (idx + replaceLength < size)  replaceLength++;
				replacement = OOUnits();
			}

			// Avoid copying if we're replacing the entire input string.
			if (copyRangeStart == 0 && replaceLength == size)
			{
				return *replacement;
			}

			// Write the pending literal segment to result. This also allocates result if needed.
			AppendCharacters(&result, characters, copyRangeStart, idx);

			*result += *replacement;

			// Skip over replaced part and start a new literal segment.
			idx += replaceLength - 1;
			copyRangeStart = idx + 1;
		}
	}

	if (result.has_value())
	{
		// Append any trailing literal segment.
		AppendCharacters(&result, characters, copyRangeStart, size);

		return *result;
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
	
	The key may be terminated by a vertical bar |, followed by an operator. An
	operator is an identifier, optionally followed by a colon and additional
	text, and may be terminated with another bar and operator.
*/
OOMaybeUnits ExpandKey(OOStringExpansionContext *context, const char16_t *characters, NSUInteger size, NSUInteger idx, NSUInteger *replaceLength, NSUInteger sizeLimit, NSUInteger recursionLimit)
{
	OOCParameterAssert(context != NULL && characters != NULL && replaceLength != NULL);
	OOCParameterAssert(characters[idx] == '[');
	
	// Find the balancing close bracket.
	NSUInteger end, balanceCount = 1, firstBar = 0;
	bool allDigits = true;
	
	for (end = idx + 1; end < size && balanceCount > 0; end++)
	{
		if (characters[end] == ']')  balanceCount--;
		else
		{
			if (characters[end] == '[')  balanceCount++;
			else if (characters[end] == '|' && firstBar == 0)  firstBar = end;
			if (!isdigit(characters[end]) && firstBar == 0)  allDigits = false;
		}
	}
	
	// Fail if no balancing bracket.
	if (EXPECT_NOT(balanceCount != 0))
	{
		SyntaxWarning(context, "strings.expand.warning.unbalancedOpeningBracket", "%s", "Unbalanced [ in string.");
		return std::nullopt;
	}
	
	NSUInteger totalLength = end - idx;
	*replaceLength = totalLength;
	NSUInteger keyStart = idx + 1, keyLength = totalLength - 2;
	if (firstBar != 0)  keyLength = firstBar - idx - 1;
	
	if (EXPECT_NOT(keyLength == 0))
	{
		SyntaxWarning(context, "strings.expand.warning.emptyKey", "%s", "Invalid expansion code [] string. (To avoid this message, use %%[%%].)");
		return std::nullopt;
	}

	OOMaybeUnits expanded;
	if (allDigits)
	{
		expanded = ExpandDigitKey(context, characters, keyStart, keyLength, sizeLimit, recursionLimit);
	}
	else
	{
		OOUnits key = UnitsWithCharacters(characters + keyStart, keyLength);
		expanded = ExpandStringKey(context, key, sizeLimit, recursionLimit);
	}

	if (firstBar != 0)
	{
		OOUnits operators = UnitsWithCharacters(characters + firstBar + 1, end - firstBar - 2);
		expanded = ApplyOperators(expanded, operators);
	}

	return expanded;
}


/*	ApplyOperators(string, operatorsString)
	
	Given a string and a series of formatting operators separated by vertical
	bars (or a single formatting operator), apply the operators, in sequence,
	to the string.
 */
OOMaybeUnits ApplyOperators(OOMaybeUnits string, const OOUnits &operatorsString)
{
	// Each part of operatorsString between '|' separators (-componentsSeparatedByString:), in order.
	NSUInteger partStart = 0;
	for (;;)
	{
		const NSUInteger bar = FindUnits(operatorsString, u"|", partStart);
		const NSUInteger partEnd = (bar == NSNotFound) ? operatorsString.size() : bar;
		OOUnits op = operatorsString.substr(partStart, partEnd - partStart);

		OOMaybeUnits param;
		const NSUInteger colon = FindUnits(op, u":", 0);
		if (colon != NSNotFound)
		{
			param = op.substr(colon + 1);
			op.resize(colon);
		}
		string = ApplyOneOperator(string, op, param);

		if (bar == NSNotFound)  break;
		partStart = bar + 1;
	}

	return string;
}


// -doubleValue / -longLongValue / -intValue, answering 0 for nil as messaging nil did.
double DoubleValue(const OOMaybeUnits &string)
{
	return string.has_value() ? oo::plist_get::doubleValue(*string) : 0.0;
}


long long LongLongValue(const OOMaybeUnits &string)
{
	return string.has_value() ? oo::plist_get::longLongValue(*string) : 0;
}


int IntValue(const OOMaybeUnits &string)
{
	return string.has_value() ? oo::plist_get::intValue(*string) : 0;
}


OOMaybeUnits UnitsFromUTF8(const std::string &string)
{
	return oo::utf8ToUtf16(string);
}


OOMaybeUnits Operator_cr(const OOMaybeUnits &string, const OOMaybeUnits & /* param */)
{
	return oo::utf8ToUtf16(cxx_OOCredits(DoubleValue(string) * 10));
}


OOMaybeUnits Operator_dcr(const OOMaybeUnits &string, const OOMaybeUnits & /* param */)
{
	return oo::utf8ToUtf16(cxx_OOCredits(LongLongValue(string)));
}


OOMaybeUnits Operator_icr(const OOMaybeUnits &string, const OOMaybeUnits & /* param */)
{
	return oo::utf8ToUtf16(cxx_OOIntCredits(LongLongValue(string)));
}


OOMaybeUnits Operator_idcr(const OOMaybeUnits &string, const OOMaybeUnits & /* param */)
{
	return oo::utf8ToUtf16(cxx_OOIntCredits(round(DoubleValue(string) / 10.0)));
}


OOMaybeUnits Operator_precision(const OOMaybeUnits &string, const OOMaybeUnits &param)
{
	return UnitsFromUTF8(oo::str::format("%.*f", IntValue(param), DoubleValue(string)));
}


OOMaybeUnits Operator_multiply(const OOMaybeUnits &string, const OOMaybeUnits &param)
{
	return UnitsFromUTF8(oo::str::format("%g", DoubleValue(string) * DoubleValue(param)));
}


OOMaybeUnits Operator_add(const OOMaybeUnits &string, const OOMaybeUnits &param)
{
	return UnitsFromUTF8(oo::str::format("%g", DoubleValue(string) + DoubleValue(param)));
}


/*	ApplyOneOperator(string, op, param)
	
	Apply a single formatting operator to a string.
	
	For example, the expansion expression "[distance|precision:1]" will be
	expanded by a call to ApplyOneOperator(@"distance", @"precision", @"1").
	
	<param> may be nil, indicating an operator with no parameter (no colon).
 */
OOMaybeUnits ApplyOneOperator(const OOMaybeUnits &string, const OOUnits &op, const OOMaybeUnits &param)
{
	static const struct
	{
		std::u16string_view name;
		OOMaybeUnits (*function)(const OOMaybeUnits &string, const OOMaybeUnits &param);
	} operators[] =
	{
		#define OPERATOR(name) { u ## #name, Operator_##name }
		OPERATOR(dcr),
		OPERATOR(cr),
		OPERATOR(icr),
		OPERATOR(idcr),
		OPERATOR(precision),
		OPERATOR(multiply),
		OPERATOR(add),
		#undef OPERATOR
	};

	for (const auto &entry : operators)
	{
		if (op == entry.name)  return entry.function(string, param);
	}

	OO_LOG_ERR("strings.expand.invalidOperator", "Unknown string expansion operator {}", oo::utf16ToUtf8(op));
	return string;
}


/*	ExpandDigitKey(context, characters, keyStart, keyLength, sizeLimit, recursionLimit)
	
	Expand a key (as per ExpandKey()) consisting entirely of digits. <keyStart>
	and <keyLength> specify the range of characters containing the key.
	
	Digit-only keys are looked up in the system_description array in
	descriptions.plist, which is expected to contain only arrays of strings (no
	loose strings). When an array is retrieved, a string is selected from it
	at random and the result is expanded recursively by calling Expand().
*/
OOMaybeUnits ExpandDigitKey(OOStringExpansionContext *context, const char16_t *characters, NSUInteger keyStart, NSUInteger keyLength, NSUInteger sizeLimit, NSUInteger recursionLimit)
{
	OOCParameterAssert(context != NULL && characters != NULL);

	NSUInteger keyValue = 0, idx;
	for (idx = keyStart; idx < (keyStart + keyLength); idx++)
	{
		OOCAssert(isdigit(characters[idx]), "%s called with non-numeric key [%s].", __FUNCTION__, oo::utf16ToUtf8(UnitsWithCharacters(characters + keyStart, keyLength)).c_str());

		keyValue = keyValue * 10 + characters[idx] - '0';
	}

	// Retrieve selected system_description entry (it must be an array, as PListView required).
	const oo::PList &sysDescs = GetSystemDescriptions(context);
	const oo::PList *entry = sysDescs.at(keyValue);
	if (entry != nullptr && !entry->isArray())  entry = nullptr;

	if (EXPECT_NOT(entry == nullptr))
	{
		if (keyValue >= context->sysDescCount)
		{
			SyntaxWarning(context, "strings.expand.warning.outOfRangeKey", "Out-of-range system description expansion key [%s] in string.", oo::utf16ToUtf8(UnitsWithCharacters(characters + keyStart, keyLength)).c_str());
		}
		else
		{
			// This is out of the scope of whatever triggered it, so shouldn't be a JS warning.
			OO_LOG_ERR("strings.expand.invalidData", "{}", "descriptions.plist entry system_description must be an array of arrays of strings.");
		}
		return std::nullopt;
	}
	
	// Select a random sub-entry.
	NSUInteger selection, count = entry->count();
	NSUInteger rnd = OO_EXPANDER_RANDOM;
	if (count == 5 && !context->useGoodRNG)
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
	// PListView's string rule: a string, or a number's -stringValue; anything else is none.
	OOMaybeUnits string;
	const oo::PList *choice = entry->at(selection);
	if (choice != nullptr && (choice->isString() || choice->isNumber()))  string = oo::utf8ToUtf16(entry->at<std::string>(selection));
	OOCParameterAssert(string.has_value());
	if (!string.has_value())  return std::nullopt;
	return Expand(context, *string, sizeLimit, recursionLimit);
}


/*	ExpandStringKey(context, key, sizeLimit, recursionLimit)
	
	Expand a key (as per ExpandKey()) which doesn't consist entirely of digits.
	Looks for the key in a number of different places in prioritized order.
*/
OOMaybeUnits ExpandStringKey(OOStringExpansionContext *context, const OOUnits &key, NSUInteger sizeLimit, NSUInteger recursionLimit)
{
	OOCParameterAssert(context != NULL);

	// The lookups are keyed by the key's UTF-8 (WTF-8: lossless, as the string object the engine built).
	const std::string keyString = oo::utf16ToUtf8(key);

	// Overrides have top priority.
	OOMaybeUnits result = ExpandStringKeyOverride(context, keyString);

	// Specials override descriptions.plist.
	if (!result.has_value())  result = ExpandStringKeySpecial(context, keyString);

	// Now try descriptions.plist.
	if (!result.has_value())  result = ExpandStringKeyFromDescriptions(context, keyString, sizeLimit, recursionLimit);

	// For efficiency, descriptions.plist overrides keybindings.
	// OXPers should therefore avoid oolite_key_ description keys
	if (!result.has_value())  result = ExpandStringKeyKeyboardBinding(context, key);

	// Try mission variables.
	if (!result.has_value())  result = ExpandStringKeyMissionVariable(context, key, keyString);

	// Try legacy local variables.
	if (!result.has_value())  result = ExpandStringKeyLegacyLocalVariable(context, keyString);

	// Try legacy script methods. (Upstream calls it for its side effects and discards the result.)
	if (!result.has_value())  ExpandLegacyScriptSelectorKey(context, keyString);

#if WARNINGS
	// None of that worked, so moan a bit.
	if (!result.has_value())  ReportWarningForUnknownKey(context, key, keyString);
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
OOMaybeUnits ExpandStringKeyOverride(OOStringExpansionContext *context, const std::string &key)
{
	OOCParameterAssert(context != NULL);

	const oo::PList *value = context->overrides.find(key);
	if (value != nullptr)
	{
#if WARNINGS
		if (!value->isString() && !value->isNumber())
		{
			SyntaxWarning(context, "strings.expand.warning.invalidOverride", "String expansion override value %s for [%s] is not a string or number.", oo::DescriptionOf(*value).c_str(), key.c_str());	// the value (was <ClassName 0x...> of its Foundation object, bead oo-qps.50)
		}
#endif
		return ValueText(*value);
	}

	return std::nullopt;
}


/*	ExpandStringKeySpecial(context, key)
	
	Attempt to expand a key by matching a set of special expansion codes that
	call PlayerEntity methods but aren't legacy script methods. Also unlike
	legacy script methods, all these methods return strings.
*/
OOMaybeUnits ExpandStringKeySpecial(OOStringExpansionContext *context, const std::string &key)
{
	OOCParameterAssert(context != NULL);

	const std::string *selector = LookUpSelector(SpecialSubstitutionSelectors(), key);
	if (selector != nullptr)
	{
		OOCAssert(oo::EntityRespondsToName(PLAYER, *selector), "Special string expansion selector %s for [%s] is not implemented.", selector->c_str(), key.c_str());

		// Called by name (ADR-0055 item 5) on the player's C++ part (bead oo-9ht.39.7.2): a string
		// result, as a PList.
		const oo::PList result = oo::CallEntityByName(PLAYER, *selector);
		if (!result.isNull())
		{
			const std::string *string = result.getIf<std::string>();
			OOCAssert(string != nullptr, "Special string expansion [%s] expanded to %s, but expected a string.", key.c_str(), oo::DescriptionOf(result).c_str());
			if (string != nullptr)  return UnitsFromOptional(std::optional<std::string>(*string));
		}
	}

	return std::nullopt;
}


/*	ExpandStringKeyKeyboardBinding(context, key)

	Attempt to expand a key by matching it against the keybindings
*/
OOMaybeUnits ExpandStringKeyKeyboardBinding(OOStringExpansionContext *context, const OOUnits &key)
{
	OOCParameterAssert(context != NULL);
	if (HasPrefix(key, u"oolite_key_"))
	{
		const std::string binding = oo::utf16ToUtf8(key.substr(7));
		return UnitsFromOptional((PLAYER != nullptr ? PLAYER->keyBindingDescription2(binding) : std::optional<std::string>()));
	}
	return std::nullopt;
}


/*	SpecialSubstitutionSelectors()
	
	Retrieve the mapping of special keys for ExpandStringKeySpecial() to
	selectors.
*/
const OOSelectorTable *SpecialSubstitutionSelectors(void)
{
	static OOSelectorTable *specials = NULL;
	if (specials != NULL)  return specials;
	
	struct { const char *key; const char *selector; } selectors[] =
	{
		{ "commander_name", "commanderName_string" },
		{ "commander_shipname", "commanderShip_string" },
		{ "commander_shipdisplayname", "commanderShipDisplayName_string" },
		{ "commander_rank", "commanderRank_string" },
		{ "commander_kills", "commanderKillsAsString" },
		{ "commander_legal_status", "commanderLegalStatus_string" },
		{ "commander_bounty", "commanderBountyAsString" },
		{ "credits_number", "creditsFormattedForSubstitution" },
		{ "_oo_legacy_credits_number", "creditsFormattedForLegacySubstitution" }
	};
	unsigned i, count = sizeof selectors / sizeof *selectors;

	specials = new OOSelectorTable;
	for (i = 0; i < count; i++)
	{
		specials->emplace(selectors[i].key, selectors[i].selector);
	}
	
	return specials;
}


/*	ExpandStringKeyFromDescriptions(context, key, sizeLimit, recursionLimit)
	
	Attempt to expand a key by looking it up in descriptions.plist. Matches
	may be single strings or arrays of strings. For arrays, one of the strings
	is selected at random.
	
	Matched strings are expanded recursively by calling Expand().
*/
OOMaybeUnits ExpandStringKeyFromDescriptions(OOStringExpansionContext *context, const std::string &key, NSUInteger sizeLimit, NSUInteger recursionLimit)
{
	// The error log names the value's class as the Foundation object built from it did.
	const oo::PList *found = UNIVERSE->descriptions()->find(key);
	oo::PList value = (found != nullptr) ? *found : oo::PList();
	if (!value.isNull())
	{
		if (value.isArray() && value.count() > 0)
		{
			NSUInteger rnd = OO_EXPANDER_RANDOM % value.count();
			const oo::PList chosen = *value.at(rnd);
			value = chosen;
		}

		const std::string *text = value.getIf<std::string>();
		if (text == nullptr)
		{
			// This is out of the scope of whatever triggered it, so shouldn't be a JS warning.
			OO_LOG_ERR("strings.expand.invalidData", "String expansion value {} for [{}] from descriptions.plist is not a string or number.", oo::DescriptionOf(value), key);	// the value (was <ClassName 0x...> of its Foundation object, bead oo-qps.50)
			return std::nullopt;
		}

		// Expand recursively.
		return Expand(context, oo::utf8ToUtf16(*text), sizeLimit, recursionLimit);
	}

	return std::nullopt;
}


/*	ExpandStringKeyMissionVariable(context, key)

	Attempt to expand a key by matching it to a mission variable.
*/
OOMaybeUnits ExpandStringKeyMissionVariable(OOStringExpansionContext * /* context */, const OOUnits &key, const std::string &keyString)
{
	if (HasPrefix(key, u"mission_"))
	{
		// A string variable expands to its text; an unset one to nothing. A variable that is not a
		// string (an array, from the legacy set-list action) expands as unset: its Objective-C
		// object was sent -length, which it did not answer (bead oo-qps.50).
		const oo::PList value = (PLAYER != nullptr ? PLAYER->missionVariableForKey(keyString) : oo::PList());
		const std::string *text = value.getIf<std::string>();
		return UnitsFromOptional((text != nullptr) ? std::optional<std::string>(*text) : std::nullopt);
	}

	return std::nullopt;
}


/*	ExpandStringKeyMissionVariable(context, key)
	
	Attempt to expand a key by matching it to a legacy local variable.
	
	The main difference between overrides and legacy locals is priority.
*/
OOMaybeUnits ExpandStringKeyLegacyLocalVariable(OOStringExpansionContext *context, const std::string &key)
{
	const oo::PList *value = context->legacyLocals.find(key);
	if (value == nullptr)  return std::nullopt;
	return ValueText(*value);
}


OOMaybeUnits UnitsFromOptional(const std::optional<std::string> &string)
{
	if (!string.has_value())  return std::nullopt;
	return oo::utf8ToUtf16(*string);
}


/*	A mixed value's -description, as the lookups above inserted it: a string is itself, a number
	its -stringValue (oo::plist_get::numberStringValue), anything else the Objective-C object's
	-description.
*/
OOUnits ValueText(const oo::PList &value)
{
	if (const std::string *text = value.getIf<std::string>())  return oo::utf8ToUtf16(*text);
	if (value.isNumber())  return oo::utf8ToUtf16(oo::plist_get::numberStringValue(value));
	return oo::utf8ToUtf16(oo::DescriptionOf(value));
}


/*	ExpandLegacyScriptSelectorKey(context, key)
	
	Attempt to expand a key by treating it as a legacy script query method and
	invoking it. Only whitelisted methods are permitted, and aliases are
	respected.
*/
OOMaybeUnits ExpandLegacyScriptSelectorKey(OOStringExpansionContext *context, const std::string &key)
{
	OOCParameterAssert(context != NULL);

	const std::string *selector = LookUpLegacySelector(key);

	if (selector != nullptr)
	{
		// Called by name (ADR-0055 item 5) on the player's C++ part (bead oo-9ht.39.7.2): "%@" of the
		// result, as [[result description]] gave it (nil stays nil).
		const oo::PList result = oo::CallEntityByName(PLAYER, *selector);
		return UnitsFromOptional(!result.isNull() ? std::optional<std::string>(oo::DescriptionOf(result)) : std::nullopt);
	}
	else
	{
		return std::nullopt;
	}
}


/*	LookUpLegacySelector(key)
	
	If <key> is a whitelisted legacy script query method, or aliases to one,
	return the corresponding selector.
*/
const std::string *LookUpLegacySelector(const std::string &key)
{
	const std::string *selector = nullptr;
	static OOSelectorTable *selectorCache = NULL;

	// Try cache lookup.
	selector = LookUpSelector(selectorCache, key);

	if (selector == nullptr)
	{
		// whitelist.plist's query methods (its string entries) and aliases (a string, or a
		// number's -stringValue, as PListView's string rule gave), built once. ResourceManager is
		// not migrated here: its dictionary converts once, with oo::PListFrom.
		static std::map<std::string, std::string, std::less<>> *aliases = nullptr;
		static std::set<std::string, std::less<>> *whitelist = nullptr;
		if (whitelist == nullptr)
		{
			const oo::PList whitelistDict = ResourceManager::whitelistDictionary();
			whitelist = new std::set<std::string, std::less<>>;
			aliases = new std::map<std::string, std::string, std::less<>>;
			const oo::PList *methods = whitelistDict.find("query_methods");
			if (methods != nullptr && methods->isArray())
			{
				for (const oo::PList &method : *methods->getIf<oo::PList::Array>())
				{
					if (const std::string *name = method.getIf<std::string>())  whitelist->insert(*name);
				}
			}
			const oo::PList *aliasDict = whitelistDict.find("query_method_aliases");
			if (aliasDict != nullptr && aliasDict->isDict())
			{
				for (const auto &alias : *aliasDict->getIf<oo::PList::Dict>())
				{
					if (alias.second.isString() || alias.second.isNumber())  aliases->emplace(alias.first, aliasDict->get<std::string>(alias.first));
				}
			}
		}

		auto alias = aliases->find(key);
		const std::string &selectorName = (alias != aliases->end()) ? alias->second : key;

		if (whitelist->count(selectorName) != 0)
		{
			/*	This is an assertion, not a warning, because whitelist.plist is
				part of the game and cannot be overriden by OXPs. If there is an
				invalid selector in the whitelist, it's a game bug.
			*/
			OOCAssert(oo::EntityRespondsToName(PLAYER, selectorName), "Player does not respond to whitelisted query selector %s.", key.c_str());

			// Add it to cache (the name; a map's element does not move).
			if (selectorCache == NULL)
			{
				selectorCache = new OOSelectorTable;
			}
			selector = &selectorCache->emplace(key, selectorName).first->second;
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
void ReportWarningForUnknownKey(OOStringExpansionContext *context, const OOUnits &keyUnits, const std::string &key)
{
	if (HasSuffix(keyUnits, u"_string") || HasSuffix(keyUnits, u"_number") || HasSuffix(keyUnits, u"_bool"))
	{
		SyntaxError(context, "strings.expand.invalidSelector", "Unpermitted legacy script method [%s] in string.", key.c_str());
	}
	else
	{
		SyntaxWarning(context, "strings.expand.warning.unknownExpansion", "Unknown expansion key [%s] in string.", key.c_str());
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
		%G######, where ### are six digits
		%%
		%[
		%]
	
	In addition, the codes %@, %d and %. are ignored, because they're used
	with the Objective-C string formatter (%@ / %d) on strings that have
	already been expanded.
	
	Any other code results in a warning.
*/
OOMaybeUnits ExpandPercentEscape(OOStringExpansionContext *context, const char16_t *characters, NSUInteger size, NSUInteger idx, NSUInteger *replaceLength)
{
	OOCParameterAssert(context != NULL && characters != NULL && replaceLength != NULL);
	OOCParameterAssert(characters[idx] == '%');
	
	// All %-escapes except %J and %G are 2 characters.
	*replaceLength = 2;
	uint16_t selector = characters[idx + 1];
	
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
			return OOUnits(u"%R");
			
		case 'G':
			return ExpandSystemNameForGalaxyEscape(context, characters, size, idx, replaceLength);
			
		case 'J':
			return ExpandSystemNameEscape(context, characters, size, idx, replaceLength);
			
		case '%':
			return OOUnits(u"%");
			
		case '[':
			return OOUnits(u"[");
			
		case ']':
			return OOUnits(u"]");
			
			/*	These are Objective-C string formatting specifiers that occur in
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
			return std::nullopt;
			
		default:
			// Yay, percent signs!
			/*	The Objective-C formatter's %lc of a unichar kept only its low byte: the high byte of
				the character it produced was undefined (probed on gnustep-base 1.31.1: U+0041 gave
				U+DB41, U+0301 gave U+D301 or U+DB01 from run to run; tests/unit/expander masks all
				but the low byte). The low byte is printed, as the character U+00xx (%c for ASCII,
				so that U+0000 survives; UTF-8 through %s above it).
			*/
			const unsigned char lowByte = static_cast<unsigned char>(selector & 0xFF);
			if (lowByte < 0x80)
			{
				SyntaxWarning(context, "strings.expand.warning.unknownPercentEscape", "Unknown escape code in string: %%%c. (To encode a %% sign without this warning, use %%%% - but prefer \"percent\" in prose writing.)", lowByte);
			}
			else
			{
				SyntaxWarning(context, "strings.expand.warning.unknownPercentEscape", "Unknown escape code in string: %%%s. (To encode a %% sign without this warning, use %%%% - but prefer \"percent\" in prose writing.)", oo::utf16ToUtf8(OOUnits(1, lowByte)).c_str());
			}
			
			return std::nullopt;
	}
}


/* ExpandPercentR(context, string) 
	 Replaces all %R in string with its expansion.
	 Separate to allow this to be delayed to the end of the string expansion
	 for compatibility with 1.76 expansion of %R in planet descriptions
*/
OOMaybeUnits ExpandPercentR(OOStringExpansionContext *context, const OOMaybeUnits &input)
{
	// [input rangeOfString:@"%R"] (a nil input answered location 0, i.e. found).
	if (input.has_value() && FindUnits(*input, u"%R", 0) == NSNotFound)
	{
		return input; // no %Rs to replace
	}
	const OOMaybeUnits percentR = GetRandomNameR(context);
	if (!input.has_value())  return std::nullopt;	// Unreachable: %R is only seen in an expanded string.
	OOUnits output = *input;

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
		// Every "%R" replaced, unit for unit (it was -replaceOccurrencesOfString: with NSLiteralSearch).
		OOUnits replaced;
		replaced.reserve(output.size());
		for (NSUInteger i = 0; i < output.size();)
		{
			if (i + 1 < output.size() && output[i] == u'%' && output[i + 1] == u'R')
			{
				replaced += *percentR;
				i += 2;
			}
			else
			{
				replaced += output[i++];
			}
		}
		output = replaced;
	} while (FindUnits(output, u"%R", 0) != NSNotFound);

	return output;
}


/*	ExpandSystemNameForGalaxyEscape(context, characters, size, idx, replaceLength)
	
	Expand a %G###### code by looking up the corresponding system name in any
	cgalaxy.
*/
OOMaybeUnits ExpandSystemNameForGalaxyEscape(OOStringExpansionContext *context, const char16_t *characters, NSUInteger size, NSUInteger idx, NSUInteger *replaceLength)
{
	OOCParameterAssert(context != NULL && characters != NULL && replaceLength != NULL);
	OOCParameterAssert(characters[idx + 1] == 'G');
	
	// A valid %G escape is always eight characters including the six digits.
	*replaceLength = 8;
	
	#define kInvalidGEscapeMessage "String escape code %G must be followed by six integers."
	if (EXPECT_NOT(size - idx < 8))
	{
		// Too close to end of string to actually have six characters, let alone six digits.
		SyntaxError(context, "strings.expand.invalidJEscape", "%s", kInvalidGEscapeMessage);
		return std::nullopt;
	}
	
	char hundreds = characters[idx + 2];
	char tens = characters[idx + 3];
	char units = characters[idx + 4];
	char galHundreds = characters[idx + 5];
	char galTens = characters[idx + 6];
	char galUnits = characters[idx + 7];
	
	if (!(isdigit(hundreds) && isdigit(tens) && isdigit(units) && isdigit(galHundreds) && isdigit(galTens) && isdigit(galUnits)))
	{
		SyntaxError(context, "strings.expand.invalidJEscape", "%s", kInvalidGEscapeMessage);
		return std::nullopt;
	}
	
	OOSystemID sysID = (hundreds - '0') * 100 + (tens - '0') * 10 + (units - '0');
	if (sysID > kOOMaximumSystemID)
	{
		SyntaxError(context, "strings.expand.invalidJEscape.range", "String escape code %%G%3u for system is out of range (must be less than %u).", sysID, kOOMaximumSystemID + 1);
		return std::nullopt;
	}
	
	OOGalaxyID galID = (galHundreds - '0') * 100 + (galTens - '0') * 10 + (galUnits - '0');
	if (galID > kOOMaximumGalaxyID)
	{
		SyntaxError(context, "strings.expand.invalidJEscape.range", "String escape code %%G%3u for galaxy is out of range (must be less than %u).", galID, kOOMaximumGalaxyID + 1);
		return std::nullopt;
	}
	
	return UnitsFromOptional((UNIVERSE != nullptr ? UNIVERSE->getSystemName(sysID, galID) : std::optional<std::string>()));
}


/*	ExpandSystemNameEscape(context, characters, size, idx, replaceLength)
	
	Expand a %J### code by looking up the corresponding system name in the
	current galaxy.
*/
OOMaybeUnits ExpandSystemNameEscape(OOStringExpansionContext *context, const char16_t *characters, NSUInteger size, NSUInteger idx, NSUInteger *replaceLength)
{
	OOCParameterAssert(context != NULL && characters != NULL && replaceLength != NULL);
	OOCParameterAssert(characters[idx + 1] == 'J');
	
	// A valid %J escape is always five characters including the three digits.
	*replaceLength = 5;
	
	#define kInvalidJEscapeMessage "String escape code %J must be followed by three integers."
	if (EXPECT_NOT(size - idx < 5))
	{
		// Too close to end of string to actually have three characters, let alone three digits.
		SyntaxError(context, "strings.expand.invalidJEscape", "%s", kInvalidJEscapeMessage);
		return std::nullopt;
	}
	
	char hundreds = characters[idx + 2];
	char tens = characters[idx + 3];
	char units = characters[idx + 4];
	
	if (!(isdigit(hundreds) && isdigit(tens) && isdigit(units)))
	{
		SyntaxError(context, "strings.expand.invalidJEscape", "%s", kInvalidJEscapeMessage);
		return std::nullopt;
	}
	
	OOSystemID sysID = (hundreds - '0') * 100 + (tens - '0') * 10 + (units - '0');
	if (sysID > kOOMaximumSystemID)
	{
		SyntaxError(context, "strings.expand.invalidJEscape.range", "String escape code %%J%3u is out of range (must be less than %u).", sysID, kOOMaximumSystemID + 1);
		return std::nullopt;
	}
	
	return UnitsFromOptional((UNIVERSE != nullptr ? UNIVERSE->getSystemName(sysID) : std::optional<std::string>()));
}


void AppendCharacters(OOMaybeUnits *result, const char16_t *characters, NSUInteger start, NSUInteger end)
{
	OOCParameterAssert(result != NULL && characters != NULL && start <= end);

	if (!result->has_value())
	{
		// Ensure there is a string. We want this even if the range is empty.
		result->emplace();
	}

	if (start == end)  return;

	// The segment goes through -initWithCharacters:length:'s byte-order-mark handling, as the
	// temporary Objective-C string it used to be built as did.
	**result += UnitsWithCharacters(characters + start, end - start);
}


OOMaybeUnits GetSystemName(OOStringExpansionContext *context)
{
	OOCParameterAssert(context != NULL);
	if (!context->systemName.has_value()) {
		context->systemName = UnitsFromOptional((UNIVERSE != nullptr ? UNIVERSE->getSystemName((PLAYER != nullptr ? PLAYER->systemID() : 0)) : std::optional<std::string>()));
	}

	return context->systemName;
}


OOMaybeUnits GetSystemNameIan(OOStringExpansionContext *context)
{
	OOCParameterAssert(context != NULL);

	if (!context->systemNameWithIan.has_value())
	{
		const std::optional<std::string> name = cxx_OOExpandDescriptionString(context->seed, "planetname-possessive", oo::PList(), oo::PList(), std::nullopt, kOOExpandDisallowPercentI | kOOExpandGoodRNG | kOOExpandKey);
		if (name.has_value())  context->systemNameWithIan = oo::utf8ToUtf16(*name);
	}

	return context->systemNameWithIan;
}


OOMaybeUnits GetRandomNameN(OOStringExpansionContext *context)
{
	OOCParameterAssert(context != NULL);

	if (!context->randomNameN.has_value())
	{
		context->randomNameN = NewRandomDigrams(context);
	}

	return context->randomNameN;
}


OOMaybeUnits GetRandomNameR(OOStringExpansionContext *context)
{
	OOCParameterAssert(context != NULL);

	if (!context->randomNameR.has_value())
	{
		context->randomNameR = OldRandomDigrams();
	}

	return context->randomNameR;
}


const oo::PList &GetSystemDescriptions(OOStringExpansionContext *context)
{
	OOCParameterAssert(context != NULL);

	if (context->systemDescriptions.isNull())
	{
		// Looked up once per context (PListView's rule: an array, else none).
		const oo::PList *found = UNIVERSE->descriptions()->find("system_description");
		const oo::PList value = (found != nullptr) ? *found : oo::PList();
		if (value.isArray())  context->systemDescriptions = value;
		context->sysDescCount = context->systemDescriptions.count();
	}

	return context->systemDescriptions;
}


/*	The digram at <location> of descriptions.plist's "digrams" string ([digrams
	substringWithRange:NSMakeRange(location, 2)], which raises past the end).
*/
OOUnits Digram(const std::optional<std::string> &digrams, const OOUnits &units, NSUInteger location)
{
	if (location + 2 > units.size())
	{
		// Raises OORangeException with GNUstep's -substringWithRange: text, as messaging the string
		// did; answers nothing (nothing appended) for no <digrams> (a message to nil).
		if (digrams.has_value())
		{
			OORaiseException(OORangeException, "in substringWithRange:, range { %lu, 2 } extends beyond size (%lu)", (unsigned long)location, (unsigned long)units.size());
		}
		return OOUnits();
	}
	return units.substr(location, 2);
}


// -capitalizedString.
OOUnits Capitalized(const OOUnits &name)
{
	return oo::utf8ToUtf16(oo::str::capitalized(oo::utf16ToUtf8(name)));
}


/*	Generates pseudo-random digram string using gen_rnd_number()
	(world-generation consistent PRNG), but misses some possibilities. Used
	for "%R" description string for backwards compatibility.
*/
OOUnits OldRandomDigrams(void)
{
	/* The only point of using %R is for world generation, so there's
	 * no point in checking the context */
	unsigned len = gen_rnd_number() & 3;
	const oo::PList *digramsEntry = UNIVERSE->descriptions()->find("digrams");
	const std::string *digramsText = (digramsEntry != nullptr) ? digramsEntry->getIf<std::string>() : nullptr;
	const std::optional<std::string> digrams = (digramsText != nullptr) ? std::optional<std::string>(*digramsText) : std::nullopt;
	const OOUnits digramUnits = UnitsFromOptional(digrams).value_or(OOUnits());
	OOUnits name;

	for (unsigned i = 0; i <=len; i++)
	{
		unsigned x =  gen_rnd_number() & 0x3e;
		name += Digram(digrams, digramUnits, x);
	}

	return Capitalized(name);
}


/*	Generates pseudo-random digram string. Used for "%N" description string.
*/
OOUnits NewRandomDigrams(OOStringExpansionContext *context)
{
	unsigned length = (OO_EXPANDER_RANDOM % 4) + 1;
	if ((OO_EXPANDER_RANDOM % 5) < ((length == 1) ? 3 : 1))  ++length;	// Make two-letter names rarer and 10-letter names happen sometimes
	const oo::PList *digramsEntry = UNIVERSE->descriptions()->find("digrams");
	const std::string *digramsText = (digramsEntry != nullptr) ? digramsEntry->getIf<std::string>() : nullptr;
	const std::optional<std::string> digrams = (digramsText != nullptr) ? std::optional<std::string>(*digramsText) : std::nullopt;
	const OOUnits digramUnits = UnitsFromOptional(digrams).value_or(OOUnits());
	NSUInteger count = digramUnits.size() / 2;
	OOUnits name;

	for (unsigned i = 0; i != length; ++i)
	{
		name += Digram(digrams, digramUnits, (OO_EXPANDER_RANDOM % count) * 2);
	}

	return Capitalized(name);
}


// MARK: -
// MARK: UTF-16 units


/*	+stringWithCharacters:length: / -initWithCharacters:length:, which is how the
	engine used to cut keys, operators and literal segments out of a string: GNUstep drops a
	leading U+FEFF, or drops a leading U+FFFE and byte-swaps the rest, and does so twice
	(probed on gnustep-base 1.31.1).
*/
OOUnits UnitsWithCharacters(const char16_t *characters, NSUInteger length)
{
	OOUnits units(characters, length);
	for (int pass = 0; pass < 2 && !units.empty(); pass++)
	{
		if (units[0] == 0xFEFF)
		{
			units.erase(0, 1);
		}
		else if (units[0] == 0xFFFE)
		{
			units.erase(0, 1);
			for (char16_t &c : units)  c = static_cast<char16_t>((c << 8) | (c >> 8));
		}
	}
	return units;
}


/*	-rangeOfString:<target> options:0 range:<from to end>.location, NSNotFound if absent: literal
	units, except that an occurrence a sequence-extending unit follows is inside a longer composed
	sequence and does not count, and that a search starting inside a composed sequence (not at
	the start of the string) cannot match at the first unit after it (oo::str::Scanner has the
	same rule, probed on gnustep-base 1.31.1). <target> is ASCII.
*/
NSUInteger FindUnits(const OOUnits &string, std::u16string_view target, NSUInteger from)
{
	NSUInteger blind = NSNotFound;
	if (from > 0 && from < string.size() && oo::str::detail::extendsSequence(string[from]))
	{
		blind = from;
		while (blind < string.size() && oo::str::detail::extendsSequence(string[blind]))  blind++;
	}
	for (NSUInteger at = from; at + target.size() <= string.size(); at++)
	{
		if (at == blind || std::u16string_view(string).substr(at, target.size()) != target)  continue;
		const NSUInteger end = at + target.size();
		if (end < string.size() && oo::str::detail::extendsSequence(string[end]))  continue;
		return at;
	}
	return NSNotFound;
}


// -hasPrefix: / -hasSuffix: (literal) with a non-empty ASCII argument.
bool HasPrefix(const OOUnits &string, std::u16string_view prefix)
{
	return string.size() >= prefix.size() && std::u16string_view(string).substr(0, prefix.size()) == prefix;
}


bool HasSuffix(const OOUnits &string, std::u16string_view suffix)
{
	return string.size() >= suffix.size() && std::u16string_view(string).substr(string.size() - suffix.size()) == suffix;
}


void SyntaxIssue(OOStringExpansionContext *context, const char *function, const char *fileName, NSUInteger line, const char *logMessageClass, const char *prefix, const char *format, ...)
{
	OOCParameterAssert(context != NULL);

	va_list args;
	va_start(args, format);
	const std::string message = oo::str::vformat(format, args);
	va_end(args);

	// Logging and the JavaScript engine call sites are not migrated here: the formatted text is handed on.
	if (oo::log::willDisplay(logMessageClass))
	{
		if (context->isJavaScript)
		{
			/*	NOTE: syntax errors are reported as warnings when called from JS
				because we don't want to start throwing exceptions when the old
				expander didn't.
			*/
			ooscript::Context jsc = OOJSAcquireContext();
			ReportJavaScriptWarning(jsc, "%s", message.c_str());
			OOJSRelinquishContext(jsc);
		}
		else
		{
			oo::log::logger().write(logMessageClass, function, fileName, line, std::string(prefix) + message);
		}
	}
}


// cxx_OOJSReportWarningWithArguments with a printf format and its arguments (the engine's va_list entry).
void ReportJavaScriptWarning(ooscript::Context jsc, const char *format, ...)
{
	va_list args;
	va_start(args, format);
	cxx_OOJSReportWarningWithArguments(jsc, format, args);
	va_end(args);
}

}	// namespace
