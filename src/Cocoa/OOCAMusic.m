//	
//	OOCAMusic.m
//	CoreAudio sound implementation for Oolite
//	
/*

Copyright © 2005-2006 Jens Ayton
All rights reserved.

This work is licensed under the Creative Commons Attribution-ShareAlike License.
To view a copy of this license, visit http://creativecommons.org/licenses/by-sa/2.0/
or send a letter to Creative Commons, 559 Nathan Abbott Way, Stanford, California 94305, USA.

You are free:

•	to copy, distribute, display, and perform the work
•	to make derivative works

Under the following conditions:

•	Attribution. You must give the original author credit.

•	Share Alike. If you alter, transform, or build upon this work,
you may distribute the resulting work only under a license identical to this one.

For any reuse or distribution, you must make clear to others the license terms of this work.

Any of these conditions can be waived if you get permission from the copyright holder.

Your fair use and other rights are in no way affected by the above.

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
