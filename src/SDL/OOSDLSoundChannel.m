/*

OOSDLSoundChannel.m

OOSDLSound - SDL_mixer sound implementation for Oolite.
Copyright (C) 2006-2008 Jens Ayton


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

Copyright (C) 2006-2008 Jens Ayton

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

#import "OOSDLSoundInternal.h"


@interface OOSoundChannel (Private)

- (void) hasStopped;

@end


@implementation OOSoundChannel

- (id) initWithID:(uint16_t)ID
{
	if ((self = [super init]))
	{
		_ID = ID;
	}
	return self;
}


- (void) update
{
	// Check if we've reached the end of a sound.
	if (_sound != nil && !Mix_Playing(_ID))  [self hasStopped];
}


- (void) setDelegate:(id)delegate
{
	_delegate = delegate;
}


- (uint32_t)ID
{
	return _ID;
}


- (OOSoundChannel *) next
{
	return _next;
}


- (void) setNext:(OOSoundChannel *)next
{
	_next = next;
}


- (BOOL) playSound:(OOSound *)sound looped:(BOOL)loop
{
	if (sound == nil)  return NO;
	
	if (_sound != nil)  [self stop];
	
	Mix_Chunk *chunk = [sound chunk];
	if (chunk != NULL)
	{
		Mix_PlayChannel(_ID, chunk, loop ? -1 : 0);
		_sound = [sound retain];
		return YES;
	}
	return NO;
}


- (void) stop
{
	if (_sound != nil)
	{
		Mix_HaltChannel(_ID);
		[self hasStopped];
	}
}


- (void) hasStopped
{
	OOSound *sound = _sound;
	_sound = nil;
	
	if (nil != _delegate && [_delegate respondsToSelector:@selector(channel:didFinishPlayingSound:)])
	{
		[_delegate channel:self didFinishPlayingSound:sound];
	}
	[sound release];
}


- (OOSound *)sound
{
	return _sound;
}

@end
