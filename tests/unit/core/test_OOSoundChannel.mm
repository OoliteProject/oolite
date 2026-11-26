/*	test_OOSoundChannel.mm
	Unit tests for OOSoundChannel (src/Core/OOALSoundChannel.h): bead oo-5vp8, a class of the Audio
	module (proposed ADR-0056, amendment oo-2en).

	A channel owns one OpenAL source. It plays a sound by queueing the sound's buffers on it (one
	for a buffered sound, one at a time for a streamed one, two in flight), and when the source
	stops it deletes the buffers, drops the sound and tells its delegate. The free list of the
	mixer is kept through -next/-setNext:. OpenAL runs on OpenAL Soft's null backend
	(ALSOFT_DRIVERS=null), which plays in real time, so the tests wait for a short sound to end.
	The sounds are this file's Objective-C subclasses of the root OOSound, which make real OpenAL
	buffers of silence; the decoder, the two concrete sounds and the mixer that OOALSound.mm names
	are stubs (amendment oo-z1s4 item 4). The channel's source is private, so the test reads it as
	a friend (amendment oo-zffj item 3; through the runtime before the conversion). These
	expectations were written against the Objective-C API and ran on the unconverted class first;
	they now run through the facade, which is its forwarding test. After them come the C++ API
	(cxx::OOSoundChannel) and the facade's contract. Run: bash tools/check-core-tests.sh test_OOSoundChannel
*/

#import "OOALSoundChannel.h"
#import "OOALSound.h"

#include "oo_test.hpp"

#include <chrono>
#include <cstdlib>
#include <filesystem>
#include <process.h>
#include <string>
#include <thread>
#include <vector>

namespace stdfs = std::filesystem;


void OOLogGenericSubclassResponsibilityForFunction(const char *inFunction)
{
	(void)inFunction;
}


@interface OOSoundMixer: OOObject
+ (id) sharedMixer;
@end

@implementation OOSoundMixer
+ (id) sharedMixer	{ return nil; }
- (void) update		{}
@end

@interface OOALSoundDecoder: OOObject
@end

@implementation OOALSoundDecoder
- (id)cxx_initWithPath:(const std::optional<std::string> &)inPath	{ (void)inPath; [self release]; return nil; }
@end

@interface OOALBufferedSound: OOSound
@end

@implementation OOALBufferedSound
@end

@interface OOALStreamedSound: OOSound
@end

@implementation OOALStreamedSound
@end


/*	A sound of `chunks` buffers of `frames` frames of mono silence at 22050 Hz: incomplete until
	the last has been made. Counts its buffers and rewinds.
*/
static int gLiveSounds = 0;

@interface TestSound: OOSound
{
@public
	int			_chunks;
	int			_made;
	int			_frames;
	int			_rewinds;
}
@end


@implementation TestSound

- (id) init
{
	self = [super init];
	if (self != nil)
	{
		_chunks = 1;
		_frames = 64;
		gLiveSounds++;
	}
	return self;
}


- (void) dealloc
{
	gLiveSounds--;
	[super dealloc];
}


- (std::optional<std::string>)cxx_name
{
	return std::string("test");
}


- (ALuint) soundBuffer
{
	std::vector<short> silence(static_cast<size_t>(_frames), 0);
	ALuint buffer = 0;
	alGenBuffers(1, &buffer);
	alBufferData(buffer, AL_FORMAT_MONO16, silence.data(), static_cast<ALsizei>(silence.size() * sizeof(short)), 22050);
	_made++;
	return buffer;
}


- (BOOL) soundIncomplete
{
	return _made < _chunks;
}


- (void) rewind
{
	_rewinds++;
	_made = 0;
}

@end


// The delegate: records each sound it is told has finished, and on which channel.
@interface TestDelegate: OOObject
{
@public
	std::vector<id>		_finished;
	id					_lastChannel;
}
@end


@implementation TestDelegate

- (void)channel:(OOSoundChannel *)inChannel didFinishPlayingSound:(OOSound *)inSound
{
	_lastChannel = inChannel;
	_finished.push_back(inSound);
}

@end


namespace {

stdfs::path sRoot;


void SetUp()
{
	if (!sRoot.empty())  return;
	OO_CHECK(::_putenv_s("ALSOFT_DRIVERS", "null") == 0);
	sRoot = stdfs::temp_directory_path() / ("oo-test-soundchannel-" + std::to_string(static_cast<unsigned long>(::_getpid())));
	stdfs::remove_all(sRoot);
	stdfs::create_directories(sRoot);
	OO_CHECK(::_putenv_s("HOMEPATH", sRoot.string().c_str()) == 0);
	stdfs::current_path(sRoot);
	OO_CHECK([OOSound setUp]);
}


}	// namespace


struct OOSoundChannelTestAccess
{
	static ALuint Source(cxx::OOSoundChannel *channel)  { return channel->_source; }
};


