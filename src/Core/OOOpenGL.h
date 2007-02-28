/*

OOOpenGL.h

Do whatever is appropriate to get gl.h, glu.h and glext.h included.

For Oolite
Copyright (C) 2004  Giles C Williams

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

#ifndef GNUSTEP

// Apple OpenGL includes...
#include <OpenGL/OpenGL.h>
#include <OpenGL/gl.h>
#include <OpenGL/glu.h>
#include <OpenGL/glext.h>

#else

// SDL OpenGL includes...

// prevent the including of SDL_opengl.h loading a previous version of glext.h
#define NO_SDL_GLEXT

// the standard SDL_opengl.h
#include <SDL_opengl.h>

// include an up-to-date version of glext.h
#include <GL/glext.h>

#endif
