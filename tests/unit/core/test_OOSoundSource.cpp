/*	test_OOSoundSource.mm
	Unit tests for OOSoundSource (src/Core/OOSoundSource.h): bead oo-zoj3, a class of the Audio
	module (proposed ADR-0056, amendment oo-2en).

	A sound source plays one sound at a time through a channel it pops from the shared mixer, as
	the channel's delegate: it gives the channel its position and gain, keeps itself alive while
	it plays, plays the sound again until its repeat count is spent, and then pushes the channel
	back. +stopAll stops every source that is playing. The mixer and its channels are this file's
	stubs, which record what they are told (the real ones would make OpenAL sources); the sound is
	an opaque object to a source, so it is a stub too, with only a name (amendment oo-z1s4 item 4;
	a C++ subclass of the root since bead oo-9ht.68 deleted the facade it stood in for, with the
	root's members OOALSound.mm would define).
	The playing channel is private, so the test reads it as a friend (amendment oo-zffj item 3;
	through the runtime before the conversion). These expectations were written against the
	Objective-C API and ran on the unconverted class first; they ran through the facade, which was
	its forwarding test, until bead oo-9ht.88 deleted it: they now ask the C++ source (alloc/init as
	oo::makeRef, "%@" as descriptionComponents(), an autorelease pool as an oo::AutoreleaseScope)
	with every expectation kept (standing approval oo-9n5p9). After them comes the C++ API. The
	mixer and the channel are C++ stand-ins since beads oo-9ht.87 and oo-9ht.86 deleted their
	facades, and the source is its channel's C++ delegate (OOSoundChannelDelegate).
	Run: bash tools/check-core-tests.sh test_OOSoundSource
*/

#import "OOSoundSource.h"
#import "OOALSoundMixer.h"

#include "oo_test.hpp"
#include "oofnd/String.hpp"

#include <map>
#include <string>
#include <vector>


static int gLiveSounds = 0;

/*	The sound: OOALSound.mm is not linked, so the root's members the source and the sound's vtable
	name are defined here as the root answers them (C++ since bead oo-9ht.68 deleted the facade this
	file stubbed), and a test sound has only a name, which "%@" prints between the braces.
*/
OOSound::OOSound()  {}
std::optional<std::string> OOSound::name()  { return std::nullopt; }
ALuint OOSound::soundBuffer()  { return 0; }
bool OOSound::soundIncomplete()  { return false; }
void OOSound::rewind()  {}
std::optional<std::string> OOSound::descriptionComponents() const  { return std::nullopt; }

std::string OOSound::description() const
{
	std::string result = oo::str::format("<OOSound %s>", oo::str::pointerDescription(this).c_str());
	if (const std::optional<std::string> components = descriptionComponents())  result += "{" + *components + "}";
	return result;
}


class TestSound final : public OOSound
{
public:
	explicit TestSound(const std::string &name) : _name(name)  { gLiveSounds++; }
	~TestSound() override  { gLiveSounds--; }

	std::optional<std::string> descriptionComponents() const override  { return _name; }

	std::string		_name;
};


/*	A channel records what it is told, in order; Finish() ends its sound as the real one does when
	OpenAL stops, and stop() as its stop() does: both tell the delegate. A C++ stand-in since bead
	oo-9ht.86 deleted the Objective-C facade this file stubbed (the members a source calls): its
	delegate, sound and loop are the channel's own; the position and gain it is given are kept per
	channel here.
*/
static std::vector<std::string> gLog;

struct TestChannelState
{
	Vector	position = {};
	float	gain = 0;
};
static std::map<OOSoundChannel *, TestChannelState> gChannels;


struct OOSoundChannelTestAccess
{
	static OOSoundChannelDelegate *Delegate(OOSoundChannel *channel)  { return channel->_delegate; }

	// The stub's -finish.
	static void Finish(OOSoundChannel *channel)
	{
		oo::Ref<OOSound> sound = std::move(channel->_sound);	// [sound release] at the end of the scope
		channel->_sound = nullptr;
		if (channel->_delegate != nullptr)  channel->_delegate->channel(channel, sound.get());
	}
};


OOSoundChannel::~OOSoundChannel()
{
	gChannels.erase(this);
}


void OOSoundChannel::setDelegate(OOSoundChannelDelegate *delegate)
{
	_delegate = delegate;
}


