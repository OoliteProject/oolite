/*	test_OOSound.mm
	Unit tests for cxx::OOSound (src/Core/OOALSound.h) and its Objective-C facade
	(OOALSound+ObjCBridge.h): bead oo-2en, the Audio module's pattern seam (proposed ADR-0056,
	amendment oo-2en).

	OOSound is the root of the sounds: OOALBufferedSound, OOALStreamedSound and OOMusic derive
	from it in their own files and convert in their own beads. The root keeps the sound system's
	global state (set up, sound OK, the master volume, which it keeps in the "volume_control"
	default) and is the class cluster that -cxx_initWithContentsOfFile: turns into a buffered or a
	streamed sound by the decoded size. These expectations were written against the Objective-C API
	and run on the unconverted class first (commit cecf0a94f); they now run through the facade,
	which is its forwarding test. After them come the C++ API and the hierarchy's crossing both
	ways, as test_OODrawable.mm does.

	OpenAL runs on OpenAL Soft's null backend (ALSOFT_DRIVERS=null), so the machine's sound
	hardware cannot change the answers; the user's defaults are a scratch folder's (HOMEPATH), so
	the machine's own volume cannot either. The decoder, the two concrete sounds and the mixer are
	this file's stubs (proposed ADR-0056, amendment oo-z1s4 item 4): the real ones would bring
	Vorbis and the whole mixer into the link. The concrete sounds are C++ stand-ins since beads
	oo-9ht.83 and oo-9ht.84 deleted their facades, and their class checks ask the C++ sound
	(standing approval oo-9n5p9).
	Run: bash tools/check-core-tests.sh
*/

#import "OOALSound.h"
#import "OOALBufferedSound.h"
#import "OOALStreamedSound.h"
#import "OOALSoundMixer.h"
#import "OOLogging.h"

#include "oofnd/Defaults.hpp"
#include "oofnd/Log.hpp"
#include "oo_test.hpp"

#include <cmath>
#include <cstdlib>
#include <filesystem>
#include <map>
#include <process.h>
#include <string>
#include <string_view>
#include <vector>

namespace stdfs = std::filesystem;


/*	The game's OOLogging.mm reaches the resource manager, so it is not linked. The one function of
	it that the root calls is defined here instead, and counts.
*/
static int gSubclassResponsibilities = 0;

void OOLogGenericSubclassResponsibilityForFunction(const char *inFunction)
{
	(void)inFunction;
	gSubclassResponsibilities++;
}


static unsigned gMixerUpdates = 0;

// The mixer (a C++ stand-in since bead oo-9ht.87 deleted the Objective-C facade this file stubbed):
// one, never released, counting the updates the root sends it.
OOSoundMixer *OOSoundMixer::sharedMixer()
{
	static OOSoundMixer *mixer = oo::makeRef<OOSoundMixer>().leakRef();
	return mixer;
}


void OOSoundMixer::update()
{
	gMixerUpdates++;
}


void OOSoundMixer::shutdown()
{
}


/*	The decoder: a path names its decoded size. "missing.ogg" (and no path) has no decoder,
	"big.ogg" is one byte over the 1 MB a buffered sound may hold, "edge.ogg" exactly that, and
	anything else is small. Counts the decoders alive, so the test sees each released.
*/
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
	if (_path.has_value())  gLiveDecoders--;	// a refused decoder was never counted
	[super dealloc];
}


- (size_t)sizeAsBuffer
{
	if (_path == "big.ogg")  return (1 << 20) + 1;
	if (_path == "edge.ogg")  return 1 << 20;
	return 1000;
}


- (std::optional<std::string>)cxx_name
{
	return _path;
}

@end


