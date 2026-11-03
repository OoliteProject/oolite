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
	they ran through the facade until bead oo-9ht.86 deleted it, and now ask the C++ channel with
	the same expectations (the facade's own contract was retired with it: ADR-0049, standing
	approval oo-9n5p9; what its -dealloc told the delegate is the destructor's now, pinned by
	releasedWhilePlayingTellsTheDelegate). The delegate is a C++ OOSoundChannelDelegate.
	Run: bash tools/check-core-tests.sh test_OOSoundChannel
*/

#import "OOALSoundChannel.h"
#import "OOALSound.h"
#import "OOALBufferedSound.h"
#import "OOALStreamedSound.h"
#import "OOALSoundMixer.h"

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


// The mixer, as the root's update() and the OpenAL controller's shutdown() reach it: there is
// none (a C++ stand-in since bead oo-9ht.87 deleted the Objective-C facade this file stubbed).
OOSoundMixer *OOSoundMixer::sharedMixer()  { return nullptr; }
void OOSoundMixer::update()  {}
void OOSoundMixer::shutdown()  {}

@interface OOALSoundDecoder: OOObject
@end

@implementation OOALSoundDecoder
- (id)cxx_initWithPath:(const std::optional<std::string> &)inPath	{ (void)inPath; [self release]; return nil; }
@end

// The buffered sound the root's cluster names: a C++ stand-in since bead oo-9ht.83 deleted the
// Objective-C facade this file stubbed. The decoder above refuses every path, so none is made.
oo::Ref<OOALBufferedSound> OOALBufferedSound::initWithDecoder(::OOALSoundDecoder *inDecoder)	{ (void)inDecoder; return nullptr; }
OOALBufferedSound::~OOALBufferedSound()  {}
std::optional<std::string> OOALBufferedSound::name()  { return _name; }
ALuint OOALBufferedSound::soundBuffer()  { return 0; }

// The streamed sound the root's cluster names: a C++ stand-in since bead oo-9ht.84 deleted the
// Objective-C facade this file stubbed. None is made here.
oo::Ref<OOALStreamedSound> OOALStreamedSound::initWithDecoder(::OOALSoundDecoder *inDecoder)	{ (void)inDecoder; return nullptr; }
OOALStreamedSound::~OOALStreamedSound()  {}
std::optional<std::string> OOALStreamedSound::name()  { return _name; }
void OOALStreamedSound::rewind()  {}
bool OOALStreamedSound::soundIncomplete()  { return false; }
ALuint OOALStreamedSound::soundBuffer()  { return 0; }


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


// The delegate: records each sound it is told has finished, and on which channel. (An Objective-C
// object answering -channel:didFinishPlayingSound: until bead oo-9ht.86 made the delegate C++.)
class TestDelegate final : public OOSoundChannelDelegate
{
public:
	void channel(OOSoundChannel *inChannel, OOSound *inSound) override
	{
		_lastChannel = inChannel;
		_finished.push_back(inSound);
	}

	std::vector<id>		_finished;
	OOSoundChannel		*_lastChannel = nullptr;
};


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
	static ALuint Source(OOSoundChannel *channel)  { return channel->_source; }
};


namespace {

// The channel's OpenAL source (its private _source).
ALuint SourceOf(OOSoundChannel *channel)
{
	return OOSoundChannelTestAccess::Source(channel);
}


// What [[OOSoundChannel alloc] init] made: a new channel, null when OpenAL would not make its source.
oo::Ref<OOSoundChannel> NewChannel()
{
	oo::Ref<OOSoundChannel> channel = oo::makeRef<OOSoundChannel>();
	if (!channel->init())  channel = nullptr;
	return channel;
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
	for (int i = 0; i < 400 && channel->sound() != nil; i++)
	{
		channel->update();
		std::this_thread::sleep_for(std::chrono::milliseconds(5));
	}
	return channel->sound() == nil;
}

}	// namespace


