/*	oofnd/objc/OOObject.h
        The Foundation-free Objective-C root class OOObject (proposed ADR-0029, bead oo-3rb.1), its
        protocols (OOObject, OOCopying, OOMutableCopying), the OOConstantString class behind @"..."
        literals and OOObjCInstallFloor() were deleted by bead oo-4aq6a.8: no game class or test is
        rooted on OOObject and no @"..." literal is compiled (ADR-0056 amendment oo-4aq6a.8).

        This header stays as a forwarding header so its includers need no change: it gives them what
        they still had from it, the runtime's types (id, Class, SEL, BOOL; <objc/runtime.h>) and the
        opaque OOZone (always nil) that OOMesh's copy members still name. Both go with libobjc2 (oo-dbz).
*/

#ifndef OOFND_OBJC_OOOBJECT_H
#define OOFND_OBJC_OOOBJECT_H

#include <stdint.h>

// NSZone is a GNUstep-only concept Oolite never uses beyond passing it through; always nil.
typedef struct OOZone OOZone;

#endif // OOFND_OBJC_OOOBJECT_H
