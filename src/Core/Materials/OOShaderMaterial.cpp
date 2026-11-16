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

#include "OOShaderMaterial.h"
#include "OOObjCPList.h"
#include "OOShaderUniformMethodType.h" // the binding target's hooks (bead oo-9ht.39.6)

#if OO_SHADERS

#include "OODebugFlags.h"
#include "OOFunctionAttributes.h"
#include "OOIsNumberLiteral.h"
#include "OOLogging.h"
#include "OOMacroOpenGL.h"
#include "OOOpenGLExtensionManager.h"
#include "OOPListGameTypes.h"
#include "OOShaderProgram.h"
#include "OOShaderUniform.h"
#include "OOStringParsing.h"
#include "OOTexture.h"
#include "ResourceManager.h"
#include "Universe.h"
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

bool OOShaderMaterial::configurationDictionarySpecifiesShaderMaterial(const oo::PList& configuration)
{
    if (configuration.isNull())
        return false;

    if (StringForKey(configuration, kOOVertexShaderSourceKey).has_value())
        return true;
    if (StringForKey(configuration, kOOFragmentShaderSourceKey).has_value())
        return true;
    if (StringForKey(configuration, kOOVertexShaderNameKey).has_value())
        return true;
    if (StringForKey(configuration, kOOVertexShaderNameKey).has_value())
        return true;

    return false;
}

// What the log lines printed for the binding target's Objective-C object (beads oo-9ht.39.6,
// oo-dpyk8): its class's name and its description; "(null)" for none, or where the entities have
// registered no hooks, as nil's.
namespace {

std::string TargetClassName(Entity* target)
{
    const OOShaderEntityHooks* hooks = OOShaderEntityHooksIfSet();
    return (target != nullptr && hooks != nullptr) ? hooks->className(target) : std::string("(null)");
}

std::string TargetDescription(Entity* target)
{
    const OOShaderEntityHooks* hooks = OOShaderEntityHooksIfSet();
    return (target != nullptr && hooks != nullptr) ? hooks->description(target) : std::string("(null)");
}

} // namespace

oo::Ref<OOShaderMaterial> OOShaderMaterial::shaderMaterialWithName(const std::optional<std::string>& name,
    const oo::PList& configuration,
    const oo::PList& macros,
    Entity* target)
{
    oo::Ref<OOShaderMaterial> result = oo::makeRef<OOShaderMaterial>();
    if (!result->initWithName(name, configuration, macros, target))
        return nullptr;
    return result;
}

bool OOShaderMaterial::initWithName(const std::optional<std::string>& name,
    const oo::PList& configuration,
    const oo::PList& macros,
    Entity* target)
{
    bool OK = true;
    std::optional<std::string> macroString;
    std::optional<std::string> vertexShader;
    std::optional<std::string> fragmentShader;
    GLint textureUnits = OOOpenGLExtensionManager::sharedManager()->textureImageUnitCount();
    oo::PList modifiedMacros;
    std::optional<std::string> vsName = "<synthesized>";
    std::optional<std::string> fsName = "<synthesized>";
    std::optional<std::string> vsCacheKey;
    std::optional<std::string> fsCacheKey;

    if (configuration.isNull())
        OK = false;

    // [super initWithName:configuration:], which cannot fail (its self == nil test is gone).
    OOBasicMaterial::initWithName(name, configuration);

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
                    OK = false;
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
                    OK = false;
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
            // Held by the Ref for as long as the material wants the cached program.
            shaderProgram = OOShaderProgram::shaderProgramWithVertexShader(vertexShader, fragmentShader, vsName, fsName, macroString, attributeBindings, cacheKey);
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
					shaderProgram = OOShaderProgram::shaderProgramWithVertexShader(vertexShader, fragmentShader, vsName, fsName, macroString, attributeBindings, cacheKey);
					OOLogOutdent();

					if (shaderProgram != nil)
					{
						OO_LOG("shader.load.fallbackSuccess", "{}", "Simple mode fallback successful.");
					}
				}
			}