// The two concrete sounds. "bad.ogg" fails to load. The buffered sound is a C++ stand-in since
// bead oo-9ht.83 deleted the Objective-C facade this file stubbed (the members the cluster and the
// root's facade call); the streamed sound is an Objective-C subclass of the root, as the real one's
// facade is.
oo::Ref<OOALBufferedSound> OOALBufferedSound::initWithDecoder(::OOALSoundDecoder *inDecoder)
{
	if ([inDecoder cxx_name] == "bad.ogg")  return nullptr;
	oo::Ref<OOALBufferedSound> sound = oo::adopt(new OOALBufferedSound);
	sound->_name = [inDecoder cxx_name];
	return sound;
}


OOALBufferedSound::~OOALBufferedSound()
{
}


std::optional<std::string> OOALBufferedSound::name()
{
	return _name;
}


ALuint OOALBufferedSound::soundBuffer()
{
	return 42;
}


// The streamed sound: a C++ stand-in since bead oo-9ht.84 deleted the Objective-C facade this file
// stubbed. Its rewinds are counted per sound (its _rewinds ivar was), and a rewind reaches the root's.
static std::map<const OOALStreamedSound *, int> gStreamedRewinds;

oo::Ref<OOALStreamedSound> OOALStreamedSound::initWithDecoder(::OOALSoundDecoder *inDecoder)
{
	oo::Ref<OOALStreamedSound> sound = oo::adopt(new OOALStreamedSound);
	sound->_name = [inDecoder cxx_name];
	return sound;
}


OOALStreamedSound::~OOALStreamedSound()
{
	gStreamedRewinds.erase(this);
}


std::optional<std::string> OOALStreamedSound::name()
{
	return _name;
}


void OOALStreamedSound::rewind()
{
	gStreamedRewinds[this]++;
	cxx::OOSound::rewind();
}


bool OOALStreamedSound::soundIncomplete()
{
	return true;
}


ALuint OOALStreamedSound::soundBuffer()
{
	return 7;
}


// The rewinds of the streamed sound behind a facade.
static int Rewinds(OOSound *sound)
{
	const auto found = gStreamedRewinds.find(dynamic_cast<OOALStreamedSound *>(oo::ToCxx(sound)));
	return found != gStreamedRewinds.end() ? found->second : 0;
}


// A subclass that overrides the designated initialiser and wraps a sound, as OOMusic does.
@interface TestMusic: OOSound
{
	OOSound		*_sound;
}
@end


@implementation TestMusic

- (id)cxx_initWithContentsOfFile:(const std::optional<std::string> &)inPath
{
	self = [super init];
	if (nil != self)
	{
		_sound = [[OOSound alloc] cxx_initWithContentsOfFile:inPath];
		if (nil == _sound)
		{
			[self release];
			self = nil;
		}
	}
	return self;
}


- (void)dealloc
{
	[_sound release];
	[super dealloc];
}


- (std::optional<std::string>)cxx_name
{
	return [_sound cxx_name];
}

@end


namespace {

stdfs::path sRoot;


// The null OpenAL backend and a scratch home, before anything asks for either.
void SetUp()
{
	if (!sRoot.empty())  return;
	OO_CHECK(::_putenv_s("ALSOFT_DRIVERS", "null") == 0);
	sRoot = stdfs::temp_directory_path() / ("oo-test-sound-" + std::to_string(static_cast<unsigned long>(::_getpid())));
	stdfs::remove_all(sRoot);
	stdfs::create_directories(sRoot);
	OO_CHECK(::_putenv_s("HOMEPATH", sRoot.string().c_str()) == 0);
	stdfs::current_path(sRoot);
}


bool Near(float a, float b)
{
	return std::fabs(a - b) < 1e-6f;
}


float ListenerGain()
{
	ALfloat gain = -1.0f;
	alGetListenerf(AL_GAIN, &gain);
	return gain;
}


float VolumeDefault()
{
	return oo::Defaults::standard().floatForKey("volume_control");
}


// The log, as the sound writes it.
std::vector<std::string> gLog;


void Capture(std::string_view line)
{
	gLog.emplace_back(line);
}


void StartLog()
{
	oo::log::logger().setInitialized(true);
	oo::log::logger().setSink(&Capture);
	gLog.clear();
}


int LogLinesContaining(std::string_view text)
{
	int count = 0;
	for (const std::string &line : gLog)
	{
		if (line.find(text) != std::string::npos)  count++;
	}
	return count;
}

}	// namespace