void OOSoundChannel::setPosition(Vector position)
{
	gChannels[this].position = position;
}


void OOSoundChannel::setGain(float gain)
{
	gChannels[this].gain = gain;
}


bool OOSoundChannel::playSound(OOSound *sound, bool loop)
{
	gLog.push_back("play " + static_cast<TestSound *>(sound)->_name + (loop ? " looped" : ""));
	_loop = loop;
	_sound = oo::Ref<OOSound>(sound);	// [sound retain]
	return true;
}


void OOSoundChannel::stop()
{
	gLog.push_back("stop");
	OOSoundChannelTestAccess::Finish(this);
}


static int gChannelsOut = 0;
static int gChannelsAvailable = 8;

// The mixer (a C++ stand-in since bead oo-9ht.87 deleted the Objective-C facade this file stubbed):
// one, never released, handing out at most gChannelsAvailable channels.
OOSoundMixer *OOSoundMixer::sharedMixer()
{
	static OOSoundMixer *mixer = oo::makeRef<OOSoundMixer>().leakRef();
	return mixer;
}


::OOSoundChannel *OOSoundMixer::popChannel()
{
	if (gChannelsOut == gChannelsAvailable)  return nullptr;
	gChannelsOut++;
	return oo::makeRef<OOSoundChannel>().leakRef();	// leaked: a few per run
}


void OOSoundMixer::pushChannel(::OOSoundChannel *channel)
{
	(void)channel;
	gChannelsOut--;
	gLog.push_back("push");
}


namespace {

// [[[OOSound alloc] init] autorelease] with a name: it lives until the innermost scope ends.
OOSound *MakeSound(const char *name)
{
	return oo::autorelease(oo::makeRef<TestSound>(name));
}


std::vector<std::string> TakeLog()
{
	std::vector<std::string> result;
	result.swap(gLog);
	return result;
}


}	// namespace


struct OOSoundSourceTestAccess
{
	static OOSoundChannel *Channel(OOSoundSource *source)  { return source->_channel; }
};


namespace {

// The channel a playing source has (its private _channel).
OOSoundChannel *ChannelOf(OOSoundSource *source)
{
	return OOSoundSourceTestAccess::Channel(source);
}

}	// namespace


OO_TEST(defaults)
{
	{
		oo::AutoreleaseScope scope;	// was @autoreleasepool
		const oo::Ref<OOSoundSource> source = oo::makeRef<OOSoundSource>();
		OO_CHECK(source->sound() == nullptr);
		OO_CHECK(!source->loop() && source->repeatCount() == 1 && !source->isPlaying());
		OO_CHECK(!source->positional() && vector_equal(source->position(), kZeroVector));
		OO_CHECK(source->gain() == OO_DEFAULT_SOUNDSOURCE_GAIN);

		source->play();	// no sound: nothing
		OO_CHECK(!source->isPlaying() && TakeLog().empty());

		OO_CHECK(source->descriptionComponents() == std::optional<std::string>("sound=(null), loop=NO, repeatCount=1, not playing"));
	}
}


OO_TEST(attributes)
{
	{
		oo::AutoreleaseScope scope;	// was @autoreleasepool
		OOSound *sound = MakeSound("beep");
		const oo::Ref<OOSoundSource> source = OOSoundSource::sourceWithSound(sound);
		OO_CHECK(source->sound() == sound);
		OO_CHECK(dynamic_cast<OOSoundSource *>(source.get()) != nullptr);

		source->setLoop(YES);
		OO_CHECK(source->loop());
		source->setRepeatCount(3);
		OO_CHECK(source->repeatCount() == 3);
		source->setRepeatCount(0);
		OO_CHECK(source->repeatCount() == 1);	// 0 reads as 1

		source->setPosition(make_vector(1, 2, 3));
		OO_CHECK(source->positional() && vector_equal(source->position(), make_vector(1, 2, 3)));
		source->setPositional(NO);
		OO_CHECK(!source->positional() && vector_equal(source->position(), kZeroVector));
		source->setPositional(YES);
		OO_CHECK(source->positional());
		source->setPosition(kZeroVector);
		OO_CHECK(source->positional());	// a zero position does not clear it

		source->setGain(0.5f);
		OO_CHECK(source->gain() == 0.5f);

		// The advanced attributes are ignored.
		source->setVelocity(make_vector(1, 1, 1));
		source->setOrientation(make_vector(1, 1, 1));
		source->setConeAngle(1.0f);
		source->setGainInsideCone(1.0f, 0.5f);
		source->positionRelativeTo(nullptr);

		OOSound *other = MakeSound("boop");
		source->setSound(other);
		OO_CHECK(source->sound() == other);
		OO_CHECK(source->descriptionComponents() == std::optional<std::string>("sound=" + other->description() + ", loop=YES, repeatCount=1, not playing"));
	}
}


