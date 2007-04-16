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

*/

#import "OOMesh.h"
#import "OOMacroOpenGL.h"
#import "OOFunctionAttributes.h"
#import "OOCacheManager.h"


enum
{
	kCacheDataFormatVersion			= 1UL,
	kCacheDataFormatTag				= 0x4F4F6D00UL | kCacheDataFormatVersion	// ASCII 'OOm' followed by version byte
};


static NSString * const		kOOMeshDataCacheKey = @"OOMesh data";

static NSMutableDictionary	*sInUseMeshes = nil;


@interface OOMesh (OOPrivate)

// Designated initializer. Mesh takes ownership of subMeshes, and expects it to be freeable.
- (id)initWithSubMeshes:(OOMeshSubMesh *)subMeshes count:(size_t)count name:(NSString *)name;

- (id)initWithName:(NSString *)name materialConfiguration:(NSDictionary *)materialConf name:(NSString *)name;
- (id)initWithCacheRepresentation:(id)cacheRep materialConfiguration:(NSDictionary *)materialConf name:(NSString *)name;

- (id)cacheRepresentation;

@end


@implementation OOMesh

+ (id)meshWithName:(NSString *)name materialConfiguration:(NSDictionary *)materialConf
{
	id					result = nil;
	id					cacheRep = nil;
	OOCacheManager		*cache = nil;
	
	if (EXPECT_NOT(name == nil))  return nil;
	
	result = [[sInUseMeshes objectForKey:name] retain];
	if (result == nil)
	{
		cache = [OOCacheManager sharedCache];
		cacheRep = [cache objectForKey:name inCache:kOOMeshDataCacheKey];
		if (cacheRep != nil)
		{
			result = [[self alloc] initWithCacheRepresentation:cacheRep materialConfiguration:materialConf name:name];
			if (result != nil)
			{
				cacheRep = [result cacheRepresentation];
				[cache setObject:cacheRep forKey:name inCache:kOOMeshDataCacheKey];
			}
		}
		if (result == nil)
		{
			result = [[self alloc] initWithName:name materialConfiguration:(NSDictionary *)materialConf name:name];
		}
		
		if (result != nil)
		{
			if (sInUseMeshes == nil)  sInUseMeshes = [[NSMutableDictionary alloc] init];
			[sInUseMeshes setObject:result forKey:name];
		}
	}
	
	return [result autorelease];
}


- (void)dealloc
{
	[sInUseMeshes removeObjectForKey:name];
	[name release];
	
	if (meshes != nil)  free(meshes);
	
	[super dealloc];
}

@end


@implementation OOMesh (OOPrivate)

/*
// Designated initializer. Mesh takes ownership of subMeshes, and expects it to be freeable.
- (id)initWithSubMeshes:(OOMeshSubMesh *)subMeshes count:(size_t)count name:(NSString *)name;

- (id)initWithName:(NSString *)name materialConfiguration:(NSDictionary *)materialConf name:(NSString *)name;
- (id)initWithCacheDataRepresentation:(NSData *)data materialConfiguration:(NSDictionary *)materialConf name:(NSString *)name;
*/

/*	Create cache representation.
	Cache representation consists of two parts: an array of material names,
	and a data object containing native-endian serialized mesh data.
*/
- (id)cacheRepresentation
{
	size_t				size;
	uint32_t			tag = kCacheDataFormatTag;
	size_t				i;
	size_t				vertexCount;
	size_t				partSize;
	char				*data = NULL, *curr = NULL;
	
	if (EXPECT_NOT(subMeshCount == 0 || meshes == NULL))  return nil;
	
	size = sizeof tag + sizeof subMeshCount + subMeshCount * sizeof (size_t);
	
	// Find size of each submesh
	for (i = 0; i != subMeshCount; ++i)
	{
		size += (sizeof (Vector) * 2 + sizeof (OOMeshTexCoords)) * meshes[i].vertexCount;
	}
	
	data = malloc(size);
	if (EXPECT_NOT(data == NULL))  return nil;
	
	/*	Set up data.
		Format is:
			tag					uint32_t
			subMeshCount		size_t
			[subMeshCount]:
				vertexCount		size_t
				vertices		vertexCount * Vector
				normals			vertexCount * Vector
				texCoords		vertexCount * OOMeshTexCoords
	*/
	curr = data;
	*(uint32_t *)curr = tag;
	curr += sizeof (tag);
	*(size_t *)curr = subMeshCount;
	curr += sizeof (subMeshCount);
	
	for (i = 0; i != subMeshCount; ++i)
	{
		vertexCount = meshes[i].vertexCount;
		
		*(size_t *)curr = vertexCount;
		curr += sizeof (size_t);
		
		partSize = vertexCount * sizeof (Vector);
		memcpy(curr, meshes[i].vertices, partSize);
		curr += partSize;
		
		memcpy(curr, meshes[i].normals, partSize);
		curr += partSize;
		
		partSize = vertexCount * sizeof (OOMeshTexCoords);
		memcpy(curr, meshes[i].texCoords, partSize);
		curr += partSize;
	}
	
	return [NSData dataWithBytesNoCopy:data length:size	freeWhenDone:YES];
}

@end
