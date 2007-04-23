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

#import "OODrawable.h"
#import "OOOpenGL.h"
#import "OOMaths.h"
#import "OOWeakReference.h"

@class OOMaterial;


typedef struct OOMeshTexCoords OOMeshTexCoords;
typedef struct OOMeshMaterialGroup OOMeshMaterialGroup;


@interface OOMesh: OODrawable
{
	NSString			*name;
	
	/*	A single set of arrays is shared between all submeshes. A vertex is
		an index into these lists, identifying a unique position + normal +
		texCoord combination.
	*/
	size_t				vertexCount;
	Vector				*positions;
	Vector				*normals;
	OOMeshTexCoords		*texCoords;
	
	//	Primitives are grouped by material to minimize state changes.
	size_t				materialGroupCount;
	OOMeshMaterialGroup	**materialGroups;	// malloc()ed variable-sized array of pointers to malloc()ed OOMeshMaterialGroups.
	
	GLuint				displayList;
	
#if GL_ARB_vertex_buffer_object
	BOOL				VBOsReady;
#endif
}

+ (id)meshWithName:(NSString *)name materialDictionary:(NSDictionary *)materialDict shadersDictionary:(NSDictionary *)shadersDict smooth:(BOOL)smooth shaderMacros:(NSDictionary *)macros shaderBindingTarget:(id<OOWeakReferenceSupport>)object;

- (size_t)vertexCount;
- (size_t)faceCount;		// O(n) in number of primitives

@end



/***** The following declarations are for the use of OOMeshLoaders. *****/

struct OOMeshTexCoords
{
	GLfloat				s, t;
};


typedef struct OOMeshPrimitive
{
	// These correspond to glDrawRangeElements() parameters.
	GLenum				mode;		// GL_TRIANGLE_STRIP, GL_TRIANGLE_FAN, GL_TRIANGLES
	GLuint				start;
	GLuint				end;
	GLsizei				count;
//	type is always GL_UNSIGNED_INT
	
#if GL_ARB_vertex_buffer_object
	GLuint				VBO;
#endif
	
	GLuint				indicies[];	// Variable-size array of GLuints
} OOMeshPrimitive;


struct OOMeshMaterialGroup
{
	NSString			*materialKey;
	OOMaterial			*material;
	size_t				primitiveCount;
	OOMeshPrimitive		*primitives[];	// Variable-sized array of pointers to malloc()ed OOMeshPrimitives
};


OOINLINE OOMeshPrimitive *OOMeshPrimitiveAlloc(GLsizei count);
OOINLINE size_t OOMeshPrimitiveSize(OOMeshPrimitive *primitive);
OOINLINE size_t OOMeshPrimitiveSizeForCount(GLsizei count);
void OOMeshPrimitiveFindStartAndEnd(OOMeshPrimitive *primitive);


OOINLINE size_t OOMeshPrimitiveSizeForCount(GLsizei count)
{
	return sizeof (OOMeshPrimitive) + sizeof (GLuint) * count;
}


OOINLINE OOMeshPrimitive *OOMeshPrimitiveAlloc(GLsizei count)
{
	OOMeshPrimitive *result = calloc(1, OOMeshPrimitiveSizeForCount(count));
	if (result != NULL)  result->count = count;
	return result;
}


OOINLINE size_t OOMeshPrimitiveSize(OOMeshPrimitive *primitive)
{
	return (primitive != NULL) ? OOMeshPrimitiveSizeForCount(primitive->count) : 0;
}


OOINLINE OOMeshMaterialGroup *OOMeshMaterialGroupAlloc(GLsizei count);
void OOMeshMaterialGroupFree(OOMeshMaterialGroup *materialGroup);
void OOMeshMaterialGroupFreeMultiple(OOMeshMaterialGroup **materialGroups, size_t count);	// Free malloc()ed array of malloc()ed OOMeshMaterialGroups.
OOINLINE size_t OOMeshMaterialGroupSize(OOMeshMaterialGroup *materialGroup);
OOINLINE size_t OOMeshMaterialGroupSizeForCount(GLsizei count);


OOINLINE size_t OOMeshMaterialGroupSizeForCount(GLsizei count)
{
	return sizeof (OOMeshMaterialGroup) + sizeof (OOMeshPrimitive *) * count;
}


OOINLINE OOMeshMaterialGroup *OOMeshMaterialGroupAlloc(GLsizei count)
{
	OOMeshMaterialGroup *result = calloc(1, OOMeshMaterialGroupSizeForCount(count));
	if (result != NULL)  result->primitiveCount = count;
	return result;
}


OOINLINE size_t OOMeshMaterialGroupSize(OOMeshMaterialGroup *materialGroup)
{
	return (materialGroup != NULL) ? OOMeshPrimitiveSizeForCount(materialGroup->primitiveCount) : 0;
}
