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
#include "OOFunctionAttributes.h"
#include "OOLogging.h"
#include "OOMaterialState.h"
#include "oofnd/String.hpp"

#include "oofnd/Ref.hpp" // oo::autorelease (beads oo-pvhrh, oo-31u.7)
#include <cstdlib>
#include <cxxabi.h>
#include <typeinfo>

namespace {

/*	The current material, retained (proposed ADR-0056, amendments oo-smy item 4 and oo-9ht.8: it
        held the Objective-C object until the facade was deleted). Never destroyed, as the static
        pointer was not.
*/
oo::Ref<OOMaterial>& ActiveMaterial()
{
    static auto* active = new oo::Ref<OOMaterial>;
    return *active;
}

} // namespace

void OOMaterial::setUp()
{
    // I thought we'd need this, but the stuff I needed it for turned out to be problematic. Maybe in future. -- Ahruman
}

// name() is a subclass's override, so it cannot be const.
std::optional<std::string> OOMaterial::descriptionComponents() const
{
    return "\"" + const_cast<OOMaterial*>(this)->name().value_or("(null)") + "\""; // "%@" of the name, quoted
}

std::string OOMaterial::description() const
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

std::optional<std::string> OOMaterial::name()
{
    OOLogGenericParameterError();
    return std::nullopt;
}

// Make this the current GL shader program.
void OOMaterial::apply()
{
    if (OOMaterial* active = ActiveMaterial().get())
        active->unapplyWithNext(this);
    ActiveMaterial() = nullptr;

    if (doApply()) {
        ActiveMaterial() = oo::Ref<OOMaterial>(this);
    }
}

void OOMaterial::applyNone()
{
    if (OOMaterial* active = ActiveMaterial().get())
        active->unapplyWithNext(nullptr);
    ActiveMaterial() = nullptr;
}

oo::Ref<OOMaterial> OOMaterial::current()
{
    return ActiveMaterial();
}

// OOMaterialState.h: the slot for plain C++ translation units (bead oo-9ht.185).
OOMaterial* OOMaterialRetainCurrent()
{
    return OOMaterial::current().leakRef();
}

void OOMaterialApplyNone()
{
    OOMaterial::applyNone();
}

void OOMaterialApplyAndRelease(OOMaterial* material)
{
    if (material != nullptr)
        material->apply(); // a message to nil did nothing
    oo::release(material);
}

void OOMaterial::ensureFinishedLoading()
{
}

bool OOMaterial::isFinishedLoading()
{
    return true;
}

void OOMaterial::setBindingTarget(Entity* /*target*/)
{
}

bool OOMaterial::wantsNormalsAsTextureCoordinates()
{
    return false;
}

#if OO_MULTITEXTURE
NSUInteger OOMaterial::countOfTextureUnitsWithBaseCoordinates()
{
    return 1;
}
#endif

#ifdef OO_DEBUG_MONITOR_ENABLED
std::vector<oo::Ref<OOTexture>> OOMaterial::allTextures()
{
    return { };
}
#endif

bool OOMaterial::doApply()
{
    OOLogGenericSubclassResponsibility();
    return false;
}

void OOMaterial::unapplyWithNext(OOMaterial* /*next*/)
{
    // Do nothing.
}

void OOMaterial::willDealloc()
{
    if (EXPECT_NOT(ActiveMaterial().get() == this)) {
        OO_LOG("shader.dealloc.imbalance", "{}", "***** Material deallocated while active, indicating a retain/release imbalance.");
        unapplyWithNext(nullptr);
        (void)ActiveMaterial().leakRef(); // = nil: not released, it is being deallocated
    }
}

/*	OOMaterialAutorelease(): the material goes to the innermost oo::AutoreleaseScope, whose drain releases it
        where the keeper object that held it was released (beads oo-pvhrh, oo-31u.7).
*/
void OOMaterialAutorelease(oo::Ref<OOMaterial> material)
{
    if (material == nullptr)
        return;
    oo::autorelease(std::move(material));
}
