/*	OOTCPStreamDecoderAbstractionLayer.h

The handle types and functions OOTCPStreamDecoder works through: strings, data
buffers and property lists, implemented over oofnd.
*/

#pragma once

#include <stdarg.h>
#include <stdbool.h>
#include <stdlib.h>

/*	The handles are opaque in C and C++ alike: a struct OOALObject, defined
   in OOTCPStreamDecoderAbstractionLayer.cpp, holding a string, a data buffer or
   a property list (an oo::PList). Handles made by a Create/FromData function
   are owned (+1) and freed by OOALRelease(); OOALDictionaryGetValue(),
   OOTypeDescription() and OOALSTR() answer borrowed handles that live as long
   as their parent (or for ever, for OOALSTR). A handle from
   OOALPropertyListFromData() belongs to the innermost
        OOALCreateAutoreleasePool() and is freed when it is destroyed.
*/
typedef const struct OOALObject* OOALObjectRef;

typedef const struct OOALObject* OOALStringRef;
typedef const struct OOALObject* OOALDataRef;
typedef struct OOALObject* OOALMutableDataRef;
typedef const struct OOALObject* OOALDictionaryRef;
typedef struct OOALAutoreleasePool* OOALAutoreleasePoolRef;

OOALStringRef OOALGetConstantString(
    const char* string);  // Should only be used with string literals!

/*	Only the C decoder spells its protocol constants
   (OODebugTCPConsoleProtocol.h) as handles; OODebugTCPConsoleClient uses plain
   literals.
*/
#ifdef OO_PLAIN_CPP_UNIT
#define OOALSTR(string) OOALGetConstantString("" string "")
#endif

void OOALRelease(OOALObjectRef object);
OOALStringRef OOTypeDescription(OOALObjectRef object);

bool OOALIsString(OOALObjectRef object);
OOALStringRef OOALStringCreateWithFormatAndArguments(OOALStringRef format,
                                                     va_list args);

bool OOALIsDictionary(OOALObjectRef object);
OOALObjectRef OOALDictionaryGetValue(OOALDictionaryRef dictionary,
                                     OOALObjectRef key);

bool OOALIsData(OOALObjectRef object);
OOALMutableDataRef OOALDataCreateMutable(size_t capacity);
void OOALMutableDataAppendBytes(OOALMutableDataRef data, const void* bytes,
                                size_t length);
const void* OOALDataGetBytePtr(OOALDataRef data);
size_t OOALDataGetLength(OOALDataRef data);

OOALAutoreleasePoolRef OOALCreateAutoreleasePool(void);
void OOALDestroyAutoreleasePool(OOALAutoreleasePoolRef pool);

OOALObjectRef OOALPropertyListFromData(OOALMutableDataRef data,
                                       OOALStringRef* errStr);

#include "oofnd/PList.hpp"
// The value a handle holds, as a property list (a string or data handle as a
// string or data node).
const oo::PList& OOALObjectPList(OOALObjectRef object);
