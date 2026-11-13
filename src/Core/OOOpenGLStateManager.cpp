/*

OOOpenGLStateManager.m

Implementation of OOSetOpenGLState()/OOVerifyOpenGLState().


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

#include <cstring>
#include <string_view>

#include "OOFunctionAttributes.h"
#include "OOMacroOpenGL.h"
#include "OOOpenGL.h"
#include "OOOpenGLExtensionManager.h"  // IWYU pragma: keep: the OpenGL feature macros its #if lines test
#include "oofnd/Log.hpp"
#include "oofnd/objc/OOAssert.h"

/*	DESIGN NOTES

        The state manager is heavily based on macro metaprogramming, to avoid
   copy- and-paste errors. The state it manages is defined in
   OOOpenGLStates.tbl, which is included each time something needs to be done
   for each state item (currently six times in total). The exception is the GL
   blend mode, which is represented by two variables but set with a single
   glBlendFunc() call; this needs to be managed separately.

        For the meanings of the different ITEM_FOO macro used, see
   OOOpenGLStates.tbl.

        The states are defined as structs but referred to by index so that the
        definitions are all in one place. This somewhat reduces the chance of
        missing one when updating OOOpenGLStates.tbl. The actual definitions are
        just after the OOOpenGLState type (C++ has no forward declaration of a
        static const object).
*/

enum class StateFlag : std::uint8_t { kFalse = false, kTrue = true, kMaybe };

#if OO_GL_STATE_VERIFICATION
// A flag as the GL dump logs it: anything but kFalse reads as on, as the
// unscoped enum converted to bool. (The dump, and OOGLFlagToString, exist only
// with the state verifier.)
std::string StateFlagToString(StateFlag flag) {
  return OOGLFlagToString(flag != StateFlag::kFalse);
}
#endif

using OOOpenGLState = struct {
  std::string_view name;

#define ITEM_STATEFLAG(NAME) StateFlag NAME
#define ITEM_CLIENTSTATEFLAG(NAME) bool NAME
#define ITEM_SPECIAL(NAME, TYPE, _) TYPE NAME
#define ITEM_INT(NAME) GLint NAME

#include "OOOpenGLStates.tbl"

  // These require extra-special handling, because they're set with one
  // function.
  GLint BLEND_SRC;
  GLint BLEND_DST;

#undef ITEM_STATEFLAG
#undef ITEM_CLIENTSTATEFLAG
#undef ITEM_SPECIAL
#undef ITEM_INT
};

