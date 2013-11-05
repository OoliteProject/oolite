/*

OOCAStreamingSound.m

This class is an implementation detail. Do not use it directly; use OOSound.


OOCASound - Core Audio sound implementation for Oolite.
Copyright (C) 2005-2013 Jens Ayton

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

*/

#import "OOCASoundInternal.h"
#import "OOCASoundDecoder.h"
#import "VirtualRingBuffer.h"
#import "NSThreadOOExtensions.h"


static NSString * const kOOLogSoundStreamingRefill		= @"sound.streaming.refill";
static NSString * const kOOLogSoundStreamingLoop		= @"sound.streaming.loop";
static NSString * const kOOLogSoundStreamingUnderflow	= @"sound.streaming.underflow";


static BOOL					sFeederThreadActive = NO;
static MPQueueID			sFeederQueue = kInvalidID;


// For IMP caching of VirtualRingBuffer methods
typedef UInt32 (*VRB_lengthAvailableToReadReturningPointerIMP)(id inSelf, SEL inSel, void ** outReturnedReadPointer);
typedef void (*VRB_didReadLengthIMP)(id inSelf, SEL inSel, UInt32 inLength);

#define kSEL_VRB_lengthAvailableToReadReturningPointer	@selector(lengthAvailableToReadReturningPointer:)
#define kSEL_VRB_didReadLength							@selector(didReadLength:)

static VRB_lengthAvailableToReadReturningPointerIMP		VRB_lengthAvailableToReadReturningPointer = NULL;
static VRB_didReadLengthIMP								VRB_didReadLength = NULL;


typedef struct
{
	uint64_t				readOffset;
	VirtualRingBuffer		*bufferL,
							*bufferR;
	int32_t					pendingCount;
	BOOL					atEnd,
							loop,
							empty,
							stopped;
} *OOCAStreamingSoundRenderContext;


@interface OOCAStreamingSound (Internal)

+ (void)feederThread:ignored;
- (BOOL)setUpAudioUnit;
- (void)fillBuffersWithContext:(OOCAStreamingSoundRenderContext)inContext;
- (void)releaseContext:(OOCAStreamingSoundRenderContext)inContext;

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
	
	if (OK && VRB_lengthAvailableToReadReturningPointer == NULL)
	{
		VRB_lengthAvailableToReadReturningPointer = (VRB_lengthAvailableToReadReturningPointerIMP)[VirtualRingBuffer instanceMethodForSelector:@selector(lengthAvailableToReadReturningPointer:)];
		VRB_didReadLength = (VRB_didReadLengthIMP)[VirtualRingBuffer instanceMethodForSelector:@selector(didReadLength:)];
		
		if (VRB_lengthAvailableToReadReturningPointer == NULL || VRB_didReadLength == NULL) OK = NO;
	}
	
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


