/*

OOTextureGenerator+ObjCBridge.mm

TRANSITIONAL (proposed ADR-0056): the Objective-C OOTextureGenerator facade over
cxx::OOTextureGenerator, and the adapter that is an Objective-C generator's C++ part. Every method
forwards in one line. Deleted, with OOTextureGenerator+ObjCBridge.h, by the bridge's deletion bead.


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

#import "OOTextureGenerator.h"

namespace {

/*	The C++ part of an Objective-C generator: the loaders' adapter over cxx::OOTextureGenerator,
        with the members the generator adds, each messaging the Objective-C object (amendment oo-vl43
        item 1).
*/
class ObjCTextureGenerator final : public oo::ObjCTextureLoader<cxx::OOTextureGenerator> {
public:
    explicit ObjCTextureGenerator(::OOTextureGenerator* owner)
        : ObjCTextureLoader(owner)
    {
    }

    uint32_t textureOptions() override { return [Owner() textureOptions]; }
    GLfloat anisotropy() override { return [Owner() anisotropy]; }
    GLfloat lodBias() override { return [Owner() lodBias]; }
    bool enqueue() override { return [Owner() enqueue]; }

private:
    ::OOTextureGenerator* Owner() { return (::OOTextureGenerator*)_owner; }
};

// The generator when it is an Objective-C generator's C++ part (not a C++ generator).
bool IsObjCGenerator(cxx::OOTextureLoader* loader)
{
    return oo::AsObjCTextureLoader(loader) != nullptr;
}

} // namespace

@implementation OOTextureGenerator

// An Objective-C generator's designated initialiser: its C++ part is the generator's adapter.
- (id)cxx_initWithPath:(const std::optional<std::string>&)inPath options:(uint32_t)options
{
    return [self cxx_initWithCxxLoader:oo::makeRef<ObjCTextureGenerator>(self) path:inPath options:options];
}

/*	The overridable methods. On an Objective-C generator these are reached only when the subclass
        does not override them, or by [super ...]: the generator's own member answers. On a C++
        generator's facade the C++ override answers.
*/

- (uint32_t)textureOptions
{
    if (IsObjCGenerator(_cxxLoader.get()))
        return oo::ToCxx(self)->cxx::OOTextureGenerator::textureOptions();
    return oo::ToCxx(self)->textureOptions();
}

- (GLfloat)anisotropy
{
    if (IsObjCGenerator(_cxxLoader.get()))
        return oo::ToCxx(self)->cxx::OOTextureGenerator::anisotropy();
    return oo::ToCxx(self)->anisotropy();
}

- (GLfloat)lodBias
{
    if (IsObjCGenerator(_cxxLoader.get()))
        return oo::ToCxx(self)->cxx::OOTextureGenerator::lodBias();
    return oo::ToCxx(self)->lodBias();
}

- (std::optional<std::string>)cxx_cacheKey
{
    if (IsObjCGenerator(_cxxLoader.get()))
        return oo::ToCxx(self)->cxx::OOTextureGenerator::cacheKey();
    return oo::ToCxx(self)->cacheKey();
}

- (BOOL)enqueue
{
    if (IsObjCGenerator(_cxxLoader.get()))
        return oo::ToCxx(self)->cxx::OOTextureGenerator::enqueue();
    return oo::ToCxx(self)->enqueue();
}

@end

// A C++ generator's facade is an OOTextureGenerator: the root's oo::ToObjC picks the Objective-C
// class named as the C++ class is (amendment oo-up4b item 3).
OOTextureGenerator* oo::ToObjC(cxx::OOTextureGenerator* generator)
{
    return static_cast<OOTextureGenerator*>(oo::ToObjC(static_cast<cxx::OOTextureLoader*>(generator)));
}

cxx::OOTextureGenerator* oo::ToCxx(OOTextureGenerator* generator)
{
    return static_cast<cxx::OOTextureGenerator*>(oo::ToCxx(static_cast<OOTextureLoader*>(generator)));
}
