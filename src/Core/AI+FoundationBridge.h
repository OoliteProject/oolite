/*

AI+FoundationBridge.h

TRANSITIONAL (proposed ADR-0043, "Transitional bridges"; beads oo-3rb.84-87 for oo-gtl8). AI's
Foundation-typed API as it was before its sweep, with the same selector names and types,
forwarding to the cxx_ API in AI.h. It exists so that AI's callers compile unchanged; each caller
moves to the cxx_ API in its own sweep bead. When `git grep` finds no caller of anything declared
here, the bridge bead deletes this file, AI+FoundationBridge.mm, its line in Core/meson.build and
the #import at the end of AI.h. Never add to it outside the AI.mm chunk beads; never call it from
migrated code. oo-qps (the removal of gnustep-base) cannot compile while it exists.

Registry: src/oofnd/README.md, "Transitional bridges".

Copyright (C) 2004-2013 Giles C Williams and contributors (AI.h)

*/

// Imported only from the end of AI.h (which declares everything used here); never import it
// directly, and never import AI.h from it (a cycle).
#ifndef AI_FOUNDATIONBRIDGE_H
#define AI_FOUNDATIONBRIDGE_H

@interface AI (OOFoundationBridge)

- (void)setStateMachine:(NSString*)smName withJSScript:(NSString*)script; // -> -cxx_setStateMachine:withJSScript:
- (void)setState:(NSString*)stateName; // -> -cxx_setState:

- (void)setStateMachine:(NSString*)smName afterDelay:(NSTimeInterval)delay; // -> -cxx_setStateMachine:afterDelay:
- (void)setState:(NSString*)stateName afterDelay:(NSTimeInterval)delay; // -> -cxx_setState:afterDelay:

- (id)initWithStateMachine:(NSString*)smName andState:(NSString*)stateName; // -> -cxx_initWithStateMachine:andState:

- (void)exitStateMachineWithMessage:(NSString*)message; // -> -cxx_exitStateMachineWithMessage:

+ (NSString*)currentlyRunningAIDescription; // -> +cxx_currentlyRunningAIDescription
- (NSString*)associatedJS; // -> -cxx_associatedJS

- (void)reactToMessage:(NSString*)message context:(NSString*)debugContext; // -> -cxx_reactToMessage:context:
- (void)takeAction:(NSString*)action; // -> -cxx_takeAction:
- (void)dropMessage:(NSString*)ms; // -> -cxx_dropMessage:

@end

#endif // AI_FOUNDATIONBRIDGE_H
