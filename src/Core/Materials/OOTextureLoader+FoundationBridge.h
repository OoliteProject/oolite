/*

OOTextureLoader+FoundationBridge.h

TRANSITIONAL (proposed ADR-0043, "Transitional bridges"; bead oo-wzti). OOTextureLoader's
Foundation-typed API as it was before its sweep, with the same selector names and types,
forwarding to the cxx_ API in OOTextureLoader.h (a texture specifier crosses as an oo::PList,
exact by Amendment 2). It exists so that OOTextureLoader's callers and subclasses compile
unchanged; each moves to the cxx_ API in its own sweep bead. When `git grep` finds no use of
anything declared here outside the bridge, the bridge bead deletes this file,
OOTextureLoader+FoundationBridge.mm, its line in Materials/meson.build and the #import at the end
of OOTextureLoader.h. Never add to it; never call it from migrated code. oo-qps (the removal of
gnustep-base) cannot compile while it exists.

Registry: src/oofnd/README.md, "Transitional bridges".

Copyright (C) 2007-2014 Jens Ayton (OOTextureLoader.h)

*/

// Imported only from the end of OOTextureLoader.h (which declares everything used here); never
// import it directly, and never import OOTextureLoader.h from it (a cycle).
#ifndef OOTEXTURELOADER_FOUNDATIONBRIDGE_H
#define OOTEXTURELOADER_FOUNDATIONBRIDGE_H

@interface OOTextureLoader (OOFoundationBridge)

+ (id)loaderWithPath:(NSString*)path options:(uint32_t)options; // -> +cxx_loaderWithPath:options:

+ (id)loaderWithTextureSpecifier:(id)specifier extraOptions:(uint32_t)extraOptions folder:(NSString*)folder; // -> +cxx_loaderWithTextureSpecifier:extraOptions:folder:

- (id)initWithPath:(NSString*)path options:(uint32_t)options; // -> -cxx_initWithPath:options:

- (NSString*)path; // -> -cxx_path

@end

#endif // OOTEXTURELOADER_FOUNDATIONBRIDGE_H
