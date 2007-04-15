/*

OOSelfDrawingEntity.h

Abstract intermediate class for entities which draw themselves directly using
mesh data contained in the object itself.

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

#import "Entity.h"

#define MAX_VERTICES_PER_ENTITY		320
#define MAX_FACES_PER_ENTITY		512
#define MAX_TEXTURES_PER_ENTITY		8
#define MAX_VERTICES_PER_FACE		16

#define	NUM_VERTEX_ARRAY_RANGES		16


typedef struct
{
	GLfloat					red;
	GLfloat					green;
	GLfloat					blue;
	
	Vector					normal;
	
	int						n_verts;
	
	GLint					vertex[MAX_VERTICES_PER_FACE];
	
	Str255					textureFileStr255;
	GLuint					texName;
	GLfloat					s[MAX_VERTICES_PER_FACE];
	GLfloat					t[MAX_VERTICES_PER_FACE];
} Face;


typedef struct
{
	GLint					index_array[3 * MAX_FACES_PER_ENTITY];	// triangles
	GLfloat					texture_uv_array[ 3 * MAX_FACES_PER_ENTITY * 2];
	Vector					vertex_array[3 * MAX_FACES_PER_ENTITY];
	Vector					normal_array[3 * MAX_FACES_PER_ENTITY];
	
	GLuint					texName;
	
	int						n_triangles;
} EntityData;	// per texture


typedef struct
{
	long					rangeSize;		// # of bytes in this VAR block
	void					*dataBlockPtr;	// ptr to the memory that we're making VAR
	BOOL					forceUpdate;	// true if data in VAR block needs updating
	BOOL					activated;		// set to true the first time we use it
} VertexArrayRangeType;


@interface OOSelfDrawingEntity: Entity
{
	uint8_t					isSmoothShaded: 1,
#if GL_APPLE_vertex_array_object
							usingVAR: 1,
#endif
							materialsReady: 1;
	
	uint8_t					n_textures;
    uint16_t				n_vertices, n_faces;
    
    NSString				*basefile;
	
    Vector					vertices[MAX_VERTICES_PER_ENTITY];
    Vector					vertex_normal[MAX_VERTICES_PER_ENTITY];
    Face					faces[MAX_FACES_PER_ENTITY];
    GLuint					displayListName;
	
	EntityData				entityData;
	NSRange					triangle_range[MAX_TEXTURES_PER_ENTITY];
	Str255					texture_file[MAX_TEXTURES_PER_ENTITY];
	GLuint					texture_name[MAX_TEXTURES_PER_ENTITY];
	
	// COMMON OGL STUFF
#if GL_APPLE_vertex_array_object
	GLuint					gVertexArrayRangeObjects[NUM_VERTEX_ARRAY_RANGES];	// OpenGL's VAR object references
	VertexArrayRangeType	gVertexArrayRangeData[NUM_VERTEX_ARRAY_RANGES];		// our info about each VAR block
#endif
}


- (void) setModelName:(NSString *)modelName;
- (NSString *) modelName;

@end


#if GL_APPLE_vertex_array_object
@interface OOSelfDrawingEntity(OOVertexArrayRange)

// COMMON OGL ROUTINES
- (BOOL) OGL_InitVAR;
- (void) OGL_AssignVARMemory:(long) size :(void *) data :(Byte) whichVAR;
- (void) OGL_UpdateVAR;

@end
#endif


// TODO: move this stuff to OOOpenGL

// keep track of various OpenGL states
//
BOOL mygl_texture_2d;
//
void my_glEnable(GLenum gl_state);
void my_glDisable(GLenum gl_state);

// log a list of current states
//
void LogOpenGLState();

// check for OpenGL errors, reporting them if where is not nil
//
BOOL CheckOpenGLErrors(NSString* where);
