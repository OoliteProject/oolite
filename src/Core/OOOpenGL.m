/*

OOOpenGL.m

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

#import "OOOpenGL.h"
#import "OOLogging.h"


static NSString * const kOOLogOpenGLStateDump				= @"rendering.opengl.stateDump";


BOOL CheckOpenGLErrors(NSString *format, ...)
{
	GLenum			errCode;
	const GLubyte	*errString = NULL;
	BOOL			errorOccurred = NO;
	va_list			args;
	
	// Short-circut here, because glGetError() is quite expensive.
	if (OOLogWillDisplayMessagesInClass(kOOLogOpenGLError))
	{
		errCode = glGetError();
		
		if (errCode != GL_NO_ERROR)
		{
			errorOccurred = YES;
			errString = gluErrorString(errCode);
			if (format == nil) format = @"<unknown>";
			
			va_start(args, format);
			format = [[NSString alloc] initWithFormat:format arguments:args];
			va_end(args);
			OOLog(kOOLogOpenGLError, @"OpenGL error: \"%s\" (%u), context: %@", errString, errCode, format);
		}
	}
	return errorOccurred;
}


static GLfloat stored_mat_ambient[4];
static GLfloat stored_mat_diffuse[4];
static GLfloat stored_mat_emission[4];
static GLfloat stored_mat_specular[4];
static GLfloat stored_mat_shininess[1];


void LogOpenGLState()
{
	if (!OOLogWillDisplayMessagesInClass(kOOLogOpenGLStateDump))  return;
	
	// we need to report on the material properties
	GLfloat mat_ambient[4];
	GLfloat mat_diffuse[4];
	GLfloat mat_emission[4];
	GLfloat mat_specular[4];
	GLfloat mat_shininess[1];
	//
	GLfloat current_color[4];
	//
	GLint gl_shade_model[1];
	//
	GLint gl_texture_env_mode[1];
	NSString* tex_env_mode_string = nil;
	//
	GLint gl_cull_face_mode[1];
	NSString* cull_face_mode_string = nil;
	//
	GLint gl_front_face[1];
	NSString* front_face_string = nil;
	//
	GLint gl_blend_src[1];
	NSString* blend_src_string = nil;
	GLint gl_blend_dst[1];
	NSString* blend_dst_string = nil;
	//
	GLenum errCode;
	const GLubyte *errString;

	glGetMaterialfv( GL_FRONT, GL_AMBIENT, mat_ambient);
	glGetMaterialfv( GL_FRONT, GL_DIFFUSE, mat_diffuse);
	glGetMaterialfv( GL_FRONT, GL_EMISSION, mat_emission);
	glGetMaterialfv( GL_FRONT, GL_SPECULAR, mat_specular);
	glGetMaterialfv( GL_FRONT, GL_SHININESS, mat_shininess);
	//
	glGetFloatv( GL_CURRENT_COLOR, current_color);
	//
	glGetIntegerv( GL_SHADE_MODEL, gl_shade_model);
	//
	glGetIntegerv( GL_BLEND_SRC, gl_blend_src);
	switch (gl_blend_src[0])
	{
		case GL_ZERO:
			blend_src_string = @"GL_ZERO";
			break;
		case GL_ONE:
			blend_src_string = @"GL_ONE";
			break;
		case GL_DST_COLOR:
			blend_src_string = @"GL_DST_COLOR";
			break;
		case GL_SRC_COLOR:
			blend_src_string = @"GL_SRC_COLOR";
			break;
		case GL_ONE_MINUS_DST_COLOR:
			blend_src_string = @"GL_ONE_MINUS_DST_COLOR";
			break;
		case GL_ONE_MINUS_SRC_COLOR:
			blend_src_string = @"GL_ONE_MINUS_SRC_COLOR";
			break;
		case GL_SRC_ALPHA:
			blend_src_string = @"GL_SRC_ALPHA";
			break;
		case GL_DST_ALPHA:
			blend_src_string = @"GL_DST_ALPHA";
			break;
		case GL_ONE_MINUS_SRC_ALPHA:
			blend_src_string = @"GL_ONE_MINUS_SRC_ALPHA";
			break;
		case GL_ONE_MINUS_DST_ALPHA:
			blend_src_string = @"GL_ONE_MINUS_DST_ALPHA";
			break;
		case GL_SRC_ALPHA_SATURATE:
			blend_src_string = @"GL_SRC_ALPHA_SATURATE";
			break;
		default:
			break;
	}
	//
	glGetIntegerv( GL_BLEND_DST, gl_blend_dst);
	switch (gl_blend_dst[0])
	{
		case GL_ZERO:
			blend_dst_string = @"GL_ZERO";
			break;
		case GL_ONE:
			blend_dst_string = @"GL_ONE";
			break;
		case GL_DST_COLOR:
			blend_dst_string = @"GL_DST_COLOR";
			break;
		case GL_SRC_COLOR:
			blend_dst_string = @"GL_SRC_COLOR";
			break;
		case GL_ONE_MINUS_DST_COLOR:
			blend_dst_string = @"GL_ONE_MINUS_DST_COLOR";
			break;
		case GL_ONE_MINUS_SRC_COLOR:
			blend_dst_string = @"GL_ONE_MINUS_SRC_COLOR";
			break;
		case GL_SRC_ALPHA:
			blend_dst_string = @"GL_SRC_ALPHA";
			break;
		case GL_DST_ALPHA:
			blend_dst_string = @"GL_DST_ALPHA";
			break;
		case GL_ONE_MINUS_SRC_ALPHA:
			blend_dst_string = @"GL_ONE_MINUS_SRC_ALPHA";
			break;
		case GL_ONE_MINUS_DST_ALPHA:
			blend_dst_string = @"GL_ONE_MINUS_DST_ALPHA";
			break;
		case GL_SRC_ALPHA_SATURATE:
			blend_dst_string = @"GL_SRC_ALPHA_SATURATE";
			break;
		default:
			break;
	}
	//
	glGetIntegerv( GL_CULL_FACE_MODE, gl_cull_face_mode);
	switch (gl_cull_face_mode[0])
	{
		case GL_BACK:
			cull_face_mode_string = @"GL_BACK";
			break;
		case GL_FRONT:
			cull_face_mode_string = @"GL_FRONT";
			break;
		default:
			break;
	}
	//
	glGetIntegerv( GL_FRONT_FACE, gl_front_face);
	switch (gl_front_face[0])
	{
		case GL_CCW:
			front_face_string = @"GL_CCW";
			break;
		case GL_CW:
			front_face_string = @"GL_CW";
			break;
		default:
			break;
	}
	//
	glGetTexEnviv(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, gl_texture_env_mode);
	switch (gl_texture_env_mode[0])
	{
		case GL_DECAL:
			tex_env_mode_string = @"GL_DECAL";
			break;
		case GL_REPLACE:
			tex_env_mode_string = @"GL_REPLACE";
			break;
		case GL_MODULATE:
			tex_env_mode_string = @"GL_MODULATE";
			break;
		case GL_BLEND:
			tex_env_mode_string = @"GL_BLEND";
			break;
		default:
			break;
	}
	//
	if ((errCode =glGetError()) != GL_NO_ERROR)
	{
		errString = gluErrorString(errCode);
		OOLog(kOOLogOpenGLError, @"OpenGL error: '%s' (%u) in: %@", errString, errCode);
	}

	/*-- MATERIALS --*/
	if ((stored_mat_ambient[0] != mat_ambient[0])||(stored_mat_ambient[1] != mat_ambient[1])||(stored_mat_ambient[2] != mat_ambient[2])||(stored_mat_ambient[3] != mat_ambient[2]))
		OOLog(kOOLogOpenGLStateDump, @"OPENGL_DEBUG GL_AMBIENT ( %.2ff, %.2ff, %.2ff, %.2ff)",
			mat_ambient[0], mat_ambient[1], mat_ambient[2], mat_ambient[3]);
	if ((stored_mat_diffuse[0] != mat_diffuse[0])||(stored_mat_diffuse[1] != mat_diffuse[1])||(stored_mat_diffuse[2] != mat_diffuse[2])||(stored_mat_diffuse[3] != mat_diffuse[2]))
		OOLog(kOOLogOpenGLStateDump, @"OPENGL_DEBUG GL_DIFFUSE ( %.2ff, %.2ff, %.2ff, %.2ff)",
			mat_diffuse[0], mat_diffuse[1], mat_diffuse[2], mat_diffuse[3]);
	if ((stored_mat_emission[0] != mat_emission[0])||(stored_mat_emission[1] != mat_emission[1])||(stored_mat_emission[2] != mat_emission[2])||(stored_mat_emission[3] != mat_emission[2]))
		OOLog(kOOLogOpenGLStateDump, @"OPENGL_DEBUG GL_EMISSION ( %.2ff, %.2ff, %.2ff, %.2ff)",
			mat_emission[0], mat_emission[1], mat_emission[2], mat_emission[3]);
	if ((stored_mat_specular[0] != mat_specular[0])||(stored_mat_specular[1] != mat_specular[1])||(stored_mat_specular[2] != mat_specular[2])||(stored_mat_specular[3] != mat_specular[2]))
		OOLog(kOOLogOpenGLStateDump, @"OPENGL_DEBUG GL_SPECULAR ( %.2ff, %.2ff, %.2ff, %.2ff)",
			mat_specular[0], mat_specular[1], mat_specular[2], mat_specular[3]);
	if (stored_mat_shininess[0] != mat_shininess[0])
		OOLog(kOOLogOpenGLStateDump, @"OPENGL_DEBUG GL_SHININESS ( %.2ff)", mat_shininess[0]);
	stored_mat_ambient[0] = mat_ambient[0];	stored_mat_ambient[1] = mat_ambient[1];	stored_mat_ambient[2] = mat_ambient[2];	stored_mat_ambient[3] = mat_ambient[3];
	stored_mat_diffuse[0] = mat_diffuse[0];	stored_mat_diffuse[1] = mat_diffuse[1];	stored_mat_diffuse[2] = mat_diffuse[2];	stored_mat_diffuse[3] = mat_diffuse[3];
	stored_mat_emission[0] = mat_emission[0];	stored_mat_emission[1] = mat_emission[1];	stored_mat_emission[2] = mat_emission[2];	stored_mat_emission[3] = mat_emission[3];
	stored_mat_specular[0] = mat_specular[0];	stored_mat_specular[1] = mat_specular[1];	stored_mat_specular[2] = mat_specular[2];	stored_mat_specular[3] = mat_specular[3];
	stored_mat_shininess[0] = mat_shininess[0];
	/*-- MATERIALS --*/

	//
	/*-- LIGHTS --*/
	if (glIsEnabled(GL_LIGHTING))
	{
		OOLog(kOOLogOpenGLStateDump, @"OPENGL_DEBUG GL_LIGHTING :ENABLED:");
		if (glIsEnabled(GL_LIGHT0))
			OOLog(kOOLogOpenGLStateDump, @"OPENGL_DEBUG GL_LIGHT0 :ENABLED:");
		if (glIsEnabled(GL_LIGHT1))
		{
			OOLog(kOOLogOpenGLStateDump, @"OPENGL_DEBUG GL_LIGHT1 :ENABLED:");
			GLfloat light_ambient[4];
			GLfloat light_diffuse[4];
			GLfloat light_specular[4];
			glGetLightfv(GL_LIGHT1, GL_AMBIENT, light_ambient);
			glGetLightfv(GL_LIGHT1, GL_DIFFUSE, light_diffuse);
			glGetLightfv(GL_LIGHT1, GL_SPECULAR, light_specular);
			OOLog(kOOLogOpenGLStateDump, @"OPENGL_DEBUG GL_LIGHT1 GL_AMBIENT ( %.2ff, %.2ff, %.2ff, %.2ff)",
				light_ambient[0], light_ambient[1], light_ambient[2], light_ambient[3]);
			OOLog(kOOLogOpenGLStateDump, @"OPENGL_DEBUG GL_LIGHT1 GL_DIFFUSE ( %.2ff, %.2ff, %.2ff, %.2ff)",
				light_diffuse[0], light_diffuse[1], light_diffuse[2], light_diffuse[3]);
			OOLog(kOOLogOpenGLStateDump, @"OPENGL_DEBUG GL_LIGHT1 GL_SPECULAR ( %.2ff, %.2ff, %.2ff, %.2ff)",
				light_specular[0], light_specular[1], light_specular[2], light_specular[3]);
		}
		if (glIsEnabled(GL_LIGHT2))
			OOLog(kOOLogOpenGLStateDump, @"OPENGL_DEBUG GL_LIGHT2 :ENABLED:");
		if (glIsEnabled(GL_LIGHT3))
			OOLog(kOOLogOpenGLStateDump, @"OPENGL_DEBUG GL_LIGHT3 :ENABLED:");
		if (glIsEnabled(GL_LIGHT4))
			OOLog(kOOLogOpenGLStateDump, @"OPENGL_DEBUG GL_LIGHT4 :ENABLED:");
		if (glIsEnabled(GL_LIGHT5))
			OOLog(kOOLogOpenGLStateDump, @"OPENGL_DEBUG GL_LIGHT5 :ENABLED:");
		if (glIsEnabled(GL_LIGHT6))
			OOLog(kOOLogOpenGLStateDump, @"OPENGL_DEBUG GL_LIGHT6 :ENABLED:");
		if (glIsEnabled(GL_LIGHT7))
			OOLog(kOOLogOpenGLStateDump, @"OPENGL_DEBUG GL_LIGHT7 :ENABLED:");
	}
	/*-- LIGHTS --*/

	OOLog(kOOLogOpenGLStateDump, @"OPENGL_DEBUG GL_CURRENT_COLOR ( %.2ff, %.2ff, %.2ff, %.2ff)",
		current_color[0], current_color[1], current_color[2], current_color[3]);
	//
	OOLog(kOOLogOpenGLStateDump, @"OPENGL_DEBUG GL_TEXTURE_ENV_MODE :%@:", tex_env_mode_string);
	//
	OOLog(kOOLogOpenGLStateDump, @"OPENGL_DEBUG GL_SHADEMODEL :%@:",  (gl_shade_model[0] == GL_SMOOTH)? @"GL_SMOOTH": @"GL_FLAT");
	//
	if (glIsEnabled(GL_FOG))
		OOLog(kOOLogOpenGLStateDump, @"OPENGL_DEBUG GL_FOG :ENABLED:");
	//
	if (glIsEnabled(GL_COLOR_MATERIAL))
		OOLog(kOOLogOpenGLStateDump, @"OPENGL_DEBUG GL_COLOR_MATERIAL :ENABLED:");
	//
	if (glIsEnabled(GL_BLEND))
	{
		OOLog(kOOLogOpenGLStateDump, @"OPENGL_DEBUG GL_BLEND :ENABLED:");
		OOLog(kOOLogOpenGLStateDump, @"OPENGL_DEBUG GL_BLEND_FUNC (:%@:, :%@:)", blend_src_string, blend_dst_string);
	}
	//
	if (glIsEnabled(GL_CULL_FACE))
		OOLog(kOOLogOpenGLStateDump, @"OPENGL_DEBUG GL_CULL_FACE :ENABLED:");
	//
	OOLog(kOOLogOpenGLStateDump, @"OPENGL_DEBUG GL_CULL_FACE_MODE :%@:", cull_face_mode_string);
	//
	OOLog(kOOLogOpenGLStateDump, @"OPENGL_DEBUG GL_FRONT_FACE :%@:", front_face_string);
}


void GLDebugWireframeModeOn(void)
{
	glPushAttrib(GL_POLYGON_BIT | GL_LINE_BIT | GL_TEXTURE_BIT);
	glLineWidth(1.0f);
	glPolygonMode(GL_FRONT_AND_BACK, GL_LINE);
	glDisable(GL_TEXTURE_2D);
}


void GLDebugWireframeModeOff(void)
{
	glPopAttrib();
}
