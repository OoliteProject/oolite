// Do whatever is appropriate to get gl.h, glu.h and glext.h included.

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
#include "SDL_opengl.h"

// include an up-to-date version of glext.h
#include "glext.h"

#endif
