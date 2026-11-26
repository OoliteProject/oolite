/*	oofnd/objc/OOObject.h
        A forwarding header: no game class or test is rooted on OOObject and no
   @"..." literal is compiled, so it gives its includers only the runtime's
   types (id, Class, SEL, bool; <objc/runtime.h>) and the opaque OOZone (always
   nil) that OOMesh's copy members still name.
*/

#pragma once

#include <stdint.h>

// NSZone is a GNUstep-only concept Oolite never uses beyond passing it through;
// always nil.
typedef struct OOZone OOZone;
