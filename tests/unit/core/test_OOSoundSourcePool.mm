/*	test_OOSoundSourcePool.mm
	Unit tests for OOSoundSourcePool (src/Core/OOSoundSourcePool.h): bead oo-d2y9, a class of the
	Audio module (proposed ADR-0056, amendment oo-2en).

	A pool keeps a fixed number of sound sources and plays each customsounds.plist key on one of
	them, chosen by priority and expiry time: an idle source first, then an expired one of lower
	priority, then an unexpired one of lower priority, then an expired one of equal priority, else
	none. It can refuse a key repeated within its minimum repeat time, and reserve a source for a
	sound that must not overlap itself. The game clock is a fake Universe answering -getTime
	(amendment oo-8kx7 item 7); the sound (with its custom-sound category) and the sound source
	are this file's stubs, which record what the pool asks of them (amendment oo-z1s4 item 4).
	These expectations were written against the Objective-C API and ran on the unconverted class
	first; they now run through the facade, which is its forwarding test. After them come the C++
	API (cxx::OOSoundSourcePool, whose selectors are overloads) and the facade's contract.
	Run: bash tools/check-core-tests.sh test_OOSoundSourcePool
*/

#import "OOSoundSourcePool.h"

#include "oo_test.hpp"

#include <algorithm>
#include <string>
#include <vector>


// The game clock.
@interface Universe: OOObject
{
@public
	OOTimeAbsolute	_time;
}
- (OOTimeAbsolute) getTime;
@end

@implementation Universe
- (OOTimeAbsolute) getTime	{ return _time; }
@end

Universe *gSharedUniverse = nil;


// A sound is its key; "[missing]" has none.
@interface OOSound: OOObject
{
@public
	std::string		_key;
}
+ (id) cxx_soundWithCustomSoundKey:(const std::string &)key;
@end


@implementation OOSound

+ (id) cxx_soundWithCustomSoundKey:(const std::string &)key
{
	if (key == "[missing]")  return nil;
	OOSound *sound = [[[OOSound alloc] init] autorelease];
	sound->_key = key;
	return sound;
}

@end


// A source records what it plays; the test says when it has stopped playing.
static std::vector<id> gSources;

@interface OOSoundSource: OOObject
{
@public
	std::string		_key;
	Vector			_position;
	BOOL			_playing;
	int				_stops;
}
@end


@implementation OOSoundSource

- (id) init
{
	self = [super init];
	if (self != nil)  gSources.push_back(self);
	return self;
}


- (void) stop
{
	_stops++;
	_playing = NO;
}


- (void) setPosition:(Vector)position
{
	_position = position;
}


- (void) playOOSound:(OOSound *)sound
{
	_key = sound->_key;
	_playing = YES;
}


- (BOOL) isPlaying
{
	return _playing;
}

@end


namespace {

OOSoundSource *Source(size_t i)
{
	return i < gSources.size() ? static_cast<OOSoundSource *>(gSources[i]) : nil;
}


// What each of the pool's sources (in the order they were made) is playing, "-" when idle.
std::vector<std::string> Playing()
{
	std::vector<std::string> result;
	for (id source : gSources)
	{
		OOSoundSource *s = source;
		result.push_back(s->_playing ? s->_key : "-");
	}
	return result;
}


// How many sources are playing key.
long PlayingCount(const char *key)
{
	const std::vector<std::string> playing = Playing();
	return std::count(playing.begin(), playing.end(), key);
}


void StopAll()
{
	for (id source : gSources)  static_cast<OOSoundSource *>(source)->_playing = NO;
}


void Reset(OOTimeAbsolute time)
{
	gSources.clear();	// the pools of earlier tests keep their own
	if (gSharedUniverse == nil)  gSharedUniverse = [[Universe alloc] init];
	gSharedUniverse->_time = time;
}

}	// namespace


