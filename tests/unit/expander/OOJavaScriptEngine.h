// Stub for tests/unit/expander (bead oo-3rb.61): only what src/Core/OOStringExpander.mm uses.
#pragma once
#include "OOCocoa.h"
#include <cstdarg>
namespace ooscript { struct Context { void *p; }; }
ooscript::Context OOJSAcquireContext(void);
void OOJSRelinquishContext(ooscript::Context context);
// The C++ form the expander calls since bead oo-vp0y.10 (printf format; bead oo-qqz6: stub-API tracking).
void cxx_OOJSReportWarningWithArguments(ooscript::Context context, const char *format, va_list args);