OO_TEST(aNewChannelHasARelativeSource)
{
	SetUp();
	@autoreleasepool
	{
		const oo::Ref<OOSoundChannel> channel = NewChannel();
		OO_CHECK(channel != nullptr);
		const ALuint source = SourceOf(channel.get());
		OO_CHECK(source != 0 && alIsSource(source));
		OO_CHECK(SourceInt(source, AL_SOURCE_RELATIVE) == AL_TRUE);
		OO_CHECK(channel->sound() == nil && channel->next() == nullptr);
		channel->update();	// nothing playing: nothing
		channel->stop();
		OO_CHECK(channel->sound() == nil);
	}
}


OO_TEST(positionGainAndTheFreeList)
{
	SetUp();
	@autoreleasepool
	{
		const oo::Ref<OOSoundChannel> channel = NewChannel();
		const oo::Ref<OOSoundChannel> other = NewChannel();
		const ALuint source = SourceOf(channel.get());

		channel->setPosition(make_vector(1.0f, 2.0f, 3.0f));
		ALfloat x = 0, y = 0, z = 0;
		alGetSource3f(source, AL_POSITION, &x, &y, &z);
		OO_CHECK(x == 1.0f && y == 2.0f && z == 3.0f);

		channel->setGain(0.5f);
		ALfloat gain = 0;
		alGetSourcef(source, AL_GAIN, &gain);
		OO_CHECK(gain == 0.5f);

		channel->setNext(other.get());
		OO_CHECK(channel->next() == other.get() && other->next() == nullptr);
		channel->setNext(nullptr);
		OO_CHECK(channel->next() == nullptr);
	}
}


// A sound plays, is retained while it plays, and when it ends the delegate hears of it.
OO_TEST(playsASoundToTheEnd)
{
	SetUp();
	TestDelegate delegate;
	@autoreleasepool
	{
		const oo::Ref<OOSoundChannel> channel = NewChannel();
		channel->setDelegate(&delegate);

		OO_CHECK(!channel->playSound(nil, false));

		TestSound *sound = [[TestSound alloc] init];
		OO_CHECK(channel->playSound(sound, false));
		OO_CHECK(sound->_rewinds == 1 && sound->_made == 1);
		OO_CHECK(channel->sound() == sound);
		const ALuint source = SourceOf(channel.get());
		OO_CHECK(SourceInt(source, AL_BUFFERS_QUEUED) == 1);
		[sound release];
		OO_CHECK(gLiveSounds == 1);	// the channel keeps it

		OO_CHECK(UpdateUntilFinished(channel.get()));
		OO_CHECK(delegate._finished.size() == 1 && delegate._finished[0] == sound && delegate._lastChannel == channel.get());
		OO_CHECK(SourceInt(source, AL_BUFFERS_QUEUED) == 0);
		channel->setDelegate(nullptr);	// unretained
	}
	OO_CHECK(gLiveSounds == 0);
}


// stop() ends the sound at once, and the delegate hears of it; a new sound stops the old one.
OO_TEST(stopAndReplace)
{
	SetUp();
	TestDelegate delegate;
	@autoreleasepool
	{
		const oo::Ref<OOSoundChannel> channel = NewChannel();
		channel->setDelegate(&delegate);

		TestSound *first = [[[TestSound alloc] init] autorelease];
		first->_frames = 22050;	// a second: still playing when stopped
		TestSound *second = [[[TestSound alloc] init] autorelease];
		second->_frames = 22050;
		OO_CHECK(channel->playSound(first, false));
		OO_CHECK(channel->playSound(second, false));
		OO_CHECK(delegate._finished.size() == 1 && delegate._finished[0] == first);
		OO_CHECK(channel->sound() == second);

		channel->stop();
		OO_CHECK(delegate._finished.size() == 2 && delegate._finished[1] == second);
		OO_CHECK(channel->sound() == nil);
		OO_CHECK(SourceInt(SourceOf(channel.get()), AL_SOURCE_STATE) == AL_STOPPED);
		OO_CHECK(SourceInt(SourceOf(channel.get()), AL_BUFFERS_QUEUED) == 0);
		channel->setDelegate(nullptr);
	}
	OO_CHECK(gLiveSounds == 0);
}


