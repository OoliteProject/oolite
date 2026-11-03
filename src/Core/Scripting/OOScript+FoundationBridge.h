/*

OOScript+FoundationBridge.h

TRANSITIONAL (proposed ADR-0043, "Transitional bridges"; bead oo-du83). OOScript's Foundation-typed
class API as it was before its sweep, with the same selector names and types, forwarding to the
cxx_ API in OOScript.h. It exists so that OOScript's callers compile unchanged; each caller moves to
the cxx_ API in its own sweep bead. When `git grep` finds no caller of anything declared here, the
bridge bead deletes this file, OOScript+FoundationBridge.mm, its line in Core/Scripting/meson.build
and the #import at the end of OOScript.h. Never add to it; never call it from migrated code. oo-qps
(the removal of gnustep-base) cannot compile while it exists.

Registry: src/oofnd/README.md, "Transitional bridges".

Copyright (C) 2004-2013 Giles C Williams and contributors (OOScript.h)

*/

// Imported only from the end of OOScript.h (which declares everything used here); never import it
// directly, and never import OOScript.h from it (a cycle).
#ifndef OOSCRIPT_FOUNDATIONBRIDGE_H
#define OOSCRIPT_FOUNDATIONBRIDGE_H

@interface OOScript (OOFoundationBridge)

/*	Looks for path/world-scripts.plist, path/script.js, then path/script.plist.
        May return zero or more scripts.
*/
+ (NSArray*)worldScriptsAtPath:(NSString*)path;

//	Load a single JavaScript script.
+ (id)jsScriptFromFileNamed:(NSString*)fileName properties:(NSDictionary*)properties;
//  As above, but load from the "AIs" directory
+ (id)jsAIScriptFromFileNamed:(NSString*)fileName properties:(NSDictionary*)properties;

@end

#endif // OOSCRIPT_FOUNDATIONBRIDGE_H