// The state definitions.
static const OOOpenGLState
    kStandardStates[oo::ToUnderlying(OOOpenGLStateID::kInternalUseOnly) + 1] = {
        {
            // [OOOpenGLStateID::kOpaque]
            .name = "OPENGL_STATE_OPAQUE",
            .LIGHTING = StateFlag::kTrue,
            .LIGHT0 = StateFlag::kMaybe,
            /* FIXME: in shader mode, these should not be StateFlag::kMaybe, but
             * false for 0 and true for 1. On the other hand, in shader mode
             * these settings are supposed to be irrelevant. */
            .LIGHT1 = StateFlag::kMaybe,  // FIXME: see above
            .LIGHT2 = StateFlag::kFalse,
            .LIGHT3 = StateFlag::kFalse,
            .LIGHT4 = StateFlag::kFalse,
            .LIGHT5 = StateFlag::kFalse,
            .LIGHT6 = StateFlag::kFalse,
            .LIGHT7 = StateFlag::kFalse,
            .TEXTURE_2D = StateFlag::kTrue,
            .COLOR_MATERIAL = StateFlag::kFalse,
            .BLEND = StateFlag::kFalse,
            .FOG = StateFlag::kMaybe,
            .DEPTH_TEST = StateFlag::kTrue,
            .NORMALIZE = StateFlag::kFalse,
            .RESCALE_NORMAL = StateFlag::kFalse,
            .VERTEX_ARRAY = true,
            .NORMAL_ARRAY = true,
            .COLOR_ARRAY = false,
            .INDEX_ARRAY = false,
            .TEXTURE_COORD_ARRAY = false,
            .EDGE_FLAG_ARRAY = false,
            .DEPTH_WRITEMASK = true,
            .CULL_FACE = StateFlag::kTrue,
            .SHADE_MODEL = GL_SMOOTH,
            .TEXTURE_ENV_MODE = GL_MODULATE,
            .ACTIVE_TEXTURE = GL_TEXTURE0,
            .CLIENT_ACTIVE_TEXTURE = GL_TEXTURE0,
            .CULL_FACE_MODE = GL_BACK,
            .FRONT_FACE = GL_CCW,
            .BLEND_SRC = GL_SRC_ALPHA,
            .BLEND_DST = GL_ONE_MINUS_SRC_ALPHA,
        },
        {
            // [OOOpenGLStateID::kTranslucentPass]
            .name = "OPENGL_STATE_TRANSLUCENT_PASS",
            .LIGHTING = StateFlag::kFalse,
            .LIGHT0 = StateFlag::kMaybe,  // FIXME: see above
            .LIGHT1 = StateFlag::kMaybe,  // FIXME: see above
            .LIGHT2 = StateFlag::kFalse,
            .LIGHT3 = StateFlag::kFalse,
            .LIGHT4 = StateFlag::kFalse,
            .LIGHT5 = StateFlag::kFalse,
            .LIGHT6 = StateFlag::kFalse,
            .LIGHT7 = StateFlag::kFalse,
            .TEXTURE_2D = StateFlag::kFalse,
            .COLOR_MATERIAL = StateFlag::kFalse,
            .BLEND = StateFlag::kFalse,
            .FOG = StateFlag::kMaybe,
            .DEPTH_TEST = StateFlag::kTrue,
            .NORMALIZE = StateFlag::kFalse,
            .RESCALE_NORMAL = StateFlag::kFalse,
            .VERTEX_ARRAY = false,
            .NORMAL_ARRAY = false,
            .COLOR_ARRAY = false,
            .INDEX_ARRAY = false,
            .TEXTURE_COORD_ARRAY = false,
            .EDGE_FLAG_ARRAY = false,
            .DEPTH_WRITEMASK = false,
            .CULL_FACE = StateFlag::kTrue,
            .SHADE_MODEL = GL_SMOOTH,
            .TEXTURE_ENV_MODE = GL_MODULATE,
            .ACTIVE_TEXTURE = GL_TEXTURE0,
            .CLIENT_ACTIVE_TEXTURE = GL_TEXTURE0,
            .CULL_FACE_MODE = GL_BACK,
            .FRONT_FACE = GL_CCW,
            .BLEND_SRC = GL_SRC_ALPHA,
            .BLEND_DST = GL_ONE_MINUS_SRC_ALPHA,
        },
        {
            // [OOOpenGLStateID::kAdditiveBlending]
            .name = "OPENGL_STATE_ADDITIVE_BLENDING",
            .LIGHTING = StateFlag::kFalse,
            .LIGHT0 = StateFlag::kMaybe,  // FIXME: see above
            .LIGHT1 = StateFlag::kMaybe,  // FIXME: see above
            .LIGHT2 = StateFlag::kFalse,
            .LIGHT3 = StateFlag::kFalse,
            .LIGHT4 = StateFlag::kFalse,
            .LIGHT5 = StateFlag::kFalse,
            .LIGHT6 = StateFlag::kFalse,
            .LIGHT7 = StateFlag::kFalse,
            .TEXTURE_2D = StateFlag::kFalse,
            .COLOR_MATERIAL = StateFlag::kFalse,
            .BLEND = StateFlag::kTrue,
            .FOG = StateFlag::kMaybe,
            .DEPTH_TEST = StateFlag::kTrue,
            .NORMALIZE = StateFlag::kFalse,
            .RESCALE_NORMAL = StateFlag::kFalse,
            .VERTEX_ARRAY = true,
            .NORMAL_ARRAY = false,
            .COLOR_ARRAY = false,
            .INDEX_ARRAY = false,
            .TEXTURE_COORD_ARRAY = false,
            .EDGE_FLAG_ARRAY = false,
            .DEPTH_WRITEMASK = false,
            .CULL_FACE = StateFlag::kFalse,
            .SHADE_MODEL = GL_SMOOTH,
            .TEXTURE_ENV_MODE = GL_MODULATE,  // Should be GL_BLEND?
            .ACTIVE_TEXTURE = GL_TEXTURE0,
            .CLIENT_ACTIVE_TEXTURE = GL_TEXTURE0,
            .CULL_FACE_MODE = GL_BACK,
            .FRONT_FACE = GL_CCW,
            .BLEND_SRC = GL_SRC_ALPHA,
            .BLEND_DST = GL_ONE,
        },
        {
            // [OOOpenGLStateID::kOverlay]
            .name = "OPENGL_STATE_OVERLAY",
            .LIGHTING = StateFlag::kFalse,
            .LIGHT0 = StateFlag::kMaybe,  // FIXME: see above
            .LIGHT1 = StateFlag::kMaybe,  // FIXME: see above
            .LIGHT2 = StateFlag::kFalse,
            .LIGHT3 = StateFlag::kFalse,
            .LIGHT4 = StateFlag::kFalse,
            .LIGHT5 = StateFlag::kFalse,
            .LIGHT6 = StateFlag::kFalse,
            .LIGHT7 = StateFlag::kFalse,
            .TEXTURE_2D = StateFlag::kFalse,
            .COLOR_MATERIAL = StateFlag::kFalse,
            .BLEND = StateFlag::kTrue,
            .FOG = StateFlag::kFalse,
            .DEPTH_TEST = StateFlag::kFalse,
            .NORMALIZE = StateFlag::kFalse,
            .RESCALE_NORMAL = StateFlag::kFalse,
            .VERTEX_ARRAY = false,
            .NORMAL_ARRAY = false,
            .COLOR_ARRAY = false,
            .INDEX_ARRAY = false,
            .TEXTURE_COORD_ARRAY = false,
            .EDGE_FLAG_ARRAY = false,
            .DEPTH_WRITEMASK = false,
            .CULL_FACE = StateFlag::kFalse,  // ??
            .SHADE_MODEL = GL_SMOOTH,
            .TEXTURE_ENV_MODE = GL_MODULATE,
            .ACTIVE_TEXTURE = GL_TEXTURE0,
            .CLIENT_ACTIVE_TEXTURE = GL_TEXTURE0,
            .CULL_FACE_MODE = GL_BACK,
            .FRONT_FACE = GL_CCW,
            .BLEND_SRC = GL_SRC_ALPHA,
            .BLEND_DST = GL_ONE_MINUS_SRC_ALPHA,
        },
        {
            // [OOOpenGLStateID::kInternalUseOnly]
            .name = "<canonical initial state>",
            .LIGHTING = StateFlag::kFalse,
            .LIGHT0 = StateFlag::kFalse,
            .LIGHT1 = StateFlag::kFalse,
            .LIGHT2 = StateFlag::kFalse,
            .LIGHT3 = StateFlag::kFalse,
            .LIGHT4 = StateFlag::kFalse,
            .LIGHT5 = StateFlag::kFalse,
            .LIGHT6 = StateFlag::kFalse,
            .LIGHT7 = StateFlag::kFalse,
            .TEXTURE_2D = StateFlag::kFalse,
            .COLOR_MATERIAL = StateFlag::kFalse,
            .BLEND = StateFlag::kFalse,
            .FOG = StateFlag::kFalse,
            .DEPTH_TEST = StateFlag::kFalse,
            .NORMALIZE = StateFlag::kFalse,
            .RESCALE_NORMAL = StateFlag::kFalse,
            .VERTEX_ARRAY = false,
            .NORMAL_ARRAY = false,
            .COLOR_ARRAY = false,
            .INDEX_ARRAY = false,
            .TEXTURE_COORD_ARRAY = false,
            .EDGE_FLAG_ARRAY = false,
            .DEPTH_WRITEMASK = true,
            .CULL_FACE = StateFlag::kFalse,
            .SHADE_MODEL = GL_SMOOTH,
            .TEXTURE_ENV_MODE = GL_MODULATE,
            .ACTIVE_TEXTURE = GL_TEXTURE0,
            .CLIENT_ACTIVE_TEXTURE = GL_TEXTURE0,
            .CULL_FACE_MODE = GL_BACK,
            .FRONT_FACE = GL_CCW,
            .BLEND_SRC = GL_ONE,
            .BLEND_DST = GL_ZERO,
        }};

