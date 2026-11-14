/*

OOMaterialConvenienceCreators.m


Copyright (C) 2007-2013 Jens Ayton

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

*/

#ifndef USE_NEW_SHADER_SYNTHESIZER
#define USE_NEW_SHADER_SYNTHESIZER 0
#endif

#include "OOMaterialConvenienceCreators.h"
#include "OOColor.h"
#include "OOMaterialSpecifier.h"

#if USE_NEW_SHADER_SYNTHESIZER
#include "OODefaultShaderSynthesizer.h"
#include "ResourceManager.h"
#endif

#include "OOCacheManager.h"
#include "OODebugFlags.h"
#include "OOMultiTextureMaterial.h"
#include "OOOpenGLExtensionManager.h"
#include "OOShaderMaterial.h"
#include "OOSingleTextureMaterial.h"
#include "OOTexture.h"
#include "Universe.h"
#include "oofnd/Defaults.hpp"
#include "oofnd/PListWriting.hpp"
#include "oofnd/StdLib.hpp"
#include "oofnd/String.hpp"
#include "oofnd/objc/OOAssert.h"

#if !USE_NEW_SHADER_SYNTHESIZER
namespace {

struct OOMaterialSynthContext {
    oo::PList inConfig;
    oo::PList::Dict outConfig;
    NSUInteger texturesUsed;
    NSUInteger maxTextures;

    oo::PList::Dict macros;
    std::vector<oo::PList> textures;
    oo::PList::Dict uniforms;
};

void SetUniform(oo::PList::Dict& uniforms, const std::string& key, const char* type, const oo::PList& value);
void SetUniformFloat(OOMaterialSynthContext* context, const std::string& key, float value);

/*	AddTexture(): add a texture to the configuration being synthesized.
 * specifier is added to the textures array.
 * uniformName is mapped to the appropriate texture unit in the uniforms dictionary.
 * If nonShaderKey is not nil, nonShaderKey (e.g. diffuse_map) is set to specifier.
 * If macroName is not nil, macroName is set to 1 in the macros dictionary.
 */
void AddTexture(OOMaterialSynthContext* context, const char* uniformName, const char* nonShaderKey, const char* macroName, const oo::PList& specifier);

void AddColorIfAppropriate(OOMaterialSynthContext* context, OOColor* color, const char* key, const char* macroName);
void AddMacroColorIfAppropriate(OOMaterialSynthContext* context, OOColor* color, const char* macroName);

void SynthDiffuse(OOMaterialSynthContext* context, const std::optional<std::string>& name);
void SynthEmissionAndIllumination(OOMaterialSynthContext* context);
void SynthNormalMap(OOMaterialSynthContext* context);
void SynthSpecular(OOMaterialSynthContext* context);

} // namespace
#endif

#if !USE_NEW_SHADER_SYNTHESIZER

