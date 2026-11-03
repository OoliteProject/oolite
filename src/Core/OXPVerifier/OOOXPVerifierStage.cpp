/*

OOOXPVerifierStage.mm

C++20 since bead oo-cwz, the Phase 3 class-hierarchy exemplar (proposed ADR-0056, Amendment 1).
Method bodies are the Objective-C ones with message sends turned into calls (ADR-0012); the
subclass responsibilities are virtual. Global since bead oo-9ht.4 deleted its facade. Still
Objective-C++ until Phase 4: the exceptions a stage raises are Objective-C objects (the
verifier it keeps is the C++ one since bead oo-qg71f).


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

#include <assert.h>

#include "OOOXPVerifierStage.h"
#include "oofnd/String.hpp"
#include "oofnd/objc/OOException.h"

#if OO_OXP_VERIFIER_ENABLED

#include "oofnd/Log.hpp"

#include <cstdlib>
#include <cxxabi.h>
#include <typeinfo>

// Adding a stage to a set of stages: identity, no duplicates, null ignored.
namespace {

void AddStage(std::vector<oo::Ref<OOOXPVerifierStage>>& stages, OOOXPVerifierStage* stage)
{
    if (stage == nullptr)
        return;
    if (std::find(stages.begin(), stages.end(), stage) == stages.end())
        stages.emplace_back(stage);
}

} // namespace

// OOObject's -description wraps this as "<Class 0x...>{"name"}", which is what this class's own
// -description printed. name() is a subclass's override, so it cannot be const.
std::optional<std::string> OOOXPVerifierStage::descriptionComponents() const
{
    return "\"" + const_cast<OOOXPVerifierStage*>(this)->name().value_or("(null)") + "\"";
}

// What the facade's -description printed (its -cxx_description, until bead oo-9ht.4).
std::string OOOXPVerifierStage::description() const
{
    return oo::str::format("<%s %s>{", className().c_str(), oo::str::pointerDescription(this).c_str()) + descriptionComponents().value_or("") + "}";
}

// The C++ class's name (the facade's ClassName(): demangled, "cxx::" dropped).
std::string OOOXPVerifierStage::className() const
{
    int status = 0;
    char* demangled = abi::__cxa_demangle(typeid(*this).name(), nullptr, nullptr, &status);
    std::string result = (status == 0 && demangled != nullptr) ? demangled : typeid(*this).name();
    std::free(demangled);
    if (result.starts_with("cxx::"))
        result.erase(0, 5);
    return result;
}

// The C++ verifier, borrowed (bead oo-qg71f; it was the Objective-C verifier, retained and
// autoreleased): the verifier keeps its stages and outlives them while they run.
OOOXPVerifier* OOOXPVerifierStage::verifier()
{
    return _verifier;
}

bool OOOXPVerifierStage::completed()
{
    return _hasRun;
}

std::optional<std::string> OOOXPVerifierStage::name()
{
    OOLogGenericSubclassResponsibility();
    return std::nullopt;
}

std::optional<std::vector<std::string>> OOOXPVerifierStage::dependencies()
{
    return std::nullopt;
}

std::optional<std::vector<std::string>> OOOXPVerifierStage::dependents()
{
    return std::nullopt;
}

bool OOOXPVerifierStage::shouldRun()
{
    return true;
}

void OOOXPVerifierStage::run()
{
    OOLogGenericSubclassResponsibility();
}

// Internal (was the OOInternal category).

void OOOXPVerifierStage::setVerifier(OOOXPVerifier* verifier)
{
    _verifier = verifier; // Not retained.
}

bool OOOXPVerifierStage::isDependentOf(OOOXPVerifierStage* stage)
{
    if (stage == nullptr)
        return false;

    // Direct dependency check.
    if (std::find(_dependencies.begin(), _dependencies.end(), stage) != _dependencies.end())
        return true;

    // Recursive dependency check.
    for (const auto& directDep : _dependencies) {
        if (directDep->isDependentOf(stage))
            return true;
    }

    return false;
}

void OOOXPVerifierStage::registerDependency(OOOXPVerifierStage* dependency)
{
    AddStage(_dependencies, dependency);
    AddStage(_incompleteDependencies, dependency);

    if (dependency != nullptr)
        dependency->registerDepedent(this);
}

bool OOOXPVerifierStage::canRun()
{
    return _canRun;
}

void OOOXPVerifierStage::performRun()
{
    assert(_canRun && !_hasRun);

    oo::log::pushIndent();
    try {
        run();
    } catch (...) {
        const auto exception = oo::CurrentOOException();
        if (!exception)
            throw; // not an OOException: it goes on up, as before
        // %@ of a Foundation exception printed GNUstep's -description, "<ClassName: 0x...> NAME:... REASON:...";
        // OOException has no -description, so the same layout is spelled out (proposed ADR-0037).
        OO_LOG("verifyOXP.exception", "***** Exception while running verification stage \"{}\": <OOException: {}> NAME:{} REASON:{}", name().value_or("(null)"), oo::str::pointerDescription(exception->object()), exception->name(), exception->reason());
    }
    oo::log::popIndent();

    _hasRun = true;
    _canRun = false;
    notifyDependents();
}

void OOOXPVerifierStage::noteSkipped()
{
    assert(_canRun && !_hasRun);

    _hasRun = true;
    _canRun = false;
    notifyDependents();
}

void OOOXPVerifierStage::dependencyRegistrationComplete()
{
    _canRun = _incompleteDependencies.empty();
}

std::vector<oo::Ref<OOOXPVerifierStage>> OOOXPVerifierStage::resolvedDependencies()
{
    return _dependencies;
}

std::vector<oo::Ref<OOOXPVerifierStage>> OOOXPVerifierStage::resolvedDependents()
{
    return _dependents;
}

// Private (was the OOPrivate category).

void OOOXPVerifierStage::registerDepedent(OOOXPVerifierStage* dependent)
{
    assert(!isDependentOf(dependent));

    AddStage(_dependents, dependent);
}

void OOOXPVerifierStage::dependencyCompleted(OOOXPVerifierStage* dependency)
{
    const auto where = std::find(_incompleteDependencies.begin(), _incompleteDependencies.end(), dependency);
    if (where != _incompleteDependencies.end())
        _incompleteDependencies.erase(where);
    if (_incompleteDependencies.empty())
        _canRun = true;
}

// -makeObjectsPerformSelector:withObject: over the dependents: each is told once, in the order
// they registered.
void OOOXPVerifierStage::notifyDependents()
{
    const std::vector<oo::Ref<OOOXPVerifierStage>> dependents = _dependents;
    for (const auto& dependent : dependents) {
        dependent->dependencyCompleted(this);
    }
}

#endif // OO_OXP_VERIFIER_ENABLED
