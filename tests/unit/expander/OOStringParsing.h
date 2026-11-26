// Stub for tests/unit/expander: only what
// src/Core/OOStringExpander.mm uses.
#pragma once
// The C++ forms the expander calls, over the harness's credits formatter
// (test_string_expander.cpp; Foundation-free, the same text).
#include "OOFoundation.h"
#include "OOTypes.h"
#ifdef __cplusplus
#include <string>
std::string OOHarnessCredits(OOCreditsQuantity tenths, bool decimal);
static inline std::string cxx_OOCredits(OOCreditsQuantity tenthsOfCredits) {
  return OOHarnessCredits(tenthsOfCredits, true);
}
static inline std::string cxx_OOIntCredits(OOCreditsQuantity integerCredits) {
  return OOHarnessCredits(integerCredits * 10, false);
}
#endif
