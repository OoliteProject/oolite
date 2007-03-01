/*

SDLImage.m
By David Taylor

This class encapsulates an SDL_Surface pointer so it can be stored in an
Objective-C collection.

Oolite
Copyright (C) 2004-2007 Giles C Williams and contributors

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

#ifndef SDLIMAGE_H
#define SDLIMAGE_H
#include <Foundation/Foundation.h>

#include <SDL.h>
#include <SDL_image.h>

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
