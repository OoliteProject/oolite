//	
//	OOCABufferedSound.m
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


@implementation OOCABufferedSound


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
			if (![self bufferSound:inPath]) OK = NO;
		}
	}
	
	if (!OK)
	{
		[self release];
		self = nil;
	}
	return self;
}


- (BOOL)bufferSound:(NSString *)inPath
{
	OOCASoundDecoder		*decoder;
	BOOL					OK = YES;
	
	decoder = [[OOCASoundDecoder alloc] initWithPath:inPath];
	if (nil == decoder) OK = NO;
	else
	{
		_name = [[decoder name] retain];
		_sampleRate = [decoder sampleRate];
		OK = [decoder readMonoCreatingBuffer:&_buffer withFrameCount:&_size];
	}
	
	[decoder release];
	return OK;
}


- (void)dealloc
{
	if (_buffer) free(_buffer);
	
	[super dealloc];
}


- (NSString *)name
{
	return _name;
}


- (void)play
{
	[[OOCASoundMixer mixer] playSound:self];
	/*
	OOSoundSource *source = [[OOSoundSource alloc] init];
	[source playSound:self];
	[source release];
	*/
}


- (BOOL)getAudioStreamBasicDescription:(AudioStreamBasicDescription *)outFormat
{
	assert(NULL != outFormat);
	
	outFormat->mSampleRate = _sampleRate;
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
	size_t					toCopy, remaining, underflow, offset;
	unsigned				i, count;
	
	offset = *ioContext;
	count = ioData->mNumberBuffers;
	
	if (offset < _size)
	{
		remaining = _size - offset;
		if (remaining < inNumFrames)
		{
			toCopy = remaining;
			underflow = inNumFrames - remaining;
		}
		else
		{
			toCopy = inNumFrames;
			underflow = 0;
		}
		
		*ioContext += toCopy;
		
		toCopy *= sizeof (float);
		
		for (i = 0; i != count; ++i)
		{
			bcopy(_buffer + offset, ioData->mBuffers[i].mData, toCopy);
		}
	}
	else
	{
		toCopy = 0;
		underflow = inNumFrames;
		*ioFlags |= kAudioUnitRenderAction_OutputIsSilence;
	}
	
	if (underflow)
	{
		underflow *= sizeof (float);
		for (i = 0; i != count; ++i)
		{
			bzero(ioData->mBuffers[i].mData + toCopy, underflow);
		}
	}
	
	return underflow ? endOfDataReached : noErr;
}

@end
