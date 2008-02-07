/*

OOBasicSoundSource.m


Oolite
Copyright (C) 2004-2008 Giles C Williams and contributors

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

Copyright (C) 2005-2008 Jens Ayton

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

#import "OOBasicSoundSource.h"
#import "OOSound.h"


@interface OOSoundSource (Private)

- (void)update;

@end


static NSMutableSet			*sUpdateSet = nil;


@implementation OOSoundSource

- (id) init
{
	return [super init];
}


- (void) dealloc
{
	[self stop];
	[_sound autorelease];
	
	[super dealloc];
}


- (NSString *) description
{
	return [NSString stringWithFormat:@"<%@ %p>{sound=%@, loop=%s, repeatCount=%u, %@playing}", [self className], self, sound, [self loop] ? "YES" : "NO", [self repeatCount], [self isPlaying] ? @"" : @"not "];
}


+ (id) sourceWithSound:(OOSound *)sound
{
	return [[[self alloc] initWithSound:sound] autorelease];
}


- (id) initWithSound:(OOSound *)sound
{
	self = [self init];
	if (!self) return nil;
	
	[self setSound:sound];
	
	return self;
}


- (OOSound *) sound
{
	return _sound;
}


- (void) setSound:(OOSound *)sound
{
	if (_sound != sound)
	{
		[_sound autorelease];
		_sound = [sound retain];
	}
}


- (BOOL) loop
{
	return _loop;
}


- (void) setLoop:(BOOL)loop
{
	_loop = !!loop;
}


- (uint8_t) repeatCount
{
	return _repeatCount ? _repeatCount : 1;
}


- (void) setRepeatCount:(uint8_t)count
{
	_repeatCount = count;
}


- (BOOL) isPlaying
{
	return [_sound isPlaying] || _remainingCount != 0;
}


- (void) play
{
	// Set the sound playing.
	[self stop];
	[_sound play];
	
	// Put sound source in update set, so its -update gets called from +update.
	_remainingCount = [self repeatCount];
	if (nil == sUpdateSet) sUpdateSet = [[NSMutableSet alloc] init];
	[sUpdateSet addObject:self];
}


- (void) playOrRepeat
{
	if (![self isPlaying])  [self play];
	else ++_remainingCount;
}


- (void) stop
{
	if ([self isPlaying])
	{
		[_sound stop];
		[sUpdateSet removeObject:self];
		_remainingCount = 0;
	}
}


- (void) playSound:(OOSound *)sound
{
	[self playSound:sound repeatCount:_repeatCount];
}


- (void) playSound:(OOSound *)sound repeatCount:(uint8_t)count
{
	[self stop];
	[self setSound:sound];
	[self setRepeatCount:count];
	[self play];
}


- (void) playOrRepeatSound:(OOSound *)sound
{
	if (sound != sound) [self playSound:sound];
	else [self playOrRepeat];
}


+ (void) update
{
	[sUpdateSet makeObjectsPerformSelector:@selector(update)];
}


- (void) update
{
	if (![_sound isPlaying])
	{
		if (_loop) ++_remainingCount;
		if (--_remainingCount)
		{
			[_sound play];
		}
		else
		{
			[self stop];
		}
	}
}


- (void) positionRelativeTo:(OOSoundReferencePoint *)point
{
	
}


- (void) setPositional:(BOOL)positional
{
	
}


- (void) setPosition:(Vector)position
{
	
}


- (void) setVelocity:(Vector)velocity
{
	
}


- (void) setOrientation:(Vector)orientation
{
	
}


- (void) setConeAngle:(float)angle
{
	
}


- (void) setGainInsideCone:(float)inside outsideCone:(float)outside
{
	
}

@end