namespace {

// The channel's OpenAL source (its private _source).
ALuint SourceOf(OOSoundChannel *channel)
{
	return OOSoundChannelTestAccess::Source(oo::ToCxx(channel));
}


ALint SourceInt(ALuint source, ALenum what)
{
	ALint value = -1;
	alGetSourcei(source, what, &value);
	return value;
}


// Updates the channel until its sound is gone (at most two seconds).
bool UpdateUntilFinished(OOSoundChannel *channel)
{
	for (int i = 0; i < 400 && [channel sound] != nil; i++)
	{
		[channel update];
		std::this_thread::sleep_for(std::chrono::milliseconds(5));
	}
	return [channel sound] == nil;
}

}	// namespace


OO_TEST(aNewChannelHasARelativeSource)
{
	SetUp();
	@autoreleasepool
	{
		OOSoundChannel *channel = [[[OOSoundChannel alloc] init] autorelease];
		OO_CHECK(channel != nil);
		const ALuint source = SourceOf(channel);
		OO_CHECK(source != 0 && alIsSource(source));
		OO_CHECK(SourceInt(source, AL_SOURCE_RELATIVE) == AL_TRUE);
		OO_CHECK([channel sound] == nil && [channel next] == nil);
		[channel update];	// nothing playing: nothing
		[channel stop];
		OO_CHECK([channel sound] == nil);
	}
}


OO_TEST(positionGainAndTheFreeList)
{
	SetUp();
	@autoreleasepool
	{
		OOSoundChannel *channel = [[[OOSoundChannel alloc] init] autorelease];
		OOSoundChannel *other = [[[OOSoundChannel alloc] init] autorelease];
		const ALuint source = SourceOf(channel);

		[channel setPosition:make_vector(1.0f, 2.0f, 3.0f)];
		ALfloat x = 0, y = 0, z = 0;
		alGetSource3f(source, AL_POSITION, &x, &y, &z);
		OO_CHECK(x == 1.0f && y == 2.0f && z == 3.0f);

		[channel setGain:0.5f];
		ALfloat gain = 0;
		alGetSourcef(source, AL_GAIN, &gain);
		OO_CHECK(gain == 0.5f);

		[channel setNext:other];
		OO_CHECK([channel next] == other && [other next] == nil);
		[channel setNext:nil];
		OO_CHECK([channel next] == nil);
	}
}


// A sound plays, is retained while it plays, and when it ends the delegate hears of it.
OO_TEST(playsASoundToTheEnd)
{
	SetUp();
	@autoreleasepool
	{
		OOSoundChannel *channel = [[[OOSoundChannel alloc] init] autorelease];
		TestDelegate *delegate = [[[TestDelegate alloc] init] autorelease];
		[channel setDelegate:delegate];

		OO_CHECK(![channel playSound:nil looped:NO]);

		TestSound *sound = [[TestSound alloc] init];
		OO_CHECK([channel playSound:sound looped:NO]);
		OO_CHECK(sound->_rewinds == 1 && sound->_made == 1);
		OO_CHECK([channel sound] == sound);
		const ALuint source = SourceOf(channel);
		OO_CHECK(SourceInt(source, AL_BUFFERS_QUEUED) == 1);
		[sound release];
		OO_CHECK(gLiveSounds == 1);	// the channel keeps it

		OO_CHECK(UpdateUntilFinished(channel));
		OO_CHECK(delegate->_finished.size() == 1 && delegate->_finished[0] == sound && delegate->_lastChannel == channel);
		OO_CHECK(SourceInt(source, AL_BUFFERS_QUEUED) == 0);
		[channel setDelegate:nil];	// unretained, and the pool may release it first
	}
	OO_CHECK(gLiveSounds == 0);
}


// -stop ends the sound at once, and the delegate hears of it; a new sound stops the old one.
OO_TEST(stopAndReplace)
{
	SetUp();
	@autoreleasepool
	{
		OOSoundChannel *channel = [[[OOSoundChannel alloc] init] autorelease];
		TestDelegate *delegate = [[[TestDelegate alloc] init] autorelease];
		[channel setDelegate:delegate];

		TestSound *first = [[[TestSound alloc] init] autorelease];
		first->_frames = 22050;	// a second: still playing when stopped
		TestSound *second = [[[TestSound alloc] init] autorelease];
		second->_frames = 22050;
		OO_CHECK([channel playSound:first looped:NO]);
		OO_CHECK([channel playSound:second looped:NO]);
		OO_CHECK(delegate->_finished.size() == 1 && delegate->_finished[0] == first);
		OO_CHECK([channel sound] == second);

		[channel stop];
		OO_CHECK(delegate->_finished.size() == 2 && delegate->_finished[1] == second);
		OO_CHECK([channel sound] == nil);
		OO_CHECK(SourceInt(SourceOf(channel), AL_SOURCE_STATE) == AL_STOPPED);
		OO_CHECK(SourceInt(SourceOf(channel), AL_BUFFERS_QUEUED) == 0);
		[channel setDelegate:nil];
	}
	OO_CHECK(gLiveSounds == 0);
}


