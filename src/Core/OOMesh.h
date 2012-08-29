/*

OOMesh.h

Standard OODrawable for static meshes from DAT files. OOMeshes are immutable
(and can therefore be shared). Avoid the temptation to add externally-visible
mutator methods as it will break such sharing. (Sharing will be implemented
when ship types are turned into objects instead of dictionaries; this is
currently slated for post-1.70. -- Ahruman)

Hmm. On further consideration, sharing will be problematic because of material
bindings. Two possible solutions: separate mesh data into shared object with
each mesh instance having its own set of materials but shared data, or
retarget bindings each frame. -- Ahruman


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

#import "OODrawable.h"
#import "OOOpenGL.h"
#import "OOWeakReference.h"
#import "OOOpenGLExtensionManager.h"

@class OOMaterial, Octree;


#define OOMESH_PROFILE	0
#if OOMESH_PROFILE
@class OOProfilingStopwatch;
#endif


enum
{
	kOOMeshMaxMaterials			= 8
};


typedef uint16_t			OOMeshSmoothGroup;
typedef uint8_t				OOMeshMaterialIndex, OOMeshMaterialCount;
typedef uint32_t			OOMeshVertexCount;
typedef uint32_t			OOMeshFaceCount;
typedef uint8_t				OOMeshFaceVertexCount;


typedef struct
{
	OOMeshSmoothGroup		smoothGroup;
	OOMeshMaterialIndex		materialIndex;
	GLuint					vertex[3];
	
	Vector					normal;
	Vector					tangent;
	GLfloat					s[3];
	GLfloat					t[3];
} OOMeshFace;


typedef struct
{
	GLint					*indexArray;
	GLfloat					*textureUVArray;
	Vector					*vertexArray;
	Vector					*normalArray;
	Vector					*tangentArray;
	
	GLuint					count;
} OOMeshDisplayLists;


@interface OOMesh: OODrawable <NSCopying>
{
@private
	uint8_t					_normalMode: 2,
							brokenInRender: 1,
							listsReady: 1;
	
	OOMeshMaterialCount		materialCount;
	OOMeshVertexCount		vertexCount;
	OOMeshFaceCount			faceCount;
	
	NSString				*baseFile;
	
	Vector					*_vertices;
	Vector					*_normals;
	Vector					*_tangents;
	OOMeshFace				*_faces;
	
	// Redundancy! Needs fixing.
	OOMeshDisplayLists		_displayLists;
	
	NSRange					triangle_range[kOOMeshMaxMaterials];
	NSString				*materialKeys[kOOMeshMaxMaterials];
	OOMaterial				*materials[kOOMeshMaxMaterials];
	GLuint					displayList0;
	
	GLfloat					collisionRadius;
	GLfloat					maxDrawDistance;
	BoundingBox				boundingBox;
	
	Octree					*octree;
	
	NSMutableDictionary		*_retainedObjects;
	
	NSDictionary			*_materialDict;
	NSDictionary			*_shadersDict;
	NSString				*_cacheKey;
	NSDictionary			*_shaderMacros;
	id						_shaderBindingTarget;

	Vector					_lastPosition;
	OOMatrix				_lastRotMatrix;
	BoundingBox				_lastBoundingBox;
	
#if OO_MULTITEXTURE
	NSUInteger				_textureUnitCount;
#endif
	
#if OOMESH_PROFILE
	OOProfilingStopwatch	*_stopwatch;
	double					_stopwatchLastTime;
#endif
}

+ (instancetype) meshWithName:(NSString *)name
					 cacheKey:(NSString *)cacheKey
		   materialDictionary:(NSDictionary *)materialDict
			shadersDictionary:(NSDictionary *)shadersDict
					   smooth:(BOOL)smooth
				 shaderMacros:(NSDictionary *)macros
		  shaderBindingTarget:(id<OOWeakReferenceSupport>)object;

+ (OOMaterial *) placeholderMaterial;

- (NSString *) modelName;

- (void) rebindMaterials;

- (NSDictionary *) materials;
- (NSDictionary *) shaders;

- (size_t) vertexCount;
- (size_t) faceCount;

- (Octree *) octree;

// This needs a better name.
- (BoundingBox) findBoundingBoxRelativeToPosition:(Vector)opv
											basis:(Vector)ri :(Vector)rj :(Vector)rk
									 selfPosition:(Vector)position
										selfBasis:(Vector)si :(Vector)sj :(Vector)sk;
- (BoundingBox) findSubentityBoundingBoxWithPosition:(Vector)position rotMatrix:(OOMatrix)rotMatrix;

- (OOMesh *) meshRescaledBy:(GLfloat)scaleFactor;
- (void) copyVertexArray;

@end


#import "OOCacheManager.h"
@interface OOCacheManager (Octree)

+ (Octree *)octreeForModel:(NSString *)inKey;
+ (void)setOctree:(Octree *)inOctree forModel:(NSString *)inKey;

@end
