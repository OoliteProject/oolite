/*

OOMaterial+ObjCBridge.mm

TRANSITIONAL (proposed ADR-0056, amendment oo-smy): the Objective-C OOMaterial facade (see
OOMaterial+ObjCBridge.h). Every method forwards to its C++ member: arguments that were
OOMaterial * go through oo::ToCxx, results come back through oo::ToObjC. An Objective-C
subclass's C++ part is an oo::ObjCMaterial (OOMaterial+ObjCBridge.h), whose virtual members
message the subclass. Deleted with
OOMaterial+ObjCBridge.h.


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

#import "OODescription.h"
#import "OOMaterial.h"
#include "oofnd/String.hpp"
#include "oofnd/objc/OOObjCPeer.h"
#include "oofnd/objc/OORuntime.h"

#include <cstdlib>
#include <cxxabi.h>
#include <typeinfo>

namespace {

// Never destroyed: a facade may be released while the process exits.
oo::ObjCPeers& Peers()
{
    static oo::ObjCPeers* peers = new oo::ObjCPeers;
    return *peers;
}

std::string DemangledName(const std::type_info& type)
{
    int status = 0;
    char* demangled = abi::__cxa_demangle(type.name(), nullptr, nullptr, &status);
    std::string result = (status == 0 && demangled != nullptr) ? demangled : type.name();
    std::free(demangled);
    return result;
}

// The C++ class's name, as [self class] named an Objective-C material's class ("cxx::" dropped).
std::string ClassName(cxx::OOMaterial& material)
{
    std::string result = DemangledName(typeid(material));
    if (result.starts_with("cxx::"))
        result.erase(0, 5);
    return result;
}

// A class's (first) base class, from the Itanium C++ ABI's type information; null for none.
const std::type_info* BaseOf(const std::type_info& type)
{
    if (const auto* single = dynamic_cast<const abi::__si_class_type_info*>(&type))
        return single->__base_type;
    if (const auto* multiple = dynamic_cast<const abi::__vmi_class_type_info*>(&type)) {
        return multiple->__base_count > 0 ? multiple->__base_info[0].__base_type : nullptr;
    }
    return nullptr;
}

/*	The class of a C++ material's facade. A C++ class in namespace cxx has a facade of its own
        (ADR-0056 item 5): the Objective-C class of the same name, a subclass of this one, which its
        callers message by its own selectors (cxx::OOBasicMaterial's is OOBasicMaterial; ADR-0056
        amendment of bead oo-up4b, item 3). A class without one (a global C++ class) is seen as its
        nearest base class that has one, so a global subclass of cxx::OOBasicMaterial still answers the
        basic material's selectors (amendment oo-vl43); failing that, as an OOMaterial.
*/
Class FacadeClass(cxx::OOMaterial& material)
{
    for (const std::type_info* type = &typeid(material); type != nullptr; type = BaseOf(*type)) {
        const std::string name = DemangledName(*type);
        if (!name.starts_with("cxx::"))
            continue;
        Class facade = OOClassFromName(std::string_view(name).substr(5));
        if (facade != Nil && [facade isSubclassOfClass:[OOMaterial class]])
            return facade;
    }
    return [OOMaterial class];
}

} // namespace

@implementation OOMaterial

// Inside the @implementation for the private ivar.
OOMaterial* oo::ToObjC(cxx::OOMaterial* material)
{
    if (oo::ObjCMaterialLink* objCMaterial = oo::AsObjCMaterial(material))
        return [[objCMaterial->owner() retain] autorelease];
    if (material == nullptr)
        return nil;
    Class facadeClass = FacadeClass(*material);
    return Peers().peerFor(material, [material, facadeClass] { return [[facadeClass alloc] initWithCxxMaterial:material]; });
}

oo::ObjCMaterialLink* oo::AsObjCMaterial(cxx::OOMaterial* material)
{
    return dynamic_cast<ObjCMaterialLink*>(material);
}

cxx::OOMaterial* oo::ToCxx(OOMaterial* material)
{
    if (material == nil)
        return nullptr;
    return material->_cxxMaterial.get();
}

// An Objective-C material: [[X alloc] init] of a subclass (or of this class).
- (id)init
{
    self = [super init];
    if (self != nil)
        _cxxMaterial = oo::makeRef<oo::ObjCMaterial<cxx::OOMaterial>>(self);
    return self;
}

// A C++ material's facade (oo::ToObjC), or an intermediate class's Objective-C material (its initialisers).
- (id)initWithCxxMaterial:(cxx::OOMaterial*)material
{
    self = [super init];
    if (self != nil)
        _cxxMaterial = oo::Ref<cxx::OOMaterial>(material);
    return self;
}

// A converted class's facade initialiser: the new C++ material, and this is its peer.
- (id)initWithNewCxxMaterial:(const oo::Ref<cxx::OOMaterial>&)material
{
    self = [super init];
    if (self != nil) {
        _cxxMaterial = material;
        @autoreleasepool {
            Peers().peerFor(_cxxMaterial.get(), [self] { return [self retain]; });
        }
    }
    return self;
}