static OOOpenGLStateID sCurrentStateID = OOOpenGLStateID::kInternalUseOnly;

/*	SwitchOpenGLStateInternal(sourceState, targetState)

        Applies the differences between sourceState and targetState. It is
   assumed that sourceState accurately reflects the current state.
*/
namespace {
static void SwitchOpenGLStateInternal(
    const OOOpenGLState* sourceState,
    const OOOpenGLState*
        targetState);  // no NONNULL_FUNC: the body asserts its arguments are
                       // non-null, which GCC drops as always true under the
                       // attribute (-Wnonnull-compare)
}  // namespace

/*	Accessors

        These functions and macros are used to read and write ITEM_SPECIAL state
        items. The GetState_ accessors are used only in debug mode, while the
        SetState_ acccessors are used in either mode.
*/
#ifndef NDEBUG
static inline bool GetState_DEPTH_WRITEMASK() {
  OO_ENTER_OPENGL();

  GLboolean value;
  OOGL(glGetBooleanv(GL_DEPTH_WRITEMASK, &value));
  return value;
}
#endif

#define SetState_DEPTH_WRITEMASK(VALUE) OOGL(glDepthMask(VALUE))

#define SetState_SHADE_MODEL(VALUE) OOGL(glShadeModel(VALUE))

#ifndef NDEBUG
static inline GLenum GetState_TEXTURE_ENV_MODE() {
  OO_ENTER_OPENGL();

  GLint value;
  OOGL(glGetTexEnviv(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, &value));
  return value;
}
#endif

