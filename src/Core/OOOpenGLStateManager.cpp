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

#include <cstddef>
#include <cstring>
#include <iterator>
#include <string>
#include <string_view>

#include "OOFunctionAttributes.h"
#include "OOMacroOpenGL.h"
#include "OOOpenGL.h"
#include "OOOpenGLExtensionManager.h"  // IWYU pragma: keep: the OpenGL feature macros its #if lines test
#include "oofnd/Log.hpp"
#include "oofnd/objc/OOAssert.h"

/*	DESIGN NOTES

        OOOpenGLState is the state the manager tracks: a name, one field per
   state item, and the GL blend mode. kStateItems, below the accessors, lists
   the items once, in order, each with how it is read, compared, logged and set;
   GetCurrentOpenGLState(), StatesEqual(), VerifyOpenGLStateInternal() and
   SwitchOpenGLStateInternal() loop over it. A static_assert after the list
   checks that the record has one field per item and nothing else but its name
   and the blend mode. The blend mode is two fields set with a single
   glBlendFunc() call, so it is managed separately, after the items.

        The states are defined as structs but referred to by index so that the
        definitions are all in one place. The actual definitions are just after
        the OOOpenGLState type (C++ has no forward declaration of a static const
        object).
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

/*	The state record. Field names are the OpenGL enumerants without the GL_
        prefix, and each field's type follows its item's kind (see kStateItems):
        StateFlag for an on/off flag, bool for a client-array flag, GLint for an
        integer, and the special item's own type.
*/
using OOOpenGLState = struct {
  std::string_view name;

  StateFlag LIGHTING;
  StateFlag LIGHT0;
  StateFlag LIGHT1;
  StateFlag LIGHT2;
  StateFlag LIGHT3;
  StateFlag LIGHT4;
  StateFlag LIGHT5;
  StateFlag LIGHT6;
  StateFlag LIGHT7;
  StateFlag TEXTURE_2D;
  StateFlag COLOR_MATERIAL;
  StateFlag BLEND;
  StateFlag FOG;
  StateFlag DEPTH_TEST;
  StateFlag NORMALIZE;
  StateFlag RESCALE_NORMAL;
  bool VERTEX_ARRAY;
  bool NORMAL_ARRAY;
  bool COLOR_ARRAY;
  bool INDEX_ARRAY;
  bool TEXTURE_COORD_ARRAY;
  bool EDGE_FLAG_ARRAY;
  bool DEPTH_WRITEMASK;
  StateFlag CULL_FACE;
  GLint SHADE_MODEL;
  GLenum TEXTURE_ENV_MODE;
  GLenum ACTIVE_TEXTURE;
  GLenum CLIENT_ACTIVE_TEXTURE;
  GLint CULL_FACE_MODE;
  GLint FRONT_FACE;

  // These require extra-special handling, because they're set with one
  // function.
  GLint BLEND_SRC;
  GLint BLEND_DST;
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

        These functions read and write the special and integer state items
        (glGetIntegerv() reads the integers). kStateItems names them, so they
        exist in every build; the GetState_ accessors are called only by the
        state verifier, while the SetState_ accessors are called in either mode.
*/
static inline bool GetState_DEPTH_WRITEMASK() {
  OO_ENTER_OPENGL();

  GLboolean value;
  OOGL(glGetBooleanv(GL_DEPTH_WRITEMASK, &value));
  return value;
}

static inline void SetState_DEPTH_WRITEMASK(bool value) {
  OO_ENTER_OPENGL();

  OOGL(glDepthMask(value));
}

static inline void SetState_SHADE_MODEL(GLint value) {
  OO_ENTER_OPENGL();

  OOGL(glShadeModel(value));
}

static inline GLenum GetState_TEXTURE_ENV_MODE() {
  OO_ENTER_OPENGL();

  GLint value;
  OOGL(glGetTexEnviv(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, &value));
  return value;
}

static inline void SetState_TEXTURE_ENV_MODE(GLenum value) {
  OO_ENTER_OPENGL();

  OOGL(glTexEnvi(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, value));
}

#if OO_MULTITEXTURE
static inline GLenum GetState_ACTIVE_TEXTURE() {
  OO_ENTER_OPENGL();

  GLint value;
  OOGL(glGetIntegerv(GL_ACTIVE_TEXTURE_ARB, &value));
  return value;
}

static inline void SetState_ACTIVE_TEXTURE(GLenum value) {
  OO_ENTER_OPENGL();

  OOGL(glActiveTextureARB(value));
}

static inline GLenum GetState_CLIENT_ACTIVE_TEXTURE() {
  OO_ENTER_OPENGL();

  GLint value;
  OOGL(glGetIntegerv(GL_CLIENT_ACTIVE_TEXTURE_ARB, &value));
  return value;
}

static inline void SetState_CLIENT_ACTIVE_TEXTURE(GLenum value) {
  OO_ENTER_OPENGL();

  OOGL(glClientActiveTextureARB(value));
}

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

static inline void SetState_FRONT_FACE(GLint value) {
  OO_ENTER_OPENGL();

  OOGL(glFrontFace(value));
}

/*	The state items

        kStateItems lists every item the state manager tracks, once, in the
   order the verifier reports them. Each is built by the function for its kind,
   which takes the item's field in OOOpenGLState and, for special and integer
   items, the functions that read and set it, so an item cannot be listed
   without them.

        StateFlagItem: read with glIsEnabled() and set with glEnable()/
   glDisable(). StateFlag::kMaybe, in either the source or the target state,
   leaves the item alone: it is not compared or set, nor reported when it is the
   expected value.
        ClientStateFlagItem: like a flag, but set with glEnableClientState()/
   glDisableClientState(), and never kMaybe.
        SpecialItem: read and set by its GetState_ and SetState_ functions.
        IntItem: read with glGetIntegerv() and set by its SetState_ function.

        The verifier shows flags, client-array flags and special items as
   ENABLED/disabled, whatever the special item's type, and integers as GL
   enumerants.
*/
namespace {

struct StateItem {
  // The GL enumerant without GL_, as the verifier logs it.
  std::string_view name;
  // The GL enumerant for flags and integers; 0 for special items.
  GLenum cap;
#if OO_GL_STATE_VERIFICATION
  void (*read)(const StateItem& item, OOOpenGLState& state);
  bool (*equal)(const OOOpenGLState& a, const OOOpenGLState& b);
  // True if the verifier reports the item, with the expected and the current
  // value as it shows them.
  bool (*mismatch)(const OOOpenGLState& expected, const OOOpenGLState& current,
                   std::string& shouldBe, std::string& is);
#endif
  void (*write)(const StateItem& item, const OOOpenGLState& source,
                const OOOpenGLState& target);
};

template <StateFlag OOOpenGLState::* Field>
constexpr StateItem StateFlagItem(std::string_view name, GLenum cap) {
  return {
      .name = name,
      .cap = cap,
#if OO_GL_STATE_VERIFICATION
      .read =
          [](const StateItem& item, OOOpenGLState& state) {
            OO_ENTER_OPENGL();
            OOGL(state.*Field = static_cast<StateFlag>(glIsEnabled(item.cap)));
          },
      .equal =
          [](const OOOpenGLState& a, const OOOpenGLState& b) {
            return a.*Field == b.*Field || a.*Field == StateFlag::kMaybe ||
                   b.*Field == StateFlag::kMaybe;
          },
      .mismatch =
          [](const OOOpenGLState& expected, const OOOpenGLState& current,
             std::string& shouldBe, std::string& is) {
            if (expected.*Field == StateFlag::kMaybe ||
                current.*Field == expected.*Field) {
              return false;
            }
            shouldBe = StateFlagToString(expected.*Field);
            is = StateFlagToString(current.*Field);
            return true;
          },
#endif
      .write =
          [](const StateItem& item, const OOOpenGLState& source,
             const OOOpenGLState& target) {
            OO_ENTER_OPENGL();
            if (source.*Field != target.*Field &&
                source.*Field != StateFlag::kMaybe &&
                target.*Field != StateFlag::kMaybe) {
              if (target.*Field != StateFlag::kFalse) {
                OOGL(glEnable(item.cap));
              } else {
                OOGL(glDisable(item.cap));
              }
            }
          },
  };
}

template <bool OOOpenGLState::* Field>
constexpr StateItem ClientStateFlagItem(std::string_view name, GLenum array) {
  return {
      .name = name,
      .cap = array,
#if OO_GL_STATE_VERIFICATION
      .read =
          [](const StateItem& item, OOOpenGLState& state) {
            OO_ENTER_OPENGL();
            OOGL(state.*Field = glIsEnabled(item.cap));
          },
      .equal = [](const OOOpenGLState& a,
                  const OOOpenGLState& b) { return a.*Field == b.*Field; },
      .mismatch =
          [](const OOOpenGLState& expected, const OOOpenGLState& current,
             std::string& shouldBe, std::string& is) {
            if (current.*Field == expected.*Field) return false;
            shouldBe = OOGLFlagToString(expected.*Field);
            is = OOGLFlagToString(current.*Field);
            return true;
          },
#endif
      .write =
          [](const StateItem& item, const OOOpenGLState& source,
             const OOOpenGLState& target) {
            OO_ENTER_OPENGL();
            if (source.*Field != target.*Field) {
              if (target.*Field) {
                OOGL(glEnableClientState(item.cap));
              } else {
                OOGL(glDisableClientState(item.cap));
              }
            }
          },
  };
}

template <auto Field, auto Get, auto Set>
constexpr StateItem SpecialItem(std::string_view name) {
  return {
      .name = name,
      .cap = 0,
#if OO_GL_STATE_VERIFICATION
      .read = [](const StateItem& /*item*/,
                 OOOpenGLState& state) { state.*Field = Get(); },
      .equal = [](const OOOpenGLState& a,
                  const OOOpenGLState& b) { return a.*Field == b.*Field; },
      .mismatch =
          [](const OOOpenGLState& expected, const OOOpenGLState& current,
             std::string& shouldBe, std::string& is) {
            if (current.*Field == expected.*Field) return false;
            shouldBe = OOGLFlagToString(static_cast<bool>(expected.*Field));
            is = OOGLFlagToString(static_cast<bool>(current.*Field));
            return true;
          },
#endif
      .write =
          [](const StateItem& /*item*/, const OOOpenGLState& source,
             const OOOpenGLState& target) {
            if (source.*Field != target.*Field) Set(target.*Field);
          },
  };
}

template <GLint OOOpenGLState::* Field, auto Set>
constexpr StateItem IntItem(std::string_view name, GLenum query) {
  return {
      .name = name,
      .cap = query,
#if OO_GL_STATE_VERIFICATION
      .read =
          [](const StateItem& item, OOOpenGLState& state) {
            OO_ENTER_OPENGL();
            OOGL(glGetIntegerv(item.cap, &(state.*Field)));
          },
      .equal = [](const OOOpenGLState& a,
                  const OOOpenGLState& b) { return a.*Field == b.*Field; },
      .mismatch =
          [](const OOOpenGLState& expected, const OOOpenGLState& current,
             std::string& shouldBe, std::string& is) {
            if (current.*Field == expected.*Field) return false;
            shouldBe = OOGLEnumToString(static_cast<GLenum>(expected.*Field));
            is = OOGLEnumToString(static_cast<GLenum>(current.*Field));
            return true;
          },
#endif
      .write =
          [](const StateItem& /*item*/, const OOOpenGLState& source,
             const OOOpenGLState& target) {
            if (source.*Field != target.*Field) Set(target.*Field);
          },
  };
}

constexpr StateItem kStateItems[] = {
    StateFlagItem<&OOOpenGLState::LIGHTING>("LIGHTING", GL_LIGHTING),
    StateFlagItem<&OOOpenGLState::LIGHT0>("LIGHT0", GL_LIGHT0),
    StateFlagItem<&OOOpenGLState::LIGHT1>("LIGHT1", GL_LIGHT1),
    StateFlagItem<&OOOpenGLState::LIGHT2>("LIGHT2", GL_LIGHT2),
    StateFlagItem<&OOOpenGLState::LIGHT3>("LIGHT3", GL_LIGHT3),
    StateFlagItem<&OOOpenGLState::LIGHT4>("LIGHT4", GL_LIGHT4),
    StateFlagItem<&OOOpenGLState::LIGHT5>("LIGHT5", GL_LIGHT5),
    StateFlagItem<&OOOpenGLState::LIGHT6>("LIGHT6", GL_LIGHT6),
    StateFlagItem<&OOOpenGLState::LIGHT7>("LIGHT7", GL_LIGHT7),
    StateFlagItem<&OOOpenGLState::TEXTURE_2D>("TEXTURE_2D", GL_TEXTURE_2D),
    StateFlagItem<&OOOpenGLState::COLOR_MATERIAL>("COLOR_MATERIAL",
                                                  GL_COLOR_MATERIAL),
    StateFlagItem<&OOOpenGLState::BLEND>("BLEND", GL_BLEND),
    StateFlagItem<&OOOpenGLState::FOG>("FOG", GL_FOG),
    StateFlagItem<&OOOpenGLState::DEPTH_TEST>("DEPTH_TEST", GL_DEPTH_TEST),
    StateFlagItem<&OOOpenGLState::NORMALIZE>("NORMALIZE", GL_NORMALIZE),
    StateFlagItem<&OOOpenGLState::RESCALE_NORMAL>("RESCALE_NORMAL",
                                                  GL_RESCALE_NORMAL),
    ClientStateFlagItem<&OOOpenGLState::VERTEX_ARRAY>("VERTEX_ARRAY",
                                                      GL_VERTEX_ARRAY),
    ClientStateFlagItem<&OOOpenGLState::NORMAL_ARRAY>("NORMAL_ARRAY",
                                                      GL_NORMAL_ARRAY),
    ClientStateFlagItem<&OOOpenGLState::COLOR_ARRAY>("COLOR_ARRAY",
                                                     GL_COLOR_ARRAY),
    ClientStateFlagItem<&OOOpenGLState::INDEX_ARRAY>("INDEX_ARRAY",
                                                     GL_INDEX_ARRAY),
    ClientStateFlagItem<&OOOpenGLState::TEXTURE_COORD_ARRAY>(
        "TEXTURE_COORD_ARRAY", GL_TEXTURE_COORD_ARRAY),
    ClientStateFlagItem<&OOOpenGLState::EDGE_FLAG_ARRAY>("EDGE_FLAG_ARRAY",
                                                         GL_EDGE_FLAG_ARRAY),
    // Smoothing flags are not included. They're set once at startup and never
    // disabled, except that they're not enabled if gpu-settings.plist says not
    // to.
    SpecialItem<&OOOpenGLState::DEPTH_WRITEMASK, GetState_DEPTH_WRITEMASK,
                SetState_DEPTH_WRITEMASK>("DEPTH_WRITEMASK"),
    StateFlagItem<&OOOpenGLState::CULL_FACE>("CULL_FACE", GL_CULL_FACE),
    IntItem<&OOOpenGLState::SHADE_MODEL, SetState_SHADE_MODEL>("SHADE_MODEL",
                                                               GL_SHADE_MODEL),
    SpecialItem<&OOOpenGLState::TEXTURE_ENV_MODE, GetState_TEXTURE_ENV_MODE,
                SetState_TEXTURE_ENV_MODE>("TEXTURE_ENV_MODE"),
    SpecialItem<&OOOpenGLState::ACTIVE_TEXTURE, GetState_ACTIVE_TEXTURE,
                SetState_ACTIVE_TEXTURE>("ACTIVE_TEXTURE"),
    SpecialItem<&OOOpenGLState::CLIENT_ACTIVE_TEXTURE,
                GetState_CLIENT_ACTIVE_TEXTURE, SetState_CLIENT_ACTIVE_TEXTURE>(
        "CLIENT_ACTIVE_TEXTURE"),
    IntItem<&OOOpenGLState::CULL_FACE_MODE, SetState_CULL_FACE_MODE>(
        "CULL_FACE_MODE", GL_CULL_FACE_MODE),
    IntItem<&OOOpenGLState::FRONT_FACE, SetState_FRONT_FACE>("FRONT_FACE",
                                                             GL_FRONT_FACE),
    // The blend mode is two values set with one glBlendFunc() call: it is not
    // an item, and each step handles it after the items.
};

// Something that converts to any field's type, to count an aggregate's fields.
// Declared only: it is used in unevaluated contexts.
struct AnyField {
  template <class T>
  constexpr operator T() const noexcept;
};

// How many initialisers T's braces take: its field count, for an aggregate of
// scalar and class fields.
template <class T, class... Fields>
consteval std::size_t AggregateFieldCount() {
  if constexpr (requires { T{Fields{}..., AnyField{}}; }) {
    return AggregateFieldCount<T, Fields..., AnyField>();
  } else {
    return sizeof...(Fields);
  }
}

// The record is the name, one field per item, and the blend mode's two values:
// a field without an item, or an item without a field, fails here.
static_assert(AggregateFieldCount<OOOpenGLState>() ==
              1 + std::size(kStateItems) + 2);

}  // namespace

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

  for (const StateItem& item : kStateItems) item.read(item, *state);

  OOGL(glGetIntegerv(GL_BLEND_SRC, &state->BLEND_SRC));
  OOGL(glGetIntegerv(GL_BLEND_DST, &state->BLEND_DST));
}

