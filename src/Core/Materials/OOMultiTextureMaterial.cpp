/*

OOMultiTextureMaterial.m


Copyright (C) 2010-2013 Jens Ayton

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

#include "OOMultiTextureMaterial.h"
#include "OOCombinedEmissionMapGenerator.h"
#include "OOMacroOpenGL.h"
#include "OOMaterialSpecifier.h"
#include "OOOpenGLExtensionManager.h"
#include "OOTexture.h"
#include "oofnd/objc/OOAssert.h"

#if OO_MULTITEXTURE

oo::Ref<OOMultiTextureMaterial> OOMultiTextureMaterial::materialWithName(const std::optional<std::string>& name, const oo::PList& configuration)
{
    oo::Ref<OOMultiTextureMaterial> result = oo::makeRef<OOMultiTextureMaterial>();
    if (!result->initWithName(name, configuration))
        return nullptr;
    return result;
}

bool OOMultiTextureMaterial::initWithName(const std::optional<std::string>& name, const oo::PList& configuration)
{
    if (!OOOpenGLExtensionManager::sharedManager()->textureCombinersSupported()) {
        return false; // [self release]; return nil: the factory drops the object
    }

    // The configuration mixes plist data with live objects (colours): an oo::PList carries both
    // exactly (proposed ADR-0043 Amendment 2).
    const oo::PList& config = configuration;
    const oo::PList diffuseSpec = cxx_OOMaterialDiffuseMapSpecifier(config, name);
    const oo::PList emissionSpec = cxx_OOMaterialEmissionMapSpecifier(config);
    const oo::PList illuminationSpec = cxx_OOMaterialIlluminationMapSpecifier(config);
    const oo::PList emissionAndIlluminationSpec = cxx_OOMaterialEmissionAndIlluminationMapSpecifier(config);
    oo::Ref<OOColor> diffuseColor = cxx_OOMaterialDiffuseColor(config);
    oo::Ref<OOColor> emissionColor;
    oo::Ref<OOColor> illuminationColor = cxx_OOMaterialIlluminationModulateColor(config);

    // A copy of the configuration (an empty one for nil, as +dictionaryWithDictionary: gave).
    oo::PList mutableConfiguration = config.isDict() ? config : oo::PList(oo::PList::Dict { });

    if (!emissionSpec.isNull() || !emissionAndIlluminationSpec.isNull()) {
        emissionColor = cxx_OOMaterialEmissionModulateColor(config);

        /*	If an emission map and an emission colour are both specified, stop
                the superclass (OOBasicMaterial) from applying the emission colour.
        */
        mutableConfiguration.getIf<oo::PList::Dict>()->erase(cxx_kOOMaterialEmissionColorName);
        mutableConfiguration.getIf<oo::PList::Dict>()->erase(cxx_kOOMaterialEmissionColorLegacyName);
    }

    OOBasicMaterial::initWithName(name, mutableConfiguration);
    { // was if (self != nil): the superclass's initialiser cannot fail
        if (!diffuseSpec.isNull()) {
            _diffuseMap = oo::Ref<OOTexture>(OOTexture::textureWithConfiguration(diffuseSpec));
            if (_diffuseMap.get() != nil)
                _unitsUsed++;
        }

        // Check for simplest cases, where we don't need to bake a derived emission map.
        if (!emissionSpec.isNull() && illuminationSpec.isNull() && emissionAndIlluminationSpec.isNull() && emissionColor == nil) {
            _emissionMap = oo::Ref<OOTexture>(OOTexture::textureWithConfiguration(emissionSpec, kOOTextureExtraShrink));
            if (_emissionMap.get() != nil)
                _unitsUsed++;
        } else {
            oo::Ref<OOCombinedEmissionMapGenerator> generator;

            if (!emissionAndIlluminationSpec.isNull()) {
                generator = OOCombinedEmissionMapGenerator::generatorWithEmissionAndIlluminationMapSpec(emissionAndIlluminationSpec,
                    _diffuseMap.get(),
                    diffuseColor.get(),
                    emissionColor.get(),
                    illuminationColor.get(),
                    emissionAndIlluminationSpec);
            } else {
                const oo::PList optionsSpec = !emissionSpec.isNull() ? emissionSpec : illuminationSpec;
                generator = OOCombinedEmissionMapGenerator::generatorWithEmissionMapSpec(emissionSpec,
                    emissionColor.get(),
                    _diffuseMap.get(),
                    diffuseColor.get(),
                    illuminationSpec,
                    illuminationColor.get(),
                    optionsSpec);
            }

            _emissionMap = oo::Ref<OOTexture>(OOTexture::textureWithGenerator(generator.get()));
            if (_emissionMap.get() != nil)
                _unitsUsed++;
        }
    }

    return true;
}

