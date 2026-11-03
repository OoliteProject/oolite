/*	test_OOMusic.mm
	Unit tests for OOMusic (src/Core/OOALMusic.h): bead oo-nwbw, a sound of the Audio module
	(proposed ADR-0056, amendment oo-2en), a subclass of the converted root OOSound that overrides
	the root's class-cluster initialiser.

	A music wraps the sound the root's cluster loads for its path and plays it through one sound
	source that every music shares, made on first play and never released; only one music plays
	at a time. OpenAL runs on OpenAL Soft's null backend and the user's defaults are a scratch
	folder's, as in test_OOSound.mm. The sound source is the game's; the mixer and its channels
	under it are this file's stubs, which record what the source tells them, and so are the
	decoder and the two concrete sounds that OOALSound.mm names (amendment oo-z1s4 item 4; C++
	stand-ins since beads oo-9ht.82, oo-9ht.83 and oo-9ht.84 deleted their facades): "missing.ogg"
	has no decoder. These expectations were written against the Objective-C API and ran on the
	unconverted class first; since bead oo-9ht.85 deleted the facade they run through the C++ API
	(OOMusic, a subclass of OOSound), and since beads oo-9ht.68 and oo-9ht.88 deleted the sound's
	and the source's facades they ask the C++ source (standing approval oo-9n5p9).
	Run: bash tools/check-core-tests.sh test_OOMusic
*/

#import "OOALMusic.h"
#import "OOALBufferedSound.h"
#import "OOALStreamedSound.h"
#import "OOALSoundMixer.h"
#import "OOALSoundDecoder.h"

#include "oo_test.hpp"

#include <cstdlib>
#include <filesystem>
#include <process.h>
#include <string>
#include <vector>

namespace stdfs = std::filesystem;


void OOLogGenericSubclassResponsibilityForFunction(const char *inFunction)
{
	(void)inFunction;
}


/*	The decoder: "missing.ogg" (and no path) has none; any other is small. Counts the decoders
	alive. A C++ stand-in since bead oo-9ht.82 deleted the Objective-C facade this file stubbed: the
	factory the cluster calls, a subclass answering the path, and the root's members
	(OOALSoundDecoder.mm is not linked), which its vtable names.
*/
static int gLiveDecoders = 0;

namespace {
class TestDecoder final : public OOALSoundDecoder
{
public:
	explicit TestDecoder(const std::string &path) : _path(path)  { gLiveDecoders++; }
	~TestDecoder() override  { gLiveDecoders--; }

	size_t sizeAsBuffer() override  { return 1000; }
	std::optional<std::string> name() override  { return _path; }

private:
	std::string	_path;
};
}	// namespace


oo::Ref<OOALSoundDecoder> OOALSoundDecoder::initWithPath(const std::optional<std::string> &inPath)
{
	if (!inPath.has_value() || *inPath == "missing.ogg")  return nullptr;
	return oo::makeRef<TestDecoder>(*inPath);
}

bool OOALSoundDecoder::readCreatingBuffer(char **, size_t *)  { return false; }
size_t OOALSoundDecoder::streamToBuffer(char *)  { return 0; }
size_t OOALSoundDecoder::sizeAsBuffer()  { return 0; }
bool OOALSoundDecoder::isStereo()  { return false; }
long OOALSoundDecoder::sampleRate()  { return 0; }
void OOALSoundDecoder::reset()  {}
std::optional<std::string> OOALSoundDecoder::name()  { return std::string(); }
std::optional<std::string> OOALSoundDecoder::descriptionComponents() const  { return std::nullopt; }


static int gLiveSounds = 0;

// The buffered sound: a C++ stand-in since bead oo-9ht.83 deleted the Objective-C facade this file
// stubbed (the members the cluster and the root call). Counts the live ones.
oo::Ref<OOALBufferedSound> OOALBufferedSound::initWithDecoder(OOALSoundDecoder *inDecoder)
{
	oo::Ref<OOALBufferedSound> sound = oo::adopt(new OOALBufferedSound);
	sound->_name = inDecoder->name();
	gLiveSounds++;
	return sound;
}


OOALBufferedSound::~OOALBufferedSound()
{
	gLiveSounds--;
}


std::optional<std::string> OOALBufferedSound::name()
{
	return _name;
}


ALuint OOALBufferedSound::soundBuffer()
{
	return OOSound::soundBuffer();	// the stub did not override it
}