// Playing takes a channel and hands it the source's attributes; the source keeps itself alive.
OO_TEST(playsThroughAChannel)
{
	TakeLog();
	OOSoundSource *weak = nullptr;
	{
		oo::AutoreleaseScope scope;	// was @autoreleasepool
		oo::Ref<OOSoundSource> source = oo::makeRef<OOSoundSource>(MakeSound("beep"));
		source->setPosition(make_vector(4, 5, 6));
		source->setGain(0.25f);
		source->setLoop(YES);
		source->play();
		OO_CHECK(source->isPlaying() && gChannelsOut == 1);
		OO_CHECK((TakeLog() == std::vector<std::string>{ "play beep looped" }));

		OOSoundChannel *channel = ChannelOf(source.get());
		OO_CHECK(channel != nullptr && OOSoundChannelTestAccess::Delegate(channel) == source.get());
		OO_CHECK(vector_equal(gChannels[channel].position, make_vector(4, 5, 6)) && gChannels[channel].gain == 0.25f);
		OO_CHECK(source->descriptionComponents().value_or("").find("playing on channel <OOSoundChannel 0x") != std::string::npos);

		// Changes reach the playing channel.
		source->setGain(0.75f);
		source->setPosition(make_vector(7, 8, 9));
		OO_CHECK(gChannels[channel].gain == 0.75f && vector_equal(gChannels[channel].position, make_vector(7, 8, 9)));

		weak = source.get();
		source = nullptr;	// [source release]: playing, still alive
	}
	OO_CHECK(weak->isPlaying());

	// The channel ends the sound: the source pushes the channel back and lets itself go.
	{
		oo::AutoreleaseScope scope;	// was @autoreleasepool
		OOSoundChannelTestAccess::Finish(ChannelOf(weak));
	}
	OO_CHECK((TakeLog() == std::vector<std::string>{ "push" }));
	OO_CHECK(gChannelsOut == 0);
}


// A repeat count plays the sound again (unlooped) until it is spent.
OO_TEST(repeats)
{
	TakeLog();
	{
		oo::AutoreleaseScope scope;	// was @autoreleasepool
		const oo::Ref<OOSoundSource> source = oo::makeRef<OOSoundSource>();
		source->playSound(MakeSound("beep"), 3);
		OO_CHECK(source->repeatCount() == 3);
		OOSoundChannel *channel = ChannelOf(source.get());
		OOSoundChannelTestAccess::Finish(channel);
		OOSoundChannelTestAccess::Finish(channel);
		OO_CHECK(source->isPlaying());
		OOSoundChannelTestAccess::Finish(channel);
		OO_CHECK(!source->isPlaying());
		OO_CHECK((TakeLog() == std::vector<std::string>{ "play beep", "play beep", "play beep", "push" }));

		// -playOrRepeat adds one to a playing source's count.
		source->setRepeatCount(1);
		source->play();
		source->playOrRepeat();
		channel = ChannelOf(source.get());
		OOSoundChannelTestAccess::Finish(channel);
		OO_CHECK(source->isPlaying());
		OOSoundChannelTestAccess::Finish(channel);
		OO_CHECK(!source->isPlaying());
		OO_CHECK((TakeLog() == std::vector<std::string>{ "play beep", "play beep", "push" }));
	}
}