#define SetState_TEXTURE_ENV_MODE(VALUE) \
  OOGL(glTexEnvi(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, VALUE))

#if OO_MULTITEXTURE
#ifndef NDEBUG
static inline GLenum GetState_ACTIVE_TEXTURE() {
  OO_ENTER_OPENGL();

  GLint value;
  OOGL(glGetIntegerv(GL_ACTIVE_TEXTURE_ARB, &value));
  return value;
}
#endif

#define SetState_ACTIVE_TEXTURE(VALUE) OOGL(glActiveTextureARB(VALUE))

#ifndef NDEBUG
static inline GLenum GetState_CLIENT_ACTIVE_TEXTURE() {
  OO_ENTER_OPENGL();

  GLint value;
  OOGL(glGetIntegerv(GL_CLIENT_ACTIVE_TEXTURE_ARB, &value));
  return value;
}
#endif

#define SetState_CLIENT_ACTIVE_TEXTURE(VALUE) \
  OOGL(glClientActiveTextureARB(VALUE))

#else
static inline GLenum GetState_ACTIVE_TEXTURE(void) {}
static inline void SetState_ACTIVE_TEXTURE(GLenum value) {}
static inline GLenum GetState_CLIENT_ACTIVE_TEXTURE(void) {}
static inline void SetState_CLIENT_ACTIVE_TEXTURE(GLenum value) {}
#endif

static inline void SetState_CULL_FACE_MODE(GLint value) {
  OO_ENTER_OPENGL();

  OOGL(glCullFace(value));
}

#define SetState_FRONT_FACE(VALUE) OOGL(glFrontFace(VALUE))

