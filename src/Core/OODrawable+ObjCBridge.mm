/*

OODrawable+ObjCBridge.mm

TRANSITIONAL (proposed ADR-0056, amendment oo-smy): the Objective-C OODrawable facade (see
OODrawable+ObjCBridge.h). Every method forwards to its C++ member. An Objective-C subclass's C++
part is an ObjCDrawable, whose virtual members message the subclass. Deleted with
OODrawable+ObjCBridge.h.


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

#import "OODescription.h"
#import "OODrawable.h"
#include "oofnd/String.hpp"
#include "oofnd/objc/OOAssert.h"
#include "oofnd/objc/OOObjCPeer.h"

#include <cstdlib>
#include <cxxabi.h>
#include <new>
#include <typeinfo>

namespace {

// Never destroyed: a facade may be released while the process exits.
oo::ObjCPeers& Peers()
{
    static oo::ObjCPeers* peers = new oo::ObjCPeers;
    return *peers;
}

/*	The C++ part of an Objective-C drawable: each virtual member messages the Objective-C object,
        so the subclass's override runs, as it did when the base class was Objective-C. The
        Objective-C object owns this (its _cxxDrawable) and is not retained by it; its -dealloc clears
        the pointer, after which the members answer as a message to nil did.
*/
class ObjCDrawable final : public cxx::OODrawable {
public:
    explicit ObjCDrawable(::OODrawable* owner)
        : _owner(owner)
    {
    }

    ::OODrawable* owner() { return _owner; }
    void ownerDeallocated() { _owner = nil; }

    void renderOpaqueParts() override { [_owner renderOpaqueParts]; }
    void renderTranslucentParts() override { [_owner renderTranslucentParts]; }
    bool hasOpaqueParts() override { return [_owner hasOpaqueParts]; }
    bool hasTranslucentParts() override { return [_owner hasTranslucentParts]; }
    GLfloat collisionRadius() override { return [_owner collisionRadius]; }
    GLfloat maxDrawDistance() override { return [_owner maxDrawDistance]; }
    BoundingBox boundingBox() override { return [_owner boundingBox]; }
    void setBindingTarget(id<OOWeakReferenceSupport> target) override { [_owner setBindingTarget:target]; }
    void dumpSelfState() override { [_owner dumpSelfState]; }
    std::optional<std::string> descriptionComponents() const override { return [_owner cxx_descriptionComponents]; }
#ifdef OO_DEBUG_MONITOR_ENABLED
    std::vector<oo::ObjCRef<OOTexture*>> allTextures() override { return [_owner cxx_allTextures]; }
    size_t totalSize() override { return [_owner totalSize]; }
#endif

private:
    ::OODrawable* _owner = { }; // Not retained.
};

ObjCDrawable* AsObjCDrawable(cxx::OODrawable* drawable)
{
    return dynamic_cast<ObjCDrawable*>(drawable);
}

// The C++ class's name, as [self class] named an Objective-C drawable's class ("cxx::" dropped).
std::string ClassName(cxx::OODrawable& drawable)
{
    int status = 0;
    char* demangled = abi::__cxa_demangle(typeid(drawable).name(), nullptr, nullptr, &status);
    std::string result = (status == 0 && demangled != nullptr) ? demangled : typeid(drawable).name();
    std::free(demangled);
    if (result.starts_with("cxx::"))
        result.erase(0, 5);
    return result;
}

} // namespace

@interface OODrawable (OOObjCBridgePrivate)

- (id)initWithCxxDrawable:(cxx::OODrawable*)drawable;

@end

@implementation OODrawable

// Inside the @implementation for the private ivar.
OODrawable* oo::ToObjC(cxx::OODrawable* drawable)
{
    if (ObjCDrawable* objCDrawable = AsObjCDrawable(drawable))
        return [[objCDrawable->owner() retain] autorelease];
    return Peers().peerFor(drawable, [drawable] { return [[OODrawable alloc] initWithCxxDrawable:drawable]; });
}

cxx::OODrawable* oo::ToCxx(OODrawable* drawable)
{
    if (drawable == nil)
        return nullptr;
    return drawable->_cxxDrawable.get();
}

void oo::ConstructCxxPartOfCopy(OODrawable* copy)
{
    OOCParameterAssert(AsObjCDrawable(copy->_cxxDrawable.get()) != nullptr); // only an Objective-C drawable is copied bitwise
    new (&copy->_cxxDrawable) oo::Ref<cxx::OODrawable>(oo::makeRef<ObjCDrawable>(copy));
}

