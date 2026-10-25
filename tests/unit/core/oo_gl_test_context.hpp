/*	oo_gl_test_context.hpp
	A current OpenGL context for the unit tests of converted GL classes (tests/unit/core; bead
	oo-z1s4, proposed ADR-0056 amendment oo-z1s4). The game's GL code needs a real context: it
	reads the driver's strings and limits, and it sets state that the tests read back.

	OOTestGLContext() makes, once per process, one hidden 16x16 SDL window with an OpenGL context
	of SDL's default kind (a compatibility context, as the game's), makes it current and keeps it
	for the rest of the process. The window is never shown, so it never takes the foreground. It
	answers false when the machine has no OpenGL; a test then fails, it does not skip.
*/

#ifndef OO_GL_TEST_CONTEXT_HPP
#define OO_GL_TEST_CONTEXT_HPP

#include <SDL3/SDL.h>

#include <cstdio>


inline bool OOTestGLContext()
{
	static const bool ready = []
	{
		if (!SDL_Init(SDL_INIT_VIDEO))
		{
			std::fprintf(stderr, "OOTestGLContext: SDL_Init: %s\n", SDL_GetError());
			return false;
		}
		SDL_Window *window = SDL_CreateWindow("oolite unit test", 16, 16, SDL_WINDOW_OPENGL | SDL_WINDOW_HIDDEN);
		if (window == nullptr)
		{
			std::fprintf(stderr, "OOTestGLContext: SDL_CreateWindow: %s\n", SDL_GetError());
			return false;
		}
		SDL_GLContext context = SDL_GL_CreateContext(window);
		if (context == nullptr || !SDL_GL_MakeCurrent(window, context))
		{
			std::fprintf(stderr, "OOTestGLContext: no OpenGL context: %s\n", SDL_GetError());
			return false;
		}
		return true;
	}();
	return ready;
}

#endif	// OO_GL_TEST_CONTEXT_HPP
