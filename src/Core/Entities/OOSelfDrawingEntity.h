/*

OOSelfDrawingEntity.h

Abstract intermediate class for entities which draw themselves directly using
mesh data contained in the object itself.

Oolite
Copyright (C) 2004-2010 Giles C Williams and contributors

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

#import "Entity.h"
#import "OOMesh.h" // Currently, we're sharing structures and constants with OOMesh


enum
{
	MAX_VERTICES_PER_ENTITY		= 320,
	MAX_FACES_PER_ENTITY		= 512,
	MAX_TEXTURES_PER_ENTITY		= 8,
	MAX_VERTICES_PER_FACE		= 16,
	
	NUM_VERTEX_ARRAY_RANGES		= 16
};


typedef char OOStr255[256];	// Not the same as the previously-abused Str255


typedef struct
{
	GLfloat					red;
	GLfloat					green;
	GLfloat					blue;
	
	Vector					normal;
	
	unsigned				n_verts;
	
	GLint					vertex[MAX_VERTICES_PER_FACE];
	
	OOStr255				textureFileName;
	GLuint					textureName;
	GLfloat					s[MAX_VERTICES_PER_FACE];
	GLfloat					t[MAX_VERTICES_PER_FACE];
} Face;


typedef struct
{
	GLint					index_array[3 * MAX_FACES_PER_ENTITY];	// triangles
	GLfloat					texture_uv_array[3 * MAX_FACES_PER_ENTITY * 2];
	Vector					vertex_array[3 * MAX_FACES_PER_ENTITY];
	Vector					normal_array[3 * MAX_FACES_PER_ENTITY];
	
	int						n_triangles;	// Actually number of entries, i.e. triangle count * 3.
} EntityData;


@interface OOSelfDrawingEntity: Entity
{
	uint8_t					isSmoothShaded: 1;
	
	OOMeshMaterialCount		textureCount;
	OOMeshVertexCount		vertexCount;
	OOMeshFaceCount			faceCount;
	
	NSString				*basefile;
	
	Vector					vertices[MAX_VERTICES_PER_ENTITY];
	Vector					vertex_normal[MAX_VERTICES_PER_ENTITY];
	Face					faces[MAX_FACES_PER_ENTITY];
	GLuint					displayListName;
	
	EntityData				entityData;
	NSRange					triangle_range[MAX_TEXTURES_PER_ENTITY];
	OOStr255				textureFileName[MAX_TEXTURES_PER_ENTITY];
	GLuint					textureNames[MAX_TEXTURES_PER_ENTITY];
}


- (void) setModelName:(NSString *)modelName;
- (NSString *) modelName;


- (void)generateDisplayList;

@end
