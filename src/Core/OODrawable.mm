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
#import "NSObjectOOExtensions.h"

namespace cxx {

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

#ifdef OO_DEBUG_MONITOR_ENABLED
std::vector<oo::ObjCRef<::OOTexture*>> OODrawable::allTextures()
{
    return { };
}

// The instance size of the Objective-C object: an Objective-C drawable's own class, as
// [self oo_objectSize] was, or a C++ drawable's facade.
size_t OODrawable::totalSize()
{
    return [oo::ToObjC(this) oo_objectSize];
}
#endif

} // namespace cxx
