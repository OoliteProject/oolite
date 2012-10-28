/*

OOOpenGLStateManager.m

Implementation of OOSetOpenGLState()/OOVerifyOpenGLState().


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

#import "OOOpenGL.h"
#import "OOLogging.h"
#import "OOMaths.h"
#import "OOMacroOpenGL.h"
#import "OOFunctionAttributes.h"
#import "OOOpenGLExtensionManager.h"

/*	DESIGN NOTES
	
	The state manager is heavily based on macro metaprogramming, to avoid copy-
	and-paste errors. The state it manages is defined in OOOpenGLStates.tbl,
	which is included each time something needs to be done for each state item
	(currently six times in total). The exception is the GL blend mode, which
	is represented by two variables but set with a single glBlendFunc() call;
	this needs to be managed separately.
	
	For the meanings of the different ITEM_FOO macro used, see OOOpenGLStates.tbl.
	
	The states are defined as structs but referred to by index so that the
	definitions are all in one place. This somewhat reduces the chance of
	missing one when updating OOOpenGLStates.tbl. The actual definitions are
	at the bottom of this file.
*/


typedef enum
{
	kStateFalse = false,
	kStateTrue = true,
	kStateMaybe
} StateFlag;


typedef struct
{
	const char					*name;
	
	#define ITEM_STATEFLAG(NAME)		StateFlag NAME
	#define ITEM_CLIENTSTATEFLAG(NAME)	bool NAME
	#define ITEM_SPECIAL(NAME, TYPE, _)	TYPE NAME
	#define ITEM_INT(NAME)				GLint NAME
	
	#include "OOOpenGLStates.tbl"
	
	// These require extra-special handling, because they're set with one function.
	GLint						BLEND_SRC;
	GLint						BLEND_DST;
	
	#undef ITEM_STATEFLAG
	#undef ITEM_CLIENTSTATEFLAG
	#undef ITEM_SPECIAL
	#undef ITEM_INT
} OOOpenGLState;


static const OOOpenGLState kStandardStates[OPENGL_STATE_INTERNAL_USE_ONLY + 1];

static OOOpenGLStateID sCurrentStateID = OPENGL_STATE_INTERNAL_USE_ONLY;


/*	SwitchOpenGLStateInternal(sourceState, targetState)
	
	Applies the differences between sourceState and targetState. It is assumed
	that sourceState accurately reflects the current state.
*/
static void SwitchOpenGLStateInternal(const OOOpenGLState *sourceState, const OOOpenGLState *targetState) NONNULL_FUNC;


/*	Accessors
	
	These functions and macros are used to read and write ITEM_SPECIAL state
	items. The GetState_ accessors are used only in debug mode, while the
	SetState_ acccessors are used in either mode.
*/
static inline bool GetState_DEPTH_WRITEMASK(void)
{
	OO_ENTER_OPENGL();
	
	GLboolean value;
	OOGL(glGetBooleanv(GL_DEPTH_WRITEMASK, &value));
	return value;
}

#define SetState_DEPTH_WRITEMASK(VALUE)  OOGL(glDepthMask(VALUE))

#define SetState_SHADE_MODEL(VALUE)  OOGL(glShadeModel(VALUE))

static inline GLenum GetState_TEXTURE_ENV_MODE(void)
{
	OO_ENTER_OPENGL();
	
	GLint value;
	OOGL(glGetTexEnviv(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, &value));
	return value;
}

#define SetState_TEXTURE_ENV_MODE(VALUE)  OOGL(glTexEnvi(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, VALUE))

#if OO_MULTITEXTURE
static inline GLenum GetState_ACTIVE_TEXTURE(void)
{
	OO_ENTER_OPENGL();
	
	GLint value;
	OOGL(glGetIntegerv(GL_ACTIVE_TEXTURE_ARB, &value));
	return value;
}

#define SetState_ACTIVE_TEXTURE(VALUE)  OOGL(glActiveTextureARB(VALUE))

