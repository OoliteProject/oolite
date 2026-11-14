/*

OOShaderMaterial.m


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

#import "OOShaderMaterial.h"
#include "oofnd/objc/OORuntime.h"

#if OO_SHADERS

#import "OOCollectionExtractors.h"
#import "OODebugFlags.h"
#import "OOFoundationBridge.h"
#import "OOFunctionAttributes.h"
#import "OOIsNumberLiteral.h"
#import "OOLogging.h"
#import "OOMacroOpenGL.h"
#import "OOOpenGLExtensionManager.h"
#import "OOShaderProgram.h"
#import "OOShaderUniform.h"
#import "OOStringBridge.h"
#import "OOStringParsing.h"
#import "OOTexture.h"
#import "ResourceManager.h"
#import "Universe.h"
#include "oofnd/Defaults.hpp"
#include "oofnd/PListGet.hpp"
#include "oofnd/String.hpp"

namespace {

// Dictionary -oo_stringForKey: as the old code read it: a string, or a number's -stringValue;
// nullopt (nil) for anything else or a missing key.
std::optional<std::string> StringForKey(const oo::PList& dictionary, std::string_view key)
{
    const oo::PList* entry = dictionary.find(key);
    if (entry == nullptr || !(entry->isString() || entry->isNumber()))
        return std::nullopt;
    return dictionary.get<std::string>(key);
}

} // namespace

namespace {

// nullopt fileName: no shader of this type (YES, *outResult untouched).
BOOL GetShaderSource(const std::optional<std::string>& fileName, const std::string& shaderType, const std::optional<std::string>& prefix, std::optional<std::string>* outResult);
// A macro dictionary as #define lines; nullopt for none or an empty result.
std::optional<std::string> MacrosToString(const oo::PList& macros);

} // namespace

@interface OOShaderMaterial (OOPrivate)

// Convert a "textures" array (texture specifiers) to texture objects.
- (std::vector<oo::ObjCRef<OOTexture*>>)loadTexturesFromArray:(const oo::PList&)textureSpecs unitCount:(GLuint)max;

// Load up an array of texture objects.
- (void)addTexturesFromArray:(const std::vector<oo::ObjCRef<OOTexture*>>&)textureObjects unitCount:(GLuint)max;

@end

@implementation OOShaderMaterial

+ (BOOL)configurationDictionarySpecifiesShaderMaterial:(const oo::PList&)configuration
{
    if (configuration.isNull())
        return NO;

    if (StringForKey(configuration, kOOVertexShaderSourceKey).has_value())
        return YES;
    if (StringForKey(configuration, kOOFragmentShaderSourceKey).has_value())
        return YES;
    if (StringForKey(configuration, kOOVertexShaderNameKey).has_value())
        return YES;
    if (StringForKey(configuration, kOOVertexShaderNameKey).has_value())
        return YES;

    return NO;
}

+ (instancetype)shaderMaterialWithName:(const std::optional<std::string>&)name
                         configuration:(const oo::PList&)configuration
                                macros:(const oo::PList&)macros
                         bindingTarget:(id<OOWeakReferenceSupport>)target
{
    return [[[self alloc] initWithName:name configuration:configuration macros:macros bindingTarget:target] autorelease];
}

- (id)initWithName:(const std::optional<std::string>&)name
     configuration:(const oo::PList&)configuration
            macros:(const oo::PList&)macros
     bindingTarget:(id<OOWeakReferenceSupport>)target
{
    BOOL OK = YES;
    std::optional<std::string> macroString;
    std::optional<std::string> vertexShader;
    std::optional<std::string> fragmentShader;
    GLint textureUnits = [[OOOpenGLExtensionManager sharedManager] textureImageUnitCount];
    oo::PList modifiedMacros;
    std::optional<std::string> vsName = "<synthesized>";
    std::optional<std::string> fsName = "<synthesized>";
    std::optional<std::string> vsCacheKey;
    std::optional<std::string> fsCacheKey;

    if (configuration.isNull())
        OK = NO;

    id configurationObject = oo::ObjectFromPList(configuration);
    self = [super initWithName:oo::NSStringOrNil(name) configuration:configurationObject];
    if (self == nil)
        OK = NO;

    if (OK) {
        // A copy of the macros (an empty one for nil, as +dictionary / -mutableCopy gave).
        modifiedMacros = macros.isDict() ? macros : oo::PList(oo::PList::Dict { });
        (*modifiedMacros.getIf<oo::PList::Dict>())["OO_TEXTURE_UNIT_COUNT"] = oo::PList::unsignedInteger(static_cast<std::uint64_t>(textureUnits));

        // used to test for simplified shaders - OO_REDUCED_COMPLEXITY - here
        macroString = MacrosToString(modifiedMacros);
    }

    if (OK) {
        vertexShader = StringForKey(configuration, kOOVertexShaderSourceKey);
        if (!vertexShader.has_value()) {
            vsName = StringForKey(configuration, kOOVertexShaderNameKey);
            vsCacheKey = vsName;
            if (vsName.has_value()) {
                if (!GetShaderSource(vsName, "vertex", macroString, &vertexShader))
                    OK = NO;
            }
        } else {
            vsCacheKey = vertexShader;
        }
    }

    if (OK) {
        fragmentShader = StringForKey(configuration, kOOFragmentShaderSourceKey);
        if (!fragmentShader.has_value()) {
            fsName = StringForKey(configuration, kOOFragmentShaderNameKey);
            fsCacheKey = fsName;
            if (fsName.has_value()) {
                if (!GetShaderSource(fsName, "fragment", macroString, &fragmentShader))
                    OK = NO;
            }
        } else {
            fsCacheKey = fragmentShader;
        }
    }

    if (OK) {
        if (vertexShader.has_value() || fragmentShader.has_value()) {
            static oo::PList attributeBindings;
            if (attributeBindings.isNull()) {
                attributeBindings = oo::PList(oo::PList::Dict {
                    { "tangent", oo::PList::signedInteger(kTangentAttributeIndex) } });
            }

            // %@ of a nil string printed "(null)"; keep that text in the cache key.
            const std::optional<std::string> cacheKey = oo::str::format(
                "$VERTEX:\n%s\n\n$FRAGMENT:\n%s\n\n$MACROS:\n%s\n",
                vsCacheKey.has_value() ? vsCacheKey->c_str() : "(null)",
                fsCacheKey.has_value() ? fsCacheKey->c_str() : "(null)",
                macroString.has_value() ? macroString->c_str() : "(null)");

            OOLogIndent();
            shaderProgram = [OOShaderProgram shaderProgramWithVertexShader:vertexShader
                                                            fragmentShader:fragmentShader
                                                          vertexShaderName:vsName
                                                        fragmentShaderName:fsName
                                                                    prefix:macroString
                                                         attributeBindings:attributeBindings
                                                                  cacheKey:cacheKey];
            OOLogOutdent();

// no reduced complexity mode now
#if 0
			if (shaderProgram == nil)
			{

				BOOL canFallBack = !modifiedMacros.get<bool>("OO_REDUCED_COMPLEXITY");
#ifdef OO_DEBUG_MONITOR_ENABLED
				if (gDebugFlags & DEBUG_NO_SHADER_FALLBACK)  canFallBack = NO;
#endif
				if (canFallBack)
				{
					OO_LOG_WARN("shader.load.fullModeFailed", "Could not build shader {}/{} in full complexity mode, trying simple mode.", vsName.value_or("(null)"), fsName.value_or("(null)"));
					
					(*modifiedMacros.getIf<oo::PList::Dict>())["OO_REDUCED_COMPLEXITY"] = oo::PList::signedInteger(1);
					macroString = MacrosToString(modifiedMacros);
					cacheKey = *cacheKey + "\n$SIMPLIFIED FALLBACK\n";
					
					OOLogIndent();
					shaderProgram = [OOShaderProgram shaderProgramWithVertexShader:vertexShader
																	fragmentShader:fragmentShader
																  vertexShaderName:vsName
																fragmentShaderName:fsName
																			prefix:macroString
																 attributeBindings:attributeBindings
																		  cacheKey:cacheKey];
					OOLogOutdent();
					
					if (shaderProgram != nil)
					{
						OO_LOG("shader.load.fallbackSuccess", "{}", "Simple mode fallback successful.");
					}
				}
			}
#endif

            if (shaderProgram == nil) {
                OO_LOG_ERR("shader.load.failed", "Could not build shader {}/{}.", vsName.value_or("(null)"), fsName.value_or("(null)"));
            }
        } else {
            OO_LOG("shader.load.noShader", "***** Error: no vertex or fragment shader specified in shader dictionary:\n{}", oo::DescriptionOf(oo::ObjectFromPList(configuration)));
        }

        OK = (shaderProgram != nil);
        if (OK)
            [shaderProgram retain];
    }

    if (OK) {
        // Load uniforms and textures, which are a flavour of uniform for our purpose.
        const oo::PList* uniformDefs = configuration.find(kOOUniformsKey);

        // Texture objects from the configuration (Object nodes), else texture specifiers loaded.
        std::vector<oo::ObjCRef<OOTexture*>> textureObjects;
        if (const oo::PList* textureArray = configuration.get<oo::PList::Array>(kOOTextureObjectsKey)) {
            for (const oo::PList& entry : *textureArray->getIf<oo::PList::Array>()) {
                textureObjects.push_back(oo::ObjCRef<OOTexture*>(oo::ObjectIn(entry)));
            }
        } else if (const oo::PList* textureSpecs = configuration.get<oo::PList::Array>(kOOTexturesKey)) {
            textureObjects = [self loadTexturesFromArray:*textureSpecs unitCount:textureUnits];
        }

        [self addUniformsFromDictionary:uniformDefs != nullptr ? *uniformDefs : oo::PList() withBindingTarget:target];
        [self addTexturesFromArray:textureObjects unitCount:textureUnits];
    }

    if (OK) {
        // write gloss and gamma correction preference to the uniforms dictionary

        if (uniforms.find("uGloss") == uniforms.end()) {
            float gloss = OOClamp_0_1_f(configuration.get<float>("gloss", 0.5f));
            [self setUniform:"uGloss" floatValue:gloss];
        }

        if (uniforms.find("uGammaCorrect") == uniforms.end()) {
            BOOL gammaCorrect = configuration.get<bool>("gamma_correct", !oo::Defaults::standard().boolForKey("no-gamma-correct"));
            [self setUniform:"uGammaCorrect" floatValue:(float)gammaCorrect];
        }
    }

    if (!OK) {
        [self release];
        self = nil;
    }
    return self;
}

- (void)dealloc
{
    uint32_t i;

    [self willDealloc];

    [shaderProgram release];

    if (textures != NULL) {
        for (i = 0; i != texCount; ++i) {
            [textures[i] release];
        }
        free(textures);
    }

    [bindingTarget release];

    [super dealloc];
}

- (BOOL)bindUniform:(const std::string&)uniformName
           toObject:(id<OOWeakReferenceSupport>)source
           property:(SEL)selector
     convertOptions:(OOUniformConvertOptions)options
{
    OOShaderUniform* uniform = nil;

    uniform = [[OOShaderUniform alloc] initWithName:uniformName
                                      shaderProgram:shaderProgram
                                      boundToObject:source
                                           property:selector
                                     convertOptions:options];
    if (uniform != nil) {
        OO_LOG("shader.uniform.set", "Set up uniform {}", oo::DescriptionOf(uniform));
        uniforms[uniformName] = oo::ObjCRef<OOShaderUniform*>::adopt(uniform);
        return YES;
    } else {
        OO_LOG("shader.uniform.unSet", "Did not set uniform \"{}\"", uniformName);
        uniforms.erase(uniformName);
        return NO;
    }
}

- (BOOL)bindSafeUniform:(const std::string&)uniformName
               toObject:(id<OOWeakReferenceSupport>)target
          propertyNamed:(const std::optional<std::string>&)property
         convertOptions:(OOUniformConvertOptions)options
{
    SEL selector = NULL;

    selector = OOSelectorFromName(property.has_value() ? property->c_str() : nullptr);

    if (selector != NULL && OOUniformBindingPermitted(*property, target)) {
        return [self bindUniform:uniformName
                        toObject:target
                        property:selector
                  convertOptions:options];
    } else {
        OO_LOG("shader.uniform.unpermittedMethod", "Did not bind uniform \"{}\" to property -[{} {}] - unpermitted method.", uniformName, oo::DescriptionOf([target class]), property.value_or("(null)"));
    }

    return NO;
}

- (void)setUniform:(const std::string&)uniformName intValue:(int)value
{
    OOShaderUniform* uniform = nil;

    uniform = [[OOShaderUniform alloc] initWithName:uniformName
                                      shaderProgram:shaderProgram
                                           intValue:value];
    if (uniform != nil) {
        OO_LOG("shader.uniform.set", "Set up uniform {}", oo::DescriptionOf(uniform));
        uniforms[uniformName] = oo::ObjCRef<OOShaderUniform*>::adopt(uniform);
    } else {
        OO_LOG("shader.uniform.unSet", "Did not set uniform \"{}\"", uniformName);
        uniforms.erase(uniformName);
    }
}

- (void)setUniform:(const std::string&)uniformName floatValue:(float)value
{
    OOShaderUniform* uniform = nil;

    uniform = [[OOShaderUniform alloc] initWithName:uniformName
                                      shaderProgram:shaderProgram
                                         floatValue:value];
    if (uniform != nil) {
        OO_LOG("shader.uniform.set", "Set up uniform {}", oo::DescriptionOf(uniform));
        uniforms[uniformName] = oo::ObjCRef<OOShaderUniform*>::adopt(uniform);
    } else {
        OO_LOG("shader.uniform.unSet", "Did not set uniform \"{}\"", uniformName);
        uniforms.erase(uniformName);
    }
}

- (void)setUniform:(const std::string&)uniformName vectorValue:(GLfloat[4])value
{
    OOShaderUniform* uniform = nil;

    uniform = [[OOShaderUniform alloc] initWithName:uniformName
                                      shaderProgram:shaderProgram
                                        vectorValue:value];
    if (uniform != nil) {
        OO_LOG("shader.uniform.set", "Set up uniform {}", oo::DescriptionOf(uniform));
        uniforms[uniformName] = oo::ObjCRef<OOShaderUniform*>::adopt(uniform);
    } else {
        OO_LOG("shader.uniform.unSet", "Did not set uniform \"{}\"", uniformName);
        uniforms.erase(uniformName);
    }
}

- (void)setUniform:(const std::string&)uniformName vectorObjectValue:(const oo::PList&)value
{
    GLfloat vecArray[4];
    if (value.isArray() && value.count() == 4) {
        for (unsigned i = 0; i < 4; i++) {
            vecArray[i] = value.at<float>(i, 0.0f); // OOFloatFromObject's conversion
        }
    } else {
        Vector vec = OOVectorFromObject(oo::ObjectFromPList(value), kZeroVector);
        vecArray[0] = vec.x;
        vecArray[1] = vec.y;
        vecArray[2] = vec.z;
        vecArray[3] = 1.0;
    }

    OOShaderUniform* uniform = [[OOShaderUniform alloc] initWithName:uniformName
                                                       shaderProgram:shaderProgram
                                                         vectorValue:vecArray];
    if (uniform != nil) {
        OO_LOG("shader.uniform.set", "Set up uniform {}", oo::DescriptionOf(uniform));
        uniforms[uniformName] = oo::ObjCRef<OOShaderUniform*>::adopt(uniform);
    } else {
        OO_LOG("shader.uniform.unSet", "Did not set uniform \"{}\"", uniformName);
        uniforms.erase(uniformName);
    }
}

- (void)setUniform:(const std::string&)uniformName quaternionValue:(Quaternion)value asMatrix:(BOOL)asMatrix
{
    OOShaderUniform* uniform = nil;

    uniform = [[OOShaderUniform alloc] initWithName:uniformName
                                      shaderProgram:shaderProgram
                                    quaternionValue:value
                                           asMatrix:asMatrix];
    if (uniform != nil) {
        OO_LOG("shader.uniform.set", "Set up uniform {}", oo::DescriptionOf(uniform));
        uniforms[uniformName] = oo::ObjCRef<OOShaderUniform*>::adopt(uniform);
    } else {
        OO_LOG("shader.uniform.unSet", "Did not set uniform \"{}\"", uniformName);
        uniforms.erase(uniformName);
    }
}

- (void)addUniformsFromDictionary:(const oo::PList&)uniformDefs withBindingTarget:(id<OOWeakReferenceSupport>)target
{
    oo::PList value;
    std::optional<std::string> binding;
    std::optional<std::string> type;
    GLfloat floatValue;
    BOOL gotValue;
    OOUniformConvertOptions convertOptions;
    BOOL quatAsMatrix = YES;
    GLfloat scale = 1.0;
    uint32_t randomSeed;
    RANROTSeed savedSeed;

    if ([target respondsToSelector:@selector(randomSeedForShaders)]) {
        randomSeed = [(id)target randomSeedForShaders];
    } else {
        randomSeed = (uint32_t)(uintptr_t)self;
    }
    savedSeed = RANROTGetFullSeed();
    ranrot_srand(randomSeed);

    // The std::map's byte order is the old -compare:-sorted key order (literal UTF-16 order, the
    // same as UTF-8 byte order).
    const oo::PList::Dict* definitions = uniformDefs.getIf<oo::PList::Dict>();
    for (const auto& [name, definition] : (definitions != nullptr) ? *definitions : oo::PList::Dict()) {
        gotValue = NO;

        type.reset();
        value = oo::PList();
        binding.reset();

        if (definition.isDict()) {
            const oo::PList* valueEntry = definition.find("value");
            if (valueEntry != nullptr)
                value = *valueEntry;
            binding = StringForKey(definition, "binding");
            type = StringForKey(definition, "type");
            scale = definition.get<float>("scale", 1.0);
            if (!type.has_value()) {
                if (!value && binding.has_value())
                    type = "binding";
                else
                    type = "float";
            }
        } else if (definition.isNumber()) {
            value = definition;
            type = "float";
        } else if (const std::string* string = definition.getIf<std::string>()) {
            if (OOIsNumberLiteral(*string, NO)) {
                value = definition;
                type = "float";
            } else {
                binding = *string;
                type = "binding";
            }
        } else if (definition.isArray()) {
            // (The old code kept the array as the binding; only a "binding" type reads it.)
            type = "vector";
        }

        // Transform random values to concrete values
        if (type == "randomFloat") {
            type = "float";
            value = oo::PList::singleReal(randf() * scale);
        } else if (type == "randomUnitVector") {
            type = "vector";
            value = oo::PListFrom(OOPropertyListFromVector(vector_multiply_scalar(OORandomUnitVector(), scale)));
        } else if (type == "randomVectorSpatial") {
            type = "vector";
            value = oo::PListFrom(OOPropertyListFromVector(OOVectorRandomSpatial(scale)));
        } else if (type == "randomVectorRadial") {
            type = "vector";
            value = oo::PListFrom(OOPropertyListFromVector(OOVectorRandomRadial(scale)));
        } else if (type == "randomQuaternion") {
            type = "quaternion";
            value = oo::PListFrom(OOPropertyListFromQuaternion(OORandomQuaternion()));
        }

        if (type == "float" || type == "real") {
            // -floatValue: only a number or a string answers it.
            gotValue = YES;
            if (value.isNumber())
                floatValue = oo::plist_get::numberFloatValue(value);
            else if (const std::string* string = value.getIf<std::string>())
                floatValue = (float)oo::str::doubleValue(*string);
            else
                gotValue = NO;

            if (gotValue) {
                [self setUniform:name floatValue:floatValue];
            }
        } else if (type == "int" || type == "integer" || type == "texture") {
            /*	"texture" is allowed as a synonym for "int" because shader
                    uniforms are mapped to texture units by specifying an integer
                    index.
                    uniforms = { diffuseMap = { type = texture; value = 0; }; };
                    means "bind uniform diffuseMap to texture unit 0" (which will
                    have the first texture in the textures array).
            */
            // -intValue: only a number or a string answers it.
            if (value.isNumber()) {
                [self setUniform:name intValue:(int)value.int64Value()];
                gotValue = YES;
            } else if (const std::string* string = value.getIf<std::string>()) {
                [self setUniform:name intValue:oo::str::intValue(*string)];
                gotValue = YES;
            }
        } else if (type == "vector") {
            [self setUniform:name vectorObjectValue:value];
            gotValue = YES;
        } else if (type == "quaternion") {
            if (definition.isDict()) {
                quatAsMatrix = definition.get<bool>("asMatrix", quatAsMatrix);
            }
            [self setUniform:name
                quaternionValue:OOQuaternionFromObject(oo::ObjectFromPList(value), kIdentityQuaternion)
                       asMatrix:quatAsMatrix];
            gotValue = YES;
        } else if (target != nil && type == "binding") {
            if (definition.isDict()) {
                convertOptions = 0;
                if (definition.get<bool>("clamped", false))
                    convertOptions |= kOOUniformConvertClamp;
                if (definition.get<bool>("normalized", definition.get<bool>("normalised", false))) {
                    convertOptions |= kOOUniformConvertNormalize;
                }
                if (definition.get<bool>("asMatrix", true))
                    convertOptions |= kOOUniformConvertToMatrix;
                if (!definition.get<bool>("bindToSubentity", false))
                    convertOptions |= kOOUniformBindToSuperTarget;
            } else {
                convertOptions = kOOUniformConvertDefaults;
            }

            [self bindSafeUniform:name toObject:target propertyNamed:binding convertOptions:convertOptions];
            gotValue = YES;
        }

        if (!gotValue) {
            OO_LOG("shader.uniform.badDescription", "----- Warning: could not bind uniform \"{}\" for target {} -- could not interpret definition:\n{}", name, oo::DescriptionOf(target), oo::DescriptionOf(oo::ObjectFromPList(definition)));
        }
    }

    RANROTSetFullSeed(savedSeed);
}

