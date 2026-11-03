/*

OODrawable.h

Abstract base class for objects which can draw themselves.

C++20 since bead oo-smy, with OOMaterial the Materials module exemplar (proposed ADR-0056,
amendment oo-smy). Global, its Objective-C facade deleted: every drawable (OOMesh,
OOPlanetDrawable, OOSkyDrawable) and every holder is C++.


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

#ifndef OODRAWABLE_H
#define OODRAWABLE_H

#include "OOFoundation.h"
#include "OOMaths.h"
#include "OOOpenGL.h"
#include "oofnd/objc/OOObject.h"
class Entity; // Entity.h: the shader binding target

#include "oofnd/Ref.hpp"
#include "oofnd/StdLib.hpp"
#include <vector>

#include "OOTexture.h" // allTextures() answers oo::Ref<OOTexture>, which needs the class

class OODrawable : public oo::RefCounted {
public:
    virtual void renderOpaqueParts();
    virtual void renderTranslucentParts();
    virtual bool hasOpaqueParts();
    virtual bool hasTranslucentParts();

    virtual GLfloat collisionRadius();
    virtual GLfloat maxDrawDistance();

    virtual BoundingBox boundingBox();

    // Passed to all materials.
    virtual void setBindingTarget(Entity* target);

    virtual void dumpSelfState();

    // What "%@" prints between the braces of <Class 0x...>{...} (OODescription.h). None here, as
    // OOObject answered; OOMesh and OOSkyDrawable override it.
    virtual std::optional<std::string> descriptionComponents() const;

    // What "%@" printed for the drawable's facade: "<Class 0x...>{components}",
    // the C++ class's name and the drawable's own address.
    std::string description() const;

#ifdef OO_DEBUG_MONITOR_ENABLED
    virtual std::vector<oo::Ref<OOTexture>> allTextures();
    virtual size_t totalSize(); // Size including dynamic data, not counting textures.

    // The object's own size, which totalSize() starts from (the facade's instance size
    // before): sizeof the dynamic type, each subclass answering its own.
    virtual size_t objectSize() const { return sizeof *this; }
#endif
};

/*	[drawable autorelease], which the deleted facade answered: keeps the drawable
        until the current autorelease pool drains, so a drawable an entity replaces lives exactly as
        long as its autoreleased object did. Nothing for null.
*/
void OODrawableAutorelease(oo::Ref<OODrawable> drawable);

#endif // OODRAWABLE_H
