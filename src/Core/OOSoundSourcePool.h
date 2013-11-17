/*

OOSoundSourcePool.h

Manages a fixed number of sound sources and distributes sounds between them.
Each sound has a priority and an expiry time. When a new sound is played, it
replaces (if possible) a sound of lower priority that has expired, a sound of
the same priority that has expired, or a sound of lower priority that has not
expired.

All sounds are specified by customsounds.plist key.
 

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

#import <Foundation/Foundation.h>
#import "OOTypes.h"
#import "OOMaths.h"

@interface OOSoundSourcePool: NSObject
{
@private
	struct OOSoundSourcePoolElement	*_sources;
	uint8_t							_count;
	uint8_t							_latest;
	uint8_t							_reserved;
	OOTimeDelta						_minRepeat;
	OOTimeAbsolute					_nextRepeat;
	NSString						*_lastKey;
}

+ (instancetype) poolWithCount:(uint8_t)count minRepeatTime:(OOTimeDelta)minRepeat;
- (id) initWithCount:(uint8_t)count minRepeatTime:(OOTimeDelta)minRepeat;

- (void) playSoundWithKey:(NSString *)key
				 priority:(float)priority
			   expiryTime:(OOTimeDelta)expiryTime
				  overlap:(BOOL)overlap
				 position:(Vector)position;

- (void) playSoundWithKey:(NSString *)key
				 priority:(float)priority
			   expiryTime:(OOTimeDelta)expiryTime;

- (void) playSoundWithKey:(NSString *)key
				 priority:(float)priority;	// expiryTime:0.1 +/- 0.5

- (void) playSoundWithKey:(NSString *)key
				 priority:(float)priority
				 position:(Vector)position;	// expiryTime:0.1 +/- 0.5

- (void) playSoundWithKey:(NSString *)key
				 position:(Vector)position;	// expiryTime:0.1 +/- 0.5

- (void) playSoundWithKey:(NSString *)key;	// priority: 1.0, expiryTime:0.1 +/- 0.5

- (void) playSoundWithKey:(NSString *)key overlap:(BOOL)overlap;	// if overlap == NO it waits for key to finish before playing key again
- (void) playSoundWithKey:(NSString *)key overlap:(BOOL)overlap position:(Vector)position;


@end
