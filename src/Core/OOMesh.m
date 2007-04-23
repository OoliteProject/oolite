/*

OOMesh.m

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

#import "OOMesh.h"
#import "OOMeshDATSupport.h"
#import "OOMacroOpenGL.h"
#import "OOFunctionAttributes.h"
#import "OOCacheManager.h"
#import "ResourceManager.h"
#import "OOCollectionExtractors.h"
#import "OOMaterial.h"


static NSString * const	kOOMeshDataCacheKey			= @"OOMesh data";

static NSString * const	kCacheRepVertexCountKey		= @"vertex count";
static NSString * const	kCacheRepPositionsKey		= @"positions";
static NSString * const	kCacheRepNormalsKey			= @"normals";
static NSString * const	kCacheRepTexCoordsKey		= @"texture co-ordinates";
static NSString * const	kCacheRepMaterialGroupsKey	= @"material groups";


@interface OOMesh (OOCaching)

- (id)initWithCacheRepresentation:(id)cacheRep materialDictionary:(NSDictionary *)materialDict shadersDictionary:(NSDictionary *)shadersDict name:(NSString *)name shaderMacros:(NSDictionary *)macros shaderBindingTarget:(id<OOWeakReferenceSupport>)object;
- (id)cacheRepresentation;

@end


@implementation OOMesh

+ (id)meshWithName:(NSString *)name materialDictionary:(NSDictionary *)materialDict shadersDictionary:(NSDictionary *)shadersDict smooth:(BOOL)smooth shaderMacros:(NSDictionary *)macros shaderBindingTarget:(id<OOWeakReferenceSupport>)object
{
	id					result = nil;
	id					cacheRep = nil;
	OOCacheManager		*cache = nil;
	NSString			*path = nil;
	
	if (EXPECT_NOT(name == nil))  return nil;
	
	/*	Note on caching:
		we cache mesh data, but not mesh objects. This is because it’s
		possible for multiple copies of a mesh to exist with different
		material specifications.
		
		This is assumed to be sufficiently rare that sharing mesh data between
		mesh objects is not useful.
		
		Caching combinations of mesh object and material specification should
		be handled by ship definitions. Since there is no ship definition
		class at the moment, this is not the case.
	*/
	
	cache = [OOCacheManager sharedCache];
	cacheRep = [cache objectForKey:name inCache:kOOMeshDataCacheKey];
	if (cacheRep != nil)
	{
		result = [[[self alloc] initWithCacheRepresentation:cacheRep
										 materialDictionary:materialDict
										  shadersDictionary:shadersDict
													   name:name
											   shaderMacros:macros
										shaderBindingTarget:object] autorelease];
		if (result == nil)  [cache removeObjectForKey:name inCache:kOOMeshDataCacheKey];
	}
	
	if (result == nil)
	{
		// Either no cache, or failed to load cache
		path = [ResourceManager pathForFileNamed:name inFolder:@"Models"];
		if (path == nil && [[path pathExtension] length] == 0)
		{
			// Implicitly add .dat extension for futureproofing...
			path = [ResourceManager pathForFileNamed:[name stringByAppendingPathExtension:@"dat"] inFolder:@"Models"];
		}
		if (path != nil)
		{
			result = [self meshWithDATFile:path
									  name:name
						materialDictionary:materialDict
						 shadersDictionary:shadersDict
							  shaderMacros:macros
					   shaderBindingTarget:object];
		}
		else
		{
			OOLog(kOOLogFileNotFound, @"***** Error: could not find model named \"%@\".", name);
		}
	}
	
	return result;
}


- (void)dealloc
{
	OO_ENTER_OPENGL();
	
	[name release];
	
	if (positions != NULL)  free(positions);
	if (normals != NULL)  free(normals);
	if (texCoords != NULL)  free(texCoords);
	
	OOMeshMaterialGroupFreeMultiple(materialGroups, materialGroupCount);
	
	if (displayList != 0)  glDeleteLists(displayList, 1);
	
	[super dealloc];
}


- (NSString *)description
{
	return [NSString stringWithFormat:@"<%@ %p>{\"%@\", %u material groups; %u vertices, %u faces}", [self class], self, name, materialGroupCount, [self vertexCount], [self faceCount]];
}


- (size_t)vertexCount
{
	return vertexCount;
}


