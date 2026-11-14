/*	test_OOMusic.mm
	Unit tests for OOMusic (src/Core/OOALMusic.h): bead oo-nwbw, a sound of the Audio module
	(proposed ADR-0056, amendment oo-2en), a subclass of the converted root OOSound that overrides
	the root's class-cluster initialiser.

	A music wraps the sound the root's cluster loads for its path and plays it through one sound
	source that every music shares, made on first play and never released; only one music plays
	at a time. OpenAL runs on OpenAL Soft's null backend and the user's defaults are a scratch
	folder's, as in test_OOSound.mm. The sound source is the game's; the mixer and its channels
	under it are this file's stubs, which record what the source tells them, and so are the
	decoder and the two concrete sounds that OOALSound.mm names (amendment oo-z1s4 item 4):
	"missing.ogg" has no decoder. These expectations were written against the Objective-C
	API and ran on the unconverted class first; they now run through the facade, which is its
	forwarding test. After them come the C++ API (cxx::OOMusic, a subclass of cxx::OOSound) and the
	facade's contract. Run: bash tools/check-core-tests.sh test_OOMusic
*/

#import "OOALMusic.h"
#import "OODescription.h"

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


static int gLiveDecoders = 0;

@interface OOALSoundDecoder: OOObject
{
	std::optional<std::string>	_path;
}

- (id)cxx_initWithPath:(const std::optional<std::string> &)inPath OO_RETURNS_RETAINED;
- (size_t)sizeAsBuffer;
- (std::optional<std::string>)cxx_name;

@end


@implementation OOALSoundDecoder

- (id)cxx_initWithPath:(const std::optional<std::string> &)inPath
{
	if (!inPath.has_value() || *inPath == "missing.ogg")
	{
		[self release];
		return nil;
	}
	self = [super init];
	if (self != nil)
	{
		_path = inPath;
		gLiveDecoders++;
	}
	return self;
}


- (void)dealloc
{
	if (_path.has_value())  gLiveDecoders--;
	[super dealloc];
}


- (size_t)sizeAsBuffer
{
	return 1000;
}


- (std::optional<std::string>)cxx_name
{
	return _path;
}

@end


static int gLiveSounds = 0;

@interface OOALBufferedSound: OOSound
{
	std::optional<std::string>	_name;
}

- (id)initWithDecoder:(OOALSoundDecoder *)inDecoder;

@end


@implementation OOALBufferedSound

- (id)initWithDecoder:(OOALSoundDecoder *)inDecoder
{
	self = [super init];
	if (self != nil)
	{
		_name = [inDecoder cxx_name];
		gLiveSounds++;
	}
	return self;
}


- (void)dealloc
{
	gLiveSounds--;
	[super dealloc];
}


- (std::optional<std::string>)cxx_name
{
	return _name;
}

@end


@interface OOALStreamedSound: OOSound

- (id)initWithDecoder:(OOALSoundDecoder *)inDecoder;

@end


@implementation OOALStreamedSound

- (id)initWithDecoder:(OOALSoundDecoder *)inDecoder
{
	(void)inDecoder;
	[self release];
	return nil;
}

@end


/*	The mixer and its channels, under the real sound source (OOSoundSource.mm): the mixer hands
	out channels that record what they are told, in order, and a stopped channel tells its
	delegate as the real one does.
*/
static std::vector<std::string> gChannelLog;

@interface OOObject (TestChannelDelegate)
- (void)channel:(id)inChannel didFinishPlayingSound:(OOSound *)inSound;
@end

@interface OOSoundChannel: OOObject
{
@public
	id			_delegate;
	OOSound		*_sound;
}
@end


@implementation OOSoundChannel

- (void) setDelegate:(id)delegate		{ _delegate = delegate; }
- (void) setPosition:(Vector)position	{ (void)position; }
- (void) setGain:(float)gain			{ gChannelLog.push_back("gain " + std::to_string(gain)); }


- (BOOL) playSound:(OOSound *)sound looped:(BOOL)loop
{
	gChannelLog.push_back("play " + [sound cxx_name].value_or("(none)") + (loop ? " looped" : ""));
	_sound = [sound retain];
	return YES;
}


- (void) stop
{
	gChannelLog.push_back("stop");
	OOSound *sound = _sound;
	_sound = nil;
	[_delegate channel:self didFinishPlayingSound:sound];
	[sound release];
}

@end


static int gChannelsOut = 0;

@interface OOSoundMixer: OOObject
+ (id) sharedMixer;
@end


@implementation OOSoundMixer

+ (id) sharedMixer
{
	static OOSoundMixer *mixer = nil;
	if (mixer == nil)  mixer = [[OOSoundMixer alloc] init];
	return mixer;
}


- (void) update
{
}


- (OOSoundChannel *) popChannel
{
	gChannelsOut++;
	return [[OOSoundChannel alloc] init];	// leaked: a few per run
}


- (void) pushChannel:(OOSoundChannel *)channel
{
	(void)channel;
	gChannelsOut--;
}

@end


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
	OO_CHECK([OOSound setUp]);
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
		OOMusic *music = [[[OOMusic alloc] cxx_initWithContentsOfFile:std::string("theme.ogg")] autorelease];
		OO_CHECK(music != nil);
		OO_CHECK([music musicSoundSource] == nil);
		OO_CHECK([music musicGain] == 0.0f);
		[music setMusicGain:0.5f];
		OO_CHECK(![music isPlaying]);
		[music stop];
		OO_CHECK(TakeChannelLog().empty() && gChannelsOut == 0);
	}
}


