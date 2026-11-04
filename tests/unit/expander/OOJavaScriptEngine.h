// Stub for tests/unit/expander: only what
// src/Core/OOStringExpander.mm uses.
#pragma once
#include "OOFoundation.h"
#include <cstdarg>
typedef struct JSContext JSContext;
JSContext *OOJSAcquireContext(void);
void OOJSRelinquishContext(JSContext *context);
// The C++ form the expander calls (printf format).
void cxx_OOJSReportWarningWithArguments(JSContext *context, const char *format, va_list args);
