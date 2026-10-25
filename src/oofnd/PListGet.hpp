/*	oofnd/PListGet.hpp
	oo::PList::get<T>(key, fallback) and oo::PList::at<T>(index, fallback): the typed, defaulted
	accessor that replaces OOCollectionExtractors (`-oo_<type>ForKey:defaultValue:` and
	`-oo_<type>AtIndex:defaultValue:`), with the SAME conversions. Proposed ADR-0031.

	    Objective-C (OOCollectionExtractors)                  oo::PList
	    ----------------------------------------------------  -------------------------------------------
	    [d oo_floatForKey:@"k" defaultValue:1.0f]             d.get<float>("k", 1.0f)
	    [d oo_floatForKey:@"k"]                               d.get<float>("k")             (fallback 0)
	    [a oo_intAtIndex:3 defaultValue:-1]                   a.at<int>(3, -1)
	    char short int long long long, unsigned ...           the same C++ type (clamped exactly as the
	                                                          OO<Type>FromObject functions clamp)
	    NSInteger / NSUInteger                                long long / unsigned long long (Windows)
	    oo_boolForKey (BOOL)                                  get<bool>
	    oo_nonNegativeFloatForKey / ...DoubleForKey           get<oo::NonNegative<float>> / <double>
	    oo_stringForKey (NSString *)                          get<std::string>   (fallback "", not nil)
	    oo_objectForKey (id)                                  get<oo::PList>          -> const PList*
	    oo_arrayForKey / oo_dictionaryForKey / oo_dataForKey  get<PList::Array> / <PList::Dict> /
	                                                          <PList::Data>           -> const PList*
	    oo_setForKey, vector/quaternion, fuzzy boolean        not here: no PList kind (NSSet) or a game
	                                                          type; the game specialises oo::PListGet<T>

	While the game still holds NSDictionary/NSArray, call sites use the zero-copy bridge
	oo::PListView (src/Core/OOPListView.h) whose get<T>/at<T> have this signature; see
	src/oofnd/README.md "Migrating oo_*ForKey".

	Semantics, each pinned by tests/unit/oofnd/test_plist_get.cpp against values captured from
	OOCollectionExtractors.mm running on GNUstep base 1.31.1 (the build the game links):

	  * A missing key (or index out of range) gives the fallback. So does a value of a kind the
	    conversion does not accept (a dict where a number is wanted, ...): OO<Type>FromObject asks
	    -respondsToSelector:, and only NSString and NSNumber respond.
	  * `get` on a null PList returns the zero of the result type, NOT the fallback: it is the
	    translation of messaging nil (`[nil oo_floatForKey:k defaultValue:1]` is 0).
	  * Numbers (bool / integer / real) convert as NSNumber does: C casts, with a real outside the
	    int64 range (or NaN) giving INT64_MIN as x86-64's cvttsd2si does, and the unsigned reading
	    of a real reproducing GNUstep's compiled code (see realToUnsigned below).
	  * Strings convert as GNUstep's NSString does: -longLongValue / -intValue read optional ASCII
	    space, a sign and at most 20 sign+digit characters then saturate (strtoll / strtol, so
	    `long` is 32-bit on Windows); -doubleValue is NSScanner's own scanner (Unicode whitespace
	    skipped, 18 significant digits kept, excess integer digits dropped WITHOUT rescaling:
	    "9223372036854775807" reads as 9.2233720368547758e17; an exponent over 511 is no number).
	    The unsigned 64-bit reading of a string is its -intValue, sign-extended ("5000000000" gives
	    2147483647), because NSString answers no unsigned selector.
	  * float/double from a string: a result of zero counts only when the string "is zero" (after
	    spaces and tabs, a '0'); otherwise the fallback ("abc", "-0" and "1e-50"-as-float give the
	    fallback). Non-negative variants skip that test and clamp at +0 (NaN and -0 too, as the
	    game's -O2 fmax does), but return a negative fallback unclamped.
	  * bool from a string: yes/true/on (ASCII, any case) or a non-zero -doubleValue is true;
	    no/false/off or a zero string is false; anything else is the fallback.
	  * string from a number: NSNumber -stringValue ("%lld"/"%llu", reals "%0.16g", bools "1"/"0").

	Integer types dispatch by size and signedness: a 64-bit signed type reads OOLongLongFromObject,
	a 64-bit unsigned type OOUnsignedLongLongFromObject, and anything narrower clamps the long long
	reading into its own range. That is exact on Windows (LLP64), the only platform today
	(ADR-0017). On LP64, Oolite's `unsigned long` accessor aliased the SIGNED reading; revisit when
	Linux returns (Phase 5).
*/

