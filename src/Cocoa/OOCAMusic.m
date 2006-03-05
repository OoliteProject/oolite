//	
//	OOCAMusic.m
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

#import "OOCASoundInternal.h"
#import "VirtualRingBuffer.h"

static BOOL					sFeederThreadActive = NO;
static NSMachPort			*sFeederPort = NULL;


@interface OOMusic (Internal)

+ (void)feederThread:ignored;
- (BOOL)setUpAudioUnit;
- (void)fillBuffers;

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
	kStreamBufferSize				= kStreamBufferCount * sizeof (float)
};


@implementation OOMusic

- (id)initWithContentsOfFile:(NSString *)inPath
{
	BOOL					OK = YES;
	
	if (!gOOSoundSetUp) [OOSound setUp];
	if (gOOSoundBroken) OK = NO;
	
	if (OK)
	{
		self = [super init];
		if (nil != self)
		{
			_decoder = [[OOCASoundDecoder codecWithPath:inPath] retain];
			if (nil == _decoder) OK = NO;
		}
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
	if ([self isPlaying]) [self stop];
	[_decoder release];
	
	[super dealloc];
}


- (BOOL)play
{
	[[OOCASoundMixer mixer] playMusic:self];
	return YES;
}


- (BOOL)stop
{
	[[OOCASoundMixer mixer] stopMusic:self];
	return YES;
}


- (BOOL)isPaused
{
	return NO;
}


- (BOOL)isPlaying
{
	return [[OOCASoundMixer mixer] currentMusic] == self;
}


- (BOOL)pause
{
	NSLog(@"[OOMusic pause] called but ignored - please report.");
	return NO;
}


- (BOOL)resume
{
	NSLog(@"[OOMusic resume] called but ignored - please report.");
	return NO;
}


- (BOOL)prepareToPlayWithContext:(OOCASoundRenderContext *)outContext
{
	BOOL OK = YES;
	
	if (OK)
	{
		if (!_bufferL) _bufferL = [[VirtualRingBuffer alloc] initWithLength:kStreamBufferSize]; 
		if (!_bufferR) _bufferR = [[VirtualRingBuffer alloc] initWithLength:kStreamBufferSize]; 
		if (!_bufferL || !_bufferR)
		{
			NSLog(@"DEBUG OOMUSIC: failed to create ring buffers.");
			OK = NO;
		}
	}
	
	if (OK && !sFeederThreadActive) [NSThread detachNewThreadSelector:@selector(feederThread:) toTarget:[OOMusic class] withObject:nil];
	
	[self fillBuffers];
	
	return OK;
}


- (void)finishStoppingWithContext:(OOCASoundRenderContext *)outContext
{
	[_bufferL release];
	_bufferL = nil;
	[_bufferR release];
	_bufferR = nil;
	[_decoder rewindToBeginning];
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
	NSData					*data;
	OOMusic					*music;
	
	switch ([inMessage msgid])
	{
		case kMsgFillBuffers:
			data = [[inMessage components] objectAtIndex:0];
			if ([data length] == sizeof music)
			{
				music = *(OOMusic **)[data bytes];
				[music fillBuffers];
				[music release];
			}
	}
}


- (void)fillBuffers
{
	size_t					spaceL, spaceR;
	void					*ptrL, *ptrR;
	
	[gOOCASoundSyncLock lock];
	spaceL = [_bufferL lengthAvailableToWriteReturningPointer:&ptrL];
	spaceR = [_bufferR lengthAvailableToWriteReturningPointer:&ptrR];
	
	if (spaceR < spaceL) spaceL = spaceR;
	spaceL /= sizeof (float);
	
	if (0 != spaceL)
	{
		spaceL = [_decoder readStereoToBufferL:(float *)ptrL bufferR:(float *)ptrR maxFrames:(size_t)spaceL];
		[_bufferL didWriteLength:spaceL * sizeof (float)];
		[_bufferR didWriteLength:spaceL * sizeof (float)];
		
		if ([_decoder atEnd])
		{
			if (_loop) [_decoder rewindToBeginning];
			else _atEnd = YES;
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
	size_t					availL, availR, remaining, underflow;
	size_t					numBytes;
	void					*ptrL, *ptrR;
	
	assert(2 == ioData->mNumberBuffers);
	
	availL = [_bufferL lengthAvailableToReadReturningPointer:&ptrL];
	availR = [_bufferR lengthAvailableToReadReturningPointer:&ptrR];
	
	numBytes = inNumFrames * sizeof (float);
	
	if (availR < availL) availL = availR;
	remaining = availL;
	if (numBytes < availL) availL = numBytes;
	
	bcopy(ptrL, ioData->mBuffers[0].mData, availL);
	bcopy(ptrR, ioData->mBuffers[1].mData, availL);
	
	[_bufferL didReadLength:availL];
	[_bufferR didReadLength:availL];
	
	if (availL < numBytes)
	{
		// Buffer underflow! Fill with silence.
		underflow = numBytes - availL;
		
		if (0 == availL) *ioFlags |= kAudioUnitRenderAction_OutputIsSilence;
		
		bzero(ioData->mBuffers[0].mData + availL, underflow);
		bzero(ioData->mBuffers[0].mData + availL, underflow);
		if (_atEnd && !_loop) [self stop];
	}
	
	remaining -= availL;
	if (!_atEnd && remaining < kStreamBufferRefillThreshold * sizeof (float) && nil != sFeederPort)
	{
		// Queue self for refilling
		// Supposedly this is more efficient than, say, MPQueues. Huh?
		NSAutoreleasePool		*pool;
		NSPortMessage			*msg;
		
		pool = [[NSAutoreleasePool alloc] init];
		[self retain];
		msg = [[NSPortMessage alloc] initWithSendPort:sFeederPort receivePort:nil components:[NSArray arrayWithObject:[NSData dataWithBytes:&self length: sizeof self]]];
		[msg setMsgid:kMsgFillBuffers];
		[msg sendBeforeDate:[NSDate date]];
		[pool release];
	}
	
	return _atEnd ? endOfDataReached : noErr;
}


- (void)setLoop:(BOOL)inLoop
{
	_loop = !!inLoop;
}


- (BOOL)loop
{
	return _loop;
}


- (NSString *)name
{
	return [_decoder name];
}

@end