oo::PList OOMaterial::synthesizeMaterialDictionaryWithName(const std::optional<std::string>& name,
    const oo::PList& configuration,
    const oo::PList& macros)
{
    oo::PList::Dict macrosCopy;
    if (const oo::PList::Dict* src = macros.getIf<oo::PList::Dict>()) {
        macrosCopy = *src;
    }

    OOMaterialSynthContext context = {
        .inConfig = configuration.isNull() ? oo::PList(oo::PList::Dict { }) : configuration,
        .outConfig = oo::PList::Dict { },
        .texturesUsed = 0,
        .maxTextures = (NSUInteger)OOOpenGLExtensionManager::sharedManager()->textureImageUnitCount(),

        .macros = std::move(macrosCopy),
        .textures = { },
        .uniforms = { }
    };

    if ((UNIVERSE != nullptr ? UNIVERSE->reducedDetail() : false)) {
        context.maxTextures = 3;
    }

    //	Basic stuff.

    /*	Set up the various material attributes.
            Order is significant here, because it determines the order in which
            features will be dropped if we exceed the hardware's texture image
            unit limit.
    */
    SynthDiffuse(&context, name);
    SynthEmissionAndIllumination(&context);
    SynthNormalMap(&context);
    SynthSpecular(&context);

    if ((UNIVERSE != nullptr ? UNIVERSE->getDetailLevel() : OOGraphicsDetail { }) >= DETAIL_LEVEL_SHADERS) {
        //	Add uniforms required for hull heat glow.
        context.uniforms["uHullHeatLevel"] = oo::PList("hullHeatLevel");
        context.uniforms["uTime"] = oo::PList("timeElapsedSinceSpawn");
        context.uniforms["uFogColor"] = oo::PList("fogUniform");
    }

    //	Stuff in the general properties.
    context.outConfig["_oo_is_synthesized_config"] = oo::PList("true");
    context.outConfig["vertex_shader"] = oo::PList("oolite-tangent-space-vertex.vertex");
    context.outConfig["fragment_shader"] = oo::PList("oolite-default-shader.fragment");

    if (!context.textures.empty())
        context.outConfig["textures"] = oo::PList(oo::PList::Array(context.textures));
    if (!context.uniforms.empty())
        context.outConfig["uniforms"] = oo::PList(context.uniforms);
    if (!context.macros.empty())
        context.outConfig["_oo_synthesized_material_macros"] = oo::PList(context.macros);

    return oo::PList(std::move(context.outConfig));
}

oo::Ref<OOMaterial> OOMaterial::defaultShaderMaterialWithName(const std::optional<std::string>& name,
    const std::optional<std::string>& cacheKey,
    const oo::PList& configuration,
    const oo::PList& macros,
    Entity* target)
{
    // The cache manager's facade, still messaged (proposed ADR-0056 amendment oo-rmd7 item 3).
    ::OOCacheManager* cache = nullptr;
    oo::PList synthesizedConfig;
    oo::Ref<OOMaterial> result;

    // Avoid looping (can happen if shader fails to compile).
    if (configuration.find("_oo_is_synthesized_config") != nullptr) {
        OO_LOG("material.synthesize.loop", "Synthesis loop for material {}.",
            name ? *name : std::string("(null)"));
        return nullptr;
    }

    std::string cacheKeyStr;
    if (cacheKey.has_value()) {
        cache = OOCacheManager::sharedCache();
        // configuration must be in cache key, as otherwise changes in
        // non-diffuse map can end up miscached
        cacheKeyStr = oo::str::format("%s/%s/%s",
            cacheKey->c_str(),
            name.value_or("").c_str(),
            oo::DescriptionOf(configuration).c_str());
        synthesizedConfig = cache->pListForKey(cacheKeyStr, "synthesized shader materials");
    }

    if (synthesizedConfig.isNull()) {
        synthesizedConfig = synthesizeMaterialDictionaryWithName(name,
            configuration.isNull() ? oo::PList(oo::PList::Dict { }) : configuration,
            macros);
        if (!synthesizedConfig.isNull() && cacheKey.has_value()) {
            cache->setPList(synthesizedConfig, cacheKeyStr, "synthesized shader materials");
        }
    }

    if (!synthesizedConfig.isNull()) {
        oo::PList macrosPList;
        if (const oo::PList* found = synthesizedConfig.find("_oo_synthesized_material_macros")) {
            macrosPList = *found;
        }
        result = materialWithName(name,
            cacheKey,
            synthesizedConfig,
            macrosPList,
            target,
            true);
    }

    return result;
}

#else

#ifndef NDEBUG
namespace {

// Read once, on first use (was +initialize, sent before the class's first message).
bool DumpShaderSource()
{
    static const bool dump = oo::Defaults::standard().boolForKey("dump-synthesized-shaders");
    return dump;
}

} // namespace
#endif

