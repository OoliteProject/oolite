/*	test_OOSoundSourcePool.mm
	Unit tests for OOSoundSourcePool (src/Core/OOSoundSourcePool.h): bead oo-d2y9, a class of the
	Audio module (proposed ADR-0056, amendment oo-2en).

	A pool keeps a fixed number of sound sources and plays each customsounds.plist key on one of
	them, chosen by priority and expiry time: an idle source first, then an expired one of lower
	priority, then an unexpired one of lower priority, then an expired one of equal priority, else
	none. It can refuse a key repeated within its minimum repeat time, and reserve a source for a
	sound that must not overlap itself. The game clock is a fake Universe answering -getTime
	(amendment oo-8kx7 item 7); the sound (with its custom-sound look-up) and the sound source
	are this file's stubs, which record what the pool asks of them (amendment oo-z1s4 item 4; C++
	stand-ins since beads oo-9ht.68 and oo-9ht.88 deleted the facades they stood in for, and an
	autorelease pool is an oo::AutoreleaseScope). These expectations were written against the
	Objective-C API and ran on the unconverted class first; since bead oo-9ht.89 deleted the pool's
	facade they ask the C++ pool. After them comes the C++ API (OOSoundSourcePool, whose selectors
	are overloads).
	Run: bash tools/check-core-tests.sh test_OOSoundSourcePool
*/

#import "OOSoundSourcePool.h"
#import "OOSoundSource.h"
#import "OOALSound.h"

#include "oo_test.hpp"

#include <algorithm>
#include <map>
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


/*	A sound is its key; "[missing]" has none. A C++ stand-in since bead oo-9ht.68 deleted the facade
	this file stubbed: the custom-sound look-up the pool calls (Universe.h; its sound lives until
	the innermost scope ends, as the autoreleased one did) and the root's members a sound's vtable
	names.
*/
OOSound::OOSound()  {}
std::optional<std::string> OOSound::name()  { return std::nullopt; }
ALuint OOSound::soundBuffer()  { return 0; }
bool OOSound::soundIncomplete()  { return false; }
void OOSound::rewind()  {}
std::optional<std::string> OOSound::descriptionComponents() const  { return std::nullopt; }

class TestSound final : public OOSound
{
public:
	explicit TestSound(const std::string &key) : _key(key)  {}

	std::string		_key;
};

::OOSound *OOSoundWithCustomSoundKey(const std::string &key);

::OOSound *OOSoundWithCustomSoundKey(const std::string &key)
{
	if (key == "[missing]")  return nullptr;
	return oo::autorelease(oo::makeRef<TestSound>(key));
}


/*	A source records what it plays; the test says when it has stopped playing. A C++ stand-in since
	bead oo-9ht.88 deleted the facade this file stubbed: the members the pool calls (and the
	delegate member its vtable names), recording per source in the order they were made.
*/
struct SourceRecord
{
	std::string		_key;
	Vector			_position = {};
	BOOL			_playing = NO;
	int				_stops = 0;
};

static std::map<const OOSoundSource *, SourceRecord> gRecords;
static std::vector<SourceRecord *> gSources;

OOSoundSource::OOSoundSource()
{
	gSources.push_back(&gRecords[this]);
}


OOSoundSource::~OOSoundSource()
{
	SourceRecord *record = &gRecords[this];
	gSources.erase(std::remove(gSources.begin(), gSources.end(), record), gSources.end());
	gRecords.erase(this);
}


void OOSoundSource::stop()
{
	gRecords[this]._stops++;
	gRecords[this]._playing = NO;
}


void OOSoundSource::setPosition(Vector position)
{
	gRecords[this]._position = position;
}


void OOSoundSource::playOOSound(OOSound *sound)
{
	gRecords[this]._key = static_cast<TestSound *>(sound)->_key;
	gRecords[this]._playing = YES;
}


bool OOSoundSource::isPlaying()
{
	return gRecords[this]._playing;
}


