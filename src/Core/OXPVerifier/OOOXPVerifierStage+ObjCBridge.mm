/*

OOOXPVerifierStage+ObjCBridge.mm

TRANSITIONAL (proposed ADR-0056 Amendment 1, bead oo-cwz): the Objective-C OOOXPVerifierStage
facade (see OOOXPVerifierStage+ObjCBridge.h). Every method forwards to its C++ member: arguments
that were OOOXPVerifierStage * go through oo::ToCxx, results come back through oo::ToObjC. An
Objective-C subclass's C++ part is an oo::ObjCStage (OOOXPVerifierStage+ObjCBridge.h), whose
virtual members message the subclass.
Deleted with OOOXPVerifierStage+ObjCBridge.h.


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

#import "OOOXPVerifierStageInternal.h"

#if OO_OXP_VERIFIER_ENABLED

#import "OODescription.h"
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

std::string DemangledName(cxx::OOOXPVerifierStage& stage)
{
    int status = 0;
    char* demangled = abi::__cxa_demangle(typeid(stage).name(), nullptr, nullptr, &status);
    std::string result = (status == 0 && demangled != nullptr) ? demangled : typeid(stage).name();
    std::free(demangled);
    return result;
}

// The C++ class's name, as [self class] named an Objective-C stage's class ("cxx::" dropped).
std::string ClassName(cxx::OOOXPVerifierStage& stage)
{
    std::string result = DemangledName(stage);
    if (result.starts_with("cxx::"))
        result.erase(0, 5);
    return result;
}

/*	The class of a C++ stage's facade. A C++ class in namespace cxx has a facade of its own
        (ADR-0056 item 5): the Objective-C class of the same name, a subclass of this one, which its
        callers message by its own selectors (cxx::OOFileScannerVerifierStage's is
        OOFileScannerVerifierStage). A global C++ class has none, and Objective-C sees it as an
        OOOXPVerifierStage.
*/
Class FacadeClass(cxx::OOOXPVerifierStage& stage)
{
    const std::string name = DemangledName(stage);
    if (name.starts_with("cxx::")) {
        Class facade = OOClassFromName(std::string_view(name).substr(5));
        if (facade != Nil && [facade isSubclassOfClass:[OOOXPVerifierStage class]])
            return facade;
    }
    return [OOOXPVerifierStage class];
}

} // namespace

@implementation OOOXPVerifierStage

// Inside the @implementation for the private ivar.
OOOXPVerifierStage* oo::ToObjC(cxx::OOOXPVerifierStage* stage)
{
    if (oo::ObjCStageLink* objCStage = oo::AsObjCStage(stage))
        return [[objCStage->owner() retain] autorelease];
    if (stage == nullptr)
        return nil;
    Class facadeClass = FacadeClass(*stage);
    return Peers().peerFor(stage, [stage, facadeClass] { return [[facadeClass alloc] initWithCxxStage:stage]; });
}

oo::ObjCStageLink* oo::AsObjCStage(cxx::OOOXPVerifierStage* stage)
{
    return dynamic_cast<ObjCStageLink*>(stage);
}

cxx::OOOXPVerifierStage* oo::ToCxx(OOOXPVerifierStage* stage)
{
    if (stage == nil)
        return nullptr;
    return stage->_cxxStage.get();
}

// An Objective-C stage: [[X alloc] init] of a subclass (or of this class).
- (id)init
{
    self = [super init];
    if (self != nil)
        _cxxStage = oo::makeRef<oo::ObjCStage<cxx::OOOXPVerifierStage>>(self);
    return self;
}

// A C++ stage's facade (oo::ToObjC), or an intermediate class's Objective-C stage (its -init).
- (id)initWithCxxStage:(cxx::OOOXPVerifierStage*)stage
{
    self = [super init];
    if (self != nil)
        _cxxStage = oo::Ref<cxx::OOOXPVerifierStage>(stage);
    return self;
}

