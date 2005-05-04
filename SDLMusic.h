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
	NSString* filename;
	BOOL isPlaying;
	Mix_Music *music;
}

- (id) initWithContentsOfFile:(NSString*) filepath;
- (BOOL) pause;
- (BOOL) isPlaying;
- (BOOL) play;
- (BOOL) stop;
- (BOOL) resume;
- (void) goToBeginning;

@end
