/*

OOMaterialSpecifier+FoundationBridge.h

TRANSITIONAL (proposed ADR-0043 Amendments 1-2; bead oo-hiis). The NSDictionary category and the
NSString key constants OOMaterialSpecifier.h declared before its sweep, with the same names and
types, forwarding to the cxx_OOMaterial* functions over an oo::PList configuration. Callers
compile unchanged; each moves to the cxx_ API in its own sweep bead. When `git grep` finds no use
of anything declared here outside the bridge, the bridge bead deletes this file,
OOMaterialSpecifier+FoundationBridge.mm, its line in Materials/meson.build and the #import at the
end of OOMaterialSpecifier.h. This file is also where the NSDictionary category retires (Amendment 1,
item 7). Never add to it; never call it from migrated code.

Registry: src/oofnd/README.md, "Transitional bridges".

*/

// Imported only from the end of OOMaterialSpecifier.h; never import it directly.
#ifndef OOMATERIALSPECIFIER_FOUNDATIONBRIDGE_H
#define OOMATERIALSPECIFIER_FOUNDATIONBRIDGE_H

//	Convenience methods to extract properties from material dictionaries.
@interface NSDictionary (OOMateralProperties)

- (OOColor*)oo_diffuseColor;
- (OOColor*)oo_ambientColor;
- (OOColor*)oo_specularColor;
- (OOColor*)oo_specularModulateColor;
- (OOColor*)oo_emissionColor;
- (OOColor*)oo_emissionModulateColor;
- (OOColor*)oo_illuminationModulateColor;

- (NSDictionary*)oo_diffuseMapSpecifierWithDefaultName:(NSString*)name;
- (NSDictionary*)oo_combinedSpecularMapSpecifier;
- (NSDictionary*)oo_specularColorMapSpecifier;
- (NSDictionary*)oo_specularExponentMapSpecifier;
- (NSDictionary*)oo_normalMapSpecifier;
- (NSDictionary*)oo_parallaxMapSpecifier;
- (NSDictionary*)oo_normalAndParallaxMapSpecifier;
- (NSDictionary*)oo_emissionMapSpecifier;
- (NSDictionary*)oo_illuminationMapSpecifier;
- (NSDictionary*)oo_emissionAndIlluminationMapSpecifier;

- (float)oo_parallaxScale;
- (float)oo_parallaxBias;

- (BOOL)oo_gammaCorrect;

- (float)oo_gloss;

- (int)oo_specularExponent;

@end

extern NSString* const kOOMaterialDiffuseColorName;
extern NSString* const kOOMaterialDiffuseColorLegacyName;
extern NSString* const kOOMaterialAmbientColorName;
extern NSString* const kOOMaterialAmbientColorLegacyName;
extern NSString* const kOOMaterialSpecularColorName;
extern NSString* const kOOMaterialSpecularColorLegacyName;
extern NSString* const kOOMaterialSpecularModulateColorName;
extern NSString* const kOOMaterialEmissionColorName;
extern NSString* const kOOMaterialEmissionColorLegacyName;
extern NSString* const kOOMaterialEmissionModulateColorName;
extern NSString* const kOOMaterialIlluminationModulateColorName;
extern NSString* const kOOMaterialDiffuseMapName;
extern NSString* const kOOMaterialSpecularColorMapName;
extern NSString* const kOOMaterialSpecularExponentMapName;
extern NSString* const kOOMaterialCombinedSpecularMapName;
extern NSString* const kOOMaterialNormalMapName;
extern NSString* const kOOMaterialParallaxMapName;
extern NSString* const kOOMaterialNormalAndParallaxMapName;
extern NSString* const kOOMaterialEmissionMapName;
extern NSString* const kOOMaterialIlluminationMapName;
extern NSString* const kOOMaterialEmissionAndIlluminationMapName;
extern NSString* const kOOMaterialParallaxScaleName;
extern NSString* const kOOMaterialParallaxBiasName;
extern NSString* const kOOMaterialGammaCorrectName;
extern NSString* const kOOMaterialGlossName;
extern NSString* const kOOMaterialSpecularExponentName;
extern NSString* const kOOMaterialSpecularExponentLegacyName;
extern NSString* const kOOMaterialLightMapsName;

#endif // OOMATERIALSPECIFIER_FOUNDATIONBRIDGE_H
