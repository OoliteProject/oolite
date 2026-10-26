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

// GL_GLEXT_PROTOTYPES must be defined for the Linux and macOS builds to use shaders.
#if OOLITE_LINUX || defined(__APPLE__)
#ifndef GL_GLEXT_PROTOTYPES
#define GL_GLEXT_PROTOTYPES
#define __DEFINED_GL_GLEXT_PROTOTYPES
#endif // GL_GLEXT_PROTOTYPES
#endif // OOLITE_LINUX && !OOLITE_WINDOWS

// the standard SDL_opengl.h
#include <SDL3/SDL_opengl.h>

// include an up-to-date version of glext.h
#ifdef __APPLE__
#include <OpenGL/glext.h>
#include <OpenGL/glu.h>
#else
#include <GL/glext.h>
#include <GL/glu.h>
#endif

#ifdef __APPLE__
/*	The macOS legacy (2.1) context provides the GL 3.x features Oolite uses
        through extensions. Map the core names onto them.
 */
#define glGenVertexArrays glGenVertexArraysAPPLE
#define glBindVertexArray glBindVertexArrayAPPLE
#define glDeleteVertexArrays glDeleteVertexArraysAPPLE
#define glClampColor glClampColorARB
#define OO_MSAA_COLOR_RENDERBUFFER 1
#else
#define OO_MSAA_COLOR_RENDERBUFFER 0
#endif

#ifdef __DEFINED_GL_GLEXT_PROTOTYPES
#undef GL_GLEXT_PROTOTYPES
#undef __DEFINED_GL_GLEXT_PROTOTYPES
#endif
