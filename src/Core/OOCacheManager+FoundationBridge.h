/*

OOCacheManager+FoundationBridge.h

TRANSITIONAL (proposed ADR-0043, "Transitional bridges"; bead oo-19g0). OOCacheManager's
Foundation-typed API as it was before its sweep, with the same selector names and types,
forwarding to the cxx_ API in OOCacheManager.h. It exists so that OOCacheManager's callers compile
unchanged; each caller moves to the cxx_ API in its own sweep bead. When `git grep` finds no
caller of anything declared here, the bridge bead deletes this file,
OOCacheManager+FoundationBridge.mm, its line in Core/meson.build and the #import at the end of
OOCacheManager.h. Never add to it; never call it from migrated code. oo-qps (the removal of
gnustep-base) cannot compile while it exists.

Registry: src/oofnd/README.md, "Transitional bridges".

Copyright (C) 2004-2013 Giles C Williams and contributors (OOCacheManager.h)

*/

// Imported only from the end of OOCacheManager.h (which declares everything used here); never
// import it directly, and never import OOCacheManager.h from it (a cycle).
#ifndef OOCACHEMANAGER_FOUNDATIONBRIDGE_H
#define OOCACHEMANAGER_FOUNDATIONBRIDGE_H

@interface OOCacheManager (OOFoundationBridge)

- (id)objectForKey:(NSString*)inKey inCache:(NSString*)inCacheKey; // -> -cxx_objectForKey:inCache:
- (void)setObject:(id)inElement forKey:(NSString*)inKey inCache:(NSString*)inCacheKey; // -> -cxx_setObject:forKey:inCache:
- (void)removeObjectForKey:(NSString*)inKey inCache:(NSString*)inCacheKey; // -> -cxx_removeObjectForKey:inCache:
- (void)clearCache:(NSString*)inCacheKey; // -> -cxx_clearCache:

- (NSString*)cacheDirectoryPathCreatingIfNecessary:(BOOL)create; // -> -cxx_cacheDirectoryPathCreatingIfNecessary:

@end

#endif // OOCACHEMANAGER_FOUNDATIONBRIDGE_H
