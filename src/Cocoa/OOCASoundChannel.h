/*

OOCASoundChannel.h

A channel for audio playback.

This class is an implementation detail. Do not use it directly; use an
OOSoundSource to play an OOSound.

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
#import <AudioToolbox/AudioToolbox.h>

@class OOSound;


typedef uintptr_t OOCASoundRenderContext;
typedef  OSStatus (*OOCASoundChannel_RenderIMP)(id inSelf, SEL inSelector, AudioUnitRenderActionFlags *ioFlags, UInt32 inNumFrames, OOCASoundRenderContext *ioContext, AudioBufferList *ioData);


@interface OOCASoundChannel: NSObject
{
	OOCASoundChannel			*_next;
	id							_delegate;
	AUNode						_subGraphNode;
	AUGraph						_subGraph;
	AUNode						_node;
	AudioUnit					_au;
	OOSound						*_sound;
	OOCASoundRenderContext		_context;
	OOCASoundChannel_RenderIMP	Render;
	uint8_t						_state,
								_id,
								_stopReq;
	OSStatus					_error;
}

+ (BOOL)setUp;
+ (void)tearDown;

- (id)initWithID:(uint32_t)inID auGraph:(AUGraph)inGraph;

- (void)setDelegate:(id)inDelegate;

- (uint32_t)ID;

- (AUNode)auSubGraphNode;

// Unretained pointer used to maintain simple stack
- (OOCASoundChannel *)next;
- (void)setNext:(OOCASoundChannel *)inNext;

- (BOOL)playSound:(OOSound *)inSound looped:(BOOL)inLoop;
- (void)stop;

- (OOSound *)sound;

- (BOOL)isOK;

@end


@interface NSObject(OOCASoundChannelDelegate)

// Note: this will be called in a separate thread.
- (void)channel:(OOCASoundChannel *)inChannel didFinishPlayingSound:(OOSound *)inSound;

@end
