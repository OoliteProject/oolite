/*

OOStringParsing.mm

Oolite
Copyright (C) 2004-2013 Giles C Williams and contributors

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

#include "OOStringParsing.h"
#include "OOLogging.h"
#include "legacy_random.h"
#include "Universe.h"
#include "PlayerEntity.h"
#include "PlayerEntityLegacyScriptEngine.h"
#include "OOFunctionAttributes.h"
#include "ResourceManager.h"
#include "HeadUpDisplay.h"

#include "OOJavaScriptEngine.h"
#include "OOJSEngineTimeManagement.h"

#include "ooscript/JSEngine.hpp"
#include "oofnd/Scanner.hpp"
#include "oofnd/String.hpp"

/*
	OOStringFromDeciCredits below is retargeted onto the ooscript façade (JSEngine.hpp), the
	same call-site pattern OOJSVector.mm (bead oo-sdz) established: the small set of directly
	spelled engine calls it makes (retrieving and restoring a pending exception, looking a
	method up by id, the numeric-conversion call, and invoking a function value) become the
	façade's equivalents, taking and returning the façade's own Context/Object/Value/PropertyId
	types directly, while the OOJS_* helpers stay exactly as they were.
*/

namespace ooscript { }
using ooscript::Context;
using ooscript::Object;
using ooscript::Value;
using ooscript::PropertyId;



BOOL cxx_ScanVectorFromString(const std::optional<std::string> &xyzString, Vector *outVector)
{
	GLfloat					xyz[] = {0.0, 0.0, 0.0};
	int						i = 0;
	const char				*error = nullptr;

	assert(outVector != NULL);
	if (!xyzString.has_value()) return NO;

	oo::str::Scanner		scanner(*xyzString);
	while (!scanner.isAtEnd() && i < 3 && !error)
	{
		if (!scanner.scanFloat(&xyz[i++]))  error = "could not scan a float value.";
	}

	if (!error && i < 3)  error = "found less than three float values.";

	if (!error)
	{
		*outVector = make_vector(xyz[0], xyz[1], xyz[2]);
		return YES;
	}
	else
	{
		 OO_LOG_ERR("strings.conversion.vector", "cannot make vector from '{}': {}", *xyzString, error);
		 return NO;
	}
}

BOOL cxx_ScanHPVectorFromString(const std::optional<std::string> &xyzString, HPVector *outVector)
{
	Vector scanVector;
	assert(outVector != NULL);
	BOOL result = cxx_ScanVectorFromString(xyzString, &scanVector);
	if (!result)
	{
		return NO;
	}
	*outVector = vectorToHPVector(scanVector);
	return YES;
}

BOOL cxx_ScanQuaternionFromString(const std::optional<std::string> &wxyzString, Quaternion *outQuaternion)
{
	GLfloat					wxyz[] = {1.0, 0.0, 0.0, 0.0};
	int						i = 0;
	const char				*error = nullptr;

	assert(outQuaternion != NULL);
	if (!wxyzString.has_value()) return NO;

	oo::str::Scanner		scanner(*wxyzString);
	while (!scanner.isAtEnd() && i < 4 && !error)
	{
		if (!scanner.scanFloat(&wxyz[i++]))  error = "could not scan a float value.";
	}

	if (!error && i < 4)  error = "found less than four float values.";

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
		OO_LOG_ERR("strings.conversion.quaternion", "cannot make quaternion from '{}': {}", *wxyzString, error);
		return NO;
	}
}