static inline GLenum GetState_CLIENT_ACTIVE_TEXTURE(void)
{
	OO_ENTER_OPENGL();
	
	GLint value;
	OOGL(glGetIntegerv(GL_CLIENT_ACTIVE_TEXTURE_ARB, &value));
	return value;
}

#define SetState_CLIENT_ACTIVE_TEXTURE(VALUE)  OOGL(glClientActiveTextureARB(VALUE))

#else
static inline GLenum GetState_ACTIVE_TEXTURE(void) {}
static inline void SetState_ACTIVE_TEXTURE(GLenum value) {}
static inline GLenum GetState_CLIENT_ACTIVE_TEXTURE(void) {}
static inline void SetState_CLIENT_ACTIVE_TEXTURE(GLenum value) {}
#endif

static inline void SetState_CULL_FACE_MODE(GLint value)
{
	OO_ENTER_OPENGL();
	
	OOGL(glCullFace(value));
}

#define SetState_FRONT_FACE(VALUE)  OOGL(glFrontFace(VALUE))


#if OO_GL_STATE_VERIFICATION
/*	Debug mode implementation.
*/

static NSString * const kOOLogOpenGLVerifyDump = @"rendering.opengl.state";


/*
	VerifyOpenGLStateInternal(caller, nominalCaller, line)
	
	Tests whether the current OpenGL state matches the last set nominal state.
	If not, it logs the differences, then reverts to the last set nominal state
	(using SwitchOpenGLStateInternal()).
*/
static void VerifyOpenGLStateInternal(const char *caller, const char *nominalCaller, unsigned line) NONNULL_FUNC;


/*	GetCurrentOpenGLState(state)
	
	Retrieves the current OpenGL state.
*/
static void GetCurrentOpenGLState(OOOpenGLState *state) NONNULL_FUNC;


/*	StatesEqual(a, b)
	
	Test whether two states are identical.
*/
static bool StatesEqual(const OOOpenGLState *a, const OOOpenGLState *b) NONNULL_FUNC;


#if OO_CHECK_GL_HEAVY
/*	OOGLNoteCurrentFunction(function, line)
	
	If OO_GL_STATE_VERIFICATION && OO_CHECK_GL_HEAVY, OOGL() calls
	OOGLNoteCurrentFunction() to help us keep track of where OpenGL calls have
	been made recently. The penultimate seen function is logged when we come
	across a state error, which is occasionally actually helpful.
*/

static const char *sLatestFunction = "<none yet>";
static unsigned sLatestLine;
static const char *sPreviousFunction = "<none yet>";
static unsigned sPreviousLine;
static bool sGLFunctionTracking = true;

void OOGLNoteCurrentFunction(const char *function, unsigned line)
{
	if (sGLFunctionTracking)
	{
		if (function != sLatestFunction)
		{
			sPreviousFunction = sLatestFunction;
			sPreviousLine = sLatestLine;
			sLatestFunction = function;
		}
		sLatestLine = line;
	}
}


/*	SetFunctionTracking()
	
	Enable or disable OOGLNoteCurrentFunction(). It is disabled within the
	state manager implementation.
*/
static inline void SetFunctionTracking(bool value)
{
	sGLFunctionTracking = value;
}

#else

static inline void SetFunctionTracking(bool value)  {}

#endif


void OOSetOpenGLState_(OOOpenGLStateID state, const char *function, unsigned line)
{
	NSCParameterAssert((unsigned)state < OPENGL_STATE_INTERNAL_USE_ONLY);
	
	OOGLNoteCurrentFunction(function, line);
	SetFunctionTracking(false);
	
	VerifyOpenGLStateInternal("OOSetOpenGLState", function, line);
	
	if (state != sCurrentStateID)
	{
		SwitchOpenGLStateInternal(&kStandardStates[sCurrentStateID], &kStandardStates[state]);
		sCurrentStateID = state;
	}
	
	SetFunctionTracking(true);
}


void OOVerifyOpenGLState_(const char *function, unsigned line)
{
	OOGLNoteCurrentFunction(function, line);
	SetFunctionTracking(false);
	
	VerifyOpenGLStateInternal("OOVerifyOpenGLState", function, line);
	
	SetFunctionTracking(true);
}


