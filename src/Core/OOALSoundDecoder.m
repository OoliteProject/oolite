/*

OOALSoundDecoder.m


OOALSound - OpenAL sound implementation for Oolite.
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

#import "OOALSoundDecoder.h"
#import "NSDataOOExtensions.h"
#import <vorbis/vorbisfile.h>
#import "OOLogging.h"
#import "unzip.h"

enum
{
	kMaxDecodeSize			= 1 << 20		// 2^20 frames = 4 MB
};

static size_t OOReadOXZVorbis (void *ptr, size_t size, size_t nmemb, void *datasource);
static int OOCloseOXZVorbis (void *datasource);
// not practical to implement these
//static int OOSeekOXZVorbis  (void *datasource, ogg_int64_t offset, int whence);
//static long OOTellOXZVorbis (void *datasource);

@interface OOALSoundVorbisCodec: OOALSoundDecoder
{
	OggVorbis_File			_vf;
	NSString				*_name;
	BOOL					_readStarted;
	BOOL					_seekableStream;
@public
	unzFile					uf;
}

- (NSDictionary *)comments;

@end


@implementation OOALSoundDecoder

- (id)initWithPath:(NSString *)inPath
{
	[self release];
	self = nil;
	
	if ([[inPath pathExtension] isEqual:@"ogg"])
	{
		self = [[OOALSoundVorbisCodec alloc] initWithPath:inPath];
	}
	
	return self;
}


+ (OOALSoundDecoder *)codecWithPath:(NSString *)inPath
{
	if ([[inPath pathExtension] isEqual:@"ogg"])
	{
		return [[[OOALSoundVorbisCodec alloc] initWithPath:inPath] autorelease];
	}
	return nil;
}


- (size_t)streamToBuffer:(char *)ioBuffer
{
	return 0;
}


- (BOOL)readCreatingBuffer:(char **)outBuffer withFrameCount:(size_t *)outSize
{
	if (NULL != outBuffer) *outBuffer = NULL;
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


- (long)sampleRate
{
	return 0;
}


- (void) reset
{
	// nothing
}


- (NSString *)name
{
	return @"";
}

@end


@implementation OOALSoundVorbisCodec

- (id)initWithPath:(NSString *)path
{
	if ((self = [super init]))
	{
		BOOL				OK = NO;

		_name = [[path lastPathComponent] retain];

		unsigned i, cl;
		NSArray *components = [path pathComponents];
		cl = [components count];
		for (i = 0 ; i < cl ; i++)
		{
			NSString *component = [components objectAtIndex:i];
			if ([[[component pathExtension] lowercaseString] isEqualToString:@"oxz"])
			{
				break;
			}
		}
		// if i == cl then the path is entirely uncompressed
		if (i == cl)
		{
			/* Get vorbis data from a standard file stream */
			int					err;
			FILE				*file;
	
			_seekableStream = YES;
		
			if (nil != path)
			{
				file = fopen([path UTF8String], "rb");
				if (NULL != file) 
				{
					err = ov_open_callbacks(file, &_vf, NULL, 0, OV_CALLBACKS_DEFAULT);
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
		else
		{
			_seekableStream = NO;

			NSRange range;
			range.location = 0; range.length = i+1;
			NSString *zipFile = [NSString pathWithComponents:[components subarrayWithRange:range]];
			range.location = i+1; range.length = cl-(i+1);
			NSString *containedFile = [NSString pathWithComponents:[components subarrayWithRange:range]];

	
			const char* zipname = [zipFile UTF8String];
			if (zipname != NULL)
			{
				uf = unzOpen64(zipname);
			}
			if (uf == NULL)
			{
				OOLog(kOOLogFileNotFound, @"Could not unzip OXZ at %@", zipFile);
				[self release];
				self = nil;
			}
			else 
			{
				const char* filename = [containedFile UTF8String];
				// unzLocateFile(*, *, 1) = case-sensitive extract
				if (unzLocateFile(uf, filename, 1) != UNZ_OK)
				{
					unzClose(uf);
					[self release];
					self = nil;
				}
				else
				{
					int err = UNZ_OK;
					unz_file_info64 file_info = {0};
					err = unzGetCurrentFileInfo64(uf, &file_info, NULL, 0, NULL, 0, NULL, 0);
					if (err != UNZ_OK)
					{
						unzClose(uf);
						OOLog(kOOLogFileNotFound, @"Could not get properties of %@ within OXZ at %@", containedFile, zipFile);
						[self release];
						self = nil;
					}
					else
					{
						err = unzOpenCurrentFile(uf);
						if (err != UNZ_OK)
						{
							unzClose(uf);
							OOLog(kOOLogFileNotFound, @"Could not read %@ within OXZ at %@", containedFile, zipFile);
							[self release];
							self = nil;
						}
						else
						{
							ov_callbacks _callbacks = {
								OOReadOXZVorbis, // read sequentially
								NULL, // no seek
								OOCloseOXZVorbis, // close file
								NULL, // no tell
							};
							err = ov_open_callbacks(self, &_vf, NULL, 0, _callbacks);
							if (0 == err)
							{
								OK = YES;
								_readStarted = NO;
							}
							if (!OK)
							{
								unzClose(uf);
								[self release];
								self = nil;
							}
						}
					}
				}
			}
		}
	}
	return self;
}


