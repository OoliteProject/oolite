/*

Entity+FoundationBridge.h

TRANSITIONAL (proposed ADR-0043, "Transitional bridges"; bead oo-2qdy). The Foundation-typed
C functions Entity.h declared before its sweep, moved here verbatim (same names, types and C
linkage). Their definitions are the forwarders in OOConstToString+FoundationBridge.mm (oo-3rb.161)
to the cxx_ forms declared at the end of Entity.h; callers in PlayerEntity.mm, ShipEntity.mm,
PlayerEntityLegacyScriptEngine.mm, ShipEntityAI.mm, ShipEntityLoadRestore.mm and the scripting
files compile unchanged and move to the cxx_ functions in their own sweep beads. When `git grep`
finds no caller of anything declared here, the bridge bead deletes this file and the #import at
the end of Entity.h. Never add to it; never call it from migrated code. oo-qps (the removal of
gnustep-base) cannot compile while it exists.

Registry: src/oofnd/README.md, "Transitional bridges".

Copyright (C) 2004-2013 Giles C Williams and contributors (Entity.h)

*/

// Imported only from the end of Entity.h (which declares everything used here); never import it
// directly, and never import Entity.h from it (a cycle).
#ifndef ENTITY_FOUNDATIONBRIDGE_H
#define ENTITY_FOUNDATIONBRIDGE_H

#ifdef __cplusplus
extern "C" {
#endif

NSString* OOStringFromEntityStatus(OOEntityStatus status) CONST_FUNC;
OOEntityStatus OOEntityStatusFromString(NSString* string) PURE_FUNC;

NSString* OOStringFromScanClass(OOScanClass scanClass) CONST_FUNC;
OOScanClass OOScanClassFromString(NSString* string) PURE_FUNC;

#ifdef __cplusplus
}
#endif

#endif // ENTITY_FOUNDATIONBRIDGE_H