static void GetCurrentOpenGLState(OOOpenGLState *state)
{
	static const char *name = "<current state>";
	
	NSCParameterAssert(state != NULL);
	OO_ENTER_OPENGL();
	memset(state, 0, sizeof *state);
	state->name = name;
	
	#define ITEM_STATEFLAG(NAME)		OOGL(state->NAME = glIsEnabled(GL_##NAME))
	#define ITEM_CLIENTSTATEFLAG(NAME)	OOGL(state->NAME = glIsEnabled(GL_##NAME))
	#define ITEM_SPECIAL(NAME, _, __)	state->NAME = GetState_##NAME()
	#define ITEM_INT(NAME)				OOGL(glGetIntegerv(GL_##NAME, &state->NAME))
	
	#include "OOOpenGLStates.tbl"
	
	OOGL(glGetIntegerv(GL_BLEND_SRC, &state->BLEND_SRC));
	OOGL(glGetIntegerv(GL_BLEND_DST, &state->BLEND_DST));
	
	#undef ITEM_STATEFLAG
	#undef ITEM_CLIENTSTATEFLAG
	#undef ITEM_SPECIAL
	#undef ITEM_INT
}


static bool StatesEqual(const OOOpenGLState *a, const OOOpenGLState *b)
{
	NSCParameterAssert(a != NULL && b != NULL);
	
	#define ITEM_STATEFLAG(NAME)		do { if (a->NAME != b->NAME && a->NAME != kStateMaybe && b->NAME != kStateMaybe)  return false; } while (0)
	#define ITEM_CLIENTSTATEFLAG(NAME)	do { if (a->NAME != b->NAME)  return false; } while (0)
	#define ITEM_SPECIAL(NAME, _, __)	do { if (a->NAME != b->NAME)  return false; } while (0)
	#define ITEM_INT(NAME)				do { if (a->NAME != b->NAME)  return false; } while (0)
	
	#include "OOOpenGLStates.tbl"
	
	#undef ITEM_STATEFLAG
	#undef ITEM_CLIENTSTATEFLAG
	#undef ITEM_SPECIAL
	#undef ITEM_INT
	
	return true;
}


