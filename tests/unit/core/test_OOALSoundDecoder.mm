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
	first; they now run through the facade (OOALSoundDecoder+ObjCBridge.h), which is its forwarding
	test. After them come the C++ API (cxx::OOALSoundDecoder) and the facade's contract.
	Run: bash tools/check-core-tests.sh test_OOALSoundDecoder
*/

#import "OOALSoundDecoder.h"
#import "OOLogging.h"
#import "OODescription.h"

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
	@autoreleasepool
	{
		OO_CHECK(stdfs::exists(BoopPath()));

		OOALSoundDecoder *decoder = [[[OOALSoundDecoder alloc] cxx_initWithPath:BoopPath()] autorelease];
		OO_CHECK(decoder != nil);
		OO_CHECK([decoder isKindOfClass:[OOALSoundDecoder class]]);
		OO_CHECK([decoder cxx_name] == std::optional<std::string>("boop.ogg"));

		OO_CHECK([[OOALSoundDecoder alloc] cxx_initWithPath:std::nullopt] == nil);
		OO_CHECK([[OOALSoundDecoder alloc] cxx_initWithPath:std::string("boop.wav")] == nil);
		OO_CHECK([[OOALSoundDecoder alloc] cxx_initWithPath:std::string("no-such-file.ogg")] == nil);
		OO_CHECK(gLog.empty());

		OO_CHECK([OOALSoundDecoder codecWithPath:BoopPath()] != nil);
		OO_CHECK([[OOALSoundDecoder codecWithPath:BoopPath()] cxx_name] == std::optional<std::string>("boop.ogg"));
		OO_CHECK([OOALSoundDecoder codecWithPath:"boop.wav"] == nil);
		OO_CHECK([OOALSoundDecoder codecWithPath:"no-such-file.ogg"] == nil);

		// A path through an OXZ that is not there: nil, logged.
		OO_CHECK([[OOALSoundDecoder alloc] cxx_initWithPath:std::string("no-such.oxz/Sounds/x.ogg")] == nil);
		OO_CHECK(LogLinesContaining("Could not unzip OXZ at no-such.oxz") == 1);
	}
}


OO_TEST(theSoundsProperties)
{
	@autoreleasepool
	{
		OOALSoundDecoder *decoder = [OOALSoundDecoder codecWithPath:BoopPath()];
		OO_CHECK(![decoder isStereo]);
		OO_CHECK([decoder sampleRate] == kBoopRate);
		OO_CHECK([decoder sizeAsBuffer] == kBoopBytes);

		const std::string description = oo::DescriptionOf(decoder);
		OO_CHECK(description.starts_with("<OOALSoundVorbisCodec 0x"));
		OO_CHECK(description.find(">{\"boop.ogg\", comments=") != std::string::npos);
	}
}


OO_TEST(readsTheWholeSound)
{
	@autoreleasepool
	{
		OOALSoundDecoder *decoder = [OOALSoundDecoder codecWithPath:BoopPath()];
		char *buffer = nullptr;
		size_t size = 0;
		OO_CHECK([decoder readCreatingBuffer:&buffer withFrameCount:&size]);
		OO_CHECK(buffer != nullptr && size == kBoopBytes);
		bool silent = true;
		for (size_t i = 0; i < size; i++)  silent = silent && buffer[i] == 0;
		OO_CHECK(!silent);
		std::free(buffer);

		// No out-parameters: refused.
		OO_CHECK(![decoder readCreatingBuffer:NULL withFrameCount:&size] && size == 0);
	}
}


OO_TEST(streamsAndStartsAgain)
{
	@autoreleasepool
	{
		OOALSoundDecoder *whole = [OOALSoundDecoder codecWithPath:BoopPath()];
		char *expected = nullptr;
		size_t size = 0;
		OO_CHECK([whole readCreatingBuffer:&expected withFrameCount:&size]);

		OOALSoundDecoder *decoder = [OOALSoundDecoder codecWithPath:BoopPath()];
		std::vector<char> chunk(OOAL_STREAM_CHUNK_SIZE);
		OO_CHECK([decoder streamToBuffer:chunk.data()] == kBoopBytes);
		OO_CHECK(expected != nullptr && std::memcmp(chunk.data(), expected, kBoopBytes) == 0);
		OO_CHECK([decoder streamToBuffer:chunk.data()] == 0);	// the end

		[decoder reset];
		std::fill(chunk.begin(), chunk.end(), 0);
		OO_CHECK([decoder streamToBuffer:chunk.data()] == kBoopBytes);
		OO_CHECK(std::memcmp(chunk.data(), expected, kBoopBytes) == 0);
		std::free(expected);
	}
}


