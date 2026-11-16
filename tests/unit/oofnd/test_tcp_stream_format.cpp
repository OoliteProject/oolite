/*	test_tcp_stream_format.cpp
	The debug console's stream decoder formatter (src/Core/Debug/OOTCPStreamDecoderFormat.hpp,
	bead oo-0mxm): -[NSString initWithFormat:arguments:] for the conversions OOTCPStreamDecoder.c
	uses. Not an oofnd header, but plain C++ with no Foundation, so it lives in this tier.

	The expected texts were captured from GNUstep 1.31.1 on this toolchain with a throwaway
	harness (clang, gnustep-base, -initWithFormat:arguments: over the decoder's own formats and
	the same arguments). "%@" of a handle is whatever the caller's describe gives it: in the game
	that is the object's -description (a string as itself, nil as "(null)", data as GNUstep's
	"<01020304 05060708 09>"), which the fake below returns verbatim for the captured objects.
*/

#include "oo_test.hpp"
#include "../../../src/Core/Debug/OOTCPStreamDecoderFormat.hpp"

#include <cstdarg>
#include <string>

namespace {

// Stand-ins for the decoder's handles: the text GNUstep printed for each object.
struct Handle
{
	const char* description;
};

std::string Describe(const Handle* handle)
{
	return handle != nullptr ? handle->description : "(null)";
}

std::string Format(const char* format, ...)
{
	va_list args;
	va_start(args, format);
	std::string result = OOTCPStreamDecoderFormat::FormatWithArguments<const Handle*>(format, args, Describe);
	va_end(args);
	return result;
}

const Handle kNineBytes{ "<01020304 05060708 09>" };	// [NSData dataWithBytes:{1..9} length:9]
const Handle kEmptyData{ "<>" };						// [NSData data]
const Handle kThreeBytes{ "<deadbe>" };					// {0xde, 0xad, 0xbe}
const Handle kParseError{ "Parse failed at line 1" };	// an NSString
const Handle kTypeName{ "GSMutableArray" };				// an NSString

}	// namespace

OO_TEST(unsignedConversion)
{
	OO_CHECK_EQ(Format("Invalid data -- NULL bytes but %u byte count.", 0u), std::string("Invalid data -- NULL bytes but 0 byte count."));
	OO_CHECK_EQ(Format("Invalid data -- NULL bytes but %u byte count.", 4294967295u), std::string("Invalid data -- NULL bytes but 4294967295 byte count."));
}

OO_TEST(sizeConversionAndData)
{
	OO_CHECK_EQ(Format("nextSize = %zu, bufferUsed = %zu, nextPacketData = %@.", static_cast<size_t>(0), static_cast<size_t>(18446744073709551615ULL), &kNineBytes),
				std::string("nextSize = 0, bufferUsed = 18446744073709551615, nextPacketData = <01020304 05060708 09>."));
	OO_CHECK_EQ(Format("nextPacketData = %@.", &kEmptyData), std::string("nextPacketData = <>."));
	OO_CHECK_EQ(Format("nextPacketData = %@.", &kThreeBytes), std::string("nextPacketData = <deadbe>."));
}

OO_TEST(objectConversion)
{
	OO_CHECK_EQ(Format("nextPacketData = %@.", static_cast<const Handle*>(nullptr)), std::string("nextPacketData = (null)."));
	OO_CHECK_EQ(Format("Protocol error: packet is not property list (property list error: %@).", &kParseError),
				std::string("Protocol error: packet is not property list (property list error: Parse failed at line 1)."));
	OO_CHECK_EQ(Format("Protocol error: packet is a %@, not a dictionary.", &kTypeName),
				std::string("Protocol error: packet is a GSMutableArray, not a dictionary."));
}

OO_TEST(percentSigns)
{
	OO_CHECK_EQ(Format("100%% %u%%", 7u), std::string("100% 7%"));
	OO_CHECK_EQ(Format("trailing %"), std::string("trailing %"));
	OO_CHECK_EQ(Format("Protocol error: packet contains no packet type."), std::string("Protocol error: packet contains no packet type."));
}

OO_TEST_MAIN()
