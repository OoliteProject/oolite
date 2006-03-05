/*
 * This class encapsulates an SDL_Surface pointer so it can be stored in
 * an Objective-C collection.
 *
 * David Taylor 23-May-2005
 */
#ifndef SDLIMAGE_H
#define SDLIMAGE_H
#include <Foundation/Foundation.h>

#include <SDL.h>
#include <SDL_image.h>
#include <SDL_rotozoom.h>

@interface SDLImage : NSObject
{
	SDL_Surface *m_surface;
	NSSize m_size;
}

- (id) initWithSurface: (SDL_Surface *)surface;
- (SDL_Surface *) surface;
- (NSSize) size;
@end

#endif
