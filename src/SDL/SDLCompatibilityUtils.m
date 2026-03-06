#import "SDLCompatibilityUtils.h"
#import <dlfcn.h>

// Define the SDL2 centering constant if not available
#ifndef SDL_WINDOWPOS_CENTERED
#define SDL_WINDOWPOS_CENTERED 0x2FFF0000
#endif

@implementation SDLCompatibilityUtils

+ (BOOL)isUsingSDL12Compat {
    return (dlsym(RTLD_DEFAULT, "SDL12COMPAT_GetWindow") != NULL);
}

+ (BOOL)isUsingSDL2Backend {
    // We check for the common shared object names for SDL2.
    // RTLD_NOLOAD ensures we only check if it's ALREADY loaded in the
    // process memory, rather than loading it ourselves.
    void *sdl2handle = dlopen("libSDL2-2.0.so.0", RTLD_NOLOAD | RTLD_LAZY);
    if (!sdl2handle) {
        sdl2handle = dlopen("libSDL2.so", RTLD_NOLOAD | RTLD_LAZY);
    }

    BOOL found = (sdl2handle != NULL);

    // If found, we must close the handle returned by dlopen
    if (sdl2handle) {
        dlclose(sdl2handle);
    }

    return found;
}

+ (BOOL)isUsingSDL3Backend {
    void *sdl3handle = dlopen("libSDL3.so.0", RTLD_NOLOAD | RTLD_LAZY);
    if (!sdl3handle) {
        sdl3handle = dlopen("libSDL3.so", RTLD_NOLOAD | RTLD_LAZY);
    }
    BOOL found = (sdl3handle != NULL);
    if (sdl3handle) dlclose(sdl3handle);
    return found;
}

+ (void)attemptSDL2WindowCentering {
    typedef void* (*PFN_SDL_GetWindowFromID)(unsigned int);
    typedef void (*PFN_SDL_SetWindowPosition)(void*, int, int);

    // Search the global scope for SDL2 symbols
    PFN_SDL_GetWindowFromID getWin = (PFN_SDL_GetWindowFromID)dlsym(RTLD_DEFAULT, "SDL_GetWindowFromID");
    PFN_SDL_SetWindowPosition setPos = (PFN_SDL_SetWindowPosition)dlsym(RTLD_DEFAULT, "SDL_SetWindowPosition");

    if (getWin && setPos) {
        // Iterate through potential window IDs
        for (unsigned int i = 1; i <= 10; i++) {
            void* win = getWin(i);
            if (win) {
                setPos(win, SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED);
                break; // Stop after centering the first window found
            }
        }
    }
}

@end