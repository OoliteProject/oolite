/*	oofnd/objc/OOException.h
        The Foundation-free Objective-C exception (proposed ADR-0029 Decision 4, bead oo-3rb.5).

        Exceptions stay Objective-C in Phase 2: @try/@catch/@finally are kept exactly as they are,
        only the thrown object changes. A C++ exception would not be caught by the game's
        `@catch (id)` sites (ADR-0029 measurement 10), so moving to C++ exceptions waits for Phase 3,
        class by class.

            NSException                                   OOException
            --------------------------------------------  ----------------------------------------------
            [NSException raise:NSInvalidArgumentException [OOException raise:OOInvalidArgumentException
                        format:@"bad %@", x]                          format:"bad %s", ...]  (printf)
            [NSException exceptionWithName:reason:        [OOException exceptionWithName:reason:
                                      userInfo:nil]                                  ]  (const char *)
            [e raise], @throw e                           the same
            @catch (NSException *e)                       @catch (OOException *e)
            [e name], [e reason] (NSString *)             [e name], [e reason] (const char *, UTF-8)
            NSInvalidArgumentException & co. (NSString)   OOInvalidArgumentException & co.: const char *
                                                          with the SAME text, so logged names do not change

        +raise:format: never returns. %@ has no meaning in the format: callers pass UTF-8 strings
        (%s), class names (class_getName) and selector names (sel_getName) instead.

        Transition note: until every raise site in a call chain is converted, a `@catch (NSException *)`
        does not catch an OOException (and vice versa); `@catch (id)` catches both. Convert a raise
        site together with the handlers that expect it, or leave the handler as `@catch (id)`.
*/

#ifndef OOFND_OBJC_OOEXCEPTION_H
#define OOFND_OBJC_OOEXCEPTION_H

#include "oofnd/objc/OOObject.h"

#ifdef __cplusplus
extern "C" {
#endif

// Exception names. The text is Foundation's, so a name that reaches a log reads as it did.
extern const char* const OOGenericException;
extern const char* const OOInvalidArgumentException;
extern const char* const OORangeException;
extern const char* const OOInternalInconsistencyException;
extern const char* const OOMallocException;

#ifdef __cplusplus
}
#endif

@interface OOException : OOObject

// Autoreleased, like +[NSException exceptionWithName:reason:userInfo:]. Both strings are copied;
// nil/NULL becomes "".
+ (id)exceptionWithName:(const char*)name reason:(const char*)reason;

// Formats the reason with printf semantics, then throws. Never returns.
+ (void)raise:(const char*)name format:(const char*)format, ... __attribute__((format(printf, 2, 3), noreturn));

- (id)initWithName:(const char*)name reason:(const char*)reason;

// UTF-8, owned by the exception: valid while it is alive.
- (const char*)name;
- (const char*)reason;

// @throw self. Never returns.
- (void)raise __attribute__((noreturn));

@end

#endif // OOFND_OBJC_OOEXCEPTION_H
