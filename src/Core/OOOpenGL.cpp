/*

OOOpenGL.m

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

#include "OOOpenGL.h"

#include "OOFunctionAttributes.h"
#include "OOLogging.h"
#include "OOMacroOpenGL.h"
#include "OOMaths.h"
#include "OOOpenGLExtensionManager.h"
#include "oofnd/Log.hpp"
#include "oofnd/String.hpp"
#include "oofnd/objc/OOAssert.h"

#ifndef NDEBUG
static const char* const kOOLogOpenGLStateDump = "rendering.opengl.stateDump";
#endif

static GLfloat sDisplayScaleFactor = 1.0f;

bool cxx_OOCheckOpenGLErrors(const char* format, ...) {
  va_list args;

  va_start(args, format);
  // formatted only when an error is found (a copy of the arguments each time it
  // is)
  bool errorOccurred =
      cxx_OOCheckOpenGLErrors([format, &args]() -> std::string {
        if (format == nullptr) return "<unknown>";
        va_list copy;
        va_copy(copy, args);
        std::string context = oo::str::vformat(format, copy);
        va_end(copy);
        return context;
      });
  va_end(args);

  return errorOccurred;
}

bool cxx_OOCheckOpenGLErrors(const std::function<std::string()>& context) {
  GLenum errCode;
  const GLubyte* errString = NULL;
  bool errorOccurred = false;
  static bool noReenter;

  if (noReenter) return false;
  noReenter = true;

  OO_ENTER_OPENGL();

  // Short-circut here, because glGetError() is quite expensive.
  if (oo::log::willDisplay("rendering.opengl.error")) {
    std::optional<std::string> contextText;  // built once, at the first error
    for (;;) {
      errCode = glGetError();

      if (errCode == GL_NO_ERROR) break;

      errorOccurred = true;
      errString = gluErrorString(errCode);
      if (!contextText.has_value()) contextText = context();

      // gluErrorString can answer NULL, which %s printed as (null).
      OO_LOG("rendering.opengl.error",
             "OpenGL error: \"{}\" ({:#x}), context: {}",
             errString != NULL ? reinterpret_cast<const char*>(errString)
                               : "(null)",
             errCode, *contextText);
    }
  }

#if OO_CHECK_GL_HEAVY
  if (errorOccurred) {
    OOLogIndent();
    LogOpenGLState();
    OOLogOutdent();
    while (glGetError() != 0) {
    }  // Suppress any errors caused by LogOpenGLState().
  }
#endif

  noReenter = false;
  return errorOccurred;
}

void OOGLWireframeModeOn(void) {
  OO_ENTER_OPENGL();

  /* Because of where this is called relative to the
   * OpenGLStateManager methods, pushAttrib/popAttrib causes the
   * OpenGL state to move away from where it should be. So, instead,
   * just switch polygon mode as needed. Linewidth is set already by
   * everything that needs it and not handled by the state
   * manager.  - CIM*/
  //	OOGL(glPushAttrib(GL_POLYGON_BIT | GL_LINE_BIT | GL_TEXTURE_BIT));
  OOGL(GLScaledLineWidth(1.0f));
  OOGL(glPolygonMode(GL_FRONT_AND_BACK, GL_LINE));
}

void OOGLWireframeModeOff(void) {
  OO_ENTER_OPENGL();
  OOGL(glPolygonMode(GL_FRONT_AND_BACK, GL_FILL));
  //	OOGL(glPopAttrib());
}

void GLDrawBallBillboard(GLfloat radius, GLfloat step, GLfloat z_distance) {
  if (EXPECT_NOT((radius <= 0) || (step < 1))) return;
  if (EXPECT_NOT(radius >= z_distance)) return;  // inside the sphere

  GLfloat i, delta;
  GLfloat s, c;
  GLfloat r;

  OO_ENTER_OPENGL();

  r = radius * z_distance / sqrt(z_distance * z_distance - radius * radius);
  delta = step * M_PI / 180.0f;  // Convert step from degrees to radians

  glVertex3i(0, 0, 0);
  for (i = 0; i < (M_PI * 2.0); i += delta) {
    s = r * sin(i);
    c = r * cos(i);
    glVertex3f(s, c, 0.0);
  }
  glVertex3f(0.0, r, 0.0);  // repeat the zero value to close
}

