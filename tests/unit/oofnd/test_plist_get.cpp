/*	test_plist_get.cpp
	oo::PList::get<T> / at<T> (oofnd/PListGet.hpp, bead oo-u77, proposed ADR-0031) against
	OOCollectionExtractors as the game runs it today.

	kCaptured below was printed by a throwaway harness that compiled OOCollectionExtractors.mm
	(OOCOLLECTIONEXTRACTORS_SIMPLE, -O2 as the game builds it) against GNUstep base 1.31.1, and ran
	OO<Type>FromObject on the Foundation object each row names - the object the GNUstep plist
	parsers produce for that PList: nil, NSNumber numberWithBool: (B) / numberWithLongLong: (I) /
	numberWithUnsignedLongLong: (U) / numberWithDouble: (R), NSString (S), and an NSArray,
	NSDictionary, NSData and NSDate. Every row is GNUstep's answer, quirks included; the test asks
	PList::get for the same thing in the same format and requires byte-identical text.

	Fallbacks are 77 for every integer type, NO/YES for bool, 7.5f / 7.25 for float / double,
	-3.5 for the non-negative variants and "D" for strings, so a fallback is always visible.
	meson test --suite oofnd-plist
*/

// Included as Objective-C++ game code includes it, after OOCocoa.h's true/false macros.
#define true						1
#define false						0
#include "oofnd/PListGet.hpp"
static_assert(std::is_same_v<decltype(true), int>, "PListGet.hpp must restore OOCocoa.h's true macro");
static_assert(std::is_same_v<decltype(false), int>, "PListGet.hpp must restore OOCocoa.h's false macro");
#undef true
#undef false

#include "oo_test.hpp"

#include <cmath>
#include <cstdio>
#include <optional>
#include <string>
#include <string_view>

