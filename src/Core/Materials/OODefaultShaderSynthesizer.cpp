/*

OODefaultShaderSynthesizer.m


Copyright © 2011-2013 Jens Ayton

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the “Software”), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

*/

#include "OODefaultShaderSynthesizer.h"
#include "OOColor.h"
#include "OOMesh.h"
#include "OOTexture.h"

#include "OOMaterialSpecifier.h"
#include "ResourceManager.h"
#include "oofnd/Log.hpp"
#include "oofnd/StdLib.hpp"
#include "oofnd/String.hpp"
#include "oofnd/objc/OOAssert.h"
#include "oofnd/objc/OOException.h"

namespace {

oo::PList CanonicalizeMaterialSpecifier(const oo::PList& spec, const std::optional<std::string>& materialKey);

} // namespace

namespace {

std::string FormatFloat(double value);

} // namespace

/*
        REQUIRE_STAGE(): pull in the required stage. A stage must have a
        zero-parameter member function and a matching _completed_stage member.

        In debug/testrelease builds, this dispatches through performStage() which
        checks for recursive calls. The stage is named by its text and called through
        a member-function pointer where it was named by a selector (bead oo-bhxc).
*/
#ifndef NDEBUG
#define REQUIRE_STAGE(NAME)                                     \
    if (!_completed_##NAME) {                                   \
        performStage(#NAME, &OODefaultShaderSynthesizer::NAME); \
        _completed_##NAME = YES;                                \
    }
#else
#define REQUIRE_STAGE(NAME)      \
    if (!_completed_##NAME) {    \
        NAME();                  \
        _completed_##NAME = YES; \
    }
#endif

namespace {

std::optional<std::string> GetExtractMode(const oo::PList& textureSpecifier);

} // namespace

BOOL OOSynthesizeMaterialShader(const oo::PList& configuration, const std::optional<std::string>& materialKey, const std::optional<std::string>& entityName, std::string* outVertexShader, std::string* outFragmentShader, oo::PList* outTextureSpecs, oo::PList* outUniformSpecs)
{
    OOCParameterAssert(!configuration.isNull() && outVertexShader != NULL && outFragmentShader != NULL && outTextureSpecs != NULL && outUniformSpecs != NULL);

    {
        oo::Ref<OODefaultShaderSynthesizer> synthesizer = oo::makeRef<OODefaultShaderSynthesizer>(configuration, materialKey, entityName);

        bool OK = synthesizer->run();
        if (OK) {
            *outVertexShader = synthesizer->vertexShader();
            *outFragmentShader = synthesizer->fragmentShader();
            *outTextureSpecs = synthesizer->textureSpecifications();
            *outUniformSpecs = synthesizer->uniformSpecifications();
        } else {
            outVertexShader->clear();
            outFragmentShader->clear();
            *outTextureSpecs = oo::PList();
            *outUniformSpecs = oo::PList();
        }
    }

    return YES;
}

OODefaultShaderSynthesizer::OODefaultShaderSynthesizer(const oo::PList& configuration, const std::optional<std::string>& materialKey, const std::optional<std::string>& /*name*/)
{
    _configuration = CanonicalizeMaterialSpecifier(configuration, materialKey);
    _materialKey = materialKey;
    // _entityName stays nil: upstream copied it from itself ([_entityName copy]) instead of name.
}

/*	-dealloc sent -destroyTemporaries, which only empties members that the destructor destroys
        anyway; the destructor is the implicit one (amendment oo-vt0o item 2).
*/

std::string OODefaultShaderSynthesizer::vertexShader()
{
    return _vertexShader;
}

std::string OODefaultShaderSynthesizer::fragmentShader()
{
    return _fragmentShader;
}

oo::PList OODefaultShaderSynthesizer::textureSpecifications()
{
    return oo::PList(oo::PList::Array(_textures));
}

oo::PList OODefaultShaderSynthesizer::uniformSpecifications()
{
    return oo::PList(_uniforms);
}

bool OODefaultShaderSynthesizer::run()
{
    createTemporaries();
    _uniforms.clear();
    _vertexBody += "void main(void)\n{\n";
    _fragmentPreTextures += "void main(void)\n{\n";

    const oo::Finally temporaries([this] { destroyTemporaries(); }); // was @finally: runs after the handler
    try {
        REQUIRE_STAGE(writeFinalColorComposite);

        composeVertexShader();
        composeFragmentShader();
    } catch (...) {
        const auto exception = oo::CurrentOOException();
        if (!exception)
            throw; // not an OOException: it goes on up, as before
        // Error should have been reported already.
        return false;
    }

    return true;
}

std::optional<std::string> OODefaultShaderSynthesizer::materialKey()
{
    return _materialKey;
}

std::optional<std::string> OODefaultShaderSynthesizer::entityName()
{
    return _entityName;
}

// MARK: - Utilities

namespace {

void AppendIfNotEmpty(std::string& buffer, const std::string& segment, const char* name)
{
    if (!segment.empty()) {
        if (!buffer.empty())
            buffer += "\n\n";
        if (name != nullptr && name[0] != '\0') {
            buffer += "// ";
            buffer += name;
            buffer += "\n";
        }
        buffer += segment;
    }
}

} // namespace

namespace {

/*	The extract_channel of a texture specifier if it is one to four of r, g, b and a, else nil.
        (A number never qualifies, so only a string value is read; all-ASCII, so its UTF-8 length is its
        length in characters.)
*/
std::optional<std::string> GetExtractMode(const oo::PList& textureSpecifier)
{
    std::optional<std::string> result;

    const oo::PList* value = textureSpecifier.find(cxx_kOOTextureSpecifierSwizzleKey);
    const std::string* rawMode = (value != nullptr) ? value->getIf<std::string>() : nullptr;
    if (rawMode != nullptr) {
        std::size_t length = rawMode->size();
        if (1 <= length && length <= 4 && rawMode->find_first_not_of("rgba") == std::string::npos) {
            result = *rawMode;
        }
    }

    return result;
}

// The string-typed read of the value for key that oo::PListView did: a string, or a number as a string; anything else nil.
std::optional<std::string> OptionalStringFor(const oo::PList& spec, const char* key)
{
    const oo::PList* value = spec.find(key);
    if (value == nullptr || !(value->isString() || value->isNumber()))
        return std::nullopt;
    return spec.get<std::string>(key);
}

} // namespace

void OODefaultShaderSynthesizer::appendVariable(const std::string& name, const std::string& type, const std::string& prefix, std::string& buffer)
{
    NSUInteger typeDeclLength = prefix.size() + type.size() + 1;
    NSUInteger padding = (typeDeclLength < 20) ? (23 - typeDeclLength) / 4 : 1;
    buffer += prefix + " " + type + std::string(padding, '\t') + name + ";\n";
}

void OODefaultShaderSynthesizer::addAttribute(const std::string& name, const std::string& type)
{
    appendVariable(name, type, "attribute", _attributes);
}

void OODefaultShaderSynthesizer::addVarying(const std::string& name, const std::string& type)
{
    appendVariable(name, type, "varying", _varyings);
}

void OODefaultShaderSynthesizer::addVertexUniform(const std::string& name, const std::string& type)
{
    appendVariable(name, type, "uniform", _vertexUniforms);
}

void OODefaultShaderSynthesizer::addFragmentUniform(const std::string& name, const std::string& type)
{
    appendVariable(name, type, "uniform", _fragmentUniforms);
}

std::optional<std::string> OODefaultShaderSynthesizer::defineBindingUniform(const oo::PList& binding, const std::string& type)
{
    std::string name = OptionalStringFor(binding, "binding").value_or(std::string());
    OOCParameterAssert(!name.empty());

    oo::PList bindingSpec = binding;
    if (!OptionalStringFor(bindingSpec, "type").has_value()) {
        if (oo::PList::Dict* dict = bindingSpec.getIf<oo::PList::Dict>())
            (*dict)["type"] = oo::PList("binding");
    }

    // Use existing uniform if one is defined.
    for (const auto& [spec, uniformName] : _uniformBindingNames) {
        if (spec == bindingSpec)
            return uniformName;
    }

    // Capitalize first char of name, and prepend u. (Binding names are ASCII property names.)
    std::string baseName = "u";
    baseName += static_cast<char>(toupper(static_cast<unsigned char>(name[0])));
    baseName += name.substr(1);

    // Ensure name is unique.
    name = baseName;
    unsigned idx = 1;
    while (_uniforms.contains(name)) {
        name = oo::str::format("%s%u", baseName.c_str(), ++idx);
    }

    addFragmentUniform(name, type);

    _uniforms[name] = bindingSpec;
    _uniformBindingNames.emplace_back(bindingSpec, name);

    return name;
}

void OODefaultShaderSynthesizer::composeVertexShader()
{
    while (_vertexBody.ends_with("\t\n")) {
        _vertexBody.erase(_vertexBody.size() - 2);
    }
    _vertexBody += "}";

    std::string vertexShader;
    AppendIfNotEmpty(vertexShader, _attributes, "Attributes");
    AppendIfNotEmpty(vertexShader, _vertexUniforms, "Uniforms");
    AppendIfNotEmpty(vertexShader, _varyings, "Varyings");
    AppendIfNotEmpty(vertexShader, _vertexHelpers, "Helper functions");
    AppendIfNotEmpty(vertexShader, _vertexBody, nullptr);

    _vertexShader = vertexShader;
}

void OODefaultShaderSynthesizer::composeFragmentShader()
{
    while (_fragmentBody.ends_with("\t\n")) {
        _fragmentBody.erase(_fragmentBody.size() - 2);
    }

    std::string fragmentShader;
    AppendIfNotEmpty(fragmentShader, _fragmentUniforms, "Uniforms");
    AppendIfNotEmpty(fragmentShader, _varyings, "Varyings");
    AppendIfNotEmpty(fragmentShader, _fragmentHelpers, "Helper functions");
    AppendIfNotEmpty(fragmentShader, _fragmentPreTextures, nullptr);
    if (!_fragmentTextureLookups.empty()) {
        fragmentShader += "\t\n\t// Texture lookups\n";
        fragmentShader += _fragmentTextureLookups;
    }
    fragmentShader += "\t\n";
    fragmentShader += _fragmentBody;
    fragmentShader += "}";

    _fragmentShader = fragmentShader;
}

/*
        Build a key for a texture specifier, taking all texture configuration
        options into account and ignoring the other stuff that might be there.

        FIXME: efficiency and stuff.
*/
namespace {

std::string KeyFromTextureParameters(const std::string& name, OOTextureFlags options, float anisotropy, float lodBias)
{
#ifndef NDEBUG
    options = OOApplyTextureOptionDefaults(options);
#endif

    // Extraction modes are ignored in synthesized shaders, since we use swizzling instead.
    options &= ~kOOTextureExtractChannelMask;

    return oo::str::format("%s:%X:%g:%g", name.c_str(), options, anisotropy, lodBias);
}

std::string KeyFromTextureSpec(const oo::PList& spec)
{
    std::string texName;
    OOTextureFlags texOptions;
    float anisotropy, lodBias;
    if (!cxx_OOInterpretTextureSpecifier(spec, &texName, &texOptions, &anisotropy, &lodBias, YES)) {
        // OOInterpretTextureSpecifier() will have logged something.
        OORaiseException(OOGenericException, "Invalid texture specifier");
    }

    return KeyFromTextureParameters(texName, texOptions, anisotropy, lodBias);
}

} // namespace

NSUInteger OODefaultShaderSynthesizer::assignIDForTexture(const oo::PList& textureSpec)
{
    OOCParameterAssert(!textureSpec.isNull());

    // extract_channel doesn't affect uniqueness, and we don't want OOTexture to do actual extraction.
    oo::PList spec = textureSpec;
    if (oo::PList::Dict* dict = spec.getIf<oo::PList::Dict>()) {
        dict->erase(cxx_kOOTextureSpecifierSwizzleKey);
    }

    std::string texName;
    OOTextureFlags texOptions;
    float anisotropy, lodBias;
    if (!cxx_OOInterpretTextureSpecifier(spec, &texName, &texOptions, &anisotropy, &lodBias, YES)) {
        // OOInterpretTextureSpecifier() will have logged something.
        OORaiseException(OOGenericException, "Invalid texture specifier");
    }

    if (texOptions & kOOTextureAllowCubeMap) {
        // cube_map = true; fail regardless of whether actual texture qualifies.
        OO_LOG_ERR("material.synthesis.error.cubeMap", "The material \"{}\" of \"{}\" specifies a cube map texture, but doesn't have custom shaders. Cube map textures are not supported with the default shaders.", materialKey().value_or("(null)"), entityName().value_or("(null)"));
        OORaiseException(OOGenericException, "Invalid material");
    }

    std::string key = KeyFromTextureParameters(texName, texOptions, anisotropy, lodBias);
    NSUInteger texID;
    if (_texturesByName.find(key) == _texturesByName.end()) {
        texID = _texturesByName.size();
        std::string texUniform = oo::str::format("uTexture%zu", texID);

#ifndef NDEBUG
        BOOL useInternalFormat = NO;
#else
        BOOL useInternalFormat = YES;
#endif

        _textures.push_back(cxx_OOMakeTextureSpecifier(texName, texOptions, anisotropy, lodBias, useInternalFormat));
        _texturesByName[key] = spec;
        _textureIDs[key] = texID;
        oo::PList uniform(oo::PList::Dict { { "type", oo::PList("texture") }, { "value", oo::PList::unsignedInteger(texID) } });
        _uniforms[texUniform] = uniform;

        addFragmentUniform(texUniform, "sampler2D");
    } else {
        // Upstream looks the ID up by texName, not by key, so it finds none and answers 0 (kept).
        auto found = _textureIDs.find(texName);
        texID = (found != _textureIDs.end()) ? found->second : 0;
    }

    return texID;
}

NSUInteger OODefaultShaderSynthesizer::textureIDForSpec(const oo::PList& textureSpec)
{
    auto found = _textureIDs.find(KeyFromTextureSpec(textureSpec));
    return (found != _textureIDs.end()) ? found->second : 0;
}

void OODefaultShaderSynthesizer::setUpOneTexture(const oo::PList& textureSpec)
{
    if (textureSpec.isNull())
        return;

    REQUIRE_STAGE(writeTextureCoordRead);

    NSUInteger texID = assignIDForTexture(textureSpec);
    if (_sampledTextures.insert(texID).second) {
        _fragmentTextureLookups += oo::str::format("\tvec4 tex%zuSample = texture2D(uTexture%zu, texCoords);  // %s\n", texID, texID, OptionalStringFor(textureSpec, cxx_kOOTextureSpecifierNameKey).value_or("(null)").c_str());
    }
}

void OODefaultShaderSynthesizer::getSampleName(std::string* outSampleName, std::string* outSwizzleOp, const oo::PList& textureSpec)
{
    OOCParameterAssert(outSampleName != NULL && outSwizzleOp != NULL && !textureSpec.isNull());

    setUpOneTexture(textureSpec);
    NSUInteger texID = textureIDForSpec(textureSpec);

    *outSampleName = oo::str::format("tex%zuSample", texID);
    *outSwizzleOp = GetExtractMode(textureSpec).value_or(std::string());
}

std::optional<std::string> OODefaultShaderSynthesizer::readRGBForTextureSpec(const oo::PList& textureSpec, const std::string& mapName)
{
    std::string sample, swizzle;
    getSampleName(&sample, &swizzle, textureSpec);

    if (swizzle.empty()) {
        return sample + ".rgb";
    }

    NSUInteger channelCount = swizzle.size();

    if (channelCount == 1) {
        return sample + "." + swizzle + swizzle + swizzle;
    } else if (channelCount == 3) {
        return sample + "." + swizzle;
    }

    OO_LOG_WARN("material.synthesis.warning.extractionMismatch", "The {} map for material \"{}\" of \"{}\" specifies {} channels to extract, but only {} may be used.", mapName, materialKey().value_or("(null)"), entityName().value_or("(null)"), channelCount, "1 or 3");
    return std::nullopt;
}

std::optional<std::string> OODefaultShaderSynthesizer::readOneChannelForTextureSpec(const oo::PList& textureSpec, const std::string& mapName)
{
    std::string sample, swizzle;
    getSampleName(&sample, &swizzle, textureSpec);

    if (swizzle.empty()) {
        return sample + ".r";
    }

    NSUInteger channelCount = swizzle.size();

    if (channelCount == 1) {
        return sample + "." + swizzle;
    }

    OO_LOG_WARN("material.synthesis.warning.extractionMismatch", "The {} map for material \"{}\" of \"{}\" specifies {} channels to extract, but only {} may be used.", mapName, materialKey().value_or("(null)"), entityName().value_or("(null)"), channelCount, "1");
    return std::nullopt;
}

#ifndef NDEBUG
void OODefaultShaderSynthesizer::performStage(const char* name, Stage stage)
{
    // Ensure that we aren’t recursing.
    if (_stagesInProgress.count(name) != 0) {
        OO_LOG_ERR("material.synthesis.error.recursion", "Shader synthesis recursion for stage {}.", name);
        OORaiseException(OOInternalInconsistencyException, "stage recursion");
    }

    _stagesInProgress.insert(name);

    (this->*stage)();

    _stagesInProgress.erase(name);
}
#endif

void OODefaultShaderSynthesizer::createTemporaries()
{
    _attributes.clear();
    _varyings.clear();
    _vertexUniforms.clear();
    _fragmentUniforms.clear();
    _vertexHelpers.clear();
    _fragmentHelpers.clear();
    _vertexBody.clear();
    _fragmentPreTextures.clear();
    _fragmentTextureLookups.clear();
    _fragmentBody.clear();

    _textures.clear();
    _texturesByName.clear();
    _textureIDs.clear();
    _sampledTextures.clear();

    _uniformBindingNames.clear();

#ifndef NDEBUG
    _stagesInProgress.clear();
#endif
}

void OODefaultShaderSynthesizer::destroyTemporaries()
{
    _attributes.clear();
    _varyings.clear();
    _vertexUniforms.clear();
    _fragmentUniforms.clear();
    _vertexHelpers.clear();
    _fragmentHelpers.clear();
    _vertexBody.clear();
    _fragmentPreTextures.clear();
    _fragmentTextureLookups.clear();
    _fragmentBody.clear();

    _texturesByName.clear();
    _textureIDs.clear();
    _sampledTextures.clear();

    _uniformBindingNames.clear();

#ifndef NDEBUG
    _stagesInProgress.clear();
#endif
}

// MARK: - Synthesis stages

// MARK: - Synthesis stages

void OODefaultShaderSynthesizer::writeTextureCoordRead()
{
    addVarying("vTexCoords", "vec2");
    _vertexBody += "\tvTexCoords = gl_MultiTexCoord0.st;\n\t\n";

    BOOL haveTexCoords = NO;
    oo::PList parallaxMap = cxx_OOMaterialParallaxMapSpecifier(_configuration);

    if (!parallaxMap.isNull()) {
        float parallaxScale = cxx_OOMaterialParallaxScale(_configuration);
        if (parallaxScale != 0.0f) {
            /*
                    We can’t call -getSampleName:... here because the standard
                    texture loading mechanism has to occur after determining
                    texture coordinates (duh).
            */
            std::string swizzle = GetExtractMode(parallaxMap).value_or("a");
            NSUInteger channelCount = swizzle.size();
            if (channelCount == 1) {
                haveTexCoords = YES;

                REQUIRE_STAGE(writeEyeVector);

                _fragmentPreTextures += "\t// Parallax mapping\n";

                NSUInteger texID = assignIDForTexture(parallaxMap);
                _fragmentPreTextures += oo::str::format("\tfloat parallax = texture2D(uTexture%zu, vTexCoords).%s;\n", texID, swizzle.c_str());

                if (parallaxScale != 1.0f) {
                    _fragmentPreTextures += oo::str::format("\tparallax *= %s;  // Parallax scale\n", FormatFloat(parallaxScale).c_str());
                }

                float parallaxBias = cxx_OOMaterialParallaxBias(_configuration);
                if (parallaxBias != 0.0) {
                    _fragmentPreTextures += oo::str::format("\tparallax += %s;  // Parallax bias\n", FormatFloat(parallaxBias).c_str());
                }

                _fragmentPreTextures += "\tvec2 texCoords = vTexCoords - parallax * eyeVector.xy * vec2(1.0, -1.0);\n";
            } else {
                OO_LOG_WARN("material.synthesis.warning.extractionMismatch", "The {} map for material \"{}\" of \"{}\" specifies {} channels to extract, but only {} may be used.", "parallax", materialKey().value_or("(null)"), entityName().value_or("(null)"), channelCount, "1");
            }
        }
    }

    if (!haveTexCoords) {
        _fragmentPreTextures += "\tvec2 texCoords = vTexCoords;\n";
    }
}

void OODefaultShaderSynthesizer::writeDiffuseColorTermIfNeeded()
{
    oo::PList diffuseMap = cxx_OOMaterialDiffuseMapSpecifier(_configuration, materialKey());
    oo::Ref<OOColor> diffuseColor(cxx_OOMaterialDiffuseColor(_configuration));
    if (diffuseColor == nullptr)
        diffuseColor = OOColor::whiteColor();

    if (diffuseColor->isBlack())
        return;
    _usesDiffuseTerm = YES;

    BOOL haveDiffuseColor = NO;
    if (!diffuseMap.isNull()) {
        std::optional<std::string> readInstr = readRGBForTextureSpec(diffuseMap, "diffuse");
        if (EXPECT_NOT(!readInstr.has_value())) {
            _fragmentBody += "\t// INVALID EXTRACTION KEY\n\t\n";
        } else {
            _fragmentBody += oo::str::format("\tvec3 diffuseColor = %s;\n", readInstr->c_str());
            haveDiffuseColor = YES;
        }
    }

    if (!haveDiffuseColor || !diffuseColor->isWhite()) {
        float rgba[4];
        diffuseColor->getRed(&rgba[0], &rgba[1], &rgba[2], &rgba[3]);
        if (haveDiffuseColor) {
            _fragmentBody += oo::str::format("\tdiffuseColor *= vec3(%s, %s, %s);\n", FormatFloat(rgba[0]).c_str(), FormatFloat(rgba[1]).c_str(), FormatFloat(rgba[2]).c_str());
        } else {
            _fragmentBody += oo::str::format("\tconst vec3 diffuseColor = vec3(%s, %s, %s);\n", FormatFloat(rgba[0]).c_str(), FormatFloat(rgba[1]).c_str(), FormatFloat(rgba[2]).c_str());
            haveDiffuseColor = YES;
        }
    }

    (void)haveDiffuseColor;
    _fragmentBody += "\t\n";
}

void OODefaultShaderSynthesizer::writeDiffuseColorTerm()
{
    REQUIRE_STAGE(writeDiffuseColorTermIfNeeded);

    if (!_usesDiffuseTerm) {
        _fragmentBody += "\tconst vec3 diffuseColor = vec3(0.0);  // Diffuse colour is black.\n\t\n";
    }
}

void OODefaultShaderSynthesizer::writeDiffuseLighting()
{
    REQUIRE_STAGE(writeDiffuseColorTermIfNeeded);
    if (!_usesDiffuseTerm)
        return;

    REQUIRE_STAGE(writeTotalColor);
    REQUIRE_STAGE(writeVertexPosition);
    REQUIRE_STAGE(writeNormalIfNeeded);
    REQUIRE_STAGE(writeLightVector);

    // FIXME: currently uncoloured diffuse and ambient lighting.
    const char* normalDotLight = _constZNormal ? "lightVector.z" : "dot(normal, lightVector)";

    _fragmentBody += oo::str::format(
        "\t// Diffuse (Lambertian) and ambient lighting\n"
        "\tvec3 diffuseLight = (gl_LightSource[1].diffuse * max(0.0, %s) + gl_LightModel.ambient).rgb;\n\t\n",
        normalDotLight);

    _haveDiffuseLight = YES;
}

void OODefaultShaderSynthesizer::writeLightVector()
{
    REQUIRE_STAGE(writeVertexPosition);
    REQUIRE_STAGE(writeNormalIfNeeded);

    addVarying("vLightVector", "vec3");

    _vertexBody += "\tvec3 lightVector = gl_LightSource[1].position.xyz;\n"
                   "\tvLightVector = lightVector * TBN;\n\t\n";
    _fragmentBody += "\tvec3 lightVector = normalize(vLightVector);\n\t\n";
}

void OODefaultShaderSynthesizer::writeEyeVector()
{
    REQUIRE_STAGE(writeVertexPosition);
    REQUIRE_STAGE(writeVertexTangentBasis);

    addVarying("vEyeVector", "vec3");

    _vertexBody += "\tvEyeVector = position.xyz * TBN;\n\t\n";
    _fragmentPreTextures += "\tvec3 eyeVector = normalize(vEyeVector);\n\t\n";
}

void OODefaultShaderSynthesizer::writeVertexTangentBasis()
{
    addAttribute("tangent", "vec3");

    _vertexBody += "\t// Build tangent space basis\n"
                   "\tvec3 n = gl_NormalMatrix * gl_Normal;\n"
                   "\tvec3 t = gl_NormalMatrix * tangent;\n"
                   "\tvec3 b = cross(n, t);\n"
                   "\tmat3 TBN = mat3(t, b, n);\n\t\n";
}

void OODefaultShaderSynthesizer::writeNormalIfNeeded()
{
    REQUIRE_STAGE(writeVertexPosition);
    REQUIRE_STAGE(writeVertexTangentBasis);

    oo::PList normalMap = cxx_OOMaterialNormalMapSpecifier(_configuration);
    if (normalMap.isNull()) {
        // FIXME: this stuff should be handled in OOMaterialSpecifier.m when synthesizer takes over the world. -- Ahruman 2012-02-08
        normalMap = cxx_OOMaterialNormalAndParallaxMapSpecifier(_configuration);
    }
    if (!normalMap.isNull()) {
        std::string sample, swizzle;
        getSampleName(&sample, &swizzle, normalMap);
        if (swizzle.empty())
            swizzle = "rgb";
        if (swizzle.size() == 3) {
            _fragmentBody += oo::str::format("\tvec3 normal = normalize(%s.%s - 0.5);\n\t\n", sample.c_str(), swizzle.c_str());
            _usesNormalMap = YES;
            return;
        } else {
            OO_LOG_WARN("material.synthesis.warning.extractionMismatch", "The {} map for material \"{}\" of \"{}\" specifies {} channels to extract, but only {} may be used.", "normal", materialKey().value_or("(null)"), entityName().value_or("(null)"), swizzle.size(), "3");
        }
    }
    _constZNormal = YES;
}

void OODefaultShaderSynthesizer::writeNormal()
{
    REQUIRE_STAGE(writeNormalIfNeeded);

    if (_constZNormal) {
        _fragmentBody += "\tconst vec3 normal = vec3(0.0, 0.0, 1.0);\n\t\n";
    }
}

void OODefaultShaderSynthesizer::writeSpecularLighting()
{
    float specularExponent = cxx_OOMaterialSpecularExponent(_configuration);
    if (specularExponent <= 0)
        return;

    oo::PList specularColorMap = cxx_OOMaterialSpecularColorMapSpecifier(_configuration);
    oo::PList specularExponentMap = cxx_OOMaterialSpecularExponentMapSpecifier(_configuration);
    float scaleFactor = 1.0f;

    if (!specularColorMap.isNull()) {
        scaleFactor = specularColorMap.get<double>(cxx_kOOTextureSpecifierScaleFactorKey, 1.0f);
    }

    oo::Ref<OOColor> specularColor; // never null: both functions below answer a default colour
    if (specularColorMap.isNull()) {
        specularColor = oo::Ref<OOColor>(cxx_OOMaterialSpecularColor(_configuration));
    } else {
        specularColor = oo::Ref<OOColor>(cxx_OOMaterialSpecularModulateColor(_configuration));
    }

    if (specularColor->isBlack())
        return;

    BOOL modulateWithDiffuse = specularColorMap.get<bool>(cxx_kOOTextureSpecifierSelfColorKey);

    REQUIRE_STAGE(writeTotalColor);
    REQUIRE_STAGE(writeNormalIfNeeded);
    REQUIRE_STAGE(writeEyeVector);
    REQUIRE_STAGE(writeLightVector);
    if (modulateWithDiffuse) {
        REQUIRE_STAGE(writeDiffuseColorTerm);
    }

    _fragmentBody += "\t// Specular (Blinn-Phong) lighting\n";

    BOOL haveSpecularColor = NO;
    if (!specularColorMap.isNull()) {
        std::optional<std::string> readInstr = readRGBForTextureSpec(specularColorMap, "specular colour");
        if (EXPECT_NOT(!readInstr.has_value())) {
            _fragmentBody += "\t// INVALID EXTRACTION KEY\n\t\n";
            return;
        }

        _fragmentBody += oo::str::format("\tvec3 specularColor = %s;\n", readInstr->c_str());
        haveSpecularColor = YES;
    }

    if (!haveSpecularColor || !specularColor->isWhite()) {
        float rgba[4];
        specularColor->getRed(&rgba[0], &rgba[1], &rgba[2], &rgba[3]);

        const char* comment = (scaleFactor == 1.0f) ? "Constant colour" : "Constant colour and scale factor";

        // Handle scale factor, colour, and colour alpha scaling as one multiply.
        scaleFactor *= rgba[3];
        rgba[0] *= scaleFactor;
        rgba[1] *= scaleFactor;
        rgba[2] *= scaleFactor;

        // Avoid reapplying scaleFactor below.
        scaleFactor = 1.0;

        if (haveSpecularColor) {
            _fragmentBody += oo::str::format("\tspecularColor *= vec3(%s, %s, %s);  // %s\n", FormatFloat(rgba[0]).c_str(), FormatFloat(rgba[1]).c_str(), FormatFloat(rgba[2]).c_str(), comment);
        } else {
            _fragmentBody += oo::str::format("\tvec3 specularColor = vec3(%s, %s, %s);  // %s\n", FormatFloat(rgba[0]).c_str(), FormatFloat(rgba[1]).c_str(), FormatFloat(rgba[2]).c_str(), comment);
            haveSpecularColor = YES;
        }
    }

    // Handle scale_factor if no constant colour.
    if (haveSpecularColor && scaleFactor != 1.0f) {
        _fragmentBody += oo::str::format("\tspecularColor *= %s;  // Scale factor\n", FormatFloat(scaleFactor).c_str());
    }

    // Handle self_color.
    if (modulateWithDiffuse) {
        _fragmentBody += "\tspecularColor *= diffuseColor;  // Self-colouring\n";
    }

    // Specular exponent.
    BOOL haveSpecularExponent = NO;
    if (!specularExponentMap.isNull()) {
        std::optional<std::string> readInstr = readOneChannelForTextureSpec(specularExponentMap, "specular exponent");
        if (EXPECT_NOT(!readInstr.has_value())) {
            _fragmentBody += "\t// INVALID EXTRACTION KEY\n\t\n";
            return;
        }

        _fragmentBody += oo::str::format("\tfloat specularExponent = %s * %.1f;\n", readInstr->c_str(), specularExponent);
        haveSpecularExponent = YES;
    }
    if (!haveSpecularExponent) {
        _fragmentBody += oo::str::format("\tconst float specularExponent = %.1f;\n", specularExponent);
    }

    if (_usesNormalMap) {
        _fragmentBody += "\tvec3 reflection = reflect(lightVector, normal);\n";
    } else {
        /*	reflect(I, N) is defined as I - 2 * dot(N, I) * N
                If N is (0,0,1), this becomes (I.x,I.y,-I.z).
        */
        _fragmentBody += "\tvec3 reflection = vec3(lightVector.x, lightVector.y, -lightVector.z);  // Equivalent to reflect(lightVector, normal) since normal is known to be (0, 0, 1) in tangent space.\n";
    }

    _fragmentBody += "\tfloat specIntensity = dot(reflection, eyeVector);\n"
                     "\tspecIntensity = pow(max(0.0, specIntensity), specularExponent);\n"
                     "\ttotalColor += specIntensity * specularColor * gl_LightSource[1].specular.rgb;\n\t\n";
}

void OODefaultShaderSynthesizer::writeLightMaps()
{
    const oo::PList* lightMaps = _configuration.get<oo::PList::Array>(cxx_kOOMaterialLightMapsName);
    NSUInteger idx, count = (lightMaps != nullptr) ? lightMaps->count() : 0;
    if (count == 0)
        return;

    REQUIRE_STAGE(writeTotalColor);

    // Check if we need the diffuse colour term.
    for (idx = 0; idx < count; idx++) {
        const oo::PList* lightMapSpec = lightMaps->at<oo::PList::Dict>(idx);
        if (lightMapSpec != nullptr && lightMapSpec->get<bool>(cxx_kOOTextureSpecifierIlluminationModeKey)) {
            REQUIRE_STAGE(writeDiffuseColorTerm);
            REQUIRE_STAGE(writeDiffuseLighting);
            break;
        }
    }

    _fragmentBody += "\tvec3 lightMapColor;\n";

    const oo::PList notADictionary; // a light map entry that is not a dictionary reads as nil
    for (idx = 0; idx < count; idx++) {
        const oo::PList* entry = lightMaps->at<oo::PList::Dict>(idx);
        const oo::PList& lightMapSpec = (entry != nullptr) ? *entry : notADictionary;
        oo::PList textureSpec = cxx_OOTextureSpecFromObject(lightMapSpec, std::nullopt);
        const oo::PList* color = lightMapSpec.get<oo::PList::Array>(cxx_kOOTextureSpecifierModulateColorKey);
        float rgba[4] = { 1.0f, 1.0f, 1.0f, 1.0f };
        BOOL isIllumination = lightMapSpec.get<bool>(cxx_kOOTextureSpecifierIlluminationModeKey);

        if (EXPECT_NOT(color == nullptr && textureSpec.isNull())) {
            _fragmentBody += "\t// Light map with neither colour nor texture has no effect.\n\t\n";
            continue;
        }

        if (color != nullptr) {
            NSUInteger idx, count = color->count();
            if (count > 4)
                count = 4;
            for (idx = 0; idx < count; idx++) {
                rgba[idx] = color->at<double>(idx);
            }
            rgba[0] *= rgba[3];
            rgba[1] *= rgba[3];
            rgba[2] *= rgba[3];
        }

        if (EXPECT_NOT((rgba[0] == 0.0f && rgba[1] == 0.0f && rgba[2] == 0.0f) || (!_usesDiffuseTerm && isIllumination))) {
            _fragmentBody += "\t// Light map tinted black has no effect.\n\t\n";
            continue;
        }

        if (!textureSpec.isNull()) {
            std::optional<std::string> readInstr = readRGBForTextureSpec(textureSpec, "light");
            if (EXPECT_NOT(!readInstr.has_value())) {
                _fragmentBody += "\t// INVALID EXTRACTION KEY\n\n";
                continue;
            }

            _fragmentBody += oo::str::format("\tlightMapColor = %s;\n", readInstr->c_str());

            if (rgba[0] != 1.0f || rgba[1] != 1.0f || rgba[2] != 1.0f) {
                _fragmentBody += oo::str::format("\tlightMapColor *= vec3(%s, %s, %s);\n", FormatFloat(rgba[0]).c_str(), FormatFloat(rgba[1]).c_str(), FormatFloat(rgba[2]).c_str());
            }
        } else {
            _fragmentBody += oo::str::format("\tlightMapColor = vec3(%s, %s, %s);\n", FormatFloat(rgba[0]).c_str(), FormatFloat(rgba[1]).c_str(), FormatFloat(rgba[2]).c_str());
        }

        const oo::PList* binding = textureSpec.get<oo::PList::Dict>(cxx_kOOTextureSpecifierBindingKey);
        if (binding != nullptr) {
            std::string bindingName = binding->get<std::string>("binding");
            oo::PList bindingTypes = ResourceManager::shaderBindingTypesDictionary();
            const oo::PList* typeDict = bindingTypes.get<oo::PList::Dict>("player"); // FIXME: select appropriate binding subset.
            std::optional<std::string> bindingType = (typeDict != nullptr) ? OptionalStringFor(*typeDict, bindingName.c_str()) : std::nullopt;
            const char* glslType = nullptr;
            const char* swizzle = "";

            if (bindingType == "float") {
                glslType = "float";
            } else if (bindingType == "vector") {
                glslType = "vec3";
            } else if (bindingType == "color") {
                glslType = "vec4";
                swizzle = ".rgb";
            }

            if (glslType != nullptr) {
                std::optional<std::string> uniformName = defineBindingUniform(*binding, bindingType.value_or(std::string()));
                _fragmentBody += oo::str::format("\tlightMapColor *= %s%s;\n", uniformName.value_or(std::string()).c_str(), swizzle);
            } else {
                if (!bindingType.has_value()) {
                    OO_LOG_ERR("material.binding.error.unknown", "Cannot bind light map to unknown attribute \"{}\".", bindingName);
                } else {
                    OO_LOG_ERR("material.binding.error.badType", "Cannot bind light map to attribute \"{}\" of type {}.", bindingName, *bindingType);
                }
                _fragmentBody += "\tlightMapColor = vec3(0.0);  // Bad binding, see log.\n";
            }
        }

        if (!isIllumination) {
            _fragmentBody += "\ttotalColor += lightMapColor;\n\t\n";
        } else {
            _fragmentBody += "\tdiffuseLight += lightMapColor;\n\t\n";
        }
    }
}

void OODefaultShaderSynthesizer::writeVertexPosition()
{
    _vertexBody += "\tvec4 position = gl_ModelViewMatrix * gl_Vertex;\n"
                   "\tgl_Position = gl_ProjectionMatrix * position;\n\t\n";
}

void OODefaultShaderSynthesizer::writeTotalColor()
{
    _fragmentPreTextures += "\tvec3 totalColor = vec3(0.0);\n\t\n";
}

void OODefaultShaderSynthesizer::writeFinalColorComposite()
{
    REQUIRE_STAGE(writeTotalColor); // Needed even if none of the following stages does anything.
    REQUIRE_STAGE(writeDiffuseLighting);
    REQUIRE_STAGE(writeSpecularLighting);
    REQUIRE_STAGE(writeLightMaps);

    if (_haveDiffuseLight) {
        _fragmentBody += "\ttotalColor += diffuseColor * diffuseLight;\n";
    }

    _fragmentBody += "\tgl_FragColor = vec4(totalColor, 1.0);\n\t\n";
}

namespace {

// A texture specifier naming just a file: a dictionary with the one key kOOTextureSpecifierNameKey.
oo::PList NameSpecifier(const std::string& name)
{
    return oo::PList(oo::PList::Dict { { cxx_kOOTextureSpecifierNameKey, oo::PList(name) } });
}

// A string becomes a name specifier, a dictionary is kept, anything else (or no value) is nil.
oo::PList StringOrDictionarySpecifier(const oo::PList* texSpec)
{
    if (texSpec == nullptr)
        return oo::PList();
    if (const std::string* name = texSpec->getIf<std::string>())
        return NameSpecifier(*name);
    if (texSpec->isDict())
        return *texSpec;
    return oo::PList();
}

// PList dict with one added entry on a dictionary specifier.
oo::PList AddingValue(oo::PList specifier, const char* key, oo::PList value)
{
    if (oo::PList::Dict* dict = specifier.getIf<oo::PList::Dict>())
        (*dict)[key] = std::move(value);
    return specifier;
}

// OOColor::colorWithDescription() of the value for key (null if there is none).
oo::Ref<OOColor> ColorIn(const oo::PList& spec, const char* key)
{
    const oo::PList* value = spec.find(key);
    return OOColor::colorWithDescription((value != nullptr) ? *value : oo::PList());
}

// OOColor::normalizedArray(): four +numberWithFloat: components. (The callers never pass null.)
oo::PList NormalizedArray(OOColor* color)
{
    oo::PList::Array result;
    for (float component : color->normalizedArray())
        result.push_back(oo::PList::singleReal(component));
    return oo::PList(std::move(result));
}

/*
        Convert any legacy properties and simplified forms in a material specifier
        to the standard form.

        FIXME: this should be done up front in OOShipRegistry. When doing that, it
        also need to be done when materials are set on the fly through JS,
*/
oo::PList CanonicalizeMaterialSpecifier(const oo::PList& spec, const std::optional<std::string>& materialKey)
{
    oo::PList::Dict result;
    oo::Ref<OOColor> col;
    oo::PList texSpec;

    // Colours.
    col = ColorIn(spec, cxx_kOOMaterialDiffuseColorName);
    if (col == nullptr)
        col = ColorIn(spec, cxx_kOOMaterialDiffuseColorLegacyName);
    if (col != nullptr)
        result[cxx_kOOMaterialDiffuseColorName] = NormalizedArray(col.get());

    col = ColorIn(spec, cxx_kOOMaterialAmbientColorName);
    if (col == nullptr)
        col = ColorIn(spec, cxx_kOOMaterialAmbientColorLegacyName);
    if (col != nullptr)
        result[cxx_kOOMaterialAmbientColorName] = NormalizedArray(col.get());

    col = ColorIn(spec, cxx_kOOMaterialSpecularColorName);
    if (col == nullptr)
        col = ColorIn(spec, cxx_kOOMaterialSpecularColorLegacyName);
    if (col != nullptr)
        result[cxx_kOOMaterialSpecularColorName] = NormalizedArray(col.get());

    col = ColorIn(spec, cxx_kOOMaterialSpecularModulateColorName);
    if (col != nullptr)
        result[cxx_kOOMaterialSpecularModulateColorName] = NormalizedArray(col.get());

    col = ColorIn(spec, cxx_kOOMaterialEmissionColorName);
    if (col == nullptr)
        col = ColorIn(spec, cxx_kOOMaterialEmissionColorLegacyName);
    if (col != nullptr)
        result[cxx_kOOMaterialEmissionColorName] = NormalizedArray(col.get());

    // Diffuse map.
    const oo::PList* diffuseSpec = spec.find(cxx_kOOMaterialDiffuseMapName);
    if (diffuseSpec != nullptr && diffuseSpec->isString()) {
        const std::string& name = *diffuseSpec->getIf<std::string>();
        texSpec = name.empty() ? *diffuseSpec : NameSpecifier(name);
    } else if (diffuseSpec != nullptr && diffuseSpec->isDict()) {
        /*	Special case for diffuse map: no name is changed to
                name = materialKey, while name = "" is changed to no name.
        */
        texSpec = *diffuseSpec;
        const oo::PList* name = diffuseSpec->find(cxx_kOOTextureSpecifierNameKey);
        if (name == nullptr) {
            if (materialKey.has_value())
                texSpec = AddingValue(texSpec, cxx_kOOTextureSpecifierNameKey, oo::PList(*materialKey));
        } else if (name->isString() && name->getIf<std::string>()->empty()) {
            texSpec.getIf<oo::PList::Dict>()->erase(cxx_kOOTextureSpecifierNameKey);
        }
    } else {
        // Special case for unspecified diffuse map. (The one caller always has a material key.)
        texSpec = NameSpecifier(materialKey.value_or(std::string()));
    }
    result[cxx_kOOMaterialDiffuseMapName] = texSpec;

    // Specular maps.
    {
        BOOL haveNewSpecular = NO;
        texSpec = StringOrDictionarySpecifier(spec.find(cxx_kOOMaterialSpecularColorMapName));
        if (!texSpec.isNull()) {
            haveNewSpecular = YES;
            result[cxx_kOOMaterialSpecularColorMapName] = texSpec;
        }

        texSpec = StringOrDictionarySpecifier(spec.find(cxx_kOOMaterialSpecularExponentMapName));
        if (!texSpec.isNull()) {
            haveNewSpecular = YES;
            result[cxx_kOOMaterialSpecularExponentMapName] = texSpec;
        }

        if (!haveNewSpecular) {
            // Fall back to legacy combined specular map if defined.
            texSpec = StringOrDictionarySpecifier(spec.find(cxx_kOOMaterialCombinedSpecularMapName));
            if (!texSpec.isNull()) {
                result[cxx_kOOMaterialSpecularColorMapName] = texSpec;
                texSpec = AddingValue(texSpec, cxx_kOOTextureSpecifierSwizzleKey, oo::PList("a"));
                result[cxx_kOOMaterialSpecularExponentMapName] = texSpec;
            }
        }
    }

    // Normal and parallax maps.
    {
        BOOL haveParallax = NO;
        BOOL haveNewNormal = NO;
        texSpec = StringOrDictionarySpecifier(spec.find(cxx_kOOMaterialNormalMapName));
        if (!texSpec.isNull()) {
            haveNewNormal = YES;
            result[cxx_kOOMaterialNormalMapName] = texSpec;
        }

        texSpec = StringOrDictionarySpecifier(spec.find(cxx_kOOMaterialParallaxMapName));
        if (!texSpec.isNull()) {
            haveNewNormal = YES;
            haveParallax = YES;
            result[cxx_kOOMaterialParallaxMapName] = texSpec;
        }

        if (!haveNewNormal) {
            // Fall back to legacy combined normal and parallax map if defined.
            texSpec = StringOrDictionarySpecifier(spec.find(cxx_kOOMaterialNormalAndParallaxMapName));
            if (!texSpec.isNull()) {
                haveParallax = YES;
                result[cxx_kOOMaterialNormalMapName] = texSpec;
                texSpec = AddingValue(texSpec, cxx_kOOTextureSpecifierSwizzleKey, oo::PList("a"));
                result[cxx_kOOMaterialParallaxMapName] = texSpec;
            }
        }

        // Additional parallax parameters (-oo_setFloat:forKey: stores a double).
        if (haveParallax) {
            float parallaxScale = spec.get<float>(cxx_kOOMaterialParallaxScaleName, kOOMaterialDefaultParallaxScale);
            result[cxx_kOOMaterialParallaxScaleName] = oo::PList(static_cast<double>(parallaxScale));

            float parallaxBias = spec.get<float>(cxx_kOOMaterialParallaxBiasName);
            result[cxx_kOOMaterialParallaxBiasName] = oo::PList(static_cast<double>(parallaxBias));
        }
    }

    // Light maps.
    {
        oo::PList::Array lightMaps;
        oo::PList::Array lightMapSpecs;
        if (const oo::PList* value = spec.find(cxx_kOOMaterialLightMapsName)) {
            if (const oo::PList::Array* array = value->getIf<oo::PList::Array>())
                lightMapSpecs = *array;
            else
                lightMapSpecs.push_back(*value);
        }

        for (const oo::PList& entry : lightMapSpecs) {
            oo::PList lmSpec;
            if (const std::string* name = entry.getIf<std::string>()) {
                lmSpec = NameSpecifier(*name);
            } else if (entry.isDict()) {
                lmSpec = entry;
            } else {
                continue;
            }
            oo::PList::Dict& lmDict = *lmSpec.getIf<oo::PList::Dict>();

            auto modulateColor = lmDict.find(cxx_kOOTextureSpecifierModulateColorKey);
            if (modulateColor != lmDict.end() && !modulateColor->second.isArray()) {
                // Don't convert arrays here, because we specifically don't want the behaviour of treating numbers greater than 1 as 0..255 components.
                col = OOColor::colorWithDescription(modulateColor->second);
                // A description that is no colour leaves no colour (upstream set nil, which Foundation refuses).
                if (col != nullptr)
                    modulateColor->second = NormalizedArray(col.get());
                else
                    lmDict.erase(modulateColor);
            }

            auto binding = lmDict.find(cxx_kOOTextureSpecifierBindingKey);
            if (binding != lmDict.end()) {
                if (const std::string* bindingName = binding->second.getIf<std::string>()) {
                    oo::PList expandedBinding(oo::PList::Dict { { "type", oo::PList("binding") }, { "binding", oo::PList(*bindingName) } });
                    binding->second = std::move(expandedBinding);
                } else if (!binding->second.isDict() || binding->second.get<std::string>("binding").empty()) {
                    lmDict.erase(binding);
                }
            }

            lightMaps.push_back(std::move(lmSpec));
        }

        if (lightMaps.empty()) {
            // If light_map isn't use, handle legacy emission_map, illumination_map and emission_and_illumination_map.
            const oo::PList* emissionValue = spec.find(cxx_kOOMaterialEmissionMapName);
            const oo::PList* illuminationValue = spec.find(cxx_kOOMaterialIlluminationMapName);
            oo::PList emissionSpec = (emissionValue != nullptr) ? *emissionValue : oo::PList();
            oo::PList illuminationSpec = (illuminationValue != nullptr) ? *illuminationValue : oo::PList();

            if (emissionSpec.isNull() && illuminationSpec.isNull()) {
                // Redundantish string check required because we want to modify this as a dictionary to make illuminationSpec.
                emissionSpec = StringOrDictionarySpecifier(spec.find(cxx_kOOMaterialEmissionAndIlluminationMapName));

                if (!emissionSpec.isNull()) {
                    illuminationSpec = AddingValue(emissionSpec, cxx_kOOTextureSpecifierSwizzleKey, oo::PList("a"));
                }
            }

            if (!emissionSpec.isNull()) {
                if (const std::string* name = emissionSpec.getIf<std::string>()) {
                    emissionSpec = NameSpecifier(*name);
                }
                if (emissionSpec.isDict()) {
                    col = ColorIn(spec, cxx_kOOMaterialEmissionModulateColorName);
                    if (col != nullptr)
                        emissionSpec = AddingValue(emissionSpec, cxx_kOOTextureSpecifierModulateColorKey, NormalizedArray(col.get()));

                    lightMaps.push_back(emissionSpec);
                }
            }

            if (!illuminationSpec.isNull()) {
                if (const std::string* name = illuminationSpec.getIf<std::string>()) {
                    illuminationSpec = NameSpecifier(*name);
                }
                if (illuminationSpec.isDict()) {
                    col = ColorIn(spec, cxx_kOOMaterialIlluminationModulateColorName);
                    if (col != nullptr)
                        illuminationSpec = AddingValue(illuminationSpec, cxx_kOOTextureSpecifierModulateColorKey, NormalizedArray(col.get()));

                    illuminationSpec = AddingValue(illuminationSpec, cxx_kOOTextureSpecifierIlluminationModeKey, oo::PList(true));

                    lightMaps.push_back(illuminationSpec);
                }
            }
        }

        result[cxx_kOOMaterialLightMapsName] = oo::PList(std::move(lightMaps));
    }

    oo::PList canonical(std::move(result));
    OO_LOG("material.canonicalForm", "Canonicalized material {}:\nORIGINAL:\n{}\n\n@CANONICAL:\n{}", materialKey.value_or("(null)"), oo::DescriptionOf(spec), oo::DescriptionOf(canonical));

    return canonical;
}

std::string FormatFloat(double value)
{
    long long intValue = value;
    if (value == intValue) {
        return oo::str::format("%lli.0", intValue);
    } else {
        return oo::str::format("%g", value);
    }
}

} // namespace