// -dealloc's [self willDealloc] is the root facade's (proposed ADR-0056, amendment oo-smy item 3),
// and the maps are released with their oo::ObjCRefs.

std::optional<std::string> OOMultiTextureMaterial::descriptionComponents() const
{
    std::vector<std::string> bits;
    if (_diffuseMap.get())
        bits.push_back("diffuse map: " + _diffuseMap->shortDescription());
    if (_emissionMap.get())
        bits.push_back("emission map: " + _emissionMap->shortDescription());

    std::optional<std::string> result = OOBasicMaterial::descriptionComponents();
    if (!bits.empty()) {
        std::string joined;
        for (const std::string& bit : bits)
            joined += (joined.empty() ? "" : ",") + bit;
        result = result.value_or("") + " - " + joined; // StdString(nil) was ""
    }
    return result;
}

NSUInteger OOMultiTextureMaterial::textureUnitCount()
{
    return _unitsUsed;
}

NSUInteger OOMultiTextureMaterial::countOfTextureUnitsWithBaseCoordinates()
{
    return _unitsUsed;
}

void OOMultiTextureMaterial::ensureFinishedLoading()
{
    if (_diffuseMap != nullptr)
        _diffuseMap->ensureFinishedLoading();
    if (_emissionMap != nullptr)
        _emissionMap->ensureFinishedLoading();
}

void OOMultiTextureMaterial::apply()
{
    OO_ENTER_OPENGL();

    OOBasicMaterial::apply();

    GLenum textureUnit = GL_TEXTURE0_ARB;

    if (_diffuseMap.get() != nil) {
        OOGL(glActiveTextureARB(textureUnit++));
        OOGL(glTexEnvi(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_COMBINE_ARB));
        OOGL(glTexEnvi(GL_TEXTURE_ENV, GL_COMBINE_RGB_ARB, GL_MODULATE));
        if (_diffuseMap != nullptr)
            _diffuseMap->apply();
    }

    if (_emissionMap.get() != nil) {
        OOGL(glActiveTextureARB(textureUnit++));
        OOGL(glTexEnvi(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_COMBINE_ARB));
        OOGL(glTexEnvi(GL_TEXTURE_ENV, GL_COMBINE_RGB_ARB, GL_ADD));
        if (_emissionMap != nullptr)
            _emissionMap->apply();
    }

    OOCAssert(textureUnit - GL_TEXTURE0_ARB == _unitsUsed, "OOMultiTextureMaterial texture unit count invalid (expected %zu, actually using %u)", _unitsUsed, textureUnit - GL_TEXTURE0_ARB);

    if (textureUnit > GL_TEXTURE1_ARB) {
        OOGL(glActiveTextureARB(GL_TEXTURE0_ARB));
    }
}

void OOMultiTextureMaterial::unapplyWithNext(OOMaterial* next)
{
    OO_ENTER_OPENGL();

    OOBasicMaterial::unapplyWithNext(next);

    // -isKindOfClass: (nil is not one)
    NSUInteger i;
    OOMultiTextureMaterial* nextMulti = dynamic_cast<OOMultiTextureMaterial*>(next);
    i = (nextMulti != nullptr) ? nextMulti->textureUnitCount() : 0;
    for (; i != _unitsUsed; ++i) {
        OOGL(glActiveTextureARB(GL_TEXTURE0_ARB + i));
        OOTexture::applyNone();
        OOGL(glTexEnvi(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_MODULATE));
    }
    OOGL(glActiveTextureARB(GL_TEXTURE0_ARB));
}

#ifdef OO_DEBUG_MONITOR_ENABLED
std::vector<oo::Ref<OOTexture>> OOMultiTextureMaterial::allTextures()
{
    std::vector<oo::Ref<OOTexture>> result;
    if (_diffuseMap.get() == nil) {
        result.emplace_back(_emissionMap.get());
        return result;
    }
    result.emplace_back(_diffuseMap.get());
    result.emplace_back(_emissionMap.get());
    return result;
}
#endif

#endif /* OO_MULTITEXTURE */
