/*

OOHPVector+FoundationBridge.h

TRANSITIONAL (proposed ADR-0043, "Transitional bridges"; bead oo-dlox). OOHPVector's Foundation-typed
functions as they were before its sweep, with the same names, types and C linkage, forwarding to
the cxx_ functions in OOHPVector.h. It exists so that OOHPVector's callers compile unchanged; each
caller moves to the cxx_ API in its own sweep bead. When `git grep` finds no caller of anything
declared here, the bridge bead deletes this file, OOHPVector+FoundationBridge.mm, its line in
Core/meson.build and the #import at the end of OOHPVector.h. Never add to it; never call it from
migrated code. oo-qps (the removal of gnustep-base) cannot compile while it exists.

Registry: src/oofnd/README.md, "Transitional bridges".

Copyright (C) 2004-2013 Giles C Williams and contributors (OOHPVector.h)

*/

// Imported only from the end of OOHPVector.h (inside OOMaths.h's extern "C", which declares
// everything used here); never import it directly, and never import OOMaths.h from it (a cycle).
#ifndef OOHPVECTOR_FOUNDATIONBRIDGE_H
#define OOHPVECTOR_FOUNDATIONBRIDGE_H

NSString* HPVectorDescription(HPVector vector); // @"(x, y, z)" -> cxx_HPVectorDescription
NSArray* ArrayFromHPVector(HPVector vector); // -> cxx_ArrayFromHPVector

#endif // OOHPVECTOR_FOUNDATIONBRIDGE_H