- (void)dealloc
{
    if (oo::ObjCMaterialLink* objCMaterial = oo::AsObjCMaterial(_cxxMaterial.get())) {
        // Ensure cleanup happens; doing it more than once is safe.
        [self willDealloc];
        objCMaterial->ownerDeallocated();
    } else
        Peers().forget(_cxxMaterial.get());

    [super dealloc];
}

// On an Objective-C material this is reached only when the subclass does not override it, or by
// [super ...]: its nearest converted superclass's own member answers (through the adapter's
// super...() members). On a C++ material's facade the C++ override does.
- (std::optional<std::string>)cxx_descriptionComponents
{
    if (oo::ObjCMaterialLink* objCMaterial = oo::AsObjCMaterial(_cxxMaterial.get()))
        return objCMaterial->superDescriptionComponents();
    return _cxxMaterial->descriptionComponents();
}

// A C++ material's facade describes itself with the C++ class's name.
- (std::optional<std::string>)cxx_description
{
    if (oo::AsObjCMaterial(_cxxMaterial.get()) != nullptr)
        return [super cxx_description];
    std::string result = oo::str::format("<%s %s>", ClassName(*_cxxMaterial).c_str(), oo::str::pointerDescription(self).c_str());
    if (const std::optional<std::string> components = _cxxMaterial->descriptionComponents())
        result += "{" + *components + "}";
    return result;
}

+ (void)setUp
{
    cxx::OOMaterial::setUp();
}
+ (void)applyNone
{
    cxx::OOMaterial::applyNone();
}
+ (OOMaterial*)current
{
    return oo::ToObjC(cxx::OOMaterial::current());
}

// The overridable methods: the same two cases as -cxx_descriptionComponents.

- (void)apply
{
    if (oo::ObjCMaterialLink* objCMaterial = oo::AsObjCMaterial(_cxxMaterial.get()))
        objCMaterial->superApply();
    else
        _cxxMaterial->apply();
}

- (std::optional<std::string>)cxx_name
{
    if (oo::ObjCMaterialLink* objCMaterial = oo::AsObjCMaterial(_cxxMaterial.get()))
        return objCMaterial->superName();
    return _cxxMaterial->name();
}

- (void)ensureFinishedLoading
{
    if (oo::ObjCMaterialLink* objCMaterial = oo::AsObjCMaterial(_cxxMaterial.get()))
        objCMaterial->superEnsureFinishedLoading();
    else
        _cxxMaterial->ensureFinishedLoading();
}

- (BOOL)isFinishedLoading
{
    if (oo::ObjCMaterialLink* objCMaterial = oo::AsObjCMaterial(_cxxMaterial.get()))
        return objCMaterial->superIsFinishedLoading();
    return _cxxMaterial->isFinishedLoading();
}

- (void)setBindingTarget:(id<OOWeakReferenceSupport>)target
{
    if (oo::ObjCMaterialLink* objCMaterial = oo::AsObjCMaterial(_cxxMaterial.get()))
        objCMaterial->superSetBindingTarget(target);
    else
        _cxxMaterial->setBindingTarget(target);
}

- (BOOL)wantsNormalsAsTextureCoordinates
{
    if (oo::ObjCMaterialLink* objCMaterial = oo::AsObjCMaterial(_cxxMaterial.get()))
        return objCMaterial->superWantsNormalsAsTextureCoordinates();
    return _cxxMaterial->wantsNormalsAsTextureCoordinates();
}

#if OO_MULTITEXTURE
- (NSUInteger)countOfTextureUnitsWithBaseCoordinates
{
    if (oo::ObjCMaterialLink* objCMaterial = oo::AsObjCMaterial(_cxxMaterial.get()))
        return objCMaterial->superCountOfTextureUnitsWithBaseCoordinates();
    return _cxxMaterial->countOfTextureUnitsWithBaseCoordinates();
}
#endif

#ifdef OO_DEBUG_MONITOR_ENABLED
- (std::vector<oo::ObjCRef<OOTexture*>>)cxx_allTextures
{
    if (oo::ObjCMaterialLink* objCMaterial = oo::AsObjCMaterial(_cxxMaterial.get()))
        return objCMaterial->superAllTextures();
    return _cxxMaterial->allTextures();
}
#endif

- (BOOL)doApply
{
    if (oo::ObjCMaterialLink* objCMaterial = oo::AsObjCMaterial(_cxxMaterial.get()))
        return objCMaterial->superDoApply();
    return _cxxMaterial->doApply();
}

- (void)unapplyWithNext:(OOMaterial*)next
{
    if (oo::ObjCMaterialLink* objCMaterial = oo::AsObjCMaterial(_cxxMaterial.get()))
        objCMaterial->superUnapplyWithNext(oo::ToCxx(next));
    else
        _cxxMaterial->unapplyWithNext(oo::ToCxx(next));
}

- (void)willDealloc
{
    _cxxMaterial->willDealloc();
}

@end
