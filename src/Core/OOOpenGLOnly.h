/*

OOOpenGL.h

Do whatever is appropriate to get gl.h, glu.h and glext.h included.


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

#ifndef OOLITE_SDL
#if (!OOLITE_MAC_OS_X && GNUSTEP) && !defined(OOLITE_SDL_MAC)
#define OOLITE_SDL	1
#endif
#endif

#if OOLITE_MAC_OS_X

// Apple OpenGL includes...
#include <OpenGL/OpenGL.h>
#include <OpenGL/gl.h>
#include <OpenGL/glu.h>
#include <OpenGL/glext.h>

#elif OOLITE_SDL

// SDL OpenGL includes...

// prevent the including of SDL_opengl.h loading a previous version of glext.h
#define NO_SDL_GLEXT

// GL_GLEXT_PROTOTYPES must be defined for the Linux build to use shaders.
#if OOLITE_LINUX
#ifndef GL_GLEXT_PROTOTYPES
#define GL_GLEXT_PROTOTYPES
#define	__DEFINED_GL_GLEXT_PROTOTYPES
#endif	// GL_GLEXT_PROTOTYPES
#endif	// OOLITE_LINUX && !OOLITE_WINDOWS

// the standard SDL_opengl.h
#include <SDL_opengl.h>

// include an up-to-date version of glext.h
#include <GL/glext.h>

#ifdef __DEFINED_GL_GLEXT_PROTOTYPES
#undef GL_GLEXT_PROTOTYPES
#undef __DEFINED_GL_GLEXT_PROTOTYPES
#endif

#else	// Not OS X or SDL

#error OOOpenGL.h: unknown target!

#endif
