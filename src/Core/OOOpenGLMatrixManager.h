/*

OOOpenGLMatrixManager.h

Manages OpenGL Model, View, etc. matrices.

Oolite
Copyright (C) 2004-2014 Giles C Williams and contributors

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

#import "OOMaths.h"

extern const char* ooliteStandardMatrixUniforms[];

enum
{
	OOLITE_GL_MATRIX_MODELVIEW,
	OOLITE_GL_MATRIX_PROJECTION,
	OOLITE_GL_MATRIX_MODELVIEW_PROJECTION,
	OOLITE_GL_MATRIX_NORMAL,
	OOLITE_GL_MATRIX_MODELVIEW_INVERSE,
	OOLITE_GL_MATRIX_PROJECTION_INVERSE,
	OOLITE_GL_MATRIX_MODELVIEW_PROJECTION_INVERSE,
	OOLITE_GL_MATRIX_MODELVIEW_TRANSPOSE,
	OOLITE_GL_MATRIX_PROJECTION_TRANSPOSE,
	OOLITE_GL_MATRIX_MODELVIEW_PROJECTION_TRANSPOSE,
	OOLITE_GL_MATRIX_MODELVIEW_INVERSE_TRANSPOSE,
	OOLITE_GL_MATRIX_PROJECTION_INVERSE_TRANSPOSE,
	OOLITE_GL_MATRIX_MODELVIEW_PROJECTION_INVERSE_TRANSPOSE,
	OOLITE_GL_MATRIX_END
};

@interface OOOpenGLMatrixStack: NSObject
{
@private
	NSMutableArray	*stack;
}

- (id) init;
- (void) dealloc;
- (void) push: (OOMatrix) matrix;
- (OOMatrix) pop;

@end

@interface OOOpenGLMatrixManager: NSObject
{
@private
	OOMatrix		matrices[OOLITE_GL_MATRIX_END];
	BOOL			valid[OOLITE_GL_MATRIX_END];
	OOOpenGLMatrixStack	*modelViewStack;
	OOOpenGLMatrixStack	*projectionStack;
}

- (id) init;
- (void) dealloc;
- (void) loadModelView: (OOMatrix) matrix;
- (void) resetModelView;
- (void) multModelView: (OOMatrix) matrix;
- (void) translateModelView: (Vector) vector;
- (void) rotateModelView: (GLfloat) angle axis: (Vector) axis;
- (void) scaleModelView: (Vector) scale;
- (void) lookAtWithEye: (Vector) eye center: (Vector) center up: (Vector) up; 
- (void) pushModelView;
- (OOMatrix) popModelView;
- (OOMatrix) getModelView;
- (void) syncModelView;
- (void) loadProjection: (OOMatrix) matrix;
- (void) multProjection: (OOMatrix) matrix;
- (void) translateProjection: (Vector) vector;
- (void) rotateProjection: (GLfloat) angle axis: (Vector) axis;
- (void) scaleProjection: (Vector) scale;
- (void) frustumLeft: (double) l right: (double) r bottom: (double) b top: (double) t near: (double) n far: (double) f;
- (void) orthoLeft: (double) l right: (double) r bottom: (double) b top: (double) t near: (double) n far: (double) f;
- (void) perspectiveFovy: (double) fovy aspect: (double) aspect zNear: (double) zNear zFar: (double) zFar;
- (void) resetProjection;
- (void) pushProjection;
- (OOMatrix) popProjection;
- (OOMatrix) getProjection;
- (void) syncProjection;
- (OOMatrix) getMatrix: (int) which;
- (NSArray*) standardMatrixUniformLocations: (GLuint) program;

@end

