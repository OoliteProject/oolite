// Do whatever is appropriate to get gl.h, glu.h and glext.h included.

#ifndef GNUSTEP

#include <OpenGL/OpenGL.h>
#include <OpenGL/gl.h>
#include <OpenGL/glu.h>
#include <OpenGL/glext.h>

#else

#include "SDL_opengl.h"

#endif
