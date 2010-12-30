#include "wtf/Assertions.h"

#include <CoreFoundation/CoreFoundation.h>
extern "C" void OOLogWithPrefix(CFStringRef messageClass, const char *function, const char *file, unsigned long line, CFStringRef prefix, CFStringRef format, ...);
extern "C" CFStringRef OOLogAbbreviatedFileName(const char *inName);


void WTFReportAssertionFailure(const char* file, int line, const char* function, const char* assertion)
{
	OOLogWithPrefix(CFSTR("javascript.wtf.assert"), function, file, line, CFSTR(""), CFSTR("ASSERTION FAILURE at %@:%d: %s"), OOLogAbbreviatedFileName(file), line, assertion);
	__builtin_trap();
}
