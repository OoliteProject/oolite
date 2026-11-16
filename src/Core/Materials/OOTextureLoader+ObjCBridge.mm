/*

OOTextureLoader+ObjCBridge.mm

TRANSITIONAL (proposed ADR-0056, amendments oo-whzh, oo-bj8 and oo-zl36): the Objective-C
OOTextureLoader facade over cxx::OOTextureLoader, and the adapter that is an Objective-C loader's
C++ part. Every method forwards in one line. Deleted, with OOTextureLoader+ObjCBridge.h, by the
bridge's deletion bead.


Copyright (C) 2007-2014 Jens Ayton

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
#import "OOTextureLoader.h"
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

// The C++ class's name, as [self class] named an Objective-C loader's class ("cxx::" dropped).
std::string ClassName(cxx::OOTextureLoader& loader)
{
    std::string result = DemangledName(typeid(loader));
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

/*	The class of a C++ loader's facade. A C++ class in namespace cxx that has a facade of its own
        is that Objective-C class, a subclass of this one (cxx::OOTextureGenerator's is
        OOTextureGenerator; amendment oo-up4b item 3). A class without one (a global C++ class) is seen
        as its nearest base class that has one, so a global subclass of cxx::OOTextureGenerator is an
        OOTextureGenerator to Objective-C (amendment oo-vl43 item 4); failing that, an OOTextureLoader.
*/
Class FacadeClass(cxx::OOTextureLoader& loader)
{
    for (const std::type_info* type = &typeid(loader); type != nullptr; type = BaseOf(*type)) {
        const std::string name = DemangledName(*type);
        if (!name.starts_with("cxx::"))
            continue;
        Class facade = OOClassFromName(std::string_view(name).substr(5));
        if (facade != Nil && [facade isSubclassOfClass:[OOTextureLoader class]])
            return facade;
    }
    return [OOTextureLoader class];
}

} // namespace

@interface OOTextureLoader (OOObjCBridgePrivate)

- (id)initWithCxxLoader:(cxx::OOTextureLoader*)loader;

@end

@implementation OOTextureLoader

// Inside the @implementation for the protected ivar.
OOTextureLoader* oo::ToObjC(cxx::OOTextureLoader* loader)
{
    if (oo::ObjCTextureLoaderLink* objCLoader = oo::AsObjCTextureLoader(loader))
        return [[objCLoader->owner() retain] autorelease];
    if (loader == nullptr)
        return nil;
    Class facadeClass = FacadeClass(*loader);
    return Peers().peerFor(loader, [loader, facadeClass] { return [[facadeClass alloc] initWithCxxLoader:loader]; });
}

cxx::OOTextureLoader* oo::ToCxx(OOTextureLoader* loader)
{
    if (loader == nil)
        return nullptr;
    return loader->_cxxLoader.get();
}

+ (id)cxx_loaderWithPath:(const std::optional<std::string>&)inPath options:(uint32_t)options
{
    return [[cxx::OOTextureLoader::loaderWithPath(inPath, options).get() retain] autorelease];
}

+ (id)cxx_loaderWithTextureSpecifier:(const oo::PList&)specifier extraOptions:(uint32_t)extraOptions folder:(const std::optional<std::string>&)folder
{
    return [[cxx::OOTextureLoader::loaderWithTextureSpecifier(specifier, extraOptions, folder).get() retain] autorelease];
}

// An Objective-C loader: [[X alloc] init] of a subclass (or of this class).
- (id)init
{
    self = [super init];
    if (self != nil)
        _cxxLoader = oo::makeRef<oo::ObjCTextureLoader<cxx::OOTextureLoader>>(self);
    return self;
}

// An Objective-C loader's designated initialiser: its C++ part, then the old body on it.
- (id)cxx_initWithPath:(const std::optional<std::string>&)inPath options:(uint32_t)options
{
    return [self cxx_initWithCxxLoader:oo::makeRef<oo::ObjCTextureLoader<cxx::OOTextureLoader>>(self) path:inPath options:options];
}

- (id)cxx_initWithCxxLoader:(const oo::Ref<cxx::OOTextureLoader>&)loader path:(const std::optional<std::string>&)inPath options:(uint32_t)options
{
    self = [super init];
    if (self == nil)
        return nil;
    _cxxLoader = loader;

    if (!_cxxLoader->initWithPath(inPath, options)) {
        [self release];
        return nil;
    }

    return self;
}

