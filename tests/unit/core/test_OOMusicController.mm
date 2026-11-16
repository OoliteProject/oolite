/*	test_OOMusicController.mm
	Unit tests for OOMusicController (src/Core/OOMusicController.h): bead oo-lfkq, a class of the
	Audio module (proposed ADR-0056, amendment oo-2en), and a singleton (amendment oo-r7m0).

	The controller plays one music at a time, loaded by name from the resource manager: the theme,
	the docking and docked music and the mission music, each remembered as "special" so that a
	change of mode can start it again. Its mode (off, on, or iTunes on the Mac) is the "music mode"
	default, read when it is made and written when it changes. The user's defaults are a scratch
	folder's (HOMEPATH). The resource manager and the music are this file's stubs, which record
	what they are asked (the real ones would bring the sound system into the link; amendment oo-z1s4
	item 4): "missing.ogg" has no music. These expectations were written against the Objective-C API
	and ran on the unconverted class first; they now run through the facade, which is its forwarding
	test. After them come the C++ API (cxx::OOMusicController) and the facade's contract.
	Run: bash tools/check-core-tests.sh test_OOMusicController
*/

#import "OOMusicController.h"

#include "oofnd/Defaults.hpp"
#include "oo_test.hpp"

#include <cstdlib>
#include <filesystem>
#include <process.h>
#include <string>
#include <vector>

namespace stdfs = std::filesystem;


// What the musics are told, in order.
static std::vector<std::string> gLog;
static int gLiveMusics = 0;

@interface OOMusic: OOObject
{
@public
	std::string		_name;
	BOOL			_playing;
	float			_gain;
}
@end


@implementation OOMusic

- (id) init
{
	self = [super init];
	if (self != nil)  gLiveMusics++;
	return self;
}


- (void) dealloc
{
	gLiveMusics--;
	[super dealloc];
}


- (std::optional<std::string>) cxx_name
{
	return _name;
}


- (void) setMusicGain:(float)gain
{
	_gain = gain;
}


- (void) playLooped:(BOOL)loop
{
	gLog.push_back("play " + _name + (loop ? " looped" : ""));
	_playing = YES;
}


- (void) stop
{
	gLog.push_back("stop " + _name);
	_playing = NO;
}


- (BOOL) isPlaying
{
	return _playing;
}


- (OOSoundSource *) musicSoundSource
{
	return reinterpret_cast<OOSoundSource *>(self);	// an object the controller hands on unopened
}

@end


// The resource manager: each name is a new music (as a cache miss is), from the "Music" folder.
@interface ResourceManager: OOObject
@end


@implementation ResourceManager

+ (OOMusic *) cxx_ooMusicNamed:(const std::string &)fileName inFolder:(const std::optional<std::string> &)folderName
{
	if (fileName == "missing.ogg" || folderName != std::optional<std::string>("Music"))  return nil;
	OOMusic *music = [[[OOMusic alloc] init] autorelease];
	music->_name = fileName;
	return music;
}

@end


namespace {

stdfs::path sRoot;


void SetUp()
{
	if (!sRoot.empty())  return;
	sRoot = stdfs::temp_directory_path() / ("oo-test-musiccontroller-" + std::to_string(static_cast<unsigned long>(::_getpid())));
	stdfs::remove_all(sRoot);
	stdfs::create_directories(sRoot);
	OO_CHECK(::_putenv_s("HOMEPATH", sRoot.string().c_str()) == 0);
	stdfs::current_path(sRoot);
}


std::vector<std::string> TakeLog()
{
	std::vector<std::string> result;
	result.swap(gLog);
	return result;
}


std::optional<std::string> ModeDefault()
{
	return oo::Defaults::standard().stringForKey("music mode");
}


OOMusic *Current(OOMusicController *controller)
{
	return reinterpret_cast<OOMusic *>([controller soundSource]);
}

}	// namespace


