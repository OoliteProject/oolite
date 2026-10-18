/*

OOOpenGL.h

Do whatever is appropriate to get gl.h, glu.h and glext.h included.


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

#pragma once
// SDL OpenGL includes...

// GL_GLEXT_PROTOTYPES must be defined for the Linux build to use shaders, and
// for the macOS legacy-GL build: SDL's vendored glext (SDL_opengl_glext.h) then
// declares the ARB/3.x-named entry points that Apple's <OpenGL/gl.h> no longer
// declares, giving direct linkage against OpenGL.framework (no function-pointer
// table). macOS has no <GL/glext.h> or <GL/glu.h>; SDL_opengl.h is
// self-contained.
#if OOLITE_LINUX || defined(__APPLE__)
#ifndef GL_GLEXT_PROTOTYPES
#define GL_GLEXT_PROTOTYPES
#define __DEFINED_GL_GLEXT_PROTOTYPES
#endif // GL_GLEXT_PROTOTYPES
#endif // OOLITE_LINUX && !OOLITE_WINDOWS

// the standard SDL_opengl.h
#include <SDL3/SDL_opengl.h>

// include an up-to-date version of glext.h
// On Apple platforms, SDL_opengl.h above already bundles Mesa's glext
// (SDL_opengl_glext.h, including its prototypes when GL_GLEXT_PROTOTYPES is
// defined); the GL/ directory layout is Linux/X11-only. Apple's own
// <OpenGL/glext.h> must not be mixed in, as it typedefs GLhandleARB to
// void* while the rest of the tree uses Mesa's GLuint spelling.
// Toolchain test (__APPLE__) rather than OOLITE_MAC_OS_X: this header is
// also included from plain C data tables that do not import OOFoundation.h.
// GLU, in contrast, is not bundled by SDL and comes from the platform's
// OpenGL toolkit.
#if !defined(__APPLE__)
#include <GL/glext.h>
#include <GL/glu.h>
#else
#include <OpenGL/glu.h>
#endif

#ifdef __DEFINED_GL_GLEXT_PROTOTYPES
#undef GL_GLEXT_PROTOTYPES
#undef __DEFINED_GL_GLEXT_PROTOTYPES
#endif
