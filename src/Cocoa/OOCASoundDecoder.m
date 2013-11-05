/*

OOCASoundDecoder.m


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

#define OV_EXCLUDE_STATIC_CALLBACKS

#import "OOCASoundDecoder.h"
#import <stdio.h>
#import <vorbis/vorbisfile.h>
#import "OOLogging.h"


enum
{
	kMaxDecodeSize			= 1 << 20		// 2^20 frames = 4 MB
};


static void MixDown(float *inChan1, float *inChan2, float *outMix, size_t inCount);


@interface OOCASoundVorbisCodec: OOCASoundDecoder
{
	OggVorbis_File			_vf;
	NSString				*_name;
	BOOL					_atEnd;
}

- (NSDictionary *)comments;

@end


@implementation OOCASoundDecoder

- (id)initWithPath:(NSString *)inPath
{
	[self release];
	self = nil;
	
	if ([[inPath pathExtension] isEqual:@"ogg"])
	{
		self = [[OOCASoundVorbisCodec alloc] initWithPath:inPath];
	}
	
	return self;
}


+ (OOCASoundDecoder *)codecWithPath:(NSString *)inPath
{
	if ([[inPath pathExtension] isEqual:@"ogg"])
	{
		return [[[OOCASoundVorbisCodec alloc] initWithPath:inPath] autorelease];
	}
	return nil;
}


- (size_t)streamStereoToBufferL:(float *)ioBufferL bufferR:(float *)ioBufferR maxFrames:(size_t)inMax
{
	return 0;
}


- (BOOL)readMonoCreatingBuffer:(float **)outBuffer withFrameCount:(size_t *)outSize
{
	if (NULL != outBuffer) *outBuffer = NULL;
	if (NULL != outSize) *outSize = 0;
	
	return NO;
}


- (BOOL)readStereoCreatingLeftBuffer:(float **)outLeftBuffer rightBuffer:(float **)outRightBuffer withFrameCount:(size_t *)outSize
{
	if (NULL != outLeftBuffer) *outLeftBuffer = NULL;
	if (NULL != outRightBuffer) *outRightBuffer = NULL;
	if (NULL != outSize) *outSize = 0;
	
	return NO;
}


- (size_t)sizeAsBuffer
{
	return 0;
}


- (BOOL)isStereo
{
	return NO;
}


- (double)sampleRate
{
	return 0;
}


- (BOOL)atEnd
{
	return YES;
}


- (void)rewindToBeginning
{
	
}


- (BOOL)scanToOffset:(uint64_t)inOffset
{
	return NO;
}


- (NSString *)name
{
	return @"";
}

@end


@implementation OOCASoundVorbisCodec

- (id)initWithPath:(NSString *)inPath
{
	BOOL				OK = NO;
	int					err;
	FILE				*file;
	
	if ((self = [super init]))
	{
		_name = [[inPath lastPathComponent] retain];
		
		if (nil != inPath)
		{
			file = fopen([inPath UTF8String], "rb");
			if (NULL != file) 
			{
				err = ov_open(file, &_vf, NULL, 0);
				if (0 == err)
				{
					OK = YES;
				}
			}
		}
		
		if (!OK)
		{
			[self release];
			self = nil;
		}
	}
	
	return self;
}


- (void)dealloc
{
	[_name release];
	ov_clear(&_vf);
	
	[super dealloc];
}


- (NSDictionary *)comments
{
	vorbis_comment			*comments;
	unsigned				i, count;
	NSMutableDictionary		*result = nil;
	NSString				*comment, *key, *value;
	NSRange					range;
	
	comments = ov_comment(&_vf, -1);
	if (NULL != comments)
	{
		count = comments->comments;
		if (0 != count)
		{
			result = [NSMutableDictionary dictionaryWithCapacity:count];
			for (i = 0; i != count; ++i)
			{
				comment = [[NSString alloc] initWithBytesNoCopy:comments->user_comments[i] length:comments->comment_lengths[i] encoding:NSUTF8StringEncoding freeWhenDone:NO];
				range = [comment rangeOfString:@"="];
				if (0 != range.length)
				{
					key = [comment substringToIndex:range.location];
					value = [comment substringFromIndex:range.location + 1];
				}
				else
				{
					key = comment;
					value = @"";
				}
				[result setObject:value forKey:key];
				
				[comment release];
			}
		}
	}
	
	return result;
}


- (BOOL)readMonoCreatingBuffer:(float **)outBuffer withFrameCount:(size_t *)outSize
{
	float					*buffer = NULL, *dst, **src;
	size_t					sizeInFrames = 0;
	int						remaining;
	unsigned				chanCount;
	long					framesRead;
	ogg_int64_t				totalSizeInFrames;
	BOOL					OK = YES;
	
	if (NULL != outBuffer) *outBuffer = NULL;
	if (NULL != outSize) *outSize = 0;
	if (NULL == outBuffer || NULL == outSize) OK = NO;
	
	if (OK)
	{
		totalSizeInFrames = ov_pcm_total(&_vf, -1);
		assert ((uint64_t)totalSizeInFrames < (uint64_t)SIZE_MAX);	// Should have been checked by caller
		sizeInFrames = (size_t)totalSizeInFrames;
	}
	
	if (OK)
	{
		buffer = malloc(sizeof (float) * sizeInFrames);
		if (!buffer) OK = NO;
	}
	
	if (OK && sizeInFrames)
	{
		remaining = (int)MIN(sizeInFrames, (size_t)INT_MAX);
		dst = buffer;
		
		do
		{
			chanCount = ov_info(&_vf, -1)->channels;
			framesRead = ov_read_float(&_vf, &src, remaining, NULL);
			if (framesRead <= 0)
			{
				if (OV_HOLE == framesRead) continue;
				//else:
				break;
			}
			
			if (1 == chanCount)  memcpy(dst, src[0], sizeof (float) * framesRead);
			else MixDown(src[0], src[1], dst, framesRead);
			
			remaining -= framesRead;
			dst += framesRead;
		} while (0 != remaining);
		
		sizeInFrames -= remaining;	// In case we stopped at an error
	}
	
	if (OK)
	{
		*outBuffer = buffer;
		*outSize = sizeInFrames;
	}
	else
	{
		if (buffer) free(buffer);
	}
	return OK;
}


- (BOOL)readStereoCreatingLeftBuffer:(float **)outLeftBuffer rightBuffer:(float **)outRightBuffer withFrameCount:(size_t *)outSize
{
	float					*bufferL = NULL, *bufferR = NULL, *dstL, *dstR, **src;
	size_t					sizeInFrames = 0;
	int						remaining;
	unsigned				chanCount;
	long					framesRead;
	ogg_int64_t				totalSizeInFrames;
	BOOL					OK = YES;
	
	if (NULL != outLeftBuffer) *outLeftBuffer = NULL;
	if (NULL != outRightBuffer) *outRightBuffer = NULL;
	if (NULL != outSize) *outSize = 0;
	if (NULL == outLeftBuffer || NULL == outRightBuffer || NULL == outSize) OK = NO;
	
	if (OK)
	{
		totalSizeInFrames = ov_pcm_total(&_vf, -1);
		assert ((uint64_t)totalSizeInFrames < (uint64_t)SIZE_MAX);	// Should have been checked by caller
		sizeInFrames = (size_t)totalSizeInFrames;
	}
	
	if (OK)
	{
		bufferL = malloc(sizeof (float) * sizeInFrames);
		if (!bufferL) OK = NO;
	}
	
	if (OK)
	{
		bufferR = malloc(sizeof (float) * sizeInFrames);
		if (!bufferR) OK = NO;
	}
	
	if (OK && sizeInFrames)
	{
		remaining = (int)MIN(sizeInFrames, (size_t)INT_MAX);
		dstL = bufferL;
		dstR = bufferR;
		
		do
		{
			chanCount = ov_info(&_vf, -1)->channels;
			framesRead = ov_read_float(&_vf, &src, remaining, NULL);
			if (framesRead <= 0)
			{
				if (OV_HOLE == framesRead) continue;
				//else:
				break;
			}
			
			unsigned rightChan = (chanCount == 1) ? 0 : 1;
			memcpy(dstL, src[0], sizeof (float) * framesRead);
			memcpy(dstR, src[rightChan], sizeof (float) * framesRead);
			
			remaining -= framesRead;
			dstL += framesRead;
			dstR += framesRead;
		} while (0 != remaining);
		
		sizeInFrames -= remaining;	// In case we stopped at an error
	}
	
	if (OK)
	{
		*outLeftBuffer = bufferL;
		*outRightBuffer = bufferR;
		*outSize = sizeInFrames;
	}
	else
	{
		if (bufferL) free(bufferL);
		if (bufferR) free(bufferR);
	}
	return OK;
}


- (size_t)streamStereoToBufferL:(float *)ioBufferL bufferR:(float *)ioBufferR maxFrames:(size_t)inMax
{
	float					**src;
	unsigned				chanCount;
	long					framesRead;
	size_t					size;
	int						remaining;
	
	// Note: for our purposes, a frame is a set of one sample for each channel.
	if (NULL == ioBufferL || NULL == ioBufferR || 0 == inMax) return 0;
	if (_atEnd) return inMax;
	
	remaining = (int)MIN(inMax, (size_t)INT_MAX);
	do
	{
		chanCount = ov_info(&_vf, -1)->channels;
		framesRead = ov_read_float(&_vf, &src, remaining, NULL);
		if (framesRead <= 0)
		{
			if (OV_HOLE == framesRead) continue;
			//else:
			_atEnd = YES;
			break;
		}
		
		size = sizeof (float) * framesRead;
		
		unsigned rightChan = (chanCount == 1) ? 0 : 1;
		memcpy(ioBufferL, src[0], size);
		memcpy(ioBufferR, src[rightChan], size);
		
		remaining -= framesRead;
		ioBufferL += framesRead;
		ioBufferR += framesRead;
	} while (0 != remaining);
	
	return inMax - remaining;
}


- (size_t)sizeAsBuffer
{
	ogg_int64_t				size;
	
	size = ov_pcm_total(&_vf, -1);
	size *= sizeof(float) * ([self isStereo] ? 2 : 1);
	if ((uint64_t)SIZE_MAX < (uint64_t)size) size = (ogg_int64_t)SIZE_MAX;
	return (size_t)size;
}


- (BOOL)isStereo
{
	return 1 < ov_info(&_vf, -1)->channels;
}


- (NSString *)description
{
	return [NSString stringWithFormat:@"<%@ %p>{\"%@\", comments=%@}", [self className], self, _name, [self comments]];
}


- (Float64)sampleRate
{
	return ov_info(&_vf, -1)->rate;
}


- (BOOL)atEnd
{
	return _atEnd;
}


- (void)rewindToBeginning
{
	if (!ov_pcm_seek(&_vf, 0)) _atEnd = NO;
}


- (BOOL)scanToOffset:(uint64_t)inOffset
{
	if (!ov_pcm_seek(&_vf, inOffset))
	{
		_atEnd = NO;
		return YES;
	}
	else return NO;
}


- (NSString *)name
{
	return [[_name retain] autorelease];
}

@end


// TODO: optimise, vectorise
static void MixDown(float *inChan1, float *inChan2, float *outMix, size_t inCount)
{
	while (inCount--)
	{
		*outMix++ = (*inChan1++ + *inChan2++) * 0.5f;
	}
}