- (void)dealloc
{
    if (oo::ObjCStageLink* objCStage = oo::AsObjCStage(_cxxStage.get()))
        objCStage->ownerDeallocated();
    else
        Peers().forget(_cxxStage.get());
    [super dealloc];
}

- (std::optional<std::string>)cxx_descriptionComponents
{
    return _cxxStage->descriptionComponents();
}

// A C++ stage's facade describes itself with the C++ class's name.
- (std::optional<std::string>)cxx_description
{
    if (oo::AsObjCStage(_cxxStage.get()) != nullptr)
        return [super cxx_description];
    return oo::str::format("<%s %s>{", ClassName(*_cxxStage).c_str(), oo::str::pointerDescription(self).c_str()) + _cxxStage->descriptionComponents().value_or("") + "}";
}

- (OOOXPVerifier*)verifier
{
    return _cxxStage->verifier();
}
- (BOOL)completed
{
    return _cxxStage->completed();
}

// The subclass responsibilities. On an Objective-C stage these are reached only when the subclass
// does not override them, or by [super ...]: the own member of its nearest C++ superclass answers
// (cxx::OOOXPVerifierStage's, or an intermediate class's). On a C++
// stage's facade the C++ override answers.

- (std::optional<std::string>)cxx_name
{
    if (oo::ObjCStageLink* objCStage = oo::AsObjCStage(_cxxStage.get()))
        return objCStage->superName();
    return _cxxStage->name();
}

- (std::optional<std::vector<std::string>>)cxx_dependencies
{
    if (oo::ObjCStageLink* objCStage = oo::AsObjCStage(_cxxStage.get()))
        return objCStage->superDependencies();
    return _cxxStage->dependencies();
}

- (std::optional<std::vector<std::string>>)dependents
{
    if (oo::ObjCStageLink* objCStage = oo::AsObjCStage(_cxxStage.get()))
        return objCStage->superDependents();
    return _cxxStage->dependents();
}

- (BOOL)shouldRun
{
    if (oo::ObjCStageLink* objCStage = oo::AsObjCStage(_cxxStage.get()))
        return objCStage->superShouldRun();
    return _cxxStage->shouldRun();
}

- (void)run
{
    if (oo::ObjCStageLink* objCStage = oo::AsObjCStage(_cxxStage.get()))
        objCStage->superRun();
    else
        _cxxStage->run();
}

@end

@implementation OOOXPVerifierStage (OOInternal)

- (void)setVerifier:(OOOXPVerifier*)verifier
{
    _cxxStage->setVerifier(verifier);
}
- (BOOL)isDependentOf:(OOOXPVerifierStage*)stage
{
    return _cxxStage->isDependentOf(oo::ToCxx(stage));
}
- (void)registerDependency:(OOOXPVerifierStage*)dependency
{
    _cxxStage->registerDependency(oo::ToCxx(dependency));
}
- (void)dependencyRegistrationComplete
{
    _cxxStage->dependencyRegistrationComplete();
}
- (BOOL)canRun
{
    return _cxxStage->canRun();
}
- (void)performRun
{
    _cxxStage->performRun();
}
- (void)noteSkipped
{
    _cxxStage->noteSkipped();
}

- (std::vector<oo::ObjCRef<OOOXPVerifierStage*>>)resolvedDependencies
{
    std::vector<oo::ObjCRef<OOOXPVerifierStage*>> result;
    for (const auto& stage : _cxxStage->resolvedDependencies())
        result.emplace_back(oo::ToObjC(stage));
    return result;
}

- (std::vector<oo::ObjCRef<OOOXPVerifierStage*>>)resolvedDependents
{
    std::vector<oo::ObjCRef<OOOXPVerifierStage*>> result;
    for (const auto& stage : _cxxStage->resolvedDependents())
        result.emplace_back(oo::ToObjC(stage));
    return result;
}

@end

#endif // OO_OXP_VERIFIER_ENABLED
