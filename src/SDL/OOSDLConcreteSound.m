/*

OOSDLConcreteSound.m

OOSDLSound - SDL_mixer sound implementation for Oolite.
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

#import "OOSDLConcreteSound.h"
#import "OOLogging.h"
#import "NSDataOOExtensions.h"

@implementation OOSDLConcreteSound

- (id) initWithContentsOfFile:(NSString *)path
{
	if ((self = [super init]))
	{
		NSData *fileData = [NSData oo_dataWithOXZFile:path];
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


- (Mix_Chunk *) chunk
{
	return _chunk;
}

@end


@implementation OOSound (SDL)

- (Mix_Chunk *) chunk
{
	return NULL;
}

@end
