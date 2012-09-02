/*

OOOpenGL.h

Do whatever is appropriate to get gl.h, glu.h and glext.h included.

Also declares OpenGL-related utility functions.


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

#import "OOCocoa.h"
#import "OOOpenGLOnly.h"


typedef enum
{
	// NOTE: numerical values are available to scripts.
	SHADERS_NOT_SUPPORTED					= 0,
	SHADERS_OFF								= 1,
	SHADERS_SIMPLE							= 2,
	SHADERS_FULL							= 3
} OOShaderSetting;


#define NULL_SHADER ((GLhandleARB)0)


/*	CheckOpenGLErrors()
	Check for and log OpenGL errors, and returns YES if an error occurred.
	NOTE: this is controlled by the log message class rendering.opengl.error.
		  If logging is disabled, no error checking will occur. This is done
		  because glGetError() is quite expensive, requiring a full OpenGL
		  state sync.
*/
BOOL CheckOpenGLErrors(NSString *format, ...);

/*	LogOpenGLState()
	Write a bunch of OpenGL state information to the log.
*/
void LogOpenGLState(void);


/*	GLScaledLineWidth()
	GLScaledPointSize()
	GLGetDisplayScaleFactor()
	GLSetDisplayScaleFactor()
	
	These functions wrap glLineWidth() and glPointSize(), and multiply the
	specified size by a "display scale factor". This is currently used to
	support Retina display modes in Mac OS X 10.7 and later.
	
	The default display scale factor is 1.0.
*/
void GLScaledLineWidth(GLfloat width);
void GLScaledPointSize(GLfloat size);
GLfloat GLGetDisplayScaleFactor(void);
void GLSetDisplayScaleFactor(GLfloat factor);


/*	GLDebugWireframeModeOn()
	GLDebugWireframeModeOff()
	Enable/disable debug wireframe mode. In debug wireframe mode, the polygon
	mode is set to GL_LINE, textures are disabled and the line size is set to
	1 pixel.
*/
void GLDebugWireframeModeOn(void);
void GLDebugWireframeModeOff(void);

/*	GLDrawBallBillboard()
	Draws a circle corresponding to a sphere of given radius at given distance.
	Assumes Z buffering will be disabled.
*/
void GLDrawBallBillboard(GLfloat radius, GLfloat step, GLfloat z_distance);

/*	GLDrawOval(), GLDrawFilledOval()
	Draw axis-alligned ellipses, as outline and fill respectively.
*/
void GLDrawOval(GLfloat x, GLfloat y, GLfloat z, NSSize siz, GLfloat step);
void GLDrawFilledOval(GLfloat x, GLfloat y, GLfloat z, NSSize siz, GLfloat step);


/*	OO_CHECK_GL_HEAVY and error-checking stuff
	
	If OO_CHECK_GL_HEAVY is non-zero, the following error-checking facilities
	come into play:
	OOGL(foo) checks for GL errors before and after performing the statement foo.
	OOGLBEGIN(mode) checks for GL errors, then calls glBegin(mode).
	OOGLEND() calls glEnd(), then checks for GL errors.
	CheckOpenGLErrorsHeavy() checks for errors exactly like CheckOpenGLErrors().
	
	If OO_CHECK_GL_HEAVY is zero, these macros don't perform error checking,
	but otherwise continue to work as before, so:
	OOGL(foo) performs the statement foo.
	OOGLBEGIN(mode) calls glBegin(mode);
	OOGLEND() calls glEnd().
	CheckOpenGLErrorsHeavy() does nothing (including not performing any parameter side-effects).
*/
#ifndef OO_CHECK_GL_HEAVY
#define OO_CHECK_GL_HEAVY 0
#endif


#if OO_CHECK_GL_HEAVY

NSString *OOLogAbbreviatedFileName(const char *inName);
#define OOGL_PERFORM_CHECK(label, code)  CheckOpenGLErrors(@"%s %@:%u (%s)%s", label, OOLogAbbreviatedFileName(__FILE__), __LINE__, __PRETTY_FUNCTION__, code)
#define OOGL(statement)  do { OOGL_PERFORM_CHECK("PRE", " -- " #statement); statement; OOGL_PERFORM_CHECK("POST", " -- " #statement); } while (0)
#define CheckOpenGLErrorsHeavy CheckOpenGLErrors
#define OOGLBEGIN(mode) do { OOGL_PERFORM_CHECK("PRE-BEGIN", " -- " #mode); glBegin(mode); } while (0)
#define OOGLEND() do { glEnd(); OOGL_PERFORM_CHECK("POST-END", ""); } while (0)

#else

#define OOGL(statement)  do { statement; } while (0)
#define CheckOpenGLErrorsHeavy(...) do {} while (0)
#define OOGLBEGIN glBegin
#define OOGLEND glEnd

#endif


enum 
{
	kOOShaderSettingDefault		= SHADERS_NOT_SUPPORTED
};

// Programmer-readable shader mode strings.
OOShaderSetting OOShaderSettingFromString(NSString *string);
NSString *OOStringFromShaderSetting(OOShaderSetting setting);
// Localized shader mode strings.
NSString *OODisplayStringFromShaderSetting(OOShaderSetting setting);
