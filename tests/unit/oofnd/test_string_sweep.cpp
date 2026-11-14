/*	test_string_sweep.cpp
	The oo::str helpers the Foundation sweep added after its first batch (oofnd/String.hpp;
	proposed ADR-0043, "Amendment 1"): the path-component family and GNUstep's "%p".

	Every expectation is GNUstep base 1.31.1's own answer on this toolchain (64-bit Windows),
	captured by throwaway Objective-C++ probes linked against gnustep-base: the path probe read the
	71 paths and 33 component lists below from a file, and printed -pathComponents,
	-lastPathComponent, -stringByDeletingLastPathComponent, -stringByAppendingPathComponent:@"z"
	and +pathWithComponents: for each; the pointer probe printed [NSString stringWithFormat:@"%p"]
	for the pointers in pointer_description_is_gnusteps. The rows are that output, unedited.
*/

#include "oofnd/String.hpp"

#include "oo_test.hpp"

#include <cstdint>
#include <string>
#include <vector>

namespace {

struct PathRow
{
	const char* path;
	std::vector<std::string> components;
	const char* last;
	const char* deleting;
	const char* appendingZ;
	const char* rejoined;
};

struct JoinRow
{
	std::vector<std::string> components;
	const char* joined;
};

// Generated from GNUstep 1.31.1's answers (throwaway probe, see the banner): path,
// -pathComponents, -lastPathComponent, -stringByDeletingLastPathComponent,
// -stringByAppendingPathComponent:@"z", +pathWithComponents:(its own components).
const PathRow kPathRows[] = {
	{"", {}, "", "", "z", ""},
	{"/", {"/"}, "/", "/", "/z", "/"},
	{"//", {"/", "/"}, "/", "/", "/z", "/"},
	{"///", {"/", "/"}, "/", "/", "/z", "/"},
	{"\\", {"\\"}, "\\", "\\", "/z", "\\"},
	{"\\\\", {"\\", "/"}, "\\", "\\", "/z", "/"},
	{"a", {"a"}, "a", "", "a/z", "a"},
	{"a/", {"a", "/"}, "a", "", "a/z", "a"},
	{"a//", {"a", "/"}, "a", "", "a/z", "a"},
	{"a/b", {"a", "b"}, "b", "a", "a/b/z", "a/b"},
	{"a//b", {"a", "b"}, "b", "a", "a/b/z", "a/b"},
	{"a/b/", {"a", "b", "/"}, "b", "a", "a/b/z", "a/b"},
	{"/a", {"/", "a"}, "a", "/", "/a/z", "/a"},
	{"/a/b", {"/", "a", "b"}, "b", "/a", "/a/b/z", "/a/b"},
	{"//a", {"/", "a"}, "a", "/", "//a/z", "/a"},
	{"//a/b", {"/", "a", "b"}, "b", "/a", "//a/b/z", "/a/b"},
	{"//a/b/", {"//a/b/"}, "//a/b/", "//a/b/", "//a/b/z", "//a/b/"},
	{"//a/b/c", {"//a/b/", "c"}, "c", "//a/b/", "//a/b/c/z", "//a/b/c"},
	{"\\\\a\\b\\c", {"\\\\a\\b\\", "c"}, "c", "\\\\a\\b\\", "\\\\a\\b\\c/z", "\\\\a\\b/c"},
	{"\\\\a\\b", {"\\", "a", "b"}, "b", "\\a", "\\\\a/b/z", "/a/b"},
	{"\\a", {"\\", "a"}, "a", "\\", "\\a/z", "/a"},
	{"\\a\\b", {"\\", "a", "b"}, "b", "\\a", "\\a/b/z", "/a/b"},
	{"C:", {"C:"}, "C:", "", "C:z", "C:"},
	{"C:/", {"C:/"}, "C:/", "C:/", "C:/z", "C:/"},
	{"C:\\", {"C:\\"}, "C:\\", "C:\\", "C:/z", "C:\\"},
	{"C:\\\\", {"C:\\", "/"}, "C:\\", "C:\\", "C:/z", "C:/"},
	{"C://", {"C:/", "/"}, "C:/", "C:/", "C:/z", "C:/"},
	{"C:/a", {"C:/", "a"}, "a", "C:/", "C:/a/z", "C:/a"},
	{"C:\\a\\b", {"C:\\", "a", "b"}, "b", "C:\\a", "C:\\a/b/z", "C:/a/b"},
	{"C:/a/b.oxz/Music/x.ogg", {"C:/", "a", "b.oxz", "Music", "x.ogg"}, "x.ogg", "C:/a/b.oxz/Music", "C:/a/b.oxz/Music/x.ogg/z", "C:/a/b.oxz/Music/x.ogg"},
	{"C:foo", {"C:", "foo"}, "foo", "C:", "C:foo/z", "C:foo"},
	{"C:foo/bar", {"C:", "foo", "bar"}, "bar", "C:foo", "C:foo/bar/z", "C:foo/bar"},
	{"c:\\y", {"c:\\", "y"}, "y", "c:\\", "c:\\y/z", "c:/y"},
	{"z:", {"z:"}, "z:", "", "z:z", "z:"},
	{"1:", {"1:"}, "1:", "", "1:/z", "1:"},
	{"C:a\\", {"C:", "a", "/"}, "a", "C:", "C:a/z", "C:a"},
	{":", {":"}, ":", "", ":/z", ":"},
	{"a:b", {"a:", "b"}, "b", "a:", "a:b/z", "a:b"},
	{"./a", {".", "a"}, "a", ".", "./a/z", "./a"},
	{"../a", {"..", "a"}, "a", "..", "../a/z", "../a"},
	{"a/./b", {"a", ".", "b"}, "b", "a/.", "a/./b/z", "a/./b"},
	{"a/../b", {"a", "..", "b"}, "b", "a/..", "a/../b/z", "a/../b"},
	{".", {"."}, ".", "", "./z", "."},
	{"..", {".."}, "..", "", "../z", ".."},
	{"~", {"~"}, "~", "", "~/z", "~"},
	{"~/", {"~/"}, "~", "", "~/z", "~/"},
	{"~/x", {"~/", "x"}, "x", "~/", "~/x/z", "~/x"},
	{"~/x/", {"~/", "x", "/"}, "x", "~/", "~/x/z", "~/x"},
	{"~user", {"~user"}, "~user", "", "~user/z", "~user"},
	{"~user/", {"~user/"}, "~user", "", "~user/z", "~user/"},
	{"~user/x", {"~user/", "x"}, "x", "~user/", "~user/x/z", "~user/x"},
	{"a~/x", {"a~", "x"}, "x", "a~", "a~/x/z", "a~/x"},
	{"a\\b/c", {"a", "b", "c"}, "c", "a\\b", "a/b/c/z", "a/b/c"},
	{"a\\", {"a", "/"}, "a", "", "a/z", "a"},
	{"a/b\\", {"a", "b", "/"}, "b", "a", "a/b/z", "a/b"},
	{"a\\\\b", {"a", "b"}, "b", "a", "a/b/z", "a/b"},
	{" a /b ", {" a ", "b "}, "b ", " a ", " a /b /z", " a /b "},
	{"x.ogg", {"x.ogg"}, "x.ogg", "", "x.ogg/z", "x.ogg"},
	{"AddOns/foo.oxz/Music/y.ogg", {"AddOns", "foo.oxz", "Music", "y.ogg"}, "y.ogg", "AddOns/foo.oxz/Music", "AddOns/foo.oxz/Music/y.ogg/z", "AddOns/foo.oxz/Music/y.ogg"},
	{"C:\\Users\\jon\\AddOns\\foo.oxz\\Music\\a.ogg", {"C:\\", "Users", "jon", "AddOns", "foo.oxz", "Music", "a.ogg"}, "a.ogg", "C:\\Users\\jon\\AddOns\\foo.oxz\\Music", "C:\\Users/jon/AddOns/foo.oxz/Music/a.ogg/z", "C:/Users/jon/AddOns/foo.oxz/Music/a.ogg"},
	{"\xC3""\xA9""/\xC3""\xBC""", {"\xC3""\xA9""", "\xC3""\xBC"""}, "\xC3""\xBC""", "\xC3""\xA9""", "\xC3""\xA9""/\xC3""\xBC""/z", "\xC3""\xA9""/\xC3""\xBC"""},
	{"a/b/c/d/e", {"a", "b", "c", "d", "e"}, "e", "a/b/c/d", "a/b/c/d/e/z", "a/b/c/d/e"},
	{"/.", {"/", "."}, ".", "/", "/./z", "/."},
	{"/..", {"/", ".."}, "..", "/", "/../z", "/.."},
	{"a/.", {"a", "."}, ".", "a", "a/./z", "a/."},
	{"C:.", {"C:", "."}, ".", "C:", "C:./z", "C:."},
	{"~/.", {"~/", "."}, ".", "~/", "~/./z", "~/."},
	{"~\\x", {"~\\", "x"}, "x", "~\\", "~\\x/z", "~/x"},
	{"C:/a/", {"C:/", "a", "/"}, "a", "C:/", "C:/a/z", "C:/a"},
	{"/a/", {"/", "a", "/"}, "a", "/", "/a/z", "/a"},
	{"//a/b/c/", {"//a/b/", "c", "/"}, "c", "//a/b/", "//a/b/c/z", "//a/b/c"},
};

// +pathWithComponents: of these lists, as GNUstep answered.
const JoinRow kJoinRows[] = {
	{{}, ""},
	{{""}, "/"},
	{{"a"}, "a"},
	{{"a", "b"}, "a/b"},
	{{"/"}, "/"},
	{{"/", "a"}, "/a"},
	{{"\\", "a"}, "/a"},
	{{"C:", "a"}, "C:a"},
	{{"C:/", "a"}, "C:/a"},
	{{"C:\\", "a"}, "C:/a"},
	{{"C:\\"}, "C:\\"},
	{{"a", "", "b"}, "a/b"},
	{{"a/", "b"}, "a/b"},
	{{"a", "/b"}, "a/b"},
	{{"", "a"}, "/a"},
	{{"a", "b/"}, "a/b"},
	{{"//s/h/", "x"}, "//s/h/x"},
	{{"~", "x"}, "~/x"},
	{{"~/", "x"}, "~/x"},
	{{"a", "b\\"}, "a/b"},
	{{"a\\", "b"}, "a/b"},
	{{"/", "/"}, "/"},
	{{"a", "/"}, "a"},
	{{"a", "//"}, "a"},
	{{"a", "."}, "a/."},
	{{".."}, ".."},
	{{"\xC3""\xA9""", "\xC3""\xBC"""}, "\xC3""\xA9""/\xC3""\xBC"""},
	{{"C:"}, "C:"},
	{{"~"}, "~"},
	{{"~/"}, "~/"},
	{{"a", "b", ""}, "a/b"},
	{{"", ""}, "/"},
	{{"/a/", "/b/"}, "/a/b"},
};

} // namespace

