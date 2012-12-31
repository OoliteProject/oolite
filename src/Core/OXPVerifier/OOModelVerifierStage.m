/*

OOModelVerifierStage.m


Oolite
Copyright (C) 2004-2013 Giles C Williams and contributors

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

static id NSNULL = nil;


@interface OOModelVerifierStage (OOPrivate)

- (void)checkModel:(NSString *)name
		   context:(NSString *)context
		 materials:(NSDictionary *)materials
		   shaders:(NSDictionary *)shaders;

@end


@implementation OOModelVerifierStage

- (id)init
{
	self = [super init];
	if (self != nil)
	{
		NSNULL = [[NSNull null] retain];
		_modelsToCheck = [[NSMutableSet alloc] init];
	}
	return self;
}


- (void)dealloc
{
	[_modelsToCheck release];
	
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
	return [_modelsToCheck count] != 0;
}


- (void)run
{
	NSEnumerator				*nameEnum = nil;
	NSDictionary				*info = nil;
	NSAutoreleasePool			*pool = nil;
	NSString					*name = nil,
								*context = nil;
	NSDictionary				*materials = nil,
								*shaders = nil;
	
	OOLog(@"verifyOXP.models.unimplemented", @"TODO: implement model verifier.");
	
	for (nameEnum = [_modelsToCheck objectEnumerator]; (info = [nameEnum nextObject]); )
	{
		pool = [[NSAutoreleasePool alloc] init];
		
		name = [info objectForKey:@"name"];
		context = [info objectForKey:@"context"];
		if (context == NSNULL)  context = nil;
		materials = [info objectForKey:@"materials"];
		if (materials == NSNULL)  materials = nil;
		shaders = [info objectForKey:@"shaders"];
		if (shaders == NSNULL)  shaders = nil;
		
		[self checkModel:name
				 context:context
			   materials:materials
				 shaders:shaders];
		
		[pool release];
	}
	[_modelsToCheck release];
	_modelsToCheck = nil;
}


- (BOOL) modelNamed:(NSString *)name
	   usedForEntry:(NSString *)entryName
			 inFile:(NSString *)fileName
	  withMaterials:(NSDictionary *)materials
		 andShaders:(NSDictionary *)shaders
{
	OOFileScannerVerifierStage	*fileScanner = nil;
	NSDictionary				*info = nil;
	NSString					*context = nil;
	
	if (name == nil)  return NO;
	
	if (entryName != nil)  context = [NSString stringWithFormat:@"entry \"%@\" of %@", entryName, fileName];
	else context = fileName;
	
	fileScanner = [[self verifier] fileScannerStage];
	if (![fileScanner fileExists:name
						inFolder:@"Models"
				  referencedFrom:context
					checkBuiltIn:YES])
	{
		return NO;
	}
	
	if (context == nil)  context = NSNULL;
	if (materials == nil)  materials = NSNULL;
	if (shaders == nil)  shaders = NSNULL;
	
	info = [NSDictionary dictionaryWithObjectsAndKeys:
				name, @"name",
				context, @"context",
				materials, @"materials",
				shaders, @"shaders",
				nil];
	
	[_modelsToCheck addObject:info];
	
	return YES;
}

@end


@implementation OOModelVerifierStage (OOPrivate)


- (void)checkModel:(NSString *)name
				 context:(NSString *)context
			   materials:(NSDictionary *)materials
				 shaders:(NSDictionary *)shaders
{
	OOLog(@"verifyOXP.verbose.model.unimp", @"- Pretending to verify model %@ referenced in %@.", name, context);
	// FIXME: this should check DAT files.
}

@end


@implementation OOOXPVerifier(OOModelVerifierStage)

- (OOModelVerifierStage *)modelVerifierStage
{
	return [self stageWithName:kStageName];
}

@end

#endif