static void GLDrawOvalPoints(GLfloat x, GLfloat y, GLfloat z, NSSize siz,
                             GLfloat step) {
  GLfloat ww = 0.5 * siz.width;
  GLfloat hh = 0.5 * siz.height;
  GLfloat theta;
  GLfloat delta;

  OO_ENTER_OPENGL();

  delta = step * M_PI / 180.0f;

  for (theta = 0.0f; theta < (2.0f * M_PI); theta += delta) {
    glVertex3f(x + ww * sin(theta), y + hh * cos(theta), z);
  }
  glVertex3f(x, y + hh, z);
}

void GLDrawOval(GLfloat x, GLfloat y, GLfloat z, NSSize siz, GLfloat step) {
  OO_ENTER_OPENGL();

  OOGLBEGIN(GL_LINE_STRIP);
  GLDrawOvalPoints(x, y, z, siz, step);
  OOGLEND();
}

void GLDrawFilledOval(GLfloat x, GLfloat y, GLfloat z, NSSize siz,
                      GLfloat step) {
  OO_ENTER_OPENGL();

  OOGLBEGIN(GL_TRIANGLE_FAN);
  GLDrawOvalPoints(x, y, z, siz, step);
  OOGLEND();
}

void GLDrawPoints(OOGLVector* points, int n) {
  int i;
  OO_ENTER_OPENGL();
  OOGLBEGIN(GL_LINE_STRIP);
  for (i = 0; i < n; i++) {
    glVertex3f(points->x, points->y, points->z);
    points++;
  }
  OOGLEND();
  return;
}

void GLDrawFilledPoints(OOGLVector* points, int n) {
  int i;
  OO_ENTER_OPENGL();
  OOGLBEGIN(GL_TRIANGLE_FAN);
  for (i = 0; i < n; i++) {
    glVertex3f(points->x, points->y, points->z);
    points++;
  }
  OOGLEND();
  return;
}

void GLDrawQuadStrip(OOGLVector* points, int n) {
  int i;
  OO_ENTER_OPENGL();
  OOGLBEGIN(GL_QUAD_STRIP);
  for (i = 0; i < n; i++) {
    glVertex3f(points->x, points->y, points->z);
    points++;
  }
  OOGLEND();
  return;
}

void GLScaledLineWidth(GLfloat width) {
  OO_ENTER_OPENGL();
  glLineWidth(width * sDisplayScaleFactor);
}

void GLScaledPointSize(GLfloat size) {
  OO_ENTER_OPENGL();
  glPointSize(size * sDisplayScaleFactor);
}

GLfloat GLGetDisplayScaleFactor(void) { return sDisplayScaleFactor; }

void GLSetDisplayScaleFactor(GLfloat factor) {
  OOCParameterAssert(factor >= 0.0f && isfinite(factor));
  sDisplayScaleFactor = factor;
}

// MARK: LogOpenGLState() and helpers

#ifndef NDEBUG

static void GLDumpLightState(unsigned lightIdx);
static void GLDumpMaterialState(void);
static void GLDumpCullingState(void);
static void GLDumpFogState(void);
static void GLDumpStateFlags(void);

void LogOpenGLState(void) {
  unsigned i;

  if (!oo::log::willDisplay(kOOLogOpenGLStateDump)) return;

  OO_ENTER_OPENGL();

  OO_LOG(kOOLogOpenGLStateDump, "{}", "OpenGL state dump:");
  OOLogIndent();

  GLDumpMaterialState();
  GLDumpCullingState();
  if (glIsEnabled(GL_LIGHTING)) {
    OO_LOG(kOOLogOpenGLStateDump, "{}", "Lighting: ENABLED");
    for (i = 0; i != 8; ++i) {
      GLDumpLightState(i);
    }
  } else {
    OO_LOG(kOOLogOpenGLStateDump, "{}", "Lighting: disabled");
  }

  GLDumpFogState();
  GLDumpStateFlags();

  cxx_OOCheckOpenGLErrors("After state dump");

  OOLogOutdent();
}

