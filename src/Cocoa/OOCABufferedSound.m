/*

OOCABufferedSound.m


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


@interface OOCABufferedSound (Private)

- (BOOL)bufferSound:(NSString *)inPath;

@end


@implementation OOCABufferedSound

#pragma mark NSObject

- (void)dealloc
{
	free(_bufferL);
	_bufferL = NULL;
	
	if (_stereo)  free(_bufferR);
	_bufferR = NULL;
	
	[super dealloc];
}


- (NSString *)description
{
	return [NSString stringWithFormat:@"<%@ %p>{\"%@\", %s, %g Hz, %lu bytes}", [self className], self, [self name], _stereo ? "stereo" : "mono", _sampleRate, _size * sizeof (float) * (_stereo ? 2 : 1)];
}


#pragma mark OOSound

- (NSString *)name
{
	return _name;
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
	BOOL					loop, done = NO;
	
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
		
		memcpy(ioData->mBuffers[0].mData, _bufferL + offset, toCopy * sizeof (float));
		memcpy(ioData->mBuffers[1].mData, _bufferR + offset, toCopy * sizeof (float));
		
		if (underflow && loop)
		{
			offset = toCopy;
			toCopy = inNumFrames - toCopy;
			if (_size < toCopy) toCopy = _size;
			
			memcpy(((float *)ioData->mBuffers[0].mData) + offset, _bufferL, toCopy * sizeof (float));
			memcpy(((float *)ioData->mBuffers[1].mData) + offset, _bufferR, toCopy * sizeof (float));
			
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
		done = YES;
	}
	
	if (underflow)
	{
		memset(ioData->mBuffers[0].mData + toCopy, 0, underflow * sizeof (float));
		memset(ioData->mBuffers[1].mData + toCopy, 0, underflow * sizeof (float));
	}
	
	OOCASoundVerifyBuffers(ioData, inNumFrames, self);
	
	return done ? endOfDataReached : noErr;
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