// A music wraps the sound the root's cluster loads, and answers its name.
OO_TEST(wrapsTheClustersSound)
{
	SetUp();
	@autoreleasepool
	{
		OOMusic *music = [[[OOMusic alloc] cxx_initWithContentsOfFile:std::string("theme.ogg")] autorelease];
		OO_CHECK([music isKindOfClass:[OOMusic class]] && [music isKindOfClass:[OOSound class]]);
		OO_CHECK([music cxx_name] == std::optional<std::string>("theme.ogg"));
		OO_CHECK(gLiveSounds == 1 && gLiveDecoders == 0);
		OO_CHECK(![music soundIncomplete]);

		OO_CHECK([[OOMusic alloc] cxx_initWithContentsOfFile:std::string("missing.ogg")] == nil);
		OO_CHECK([[OOMusic alloc] cxx_initWithContentsOfFile:std::nullopt] == nil);
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
		OOMusic *theme = [[[OOMusic alloc] cxx_initWithContentsOfFile:std::string("theme.ogg")] autorelease];
		[theme playLooped:YES];
		OO_CHECK((TakeChannelLog() == std::vector<std::string>{ "gain 1.000000", "play theme.ogg looped" }));
		OO_CHECK([theme isPlaying] && gChannelsOut == 1);
		OOSoundSource *source = [theme musicSoundSource];
		OO_CHECK(source != nil && [source sound] != nil && [source loop]);

		[theme playLooped:NO];	// already playing: nothing
		OO_CHECK(TakeChannelLog().empty());

		[theme setMusicGain:0.25f];
		OO_CHECK([theme musicGain] == 0.25f && [source gain] == 0.25f);
		OO_CHECK((TakeChannelLog() == std::vector<std::string>{ "gain 0.250000" }));

		// Another music takes the source; the first is no longer playing.
		OOMusic *docked = [[[OOMusic alloc] cxx_initWithContentsOfFile:std::string("docked.ogg")] autorelease];
		OO_CHECK(![docked isPlaying]);
		[docked playLooped:NO];
		OO_CHECK([docked musicSoundSource] == source && gChannelsOut == 1);
		OO_CHECK((TakeChannelLog() == std::vector<std::string>{ "stop", "gain 0.250000", "play docked.ogg" }));
		OO_CHECK([docked isPlaying] && ![theme isPlaying] && ![source loop]);

		[theme stop];	// not the playing one: nothing
		OO_CHECK(TakeChannelLog().empty() && [docked isPlaying]);

		[docked stop];
		OO_CHECK((TakeChannelLog() == std::vector<std::string>{ "stop" }));
		OO_CHECK(![docked isPlaying] && [source sound] == nil && gChannelsOut == 0);

		// Played again after it was stopped.
		[docked playLooped:YES];
		OO_CHECK([docked isPlaying] && [source sound] != nil);
		[docked stop];
		TakeChannelLog();
	}
}


// A playing music that is released stops first.
OO_TEST(releasedWhilePlaying)
{
	SetUp();
	TakeChannelLog();
	OOSoundSource *source = nil;
	@autoreleasepool
	{
		OOMusic *music = [[OOMusic alloc] cxx_initWithContentsOfFile:std::string("theme.ogg")];
		[music playLooped:YES];
		source = [music musicSoundSource];
		TakeChannelLog();
		[music release];
	}
	OO_CHECK((TakeChannelLog() == std::vector<std::string>{ "stop" }));
	OO_CHECK(source != nil && [source sound] == nil && ![source isPlaying]);
	OO_CHECK(gLiveSounds == 0);
}


// The C++ API: the factory hides the root's and answers null where the initialiser answered nil.
OO_TEST(cxxApi)
{
	SetUp();
	TakeChannelLog();
	@autoreleasepool
	{
		OO_CHECK(!cxx::OOMusic::initWithContentsOfFile(std::string("missing.ogg")));
		const oo::Ref<cxx::OOMusic> music = cxx::OOMusic::initWithContentsOfFile(std::string("theme.ogg"));
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


// The facade's contract: a music's facade is an OOMusic, one per music, and is what
// [[OOMusic alloc] cxx_initWithContentsOfFile:] answers.
OO_TEST(facade)
{
	SetUp();
	@autoreleasepool
	{
		const oo::Ref<cxx::OOMusic> music = cxx::OOMusic::initWithContentsOfFile(std::string("theme.ogg"));
		OOMusic *facade = oo::ToObjC(music.get());
		OO_CHECK([facade isKindOfClass:[OOMusic class]]);
		OO_CHECK(facade == oo::ToObjC(static_cast<cxx::OOSound *>(music.get())));
		OO_CHECK(oo::ToCxx(facade) == music.get());
		OO_CHECK(oo::DescriptionOf(facade).starts_with("<OOMusic 0x"));

		OOMusic *made = [[[OOMusic alloc] cxx_initWithContentsOfFile:std::string("docked.ogg")] autorelease];
		OO_CHECK(oo::ToObjC(oo::ToCxx(made)) == made);
		OO_CHECK(oo::ToCxx(made)->name() == std::optional<std::string>("docked.ogg"));
	}
	OOMusic *none = nil;
	OO_CHECK(oo::ToCxx(none) == nullptr);
	OO_CHECK(oo::ToObjC(static_cast<cxx::OOMusic *>(nullptr)) == nil);
}


OO_TEST_MAIN()
