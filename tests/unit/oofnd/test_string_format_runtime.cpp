/*	test_string_format_runtime.cpp
	oo::str::formatRuntime (oofnd/String.hpp; proposed ADR-0043 Amendment 3): -[NSString
	stringWithFormat:] for a format string read at run time (DESC(...) entries, verifyOXP.plist's
	GraphViz templates), with %@, %p and positional arguments.

	Every expectation is GNUstep base 1.31.1's own output on this toolchain (64-bit Windows),
	captured by a throwaway Objective-C++ probe linked against gnustep-base that printed
	[NSString stringWithFormat:...] for the format strings and Objective-C arguments noted on each
	row (NSString, NSNumber, nil, pointers, C scalars). The rows are that output, unedited; the
	arguments here are the FormatArg forms of the same values.
*/

#include "oofnd/String.hpp"

#include "oo_test.hpp"

#include <cstdint>
#include <limits>
#include <string>

namespace {

using oo::str::FormatArg;
using oo::str::formatRuntime;

const void* const kSmall = reinterpret_cast<const void*>(static_cast<std::uintptr_t>(0x12345678u));
const void* const kBig = reinterpret_cast<const void*>(static_cast<std::uintptr_t>(0x7ff612345678ull));

} // namespace

OO_TEST(objectConversion)
{
	OO_CHECK_EQ(formatRuntime("[%@]", {"abc"}), std::string("[abc]"));
	OO_CHECK_EQ(formatRuntime("[%@]", {"\xc3\xa9t\xc3\xa9"}), std::string("[\xc3\xa9t\xc3\xa9]"));	// @"été"
	OO_CHECK_EQ(formatRuntime("[%@]", {FormatArg::null()}), std::string("[(null)]"));				// nil
	OO_CHECK_EQ(formatRuntime("[%@]", {42}), std::string("[42]"));									// numberWithInt:42
	OO_CHECK_EQ(formatRuntime("[%@]", {0.1}), std::string("[0.1]"));								// numberWithDouble:0.1
	OO_CHECK_EQ(formatRuntime("[%@]", {FormatArg::single(0.1f)}), std::string("[0.1]"));			// numberWithFloat:0.1f
	OO_CHECK_EQ(formatRuntime("[%@]", {1}), std::string("[1]"));									// numberWithBool:YES
	OO_CHECK_EQ(formatRuntime("[%@]", {18446744073709551615ull}), std::string("[18446744073709551615]"));
}

OO_TEST(objectWidthAndPrecisionCountUtf16Units)
{
	OO_CHECK_EQ(formatRuntime("[%6@][%-6@]", {"abc", "abc"}), std::string("[   abc][abc   ]"));
	OO_CHECK_EQ(formatRuntime("[%6@][%-6@]", {"\xc3\xa9t\xc3\xa9", "\xc3\xa9t\xc3\xa9"}),
				std::string("[   \xc3\xa9t\xc3\xa9][\xc3\xa9t\xc3\xa9   ]"));
	OO_CHECK_EQ(formatRuntime("[%.2@][%6.2@]", {"abc", "abc"}), std::string("[ab][    ab]"));
	OO_CHECK_EQ(formatRuntime("[%.2@]", {"\xc3\xa9t\xc3\xa9"}), std::string("[\xc3\xa9t]"));
}

OO_TEST(pointerConversion)
{
	OO_CHECK_EQ(formatRuntime("[%p]", {FormatArg::pointer(kSmall)}), std::string("[0x12345678]"));
	OO_CHECK_EQ(formatRuntime("[%p]", {FormatArg::pointer(kBig)}), std::string("[0x12345678]"));	// low 32 bits
	OO_CHECK_EQ(formatRuntime("[%p]", {FormatArg::pointer(nullptr)}), std::string("[(null)]"));
	OO_CHECK_EQ(formatRuntime("[%14p][%-14p]", {FormatArg::pointer(kSmall), FormatArg::pointer(kSmall)}),
				std::string("[    0x12345678][0x12345678    ]"));
}

