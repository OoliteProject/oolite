/*

OOOXPVerifierStage.h

Pipeline stage for OXP verification pipeline managed by OOOXPVerifier.

C++20 since bead oo-cwz, the Phase 3 class-HIERARCHY exemplar (proposed ADR-0056, Amendment 1;
docs/phases/3-cpp-conversion.md, "Converting a class"). The class is cxx::OOOXPVerifierStage and
its subclass responsibilities are virtual. While Objective-C subclasses and the Objective-C
OOOXPVerifier remain, OOOXPVerifierStage+ObjCBridge.h, imported at the end of this header, keeps
the Objective-C OOOXPVerifierStage they subclass and message; the bridge's deletion bead moves
the class out of namespace cxx.


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

#import "OOOXPVerifier.h"

#if OO_OXP_VERIFIER_ENABLED

#include "oofnd/Ref.hpp"
#include "oofnd/StdLib.hpp"

namespace cxx {

/*	Foundation sweep (proposed ADR-0043, bead oo-84h8): the resolved stage sets are vectors of
        retained stages (identity, no duplicates), in registration order.
*/
class OOOXPVerifierStage : public oo::RefCounted {
public:
    OOOXPVerifier* verifier();
    bool completed();

    // Subclass responsibilities:

    /*	Name of stage. Used for display and for dependency resolution; must be
            unique. The name should be a phrase describing what will be done, like
            "Scanning files" or "Verifying plist scripts".
    */
    virtual std::optional<std::string> name(); // nullopt: none (bead oo-3rb.289.1)

    /*	Dependencies and dependents:
            dependencies() returns a set of names of stages that must be run before this
            one. If it contains the name of a stage that's not registered, this stage
            cannot run.
            dependents() returns a set of names of stages that should not be run before
            this one. Unlike dependencies(), these are considered non-critical.
    */
    virtual std::optional<std::vector<std::string>> dependencies(); // nullopt: none (nil)
    virtual std::optional<std::vector<std::string>> dependents(); // stage names; nullopt: none (nil)

    /*	This is called once by the verifier.
            When it is called, all the verifier stages listed in dependencies() will
            have run. At this point, it is possible to access them using the
            verifier's -stageWithName: method in order to query them about results.
            Stages whose dependencies have all run will be released, so the result of
            calling -stageWithName: with a name not in dependencies() is undefined.

            shouldRun() can be overridden to avoid running at all (without anything
            being logged). For dependency resolution purposes, returning false from
            shouldRun() counts as running; that is, it will stop this verifier stage
            from running but will not stop dependencies from running.
    */
    virtual bool shouldRun();
    virtual void run();

    // What "%@" prints between the braces of <Class 0x...>{...} (OODescription.h): the quoted name.
    std::optional<std::string> descriptionComponents() const;

    /*	Internal: the interface between OOOXPVerifierStage and OOOXPVerifier (it was the
            OOInternal category, OOOXPVerifierStageInternal.h, which the facade still declares for
            the Objective-C verifier). Nothing else calls these.
    */
    void setVerifier(OOOXPVerifier* verifier);
    bool isDependentOf(OOOXPVerifierStage* stage);
    void registerDependency(OOOXPVerifierStage* dependency);
    void dependencyRegistrationComplete();

    bool canRun();

    void performRun();
    void noteSkipped();

    // These return sets of stages set up by registerDependency(), wheras dependencies()/dependents() return sets of names.
    std::vector<oo::Ref<OOOXPVerifierStage>> resolvedDependencies();
    std::vector<oo::Ref<OOOXPVerifierStage>> resolvedDependents();

private:
    void registerDepedent(OOOXPVerifierStage* dependent);
    void dependencyCompleted(OOOXPVerifierStage* dependency);
    void notifyDependents();

    OOOXPVerifier* _verifier = { }; // Not retained.
    std::vector<oo::Ref<OOOXPVerifierStage>> _dependencies = { };
    std::vector<oo::Ref<OOOXPVerifierStage>> _incompleteDependencies = { };
    std::vector<oo::Ref<OOOXPVerifierStage>> _dependents = { };
    bool _canRun = { }, _hasRun = { };
};

} // namespace cxx

// Transitional: the Objective-C OOOXPVerifierStage, for the verifier and the stages not yet
// converted. Deleted, with namespace cxx above, by the bridge's deletion bead.
#import "OOOXPVerifierStage+ObjCBridge.h"

#endif