- (BOOL)doApply
{
    uint32_t i;

    OO_ENTER_OPENGL();

    [super doApply];
    [shaderProgram apply];

    for (i = 0; i != texCount; ++i) {
        OOGL(glActiveTextureARB(GL_TEXTURE0_ARB + i));
        [textures[i] apply];
    }
    if (texCount > 1)
        OOGL(glActiveTextureARB(GL_TEXTURE0_ARB));

    @try {
        for (const auto& [name, uniform] : uniforms) {
            [uniform.get() apply];
        }
    }
    @catch (id exception) {
    }

    return YES;
}

- (void)ensureFinishedLoading
{
    uint32_t i;

    if (textures != NULL) {
        for (i = 0; i != texCount; ++i) {
            [textures[i] ensureFinishedLoading];
        }
    }
}

- (BOOL)isFinishedLoading
{
    uint32_t i;

    if (textures != NULL) {
        for (i = 0; i != texCount; ++i) {
            if (![textures[i] isFinishedLoading])
                return NO;
        }
    }

    return YES;
}

- (void)unapplyWithNext:(OOMaterial*)next
{
    uint32_t i, count;

    if (![next isKindOfClass:[OOShaderMaterial class]]) // Avoid redundant state change
    {
        OO_ENTER_OPENGL();
        [OOShaderProgram applyNone];

        /*	BUG: unapplyWithNext: was failing to clear texture state. If a
                shader material was followed by a basic material (with no texture),
                the shader's #0 texture would be used.
                It is necessary to clear at least one texture for the case where a
                shader material with textures is followed by a shader material
                without textures, then a basic material.
                -- Ahruman 2007-08-13
        */
        count = texCount ? texCount : 1;
        for (i = 0; i != count; ++i) {
            OOGL(glActiveTextureARB(GL_TEXTURE0_ARB + i));
            [OOTexture applyNone];
        }
        if (count != 1)
            OOGL(glActiveTextureARB(GL_TEXTURE0_ARB));
    }
}

