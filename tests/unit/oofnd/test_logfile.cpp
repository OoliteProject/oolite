/*	test_logfile.cpp
	oo::log::FileWriter and the Latest.log byte conversions (oofnd/LogFile.hpp, bead oo-3rb.64).

	The logFileBytes rows were captured from gnustep-base 1.31.1 by a throwaway probe that ran
	OOAsyncLogger's -asyncLogMessage: conversion (append "\n", -componentsSeparatedByString:@"\n",
	-componentsJoinedByString:@"\r\n", -dataUsingEncoding:NSUTF8StringEncoding) on each input and
	printed the data in hex ("nil" when there was none); consoleBytes' from -UTF8String of the
	same strings.
*/

// The header must survive OOCocoa.h's true/false macros and hand them back (proposed ADR-0028).
#define true						1
#define false						0
#include "oofnd/LogFile.hpp"
#include <type_traits>
static_assert(std::is_same_v<decltype(true), int>, "LogFile.hpp must restore OOCocoa.h's true macro");
#undef true
#undef false

#include "oo_test.hpp"

#include <atomic>
#include <chrono>
#include <cstdio>
#include <filesystem>
#include <initializer_list>
#include <optional>
#include <string>

namespace {

using oo::log::consoleBytes;
using oo::log::logFileBytes;

// A UTF-8 (WTF-8 for a lone surrogate) string from UTF-16 units.
std::string U(std::initializer_list<char16_t> units)
{
	return oo::utf16ToUtf8(std::u16string(units));
}

std::string hex(const std::optional<std::string>& bytes)
{
	if (!bytes.has_value())  return "nil";
	std::string out;
	char buf[4];
	for (unsigned char c : *bytes)
	{
		std::snprintf(buf, sizeof buf, "%02X", c);
		out += buf;
	}
	return out;
}

oo::fs::Path scratchDirectory(const char* name)
{
	std::error_code ec;
	const auto stamp = std::chrono::steady_clock::now().time_since_epoch().count();
	oo::fs::Path dir = std::filesystem::temp_directory_path(ec) / ("oofnd-logfile-" + std::string(name) + "-" + std::to_string(stamp));
	std::filesystem::remove_all(dir, ec);
	std::filesystem::create_directories(dir, ec);
	return dir;
}

std::string fileContents(const oo::fs::Path& path)
{
	auto data = oo::fs::readFile(path);
	if (!data)  return "<unreadable>";
	return std::string(reinterpret_cast<const char*>(data->bytes()), data->length());
}

} // namespace

OO_TEST(logFileBytesMatchGNUstep)
{
	OO_CHECK_EQ(hex(logFileBytes(U({'a', '\n', 0x0301, 'b'}), true)), std::string("610ACC81620D0A"));
	OO_CHECK_EQ(hex(logFileBytes(U({'a', '\n', 'b', '\r', '\n', 'c'}), true)), std::string("610D0A620D0D0A630D0A"));
	OO_CHECK_EQ(hex(logFileBytes(U({'a', 0xD800, 'b'}), true)), std::string("nil"));
	OO_CHECK_EQ(hex(logFileBytes(U({'a', 0xDC00}), true)), std::string("nil"));
	OO_CHECK_EQ(hex(logFileBytes(U({'x', '\n', 0xDC00, '\n', 'y'}), true)), std::string("nil"));
	OO_CHECK_EQ(hex(logFileBytes(U({0xD83D, 0xDE00, '\n', 0x00E9}), true)), std::string("F09F98800D0AC3A90D0A"));
	OO_CHECK_EQ(hex(logFileBytes(U({'\n', '\n'}), true)), std::string("0D0A0D0A0D0A"));
	OO_CHECK_EQ(hex(logFileBytes(U({'a', '\n', 0x0301, '\n', 'b'}), true)), std::string("610ACC810D0A620D0A"));
	OO_CHECK_EQ(hex(logFileBytes("", true)), std::string("0D0A"));
	// Not Windows: the line and "\n", nothing else.
	OO_CHECK_EQ(hex(logFileBytes(U({'a', '\n', 'b'}), false)), std::string("610A620A"));
	OO_CHECK_EQ(hex(logFileBytes(U({'a', 0xD800}), false)), std::string("nil"));
	// A byte that is not UTF-8 reached GNUstep as one Latin-1 unit (oo::NSStringFrom).
	OO_CHECK_EQ(hex(logFileBytes("\xE9", true)), std::string("C3A90D0A"));
}

