/*

OOSDLSoundMixer.m

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

#import "OOCocoa.h"
#import "OOSDLSoundInternal.h"


static OOSoundMixer *sSingleton = nil;


@implementation OOSoundMixer

+ (id) sharedMixer
{
	if (nil == sSingleton)
	{
		[[self alloc] init];
	}
	return sSingleton;
}


- (id) init
{
	BOOL						OK = YES;
	uint32_t					idx = 0, count = kMixerGeneralChannels;
	OOSoundChannel				*channel;
	
	if (!(self = [super init]))  return nil;
	if (![OOSound setUp])  OK = NO;
	
	if (OK)
	{
		// Allocate channels
		do
		{
			channel = [[OOSoundChannel alloc] initWithID:count];
			if (nil != channel)
			{
				_channels[idx++] = channel;
				[self pushChannel:channel];
			}
		}  while (--count);
	}
	
	if (!OK)
	{
		[super release];
		self = nil;
	}
	else
	{
		sSingleton = self;
	}
	
	return sSingleton;
}


- (void) update
{
	for (uint32_t i = 0; i < kMixerGeneralChannels; ++i)
	{
		[_channels[i] update];
	}
}


- (OOSoundChannel *) popChannel
{
	OOSoundChannel *channel = _freeList;
	_freeList = [channel next];
	[channel setNext:nil];
	
	return channel;
}


- (void) pushChannel:(OOSoundChannel *)channel
{
	assert(channel != nil);
	
	[channel setNext:_freeList];
	_freeList = channel;
}

@end


@implementation OOSoundMixer (Singleton)

/*	Canonical singleton boilerplate.
	See Cocoa Fundamentals Guide: Creating a Singleton Instance.
	See also +sharedMixer above.
	
	NOTE: assumes single-threaded access.
*/

+ (id)allocWithZone:(NSZone *)inZone
{
	if (sSingleton == nil)
	{
		sSingleton = [super allocWithZone:inZone];
		return sSingleton;
	}
	return nil;
}


- (id)copyWithZone:(NSZone *)inZone
{
	return self;
}


- (id)retain
{
	return self;
}


- (OOUInteger)retainCount
{
	return UINT_MAX;
}


- (void)release
{}


- (id)autorelease
{
	return self;
}

@end
