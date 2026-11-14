/*	oofnd/objc/OOConstantString.h
        The class behind @"..." literals once libgnustep-base is gone (proposed ADR-0029, bead
        oo-3rb.1). Selected with -fconstant-string-class=OOConstantString; until oo-qps the game keeps
        GNUstep's NSConstantString and this class is exercised only by the oofnd unit test.

        What clang emits for a literal under -fobjc-runtime=gnustep-2.2 (measured, see the ADR):

          * 9 characters or more, or any non-ASCII character: a static object with the layout below,
            whose isa is this class. flags == 0: `data` is `length` ASCII bytes, NUL-terminated.
            flags == 2: `data` is `length` UTF-16 code units (`size` bytes). `hash` is emitted as 0.
          * 1 to 8 ASCII characters: NOT an object but a small-object (tagged) pointer with tag 4:
            bits 0-2 the tag, bits 3-7 the length, then 7 bits per character from bit 57 down.
            Messaging it needs a class registered for tag 4: OOTinyString, registered by
            OOObjCInstallFloor(). Without that registration every message to it returns nil.

        Both are immortal: -retain/-release/-autorelease are no-ops, so objc_retain()/objc_release()
        send them rather than touching a reference count the literal does not have. -length counts
        UTF-16 code units, as NSString's does. -UTF8String is valid for the life of the process.

        This is a floor, not a string library: the sweeps move string work onto oo::String
        (std::string); what remains of @"..." needs only -UTF8String, -length, -isEqual: and -hash.
*/

#ifndef OOFND_OBJC_OOCONSTANTSTRING_H
#define OOFND_OBJC_OOCONSTANTSTRING_H

#include "oofnd/objc/OOObject.h"

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Registers OOTinyString as libobjc2's small-object class for clang's short-literal tag. Called by
// OOObjCInstallFloor(); idempotent; aborts if the tag belongs to another class.
void OOConstantStringInstall(void);

#ifdef __cplusplus
}
#endif

// The small-object tag clang's gnustep-2 code generator uses for short string literals.
#define OO_TINY_STRING_TAG 4

@interface OOConstantString : OOObject <OOCopying> {
@public
    // Layout fixed by clang's gnustep-2 ABI (CGObjCGNUstep2::GenerateConstantString).
    uint32_t flags;
    uint32_t length;
    uint32_t size;
    uint32_t hash;
    const char* data;
}

- (const char*)UTF8String;
- (uintptr_t)length;
- (BOOL)isEqualToString:(OOConstantString*)other;

@end

// The class of short (tagged-pointer) literals. A subclass so that
// [x isKindOfClass:[OOConstantString class]] holds for every literal; it overrides every method
// that would otherwise read an ivar, because a tagged pointer has no storage.
@interface OOTinyString : OOConstantString
@end

#endif // OOFND_OBJC_OOCONSTANTSTRING_H
