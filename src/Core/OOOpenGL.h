/*

OOOpenGL.h

Do whatever is appropriate to get gl.h, glu.h and glext.h included.

Also declares OpenGL-related utility functions.


Oolite
Copyright (C) 2004-2013 Giles C Williams and contributors

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


// Whether to use state verifier. Will be changed to equal OO_CHECK_GL_HEAVY in future.
#define OO_GL_STATE_VERIFICATION (!defined(NDEBUG))

/*
	OOSetOpenGLState(stateType)
	
	Set OpenGL state to one of two standard states.
	
	In Deployment builds, this only modifies the state that differs between
	the two standard states, and only when the last set state is not the same
	as the specified target.
	
	In Debug builds, it tests many different OpenGL state variables, complains
	if they aren't in the expected state, and corrects them.
	
	
	The correct procedure for using these functions is:
	  1. Call OOSetOpenGLState(<most appropriate state>)
	  2. Make any state changes needed
	  3. Draw
	  4. Reverse state changes from stage 2
	  5. Call OOVerifyOpenGLState()
	  6. Call OOCheckOpenGLErrors().
	
	
	The states are:
	OPENGL_STATE_OPAQUE - standard state for drawing solid objects like OOMesh
	and planets. This can be considered the Oolite baseline state.
	Differs from standard GL state as follows:
		GL_LIGHTING is on
		GL_LIGHT1 is on
		GL_TEXTURE_2D is on
		Blend mode is GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA (but GL_BLEND is off)
		GL_FOG may be either on or off (as it's set in Universe's draw loop)
		GL_VERTEX_ARRAY is on
		GL_NORMAL_ARRAY is on
		GL_DEPTH_TEST is on
		GL_CULL_FACE is on
	
	OPENGL_STATE_TRANSLUCENT_PASS is used during the translucent phase of the
	universe draw loop. This usage needs to be cleaned up.
	Differs from OPENGL_STATE_OPAQUE as follows:
		GL_LIGHTING is off
		GL_TEXTURE_2D is off
		GL_VERTEX_ARRAY is off
		GL_NORMAL_ARRAY is off
		GL_DEPTH_WRITEMASK is off
	
	OPENGL_STATE_ADDITIVE_BLENDING is used for glowy special effects.
 	Differs from OPENGL_STATE_OPAQUE as follows:
		GL_LIGHTING is off
		GL_TEXTURE_2D is off
		GL_BLEND is on
		Blend mode is GL_SRC_ALPHA, GL_ONE
		GL_NORMAL_ARRAY is off
		GL_DEPTH_WRITEMASK is off
		GL_CULL_FACE is off
	
	OPENGL_STATE_OVERLAY is used for UI elements, which are unlit and don't use
	z-buffering.
 	Differs from OPENGL_STATE_OPAQUE as follows:
		GL_LIGHTING is off
		GL_TEXTURE_2D is off
		GL_BLEND is on
		GL_FOG is off
		GL_NORMAL_ARRAY is off
		GL_DEPTH_TEST is off
		GL_DEPTH_WRITEMASK is off
		GL_CULL_FACE is off
*/
typedef enum
{
	OPENGL_STATE_OPAQUE,
	OPENGL_STATE_TRANSLUCENT_PASS,
	OPENGL_STATE_ADDITIVE_BLENDING,
	OPENGL_STATE_OVERLAY,
	
	OPENGL_STATE_INTERNAL_USE_ONLY
} OOOpenGLStateID;


#if OO_GL_STATE_VERIFICATION
void OOSetOpenGLState_(OOOpenGLStateID state, const char *function, unsigned line);
void OOVerifyOpenGLState_(const char *function, unsigned line);
#define OOSetOpenGLState(STATE)	OOSetOpenGLState_(STATE, __FUNCTION__, __LINE__)
#define OOVerifyOpenGLState()	OOVerifyOpenGLState_(__FUNCTION__, __LINE__)
#else
void OOSetOpenGLState(OOOpenGLStateID state);
#define OOVerifyOpenGLState()	do {} while (0)
#endif


// Inform the SetState/VerifyState mechanism that the OpenGL context has been reset to its initial state.
void OOResetGLStateVerifier(void);


/*	OOCheckOpenGLErrors()
	Check for and log OpenGL errors, and returns YES if an error occurred.
	NOTE: this is controlled by the log message class rendering.opengl.error.
		  If logging is disabled, no error checking will occur. This is done
		  because glGetError() is quite expensive, requiring a full OpenGL
		  state sync.
*/
BOOL OOCheckOpenGLErrors(NSString *format, ...);

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


/*	OOGLWireframeModeOn()
	OOGLWireframeModeOff()
	Enable/disable polygon-to-lines wireframe rendering with line width of 1.
*/
void OOGLWireframeModeOn(void);
void OOGLWireframeModeOff(void);


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

/*	GLDrawPoints(), GLDrawFilledPoints()
	Draw array of points, as outline and fill respectively.
*/

typedef struct {
	GLfloat x;
	GLfloat y;
	GLfloat z;
} OOGLVector;

void GLDrawPoints(OOGLVector *points, int n);
void GLDrawFilledPoints(OOGLVector *points, int n);
void GLDrawQuadStrip(OOGLVector *points, int n);

/*	OO_CHECK_GL_HEAVY and error-checking stuff
	
	If OO_CHECK_GL_HEAVY is non-zero, the following error-checking facilities
	come into play:
	OOGL(foo) checks for GL errors before and after performing the statement foo.
	OOGLBEGIN(mode) checks for GL errors, then calls glBegin(mode).
	OOGLEND() calls glEnd(), then checks for GL errors.
	CheckOpenGLErrorsHeavy() checks for errors exactly like OOCheckOpenGLErrors().
	
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

#if OO_GL_STATE_VERIFICATION
void OOGLNoteCurrentFunction(const char *func, unsigned line);
#else
#define OOGLNoteCurrentFunction(FUNC, line)  do {} while (0)
#endif

NSString *OOLogAbbreviatedFileName(const char *inName);
#define OOGL_PERFORM_CHECK(label, code)  OOCheckOpenGLErrors(@"%s %@:%u (%s)%s", label, OOLogAbbreviatedFileName(__FILE__), __LINE__, __PRETTY_FUNCTION__, code)
#define OOGL(statement)  do { OOGLNoteCurrentFunction(__FUNCTION__, __LINE__); OOGL_PERFORM_CHECK("PRE", " -- " #statement); statement; OOGL_PERFORM_CHECK("POST", " -- " #statement); } while (0)
#define CheckOpenGLErrorsHeavy OOCheckOpenGLErrors
#define OOGLBEGIN(mode) do { OOGLNoteCurrentFunction(__FUNCTION__, __LINE__); OOGL_PERFORM_CHECK("PRE-BEGIN", " -- " #mode); glBegin(mode); } while (0)
#define OOGLEND() do { glEnd(); OOGLNoteCurrentFunction(__FUNCTION__, __LINE__); OOGL_PERFORM_CHECK("POST-END", ""); } while (0)

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


#ifndef NDEBUG

NSString *OOGLColorToString(GLfloat color[4]);
NSString *OOGLEnumToString(GLenum value);
NSString *OOGLFlagToString(bool value);

#endif