// -stop hands the channel to the class, which pushes it back; playing again stops first.
OO_TEST(stops)
{
	TakeLog();
	{
		oo::AutoreleaseScope scope;	// was @autoreleasepool
		OOSound *beep = MakeSound("beep");
		const oo::Ref<OOSoundSource> source = OOSoundSource::sourceWithSound(beep);
		source->play();
		source->play();
		OO_CHECK((TakeLog() == std::vector<std::string>{ "play beep", "stop", "push", "play beep" }));
		source->stop();
		OO_CHECK(!source->isPlaying() && gChannelsOut == 0);
		OO_CHECK((TakeLog() == std::vector<std::string>{ "stop", "push" }));
		source->stop();	// not playing: nothing
		OO_CHECK(TakeLog().empty());

		// -playOrRepeatSound: plays a new sound, repeats the same one.
		source->playOrRepeatSound(beep);
		OO_CHECK(source->isPlaying());
		source->playOrRepeatSound(beep);
		OO_CHECK((TakeLog() == std::vector<std::string>{ "play beep" }));
		OOSound *boop = MakeSound("boop");
		source->playOrRepeatSound(boop);
		OO_CHECK(source->sound() == boop);
		OO_CHECK((TakeLog() == std::vector<std::string>{ "stop", "push", "play boop" }));

		// Changing the sound stops the playing one.
		source->setSound(beep);
		OO_CHECK(!source->isPlaying());
		OO_CHECK((TakeLog() == std::vector<std::string>{ "stop", "push" }));

		// -playOOSound: plays with the source's own repeat count.
		source->setRepeatCount(2);
		source->playOOSound(boop);
		OO_CHECK(source->sound() == boop && source->repeatCount() == 2);
		source->stop();
		TakeLog();
	}
}


// +stopAll stops every playing source; with no channel to be had, a source does not play.
OO_TEST(stopAllAndNoChannel)
{
	TakeLog();
	{
		oo::AutoreleaseScope scope;	// was @autoreleasepool
		const oo::Ref<OOSoundSource> a = OOSoundSource::sourceWithSound(MakeSound("a"));
		const oo::Ref<OOSoundSource> b = OOSoundSource::sourceWithSound(MakeSound("b"));
		a->play();
		b->play();
		OO_CHECK(gChannelsOut == 2);
		OOSoundSource::stopAll();
		OO_CHECK(!a->isPlaying() && !b->isPlaying() && gChannelsOut == 0);
		OO_CHECK((TakeLog() == std::vector<std::string>{ "play a", "play b", "stop", "push", "stop", "push" }));
		OOSoundSource::stopAll();	// none playing
		OO_CHECK(TakeLog().empty());

		gChannelsAvailable = 0;
		a->play();
		OO_CHECK(!a->isPlaying() && TakeLog().empty());
		gChannelsAvailable = 8;

		// It was still recorded as playing (as before); +stopAll lets every source go.
		OOSoundSource::stopAll();
		OO_CHECK(TakeLog().empty());
	}
	OO_CHECK(gLiveSounds == 0);
}


// The C++ API, and a playing C++ source: it is the channel's delegate, and it keeps itself alive.
OO_TEST(cxxApi)
{
	TakeLog();
	OOSoundSource *weak = nullptr;
	{
		oo::AutoreleaseScope scope;	// was @autoreleasepool
		const oo::Ref<OOSoundSource> source = OOSoundSource::sourceWithSound(MakeSound("beep"));
		OO_CHECK(source->sound() != nullptr && source->repeatCount() == 1 && source->gain() == OO_DEFAULT_SOUNDSOURCE_GAIN);
		OO_CHECK(source->descriptionComponents() == std::optional<std::string>("sound=" + source->sound()->description() + ", loop=NO, repeatCount=1, not playing"));
		source->setGain(0.5f);
		source->play();
		OO_CHECK(source->isPlaying());
		OOSoundChannel *channel = OOSoundSourceTestAccess::Channel(source.get());
		OO_CHECK(OOSoundChannelTestAccess::Delegate(channel) == source.get() && gChannels[channel].gain == 0.5f);
		weak = source.get();
	}
	// The Ref and the pool are gone; the playing source keeps itself.
	OO_CHECK(weak->isPlaying());
	{
		oo::AutoreleaseScope scope;	// was @autoreleasepool
		OOSoundChannelTestAccess::Finish(OOSoundSourceTestAccess::Channel(weak));
	}
	OO_CHECK((TakeLog() == std::vector<std::string>{ "play beep", "push" }));
	{
		oo::AutoreleaseScope scope;	// was @autoreleasepool
		OOSoundSource::stopAll();	// lets it go
	}
}


OO_TEST_MAIN()
