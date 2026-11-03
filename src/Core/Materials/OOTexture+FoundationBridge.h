/*

OOTexture+FoundationBridge.h

TRANSITIONAL (proposed ADR-0043 Amendments 1-2, "Transitional bridges"; bead oo-japz). OOTexture's
Foundation-typed API as it was before its sweep (OOTexture.h, and the two OOTextureInternal.h
entries defined in OOTexture.mm), with the same names and types, forwarding to the cxx_ API in
OOTexture.h / OOTextureInternal.h: configurations and specifiers cross as oo::PList (oo::PListFrom
and oo::ObjectFromPList, exact for mixed configurations by Amendment 2). It exists so that
OOTexture's callers (20+ files) compile unchanged; each caller moves to the cxx_ API in its own
sweep bead. When `git grep` finds no use of anything declared here outside the bridge, the bridge
bead deletes this file, OOTexture+FoundationBridge.mm, its line in Materials/meson.build and the
#import at the end of OOTexture.h. Never add to it; never call it from migrated code. oo-qps (the
removal of gnustep-base) cannot compile while it exists.

The NSDictionary / NSArray (OOTextureConveniences) categories had no callers left and were retired
by oo-japz (Amendment 1, item 7), not bridged.

Registry: src/oofnd/README.md, "Transitional bridges".

Copyright (C) 2007-2013 Jens Ayton and contributors (OOTexture.h)

*/

// Imported only from the end of OOTexture.h (which declares everything used here); never import it
// directly, and never import OOTexture.h from it (a cycle).
#ifndef OOTEXTURE_FOUNDATIONBRIDGE_H
#define OOTEXTURE_FOUNDATIONBRIDGE_H

@interface OOTexture (OOFoundationBridge)

+ (id)textureWithName:(NSString*)name
             inFolder:(NSString*)directory
              options:(OOTextureFlags)options
           anisotropy:(GLfloat)anisotropy
              lodBias:(GLfloat)lodBias; // -> +cxx_textureWithName:inFolder:options:anisotropy:lodBias:

+ (id)textureWithName:(NSString*)name
             inFolder:(NSString*)directory; // -> +cxx_textureWithName:inFolder:

+ (id)textureWithConfiguration:(id)configuration; // -> +cxx_textureWithConfiguration:
+ (id)textureWithConfiguration:(id)configuration extraOptions:(OOTextureFlags)extraOptions; // -> +cxx_textureWithConfiguration:extraOptions:

+ (OOTexture*)existingTextureForKey:(NSString*)key; // (OOTextureInternal.h) -> +cxx_existingTextureForKey:

#ifndef NDEBUG
+ (NSArray*)cachedTexturesByAge; // -> +cxx_cachedTexturesByAge
+ (NSSet*)allTextures; // -> +cxx_allTextures
#endif

@end

NSDictionary* OOTextureSpecFromObject(id object, NSString* defaultName); // -> cxx_OOTextureSpecFromObject

BOOL OOInterpretTextureSpecifier(id specifier, NSString** outName, OOTextureFlags* outOptions, float* outAnisotropy, float* outLODBias, BOOL ignoreExtract); // -> cxx_OOInterpretTextureSpecifier

NSDictionary* OOMakeTextureSpecifier(NSString* name, OOTextureFlags options, float anisotropy, float lodBias, BOOL internal); // -> cxx_OOMakeTextureSpecifier

NSString* OOTextureCacheKeyForSpecifier(id specifier); // (OOTextureInternal.h) -> cxx_OOTextureCacheKeyForSpecifier

// Texture specifier keys (-> cxx_kOOTextureSpecifier*Key).
extern NSString* const kOOTextureSpecifierNameKey;
extern NSString* const kOOTextureSpecifierSwizzleKey;
extern NSString* const kOOTextureSpecifierMinFilterKey;
extern NSString* const kOOTextureSpecifierMagFilterKey;
extern NSString* const kOOTextureSpecifierNoShrinkKey;
extern NSString* const kOOTextureSpecifierExtraShrinkKey;
extern NSString* const kOOTextureSpecifierRepeatSKey;
extern NSString* const kOOTextureSpecifierRepeatTKey;
extern NSString* const kOOTextureSpecifierCubeMapKey;
extern NSString* const kOOTextureSpecifierAnisotropyKey;
extern NSString* const kOOTextureSpecifierLODBiasKey;

// Keys not used in texture setup, but put in specific texture specifiers to simplify plists.
extern NSString* const kOOTextureSpecifierModulateColorKey;
extern NSString* const kOOTextureSpecifierIlluminationModeKey;
extern NSString* const kOOTextureSpecifierSelfColorKey;
extern NSString* const kOOTextureSpecifierScaleFactorKey;
extern NSString* const kOOTextureSpecifierBindingKey;

#endif // OOTEXTURE_FOUNDATIONBRIDGE_H
