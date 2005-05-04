//
// SDLSound.h: Audio interface for oolite to the SDL library.
// Implements methods from NSSound which are used by oolite.
//
// Note this does not inherit from NSSound, but has the same interface.
// This was done so there is one less dependency on GNUstep AppKit.
//
// David Taylor, 2005-05-04
//

#import <Foundation/Foundation.h>
#include "SDL.h"
#include "SDL_mixer.h"

@interface OOSound : NSObject
{
	BOOL isPlaying;
	Mix_Chunk *sample;
	int currentChannel;
}

+ (void) channelDone:(int) channel;

- (id) initWithContentsOfFile:(NSString*) filepath byReference:(BOOL) ref;
- (BOOL) pause;
- (BOOL) isPlaying;
- (BOOL) play;
- (BOOL) stop;
- (BOOL) resume;

@end