#endif

            if (shaderProgram.get() == nil) {
                OO_LOG_ERR("shader.load.failed", "Could not build shader {}/{}.", vsName.value_or("(null)"), fsName.value_or("(null)"));
            }
        } else {
            OO_LOG("shader.load.noShader", "***** Error: no vertex or fragment shader specified in shader dictionary:\n{}", oo::DescriptionOf(configuration));
        }

        OK = (shaderProgram.get() != nil);
    }

    if (OK) {
        // Load uniforms and textures, which are a flavour of uniform for our purpose.
        const oo::PList* uniformDefs = configuration.find(kOOUniformsKey);

        // Texture objects from the configuration (Object nodes), else texture specifiers loaded.
        std::vector<oo::Ref<OOTexture>> textureObjects;
        if (const oo::PList* textureArray = configuration.get<oo::PList::Array>(kOOTextureObjectsKey)) {
            for (const oo::PList& entry : *textureArray->getIf<oo::PList::Array>()) {
                textureObjects.push_back(oo::Ref<OOTexture>(OOTextureInObjectNode(entry)));
            }
        } else if (const oo::PList* textureSpecs = configuration.get<oo::PList::Array>(kOOTexturesKey)) {
            textureObjects = loadTexturesFromArray(*textureSpecs, textureUnits);
        }

        addUniformsFromDictionary(uniformDefs != nullptr ? *uniformDefs : oo::PList(), target);
        addTexturesFromArray(textureObjects, textureUnits);
    }

    if (OK) {
        // write gloss and gamma correction preference to the uniforms dictionary

        if (uniforms.find("uGloss") == uniforms.end()) {
            float gloss = OOClamp_0_1_f(configuration.get<float>("gloss", 0.5f));
            setUniform("uGloss", gloss);
        }

        if (uniforms.find("uGammaCorrect") == uniforms.end()) {
            BOOL gammaCorrect = configuration.get<bool>("gamma_correct", !oo::Defaults::standard().boolForKey("no-gamma-correct"));
            setUniform("uGammaCorrect", (float)gammaCorrect);
        }
    }

    // [self release]; self = nil where !OK: the factory drops the object.
    return OK;
}

// -dealloc's body, but for its first line ([self willDealloc], the root facade's: proposed ADR-0056,
// amendment oo-smy item 3); the shader program is an oo::Ref. (The binding target the material kept
// and never read went with bead oo-9ht.39.6: the uniforms hold it.)
OOShaderMaterial::~OOShaderMaterial()
{
    uint32_t i;

    if (textures != NULL) {
        for (i = 0; i != texCount; ++i) {
            oo::release(textures[i]);
        }
        free(textures);
    }
}

bool OOShaderMaterial::bindUniform(const std::string& uniformName,
    Entity* source,
    const char* property,
    OOUniformConvertOptions options)
{
    oo::Ref<OOShaderUniform> uniform;

    uniform = OOShaderUniform::initWithEntityTarget(uniformName, shaderProgram.get(), source, property, options);
    if (uniform != nullptr) {
        OO_LOG("shader.uniform.set", "Set up uniform {}", uniform->description().value_or("(null)"));
        uniforms[uniformName] = uniform;
        return true;
    } else {
        OO_LOG("shader.uniform.unSet", "Did not set uniform \"{}\"", uniformName);
        uniforms.erase(uniformName);
        return false;
    }
}

bool OOShaderMaterial::bindSafeUniform(const std::string& uniformName,
    Entity* target,
    const std::optional<std::string>& property,
    OOUniformConvertOptions options)
{
    // The property's name, where it was its selector (bead oo-xu228.3.2): NULL exactly where there is none.
    const char* propertyName = property.has_value() ? property->c_str() : nullptr;

    if (propertyName != NULL && OOUniformBindingPermitted(*property, target)) {
        return bindUniform(uniformName,
            target,
            propertyName,
            options);
    } else {
        OO_LOG("shader.uniform.unpermittedMethod", "Did not bind uniform \"{}\" to property -[{} {}] - unpermitted method.", uniformName, TargetClassName(target), property.value_or("(null)"));
    }

    return false;
}

void OOShaderMaterial::setUniform(const std::string& uniformName, int value)
{
    oo::Ref<OOShaderUniform> uniform;

    uniform = OOShaderUniform::initWithName(uniformName, shaderProgram.get(), value);
    if (uniform != nullptr) {
        OO_LOG("shader.uniform.set", "Set up uniform {}", uniform->description().value_or("(null)"));
        uniforms[uniformName] = uniform;
    } else {
        OO_LOG("shader.uniform.unSet", "Did not set uniform \"{}\"", uniformName);
        uniforms.erase(uniformName);
    }
}

void OOShaderMaterial::setUniform(const std::string& uniformName, float value)
{
    oo::Ref<OOShaderUniform> uniform;

    uniform = OOShaderUniform::initWithName(uniformName, shaderProgram.get(), value);
    if (uniform != nullptr) {
        OO_LOG("shader.uniform.set", "Set up uniform {}", uniform->description().value_or("(null)"));
        uniforms[uniformName] = uniform;
    } else {
        OO_LOG("shader.uniform.unSet", "Did not set uniform \"{}\"", uniformName);
        uniforms.erase(uniformName);
    }
}

