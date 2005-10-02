//
// SDLMsuic.h: An encapsulation of SDL_mixer music functions for oolite.
//
// David Taylor, 2005-05-04
//

#import <Foundation/Foundation.h>
#include "SDL.h"
#include "SDL_mixer.h"

@interface OOMusic : NSObject
{
    // The SDL_mixer music structure encapsulated by an instance of OOMusic.
	Mix_Music *music;
   BOOL paused;
}

// Initialise the OOMusic instance from the contents of "filepath"
- (id) initWithContentsOfFile:(NSString*) filepath;

// Pause the music if this instance is currently playing
- (void) pause;
- (BOOL) isPaused;

// Returns YES if this instance is playing, otherwise NO.
- (BOOL) isPlaying;

// Start playing this instance of OOMusic, stopping any other instance
// currently playing.
- (BOOL) play;

// Stop the music if this instance is currently playing.
- (void) stop;

// Resume the music if this instance was paused. Has no effect if a different
// instance was paused.
- (void) resume;

// Rewind the music if this instance is the current instance.
- (void) goToBeginning;

@end