// First: -init sets the sound system up, at half volume when the user has set none.
OO_TEST(initSetsUpAtHalfVolume)
{
	SetUp();
	@autoreleasepool
	{
		OO_CHECK(![OOSound isSoundOK]);
		OO_CHECK(oo::Defaults::standard().object("volume_control").isNull());

		OOSound *sound = [[[OOSound alloc] init] autorelease];
		OO_CHECK(sound != nil);
		OO_CHECK([OOSound isSoundOK]);
		OO_CHECK([OOSound setUp]);	// once only, and remembered
		OO_CHECK(Near([OOSound masterVolume], 0.5f));
		OO_CHECK(Near(ListenerGain(), 0.5f));
		OO_CHECK(Near(VolumeDefault(), 0.5f));
	}
}


OO_TEST(masterVolumeIsClampedAndKept)
{
	SetUp();
	[OOSound setMasterVolume:0.25f];
	OO_CHECK(Near([OOSound masterVolume], 0.25f));
	OO_CHECK(Near(ListenerGain(), 0.25f));
	OO_CHECK(Near(VolumeDefault(), 0.25f));

	[OOSound setMasterVolume:2.0f];
	OO_CHECK(Near([OOSound masterVolume], 1.0f));
	OO_CHECK(Near(VolumeDefault(), 1.0f));

	[OOSound setMasterVolume:-1.0f];
	OO_CHECK(Near([OOSound masterVolume], 0.0f));
	OO_CHECK(Near(ListenerGain(), 0.0f));

	// The default is written only when the volume changes.
	oo::Defaults::standard().setFloat("volume_control", 0.75f);
	[OOSound setMasterVolume:0.0f];
	OO_CHECK(Near(VolumeDefault(), 0.75f));
	[OOSound setMasterVolume:0.5f];
	OO_CHECK(Near(VolumeDefault(), 0.5f));
}


OO_TEST(updateAsksTheMixer)
{
	SetUp();
	const unsigned before = gMixerUpdates;
	[OOSound update];
	[OOSound update];
	OO_CHECK(gMixerUpdates == before + 2);
}


OO_TEST(rootDefaults)
{
	SetUp();
	@autoreleasepool
	{
		OOSound *sound = [[[OOSound alloc] init] autorelease];
		const int before = gSubclassResponsibilities;
		OO_CHECK([sound cxx_name] == std::optional<std::string>(std::string()));
		OO_CHECK(gSubclassResponsibilities == before + 1);
		OO_CHECK([sound soundBuffer] == 0);
		OO_CHECK(gSubclassResponsibilities == before + 2);
		OO_CHECK(![sound soundIncomplete]);
		[sound rewind];
		OO_CHECK(gSubclassResponsibilities == before + 2);
	}
}


// The class cluster: the decoded size picks the concrete sound; the decoder is released.
OO_TEST(loadingPicksBufferedOrStreamed)
{
	SetUp();
	StartLog();
	@autoreleasepool
	{
		OOSound *small = [[[OOSound alloc] cxx_initWithContentsOfFile:std::string("small.ogg")] autorelease];
		OO_CHECK(dynamic_cast<OOALBufferedSound *>(oo::ToCxx(small)) != nullptr);
		OO_CHECK([small cxx_name] == std::optional<std::string>("small.ogg"));
		OO_CHECK([small soundBuffer] == 42 && ![small soundIncomplete]);

		OOSound *edge = [[[OOSound alloc] cxx_initWithContentsOfFile:std::string("edge.ogg")] autorelease];
		OO_CHECK(dynamic_cast<OOALBufferedSound *>(oo::ToCxx(edge)) != nullptr);

		OOSound *big = [[[OOSound alloc] cxx_initWithContentsOfFile:std::string("big.ogg")] autorelease];
		OO_CHECK(dynamic_cast<OOALStreamedSound *>(oo::ToCxx(big)) != nullptr);
		OO_CHECK([big cxx_name] == std::optional<std::string>("big.ogg"));
		OO_CHECK([big soundBuffer] == 7 && [big soundIncomplete]);
		[big rewind];
		OO_CHECK(Rewinds(big) == 1);

		OO_CHECK(gLiveDecoders == 0);
	}
#ifndef NDEBUG
	OO_CHECK(LogLinesContaining("Loaded sound small.ogg") == 1);
	OO_CHECK(LogLinesContaining("Loaded sound big.ogg") == 1);
#endif
	OO_CHECK(LogLinesContaining("Failed to load sound") == 0);
}


