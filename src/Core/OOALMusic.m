/*

OOALMusic.m


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

#import "OOALMusic.h"
#import "OOSoundSource.h"

static OOMusic			*sPlayingMusic = nil;
static OOSoundSource	*sMusicSource = nil;


@implementation OOMusic

+ (id)allocWithZone:(NSZone *)inZone
{
	return NSAllocateObject([OOMusic class], 0, inZone);
}


- (void)dealloc
{
	if (sPlayingMusic == self) [self stop];
	[sound release];
	
	[super dealloc];
}

- (id)initWithContentsOfFile:(NSString *)inPath
{
	self = [super init];
	if (nil != self)
	{
		sound = [[OOSound alloc] initWithContentsOfFile:inPath];
		if (nil == sound)
		{
			[self release];
			self = nil;
		}
	}
	
	return self;
}


- (NSString *)name
{
	return [sound name];
}


- (void)playLooped:(BOOL)inLoop
{
	if (sPlayingMusic != self)
	{
		if (nil == sMusicSource)
		{
			sMusicSource = [[OOSoundSource alloc] init];
		}
		[sMusicSource stop];
		[sMusicSource setLoop:inLoop];
		[sMusicSource setSound:sound];
		[sMusicSource play];
		
		sPlayingMusic = self;
	}
}


- (BOOL)isPlaying
{
	return sPlayingMusic == self && [sMusicSource isPlaying];
}


- (void)stop
{
	if (sPlayingMusic == self)
	{
		sPlayingMusic = nil;
		[sMusicSource stop];
	}
}

@end