OO_TEST(path_components_are_gnusteps)
{
	for (const PathRow& r : kPathRows)
	{
		if (!OO_CHECK(oo::str::pathComponents(r.path) == r.components)) std::printf("    path [%s]\n", r.path);
	}
}

OO_TEST(last_path_component_is_gnusteps)
{
	for (const PathRow& r : kPathRows)
	{
		if (!OO_CHECK_EQ(oo::str::lastPathComponent(r.path), std::string(r.last))) std::printf("    path [%s]\n", r.path);
	}
}

OO_TEST(deleting_last_path_component_is_gnusteps)
{
	for (const PathRow& r : kPathRows)
	{
		if (!OO_CHECK_EQ(oo::str::deletingLastPathComponent(r.path), std::string(r.deleting))) std::printf("    path [%s]\n", r.path);
	}
}

OO_TEST(appending_path_component_is_gnusteps)
{
	for (const PathRow& r : kPathRows)
	{
		if (!OO_CHECK_EQ(oo::str::appendingPathComponent(r.path, "z"), std::string(r.appendingZ))) std::printf("    path [%s]\n", r.path);
	}
}

OO_TEST(path_with_components_is_gnusteps)
{
	for (const PathRow& r : kPathRows)
	{
		if (!OO_CHECK_EQ(oo::str::pathWithComponents(r.components), std::string(r.rejoined))) std::printf("    path [%s]\n", r.path);
	}
	for (const JoinRow& r : kJoinRows)
	{
		if (!OO_CHECK_EQ(oo::str::pathWithComponents(r.components), std::string(r.joined))) std::printf("    joined [%s]\n", r.joined);
	}
}

OO_TEST(pointer_description_is_gnusteps)
{
	struct Row { std::uint64_t pointer; const char* text; };
	const Row rows[] = {
		{0x1, "0x1"}, {0xf, "0xf"}, {0x1234, "0x1234"}, {0xffffffff, "0xffffffff"},
		{0x100000000, "0"}, {0x100000001, "0x1"}, {0x7ff6a0b1c2d0, "0xa0b1c2d0"},
		{0xdeadbeef12345678, "0x12345678"}, {0x80000000, "0x80000000"}, {0, "(null)"},
	};
	for (const Row& r : rows)
	{
		OO_CHECK_EQ(oo::str::pointerDescription(reinterpret_cast<const void*>(static_cast<std::uintptr_t>(r.pointer))), std::string(r.text));
	}
}

OO_TEST_MAIN()