OO_TEST(loadingFailures)
{
	SetUp();
	StartLog();
	@autoreleasepool
	{
		// No decoder: nil, and nothing logged.
		OO_CHECK([[OOSound alloc] cxx_initWithContentsOfFile:std::nullopt] == nil);
		OO_CHECK([[OOSound alloc] cxx_initWithContentsOfFile:std::string("missing.ogg")] == nil);
		OO_CHECK(gLog.empty());

		// The concrete sound refuses: nil, logged.
		OO_CHECK([[OOSound alloc] cxx_initWithContentsOfFile:std::string("bad.ogg")] == nil);
		OO_CHECK(LogLinesContaining("Failed to load sound \"bad.ogg\"") == 1);
		OO_CHECK(gLiveDecoders == 0);
	}
}


OO_TEST(subclassOverridingTheInitialiser)
{
	SetUp();
	@autoreleasepool
	{
		OOSound *music = [[[TestMusic alloc] cxx_initWithContentsOfFile:std::string("small.ogg")] autorelease];
		OO_CHECK([music isKindOfClass:[TestMusic class]]);
		OO_CHECK([music cxx_name] == std::optional<std::string>("small.ogg"));
		OO_CHECK(![music soundIncomplete]);
		OO_CHECK([[TestMusic alloc] cxx_initWithContentsOfFile:std::string("missing.ogg")] == nil);
	}
}


// A converted sound: a C++ subclass. Global, as a game class is, so that its description names it
// as the game's would.
class TestCxxSound : public cxx::OOSound
{
public:
	std::optional<std::string> name() override						{ return "cxx.ogg"; }
	ALuint soundBuffer() override									{ return 99; }
	void rewind() override											{ rewinds++; }
	std::optional<std::string> descriptionComponents() const override	{ return "test"; }

	int rewinds = 0;
};


OO_TEST(cxxApi)
{
	SetUp();
	OO_CHECK(cxx::OOSound::isSoundOK() && cxx::OOSound::setUp());
	cxx::OOSound::setMasterVolume(0.125f);
	OO_CHECK(Near(cxx::OOSound::masterVolume(), 0.125f) && Near([OOSound masterVolume], 0.125f));
	const unsigned updates = gMixerUpdates;
	cxx::OOSound::update();
	OO_CHECK(gMixerUpdates == updates + 1);

	@autoreleasepool
	{
		// The factory answers the concrete Objective-C sound, retained.
		const oo::ObjCRef<OOSound *> small = cxx::OOSound::initWithContentsOfFile(std::string("small.ogg"));
		OO_CHECK(dynamic_cast<OOALBufferedSound *>(oo::ToCxx(small.get())) != nullptr);
		OO_CHECK(oo::ToCxx(small.get())->name() == std::optional<std::string>("small.ogg"));
		const oo::ObjCRef<OOSound *> big = cxx::OOSound::initWithContentsOfFile(std::string("big.ogg"));
		OO_CHECK(dynamic_cast<OOALStreamedSound *>(oo::ToCxx(big.get())) != nullptr);
		OO_CHECK(!cxx::OOSound::initWithContentsOfFile(std::nullopt));
		OO_CHECK(!cxx::OOSound::initWithContentsOfFile(std::string("bad.ogg")));
		OO_CHECK(gLiveDecoders == 0);
	}

	const oo::Ref<cxx::OOSound> root = oo::makeRef<cxx::OOSound>();
	const int before = gSubclassResponsibilities;
	OO_CHECK(root->name() == std::optional<std::string>(std::string()) && root->soundBuffer() == 0);
	OO_CHECK(gSubclassResponsibilities == before + 2);
	OO_CHECK(!root->soundIncomplete());
	root->rewind();
	OO_CHECK(!root->descriptionComponents().has_value());
}


