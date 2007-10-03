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

#include <CoreFoundation/CoreFoundation.h>
#import "JAAutoreleasePool.h"


#define OOALRelease(object)  CFRelease(object)

#define OOTypeDescription(object)  JAAutorelease(CFCopyTypeIDDescription(CFGetTypeID(object)))



typedef CFStringRef OOALStringRef;
#define OOALIsString(object)  (CFGetTypeID(object) == CFStringGetTypeID())

#define OOALSTR(str) CFSTR(str)

#define OOALStringCreateWithFormatAndArguments(format, args)  CFStringCreateWithFormatAndArguments(kCFAllocatorDefault, NULL, format, args)



typedef CFDictionaryRef OOALDictionaryRef;
#define OOALIsDictionary(object)  (CFGetTypeID(object) == CFDictionaryGetTypeID())

#define OOALDictionaryGetValue(dictionary, key)  CFDictionaryGetValue(dictionary, key)



typedef CFDataRef OOALDataRef;
typedef CFMutableDataRef OOALMutableDataRef;
#define OOALIsData(object)  (CFGetTypeID(object) == CFDataGetTypeID())

#define OOALDataCreateMutable(capacity)  CFDataCreateMutable(kCFAllocatorDefault, capacity)

#define OOALMutableDataAppendBytes(data, bytes, length)  CFDataAppendBytes(data, bytes, length)

#define OOALDataGetBytePtr(data)  CFDataGetBytePtr(data)
#define OOALDataGetLength(data)  CFDataGetLength(data)



typedef JAAutoreleasePoolRef OOALAutoreleasePoolRef;

#define OOALCreateAutoreleasePool()  JACreateAutoreleasePool()
#define OOALDestroyAutoreleasePool(pool)  JADestroyAutoreleasePool(pool)



#define OOALPropertyListFromData(data, errStr)  JAAutorelease(CFPropertyListCreateFromXMLData(kCFAllocatorDefault, data, kCFPropertyListImmutable, errStr))

#else	/* !OOTCPSTREAM_USE_COREFOUNDATION */

#include <stdarg.h>
#include <stdbool.h>
#include <stdlib.h>


#if __OBJC__

#import <Foundation/Foundation.h>

typedef id								OOALObjectRef;

typedef NSString						*OOALStringRef;
typedef NSData							*OOALDataRef;
typedef NSMutableData					*OOALMutableDataRef;
typedef NSDictionary					*OOALDictionaryRef;
typedef NSAutoreleasePool				*OOALAutoreleasePoolRef;

#define OOALSTR(x) @""x

#else

typedef const void						*OOALObjectRef;

typedef const struct NSString			*OOALStringRef;
typedef const struct NSData				*OOALDataRef;
typedef struct NSData					*OOALMutableDataRef;
typedef const struct NSDictionary		*OOALDictionaryRef;
typedef const struct NSAutoreleasePool	*OOALAutoreleasePoolRef;

OOALStringRef OOALGetConstantString(const char *string);	// Should only be used with string literals!
#define OOALSTR(string) OOALGetConstantString("" string "")

#endif


void OOALRelease(OOALObjectRef object);
OOALStringRef OOTypeDescription(OOALObjectRef object);

bool OOALIsString(OOALObjectRef object);
OOALStringRef OOALStringCreateWithFormatAndArguments(OOALStringRef format, va_list args);

bool OOALIsDictionary(OOALObjectRef object);
OOALObjectRef OOALDictionaryGetValue(OOALDictionaryRef dictionary, OOALObjectRef key);

bool OOALIsData(OOALObjectRef object);
OOALMutableDataRef OOALDataCreateMutable(size_t capacity);
void OOALMutableDataAppendBytes(OOALMutableDataRef data, const void *bytes, size_t length);
const void *OOALDataGetBytePtr(OOALDataRef data);
size_t OOALDataGetLength(OOALDataRef data);

OOALAutoreleasePoolRef OOALCreateAutoreleasePool(void);
#define OOALDestroyAutoreleasePool(pool) OOALRelease(pool)

OOALObjectRef OOALPropertyListFromData(OOALMutableDataRef data, OOALStringRef *errStr);

#endif /* OOTCPSTREAM_USE_COREFOUNDATION */
#endif /* INCLUDED_OOTCPStreamDecoderAbstractionLayer_h */
