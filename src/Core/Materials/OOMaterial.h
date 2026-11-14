/*

OOMaterial.h

A material which can be applied to an OpenGL object, or more accurately, to
the current OpenGL render state.

This is an abstract class; actual materials should be subclasses.

Currently, only shader materials are supported. Direct use of textures should
also be replaced with an OOMaterial subclass.

C++20 since bead oo-smy, the Materials module exemplar (proposed ADR-0056, amendment oo-smy).
The class is cxx::OOMaterial while OOMaterial+ObjCBridge.h, imported at the end of this header,
keeps the Objective-C OOMaterial that its callers message and its unconverted subclasses derive
from; the bridge's deletion bead moves it out of namespace cxx.


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

#import "OOFoundation.h"
#import "OOOpenGL.h"
#import "OOOpenGLExtensionManager.h"
#import "OOWeakReference.h"
#import "oofnd/objc/OOObject.h"

#include "oofnd/Ref.hpp"
#include "oofnd/StdLib.hpp"
#include "oofnd/objc/OOObjCRef.h"
#include <vector>

@class OOTexture;

namespace cxx {

class OOMaterial : public oo::RefCounted {
public:
    // Called once at startup (by -[Universe init]).
    static void setUp();

    virtual std::optional<std::string> name(); // nullopt: none (bead oo-3rb.289.5)

    // What "%@" prints between the braces of <Class 0x...>{...} (OODescription.h): the quoted name.
    virtual std::optional<std::string> descriptionComponents() const;

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
    virtual void setBindingTarget(id<OOWeakReferenceSupport> target);

    // True if material wants three-component cube map texture coordinates.
    virtual bool wantsNormalsAsTextureCoordinates();

#if OO_MULTITEXTURE
    // Nasty hack: number of texture units for which the drawable should set its basic texture coordinates.
    virtual NSUInteger countOfTextureUnitsWithBaseCoordinates();
#endif

#ifdef OO_DEBUG_MONITOR_ENABLED
    virtual std::vector<oo::ObjCRef<OOTexture*>> allTextures();
#endif

    // Subclass interface (was the OOSubclassInterface category).

    // Subclass responsibilities - don't call directly.
    virtual bool doApply(); // Override instead of apply()
    virtual void unapplyWithNext(OOMaterial* next);

    /*	Call at top of an Objective-C subclass's -dealloc. A C++ material is not destroyed while it
            is current (the current-material slot retains it), so no destructor calls this; the root's -dealloc body
            that did is the facade's (proposed ADR-0056, amendment oo-smy).
    */
    void willDealloc();
};

} // namespace cxx

// Transitional: the Objective-C OOMaterial, for callers and subclasses not yet converted.
// Deleted, with namespace cxx above, by the bridge's deletion bead.
#import "OOMaterial+ObjCBridge.h"

#endif // OOMATERIAL_H