// A streamed sound: the next buffer is made while it plays, until the sound is complete.
OO_TEST(streamsAnIncompleteSound)
{
	SetUp();
	TestDelegate delegate;
	@autoreleasepool
	{
		const oo::Ref<OOSoundChannel> channel = NewChannel();
		channel->setDelegate(&delegate);

		TestSound *sound = [[[TestSound alloc] init] autorelease];
		sound->_chunks = 4;
		sound->_frames = 2205;	// a tenth of a second each
		OO_CHECK(channel->playSound(sound, false));
		OO_CHECK(UpdateUntilFinished(channel.get()));
		OO_CHECK(sound->_made == 4);
		OO_CHECK(delegate._finished.size() == 1);
		channel->setDelegate(nullptr);
	}
}


// A looped sound is rewound and played again when it is complete.
OO_TEST(loopsASound)
{
	SetUp();
	@autoreleasepool
	{
		const oo::Ref<OOSoundChannel> channel = NewChannel();
		TestSound *sound = [[[TestSound alloc] init] autorelease];
		sound->_frames = 2205;
		OO_CHECK(channel->playSound(sound, true));
		for (int i = 0; i < 400 && sound->_rewinds < 3; i++)
		{
			channel->update();
			std::this_thread::sleep_for(std::chrono::milliseconds(5));
		}
		OO_CHECK(sound->_rewinds >= 3);
		OO_CHECK(channel->sound() == sound);
		channel->stop();
		OO_CHECK(channel->sound() == nil);
	}
}


// The C++ API: -init's failure is init()'s false; the free list holds C++ channels.
OO_TEST(cxxApi)
{
	SetUp();
	TestDelegate delegate;
	@autoreleasepool
	{
		const oo::Ref<OOSoundChannel> channel = oo::makeRef<OOSoundChannel>();
		OO_CHECK(channel->init());
		const ALuint source = OOSoundChannelTestAccess::Source(channel.get());
		OO_CHECK(source != 0 && alIsSource(source) && SourceInt(source, AL_SOURCE_RELATIVE) == AL_TRUE);

		const oo::Ref<OOSoundChannel> other = oo::makeRef<OOSoundChannel>();
		OO_CHECK(other->init());
		channel->setNext(other.get());
		OO_CHECK(channel->next() == other.get() && other->next() == nullptr);

		channel->setDelegate(&delegate);
		OO_CHECK(!channel->playSound(nil, false));
		TestSound *sound = [[[TestSound alloc] init] autorelease];
		sound->_frames = 22050;
		OO_CHECK(channel->playSound(sound, false) && channel->sound() == sound);
		channel->stop();
		OO_CHECK(channel->sound() == nil);
		// The delegate is told of the channel.
		OO_CHECK(delegate._finished.size() == 1 && delegate._lastChannel == channel.get());
		channel->setDelegate(nullptr);
	}
}


// A channel released while it plays tells the delegate of itself, as the facade's -dealloc did
// (bead oo-9ht.86 moved that into the destructor).
OO_TEST(releasedWhilePlayingTellsTheDelegate)
{
	SetUp();
	TestDelegate delegate;
	OOSoundChannel *released = nullptr;
	TestSound *sound = nil;
	@autoreleasepool
	{
		oo::Ref<OOSoundChannel> channel = NewChannel();
		sound = [[[TestSound alloc] init] autorelease];
		sound->_frames = 22050;
		channel->setDelegate(&delegate);
		OO_CHECK(channel->playSound(sound, false));
		released = channel.get();
		channel = nullptr;	// the last reference
		OO_CHECK(delegate._finished.size() == 1 && delegate._finished[0] == sound);
	}
	OO_CHECK(delegate._lastChannel == released);	// the channel itself, while it was destroyed
	OO_CHECK(gLiveSounds == 0);
}


OO_TEST_MAIN()
