/*

OOSDLConcreteSound.m

OOSDLSound - SDL_mixer sound implementation for Oolite.
Copyright (C) 2006-2010 Jens Ayton


This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
MA 02110-1301, USA.


This file may also be distributed under the MIT/X11 license:

Copyright (C) 2006-2010 Jens Ayton

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


@implementation OOSDLConcreteSound

- (id) initWithContentsOfFile:(NSString *)path
{
	if ((self = [super init]))
	{
		_chunk = Mix_LoadWAV([path UTF8String]);
		
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
