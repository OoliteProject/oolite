/*

PlayerEntitySound+FoundationBridge.h

TRANSITIONAL (proposed ADR-0043, "Transitional bridges"; bead oo-14c5). PlayerEntity (Sound)'s
Foundation-typed weapon-sound API as it was before its sweep, with the same selector names and
types, forwarding to the cxx_ API in PlayerEntitySound.h. It exists so that the callers in
PlayerEntity.mm and PlayerEntityControls.mm compile unchanged; each caller moves to the cxx_ API
in its own sweep bead. When `git grep` finds no caller of anything declared here, the bridge bead
deletes this file, PlayerEntitySound+FoundationBridge.mm, its line in Core/Entities/meson.build
and the #import at the end of PlayerEntitySound.h. Never add to it; never call it from migrated
code. oo-qps (the removal of gnustep-base) cannot compile while it exists.

Registry: src/oofnd/README.md, "Transitional bridges".

Copyright (C) 2004-2013 Giles C Williams and contributors (PlayerEntitySound.h)

*/

// Imported only from the end of PlayerEntitySound.h (which declares everything used here); never
// import it directly, and never import PlayerEntitySound.h from it (a cycle).
#ifndef PLAYERENTITYSOUND_FOUNDATIONBRIDGE_H
#define PLAYERENTITYSOUND_FOUNDATIONBRIDGE_H

@interface PlayerEntity (SoundFoundationBridge)

- (void)playShieldHit:(Vector)attackVector weaponIdentifier:(NSString*)weaponIdentifier; // -> -cxx_playShieldHit:weaponIdentifier:
- (void)playDirectHit:(Vector)attackVector weaponIdentifier:(NSString*)weaponIdentifier; // -> -cxx_playDirectHit:weaponIdentifier:
- (void)playLaserHit:(BOOL)hit offset:(Vector)weaponOffset weaponIdentifier:(NSString*)weaponIdentifier; // -> -cxx_playLaserHit:offset:weaponIdentifier:
- (void)playMissileLaunched:(Vector)weaponOffset weaponIdentifier:(NSString*)weaponIdentifier; // -> -cxx_playMissileLaunched:weaponIdentifier:
- (void)playMineLaunched:(Vector)weaponOffset weaponIdentifier:(NSString*)weaponIdentifier; // -> -cxx_playMineLaunched:weaponIdentifier:

@end

#endif // PLAYERENTITYSOUND_FOUNDATIONBRIDGE_H
