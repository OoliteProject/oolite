// Stub for tests/unit/expander (bead oo-3rb.61): only what src/Core/OOStringExpander.mm uses.
#pragma once
// The C++ forms the expander calls since bead oo-3rb.147, over the harness's credits formatter
// (test_string_expander.cpp; Foundation-free since bead oo-6e1.2, the same text). The Foundation
// forms OOCredits/OOIntCredits went with the harness's Foundation.
#include "OOFoundation.h"
#include "OOTypes.h"
#ifdef __cplusplus
#include <string>
std::string OOHarnessCredits(OOCreditsQuantity tenths, bool decimal);
static inline std::string cxx_OOCredits(OOCreditsQuantity tenthsOfCredits) { return OOHarnessCredits(tenthsOfCredits, true); }
static inline std::string cxx_OOIntCredits(OOCreditsQuantity integerCredits) { return OOHarnessCredits(integerCredits * 10, false); }
#endif