- (void)setBindingTarget:(id<OOWeakReferenceSupport>)target
{
    for (const auto& [name, uniform] : uniforms) {
        [uniform.get() setBindingTarget:target];
    }
    [bindingTarget release];
    bindingTarget = [target weakRetain];
}

- (BOOL)permitSpecular
{
    return YES;
}

#ifdef OO_DEBUG_MONITOR_ENABLED
- (id)allTextures // shared selector (proposed ADR-0043)
{
    return oo::NSSetFromObjects(std::vector<OOTexture*>(textures, textures + texCount));
}
#endif

@end

@implementation OOShaderMaterial (OOPrivate)

- (std::vector<oo::ObjCRef<OOTexture*>>)loadTexturesFromArray:(const oo::PList&)textureSpecs unitCount:(GLuint)max
{
    GLuint i, count = (GLuint)MIN(textureSpecs.count(), (size_t)max);
    std::vector<oo::ObjCRef<OOTexture*>> result;
    result.reserve(count);

    for (i = 0; i < count; i++) {
        OOTexture* texture = [OOTexture cxx_textureWithConfiguration:*textureSpecs.at(i)];
        if (texture == nil)
            texture = [OOTexture nullTexture];
        result.push_back(oo::ObjCRef<OOTexture*>(texture));
    }

    return result;
}

