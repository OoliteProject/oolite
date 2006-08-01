//	
//	OOCABufferedSound.m
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


@interface OOCABufferedSound (Private)

- (BOOL)bufferSound:(NSString *)inPath;

@end


@implementation OOCABufferedSound

#pragma mark NSObject

- (void)dealloc
{
	if (_bufferL) free(_bufferL);
	if (_stereo) _bufferR = NULL;
	else if (_bufferR) free(_bufferR);
	
	[super dealloc];
}


- (NSString *)description
{
	return [NSString stringWithFormat:@"<%@ %p>{\"%@\", %s, %g Hz}", [self className], self, [self name], _stereo ? "stereo" : "mono", _sampleRate];
}


#pragma mark OOSound

- (NSString *)name
{
	return _name;
}


- (void)play
{
	[[OOCASoundMixer mixer] playSound:self];
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


// Context is (offset << 1) | loop. Offset is initially 0.
- (BOOL)prepareToPlayWithContext:(OOCASoundRenderContext *)outContext looped:(BOOL)inLoop
{
	*outContext = inLoop ? 1 : 0;
	return YES;
}


- (OSStatus)renderWithFlags:(AudioUnitRenderActionFlags *)ioFlags frames:(UInt32)inNumFrames context:(OOCASoundRenderContext *)ioContext data:(AudioBufferList *)ioData
{
	size_t					toCopy, remaining, underflow, offset;
	BOOL					loop;
	
	loop = (*ioContext) & 1;
	offset = (*ioContext) >> 1;
	assert (ioData->mNumberBuffers == 2);
	
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
		
		bcopy(_bufferL + offset, ioData->mBuffers[0].mData, toCopy * sizeof (float));
		bcopy(_bufferR + offset, ioData->mBuffers[1].mData, toCopy * sizeof (float));
		
		if (underflow && loop)
		{
			offset = toCopy;
			toCopy = inNumFrames - toCopy;
			if (_size < toCopy) toCopy = _size;
			
			bcopy(_bufferL, ((float *)ioData->mBuffers[0].mData) + offset, toCopy * sizeof (float));
			bcopy(_bufferR, ((float *)ioData->mBuffers[1].mData) + offset, toCopy * sizeof (float));
			
			underflow -= toCopy;
			offset = 0;
		}
		
		*ioContext = ((offset + toCopy) << 1) | loop;
	}
	else
	{
		toCopy = 0;
		underflow = inNumFrames;
		*ioFlags |= kAudioUnitRenderAction_OutputIsSilence;
	}
	
	if (underflow)
	{
		bzero(ioData->mBuffers[0].mData + toCopy, underflow * sizeof (float));
		bzero(ioData->mBuffers[1].mData + toCopy, underflow * sizeof (float));
	}
	
	return underflow ? endOfDataReached : noErr;
}


#pragma mark OOCABufferedSound

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
		_name = [[inDecoder name] copy];
		_sampleRate = [inDecoder sampleRate];
		if ([inDecoder isStereo])
		{
			OK = [inDecoder readStereoCreatingLeftBuffer:&_bufferL rightBuffer:&_bufferR withFrameCount:&_size];
			_stereo = YES;
		}
		else
		{
			OK = [inDecoder readMonoCreatingBuffer:&_bufferL withFrameCount:&_size];
			_bufferR = _bufferL;
		}
	}
	
	if (!OK)
	{
		[self release];
		self = nil;
	}
	return self;
}

@end
