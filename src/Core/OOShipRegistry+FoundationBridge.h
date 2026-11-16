/*

OOShipRegistry+FoundationBridge.h

TRANSITIONAL (proposed ADR-0043, "Transitional bridges"; bead oo-92mj, made by chunk oo-3rb.114 and
extended by its later chunks). OOShipRegistry's Foundation-typed API as it was before its sweep,
with the same selector names and types, forwarding to the cxx_ API in OOShipRegistry.h. It exists
so that OOShipRegistry's callers compile unchanged; each caller moves to the cxx_ API in its own
sweep bead. When `git grep` finds no caller of anything declared here, the bridge bead deletes this
file, OOShipRegistry+FoundationBridge.mm, its line in Core/meson.build and the #import at the end
of OOShipRegistry.h. Never add to it outside the oo-92mj chunks; never call it from migrated code.
oo-qps (the removal of gnustep-base) cannot compile while it exists.

Registry: src/oofnd/README.md, "Transitional bridges".

Copyright (C) 2008-2013 Jens Ayton and contributors (OOShipRegistry.h)

*/

// Imported only from the end of OOShipRegistry.h (which declares everything used here); never
// import it directly, and never import OOShipRegistry.h from it (a cycle).
#ifndef OOSHIPREGISTRY_FOUNDATIONBRIDGE_H
#define OOSHIPREGISTRY_FOUNDATIONBRIDGE_H

@interface OOShipRegistry (OOFoundationBridge)

// oo-3rb.114: ship and effect data
- (NSDictionary*)shipInfoForKey:(NSString*)key; // -> -cxx_shipInfoForKey:
- (void)setShipInfoForKey:(NSString*)key with:(NSDictionary*)newShipData; // -> -cxx_setShipInfoForKey:with:
- (NSDictionary*)effectInfoForKey:(NSString*)key; // -> -cxx_effectInfoForKey:
- (NSDictionary*)shipyardInfoForKey:(NSString*)key; // -> -cxx_shipyardInfoForKey:
- (NSArray*)playerShipKeys; // -> -cxx_playerShipKeys
- (NSArray*)shipKeys; // -> -cxx_shipKeys

// oo-3rb.115: role probability sets and demo ships
- (OOProbabilitySet*)probabilitySetForRole:(NSString*)role; // -> -cxx_probabilitySetForRole:
- (NSArray*)demoShipKeys; // -> -cxx_demoShipKeys
- (NSArray*)shipRoles; // -> -cxx_shipRoles
- (NSArray*)shipKeysWithRole:(NSString*)role; // -> -cxx_shipKeysWithRole:
- (NSString*)randomShipKeyForRole:(NSString*)role; // -> -cxx_randomShipKeyForRole:

@end

#endif // OOSHIPREGISTRY_FOUNDATIONBRIDGE_H
