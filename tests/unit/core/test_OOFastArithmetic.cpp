/*	test_OOFastArithmetic.mm
        Unit tests for OORoundUpToPowerOf2_32/_64/_NS
   (src/Core/OOFastArithmetic.h).

        The expression the functions shared with upstream had no defined value
   for 1 (__builtin_clz(0)) nor for 0 and values above the high bit (a shift by
   -1), so the -O2 test and game builds and the -O0 debug build disagreed:
   test_OOTextureLoader and test_OOConcreteTexture pin the -O2 answer (a 2-pixel
   side, (2 * 2) / 3 == 1, rounds up to 2) and failed in the debug flavour.
   Those inputs now return what the optimised x86-64 build returned (printed by
   a probe of the unfixed -O2 build, and read off its disassembly): 2 for 1, 1
   for 0 and for values above the high bit. Every other input is the plain
   mathematical answer. On the unfixed header these checks themselves failed at
        -O2: the optimiser folded the comparisons of an undefined result to
   false. The inputs pass through volatiles so the compiler evaluates the
   functions at run time, as the game does, and not by constant folding. Run:
   bash tools/check-core-tests.sh test_OOFastArithmetic (both flavours: test and
   debug)
*/

#include "OOMaths.h"
#include "oo_test.hpp"

namespace {

uint32_t Round32(uint32_t value) {
  volatile uint32_t in = value;
  return OORoundUpToPowerOf2_32(in);
}

uint64_t Round64(uint64_t value) {
  volatile uint64_t in = value;
  return OORoundUpToPowerOf2_64(in);
}

}  // namespace

OO_TEST(edgeInputsKeepTheOptimisedAnswer) {
  OO_CHECK(Round32(1) == 2);
  OO_CHECK(Round32(0) == 1);
  OO_CHECK(Round32(0x80000001U) == 1);
  OO_CHECK(Round32(0xC0000000U) == 1);
  OO_CHECK(Round32(0xFFFFFFFFU) == 1);

  OO_CHECK(Round64(1) == 2);
  OO_CHECK(Round64(0) == 1);
  OO_CHECK(Round64(0x8000000000000001ULL) == 1);
  OO_CHECK(Round64(0xFFFFFFFFFFFFFFFFULL) == 1);

  volatile NSUInteger one = 1;
  OO_CHECK(OORoundUpToPowerOf2_NS(one) == 2);
}

OO_TEST(roundsUpToThePowerOfTwo) {
  OO_CHECK(Round32(2) == 2);
  OO_CHECK(Round32(3) == 4);
  OO_CHECK(Round32(4) == 4);
  OO_CHECK(Round32(5) == 8);
  OO_CHECK(Round32(0x7FFFFFFFU) == 0x80000000U);
  OO_CHECK(Round32(0x80000000U) == 0x80000000U);
  OO_CHECK(Round64(3) == 4);
  OO_CHECK(Round64(0x100000001ULL) == 0x200000000ULL);
  OO_CHECK(Round64(0x8000000000000000ULL) == 0x8000000000000000ULL);

  // Every power of two, one below and one above it.
  bool all = true;
  for (unsigned bit = 1; bit < 32; bit++) {
    uint32_t p = 1U << bit;
    all = all && Round32(p) == p && Round32(p - 1) == ((bit == 1) ? 2U : p) &&
          (bit == 31 || Round32(p + 1) == p << 1);
  }
  for (unsigned bit = 1; bit < 64; bit++) {
    uint64_t p = 1ULL << bit;
    all = all && Round64(p) == p && Round64(p - 1) == ((bit == 1) ? 2ULL : p) &&
          (bit == 63 || Round64(p + 1) == p << 1);
  }
  OO_CHECK(all);
}

OO_TEST(aTwoPixelSideScalesToTwo) {
  // OOTextureLoader::getDesiredWidth and OOTextureVerifierStage: (2 * side) / 3
  // (OORoundUpToPowerOf2_PixMap is the 32-bit one).
  volatile uint32_t side = 2;
  OO_CHECK(OORoundUpToPowerOf2_32((2 * side) / 3) == 2);
  side = 4;
  OO_CHECK(OORoundUpToPowerOf2_32((2 * side) / 3) == 2);
}

OO_TEST_MAIN()
