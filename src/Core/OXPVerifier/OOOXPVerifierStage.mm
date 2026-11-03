/*

OOOXPVerifierStage.m


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

#import "OOOXPVerifierStageInternal.h"

#if OO_OXP_VERIFIER_ENABLED

#import "OOFoundationBridge.h"

@interface OOOXPVerifierStage (OOPrivate)

- (void)registerDepedent:(OOOXPVerifierStage*)dependent;
- (void)dependencyCompleted:(OOOXPVerifierStage*)dependency;
- (void)notifyDependents;

@end

// Adding a stage to a set of stages: identity, no duplicates, nil ignored.
namespace {

void AddStage(std::vector<oo::ObjCRef<OOOXPVerifierStage*>>& stages, OOOXPVerifierStage* stage)
{
    if (stage == nil)
        return;
    if (std::find(stages.begin(), stages.end(), stage) == stages.end())
        stages.emplace_back(stage);
}

} // namespace

@implementation OOOXPVerifierStage

- (id)init
{
    self = [super init];

    if (self != nil) {
        _canRun = NO;
    }

    return self;
}

// OOObject's -description wraps this as "<Class 0x...>{"name"}", which is what this class's own
// -description printed.
- (id)descriptionComponents
{
    return oo::NSStringFrom("\"" + oo::DescriptionOf([self name]) + "\"");
}

- (OOOXPVerifier*)verifier
{
    return [[_verifier retain] autorelease];
}

- (BOOL)completed
{
    return _hasRun;
}

- (id)name
{
    OOLogGenericSubclassResponsibility();
    return nil;
}

- (id)dependencies
{
    return nil;
}

- (id)dependents
{
    return nil;
}

- (BOOL)shouldRun
{
    return YES;
}

- (void)run
{
    OOLogGenericSubclassResponsibility();
}

@end

@implementation OOOXPVerifierStage (OOInternal)

- (void)setVerifier:(OOOXPVerifier*)verifier
{
    _verifier = verifier; // Not retained.
}

- (BOOL)isDependentOf:(OOOXPVerifierStage*)stage
{
    if (stage == nil)
        return NO;

    // Direct dependency check.
    if (std::find(_dependencies.begin(), _dependencies.end(), stage) != _dependencies.end())
        return YES;

    // Recursive dependency check.
    for (const auto& directDep : _dependencies) {
        if ([directDep.get() isDependentOf:stage])
            return YES;
    }

    return NO;
}

- (void)registerDependency:(OOOXPVerifierStage*)dependency
{
    AddStage(_dependencies, dependency);
    AddStage(_incompleteDependencies, dependency);

    [dependency registerDepedent:self];
}

- (BOOL)canRun
{
    return _canRun;
}

- (void)performRun
{
    assert(_canRun && !_hasRun);

    OOLogPushIndent();
    @try {
        [self run];
    }
    @catch (NSException* exception) {
        OOLog(@"verifyOXP.exception", @"***** Exception while running verification stage \"%@\": %@", [self name], exception);
    }
    OOLogPopIndent();

    _hasRun = YES;
    _canRun = NO;
    [self notifyDependents];
}

- (void)noteSkipped
{
    assert(_canRun && !_hasRun);

    _hasRun = YES;
    _canRun = NO;
    [self notifyDependents];
}

- (void)dependencyRegistrationComplete
{
    _canRun = _incompleteDependencies.empty();
}

- (std::vector<oo::ObjCRef<OOOXPVerifierStage*>>)resolvedDependencies
{
    return _dependencies;
}

- (std::vector<oo::ObjCRef<OOOXPVerifierStage*>>)resolvedDependents
{
    return _dependents;
}

@end

@implementation OOOXPVerifierStage (OOPrivate)

- (void)registerDepedent:(OOOXPVerifierStage*)dependent
{
    assert(![self isDependentOf:dependent]);

    AddStage(_dependents, dependent);
}

- (void)dependencyCompleted:(OOOXPVerifierStage*)dependency
{
    const auto where = std::find(_incompleteDependencies.begin(), _incompleteDependencies.end(), dependency);
    if (where != _incompleteDependencies.end())
        _incompleteDependencies.erase(where);
    if (_incompleteDependencies.empty())
        _canRun = YES;
}

// -makeObjectsPerformSelector:withObject: over the dependents: each is told once, in the order
// they registered.
- (void)notifyDependents
{
    const std::vector<oo::ObjCRef<OOOXPVerifierStage*>> dependents = _dependents;
    for (const auto& dependent : dependents) {
        [dependent.get() dependencyCompleted:self];
    }
}

@end

#endif // OO_OXP_VERIFIER_ENABLED