namespace {

using oo::PList;

// Row constructors; nullopt is "no value" (nil).
std::optional<PList> N() { return std::nullopt; }
std::optional<PList> B(bool b) { return PList(b); }
std::optional<PList> I(long long v) { return PList::signedInteger(v); }
std::optional<PList> U(unsigned long long v) { return PList::unsignedInteger(v); }
std::optional<PList> R(double d) { return PList(d); }
std::optional<PList> S(const char* s) { return PList(s); }
std::optional<PList> A() { return PList(PList::Array{PList("1")}); }
std::optional<PList> Dct() { return PList(PList::Dict{{"x", PList("1")}}); }
std::optional<PList> Dat() { return PList(oo::Data::fromString("1")); }
std::optional<PList> Dt() { return PList(PList::Date{5.0}); }

struct Row
{
	std::optional<PList> value;
	const char* expected;
};

// The harness's printf, with each OO<Type>FromObject replaced by the PList::get that retires it.
// `get` is a generic lambda: get.template operator()<T>(fallback) reads the row's value as T.
template <class Get>
std::string results(const Get& get)
{
	char buf[1024];
	const std::string str = get.template operator()<std::string>(std::string("D"));
	std::snprintf(buf, sizeof buf,
				  "ll=%lld ull=%llu i=%d ui=%u c=%d uc=%u s=%d us=%u l=%ld ul=%lu b0=%d b1=%d f=%.9g d=%.17g nf=%.9g nd=%.17g str=%s",
				  get.template operator()<long long>(77LL), get.template operator()<unsigned long long>(77ULL),
				  get.template operator()<int>(77), get.template operator()<unsigned int>(77u),
				  static_cast<int>(get.template operator()<char>(char(77))),
				  static_cast<unsigned>(get.template operator()<unsigned char>(static_cast<unsigned char>(77))),
				  static_cast<int>(get.template operator()<short>(short(77))),
				  static_cast<unsigned>(get.template operator()<unsigned short>(static_cast<unsigned short>(77))),
				  get.template operator()<long>(77L), get.template operator()<unsigned long>(77UL),
				  static_cast<int>(get.template operator()<bool>(false)), static_cast<int>(get.template operator()<bool>(true)),
				  static_cast<double>(get.template operator()<float>(7.5f)), get.template operator()<double>(7.25),
				  static_cast<double>(get.template operator()<oo::NonNegative<float>>(-3.5f)),
				  get.template operator()<oo::NonNegative<double>>(-3.5), str.c_str());
	return buf;
}

// Captured from GNUstep base 1.31.1 (see the banner). Do not edit by hand.
const Row kCaptured[] = {
	{N(), "ll=77 ull=77 i=77 ui=77 c=77 uc=77 s=77 us=77 l=77 ul=77 b0=0 b1=1 f=7.5 d=7.25 nf=-3.5 nd=-3.5 str=D"},
	{B(true), "ll=1 ull=1 i=1 ui=1 c=1 uc=1 s=1 us=1 l=1 ul=1 b0=1 b1=1 f=1 d=1 nf=1 nd=1 str=1"},
	{B(false), "ll=0 ull=0 i=0 ui=0 c=0 uc=0 s=0 us=0 l=0 ul=0 b0=0 b1=0 f=0 d=0 nf=0 nd=0 str=0"},
	{A(), "ll=77 ull=77 i=77 ui=77 c=77 uc=77 s=77 us=77 l=77 ul=77 b0=0 b1=1 f=7.5 d=7.25 nf=-3.5 nd=-3.5 str=D"},
	{Dct(), "ll=77 ull=77 i=77 ui=77 c=77 uc=77 s=77 us=77 l=77 ul=77 b0=0 b1=1 f=7.5 d=7.25 nf=-3.5 nd=-3.5 str=D"},
	{Dat(), "ll=77 ull=77 i=77 ui=77 c=77 uc=77 s=77 us=77 l=77 ul=77 b0=0 b1=1 f=7.5 d=7.25 nf=-3.5 nd=-3.5 str=D"},
	{Dt(), "ll=77 ull=77 i=77 ui=77 c=77 uc=77 s=77 us=77 l=77 ul=77 b0=0 b1=1 f=7.5 d=7.25 nf=-3.5 nd=-3.5 str=D"},
	{S(""), "ll=0 ull=0 i=0 ui=0 c=0 uc=0 s=0 us=0 l=0 ul=0 b0=0 b1=1 f=7.5 d=7.25 nf=0 nd=0 str="},
	{S(" "), "ll=0 ull=0 i=0 ui=0 c=0 uc=0 s=0 us=0 l=0 ul=0 b0=0 b1=1 f=7.5 d=7.25 nf=0 nd=0 str= "},
	{S("0"), "ll=0 ull=0 i=0 ui=0 c=0 uc=0 s=0 us=0 l=0 ul=0 b0=0 b1=0 f=0 d=0 nf=0 nd=0 str=0"},
	{S("00"), "ll=0 ull=0 i=0 ui=0 c=0 uc=0 s=0 us=0 l=0 ul=0 b0=0 b1=0 f=0 d=0 nf=0 nd=0 str=00"},
	{S(" 0"), "ll=0 ull=0 i=0 ui=0 c=0 uc=0 s=0 us=0 l=0 ul=0 b0=0 b1=0 f=0 d=0 nf=0 nd=0 str= 0"},
	{S("\0110"), "ll=0 ull=0 i=0 ui=0 c=0 uc=0 s=0 us=0 l=0 ul=0 b0=0 b1=0 f=0 d=0 nf=0 nd=0 str=\0110"},
	{S("\0120"), "ll=0 ull=0 i=0 ui=0 c=0 uc=0 s=0 us=0 l=0 ul=0 b0=0 b1=1 f=7.5 d=7.25 nf=0 nd=0 str=\0120"},
	{S("\0150"), "ll=0 ull=0 i=0 ui=0 c=0 uc=0 s=0 us=0 l=0 ul=0 b0=0 b1=1 f=7.5 d=7.25 nf=0 nd=0 str=\0150"},
	{S("-0"), "ll=0 ull=0 i=0 ui=0 c=0 uc=0 s=0 us=0 l=0 ul=0 b0=0 b1=1 f=7.5 d=7.25 nf=0 nd=0 str=-0"},
	{S("+0"), "ll=0 ull=0 i=0 ui=0 c=0 uc=0 s=0 us=0 l=0 ul=0 b0=0 b1=1 f=7.5 d=7.25 nf=0 nd=0 str=+0"},
	{S(" -0"), "ll=0 ull=0 i=0 ui=0 c=0 uc=0 s=0 us=0 l=0 ul=0 b0=0 b1=1 f=7.5 d=7.25 nf=0 nd=0 str= -0"},
	{S("0.0"), "ll=0 ull=0 i=0 ui=0 c=0 uc=0 s=0 us=0 l=0 ul=0 b0=0 b1=0 f=0 d=0 nf=0 nd=0 str=0.0"},
	{S("0e5"), "ll=0 ull=0 i=0 ui=0 c=0 uc=0 s=0 us=0 l=0 ul=0 b0=0 b1=0 f=0 d=0 nf=0 nd=0 str=0e5"},
	{S(".5"), "ll=0 ull=0 i=0 ui=0 c=0 uc=0 s=0 us=0 l=0 ul=0 b0=1 b1=1 f=0.5 d=0.5 nf=0.5 nd=0.5 str=.5"},
	{S("-.5"), "ll=0 ull=0 i=0 ui=0 c=0 uc=0 s=0 us=0 l=0 ul=0 b0=1 b1=1 f=-0.5 d=-0.5 nf=0 nd=0 str=-.5"},
	{S("1"), "ll=1 ull=1 i=1 ui=1 c=1 uc=1 s=1 us=1 l=1 ul=1 b0=1 b1=1 f=1 d=1 nf=1 nd=1 str=1"},
	{S("-1"), "ll=-1 ull=18446744073709551615 i=-1 ui=0 c=-1 uc=0 s=-1 us=0 l=-1 ul=0 b0=1 b1=1 f=-1 d=-1 nf=0 nd=0 str=-1"},
	{S("+1"), "ll=1 ull=1 i=1 ui=1 c=1 uc=1 s=1 us=1 l=1 ul=1 b0=1 b1=1 f=1 d=1 nf=1 nd=1 str=+1"},
	{S(" 42"), "ll=42 ull=42 i=42 ui=42 c=42 uc=42 s=42 us=42 l=42 ul=42 b0=1 b1=1 f=42 d=42 nf=42 nd=42 str= 42"},
	{S("\01142"), "ll=42 ull=42 i=42 ui=42 c=42 uc=42 s=42 us=42 l=42 ul=42 b0=1 b1=1 f=42 d=42 nf=42 nd=42 str=\01142"},
	{S("\01242"), "ll=42 ull=42 i=42 ui=42 c=42 uc=42 s=42 us=42 l=42 ul=42 b0=1 b1=1 f=42 d=42 nf=42 nd=42 str=\01242"},
	{S("\01342"), "ll=42 ull=42 i=42 ui=42 c=42 uc=42 s=42 us=42 l=42 ul=42 b0=1 b1=1 f=42 d=42 nf=42 nd=42 str=\01342"},
	{S("\01442"), "ll=42 ull=42 i=42 ui=42 c=42 uc=42 s=42 us=42 l=42 ul=42 b0=1 b1=1 f=42 d=42 nf=42 nd=42 str=\01442"},
	{S("42abc"), "ll=42 ull=42 i=42 ui=42 c=42 uc=42 s=42 us=42 l=42 ul=42 b0=1 b1=1 f=42 d=42 nf=42 nd=42 str=42abc"},
	{S("abc"), "ll=0 ull=0 i=0 ui=0 c=0 uc=0 s=0 us=0 l=0 ul=0 b0=0 b1=1 f=7.5 d=7.25 nf=0 nd=0 str=abc"},
	{S("abc42"), "ll=0 ull=0 i=0 ui=0 c=0 uc=0 s=0 us=0 l=0 ul=0 b0=0 b1=1 f=7.5 d=7.25 nf=0 nd=0 str=abc42"},
	{S("3.7"), "ll=3 ull=3 i=3 ui=3 c=3 uc=3 s=3 us=3 l=3 ul=3 b0=1 b1=1 f=3.70000005 d=3.7000000000000002 nf=3.70000005 nd=3.7000000000000002 str=3.7"},
	{S("-3.7"), "ll=-3 ull=18446744073709551613 i=-3 ui=0 c=-3 uc=0 s=-3 us=0 l=-3 ul=0 b0=1 b1=1 f=-3.70000005 d=-3.7000000000000002 nf=0 nd=0 str=-3.7"},
	{S("3.5"), "ll=3 ull=3 i=3 ui=3 c=3 uc=3 s=3 us=3 l=3 ul=3 b0=1 b1=1 f=3.5 d=3.5 nf=3.5 nd=3.5 str=3.5"},
	{S("2.5"), "ll=2 ull=2 i=2 ui=2 c=2 uc=2 s=2 us=2 l=2 ul=2 b0=1 b1=1 f=2.5 d=2.5 nf=2.5 nd=2.5 str=2.5"},
	{S("-2.5"), "ll=-2 ull=18446744073709551614 i=-2 ui=0 c=-2 uc=0 s=-2 us=0 l=-2 ul=0 b0=1 b1=1 f=-2.5 d=-2.5 nf=0 nd=0 str=-2.5"},
	{S("1e3"), "ll=1 ull=1 i=1 ui=1 c=1 uc=1 s=1 us=1 l=1 ul=1 b0=1 b1=1 f=1000 d=1000 nf=1000 nd=1000 str=1e3"},
	{S("1E3"), "ll=1 ull=1 i=1 ui=1 c=1 uc=1 s=1 us=1 l=1 ul=1 b0=1 b1=1 f=1000 d=1000 nf=1000 nd=1000 str=1E3"},
	{S("1e"), "ll=1 ull=1 i=1 ui=1 c=1 uc=1 s=1 us=1 l=1 ul=1 b0=1 b1=1 f=1 d=1 nf=1 nd=1 str=1e"},
	{S("1e+"), "ll=1 ull=1 i=1 ui=1 c=1 uc=1 s=1 us=1 l=1 ul=1 b0=1 b1=1 f=1 d=1 nf=1 nd=1 str=1e+"},
	{S("1e-2"), "ll=1 ull=1 i=1 ui=1 c=1 uc=1 s=1 us=1 l=1 ul=1 b0=1 b1=1 f=0.00999999978 d=0.01 nf=0.00999999978 nd=0.01 str=1e-2"},
	{S("0x10"), "ll=0 ull=0 i=0 ui=0 c=0 uc=0 s=0 us=0 l=0 ul=0 b0=0 b1=0 f=0 d=0 nf=0 nd=0 str=0x10"},
	{S("0X1A"), "ll=0 ull=0 i=0 ui=0 c=0 uc=0 s=0 us=0 l=0 ul=0 b0=0 b1=0 f=0 d=0 nf=0 nd=0 str=0X1A"},
	{S("010"), "ll=10 ull=10 i=10 ui=10 c=10 uc=10 s=10 us=10 l=10 ul=10 b0=1 b1=1 f=10 d=10 nf=10 nd=10 str=010"},
	{S("2147483647"), "ll=2147483647 ull=2147483647 i=2147483647 ui=2147483647 c=127 uc=255 s=32767 us=65535 l=2147483647 ul=2147483647 b0=1 b1=1 f=2.14748365e+09 d=2147483647 nf=2.14748365e+09 nd=2147483647 str=2147483647"},
	{S("2147483648"), "ll=2147483648 ull=2147483647 i=2147483647 ui=2147483648 c=127 uc=255 s=32767 us=65535 l=2147483647 ul=2147483648 b0=1 b1=1 f=2.14748365e+09 d=2147483648 nf=2.14748365e+09 nd=2147483648 str=2147483648"},
	{S("-2147483648"), "ll=-2147483648 ull=18446744071562067968 i=-2147483648 ui=0 c=-128 uc=0 s=-32768 us=0 l=-2147483648 ul=0 b0=1 b1=1 f=-2.14748365e+09 d=-2147483648 nf=0 nd=0 str=-2147483648"},
	{S("-2147483649"), "ll=-2147483649 ull=18446744071562067968 i=-2147483648 ui=0 c=-128 uc=0 s=-32768 us=0 l=-2147483648 ul=0 b0=1 b1=1 f=-2.14748365e+09 d=-2147483649 nf=0 nd=0 str=-2147483649"},
	{S("4294967295"), "ll=4294967295 ull=2147483647 i=2147483647 ui=4294967295 c=127 uc=255 s=32767 us=65535 l=2147483647 ul=4294967295 b0=1 b1=1 f=4.2949673e+09 d=4294967295 nf=4.2949673e+09 nd=4294967295 str=4294967295"},
	{S("4294967296"), "ll=4294967296 ull=2147483647 i=2147483647 ui=4294967295 c=127 uc=255 s=32767 us=65535 l=2147483647 ul=4294967295 b0=1 b1=1 f=4.2949673e+09 d=4294967296 nf=4.2949673e+09 nd=4294967296 str=4294967296"},
	{S("9223372036854775807"), "ll=9223372036854775807 ull=2147483647 i=2147483647 ui=4294967295 c=127 uc=255 s=32767 us=65535 l=2147483647 ul=4294967295 b0=1 b1=1 f=9.22337217e+17 d=9.2233720368547763e+17 nf=9.22337217e+17 nd=9.2233720368547763e+17 str=9223372036854775807"},
	{S("9223372036854775808"), "ll=9223372036854775807 ull=2147483647 i=2147483647 ui=4294967295 c=127 uc=255 s=32767 us=65535 l=2147483647 ul=4294967295 b0=1 b1=1 f=9.22337217e+17 d=9.2233720368547763e+17 nf=9.22337217e+17 nd=9.2233720368547763e+17 str=9223372036854775808"},
	{S("-9223372036854775808"), "ll=-9223372036854775808 ull=18446744071562067968 i=-2147483648 ui=0 c=-128 uc=0 s=-32768 us=0 l=-2147483648 ul=0 b0=1 b1=1 f=-9.22337217e+17 d=-9.2233720368547763e+17 nf=0 nd=0 str=-9223372036854775808"},
	{S("-9223372036854775809"), "ll=-9223372036854775808 ull=18446744071562067968 i=-2147483648 ui=0 c=-128 uc=0 s=-32768 us=0 l=-2147483648 ul=0 b0=1 b1=1 f=-9.22337217e+17 d=-9.2233720368547763e+17 nf=0 nd=0 str=-9223372036854775809"},
	{S("18446744073709551615"), "ll=9223372036854775807 ull=2147483647 i=2147483647 ui=4294967295 c=127 uc=255 s=32767 us=65535 l=2147483647 ul=4294967295 b0=1 b1=1 f=1.84467437e+17 d=1.8446744073709552e+17 nf=1.84467437e+17 nd=1.8446744073709552e+17 str=18446744073709551615"},
	{S("18446744073709551616"), "ll=9223372036854775807 ull=2147483647 i=2147483647 ui=4294967295 c=127 uc=255 s=32767 us=65535 l=2147483647 ul=4294967295 b0=1 b1=1 f=1.84467437e+17 d=1.8446744073709552e+17 nf=1.84467437e+17 nd=1.8446744073709552e+17 str=18446744073709551616"},
	{S("99999999999999999999"), "ll=9223372036854775807 ull=2147483647 i=2147483647 ui=4294967295 c=127 uc=255 s=32767 us=65535 l=2147483647 ul=4294967295 b0=1 b1=1 f=9.99999984e+17 d=1e+18 nf=9.99999984e+17 nd=1e+18 str=99999999999999999999"},
	{S("1e40"), "ll=1 ull=1 i=1 ui=1 c=1 uc=1 s=1 us=1 l=1 ul=1 b0=1 b1=1 f=inf d=1e+40 nf=inf nd=1e+40 str=1e40"},
	{S("-1e40"), "ll=-1 ull=18446744073709551615 i=-1 ui=0 c=-1 uc=0 s=-1 us=0 l=-1 ul=0 b0=1 b1=1 f=-inf d=-1e+40 nf=0 nd=0 str=-1e40"},
	{S("1e400"), "ll=1 ull=1 i=1 ui=1 c=1 uc=1 s=1 us=1 l=1 ul=1 b0=1 b1=1 f=inf d=inf nf=inf nd=inf str=1e400"},
	{S("-1e400"), "ll=-1 ull=18446744073709551615 i=-1 ui=0 c=-1 uc=0 s=-1 us=0 l=-1 ul=0 b0=1 b1=1 f=-inf d=-inf nf=0 nd=0 str=-1e400"},
	{S("1e-400"), "ll=1 ull=1 i=1 ui=1 c=1 uc=1 s=1 us=1 l=1 ul=1 b0=0 b1=1 f=7.5 d=7.25 nf=0 nd=0 str=1e-400"},
	{S("3.4028235e38"), "ll=3 ull=3 i=3 ui=3 c=3 uc=3 s=3 us=3 l=3 ul=3 b0=1 b1=1 f=3.40282347e+38 d=3.4028234999999999e+38 nf=3.40282347e+38 nd=3.4028234999999999e+38 str=3.4028235e38"},
	{S("3.4028236e38"), "ll=3 ull=3 i=3 ui=3 c=3 uc=3 s=3 us=3 l=3 ul=3 b0=1 b1=1 f=inf d=3.4028235999999999e+38 nf=inf nd=3.4028235999999999e+38 str=3.4028236e38"},
	{S("1e39"), "ll=1 ull=1 i=1 ui=1 c=1 uc=1 s=1 us=1 l=1 ul=1 b0=1 b1=1 f=inf d=1.0000000000000001e+39 nf=inf nd=1.0000000000000001e+39 str=1e39"},
	{S("nan"), "ll=0 ull=0 i=0 ui=0 c=0 uc=0 s=0 us=0 l=0 ul=0 b0=0 b1=1 f=7.5 d=7.25 nf=0 nd=0 str=nan"},
	{S("NaN"), "ll=0 ull=0 i=0 ui=0 c=0 uc=0 s=0 us=0 l=0 ul=0 b0=0 b1=1 f=7.5 d=7.25 nf=0 nd=0 str=NaN"},
	{S("inf"), "ll=0 ull=0 i=0 ui=0 c=0 uc=0 s=0 us=0 l=0 ul=0 b0=0 b1=1 f=7.5 d=7.25 nf=0 nd=0 str=inf"},
	{S("Infinity"), "ll=0 ull=0 i=0 ui=0 c=0 uc=0 s=0 us=0 l=0 ul=0 b0=0 b1=1 f=7.5 d=7.25 nf=0 nd=0 str=Infinity"},
	{S("-inf"), "ll=0 ull=0 i=0 ui=0 c=0 uc=0 s=0 us=0 l=0 ul=0 b0=0 b1=1 f=7.5 d=7.25 nf=0 nd=0 str=-inf"},
	{S("INF"), "ll=0 ull=0 i=0 ui=0 c=0 uc=0 s=0 us=0 l=0 ul=0 b0=0 b1=1 f=7.5 d=7.25 nf=0 nd=0 str=INF"},
	{S("yes"), "ll=0 ull=0 i=0 ui=0 c=0 uc=0 s=0 us=0 l=0 ul=0 b0=1 b1=1 f=7.5 d=7.25 nf=0 nd=0 str=yes"},
	{S("YES"), "ll=0 ull=0 i=0 ui=0 c=0 uc=0 s=0 us=0 l=0 ul=0 b0=1 b1=1 f=7.5 d=7.25 nf=0 nd=0 str=YES"},
	{S("Yes"), "ll=0 ull=0 i=0 ui=0 c=0 uc=0 s=0 us=0 l=0 ul=0 b0=1 b1=1 f=7.5 d=7.25 nf=0 nd=0 str=Yes"},
	{S("yES"), "ll=0 ull=0 i=0 ui=0 c=0 uc=0 s=0 us=0 l=0 ul=0 b0=1 b1=1 f=7.5 d=7.25 nf=0 nd=0 str=yES"},
	{S("true"), "ll=0 ull=0 i=0 ui=0 c=0 uc=0 s=0 us=0 l=0 ul=0 b0=1 b1=1 f=7.5 d=7.25 nf=0 nd=0 str=true"},
	{S("TRUE"), "ll=0 ull=0 i=0 ui=0 c=0 uc=0 s=0 us=0 l=0 ul=0 b0=1 b1=1 f=7.5 d=7.25 nf=0 nd=0 str=TRUE"},
	{S("True"), "ll=0 ull=0 i=0 ui=0 c=0 uc=0 s=0 us=0 l=0 ul=0 b0=1 b1=1 f=7.5 d=7.25 nf=0 nd=0 str=True"},
	{S("on"), "ll=0 ull=0 i=0 ui=0 c=0 uc=0 s=0 us=0 l=0 ul=0 b0=1 b1=1 f=7.5 d=7.25 nf=0 nd=0 str=on"},
	{S("ON"), "ll=0 ull=0 i=0 ui=0 c=0 uc=0 s=0 us=0 l=0 ul=0 b0=1 b1=1 f=7.5 d=7.25 nf=0 nd=0 str=ON"},
	{S("no"), "ll=0 ull=0 i=0 ui=0 c=0 uc=0 s=0 us=0 l=0 ul=0 b0=0 b1=0 f=7.5 d=7.25 nf=0 nd=0 str=no"},
	{S("NO"), "ll=0 ull=0 i=0 ui=0 c=0 uc=0 s=0 us=0 l=0 ul=0 b0=0 b1=0 f=7.5 d=7.25 nf=0 nd=0 str=NO"},
	{S("No"), "ll=0 ull=0 i=0 ui=0 c=0 uc=0 s=0 us=0 l=0 ul=0 b0=0 b1=0 f=7.5 d=7.25 nf=0 nd=0 str=No"},
	{S("false"), "ll=0 ull=0 i=0 ui=0 c=0 uc=0 s=0 us=0 l=0 ul=0 b0=0 b1=0 f=7.5 d=7.25 nf=0 nd=0 str=false"},
	{S("FALSE"), "ll=0 ull=0 i=0 ui=0 c=0 uc=0 s=0 us=0 l=0 ul=0 b0=0 b1=0 f=7.5 d=7.25 nf=0 nd=0 str=FALSE"},
	{S("off"), "ll=0 ull=0 i=0 ui=0 c=0 uc=0 s=0 us=0 l=0 ul=0 b0=0 b1=0 f=7.5 d=7.25 nf=0 nd=0 str=off"},
	{S("Off"), "ll=0 ull=0 i=0 ui=0 c=0 uc=0 s=0 us=0 l=0 ul=0 b0=0 b1=0 f=7.5 d=7.25 nf=0 nd=0 str=Off"},
	{S("OFF"), "ll=0 ull=0 i=0 ui=0 c=0 uc=0 s=0 us=0 l=0 ul=0 b0=0 b1=0 f=7.5 d=7.25 nf=0 nd=0 str=OFF"},
	{S(" yes"), "ll=0 ull=0 i=0 ui=0 c=0 uc=0 s=0 us=0 l=0 ul=0 b0=0 b1=1 f=7.5 d=7.25 nf=0 nd=0 str= yes"},
	{S("yes "), "ll=0 ull=0 i=0 ui=0 c=0 uc=0 s=0 us=0 l=0 ul=0 b0=0 b1=1 f=7.5 d=7.25 nf=0 nd=0 str=yes "},
	{S("y"), "ll=0 ull=0 i=0 ui=0 c=0 uc=0 s=0 us=0 l=0 ul=0 b0=0 b1=1 f=7.5 d=7.25 nf=0 nd=0 str=y"},
	{S("n"), "ll=0 ull=0 i=0 ui=0 c=0 uc=0 s=0 us=0 l=0 ul=0 b0=0 b1=1 f=7.5 d=7.25 nf=0 nd=0 str=n"},
	{S("t"), "ll=0 ull=0 i=0 ui=0 c=0 uc=0 s=0 us=0 l=0 ul=0 b0=0 b1=1 f=7.5 d=7.25 nf=0 nd=0 str=t"},
	{S("f"), "ll=0 ull=0 i=0 ui=0 c=0 uc=0 s=0 us=0 l=0 ul=0 b0=0 b1=1 f=7.5 d=7.25 nf=0 nd=0 str=f"},
	{S("yess"), "ll=0 ull=0 i=0 ui=0 c=0 uc=0 s=0 us=0 l=0 ul=0 b0=0 b1=1 f=7.5 d=7.25 nf=0 nd=0 str=yess"},
	{S("nope"), "ll=0 ull=0 i=0 ui=0 c=0 uc=0 s=0 us=0 l=0 ul=0 b0=0 b1=1 f=7.5 d=7.25 nf=0 nd=0 str=nope"},
	{S("1.5e-50"), "ll=1 ull=1 i=1 ui=1 c=1 uc=1 s=1 us=1 l=1 ul=1 b0=1 b1=1 f=7.5 d=1.5e-50 nf=0 nd=1.5e-50 str=1.5e-50"},
	{S("0.1"), "ll=0 ull=0 i=0 ui=0 c=0 uc=0 s=0 us=0 l=0 ul=0 b0=1 b1=1 f=0.100000001 d=0.10000000000000001 nf=0.100000001 nd=0.10000000000000001 str=0.1"},
	{S("0.3"), "ll=0 ull=0 i=0 ui=0 c=0 uc=0 s=0 us=0 l=0 ul=0 b0=1 b1=1 f=0.300000012 d=0.29999999999999999 nf=0.300000012 nd=0.29999999999999999 str=0.3"},
	{S("1,5"), "ll=1 ull=1 i=1 ui=1 c=1 uc=1 s=1 us=1 l=1 ul=1 b0=1 b1=1 f=1 d=1 nf=1 nd=1 str=1,5"},
	{S("1 2"), "ll=1 ull=1 i=1 ui=1 c=1 uc=1 s=1 us=1 l=1 ul=1 b0=1 b1=1 f=1 d=1 nf=1 nd=1 str=1 2"},
	{S("- 1"), "ll=0 ull=0 i=0 ui=0 c=0 uc=0 s=0 us=0 l=0 ul=0 b0=0 b1=1 f=7.5 d=7.25 nf=0 nd=0 str=- 1"},
	{S("--1"), "ll=0 ull=0 i=0 ui=0 c=0 uc=0 s=0 us=0 l=0 ul=0 b0=0 b1=1 f=7.5 d=7.25 nf=0 nd=0 str=--1"},
	{S("+-1"), "ll=0 ull=0 i=0 ui=0 c=0 uc=0 s=0 us=0 l=0 ul=0 b0=0 b1=1 f=7.5 d=7.25 nf=0 nd=0 str=+-1"},
	{S("-+1"), "ll=0 ull=0 i=0 ui=0 c=0 uc=0 s=0 us=0 l=0 ul=0 b0=0 b1=1 f=7.5 d=7.25 nf=0 nd=0 str=-+1"},
	{S("1."), "ll=1 ull=1 i=1 ui=1 c=1 uc=1 s=1 us=1 l=1 ul=1 b0=1 b1=1 f=1 d=1 nf=1 nd=1 str=1."},
	{S("1.e5"), "ll=1 ull=1 i=1 ui=1 c=1 uc=1 s=1 us=1 l=1 ul=1 b0=1 b1=1 f=100000 d=100000 nf=100000 nd=100000 str=1.e5"},
	{S(".e5"), "ll=0 ull=0 i=0 ui=0 c=0 uc=0 s=0 us=0 l=0 ul=0 b0=0 b1=1 f=7.5 d=7.25 nf=0 nd=0 str=.e5"},
	{S("e5"), "ll=0 ull=0 i=0 ui=0 c=0 uc=0 s=0 us=0 l=0 ul=0 b0=0 b1=1 f=7.5 d=7.25 nf=0 nd=0 str=e5"},
	{S("."), "ll=0 ull=0 i=0 ui=0 c=0 uc=0 s=0 us=0 l=0 ul=0 b0=0 b1=1 f=7.5 d=7.25 nf=0 nd=0 str=."},
	{S("-."), "ll=0 ull=0 i=0 ui=0 c=0 uc=0 s=0 us=0 l=0 ul=0 b0=0 b1=1 f=7.5 d=7.25 nf=0 nd=0 str=-."},
	{S("1_000"), "ll=1 ull=1 i=1 ui=1 c=1 uc=1 s=1 us=1 l=1 ul=1 b0=1 b1=1 f=1 d=1 nf=1 nd=1 str=1_000"},
	{S("300"), "ll=300 ull=300 i=300 ui=300 c=127 uc=255 s=300 us=300 l=300 ul=300 b0=1 b1=1 f=300 d=300 nf=300 nd=300 str=300"},
	{S("-300"), "ll=-300 ull=18446744073709551316 i=-300 ui=0 c=-128 uc=0 s=-300 us=0 l=-300 ul=0 b0=1 b1=1 f=-300 d=-300 nf=0 nd=0 str=-300"},
	{S("70000"), "ll=70000 ull=70000 i=70000 ui=70000 c=127 uc=255 s=32767 us=65535 l=70000 ul=70000 b0=1 b1=1 f=70000 d=70000 nf=70000 nd=70000 str=70000"},
	{S("-70000"), "ll=-70000 ull=18446744073709481616 i=-70000 ui=0 c=-128 uc=0 s=-32768 us=0 l=-70000 ul=0 b0=1 b1=1 f=-70000 d=-70000 nf=0 nd=0 str=-70000"},
	{S("255"), "ll=255 ull=255 i=255 ui=255 c=127 uc=255 s=255 us=255 l=255 ul=255 b0=1 b1=1 f=255 d=255 nf=255 nd=255 str=255"},
	{S("256"), "ll=256 ull=256 i=256 ui=256 c=127 uc=255 s=256 us=256 l=256 ul=256 b0=1 b1=1 f=256 d=256 nf=256 nd=256 str=256"},
	{S("-129"), "ll=-129 ull=18446744073709551487 i=-129 ui=0 c=-128 uc=0 s=-129 us=0 l=-129 ul=0 b0=1 b1=1 f=-129 d=-129 nf=0 nd=0 str=-129"},
	{S("127"), "ll=127 ull=127 i=127 ui=127 c=127 uc=127 s=127 us=127 l=127 ul=127 b0=1 b1=1 f=127 d=127 nf=127 nd=127 str=127"},
	{S("128"), "ll=128 ull=128 i=128 ui=128 c=127 uc=128 s=128 us=128 l=128 ul=128 b0=1 b1=1 f=128 d=128 nf=128 nd=128 str=128"},
	{S("0.00000000000000000000000000000000000001"), "ll=0 ull=0 i=0 ui=0 c=0 uc=0 s=0 us=0 l=0 ul=0 b0=1 b1=1 f=9.99999935e-39 d=9.9999999999999996e-39 nf=9.99999935e-39 nd=9.9999999999999996e-39 str=0.00000000000000000000000000000000000001"},
	{S("000000000000000000000000000000000000000000001"), "ll=0 ull=0 i=0 ui=0 c=0 uc=0 s=0 us=0 l=0 ul=0 b0=1 b1=1 f=1 d=1 nf=1 nd=1 str=000000000000000000000000000000000000000000001"},
	{S("                                        7"), "ll=7 ull=7 i=7 ui=7 c=7 uc=7 s=7 us=7 l=7 ul=7 b0=1 b1=1 f=7 d=7 nf=7 nd=7 str=                                        7"},
	{S("1234567890123456789012345678901234567890"), "ll=9223372036854775807 ull=2147483647 i=2147483647 ui=4294967295 c=127 uc=255 s=32767 us=65535 l=2147483647 ul=4294967295 b0=1 b1=1 f=1.23456791e+17 d=1.2345678901234568e+17 nf=1.23456791e+17 nd=1.2345678901234568e+17 str=1234567890123456789012345678901234567890"},
	{S("3.14159265358979323846264338327950288419716939937510"), "ll=3 ull=3 i=3 ui=3 c=3 uc=3 s=3 us=3 l=3 ul=3 b0=1 b1=1 f=3.14159274 d=3.1415926535897931 nf=3.14159274 nd=3.1415926535897931 str=3.14159265358979323846264338327950288419716939937510"},
	{S("\302\2401"), "ll=0 ull=0 i=0 ui=0 c=0 uc=0 s=0 us=0 l=0 ul=0 b0=1 b1=1 f=1 d=1 nf=1 nd=1 str=\302\2401"},
	{S("\342\200\2001"), "ll=0 ull=0 i=0 ui=0 c=0 uc=0 s=0 us=0 l=0 ul=0 b0=1 b1=1 f=1 d=1 nf=1 nd=1 str=\342\200\2001"},
	{S("\343\200\2005"), "ll=0 ull=0 i=0 ui=0 c=0 uc=0 s=0 us=0 l=0 ul=0 b0=1 b1=1 f=5 d=5 nf=5 nd=5 str=\343\200\2005"},
	{S("\357\274\221"), "ll=0 ull=0 i=0 ui=0 c=0 uc=0 s=0 us=0 l=0 ul=0 b0=0 b1=1 f=7.5 d=7.25 nf=0 nd=0 str=\357\274\221"},
	{S("\331\243"), "ll=0 ull=0 i=0 ui=0 c=0 uc=0 s=0 us=0 l=0 ul=0 b0=0 b1=1 f=7.5 d=7.25 nf=0 nd=0 str=\331\243"},
	{S("YE\305\277"), "ll=0 ull=0 i=0 ui=0 c=0 uc=0 s=0 us=0 l=0 ul=0 b0=0 b1=1 f=7.5 d=7.25 nf=0 nd=0 str=YE\305\277"},
	{S("\357\275\231\357\275\205\357\275\223"), "ll=0 ull=0 i=0 ui=0 c=0 uc=0 s=0 us=0 l=0 ul=0 b0=0 b1=1 f=7.5 d=7.25 nf=0 nd=0 str=\357\275\231\357\275\205\357\275\223"},
	{S("\342\204\252"), "ll=0 ull=0 i=0 ui=0 c=0 uc=0 s=0 us=0 l=0 ul=0 b0=0 b1=1 f=7.5 d=7.25 nf=0 nd=0 str=\342\204\252"},
	{S("caf\303\251"), "ll=0 ull=0 i=0 ui=0 c=0 uc=0 s=0 us=0 l=0 ul=0 b0=0 b1=1 f=7.5 d=7.25 nf=0 nd=0 str=caf\303\251"},
	{S("0\303\251"), "ll=0 ull=0 i=0 ui=0 c=0 uc=0 s=0 us=0 l=0 ul=0 b0=0 b1=0 f=0 d=0 nf=0 nd=0 str=0\303\251"},
	{S("5\303\251"), "ll=5 ull=5 i=5 ui=5 c=5 uc=5 s=5 us=5 l=5 ul=5 b0=1 b1=1 f=5 d=5 nf=5 nd=5 str=5\303\251"},
	{S(" \011 0"), "ll=0 ull=0 i=0 ui=0 c=0 uc=0 s=0 us=0 l=0 ul=0 b0=0 b1=0 f=0 d=0 nf=0 nd=0 str= \011 0"},
	{S(" \011 1"), "ll=1 ull=1 i=1 ui=1 c=1 uc=1 s=1 us=1 l=1 ul=1 b0=1 b1=1 f=1 d=1 nf=1 nd=1 str= \011 1"},
	{S("\011\011-0"), "ll=0 ull=0 i=0 ui=0 c=0 uc=0 s=0 us=0 l=0 ul=0 b0=0 b1=1 f=7.5 d=7.25 nf=0 nd=0 str=\011\011-0"},
	{S("0 "), "ll=0 ull=0 i=0 ui=0 c=0 uc=0 s=0 us=0 l=0 ul=0 b0=0 b1=0 f=0 d=0 nf=0 nd=0 str=0 "},
	{S("-"), "ll=0 ull=0 i=0 ui=0 c=0 uc=0 s=0 us=0 l=0 ul=0 b0=0 b1=1 f=7.5 d=7.25 nf=0 nd=0 str=-"},
	{S("+"), "ll=0 ull=0 i=0 ui=0 c=0 uc=0 s=0 us=0 l=0 ul=0 b0=0 b1=1 f=7.5 d=7.25 nf=0 nd=0 str=+"},
	{S("0x"), "ll=0 ull=0 i=0 ui=0 c=0 uc=0 s=0 us=0 l=0 ul=0 b0=0 b1=0 f=0 d=0 nf=0 nd=0 str=0x"},
	{S("1e1000000"), "ll=1 ull=1 i=1 ui=1 c=1 uc=1 s=1 us=1 l=1 ul=1 b0=0 b1=1 f=7.5 d=7.25 nf=0 nd=0 str=1e1000000"},
	{S("4e-45"), "ll=4 ull=4 i=4 ui=4 c=4 uc=4 s=4 us=4 l=4 ul=4 b0=1 b1=1 f=4.20389539e-45 d=3.9999999999999999e-45 nf=4.20389539e-45 nd=3.9999999999999999e-45 str=4e-45"},
	{S("1e-45"), "ll=1 ull=1 i=1 ui=1 c=1 uc=1 s=1 us=1 l=1 ul=1 b0=1 b1=1 f=1.40129846e-45 d=9.9999999999999998e-46 nf=1.40129846e-45 nd=9.9999999999999998e-46 str=1e-45"},
	{S("1e-38"), "ll=1 ull=1 i=1 ui=1 c=1 uc=1 s=1 us=1 l=1 ul=1 b0=1 b1=1 f=9.99999935e-39 d=9.9999999999999996e-39 nf=9.99999935e-39 nd=9.9999999999999996e-39 str=1e-38"},
	{S("1e-39"), "ll=1 ull=1 i=1 ui=1 c=1 uc=1 s=1 us=1 l=1 ul=1 b0=1 b1=1 f=1.00000022e-39 d=9.9999999999999993e-40 nf=1.00000022e-39 nd=9.9999999999999993e-40 str=1e-39"},
	{S("-1e-50"), "ll=-1 ull=18446744073709551615 i=-1 ui=0 c=-1 uc=0 s=-1 us=0 l=-1 ul=0 b0=1 b1=1 f=7.5 d=-9.9999999999999989e-51 nf=0 nd=0 str=-1e-50"},
	{S("123456789"), "ll=123456789 ull=123456789 i=123456789 ui=123456789 c=127 uc=255 s=32767 us=65535 l=123456789 ul=123456789 b0=1 b1=1 f=123456792 d=123456789 nf=123456792 nd=123456789 str=123456789"},
	{S("16777217"), "ll=16777217 ull=16777217 i=16777217 ui=16777217 c=127 uc=255 s=32767 us=65535 l=16777217 ul=16777217 b0=1 b1=1 f=16777216 d=16777217 nf=16777216 nd=16777217 str=16777217"},
	{S("0.1e1"), "ll=0 ull=0 i=0 ui=0 c=0 uc=0 s=0 us=0 l=0 ul=0 b0=1 b1=1 f=1 d=1 nf=1 nd=1 str=0.1e1"},
	{S("1.0000001"), "ll=1 ull=1 i=1 ui=1 c=1 uc=1 s=1 us=1 l=1 ul=1 b0=1 b1=1 f=1.00000012 d=1.0000001000000001 nf=1.00000012 nd=1.0000001000000001 str=1.0000001"},
	{S("9007199254740993"), "ll=9007199254740993 ull=2147483647 i=2147483647 ui=4294967295 c=127 uc=255 s=32767 us=65535 l=2147483647 ul=4294967295 b0=1 b1=1 f=9.00719925e+15 d=9007199254740992 nf=9.00719925e+15 nd=9007199254740992 str=9007199254740993"},
	{S("1e19"), "ll=1 ull=1 i=1 ui=1 c=1 uc=1 s=1 us=1 l=1 ul=1 b0=1 b1=1 f=9.99999998e+18 d=1e+19 nf=9.99999998e+18 nd=1e+19 str=1e19"},
	{S("1e20"), "ll=1 ull=1 i=1 ui=1 c=1 uc=1 s=1 us=1 l=1 ul=1 b0=1 b1=1 f=1.00000002e+20 d=1e+20 nf=1.00000002e+20 nd=1e+20 str=1e20"},
	{S("-1e19"), "ll=-1 ull=18446744073709551615 i=-1 ui=0 c=-1 uc=0 s=-1 us=0 l=-1 ul=0 b0=1 b1=1 f=-9.99999998e+18 d=-1e+19 nf=0 nd=0 str=-1e19"},
	{S("-1e20"), "ll=-1 ull=18446744073709551615 i=-1 ui=0 c=-1 uc=0 s=-1 us=0 l=-1 ul=0 b0=1 b1=1 f=-1.00000002e+20 d=-1e+20 nf=0 nd=0 str=-1e20"},
	{U(0ULL), "ll=0 ull=0 i=0 ui=0 c=0 uc=0 s=0 us=0 l=0 ul=0 b0=0 b1=0 f=0 d=0 nf=0 nd=0 str=0"},
	{I(0LL), "ll=0 ull=0 i=0 ui=0 c=0 uc=0 s=0 us=0 l=0 ul=0 b0=0 b1=0 f=0 d=0 nf=0 nd=0 str=0"},
	{U(1ULL), "ll=1 ull=1 i=1 ui=1 c=1 uc=1 s=1 us=1 l=1 ul=1 b0=1 b1=1 f=1 d=1 nf=1 nd=1 str=1"},
	{I(1LL), "ll=1 ull=1 i=1 ui=1 c=1 uc=1 s=1 us=1 l=1 ul=1 b0=1 b1=1 f=1 d=1 nf=1 nd=1 str=1"},
	{I(-1LL), "ll=-1 ull=18446744073709551615 i=-1 ui=0 c=-1 uc=0 s=-1 us=0 l=-1 ul=0 b0=1 b1=1 f=-1 d=-1 nf=0 nd=0 str=-1"},
	{U(42ULL), "ll=42 ull=42 i=42 ui=42 c=42 uc=42 s=42 us=42 l=42 ul=42 b0=1 b1=1 f=42 d=42 nf=42 nd=42 str=42"},
	{I(42LL), "ll=42 ull=42 i=42 ui=42 c=42 uc=42 s=42 us=42 l=42 ul=42 b0=1 b1=1 f=42 d=42 nf=42 nd=42 str=42"},
	{I(-42LL), "ll=-42 ull=18446744073709551574 i=-42 ui=0 c=-42 uc=0 s=-42 us=0 l=-42 ul=0 b0=1 b1=1 f=-42 d=-42 nf=0 nd=0 str=-42"},
	{U(127ULL), "ll=127 ull=127 i=127 ui=127 c=127 uc=127 s=127 us=127 l=127 ul=127 b0=1 b1=1 f=127 d=127 nf=127 nd=127 str=127"},
	{I(127LL), "ll=127 ull=127 i=127 ui=127 c=127 uc=127 s=127 us=127 l=127 ul=127 b0=1 b1=1 f=127 d=127 nf=127 nd=127 str=127"},
	{U(128ULL), "ll=128 ull=128 i=128 ui=128 c=127 uc=128 s=128 us=128 l=128 ul=128 b0=1 b1=1 f=128 d=128 nf=128 nd=128 str=128"},
	{I(128LL), "ll=128 ull=128 i=128 ui=128 c=127 uc=128 s=128 us=128 l=128 ul=128 b0=1 b1=1 f=128 d=128 nf=128 nd=128 str=128"},
	{I(-128LL), "ll=-128 ull=18446744073709551488 i=-128 ui=0 c=-128 uc=0 s=-128 us=0 l=-128 ul=0 b0=1 b1=1 f=-128 d=-128 nf=0 nd=0 str=-128"},
	{I(-129LL), "ll=-129 ull=18446744073709551487 i=-129 ui=0 c=-128 uc=0 s=-129 us=0 l=-129 ul=0 b0=1 b1=1 f=-129 d=-129 nf=0 nd=0 str=-129"},
	{U(255ULL), "ll=255 ull=255 i=255 ui=255 c=127 uc=255 s=255 us=255 l=255 ul=255 b0=1 b1=1 f=255 d=255 nf=255 nd=255 str=255"},
	{I(255LL), "ll=255 ull=255 i=255 ui=255 c=127 uc=255 s=255 us=255 l=255 ul=255 b0=1 b1=1 f=255 d=255 nf=255 nd=255 str=255"},
	{U(256ULL), "ll=256 ull=256 i=256 ui=256 c=127 uc=255 s=256 us=256 l=256 ul=256 b0=1 b1=1 f=256 d=256 nf=256 nd=256 str=256"},
	{I(256LL), "ll=256 ull=256 i=256 ui=256 c=127 uc=255 s=256 us=256 l=256 ul=256 b0=1 b1=1 f=256 d=256 nf=256 nd=256 str=256"},
	{U(300ULL), "ll=300 ull=300 i=300 ui=300 c=127 uc=255 s=300 us=300 l=300 ul=300 b0=1 b1=1 f=300 d=300 nf=300 nd=300 str=300"},
	{I(300LL), "ll=300 ull=300 i=300 ui=300 c=127 uc=255 s=300 us=300 l=300 ul=300 b0=1 b1=1 f=300 d=300 nf=300 nd=300 str=300"},
	{I(-300LL), "ll=-300 ull=18446744073709551316 i=-300 ui=0 c=-128 uc=0 s=-300 us=0 l=-300 ul=0 b0=1 b1=1 f=-300 d=-300 nf=0 nd=0 str=-300"},
	{U(32767ULL), "ll=32767 ull=32767 i=32767 ui=32767 c=127 uc=255 s=32767 us=32767 l=32767 ul=32767 b0=1 b1=1 f=32767 d=32767 nf=32767 nd=32767 str=32767"},
	{I(32767LL), "ll=32767 ull=32767 i=32767 ui=32767 c=127 uc=255 s=32767 us=32767 l=32767 ul=32767 b0=1 b1=1 f=32767 d=32767 nf=32767 nd=32767 str=32767"},
	{U(32768ULL), "ll=32768 ull=32768 i=32768 ui=32768 c=127 uc=255 s=32767 us=32768 l=32768 ul=32768 b0=1 b1=1 f=32768 d=32768 nf=32768 nd=32768 str=32768"},
	{I(32768LL), "ll=32768 ull=32768 i=32768 ui=32768 c=127 uc=255 s=32767 us=32768 l=32768 ul=32768 b0=1 b1=1 f=32768 d=32768 nf=32768 nd=32768 str=32768"},
	{I(-32769LL), "ll=-32769 ull=18446744073709518847 i=-32769 ui=0 c=-128 uc=0 s=-32768 us=0 l=-32769 ul=0 b0=1 b1=1 f=-32769 d=-32769 nf=0 nd=0 str=-32769"},
	{U(65535ULL), "ll=65535 ull=65535 i=65535 ui=65535 c=127 uc=255 s=32767 us=65535 l=65535 ul=65535 b0=1 b1=1 f=65535 d=65535 nf=65535 nd=65535 str=65535"},
	{I(65535LL), "ll=65535 ull=65535 i=65535 ui=65535 c=127 uc=255 s=32767 us=65535 l=65535 ul=65535 b0=1 b1=1 f=65535 d=65535 nf=65535 nd=65535 str=65535"},
	{U(65536ULL), "ll=65536 ull=65536 i=65536 ui=65536 c=127 uc=255 s=32767 us=65535 l=65536 ul=65536 b0=1 b1=1 f=65536 d=65536 nf=65536 nd=65536 str=65536"},
	{I(65536LL), "ll=65536 ull=65536 i=65536 ui=65536 c=127 uc=255 s=32767 us=65535 l=65536 ul=65536 b0=1 b1=1 f=65536 d=65536 nf=65536 nd=65536 str=65536"},
	{U(70000ULL), "ll=70000 ull=70000 i=70000 ui=70000 c=127 uc=255 s=32767 us=65535 l=70000 ul=70000 b0=1 b1=1 f=70000 d=70000 nf=70000 nd=70000 str=70000"},
	{I(70000LL), "ll=70000 ull=70000 i=70000 ui=70000 c=127 uc=255 s=32767 us=65535 l=70000 ul=70000 b0=1 b1=1 f=70000 d=70000 nf=70000 nd=70000 str=70000"},
	{I(-70000LL), "ll=-70000 ull=18446744073709481616 i=-70000 ui=0 c=-128 uc=0 s=-32768 us=0 l=-70000 ul=0 b0=1 b1=1 f=-70000 d=-70000 nf=0 nd=0 str=-70000"},
	{U(2147483647ULL), "ll=2147483647 ull=2147483647 i=2147483647 ui=2147483647 c=127 uc=255 s=32767 us=65535 l=2147483647 ul=2147483647 b0=1 b1=1 f=2.14748365e+09 d=2147483647 nf=2.14748365e+09 nd=2147483647 str=2147483647"},
	{I(2147483647LL), "ll=2147483647 ull=2147483647 i=2147483647 ui=2147483647 c=127 uc=255 s=32767 us=65535 l=2147483647 ul=2147483647 b0=1 b1=1 f=2.14748365e+09 d=2147483647 nf=2.14748365e+09 nd=2147483647 str=2147483647"},
	{U(2147483648ULL), "ll=2147483648 ull=2147483648 i=2147483647 ui=2147483648 c=127 uc=255 s=32767 us=65535 l=2147483647 ul=2147483648 b0=1 b1=1 f=2.14748365e+09 d=2147483648 nf=2.14748365e+09 nd=2147483648 str=2147483648"},
	{I(2147483648LL), "ll=2147483648 ull=2147483648 i=2147483647 ui=2147483648 c=127 uc=255 s=32767 us=65535 l=2147483647 ul=2147483648 b0=1 b1=1 f=2.14748365e+09 d=2147483648 nf=2.14748365e+09 nd=2147483648 str=2147483648"},
	{I(-2147483648LL), "ll=-2147483648 ull=18446744071562067968 i=-2147483648 ui=0 c=-128 uc=0 s=-32768 us=0 l=-2147483648 ul=0 b0=1 b1=1 f=-2.14748365e+09 d=-2147483648 nf=0 nd=0 str=-2147483648"},
	{I(-2147483649LL), "ll=-2147483649 ull=18446744071562067967 i=-2147483648 ui=0 c=-128 uc=0 s=-32768 us=0 l=-2147483648 ul=0 b0=1 b1=1 f=-2.14748365e+09 d=-2147483649 nf=0 nd=0 str=-2147483649"},
	{U(4294967295ULL), "ll=4294967295 ull=4294967295 i=2147483647 ui=4294967295 c=127 uc=255 s=32767 us=65535 l=2147483647 ul=4294967295 b0=1 b1=1 f=4.2949673e+09 d=4294967295 nf=4.2949673e+09 nd=4294967295 str=4294967295"},
	{I(4294967295LL), "ll=4294967295 ull=4294967295 i=2147483647 ui=4294967295 c=127 uc=255 s=32767 us=65535 l=2147483647 ul=4294967295 b0=1 b1=1 f=4.2949673e+09 d=4294967295 nf=4.2949673e+09 nd=4294967295 str=4294967295"},
	{U(4294967296ULL), "ll=4294967296 ull=4294967296 i=2147483647 ui=4294967295 c=127 uc=255 s=32767 us=65535 l=2147483647 ul=4294967295 b0=1 b1=1 f=4.2949673e+09 d=4294967296 nf=4.2949673e+09 nd=4294967296 str=4294967296"},
	{I(4294967296LL), "ll=4294967296 ull=4294967296 i=2147483647 ui=4294967295 c=127 uc=255 s=32767 us=65535 l=2147483647 ul=4294967295 b0=1 b1=1 f=4.2949673e+09 d=4294967296 nf=4.2949673e+09 nd=4294967296 str=4294967296"},
	{U(9223372036854775807ULL), "ll=9223372036854775807 ull=9223372036854775807 i=2147483647 ui=4294967295 c=127 uc=255 s=32767 us=65535 l=2147483647 ul=4294967295 b0=1 b1=1 f=9.22337204e+18 d=9.2233720368547758e+18 nf=9.22337204e+18 nd=9.2233720368547758e+18 str=9223372036854775807"},
	{I(9223372036854775807LL), "ll=9223372036854775807 ull=9223372036854775807 i=2147483647 ui=4294967295 c=127 uc=255 s=32767 us=65535 l=2147483647 ul=4294967295 b0=1 b1=1 f=9.22337204e+18 d=9.2233720368547758e+18 nf=9.22337204e+18 nd=9.2233720368547758e+18 str=9223372036854775807"},
	{I(-9223372036854775807LL - 1), "ll=-9223372036854775808 ull=9223372036854775808 i=-2147483648 ui=0 c=-128 uc=0 s=-32768 us=0 l=-2147483648 ul=0 b0=1 b1=1 f=-9.22337204e+18 d=-9.2233720368547758e+18 nf=0 nd=0 str=-9223372036854775808"},
	{U(9223372036854775808ULL), "ll=-9223372036854775808 ull=9223372036854775808 i=-2147483648 ui=0 c=-128 uc=0 s=-32768 us=0 l=-2147483648 ul=0 b0=1 b1=1 f=9.22337204e+18 d=9.2233720368547758e+18 nf=9.22337204e+18 nd=9.2233720368547758e+18 str=9223372036854775808"},
	{U(18446744073709551615ULL), "ll=-1 ull=18446744073709551615 i=-1 ui=0 c=-1 uc=0 s=-1 us=0 l=-1 ul=0 b0=1 b1=1 f=1.84467441e+19 d=1.8446744073709552e+19 nf=1.84467441e+19 nd=1.8446744073709552e+19 str=18446744073709551615"},
	{U(18446744073709551614ULL), "ll=-2 ull=18446744073709551614 i=-2 ui=0 c=-2 uc=0 s=-2 us=0 l=-2 ul=0 b0=1 b1=1 f=1.84467441e+19 d=1.8446744073709552e+19 nf=1.84467441e+19 nd=1.8446744073709552e+19 str=18446744073709551614"},
	{U(4294967301ULL), "ll=4294967301 ull=4294967301 i=2147483647 ui=4294967295 c=127 uc=255 s=32767 us=65535 l=2147483647 ul=4294967295 b0=1 b1=1 f=4.2949673e+09 d=4294967301 nf=4.2949673e+09 nd=4294967301 str=4294967301"},
	{R(0.0), "ll=0 ull=0 i=0 ui=0 c=0 uc=0 s=0 us=0 l=0 ul=0 b0=0 b1=0 f=0 d=0 nf=0 nd=0 str=0"},
	{R(-0.0), "ll=0 ull=0 i=0 ui=0 c=0 uc=0 s=0 us=0 l=0 ul=0 b0=0 b1=0 f=-0 d=-0 nf=0 nd=0 str=-0"},
	{R(0.5), "ll=0 ull=0 i=0 ui=0 c=0 uc=0 s=0 us=0 l=0 ul=0 b0=1 b1=1 f=0.5 d=0.5 nf=0.5 nd=0.5 str=0.5"},
	{R(-0.5), "ll=0 ull=0 i=0 ui=0 c=0 uc=0 s=0 us=0 l=0 ul=0 b0=1 b1=1 f=-0.5 d=-0.5 nf=0 nd=0 str=-0.5"},
	{R(1.5), "ll=1 ull=1 i=1 ui=1 c=1 uc=1 s=1 us=1 l=1 ul=1 b0=1 b1=1 f=1.5 d=1.5 nf=1.5 nd=1.5 str=1.5"},
	{R(-1.5), "ll=-1 ull=18446744073709551615 i=-1 ui=0 c=-1 uc=0 s=-1 us=0 l=-1 ul=0 b0=1 b1=1 f=-1.5 d=-1.5 nf=0 nd=0 str=-1.5"},
	{R(2.5), "ll=2 ull=2 i=2 ui=2 c=2 uc=2 s=2 us=2 l=2 ul=2 b0=1 b1=1 f=2.5 d=2.5 nf=2.5 nd=2.5 str=2.5"},
	{R(3.7), "ll=3 ull=3 i=3 ui=3 c=3 uc=3 s=3 us=3 l=3 ul=3 b0=1 b1=1 f=3.70000005 d=3.7000000000000002 nf=3.70000005 nd=3.7000000000000002 str=3.7"},
	{R(-3.7), "ll=-3 ull=18446744073709551613 i=-3 ui=0 c=-3 uc=0 s=-3 us=0 l=-3 ul=0 b0=1 b1=1 f=-3.70000005 d=-3.7000000000000002 nf=0 nd=0 str=-3.7"},
	{R(0.1), "ll=0 ull=0 i=0 ui=0 c=0 uc=0 s=0 us=0 l=0 ul=0 b0=1 b1=1 f=0.100000001 d=0.10000000000000001 nf=0.100000001 nd=0.10000000000000001 str=0.1"},
	{R(1.0/3.0), "ll=0 ull=0 i=0 ui=0 c=0 uc=0 s=0 us=0 l=0 ul=0 b0=1 b1=1 f=0.333333343 d=0.33333333333333331 nf=0.333333343 nd=0.33333333333333331 str=0.3333333333333333"},
	{R(100.0), "ll=100 ull=100 i=100 ui=100 c=100 uc=100 s=100 us=100 l=100 ul=100 b0=1 b1=1 f=100 d=100 nf=100 nd=100 str=100"},
	{R(127.9), "ll=127 ull=127 i=127 ui=127 c=127 uc=127 s=127 us=127 l=127 ul=127 b0=1 b1=1 f=127.900002 d=127.90000000000001 nf=127.900002 nd=127.90000000000001 str=127.9"},
	{R(128.0), "ll=128 ull=128 i=128 ui=128 c=127 uc=128 s=128 us=128 l=128 ul=128 b0=1 b1=1 f=128 d=128 nf=128 nd=128 str=128"},
	{R(-129.5), "ll=-129 ull=18446744073709551487 i=-129 ui=0 c=-128 uc=0 s=-129 us=0 l=-129 ul=0 b0=1 b1=1 f=-129.5 d=-129.5 nf=0 nd=0 str=-129.5"},
	{R(255.5), "ll=255 ull=255 i=255 ui=255 c=127 uc=255 s=255 us=255 l=255 ul=255 b0=1 b1=1 f=255.5 d=255.5 nf=255.5 nd=255.5 str=255.5"},
	{R(256.0), "ll=256 ull=256 i=256 ui=256 c=127 uc=255 s=256 us=256 l=256 ul=256 b0=1 b1=1 f=256 d=256 nf=256 nd=256 str=256"},
	{R(70000.25), "ll=70000 ull=70000 i=70000 ui=70000 c=127 uc=255 s=32767 us=65535 l=70000 ul=70000 b0=1 b1=1 f=70000.25 d=70000.25 nf=70000.25 nd=70000.25 str=70000.25"},
	{R(2147483647.5), "ll=2147483647 ull=2147483647 i=2147483647 ui=2147483647 c=127 uc=255 s=32767 us=65535 l=2147483647 ul=2147483647 b0=1 b1=1 f=2.14748365e+09 d=2147483647.5 nf=2.14748365e+09 nd=2147483647.5 str=2147483647.5"},
	{R(2147483648.0), "ll=2147483648 ull=2147483648 i=2147483647 ui=2147483648 c=127 uc=255 s=32767 us=65535 l=2147483647 ul=2147483648 b0=1 b1=1 f=2.14748365e+09 d=2147483648 nf=2.14748365e+09 nd=2147483648 str=2147483648"},
	{R(-2147483649.0), "ll=-2147483649 ull=18446744071562067967 i=-2147483648 ui=0 c=-128 uc=0 s=-32768 us=0 l=-2147483648 ul=0 b0=1 b1=1 f=-2.14748365e+09 d=-2147483649 nf=0 nd=0 str=-2147483649"},
	{R(4294967296.0), "ll=4294967296 ull=4294967296 i=2147483647 ui=4294967295 c=127 uc=255 s=32767 us=65535 l=2147483647 ul=4294967295 b0=1 b1=1 f=4.2949673e+09 d=4294967296 nf=4.2949673e+09 nd=4294967296 str=4294967296"},
	{R(1e10), "ll=10000000000 ull=10000000000 i=2147483647 ui=4294967295 c=127 uc=255 s=32767 us=65535 l=2147483647 ul=4294967295 b0=1 b1=1 f=1e+10 d=10000000000 nf=1e+10 nd=10000000000 str=10000000000"},
	{R(-1e10), "ll=-10000000000 ull=18446744063709551616 i=-2147483648 ui=0 c=-128 uc=0 s=-32768 us=0 l=-2147483648 ul=0 b0=1 b1=1 f=-1e+10 d=-10000000000 nf=0 nd=0 str=-10000000000"},
	{R(1e15), "ll=1000000000000000 ull=1000000000000000 i=2147483647 ui=4294967295 c=127 uc=255 s=32767 us=65535 l=2147483647 ul=4294967295 b0=1 b1=1 f=9.99999987e+14 d=1000000000000000 nf=9.99999987e+14 nd=1000000000000000 str=1000000000000000"},
	{R(1e16), "ll=10000000000000000 ull=10000000000000000 i=2147483647 ui=4294967295 c=127 uc=255 s=32767 us=65535 l=2147483647 ul=4294967295 b0=1 b1=1 f=1.00000003e+16 d=10000000000000000 nf=1.00000003e+16 nd=10000000000000000 str=1e+16"},
	{R(1e17), "ll=100000000000000000 ull=100000000000000000 i=2147483647 ui=4294967295 c=127 uc=255 s=32767 us=65535 l=2147483647 ul=4294967295 b0=1 b1=1 f=9.99999984e+16 d=1e+17 nf=9.99999984e+16 nd=1e+17 str=1e+17"},
	{R(123456789.123), "ll=123456789 ull=123456789 i=123456789 ui=123456789 c=127 uc=255 s=32767 us=65535 l=123456789 ul=123456789 b0=1 b1=1 f=123456792 d=123456789.123 nf=123456792 nd=123456789.123 str=123456789.123"},
	{R(9.2233720368547758e18), "ll=-9223372036854775808 ull=9223372036854775808 i=-2147483648 ui=0 c=-128 uc=0 s=-32768 us=0 l=-2147483648 ul=0 b0=1 b1=1 f=9.22337204e+18 d=9.2233720368547758e+18 nf=9.22337204e+18 nd=9.2233720368547758e+18 str=9.223372036854776e+18"},
	{R(1e19), "ll=-9223372036854775808 ull=10000000000000000000 i=-2147483648 ui=0 c=-128 uc=0 s=-32768 us=0 l=-2147483648 ul=0 b0=1 b1=1 f=9.99999998e+18 d=1e+19 nf=9.99999998e+18 nd=1e+19 str=1e+19"},
	{R(-1e19), "ll=-9223372036854775808 ull=9223372036854775808 i=-2147483648 ui=0 c=-128 uc=0 s=-32768 us=0 l=-2147483648 ul=0 b0=1 b1=1 f=-9.99999998e+18 d=-1e+19 nf=0 nd=0 str=-1e+19"},
	{R(1.8446744073709552e19), "ll=-9223372036854775808 ull=9223372036854775808 i=-2147483648 ui=0 c=-128 uc=0 s=-32768 us=0 l=-2147483648 ul=0 b0=1 b1=1 f=1.84467441e+19 d=1.8446744073709552e+19 nf=1.84467441e+19 nd=1.8446744073709552e+19 str=1.844674407370955e+19"},
	{R(1e20), "ll=-9223372036854775808 ull=9223372036854775808 i=-2147483648 ui=0 c=-128 uc=0 s=-32768 us=0 l=-2147483648 ul=0 b0=1 b1=1 f=1.00000002e+20 d=1e+20 nf=1.00000002e+20 nd=1e+20 str=1e+20"},
	{R(-1e20), "ll=-9223372036854775808 ull=9223372036854775808 i=-2147483648 ui=0 c=-128 uc=0 s=-32768 us=0 l=-2147483648 ul=0 b0=1 b1=1 f=-1.00000002e+20 d=-1e+20 nf=0 nd=0 str=-1e+20"},
	{R(1e300), "ll=-9223372036854775808 ull=9223372036854775808 i=-2147483648 ui=0 c=-128 uc=0 s=-32768 us=0 l=-2147483648 ul=0 b0=1 b1=1 f=inf d=1.0000000000000001e+300 nf=inf nd=1.0000000000000001e+300 str=1e+300"},
	{R(-1e300), "ll=-9223372036854775808 ull=9223372036854775808 i=-2147483648 ui=0 c=-128 uc=0 s=-32768 us=0 l=-2147483648 ul=0 b0=1 b1=1 f=-inf d=-1.0000000000000001e+300 nf=0 nd=0 str=-1e+300"},
	{R(3.4028235e38), "ll=-9223372036854775808 ull=9223372036854775808 i=-2147483648 ui=0 c=-128 uc=0 s=-32768 us=0 l=-2147483648 ul=0 b0=1 b1=1 f=3.40282347e+38 d=3.4028234999999999e+38 nf=3.40282347e+38 nd=3.4028234999999999e+38 str=3.4028235e+38"},
	{R(1e39), "ll=-9223372036854775808 ull=9223372036854775808 i=-2147483648 ui=0 c=-128 uc=0 s=-32768 us=0 l=-2147483648 ul=0 b0=1 b1=1 f=inf d=9.9999999999999994e+38 nf=inf nd=9.9999999999999994e+38 str=9.999999999999999e+38"},
	{R(-1e39), "ll=-9223372036854775808 ull=9223372036854775808 i=-2147483648 ui=0 c=-128 uc=0 s=-32768 us=0 l=-2147483648 ul=0 b0=1 b1=1 f=-inf d=-9.9999999999999994e+38 nf=0 nd=0 str=-9.999999999999999e+38"},
	{R(1e-50), "ll=0 ull=0 i=0 ui=0 c=0 uc=0 s=0 us=0 l=0 ul=0 b0=1 b1=1 f=0 d=1e-50 nf=0 nd=1e-50 str=1e-50"},
	{R(-1e-50), "ll=0 ull=0 i=0 ui=0 c=0 uc=0 s=0 us=0 l=0 ul=0 b0=1 b1=1 f=-0 d=-1e-50 nf=0 nd=0 str=-1e-50"},
	{R(NAN), "ll=-9223372036854775808 ull=9223372036854775808 i=-2147483648 ui=0 c=-128 uc=0 s=-32768 us=0 l=-2147483648 ul=0 b0=1 b1=1 f=nan d=nan nf=0 nd=0 str=nan"},
	{R(INFINITY), "ll=-9223372036854775808 ull=9223372036854775808 i=-2147483648 ui=0 c=-128 uc=0 s=-32768 us=0 l=-2147483648 ul=0 b0=1 b1=1 f=inf d=inf nf=inf nd=inf str=inf"},
	{R(-INFINITY), "ll=-9223372036854775808 ull=9223372036854775808 i=-2147483648 ui=0 c=-128 uc=0 s=-32768 us=0 l=-2147483648 ul=0 b0=1 b1=1 f=-inf d=-inf nf=0 nd=0 str=-inf"},
	{R(5e-324), "ll=0 ull=0 i=0 ui=0 c=0 uc=0 s=0 us=0 l=0 ul=0 b0=1 b1=1 f=0 d=4.9406564584124654e-324 nf=0 nd=4.9406564584124654e-324 str=4.940656458412465e-324"},
	{R(1e21), "ll=-9223372036854775808 ull=9223372036854775808 i=-2147483648 ui=0 c=-128 uc=0 s=-32768 us=0 l=-2147483648 ul=0 b0=1 b1=1 f=1.00000002e+21 d=1e+21 nf=1.00000002e+21 nd=1e+21 str=1e+21"},
	{R(1e22), "ll=-9223372036854775808 ull=9223372036854775808 i=-2147483648 ui=0 c=-128 uc=0 s=-32768 us=0 l=-2147483648 ul=0 b0=1 b1=1 f=9.99999978e+21 d=1e+22 nf=9.99999978e+21 nd=1e+22 str=1e+22"},
	{R(123456.0), "ll=123456 ull=123456 i=123456 ui=123456 c=127 uc=255 s=32767 us=65535 l=123456 ul=123456 b0=1 b1=1 f=123456 d=123456 nf=123456 nd=123456 str=123456"},
	{R(0.000001), "ll=0 ull=0 i=0 ui=0 c=0 uc=0 s=0 us=0 l=0 ul=0 b0=1 b1=1 f=9.99999997e-07 d=9.9999999999999995e-07 nf=9.99999997e-07 nd=9.9999999999999995e-07 str=1e-06"},
	{R(0.0000001), "ll=0 ull=0 i=0 ui=0 c=0 uc=0 s=0 us=0 l=0 ul=0 b0=1 b1=1 f=1.00000001e-07 d=9.9999999999999995e-08 nf=1.00000001e-07 nd=9.9999999999999995e-08 str=1e-07"},
	{R(1e-5), "ll=0 ull=0 i=0 ui=0 c=0 uc=0 s=0 us=0 l=0 ul=0 b0=1 b1=1 f=9.99999975e-06 d=1.0000000000000001e-05 nf=9.99999975e-06 nd=1.0000000000000001e-05 str=1e-05"},
};

bool checkRow(const Row& row, const std::string& got, const char* how)
{
	if (got == row.expected) return true;
	std::printf("  %s:\n    want %s\n    got  %s\n", how, row.expected, got.c_str());
	return false;
}

} // namespace

