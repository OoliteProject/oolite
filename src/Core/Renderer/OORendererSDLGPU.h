/*

OORendererSDLGPU.h

Set-up for the SDL_GPU renderer backend (OORendererSDLGPU.c). The rest of
its interface is OORendererBackend.h.


Copyright (C) 2026 Oolite contributors

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

#ifndef OORENDERERSDLGPU_H
#define OORENDERERSDLGPU_H

#include <SDL3/SDL.h>
#include <stdbool.h>

/*  Use device, drawing the window target into an offscreen RGBA8 texture
    of width x height with a 32-bit float depth buffer. Returns false on
    failure, with the reason on stderr or in SDL_GetError().
*/
bool OORendererSDLGPUInit(SDL_GPUDevice* device, unsigned width, unsigned height);

// The window was resized: the window target follows, in backing pixels.
void OORendererSDLGPUResize(unsigned width, unsigned height);

/*  Show the window target in window, which the device has claimed: a blit
    to the swapchain texture, flipped from GL's bottom-up rows. Doesn't
    block; returns false and skips the frame if no swapchain texture is
    free (for example while the window is hidden).
*/
bool OORendererSDLGPUPresent(SDL_Window* window);

#endif
