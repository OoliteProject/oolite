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

#import "OODrawable.h"
#import "OOOpenGL.h"
#import "OOWeakReference.h"

@class OOMaterial, Octree;


enum
{
	kOOMeshMaxVertices			= 500,
	kOOMeshMaxFaces				= 800,
	kOOMeshMaxMaterials			= 8,
	kOOMeshMaxVertsPerFace		= 16,
	
	kOOMeshVARCount				= 16
};


typedef uint8_t				OOMeshSmoothGroup;
typedef uint8_t				OOMeshMaterialIndex, OOMeshMaterialCount;
typedef uint16_t			OOMeshVertexCount;
typedef uint16_t			OOMeshFaceCount;
typedef uint8_t				OOMeshFaceVertexCount;


typedef struct
{
	OOMeshSmoothGroup		smoothGroup;
	OOMeshMaterialIndex		materialIndex;
	OOMeshFaceVertexCount	n_verts;
	GLint					vertex[kOOMeshMaxVertsPerFace];
	
	Vector					normal;
	GLfloat					s[kOOMeshMaxVertsPerFace];
	GLfloat					t[kOOMeshMaxVertsPerFace];
} OOMeshFace;


typedef struct
{
	GLint					index_array[3 * kOOMeshMaxFaces];	// triangles
	GLfloat					texture_uv_array[3 * kOOMeshMaxFaces * 2];
	Vector					vertex_array[3 * kOOMeshMaxFaces];
	Vector					normal_array[3 * kOOMeshMaxFaces];
	
	int						n_triangles;	// Actually number of entries, i.e. triangle count * 3.
} EntityData;


@interface OOMesh: OODrawable <NSCopying>
{
	uint8_t					isSmoothShaded: 1,
							brokenInRender: 1,
							listsReady: 1;
	
	OOMeshMaterialCount		materialCount;
    OOMeshVertexCount		vertexCount;
	OOMeshFaceCount			faceCount;
    
    NSString				*baseFile;
	
    Vector					vertices[kOOMeshMaxVertices];
    Vector					normals[kOOMeshMaxVertices];
    OOMeshFace				faces[kOOMeshMaxFaces];
	
	EntityData				entityData;
	NSRange					triangle_range[kOOMeshMaxMaterials];
	NSString				*materialKeys[kOOMeshMaxMaterials];
	OOMaterial				*materials[kOOMeshMaxMaterials];
    GLuint					displayList0;
	
	GLfloat					collisionRadius;
	GLfloat					maxDrawDistance;
	BoundingBox				boundingBox;
	
	Octree					*octree;
}

+ (id)meshWithName:(NSString *)name
materialDictionary:(NSDictionary *)materialDict
 shadersDictionary:(NSDictionary *)shadersDict
			smooth:(BOOL)smooth
	  shaderMacros:(NSDictionary *)macros
shaderBindingTarget:(id<OOWeakReferenceSupport>)object;

- (NSString *) modelName;

- (size_t)vertexCount;
- (size_t)faceCount;

- (Octree *)octree;

// This needs a better name.
- (BoundingBox) findBoundingBoxRelativeToPosition:(Vector)opv
											basis:(Vector)ri :(Vector)rj :(Vector)rk
									 selfPosition:(Vector)position
										selfBasis:(Vector)si :(Vector)sj :(Vector)sk;
- (BoundingBox)findSubentityBoundingBoxWithPosition:(Vector)position rotMatrix:(OOMatrix)rotMatrix;

- (OOMesh *)meshRescaledBy:(GLfloat)scaleFactor;
- (OOMesh *)meshRescaledByX:(GLfloat)scaleX y:(GLfloat)scaleY z:(GLfloat)scaleZ;

@end


#import "OOCacheManager.h"
@interface OOCacheManager (Octree)

+ (Octree *)octreeForModel:(NSString *)inKey;
+ (void)setOctree:(Octree *)inOctree forModel:(NSString *)inKey;

@end
