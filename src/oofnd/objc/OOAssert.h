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

        LIVE IN EVERY FLAVOUR, deployment (NDEBUG) included, because Foundation's were.
        Upstream's OOFoundation.h defines NS_BLOCK_ASSERTIONS iff NDEBUG, but only AFTER it imports
        the Foundation umbrella header, and gnustep-base's include-guarded exception header picks the
        blocked or live assertion macros when it is first parsed, so the define came too late and
        never blocked anything. Blocking these under NDEBUG skips the side effect in PlayerEntity's
        -deferredInit assertion (the player's ship set-up), and a deployment build cannot launch.
        The arguments are always evaluated, and a false condition logs one line in message class
        "gnustep" (where the NSLog
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

#include "oofnd/objc/OOException.h"

#ifdef __cplusplus
extern "C" {
#endif

// Log and raise; never return. Called by the macros below, not directly.
void OOAssertFailedInMethod(id object, SEL selector, const char* file, long line, const char* format, ...)
    __attribute__((format(printf, 5, 6), noreturn));
void OOAssertFailedInFunction(const char* function, const char* file, long line, const char* format, ...)
    __attribute__((format(printf, 4, 5), noreturn));

#ifdef __cplusplus
}
#endif

// Not conditional on NDEBUG: see the head of this file.
#define OOAssert(condition, ...)                                                 \
    do {                                                                         \
        if (!(condition))                                                        \
            OOAssertFailedInMethod(self, _cmd, __FILE__, __LINE__, __VA_ARGS__); \
    } while (0)
#define OOCAssert(condition, ...)                                                           \
    do {                                                                                    \
        if (!(condition))                                                                   \
            OOAssertFailedInFunction(__PRETTY_FUNCTION__, __FILE__, __LINE__, __VA_ARGS__); \
    } while (0)

#define OOParameterAssert(condition) OOAssert((condition), "Invalid parameter not satisfying: %s", #condition)
#define OOCParameterAssert(condition) OOCAssert((condition), "Invalid parameter not satisfying: %s", #condition)

#endif // OOFND_OBJC_OOASSERT_H