// The streamed sound: a C++ stand-in since bead oo-9ht.84 deleted the Objective-C facade this
// file stubbed. It refuses every decoder, as the stub did.
oo::Ref<OOALStreamedSound> OOALStreamedSound::initWithDecoder(OOALSoundDecoder *inDecoder)	{ (void)inDecoder; return nullptr; }
OOALStreamedSound::~OOALStreamedSound()  {}
std::optional<std::string> OOALStreamedSound::name()  { return _name; }
void OOALStreamedSound::rewind()  {}
bool OOALStreamedSound::soundIncomplete()  { return false; }
ALuint OOALStreamedSound::soundBuffer()  { return 0; }


/*	The mixer and its channels, under the real sound source (OOSoundSource.mm): the mixer hands
	out channels that record what they are told, in order, and a stopped channel tells its
	delegate as the real one does. The channel is a C++ stand-in since bead oo-9ht.86 deleted the
	Objective-C facade this file stubbed (the members the source calls), with its own delegate and
	sound.
*/
static std::vector<std::string> gChannelLog;

OOSoundChannel::~OOSoundChannel()  {}
void OOSoundChannel::setDelegate(OOSoundChannelDelegate *delegate)  { _delegate = delegate; }
void OOSoundChannel::setPosition(Vector position)  { (void)position; }
void OOSoundChannel::setGain(float gain)  { gChannelLog.push_back("gain " + std::to_string(gain)); }


bool OOSoundChannel::playSound(OOSound *sound, bool loop)
{
	gChannelLog.push_back("play " + ((sound != nullptr) ? sound->name() : std::nullopt).value_or("(none)") + (loop ? " looped" : ""));
	_sound = oo::Ref<OOSound>(sound);	// [sound retain]
	return true;
}


void OOSoundChannel::stop()
{
	gChannelLog.push_back("stop");
	oo::Ref<OOSound> sound = std::move(_sound);	// _sound = nil; [sound release] at the end of the scope
	if (_delegate != nullptr)  _delegate->channel(this, sound.get());
}


static int gChannelsOut = 0;

// The mixer (a C++ stand-in since bead oo-9ht.87 deleted the Objective-C facade this file stubbed):
// one, never released, handing out a new channel each time.
OOSoundMixer *OOSoundMixer::sharedMixer()
{
	static OOSoundMixer *mixer = oo::makeRef<OOSoundMixer>().leakRef();
	return mixer;
}


void OOSoundMixer::update()
{
}


void OOSoundMixer::shutdown()
{
}


::OOSoundChannel *OOSoundMixer::popChannel()
{
	gChannelsOut++;
	return oo::makeRef<OOSoundChannel>().leakRef();	// leaked: a few per run
}


void OOSoundMixer::pushChannel(::OOSoundChannel *channel)
{
	(void)channel;
	gChannelsOut--;
}


namespace {

stdfs::path sRoot;


void SetUp()
{
	if (!sRoot.empty())  return;
	OO_CHECK(::_putenv_s("ALSOFT_DRIVERS", "null") == 0);
	sRoot = stdfs::temp_directory_path() / ("oo-test-music-" + std::to_string(static_cast<unsigned long>(::_getpid())));
	stdfs::remove_all(sRoot);
	stdfs::create_directories(sRoot);
	OO_CHECK(::_putenv_s("HOMEPATH", sRoot.string().c_str()) == 0);
	stdfs::current_path(sRoot);
	OO_CHECK(OOSound::setUp());
}


std::vector<std::string> TakeChannelLog()
{
	std::vector<std::string> result;
	result.swap(gChannelLog);
	return result;
}

}	// namespace


// First: before any music has played there is no source; its gain is 0 and setting it does nothing.
OO_TEST(noSourceBeforeTheFirstPlay)
{
	SetUp();
	@autoreleasepool
	{
		oo::Ref<OOMusic> music = OOMusic::initWithContentsOfFile(std::string("theme.ogg"));
		OO_CHECK(music != nil);
		OO_CHECK(music->musicSoundSource() == nil);
		OO_CHECK(music->musicGain() == 0.0f);
		music->setMusicGain(0.5f);
		OO_CHECK(!music->isPlaying());
		music->stop();
		OO_CHECK(TakeChannelLog().empty() && gChannelsOut == 0);
	}
}