void OOShaderMaterial::setUniform(const std::string& uniformName, GLfloat value[4])
{
    oo::Ref<OOShaderUniform> uniform;

    uniform = OOShaderUniform::initWithName(uniformName, shaderProgram.get(), value);
    if (uniform != nullptr) {
        OO_LOG("shader.uniform.set", "Set up uniform {}", uniform->description().value_or("(null)"));
        uniforms[uniformName] = uniform;
    } else {
        OO_LOG("shader.uniform.unSet", "Did not set uniform \"{}\"", uniformName);
        uniforms.erase(uniformName);
    }
}

void OOShaderMaterial::setUniform(const std::string& uniformName, const oo::PList& value)
{
    GLfloat vecArray[4];
    if (value.isArray() && value.count() == 4) {
        for (unsigned i = 0; i < 4; i++) {
            vecArray[i] = value.at<float>(i, 0.0f); // OOFloatFromObject's conversion
        }
    } else {
        Vector vec = OOVectorFromPList(&value, kZeroVector);
        vecArray[0] = vec.x;
        vecArray[1] = vec.y;
        vecArray[2] = vec.z;
        vecArray[3] = 1.0;
    }

    oo::Ref<OOShaderUniform> uniform = OOShaderUniform::initWithName(uniformName, shaderProgram.get(), vecArray);
    if (uniform != nullptr) {
        OO_LOG("shader.uniform.set", "Set up uniform {}", uniform->description().value_or("(null)"));
        uniforms[uniformName] = uniform;
    } else {
        OO_LOG("shader.uniform.unSet", "Did not set uniform \"{}\"", uniformName);
        uniforms.erase(uniformName);
    }
}

void OOShaderMaterial::setUniform(const std::string& uniformName, Quaternion value, bool asMatrix)
{
    oo::Ref<OOShaderUniform> uniform;

    uniform = OOShaderUniform::initWithName(uniformName, shaderProgram.get(), value, asMatrix);
    if (uniform != nullptr) {
        OO_LOG("shader.uniform.set", "Set up uniform {}", uniform->description().value_or("(null)"));
        uniforms[uniformName] = uniform;
    } else {
        OO_LOG("shader.uniform.unSet", "Did not set uniform \"{}\"", uniformName);
        uniforms.erase(uniformName);
    }
}

void OOShaderMaterial::addUniformsFromDictionary(const oo::PList& uniformDefs, Entity* target)
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

    const OOShaderEntityHooks* hooks = OOShaderEntityHooksIfSet();
    if (target != nullptr && hooks != nullptr && hooks->randomSeed(target, &randomSeed)) {
        // -randomSeedForShaders, where the target's object answered it (bead oo-9ht.39.6: the hook).
    } else {
        // The material's address, as (uint32_t)(uintptr_t)self was: now the C++ object's.
        randomSeed = (uint32_t)(uintptr_t)this;
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
            value = OOPListFromVector(vector_multiply_scalar(OORandomUnitVector(), scale));
        } else if (type == "randomVectorSpatial") {
            type = "vector";
            value = OOPListFromVector(OOVectorRandomSpatial(scale));
        } else if (type == "randomVectorRadial") {
            type = "vector";
            value = OOPListFromVector(OOVectorRandomRadial(scale));
        } else if (type == "randomQuaternion") {
            type = "quaternion";
            value = OOPListFromQuaternion(OORandomQuaternion());
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
                setUniform(name, floatValue);
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
                setUniform(name, (int)value.int64Value());
                gotValue = YES;
            } else if (const std::string* string = value.getIf<std::string>()) {
                setUniform(name, (int)oo::str::intValue(*string));
                gotValue = YES;
            }
        } else if (type == "vector") {
            setUniform(name, value);
            gotValue = YES;
        } else if (type == "quaternion") {
            if (definition.isDict()) {
                quatAsMatrix = definition.get<bool>("asMatrix", quatAsMatrix);
            }
            setUniform(name,
                OOQuaternionFromPList(&value, kIdentityQuaternion),
                quatAsMatrix);
            gotValue = YES;
        } else if (target != nullptr && type == "binding") {
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

            bindSafeUniform(name, target, binding, convertOptions);
            gotValue = YES;
        }

        if (!gotValue) {
            OO_LOG("shader.uniform.badDescription", "----- Warning: could not bind uniform \"{}\" for target {} -- could not interpret definition:\n{}", name, TargetDescription(target), oo::DescriptionOf(definition));
        }
    }

    RANROTSetFullSeed(savedSeed);
}

