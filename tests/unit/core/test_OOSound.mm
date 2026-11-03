/*	test_OOSound.mm
	Unit tests for OOSound (src/Core/OOALSound.h): bead oo-2en, the Audio module's pattern seam
	(proposed ADR-0056, amendment oo-2en).

	OOSound is the root of the sounds: OOALBufferedSound, OOALStreamedSound and OOMusic derive
	from it in their own files and convert in their own beads. The root keeps the sound system's
	global state (set up, sound OK, the master volume, which it keeps in the "volume_control"
	default) and is the class cluster that initWithContentsOfFile() turns into a buffered or a
	streamed sound by the decoded size. These expectations were written against the Objective-C API
	and run on the unconverted class first (commit cecf0a94f); they ran through the facade, which
	was its forwarding test, until bead oo-9ht.68 deleted it: they now ask the C++ class (alloc/init
	as oo::makeRef, the cluster as the factory, the class checks as dynamic_cast, "%@" as
	description()) with every expectation kept (standing approval oo-9n5p9). After them come the
	C++ API and a C++ subclass, as test_OODrawable.mm does.

	OpenAL runs on OpenAL Soft's null backend (ALSOFT_DRIVERS=null), so the machine's sound
	hardware cannot change the answers; the user's defaults are a scratch folder's (HOMEPATH), so
	the machine's own volume cannot either. The decoder, the two concrete sounds and the mixer are
	this file's stubs (proposed ADR-0056, amendment oo-z1s4 item 4): the real ones would bring
	Vorbis and the whole mixer into the link. All are C++ stand-ins since beads oo-9ht.82,
	oo-9ht.83, oo-9ht.84 and oo-9ht.87 deleted their facades (standing approval oo-9n5p9).
	Run: bash tools/check-core-tests.sh
*/

#import "OOALSound.h"
#import "OOALBufferedSound.h"
#import "OOALStreamedSound.h"
#import "OOALSoundDecoder.h"
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
	anything else is small. Counts the decoders alive, so the test sees each released. A C++
	stand-in since bead oo-9ht.82 deleted the Objective-C facade this file stubbed: the factory the
	cluster calls, a subclass answering the path, and the root's members (OOALSoundDecoder.mm is not
	linked), which its vtable names.
*/
static int gLiveDecoders = 0;

namespace {
class TestDecoder final : public OOALSoundDecoder
{
public:
	explicit TestDecoder(const std::string &path) : _path(path)  { gLiveDecoders++; }
	~TestDecoder() override  { gLiveDecoders--; }