#ifndef OOFND_PLISTGET_HPP
#define OOFND_PLISTGET_HPP

// OOCocoa.h's `#define true 1` / `#define false 0` are suspended for this header (ADR-0028).
#pragma push_macro("true")
#pragma push_macro("false")
#undef true
#undef false

#include "oofnd/PList.hpp"

#include <array>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <limits>
#include <string>
#include <string_view>
#include <type_traits>

namespace oo {

// Tag: read a float/double and clamp it at zero (oo_nonNegativeFloatForKey and friends).
template <class F>
	requires std::floating_point<F>
struct NonNegative
{
};

namespace plist_get {

// --- GNUstep's NSString conversions ----------------------------------------------------------

// isspace() in the C locale: what GSString's intBuf_c/intBuf_u skip before a number.
constexpr bool isCSpace(char16_t c) noexcept { return c == u' ' || (c >= u'\t' && c <= u'\r'); }

// +[NSCharacterSet whitespaceAndNewlineCharacterSet] in GNUstep 1.31.1 (probed over the BMP):
// NSScanner's default skip set, so what -doubleValue skips.
constexpr bool isScannerWhitespace(char16_t c) noexcept
{
	return (c >= 0x09 && c <= 0x0D) || c == 0x20 || c == 0x85 || c == 0xA0 || c == 0x1680 || (c >= 0x2000 && c <= 0x200B)
		   || c == 0x2028 || c == 0x2029 || c == 0x202F || c == 0x205F || c == 0x3000;
}

// GSString.m intBuf_*: optional C spaces, an optional sign, then decimal digits while the buffer
// (sign included) holds fewer than 20 characters.
inline std::string intBuf(std::u16string_view s)
{
	std::string buf;
	std::size_t i = 0;
	while (i < s.size() && isCSpace(s[i])) ++i;
	if (i < s.size() && (s[i] == u'+' || s[i] == u'-')) buf += static_cast<char>(s[i++]);
	while (i < s.size() && buf.size() < 20 && s[i] >= u'0' && s[i] <= u'9') buf += static_cast<char>(s[i++]);
	return buf;
}

// strtoll()/strtol() of an intBuf: sign, digits, saturating at the type's range.
template <class I>
I saturatingParse(std::string_view buf) noexcept
{
	bool negative = false;
	std::size_t i = 0;
	if (i < buf.size() && (buf[i] == '+' || buf[i] == '-')) negative = buf[i++] == '-';
	const std::uint64_t limit = negative ? static_cast<std::uint64_t>(std::numeric_limits<I>::max()) + 1u
										 : static_cast<std::uint64_t>(std::numeric_limits<I>::max());
	std::uint64_t magnitude = 0;
	for (; i < buf.size(); ++i)
	{
		const unsigned digit = static_cast<unsigned>(buf[i] - '0');
		if (magnitude > (limit - digit) / 10)
		{
			magnitude = limit;
			break;
		}
		magnitude = magnitude * 10 + digit;
	}
	if (!negative) return static_cast<I>(magnitude);
	return magnitude == 0 ? I(0) : static_cast<I>(-static_cast<I>(magnitude - 1) - 1);
}

// -[GSString longLongValue] / -intValue (strtol: `long`, then the int conversion).
inline long long longLongValue(std::u16string_view s) noexcept { return saturatingParse<long long>(intBuf(s)); }
inline int intValue(std::u16string_view s) noexcept { return static_cast<int>(saturatingParse<long>(intBuf(s))); }

// -[NSScanner scanDouble:] (NSScanner.m), GNUstep 1.31.1, ported statement for statement, from
// scan location <location>; on success <location> is past the number (oo::str::Scanner).
inline bool scanDoubleAt(std::u16string_view s, std::size_t& location, double* value) noexcept
{
	static constexpr double powersOf10[] = {1.0e1, 1.0e2, 1.0e4, 1.0e8, 1.0e16, 1.0e32, 1.0e64, 1.0e128, 1.0e256};
	const std::size_t length = s.size();
	std::size_t loc = location;
	while (loc < length && isScannerWhitespace(s[loc])) ++loc;
	if (loc >= length) return false;

	bool negativeMantissa = false;
	if (s[loc] == u'+') ++loc;
	else if (s[loc] == u'-')
	{
		++loc;
		negativeMantissa = true;
	}
	if (loc >= length) return false;

	// Leading zeros are dropped (counted in `shift` after the point); at most 19 digits are kept,
	// then 18 are used. Digits past the 19th are skipped without moving the decimal point.
	char mantissa[20];
	int mantissaLength = 0;
	int dotPos = -1;
	unsigned shift = 0;
	bool mantissaDigit = false;
	for (; loc < length; ++loc)
	{
		const char16_t c = s[loc];
		if (c < u'0' || c > u'9')
		{
			if (dotPos >= 0) break;
			if (c == u'.') dotPos = mantissaLength;
			else break;
		}
		else
		{
			mantissaDigit = true;
			if (mantissaLength == 0 && c == u'0')
			{
				if (dotPos >= 0) ++shift;
			}
			else if (mantissaLength < 19)
			{
				mantissa[mantissaLength++] = static_cast<char>(c);
			}
		}
	}
	if (!mantissaDigit) return false;
	if (mantissaLength > 18) mantissaLength = 18;
	if (dotPos < 0) dotPos = mantissaLength;
	dotPos -= mantissaLength;

	int hi = 0;
	int lo = 0;
	const char* ptr = mantissa;
	for (; mantissaLength > 9; --mantissaLength) hi = hi * 10 + (*ptr++ - '0');
	for (; mantissaLength > 0; --mantissaLength) lo = lo * 10 + (*ptr++ - '0');
	double result = (1.0e9 * hi) + lo;

	// The exponent accumulates in an int; GNUstep lets it wrap, so it wraps here too (unsigned
	// arithmetic, then the two's-complement conversion C++20 defines).
	std::uint32_t exponentBits = 0;
	bool negativeExponent = false;
	if (loc < length && (s[loc] == u'e' || s[loc] == u'E'))
	{
		const std::size_t saveExpLoc = loc;
		++loc;
		if (loc >= length)
		{
			loc = saveExpLoc;
		}
		else
		{
			if (s[loc] == u'+') ++loc;
			else if (s[loc] == u'-')
			{
				++loc;
				negativeExponent = true;
			}
			if (loc >= length || s[loc] < u'0' || s[loc] > u'9')
			{
				loc = saveExpLoc;   // no exponent (negativeExponent may stay set: harmless, it is 0)
			}
			else
			{
				while (loc < length && s[loc] >= u'0' && s[loc] <= u'9')
				{
					exponentBits = exponentBits * 10u + static_cast<std::uint32_t>(s[loc] - u'0');
					++loc;
				}
			}
		}
	}
	const std::uint32_t dotBits = static_cast<std::uint32_t>(dotPos);
	std::uint32_t adjusted = negativeExponent ? dotBits - exponentBits : dotBits + exponentBits;
	adjusted -= shift;
	int exponent = static_cast<int>(adjusted);
	if (exponent == std::numeric_limits<int>::min()) return false;   // GNUstep: -INT_MIN, then UB
	if (exponent < 0)
	{
		negativeExponent = true;
		exponent = -exponent;
	}
	else
	{
		negativeExponent = false;
	}
	if (exponent > 511) return false;

	double e = 1.0;
	for (const double* d = powersOf10; exponent != 0; exponent >>= 1, ++d)
	{
		if (exponent & 1) e *= *d;
	}
	result = negativeExponent ? result / e : result * e;
	if (value != nullptr) *value = negativeMantissa ? -result : result;
	location = loc;
	return true;
}

inline bool scanDouble(std::u16string_view s, double* value) noexcept
{
	std::size_t location = 0;
	return scanDoubleAt(s, location, value);
}

// -[NSString doubleValue]: 0.0 when nothing scans.
inline double doubleValue(std::u16string_view s) noexcept
{
	double d = 0.0;
	scanDouble(s, &d);
	return d;
}

// OOCollectionExtractors' IsZeroString: after spaces and tabs, a '0'. (Its "optional minus"
// line tests for ' ' instead of '-', so "-0" is NOT a zero string; reproduced.)
inline bool isZeroString(std::u16string_view s) noexcept
{
	std::size_t i = 0;
	while (i < s.size() && (s[i] == u' ' || s[i] == u'\t')) ++i;
	return i < s.size() && s[i] == u'0';
}

// -caseInsensitiveCompare: == NSOrderedSame against an ASCII word.
inline bool equalsIgnoringCase(std::u16string_view s, std::string_view word) noexcept
{
	if (s.size() != word.size()) return false;
	for (std::size_t i = 0; i < s.size(); ++i)
	{
		char16_t c = s[i];
		if (c >= u'A' && c <= u'Z') c = static_cast<char16_t>(c - u'A' + u'a');
		if (c != static_cast<unsigned char>(word[i])) return false;
	}
	return true;
}

// --- NSNumber's conversions of a real (x86-64 code generation, captured) ---------------------

// (long long)d as cvttsd2si computes it: INT64_MIN for NaN and anything out of range.
inline std::int64_t realToSigned(double d) noexcept
{
	if (std::isnan(d) || d >= 9223372036854775808.0 || d < -9223372036854775808.0) return std::numeric_limits<std::int64_t>::min();
	return static_cast<std::int64_t>(d);
}

// (unsigned long long)d as GNUstep's compiled -unsignedLongLongValue computes it (captured:
// -1.5 -> 2^64-1, 1e19 -> 1e19, 2^64 and NaN -> 2^63).
inline std::uint64_t realToUnsigned(double d) noexcept
{
	const std::uint64_t a = static_cast<std::uint64_t>(realToSigned(d));
	const std::uint64_t b = static_cast<std::uint64_t>(realToSigned(d - 9223372036854775808.0));
	return a | (b & (0u - (a >> 63)));
}

// --- OOCollectionExtractors' OO*FromObject over a PList value (nullptr = nil) -----------------

inline long long longLongFrom(const PList* v, long long fallback) noexcept
{
	if (v == nullptr) return fallback;
	if (const bool* b = v->getIf<bool>()) return *b ? 1 : 0;
	if (const PList::Integer* i = v->getIf<PList::Integer>()) return i->value;
	if (const double* d = v->getIf<double>()) return realToSigned(*d);
	if (const std::string* s = v->getIf<std::string>()) return longLongValue(utf8ToUtf16(*s));
	return fallback;
}

inline unsigned long long unsignedLongLongFrom(const PList* v, unsigned long long fallback) noexcept
{
	if (v == nullptr) return fallback;
	if (const bool* b = v->getIf<bool>()) return *b ? 1u : 0u;
	if (const PList::Integer* i = v->getIf<PList::Integer>()) return i->unsignedValue();
	if (const double* d = v->getIf<double>()) return realToUnsigned(*d);
	if (const std::string* s = v->getIf<std::string>())
	{
		return static_cast<unsigned long long>(static_cast<long long>(intValue(utf8ToUtf16(*s))));
	}
	return fallback;
}

inline bool boolFrom(const PList* v, bool fallback) noexcept
{
	if (v == nullptr) return fallback;
	if (const std::string* s = v->getIf<std::string>())
	{
		const std::u16string u = utf8ToUtf16(*s);
		if (equalsIgnoringCase(u, "yes") || equalsIgnoringCase(u, "true") || equalsIgnoringCase(u, "on") || doubleValue(u) != 0.0)
		{
			return true;
		}
		if (equalsIgnoringCase(u, "no") || equalsIgnoringCase(u, "false") || equalsIgnoringCase(u, "off") || isZeroString(u))
		{
			return false;
		}
		return fallback;
	}
	if (v->isNumber()) return v->boolValue();
	return fallback;
}

// NSNumber -floatValue: a C cast from the stored type (an integer converts straight to float).
inline float numberFloatValue(const PList& v) noexcept
{
	if (const PList::Integer* i = v.getIf<PList::Integer>())
	{
		return i->isUnsigned ? static_cast<float>(i->unsignedValue()) : static_cast<float>(i->value);
	}
	return static_cast<float>(v.doubleValue());
}

template <class F>
F realFrom(const PList* v, F fallback) noexcept
{
	if (v == nullptr) return fallback;
	if (v->isNumber())
	{
		if constexpr (std::is_same_v<F, float>) return numberFloatValue(*v);
		else return v->doubleValue();
	}
	if (const std::string* s = v->getIf<std::string>())
	{
		const std::u16string u = utf8ToUtf16(*s);
		const F result = static_cast<F>(doubleValue(u));
		return (result == F(0) && !isZeroString(u)) ? fallback : result;
	}
	return fallback;
}

template <class F>
F nonNegativeRealFrom(const PList* v, F fallback) noexcept
{
	F result;
	if (v != nullptr && v->isNumber())
	{
		if constexpr (std::is_same_v<F, float>) result = numberFloatValue(*v);
		else result = v->doubleValue();
	}
	else if (const std::string* s = (v != nullptr) ? v->getIf<std::string>() : nullptr)
	{
		result = static_cast<F>(doubleValue(utf8ToUtf16(*s)));
	}
	else
	{
		return fallback;   // the fallback is not clamped
	}
	// fmax(result, 0) as the game's -O2 build evaluates it (captured): NaN and -0 give +0. (An -O0
	// build's library fmaxf keeps -0; the sign of fmax(-0, +0) is unspecified, so it is spelled out.)
	return (result > F(0)) ? result : F(0);
}

// --- OOCollectionExtractors' game-type forms, without the game (bead oo-9ftb) --------------------
//
// OOVectorFromObject / OOHPVectorFromObject / OOQuaternionFromObject read N numbers: from an array
// of exactly N elements (element i as -oo_floatAtIndex:i / -oo_doubleAtIndex:i did, realFrom with
// fallback 0), or from a dictionary that holds at least one of the N keys (each key's value as
// get<F>(key, 0.0) did: a missing key is 0, not the default's component). A string is scanned by
// the game (Scan*FromString, which logs a malformed one) and an object may be the game's native
// vector, so those two are reported, not read; anything else leaves the default. A null element or
// value counts as absent, as oo::ObjectFromPList dropped them before the Foundation functions saw
// the collection. keys name the components in out's order (x y z; w x y z for a quaternion).
enum class TupleSource
{
	none,			// keep the default
	components,		// out holds the N components
	string,			// the caller scans the string
	object			// the caller looks at the object (the game's native vector)
};

template <class F, std::size_t N>
TupleSource tupleFrom(const PList* v, const std::array<std::string_view, N>& keys, std::array<F, N>& out) noexcept
{
	if (v == nullptr) return TupleSource::none;
	if (v->isString()) return TupleSource::string;
	if (v->isObject()) return TupleSource::object;
	if (const PList::Array* array = v->getIf<PList::Array>())
	{
		std::array<const PList*, N> elements{};
		std::size_t count = 0;
		for (const PList& element : *array)
		{
			if (element.isNull()) continue;
			if (count == N) return TupleSource::none;   // more than N: -count != N
			elements[count++] = &element;
		}
		if (count != N) return TupleSource::none;
		for (std::size_t i = 0; i < N; ++i) out[i] = realFrom<F>(elements[i], F(0));
		return TupleSource::components;
	}
	if (v->getIf<PList::Dict>() != nullptr)
	{
		std::array<const PList*, N> values{};
		bool any = false;
		for (std::size_t i = 0; i < N; ++i)
		{
			const PList* value = v->find(keys[i]);
			if (value != nullptr && value->isNull()) value = nullptr;
			values[i] = value;
			any = any || value != nullptr;
		}
		if (!any) return TupleSource::none;
		for (std::size_t i = 0; i < N; ++i) out[i] = realFrom<F>(values[i], F(0));
		return TupleSource::components;
	}
	return TupleSource::none;
}

// OOPropertyListFromVector / HPVector / Quaternion: a dictionary of the components under keys,
// each +numberWithFloat: (a single-precision real) or +numberWithDouble:.
template <class F, std::size_t N>
PList tuplePList(const std::array<std::string_view, N>& keys, const std::array<F, N>& values)
{
	static_assert(std::is_same_v<F, float> || std::is_same_v<F, double>);
	PList::Dict dict;
	for (std::size_t i = 0; i < N; ++i)
	{
		if constexpr (std::is_same_v<F, float>) dict.emplace(std::string(keys[i]), PList::singleReal(values[i]));
		else dict.emplace(std::string(keys[i]), PList(values[i]));
	}
	return PList(std::move(dict));
}

// OOFuzzyBooleanFromObject's probability (the game draws randf() < p). A string: its -floatValue;
// when that is 0 for a string that is not a zero string, FuzzyBooleanProbabilityFromString: 1 for
// yes/true/on or a non-zero -doubleValue, 0 for no/false/off or a zero string, else the fallback.
// Anything else: OOFloatFromObject (realFrom<float>).
inline float fuzzyProbabilityFrom(const PList* v, float fallback) noexcept
{
	const std::string* s = (v != nullptr) ? v->getIf<std::string>() : nullptr;
	if (s == nullptr) return realFrom<float>(v, fallback);

	const std::u16string u = utf8ToUtf16(*s);
	const float probability = static_cast<float>(doubleValue(u));
	if (probability != 0.0f || isZeroString(u)) return probability;
	if (equalsIgnoringCase(u, "yes") || equalsIgnoringCase(u, "true") || equalsIgnoringCase(u, "on") || doubleValue(u) != 0.0) return 1.0f;
	if (equalsIgnoringCase(u, "no") || equalsIgnoringCase(u, "false") || equalsIgnoringCase(u, "off") || isZeroString(u)) return 0.0f;
	return fallback;
}

// NSNumber -stringValue.
inline std::string numberStringValue(const PList& v)
{
	char buf[64];
	if (const bool* b = v.getIf<bool>()) return *b ? "1" : "0";
	if (const PList::Integer* i = v.getIf<PList::Integer>())
	{
		if (i->isUnsigned) std::snprintf(buf, sizeof buf, "%llu", static_cast<unsigned long long>(i->unsignedValue()));
		else std::snprintf(buf, sizeof buf, "%lld", static_cast<long long>(i->value));
		return buf;
	}
	const double d = v.doubleValue();
	if (std::isnan(d)) return "nan";
	if (std::isinf(d)) return d < 0 ? "-inf" : "inf";
	if (v.isSinglePrecision()) std::snprintf(buf, sizeof buf, "%0.7g", static_cast<double>(static_cast<float>(d)));   // +numberWithFloat: (captured)
	else std::snprintf(buf, sizeof buf, "%0.16g", d);
	return buf;
}

} // namespace plist_get

// --- the conversions, one specialisation per requested type ----------------------------------
//
// PListGet<T> says what get<T>/at<T> return (Result), what fallback they take (Fallback), what
// the no-fallback form falls back to (defaultFallback, the extractors' `...ForKey:` defaults) and
// how a value converts (from; nullptr = absent). A game type (Vector, Quaternion, ...) joins by
// specialising this template in a game header.

template <class T>
	requires(std::integral<T> && !std::same_as<T, bool>)
struct PListGet<T>
{
	using Result = T;
	using Fallback = T;
	static constexpr T defaultFallback() noexcept { return T(0); }
	static T from(const PList* v, T fallback) noexcept
	{
		if constexpr (sizeof(T) == sizeof(long long) && std::is_signed_v<T>)
		{
			return static_cast<T>(plist_get::longLongFrom(v, fallback));   // OOLongLongFromObject
		}
		else if constexpr (sizeof(T) == sizeof(long long))
		{
			return static_cast<T>(plist_get::unsignedLongLongFrom(v, fallback));   // OOUnsignedLongLongFromObject
		}
		else
		{
			// OO_DEFINE_CLAMP: OOClampInteger(OOLongLongFromObject(v, fallback), MIN, MAX).
			const long long ll = plist_get::longLongFrom(v, static_cast<long long>(fallback));
			const long long lo = static_cast<long long>(std::numeric_limits<T>::min());
			const long long hi = static_cast<long long>(std::numeric_limits<T>::max());
			return static_cast<T>((lo < ll) ? ((ll < hi) ? ll : hi) : lo);
		}
	}
};

template <>
struct PListGet<bool>
{
	using Result = bool;
	using Fallback = bool;
	static constexpr bool defaultFallback() noexcept { return false; }
	static bool from(const PList* v, bool fallback) noexcept { return plist_get::boolFrom(v, fallback); }
};

template <class F>
	requires std::floating_point<F>
struct PListGet<F>
{
	using Result = F;
	using Fallback = F;
	static constexpr F defaultFallback() noexcept { return F(0); }
	static F from(const PList* v, F fallback) noexcept { return plist_get::realFrom<F>(v, fallback); }
};

template <class F>
struct PListGet<NonNegative<F>>
{
	using Result = F;
	using Fallback = F;
	static constexpr F defaultFallback() noexcept { return F(0); }
	static F from(const PList* v, F fallback) noexcept { return plist_get::nonNegativeRealFrom<F>(v, fallback); }
};

// oo_stringForKey: the string itself, or a number's -stringValue. No-fallback form: "" (the
// Objective-C form returned nil, which std::string cannot say; use get<PList> to test presence).
template <>
struct PListGet<std::string>
{
	using Result = std::string;
	using Fallback = std::string;
	static std::string defaultFallback() { return {}; }
	static std::string from(const PList* v, std::string fallback)
	{
		if (v == nullptr) return fallback;
		if (const std::string* s = v->getIf<std::string>()) return *s;
		if (v->isNumber()) return plist_get::numberStringValue(*v);
		return fallback;
	}
};

// oo_objectForKey: any present value.
template <>
struct PListGet<PList>
{
	using Result = const PList*;
	using Fallback = const PList*;
	static constexpr const PList* defaultFallback() noexcept { return nullptr; }
	static const PList* from(const PList* v, const PList* fallback) noexcept { return v != nullptr ? v : fallback; }
};

// oo_arrayForKey / oo_dictionaryForKey / oo_dataForKey / (date): the value if it is of that kind
// (-isKindOfClass:), as the PList node so get/at/count work on it.
template <class K>
	requires(std::same_as<K, PList::Array> || std::same_as<K, PList::Dict> || std::same_as<K, PList::Data>
			 || std::same_as<K, PList::Date>)
struct PListGet<K>
{
	using Result = const PList*;
	using Fallback = const PList*;
	static constexpr const PList* defaultFallback() noexcept { return nullptr; }
	static const PList* from(const PList* v, const PList* fallback) noexcept
	{
		return (v != nullptr && v->getIf<K>() != nullptr) ? v : fallback;
	}
};

// --- PList members (declared in PList.hpp) ---------------------------------------------------

template <class T>
typename PListGet<T>::Result PList::get(std::string_view key, typename PListGet<T>::Fallback fallback) const
{
	if (isNull()) return typename PListGet<T>::Result{};   // messaging nil
	return PListGet<T>::from(find(key), std::move(fallback));
}

template <class T>
typename PListGet<T>::Result PList::get(std::string_view key) const
{
	return get<T>(key, PListGet<T>::defaultFallback());
}

template <class T>
typename PListGet<T>::Result PList::at(std::size_t index, typename PListGet<T>::Fallback fallback) const
{
	if (isNull()) return typename PListGet<T>::Result{};   // messaging nil
	return PListGet<T>::from(at(index), std::move(fallback));
}

template <class T>
typename PListGet<T>::Result PList::at(std::size_t index) const
{
	return at<T>(index, PListGet<T>::defaultFallback());
}

} // namespace oo

#pragma pop_macro("false")
#pragma pop_macro("true")

#endif // OOFND_PLISTGET_HPP
