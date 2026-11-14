/*

GameController+FoundationBridge.h

TRANSITIONAL (proposed ADR-0043, "Transitional bridges"; bead oo-m6ej, made by its chunk
oo-3rb.88, and chunks oo-3rb.89..91 move their own selectors in). GameController's
Foundation-typed API as it was before its sweep, with the same selector names and types,
forwarding to the cxx_ API in GameController.h. It exists so that GameController's callers
compile unchanged; each caller moves to the cxx_ API in its own sweep bead. When `git grep` finds
no caller of anything declared here, the bridge bead deletes this file,
GameController+FoundationBridge.mm, its line in Core/meson.build and the #import at the end of
GameController.h. Never add to it; never call it from migrated code. oo-qps (the removal of
gnustep-base) cannot compile while it exists.

Registry: src/oofnd/README.md, "Transitional bridges".

Copyright (C) 2004-2013 Giles C Williams and contributors (GameController.h)

*/

// Imported only from the end of GameController.h (which declares everything used here); never
// import it directly, and never import GameController.h from it (a cycle).
#ifndef GAMECONTROLLER_FOUNDATIONBRIDGE_H
#define GAMECONTROLLER_FOUNDATIONBRIDGE_H

@interface GameController (OOFoundationBridge)

- (void)exitAppWithContext:(NSString*)context; // -> -cxx_exitAppWithContext:

- (NSString*)playerFileToLoad; // -> -cxx_playerFileToLoad
- (void)setPlayerFileToLoad:(NSString*)filename; // -> -cxx_setPlayerFileToLoad:

- (NSString*)playerFileDirectory; // -> -cxx_playerFileDirectory
- (void)setPlayerFileDirectory:(NSString*)filename; // -> -cxx_setPlayerFileDirectory:

- (void)logProgress:(NSString*)message; // -> -cxx_logProgress:
#if OO_DEBUG
// The %@ format forms format as they always did, then pass the message on.
- (void)debugLogProgress:(NSString*)format, ... OO_TAKES_FORMAT_STRING(1, 2); // -> -cxx_debugLogProgress:
- (void)debugLogProgress:(NSString*)format arguments:(va_list)arguments OO_TAKES_FORMAT_STRING(1, 0); // -> -cxx_debugLogProgress:
- (void)debugPushProgressMessage:(NSString*)format, ... OO_TAKES_FORMAT_STRING(1, 2); // -> -cxx_debugPushProgressMessage:
#endif

@end

#endif // GAMECONTROLLER_FOUNDATIONBRIDGE_H