static void VerifyOpenGLStateInternal(const char *caller, const char *nominalCaller, unsigned line)
{
	OOOpenGLState currentState;
	GetCurrentOpenGLState(&currentState);
	
	NSCParameterAssert(sCurrentStateID <= OPENGL_STATE_INTERNAL_USE_ONLY);
	
	const OOOpenGLState *expectedState = &kStandardStates[sCurrentStateID];
	
	if (!StatesEqual(&currentState, expectedState))
	{
		if (OOLogWillDisplayMessagesInClass(kOOLogOpenGLVerifyDump))
		{
			OOLog(kOOLogOpenGLVerifyDump, @"Incorrect OpenGL state in %s (line %u)->%s", nominalCaller, line, caller);
#if OO_CHECK_GL_HEAVY
			OOLog(kOOLogOpenGLVerifyDump, @"Previous OpenGL-using function: %s (line %u)", sPreviousFunction, sPreviousLine);
#endif
			OOLog(kOOLogOpenGLVerifyDump, @"Expected previous state: %s", expectedState->name);
			
			OOLogIndent();
			
			#define TEST_ITEM(NAME_, DISP_) \
				if (currentState.NAME_ != expectedState->NAME_) \
				{ \
					OOLog(kOOLogOpenGLVerifyDump, @"GL_%@ should be %@ but is %@.", @#NAME_, DISP_(expectedState->NAME_), DISP_(currentState.NAME_)); \
				}
			
			#define ITEM_STATEFLAG(NAME)		if (expectedState->NAME != kStateMaybe) { TEST_ITEM(NAME, OOGLFlagToString) }
			#define ITEM_CLIENTSTATEFLAG(NAME)	TEST_ITEM(NAME, OOGLFlagToString)
			#define ITEM_SPECIAL(NAME, _, __)	TEST_ITEM(NAME, OOGLFlagToString)
			#define ITEM_INT(NAME)				TEST_ITEM(NAME, OOGLEnumToString)
			
			#include "OOOpenGLStates.tbl"
			
			if (currentState.BLEND_SRC != expectedState->BLEND_SRC || currentState.BLEND_DST != expectedState->BLEND_DST)
			{
				OOLog(kOOLogOpenGLVerifyDump, @"GL blend mode should be %@, %@ but is %@, %@.", OOGLEnumToString(expectedState->BLEND_SRC), OOGLEnumToString(expectedState->BLEND_DST), OOGLEnumToString(currentState.BLEND_SRC), OOGLEnumToString(currentState.BLEND_DST));
			}
			
			#undef ITEM_STATEFLAG
			#undef ITEM_CLIENTSTATEFLAG
			#undef ITEM_SPECIAL
			#undef ITEM_INT
			
			#undef TEST_ITEM
			
			OOLogOutdent();
		}
		
		SwitchOpenGLStateInternal(&currentState, expectedState);
	}
}

#else	// OO_GL_STATE_VERIFICATION
/*	Non-debug mode implementation.
	
	OOSetOpenGLState() performs a switch from the previous nominal state to the
	new nominal state, without checking that the previous nominal state matches
	the actual state. OOVerifyOpenGLState is a do-nothing macro.
*/

void OOSetOpenGLState(OOOpenGLStateID state)
{
	NSCParameterAssert((unsigned)state < OPENGL_STATE_INTERNAL_USE_ONLY);
	
	if (state != sCurrentStateID)
	{
		SwitchOpenGLStateInternal(&kStandardStates[sCurrentStateID], &kStandardStates[state]);
		sCurrentStateID = state;
	}
}

#endif	// OO_GL_STATE_VERIFICATION


static void SwitchOpenGLStateInternal(const OOOpenGLState *sourceState, const OOOpenGLState *targetState)
{
	NSCParameterAssert(sourceState != NULL && targetState != NULL);
	OO_ENTER_OPENGL();
	
	#define ITEM_STATEFLAG(NAME) \
	if (sourceState->NAME != targetState->NAME && sourceState->NAME != kStateMaybe && targetState->NAME != kStateMaybe) \
	{ \
		if (targetState->NAME) \
		{ \
			OOGL(glEnable(GL_##NAME)); \
		} \
		else \
		{ \
			OOGL(glDisable(GL_##NAME)); \
		} \
	}
	#define ITEM_CLIENTSTATEFLAG(NAME) \
	if (sourceState->NAME != targetState->NAME) \
	{ \
		if (targetState->NAME) \
		{ \
			OOGL(glEnableClientState(GL_##NAME)); \
		} \
		else \
		{ \
			OOGL(glDisableClientState(GL_##NAME)); \
		} \
	}
	#define ITEM_SPECIAL(NAME, TYPE, _) \
	if (sourceState->NAME != targetState->NAME) \
	{ \
		SetState_##NAME(targetState->NAME); \
	}
	#define ITEM_INT(NAME) \
	if (sourceState->NAME != targetState->NAME) \
	{ \
		SetState_##NAME(targetState->NAME); \
	}
	
	#include "OOOpenGLStates.tbl"
	
	
	if (sourceState->BLEND_SRC != targetState->BLEND_SRC || sourceState->BLEND_DST != targetState->BLEND_DST)
	{
		OOGL(glBlendFunc(targetState->BLEND_SRC, targetState->BLEND_DST));
	}
	
	#undef ITEM_STATEFLAG
	#undef ITEM_CLIENTSTATEFLAG
	#undef ITEM_SPECIAL
	#undef ITEM_INT
}


void OOResetGLStateVerifier(void)
{
	// State has been reset behind our backs, so to speak; don't verify.
	sCurrentStateID = OPENGL_STATE_INTERNAL_USE_ONLY;
}


// The state definitions.
static const OOOpenGLState kStandardStates[OPENGL_STATE_INTERNAL_USE_ONLY + 1] =
{
	[OPENGL_STATE_INTERNAL_USE_ONLY] =
	{
		.name = "<canonical initial state>",
		.LIGHTING				= false,
		.LIGHT0					= false,
		.LIGHT1					= false,
		.LIGHT2					= false,
		.LIGHT3					= false,
		.LIGHT4					= false,
		.LIGHT5					= false,
		.LIGHT6					= false,
		.LIGHT7					= false,
		.TEXTURE_2D				= false,
		.COLOR_MATERIAL			= false,
		.SHADE_MODEL			= GL_SMOOTH,
		.TEXTURE_ENV_MODE		= GL_MODULATE,
		.ACTIVE_TEXTURE			= GL_TEXTURE0,
		.CLIENT_ACTIVE_TEXTURE	= GL_TEXTURE0,
		.BLEND					= false,
		.BLEND_SRC				= GL_ONE,
		.BLEND_DST				= GL_ZERO,
		.FOG					= false,
		.VERTEX_ARRAY			= false,
		.NORMAL_ARRAY			= false,
		.COLOR_ARRAY			= false,
		.INDEX_ARRAY			= false,
		.TEXTURE_COORD_ARRAY	= false,
		.EDGE_FLAG_ARRAY		= false,
		.NORMALIZE				= false,
		.RESCALE_NORMAL			= false,
		.DEPTH_TEST				= false,
		.DEPTH_WRITEMASK		= true,
		.CULL_FACE				= false,
		.CULL_FACE_MODE			= GL_BACK,
		.FRONT_FACE				= GL_CCW,
	},
	[OPENGL_STATE_OPAQUE] =
	{
		.name = "OPENGL_STATE_OPAQUE",
		.LIGHTING				= true,
		.LIGHT0					= false,
		.LIGHT1					= true,
		.LIGHT2					= false,
		.LIGHT3					= false,
		.LIGHT4					= false,
		.LIGHT5					= false,
		.LIGHT6					= false,
		.LIGHT7					= false,
		.TEXTURE_2D				= true,
		.COLOR_MATERIAL			= false,
		.SHADE_MODEL			= GL_SMOOTH,
		.TEXTURE_ENV_MODE		= GL_MODULATE,
		.ACTIVE_TEXTURE			= GL_TEXTURE0,
		.CLIENT_ACTIVE_TEXTURE	= GL_TEXTURE0,
		.BLEND					= false,
		.BLEND_SRC				= GL_SRC_ALPHA,
		.BLEND_DST				= GL_ONE_MINUS_SRC_ALPHA,
		.FOG					= kStateMaybe,
		.VERTEX_ARRAY			= true,
		.NORMAL_ARRAY			= true,
		.COLOR_ARRAY			= false,
		.INDEX_ARRAY			= false,
		.TEXTURE_COORD_ARRAY	= false,
		.EDGE_FLAG_ARRAY		= false,
		.NORMALIZE				= false,
		.RESCALE_NORMAL			= false,
		.DEPTH_TEST				= true,
		.DEPTH_WRITEMASK		= true,
		.CULL_FACE				= true,
		.CULL_FACE_MODE			= GL_BACK,
		.FRONT_FACE				= GL_CCW,
	},
	[OPENGL_STATE_TRANSLUCENT_PASS] =
	{
		.name = "OPENGL_STATE_TRANSLUCENT_PASS",
		.LIGHTING				= false,
		.LIGHT0					= false,
		.LIGHT1					= true,
		.LIGHT2					= false,
		.LIGHT3					= false,
		.LIGHT4					= false,
		.LIGHT5					= false,
		.LIGHT6					= false,
		.LIGHT7					= false,
		.TEXTURE_2D				= false,
		.COLOR_MATERIAL			= false,
		.SHADE_MODEL			= GL_SMOOTH,
		.TEXTURE_ENV_MODE		= GL_MODULATE,
		.ACTIVE_TEXTURE			= GL_TEXTURE0,
		.CLIENT_ACTIVE_TEXTURE	= GL_TEXTURE0,
		.BLEND					= false,
		.BLEND_SRC				= GL_SRC_ALPHA,
		.BLEND_DST				= GL_ONE_MINUS_SRC_ALPHA,
		.FOG					= kStateMaybe,
		.VERTEX_ARRAY			= false,
		.NORMAL_ARRAY			= false,
		.COLOR_ARRAY			= false,
		.INDEX_ARRAY			= false,
		.TEXTURE_COORD_ARRAY	= false,
		.EDGE_FLAG_ARRAY		= false,
		.NORMALIZE				= false,
		.RESCALE_NORMAL			= false,
		.DEPTH_TEST				= true,
		.DEPTH_WRITEMASK		= false,
		.CULL_FACE				= true,
		.CULL_FACE_MODE			= GL_BACK,
		.FRONT_FACE				= GL_CCW,
	},
	[OPENGL_STATE_ADDITIVE_BLENDING] =
	{
		.name = "OPENGL_STATE_ADDITIVE_BLENDING",
		.LIGHTING				= false,
		.LIGHT0					= false,
		.LIGHT1					= true,
		.LIGHT2					= false,
		.LIGHT3					= false,
		.LIGHT4					= false,
		.LIGHT5					= false,
		.LIGHT6					= false,
		.LIGHT7					= false,
		.TEXTURE_2D				= false,
		.COLOR_MATERIAL			= false,
		.SHADE_MODEL			= GL_SMOOTH,
		.TEXTURE_ENV_MODE		= GL_MODULATE, // Should be GL_BLEND?
		.ACTIVE_TEXTURE			= GL_TEXTURE0,
		.CLIENT_ACTIVE_TEXTURE	= GL_TEXTURE0,
		.BLEND					= true,
		.BLEND_SRC				= GL_SRC_ALPHA,
		.BLEND_DST				= GL_ONE,
		.FOG					= false,
		.VERTEX_ARRAY			= true,
		.NORMAL_ARRAY			= false,
		.COLOR_ARRAY			= false,
		.INDEX_ARRAY			= false,
		.TEXTURE_COORD_ARRAY	= false,
		.EDGE_FLAG_ARRAY		= false,
		.NORMALIZE				= false,
		.RESCALE_NORMAL			= false,
		.DEPTH_TEST				= true,
		.DEPTH_WRITEMASK		= false,
		.CULL_FACE				= false,
		.CULL_FACE_MODE			= GL_BACK,
		.FRONT_FACE				= GL_CCW,
	},
	[OPENGL_STATE_OVERLAY] =
	{
		.name = "OPENGL_STATE_OVERLAY",
		.LIGHTING				= false,
		.LIGHT0					= false,
		.LIGHT1					= true,
		.LIGHT2					= false,
		.LIGHT3					= false,
		.LIGHT4					= false,
		.LIGHT5					= false,
		.LIGHT6					= false,
		.LIGHT7					= false,
		.TEXTURE_2D				= false,
		.COLOR_MATERIAL			= false,
		.SHADE_MODEL			= GL_SMOOTH,
		.TEXTURE_ENV_MODE		= GL_MODULATE,
		.ACTIVE_TEXTURE			= GL_TEXTURE0,
		.CLIENT_ACTIVE_TEXTURE	= GL_TEXTURE0,
		.BLEND					= true,
		.BLEND_SRC				= GL_SRC_ALPHA,
		.BLEND_DST				= GL_ONE_MINUS_SRC_ALPHA,
		.FOG					= false,
		.VERTEX_ARRAY			= false,
		.NORMAL_ARRAY			= false,
		.COLOR_ARRAY			= false,
		.INDEX_ARRAY			= false,
		.TEXTURE_COORD_ARRAY	= false,
		.EDGE_FLAG_ARRAY		= false,
		.NORMALIZE				= false,
		.RESCALE_NORMAL			= false,
		.DEPTH_TEST				= false,
		.DEPTH_WRITEMASK		= false,
		.CULL_FACE				= false,	// ??
		.CULL_FACE_MODE			= GL_BACK,
		.FRONT_FACE				= GL_CCW,
	}
};