- (size_t)faceCount
{
	size_t					i, j;
	OOMeshMaterialGroup		*materialGroup = NULL;
	OOMeshPrimitive			*primitive = NULL;
	GLsizei					primCount;
	size_t					count = 0;
	
	for (i = 0; i != materialGroupCount; ++i)
	{
		materialGroup = materialGroups[i];
		for (j = 0; j != materialGroup->primitiveCount; ++j)
		{
			primitive = materialGroup->primitives[j];
			primCount = primitive->count;
			
			switch (primitive->mode)
			{
				case GL_TRIANGLE_STRIP:
				case GL_TRIANGLE_FAN:
					count += primCount - 2;
					break;
				
				case GL_TRIANGLES:
					count += primCount / 3;
					break;
				
				default:
					OOLog(@"mesh.faceCount.unknownMode", @"Unknown primitive mode %u, face count will be off.", primitive->mode);
			}
		}
	}
	
	return count;
}

@end


@implementation OOMesh (OOCaching)


- (id)initWithCacheRepresentation:(id)cacheRep materialDictionary:(NSDictionary *)materialDict shadersDictionary:(NSDictionary *)shadersDict name:(NSString *)name shaderMacros:(NSDictionary *)macros shaderBindingTarget:(id<OOWeakReferenceSupport>)object
{
	NSData					*positionsData = nil;
	NSData					*normalsData = nil;
	NSData					*texCoordsData = nil;
	size_t					size;
	NSDictionary			*materialGroupsDict = nil;
	NSEnumerator			*materialGroupEnum = nil;
	NSString				*materialKey = nil;
	OOMaterial				*material = nil;
	NSArray					*primitivesArray = nil;
	NSEnumerator			*primitiveEnum = nil;
	NSData					*primitiveData = nil;
	size_t					i, j;
	
	self = [super init];
	if (self == nil)  goto FAIL;
	
	if (![cacheRep isKindOfClass:[NSDictionary class]])  goto FAIL;
	
	// Load vertex count.
	vertexCount = [cacheRep unsignedLongForKey:kCacheRepVertexCountKey defaultValue:-1UL];
	if (vertexCount == -1UL)  goto FAIL;
	
	// Load positions, normals and texCoords, ensure all are defined and all have the right length.
	positionsData = [cacheRep dataForKey:kCacheRepPositionsKey defaultValue:nil];
	size = [positionsData length];
	if (positionsData == nil || size != (vertexCount * sizeof (Vector)))  goto FAIL;
	positions = malloc(size);
	if (positions == NULL)  goto FAIL;
	memcpy(positions, positionsData, size);
	
	normalsData = [cacheRep dataForKey:kCacheRepNormalsKey defaultValue:nil];
	size = [normalsData length];
	if (normalsData == nil || size != (vertexCount * sizeof (Vector)))  goto FAIL;
	normals = malloc(size);
	if (normals == NULL)  goto FAIL;
	memcpy(normals, normalsData, size);
	
	texCoordsData = [cacheRep dataForKey:kCacheRepTexCoordsKey defaultValue:nil];
	size = [texCoordsData length];
	if (texCoordsData == nil || size != (vertexCount * sizeof (OOMeshTexCoords)))  goto FAIL;
	normals = malloc(size);
	if (texCoords == NULL)  goto FAIL;
	memcpy(texCoords, texCoordsData, size);
	
	// Load material groups
	materialGroupsDict = [cacheRep dictionaryForKey:kCacheRepMaterialGroupsKey defaultValue:nil];
	if (materialGroupsDict == nil)  goto FAIL;
	
	materialGroupCount = [materialGroupsDict count];
	materialGroups = calloc(sizeof *materialGroups, materialGroupCount);
	if (materialGroups == NULL) goto FAIL;
	
	i = 0;
	for (materialGroupEnum = [materialGroupsDict keyEnumerator]; (materialKey = [materialGroupEnum nextObject]); )
	{
		primitivesArray = [materialGroupsDict arrayForKey:materialKey defaultValue:nil];
		if (primitivesArray == nil)  goto FAIL;
		
		material = [OOMaterial materialWithName:materialKey materialDictionary:materialDict shadersDictionary:shadersDict macros:macros bindingTarget:object];
		if (material == nil)  goto FAIL;
		
		materialGroups[i] = OOMeshMaterialGroupAlloc([primitivesArray count]);
		materialGroups[i]->materialKey = [materialKey copy];
		materialGroups[i]->material = [material retain];
		
		j = 0;
		for (primitiveEnum = [primitivesArray objectEnumerator]; (primitiveData = [primitiveEnum nextObject]); )
		{
			if (![primitiveData isKindOfClass:[NSData class]])  goto FAIL;
			
			size = [primitiveData length];
			if (size < sizeof (OOMeshPrimitive))  goto FAIL;
			
			materialGroups[i]->primitives[j] = malloc(size);
			if (materialGroups[i]->primitives[j] != NULL)  goto FAIL;
			
			memcpy(materialGroups[i]->primitives[j], [primitiveData bytes], size);
			if (size != OOMeshPrimitiveSize(materialGroups[i]->primitives[j]))  goto FAIL;
			
#if GL_ARB_vertex_buffer_object
			materialGroups[i]->primitives[j]->VBO = 0;
#endif
			++j;
		}
		
		++i;
	}
	
	return self;
	
FAIL:
	[self release];
	return nil;
}