// A music wraps the sound the root's cluster loads, and answers its name.
OO_TEST(wrapsTheClustersSound)
{
	SetUp();
	@autoreleasepool
	{
		oo::Ref<OOMusic> music = OOMusic::initWithContentsOfFile(std::string("theme.ogg"));
		OO_CHECK(music.get() != nullptr);
		OO_CHECK(music->name() == std::optional<std::string>("theme.ogg"));
		OO_CHECK(gLiveSounds == 1 && gLiveDecoders == 0);
		OO_CHECK(!music->soundIncomplete());

		OO_CHECK(!OOMusic::initWithContentsOfFile(std::string("missing.ogg")));
		OO_CHECK(!OOMusic::initWithContentsOfFile(std::nullopt));
		OO_CHECK(gLiveSounds == 1);
	}
	OO_CHECK(gLiveSounds == 0);	// released with the music
}


OO_TEST(playsThroughTheSharedSource)
{
	SetUp();
	TakeChannelLog();
	@autoreleasepool
	{
		oo::Ref<OOMusic> theme = OOMusic::initWithContentsOfFile(std::string("theme.ogg"));
		theme->playLooped(true);
		OO_CHECK((TakeChannelLog() == std::vector<std::string>{ "gain 1.000000", "play theme.ogg looped" }));
		OO_CHECK(theme->isPlaying() && gChannelsOut == 1);
		OOSoundSource *source = theme->musicSoundSource();
		OO_CHECK(source != nullptr && source->sound() != nullptr && source->loop());

		theme->playLooped(false);	// already playing: nothing
		OO_CHECK(TakeChannelLog().empty());

		theme->setMusicGain(0.25f);
		OO_CHECK(theme->musicGain() == 0.25f && source->gain() == 0.25f);
		OO_CHECK((TakeChannelLog() == std::vector<std::string>{ "gain 0.250000" }));

		// Another music takes the source; the first is no longer playing.
		oo::Ref<OOMusic> docked = OOMusic::initWithContentsOfFile(std::string("docked.ogg"));
		OO_CHECK(!docked->isPlaying());
		docked->playLooped(false);
		OO_CHECK(docked->musicSoundSource() == source && gChannelsOut == 1);
		OO_CHECK((TakeChannelLog() == std::vector<std::string>{ "stop", "gain 0.250000", "play docked.ogg" }));
		OO_CHECK(docked->isPlaying() && !theme->isPlaying() && !source->loop());

		theme->stop();	// not the playing one: nothing
		OO_CHECK(TakeChannelLog().empty() && docked->isPlaying());

		docked->stop();
		OO_CHECK((TakeChannelLog() == std::vector<std::string>{ "stop" }));
		OO_CHECK(!docked->isPlaying() && source->sound() == nullptr && gChannelsOut == 0);

		// Played again after it was stopped.
		docked->playLooped(true);
		OO_CHECK(docked->isPlaying() && source->sound() != nullptr);
		docked->stop();
		TakeChannelLog();
	}
}


// A playing music that is released stops first.
OO_TEST(releasedWhilePlaying)
{
	SetUp();
	TakeChannelLog();
	OOSoundSource *source = nullptr;
	@autoreleasepool
	{
		oo::Ref<OOMusic> music = OOMusic::initWithContentsOfFile(std::string("theme.ogg"));
		music->playLooped(true);
		source = music->musicSoundSource();
		TakeChannelLog();
		music = nullptr;
	}
	OO_CHECK((TakeChannelLog() == std::vector<std::string>{ "stop" }));
	OO_CHECK(source != nullptr && source->sound() == nullptr && !source->isPlaying());
	OO_CHECK(gLiveSounds == 0);
}


// The C++ API: the factory hides the root's and answers null where the initialiser answered nil.
OO_TEST(cxxApi)
{
	SetUp();
	TakeChannelLog();
	@autoreleasepool
	{
		OO_CHECK(!OOMusic::initWithContentsOfFile(std::string("missing.ogg")));
		const oo::Ref<OOMusic> music = OOMusic::initWithContentsOfFile(std::string("theme.ogg"));
		OO_CHECK(music && music->name() == std::optional<std::string>("theme.ogg"));
		OO_CHECK(!music->isPlaying() && music->soundBuffer() == 0);	// the root's default
		music->playLooped(false);
		OO_CHECK(music->isPlaying() && music->musicSoundSource() != nil);
		music->setMusicGain(0.5f);
		OO_CHECK(music->musicGain() == 0.5f);
		music->stop();
		OO_CHECK(!music->isPlaying());
		OO_CHECK((TakeChannelLog() == std::vector<std::string>{ "gain 0.250000", "play theme.ogg", "gain 0.500000", "stop" }));
	}
	OO_CHECK(gLiveSounds == 0);
}


OO_TEST_MAIN()
