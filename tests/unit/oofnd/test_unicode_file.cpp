/*	test_unicode_file.cpp
	oo::str::stringWithContentsOfUnicodeFile / decodeUnicodeText (oofnd/Encoding.hpp, bead
	oo-3rb.123): +[NSString stringWithContentsOfUnicodeFile:] (NSStringOOExtensions) as GNUstep
	1.31.1 runs it.

	Captured with a throwaway Objective-C probe (not committed) linked against gnustep-base: the
	method's body copied verbatim with +[NSData oo_dataWithOXZFile:]'s plain-file branch inlined,
	run three times over the files below, printing -length, every -characterAtIndex: and nil. The
	expectations are those UTF-16 units. The rows after a UTF-8 BOM are the exception the header's
	banner describes: GNUstep also decoded six bytes past the buffer (NULs in one run, heap garbage
	in the next two, once flipping the result to Latin-1); the rows hold the file's own text.
*/

#include "oofnd/Encoding.hpp"

#include "oo_test.hpp"

#include <atomic>
#include <cstdio>
#include <filesystem>
#include <optional>
#include <string>
#include <string_view>
#include <system_error>

namespace {

struct Row
{
	const char* name;
	std::string_view bytes;
	std::u16string_view units;
};

using namespace std::string_view_literals;

const Row kRows[] = {
	{"utf8_plain", "hello\nworld"sv, u"hello\nworld"sv},
	{"utf8_bom", "\xEF\xBB\xBFh\xC3\xA9llo"sv, u"héllo"sv},
	{"utf8_bom_only", "\xEF\xBB\xBF"sv, u""sv},
	{"utf8_bom_invalid", "\xEF\xBB\xBF" "A\xE9"sv, u"Aé"sv},
	{"utf8_double_bom", "\xEF\xBB\xBF\xEF\xBB\xBFx"sv, u"x"sv},
	{"utf16le_bom", "\xFF\xFEh\0i\0\xE9\0"sv, u"hié"sv},
	{"utf16be_bom", "\xFE\xFF\0h\0i"sv, u"栀椀"sv},
	{"utf16le_bom_only", "\xFF\xFE"sv, u""sv},
	{"utf16le_pair", "\xFF\xFE" "a\0\x3D\xD8\x00\xDE"sv, u"a\U0001F600"sv},
	{"utf16le_lone", "\xFF\xFE" "a\0\0\xD8" "b\0"sv, u"a\xD800" u"b"sv},
	{"utf16le_double_bom", "\xFF\xFE\xFF\xFEh\0"sv, u"h"sv},
	{"utf16le_bom_fffe", "\xFF\xFE\xFE\xFF\0h"sv, u"h"sv},
	{"utf16_odd", "\xFF\xFE" "A"sv, u"ÿþ" u"A"sv},
	{"latin1", "caf\xE9"sv, u"café"sv},
	{"latin1_crlf", "a\r\nb\xFF"sv, u"a\r\nbÿ"sv},
	{"nul_inside", "a\0b"sv, u"a\0b"sv},
	{"cesu", "\xED\xA0\x80"sv, u"í \u0080"sv},
	{"overlong", "\xC0\x80"sv, u"À\u0080"sv},
	{"beyond", "\xF4\x90\x80\x80"sv, u"ô\u0090\u0080\u0080"sv},
	{"four_byte", "\xF0\x9F\x98\x80"sv, u"\U0001F600"sv},
	{"truncated", "ab\xE2\x82"sv, u"abâ\u0082"sv},
	{"utf8_inner_bom", "a\xEF\xBB\xBF" "b"sv, u"a﻿" u"b"sv},
};

// A fresh directory under the system temporary directory, removed at scope exit.
class Scratch
{
public:
	Scratch()
	{
		static std::atomic<int> counter{0};
		std::error_code ec;
		root_ = std::filesystem::temp_directory_path(ec) /
			("oofnd-unicode-file-test-" + std::to_string(static_cast<long long>(std::filesystem::file_time_type::clock::now().time_since_epoch().count())) +
			 "-" + std::to_string(counter++));
		std::filesystem::remove_all(root_, ec);
		std::filesystem::create_directories(root_, ec);
	}
	~Scratch()
	{
		std::error_code ec;
		std::filesystem::remove_all(root_, ec);
	}
	std::string write(const char* name, std::string_view bytes) const
	{
		const std::filesystem::path p = root_ / name;
		std::FILE* f = std::fopen(p.string().c_str(), "wb");
		if (f != nullptr)
		{
			std::fwrite(bytes.data(), 1, bytes.size(), f);
			std::fclose(f);
		}
		return oo::fs::utf8String(p);
	}
	std::string path(const char* name) const { return oo::fs::utf8String(root_ / name); }
	const std::filesystem::path& root() const { return root_; }

private:
	std::filesystem::path root_;
};

} // namespace

OO_TEST(decode_matches_gnustep)
{
	for (const Row& r : kRows)
	{
		if (!OO_CHECK(oo::utf8ToUtf16(oo::str::decodeUnicodeText(r.bytes)) == r.units)) std::printf("    row %s\n", r.name);
	}
}

OO_TEST(file_matches_gnustep)
{
	Scratch dir;
	for (const Row& r : kRows)
	{
		const std::optional<std::string> s = oo::str::stringWithContentsOfUnicodeFile(dir.write(r.name, r.bytes));
		if (!OO_CHECK(s.has_value() && oo::utf8ToUtf16(*s) == r.units)) std::printf("    row %s\n", r.name);
	}
}

OO_TEST(result_is_utf8)
{
	OO_CHECK_EQ(oo::str::decodeUnicodeText("\xFF\xFEh\0i\0\xE9\0"sv), std::string("hi\xC3\xA9"));
	OO_CHECK_EQ(oo::str::decodeUnicodeText("caf\xE9"sv), std::string("caf\xC3\xA9"));
	OO_CHECK_EQ(oo::str::decodeUnicodeText("\xFF\xFE" "a\0\x3D\xD8\x00\xDE"sv), std::string("a\xF0\x9F\x98\x80"));
	// A lone surrogate is kept as WTF-8, as a PList string keeps it (-UTF8String printed U+FFFD).
	OO_CHECK_EQ(oo::str::decodeUnicodeText("\xFF\xFE" "a\0\0\xD8" "b\0"sv), std::string("a\xED\xA0\x80" "b"));
}

OO_TEST(missing_directory_and_empty_are_nil)
{
	Scratch dir;
	OO_CHECK(!oo::str::stringWithContentsOfUnicodeFile(dir.path("missing")).has_value());
	OO_CHECK(!oo::str::stringWithContentsOfUnicodeFile(dir.write("empty", ""sv)).has_value());
	std::error_code ec;
	std::filesystem::create_directories(dir.root() / "adir", ec);
	OO_CHECK(!oo::str::stringWithContentsOfUnicodeFile(dir.path("adir")).has_value());
}

OO_TEST_MAIN()