OO_TEST(getMatchesGNUstepCapturedTable)
{
	for (const Row& row : kCaptured)
	{
		PList::Dict d;
		if (row.value) d.emplace("k", *row.value);
		const PList dict(std::move(d));
		const std::string got = results([&]<class T>(typename oo::PListGet<T>::Fallback fb) { return dict.get<T>("k", fb); });
		OO_CHECK(checkRow(row, got, "dict.get<T>(\"k\", fallback)"));
	}
}

OO_TEST(atMatchesGNUstepCapturedTable)
{
	for (const Row& row : kCaptured)
	{
		PList::Array a{PList("pad")};
		if (row.value) a.push_back(*row.value);
		const PList array(std::move(a));
		const std::string got = results([&]<class T>(typename oo::PListGet<T>::Fallback fb) { return array.at<T>(1, fb); });
		OO_CHECK(checkRow(row, got, "array.at<T>(1, fallback)"));
	}
}

// [nil oo_floatForKey:k defaultValue:1] is 0: messaging nil returns zero, not the fallback.
OO_TEST(nullReceiverIsNilNotFallback)
{
	const PList nil;
	OO_CHECK_EQ(nil.get<float>("k", 1.0f), 0.0f);
	OO_CHECK_EQ(nil.get<int>("k", 5), 0);
	OO_CHECK_EQ(nil.get<bool>("k", true), false);
	OO_CHECK_EQ(nil.get<std::string>("k", "D"), std::string());
	OO_CHECK_EQ(nil.get<oo::NonNegative<double>>("k", 2.0), 0.0);
	OO_CHECK(nil.get<PList::Dict>("k", &nil) == nullptr);
	OO_CHECK_EQ(nil.at<int>(0, 5), 0);
}

