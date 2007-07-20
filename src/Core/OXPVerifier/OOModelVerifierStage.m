/*

OOModelVerifierStage.m


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

*/

#import "OOModelVerifierStage.h"

#if OO_OXP_VERIFIER_ENABLED

#import "OOFileScannerVerifierStage.h"

static NSString * const kStageName	= @"Testing models";


@interface OOModelVerifierStage (OOPrivate)

- (void)checkModelNamed:(NSString *)name inFolder:(NSString *)folder;

@end


@implementation OOModelVerifierStage

- (id)init
{
	self = [super init];
	if (self != nil)
	{
		_usedModels = [[NSMutableSet alloc] init];
	}
	return self;
}


- (void)dealloc
{
	[_usedModels release];
	
	[super dealloc];
}


+ (NSString *)nameForReverseDependencyForVerifier:(OOOXPVerifier *)verifier
{
	OOModelVerifierStage *stage = [verifier stageWithName:kStageName];
	if (stage == nil)
	{
		stage = [[OOModelVerifierStage alloc] init];
		[verifier registerStage:stage];
		[stage release];
	}
	
	return kStageName;
}


- (NSString *)name
{
	return kStageName;
}


- (BOOL)shouldRun
{
	return [_usedModels count] != 0;
}


- (void)run
{
	NSEnumerator				*nameEnum = nil;
	NSString					*name = nil;
	NSAutoreleasePool			*pool = nil;
	
	OOLog(@"verifyOXP.models.unimplemented", @"TODO: implement model verifier.");
	
	for (nameEnum = [_usedModels objectEnumerator]; (name = [nameEnum nextObject]); )
	{
		pool = [[NSAutoreleasePool alloc] init];
		[self checkModelNamed:name inFolder:@"Models"];
		[pool release];
	}
	[_usedModels release];
	_usedModels = nil;
}


- (void) modelNamed:(NSString *)name usedInContext:(NSString *)context
{
	OOFileScannerVerifierStage	*fileScanner = nil;
	
	if ([_usedModels member:name] != nil)  return;
	[_usedModels addObject:name];
	
	fileScanner = [[self verifier] fileScannerStage];
	if (![fileScanner fileExists:name
						inFolder:@"Models"
				  referencedFrom:context
					checkBuiltIn:YES])
	{
		OOLog(@"verifyOXP.model.notFound", @"WARNING: model \"%@\" referenced in %@ could not be found in %@ or in Oolite.", name, context, [[self verifier] oxpDisplayName]);
	}
}

@end


@implementation OOModelVerifierStage (OOPrivate)

- (void)checkModelNamed:(NSString *)name inFolder:(NSString *)folder
{
	// FIXME: this should check DAT files.
}

@end

#endif
