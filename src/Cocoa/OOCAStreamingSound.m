/*

OOCAStreamingSound.m

This class is an implementation detail. Do not use it directly; use OOSound.

OOCASound - Core Audio sound implementation for Oolite.
Copyright (C) 2005-2006 Jens Ayton

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

#import "OOCASoundInternal.h"
#import "OOCASoundDecoder.h"
#import "VirtualRingBuffer.h"


static NSString * const kOOLogSoundStreamingRefill		= @"sound.streaming.refill";
static NSString * const kOOLogSoundStreamingLoop		= @"sound.streaming.loop";
static NSString * const kOOLogSoundStreamingUnderflow	= @"sound.streaming.underflow";


static BOOL					sFeederThreadActive = NO;
static MPQueueID			sFeederQueue = kInvalidID;


typedef struct
{
	uint64_t				readOffset;
	VirtualRingBuffer		*bufferL,
							*bufferR;
	BOOL					atEnd,
							loop,
							empty;
} *OOCAStreamingSoundRenderContext;


@interface OOCAStreamingSound (Internal)

+ (void)feederThread:ignored;
- (BOOL)setUpAudioUnit;
- (void)fillBuffersWithContext:(OOCAStreamingSoundRenderContext)inContext;

@end


enum
{
	// Port messages
	kMsgFillBuffers			= 1UL
};


enum
{
	kStreamBufferCount				= 400000,						// Number of frames in buffer
	kStreamBufferRefillThreshold	= kStreamBufferCount / 3,		// When to request refill
	kMinRebufferFrames				= kStreamBufferCount / 10,		// When to ignore fill request (may get multiple requests before filler thread is scheduled)
	kStreamBufferSize				= kStreamBufferCount * sizeof (float)
};


@implementation OOCAStreamingSound

- (id)initWithDecoder:(OOCASoundDecoder *)inDecoder
{
	BOOL					OK = YES;
	
	assert(gOOSoundSetUp);
	if (gOOSoundBroken || nil == inDecoder) OK = NO;
	
	if (OK)
	{
		self = [super init];
		if (nil == self) OK = NO;
	}
	
	if (OK)
	{
		_decoder = [inDecoder retain];
	}
	
	if (!OK)
	{
		[self release];
		self = nil;
	}
	return self;
}


- (void)dealloc
{
	assert(![self isPlaying]);
	[_decoder release];
	
	[super dealloc];
}


- (void)play
{
	[[OOCASoundMixer mixer] playSound:self];
}


- (BOOL)pause
{
	OOLog(kOOLogDeprecatedMethodOOCASound, @"%s called but ignored - please report.", __FUNCTION__);
	return NO;
}


- (BOOL)resume
{
	OOLog(kOOLogDeprecatedMethodOOCASound, @"%s called but ignored - please report.", __FUNCTION__);
	return NO;
}


- (BOOL)prepareToPlayWithContext:(OOCASoundRenderContext *)outContext looped:(BOOL)inLoop
{
	BOOL							OK = YES;
	OOCAStreamingSoundRenderContext	context;
	
	if (OK)
	{
		context = calloc(1, sizeof *context);
		if (nil != context)
		{
			*outContext = (OOCASoundRenderContext)context;
			context->loop = inLoop;
			context->empty = YES;
		}
	}
	
	if (OK)
	{
		context->bufferL = [[VirtualRingBuffer alloc] initWithLength:kStreamBufferSize]; 
		context->bufferR = [[VirtualRingBuffer alloc] initWithLength:kStreamBufferSize]; 
		if (!context->bufferL || !context->bufferR)
		{
			OK = NO;
		}
	}
	
	if (OK && sFeederQueue == kInvalidID)
	{
		OK = (noErr == MPCreateQueue(&sFeederQueue)) && (sFeederQueue != kInvalidID);
	}
	
	if (OK && !sFeederThreadActive) [NSThread detachNewThreadSelector:@selector(feederThread:) toTarget:[OOCAStreamingSound class] withObject:nil];
	
	[self fillBuffersWithContext:context];
	
	return OK;
}


- (void)finishStoppingWithContext:(OOCASoundRenderContext)inContext
{
	OOCAStreamingSoundRenderContext	context;
	
	context = (OOCAStreamingSoundRenderContext) inContext;
	
	[context->bufferL release];
	[context->bufferR release];
	
	free(context);
}


+ (void)feederThread:ignored
{
	uintptr_t						msgID;
	void							*param1, *param2;
	OOCAStreamingSound				*sound;
	OOCAStreamingSoundRenderContext	context = 0;
	
	assert(sFeederQueue != kInvalidID);
	
	sFeederThreadActive = YES;
	
	for (;;)
	{
		if (noErr != MPWaitOnQueue(sFeederQueue, (void **)&msgID, &param1, &param2, kDurationForever))  continue;
		
		switch (msgID)
		{
			case kMsgFillBuffers:
				sound = param1;
				context = param2;
				[sound fillBuffersWithContext:context];
		}
	}
}


- (void)fillBuffersWithContext:(OOCAStreamingSoundRenderContext)inContext
{
	size_t					spaceL, spaceR;
	void					*ptrL, *ptrR;
	size_t					frames;
	
	[gOOCASoundSyncLock lock];
	spaceL = [inContext->bufferL lengthAvailableToWriteReturningPointer:&ptrL];
	spaceR = [inContext->bufferR lengthAvailableToWriteReturningPointer:&ptrR];
	
	// These ought to be the same
	frames = MIN(spaceL, spaceR) / sizeof (float);
	
	if (kMinRebufferFrames < frames)
	{
		if (![_decoder scanToOffset:inContext->readOffset])
		{
			inContext->atEnd = YES;
		}
		else
		{
			if (kStreamBufferCount < frames)
			{
				if (!inContext->empty) OOLog(kOOLogSoundStreamingUnderflow, @"Buffer underflow for sound %@.", self);
				inContext->empty = NO;
			}
			
			OOLog(kOOLogSoundStreamingRefill, @"Buffering %u frames for sound %@.", frames, self);
			frames = [_decoder streamStereoToBufferL:(float *)ptrL bufferR:(float *)ptrR maxFrames:frames];
			inContext->readOffset += frames;
			[inContext->bufferL didWriteLength:frames * sizeof (float)];
			[inContext->bufferR didWriteLength:frames * sizeof (float)];
			
			if ([_decoder atEnd])
			{
				if (inContext->loop)
				{
					OOLog(kOOLogSoundStreamingLoop, @"Resetting streaming sound %@ for looping.", self);
					inContext->readOffset = 0;
				}
				else inContext->atEnd = YES;
			}
		}
	}
	[gOOCASoundSyncLock unlock];
}


- (BOOL)getAudioStreamBasicDescription:(AudioStreamBasicDescription *)outFormat
{
	assert(NULL != outFormat);
	
	outFormat->mSampleRate = [_decoder sampleRate];
	outFormat->mFormatID = kAudioFormatLinearPCM;
	outFormat->mFormatFlags = kAudioFormatFlagsNativeFloatPacked | kLinearPCMFormatFlagIsNonInterleaved;
	outFormat->mBytesPerPacket = sizeof (float);
	outFormat->mFramesPerPacket = 1;
	outFormat->mBytesPerFrame = sizeof (float);
	outFormat->mChannelsPerFrame = 2;
	outFormat->mBitsPerChannel = sizeof (float) * 8;
	outFormat->mReserved = 0;
	
	return YES;
}


- (OSStatus)renderWithFlags:(AudioUnitRenderActionFlags *)ioFlags frames:(UInt32)inNumFrames context:(OOCASoundRenderContext *)ioContext data:(AudioBufferList *)ioData
{
	size_t							availL, availR, remaining, underflow;
	size_t							numBytes;
	void							*ptrL, *ptrR;
	OOCAStreamingSoundRenderContext	context;
	
	context = (OOCAStreamingSoundRenderContext)*ioContext;
	
	assert(2 == ioData->mNumberBuffers);
	
	availL = [context->bufferL lengthAvailableToReadReturningPointer:&ptrL];
	availR = [context->bufferR lengthAvailableToReadReturningPointer:&ptrR];
	
	numBytes = inNumFrames * sizeof (float);
	
	if (availR < availL) availL = availR;
	remaining = availL;
	if (numBytes < availL) availL = numBytes;
	
	bcopy(ptrL, ioData->mBuffers[0].mData, availL);
	bcopy(ptrR, ioData->mBuffers[1].mData, availL);
	
	[context->bufferL didReadLength:availL];
	[context->bufferR didReadLength:availL];
	
	if (availL < numBytes)
	{
		// Buffer underflow! Fill with silence.
		underflow = numBytes - availL;
		
		if (0 == availL) *ioFlags |= kAudioUnitRenderAction_OutputIsSilence;
		
		bzero(ioData->mBuffers[0].mData + availL, underflow);
		bzero(ioData->mBuffers[0].mData + availL, underflow);
	}
	
	remaining -= availL;
	if (!context->atEnd && remaining < kStreamBufferRefillThreshold * sizeof (float) && sFeederQueue != kInvalidID)
	{
		MPNotifyQueue(sFeederQueue, (void *)kMsgFillBuffers, self, context);
	}
	
	return context->atEnd ? endOfDataReached : noErr;
}


- (NSString *)name
{
	return [_decoder name];
}

@end
