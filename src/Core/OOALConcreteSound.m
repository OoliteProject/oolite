/*

OOALConcreteSound.m

OOALSound - OpenAL sound implementation for Oolite.
Copyright (C) 2006-2013 Jens Ayton

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

*/

#include <ogg/ogg.h>
#include <vorbis/vorbisfile.h>
#include <vorbis/codec.h>

#import "OOALConcreteSound.h"
#import "OOLogging.h"
#import "NSDataOOExtensions.h"

size_t OOReadVorbis (void *ptr, size_t size, size_t nmemb, void *datasource);

typedef struct {
	NSData *file;
	size_t seek;
} OOOggBytes;

@implementation OOALConcreteSound

- (id) initWithContentsOfFile:(NSString *)path
{
	if ((self = [super init]))
	{
		NSData *fileData = [NSData oo_dataWithOXZFile:path];
		
		OggVorbis_File _vf;
		ov_callbacks _callbacks = {
			OOReadVorbis, // read sequentially
			NULL, // no seek
			NULL, // no close
			NULL, // no tell
		};
		OOOggBytes bitData = {
			fileData,
			0
		};
		ov_open_callbacks(bitData, _vf, NULL, 0, _callbacks);

		


		SDL_RWops *soundData = SDL_RWFromConstMem([fileData bytes],[fileData length]);
		_chunk = Mix_LoadWAV_RW(soundData, 0);
		SDL_RWclose(soundData);
		
		if (_chunk != NULL)
		{
			#ifndef NDEBUG
				OOLog(@"sound.load.success", @"Loaded a sound from \"%@\".", path);
			#endif
			_name = [[path lastPathComponent] copy];
		}
		else
		{
			OOLog(@"sound.load.failed", @"Could not load a sound from \"%@\".", path);
			[self release];
			self = nil;
		}
	}
	
	return self;
}


- (void) dealloc
{
	if (_chunk != NULL)  Mix_FreeChunk(_chunk);
	[_name autorelease];
	
	[super dealloc];
}


- (NSString *) descriptionComponents
{
	return [NSString stringWithFormat:@"\"%@\"", _name];
}


- (NSString *)name
{
	return _name;
}


- (ALuint) buffer
{
	return _buffer;
}

@end

// wants size*nmemb bytes from datasource transferred to ptr
size_t OOReadVorbis (void *ptr, size_t size, size_t nmemb, void *datasource)
{
	size_t toRead = size*nmemb;
	NSData *file = (OOOggBytes)datasource.file;
	size_t seek = (OOOggBytes)datasource.seek;
	if (seek+toRead > [file length])
	{
		toRead = [file length] - seek;
	}
	[file getBytes:ptr range:((NSRange){seek, toRead})];
	(OOOggBytes)datasource.seek += toRead;
	return toRead;
}
