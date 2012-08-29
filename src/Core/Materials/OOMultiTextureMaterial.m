/*

OOMultiTextureMaterial.m

 
Copyright (C) 2010-2012 Jens Ayton

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

#import "OOMultiTextureMaterial.h"
#import "OOCombinedEmissionMapGenerator.h"
#import "OOOpenGLExtensionManager.h"
#import "OOTexture.h"
#import "OOMacroOpenGL.h"
#import "NSDictionaryOOExtensions.h"
#import "OOMaterialSpecifier.h"

#if OO_MULTITEXTURE


@implementation OOMultiTextureMaterial

- (id)initWithName:(NSString *)name configuration:(NSDictionary *)configuration
{
	if (![[OOOpenGLExtensionManager sharedManager] textureCombinersSupported])
	{
		[self release];
		return nil;
	}
	
	NSDictionary *diffuseSpec = [configuration oo_diffuseMapSpecifierWithDefaultName:name];
	NSDictionary *emissionSpec = [configuration oo_emissionMapSpecifier];
	NSDictionary *illuminationSpec = [configuration oo_illuminationMapSpecifier];
	NSDictionary *emissionAndIlluminationSpec = [configuration oo_emissionAndIlluminationMapSpecifier];
	OOColor *diffuseColor = [configuration oo_diffuseColor];
	OOColor *emissionColor = nil;
	OOColor *illuminationColor = [configuration oo_illuminationModulateColor];
	
	NSMutableDictionary *mutableConfiguration = [NSMutableDictionary dictionaryWithDictionary:configuration];
	
	if (emissionSpec != nil || emissionAndIlluminationSpec != nil)
	{
		emissionColor = [configuration oo_emissionModulateColor];
		
		/*	If an emission map and an emission colour are both specified, stop
			the superclass (OOBasicMaterial) from applying the emission colour.
		*/
		[mutableConfiguration removeObjectForKey:kOOMaterialEmissionColorName];
		[mutableConfiguration removeObjectForKey:kOOMaterialEmissionColorLegacyName];
	}
	
	if ((self = [super initWithName:name configuration:mutableConfiguration]))
	{
		if (diffuseSpec != nil)
		{
			_diffuseMap = [[OOTexture textureWithConfiguration:diffuseSpec] retain];
			if (_diffuseMap != nil)  _unitsUsed++;
		}
		
		// Check for simplest cases, where we don't need to bake a derived emission map.
		if (emissionSpec != nil && illuminationSpec == nil && emissionAndIlluminationSpec == nil && emissionColor == nil)
		{
			_emissionMap = [[OOTexture textureWithConfiguration:emissionSpec] retain];
			if (_emissionMap != nil)  _unitsUsed++;
		}
		else
		{
			OOCombinedEmissionMapGenerator *generator = nil;
			
			if (emissionAndIlluminationSpec != nil)
			{
				OOTextureLoader *emissionAndIlluminationMap = [OOTextureLoader loaderWithTextureSpecifier:emissionAndIlluminationSpec
																							 extraOptions:0
																								   folder:@"Textures"];
				generator = [[OOCombinedEmissionMapGenerator alloc] initWithEmissionAndIlluminationMap:emissionAndIlluminationMap
																							diffuseMap:_diffuseMap
																						  diffuseColor:diffuseColor
																						 emissionColor:emissionColor
																					 illuminationColor:illuminationColor
																					  optionsSpecifier:emissionAndIlluminationSpec];
			}
			else
			{
				OOTextureLoader *emissionMap = [OOTextureLoader loaderWithTextureSpecifier:emissionSpec
																			  extraOptions:0
																					folder:@"Textures"];
				OOTextureLoader *illuminationMap = [OOTextureLoader loaderWithTextureSpecifier:illuminationSpec
																				  extraOptions:0
																						folder:@"Textures"];
				generator = [[OOCombinedEmissionMapGenerator alloc] initWithEmissionMap:emissionMap
																		  emissionColor:emissionColor
																			 diffuseMap:_diffuseMap
																		   diffuseColor:diffuseColor
																		illuminationMap:illuminationMap
																	  illuminationColor:illuminationColor
																	   optionsSpecifier:emissionSpec ?: illuminationSpec];
			}
			
			_emissionMap = [[OOTexture textureWithGenerator:[generator autorelease]] retain];
			if (_emissionMap != nil)  _unitsUsed++;
		}
	}
	
	return self;
}


