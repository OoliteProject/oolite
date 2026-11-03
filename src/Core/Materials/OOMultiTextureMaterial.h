/*

OOMultiTextureMaterial.h

A material that uses multitexturing and texture combiners.

C++20 since bead oo-lh0x (proposed ADR-0056, amendments oo-smy and oo-vl43). Its Objective-C
facade was deleted by bead oo-9ht.42 (ADR-0056 amendment "deleting a facade"): the class is global,
and Objective-C sees one as an OOMaterial (OOBasicMaterial's facade was deleted by bead oo-9ht.33).


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

#ifndef OOMULTITEXTUREMATERIAL_H
#define OOMULTITEXTUREMATERIAL_H

#include "OOOpenGLExtensionManager.h"

#if OO_MULTITEXTURE

#include "OOBasicMaterial.h"

class OOTexture;

class OOMultiTextureMaterial : public OOBasicMaterial {
public:
    /*	A new material, initialised by initWithName() (below); null where it failed (it answered
            nil: no texture combiners). It was [[OOMultiTextureMaterial alloc] initWithName:configuration:].
    */
    static oo::Ref<OOMultiTextureMaterial> materialWithName(const std::optional<std::string>& name, const oo::PList& configuration);

    // Runs once, right after construction (proposed ADR-0056, amendment oo-vl43); false where the
    // Objective-C initialiser answered nil.
    bool initWithName(const std::optional<std::string>& name, const oo::PList& configuration); // shared with OOBasicMaterial

    NSUInteger textureUnitCount();

    std::optional<std::string> descriptionComponents() const override;
    NSUInteger countOfTextureUnitsWithBaseCoordinates() override;
    void ensureFinishedLoading() override;
    void apply() override;
    void unapplyWithNext(OOMaterial* next) override;
    size_t objectSize() const override { return sizeof *this; }
#ifdef OO_DEBUG_MONITOR_ENABLED
    std::vector<oo::Ref<OOTexture>> allTextures() override;
#endif

private:
    oo::Ref<OOTexture> _diffuseMap = { };
    oo::Ref<OOTexture> _emissionMap = { };

    NSUInteger _unitsUsed = { };
};

#endif /* OO_MULTITEXTURE */

#endif // OOMULTITEXTUREMATERIAL_H