oo::Ref<OOMaterial> OOMaterial::defaultShaderMaterialWithName(const std::optional<std::string>& name,
    const std::optional<std::string>& cacheKey,
    const oo::PList& configuration,
    const oo::PList& macros,
    Entity* target)
{
    (void)macros;
    std::string vertexShaderSource, fragmentShaderSource;
    oo::PList textureSpecList, uniformSpecDict;

    if (!OOSynthesizeMaterialShader(configuration, name, cacheKey /* FIXME: entity name for error reporting */, &vertexShaderSource, &fragmentShaderSource, &textureSpecList, &uniformSpecDict)) {
        return nullptr;
    }
    // A failed synthesis leaves the texture list null (and the shaders empty) where it left all four nil.
    // Mirror dictionaryWithObjectsAndKeys: nil-stop — unsynthesized keeps only the is-synthesized flag.
    BOOL synthesized = !textureSpecList.isNull();
    oo::PList::Dict synthesizedConfigDict;
    synthesizedConfigDict[kOOIsSynthesizedMaterialConfigurationKey] = oo::PList(true);
    if (synthesized) {
        if (!textureSpecList.isNull())
            synthesizedConfigDict[kOOTexturesKey] = textureSpecList;
        if (!uniformSpecDict.isNull())
            synthesizedConfigDict[kOOUniformsKey] = uniformSpecDict;
        synthesizedConfigDict[kOOVertexShaderSourceKey] = oo::PList(vertexShaderSource);
        synthesizedConfigDict[kOOFragmentShaderSourceKey] = oo::PList(fragmentShaderSource);
    }
    oo::PList synthesizedConfig(std::move(synthesizedConfigDict));

#ifndef NDEBUG
    if (DumpShaderSource()) {
        const char* cacheKeyText = cacheKey ? cacheKey->c_str() : "(null)";
        const char* nameText = name ? name->c_str() : "(null)";
        std::string dumpPath = oo::str::format("Synthesized Materials/%s/%s", cacheKeyText, nameText);

                ResourceManager::writeDiagnosticString(synthesized ?, std::string(), dumpPath + ".vertex");
                ResourceManager::writeDiagnosticString(synthesized ?, std::string(), dumpPath + ".fragment");

                // Hide internal keys in the synthesized config before writing it.
                oo::PList::Dict humanFriendlyConfig = *synthesizedConfig.getIf<oo::PList::Dict>();
                humanFriendlyConfig.erase(kOOVertexShaderSourceKey);
                humanFriendlyConfig.erase(kOOFragmentShaderSourceKey);
                humanFriendlyConfig.erase(kOOIsSynthesizedMaterialConfigurationKey);
                humanFriendlyConfig[kOOVertexShaderNameKey] = oo::PList(oo::str::format("%s.vertex", nameText));
                humanFriendlyConfig[kOOFragmentShaderNameKey] = oo::PList(oo::str::format("%s.fragment", nameText));

                ResourceManager::writeDiagnosticPList(oo::PList(humanFriendlyConfig), dumpPath + ".plist");

                ResourceManager::writeDiagnosticPList(configuration, dumpPath + "-original.plist");
    }
#endif

    return materialWithName(name,
        cacheKey,
        synthesizedConfig,
        oo::PList(),
        target,
        true);
}

#endif

