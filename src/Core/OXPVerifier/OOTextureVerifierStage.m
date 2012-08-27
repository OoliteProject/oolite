/*

OOTextureVerifierStage.m


Oolite
Copyright (C) 2004-2012 Giles C Williams and contributors

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
	}
	return self;
}


- (void)dealloc
{
	[_usedTextures release];
	
	[super dealloc];
}


+ (NSString *)nameForReverseDependencyForVerifier:(OOOXPVerifier *)verifier
{
	return kStageName;
}


- (NSString *)name
{
	return kStageName;
}


- (BOOL)shouldRun
{
	return [_usedTextures count] != 0 || [[[self verifier] fileScannerStage] filesInFolder:@"Images"] != nil;
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
	
	// All "images" are considered used, since we don't have a reasonable way to look for images referenced in JavaScript scripts.
	nameEnum = [[[[self verifier] fileScannerStage] filesInFolder:@"Images"] objectEnumerator];
	while ((name = [nameEnum nextObject]))
	{
		[self checkTextureNamed:name inFolder:@"Images"];
	}
}


- (void) textureNamed:(NSString *)name usedInContext:(NSString *)context
{
	OOFileScannerVerifierStage	*fileScanner = nil;
	
	if (name == nil)  return;
	if ([_usedTextures containsObject:name])  return;
	[_usedTextures addObject:name];
	
	fileScanner = [[self verifier] fileScannerStage];
	if (![fileScanner fileExists:name
						inFolder:@"Textures"
				  referencedFrom:context
					checkBuiltIn:YES])
	{
		OOLog(@"verifyOXP.texture.notFound", @"----- WARNING: texture \"%@\" referenced in %@ could not be found in %@ or in Oolite.", name, context, [[self verifier] oxpDisplayName]);
	}
}

@end


@implementation OOTextureVerifierStage (OOPrivate)

- (void)checkTextureNamed:(NSString *)name inFolder:(NSString *)folder
{
	OOTextureLoader				*loader = nil;
	NSString					*path = nil;
	OOFileScannerVerifierStage	*fileScanner = nil;
	NSString					*displayName = nil;
	OOPixMapDimension			rWidth, rHeight;
	BOOL						success;
	OOPixMap					pixmap;
	OOTextureDataFormat			format;
	
	fileScanner = [[self verifier] fileScannerStage];
	path = [fileScanner pathForFile:name
						   inFolder:folder
					 referencedFrom:nil
					   checkBuiltIn:NO];
	
	if (path == nil)  return;
	
	loader = [OOTextureLoader loaderWithPath:path
									 options:kOOTextureMinFilterNearest |
											 kOOTextureMinFilterNearest |
											 kOOTextureNoShrink |
											 kOOTextureNoFNFMessage |
											 kOOTextureNeverScale];
	
	displayName = [fileScanner displayNameForFile:name andFolder:folder];
	if (loader == nil)
	{
		OOLog(@"verifyOXP.texture.failed", @"***** ERROR: image %@ could not be read.", displayName);
	}
	else
	{
		success = [loader getResult:&pixmap format:&format originalWidth:NULL originalHeight:NULL];
		
		if (success)
		{
			rWidth = OORoundUpToPowerOf2_PixMap((2 * pixmap.width) / 3);
			rHeight = OORoundUpToPowerOf2_PixMap((2 * pixmap.height) / 3);
			if (pixmap.width != rWidth || pixmap.height != rHeight)
			{
				OOLog(@"verifyOXP.texture.notPOT", @"----- WARNING: image %@ has non-power-of-two dimensions; it will have to be rescaled (from %ux%u pixels to %ux%u pixels) at runtime.", displayName, pixmap.width, pixmap.height, rWidth, rHeight);
			}
			else
			{
				OOLog(@"verifyOXP.verbose.texture.OK", @"- %@ (%ux%u px) OK.", displayName, pixmap.width, pixmap.height);
			}
			
			OOFreePixMap(&pixmap);
		}
		else
		{
			OOLog(@"verifyOXP.texture.failed", @"***** ERROR: texture loader failed to load %@.", displayName);
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


@implementation OOOXPVerifier(OOTextureVerifierStage)

- (OOTextureVerifierStage *)textureVerifierStage
{
	return [self stageWithName:kStageName];
}

@end

#endif
