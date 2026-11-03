/*	test_OOALBufferedSound.mm
	Unit tests for OOALBufferedSound (src/Core/OOALBufferedSound.h): bead oo-2wpb, a sound of the
	Audio module (proposed ADR-0056, amendment oo-2en), a subclass of the converted root OOSound.

	A buffered sound decodes the whole of its decoder's sound when it is made, and each
	-soundBuffer is a new OpenAL buffer holding all of it. OpenAL runs on OpenAL Soft's null
	backend (ALSOFT_DRIVERS=null) and the user's defaults are a scratch folder's (HOMEPATH), as in
	test_OOSound.mm. The decoder is the game's own, on the game's Resources/Sounds/boop.ogg; the
	streamed sound and the mixer, which OOALSound.mm also names, are this file's stubs (amendment
	oo-z1s4 item 4). These expectations were written against the Objective-C API and ran on the
	unconverted class first; they ran through the facade, which was its forwarding test, until bead
	oo-9ht.83 deleted the facade: they now ask the C++ class (alloc/init as initWithDecoder(), the
	class checks as dynamic_cast, the description through the root's facade) with every expectation
	kept (standing approval oo-9n5p9). After them come the C++ API (OOALBufferedSound, a subclass of
	cxx::OOSound) and the crossing that replaced the facade's contract: a buffered sound's facade
	is the root's. Run: bash tools/check-core-tests.sh test_OOALBufferedSound
*/

#import "OOALBufferedSound.h"
#import "OOALStreamedSound.h"
#import "OOALSoundDecoder.h"
#import "OOALSoundMixer.h"
#import "OODescription.h"

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


// OOALSound.mm makes a streamed sound for more than 1 MB of decoded data; never here. A C++
// stand-in since bead oo-9ht.84 deleted the Objective-C facade this file stubbed.
oo::Ref<OOALStreamedSound> OOALStreamedSound::initWithDecoder(::OOALSoundDecoder *inDecoder)	{ (void)inDecoder; return nullptr; }
OOALStreamedSound::~OOALStreamedSound()  {}
std::optional<std::string> OOALStreamedSound::name()  { return _name; }
void OOALStreamedSound::rewind()  {}
bool OOALStreamedSound::soundIncomplete()  { return false; }
ALuint OOALStreamedSound::soundBuffer()  { return 0; }


namespace {

stdfs::path sRoot;


const std::string &BoopPath()
{
	static const std::string path = stdfs::absolute(stdfs::path(__FILE__).parent_path() / ".." / ".." / ".." / "Resources" / "Sounds" / "boop.ogg").lexically_normal().generic_string();
	return path;
}


// The null OpenAL backend and a scratch home, before anything asks for either.
void SetUp()
{
	if (!sRoot.empty())  return;
	(void)BoopPath();
	OO_CHECK(::_putenv_s("ALSOFT_DRIVERS", "null") == 0);
	sRoot = stdfs::temp_directory_path() / ("oo-test-bufferedsound-" + std::to_string(static_cast<unsigned long>(::_getpid())));
	stdfs::remove_all(sRoot);
	stdfs::create_directories(sRoot);
	OO_CHECK(::_putenv_s("HOMEPATH", sRoot.string().c_str()) == 0);
	stdfs::current_path(sRoot);
	OO_CHECK([OOSound setUp]);
}


ALint BufferInt(ALuint buffer, ALenum what)
{
	ALint value = -1;
	alGetBufferi(buffer, what, &value);
	return value;
}


// boop.ogg, decoded: mono, 11025 Hz, 7682 bytes.
constexpr ALint kBoopRate = 11025;
constexpr ALint kBoopBytes = 7682;

}	// namespace


OO_TEST(madeFromADecoder)
{
	SetUp();
	@autoreleasepool
	{
		OOALSoundDecoder *decoder = [OOALSoundDecoder codecWithPath:BoopPath()];
		OO_CHECK(decoder != nil);
		const oo::Ref<OOALBufferedSound> sound = OOALBufferedSound::initWithDecoder(decoder);
		OO_CHECK(sound != nullptr);
		OO_CHECK(dynamic_cast<OOALBufferedSound *>(sound.get()) != nullptr && dynamic_cast<cxx::OOSound *>(sound.get()) != nullptr);
		OO_CHECK(sound->name() == std::optional<std::string>("boop.ogg"));
		OO_CHECK(!sound->soundIncomplete());
		sound->rewind();
		OO_CHECK(!sound->soundIncomplete());
		OO_CHECK(oo::DescriptionOf(oo::ToObjC(sound.get())).starts_with("<OOALBufferedSound 0x"));

		OO_CHECK(!OOALBufferedSound::initWithDecoder(nil));
	}
}


