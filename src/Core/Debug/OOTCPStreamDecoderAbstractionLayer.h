/*	OOTCPStreamDecoderAbstractionLayer.h

Abstraction layer to allow OOTCPStreamDecoder to work with CoreFoundation/
CF-Lite, Cocoa Foundation or GNUstep Foundation.
*/

#ifndef INCLUDED_OOTCPStreamDecoderAbstractionLayer_h
#define INCLUDED_OOTCPStreamDecoderAbstractionLayer_h

#ifndef OOTCPSTREAM_USE_COREFOUNDATION
#define OOTCPSTREAM_USE_COREFOUNDATION 0
#endif

#if OOTCPSTREAM_USE_COREFOUNDATION

#import "JAAutoreleasePool.h"
#include <CoreFoundation/CoreFoundation.h>

#define OOALRelease(object) CFRelease(object)

#define OOTypeDescription(object) JAAutorelease(CFCopyTypeIDDescription(CFGetTypeID(object)))

typedef CFStringRef OOALStringRef;
#define OOALIsString(object) (CFGetTypeID(object) == CFStringGetTypeID())

#define OOALSTR(str) CFSTR(str)

#define OOALStringCreateWithFormatAndArguments(format, args) CFStringCreateWithFormatAndArguments(kCFAllocatorDefault, NULL, format, args)

typedef CFDictionaryRef OOALDictionaryRef;
#define OOALIsDictionary(object) (CFGetTypeID(object) == CFDictionaryGetTypeID())

#define OOALDictionaryGetValue(dictionary, key) CFDictionaryGetValue(dictionary, key)

typedef CFDataRef OOALDataRef;
typedef CFMutableDataRef OOALMutableDataRef;
#define OOALIsData(object) (CFGetTypeID(object) == CFDataGetTypeID())

#define OOALDataCreateMutable(capacity) CFDataCreateMutable(kCFAllocatorDefault, capacity)

#define OOALMutableDataAppendBytes(data, bytes, length) CFDataAppendBytes(data, bytes, length)

#define OOALDataGetBytePtr(data) CFDataGetBytePtr(data)
#define OOALDataGetLength(data) CFDataGetLength(data)

typedef JAAutoreleasePoolRef OOALAutoreleasePoolRef;

#define OOALCreateAutoreleasePool() JACreateAutoreleasePool()
#define OOALDestroyAutoreleasePool(pool) JADestroyAutoreleasePool(pool)

#define OOALPropertyListFromData(data, errStr) JAAutorelease(CFPropertyListCreateFromXMLData(kCFAllocatorDefault, data, kCFPropertyListImmutable, errStr))

#else /* !OOTCPSTREAM_USE_COREFOUNDATION */

#include <stdarg.h>
#include <stdbool.h>
#include <stdlib.h>

/*	The handles are opaque in C and C++ alike (proposed ADR-0043 Amendment 2 item 14): a
        struct OOALObject, defined in OOTCPStreamDecoderAbstractionLayer.mm, holding a string, a
        data buffer or a property list (an oo::PList). Handles made by a Create/FromData function are
        owned (+1) and freed by OOALRelease(); OOALDictionaryGetValue(), OOTypeDescription() and
        OOALSTR() answer borrowed handles that live as long as their parent (or for ever, for
        OOALSTR). A handle from OOALPropertyListFromData() belongs to the innermost
        OOALCreateAutoreleasePool() and is freed when it is destroyed.
*/
typedef const struct OOALObject* OOALObjectRef;

typedef const struct OOALObject* OOALStringRef;
typedef const struct OOALObject* OOALDataRef;
typedef struct OOALObject* OOALMutableDataRef;
typedef const struct OOALObject* OOALDictionaryRef;
typedef struct OOALAutoreleasePool* OOALAutoreleasePoolRef;

#ifdef __cplusplus
extern "C" {
#endif
OOALStringRef OOALGetConstantString(const char* string); // Should only be used with string literals!
#ifdef __cplusplus
}
#endif

/*	In Objective-C the protocol constants (OODebugTCPConsoleProtocol.h) stay Objective-C string
        literals for OODebugTCPConsoleClient; only the C decoder spells its strings as handles.
*/
#if !(defined(__cplusplus) && !defined(OO_PLAIN_CPP_UNIT)) // was !__OBJC__ (bead oo-dbz)
#define OOALSTR(string) OOALGetConstantString("" string "")
#endif

#ifdef __cplusplus
extern "C" {
#endif

void OOALRelease(OOALObjectRef object);
OOALStringRef OOTypeDescription(OOALObjectRef object);

bool OOALIsString(OOALObjectRef object);
OOALStringRef OOALStringCreateWithFormatAndArguments(OOALStringRef format, va_list args);

bool OOALIsDictionary(OOALObjectRef object);
OOALObjectRef OOALDictionaryGetValue(OOALDictionaryRef dictionary, OOALObjectRef key);

bool OOALIsData(OOALObjectRef object);
OOALMutableDataRef OOALDataCreateMutable(size_t capacity);
void OOALMutableDataAppendBytes(OOALMutableDataRef data, const void* bytes, size_t length);
const void* OOALDataGetBytePtr(OOALDataRef data);
size_t OOALDataGetLength(OOALDataRef data);

OOALAutoreleasePoolRef OOALCreateAutoreleasePool(void);
void OOALDestroyAutoreleasePool(OOALAutoreleasePoolRef pool);

OOALObjectRef OOALPropertyListFromData(OOALMutableDataRef data, OOALStringRef* errStr);
#ifdef __cplusplus
}
#endif

#ifdef __cplusplus
extern "C++" {
#include "oofnd/PList.hpp"
// The value a handle holds, as a property list (a string or data handle as a string or data node).
const oo::PList& OOALObjectPList(OOALObjectRef object);
}
#endif

#endif /* OOTCPSTREAM_USE_COREFOUNDATION */
#endif /* INCLUDED_OOTCPStreamDecoderAbstractionLayer_h */
