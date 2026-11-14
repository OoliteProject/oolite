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

#import "OOMultiTextureMaterial.h"
#import "OOCombinedEmissionMapGenerator.h"
#import "OOFoundationBridge.h"
#import "OOMacroOpenGL.h"
#import "OOMaterialSpecifier.h"
#import "OOOpenGLExtensionManager.h"
#import "OOTexture.h"

#if OO_MULTITEXTURE

@implementation OOMultiTextureMaterial

- (id)initWithName:(id)name configuration:(id)configuration
{
    if (![[OOOpenGLExtensionManager sharedManager] textureCombinersSupported]) {
        [self release];
        return nil;
    }

    // The configuration mixes plist data with live objects (colours): an oo::PList carries both
    // exactly (proposed ADR-0043 Amendment 2).
    const oo::PList config = oo::PListFrom(configuration);
    const oo::PList diffuseSpec = cxx_OOMaterialDiffuseMapSpecifier(config, oo::OptionalString(name));
    const oo::PList emissionSpec = cxx_OOMaterialEmissionMapSpecifier(config);
    const oo::PList illuminationSpec = cxx_OOMaterialIlluminationMapSpecifier(config);
    const oo::PList emissionAndIlluminationSpec = cxx_OOMaterialEmissionAndIlluminationMapSpecifier(config);
    OOColor* diffuseColor = cxx_OOMaterialDiffuseColor(config);
    OOColor* emissionColor = nil;
    OOColor* illuminationColor = cxx_OOMaterialIlluminationModulateColor(config);

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

    self = [super initWithName:name configuration:oo::ObjectFromPList(mutableConfiguration)];
    if (self != nil) {
        if (!diffuseSpec.isNull()) {
            _diffuseMap = [[OOTexture textureWithConfiguration:oo::ObjectFromPList(diffuseSpec)] retain];
            if (_diffuseMap != nil)
                _unitsUsed++;
        }

        // Check for simplest cases, where we don't need to bake a derived emission map.
        if (!emissionSpec.isNull() && illuminationSpec.isNull() && emissionAndIlluminationSpec.isNull() && emissionColor == nil) {
            _emissionMap = [[OOTexture textureWithConfiguration:oo::ObjectFromPList(emissionSpec) extraOptions:kOOTextureExtraShrink] retain];
            if (_emissionMap != nil)
                _unitsUsed++;
        } else {
            OOCombinedEmissionMapGenerator* generator = nil;

            if (!emissionAndIlluminationSpec.isNull()) {
                id spec = oo::ObjectFromPList(emissionAndIlluminationSpec); // one object for both arguments, as before
                generator = [[OOCombinedEmissionMapGenerator alloc] initWithEmissionAndIlluminationMapSpec:spec
                                                                                                diffuseMap:_diffuseMap
                                                                                              diffuseColor:diffuseColor
                                                                                             emissionColor:emissionColor
                                                                                         illuminationColor:illuminationColor
                                                                                          optionsSpecifier:spec];
            } else {
                id emission = oo::ObjectFromPList(emissionSpec), illumination = oo::ObjectFromPList(illuminationSpec); // one object each, as before
                generator = [[OOCombinedEmissionMapGenerator alloc] initWithEmissionMapSpec:emission
                                                                              emissionColor:emissionColor
                                                                                 diffuseMap:_diffuseMap
                                                                               diffuseColor:diffuseColor
                                                                        illuminationMapSpec:illumination
                                                                          illuminationColor:illuminationColor
                                                                           optionsSpecifier:emission ?: illumination];
            }

            _emissionMap = [[OOTexture textureWithGenerator:[generator autorelease]] retain];
            if (_emissionMap != nil)
                _unitsUsed++;
        }
    }

    return self;
}

- (void)dealloc
{
    [self willDealloc];

    DESTROY(_diffuseMap);
    DESTROY(_emissionMap);

    [super dealloc];
}

- (id)descriptionComponents // shared selector (proposed ADR-0043)
{
    std::vector<std::string> bits;
    if (_diffuseMap)
        bits.push_back("diffuse map: " + oo::DescriptionOf([_diffuseMap shortDescription]));
    if (_emissionMap)
        bits.push_back("emission map: " + oo::DescriptionOf([_emissionMap shortDescription]));

    id result = [super descriptionComponents];
    if (!bits.empty()) {
        std::string joined;
        for (const std::string& bit : bits)
            joined += (joined.empty() ? "" : ",") + bit;
        result = oo::NSStringFrom(oo::StdString(result) + " - " + joined);
    }
    return result;
}

- (NSUInteger)textureUnitCount
{
    return _unitsUsed;
}

- (NSUInteger)countOfTextureUnitsWithBaseCoordinates
{
    return _unitsUsed;
}

- (void)ensureFinishedLoading
{
    [_diffuseMap ensureFinishedLoading];
    [_emissionMap ensureFinishedLoading];
}

- (void)apply
{
    OO_ENTER_OPENGL();

    [super apply];

    GLenum textureUnit = GL_TEXTURE0_ARB;

    if (_diffuseMap != nil) {
        OOGL(glActiveTextureARB(textureUnit++));
        OOGL(glTexEnvi(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_COMBINE_ARB));
        OOGL(glTexEnvi(GL_TEXTURE_ENV, GL_COMBINE_RGB_ARB, GL_MODULATE));
        [_diffuseMap apply];
    }

    if (_emissionMap != nil) {
        OOGL(glActiveTextureARB(textureUnit++));
        OOGL(glTexEnvi(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_COMBINE_ARB));
        OOGL(glTexEnvi(GL_TEXTURE_ENV, GL_COMBINE_RGB_ARB, GL_ADD));
        [_emissionMap apply];
    }

    NSAssert2(textureUnit - GL_TEXTURE0_ARB == _unitsUsed, @"OOMultiTextureMaterial texture unit count invalid (expected %zu, actually using %u)", _unitsUsed, textureUnit - GL_TEXTURE0_ARB);

    if (textureUnit > GL_TEXTURE1_ARB) {
        OOGL(glActiveTextureARB(GL_TEXTURE0_ARB));
    }
}

- (void)unapplyWithNext:(OOMaterial*)next
{
    OO_ENTER_OPENGL();

    [super unapplyWithNext:next];

    NSUInteger i;
    i = [next isKindOfClass:[OOMultiTextureMaterial class]] ? [(OOMultiTextureMaterial*)next textureUnitCount] : 0;
    for (; i != _unitsUsed; ++i) {
        OOGL(glActiveTextureARB(GL_TEXTURE0_ARB + i));
        [OOTexture applyNone];
        OOGL(glTexEnvi(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_MODULATE));
    }
    OOGL(glActiveTextureARB(GL_TEXTURE0_ARB));
}

#ifdef OO_DEBUG_MONITOR_ENABLED
- (id)allTextures // shared selector (proposed ADR-0043)
{
    if (_diffuseMap == nil)
        return oo::NSSetFromObjects(std::vector<id> { _emissionMap });
    return oo::NSSetFromObjects(std::vector<id> { _diffuseMap, _emissionMap });
}
#endif

@end

#endif /* OO_MULTITEXTURE */
