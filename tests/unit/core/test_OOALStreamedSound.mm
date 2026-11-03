/*	test_OOALStreamedSound.mm
	Unit tests for OOALStreamedSound (src/Core/OOALStreamedSound.h): bead oo-03g7, a sound of the
	Audio module (proposed ADR-0056, amendment oo-2en), a subclass of the converted root OOSound.

	A streamed sound keeps its decoder and decodes OOAL_STREAM_CHUNK_SIZE bytes into each
	-soundBuffer, a new OpenAL buffer, until a chunk comes back short; -rewind starts the decoder
	again. OpenAL runs on OpenAL Soft's null backend (ALSOFT_DRIVERS=null) and the user's
	defaults are a scratch folder's (HOMEPATH), as in test_OOSound.mm. The decoder is the game's
	own, on the game's Resources: boop.ogg fits in one chunk, OoliteTheme.ogg (the music) needs
	many and is the one the root's class cluster streams. The buffered sound and the mixer, which
	OOALSound.mm also names, are this file's stubs (amendment oo-z1s4 item 4). These expectations
	were written against the Objective-C API and ran on the unconverted class first; they ran
	through the facade, which was its forwarding test, until bead oo-9ht.84 deleted the facade: they
	now ask the C++ class (alloc/init as initWithDecoder(), the class checks as dynamic_cast) with
	every expectation kept (standing approval oo-9n5p9); since beads oo-9ht.68 and oo-9ht.82 deleted
	the root's and the decoder's facades the description is the root's description(), the buffer
	helper calls the C++ sound and the decoder and the cluster are C++. After them comes the C++ API
	(OOALStreamedSound, a subclass of OOSound).
	Run: bash tools/check-core-tests.sh test_OOALStreamedSound
*/

#import "OOALStreamedSound.h"
#import "OOALBufferedSound.h"
#import "OOALSoundDecoder.h"
#import "OOALSoundMixer.h"

#include "oo_test.hpp"

#include <cstdlib>
#include <filesystem>
#include <process.h>
#include <string>

namespace stdfs = std::filesystem;


// Link stubs for OOLogging.mm, which reaches the resource manager.
const char *const cxx_kOOLogFileNotFound = "files.notFound";

void OOLogGenericSubclassResponsibilityForFunction(const char *inFunction)
{
	(void)inFunction;
}


// The mixer, as the root's update() and the OpenAL controller's shutdown() reach it: there is
// none (a C++ stand-in since bead oo-9ht.87 deleted the Objective-C facade this file stubbed).
OOSoundMixer *OOSoundMixer::sharedMixer()  { return nullptr; }
void OOSoundMixer::update()  {}
void OOSoundMixer::shutdown()  {}


// OOALSound.mm makes a buffered sound for up to 1 MB of decoded data; never here. A C++ stand-in
// since bead oo-9ht.83 deleted the Objective-C facade this file stubbed.
oo::Ref<OOALBufferedSound> OOALBufferedSound::initWithDecoder(OOALSoundDecoder *inDecoder)	{ (void)inDecoder; return nullptr; }
OOALBufferedSound::~OOALBufferedSound()  {}
std::optional<std::string> OOALBufferedSound::name()  { return _name; }
ALuint OOALBufferedSound::soundBuffer()  { return 0; }


namespace {

stdfs::path sRoot;


std::string ResourcePath(const char *folder, const char *file)
{
	return stdfs::absolute(stdfs::path(__FILE__).parent_path() / ".." / ".." / ".." / "Resources" / folder / file).lexically_normal().generic_string();
}


const std::string &BoopPath()
{
	static const std::string path = ResourcePath("Sounds", "boop.ogg");
	return path;
}


const std::string &ThemePath()
{
	static const std::string path = ResourcePath("Music", "OoliteTheme.ogg");
	return path;
}


// The null OpenAL backend and a scratch home, before anything asks for either.
void SetUp()
{
	if (!sRoot.empty())  return;
	(void)BoopPath();
	(void)ThemePath();
	OO_CHECK(::_putenv_s("ALSOFT_DRIVERS", "null") == 0);
	sRoot = stdfs::temp_directory_path() / ("oo-test-streamedsound-" + std::to_string(static_cast<unsigned long>(::_getpid())));
	stdfs::remove_all(sRoot);
	stdfs::create_directories(sRoot);
	OO_CHECK(::_putenv_s("HOMEPATH", sRoot.string().c_str()) == 0);
	stdfs::current_path(sRoot);
	OO_CHECK(OOSound::setUp());
}


ALint BufferInt(ALuint buffer, ALenum what)
{
	ALint value = -1;
	alGetBufferi(buffer, what, &value);
	return value;
}


// The next buffer's size; the buffer is deleted.
ALint NextBufferSize(OOSound *sound)
{
	ALuint buffer = sound->soundBuffer();
	const ALint size = BufferInt(buffer, AL_SIZE);
	alDeleteBuffers(1, &buffer);
	return size;
}


// boop.ogg, decoded: mono, 11025 Hz, 7682 bytes.
constexpr ALint kBoopRate = 11025;
constexpr ALint kBoopBytes = 7682;

}	// namespace


