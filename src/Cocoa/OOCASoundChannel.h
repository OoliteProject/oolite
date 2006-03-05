//	
//	OOCASoundChannel.h
//	CoreAudio sound implementation for Oolite
//	
/*

Copyright © 2005, Jens Ayton
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

- (BOOL)playSound:(OOSound *)inSound;
- (void)stop;

- (OOSound *)sound;

@end


@interface NSObject(OOCASoundChannelDelegate)

// Note: this will be called in a separate thread.
- (void)channel:(OOCASoundChannel *)inChannel didFinishPlayingSound:(OOSound *)inSound;

@end