// First: the shared controller reads its mode from the defaults when it is made.
OO_TEST(theSharedControllerReadsItsMode)
{
	SetUp();
	oo::Defaults::standard().setObject("music mode", oo::PList(std::string("off")));
	OOMusicController *controller = [OOMusicController sharedController];
	OO_CHECK(controller != nil && [OOMusicController sharedController] == controller);
	OO_CHECK([controller mode] == kOOMusicOff);
	OO_CHECK(![controller isPlaying] && ![controller playingMusic].has_value() && [controller soundSource] == nil);

	// Off: nothing plays.
	[controller playThemeMusic];
	[controller playMusicNamed:"x.ogg" loop:NO];
	OO_CHECK(TakeLog().empty() && ![controller isPlaying]);
}


// The theme asked for while off is remembered: turning music on plays it.
OO_TEST(modeChangesAreKept)
{
	SetUp();
	OOMusicController *controller = [OOMusicController sharedController];
	@autoreleasepool
	{
		[controller setMode:kOOMusicOn];
		OO_CHECK([controller mode] == kOOMusicOn && ModeDefault() == std::optional<std::string>("on"));
		OO_CHECK((TakeLog() == std::vector<std::string>{ "play OoliteTheme.ogg looped" }));
		[controller setMode:kOOMusicITunes];	// not on this platform: refused
		OO_CHECK([controller mode] == kOOMusicOn && ModeDefault() == std::optional<std::string>("on"));
		[controller setMode:kOOMusicOff];
		OO_CHECK([controller mode] == kOOMusicOff && ModeDefault() == std::optional<std::string>("off"));
		OO_CHECK((TakeLog() == std::vector<std::string>{ "stop OoliteTheme.ogg" }));
		[controller setMode:kOOMusicOn];	// the stop forgot the theme: nothing plays
		OO_CHECK(TakeLog().empty() && ![controller isPlaying]);
	}
	OO_CHECK(gLiveMusics == 0);
}


OO_TEST(playsMusicByName)
{
	SetUp();
	OOMusicController *controller = [OOMusicController sharedController];
	@autoreleasepool
	{
		[controller playMusicNamed:"a.ogg" loop:YES gain:2.0f];
		OO_CHECK((TakeLog() == std::vector<std::string>{ "play a.ogg looped" }));
		OO_CHECK([controller isPlaying] && [controller playingMusic] == std::optional<std::string>("a.ogg"));
		OO_CHECK(Current(controller)->_gain == 1.0f);	// clamped

		[controller playMusicNamed:"a.ogg" loop:NO];	// already playing it: nothing
		OO_CHECK(TakeLog().empty());

		[controller playMusicNamed:"missing.ogg" loop:NO];	// none: the current one goes on
		OO_CHECK(TakeLog().empty() && [controller playingMusic] == std::optional<std::string>("a.ogg"));

		[controller playMusicNamed:"b.ogg" loop:NO];
		OO_CHECK((TakeLog() == std::vector<std::string>{ "stop a.ogg", "play b.ogg" }));
		OO_CHECK(Current(controller)->_gain == OO_DEFAULT_SOUNDSOURCE_GAIN);

		[controller stopMusicNamed:"a.ogg"];	// not the one playing
		OO_CHECK(TakeLog().empty());
		[controller stopMusicNamed:"b.ogg"];
		OO_CHECK((TakeLog() == std::vector<std::string>{ "stop b.ogg" }));
		OO_CHECK(![controller isPlaying] && [controller soundSource] == nil);
	}
	OO_CHECK(gLiveMusics == 0);
}