std::string OOGLColorToString(GLfloat color[4]) {
#define COLOR_EQUAL(color, r, g, b, a) \
  (color[0] == (r) && color[1] == (g) && color[2] == (b) && color[3] == (a))
#define COLOR_CASE(r, g, b, a, str)                           \
  do {                                                        \
    if (COLOR_EQUAL(color, (r), (g), (b), (a))) return (str); \
  } while (0)

  COLOR_CASE(1, 1, 1, 1, "white");
  COLOR_CASE(0, 0, 0, 1, "black");
  COLOR_CASE(0, 0, 0, 0, "clear");
  COLOR_CASE(1, 0, 0, 1, "red");
  COLOR_CASE(0, 1, 0, 1, "green");
  COLOR_CASE(0, 0, 1, 1, "blue");
  COLOR_CASE(0, 1, 1, 1, "cyan");
  COLOR_CASE(1, 0, 1, 1, "magenta");
  COLOR_CASE(1, 1, 0, 1, "yellow");

  return oo::str::format("(%.2ff, %.2ff, %.2ff, %.2ff)", color[0], color[1],
                         color[2], color[3]);
}

static void GLDumpLightState(unsigned lightIdx) {
  bool enabled;
  GLenum lightID = GL_LIGHT0 + lightIdx;
  GLfloat color[4];

  OO_ENTER_OPENGL();

  OOGL(enabled = glIsEnabled(lightID));
  OO_LOG(kOOLogOpenGLStateDump, "Light {}: {}", static_cast<unsigned>(lightIdx),
         OOGLFlagToString(enabled));

  if (enabled) {
    OOLogIndent();

    OOGL(glGetLightfv(GL_LIGHT1, GL_AMBIENT, color));
    OO_LOG(kOOLogOpenGLStateDump, "Ambient: {}", OOGLColorToString(color));
    OOGL(glGetLightfv(GL_LIGHT1, GL_DIFFUSE, color));
    OO_LOG(kOOLogOpenGLStateDump, "Diffuse: {}", OOGLColorToString(color));
    OOGL(glGetLightfv(GL_LIGHT1, GL_SPECULAR, color));
    OO_LOG(kOOLogOpenGLStateDump, "Specular: {}", OOGLColorToString(color));

    OOLogOutdent();
  }
}