- (void)addTexturesFromArray:(const std::vector<oo::ObjCRef<OOTexture*>>&)textureObjects unitCount:(GLuint)max
{
    // Allocate space for texture object name array
    texCount = (uint32_t)MIN(textureObjects.size(), (size_t)max);
    if (texCount == 0)
        return;

    textures = (OOTexture**)malloc(texCount * sizeof *textures);
    if (textures == NULL) {
        texCount = 0;
        return;
    }

    // Set up texture object names and appropriate uniforms
    unsigned i;
    for (i = 0; i != texCount; ++i) {
        textures[i] = textureObjects[i].get();
        [textures[i] retain];
    }
}

@end

namespace {

std::optional<std::string> MacrosToString(const oo::PList& macros)
{
    const oo::PList::Dict* entries = macros.getIf<oo::PList::Dict>();
    if (entries == nullptr)
        return std::nullopt;

    // Keys in std::map order (was the dictionary's hash order); each value as %@ printed it.
    std::string result;
    for (const auto& entry : *entries) {
        const oo::PList& value = entry.second;
        std::string text;
        if (const std::string* string = value.getIf<std::string>())
            text = *string;
        else if (value.isNumber())
            text = oo::plist_get::numberStringValue(value);
        else
            text = oo::DescriptionOf(oo::ObjectFromPList(value));

        result += "#define " + entry.first + "  " + text + "\n";
    }

    if (result.empty())
        return std::nullopt;
    result += "\n\n";
    return result;
}

} // namespace

