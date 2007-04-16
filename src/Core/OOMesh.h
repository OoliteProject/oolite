/*

OOMesh.h

Standard OODrawable for static meshes from DAT files.

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
#import "OOMaths.h"

@class OOMaterial;


typedef struct
{
	GLfloat				s, t;
} OOMeshTexCoords;


typedef struct
{
	size_t				vertexCount;
	OOMaterial			*material;
#if GL_ARB_vertex_buffer_object
	GLuint				buffer;
#endif
	Vector				*vertices;
	Vector				*normals;
	OOMeshTexCoords		*texCoords;
} OOMeshSubMesh;


@interface OOMesh: OODrawable
{
	NSString			*name;
	size_t				subMeshCount;
	OOMeshSubMesh		*meshes;
}

+ (id)meshWithName:(NSString *)name materialConfiguration:(NSDictionary *)materialConf;

@end