oo::Ref<OOMaterial> OOMaterial::materialWithName(const std::optional<std::string>& name,
    const std::optional<std::string>& cacheKey,
    const oo::PList& configuration,
    const oo::PList& macros,
    Entity* object,
    bool smooth) // Internally, this flg really means "force use of shaders".
{
    oo::Ref<OOMaterial> result;

#if OO_SHADERS

    if ((UNIVERSE != nullptr ? UNIVERSE->useShaders() : false)) {
        if (OOShaderMaterial::configurationDictionarySpecifiesShaderMaterial(configuration)) {
            result = OOShaderMaterial::shaderMaterialWithName(name,
                configuration,
                macros,
                object);
        }

        // Use default shader if smoothing is on, or shader detail is full, DEBUG_NO_SHADER_FALLBACK is set, or material uses an effect map.
        if (result == nullptr && (smooth || gDebugFlags & DEBUG_NO_SHADER_FALLBACK || (UNIVERSE != nullptr ? UNIVERSE->getDetailLevel() : OOGraphicsDetail { }) >= DETAIL_LEVEL_SHADERS || !cxx_OOMaterialCombinedSpecularMapSpecifier(configuration).isNull() || !cxx_OOMaterialNormalMapSpecifier(configuration).isNull() || !cxx_OOMaterialParallaxMapSpecifier(configuration).isNull() || !cxx_OOMaterialNormalAndParallaxMapSpecifier(configuration).isNull() || !cxx_OOMaterialEmissionMapSpecifier(configuration).isNull() || !cxx_OOMaterialIlluminationMapSpecifier(configuration).isNull() || !cxx_OOMaterialEmissionAndIlluminationMapSpecifier(configuration).isNull())) {
            result = defaultShaderMaterialWithName(name,
                cacheKey,
                configuration,
                macros,
                object);
        }
    }
#endif

#if OO_MULTITEXTURE
    if (result == nullptr /*&& !(UNIVERSE != nullptr ? UNIVERSE->reducedDetail() : false)*/) {
        if (!cxx_OOMaterialEmissionMapSpecifier(configuration).isNull() || !cxx_OOMaterialIlluminationMapSpecifier(configuration).isNull() || !cxx_OOMaterialEmissionAndIlluminationMapSpecifier(configuration).isNull()) {
            result = OOMultiTextureMaterial::materialWithName(name,
                configuration);
        }
    }
#endif

    if (result == nullptr) {
        if (cxx_OOMaterialDiffuseMapSpecifier(configuration, name).isNull()) {
            result = OOBasicMaterial::materialWithName(name, configuration);
        } else {
            result = OOSingleTextureMaterial::materialWithName(name, configuration);
        }
        if (result == nullptr) {
            result = OOBasicMaterial::materialWithName(name, configuration);
        }
    }
    return result;
}

oo::Ref<OOMaterial> OOMaterial::materialWithName(const std::optional<std::string>& name,
    const std::optional<std::string>& cacheKey,
    const oo::PList& materialDict,
    const oo::PList& shadersDict,
    const oo::PList& macros,
    Entity* object,
    bool smooth)
{
    oo::PList configuration;

#if OO_SHADERS

    if ((UNIVERSE != nullptr ? UNIVERSE->useShaders() : false) && name.has_value()) {
        if (const oo::PList* found = shadersDict.get<oo::PList::Dict>(*name)) {
            configuration = *found;
        }
    }
#endif

    if (configuration.isNull() && name.has_value()) {
        if (const oo::PList* found = materialDict.get<oo::PList::Dict>(*name)) {
            configuration = *found;
        }
    }

    if (configuration.isNull()) {
        // Use fallback material for non-existent simple texture.
        // Texture caching means this won't be wasted in the general case.
        oo::Ref<OOTexture> texture = OOTexture::textureWithName(name, std::optional<std::string>("Textures"));
        if (texture == nullptr)
            return nullptr;

        configuration = oo::PList(oo::PList::Dict { });
    }

    return materialWithName(name,
        cacheKey,
        configuration,
        macros,
        object,
        smooth);
}

