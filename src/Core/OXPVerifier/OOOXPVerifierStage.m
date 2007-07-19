/*

OOOXPVerifierStage.m


Oolite
Copyright (C) 2004-2007 Giles C Williams and contributors

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
MA 02110-1301, USA.


This file may also be distributed under the MIT/X11 license:

Copyright (C) 2007 Jens Ayton

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

*/

#import "OOOXPVerifierStageInternal.h"

#if OO_OXP_VERIFIER_ENABLED

@interface OOOXPVerifierStage (OOPrivate)

- (void)registerDepedent:(OOOXPVerifierStage *)dependent;
- (void)dependencyCompleted:(OOOXPVerifierStage *)dependency;

@end


@implementation OOOXPVerifierStage

- (void)dealloc
{
	[_dependencies release];
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


- (NSSet *)requiredStages
{
	return [NSSet set];
}


- (BOOL)shouldRun
{
	return YES;
}


- (void)run
{
	OOLogGenericSubclassResponsibility();
}


- (BOOL)needsPostRun
{
	return NO;
}


- (void)postRun
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
	if ([_dependencies member:stage] != nil)  return YES;
	
	// Recursive dependency check.
	for (directDepEnum = [_dependencies objectEnumerator]; (directDep = [directDepEnum nextObject]); )
	{
		if ([directDep isDependentOf:stage])  return YES;
	}
	
	return NO;
}


- (void)registerDependency:(OOOXPVerifierStage *)dependency
{
	if (_dependencies == nil)  _dependencies = [[NSMutableSet alloc] init];
	[_dependencies addObject:dependency];
	if (_incompleteDependencies == nil)  _incompleteDependencies = [[NSMutableSet alloc] init];
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
	NS_DURING
		[self run];
	NS_HANDLER
		OOLog(@"verifyOXP.exception", @"***** Exception while running verification stage \"%@\": %@", [self name], localException);
	NS_ENDHANDLER
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


- (NSSet *)dependencies
{
	return _dependencies;
}


- (NSSet *)dependents
{
	return _dependents;
}

@end


@implementation OOOXPVerifierStage (OOPrivate)

- (void)registerDepedent:(OOOXPVerifierStage *)dependent
{
	assert(![self isDependentOf:dependent]);
	
	if (_dependents == nil)  _dependents = [[NSMutableSet alloc] init];
	[_dependents addObject:dependent];
}


- (void)dependencyCompleted:(OOOXPVerifierStage *)dependency
{
	[_incompleteDependencies removeObject:dependency];
	if ([_incompleteDependencies count] == 0)  _canRun = YES;
}

@end

#endif	//OO_OXP_VERIFIER_ENABLED