#if OO_GL_STATE_VERIFICATION
/*	Debug mode implementation.
 */

namespace {
constexpr const char* kOOLogOpenGLVerifyDump =
    "rendering.opengl.state";  // an OO_LOG message class
}

/*
        VerifyOpenGLStateInternal(caller, nominalCaller, line)

        Tests whether the current OpenGL state matches the last set nominal
   state. If not, it logs the differences, then reverts to the last set nominal
   state (using SwitchOpenGLStateInternal()).
*/
static void VerifyOpenGLStateInternal(const char* caller,
                                      const char* nominalCaller,
                                      unsigned line) NONNULL_FUNC;

/*	GetCurrentOpenGLState(state)

        Retrieves the current OpenGL state.
*/
static void GetCurrentOpenGLState(OOOpenGLState* state) NONNULL_FUNC;

/*	StatesEqual(a, b)

        Test whether two states are identical.
*/
namespace {
static bool StatesEqual(
    const OOOpenGLState* a,
    const OOOpenGLState*
        b);  // no NONNULL_FUNC: the body asserts its arguments are non-null,
             // which GCC drops as always true under the attribute
             // (-Wnonnull-compare)
}  // namespace

#if OO_CHECK_GL_HEAVY
/*	OOGLNoteCurrentFunction(function, line)

        If OO_GL_STATE_VERIFICATION && OO_CHECK_GL_HEAVY, OOGL() calls
        OOGLNoteCurrentFunction() to help us keep track of where OpenGL calls
   have been made recently. The penultimate seen function is logged when we come
        across a state error, which is occasionally actually helpful.
*/

static const char* sLatestFunction = "<none yet>";
static unsigned sLatestLine;
static const char* sPreviousFunction = "<none yet>";
static unsigned sPreviousLine;
static bool sGLFunctionTracking = true;

