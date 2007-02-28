/*

OOCASoundInternal.h

Declarations used within OOCASound. This file should not be used by client
code.

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
