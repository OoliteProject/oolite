/*

OOMaterial.m


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

#include "OOMaterial.h"

#include <format>
#include <typeinfo>

#include "OODemangle.h"
#include "OOFunctionAttributes.h"
#include "OOLogging.h"
#include "OOMaterialState.h"
#include "oofnd/Ref.hpp"  // oo::autorelease
#include "oofnd/String.hpp"

namespace {

/*	The current material, retained. Never destroyed, as the static pointer
   was not.
*/
std::shared_ptr<OOMaterial>& ActiveMaterial() {
  static auto* active = new std::shared_ptr<OOMaterial>;
  return *active;
}

}  // namespace

void OOMaterial::setUp() {
  // I thought we'd need this, but the stuff I needed it for turned out to be
  // problematic. Maybe in future. -- Ahruman
}

// name() is a subclass's override, so it cannot be const.
std::optional<std::string> OOMaterial::descriptionComponents() const {
  return "\"" + const_cast<OOMaterial*>(this)->name().value_or("(null)") +
         "\"";  // "%@" of the name, quoted
}

std::string OOMaterial::description() const {
  const std::string name = OODemangle(typeid(*this).name());
  std::string result =
      std::format("<{} {}>", name, oo::str::pointerDescription(this));
  if (const std::optional<std::string> components = descriptionComponents())
    result += "{" + *components + "}";
  return result;
}

std::optional<std::string> OOMaterial::name() {
  OOLogGenericParameterError();
  return std::nullopt;
}

// Make this the current GL shader program.
void OOMaterial::apply() {
  if (OOMaterial* active = ActiveMaterial().get())
    active->unapplyWithNext(this);
  ActiveMaterial() = nullptr;

  if (doApply()) {
    ActiveMaterial() = oo::share(this);
  }
}

void OOMaterial::applyNone() {
  if (OOMaterial* active = ActiveMaterial().get())
    active->unapplyWithNext(nullptr);
  ActiveMaterial() = nullptr;
}

std::shared_ptr<OOMaterial> OOMaterial::current() { return ActiveMaterial(); }

// OOMaterialState.h: the slot for plain C++ translation units.
std::shared_ptr<OOMaterial> OOMaterialRetainCurrent() {
  return OOMaterial::current();
}

void OOMaterialApplyNone() { OOMaterial::applyNone(); }

void OOMaterialApplyAndRelease(std::shared_ptr<OOMaterial> material) {
  if (material != nullptr) material->apply();  // a message to nil did nothing
}

void OOMaterial::ensureFinishedLoading() {}

bool OOMaterial::isFinishedLoading() { return true; }

void OOMaterial::setBindingTarget(Entity* /*target*/) {}

bool OOMaterial::wantsNormalsAsTextureCoordinates() { return false; }

#if OO_MULTITEXTURE
std::size_t OOMaterial::countOfTextureUnitsWithBaseCoordinates() { return 1; }
#endif

#ifdef OO_DEBUG_MONITOR_ENABLED
std::vector<std::shared_ptr<OOTexture>> OOMaterial::allTextures() { return {}; }
#endif

bool OOMaterial::doApply() {
  OOLogGenericSubclassResponsibility();
  return false;
}

void OOMaterial::unapplyWithNext(OOMaterial* /*next*/) {
  // Do nothing.
}

void OOMaterial::willDealloc() {
  if (EXPECT_NOT(ActiveMaterial().get() == this)) {
    OO_LOG("shader.dealloc.imbalance", "{}",
           "***** Material deallocated while active, indicating a "
           "retain/release imbalance.");
    unapplyWithNext(nullptr);
    // = nil, not released: it is being deallocated. The reference is moved
    // into a holder that is never deleted.
    (void)new std::shared_ptr<OOMaterial>(std::move(ActiveMaterial()));
  }
}

/*	OOMaterialAutorelease(): the material goes to the innermost
   oo::AutoreleaseScope, whose drain releases it where the keeper object that
   held it was released.
*/
void OOMaterialAutorelease(std::shared_ptr<OOMaterial> material) {
  if (material == nullptr) return;
  oo::autorelease(std::move(material));
}