	size_t sizeAsBuffer() override
	{
		if (_path == "big.ogg")  return (1 << 20) + 1;
		if (_path == "edge.ogg")  return 1 << 20;
		return 1000;
	}

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


// The two concrete sounds. "bad.ogg" fails to load. The buffered sound is a C++ stand-in since
// bead oo-9ht.83 deleted the Objective-C facade this file stubbed (the members the cluster and the
// root call).
oo::Ref<OOALBufferedSound> OOALBufferedSound::initWithDecoder(OOALSoundDecoder *inDecoder)
{
	if (inDecoder->name() == "bad.ogg")  return nullptr;
	oo::Ref<OOALBufferedSound> sound = oo::adopt(new OOALBufferedSound);
	sound->_name = inDecoder->name();
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

oo::Ref<OOALStreamedSound> OOALStreamedSound::initWithDecoder(OOALSoundDecoder *inDecoder)
{
	oo::Ref<OOALStreamedSound> sound = oo::adopt(new OOALStreamedSound);
	sound->_name = inDecoder->name();
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
	OOSound::rewind();
}


bool OOALStreamedSound::soundIncomplete()
{
	return true;
}


ALuint OOALStreamedSound::soundBuffer()
{
	return 7;
}


// The rewinds of a streamed sound.
static int Rewinds(OOSound *sound)
{
	const auto found = gStreamedRewinds.find(dynamic_cast<OOALStreamedSound *>(sound));
	return found != gStreamedRewinds.end() ? found->second : 0;
}


// A subclass that overrides the designated initialiser and wraps a sound, as OOMusic does (a C++
// subclass since bead oo-9ht.68 deleted the facade its Objective-C version subclassed).
class TestMusic final : public OOSound
{
public:
	static oo::Ref<TestMusic> initWithContentsOfFile(const std::optional<std::string> &inPath)
	{
		oo::Ref<TestMusic> self = oo::adopt(new TestMusic);
		self->_sound = OOSound::initWithContentsOfFile(inPath);
		if (nullptr == self->_sound)  self = nullptr;
		return self;
	}

	std::optional<std::string> name() override  { return _sound->name(); }

private:
	TestMusic() = default;

	oo::Ref<OOSound>	_sound;
};


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


// First: making a sound sets the sound system up, at half volume when the user has set none.
OO_TEST(initSetsUpAtHalfVolume)
{
	SetUp();
	OO_CHECK(!OOSound::isSoundOK());
	OO_CHECK(oo::Defaults::standard().object("volume_control").isNull());

	const oo::Ref<OOSound> sound = oo::makeRef<OOSound>();
	OO_CHECK(sound != nullptr);
	OO_CHECK(OOSound::isSoundOK());
	OO_CHECK(OOSound::setUp());	// once only, and remembered
	OO_CHECK(Near(OOSound::masterVolume(), 0.5f));
	OO_CHECK(Near(ListenerGain(), 0.5f));
	OO_CHECK(Near(VolumeDefault(), 0.5f));
}


OO_TEST(masterVolumeIsClampedAndKept)
{
	SetUp();
	OOSound::setMasterVolume(0.25f);
	OO_CHECK(Near(OOSound::masterVolume(), 0.25f));
	OO_CHECK(Near(ListenerGain(), 0.25f));
	OO_CHECK(Near(VolumeDefault(), 0.25f));

	OOSound::setMasterVolume(2.0f);
	OO_CHECK(Near(OOSound::masterVolume(), 1.0f));
	OO_CHECK(Near(VolumeDefault(), 1.0f));

	OOSound::setMasterVolume(-1.0f);
	OO_CHECK(Near(OOSound::masterVolume(), 0.0f));
	OO_CHECK(Near(ListenerGain(), 0.0f));

	// The default is written only when the volume changes.
	oo::Defaults::standard().setFloat("volume_control", 0.75f);
	OOSound::setMasterVolume(0.0f);
	OO_CHECK(Near(VolumeDefault(), 0.75f));
	OOSound::setMasterVolume(0.5f);
	OO_CHECK(Near(VolumeDefault(), 0.5f));
}


OO_TEST(updateAsksTheMixer)
{
	SetUp();
	const unsigned before = gMixerUpdates;
	OOSound::update();
	OOSound::update();
	OO_CHECK(gMixerUpdates == before + 2);
}


OO_TEST(rootDefaults)
{
	SetUp();
	const oo::Ref<OOSound> sound = oo::makeRef<OOSound>();
	const int before = gSubclassResponsibilities;
	OO_CHECK(sound->name() == std::optional<std::string>(std::string()));
	OO_CHECK(gSubclassResponsibilities == before + 1);
	OO_CHECK(sound->soundBuffer() == 0);
	OO_CHECK(gSubclassResponsibilities == before + 2);
	OO_CHECK(!sound->soundIncomplete());
	sound->rewind();
	OO_CHECK(gSubclassResponsibilities == before + 2);
}


// The class cluster: the decoded size picks the concrete sound; the decoder is released.
OO_TEST(loadingPicksBufferedOrStreamed)
{
	SetUp();
	StartLog();
	{
		const oo::Ref<OOSound> small = OOSound::initWithContentsOfFile(std::string("small.ogg"));
		OO_CHECK(dynamic_cast<OOALBufferedSound *>(small.get()) != nullptr);
		OO_CHECK(small->name() == std::optional<std::string>("small.ogg"));
		OO_CHECK(small->soundBuffer() == 42 && !small->soundIncomplete());

		const oo::Ref<OOSound> edge = OOSound::initWithContentsOfFile(std::string("edge.ogg"));
		OO_CHECK(dynamic_cast<OOALBufferedSound *>(edge.get()) != nullptr);

		const oo::Ref<OOSound> big = OOSound::initWithContentsOfFile(std::string("big.ogg"));
		OO_CHECK(dynamic_cast<OOALStreamedSound *>(big.get()) != nullptr);
		OO_CHECK(big->name() == std::optional<std::string>("big.ogg"));
		OO_CHECK(big->soundBuffer() == 7 && big->soundIncomplete());
		big->rewind();
		OO_CHECK(Rewinds(big.get()) == 1);

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
	// No decoder: null, and nothing logged.
	OO_CHECK(OOSound::initWithContentsOfFile(std::nullopt) == nullptr);
	OO_CHECK(OOSound::initWithContentsOfFile(std::string("missing.ogg")) == nullptr);
	OO_CHECK(gLog.empty());

	// The concrete sound refuses: null, logged.
	OO_CHECK(OOSound::initWithContentsOfFile(std::string("bad.ogg")) == nullptr);
	OO_CHECK(LogLinesContaining("Failed to load sound \"bad.ogg\"") == 1);
	OO_CHECK(gLiveDecoders == 0);
}


OO_TEST(subclassOverridingTheInitialiser)
{
	SetUp();
	const oo::Ref<TestMusic> music = TestMusic::initWithContentsOfFile(std::string("small.ogg"));
	OO_CHECK(dynamic_cast<TestMusic *>(static_cast<OOSound *>(music.get())) != nullptr);
	OO_CHECK(music->name() == std::optional<std::string>("small.ogg"));
	OO_CHECK(!music->soundIncomplete());
	OO_CHECK(TestMusic::initWithContentsOfFile(std::string("missing.ogg")) == nullptr);
}


// A converted sound: a C++ subclass. Global, as a game class is, so that its description names it
// as the game's would.
class TestCxxSound : public OOSound
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
	OO_CHECK(OOSound::isSoundOK() && OOSound::setUp());
	OOSound::setMasterVolume(0.125f);
	OO_CHECK(Near(OOSound::masterVolume(), 0.125f));
	const unsigned updates = gMixerUpdates;
	OOSound::update();
	OO_CHECK(gMixerUpdates == updates + 1);

	{
		// The factory answers the concrete sound.
		const oo::Ref<OOSound> small = OOSound::initWithContentsOfFile(std::string("small.ogg"));
		OO_CHECK(dynamic_cast<OOALBufferedSound *>(small.get()) != nullptr);
		OO_CHECK(small->name() == std::optional<std::string>("small.ogg"));
		const oo::Ref<OOSound> big = OOSound::initWithContentsOfFile(std::string("big.ogg"));
		OO_CHECK(dynamic_cast<OOALStreamedSound *>(big.get()) != nullptr);
		OO_CHECK(!OOSound::initWithContentsOfFile(std::nullopt));
		OO_CHECK(!OOSound::initWithContentsOfFile(std::string("bad.ogg")));
		OO_CHECK(gLiveDecoders == 0);
	}

	const oo::Ref<OOSound> root = oo::makeRef<OOSound>();
	const int before = gSubclassResponsibilities;
	OO_CHECK(root->name() == std::optional<std::string>(std::string()) && root->soundBuffer() == 0);
	OO_CHECK(gSubclassResponsibilities == before + 2);
	OO_CHECK(!root->soundIncomplete());
	root->rewind();
	OO_CHECK(!root->descriptionComponents().has_value());
}


// A C++ subclass's overrides answer, and the root's defaults; "%@" names the class.
OO_TEST(cxxSoundBehindTheFacade)
{
	SetUp();
	const oo::Ref<TestCxxSound> sound = oo::makeRef<TestCxxSound>();
	OOSound *root = sound.get();

	OO_CHECK(root->name() == std::optional<std::string>("cxx.ogg"));
	OO_CHECK(root->soundBuffer() == 99 && !root->soundIncomplete());
	root->rewind();
	OO_CHECK(sound->rewinds == 1);

	const std::string text = root->description();
	OO_CHECK(text.starts_with("<TestCxxSound 0x"));
	OO_CHECK(text.ends_with(">{test}"));
}


// Virtual calls reach the concrete sounds' overrides, and the root's where they have none.
OO_TEST(objCSoundBehindACxxPointer)
{
	SetUp();
	const oo::Ref<OOSound> part = OOSound::initWithContentsOfFile(std::string("big.ogg"));
	OO_CHECK(part != nullptr);

	// The streamed sound is C++ since oo-9ht.84; its rewind reaches the root's.
	OO_CHECK(part->name() == std::optional<std::string>("big.ogg"));
	OO_CHECK(part->soundBuffer() == 7 && part->soundIncomplete());
	part->rewind();
	OO_CHECK(Rewinds(part.get()) == 1);
	OO_CHECK(!part->descriptionComponents().has_value());

	// A subclass that overrides only some: the root answers the rest.
	const oo::Ref<TestMusic> music = TestMusic::initWithContentsOfFile(std::string("small.ogg"));
	OO_CHECK(music->name() == std::optional<std::string>("small.ogg"));
	OO_CHECK(!music->soundIncomplete());
}


OO_TEST_MAIN()