OO_TEST(integerConversions)
{
	OO_CHECK_EQ(formatRuntime("[%d][%d][%5d][%-5d][%05d][%+d][% d]", {7, -7, 7, 7, 7, 7, 7}),
				std::string("[7][-7][    7][7    ][00007][+7][ 7]"));
	OO_CHECK_EQ(formatRuntime("[%02d][%07d][%02d]", {3, 1234, 123}), std::string("[03][0001234][123]"));
	OO_CHECK_EQ(formatRuntime("[%u][%u]", {7u, 4294967295u}), std::string("[7][4294967295]"));
	OO_CHECK_EQ(formatRuntime("[%ld][%lu][%lld][%llu][%zu][%qd]",
							  {-5L, 5UL, std::numeric_limits<long long>::min(), 18446744073709551615ull, 12ull, 3LL}),
				std::string("[-5][5][-9223372036854775808][18446744073709551615][12][3]"));
	OO_CHECK_EQ(formatRuntime("[%hd][%hhd][%hu]", {70000, 300, 70000}), std::string("[4464][44][4464]"));
	OO_CHECK_EQ(formatRuntime("[%x][%X][%#x][%o][%c]", {255, 255, 255, 8, 'A'}), std::string("[ff][FF][0xff][10][A]"));
}

OO_TEST(realConversions)
{
	OO_CHECK_EQ(formatRuntime("[%f][%.1f][%.1f][%8.3f][%-8.2f][%.0f][%.0f]", {0.1, 2.25, 2.35, 3.14159, 2.5, 0.5, 1.5}),
				std::string("[0.100000][2.2][2.4][   3.142][2.50    ][0][2]"));
	OO_CHECK_EQ(formatRuntime("[%g][%g][%g][%.3g][%e][%G]", {0.1, 1e20, 123456789.0, 3.14159, 12345.678, 1e-10}),
				std::string("[0.1][1e+20][1.23457e+08][3.14][1.234568e+04][1E-10]"));
	OO_CHECK_EQ(formatRuntime("[%f][%g][%f]", {std::numeric_limits<double>::infinity(), -std::numeric_limits<double>::infinity(),
											   std::numeric_limits<double>::quiet_NaN()}),
				std::string("[inf][-inf][nan]"));
	OO_CHECK_EQ(formatRuntime("[%g][%.1f]", {-0.0, -0.0}), std::string("[-0][-0.0]"));
}

OO_TEST(cStringsPercentAndLiterals)
{
	OO_CHECK_EQ(formatRuntime("[%s][%5s][%-5s][%.2s]", {"hi", "hi", "hi", "hello"}), std::string("[hi][   hi][hi   ][he]"));
	OO_CHECK_EQ(formatRuntime("[%%][100%%]"), std::string("[%][100%]"));
	OO_CHECK_EQ(formatRuntime("[50%"), std::string("[50%"));
	OO_CHECK_EQ(formatRuntime("[%k]"), std::string("[%k]"));
}

OO_TEST(positionalAndStarArguments)
{
	OO_CHECK_EQ(formatRuntime("[%2$@ %1$@]", {"a", "b"}), std::string("[b a]"));
	OO_CHECK_EQ(formatRuntime("[%2$d %1$@ %2$d]", {"x", 5}), std::string("[5 x 5]"));
	OO_CHECK_EQ(formatRuntime("[%1$5d|%2$-4@|]", {42, "ab"}), std::string("[   42|ab  |]"));
	OO_CHECK_EQ(formatRuntime("[%*d][%-*d][%.*f]", {5, 42, 4, 7, 2, 3.14159}), std::string("[   42][7   ][3.14]"));
}

OO_TEST(verifyOXPGraphvizTemplates)
{
	// OOOXPVerifier -dumpDebugGraphviz: node and arc templates as verifyOXP.plist spells them.
	OO_CHECK_EQ(formatRuntime("\tst%p [label=\"%@\\n\xe2\x80\x9c%@\xe2\x80\x9d\"];\n",
							  {FormatArg::pointer(kSmall), "OOTextureVerifierStage", "Textures"}),
				std::string("\tst0x12345678 [label=\"OOTextureVerifierStage\\n\xe2\x80\x9cTextures\xe2\x80\x9d\"];\n"));
	OO_CHECK_EQ(formatRuntime("\tst%p -> st%p\n", {FormatArg::pointer(kSmall), FormatArg::pointer(kBig)}),
				std::string("\tst0x12345678 -> st0x12345678\n"));
}

OO_TEST(missingArgumentsPrintAsNil_ADR0043)
{
	// GNUstep reads past the argument list here (undefined); oofnd prints nil / zero.
	OO_CHECK_EQ(formatRuntime("[%@][%d][%s][%p]"), std::string("[(null)][0][(null)][(null)]"));
}

OO_TEST_MAIN()