OO_TEST(specialMusic)
{
	SetUp();
	OOMusicController *controller = [OOMusicController sharedController];
	@autoreleasepool
	{
		[controller playThemeMusic];
		OO_CHECK((TakeLog() == std::vector<std::string>{ "play OoliteTheme.ogg looped" }));
		[controller stopDockingMusic];	// not docking music: nothing
		[controller stopMissionMusic];
		OO_CHECK(TakeLog().empty());
		[controller stopThemeMusic];	// the theme gives way to the docked music
		OO_CHECK((TakeLog() == std::vector<std::string>{ "stop OoliteTheme.ogg", "play OoliteDocked.ogg" }));

		[controller playDockingMusic];
		OO_CHECK((TakeLog() == std::vector<std::string>{ "stop OoliteDocked.ogg", "play BlueDanube.ogg looped" }));
		[controller toggleDockingMusic];	// playing the docking music: stops it
		OO_CHECK((TakeLog() == std::vector<std::string>{ "stop BlueDanube.ogg" }));
		[controller toggleDockingMusic];	// nothing playing: starts it
		OO_CHECK((TakeLog() == std::vector<std::string>{ "play BlueDanube.ogg looped" }));
		[controller stopDockingMusic];
		OO_CHECK((TakeLog() == std::vector<std::string>{ "stop BlueDanube.ogg" }));

		// The mission music: the theme until it is set; none when it is cleared.
		[controller playMissionMusic];
		OO_CHECK((TakeLog() == std::vector<std::string>{ "play OoliteTheme.ogg" }));
		[controller cxx_setMissionMusic:std::string("mission.ogg")];
		[controller playMissionMusic];
		OO_CHECK((TakeLog() == std::vector<std::string>{ "stop OoliteTheme.ogg", "play mission.ogg" }));
		[controller stopMissionMusic];
		OO_CHECK((TakeLog() == std::vector<std::string>{ "stop mission.ogg" }));
		[controller cxx_setMissionMusic:std::nullopt];
		[controller playMissionMusic];
		OO_CHECK(TakeLog().empty());

		// A change of mode stops the music, and on again starts the special one.
		[controller playDockedMusic];
		TakeLog();
		[controller setMode:kOOMusicOff];
		OO_CHECK((TakeLog() == std::vector<std::string>{ "stop OoliteDocked.ogg" }));
		[controller toggleDockingMusic];	// only when on
		OO_CHECK(TakeLog().empty());
		[controller playDockedMusic];	// off: remembered, not played
		OO_CHECK(TakeLog().empty());
		[controller setMode:kOOMusicOn];
		OO_CHECK((TakeLog() == std::vector<std::string>{ "play OoliteDocked.ogg" }));

		[controller justStop];
		OO_CHECK((TakeLog() == std::vector<std::string>{ "stop OoliteDocked.ogg" }));
		[controller setMode:kOOMusicOff];
		[controller setMode:kOOMusicOn];	// nothing special any more: just stops
		[controller stop];
		OO_CHECK(TakeLog().empty());
	}
	OO_CHECK(gLiveMusics == 0);
}


// The C++ API: the one controller, the same state as the facade's.
OO_TEST(cxxApi)
{
	SetUp();
	cxx::OOMusicController *controller = cxx::OOMusicController::sharedController();
	OO_CHECK(controller != nullptr && controller == cxx::OOMusicController::sharedController());
	OO_CHECK(oo::ToCxx([OOMusicController sharedController]) == controller);
	@autoreleasepool
	{
		OO_CHECK(controller->mode() == kOOMusicOn);
		controller->setMissionMusic(std::string("c.ogg"));
		controller->playMissionMusic();
		OO_CHECK((TakeLog() == std::vector<std::string>{ "play c.ogg" }));
		OO_CHECK(controller->isPlaying() && controller->playingMusic() == std::optional<std::string>("c.ogg"));
		OO_CHECK([[OOMusicController sharedController] isPlaying]);
		controller->playMusicNamed("d.ogg", true, 0.5f);
		OO_CHECK((TakeLog() == std::vector<std::string>{ "stop c.ogg", "play d.ogg looped" }));
		OO_CHECK(Current([OOMusicController sharedController])->_gain == 0.5f);
		controller->stop();
		OO_CHECK((TakeLog() == std::vector<std::string>{ "stop d.ogg" }) && !controller->isPlaying());
	}
	OO_CHECK(gLiveMusics == 0);
}


// The facade's contract: one facade for the life of the process.
OO_TEST(facade)
{
	SetUp();
	OOMusicController *facade = nil;
	@autoreleasepool
	{
		facade = [OOMusicController sharedController];
	}
	OO_CHECK(facade == [OOMusicController sharedController]);
	OO_CHECK(oo::ToObjC(cxx::OOMusicController::sharedController()) == facade);
	OOMusicController *none = nil;
	OO_CHECK(oo::ToCxx(none) == nullptr);
	OO_CHECK(oo::ToObjC(static_cast<cxx::OOMusicController *>(nullptr)) == nil);
}


OO_TEST_MAIN()
