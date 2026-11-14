// Stub for tests/unit/expander (bead oo-3rb.61): only what src/Core/OOStringExpander.mm uses.
#import "OOFoundation.h"
#import "OOTypes.h"
NSString *OOHarnessCredits(OOCreditsQuantity tenths, BOOL decimal);
static inline NSString *OOCredits(OOCreditsQuantity tenthsOfCredits) { return OOHarnessCredits(tenthsOfCredits, YES); }
static inline NSString *OOIntCredits(OOCreditsQuantity integerCredits) { return OOHarnessCredits(integerCredits * 10, NO); }
// C++ forms the expander calls since bead oo-3rb.147 (oo-1886 chunk 2), over the same harness
// credits formatter (additive: the lines above are unchanged).
#ifdef __cplusplus
#import "OOFoundationBridge.h"	// the harness stub (bead oo-3rb.335): OOStringBridge.h went with oo-qps.16
static inline std::string cxx_OOCredits(OOCreditsQuantity tenthsOfCredits) { return oo::StdString(OOCredits(tenthsOfCredits)); }
static inline std::string cxx_OOIntCredits(OOCreditsQuantity integerCredits) { return oo::StdString(OOIntCredits(integerCredits)); }
#endif