namespace {
static bool StatesEqual(const OOOpenGLState* a, const OOOpenGLState* b) {
  OOCParameterAssert(a != nullptr && b != nullptr);

  // The blend mode is not compared: a difference in it alone is not reported
  // or repaired.
  for (const StateItem& item : kStateItems) {
    if (!item.equal(*a, *b)) return false;
  }

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

      std::string shouldBe;
      std::string is;
      for (const StateItem& item : kStateItems) {
        if (item.mismatch(*expectedState, currentState, shouldBe, is)) {
          OO_LOG(kOOLogOpenGLVerifyDump, "GL_{} should be {} but is {}.",
                 item.name, shouldBe, is);
        }
      }

      if (currentState.BLEND_SRC != expectedState->BLEND_SRC ||
          currentState.BLEND_DST != expectedState->BLEND_DST) {
        OO_LOG(kOOLogOpenGLVerifyDump,
               "GL blend mode should be {}, {} but is {}, {}.",
               OOGLEnumToString(expectedState->BLEND_SRC),
               OOGLEnumToString(expectedState->BLEND_DST),
               OOGLEnumToString(currentState.BLEND_SRC),
               OOGLEnumToString(currentState.BLEND_DST));
      }

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

  for (const StateItem& item : kStateItems) {
    item.write(item, *sourceState, *targetState);
  }

  /* some implementations, in non-shader mode, seem to throw out/reset
   * BlendFunc if Blend is disabled. Therefore, if coming from Blend=false
   * always reset the blend function even if this should be unnecessary
   * CIM: 3/1/13 */
  if (sourceState->BLEND_SRC != targetState->BLEND_SRC ||
      sourceState->BLEND_DST != targetState->BLEND_DST ||
      sourceState->BLEND == StateFlag::kFalse) {
    OOGL(glBlendFunc(targetState->BLEND_SRC, targetState->BLEND_DST));
  }
}
}  // namespace

void OOResetGLStateVerifier() {
  // State has been reset behind our backs, so to speak; don't verify.
  sCurrentStateID = OOOpenGLStateID::kInternalUseOnly;
}