BOOL cxx_ScanVectorAndQuaternionFromString(const std::optional<std::string> &xyzwxyzString, Vector *outVector, Quaternion *outQuaternion)
{
	GLfloat					xyzwxyz[] = { 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0};
	int						i = 0;
	const char				*error = nullptr;

	assert(outVector != NULL && outQuaternion != NULL);
	if (!xyzwxyzString.has_value()) return NO;

	oo::str::Scanner		scanner(*xyzwxyzString);
	while (!scanner.isAtEnd() && i < 7 && !error)
	{
		if (!scanner.scanFloat(&xyzwxyz[i++]))  error = "Could not scan a float value.";
	}

	if (!error && i < 7)  error = "Found less than seven float values.";

	if (error)
	{
		OO_LOG_ERR("strings.conversion.quaternion", "cannot make vector and quaternion from '{}': {}", *xyzwxyzString, error);
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


Vector cxx_VectorFromString(const std::optional<std::string> &xyzString, Vector defaultValue)
{
	Vector result;
	if (!cxx_ScanVectorFromString(xyzString, &result))  result = defaultValue;
	return result;
}


Quaternion cxx_QuaternionFromString(const std::optional<std::string> &wxyzString, Quaternion defaultValue)
{
	Quaternion result;
	if (!cxx_ScanQuaternionFromString(wxyzString, &result))  result = defaultValue;
	return result;
}


std::string cxx_StringFromPoint(NSPoint point)
{
	return oo::str::format("%f %f", point.x, point.y);
}


NSPoint cxx_PointFromString(const std::string &xyString)
{
	const std::vector<std::string> tokens = oo::str::tokens(xyString);
	NSPoint		result = NSZeroPoint;

	if (tokens.size() == 2)
	{
		result.x = oo::str::doubleValue(tokens[0]);
		result.y = oo::str::doubleValue(tokens[1]);
	}
	return result;
}


Random_Seed cxx_RandomSeedFromString(const std::optional<std::string> &abcdefString)
{
	Random_Seed				result;
	int						abcdef[] = { 0, 0, 0, 0, 0, 0};
	int						i = 0;
	const char				*error = nullptr;
	oo::str::Scanner		scanner(abcdefString.value_or(""));	// a nil string scans as an empty one (proposed ADR-0039)

	while (!scanner.isAtEnd() && i < 6 && !error)
	{
		if (!scanner.scanInt(&abcdef[i++]))  error = "could not scan a int value.";
	}

	if (!error && i < 6)  error = "found less than six int values.";

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
		OO_LOG_ERR("strings.conversion.randomSeed", "cannot make Random_Seed from '{}': {}", abcdefString.value_or("(null)"), error);
		result = kNilRandomSeed;
	}

	return result;
}


std::string cxx_StringFromRandomSeed(Random_Seed seed)
{
	return oo::str::format("%d %d %d %d %d %d", seed.a, seed.b, seed.c, seed.d, seed.e, seed.f);
}


std::string cxx_OOPadStringToEms(const std::string &string, float padEms)
{
	std::string		result = string;
	float numEms = padEms - cxx_OOStringWidthInEm(result);
	if (numEms>0)
	{
		numEms /= cxx_OOStringWidthInEm(" "); // start with wide space
		result = std::string((NSUInteger)numEms, ' ') + result;
	}
	// most of the way there, so switch to narrow space
	numEms = padEms - cxx_OOStringWidthInEm(result);
	if (numEms>0)
	{
		numEms /= cxx_OOStringWidthInEm("\037"); // 037 is narrow space
		result = std::string((NSUInteger)numEms, '\037') + result;
	}
	return result;
}


std::string cxx_OOStringFromDeciCredits(OOCreditsQuantity tenthsOfCredits, BOOL includeDecimal, BOOL includeSymbol)
{
	ooscript::Context context = OOJSAcquireContext();
	ooscript::Object global = OOJavaScriptEngine::sharedEngine()->globalObject();
	ooscript::Value				method;
	ooscript::Value				rval;
	std::optional<std::string>	result;
	ooscript::Value				exception;
	BOOL				hadException;

	/*	Because the |cr etc. formatting operators call this, and the
		implementation may use string expansion, we need to ensure recursion
		can't happen.
	*/
	static BOOL reentrancyLock;
	if (reentrancyLock)  return oo::str::format("%0.1f", tenthsOfCredits * 0.1);

	reentrancyLock = YES;

	hadException = ooscript::getPendingException((context), (&exception));
	ooscript::clearPendingException((context));

	{
		Object fakeRootFacade = NULL;
		if (ooscript::getMethodById((context), (global), OOJSID("formatCredits"), &fakeRootFacade, (&method)))
		{
			ooscript::Value args[3];
			if (ooscript::newNumberValue((context), tenthsOfCredits * 0.1, (&args[0])))
			{
				args[1] = OOJSValueFromBOOL(includeDecimal);
				args[2] = OOJSValueFromBOOL(includeSymbol);

				OOJSStartTimeLimiter();
				ooscript::callFunctionValue((context), (global), (method), 3, (args), (&rval));
				OOJSStopTimeLimiter();

				// nullopt (was nil) for null or undefined
				result = cxx_OOStringFromJSValue(context, rval);
			}
		}
	}

	if (hadException)  ooscript::setPendingException((context), (exception));

	OOJSRelinquishContext(context);

	if (EXPECT_NOT(!result.has_value()))  result = oo::str::format("%li", (long)(tenthsOfCredits) / 10);

	reentrancyLock = NO;

	return *result;
}


std::vector<unsigned> cxx_ComponentsFromVersionString(const std::string &string)
{
	return oo::str::versionComponents(string);
}


OOComparisonResult cxx_CompareVersions(const std::vector<unsigned> &version1, const std::vector<unsigned> &version2)
{
	const int order = oo::str::compareVersions(version1, version2);
	if (order < 0) return OOOrderedAscending;
	if (order > 0) return OOOrderedDescending;
	return OOOrderedSame;
}


std::string cxx_ClockToString(double clock, BOOL adjusting)
{
	int				days, hrs, mins, secs;
	std::string		format;

	days = floor(clock / 86400.0);
	secs = floor(clock - days * 86400.0);
	hrs = floor(secs / 3600.0);
	secs %= 3600;
	mins = floor(secs / 60.0);
	secs %= 60;

	// DESC() (Universe) is unmigrated: convert at the call. The format is read at run time.
	if (adjusting)  format = OO_DESC("clock-format-adjusting");
	else  format = OO_DESC("clock-format");

	return oo::str::formatRuntime(format, {days, hrs, mins, secs});
}


#if DEBUG_GRAPHVIZ

std::string cxx_EscapedGraphVizString(const std::string &string)
{
	const char * const srcStrings[] =
	{
		//Note: backslash must be first.
		"\\", "\"", "\'", "\r", "\n", "\t", nullptr
	};
	const char * const subStrings[] =
	{
		//Note: must be same order.
		"\\\\", "\\\"", "\\\'", "\\r", "\\n", "\\t", nullptr
	};

	const char * const *	src = srcStrings;
	const char * const *	sub = subStrings;
	std::string				result = string;

	while (*src != nullptr)
	{
		// -replaceOccurrencesOfString:withString:options:0 range:(the whole string)
		result = oo::str::replaceOccurrences(result, *src++, *sub++);
	}

	return result;
}


namespace {

// The GraphViz keywords, matched case-insensitively (-lowercaseString).
constexpr std::string_view kGraphVizKeywords[] = { "node", "edge", "graph", "digraph", "subgraph", "strict" };

BOOL NameIsTaken(const std::string &name, const std::set<std::string> *uniqueSet)
{
	if (uniqueSet != nullptr && uniqueSet->contains(name))  return YES;

	const std::string lowercaseName = oo::str::lowercase(name);
	for (std::string_view keyword : kGraphVizKeywords)
	{
		if (lowercaseName == keyword)  return YES;
	}
	return NO;
}

} // namespace

std::string cxx_GraphVizTokenString(const std::string &string, std::set<std::string> *uniqueSet)
{
	std::string token;
	BOOL lastWasUnderscore = NO;
	// UTF-16 units, as -characterAtIndex: read them
	const std::u16string units = oo::utf8ToUtf16(string);
	std::size_t i, length = units.size();
	std::u16string result;
	result.reserve(length);

	if (length > 0)
	{
		// Special case for first char - can't be digit.
		char16_t c = units[0];
		if (!isalpha(c))
		{
			c = '_';
			lastWasUnderscore = YES;
		}
		result.push_back(c);

		for (i = 1; i < length; i++)
		{
			c = units[i];
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

			result.push_back(c);
		}

		token = oo::utf16ToUtf8(result);
	}
	else
	{
		token = "_";
	}

	if (NameIsTaken(token, uniqueSet))
	{
		if (!lastWasUnderscore)  token += "_";
		std::string uniqueToken;
		unsigned uniqueID = 2;

		for (;;)
		{
			uniqueToken = oo::str::format("%s%u", token.c_str(), uniqueID);
			if (!NameIsTaken(uniqueToken, uniqueSet))  break;
		}
		token = uniqueToken;
	}
	if (uniqueSet != nullptr)  uniqueSet->insert(token);

	return token;
}

#endif //DEBUG_GRAPHVIZ