static void GLDumpMaterialState(void) {
  GLfloat color[4];
  GLfloat shininess;
  GLint shadeModel, blendSrc, blendDst, texMode;
  bool blending;

  OO_ENTER_OPENGL();

  OO_LOG(kOOLogOpenGLStateDump, "{}", "Material state:");
  OOLogIndent();

  OOGL(glGetMaterialfv(GL_FRONT, GL_AMBIENT, color));
  OO_LOG(kOOLogOpenGLStateDump, "Ambient: {}", OOGLColorToString(color));

  OOGL(glGetMaterialfv(GL_FRONT, GL_DIFFUSE, color));
  OO_LOG(kOOLogOpenGLStateDump, "Diffuse: {}", OOGLColorToString(color));

  OOGL(glGetMaterialfv(GL_FRONT, GL_EMISSION, color));
  OO_LOG(kOOLogOpenGLStateDump, "Emission: {}", OOGLColorToString(color));

  OOGL(glGetMaterialfv(GL_FRONT, GL_SPECULAR, color));
  OO_LOG(kOOLogOpenGLStateDump, "Specular: {}", OOGLColorToString(color));

  OOGL(glGetMaterialfv(GL_FRONT, GL_SHININESS, &shininess));
  OO_LOG(kOOLogOpenGLStateDump, "Shininess: {:g}", shininess);

  OOGL(OO_LOG(kOOLogOpenGLStateDump, "Colour material: {}",
              OOGLFlagToString(glIsEnabled(GL_COLOR_MATERIAL))));

  OOGL(glGetFloatv(GL_CURRENT_COLOR, color));
  OO_LOG(kOOLogOpenGLStateDump, "Current color: {}", OOGLColorToString(color));

  OOGL(glGetIntegerv(GL_SHADE_MODEL, &shadeModel));
  OO_LOG(kOOLogOpenGLStateDump, "Shade model: {}",
         OOGLEnumToString(shadeModel));

  OOGL(blending = glIsEnabled(GL_BLEND));
  OO_LOG(kOOLogOpenGLStateDump, "Blending: {}", OOGLFlagToString(blending));
  if (blending) {
    OOGL(glGetIntegerv(GL_BLEND_SRC, &blendSrc));
    OOGL(glGetIntegerv(GL_BLEND_DST, &blendDst));
    OO_LOG(kOOLogOpenGLStateDump, "Blend function: {}, {}",
           OOGLEnumToString(blendSrc), OOGLEnumToString(blendDst));
  }

  OOGL(glGetTexEnviv(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, &texMode));
  OO_LOG(kOOLogOpenGLStateDump, "Texture env mode: {}",
         OOGLEnumToString(texMode));

#if OO_MULTITEXTURE
  if (OOOpenGLExtensionManager::sharedManager()->textureUnitCount() > 1) {
    GLint textureUnit;
    OOGL(glGetIntegerv(GL_ACTIVE_TEXTURE_ARB, &textureUnit));
    OO_LOG(kOOLogOpenGLStateDump, "Active texture unit: {}",
           OOGLEnumToString(textureUnit));

    OOGL(glGetIntegerv(GL_CLIENT_ACTIVE_TEXTURE_ARB, &textureUnit));
    OO_LOG(kOOLogOpenGLStateDump, "Active client texture unit: {}",
           OOGLEnumToString(textureUnit));
  }
#endif

  OOLogOutdent();
}

static void GLDumpCullingState(void) {
  OO_ENTER_OPENGL();

  bool enabled;
  OOGL(enabled = glIsEnabled(GL_CULL_FACE));
  OO_LOG(kOOLogOpenGLStateDump, "Face culling: {}", OOGLFlagToString(enabled));
  if (enabled) {
    GLint value;

    OOLogIndent();

    OOGL(glGetIntegerv(GL_CULL_FACE_MODE, &value));
    OO_LOG(kOOLogOpenGLStateDump, "Cull face mode: {}",
           OOGLEnumToString(value));

    OOGL(glGetIntegerv(GL_FRONT_FACE, &value));
    OO_LOG(kOOLogOpenGLStateDump, "Front face direction: {}",
           OOGLEnumToString(value));

    OOLogOutdent();
  }
}

static void GLDumpFogState(void) {
  bool enabled;
  GLint value;
  GLfloat start, end, density, index;
  GLfloat color[4];

  OO_ENTER_OPENGL();

  OOGL(enabled = glIsEnabled(GL_FOG));
  OO_LOG(kOOLogOpenGLStateDump, "Fog: {}", OOGLFlagToString(enabled));
  if (enabled) {
    OOLogIndent();

    OOGL(glGetIntegerv(GL_FOG_MODE, &value));
    OO_LOG(kOOLogOpenGLStateDump, "Fog mode: {}", OOGLEnumToString(value));

    OOGL(glGetFloatv(GL_FOG_COLOR, color));
    OO_LOG(kOOLogOpenGLStateDump, "Fog colour: {}", OOGLColorToString(color));

    OOGL(glGetFloatv(GL_FOG_START, &start));
    OOGL(glGetFloatv(GL_FOG_END, &end));
    OO_LOG(kOOLogOpenGLStateDump, "Fog start, end: {:g}, {:g}", start, end);

    OOGL(glGetFloatv(GL_FOG_DENSITY, &density));
    OO_LOG(kOOLogOpenGLStateDump, "Fog density: {:g}", density);

    OOGL(glGetFloatv(GL_FOG_DENSITY, &index));
    OO_LOG(kOOLogOpenGLStateDump, "Fog index: {:g}", index);

    OOLogOutdent();
  }
}