// A C++ loader's facade (oo::ToObjC).
- (id)initWithCxxLoader:(cxx::OOTextureLoader*)loader
{
    self = [super init];
    if (self != nil)
        _cxxLoader = oo::Ref<cxx::OOTextureLoader>(loader);
    return self;
}

// A converted subclass's facade, made by its initialiser: the new C++ loader, and this is its peer.
- (id)initWithNewCxxLoader:(const oo::Ref<cxx::OOTextureLoader>&)loader
{
    self = [super init];
    if (self != nil) {
        _cxxLoader = loader;
        @autoreleasepool {
            Peers().peerFor(_cxxLoader.get(), [self] { return [self retain]; });
        }
    }
    return self;
}

// The pixels not handed over are freed with the C++ part, after this.
- (void)dealloc
{
    if (oo::ObjCTextureLoaderLink* objCLoader = oo::AsObjCTextureLoader(_cxxLoader.get()))
        objCLoader->ownerDeallocated();
    else
        Peers().forget(_cxxLoader.get());
    [super dealloc];
}

// A C++ loader's facade describes itself with the C++ class's name and components.
- (std::optional<std::string>)cxx_description
{
    if (oo::AsObjCTextureLoader(_cxxLoader.get()) != nullptr)
        return [super cxx_description];
    std::string result = oo::str::format("<%s %s>", ClassName(*_cxxLoader).c_str(), oo::str::pointerDescription(self).c_str());
    if (const std::optional<std::string> components = _cxxLoader->descriptionComponents())
        result += "{" + *components + "}";
    return result;
}

/*	The descriptions. On an Objective-C loader that does not override them, its nearest converted
        class's own member answers; on a C++ loader's facade, the C++ override.
*/
- (std::optional<std::string>)cxx_descriptionComponents
{
    if (oo::ObjCTextureLoaderLink* objCLoader = oo::AsObjCTextureLoader(_cxxLoader.get()))
        return objCLoader->superDescriptionComponents();
    return _cxxLoader->descriptionComponents();
}

- (std::optional<std::string>)cxx_shortDescriptionComponents
{
    if (oo::ObjCTextureLoaderLink* objCLoader = oo::AsObjCTextureLoader(_cxxLoader.get()))
        return objCLoader->superShortDescriptionComponents();
    return _cxxLoader->shortDescriptionComponents();
}

- (std::optional<std::string>)cxx_path
{
    return _cxxLoader->path();
}

- (BOOL)isReady
{
    return _cxxLoader->isReady();
}

/*	The overridable methods. On an Objective-C loader these are reached only when the subclass
        does not override them, or by [super ...]: its nearest converted class's own member answers
        (the adapter's super...()). On a C++ loader's facade the C++ override answers.
*/

- (BOOL)getResult:(OOPixMap*)result
            format:(OOTextureDataFormat*)outFormat
     originalWidth:(uint32_t*)outWidth
    originalHeight:(uint32_t*)outHeight
{
    if (oo::ObjCTextureLoaderLink* objCLoader = oo::AsObjCTextureLoader(_cxxLoader.get()))
        return objCLoader->superGetResult(result, outFormat, outWidth, outHeight);
    return _cxxLoader->getResult(result, outFormat, outWidth, outHeight);
}

- (std::optional<std::string>)cxx_cacheKey
{
    if (oo::ObjCTextureLoaderLink* objCLoader = oo::AsObjCTextureLoader(_cxxLoader.get()))
        return objCLoader->superCacheKey();
    return _cxxLoader->cacheKey();
}

- (void)loadTexture
{
    if (oo::ObjCTextureLoaderLink* objCLoader = oo::AsObjCTextureLoader(_cxxLoader.get()))
        objCLoader->superLoadTexture();
    else
        _cxxLoader->loadTexture();
}

// OOAsyncWorkTask: the work manager sends these to the task, the Objective-C object.

- (void)performAsyncTask
{
    _cxxLoader->performAsyncTask();
}

- (void)completeAsyncTask
{
    _cxxLoader->completeAsyncTask();
}

@end
