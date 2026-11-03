/*

OOOXPVerifier+FoundationBridge.h

TRANSITIONAL (proposed ADR-0043, "Transitional bridges"; bead oo-hkvv). OOOXPVerifier's
Foundation-typed API as it was before its sweep, with the same selector names and types,
forwarding to the cxx_ API in OOOXPVerifier.h. It exists so that the verifier stages that call it
compile unchanged; each caller moves to the cxx_ API in its own sweep bead. When `git grep` finds
no caller of anything declared here, the bridge bead deletes this file,
OOOXPVerifier+FoundationBridge.mm, its line in OXPVerifier/meson.build and the #import at the end
of OOOXPVerifier.h. Never add to it; never call it from migrated code. oo-qps (the removal of
gnustep-base) cannot compile while it exists.

Registry: src/oofnd/README.md, "Transitional bridges".

Copyright (C) 2007-2013 Jens Ayton and contributors (OOOXPVerifier.h)

*/

// Imported only from the end of OOOXPVerifier.h (which declares everything used here); never
// import it directly, and never import OOOXPVerifier.h from it (a cycle).
#ifndef OOOXPVERIFIER_FOUNDATIONBRIDGE_H
#define OOOXPVERIFIER_FOUNDATIONBRIDGE_H

@interface OOOXPVerifier (OOFoundationBridge)

- (NSString*)oxpPath; // -> -cxx_oxpPath
- (NSString*)oxpDisplayName; // -> -cxx_oxpDisplayName

- (id)stageWithName:(NSString*)name; // -> -cxx_stageWithName:

- (NSArray*)configurationArrayForKey:(NSString*)key; // -> -cxx_configurationArrayForKey:
- (NSDictionary*)configurationDictionaryForKey:(NSString*)key; // -> -cxx_configurationDictionaryForKey:
- (NSString*)configurationStringForKey:(NSString*)key; // -> -cxx_configurationStringForKey:
- (NSSet*)configurationSetForKey:(NSString*)key; // -> -cxx_configurationSetForKey:

@end

#endif // OOOXPVERIFIER_FOUNDATIONBRIDGE_H