// An Objective-C drawable: [[X alloc] init] of a subclass (or of this class).
- (id)init
{
    self = [super init];
    if (self != nil)
        _cxxDrawable = oo::makeRef<ObjCDrawable>(self);
    return self;
}

// A C++ drawable's facade (oo::ToObjC).
- (id)initWithCxxDrawable:(cxx::OODrawable*)drawable
{
    self = [super init];
    if (self != nil)
        _cxxDrawable = oo::Ref<cxx::OODrawable>(drawable);
    return self;
}

- (void)dealloc
{
    if (ObjCDrawable* objCDrawable = AsObjCDrawable(_cxxDrawable.get()))
        objCDrawable->ownerDeallocated();
    else
        Peers().forget(_cxxDrawable.get());
    [super dealloc];
}

// A C++ drawable's facade describes itself with the C++ class's name and components.
- (std::optional<std::string>)cxx_description
{
    if (AsObjCDrawable(_cxxDrawable.get()) != nullptr)
        return [super cxx_description];
    std::string result = oo::str::format("<%s %s>", ClassName(*_cxxDrawable).c_str(), oo::str::pointerDescription(self).c_str());
    if (const std::optional<std::string> components = _cxxDrawable->descriptionComponents())
        result += "{" + *components + "}";
    return result;
}

/*	The overridable methods. On an Objective-C drawable these are reached only when the subclass
        does not override them, or by [super ...]: the base class's own member answers. On a C++
        drawable's facade the C++ override answers. (-cxx_descriptionComponents is not forwarded:
        OOObject's answers an Objective-C drawable, and -cxx_description above a C++ one.)
*/

- (void)renderOpaqueParts
{
    if (AsObjCDrawable(_cxxDrawable.get()) != nullptr)
        _cxxDrawable->cxx::OODrawable::renderOpaqueParts();
    else
        _cxxDrawable->renderOpaqueParts();
}

- (void)renderTranslucentParts
{
    if (AsObjCDrawable(_cxxDrawable.get()) != nullptr)
        _cxxDrawable->cxx::OODrawable::renderTranslucentParts();
    else
        _cxxDrawable->renderTranslucentParts();
}

- (BOOL)hasOpaqueParts
{
    if (AsObjCDrawable(_cxxDrawable.get()) != nullptr)
        return _cxxDrawable->cxx::OODrawable::hasOpaqueParts();
    return _cxxDrawable->hasOpaqueParts();
}

- (BOOL)hasTranslucentParts
{
    if (AsObjCDrawable(_cxxDrawable.get()) != nullptr)
        return _cxxDrawable->cxx::OODrawable::hasTranslucentParts();
    return _cxxDrawable->hasTranslucentParts();
}

- (GLfloat)collisionRadius
{
    if (AsObjCDrawable(_cxxDrawable.get()) != nullptr)
        return _cxxDrawable->cxx::OODrawable::collisionRadius();
    return _cxxDrawable->collisionRadius();
}

- (GLfloat)maxDrawDistance
{
    if (AsObjCDrawable(_cxxDrawable.get()) != nullptr)
        return _cxxDrawable->cxx::OODrawable::maxDrawDistance();
    return _cxxDrawable->maxDrawDistance();
}

- (BoundingBox)boundingBox
{
    if (AsObjCDrawable(_cxxDrawable.get()) != nullptr)
        return _cxxDrawable->cxx::OODrawable::boundingBox();
    return _cxxDrawable->boundingBox();
}

- (void)setBindingTarget:(id<OOWeakReferenceSupport>)target
{
    if (AsObjCDrawable(_cxxDrawable.get()) != nullptr)
        _cxxDrawable->cxx::OODrawable::setBindingTarget(target);
    else
        _cxxDrawable->setBindingTarget(target);
}

- (void)dumpSelfState
{
    if (AsObjCDrawable(_cxxDrawable.get()) != nullptr)
        _cxxDrawable->cxx::OODrawable::dumpSelfState();
    else
        _cxxDrawable->dumpSelfState();
}

#ifdef OO_DEBUG_MONITOR_ENABLED
- (std::vector<oo::ObjCRef<OOTexture*>>)cxx_allTextures
{
    if (AsObjCDrawable(_cxxDrawable.get()) != nullptr)
        return _cxxDrawable->cxx::OODrawable::allTextures();
    return _cxxDrawable->allTextures();
}

- (size_t)totalSize
{
    if (AsObjCDrawable(_cxxDrawable.get()) != nullptr)
        return _cxxDrawable->cxx::OODrawable::totalSize();
    return _cxxDrawable->totalSize();
}
#endif

@end
