/*

OOSingleTextureMaterial.h


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

#import "OOSingleTextureMaterial.h"
#import "OOTexture.h"
#import "OOCollectionExtractors.h"
#import "OOFunctionAttributes.h"


@implementation OOSingleTextureMaterial

- (id)initWithName:(NSString *)name configuration:(NSDictionary *)configuration
{
	id					texSpec = nil;
	
	if (configuration != nil)
	{
		texSpec = [configuration oo_textureSpecifierForKey:@"diffuse_map" defaultName:name];
	}
	else
	{
		texSpec = name;
	}
	
	return [self initWithName:name
					  texture:[OOTexture textureWithConfiguration:texSpec]
				configuration:configuration];
}


- (id) initWithName:(NSString *)name texture:(OOTexture *)texture configuration:(NSDictionary *)configuration
{
	if (name != nil && texture != nil)
	{
		self = [super initWithName:name configuration:configuration];
		if (self != nil)
		{
			_texture = [texture retain];
		}
	}
	else
	{
		DESTROY(self);
	}

	
	return self;
}


- (void)dealloc
{
	[self willDealloc];
	[_texture release];
	
	[super dealloc];
}


- (NSString *) descriptionComponents
{
	return [_texture description];
}


- (BOOL)doApply
{
	if (EXPECT_NOT(![super doApply]))  return NO;
	
	[_texture apply];
	return YES;
}


- (void)unapplyWithNext:(OOMaterial *)next
{
	if (![next isKindOfClass:[OOSingleTextureMaterial class]])  [OOTexture applyNone];
	[super unapplyWithNext:next];
}


- (void)ensureFinishedLoading
{
	[_texture ensureFinishedLoading];
}


- (BOOL) isFinishedLoading
{
	return [_texture isFinishedLoading];
}


- (BOOL) wantsNormalsAsTextureCoordinates
{
	return [_texture isCubeMap];
}


#ifndef NDEBUG
- (NSSet *) allTextures
{
	return [NSSet setWithObject:_texture];
}
#endif

@end