// A count of 0 is 1, and of 255 is 254; a source is made the first time its slot is used.
OO_TEST(countsAndSources)
{
	@autoreleasepool
	{
		Reset(100.0);
		OOSoundSourcePool *one = [OOSoundSourcePool poolWithCount:0 minRepeatTime:0.0];
		OO_CHECK(one != nil && gSources.empty());
		[one playSoundWithKey:"[a]"];
		OO_CHECK((Playing() == std::vector<std::string>{ "[a]" }));
		[one playSoundWithKey:"[b]"];	// the one source is busy with an unexpired equal priority
		OO_CHECK((Playing() == std::vector<std::string>{ "[a]" }));
		gSharedUniverse->_time += 1.0;	// now it has expired
		[one playSoundWithKey:"[b]"];
		OO_CHECK((Playing() == std::vector<std::string>{ "[b]" }) && Source(0)->_stops == 1);

		Reset(100.0);
		OOSoundSourcePool *many = [[[OOSoundSourcePool alloc] initWithCount:255 minRepeatTime:-1.0] autorelease];
		for (int i = 0; i < 300; i++)  [many playSoundWithKey:"[k]" priority:1.0f expiryTime:10.0];
		OO_CHECK(gSources.size() == 254);

		// A missing sound plays nothing and makes no source.
		Reset(100.0);
		OOSoundSourcePool *pool = [OOSoundSourcePool poolWithCount:2 minRepeatTime:0.0];
		[pool playSoundWithKey:"[missing]"];
		OO_CHECK(gSources.empty());
	}
}


OO_TEST(slotsByPriorityAndExpiry)
{
	@autoreleasepool
	{
		Reset(100.0);
		OOSoundSourcePool *pool = [OOSoundSourcePool poolWithCount:3 minRepeatTime:0.0];
		[pool playSoundWithKey:"[low]" priority:1.0f expiryTime:1.0];
		[pool playSoundWithKey:"[mid]" priority:2.0f expiryTime:5.0];
		[pool playSoundWithKey:"[high]" priority:3.0f expiryTime:1.0];
		OO_CHECK((Playing() == std::vector<std::string>{ "[low]", "[mid]", "[high]" }));

		// Full, nothing expired: a higher priority takes an unexpired lower-priority source...
		[pool playSoundWithKey:"[x]" priority:2.5f expiryTime:1.0];
		OO_CHECK(Playing()[0] == "[x]" || Playing()[1] == "[x]");
		OO_CHECK(Playing()[2] == "[high]");
		// ...and a lower priority than every source gets none.
		[pool playSoundWithKey:"[y]" priority:0.5f expiryTime:1.0];
		OO_CHECK(PlayingCount("[y]") == 0);

		// An expired lower-priority source is preferred to an unexpired one.
		Reset(100.0);
		pool = [OOSoundSourcePool poolWithCount:2 minRepeatTime:0.0];
		[pool playSoundWithKey:"[short]" priority:1.0f expiryTime:1.0];
		[pool playSoundWithKey:"[long]" priority:1.0f expiryTime:10.0];
		gSharedUniverse->_time += 2.0;
		[pool playSoundWithKey:"[new]" priority:2.0f expiryTime:1.0];
		OO_CHECK((Playing() == std::vector<std::string>{ "[new]", "[long]" }));

		// An idle source is preferred to anything.
		StopAll();
		Source(0)->_playing = YES;
		[pool playSoundWithKey:"[idle]" priority:0.5f expiryTime:1.0];
		OO_CHECK((Playing() == std::vector<std::string>{ "[new]", "[idle]" }));
	}
}


// The position goes to the source; the conveniences' defaults.
OO_TEST(positionsAndDefaults)
{
	@autoreleasepool
	{
		Reset(100.0);
		OOSoundSourcePool *pool = [OOSoundSourcePool poolWithCount:4 minRepeatTime:0.0];
		[pool playSoundWithKey:"[p]" priority:1.0f position:make_vector(1, 2, 3)];
		OO_CHECK(vector_equal(Source(0)->_position, make_vector(1, 2, 3)));
		[pool playSoundWithKey:"[q]" position:make_vector(4, 5, 6)];
		OO_CHECK(vector_equal(Source(1)->_position, make_vector(4, 5, 6)));
		[pool playSoundWithKey:"[r]" priority:1.0f];
		OO_CHECK(vector_equal(Source(2)->_position, kZeroVector));
		[pool playSoundWithKey:"[s]" priority:1.0f expiryTime:1.0];
		OO_CHECK(vector_equal(Source(3)->_position, kZeroVector));

		// The default expiry is between 0.5 and 0.6 s: 0.45 s later an equal priority is refused,
		// 0.65 s later it is taken.
		gSharedUniverse->_time += 0.45;
		[pool playSoundWithKey:"[t]"];
		OO_CHECK(PlayingCount("[t]") == 0);
		gSharedUniverse->_time += 0.2;
		[pool playSoundWithKey:"[t]" overlap:YES position:make_vector(7, 8, 9)];
		OO_CHECK(PlayingCount("[t]") == 1);
	}
}


