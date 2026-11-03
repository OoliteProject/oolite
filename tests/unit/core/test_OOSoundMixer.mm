/*	test_OOSoundMixer.mm
	Unit tests for OOSoundMixer (src/Core/OOALSoundMixer.h): bead oo-6g4z, a class of the Audio
	module (proposed ADR-0056, amendment oo-2en), and a singleton (amendment oo-r7m0).

	The mixer is made on first use, after setting sound up, with kMixerGeneralChannels channels on
	a free list that the sound sources pop and push; -update updates every channel, and -shutdown
	(at exit) releases them. OpenAL runs on OpenAL Soft's null backend and the user's defaults are
	a scratch folder's, as in test_OOSound.mm. The channels are this file's stubs, which count what
	they are told (the real ones would make OpenAL sources); so are the decoder and the two
	concrete sounds that OOALSound.mm names (amendment oo-z1s4 item 4). The root's +update is the
	game's, so it reaches this mixer. These expectations were written against the Objective-C API
	and ran on the unconverted class first; they now run through the facade, which is its forwarding
	test. Before the shutdown, which is last, come the C++ API (cxx::OOSoundMixer) and the facade's
	contract. Run: bash tools/check-core-tests.sh test_OOSoundMixer
*/

#import "OOALSoundMixer.h"
#import "OOALSound.h"

#include "oo_test.hpp"

#include <cstdlib>
#include <filesystem>
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

@interface OOALBufferedSound: OOSound
@end

@implementation OOALBufferedSound
@end

@interface OOALStreamedSound: OOSound
@end

@implementation OOALStreamedSound
@end


static int gLiveChannels = 0;
static int gChannelUpdates = 0;

@interface OOSoundChannel: OOObject
{
@public
	OOSoundChannel	*_next;
	int				_updates;
}

- (OOSoundChannel *) next;
- (void) setNext:(OOSoundChannel *)next;

@end


@implementation OOSoundChannel

- (id) init
{
	self = [super init];
	if (self != nil)  gLiveChannels++;
	return self;
}


- (void) dealloc
{
	gLiveChannels--;
	[super dealloc];
}


- (void) update
{
	_updates++;
	gChannelUpdates++;
}


- (OOSoundChannel *) next
{
	return _next;
}


- (void) setNext:(OOSoundChannel *)next
{
	_next = next;
}

@end


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
	OOSoundMixer *mixer = [OOSoundMixer sharedMixer];
	OO_CHECK(mixer != nil);
	OO_CHECK([OOSound isSoundOK]);
	OO_CHECK(gLiveChannels == kMixerGeneralChannels);
	OO_CHECK([OOSoundMixer sharedMixer] == mixer);
	OO_CHECK(gLiveChannels == kMixerGeneralChannels);
}


// The free list: last pushed, first popped; each channel once; nil when empty.
OO_TEST(popAndPushTheFreeList)
{
	SetUp();
	OOSoundMixer *mixer = [OOSoundMixer sharedMixer];
	std::set<OOSoundChannel *> popped;
	OOSoundChannel *first = nil;
	for (int i = 0; i < kMixerGeneralChannels; i++)
	{
		OOSoundChannel *channel = [mixer popChannel];
		OO_CHECK(channel != nil && [channel next] == nil);
		if (first == nil)  first = channel;
		popped.insert(channel);
	}
	OO_CHECK(popped.size() == kMixerGeneralChannels);
	OO_CHECK([mixer popChannel] == nil);
	OO_CHECK([mixer popChannel] == nil);

	OOSoundChannel *a = *popped.begin();
	OOSoundChannel *b = *popped.rbegin();
	[mixer pushChannel:a];
	[mixer pushChannel:b];
	OO_CHECK([b next] == a);
	OO_CHECK([mixer popChannel] == b);
	OO_CHECK([mixer popChannel] == a);
	OO_CHECK([mixer popChannel] == nil);

	for (OOSoundChannel *channel : popped)  [mixer pushChannel:channel];
	OO_CHECK(gLiveChannels == kMixerGeneralChannels);
	(void)first;
}


// -update, and the root's +update, update every channel once.
OO_TEST(updateUpdatesEveryChannel)
{
	SetUp();
	OOSoundMixer *mixer = [OOSoundMixer sharedMixer];
	const int before = gChannelUpdates;
	[mixer update];
	OO_CHECK(gChannelUpdates == before + kMixerGeneralChannels);
	[OOSound update];
	OO_CHECK(gChannelUpdates == before + 2 * kMixerGeneralChannels);

	OOSoundChannel *channel = [mixer popChannel];
	OO_CHECK(channel->_updates == 2);
	[mixer pushChannel:channel];
}


// The C++ API: the one mixer, the same free list and the same channels as the facade's.
OO_TEST(cxxApi)
{
	SetUp();
	cxx::OOSoundMixer *mixer = cxx::OOSoundMixer::sharedMixer();
	OO_CHECK(mixer != nullptr && mixer == cxx::OOSoundMixer::sharedMixer());
	OOSoundMixer *facade = [OOSoundMixer sharedMixer];	// +sharedMixer answers id
	OO_CHECK(oo::ToCxx(facade) == mixer);

	OOSoundChannel *channel = mixer->popChannel();
	OO_CHECK(channel != nil && [channel next] == nil);
	mixer->pushChannel(channel);
	OO_CHECK([[OOSoundMixer sharedMixer] popChannel] == channel);
	[[OOSoundMixer sharedMixer] pushChannel:channel];

	const int before = gChannelUpdates;
	mixer->update();
	OO_CHECK(gChannelUpdates == before + kMixerGeneralChannels);
}


// The facade's contract: one facade for the life of the process.
OO_TEST(facade)
{
	SetUp();
	OOSoundMixer *facade = nil;
	@autoreleasepool
	{
		facade = [OOSoundMixer sharedMixer];
	}
	OO_CHECK(facade == [OOSoundMixer sharedMixer]);
	OO_CHECK(oo::ToObjC(cxx::OOSoundMixer::sharedMixer()) == facade);
	OOSoundMixer *none = nil;
	OO_CHECK(oo::ToCxx(none) == nullptr);
	OO_CHECK(oo::ToObjC(static_cast<cxx::OOSoundMixer *>(nullptr)) == nil);
}


// Last: -shutdown releases the channels; -update then has nothing to update.
OO_TEST(shutdownReleasesTheChannels)
{
	SetUp();
	OOSoundMixer *mixer = [OOSoundMixer sharedMixer];
	[mixer shutdown];
	OO_CHECK(gLiveChannels == 0);
	const int before = gChannelUpdates;
	[mixer update];
	OO_CHECK(gChannelUpdates == before);
	OO_CHECK([OOSoundMixer sharedMixer] == mixer);
}


OO_TEST_MAIN()
