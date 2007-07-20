/*

OOTextureVerifierStage.m


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

#import "OOTextureVerifierStage.h"

#if OO_OXP_VERIFIER_ENABLED

#import "OOTextureLoader.h"
#import "OOFileScannerVerifierStage.h"
#import "OOMaths.h"

static NSString * const kStageName	= @"Testing textures and images";


@interface OOTextureVerifierStage (OOPrivate)

- (void)checkTextureNamed:(NSString *)name inFolder:(NSString *)folder;

@end


@implementation OOTextureVerifierStage

- (id)init
{
	self = [super init];
	if (self != nil)
	{
		_usedTextures = [[NSMutableSet alloc] init];
		_usedImages = [[NSMutableSet alloc] init];
	}
	return self;
}


- (void)dealloc
{
	[_usedTextures release];
	[_usedImages release];
	
	[super dealloc];
}


+ (NSString *)nameForReverseDependencyForVerifier:(OOOXPVerifier *)verifier
{
	OOTextureVerifierStage *stage = [verifier stageWithName:kStageName];
	if (stage == nil)
	{
		stage = [[OOListUnusedFilesStage alloc] init];
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
	return [_usedTextures count] + [_usedImages count] != 0;
}


- (void)run
{
	NSEnumerator				*nameEnum = nil;
	NSString					*name = nil;
	NSAutoreleasePool			*pool = nil;
	
	for (nameEnum = [_usedTextures objectEnumerator]; (name = [nameEnum nextObject]); )
	{
		pool = [[NSAutoreleasePool alloc] init];
		[self checkTextureNamed:name inFolder:@"Textures"];
		[pool release];
	}
	[_usedTextures release];
	_usedTextures = nil;
	
	for (nameEnum = [_usedImages objectEnumerator]; (name = [nameEnum nextObject]); )
	{
		pool = [[NSAutoreleasePool alloc] init];
		[self checkTextureNamed:name inFolder:@"Images"];
		[pool release];
	}
	[_usedImages release];
	_usedImages = nil;
}


- (void) textureNamed:(NSString *)name usedInContext:(NSString *)context
{
	OOFileScannerVerifierStage	*fileScanner = nil;
	
	if ([_usedTextures member:name] != nil)  return;
	[_usedTextures addObject:name];
	
	fileScanner = [[self verifier] fileScannerStage];
	if (![fileScanner fileExists:name
						inFolder:@"Textures"
				  referencedFrom:context
					checkBuiltIn:YES])
	{
		OOLog(@"verifyOXP.texture.notFound", @"WARNING: texture \"%@\" referenced in %@ could not be found in %@ or in Oolite.", name, context, [[self verifier] oxpDisplayName]);
	}
}


- (void) imageNamed:(NSString *)name usedInContext:(NSString *)context
{
	OOFileScannerVerifierStage	*fileScanner = nil;
	
	if ([_usedImages member:name] != nil)  return;
	[_usedImages addObject:name];
	
	fileScanner = [[self verifier] fileScannerStage];
	if (![fileScanner fileExists:name
						inFolder:@"Images"
				  referencedFrom:context
					checkBuiltIn:YES])
	{
		OOLog(@"verifyOXP.texture.notFound", @"WARNING: image \"%@\" referenced in %@ could not be found in %@ or in Oolite.", name, context, [[self verifier] oxpDisplayName]);
	}
}

@end


@implementation OOTextureVerifierStage (OOPrivate)

- (void)checkTextureNamed:(NSString *)name inFolder:(NSString *)folder
{
	OOTextureLoader				*loader = nil;
	NSString					*path = nil;
	OOFileScannerVerifierStage	*fileScanner = nil;
	void						*data = nil;
	uint32_t					width, height, rWidth, rHeight;
	
	fileScanner = [[self verifier] fileScannerStage];
	path = [fileScanner pathForFile:name
						   inFolder:folder
					 referencedFrom:nil
					   checkBuiltIn:NO];
	
	if (path == nil)  return;
	
	loader = [OOTextureLoader loaderWithPath:name
									 options:kOOTextureMinFilterNearest |
											 kOOTextureMinFilterNearest |
											 kOOTextureNoShrink |
											 kOOTextureNoFNFMessage |
											 kOOTextureNeverScale];
	
	if (loader == nil)
	{
		OOLog(@"verifyOXP.texture.failed", @"ERROR: image %@ could not be read.", [fileScanner displayNameForFile:name andFolder:folder]);
	}
	else
	{
		[loader getResult:&data format:NULL width:&width height:&height];
		free(data);
		
		rWidth = OORoundUpToPowerOf2((2 * width) / 3);
		rHeight = OORoundUpToPowerOf2((2 * height) / 3);
		if (width != rWidth || height != rHeight)
		{
			OOLog(@"verifyOXP.texture.notPOT", @"WARNING: image %@ has non-power-of-two dimensions; it will have to be rescaled (from %ux%u pixels to %ux%u pixels) at runtime.", [fileScanner displayNameForFile:name andFolder:folder], width, height, rWidth, rHeight);
		}
	}
}

@end


@implementation OOTextureHandlingStage

- (NSSet *)dependents
{
	NSMutableSet *result = [[super dependents] mutableCopy];
	[result addObject:[OOTextureVerifierStage nameForReverseDependencyForVerifier:[self verifier]]];
	return [result autorelease];
}

@end

#endif
