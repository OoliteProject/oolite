/*	test_OOALSoundDecoder.mm
	Unit tests for OOALSoundDecoder (src/Core/OOALSoundDecoder.h): bead oo-y0gz, a Phase 3 class
	conversion (proposed ADR-0056, the Audio module's pattern: amendment oo-2en).

	The decoder is a class cluster: -cxx_initWithPath: and +codecWithPath: answer the private
	Vorbis codec for a path ending in "ogg" (a file, or a file inside an OXZ) and nil otherwise; the
	public class's own answers are a decoder of nothing. The codec reads the whole sound into a
	buffer, or streams it in chunks of OOAL_STREAM_CHUNK_SIZE and starts again on -reset. The
	sound decoded here is the game's own Resources/Sounds/boop.ogg, found from this file's path,
	so the answers are the file's: Vorbis decodes the same samples on every machine.
	These expectations were written against the Objective-C API and ran on the unconverted class
	first; since bead oo-9ht.82 deleted the facade they ask the C++ class (standing approval
	oo-9n5p9). After them comes the C++ API's own case.
	Run: bash tools/check-core-tests.sh test_OOALSoundDecoder
*/

#import "OOALSoundDecoder.h"
#import "OOLogging.h"

#include "oofnd/Log.hpp"
#include "oo_test.hpp"

#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <string>
#include <string_view>
#include <vector>

namespace stdfs = std::filesystem;


// The game's OOLogging.mm reaches the resource manager, so it is not linked; the decoder's one
// message class from it is defined here.
const char *const cxx_kOOLogFileNotFound = "files.notFound";


namespace {

// Resources/Sounds/boop.ogg, from this file's path (tests/unit/core/), made absolute before
// anything changes the current directory.
const std::string &BoopPath()
{
	static const std::string path = stdfs::absolute(stdfs::path(__FILE__).parent_path() / ".." / ".." / ".." / "Resources" / "Sounds" / "boop.ogg").lexically_normal().generic_string();
	return path;
}


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


// boop.ogg, as Vorbis decodes it: mono, 11025 Hz, 3841 frames of 16 bits.
constexpr long kBoopRate = 11025;
constexpr size_t kBoopBytes = 3841 * 2;

}	// namespace


OO_TEST(clusterPicksTheCodecByExtension)
{
	StartLog();
	OO_CHECK(stdfs::exists(BoopPath()));

	const oo::Ref<OOALSoundDecoder> decoder = OOALSoundDecoder::initWithPath(BoopPath());
	OO_CHECK(decoder != nullptr);
	OO_CHECK(dynamic_cast<OOALSoundDecoder *>(decoder.get()) != nullptr);
	OO_CHECK(decoder->name() == std::optional<std::string>("boop.ogg"));

	OO_CHECK(OOALSoundDecoder::initWithPath(std::nullopt) == nullptr);
	OO_CHECK(OOALSoundDecoder::initWithPath(std::string("boop.wav")) == nullptr);
	OO_CHECK(OOALSoundDecoder::initWithPath(std::string("no-such-file.ogg")) == nullptr);
	OO_CHECK(gLog.empty());

	OO_CHECK(OOALSoundDecoder::codecWithPath(BoopPath()) != nullptr);
	OO_CHECK(OOALSoundDecoder::codecWithPath(BoopPath())->name() == std::optional<std::string>("boop.ogg"));
	OO_CHECK(OOALSoundDecoder::codecWithPath("boop.wav") == nullptr);
	OO_CHECK(OOALSoundDecoder::codecWithPath("no-such-file.ogg") == nullptr);

	// A path through an OXZ that is not there: null, logged.
	OO_CHECK(OOALSoundDecoder::initWithPath(std::string("no-such.oxz/Sounds/x.ogg")) == nullptr);
	OO_CHECK(LogLinesContaining("Could not unzip OXZ at no-such.oxz") == 1);
}


OO_TEST(theSoundsProperties)
{
	const oo::Ref<OOALSoundDecoder> decoder = OOALSoundDecoder::codecWithPath(BoopPath());
	OO_CHECK(!decoder->isStereo());
	OO_CHECK(decoder->sampleRate() == kBoopRate);
	OO_CHECK(decoder->sizeAsBuffer() == kBoopBytes);

	// What the description printed between its braces (the facade's "<OOALSoundVorbisCodec 0x..."
	// went with it).
	OO_CHECK(decoder->descriptionComponents().value_or("").starts_with("\"boop.ogg\", comments="));
}


