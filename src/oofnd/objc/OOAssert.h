/*	oofnd/objc/OOAssert.h
        Foundation-free assertions with the semantics of gnustep-base 1.31.1's
   macros (pinned with a throwaway harness). OOCAssert(cond, fmt, ...) stands
   for NSCAssert, NSAssert and their numbered forms; OOCParameterAssert(cond)
   for NSParameterAssert and NSCParameterAssert. The format is printf-style:
   pass UTF-8 strings with %s, never %@.

        LIVE IN EVERY FLAVOUR, deployment (NDEBUG) included, because
   Foundation's were. Upstream's OOFoundation.h defines NS_BLOCK_ASSERTIONS iff
   NDEBUG, but only AFTER it imports the Foundation umbrella header, and
   gnustep-base's include-guarded exception header picks the blocked or live
   assertion macros when it is first parsed, so the define came too late and
   never blocked anything. Blocking these under NDEBUG skips the side effect in
   PlayerEntity's -deferredInit assertion (the player's ship set-up), and a
   deployment build cannot launch.

        The arguments are always evaluated. A false condition logs one line in
   message class "gnustep" (where gnustep-base's assertion log went) and raises
   an OOException named OOInternalInconsistencyException, the parameter form
   too, with Foundation's reason text: "<file>:<line>  Assertion failed in
   <function>.  <message>". The parameter form's message is "Invalid parameter
   not satisfying: <condition>".
*/

#pragma once

/*	There are no method forms (OOAssert, OOParameterAssert: self/_cmd): no
   game code calls them. A game C++ unit gets OOException.h from here; a plain
   C or C++ translation unit (OO_PLAIN_CPP_UNIT, e.g. OOConstToJSString) does
   not.
*/
#ifndef OO_PLAIN_CPP_UNIT
#include "oofnd/objc/OOException.h"
#endif
#include "oofnd/PrintfFormat.h"

// Log and raise; never return. Called by the macros below, not directly.
void OOAssertFailedInFunction(const char* function, const char* file, long line,
                              const char* format, ...) OO_PRINTF_FORMAT(4, 5)
    __attribute__((noreturn));

// Not conditional on NDEBUG: see the head of this file.
#define OOCAssert(condition, ...)                                       \
  do {                                                                  \
    if (!(condition))                                                   \
      OOAssertFailedInFunction(__PRETTY_FUNCTION__, __FILE__, __LINE__, \
                               __VA_ARGS__);                            \
  } while (0)

#define OOCParameterAssert(condition) \
  OOCAssert((condition), "Invalid parameter not satisfying: %s", #condition)
