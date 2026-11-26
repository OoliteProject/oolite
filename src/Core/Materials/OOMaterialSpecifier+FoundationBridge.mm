/*

OOMaterialSpecifier+FoundationBridge.mm

TRANSITIONAL: see OOMaterialSpecifier+FoundationBridge.h. Each method converts the receiver with
oo::PListFrom (exact: live objects travel as PList::Object nodes, floats stay floats) and forwards
to its cxx_ function; specifiers come back through oo::ObjectFromPList (equal dictionaries; no
longer the same object as the configuration's own sub-dictionary).

*/

#import "OOColor.h"
#import "OOFoundationBridge.h"
#import "OOMaterialSpecifier.h" // declares the bridge at its end

NSString* const kOOMaterialDiffuseColorName = @"diffuse_color";
NSString* const kOOMaterialDiffuseColorLegacyName = @"diffuse";
NSString* const kOOMaterialAmbientColorName = @"ambient_color";
NSString* const kOOMaterialAmbientColorLegacyName = @"ambient";
NSString* const kOOMaterialSpecularColorName = @"specular_color";
NSString* const kOOMaterialSpecularColorLegacyName = @"specular";
NSString* const kOOMaterialSpecularModulateColorName = @"specular_modulate_color";
NSString* const kOOMaterialEmissionColorName = @"emission_color";
NSString* const kOOMaterialEmissionColorLegacyName = @"emission";
NSString* const kOOMaterialEmissionModulateColorName = @"emission_modulate_color";
NSString* const kOOMaterialIlluminationModulateColorName = @"illumination_modulate_color";
NSString* const kOOMaterialDiffuseMapName = @"diffuse_map";
NSString* const kOOMaterialSpecularColorMapName = @"specular_color_map";
NSString* const kOOMaterialSpecularExponentMapName = @"specular_exponent_map";
NSString* const kOOMaterialCombinedSpecularMapName = @"specular_map"; // Combined specular_color_map and specular_exponent_map (unfortunate name required for backwards-compatibility).
NSString* const kOOMaterialNormalMapName = @"normal_map";
NSString* const kOOMaterialParallaxMapName = @"parallax_map";
NSString* const kOOMaterialNormalAndParallaxMapName = @"normal_and_parallax_map";
NSString* const kOOMaterialEmissionMapName = @"emission_map";
NSString* const kOOMaterialIlluminationMapName = @"illumination_map";
NSString* const kOOMaterialEmissionAndIlluminationMapName = @"emission_and_illumination_map";
NSString* const kOOMaterialParallaxScaleName = @"parallax_scale";
NSString* const kOOMaterialParallaxBiasName = @"parallax_bias";
NSString* const kOOMaterialGammaCorrectName = @"gamma_correct";
NSString* const kOOMaterialGlossName = @"gloss";
NSString* const kOOMaterialSpecularExponentName = @"specular_exponent";
NSString* const kOOMaterialSpecularExponentLegacyName = @"shininess";
NSString* const kOOMaterialLightMapsName = @"light_map";

@implementation NSDictionary (OOMateralProperties)

- (OOColor*)oo_diffuseColor
{
    return cxx_OOMaterialDiffuseColor(oo::PListFrom(self));
}

- (OOColor*)oo_ambientColor
{
    return cxx_OOMaterialAmbientColor(oo::PListFrom(self));
}

- (OOColor*)oo_specularColor
{
    return cxx_OOMaterialSpecularColor(oo::PListFrom(self));
}

- (OOColor*)oo_specularModulateColor
{
    return cxx_OOMaterialSpecularModulateColor(oo::PListFrom(self));
}

- (OOColor*)oo_emissionColor
{
    return cxx_OOMaterialEmissionColor(oo::PListFrom(self));
}

- (OOColor*)oo_emissionModulateColor
{
    return cxx_OOMaterialEmissionModulateColor(oo::PListFrom(self));
}

- (OOColor*)oo_illuminationModulateColor
{
    return cxx_OOMaterialIlluminationModulateColor(oo::PListFrom(self));
}

- (NSDictionary*)oo_diffuseMapSpecifierWithDefaultName:(NSString*)name
{
    return oo::ObjectFromPList(cxx_OOMaterialDiffuseMapSpecifier(oo::PListFrom(self), oo::OptionalString(name)));
}

- (NSDictionary*)oo_combinedSpecularMapSpecifier
{
    return oo::ObjectFromPList(cxx_OOMaterialCombinedSpecularMapSpecifier(oo::PListFrom(self)));
}

- (NSDictionary*)oo_specularColorMapSpecifier
{
    return oo::ObjectFromPList(cxx_OOMaterialSpecularColorMapSpecifier(oo::PListFrom(self)));
}

- (NSDictionary*)oo_specularExponentMapSpecifier
{
    return oo::ObjectFromPList(cxx_OOMaterialSpecularExponentMapSpecifier(oo::PListFrom(self)));
}

- (NSDictionary*)oo_normalMapSpecifier
{
    return oo::ObjectFromPList(cxx_OOMaterialNormalMapSpecifier(oo::PListFrom(self)));
}

- (NSDictionary*)oo_parallaxMapSpecifier
{
    return oo::ObjectFromPList(cxx_OOMaterialParallaxMapSpecifier(oo::PListFrom(self)));
}

- (NSDictionary*)oo_normalAndParallaxMapSpecifier
{
    return oo::ObjectFromPList(cxx_OOMaterialNormalAndParallaxMapSpecifier(oo::PListFrom(self)));
}

- (NSDictionary*)oo_emissionMapSpecifier
{
    return oo::ObjectFromPList(cxx_OOMaterialEmissionMapSpecifier(oo::PListFrom(self)));
}

- (NSDictionary*)oo_illuminationMapSpecifier
{
    return oo::ObjectFromPList(cxx_OOMaterialIlluminationMapSpecifier(oo::PListFrom(self)));
}

- (NSDictionary*)oo_emissionAndIlluminationMapSpecifier
{
    return oo::ObjectFromPList(cxx_OOMaterialEmissionAndIlluminationMapSpecifier(oo::PListFrom(self)));
}

- (float)oo_parallaxScale
{
    return cxx_OOMaterialParallaxScale(oo::PListFrom(self));
}

- (float)oo_parallaxBias
{
    return cxx_OOMaterialParallaxBias(oo::PListFrom(self));
}

- (BOOL)oo_gammaCorrect
{
    return cxx_OOMaterialGammaCorrect(oo::PListFrom(self)) ? YES : NO;
}

- (float)oo_gloss
{
    return cxx_OOMaterialGloss(oo::PListFrom(self));
}

- (int)oo_specularExponent
{
    return cxx_OOMaterialSpecularExponent(oo::PListFrom(self));
}

@end
