/*

OOSoundSourcePool.m
 
 
Copyright (C) 2008-2013 Jens Ayton

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

#import "OOSoundSourcePool.h"
#import "OOSound.h"
#import "Universe.h"


enum
{
	kNoSlot = UINT8_MAX
};


typedef struct OOSoundSourcePoolElement
{
	OOSoundSource			*source;
	OOTimeAbsolute			expiryTime;
	float					priority;
} PoolElement;


@interface OOSoundSourcePool (Private)

- (uint8_t) selectSlotForPriority:(float)priority;

@end


@implementation OOSoundSourcePool

+ (instancetype) poolWithCount:(uint8_t)count minRepeatTime:(OOTimeDelta)minRepeat
{
	return [[[self alloc] initWithCount:count minRepeatTime:minRepeat] autorelease];
}


- (id) initWithCount:(uint8_t)count minRepeatTime:(OOTimeDelta)minRepeat
{
	if ((self = [super init]))
	{
		// Sanity-check count
		if (count == 0)  count = 1;
		if (count == kNoSlot)  --count;
		_count = count;
		_reserved = kNoSlot;
		
		if (minRepeat < 0.0)  minRepeat = 0.0;
		_minRepeat = minRepeat;
		
		// Create source pool
		_sources = calloc(sizeof(PoolElement), count);
		if (_sources == NULL)
		{
			[self release];
			self = nil;
		}
	}
	return self;
}


- (void) dealloc
{
	uint8_t					i;
	
	for (i = 0; i != _count; i++)
	{
		[_sources[i].source release];
	}
	
	[_lastKey release];
	
	[super dealloc];
}


- (void) playSoundWithKey:(NSString *)key
				 priority:(float)priority
			   expiryTime:(OOTimeDelta)expiryTime
				 overlap:(BOOL)overlap
				 position:(Vector)position
{
	uint8_t					slot;
	OOTimeAbsolute			now, absExpiryTime;
	PoolElement				*element = NULL;
	OOSound					*sound = NULL;
	
	// Convert expiry time to absolute
	now = [UNIVERSE getTime];
	absExpiryTime = expiryTime + now;
	
	// Avoid repeats if required
	if (now < _nextRepeat && [key isEqualToString:_lastKey])  return;
	if (!overlap && _reserved != kNoSlot && [_sources[_reserved].source isPlaying]) return;
	
	// Look for a slot in the source list to use
	slot = [self selectSlotForPriority:priority];
	if (slot == kNoSlot)  return;
	element = &_sources[slot];
	
	// Load sound
	sound = [OOSound soundWithCustomSoundKey:key];
	if (sound == nil)  return;
	
	// Stop playing sound or set up sound source as appropriate
	if (element->source != nil)  [element->source stop];
	else
	{
		element->source = [[OOSoundSource alloc] init];
		if (element->source == nil)  return;
	}
	if (slot == _reserved) _reserved = kNoSlot;	// _reserved has finished playing!
	if (!overlap) _reserved = slot;
	
	// Play and store metadata
	[element->source setPosition:position];
	[element->source playSound:sound];
	element->expiryTime = absExpiryTime;
	element->priority = priority;
	if (_minRepeat > 0.0)
	{
		_nextRepeat = now + _minRepeat;
		[_lastKey release];
		_lastKey = [key copy];
	}
	
	// Set staring search location for next slot lookup
	_latest = slot;
}


- (void) playSoundWithKey:(NSString *)key
				 priority:(float)priority
			   expiryTime:(OOTimeDelta)expiryTime
{
	[self playSoundWithKey:key
				  priority:priority
				expiryTime:expiryTime
				   overlap:YES
				  position:kZeroVector];
}


- (void) playSoundWithKey:(NSString *)key
				 priority:(float)priority
				 position:(Vector)position
{
	[self playSoundWithKey:key
				  priority:priority
				expiryTime:0.5 + randf() * 0.1
				   overlap:YES
				  position:position];
}


- (void) playSoundWithKey:(NSString *)key
				 priority:(float)priority
{
	[self playSoundWithKey:key
				  priority:priority
				expiryTime:0.5 + randf() * 0.1];
}


- (void) playSoundWithKey:(NSString *)key
{
	[self playSoundWithKey:key priority:1.0];
}


- (void) playSoundWithKey:(NSString *)key position:(Vector)position
{
	[self playSoundWithKey:key priority:1.0 position:position];
}


- (void) playSoundWithKey:(NSString *)key overlap:(BOOL)overlap
{
	[self playSoundWithKey:key
				  priority:1.0
				expiryTime:0.5
				   overlap:overlap
				  position:kZeroVector];
}


- (void) playSoundWithKey:(NSString *)key overlap:(BOOL)overlap position:(Vector)position
{
	[self playSoundWithKey:key
				  priority:1.0
				expiryTime:0.5
				   overlap:overlap
				  position:position];
}


@end


@implementation OOSoundSourcePool (Private)

- (uint8_t) selectSlotForPriority:(float)priority
{
	uint8_t					curr, count, expiredLower = kNoSlot, unexpiredLower = kNoSlot, expiredEqual = kNoSlot;
	PoolElement				*element = NULL;
	OOTimeAbsolute			now = [UNIVERSE getTime];
	
#define NEXT(x) (((x) + 1) % _count)
	
	curr = _latest;
	count = _count;
	do
	{
		curr = NEXT(curr);
		element = &_sources[curr];
		
		if (element->source == nil || ![element->source isPlaying])  return curr;	// Best type of slot: empty
		else if (element->priority < priority)
		{
			if (element->expiryTime <= now)  expiredLower = curr;	// Second-best type: expired lower-priority
			else if (curr != _reserved) unexpiredLower = curr;		// Third-best type: unexpired lower-priority
		}
		else if (element->priority == priority && element->expiryTime <= now)
		{
			expiredEqual = curr;									// Fourth-best type: expired equal-priority.
		}
	} while (--count);
	
	if (expiredLower != kNoSlot)  return expiredLower;
	if (unexpiredLower != kNoSlot)  return unexpiredLower;
	return expiredEqual;	// Will be kNoSlot if none found
}

@end
