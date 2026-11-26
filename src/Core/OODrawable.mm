/*

OODrawable.m


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

#import "OODrawable.h"
#include "oofnd/String.hpp"

#include <cstdlib>
#include <cxxabi.h>
#include <typeinfo>

void OODrawable::renderOpaqueParts()
{
}

void OODrawable::renderTranslucentParts()
{
}

bool OODrawable::hasOpaqueParts()
{
    return false;
}

bool OODrawable::hasTranslucentParts()
{
    return false;
}

GLfloat OODrawable::collisionRadius()
{
    return 0.0f;
}

GLfloat OODrawable::maxDrawDistance()
{
    return 0.0f;
}

BoundingBox OODrawable::boundingBox()
{
    return kZeroBoundingBox;
}

void OODrawable::setBindingTarget(id<OOWeakReferenceSupport> /*target*/)
{
}

void OODrawable::dumpSelfState()
{
}

std::optional<std::string> OODrawable::descriptionComponents() const
{
    return std::nullopt;
}

// The facade's -cxx_description (the facade is deleted): the C++ class's name, as [self class]
// named it, and the address, now the drawable's.
std::string OODrawable::description() const
{
    int status = 0;
    char* demangled = abi::__cxa_demangle(typeid(*this).name(), nullptr, nullptr, &status);
    const std::string name = (status == 0 && demangled != nullptr) ? demangled : typeid(*this).name();
    std::free(demangled);
    std::string result = oo::str::format("<%s %s>", name.c_str(), oo::str::pointerDescription(this).c_str());
    if (const std::optional<std::string> components = descriptionComponents())
        result += "{" + *components + "}";
    return result;
}

#ifdef OO_DEBUG_MONITOR_ENABLED
std::vector<oo::ObjCRef<::OOTexture*>> OODrawable::allTextures()
{
    return { };
}

// The object's own size (was [self oo_objectSize], the facade's instance size).
size_t OODrawable::totalSize()
{
    return objectSize();
}
#endif

/*	OODrawableAutorelease()'s keeper: an autoreleased Objective-C object that holds the drawable, so
        the pool's drain releases it as it released the facade. Private to this file; nothing messages
        it (as OOScript.mm's keeper).
*/
@interface OODrawableAutoreleaseKeeper : OOObject {
@private
    oo::Ref<OODrawable> _drawable;
}

- (id)initWithDrawable:(oo::Ref<OODrawable>)drawable;

@end

@implementation OODrawableAutoreleaseKeeper

- (id)initWithDrawable:(oo::Ref<OODrawable>)drawable
{
    self = [super init];
    if (self != nil)
        _drawable = std::move(drawable);
    return self;
}

@end

void OODrawableAutorelease(oo::Ref<OODrawable> drawable)
{
    if (drawable == nullptr)
        return;
    [[[OODrawableAutoreleaseKeeper alloc] initWithDrawable:std::move(drawable)] autorelease];
}