#endif

/*	Attempt to load fragment or vertex shader source from a file.
        Returns YES if source was loaded or no shader was specified, and NO if an
        external shader was specified but could not be found.
*/
namespace {

BOOL GetShaderSource(const std::optional<std::string>& fileName, const std::string& shaderType, const std::optional<std::string>& /* prefix: unused, as before */, std::optional<std::string>* outResult)
{
    if (!fileName.has_value())
        return YES; // It's OK for one or the other of the shaders to be undefined.

    std::optional<std::string> result = [ResourceManager cxx_stringFromFilesNamed:*fileName inFolder:std::string("Shaders")];
    if (!result.has_value()) {
        const std::vector<std::string> extensions = { shaderType, shaderType.substr(0, 4) }; // vertex and vert, or fragment and frag

        // Futureproofing -- in future, we may wish to support automatic selection between supported shader languages.
        if (!oo::str::pathHasExtensionIn(*fileName, extensions)) {
            for (const std::string& extension : extensions) {
                // No oofnd form of -stringByAppendingPathExtension: yet: kept at the boundary.
                const std::string nameWithExtension = oo::StdString([oo::NSStringFrom(*fileName) stringByAppendingPathExtension:oo::NSStringFrom(extension)]);
                result = [ResourceManager cxx_stringFromFilesNamed:nameWithExtension
                                                          inFolder:std::string("Shaders")];
                if (result.has_value())
                    break;
            }
        }
        if (!result.has_value()) {
            OO_LOG(cxx_kOOLogFileNotFound, "GLSL ERROR: failed to find {} program {}.", shaderType, *fileName);
            return NO;
        }
    }

    if (outResult != NULL)
        *outResult = result;
    return YES;
}

} // namespace
