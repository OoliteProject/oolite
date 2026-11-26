/*

OOMaterial.h

A material which can be applied to an OpenGL object, or more accurately, to
the current OpenGL render state.

This is an abstract class; actual materials should be subclasses.

Currently, only shader materials are supported. Direct use of textures should
also be replaced with an OOMaterial subclass.

C++20 since bead oo-smy, the Materials module exemplar (proposed ADR-0056, amendment oo-smy).
Its Objective-C facade (the material bridge) was deleted by bead oo-9ht.8 (ADR-0056 amendment
oo-9ht.8), which moved the class out of namespace cxx: the current material is held as an
oo::Ref<OOMaterial>.


Copyright (C) 2007-2013 Jens Ayton and contributors

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

#ifndef OOMATERIAL_H
#define OOMATERIAL_H

#include "OOFoundation.h"
#include "OOOpenGL.h"
#include "OOOpenGLExtensionManager.h"
#include "oofnd/objc/OOObject.h"
class Entity; // Entity.h: the shader binding target (bead oo-9ht.39.6)

#include "oofnd/PList.hpp"
#include "oofnd/Ref.hpp"
#include "oofnd/StdLib.hpp"
#include <vector>

#include "OOTexture.h" // allTextures() answers oo::Ref<OOTexture>, which needs the class (bead oo-9ht.99)

class OOMaterial : public oo::RefCounted {
public:
    // Called once at startup (by -[Universe init]).
    static void setUp();

    virtual std::optional<std::string> name(); // nullopt: none (bead oo-3rb.289.5)

    // What "%@" prints between the braces of <Class 0x...>{...} (OODescription.h): the quoted name.
    virtual std::optional<std::string> descriptionComponents() const;

    // The facade's -cxx_description (bead oo-9ht.8 deleted it): <Class 0x...>{components}, the C++
    // class's name, as [self class] named it, and the material's address.
    std::string description() const;

    // The object's own size, for the debug sizes (was the facade's instance size; bead oo-9ht.8).
    virtual size_t objectSize() const { return sizeof *this; }

    // Make this the current material. Virtual since bead oo-lh0x: OOMultiTextureMaterial overrides it.
    virtual void apply();

    /*	Make no material the current material, tearing down anything set up by the
            current material.
    */
    static void applyNone();

    /*	Get current material.
     */
    static oo::Ref<OOMaterial> current();

    /*	Ensure material is ready to be used in a display list. This is not
            required before using a material directly.
    */
    virtual void ensureFinishedLoading();
    virtual bool isFinishedLoading();

    // Only used by shader material, but defined for all materials for convenience.
    virtual void setBindingTarget(Entity* target);

    // True if material wants three-component cube map texture coordinates.
    virtual bool wantsNormalsAsTextureCoordinates();

#if OO_MULTITEXTURE
    // Nasty hack: number of texture units for which the drawable should set its basic texture coordinates.
    virtual NSUInteger countOfTextureUnitsWithBaseCoordinates();
#endif

#ifdef OO_DEBUG_MONITOR_ENABLED
    virtual std::vector<oo::Ref<OOTexture>> allTextures();
#endif

    // Subclass interface (was the OOSubclassInterface category).

    // Subclass responsibilities - don't call directly.
    virtual bool doApply(); // Override instead of apply()
    virtual void unapplyWithNext(OOMaterial* next);

    /*	Was called at the top of an Objective-C subclass's -dealloc. A C++ material is not destroyed
            while it is current (the current-material slot retains it), so no destructor calls this
            (proposed ADR-0056, amendments oo-smy and oo-9ht.8): if it is current, it is unapplied and the
            slot's reference is detached, not released.
    */
    void willDealloc();

    /*	The convenience creators: the category OOConvenienceCreators, whose class methods are these
            static members since bead oo-9fwb, defined in OOMaterialConvenienceCreators.mm (proposed
            ADR-0056 amendment oo-o89 item 4; OOMaterialConvenienceCreators.h documents them).

            Get a material based on configuration. The result will be an
            OOBasicMaterial, OOSingleTextureMaterial or OOShaderMaterial (the latter
            only if shaders are available). cacheKey is used for caching of synthesized
            shader materials; nullopt may be passed for no caching. configuration and
            macros are oo::PList (null = nil).
    */
    static oo::Ref<OOMaterial> materialWithName(const std::optional<std::string>& name,
        const std::optional<std::string>& cacheKey,
        const oo::PList& configuration,
        const oo::PList& macros,
        Entity* object,
        bool smooth);

    /*	Select an appropriate material description (based on availability of
            shaders and content of dictionaries, which may be null) and call
            the one above.
    */
    static oo::Ref<OOMaterial> materialWithName(const std::optional<std::string>& name,
        const std::optional<std::string>& cacheKey,
        const oo::PList& materialDict,
        const oo::PList& shadersDict,
        const oo::PList& macros,
        Entity* object,
        bool smooth);

private:
    // The category's own class methods, which only it called.
    static oo::PList synthesizeMaterialDictionaryWithName(const std::optional<std::string>& name,
        const oo::PList& configuration,
        const oo::PList& macros);
    static oo::Ref<OOMaterial> defaultShaderMaterialWithName(const std::optional<std::string>& name,
        const std::optional<std::string>& cacheKey,
        const oo::PList& configuration,
        const oo::PList& macros,
        Entity* target);
};

/*	[material autorelease], which the deleted facade answered (bead oo-9ht.8): keeps the material
        until the current autorelease pool drains, so a material a drawable replaces lives exactly as
        long as its autoreleased object did, as OODrawableAutorelease() does for drawables. Nothing for
        null.
*/
void OOMaterialAutorelease(oo::Ref<OOMaterial> material);

#endif // OOMATERIAL_H
