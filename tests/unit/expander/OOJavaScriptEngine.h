// Stub for tests/unit/expander (bead oo-3rb.61): only what src/Core/OOStringExpander.mm uses.
#pragma once
#include "OOFoundation.h"
#include <cstdarg>
typedef struct JSContext JSContext;
JSContext *OOJSAcquireContext(void);
void OOJSRelinquishContext(JSContext *context);
// The C++ form the expander calls since bead oo-vp0y.10 (printf format; bead oo-qqz6: stub-API tracking).
void cxx_OOJSReportWarningWithArguments(JSContext *context, const char *format, va_list args);
