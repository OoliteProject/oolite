/*

OOSingleTextureMaterial.h


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

#import "OOSingleTextureMaterial.h"
#import "OOFunctionAttributes.h"
#import "OOTexture.h"

namespace cxx {

oo::Ref<OOSingleTextureMaterial> OOSingleTextureMaterial::materialWithName(const std::optional<std::string>& name, const oo::PList& configuration)
{
    oo::Ref<OOSingleTextureMaterial> result = oo::makeRef<OOSingleTextureMaterial>();
    if (!result->initWithName(name, configuration))
        return nullptr;
    return result;
}

oo::Ref<OOSingleTextureMaterial> OOSingleTextureMaterial::materialWithName(const std::optional<std::string>& name, ::OOTexture* texture, const oo::PList& configuration)
{
    oo::Ref<OOSingleTextureMaterial> result = oo::makeRef<OOSingleTextureMaterial>();
    if (!result->initWithName(name, texture, configuration))
        return nullptr;
    return result;
}

bool OOSingleTextureMaterial::initWithName(const std::optional<std::string>& name, const oo::PList& configuration)
{
    oo::PList texSpec;

    if (!configuration.isNull()) {
        // -oo_textureSpecifierForKey:@"diffuse_map" defaultName:name.
        const oo::PList* diffuseMap = configuration.find("diffuse_map");
        texSpec = cxx_OOTextureSpecFromObject((diffuseMap != nullptr) ? *diffuseMap : oo::PList(), name);
    } else if (name.has_value()) {
        texSpec = oo::PList(*name);
    }

    return initWithName(name,
        [::OOTexture cxx_textureWithConfiguration:texSpec],
        configuration);
}

bool OOSingleTextureMaterial::initWithName(const std::optional<std::string>& name, ::OOTexture* texture, const oo::PList& configuration)
{
    if (name.has_value() && texture != nil) {
        OOBasicMaterial::initWithName(name, configuration);
        _texture = oo::ObjCRef<::OOTexture*>(texture);
    } else {
        return false; // DESTROY(self): the factory drops the object
    }

    return true;
}

// -dealloc's [self willDealloc] is the root facade's (proposed ADR-0056, amendment oo-smy item 3),
// and the texture is released with _texture.

std::optional<std::string> OOSingleTextureMaterial::descriptionComponents() const
{
    return [_texture.get() cxx_description];
}

bool OOSingleTextureMaterial::doApply()
{
    if (EXPECT_NOT(!OOBasicMaterial::doApply()))
        return false;

    [_texture.get() apply];
    return true;
}

void OOSingleTextureMaterial::unapplyWithNext(OOMaterial* next)
{
    // -isKindOfClass: (nil is not one)
    if (dynamic_cast<OOSingleTextureMaterial*>(next) == nullptr)
        [::OOTexture applyNone];
    OOBasicMaterial::unapplyWithNext(next);
}

void OOSingleTextureMaterial::ensureFinishedLoading()
{
    [_texture.get() ensureFinishedLoading];
}

bool OOSingleTextureMaterial::isFinishedLoading()
{
    return [_texture.get() isFinishedLoading];
}

bool OOSingleTextureMaterial::wantsNormalsAsTextureCoordinates()
{
    return [_texture.get() isCubeMap];
}

#ifdef OO_DEBUG_MONITOR_ENABLED
std::vector<oo::ObjCRef<::OOTexture*>> OOSingleTextureMaterial::allTextures()
{
    std::vector<oo::ObjCRef<::OOTexture*>> result;
    result.emplace_back(_texture.get());
    return result;
}
#endif

} // namespace cxx
