/*

OOCAMusic.m

OOCASound - Core Audio sound implementation for Oolite.
Copyright (C) 2005-2006 Jens Ayton

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

*/

#import "OOCASoundInternal.h"

static OOMusic			*sPlayingMusic = nil;
static OOSoundSource	*sMusicSource = nil;


@implementation OOMusic

#pragma mark NSObject

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

#pragma mark OOSound

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


- (BOOL)doPlayWithLoop:(BOOL)inLoop
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
	return YES;
}


- (BOOL)play
{
	return [self doPlayWithLoop:NO];
}


- (BOOL)isPlaying
{
	return sPlayingMusic == self && [sMusicSource isPlaying];
}


- (BOOL)pause
{
	NSLog(@"%s called but ignored - please report.", __FUNCTION__);
	return NO;
}


- (BOOL)resume
{
	NSLog(@"%s called but ignored - please report.", __FUNCTION__);
	return NO;
}


- (BOOL)isPaused
{
	return NO;
}


- (NSString *)name
{
	return [sound name];
}


#pragma mark OOMusic

- (BOOL)playLooped
{
	return [self doPlayWithLoop:YES];
}


- (BOOL)stop
{
	if (sPlayingMusic == self)
	{
		sPlayingMusic = nil;
		[sMusicSource stop];
	}
	return YES;
}

@end
