/*

OOShipGroup+FoundationBridge.h

TRANSITIONAL (proposed ADR-0043, "Transitional bridges"; made by bead oo-5l4w). OOShipGroup's
Foundation-typed API as it was before its sweep, with the same selector names and types,
forwarding to the cxx_ API and OOShipGroupCursor in OOShipGroup.h. It exists so that OOShipGroup's
callers compile unchanged; each caller moves to the cxx_ API in its own sweep bead. When
`git grep` finds no caller of anything declared here, the bridge bead deletes this file,
OOShipGroup+FoundationBridge.mm, its line in Core/meson.build and the #import at the end of
OOShipGroup.h. Never add to it; never call it from migrated code. oo-qps (the removal of
gnustep-base) cannot compile while it exists.

Registry: src/oofnd/README.md, "Transitional bridges".

Copyright (C) 2004-2013 Giles C Williams and contributors (OOShipGroup.h)

*/

// Imported only from the end of OOShipGroup.h (which declares everything used here); never
// import it directly, and never import OOShipGroup.h from it (a cycle).
#ifndef OOSHIPGROUP_FOUNDATIONBRIDGE_H
#define OOSHIPGROUP_FOUNDATIONBRIDGE_H

@interface OOShipGroup (OOFoundationBridge)

+ (instancetype)groupWithName:(NSString*)name; // -> +cxx_groupWithName:
+ (instancetype)groupWithName:(NSString*)name leader:(ShipEntity*)leader; // -> +cxx_groupWithName:leader:

- (NSEnumerator*)objectEnumerator; // -> OOShipGroupCursor
- (NSEnumerator*)mutationSafeEnumerator; // Enumerate over contents at time this is called, even if actual group is mutated.	// -> -cxx_memberArray

- (NSSet*)members; // -> -cxx_memberArray
- (NSArray*)memberArray; // arbitrary order	// -> -cxx_memberArray
- (NSSet*)membersExcludingLeader; // -> -cxx_memberArrayExcludingLeader
- (NSArray*)memberArrayExcludingLeader; // arbitrary order	// -> -cxx_memberArrayExcludingLeader

@end

#endif // OOSHIPGROUP_FOUNDATIONBRIDGE_H