OO_TEST(cxxSoundBehindTheFacade)
{
	SetUp();
	@autoreleasepool
	{
		const oo::Ref<TestCxxSound> sound = oo::makeRef<TestCxxSound>();
		OOSound *facade = oo::ToObjC(sound.get());
		OO_CHECK(facade != nil && facade == oo::ToObjC(sound.get()));	// one live facade
		OO_CHECK(oo::ToCxx(facade) == sound.get());

		// The sound sources' messages reach the C++ overrides, and the root's defaults.
		OO_CHECK([facade cxx_name] == std::optional<std::string>("cxx.ogg"));
		OO_CHECK([facade soundBuffer] == 99 && ![facade soundIncomplete]);
		[facade rewind];
		OO_CHECK(sound->rewinds == 1);

		const std::string text = oo::DescriptionOf(facade);
		OO_CHECK(text.starts_with("<TestCxxSound 0x"));
		OO_CHECK(text.ends_with(">{test}"));
	}
}


OO_TEST(objCSoundBehindACxxPointer)
{
	SetUp();
	@autoreleasepool
	{
		OOSound *objCSound = [[[OOSound alloc] cxx_initWithContentsOfFile:std::string("big.ogg")] autorelease];
		cxx::OOSound *part = oo::ToCxx(objCSound);
		OO_CHECK(part != nullptr && oo::ToObjC(part) == objCSound);	// the object itself

		// Virtual calls from C++ reach the overrides (the streamed sound is C++ since oo-9ht.84),
		// and its rewind the root's.
		OO_CHECK(part->name() == std::optional<std::string>("big.ogg"));
		OO_CHECK(part->soundBuffer() == 7 && part->soundIncomplete());
		part->rewind();
		OO_CHECK(Rewinds(objCSound) == 1);
		OO_CHECK(!part->descriptionComponents().has_value());

		// A subclass that overrides only some: the root answers the rest.
		OOSound *music = [[[TestMusic alloc] cxx_initWithContentsOfFile:std::string("small.ogg")] autorelease];
		OO_CHECK(oo::ToCxx(music)->name() == std::optional<std::string>("small.ogg"));
		OO_CHECK(!oo::ToCxx(music)->soundIncomplete());
	}
}


OO_TEST(nilAndLifetime)
{
	SetUp();
	OOSound *none = nil;
	OO_CHECK(oo::ToCxx(none) == nullptr);
	OO_CHECK(oo::ToObjC(static_cast<cxx::OOSound *>(nullptr)) == nil);
	OO_CHECK([none soundBuffer] == 0 && ![none soundIncomplete]);

	// An Objective-C sound's C++ part outlives it, and then answers as nil did. (The streamed sound
	// was one until bead oo-9ht.84 made it C++; the subclass that overrides the initialiser is one.)
	oo::Ref<cxx::OOSound> part;
	@autoreleasepool
	{
		OOSound *objCSound = [[[TestMusic alloc] cxx_initWithContentsOfFile:std::string("big.ogg")] autorelease];
		part = oo::Ref<cxx::OOSound>(oo::ToCxx(objCSound));
	}
	OO_CHECK(!part->name().has_value() && part->soundBuffer() == 0 && !part->soundIncomplete());
	OO_CHECK(oo::ToObjC(part) == nil);
}


OO_TEST_MAIN()
