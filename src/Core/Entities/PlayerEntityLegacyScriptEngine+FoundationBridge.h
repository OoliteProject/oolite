/*

PlayerEntityLegacyScriptEngine+FoundationBridge.h

TRANSITIONAL (proposed ADR-0043, "Transitional bridges"; bead oo-3rb.190, chunk 1 of oo-j924).
PlayerEntity (Scripting)'s Foundation-typed API as it was before its sweep, with the same selector
names and types, forwarding to the cxx_ API in PlayerEntityLegacyScriptEngine.h. It exists so that
the callers compile unchanged; each caller moves to the cxx_ API in its own sweep bead. The later
chunks of oo-j924 (oo-3rb.191 .. oo-3rb.197) move their own selectors in here. When `git grep`
finds no caller of anything declared here, the bridge bead deletes this file,
PlayerEntityLegacyScriptEngine+FoundationBridge.mm, its line in Core/Entities/meson.build and the
#import at the end of PlayerEntityLegacyScriptEngine.h. Never call it from migrated code. oo-qps
(the removal of gnustep-base) cannot compile while it exists.

Registry: src/oofnd/README.md, "Transitional bridges".

Copyright (C) 2004-2013 Giles C Williams and contributors (PlayerEntityLegacyScriptEngine.h)

*/

// Imported only from the end of PlayerEntityLegacyScriptEngine.h (which declares everything used
// here); never import it directly, and never import PlayerEntityLegacyScriptEngine.h from it (a cycle).
#ifndef PLAYERENTITYLEGACYSCRIPTENGINE_FOUNDATIONBRIDGE_H
#define PLAYERENTITYLEGACYSCRIPTENGINE_FOUNDATIONBRIDGE_H

@interface PlayerEntity (ScriptingFoundationBridge)

// Chunk 1 (oo-3rb.190): the legacy-script runner.
- (void)runScriptActions:(NSArray*)sanitizedActions withContextName:(NSString*)contextName forTarget:(ShipEntity*)target; // -> -cxx_runScriptActions:withContextName:forTarget:
- (void)runUnsanitizedScriptActions:(NSArray*)unsanitizedActions allowingAIMethods:(BOOL)allowAIMethods withContextName:(NSString*)contextName forTarget:(ShipEntity*)target; // -> -cxx_runUnsanitizedScriptActions:allowingAIMethods:withContextName:forTarget:

// Test (sanitized) legacy script conditions array.
- (BOOL)scriptTestConditions:(NSArray*)array; // -> -cxx_scriptTestConditions:

// Chunk 2 (oo-3rb.191): the mission-variable store.
- (NSDictionary*)missionVariables; // the live dictionary, as before (-cxx_missionVariables is a snapshot)

- (NSString*)missionVariableForKey:(NSString*)key; // -> -cxx_missionVariableForKey:
- (void)setMissionVariable:(NSString*)value forKey:(NSString*)key; // -> -cxx_setMissionVariable:forKey:

// Chunk 4 (oo-3rb.193): mission instructions, the manifest list and the mission title.
- (NSArray*)missionsList; // -> -cxx_missionsList
- (void)setMissionInstructions:(NSString*)text forMission:(NSString*)key; // -> -cxx_setMissionInstructions:forMission:
- (void)setMissionInstructionsList:(NSArray*)list forMission:(NSString*)key; // -> -cxx_setMissionInstructionsList:forMission:
- (NSString*)missionTitle; // -> -cxx_missionTitle
- (void)setMissionTitle:(NSString*)value; // -> -cxx_setMissionTitle:

// Chunk 5 (oo-3rb.194): mission choices and the mission screen ID.
- (void)setMissionChoicesDictionary:(NSDictionary*)choicesDict; // -> -cxx_setMissionChoicesDictionary:
- (void)setMissionScreenID:(NSString*)msid; // -> -cxx_setMissionScreenID:
- (NSString*)missionScreenID; // -> -cxx_missionScreenID

// Chunk 6 (oo-3rb.195): equipment scripts.
- (BOOL)addEqScriptForKey:(NSString*)eq_key; // -> -cxx_addEqScriptForKey:
- (void)removeEqScriptForKey:(NSString*)eq_key; // -> -cxx_removeEqScriptForKey:
- (NSUInteger)eqScriptIndexForKey:(NSString*)eq_key; // -> -cxx_eqScriptIndexForKey:

// Chunk 8 (oo-3rb.197): scene backgrounds.
- (void)setBackgroundFromDescriptionsKey:(NSString*)d_key; // -> -cxx_setBackgroundFromDescriptionsKey:

@end

NSString* OOComparisonTypeToString(OOComparisonType type) CONST_FUNC; // -> cxx_OOComparisonTypeToString

#endif // PLAYERENTITYLEGACYSCRIPTENGINE_FOUNDATIONBRIDGE_H
