/*

OOOXPVerifierStage.m


Copyright (C) 2007-2012 Jens Ayton

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

@interface OOOXPVerifierStage (OOPrivate)

- (void)registerDepedent:(OOOXPVerifierStage *)dependent;
- (void)dependencyCompleted:(OOOXPVerifierStage *)dependency;

@end


@implementation OOOXPVerifierStage

- (id)init
{
	self = [super init];
	
	if (self != nil)
	{
		_dependencies = [[NSMutableSet alloc] init];
		_incompleteDependencies = [[NSMutableSet alloc] init];
		_dependents = [[NSMutableSet alloc] init];
		_canRun = NO;
	}
	
	return self;
}


- (void)dealloc
{
	[_dependencies release];
	[_incompleteDependencies release];
	[_dependents release];
	
	[super dealloc];
}


- (id)description
{
	return [NSString stringWithFormat:@"<%@ %p>{\"%@\"}", [self class], self, [self name]];
}


- (OOOXPVerifier *)verifier
{
	return [[_verifier retain] autorelease];
}


- (BOOL)completed
{
	return _hasRun;
}


- (NSString *)name
{
	OOLogGenericSubclassResponsibility();
	return nil;
}


- (NSSet *)dependencies
{
	return nil;
}


- (NSSet *)dependents
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

- (void)setVerifier:(OOOXPVerifier *)verifier
{
	_verifier = verifier;	// Not retained.
}


- (BOOL)isDependentOf:(OOOXPVerifierStage *)stage
{
	NSEnumerator			*directDepEnum = nil;
	OOOXPVerifierStage		*directDep = nil;
	
	if (stage == nil)  return NO;
	
	// Direct dependency check.
	if ([_dependencies containsObject:stage])  return YES;
	
	// Recursive dependency check.
	for (directDepEnum = [_dependencies objectEnumerator]; (directDep = [directDepEnum nextObject]); )
	{
		if ([directDep isDependentOf:stage])  return YES;
	}
	
	return NO;
}


- (void)registerDependency:(OOOXPVerifierStage *)dependency
{
	[_dependencies addObject:dependency];
	[_incompleteDependencies addObject:dependency];
	
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
	@try
	{
		[self run];
	}
	@catch (NSException *exception)
	{
		OOLog(@"verifyOXP.exception", @"***** Exception while running verification stage \"%@\": %@", [self name], exception);
	}
	OOLogPopIndent();
	
	_hasRun = YES;
	_canRun = NO;
	[_dependents makeObjectsPerformSelector:@selector(dependencyCompleted:) withObject:self];
}


- (void)noteSkipped
{
	assert(_canRun && !_hasRun);
	
	_hasRun = YES;
	_canRun = NO;
	[_dependents makeObjectsPerformSelector:@selector(dependencyCompleted:) withObject:self];
}


- (void)dependencyRegistrationComplete
{
	_canRun = [_incompleteDependencies count] == 0;
}


- (NSSet *)resolvedDependencies
{
	return _dependencies;
}


- (NSSet *)resolvedDependents
{
	return _dependents;
}

@end


@implementation OOOXPVerifierStage (OOPrivate)

- (void)registerDepedent:(OOOXPVerifierStage *)dependent
{
	assert(![self isDependentOf:dependent]);
	
	[_dependents addObject:dependent];
}


- (void)dependencyCompleted:(OOOXPVerifierStage *)dependency
{
	[_incompleteDependencies removeObject:dependency];
	if ([_incompleteDependencies count] == 0)  _canRun = YES;
}

@end

#endif	//OO_OXP_VERIFIER_ENABLED
