#ifndef SDLCOMPATIBILITYUTILS_H
#define SDLCOMPATIBILITYUTILS_H

#import <Foundation/Foundation.h>
#import <dlfcn.h>

#define SDL_POS_CENTERED 0x2FFF0000

@interface SDLCompatibilityUtils : NSObject

/**
 * Returns YES if the game is running via the sdl12-compat bridge.
 */
+ (BOOL)isUsingSDL12Compat;

/**
 * Returns YES if the SDL2 library is currently resident in memory.
 */
+ (BOOL)isUsingSDL2Backend;

/**
 * Returns YES if the SDL3 library is currently resident in memory.
 */
+ (BOOL)isUsingSDL3Backend;

/**
 * Attempts to find an active SDL2 window and center it using the
 * underlying SDL2 API.
 */
+ (void)attemptSDL2WindowCentering;

@end

#endif // SDLCOMPATIBILITYUTILS_H
