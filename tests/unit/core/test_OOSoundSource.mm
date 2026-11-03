/*	test_OOSoundSource.mm
	Unit tests for OOSoundSource (src/Core/OOSoundSource.h): bead oo-zoj3, a class of the Audio
	module (proposed ADR-0056, amendment oo-2en).

	A sound source plays one sound at a time through a channel it pops from the shared mixer, as
	the channel's delegate: it gives the channel its position and gain, keeps itself alive while
	it plays, plays the sound again until its repeat count is spent, and then pushes the channel
	back. +stopAll stops every source that is playing. The mixer and its channels are this file's
	stubs, which record what they are told (the real ones would make OpenAL sources); the sound is
	an opaque object to a source, so it is a stub too, with only a name (amendment oo-z1s4 item 4).
	The playing channel is private, so the test reads it as a friend (amendment oo-zffj item 3;
	through the runtime before the conversion). These expectations were written against the
	Objective-C API and ran on the unconverted class first; they now run through the facade, which
	is its forwarding test. After them come the C++ API (cxx::OOSoundSource) and the facade's
	contract. Run: bash tools/check-core-tests.sh test_OOSoundSource
*/

#import "OOSoundSource.h"
#import "OODescription.h"

#include "oo_test.hpp"

#include <string>
#include <vector>


@interface OOSound: OOObject
{
@public
	std::string		_name;
}
@end


static int gLiveSounds = 0;

@implementation OOSound

- (id) init
{
	self = [super init];
	if (self != nil)  gLiveSounds++;
	return self;
}


- (void) dealloc
{
	gLiveSounds--;
	[super dealloc];
}


- (std::optional<std::string>) cxx_descriptionComponents
{
	return _name;
}

@end


@interface OOObject (TestChannelDelegate)
- (void)channel:(id)inChannel didFinishPlayingSound:(OOSound *)inSound;
@end


// A channel records what it is told, in order; -finish ends its sound as the real one does when
// OpenAL stops, and -stop as its -stop does: both tell the delegate.
static std::vector<std::string> gLog;

@interface OOSoundChannel: OOObject
{
@public
	id			_delegate;
	OOSound		*_sound;
	Vector		_position;
	float		_gain;
	BOOL		_loop;
}

- (void) finish;

@end


@implementation OOSoundChannel

- (void) setDelegate:(id)delegate
{
	_delegate = delegate;
}


- (void) setPosition:(Vector)position
{
	_position = position;
}


- (void) setGain:(float)gain
{
	_gain = gain;
}


- (BOOL) playSound:(OOSound *)sound looped:(BOOL)loop
{
	gLog.push_back("play " + sound->_name + (loop ? " looped" : ""));
	_loop = loop;
	_sound = [sound retain];
	return YES;
}


- (void) finish
{
	OOSound *sound = _sound;
	_sound = nil;
	[_delegate channel:self didFinishPlayingSound:sound];
	[sound release];
}


- (void) stop
{
	gLog.push_back("stop");
	[self finish];
}

@end


static int gChannelsOut = 0;
static int gChannelsAvailable = 8;

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


- (OOSoundChannel *) popChannel
{
	if (gChannelsOut == gChannelsAvailable)  return nil;
	gChannelsOut++;
	return [[OOSoundChannel alloc] init];	// leaked: a few per run
}


- (void) pushChannel:(OOSoundChannel *)channel
{
	(void)channel;
	gChannelsOut--;
	gLog.push_back("push");
}

@end