// A minimum repeat time refuses the same key until it has passed; other keys still play.
OO_TEST(minimumRepeatTime)
{
	@autoreleasepool
	{
		Reset(100.0);
		OOSoundSourcePool *pool = [OOSoundSourcePool poolWithCount:4 minRepeatTime:0.1];
		[pool playSoundWithKey:"[scrape]"];
		[pool playSoundWithKey:"[scrape]"];
		OO_CHECK(gSources.size() == 1);
		[pool playSoundWithKey:"[hit]"];
		OO_CHECK(gSources.size() == 2);
		[pool playSoundWithKey:"[hit]"];	// the last key is now [hit]
		OO_CHECK(gSources.size() == 2);
		gSharedUniverse->_time += 0.2;
		[pool playSoundWithKey:"[hit]"];
		OO_CHECK(gSources.size() == 3);
	}
}


// A sound that must not overlap reserves its source until that has stopped.
OO_TEST(noOverlap)
{
	@autoreleasepool
	{
		Reset(100.0);
		OOSoundSourcePool *pool = [OOSoundSourcePool poolWithCount:3 minRepeatTime:0.0];
		[pool playSoundWithKey:"[overheat]" overlap:NO];
		[pool playSoundWithKey:"[overheat]" overlap:NO];
		[pool playSoundWithKey:"[other]" overlap:NO position:kZeroVector];
		OO_CHECK((Playing() == std::vector<std::string>{ "[overheat]" }));
		[pool playSoundWithKey:"[shot]"];	// overlapping sounds still play
		OO_CHECK((Playing() == std::vector<std::string>{ "[overheat]", "[shot]" }));

		Source(0)->_playing = NO;
		[pool playSoundWithKey:"[overheat]" overlap:NO];
		OO_CHECK(Playing().size() == 3 && Playing()[2] == "[overheat]");
	}
}


// The C++ API: each overload is the selector it was. An overlap is passed as a bool, since game
// code sees OOCocoa.h's integer true and false.
OO_TEST(cxxApi)
{
	const bool overlap = static_cast<bool>(1), noOverlap = static_cast<bool>(0);
	@autoreleasepool
	{
		Reset(100.0);
		const oo::Ref<cxx::OOSoundSourcePool> pool = cxx::OOSoundSourcePool::poolWithCount(3, 0.0);
		OO_CHECK(pool);
		pool->playSoundWithKey("[a]", overlap);	// overlapping, priority 1
		pool->playSoundWithKey("[b]", noOverlap, make_vector(1, 2, 3));	// reserves its source
		pool->playSoundWithKey("[c]", noOverlap);	// refused: the reserved source plays
		OO_CHECK((Playing() == std::vector<std::string>{ "[a]", "[b]" }));
		OO_CHECK(vector_equal(Source(1)->_position, make_vector(1, 2, 3)));
		pool->playSoundWithKey("[d]", 2.0f);	// a float priority, not an overlap
		OO_CHECK((Playing() == std::vector<std::string>{ "[a]", "[b]", "[d]" }));
		pool->playSoundWithKey("[e]", 3.0f, make_vector(4, 5, 6));
		OO_CHECK(PlayingCount("[e]") == 1);
		pool->playSoundWithKey("[f]", make_vector(7, 8, 9));
		pool->playSoundWithKey("[g]", 0.5f, 1.0);
		pool->playSoundWithKey("[h]", 9.0f, 1.0, overlap, kZeroVector);
		OO_CHECK(PlayingCount("[h]") == 1);
		OO_CHECK(PlayingCount("[g]") == 0);
	}
}


// The facade's contract: one live facade per pool; alloc/init makes the pool's peer.
OO_TEST(facade)
{
	@autoreleasepool
	{
		OOSoundSourcePool *made = [[[OOSoundSourcePool alloc] initWithCount:2 minRepeatTime:0.0] autorelease];
		OO_CHECK(made != nil && oo::ToObjC(oo::ToCxx(made)) == made);
		OOSoundSourcePool *pool = [OOSoundSourcePool poolWithCount:2 minRepeatTime:0.0];
		OO_CHECK(pool != made && oo::ToObjC(oo::ToCxx(pool)) == pool);
	}
	OOSoundSourcePool *none = nil;
	OO_CHECK(oo::ToCxx(none) == nullptr);
	OO_CHECK(oo::ToObjC(static_cast<cxx::OOSoundSourcePool *>(nullptr)) == nil);
}


OO_TEST_MAIN()
