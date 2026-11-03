/*

OODebugStandards+FoundationBridge.h

TRANSITIONAL (proposed ADR-0043, "Transitional bridges"; bead oo-56ct). OODebugStandards's
Foundation-typed API as it was before its sweep, with the same names and types, forwarding to the
cxx_ API in OODebugStandards.h. It exists so that OODebugStandards's callers (14 files) compile
unchanged; each caller moves to the cxx_ API in its own sweep bead. When `git grep` finds no caller
of anything declared here, the bridge bead deletes this file, OODebugStandards+FoundationBridge.mm,
its line in Debug/meson.build and the #import at the end of OODebugStandards.h. Never add to it;
never call it from migrated code. oo-qps (the removal of gnustep-base) cannot compile while it
exists.

Registry: src/oofnd/README.md, "Transitional bridges".

Copyright (C) 2014 (OODebugStandards.h)

*/

// Imported only from the end of OODebugStandards.h (which imports everything used here); never
// import it directly, and never import OODebugStandards.h from it (a cycle).
#ifndef OODEBUGSTANDARDS_FOUNDATIONBRIDGE_H
#define OODEBUGSTANDARDS_FOUNDATIONBRIDGE_H

#ifdef __cplusplus
extern "C" {
#endif

// Warn/exit if deprecated functionality used
void OOStandardsDeprecated(NSString* message); // -> cxx_OOStandardsDeprecated

// Warn/exit if an OXP error is detected
void OOStandardsError(NSString* message); // -> cxx_OOStandardsError

#ifdef __cplusplus
}
#endif

#endif // OODEBUGSTANDARDS_FOUNDATIONBRIDGE_H
