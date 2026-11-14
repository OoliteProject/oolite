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

#include "OODrawable.h"

#include <format>
#include <typeinfo>

#include "OODemangle.h"
#include "oofnd/AutoreleaseScope.hpp"
#include "oofnd/String.hpp"

void OODrawable::renderOpaqueParts() {}

void OODrawable::renderTranslucentParts() {}

bool OODrawable::hasOpaqueParts() { return false; }

bool OODrawable::hasTranslucentParts() { return false; }

GLfloat OODrawable::collisionRadius() { return 0.0f; }

GLfloat OODrawable::maxDrawDistance() { return 0.0f; }

BoundingBox OODrawable::boundingBox() { return kZeroBoundingBox; }

void OODrawable::setBindingTarget(Entity* /*target*/) {}

void OODrawable::dumpSelfState() {}

std::optional<std::string> OODrawable::descriptionComponents() const {
  return std::nullopt;
}

// The C++ class's name and the drawable's own address, with the description
// components if any.
std::string OODrawable::description() const {
  const std::string name = OODemangle(typeid(*this).name());
  std::string result =
      std::format("<{} {}>", name, oo::str::pointerDescription(this));
  if (const std::optional<std::string> components = descriptionComponents())
    result += "{" + *components + "}";
  return result;
}

#ifdef OO_DEBUG_MONITOR_ENABLED
std::vector<std::shared_ptr<OOTexture>> OODrawable::allTextures() { return {}; }

// The object's own size.
size_t OODrawable::totalSize() { return objectSize(); }
#endif

/*	OODrawableAutorelease(): the drawable goes to the innermost
   oo::AutoreleaseScope, whose drain releases it where the keeper object that
   held it was released.
*/
void OODrawableAutorelease(std::shared_ptr<OODrawable> drawable) {
  if (drawable == nullptr) return;
  oo::autorelease(std::move(drawable));
}