bool OOShaderMaterial::doApply()
{
    uint32_t i;

    OO_ENTER_OPENGL();

    OOBasicMaterial::doApply();
    shaderProgram->apply();

    for (i = 0; i != texCount; ++i) {
        OOGL(glActiveTextureARB(GL_TEXTURE0_ARB + i));
        if (textures[i] != nullptr)
            textures[i]->apply(); // a message to nil did nothing
    }
    if (texCount > 1)
        OOGL(glActiveTextureARB(GL_TEXTURE0_ARB));

    // @try / @catch (id): a C++ catch (...) catches an Objective-C exception (ADR-0056 amendment oo-ppc).
    try {
        for (const auto& [name, uniform] : uniforms) {
            uniform->apply();
        }
    } catch (...) {
        // @catch (id exception) {}: the uniforms after the one that raised are not applied, and the
        // material still applies.
        return true;
    }

    return true;
}

void OOShaderMaterial::ensureFinishedLoading()
{
    uint32_t i;

    if (textures != NULL) {
        for (i = 0; i != texCount; ++i) {
            if (textures[i] != nullptr)
                textures[i]->ensureFinishedLoading();
        }
    }
}

bool OOShaderMaterial::isFinishedLoading()
{
    uint32_t i;

    if (textures != NULL) {
        for (i = 0; i != texCount; ++i) {
            if (textures[i] == nullptr || !textures[i]->isFinishedLoading())
                return false; // nil answered NO
        }
    }

    return true;
}

void OOShaderMaterial::unapplyWithNext(OOMaterial* next)
{
    uint32_t i, count;

    if (dynamic_cast<OOShaderMaterial*>(next) == nullptr) // Avoid redundant state change (-isKindOfClass:; nil is not one)
    {
        OO_ENTER_OPENGL();
        OOShaderProgram::applyNone();

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
            OOTexture::applyNone();
        }
        if (count != 1)
            OOGL(glActiveTextureARB(GL_TEXTURE0_ARB));
    }
}

void OOShaderMaterial::setBindingTarget(Entity* target)
{
    for (const auto& [name, uniform] : uniforms) {
        uniform->setEntityBindingTarget(target);
    }
}

bool OOShaderMaterial::permitSpecular()
{
    return true;
}

#ifdef OO_DEBUG_MONITOR_ENABLED
std::vector<oo::Ref<OOTexture>> OOShaderMaterial::allTextures()
{
    std::vector<oo::Ref<OOTexture>> result;
    result.reserve(texCount);
    for (uint32_t i = 0; i < texCount; i++) {
        result.emplace_back(textures[i]);
    }
    return result;
}
#endif

std::vector<oo::Ref<OOTexture>> OOShaderMaterial::loadTexturesFromArray(const oo::PList& textureSpecs, GLuint max)
{
    GLuint i, count = (GLuint)MIN(textureSpecs.count(), (size_t)max);
    std::vector<oo::Ref<OOTexture>> result;
    result.reserve(count);

    for (i = 0; i < count; i++) {
        oo::Ref<OOTexture> texture = OOTexture::textureWithConfiguration(*textureSpecs.at(i));
        if (texture == nullptr)
            texture = OOTexture::nullTexture();
        result.push_back(texture);
    }

    return result;
}

void OOShaderMaterial::addTexturesFromArray(const std::vector<oo::Ref<OOTexture>>& textureObjects, GLuint max)
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
        textures[i] = oo::Ref<OOTexture>(textureObjects[i]).leakRef(); // released in the destructor
    }
}

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
            text = oo::DescriptionOf(value);

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

    std::optional<std::string> result = ResourceManager::stringFromFilesNamed(*fileName, std::string("Shaders"));
    if (!result.has_value()) {
        const std::vector<std::string> extensions = { shaderType, shaderType.substr(0, 4) }; // vertex and vert, or fragment and frag

        // Futureproofing -- in future, we may wish to support automatic selection between supported shader languages.
        if (!oo::str::pathHasExtensionIn(*fileName, extensions)) {
            for (const std::string& extension : extensions) {
                const std::string nameWithExtension = oo::str::appendingPathExtension(*fileName, extension);
                result = ResourceManager::stringFromFilesNamed(nameWithExtension, std::string("Shaders"));
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
