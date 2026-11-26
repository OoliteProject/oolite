/*

OODrawable.h

Abstract base class for objects which can draw themselves.

C++20 since bead oo-smy, with OOMaterial the Materials module exemplar (proposed ADR-0056,
amendment oo-smy). The class is cxx::OODrawable while OODrawable+ObjCBridge.h, imported at the end
of this header, keeps the Objective-C OODrawable that its callers message and its unconverted
subclasses (OOMesh, OOPlanetDrawable, OOSkyDrawable) derive from; the bridge's deletion bead moves
it out of namespace cxx.


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

#import "OOFoundation.h"
#import "OOMaths.h"
#import "OOOpenGL.h"
#import "OOWeakReference.h"
#import "oofnd/objc/OOObject.h"

#include "oofnd/Ref.hpp"
#include "oofnd/StdLib.hpp"
#include "oofnd/objc/OOObjCRef.h"
#include <vector>

@class OOTexture;

namespace cxx {

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
    virtual void setBindingTarget(id<OOWeakReferenceSupport> target);

    virtual void dumpSelfState();

    // What "%@" prints between the braces of <Class 0x...>{...} (OODescription.h). None here, as
    // OOObject answered; OOMesh and OOSkyDrawable override it.
    virtual std::optional<std::string> descriptionComponents() const;

#ifdef OO_DEBUG_MONITOR_ENABLED
    virtual std::vector<oo::ObjCRef<::OOTexture*>> allTextures();
    virtual size_t totalSize(); // Size including dynamic data, not counting textures.
#endif
};

} // namespace cxx

// Transitional: the Objective-C OODrawable, for callers and subclasses not yet converted.
// Deleted, with namespace cxx above, by the bridge's deletion bead.
#import "OODrawable+ObjCBridge.h"

#endif // OODRAWABLE_H