void OOSoundSource::channel(OOSoundChannel *, OOSound *)
{
}


namespace {

SourceRecord *Source(size_t i)
{
	return i < gSources.size() ? gSources[i] : nullptr;
}


// What each of the pool's sources (in the order they were made) is playing, "-" when idle.
std::vector<std::string> Playing()
{
	std::vector<std::string> result;
	for (SourceRecord *s : gSources)
	{
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
	for (SourceRecord *source : gSources)  source->_playing = NO;
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
	{
		oo::AutoreleaseScope scope;	// was @autoreleasepool
		Reset(100.0);
		oo::Ref<OOSoundSourcePool> one = OOSoundSourcePool::poolWithCount(0, 0.0);
		OO_CHECK(one != nullptr && gSources.empty());
		one->playSoundWithKey("[a]");
		OO_CHECK((Playing() == std::vector<std::string>{ "[a]" }));
		one->playSoundWithKey("[b]");	// the one source is busy with an unexpired equal priority
		OO_CHECK((Playing() == std::vector<std::string>{ "[a]" }));
		gSharedUniverse->_time += 1.0;	// now it has expired
		one->playSoundWithKey("[b]");
		OO_CHECK((Playing() == std::vector<std::string>{ "[b]" }) && Source(0)->_stops == 1);

		Reset(100.0);
		oo::Ref<OOSoundSourcePool> many = OOSoundSourcePool::poolWithCount(255, -1.0);
		for (int i = 0; i < 300; i++)  many->playSoundWithKey("[k]", 1.0f, 10.0);
		OO_CHECK(gSources.size() == 254);

		// A missing sound plays nothing and makes no source.
		Reset(100.0);
		oo::Ref<OOSoundSourcePool> pool = OOSoundSourcePool::poolWithCount(2, 0.0);
		pool->playSoundWithKey("[missing]");
		OO_CHECK(gSources.empty());
	}
}


OO_TEST(slotsByPriorityAndExpiry)
{
	{
		oo::AutoreleaseScope scope;	// was @autoreleasepool
		Reset(100.0);
		oo::Ref<OOSoundSourcePool> pool = OOSoundSourcePool::poolWithCount(3, 0.0);
		pool->playSoundWithKey("[low]", 1.0f, 1.0);
		pool->playSoundWithKey("[mid]", 2.0f, 5.0);
		pool->playSoundWithKey("[high]", 3.0f, 1.0);
		OO_CHECK((Playing() == std::vector<std::string>{ "[low]", "[mid]", "[high]" }));

		// Full, nothing expired: a higher priority takes an unexpired lower-priority source...
		pool->playSoundWithKey("[x]", 2.5f, 1.0);
		OO_CHECK(Playing()[0] == "[x]" || Playing()[1] == "[x]");
		OO_CHECK(Playing()[2] == "[high]");
		// ...and a lower priority than every source gets none.
		pool->playSoundWithKey("[y]", 0.5f, 1.0);
		OO_CHECK(PlayingCount("[y]") == 0);

		// An expired lower-priority source is preferred to an unexpired one.
		Reset(100.0);
		pool = OOSoundSourcePool::poolWithCount(2, 0.0);
		pool->playSoundWithKey("[short]", 1.0f, 1.0);
		pool->playSoundWithKey("[long]", 1.0f, 10.0);
		gSharedUniverse->_time += 2.0;
		pool->playSoundWithKey("[new]", 2.0f, 1.0);
		OO_CHECK((Playing() == std::vector<std::string>{ "[new]", "[long]" }));

		// An idle source is preferred to anything.
		StopAll();
		Source(0)->_playing = YES;
		pool->playSoundWithKey("[idle]", 0.5f, 1.0);
		OO_CHECK((Playing() == std::vector<std::string>{ "[new]", "[idle]" }));
	}
}


// The position goes to the source; the conveniences' defaults.
OO_TEST(positionsAndDefaults)
{
	{
		oo::AutoreleaseScope scope;	// was @autoreleasepool
		Reset(100.0);
		oo::Ref<OOSoundSourcePool> pool = OOSoundSourcePool::poolWithCount(4, 0.0);
		pool->playSoundWithKey("[p]", 1.0f, make_vector(1, 2, 3));
		OO_CHECK(vector_equal(Source(0)->_position, make_vector(1, 2, 3)));
		pool->playSoundWithKey("[q]", make_vector(4, 5, 6));
		OO_CHECK(vector_equal(Source(1)->_position, make_vector(4, 5, 6)));
		pool->playSoundWithKey("[r]", 1.0f);
		OO_CHECK(vector_equal(Source(2)->_position, kZeroVector));
		pool->playSoundWithKey("[s]", 1.0f, 1.0);
		OO_CHECK(vector_equal(Source(3)->_position, kZeroVector));

		// The default expiry is between 0.5 and 0.6 s: 0.45 s later an equal priority is refused,
		// 0.65 s later it is taken.
		gSharedUniverse->_time += 0.45;
		pool->playSoundWithKey("[t]");
		OO_CHECK(PlayingCount("[t]") == 0);
		gSharedUniverse->_time += 0.2;
		pool->playSoundWithKey("[t]", static_cast<bool>(YES), make_vector(7, 8, 9));
		OO_CHECK(PlayingCount("[t]") == 1);
	}
}


// A minimum repeat time refuses the same key until it has passed; other keys still play.
OO_TEST(minimumRepeatTime)
{
	{
		oo::AutoreleaseScope scope;	// was @autoreleasepool
		Reset(100.0);
		oo::Ref<OOSoundSourcePool> pool = OOSoundSourcePool::poolWithCount(4, 0.1);
		pool->playSoundWithKey("[scrape]");
		pool->playSoundWithKey("[scrape]");
		OO_CHECK(gSources.size() == 1);
		pool->playSoundWithKey("[hit]");
		OO_CHECK(gSources.size() == 2);
		pool->playSoundWithKey("[hit]");	// the last key is now [hit]
		OO_CHECK(gSources.size() == 2);
		gSharedUniverse->_time += 0.2;
		pool->playSoundWithKey("[hit]");
		OO_CHECK(gSources.size() == 3);
	}
}


// A sound that must not overlap reserves its source until that has stopped.
OO_TEST(noOverlap)
{
	{
		oo::AutoreleaseScope scope;	// was @autoreleasepool
		Reset(100.0);
		oo::Ref<OOSoundSourcePool> pool = OOSoundSourcePool::poolWithCount(3, 0.0);
		pool->playSoundWithKey("[overheat]", static_cast<bool>(NO));
		pool->playSoundWithKey("[overheat]", static_cast<bool>(NO));
		pool->playSoundWithKey("[other]", static_cast<bool>(NO), kZeroVector);
		OO_CHECK((Playing() == std::vector<std::string>{ "[overheat]" }));
		pool->playSoundWithKey("[shot]");	// overlapping sounds still play
		OO_CHECK((Playing() == std::vector<std::string>{ "[overheat]", "[shot]" }));

		Source(0)->_playing = NO;
		pool->playSoundWithKey("[overheat]", static_cast<bool>(NO));
		OO_CHECK(Playing().size() == 3 && Playing()[2] == "[overheat]");
	}
}


// The C++ API: each overload is the selector it was. An overlap is passed as a bool, since game
// code sees OOCocoa.h's integer true and false.
OO_TEST(cxxApi)
{
	const bool overlap = static_cast<bool>(1), noOverlap = static_cast<bool>(0);
	{
		oo::AutoreleaseScope scope;	// was @autoreleasepool
		Reset(100.0);
		const oo::Ref<OOSoundSourcePool> pool = OOSoundSourcePool::poolWithCount(3, 0.0);
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


OO_TEST_MAIN()
