/*	test_FormatEquivalence.cpp
        The printf formats the game used and the std::format
   formats that replace them print the same bytes. Each row is a printf format
   with oo::str::format against its std::format replacement, with the argument
   types and the casts the conversion uses (clang-tidy's modernize-use-std-format
   in StrictMode keeps printf's signedness with a static_cast). Rows are only
   ever added, never changed. Run: tests/run.sh unit
*/

#include <cstddef>
#include <cstdint>
#include <format>
#include <limits>
#include <string>

#include "oo_test.hpp"
#include "oofnd/String.hpp"

#define SAME(printfCall, stdCall) OO_CHECK_EQ(std::string(printfCall), std::string(stdCall))

OO_TEST(stringsAndSignedIntegers) {
  const std::string s = "words";
  SAME(oo::str::format("%s", s.c_str()), std::format("{}", s));
  SAME(oo::str::format("%s %d %s", "a", 3, s.c_str()), std::format("{} {} {}", "a", 3, s));
  for (int v : {0, 1, -1, 42, std::numeric_limits<int>::max(), std::numeric_limits<int>::min()}) {
    SAME(oo::str::format("%d", v), std::format("{}", v));
    SAME(oo::str::format("%i", v), std::format("{}", v));
  }
}

OO_TEST(signednessIsKeptByTheCast) {
  // %d of an unsigned argument: printf reads it as int.
  for (unsigned v : {0u, 7u, 2147483647u, 2147483648u, 4294967295u})
    SAME(oo::str::format("%d", v), std::format("{}", static_cast<int>(v)));
  // %u of a signed argument: printf reads it as unsigned.
  for (int v : {0, 7, -1, std::numeric_limits<int>::min()})
    SAME(oo::str::format("%u", v), std::format("{}", static_cast<unsigned>(v)));
  // A uint16_t is promoted to int, so %d prints it as is.
  for (std::uint16_t v : {std::uint16_t{0}, std::uint16_t{100}, std::uint16_t{65535}})
    SAME(oo::str::format("%d", v), std::format("{}", v));
}

OO_TEST(sizesAnd64BitIntegers) {
  for (std::size_t v : {std::size_t{0}, std::size_t{12345}, std::numeric_limits<std::size_t>::max()})
    SAME(oo::str::format("%zu", v), std::format("{}", v));
  for (std::ptrdiff_t v : {std::ptrdiff_t{0}, std::ptrdiff_t{-5}, std::numeric_limits<std::ptrdiff_t>::max()})
    SAME(oo::str::format("%zd", v), std::format("{}", v));
  for (unsigned long long v : {0ull, 18446744073709551615ull})
    SAME(oo::str::format("%llu", v), std::format("{}", v));
  for (std::uint64_t v : {std::uint64_t{0}, std::uint64_t{123456789012345}})
    SAME(oo::str::format("%016llx", static_cast<unsigned long long>(v)), std::format("{:016x}", v));
}

OO_TEST(hexAndCharacters) {
  for (unsigned v : {0u, 255u, 0xabcdefu})
    SAME(oo::str::format("%06x", v), std::format("{:06x}", v));
  for (unsigned v : {0u, 0x1fu, 0xffffu})
    SAME(oo::str::format("%.4X", v), std::format("{:04X}", v));
  for (int c : {'A', 'z', ' '})
    SAME(oo::str::format("%c", c), std::format("{:c}", static_cast<char>(c)));
}

OO_TEST(floatsWithPrecision) {
  for (double v : {0.0, 1.0, -1.5, 3.14159265, 1234567.0, 1e-7, 1e20}) {
    SAME(oo::str::format("%g", v), std::format("{:g}", v));
    SAME(oo::str::format("%f", v), std::format("{:f}", v));
    SAME(oo::str::format("%.2f", v), std::format("{:.2f}", v));
    SAME(oo::str::format("%.3f", v), std::format("{:.3f}", v));
    SAME(oo::str::format("%.3g", v), std::format("{:.3g}", v));
  }
  for (int precision : {0, 1, 4})
    SAME(oo::str::format("%.*f", precision, 2.71828), std::format("{:.{}f}", 2.71828, precision));
}

OO_TEST(floatArgumentsWithG) {
  // printf widens a float to double; std::format formats the float itself. The widening is
  // exact, so both round the same value (DustEntity's shader prefix passes floats to {:g}).
  for (float v : {0.0f, 1.0f / 3.0f, 0.1f, 3.14159265f, 1e-7f, 65536.0f, 1e20f, 4.0e4f / 0.5f})
    SAME(oo::str::format("%g", static_cast<double>(v)), std::format("{:g}", v));
}

OO_TEST(widthAndAlignment) {
  // printf right-aligns strings; std::format left-aligns them unless told.
  SAME(oo::str::format("%60s", "right"), std::format("{:>60}", "right"));
  SAME(oo::str::format("%5d", 42), std::format("{:5}", 42));
}

OO_TEST_MAIN()