// The public class's own answers: a decoder of nothing.
OO_TEST(theRootDecodesNothing)
{
	@autoreleasepool
	{
		OOALSoundDecoder *none = [[[OOALSoundDecoder alloc] init] autorelease];
		OO_CHECK(none != nil);
		char *buffer = reinterpret_cast<char *>(1);
		size_t size = 1;
		OO_CHECK(![none readCreatingBuffer:&buffer withFrameCount:&size]);
		OO_CHECK(buffer == nullptr && size == 0);
		char chunk[4] = {};
		OO_CHECK([none streamToBuffer:chunk] == 0);
		OO_CHECK([none sizeAsBuffer] == 0 && ![none isStereo] && [none sampleRate] == 0);
		[none reset];
		OO_CHECK([none cxx_name] == std::optional<std::string>(std::string()));
	}
}


// The C++ API: the same answers, null where the facade answered nil.
OO_TEST(cxxApi)
{
	OO_CHECK(!cxx::OOALSoundDecoder::initWithPath(std::nullopt));
	OO_CHECK(!cxx::OOALSoundDecoder::initWithPath(std::string("boop.wav")));
	OO_CHECK(!cxx::OOALSoundDecoder::codecWithPath("no-such-file.ogg"));

	const oo::Ref<cxx::OOALSoundDecoder> decoder = cxx::OOALSoundDecoder::initWithPath(BoopPath());
	OO_CHECK(decoder && decoder->name() == std::optional<std::string>("boop.ogg"));
	OO_CHECK(!decoder->isStereo() && decoder->sampleRate() == kBoopRate && decoder->sizeAsBuffer() == kBoopBytes);
	OO_CHECK(decoder->descriptionComponents().value_or("").starts_with("\"boop.ogg\", comments="));

	char *buffer = nullptr;
	size_t size = 0;
	OO_CHECK(decoder->readCreatingBuffer(&buffer, &size) && size == kBoopBytes);
	std::free(buffer);

	const oo::Ref<cxx::OOALSoundDecoder> streaming = cxx::OOALSoundDecoder::codecWithPath(BoopPath());
	std::vector<char> chunk(OOAL_STREAM_CHUNK_SIZE);
	OO_CHECK(streaming->streamToBuffer(chunk.data()) == kBoopBytes);
	OO_CHECK(streaming->streamToBuffer(chunk.data()) == 0);
	streaming->reset();
	OO_CHECK(streaming->streamToBuffer(chunk.data()) == kBoopBytes);

	const oo::Ref<cxx::OOALSoundDecoder> none = oo::makeRef<cxx::OOALSoundDecoder>();
	OO_CHECK(none->sizeAsBuffer() == 0 && none->name() == std::optional<std::string>(std::string()));
	OO_CHECK(!none->descriptionComponents().has_value());
}


// The facade's contract: one live facade per decoder, the same answers, nil stays nil.
OO_TEST(facade)
{
	@autoreleasepool
	{
		const oo::Ref<cxx::OOALSoundDecoder> decoder = cxx::OOALSoundDecoder::codecWithPath(BoopPath());
		OOALSoundDecoder *facade = oo::ToObjC(decoder.get());
		OO_CHECK(facade != nil && facade == oo::ToObjC(decoder));
		OO_CHECK(oo::ToCxx(facade) == decoder.get());
		OO_CHECK([facade sampleRate] == kBoopRate && [facade cxx_name] == decoder->name());

		// A facade made by the class cluster is the decoder's peer.
		OOALSoundDecoder *made = [[[OOALSoundDecoder alloc] cxx_initWithPath:BoopPath()] autorelease];
		OO_CHECK(oo::ToObjC(oo::ToCxx(made)) == made);
		OOALSoundDecoder *none = [[[OOALSoundDecoder alloc] init] autorelease];
		OO_CHECK(oo::ToObjC(oo::ToCxx(none)) == none);
		OO_CHECK(oo::DescriptionOf(none).starts_with("<OOALSoundDecoder 0x"));
	}
	OOALSoundDecoder *nothing = nil;
	OO_CHECK(oo::ToCxx(nothing) == nullptr);
	OO_CHECK(oo::ToObjC(static_cast<cxx::OOALSoundDecoder *>(nullptr)) == nil);
}


OO_TEST_MAIN()
