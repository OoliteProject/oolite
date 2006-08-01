//	
//	OOCAStreamingSound.m
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

#import "OOCASoundInternal.h"
#import "OOCASoundDecoder.h"
#import "VirtualRingBuffer.h"

static BOOL					sFeederThreadActive = NO;
static NSMachPort			*sFeederPort = NULL;


typedef struct
{
	uint64_t				readOffset;
	VirtualRingBuffer		*bufferL,
							*bufferR;
	BOOL					atEnd,
							loop;
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
	kStreamBufferCount				= 100000,						// Number of frames in buffer
	kStreamBufferRefillThreshold	= kStreamBufferCount / 3,		// When to request refill
	kMinRebufferFrames				= kStreamBufferCount / 25,
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
	NSLog(@"%s called but ignored - please report.", __FUNCTION__);
	return NO;
}


- (BOOL)resume
{
	NSLog(@"%s called but ignored - please report.", __FUNCTION__);
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
	NSRunLoop			*runLoop;
	
	sFeederPort = [[NSMachPort alloc] init];
	if (nil == sFeederPort) return;
	
	sFeederThreadActive = YES;
	
	[sFeederPort setDelegate:[self class]];
	runLoop = [NSRunLoop currentRunLoop];
	[runLoop addPort:sFeederPort forMode:NSDefaultRunLoopMode];
	[[NSRunLoop currentRunLoop] run];
}


+ (void)handlePortMessage:(NSPortMessage *)inMessage
{
	NSArray							*components;
	NSData							*data;
	OOCAStreamingSound				*sound;
	OOCAStreamingSoundRenderContext	context = 0;
	
	switch ([inMessage msgid])
	{
		case kMsgFillBuffers:
			components = [inMessage components];
			data = [components objectAtIndex:0];
			if ([data length] == sizeof sound)
			{
				sound = *(OOCAStreamingSound **)[data bytes];
				data = [components objectAtIndex:1];
				if ([data length] == sizeof context)
				{
					context = *(OOCAStreamingSoundRenderContext *)[data bytes];
				}
				[sound fillBuffersWithContext:context];
				[sound release];
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
			frames = [_decoder streamStereoToBufferL:(float *)ptrL bufferR:(float *)ptrR maxFrames:frames];
			inContext->readOffset += frames;
			[inContext->bufferL didWriteLength:frames * sizeof (float)];
			[inContext->bufferR didWriteLength:frames * sizeof (float)];
			
			if ([_decoder atEnd])
			{
				if (inContext->loop) inContext->readOffset = 0;
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
	if (!context->atEnd && remaining < kStreamBufferRefillThreshold * sizeof (float) && nil != sFeederPort)
	{
		// Queue self for refilling
		// Supposedly this is more efficient than, say, MPQueues. Huh?
		NSAutoreleasePool		*pool;
		NSPortMessage			*msg;
		
		pool = [[NSAutoreleasePool alloc] init];
		[self retain];
		msg = [[NSPortMessage alloc] initWithSendPort:sFeederPort receivePort:nil components:[NSArray arrayWithObjects:[NSData dataWithBytes:&self length: sizeof self], [NSData dataWithBytes:&context length: sizeof context], nil]];
		[msg setMsgid:kMsgFillBuffers];
		[msg sendBeforeDate:[NSDate date]];
		[pool release];
	}
	
	return context->atEnd ? endOfDataReached : noErr;
}


- (NSString *)name
{
	return [_decoder name];
}

@end