// The no-fallback forms (-oo_floatForKey: etc.) fall back to zero / NO / nil.
OO_TEST(noFallbackFormsUseTheExtractorDefaults)
{
	const PList d(PList::Dict{{"s", PList("x")}});
	OO_CHECK_EQ(d.get<float>("missing"), 0.0f);
	OO_CHECK_EQ(d.get<float>("s"), 0.0f);   // "x" is not a zero string, so the (zero) fallback
	OO_CHECK_EQ(d.get<unsigned>("missing"), 0u);
	OO_CHECK_EQ(d.get<bool>("s"), false);
	OO_CHECK_EQ(d.get<std::string>("missing"), std::string());
	OO_CHECK(d.get<PList>("missing") == nullptr);
	OO_CHECK_EQ(d.get<std::string>("s"), std::string("x"));
	const PList a(PList::Array{PList(3)});
	OO_CHECK_EQ(a.at<int>(0), 3);
	OO_CHECK_EQ(a.at<int>(1), 0);
	OO_CHECK_EQ(a.at<int>(1, -1), -1);   // -oo_objectAtIndex: is nil past the end, never a range exception
}

// A receiver of the wrong kind (the Objective-C method would not exist) finds nothing.
OO_TEST(wrongReceiverKindGivesFallback)
{
	const PList s("text");
	OO_CHECK_EQ(s.get<int>("k", 4), 4);
	OO_CHECK_EQ(s.at<int>(0, 4), 4);
	const PList d(PList::Dict{{"0", PList(1)}});
	OO_CHECK_EQ(d.at<int>(0, 4), 4);
}

