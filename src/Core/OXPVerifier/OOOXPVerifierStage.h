/*

OOOXPVerifierStage.h

Pipeline stage for OXP verification pipeline managed by OOOXPVerifier.


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

#include "oofnd/StdLib.hpp"
#include "oofnd/objc/OOObjCRef.h"

/*	Foundation sweep (proposed ADR-0043, bead oo-84h8): the resolved stage sets are vectors of
        retained stages (identity, no duplicates), in registration order. -name and -dependencies
        are shared with Foundation and keep Objective-C object results next to their twins;
        -dependents is std::optional<std::vector<std::string>> (bead oo-3rb.274.1).
*/
@interface OOOXPVerifierStage : OOObject {
@private
    OOOXPVerifier* _verifier;
    std::vector<oo::ObjCRef<OOOXPVerifierStage*>> _dependencies;
    std::vector<oo::ObjCRef<OOOXPVerifierStage*>> _incompleteDependencies;
    std::vector<oo::ObjCRef<OOOXPVerifierStage*>> _dependents;
    BOOL _canRun, _hasRun;
}

- (OOOXPVerifier*)verifier;
- (BOOL)completed;

// Subclass responsibilities:

/*	Name of stage. Used for display and for dependency resolution; must be
        unique. The name should be a phrase describing what will be done, like
        "Scanning files" or "Verifying plist scripts".
*/
- (id)name; // shared selector (Foundation declares -name too): -cxx_name as an Objective-C string, or nil
- (std::optional<std::string>)cxx_name; // nullopt: none (bead oo-3rb.289.1)

/*	Dependencies and dependents:
        -dependencies returns a set of names of stages that must be run before this
        one. If it contains the name of a stage that's not registered, this stage
        cannot run.
        -dependents returns a set of names of stages that should not be run before
        this one. Unlike -dependencies, these are considered non-critical.
*/
- (id)dependencies; // shared selector (Foundation declares -dependencies too): -cxx_dependencies as an Objective-C set of strings, or nil
- (std::optional<std::vector<std::string>>)cxx_dependencies; // nullopt: none (nil); override this (bead oo-3rb.291.3)
- (std::optional<std::vector<std::string>>)dependents; // stage names; nullopt: none (nil)

/*	This is called once by the verifier.
        When it is called, all the verifier stages listed in -requiredStages will
        have run. At this point, it is possible to access them using the
        verifier's -stageWithName: method in order to query them about results.
        Stages whose dependencies have all run will be released, so the result of
        calling -stageWithName: with a name not in -requiredStages is undefined.

        shouldRun can be overridden to avoid running at all (without anything
        being logged). For dependency resolution purposes, returning NO from
        shouldRun counts as running; that is, it will stop this verifier stage
        from running but will not stop dependencies from running.
*/
- (BOOL)shouldRun;
- (void)run;

@end

#endif