#if !USE_NEW_SHADER_SYNTHESIZER
namespace {

void SetUniform(oo::PList::Dict& uniforms, const std::string& key, const char* type, const oo::PList& value)
{
    uniforms[key] = oo::PList(oo::PList::Dict {
        { "type", oo::PList(type) },
        { "value", value } });
}

void SetUniformFloat(OOMaterialSynthContext* context, const std::string& key, float value)
{
    SetUniform(context->uniforms, key, "float", oo::PList::singleReal(value));
}

void AddTexture(OOMaterialSynthContext* context, const char* uniformName, const char* nonShaderKey, const char* macroName, const oo::PList& specifier)
{
    OOCParameterAssert(context->texturesUsed < context->maxTextures);

    context->texturesUsed++;
    SetUniform(context->uniforms, uniformName, "texture", oo::PList::unsignedInteger(context->textures.size()));
    context->textures.push_back(specifier);
    if (nonShaderKey != nullptr) {
        // Upstream always wrote kOOMaterialDiffuseMapName when nonShaderKey was non-nil.
        context->outConfig[cxx_kOOMaterialDiffuseMapName] = specifier;
    }
    if (macroName != nullptr) {
        context->macros[macroName] = oo::PList("1");
    }
}

void AddColorIfAppropriate(OOMaterialSynthContext* context, OOColor* color, const char* key, const char* macroName)
{
    if (color != nil) {
        oo::PList::Array components;
        for (float component : color->normalizedArray()) {
            components.push_back(oo::PList::singleReal(component));
        }
        context->outConfig[key] = oo::PList(std::move(components));
        if (macroName != nullptr)
            context->macros[macroName] = oo::PList("1");
    }
}

void AddMacroColorIfAppropriate(OOMaterialSynthContext* context, OOColor* color, const char* macroName)
{
    if (color != nil) {
        std::string macroText = oo::str::format("vec4(%g, %g, %g, %g)",
            color->redComponent(),
            color->greenComponent(),
            color->blueComponent(),
            color->alphaComponent());
        context->macros[macroName] = oo::PList(std::move(macroText));
    }
}

void SynthDiffuse(OOMaterialSynthContext* context, const std::optional<std::string>& name)
{
    // Set up diffuse map if appropriate.
    oo::PList diffuseMapSpec = cxx_OOMaterialDiffuseMapSpecifier(context->inConfig, name);
    if (!diffuseMapSpec.isNull() && context->texturesUsed < context->maxTextures) {
        AddTexture(context, "uDiffuseMap", cxx_kOOMaterialDiffuseMapName, "OOSTD_DIFFUSE_MAP", diffuseMapSpec);

        if (diffuseMapSpec.get<bool>("cube_map")) {
            context->macros["OOSTD_DIFFUSE_MAP_IS_CUBE_MAP"] = oo::PList("1");
        }
    } else {
        // No diffuse map must be specified explicitly.
        context->outConfig[cxx_kOOMaterialDiffuseMapName] = oo::PList("");
    }

    // Set up diffuse colour if any.
    AddColorIfAppropriate(context, cxx_OOMaterialDiffuseColor(context->inConfig).get(), cxx_kOOMaterialDiffuseColorName, nullptr);
}

void SynthEmissionAndIllumination(OOMaterialSynthContext* context)
{
    // Read the various emission and illumination textures, and decide what to do with them.
    oo::PList emissionMapSpec = cxx_OOMaterialEmissionMapSpecifier(context->inConfig);
    oo::PList illuminationMapSpec = cxx_OOMaterialIlluminationMapSpecifier(context->inConfig);
    oo::PList emissionAndIlluminationSpec = cxx_OOMaterialEmissionAndIlluminationMapSpecifier(context->inConfig);
    BOOL isCombinedSpec = NO;
    BOOL haveIlluminationMap = NO;

    if (emissionMapSpec.isNull() && !emissionAndIlluminationSpec.isNull()) {
        emissionMapSpec = emissionAndIlluminationSpec;
        if (illuminationMapSpec.isNull())
            isCombinedSpec = YES; // Else use only emission part of emission_and_illumination_map, combined with full illumination_map.
    }

    if (!emissionMapSpec.isNull() && context->texturesUsed < context->maxTextures) {
        /*	FIXME: at this point, if there is an illumination map, we should
                consider merging it into the emission map using
                OOCombinedEmissionMapGenerator if the total number of texture
                specifiers is greater than context->maxTextures. This will
                require adding a new type of texture specifier - not a big deal.
                -- Ahruman 2010-05-21
        */
        AddTexture(context, "uEmissionMap", nullptr, isCombinedSpec ? "OOSTD_EMISSION_AND_ILLUMINATION_MAP" : "OOSTD_EMISSION_MAP", emissionMapSpec);
        /*	Note that this sets emission_color, not emission_modulate_color.
                This is because the emission colour value is sent through the
                standard OpenGL emission colour attribute by OOBasicMaterial.
        */
        AddColorIfAppropriate(context, cxx_OOMaterialEmissionModulateColor(context->inConfig).get(), cxx_kOOMaterialEmissionColorName, "OOSTD_EMISSION");

        haveIlluminationMap = isCombinedSpec;
    } else {
        //	No emission map, use overall emission colour if specified.
        AddColorIfAppropriate(context, cxx_OOMaterialEmissionColor(context->inConfig).get(), cxx_kOOMaterialEmissionColorName, "OOSTD_EMISSION");
    }

    if (!illuminationMapSpec.isNull() && context->texturesUsed < context->maxTextures) {
        AddTexture(context, "uIlluminationMap", nullptr, "OOSTD_ILLUMINATION_MAP", illuminationMapSpec);
        haveIlluminationMap = YES;
    }

    if (haveIlluminationMap) {
        AddMacroColorIfAppropriate(context, cxx_OOMaterialIlluminationModulateColor(context->inConfig).get(), "OOSTD_ILLUMINATION_COLOR");
    }
}

void SynthNormalMap(OOMaterialSynthContext* context)
{
    if (context->texturesUsed < context->maxTextures) {
        BOOL hasParallax = YES;
        oo::PList normalMapSpec = cxx_OOMaterialNormalAndParallaxMapSpecifier(context->inConfig);
        if (normalMapSpec.isNull()) {
            hasParallax = NO;
            normalMapSpec = cxx_OOMaterialNormalMapSpecifier(context->inConfig);
        }

        if (!normalMapSpec.isNull()) {
            AddTexture(context, "uNormalMap", nullptr, "OOSTD_NORMAL_MAP", normalMapSpec);

            if (hasParallax) {
                context->macros["OOSTD_NORMAL_AND_PARALLAX_MAP"] = oo::PList("1");
                SetUniformFloat(context, "uParallaxScale", cxx_OOMaterialParallaxScale(context->inConfig));
                SetUniformFloat(context, "uParallaxBias", cxx_OOMaterialParallaxBias(context->inConfig));
            }
        }
    }
}

void SynthSpecular(OOMaterialSynthContext* context)
{
    GLint shininess = cxx_OOMaterialSpecularExponent(context->inConfig);
    if (shininess <= 0)
        return;

    GLfloat gloss = cxx_OOMaterialGloss(context->inConfig);
    if (gloss < 0.0f || gloss > 1.0f)
        return;

    BOOL gammaCorrect = cxx_OOMaterialGammaCorrect(context->inConfig) ? YES : NO;

    oo::PList specularMapSpec;
    oo::Ref<OOColor> specularColor;

    if (context->texturesUsed < context->maxTextures) {
        specularMapSpec = cxx_OOMaterialCombinedSpecularMapSpecifier(context->inConfig);
    }

    if (!specularMapSpec.isNull())
        specularColor = cxx_OOMaterialSpecularModulateColor(context->inConfig);
    else
        specularColor = cxx_OOMaterialSpecularColor(context->inConfig);
    if (specularColor->isBlack())
        return;

    SetUniformFloat(context, "uGloss", gloss);

    context->outConfig[cxx_kOOMaterialSpecularExponentLegacyName] = oo::PList::unsignedInteger(static_cast<unsigned int>(shininess));

    if (!specularMapSpec.isNull()) {
        AddTexture(context, "uSpecularMap", cxx_kOOMaterialDiffuseMapName, "OOSTD_SPECULAR_MAP", specularMapSpec);
    }

    if (specularColor != nil) {
        /*	As with emission colour, specular_modulate_color is transformed to
         specular_color here because the shader reads it from the standard
         material specular colour property set by OOBasicMaterial.
         */
        oo::PList::Array components;
        for (float component : specularColor->normalizedArray()) {
            components.push_back(oo::PList::singleReal(component));
        }
        context->outConfig[cxx_kOOMaterialSpecularColorName] = oo::PList(std::move(components));
    }
    context->macros["OOSTD_SPECULAR"] = oo::PList("1");

    // setting a bool as a float uniform, to be used in the shader as a bool again
    // this is how hackish I can get... maybe a better way exists, but this is quick
    // and can be used also for the shader materials in a not too different way
    // - Nikos 20181001
    SetUniformFloat(context, "uGammaCorrect", (float)gammaCorrect);
}

} // namespace
#endif