- (void) dealloc
{
	[self willDealloc];
	
	DESTROY(_diffuseMap);
	DESTROY(_emissionMap);
	
	[super dealloc];
}


- (NSString *) descriptionComponents
{
	NSMutableArray *bits = [NSMutableArray array];
	if (_diffuseMap)  [bits addObject:[NSString stringWithFormat:@"diffuse map: %@", [_diffuseMap shortDescription]]];
	if (_emissionMap)  [bits addObject:[NSString stringWithFormat:@"emission map: %@", [_emissionMap shortDescription]]];
	
	NSString *result = [super descriptionComponents];
	if ([bits count] > 0)  result = [result stringByAppendingFormat:@" - %@", [bits componentsJoinedByString:@","]];
	return result;
}


- (NSUInteger) textureUnitCount
{
	return _unitsUsed;
}


- (NSUInteger) countOfTextureUnitsWithBaseCoordinates
{
	return _unitsUsed;
}


- (void) ensureFinishedLoading
{
	[_diffuseMap ensureFinishedLoading];
	[_emissionMap ensureFinishedLoading];
}


- (void) apply
{
	OO_ENTER_OPENGL();
	
	[super apply];
	
	GLenum textureUnit = GL_TEXTURE0_ARB;
	
	if (_diffuseMap != nil)
	{
		OOGL(glActiveTextureARB(textureUnit++));
		OOGL(glTexEnvi(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_COMBINE_ARB));
		OOGL(glTexEnvi(GL_TEXTURE_ENV, GL_COMBINE_RGB_ARB, GL_MODULATE));
		[_diffuseMap apply];
	}
	
	if (_emissionMap != nil)
	{
		OOGL(glActiveTextureARB(textureUnit++));
		OOGL(glTexEnvi(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_COMBINE_ARB));
		OOGL(glTexEnvi(GL_TEXTURE_ENV, GL_COMBINE_RGB_ARB, GL_ADD));
		[_emissionMap apply];
	}
	
	NSAssert2(textureUnit - GL_TEXTURE0_ARB == _unitsUsed, @"OOMultiTextureMaterial texture unit count invalid (expected %lu, actually using %u)", _unitsUsed, textureUnit - GL_TEXTURE0_ARB);
	
	if (textureUnit > GL_TEXTURE1_ARB)
	{
		OOGL(glActiveTextureARB(GL_TEXTURE0_ARB));
	}
}


- (void) unapplyWithNext:(OOMaterial *)next
{
	OO_ENTER_OPENGL();
	
	[super unapplyWithNext:next];
	
	NSUInteger i;
	i = [next isKindOfClass:[OOMultiTextureMaterial class]] ? [(OOMultiTextureMaterial *)next textureUnitCount] : 0;
	for (; i != _unitsUsed; ++i)
	{
		OOGL(glActiveTextureARB(GL_TEXTURE0_ARB + i));
		[OOTexture applyNone];
		OOGL(glTexEnvi(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_MODULATE));
	}
	OOGL(glActiveTextureARB(GL_TEXTURE0_ARB));
}


#ifndef NDEBUG
- (NSSet *) allTextures
{
	if (_diffuseMap == nil)  return [NSSet setWithObject:_emissionMap];
	return [NSSet setWithObjects:_diffuseMap, _emissionMap, nil];
}
#endif

@end

#endif	/* OO_MULTITEXTURE */