OO_TEST(readsTheWholeSound)
{
	const oo::Ref<OOALSoundDecoder> decoder = OOALSoundDecoder::codecWithPath(BoopPath());
	char *buffer = nullptr;
	size_t size = 0;
	OO_CHECK(decoder->readCreatingBuffer(&buffer, &size));
	OO_CHECK(buffer != nullptr && size == kBoopBytes);
	bool silent = true;
	for (size_t i = 0; i < size; i++)  silent = silent && buffer[i] == 0;
	OO_CHECK(!silent);
	std::free(buffer);

	// No out-parameters: refused.
	OO_CHECK(!decoder->readCreatingBuffer(NULL, &size) && size == 0);
}


OO_TEST(streamsAndStartsAgain)
{
	const oo::Ref<OOALSoundDecoder> whole = OOALSoundDecoder::codecWithPath(BoopPath());
	char *expected = nullptr;
	size_t size = 0;
	OO_CHECK(whole->readCreatingBuffer(&expected, &size));

	const oo::Ref<OOALSoundDecoder> decoder = OOALSoundDecoder::codecWithPath(BoopPath());
	std::vector<char> chunk(OOAL_STREAM_CHUNK_SIZE);
	OO_CHECK(decoder->streamToBuffer(chunk.data()) == kBoopBytes);
	OO_CHECK(expected != nullptr && std::memcmp(chunk.data(), expected, kBoopBytes) == 0);
	OO_CHECK(decoder->streamToBuffer(chunk.data()) == 0);	// the end

	decoder->reset();
	std::fill(chunk.begin(), chunk.end(), 0);
	OO_CHECK(decoder->streamToBuffer(chunk.data()) == kBoopBytes);
	OO_CHECK(std::memcmp(chunk.data(), expected, kBoopBytes) == 0);
	std::free(expected);
}


// The public class's own answers: a decoder of nothing.
OO_TEST(theRootDecodesNothing)
{
	const oo::Ref<OOALSoundDecoder> none = oo::makeRef<OOALSoundDecoder>();
	OO_CHECK(none != nullptr);
	char *buffer = reinterpret_cast<char *>(1);
	size_t size = 1;
	OO_CHECK(!none->readCreatingBuffer(&buffer, &size));
	OO_CHECK(buffer == nullptr && size == 0);
	char chunk[4] = {};
	OO_CHECK(none->streamToBuffer(chunk) == 0);
	OO_CHECK(none->sizeAsBuffer() == 0 && !none->isStereo() && none->sampleRate() == 0);
	none->reset();
	OO_CHECK(none->name() == std::optional<std::string>(std::string()));
}


// The C++ API: the same answers, null where the facade answered nil.
OO_TEST(cxxApi)
{
	OO_CHECK(!OOALSoundDecoder::initWithPath(std::nullopt));
	OO_CHECK(!OOALSoundDecoder::initWithPath(std::string("boop.wav")));
	OO_CHECK(!OOALSoundDecoder::codecWithPath("no-such-file.ogg"));

	const oo::Ref<OOALSoundDecoder> decoder = OOALSoundDecoder::initWithPath(BoopPath());
	OO_CHECK(decoder && decoder->name() == std::optional<std::string>("boop.ogg"));
	OO_CHECK(!decoder->isStereo() && decoder->sampleRate() == kBoopRate && decoder->sizeAsBuffer() == kBoopBytes);
	OO_CHECK(decoder->descriptionComponents().value_or("").starts_with("\"boop.ogg\", comments="));

	char *buffer = nullptr;
	size_t size = 0;
	OO_CHECK(decoder->readCreatingBuffer(&buffer, &size) && size == kBoopBytes);
	std::free(buffer);

	const oo::Ref<OOALSoundDecoder> streaming = OOALSoundDecoder::codecWithPath(BoopPath());
	std::vector<char> chunk(OOAL_STREAM_CHUNK_SIZE);
	OO_CHECK(streaming->streamToBuffer(chunk.data()) == kBoopBytes);
	OO_CHECK(streaming->streamToBuffer(chunk.data()) == 0);
	streaming->reset();
	OO_CHECK(streaming->streamToBuffer(chunk.data()) == kBoopBytes);

	const oo::Ref<OOALSoundDecoder> none = oo::makeRef<OOALSoundDecoder>();
	OO_CHECK(none->sizeAsBuffer() == 0 && none->name() == std::optional<std::string>(std::string()));
	OO_CHECK(!none->descriptionComponents().has_value());
}


OO_TEST_MAIN()
