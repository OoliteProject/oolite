/*

PlayerEntityControls+FoundationBridge.h

TRANSITIONAL (proposed ADR-0043, "Transitional bridges"; bead oo-3rb.214, chunk 1 of oo-3rb.77's
split). PlayerEntity (Controls)'s Foundation-typed API as it was before its sweep, with the same
selector names and types, forwarding to the cxx_ API in PlayerEntityControls.h. It exists so that
the callers in PlayerEntity.mm, PlayerEntityKeyMapper.mm and OOEquipmentType.mm compile unchanged;
each caller moves to the cxx_ API in its own sweep bead. When `git grep` finds no caller of
anything declared here, the bridge bead deletes this file, PlayerEntityControls+FoundationBridge.mm,
its line in Core/Entities/meson.build and the #import at the end of PlayerEntityControls.h. Never
add to it outside the PlayerEntityControls chunks; never call it from migrated code. oo-qps (the
removal of gnustep-base) cannot compile while it exists.

Registry: src/oofnd/README.md, "Transitional bridges".

Copyright (C) 2004-2013 Giles C Williams and contributors (PlayerEntityControls.h)

*/

// Imported only from the end of PlayerEntityControls.h (which declares everything used here);
// never import it directly, and never import PlayerEntityControls.h from it (a cycle).
#ifndef PLAYERENTITYCONTROLS_FOUNDATIONBRIDGE_H
#define PLAYERENTITYCONTROLS_FOUNDATIONBRIDGE_H

@interface PlayerEntity (ControlsFoundationBridge)

// oo-3rb.214 (chunk 1)
- (NSArray*)processKeyCode:(NSArray*)key_def; // -> -cxx_processKeyCode: (returns +1, as before)

@end

#endif // PLAYERENTITYCONTROLS_FOUNDATIONBRIDGE_H
