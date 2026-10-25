/*	oofnd/objc/OOAssert.h
	Foundation-free assertions (bead oo-diow, the NSAssert seam of the oo-qps gap sweep; proposed
	ADR-0029 floor). Same semantics as gnustep-base 1.31.1's macros, pinned with a throwaway
	harness (a method, a class method and a C function, each plain and parameter form):

	    Foundation                                  here
	    ------------------------------------------  ---------------------------------------------
	    NSAssert(cond, @"fmt %@", obj)              OOAssert(cond, "fmt %s", text)      (printf)
	    NSAssert1 .. NSAssert5                      OOAssert (variadic)
	    NSCAssert(cond, @"fmt", ...), NSCAssert1..5 OOCAssert(cond, "fmt", ...)
	    NSParameterAssert(cond)                     OOParameterAssert(cond)
	    NSCParameterAssert(cond)                    OOCParameterAssert(cond)

	Blocked exactly when Foundation's were: OOCocoa.h defines NS_BLOCK_ASSERTIONS iff NDEBUG, so
	these test NDEBUG. Blocked, a macro expands to an empty statement and its arguments are not
	evaluated. Otherwise a false condition logs one line in message class "gnustep" (where the NSLog
	hook, OOLogOutputHandler, sent gnustep-base's assertion log; NSLog's own date/process prefix is
	not reproduced) and raises an OOException named OOInternalInconsistencyException (the parameter
	forms too, as in gnustep-base) with Foundation's reason text:

	    <__FILE__>:<__LINE__>  Assertion failed in <Class>(instance), method <selector>.  <message>
	    <__FILE__>:<__LINE__>  Assertion failed in <__PRETTY_FUNCTION__>.  <message>

	(gnustep-base prints "(instance)" for a class method too: it names [self class], never a
	metaclass.) The parameter forms' message is "Invalid parameter not satisfying: <#cond>".
	%@ has no meaning in the format: pass UTF-8 strings (%s), as with +[OOException raise:format:].
*/

#ifndef OOFND_OBJC_OOASSERT_H
#define OOFND_OBJC_OOASSERT_H

/*	The method forms (OOAssert, OOParameterAssert: self/_cmd) went with libobjc2 (bead oo-dbz): no game
	code called them. A game unit (an Objective-C++ unit until oo-dbz) still gets OOException.h from
	here, as it did; a plain C or C++ translation unit (bead oo-9ht.64: OOConstToJSString) does not.
*/
#if defined(__cplusplus) && !defined(OO_PLAIN_CPP_UNIT)	// was __OBJC__ (bead oo-dbz)
#include "oofnd/objc/OOException.h"
#endif
#include "oofnd/PrintfFormat.h"

#ifdef __cplusplus
extern "C" {
#endif

// Log and raise; never return. Called by the macros below, not directly.
void OOAssertFailedInFunction(const char *function, const char *file, long line, const char *format, ...)
	OO_PRINTF_FORMAT(4, 5) __attribute__((noreturn));

#ifdef __cplusplus
}
#endif

#ifdef NDEBUG
#define OOCAssert(condition, ...)			do { } while (0)
#else
#define OOCAssert(condition, ...) \
	do { if (!(condition))  OOAssertFailedInFunction(__PRETTY_FUNCTION__, __FILE__, __LINE__, __VA_ARGS__); } while (0)
#endif

#define OOCParameterAssert(condition)		OOCAssert((condition), "Invalid parameter not satisfying: %s", #condition)

#endif	// OOFND_OBJC_OOASSERT_H
