/*

OODrawable+ObjCBridge.h

TRANSITIONAL (proposed ADR-0056, amendment oo-smy): the Objective-C OODrawable, a facade over the
C++ cxx::OODrawable (OODrawable.h), for the callers that message drawables (the entities) and for
the drawables not converted yet (OOMesh, OOPlanetDrawable, OOSkyDrawable). Its interface is the
one OODrawable.h declared before the conversion, copied exactly (same selectors, same types), so
they compile and behave unchanged. Imported as the last line of OODrawable.h; do not import it
directly.

It is a hierarchy root's facade, as OOMaterial+ObjCBridge.h is; the tables there apply here:

        the drawable is                      its facade is                      virtual calls on the
                                                                                  C++ side reach
        -----------------------------------  ---------------------------------  ---------------------
        an Objective-C subclass              the subclass instance itself, and  the subclass's
          (unconverted, [[X alloc] init])    an adapter is its C++ part         methods
        a C++ subclass (converted)           made by oo::ToObjC, one live one   the C++ overrides
                                             per drawable (oo::ObjCPeers)

A converted caller that keeps a drawable while any subclass is Objective-C holds
oo::ObjCRef<OODrawable *>: an Objective-C drawable's C++ part does not retain it.

A subclass that copies itself bitwise (OOMesh's -mutableCopyWithZone:, NSCopyObject's
replacement) calls oo::ConstructCxxPartOfCopy on the copy, where it constructs its own C++ ivars
afresh: the copied ivar is the original's C++ part.

oo::ToObjC(oo::ToCxx(d)) == d for both kinds. Never add to this file; converted code does not
message the facade. Deleted by its deletion bead once every caller and every drawable is C++.


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

#ifndef OODRAWABLE_OBJCBRIDGE_H
#define OODRAWABLE_OBJCBRIDGE_H

@interface OODrawable : OOObject {
@private
    oo::Ref<cxx::OODrawable> _cxxDrawable;
}

- (void)renderOpaqueParts;
- (void)renderTranslucentParts;
- (BOOL)hasOpaqueParts;
- (BOOL)hasTranslucentParts;

- (GLfloat)collisionRadius;
- (GLfloat)maxDrawDistance;

- (BoundingBox)boundingBox;

// Passed to all materials.
- (void)setBindingTarget:(id<OOWeakReferenceSupport>)target;

- (void)dumpSelfState;

#ifndef NDEBUG
- (std::vector<oo::ObjCRef<OOTexture*>>)cxx_allTextures;
- (size_t)totalSize; // Size including dynamic data, not counting textures.
#endif

@end

namespace oo {

// The drawable's Objective-C object: an Objective-C drawable itself, else a C++ drawable's live
// facade (or a new one); autoreleased. nil for null.
OODrawable* ToObjC(cxx::OODrawable* drawable);
inline OODrawable* ToObjC(const Ref<cxx::OODrawable>& drawable) { return ToObjC(drawable.get()); }

// The C++ drawable behind an Objective-C one, borrowed (the Objective-C object retains it); null for nil.
cxx::OODrawable* ToCxx(OODrawable* drawable);

// A bitwise copy of an Objective-C drawable gets its own C++ part. The copied reference to the
// original's is dropped, not released (the copy never retained it).
void ConstructCxxPartOfCopy(OODrawable* copy);

} // namespace oo

#endif // OODRAWABLE_OBJCBRIDGE_H