static void GLDumpStateFlags(void) {
  OO_ENTER_OPENGL();

#define DUMP_STATE_FLAG(x) \
  OO_LOG(kOOLogOpenGLStateDump, #x ": {}", OOGLFlagToString(glIsEnabled(x)))
#define DUMP_GET_FLAG(x)                                              \
  do {                                                                \
    GLboolean flag;                                                   \
    glGetBooleanv(x, &flag);                                          \
    OO_LOG(kOOLogOpenGLStateDump, #x ": {}", OOGLFlagToString(flag)); \
  } while (0)

  OO_LOG(kOOLogOpenGLStateDump, "{}", "Selected state flags:");
  OOLogIndent();

  DUMP_STATE_FLAG(GL_VERTEX_ARRAY);
  DUMP_STATE_FLAG(GL_NORMAL_ARRAY);
  DUMP_STATE_FLAG(GL_TEXTURE_COORD_ARRAY);
  DUMP_STATE_FLAG(GL_COLOR_ARRAY);
  DUMP_STATE_FLAG(GL_TEXTURE_2D);
  DUMP_STATE_FLAG(GL_DEPTH_TEST);
  DUMP_GET_FLAG(GL_DEPTH_WRITEMASK);

  OOLogOutdent();

#undef DUMP_STATE_FLAG
}

#define CASE(x) \
  case x:       \
    return #x

std::string OOGLEnumToString(GLenum value) {
  switch (value) {
    // ShadingModel
    CASE(GL_FLAT);
    CASE(GL_SMOOTH);

    // BlendingFactorSrc/BlendingFactorDest
    CASE(GL_ZERO);
    CASE(GL_ONE);
    CASE(GL_DST_COLOR);
    CASE(GL_SRC_COLOR);
    CASE(GL_ONE_MINUS_DST_COLOR);
    CASE(GL_ONE_MINUS_SRC_COLOR);
    CASE(GL_SRC_ALPHA);
    CASE(GL_DST_ALPHA);
    CASE(GL_ONE_MINUS_SRC_ALPHA);
    CASE(GL_ONE_MINUS_DST_ALPHA);
    CASE(GL_SRC_ALPHA_SATURATE);

    // TextureEnvMode
    CASE(GL_MODULATE);
    CASE(GL_DECAL);
    CASE(GL_BLEND);
    CASE(GL_REPLACE);

    // FrontFaceDirection
    CASE(GL_CW);
    CASE(GL_CCW);

    // CullFaceMode
    CASE(GL_FRONT);
    CASE(GL_BACK);
    CASE(GL_FRONT_AND_BACK);

    // FogMode
    CASE(GL_LINEAR);
    CASE(GL_EXP);
    CASE(GL_EXP2);

#if OO_MULTITEXTURE
    // Texture units
#ifdef GL_TEXTURE0
#define TEXCASE CASE
#else
#define TEXCASE(x) CASE(x##_ARB)
#endif
    TEXCASE(GL_TEXTURE0);
    TEXCASE(GL_TEXTURE1);
    TEXCASE(GL_TEXTURE2);
    TEXCASE(GL_TEXTURE3);
    TEXCASE(GL_TEXTURE4);
    TEXCASE(GL_TEXTURE5);
    TEXCASE(GL_TEXTURE6);
    TEXCASE(GL_TEXTURE7);
    TEXCASE(GL_TEXTURE8);
    TEXCASE(GL_TEXTURE9);
    TEXCASE(GL_TEXTURE10);
    TEXCASE(GL_TEXTURE11);
    TEXCASE(GL_TEXTURE12);
    TEXCASE(GL_TEXTURE13);
    TEXCASE(GL_TEXTURE14);
    TEXCASE(GL_TEXTURE15);
#endif

    default:
      return oo::str::format("unknown: %u", value);
  }
}

std::string OOGLFlagToString(bool value) {
  return value ? "ENABLED" : "disabled";
}

#else

void LogOpenGLState(void) {}

#endif
