/*	test_OOOpenGLOnly.cpp
        Unit tests for OOOpenGLOnly.h (src/Core/OOOpenGLOnly.h), which includes
   gl.h, glu.h and glext.h the game's way. Since upstream #748 it is the SDL
   build's header only: no AppKit branch, no OOLITE_SDL of its own (that is
   OOFoundation.h's), SDL's GL extension header no longer suppressed
   (NO_SDL_GLEXT), and #pragma once. The cases compile the header on its own,
   twice, and check what it leaves defined. Run: bash
   meson test -C build/meson_test test_OOOpenGLOnly
*/

#include "OOOpenGLOnly.h"
#include "OOOpenGLOnly.h"  // #pragma once: a second include adds nothing
#include "oo_test.hpp"

namespace {

#ifdef NO_SDL_GLEXT
constexpr bool kSuppressesSDLGLExt = true;
#else
constexpr bool kSuppressesSDLGLExt = false;
#endif

#ifdef OOLITE_SDL
constexpr bool kDefinesOOLITE_SDL = true;
#else
constexpr bool kDefinesOOLITE_SDL = false;
#endif

}  // namespace

// The header no longer keeps SDL's own glext.h out, and leaves the platform
// macros to OOFoundation.h.
OO_TEST(sdlOnlyHeader) {
  OO_CHECK(!kSuppressesSDLGLExt);
  OO_CHECK(!kDefinesOOLITE_SDL);
}

// The GL names the game uses are there: gl.h's, glext.h's (the shader and
// framebuffer entry points' types) and the MSAA switch, off but on macOS.
OO_TEST(declaresTheGLTheGameUses) {
  GLuint name = 0;
  PFNGLGENVERTEXARRAYSPROC genVertexArrays = nullptr;
  PFNGLRENDERBUFFERSTORAGEMULTISAMPLEPROC storage = nullptr;
  OO_CHECK(name == 0 && genVertexArrays == nullptr && storage == nullptr);
  OO_CHECK(GL_COLOR_ATTACHMENT0 != 0);
#ifdef __APPLE__
  OO_CHECK(OO_MSAA_COLOR_RENDERBUFFER == 1);
#else
  OO_CHECK(OO_MSAA_COLOR_RENDERBUFFER == 0);
#endif
}

OO_TEST_MAIN()
