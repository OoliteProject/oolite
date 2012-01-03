/*

OOMacroOpenGL.h

Under Mac OS X, OpenGL performance can be improved somewhat by using macros
that call through to a function table directly, avoiding calls to functions
that just look up the current context and pass their parameters through to
a context-specific implementation function.

This header abstracts that behaviour for cross-platformity.

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

#if OOLITE_MAC_OS_X && !defined(OOLITE_NO_CGL_MACRO)

#if MAC_OS_X_VERSION_10_4 <= MAC_OS_X_VERSION_MAX_ALLOWED

#define CGL_MACRO_CACHE_RENDERER
#import <OpenGL/CGLMacro.h>

#define OO_ENTER_OPENGL CGL_MACRO_DECLARE_VARIABLES

#else

#import <OpenGL/CGLMacro.h>

#define OO_ENTER_OPENGL()	CGLContextObj CGL_MACRO_CONTEXT = CGLGetCurrentContext();	\

#endif
#else
// Not OS X
#define OO_ENTER_OPENGL()	do {} while (0)
#endif