// oo_objectForKey / oo_arrayForKey / oo_dictionaryForKey / oo_dataForKey: -isKindOfClass:.
OO_TEST(containerKindsReturnTheNode)
{
	const PList inner(PList::Dict{{"x", PList(2.5)}});
	const PList d(PList::Dict{{"a", PList(PList::Array{PList(1), PList(2)})},
							 {"d", inner},
							 {"b", PList(oo::Data::fromString("xy"))},
							 {"t", PList(PList::Date{1.0})},
							 {"s", PList("str")}});
	const PList fb;
	const PList* arr = d.get<PList::Array>("a");
	OO_CHECK(arr != nullptr && arr->count() == 2 && arr->at<int>(1) == 2);
	const PList* dict = d.get<PList::Dict>("d");
	OO_CHECK(dict != nullptr && dict->get<float>("x") == 2.5f);
	OO_CHECK(d.get<PList::Data>("b") != nullptr);
	OO_CHECK(d.get<PList::Date>("t") != nullptr);
	OO_CHECK(d.get<PList::Array>("d") == nullptr);
	OO_CHECK(d.get<PList::Dict>("a", &fb) == &fb);
	OO_CHECK(d.get<PList::Dict>("s", &fb) == &fb);   // a string is not a dictionary
	OO_CHECK(d.get<PList>("s") == d.find("s"));
	OO_CHECK(d.get<PList>("zz", &fb) == &fb);
}

