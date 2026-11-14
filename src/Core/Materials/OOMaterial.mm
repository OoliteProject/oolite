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

#import "OOMaterial.h"
#import "OOFunctionAttributes.h"
#import "OOLogging.h"

namespace cxx {

namespace {

    /*	The current material, retained. It holds the Objective-C object (an Objective-C material
            itself, or a C++ material's facade), because while any subclass is Objective-C that is what
            owns the whole material: an Objective-C material's C++ part does not retain it (proposed
            ADR-0056, amendment oo-smy). Never destroyed, as the static pointer was not.
    */
    oo::ObjCRef<::OOMaterial*>& ActiveMaterial()
    {
        static auto* active = new oo::ObjCRef<::OOMaterial*>;
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

std::optional<std::string> OOMaterial::name()
{
    OOLogGenericParameterError();
    return std::nullopt;
}

// Make this the current GL shader program.
void OOMaterial::apply()
{
    if (OOMaterial* active = oo::ToCxx(ActiveMaterial().get()))
        active->unapplyWithNext(this);
    ActiveMaterial() = nullptr;

    if (doApply()) {
        ActiveMaterial() = oo::ObjCRef<::OOMaterial*>(oo::ToObjC(this));
    }
}

void OOMaterial::applyNone()
{
    if (OOMaterial* active = oo::ToCxx(ActiveMaterial().get()))
        active->unapplyWithNext(nullptr);
    ActiveMaterial() = nullptr;
}

oo::Ref<OOMaterial> OOMaterial::current()
{
    return oo::Ref<OOMaterial>(oo::ToCxx(ActiveMaterial().get()));
}

void OOMaterial::ensureFinishedLoading()
{
}

bool OOMaterial::isFinishedLoading()
{
    return true;
}

void OOMaterial::setBindingTarget(id<OOWeakReferenceSupport> /*target*/)
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
std::vector<oo::ObjCRef<::OOTexture*>> OOMaterial::allTextures()
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
    if (EXPECT_NOT(oo::ToCxx(ActiveMaterial().get()) == this)) {
        OO_LOG("shader.dealloc.imbalance", "{}", "***** Material deallocated while active, indicating a retain/release imbalance.");
        unapplyWithNext(nullptr);
        (void)ActiveMaterial().leakRef(); // = nil: not released, it is being deallocated
    }
}

} // namespace cxx