- (id)cacheRepresentation
{
	NSData					*positionsData = nil;
	NSData					*normalsData = nil;
	NSData					*texCoordsData = nil;
	NSMutableDictionary		*materialGroupsDict = nil;
	size_t					i, j;
	OOMeshMaterialGroup		*materialGroup = NULL;
	NSMutableArray			*primitivesArray = nil;
	OOMeshPrimitive			*primitive = NULL;
	NSData					*primitiveData = nil;
	
	// Sanity check.
	if (EXPECT_NOT(vertexCount == 0 || materialGroupCount == 0 || positions == NULL || normals == NULL || texCoords == NULL || materialGroups == NULL))  return nil;
	
	// Start with the easy stuff.
	positionsData = [NSData dataWithBytes:positions length:vertexCount * sizeof *positions];
	normalsData = [NSData dataWithBytes:normals length:vertexCount * sizeof *normals];
	texCoordsData = [NSData dataWithBytes:texCoords length:vertexCount * sizeof *texCoords];
	
	if (positionsData == nil || normalsData == nil || texCoordsData == nil)  return nil;
	
	/*	Build material groups dictionary. This is a dictionary of material key
		to array of primitives. The primitives themselves are represented as
		data. Note that OOMeshPrimitive is a varaible-size struct!
	*/
	materialGroupsDict = [NSMutableDictionary dictionaryWithCapacity:materialGroupCount];
	for (i = 0; i != materialGroupCount; ++i)
	{
		materialGroup = materialGroups[i];
		primitivesArray = [NSMutableArray arrayWithCapacity:materialGroup->primitiveCount];
		for (j = 0; j != materialGroup->primitiveCount; ++j)
		{
			primitive = materialGroup->primitives[j];
			primitiveData = [NSData dataWithBytes:primitive length:OOMeshPrimitiveSize(primitive)];
			if (primitiveData == nil)  return nil;
			[primitivesArray addObject:primitiveData];
		}
		
		if ([primitivesArray count] != materialGroup->primitiveCount)  return nil;
		[materialGroupsDict setObject:primitivesArray forKey:materialGroup->materialKey];
	}
	if ([materialGroupsDict count] != materialGroupCount)  return nil;
	
	// Merge it into a dictionary.
	return [NSDictionary dictionaryWithObjectsAndKeys:
						[NSNumber numberWithUnsignedInt:vertexCount], kCacheRepVertexCountKey,
						positionsData, kCacheRepPositionsKey,
						normalsData, kCacheRepNormalsKey,
						texCoordsData, kCacheRepTexCoordsKey,
						materialGroupsDict, kCacheRepMaterialGroupsKey];
}

@end


void OOMeshPrimitiveFindStartAndEnd(OOMeshPrimitive *primitive)
{
	GLsizei					i;
	unsigned long			curr, start, end;
	
	if (EXPECT_NOT(primitive == nil))  return;
	
	if (EXPECT_NOT(primitive->count == 0))
	{
		primitive->start = 0;
		primitive->end = 0;
		return;
	}
	
	start = ULONG_MAX;
	end = 0;
	
	for (i = 0; i != primitive->count; ++i)
	{
		curr = primitive->indicies[i];
		if (curr < start)  start = curr;
		if (end < curr)  end = curr;
	}
	
	primitive->start = start;
	primitive->end = end;
}


void OOMeshMaterialGroupFree(OOMeshMaterialGroup *materialGroup)
{
	size_t					i;
	OOMeshPrimitive			*primitive = NULL;
	
#if GL_ARB_vertex_buffer_object
	OO_ENTER_OPENGL();
#endif
	
	if (EXPECT_NOT(materialGroup == NULL))  return;
	
	for (i = 0; i != materialGroup->primitiveCount; ++i)
	{
		primitive = materialGroup->primitives[i];
#if GL_ARB_vertex_buffer_object
		if (primitive->VBO != 0)  glDeleteBuffersARB(1, &primitive->VBO);
#endif
		if (primitive != NULL)  free(primitive);
	}
	
	[materialGroup->materialKey release];
	[materialGroup->material release];
	
	free(materialGroup);
}


void OOMeshMaterialGroupFreeMultiple(OOMeshMaterialGroup **materialGroups, size_t count)
{
	size_t					i;
	
	if (EXPECT_NOT(materialGroups == NULL))  return;
	
	for (i = 0; i != count; ++i)
	{
		OOMeshMaterialGroupFree(materialGroups[i]);
	}
	
	free(materialGroups);
}