// NSNumber -stringValue for the kinds a plist can hold.
OO_TEST(stringFromNumbers)
{
	const PList d(PList::Dict{{"u", PList::unsignedInteger(18446744073709551615ULL)},
							 {"i", PList::signedInteger(-5)},
							 {"r", PList(0.1)},
							 {"t", PList(true)},
							 {"a", PList(PList::Array{})}});
	OO_CHECK_EQ(d.get<std::string>("u"), std::string("18446744073709551615"));
	OO_CHECK_EQ(d.get<std::string>("i"), std::string("-5"));
	OO_CHECK_EQ(d.get<std::string>("r"), std::string("0.1"));
	OO_CHECK_EQ(d.get<std::string>("t"), std::string("1"));
	OO_CHECK_EQ(d.get<std::string>("a", "D"), std::string("D"));
}

// GNUstep's scanner keeps 18 digits and drops the rest without rescaling; an exponent past 511 is
// no number at all. (Also rows of kCaptured; spelled out here because they surprise.)
OO_TEST(scannerQuirks)
{
	OO_CHECK_EQ(oo::plist_get::doubleValue(u"9223372036854775807"), 922337203685477580.0);
	OO_CHECK_EQ(oo::plist_get::doubleValue(u"1e511"), HUGE_VAL);
	OO_CHECK_EQ(oo::plist_get::doubleValue(u"1e512"), 0.0);
	OO_CHECK_EQ(oo::plist_get::doubleValue(u"\u3000 5"), 5.0);   // Unicode space is skipped here...
	OO_CHECK_EQ(oo::plist_get::longLongValue(u"\u3000 5"), 0);   // ...but not by -longLongValue
	OO_CHECK_EQ(oo::plist_get::longLongValue(u"000000000000000000001"), 0);   // 20-character buffer
	OO_CHECK_EQ(oo::plist_get::intValue(u"-5000000000"), -2147483647 - 1);
	OO_CHECK_EQ(oo::plist_get::doubleValue(u"1e99999999999"), 0.0);   // wrapped int exponent, > 511
}

OO_TEST_MAIN()