- (BOOL)prepareToPlayWithContext:(OOCASoundRenderContext *)outContext looped:(BOOL)inLoop
{
	BOOL							OK = YES;
	OOCAStreamingSoundRenderContext	context = NULL;
	
	assert(outContext != NULL);
	
	if (OK)
	{
		context = calloc(1, sizeof *context);
		if (context != NULL)
		{
			*outContext = (OOCASoundRenderContext)context;
			context->loop = inLoop;
			context->empty = YES;
		}
		else
		{
			OK = NO;
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
	
	if (OK)
	{
		if (!sFeederThreadActive) [NSThread detachNewThreadSelector:@selector(feederThread:) toTarget:[OOCAStreamingSound class] withObject:nil];
		[self retain];	// Will be released by fillBuffers... when stopped is true and pendingCount is 0.
		++context->pendingCount;
		[self fillBuffersWithContext:context];
	}
	
	return OK;
}


- (void)finishStoppingWithContext:(OOCASoundRenderContext)inContext
{
	OOCAStreamingSoundRenderContext	context;
	
	context = (OOCAStreamingSoundRenderContext) inContext;
	
	[gOOCASoundSyncLock lock];
	context->stopped = YES;
	if (0 == context->pendingCount)
	{
		OOLog(@"sound.streaming.releaseContext.immediate", @"Streaming sound %@ stopped with 0 pendingCount, releasing context.", self);
		[self releaseContext:context];
	}
	else
	{
		OOLog(@"sound.streaming.releaseContext.deferring", @"Streaming sound %@ stopped with %i pendingCount, deferring release.", self, context->pendingCount);
	}
	[gOOCASoundSyncLock unlock];
}


+ (void)feederThread:(id)ignored
{
	uintptr_t						msgID;
	void							*param1, *param2;
	OOCAStreamingSound				*sound;
	OOCAStreamingSoundRenderContext	context = 0;
	NSAutoreleasePool				*pool = nil;
	
	assert(sFeederQueue != kInvalidID);
	
	[NSThread ooSetCurrentThreadName:@"OOCAStreamingSound feeder thread"];
	sFeederThreadActive = YES;
	
	for (;;)
	{
		if (noErr != MPWaitOnQueue(sFeederQueue, (void **)&msgID, &param1, &param2, kDurationForever))  continue;
		
		pool = [[NSAutoreleasePool alloc] init];
		
		switch (msgID)
		{
			case kMsgFillBuffers:
				sound = param1;
				context = param2;
				[sound fillBuffersWithContext:context];
		}
		
		[pool release];
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
			
			OOLog(kOOLogSoundStreamingRefill, @"Buffering %zu frames for sound %@.", frames, self);
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
	
	OSAtomicAdd32(-1, &inContext->pendingCount);
	if (inContext->pendingCount == 0 && inContext->stopped)
	{
		OOLog(@"sound.streaming.releaseContext.deferred", @"Stopped streaming sound %@ reached 0 pendingCount, releasing context.", self);
		[self releaseContext:inContext];
	}
	
	[gOOCASoundSyncLock unlock];
}


- (void)releaseContext:(OOCAStreamingSoundRenderContext)inContext
{
	[inContext->bufferL release];
	[inContext->bufferR release];
	free(inContext);
	[self autorelease];
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
	uint32_t						available, availL, availR, remaining, underflow;
	uint32_t						numBytes;
	void							*ptrL, *ptrR;
	OOCAStreamingSoundRenderContext	context;
	
	context = (OOCAStreamingSoundRenderContext)*ioContext;
	
	assert(2 == ioData->mNumberBuffers);
	
	availL = VRB_lengthAvailableToReadReturningPointer(context->bufferL, kSEL_VRB_lengthAvailableToReadReturningPointer, &ptrL);
	availR = VRB_lengthAvailableToReadReturningPointer(context->bufferR, kSEL_VRB_lengthAvailableToReadReturningPointer, &ptrR);
	
	numBytes = inNumFrames * sizeof (float);
	
	available = MIN(availL, availR);
	remaining = available;
	if (numBytes < available) available = numBytes;
	
	memcpy(ioData->mBuffers[0].mData, ptrL, available);
	memcpy(ioData->mBuffers[1].mData, ptrR, available);
	
	VRB_didReadLength(context->bufferL, kSEL_VRB_didReadLength, available);
	VRB_didReadLength(context->bufferR, kSEL_VRB_didReadLength, available);
	
	if (available < numBytes)
	{
		// Buffer underflow! Fill with silence.
		underflow = numBytes - available;
		
		if (0 == available) *ioFlags |= kAudioUnitRenderAction_OutputIsSilence;
		
		memset(ioData->mBuffers[0].mData + available, 0, underflow);
		memset(ioData->mBuffers[1].mData + available, 0, underflow);
	}
	
	OOCASoundVerifyBuffers(ioData, inNumFrames, self);
	
	remaining -= available;
	if (!context->atEnd && remaining < kStreamBufferRefillThreshold * sizeof (float) && sFeederQueue != kInvalidID)
	{
		OSAtomicAdd32(1, &context->pendingCount);
		MPNotifyQueue(sFeederQueue, (void *)kMsgFillBuffers, self, context);
	}
	
	return (context->atEnd && remaining == 0) ? endOfDataReached : noErr;
}


- (NSString *)name
{
	return [_decoder name];
}

@end