OO_TEST(consoleBytesMatchUTF8String)
{
	OO_CHECK_EQ(consoleBytes(U({'a', 0xD800, 'b'})), std::string("a\xEF\xBF\xBD" "b\n"));
	OO_CHECK_EQ(consoleBytes("plain"), std::string("plain\n"));
	OO_CHECK_EQ(consoleBytes(std::string("ab\0cd", 5)), std::string("ab"));
}

OO_TEST(writerWritesQueuedLinesThenThePostamble)
{
	const oo::fs::Path dir = scratchDirectory("write");
	const oo::fs::Path path = dir / "Latest.log";
	std::atomic<bool> saturated{false};
	{
		oo::log::FileWriter writer(saturated, true);
		OO_CHECK(writer.start(path));
		OO_CHECK(writer.running());
		writer.write("first");
		writer.write(U({'l', 'o', 'n', 'e', 0xD800}));	// dropped
		writer.flush();
		writer.write("a\nb");
		writer.end("\nClosing log at 2026-09-23 05:45:11 -0400.");
		OO_CHECK(!writer.running());
		writer.write("after the end");	// ignored
	}
	OO_CHECK_EQ(fileContents(path), std::string("first\r\na\r\nb\r\n\r\nClosing log at 2026-09-23 05:45:11 -0400.\r\n"));
	std::error_code ec;
	std::filesystem::remove_all(dir, ec);
}

OO_TEST(saturationTruncatesOnceForTheWholeProcess)
{
	const oo::fs::Path dir = scratchDirectory("saturate");
	std::atomic<bool> saturated{false};
	{
		oo::log::FileWriter writer(saturated, false, 12);
		OO_CHECK(writer.start(dir / "a.log"));
		writer.write("12345");		// 6 bytes
		writer.write("12345");		// 12: not past the limit
		writer.write("x");			// 14: replaced by the notice
		writer.write("never");
		writer.end("\nClosing log at X.");
	}
	OO_CHECK(saturated.load());
	OO_CHECK_EQ(fileContents(dir / "a.log"), std::string("12345\n12345\n\n\n\n***** LOG TRUNCATED DUE TO EXCESSIVE LENGTH *****\n"));
	{
		oo::log::FileWriter later(saturated, false, 12);
		OO_CHECK(later.start(dir / "b.log"));
		later.write("nothing");
		later.end("\nClosing log at X.");
	}
	OO_CHECK_EQ(fileContents(dir / "b.log"), std::string());
	std::error_code ec;
	std::filesystem::remove_all(dir, ec);
}

OO_TEST(rotationMovesLatestOverPrevious)
{
	const oo::fs::Path dir = scratchDirectory("rotate");
	const oo::fs::Path latest = dir / "Latest.log", previous = dir / "Previous.log";
	OO_CHECK(oo::log::rotateToPrevious(latest, previous));	// nothing to rotate
	OO_CHECK(oo::fs::writeFile(latest, oo::Data("new", 3)).has_value());
	OO_CHECK(oo::fs::writeFile(previous, oo::Data("old", 3)).has_value());
	OO_CHECK(oo::log::rotateToPrevious(latest, previous));
	OO_CHECK(!oo::fs::fileExists(latest));
	OO_CHECK_EQ(fileContents(previous), std::string("new"));
	std::atomic<bool> saturated{false};
	oo::log::FileWriter writer(saturated);
	OO_CHECK(!writer.start(dir / "missing-directory" / "Latest.log"));
	OO_CHECK(!writer.running());
	std::error_code ec;
	std::filesystem::remove_all(dir, ec);
}

OO_TEST_MAIN()