// A streamed sound: the next buffer is made while it plays, until the sound is complete.
OO_TEST(streamsAnIncompleteSound)
{
	SetUp();
	@autoreleasepool
	{
		OOSoundChannel *channel = [[[OOSoundChannel alloc] init] autorelease];
		TestDelegate *delegate = [[[TestDelegate alloc] init] autorelease];
		[channel setDelegate:delegate];

		TestSound *sound = [[[TestSound alloc] init] autorelease];
		sound->_chunks = 4;
		sound->_frames = 2205;	// a tenth of a second each
		OO_CHECK([channel playSound:sound looped:NO]);
		OO_CHECK(UpdateUntilFinished(channel));
		OO_CHECK(sound->_made == 4);
		OO_CHECK(delegate->_finished.size() == 1);
		[channel setDelegate:nil];
	}
}


// A looped sound is rewound and played again when it is complete.
OO_TEST(loopsASound)
{
	SetUp();
	@autoreleasepool
	{
		OOSoundChannel *channel = [[[OOSoundChannel alloc] init] autorelease];
		TestSound *sound = [[[TestSound alloc] init] autorelease];
		sound->_frames = 2205;
		OO_CHECK([channel playSound:sound looped:YES]);
		for (int i = 0; i < 400 && sound->_rewinds < 3; i++)
		{
			[channel update];
			std::this_thread::sleep_for(std::chrono::milliseconds(5));
		}
		OO_CHECK(sound->_rewinds >= 3);
		OO_CHECK([channel sound] == sound);
		[channel stop];
		OO_CHECK([channel sound] == nil);
	}
}


// The C++ API: -init's failure is init()'s false; the free list holds C++ channels.
OO_TEST(cxxApi)
{
	SetUp();
	@autoreleasepool
	{
		const oo::Ref<cxx::OOSoundChannel> channel = oo::makeRef<cxx::OOSoundChannel>();
		OO_CHECK(channel->init());
		const ALuint source = OOSoundChannelTestAccess::Source(channel.get());
		OO_CHECK(source != 0 && alIsSource(source) && SourceInt(source, AL_SOURCE_RELATIVE) == AL_TRUE);

		const oo::Ref<cxx::OOSoundChannel> other = oo::makeRef<cxx::OOSoundChannel>();
		OO_CHECK(other->init());
		channel->setNext(other.get());
		OO_CHECK(channel->next() == other.get() && other->next() == nullptr);

		TestDelegate *delegate = [[[TestDelegate alloc] init] autorelease];
		channel->setDelegate(delegate);
		OO_CHECK(!channel->playSound(nil, false));
		TestSound *sound = [[[TestSound alloc] init] autorelease];
		sound->_frames = 22050;
		OO_CHECK(channel->playSound(sound, false) && channel->sound() == sound);
		channel->stop();
		OO_CHECK(channel->sound() == nil);
		// The delegate is told of the channel's facade.
		OO_CHECK(delegate->_finished.size() == 1 && delegate->_lastChannel == oo::ToObjC(channel.get()));
		channel->setDelegate(nil);
	}
}


// The facade's contract: one live facade per channel; the free list's channels cross both ways; a
// facade that is released while its channel plays tells the delegate of itself, as -dealloc did.
OO_TEST(facade)
{
	SetUp();
	TestDelegate *delegate = [[TestDelegate alloc] init];
	OOSoundChannel *channel = nil;
	TestSound *sound = nil;
	@autoreleasepool
	{
		channel = [[OOSoundChannel alloc] init];
		OOSoundChannel *other = [[[OOSoundChannel alloc] init] autorelease];
		OO_CHECK(oo::ToObjC(oo::ToCxx(channel)) == channel);
		[channel setNext:other];
		OO_CHECK(oo::ToCxx(channel)->next() == oo::ToCxx(other));
		OO_CHECK([channel next] == other);

		sound = [[[TestSound alloc] init] autorelease];
		sound->_frames = 22050;
		[channel setDelegate:delegate];
		OO_CHECK([channel playSound:sound looped:NO]);
		[channel release];	// the last reference once the pool has drained
	}
	OO_CHECK(delegate->_finished.size() == 1 && delegate->_finished[0] == sound);
	OO_CHECK(delegate->_lastChannel == channel);	// the facade itself, while it was deallocated
	[delegate release];
	OOSoundChannel *none = nil;
	OO_CHECK(oo::ToCxx(none) == nullptr);
	OO_CHECK(oo::ToObjC(static_cast<cxx::OOSoundChannel *>(nullptr)) == nil);
	OO_CHECK(gLiveSounds == 0);
}


OO_TEST_MAIN()
