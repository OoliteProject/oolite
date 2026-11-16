/*

OOTexture+FoundationBridge.mm

TRANSITIONAL: see OOTexture+FoundationBridge.h. Each method and function converts its arguments
(nil strings as std::nullopt, configurations and specifiers with oo::PListFrom) and forwards to its
cxx_ counterpart; results are converted back as the old code built them (nil for nil, specifiers
through oo::ObjectFromPList: equal dictionaries, no longer the caller's own object).

*/

#import "OOFoundationBridge.h"
#import "OOTexture.h" // declares the bridge at its end
#import "OOTextureInternal.h"

NSString* const kOOTextureSpecifierNameKey = @"name";
NSString* const kOOTextureSpecifierSwizzleKey = @"extract_channel";
NSString* const kOOTextureSpecifierMinFilterKey = @"min_filter";
NSString* const kOOTextureSpecifierMagFilterKey = @"mag_filter";
NSString* const kOOTextureSpecifierNoShrinkKey = @"no_shrink";
NSString* const kOOTextureSpecifierExtraShrinkKey = @"extra_shrink";
NSString* const kOOTextureSpecifierRepeatSKey = @"repeat_s";
NSString* const kOOTextureSpecifierRepeatTKey = @"repeat_t";
NSString* const kOOTextureSpecifierCubeMapKey = @"cube_map";
NSString* const kOOTextureSpecifierAnisotropyKey = @"anisotropy";
NSString* const kOOTextureSpecifierLODBiasKey = @"texture_LOD_bias";

NSString* const kOOTextureSpecifierModulateColorKey = @"color";
NSString* const kOOTextureSpecifierIlluminationModeKey = @"illumination_mode";
NSString* const kOOTextureSpecifierSelfColorKey = @"self_color";
NSString* const kOOTextureSpecifierScaleFactorKey = @"scale_factor";
NSString* const kOOTextureSpecifierBindingKey = @"binding";

@implementation OOTexture (OOFoundationBridge)

+ (id)textureWithName:(NSString*)name
             inFolder:(NSString*)directory
              options:(OOTextureFlags)options
           anisotropy:(GLfloat)anisotropy
              lodBias:(GLfloat)lodBias
{
    return [self cxx_textureWithName:oo::OptionalString(name) inFolder:oo::OptionalString(directory) options:options anisotropy:anisotropy lodBias:lodBias];
}

+ (id)textureWithName:(NSString*)name
             inFolder:(NSString*)directory
{
    return [self cxx_textureWithName:oo::OptionalString(name) inFolder:oo::OptionalString(directory)];
}

+ (id)textureWithConfiguration:(id)configuration
{
    return [self cxx_textureWithConfiguration:oo::PListFrom(configuration)];
}

+ (id)textureWithConfiguration:(id)configuration extraOptions:(OOTextureFlags)extraOptions
{
    return [self cxx_textureWithConfiguration:oo::PListFrom(configuration) extraOptions:extraOptions];
}

+ (OOTexture*)existingTextureForKey:(NSString*)key
{
    return [self cxx_existingTextureForKey:oo::OptionalString(key)];
}

#ifdef OO_DEBUG_MONITOR_ENABLED
+ (NSArray*)cachedTexturesByAge
{
    const std::vector<oo::ObjCRef<OOTexture*>> textures = [self cxx_cachedTexturesByAge];
    return textures.empty() ? nil : oo::NSArrayFromObjects(textures); // nil when empty, as before
}

+ (NSSet*)allTextures
{
    return oo::NSSetFromObjects([self cxx_allTextures]);
}
#endif

@end

NSDictionary* OOTextureSpecFromObject(id object, NSString* defaultName)
{
    return oo::ObjectFromPList(cxx_OOTextureSpecFromObject(oo::PListFrom(object), oo::OptionalString(defaultName)));
}

BOOL OOInterpretTextureSpecifier(id specifier, NSString** outName, OOTextureFlags* outOptions, float* outAnisotropy, float* outLODBias, BOOL ignoreExtract)
{
    std::string name;
    const BOOL OK = cxx_OOInterpretTextureSpecifier(oo::PListFrom(specifier), &name, outOptions, outAnisotropy, outLODBias, ignoreExtract);
    if (OK && outName != NULL)
        *outName = oo::NSStringFrom(name);
    return OK;
}

NSDictionary* OOMakeTextureSpecifier(NSString* name, OOTextureFlags options, float anisotropy, float lodBias, BOOL internal)
{
    return oo::ObjectFromPList(cxx_OOMakeTextureSpecifier(oo::StdString(name), options, anisotropy, lodBias, internal));
}

NSString* OOTextureCacheKeyForSpecifier(id specifier)
{
    return oo::NSStringFrom(cxx_OOTextureCacheKeyForSpecifier(oo::PListFrom(specifier)));
}