- (void)dealloc
{
	[_name release];
	ov_clear(&_vf);
	unzClose(uf);
	
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


- (BOOL)readCreatingBuffer:(char **)outBuffer withFrameCount:(size_t *)outSize
{
	char					*buffer = NULL, *dst;
	size_t					sizeInFrames = 0;
	int						remaining;
	long					framesRead;
	// 16-bit samples, either two or one track
	int						frameSize = [self isStereo] ? 4 : 2;
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
		buffer = malloc(sizeof (char) * frameSize * sizeInFrames);
		if (!buffer) OK = NO;
	}
	
	if (OK && sizeInFrames)
	{
		remaining = (int)MIN(frameSize * sizeInFrames, (size_t)INT_MAX);
		dst = buffer;
		
		char pcmout[4096];

		do
		{
			int toRead = sizeof(pcmout);
			if (remaining < toRead)
			{
				toRead = remaining;
			}
			framesRead = ov_read(&_vf, pcmout, toRead, 0, 2, 1, NULL);
			if (framesRead <= 0)
			{
				if (OV_HOLE == framesRead) continue;
				//else:
				break;
			}
			
			memcpy(dst, &pcmout, sizeof (char) * framesRead);
			
			remaining -= framesRead;
			dst += framesRead;
		} while (0 < remaining);
		
		sizeInFrames -= remaining;	// In case we stopped at an error
	}
	
	if (OK)
	{
		*outBuffer = buffer;
		*outSize = sizeInFrames*frameSize;
	}
	else
	{
		if (buffer) free(buffer);
	}
	return OK;
}


- (size_t)streamToBuffer:(char *)buffer
{
	
	int remaining = OOAL_STREAM_CHUNK_SIZE;
	size_t streamed = 0;
	long framesRead;

	char *dst = buffer;
	char pcmout[4096];
	_readStarted = YES;
	do
	{
		int toRead = sizeof(pcmout);
		if (remaining < toRead)
		{
			toRead = remaining;
		}
		framesRead = ov_read(&_vf, pcmout, toRead, 0, 2, 1, NULL);
		if (framesRead <= 0)
		{
			if (OV_HOLE == framesRead) continue;
			//else:
			break;
		}
		memcpy(dst, &pcmout, sizeof (char) * framesRead);
		remaining -= sizeof(char) * framesRead;
		dst += sizeof(char) * framesRead;
		streamed += sizeof(char) * framesRead;
	} while (0 < remaining);

	return streamed;
}


- (size_t)sizeAsBuffer
{
	ogg_int64_t				size;
	size = ov_pcm_total(&_vf, -1);
	size *= sizeof(char) * ([self isStereo] ? 4 : 2);
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


- (long)sampleRate
{
	return ov_info(&_vf, -1)->rate;
}



- (void) reset
{
	if (!_readStarted)
	{
		return; // don't need to do anything
	}
	if (_seekableStream)
	{
		ov_pcm_seek(&_vf, 0);
		return;
	}
	// reset current file pointer in OXZ
	unzOpenCurrentFile(uf);
	// reopen OGG streamer
	ov_clear(&_vf);
	ov_callbacks _callbacks = {
		OOReadOXZVorbis, // read sequentially
		NULL, // no seek
		OOCloseOXZVorbis, // close file
		NULL, // no tell
	};
	ov_open_callbacks(self, &_vf, NULL, 0, _callbacks);
	_readStarted = NO;
}


- (NSString *)name
{
	return [[_name retain] autorelease];
}

@end


static size_t OOReadOXZVorbis (void *ptr, size_t size, size_t nmemb, void *datasource)
{
	OOALSoundVorbisCodec *src = (OOALSoundVorbisCodec *)datasource;
	size_t toRead = size*nmemb;
	void *buf = (void*)malloc(toRead);
	int err = UNZ_OK;
	err = unzReadCurrentFile(src->uf, buf, toRead);
//	OOLog(@"sound.replay",@"Read %d blocks, got %d",toRead,err);
	if (err > 0)
	{
		memcpy(ptr, buf, err);
	}
	if (err < 0)
	{
		return OV_EREAD;
	}
	return err;
}


static int OOCloseOXZVorbis (void *datasource)
{
//  doing this prevents replaying
//	OOALSoundVorbisCodec *src = (OOALSoundVorbisCodec *)datasource;
//	unzClose(src->uf);
	return 0;
}

