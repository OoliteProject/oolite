//	
//	OOCASoundInternal.h
//	CoreAudio sound implementation for Oolite
//	
/*

Copyright © 2005-2006 Jens Ayton
All rights reserved.

This work is licensed under the Creative Commons Attribution-ShareAlike License.
To view a copy of this license, visit http://creativecommons.org/licenses/by-sa/2.0/
or send a letter to Creative Commons, 559 Nathan Abbott Way, Stanford, California 94305, USA.

You are free:

•	to copy, distribute, display, and perform the work
•	to make derivative works

Under the following conditions:

•	Attribution. You must give the original author credit.
•	Share Alike. If you alter, transform, or build upon this work,
	you may distribute the resulting work only under a license identical to this one.

For any reuse or distribution, you must make clear to others the license terms of this work.

Any of these conditions can be waived if you get permission from the copyright holder.

Your fair use and other rights are in no way affected by the above.

*/

#import "OOCASound.h"
#import "OOCASoundMixer.h"
#import "OOCASoundChannel.h"
#import "OOCABufferedSound.h"
#import "OOCAStreamingSound.h"
#import <CoreAudio/CoreAudio.h>
#import <AudioToolbox/AudioToolbox.h>
#import "OOErrorDescription.h"
#import "OOCASoundSource.h"


@interface OOSound (Internal)

- (OSStatus)renderWithFlags:(AudioUnitRenderActionFlags *)ioFlags frames:(UInt32)inNumFrames context:(OOCASoundRenderContext *)ioContext data:(AudioBufferList *)ioData;

// Called by -play and -stop only if in appropriate state
- (BOOL)prepareToPlayWithContext:(OOCASoundRenderContext *)outContext looped:(BOOL)inLoop;
- (void)finishStoppingWithContext:(OOCASoundRenderContext)inContext;

- (BOOL)getAudioStreamBasicDescription:(AudioStreamBasicDescription *)outFormat;

- (void)incrementPlayingCount;
- (void)decrementPlayingCount;

@end


@interface OOCASoundMixer (Internal)

- (BOOL)connectChannel:(OOCASoundChannel *)inChannel;
- (OSStatus)disconnectChannel:(OOCASoundChannel *)inChannel;

@end


extern BOOL		gOOSoundSetUp, gOOSoundBroken;
extern NSLock	*gOOCASoundSyncLock;
