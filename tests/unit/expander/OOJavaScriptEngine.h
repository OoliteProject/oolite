// Stub for tests/unit/expander (bead oo-3rb.61): only what src/Core/OOStringExpander.mm uses.
#import "OOFoundation.h"
typedef struct JSContext JSContext;
JSContext *OOJSAcquireContext(void);
void OOJSRelinquishContext(JSContext *context);
void OOJSReportWarningWithArguments(JSContext *context, NSString *format, va_list args);
