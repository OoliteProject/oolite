/*	test_OOSoundMixer.mm
	Unit tests for OOSoundMixer (src/Core/OOALSoundMixer.h): bead oo-6g4z, a class of the Audio
	module (proposed ADR-0056, amendment oo-2en), and a singleton (amendment oo-r7m0).

	The mixer is made on first use, after setting sound up, with kMixerGeneralChannels channels on
	a free list that the sound sources pop and push; -update updates every channel, and -shutdown
	(at exit) releases them. OpenAL runs on OpenAL Soft's null backend and the user's defaults are
	a scratch folder's, as in test_OOSound.mm. The channels are this file's stubs (C++ since bead
	oo-9ht.86), which count what they are told (the real ones would make OpenAL sources); so are the
	decoder and the two concrete sounds that OOALSound.mm names (amendment oo-z1s4 item 4). The
	root's +update is the game's, so it reaches this mixer. These expectations were written
	against the Objective-C API and ran on the unconverted class first; they ran through the facade until bead oo-9ht.87 deleted
	it, and now ask the C++ mixer with the same expectations (the facade's own contract was retired
	with it: ADR-0049, standing approval oo-9n5p9). Before the shutdown, which is last, comes the
	C++ API. Run: bash tools/check-core-tests.sh test_OOSoundMixer
*/

#import "OOALSoundMixer.h"
#import "OOALSoundChannel.h"
#import "OOALSound.h"
#import "OOALBufferedSound.h"
#import "OOALStreamedSound.h"

#include "oo_test.hpp"

#include <cstdlib>
#include <filesystem>
#include <map>
#include <process.h>
#include <set>
#include <string>

namespace stdfs = std::filesystem;


void OOLogGenericSubclassResponsibilityForFunction(const char *inFunction)
{
	(void)inFunction;
}


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


/*	The channels: a C++ stand-in since bead oo-9ht.86 deleted the Objective-C facade this file
	stubbed (the members the mixer calls). They count the live ones and the updates each is sent;
	the free list's link is the channel's own _next.
*/
static int gLiveChannels = 0;
static int gChannelUpdates = 0;
static std::map<OOSoundChannel *, int> gUpdates;	// per channel: the stub's _updates


bool OOSoundChannel::init()
{
	gLiveChannels++;
	return true;
}


OOSoundChannel::~OOSoundChannel()
{
	gLiveChannels--;
	gUpdates.erase(this);
}


void OOSoundChannel::update()
{
	gUpdates[this]++;
	gChannelUpdates++;
}


OOSoundChannel *OOSoundChannel::next()
{
	return _next;
}


void OOSoundChannel::setNext(OOSoundChannel *next)
{
	_next = next;
}


namespace {

stdfs::path sRoot;


void SetUp()
{
	if (!sRoot.empty())  return;
	OO_CHECK(::_putenv_s("ALSOFT_DRIVERS", "null") == 0);
	sRoot = stdfs::temp_directory_path() / ("oo-test-soundmixer-" + std::to_string(static_cast<unsigned long>(::_getpid())));
	stdfs::remove_all(sRoot);
	stdfs::create_directories(sRoot);
	OO_CHECK(::_putenv_s("HOMEPATH", sRoot.string().c_str()) == 0);
	stdfs::current_path(sRoot);
}

}	// namespace


// First: the shared mixer sets sound up and makes its channels, once.
OO_TEST(theSharedMixerMakesItsChannels)
{
	SetUp();
	OO_CHECK(![OOSound isSoundOK]);
	OOSoundMixer *mixer = OOSoundMixer::sharedMixer();
	OO_CHECK(mixer != nullptr);
	OO_CHECK([OOSound isSoundOK]);
	OO_CHECK(gLiveChannels == kMixerGeneralChannels);
	OO_CHECK(OOSoundMixer::sharedMixer() == mixer);
	OO_CHECK(gLiveChannels == kMixerGeneralChannels);
}


// The free list: last pushed, first popped; each channel once; nil when empty.
OO_TEST(popAndPushTheFreeList)
{
	SetUp();
	OOSoundMixer *mixer = OOSoundMixer::sharedMixer();
	std::set<OOSoundChannel *> popped;
	OOSoundChannel *first = nullptr;
	for (int i = 0; i < kMixerGeneralChannels; i++)
	{
		OOSoundChannel *channel = mixer->popChannel();
		OO_CHECK(channel != nullptr && channel->next() == nullptr);
		if (first == nullptr)  first = channel;
		popped.insert(channel);
	}
	OO_CHECK(popped.size() == kMixerGeneralChannels);
	OO_CHECK(mixer->popChannel() == nullptr);
	OO_CHECK(mixer->popChannel() == nullptr);

	OOSoundChannel *a = *popped.begin();
	OOSoundChannel *b = *popped.rbegin();
	mixer->pushChannel(a);
	mixer->pushChannel(b);
	OO_CHECK(b->next() == a);
	OO_CHECK(mixer->popChannel() == b);
	OO_CHECK(mixer->popChannel() == a);
	OO_CHECK(mixer->popChannel() == nullptr);

	for (OOSoundChannel *channel : popped)  mixer->pushChannel(channel);
	OO_CHECK(gLiveChannels == kMixerGeneralChannels);
	(void)first;
}


// -update, and the root's +update, update every channel once.
OO_TEST(updateUpdatesEveryChannel)
{
	SetUp();
	OOSoundMixer *mixer = OOSoundMixer::sharedMixer();
	const int before = gChannelUpdates;
	mixer->update();
	OO_CHECK(gChannelUpdates == before + kMixerGeneralChannels);
	[OOSound update];
	OO_CHECK(gChannelUpdates == before + 2 * kMixerGeneralChannels);

	OOSoundChannel *channel = mixer->popChannel();
	OO_CHECK(gUpdates[channel] == 2);
	mixer->pushChannel(channel);
}


// The C++ API: the one mixer, the same free list and the same channels on every call.
OO_TEST(cxxApi)
{
	SetUp();
	OOSoundMixer *mixer = OOSoundMixer::sharedMixer();
	OO_CHECK(mixer != nullptr && mixer == OOSoundMixer::sharedMixer());

	OOSoundChannel *channel = mixer->popChannel();
	OO_CHECK(channel != nullptr && channel->next() == nullptr);
	mixer->pushChannel(channel);
	OO_CHECK(OOSoundMixer::sharedMixer()->popChannel() == channel);
	OOSoundMixer::sharedMixer()->pushChannel(channel);

	const int before = gChannelUpdates;
	mixer->update();
	OO_CHECK(gChannelUpdates == before + kMixerGeneralChannels);
}


// Last: -shutdown releases the channels; -update then has nothing to update.
OO_TEST(shutdownReleasesTheChannels)
{
	SetUp();
	OOSoundMixer *mixer = OOSoundMixer::sharedMixer();
	mixer->shutdown();
	OO_CHECK(gLiveChannels == 0);
	const int before = gChannelUpdates;
	mixer->update();
	OO_CHECK(gChannelUpdates == before);
	OO_CHECK(OOSoundMixer::sharedMixer() == mixer);
}


OO_TEST_MAIN()