void OOGLNoteCurrentFunction(const char* function, unsigned line) {
  if (sGLFunctionTracking) {
    if (function != sLatestFunction) {
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
static inline void SetFunctionTracking(bool value) {
  sGLFunctionTracking = value;
}

#else

namespace {
inline void OOGLNoteCurrentFunction(const char* /*function*/,
                                    unsigned /*line*/) {}
inline void SetFunctionTracking(bool /*value*/) {}
}  // namespace

#endif

void OOSetOpenGLState_(OOOpenGLStateID state, const char* function,
                       unsigned line) {
  OOCParameterAssert(static_cast<unsigned>(state) <
                     static_cast<unsigned>(
                         oo::ToUnderlying(OOOpenGLStateID::kInternalUseOnly)));

  OOGLNoteCurrentFunction(function, line);
  SetFunctionTracking(false);

  VerifyOpenGLStateInternal("OOSetOpenGLState", function, line);

  if (state != sCurrentStateID) {
    SwitchOpenGLStateInternal(
        &kStandardStates[oo::ToUnderlying(sCurrentStateID)],
        &kStandardStates[oo::ToUnderlying(state)]);
    sCurrentStateID = state;
  }

  SetFunctionTracking(true);
}

void OOVerifyOpenGLState_(const char* function, unsigned line) {
  OOGLNoteCurrentFunction(function, line);
  SetFunctionTracking(false);

  VerifyOpenGLStateInternal("OOVerifyOpenGLState", function, line);

  SetFunctionTracking(true);
}

static void GetCurrentOpenGLState(OOOpenGLState* state) {
  static const char* name = "<current state>";

  OOCParameterAssert(state != nullptr);
  OO_ENTER_OPENGL();
  memset(state, 0, sizeof *state);
  state->name = name;

#define ITEM_STATEFLAG(NAME) \
  OOGL(state->NAME = static_cast<StateFlag>(glIsEnabled(GL_##NAME)))
#define ITEM_CLIENTSTATEFLAG(NAME) OOGL(state->NAME = glIsEnabled(GL_##NAME))
#define ITEM_SPECIAL(NAME, _, __) state->NAME = GetState_##NAME()
#define ITEM_INT(NAME) OOGL(glGetIntegerv(GL_##NAME, &state->NAME))

#include "OOOpenGLStates.tbl"

  OOGL(glGetIntegerv(GL_BLEND_SRC, &state->BLEND_SRC));
  OOGL(glGetIntegerv(GL_BLEND_DST, &state->BLEND_DST));

#undef ITEM_STATEFLAG
#undef ITEM_CLIENTSTATEFLAG
#undef ITEM_SPECIAL
#undef ITEM_INT
}

namespace {
static bool StatesEqual(const OOOpenGLState* a, const OOOpenGLState* b) {
  OOCParameterAssert(a != nullptr && b != nullptr);

#define ITEM_STATEFLAG(NAME)                                  \
  do {                                                        \
    if (a->NAME != b->NAME && a->NAME != StateFlag::kMaybe && \
        b->NAME != StateFlag::kMaybe)                         \
      return false;                                           \
  } while (0)
#define ITEM_CLIENTSTATEFLAG(NAME)        \
  do {                                    \
    if (a->NAME != b->NAME) return false; \
  } while (0)
#define ITEM_SPECIAL(NAME, _, __)         \
  do {                                    \
    if (a->NAME != b->NAME) return false; \
  } while (0)
#define ITEM_INT(NAME)                    \
  do {                                    \
    if (a->NAME != b->NAME) return false; \
  } while (0)

#include "OOOpenGLStates.tbl"

#undef ITEM_STATEFLAG
#undef ITEM_CLIENTSTATEFLAG
#undef ITEM_SPECIAL
#undef ITEM_INT

  return true;
}
}  // namespace

static void VerifyOpenGLStateInternal(const char* caller,
                                      const char* nominalCaller,
                                      unsigned line) {
  OOOpenGLState currentState;
  GetCurrentOpenGLState(&currentState);

  OOCParameterAssert(sCurrentStateID <= OOOpenGLStateID::kInternalUseOnly);

  const OOOpenGLState* expectedState =
      &kStandardStates[oo::ToUnderlying(sCurrentStateID)];

  if (!StatesEqual(&currentState, expectedState)) {
    if (oo::log::willDisplay(kOOLogOpenGLVerifyDump)) {
      OO_LOG(kOOLogOpenGLVerifyDump,
             "Incorrect OpenGL state in {} (line {})->{}", nominalCaller,
             static_cast<unsigned>(line), caller);
#if OO_CHECK_GL_HEAVY
      OO_LOG(kOOLogOpenGLVerifyDump,
             "Previous OpenGL-using function: {} (line {})", sPreviousFunction,
             static_cast<unsigned>(sPreviousLine));
#endif
      OO_LOG(kOOLogOpenGLVerifyDump, "Expected previous state: {}",
             expectedState->name);

      oo::log::indent();

#define TEST_ITEM(NAME_, DISP_)                                             \
  if (currentState.NAME_ != expectedState->NAME_) {                         \
    OO_LOG(kOOLogOpenGLVerifyDump, "GL_{} should be {} but is {}.", #NAME_, \
           DISP_(expectedState->NAME_), DISP_(currentState.NAME_));         \
  }

#define ITEM_STATEFLAG(NAME)                      \
  if (expectedState->NAME != StateFlag::kMaybe) { \
    TEST_ITEM(NAME, StateFlagToString)            \
  }
#define ITEM_CLIENTSTATEFLAG(NAME) TEST_ITEM(NAME, OOGLFlagToString)
#define ITEM_SPECIAL(NAME, _, __) TEST_ITEM(NAME, OOGLFlagToString)
#define ITEM_INT(NAME) TEST_ITEM(NAME, OOGLEnumToString)

#include "OOOpenGLStates.tbl"

      if (currentState.BLEND_SRC != expectedState->BLEND_SRC ||
          currentState.BLEND_DST != expectedState->BLEND_DST) {
        OO_LOG(kOOLogOpenGLVerifyDump,
               "GL blend mode should be {}, {} but is {}, {}.",
               OOGLEnumToString(expectedState->BLEND_SRC),
               OOGLEnumToString(expectedState->BLEND_DST),
               OOGLEnumToString(currentState.BLEND_SRC),
               OOGLEnumToString(currentState.BLEND_DST));
      }

#undef ITEM_STATEFLAG
#undef ITEM_CLIENTSTATEFLAG
#undef ITEM_SPECIAL
#undef ITEM_INT

#undef TEST_ITEM

      oo::log::outdent();
    }

    SwitchOpenGLStateInternal(&currentState, expectedState);
  }
}

#else  // OO_GL_STATE_VERIFICATION
/*	Non-debug mode implementation.

        OOSetOpenGLState() performs a switch from the previous nominal state to
   the new nominal state, without checking that the previous nominal state
   matches the actual state. OOVerifyOpenGLState is a do-nothing macro.
*/

void OOSetOpenGLState(OOOpenGLStateID state) {
  OOCParameterAssert(static_cast<unsigned>(state) <
                     static_cast<unsigned>(
                         oo::ToUnderlying(OOOpenGLStateID::kInternalUseOnly)));

  if (state != sCurrentStateID) {
    SwitchOpenGLStateInternal(
        &kStandardStates[oo::ToUnderlying(sCurrentStateID)],
        &kStandardStates[oo::ToUnderlying(state)]);
    sCurrentStateID = state;
  }
}

#endif  // OO_GL_STATE_VERIFICATION

namespace {
static void SwitchOpenGLStateInternal(const OOOpenGLState* sourceState,
                                      const OOOpenGLState* targetState) {
  OOCParameterAssert(sourceState != nullptr && targetState != nullptr);
  OO_ENTER_OPENGL();

#define ITEM_STATEFLAG(NAME)                      \
  if (sourceState->NAME != targetState->NAME &&   \
      sourceState->NAME != StateFlag::kMaybe &&   \
      targetState->NAME != StateFlag::kMaybe) {   \
    if (targetState->NAME != StateFlag::kFalse) { \
      OOGL(glEnable(GL_##NAME));                  \
    } else {                                      \
      OOGL(glDisable(GL_##NAME));                 \
    }                                             \
  }
#define ITEM_CLIENTSTATEFLAG(NAME)              \
  if (sourceState->NAME != targetState->NAME) { \
    if (targetState->NAME) {                    \
      OOGL(glEnableClientState(GL_##NAME));     \
    } else {                                    \
      OOGL(glDisableClientState(GL_##NAME));    \
    }                                           \
  }
#define ITEM_SPECIAL(NAME, TYPE, _)             \
  if (sourceState->NAME != targetState->NAME) { \
    SetState_##NAME(targetState->NAME);         \
  }
#define ITEM_INT(NAME)                          \
  if (sourceState->NAME != targetState->NAME) { \
    SetState_##NAME(targetState->NAME);         \
  }

#include "OOOpenGLStates.tbl"

  /* some implementations, in non-shader mode, seem to throw out/reset
   * BlendFunc if Blend is disabled. Therefore, if coming from Blend=false
   * always reset the blend function even if this should be unnecessary
   * CIM: 3/1/13 */
  if (sourceState->BLEND_SRC != targetState->BLEND_SRC ||
      sourceState->BLEND_DST != targetState->BLEND_DST ||
      sourceState->BLEND == StateFlag::kFalse) {
    OOGL(glBlendFunc(targetState->BLEND_SRC, targetState->BLEND_DST));
  }

#undef ITEM_STATEFLAG
#undef ITEM_CLIENTSTATEFLAG
#undef ITEM_SPECIAL
#undef ITEM_INT
}
}  // namespace

void OOResetGLStateVerifier() {
  // State has been reset behind our backs, so to speak; don't verify.
  sCurrentStateID = OOOpenGLStateID::kInternalUseOnly;
}
