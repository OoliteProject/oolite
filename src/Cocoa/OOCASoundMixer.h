/*

OOCASoundMixer.h

Class responsible for managing and mixing sound channels. This class is an
implementation detail. Do not use it directly; use an OOSoundSource to play an
OOSound.

OOCASound - Core Audio sound implementation for Oolite.
Copyright (C) 2005-2006  Jens Ayton

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