namespace {

OOSound *MakeSound(const char *name)
{
	OOSound *sound = [[[OOSound alloc] init] autorelease];
	sound->_name = name;
	return sound;
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
	static OOSoundChannel *Channel(cxx::OOSoundSource *source)  { return source->_channel; }
};


namespace {

// The channel a playing source has (its private _channel).
OOSoundChannel *ChannelOf(OOSoundSource *source)
{
	return OOSoundSourceTestAccess::Channel(oo::ToCxx(source));
}

}	// namespace


OO_TEST(defaults)
{
	@autoreleasepool
	{
		OOSoundSource *source = [[[OOSoundSource alloc] init] autorelease];
		OO_CHECK([source sound] == nil);
		OO_CHECK(![source loop] && [source repeatCount] == 1 && ![source isPlaying]);
		OO_CHECK(![source positional] && vector_equal([source position], kZeroVector));
		OO_CHECK([source gain] == OO_DEFAULT_SOUNDSOURCE_GAIN);

		[source play];	// no sound: nothing
		OO_CHECK(![source isPlaying] && TakeLog().empty());

		OO_CHECK(oo::DescriptionOf(source).ends_with("{sound=(null), loop=NO, repeatCount=1, not playing}"));
	}
}


OO_TEST(attributes)
{
	@autoreleasepool
	{
		OOSound *sound = MakeSound("beep");
		OOSoundSource *source = [OOSoundSource sourceWithSound:sound];
		OO_CHECK([source sound] == sound);
		OO_CHECK([source isKindOfClass:[OOSoundSource class]]);

		[source setLoop:YES];
		OO_CHECK([source loop]);
		[source setRepeatCount:3];
		OO_CHECK([source repeatCount] == 3);
		[source setRepeatCount:0];
		OO_CHECK([source repeatCount] == 1);	// 0 reads as 1

		[source setPosition:make_vector(1, 2, 3)];
		OO_CHECK([source positional] && vector_equal([source position], make_vector(1, 2, 3)));
		[source setPositional:NO];
		OO_CHECK(![source positional] && vector_equal([source position], kZeroVector));
		[source setPositional:YES];
		OO_CHECK([source positional]);
		[source setPosition:kZeroVector];
		OO_CHECK([source positional]);	// a zero position does not clear it

		[source setGain:0.5f];
		OO_CHECK([source gain] == 0.5f);

		// The advanced attributes are ignored.
		[source setVelocity:make_vector(1, 1, 1)];
		[source setOrientation:make_vector(1, 1, 1)];
		[source setConeAngle:1.0f];
		[source setGainInsideCone:1.0f outsideCone:0.5f];
		[source positionRelativeTo:nullptr];

		OOSound *other = MakeSound("boop");
		[source setSound:other];
		OO_CHECK([source sound] == other);
		OO_CHECK(oo::DescriptionOf(source).ends_with("{sound=" + oo::DescriptionOf(other) + ", loop=YES, repeatCount=1, not playing}"));
	}
}


// Playing takes a channel and hands it the source's attributes; the source keeps itself alive.
OO_TEST(playsThroughAChannel)
{
	TakeLog();
	OOSoundSource *weak = nil;
	@autoreleasepool
	{
		OOSoundSource *source = [[OOSoundSource alloc] initWithSound:MakeSound("beep")];
		[source setPosition:make_vector(4, 5, 6)];
		[source setGain:0.25f];
		[source setLoop:YES];
		[source play];
		OO_CHECK([source isPlaying] && gChannelsOut == 1);
		OO_CHECK((TakeLog() == std::vector<std::string>{ "play beep looped" }));

		OOSoundChannel *channel = ChannelOf(source);
		OO_CHECK(channel != nil && channel->_delegate == source);
		OO_CHECK(vector_equal(channel->_position, make_vector(4, 5, 6)) && channel->_gain == 0.25f);
		OO_CHECK(oo::DescriptionOf(source).find("playing on channel <OOSoundChannel 0x") != std::string::npos);

		// Changes reach the playing channel.
		[source setGain:0.75f];
		[source setPosition:make_vector(7, 8, 9)];
		OO_CHECK(channel->_gain == 0.75f && vector_equal(channel->_position, make_vector(7, 8, 9)));

		weak = source;
		[source release];	// playing: still alive
	}
	OO_CHECK([weak isPlaying]);

	// The channel ends the sound: the source pushes the channel back and lets itself go.
	@autoreleasepool
	{
		[ChannelOf(weak) finish];
	}
	OO_CHECK((TakeLog() == std::vector<std::string>{ "push" }));
	OO_CHECK(gChannelsOut == 0);
}


// A repeat count plays the sound again (unlooped) until it is spent.
OO_TEST(repeats)
{
	TakeLog();
	@autoreleasepool
	{
		OOSoundSource *source = [[[OOSoundSource alloc] init] autorelease];
		[source playSound:MakeSound("beep") repeatCount:3];
		OO_CHECK([source repeatCount] == 3);
		OOSoundChannel *channel = ChannelOf(source);
		[channel finish];
		[channel finish];
		OO_CHECK([source isPlaying]);
		[channel finish];
		OO_CHECK(![source isPlaying]);
		OO_CHECK((TakeLog() == std::vector<std::string>{ "play beep", "play beep", "play beep", "push" }));

		// -playOrRepeat adds one to a playing source's count.
		[source setRepeatCount:1];
		[source play];
		[source playOrRepeat];
		channel = ChannelOf(source);
		[channel finish];
		OO_CHECK([source isPlaying]);
		[channel finish];
		OO_CHECK(![source isPlaying]);
		OO_CHECK((TakeLog() == std::vector<std::string>{ "play beep", "play beep", "push" }));
	}
}


// -stop hands the channel to the class, which pushes it back; playing again stops first.
OO_TEST(stops)
{
	TakeLog();
	@autoreleasepool
	{
		OOSound *beep = MakeSound("beep");
		OOSoundSource *source = [OOSoundSource sourceWithSound:beep];
		[source play];
		[source play];
		OO_CHECK((TakeLog() == std::vector<std::string>{ "play beep", "stop", "push", "play beep" }));
		[source stop];
		OO_CHECK(![source isPlaying] && gChannelsOut == 0);
		OO_CHECK((TakeLog() == std::vector<std::string>{ "stop", "push" }));
		[source stop];	// not playing: nothing
		OO_CHECK(TakeLog().empty());

		// -playOrRepeatSound: plays a new sound, repeats the same one.
		[source playOrRepeatSound:beep];
		OO_CHECK([source isPlaying]);
		[source playOrRepeatSound:beep];
		OO_CHECK((TakeLog() == std::vector<std::string>{ "play beep" }));
		OOSound *boop = MakeSound("boop");
		[source playOrRepeatSound:boop];
		OO_CHECK([source sound] == boop);
		OO_CHECK((TakeLog() == std::vector<std::string>{ "stop", "push", "play boop" }));

		// Changing the sound stops the playing one.
		[source setSound:beep];
		OO_CHECK(![source isPlaying]);
		OO_CHECK((TakeLog() == std::vector<std::string>{ "stop", "push" }));

		// -playOOSound: plays with the source's own repeat count.
		[source setRepeatCount:2];
		[source playOOSound:boop];
		OO_CHECK([source sound] == boop && [source repeatCount] == 2);
		[source stop];
		TakeLog();
	}
}


// +stopAll stops every playing source; with no channel to be had, a source does not play.
OO_TEST(stopAllAndNoChannel)
{
	TakeLog();
	@autoreleasepool
	{
		OOSoundSource *a = [OOSoundSource sourceWithSound:MakeSound("a")];
		OOSoundSource *b = [OOSoundSource sourceWithSound:MakeSound("b")];
		[a play];
		[b play];
		OO_CHECK(gChannelsOut == 2);
		[OOSoundSource stopAll];
		OO_CHECK(![a isPlaying] && ![b isPlaying] && gChannelsOut == 0);
		OO_CHECK((TakeLog() == std::vector<std::string>{ "play a", "play b", "stop", "push", "stop", "push" }));
		[OOSoundSource stopAll];	// none playing
		OO_CHECK(TakeLog().empty());

		gChannelsAvailable = 0;
		[a play];
		OO_CHECK(![a isPlaying] && TakeLog().empty());
		gChannelsAvailable = 8;

		// It was still recorded as playing (as before); +stopAll lets every source go.
		[OOSoundSource stopAll];
		OO_CHECK(TakeLog().empty());
	}
	OO_CHECK(gLiveSounds == 0);
}


// The C++ API, and a playing C++ source: its facade is the channel's delegate and keeps it alive.
OO_TEST(cxxApi)
{
	TakeLog();
	cxx::OOSoundSource *weak = nullptr;
	@autoreleasepool
	{
		const oo::Ref<cxx::OOSoundSource> source = cxx::OOSoundSource::sourceWithSound(MakeSound("beep"));
		OO_CHECK(source->sound() != nil && source->repeatCount() == 1 && source->gain() == OO_DEFAULT_SOUNDSOURCE_GAIN);
		OO_CHECK(source->descriptionComponents() == std::optional<std::string>("sound=" + oo::DescriptionOf(source->sound()) + ", loop=NO, repeatCount=1, not playing"));
		source->setGain(0.5f);
		source->play();
		OO_CHECK(source->isPlaying());
		OOSoundChannel *channel = OOSoundSourceTestAccess::Channel(source.get());
		OO_CHECK(channel->_delegate == oo::ToObjC(source.get()) && channel->_gain == 0.5f);
		weak = source.get();
	}
	// The Ref and the pool are gone; the playing source keeps itself.
	OO_CHECK(weak->isPlaying());
	@autoreleasepool
	{
		[OOSoundSourceTestAccess::Channel(weak) finish];
	}
	OO_CHECK((TakeLog() == std::vector<std::string>{ "play beep", "push" }));
	@autoreleasepool
	{
		cxx::OOSoundSource::stopAll();	// lets it go
	}
}


// The facade's contract: one live facade per source; alloc/init makes the source's peer.
OO_TEST(facade)
{
	@autoreleasepool
	{
		OOSoundSource *made = [[[OOSoundSource alloc] initWithSound:MakeSound("beep")] autorelease];
		OO_CHECK(oo::ToObjC(oo::ToCxx(made)) == made);
		const oo::Ref<cxx::OOSoundSource> source = oo::makeRef<cxx::OOSoundSource>();
		OOSoundSource *facade = oo::ToObjC(source.get());
		OO_CHECK(facade == oo::ToObjC(source) && oo::ToCxx(facade) == source.get());
		OO_CHECK(oo::DescriptionOf(facade).starts_with("<OOSoundSource 0x"));
	}
	OOSoundSource *none = nil;
	OO_CHECK(oo::ToCxx(none) == nullptr);
	OO_CHECK(oo::ToObjC(static_cast<cxx::OOSoundSource *>(nullptr)) == nil);
	OO_CHECK(gLiveSounds == 0);
}


OO_TEST_MAIN()
