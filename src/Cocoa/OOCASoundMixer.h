//	
//	OOCASoundMixer.h
//	CoreAudio sound implementation for Oolite
//	
/*

Copyright © 2005 Jens Ayton
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

#import <Foundation/Foundation.h>
#import <mach/port.h>
#import <AudioToolbox/AudioToolbox.h>

@class OOMusic, OOCASoundChannel, OOSoundSource;


#define kMixerGeneralChannels		32
#define SUPPORT_SOUND_INSPECTOR		0


@interface OOCASoundMixer: NSObject
{
	OOCASoundChannel			*_channels[kMixerGeneralChannels];
	OOCASoundChannel			*_freeList;
	NSLock						*_listLock;
	
	AUGraph						_graph;
	AUNode						_mixerNode;
	AUNode						_outputNode;
	AudioUnit					_mixerUnit;
	
	uint32_t					_activeChannels;
	uint32_t					_maxChannels;
	uint32_t					_playMask;
	
#if SUPPORT_SOUND_INSPECTOR
	IBOutlet NSMatrix			*checkBoxes;
	IBOutlet NSTextField		*currentField;
	IBOutlet NSTextField		*maxField;
	IBOutlet NSTextField		*loadField;
	IBOutlet NSProgressIndicator *loadBar;
#endif
}

// Singleton accessor
+ (OOCASoundMixer *)mixer;
+ (void)destroy;	// releases singleton

- (void)playSound:(OOSound *)inSound;

- (void)update;

- (void)setMasterVolume:(float)inVolume;

- (OOCASoundChannel *)popChannel;
- (void)pushChannel:(OOCASoundChannel *)inChannel;

@end