// Each buffer is a new OpenAL buffer with the whole sound.
OO_TEST(eachBufferHoldsTheWholeSound)
{
	SetUp();
	@autoreleasepool
	{
		const oo::Ref<OOALBufferedSound> sound = OOALBufferedSound::initWithDecoder([OOALSoundDecoder codecWithPath:BoopPath()]);
		const ALuint first = sound->soundBuffer();
		OO_CHECK(first != 0 && alIsBuffer(first));
		OO_CHECK(BufferInt(first, AL_SIZE) == kBoopBytes);
		OO_CHECK(BufferInt(first, AL_FREQUENCY) == kBoopRate);
		OO_CHECK(BufferInt(first, AL_CHANNELS) == 1);
		OO_CHECK(BufferInt(first, AL_BITS) == 16);

		const ALuint second = sound->soundBuffer();
		OO_CHECK(second != 0 && second != first);
		OO_CHECK(BufferInt(second, AL_SIZE) == kBoopBytes);
		alDeleteBuffers(1, &first);
		alDeleteBuffers(1, &second);
	}
}


// The root's class cluster answers a buffered sound for a small file.
OO_TEST(theClusterAnswersOne)
{
	SetUp();
	@autoreleasepool
	{
		OOSound *sound = [[[OOSound alloc] cxx_initWithContentsOfFile:BoopPath()] autorelease];
		OO_CHECK(dynamic_cast<OOALBufferedSound *>(oo::ToCxx(sound)) != nullptr);
		OO_CHECK([sound cxx_name] == std::optional<std::string>("boop.ogg"));
		const ALuint buffer = [sound soundBuffer];
		OO_CHECK(BufferInt(buffer, AL_SIZE) == kBoopBytes);
		alDeleteBuffers(1, &buffer);
	}
}


// The C++ API: the factory answers null where the initialiser answered nil.
OO_TEST(cxxApi)
{
	SetUp();
	@autoreleasepool
	{
		OO_CHECK(!OOALBufferedSound::initWithDecoder(nil));
		const oo::Ref<OOALBufferedSound> sound = OOALBufferedSound::initWithDecoder([OOALSoundDecoder codecWithPath:BoopPath()]);
		OO_CHECK(sound && sound->name() == std::optional<std::string>("boop.ogg"));
		OO_CHECK(!sound->soundIncomplete());
		ALuint buffer = sound->soundBuffer();
		OO_CHECK(BufferInt(buffer, AL_SIZE) == kBoopBytes && BufferInt(buffer, AL_FREQUENCY) == kBoopRate);
		alDeleteBuffers(1, &buffer);
	}
}


// The crossing (bead oo-9ht.83 deleted the facade): a buffered sound's facade is the root's, an
// OOSound, one per sound, and the cluster's answer is the C++ sound's peer.
OO_TEST(bufferedSoundCrossesAsTheRootFacade)
{
	SetUp();
	@autoreleasepool
	{
		const oo::Ref<OOALBufferedSound> sound = OOALBufferedSound::initWithDecoder([OOALSoundDecoder codecWithPath:BoopPath()]);
		OOSound *facade = oo::ToObjC(sound.get());
		OO_CHECK([facade isMemberOfClass:[OOSound class]]);
		OO_CHECK(facade == oo::ToObjC(sound.get()));
		OO_CHECK(oo::ToCxx(facade) == sound.get());
		OO_CHECK([facade cxx_name] == std::optional<std::string>("boop.ogg"));
		OO_CHECK(oo::DescriptionOf(facade).starts_with("<OOALBufferedSound 0x"));

		OOSound *made = [[[OOSound alloc] cxx_initWithContentsOfFile:BoopPath()] autorelease];
		OO_CHECK([made isMemberOfClass:[OOSound class]]);
		cxx::OOSound *part = oo::ToCxx(made);
		OO_CHECK(dynamic_cast<OOALBufferedSound *>(part) != nullptr);
		OO_CHECK(oo::ToObjC(part) == made);
	}
	OO_CHECK(oo::ToObjC(static_cast<OOALBufferedSound *>(nullptr)) == nil);
}


OO_TEST_MAIN()