OO_TEST(madeFromADecoder)
{
	SetUp();
	{
		const oo::Ref<OOALSoundDecoder> decoder = OOALSoundDecoder::codecWithPath(BoopPath());
		OO_CHECK(decoder != nullptr);
		const oo::Ref<OOALStreamedSound> sound = OOALStreamedSound::initWithDecoder(decoder.get());
		OO_CHECK(sound != nullptr);
		OO_CHECK(dynamic_cast<OOALStreamedSound *>(sound.get()) != nullptr && dynamic_cast<OOSound *>(sound.get()) != nullptr);
		OO_CHECK(sound->name() == std::optional<std::string>("boop.ogg"));
		OO_CHECK(sound->soundIncomplete());	// nothing streamed yet
		OO_CHECK(sound->description().starts_with("<OOALStreamedSound 0x"));

		OO_CHECK(!OOALStreamedSound::initWithDecoder(nullptr));
	}
}


// A sound shorter than a chunk: one short buffer, then complete; a rewind starts it again.
OO_TEST(aShortSoundIsOneChunk)
{
	SetUp();
	{
		const oo::Ref<OOALStreamedSound> sound = OOALStreamedSound::initWithDecoder(OOALSoundDecoder::codecWithPath(BoopPath()).get());
		ALuint buffer = sound->soundBuffer();
		OO_CHECK(buffer != 0 && alIsBuffer(buffer));
		OO_CHECK(BufferInt(buffer, AL_SIZE) == kBoopBytes);
		OO_CHECK(BufferInt(buffer, AL_FREQUENCY) == kBoopRate);
		OO_CHECK(BufferInt(buffer, AL_CHANNELS) == 1);
		alDeleteBuffers(1, &buffer);
		OO_CHECK(!sound->soundIncomplete());

		OO_CHECK(NextBufferSize(sound.get()) == 0);	// past the end: an empty buffer

		sound->rewind();
		OO_CHECK(sound->soundIncomplete());
		OO_CHECK(NextBufferSize(sound.get()) == kBoopBytes);
		OO_CHECK(!sound->soundIncomplete());
	}
}


// The music is streamed by the root's class cluster, a chunk at a time, in stereo.
OO_TEST(theClusterStreamsTheMusic)
{
	SetUp();
	{
		const oo::Ref<OOSound> sound = OOSound::initWithContentsOfFile(ThemePath());
		OO_CHECK(dynamic_cast<OOALStreamedSound *>(sound.get()) != nullptr);
		OO_CHECK(sound->name() == std::optional<std::string>("OoliteTheme.ogg"));

		ALuint buffer = sound->soundBuffer();
		OO_CHECK(BufferInt(buffer, AL_SIZE) == static_cast<ALint>(OOAL_STREAM_CHUNK_SIZE));
		OO_CHECK(BufferInt(buffer, AL_CHANNELS) == 2);
		alDeleteBuffers(1, &buffer);
		OO_CHECK(sound->soundIncomplete());
		OO_CHECK(NextBufferSize(sound.get()) == static_cast<ALint>(OOAL_STREAM_CHUNK_SIZE));

		sound->rewind();
		OO_CHECK(sound->soundIncomplete());
		OO_CHECK(NextBufferSize(sound.get()) == static_cast<ALint>(OOAL_STREAM_CHUNK_SIZE));
	}
}


// The C++ API: the factory answers null where the initialiser answered nil.
OO_TEST(cxxApi)
{
	SetUp();
	{
		OO_CHECK(!OOALStreamedSound::initWithDecoder(nullptr));
		const oo::Ref<OOALStreamedSound> sound = OOALStreamedSound::initWithDecoder(OOALSoundDecoder::codecWithPath(BoopPath()).get());
		OO_CHECK(sound && sound->name() == std::optional<std::string>("boop.ogg"));
		OO_CHECK(sound->soundIncomplete());
		ALuint buffer = sound->soundBuffer();
		OO_CHECK(BufferInt(buffer, AL_SIZE) == kBoopBytes && BufferInt(buffer, AL_FREQUENCY) == kBoopRate);
		alDeleteBuffers(1, &buffer);
		OO_CHECK(!sound->soundIncomplete());
		sound->rewind();
		OO_CHECK(sound->soundIncomplete());
	}
}


OO_TEST_MAIN()
