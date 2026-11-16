/*	test_string_path_extension.cpp
	oo::str::appendingPathExtension (oofnd/String.hpp): -stringByAppendingPathExtension: as
	gnustep-base 1.31.1 answers it on this toolchain (64-bit Windows, MSYS2 UCRT64).

	Every expectation is GNUstep's own answer, captured by two throwaway Objective-C probes linked
	against gnustep-base (bead oo-3rb.327; the probes are the ones oo-qps.68/.70/.71 used to verify
	the three file-local copies this helper replaced): the first printed
	[path stringByAppendingPathExtension:ext] for the 11 paths x 5 extensions of kGridRows, the
	second for the backslash, drive and root paths of kRootRows with @"log". The rows are that
	output, unedited. For the paths that come back unchanged GNUstep also logged "cannot append
	extension"; the helper does not log.
*/

#include "oofnd/String.hpp"

#include "oo_test.hpp"

#include <cstdio>
#include <string>

namespace {

struct Row
{
	const char* path;
	const char* extension;
	const char* appended;
};

const Row kGridRows[] = {
	{"a", "log", "a.log"},
	{"a", "vs", "a.vs"},
	{"a", "", "a."},
	{"a", "a/b", "a.a/b"},
	{"a", ".x", "a..x"},
	{"a/", "log", "a.log"},
	{"a/", "vs", "a.vs"},
	{"a/", "", "a."},
	{"a/", "a/b", "a.a/b"},
	{"a/", ".x", "a..x"},
	{"a\\", "log", "a.log"},
	{"a\\", "vs", "a.vs"},
	{"a\\", "", "a."},
	{"a\\", "a/b", "a.a/b"},
	{"a\\", ".x", "a..x"},
	{"a//", "log", "a.log"},
	{"a//", "vs", "a.vs"},
	{"a//", "", "a."},
	{"a//", "a/b", "a.a/b"},
	{"a//", ".x", "a..x"},
	{"", "log", ""},
	{"", "vs", ""},
	{"", "", ""},
	{"", "a/b", ""},
	{"", ".x", ""},
	{"a.b", "log", "a.b.log"},
	{"a.b", "vs", "a.b.vs"},
	{"a.b", "", "a.b."},
	{"a.b", "a/b", "a.b.a/b"},
	{"a.b", ".x", "a.b..x"},
	{"dir/x", "log", "dir/x.log"},
	{"dir/x", "vs", "dir/x.vs"},
	{"dir/x", "", "dir/x."},
	{"dir/x", "a/b", "dir/x.a/b"},
	{"dir/x", ".x", "dir/x..x"},
	{"/", "log", "/"},
	{"/", "vs", "/"},
	{"/", "", "/"},
	{"/", "a/b", "/"},
	{"/", ".x", "/"},
	{"C:/x/", "log", "C:/x.log"},
	{"C:/x/", "vs", "C:/x.vs"},
	{"C:/x/", "", "C:/x."},
	{"C:/x/", "a/b", "C:/x.a/b"},
	{"C:/x/", ".x", "C:/x..x"},
	{"My OXP", "log", "My OXP.log"},
	{"My OXP", "vs", "My OXP.vs"},
	{"My OXP", "", "My OXP."},
	{"My OXP", "a/b", "My OXP.a/b"},
	{"My OXP", ".x", "My OXP..x"},
	{"\xC3\xA9t\xC3\xA9", "log", "\xC3\xA9t\xC3\xA9.log"},
	{"\xC3\xA9t\xC3\xA9", "vs", "\xC3\xA9t\xC3\xA9.vs"},
	{"\xC3\xA9t\xC3\xA9", "", "\xC3\xA9t\xC3\xA9."},
	{"\xC3\xA9t\xC3\xA9", "a/b", "\xC3\xA9t\xC3\xA9.a/b"},
	{"\xC3\xA9t\xC3\xA9", ".x", "\xC3\xA9t\xC3\xA9..x"},
};

const Row kRootRows[] = {
	{"a\\b\\", "log", "a\\b.log"},
	{"C:\\x\\", "log", "C:\\x.log"},
	{"C:", "log", "C:"},
	{"C:/", "log", "C:/"},
	{"\\", "log", "\\"},
	{"//", "log", "//"},
	{"~", "log", "~"},
	{"a/.", "log", "a/..log"},
};

} // namespace

OO_TEST(appending_path_extension_is_gnusteps)
{
	for (const Row& r : kGridRows)
	{
		if (!OO_CHECK_EQ(oo::str::appendingPathExtension(r.path, r.extension), std::string(r.appended))) std::printf("    path [%s] extension [%s]\n", r.path, r.extension);
	}
}

OO_TEST(appending_path_extension_to_a_root_is_gnusteps)
{
	for (const Row& r : kRootRows)
	{
		if (!OO_CHECK_EQ(oo::str::appendingPathExtension(r.path, r.extension), std::string(r.appended))) std::printf("    path [%s] extension [%s]\n", r.path, r.extension);
	}
}

OO_TEST_MAIN()
