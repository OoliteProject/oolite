/*	test_filesystem.cpp
	Unit tests for oofnd/FileSystem.hpp (bead oo-i9q): oo::fs, the replacement for NSFileManager,
	the NSFileManager (OOExtensions) category and NSData's file I/O. Each test works in its own
	fresh directory under the system temporary directory and removes it afterwards.

	The semantics checked are the ones the header's banner promises, which are GNUstep's:
	existence follows links and never fails, creating an existing directory succeeds, removing a
	missing path fails, moving never overwrites, atomic writes replace, paths are UTF-8.
*/

#include "oofnd/FileSystem.hpp"

#include "oo_test.hpp"

#include <algorithm>
#include <atomic>
#include <string>
#include <system_error>
#include <vector>

namespace {

namespace fs = oo::fs;

// A fresh, empty directory for one test, deleted with everything in it at scope exit.
class Scratch
{
public:
	Scratch()
	{
		static std::atomic<int> counter{0};
		std::error_code ec;
		root_ = std::filesystem::temp_directory_path(ec) /
			("oofnd-fs-test-" + std::to_string(static_cast<long long>(std::filesystem::file_time_type::clock::now().time_since_epoch().count())) +
			 "-" + std::to_string(counter++));
		std::filesystem::remove_all(root_, ec);
		std::filesystem::create_directories(root_, ec);
	}
	~Scratch()
	{
		std::error_code ec;
		std::filesystem::remove_all(root_, ec);
	}
	const fs::Path& root() const { return root_; }
	fs::Path operator/(const char* name) const { return root_ / name; }

private:
	fs::Path root_;
};

bool writeText(const fs::Path& p, std::string_view text)
{
	return fs::writeFile(p, oo::Data::fromString(text), fs::WriteMode::direct).has_value();
}

std::string readText(const fs::Path& p)
{
	auto r = fs::readFile(p);
	return r ? r->toString() : std::string("<error>");
}

} // namespace

OO_TEST(utf8PathsRoundTrip)
{
	const std::string name = "caf\xc3\xa9-\xe2\x98\x85";   // café-★
	const fs::Path p = fs::pathFromUTF8(name);
	OO_CHECK_EQ(fs::utf8String(p), name);

	// utf8String spells separators as GNUstep does ('/'); nativeUTF8String leaves them alone.
	const fs::Path mixed = fs::pathFromUTF8("C:/Games\\Oolite") / "oolite-saves";
#if defined(_WIN32)
	OO_CHECK_EQ(fs::utf8String(mixed), std::string("C:/Games/Oolite/oolite-saves"));
	OO_CHECK_EQ(fs::nativeUTF8String(mixed), std::string("C:/Games\\Oolite\\oolite-saves"));
#else
	OO_CHECK_EQ(fs::utf8String(mixed), std::string("C:/Games\\Oolite/oolite-saves"));
#endif

	Scratch s;
	const fs::Path file = s.root() / p;
	OO_CHECK(writeText(file, "x"));
	OO_CHECK(fs::fileExists(file));
	auto names = fs::directoryContents(s.root());
	OO_CHECK(names.has_value());
	OO_CHECK(names && names->size() == 1 && names->front() == name);
}

OO_TEST(fileTypeDistinguishesFilesDirectoriesAndNothing)
{
	Scratch s;
	OO_CHECK(writeText(s / "f.txt", "hello"));
	OO_CHECK(fs::fileType(s / "f.txt") == fs::FileType::regular);
	OO_CHECK(fs::fileType(s.root()) == fs::FileType::directory);
	OO_CHECK(fs::fileType(s / "missing") == fs::FileType::none);
	OO_CHECK(fs::fileType(s / "missing" / "deeper") == fs::FileType::none);
	OO_CHECK(fs::fileExists(s / "f.txt"));
	OO_CHECK(!fs::isDirectory(s / "f.txt"));
	OO_CHECK(fs::isDirectory(s.root()));
	OO_CHECK(!fs::fileExists(s / "missing"));
	OO_CHECK(!fs::fileExists(fs::Path()));
}

OO_TEST(readFileReturnsTheBytes)
{
	Scratch s;
	const std::string binary("\x00\x01\xff\r\n\x1a" "end", 9);
	OO_CHECK(fs::writeFile(s / "b.bin", oo::Data::fromString(binary), fs::WriteMode::direct).has_value());
	auto r = fs::readFile(s / "b.bin");
	OO_CHECK(r.has_value());
	OO_CHECK(r && r->toString() == binary);   // binary mode: no CRLF or ^Z translation
	OO_CHECK(fs::fileSize(s / "b.bin").value_or(0) == 9u);
}

OO_TEST(readFileOfALargeFileCrossesTheBufferBoundary)
{
	Scratch s;
	std::string big(200 * 1024 + 17, '\0');
	for (std::size_t i = 0; i < big.size(); ++i)  big[i] = static_cast<char>(i * 7);
	OO_CHECK(writeText(s / "big", big));
	OO_CHECK(readText(s / "big") == big);
}

OO_TEST(readFileOfAnEmptyFileIsEmptyData)
{
	Scratch s;
	OO_CHECK(writeText(s / "empty", ""));
	auto r = fs::readFile(s / "empty");
	OO_CHECK(r.has_value() && r->empty());
}

OO_TEST(readFileErrors)
{
	Scratch s;
	auto missing = fs::readFile(s / "nope");
	OO_CHECK(!missing.has_value());
	OO_CHECK(!missing && missing.error() == std::errc::no_such_file_or_directory);
	auto dir = fs::readFile(s.root());
	OO_CHECK(!dir && dir.error() == std::errc::is_a_directory);
}

OO_TEST(writeFileDirectAndAtomicBothReplaceExistingContents)
{
	Scratch s;
	OO_CHECK(writeText(s / "a", "first, longer contents"));
	OO_CHECK(writeText(s / "a", "second"));
	OO_CHECK_EQ(readText(s / "a"), std::string("second"));

	OO_CHECK(fs::writeFile(s / "a", oo::Data::fromString("third"), fs::WriteMode::atomic).has_value());
	OO_CHECK_EQ(readText(s / "a"), std::string("third"));
	OO_CHECK(fs::writeFile(s / "new", oo::Data::fromString("fresh")).has_value());   // atomic is the default
	OO_CHECK_EQ(readText(s / "new"), std::string("fresh"));

	// The atomic write's temporary is gone afterwards.
	auto names = fs::directoryContents(s.root());
	OO_CHECK(names && names->size() == 2);
}

OO_TEST(writeFileIntoAMissingDirectoryFails)
{
	Scratch s;
	OO_CHECK(!fs::writeFile(s / "no" / "such" / "dir.txt", oo::Data::fromString("x"), fs::WriteMode::direct).has_value());
	OO_CHECK(!fs::writeFile(s / "no" / "such" / "dir.txt", oo::Data::fromString("x"), fs::WriteMode::atomic).has_value());
	auto names = fs::directoryContents(s.root());
	OO_CHECK(names && names->empty());
}

OO_TEST(directoryContentsListsNamesOnly)
{
	Scratch s;
	OO_CHECK(writeText(s / "b.txt", "b"));
	OO_CHECK(writeText(s / "a.txt", "a"));
	OO_CHECK(fs::createDirectories(s / "sub").has_value());
	OO_CHECK(writeText(s / "sub" / "inner", "i"));
	auto names = fs::directoryContents(s.root());
	OO_CHECK(names.has_value());
	if (!names)  return;
	std::vector<std::string> sorted = *names;
	std::sort(sorted.begin(), sorted.end());
	OO_CHECK((sorted == std::vector<std::string>{"a.txt", "b.txt", "sub"}));

	OO_CHECK(!fs::directoryContents(s / "missing").has_value());
	OO_CHECK(!fs::directoryContents(s / "a.txt").has_value());
}

OO_TEST(createDirectoriesMakesIntermediatesAndToleratesExisting)
{
	Scratch s;
	const fs::Path deep = s / "x" / "y" / "z";
	OO_CHECK(fs::createDirectories(deep).has_value());
	OO_CHECK(fs::isDirectory(deep));
	OO_CHECK(fs::createDirectories(deep).has_value());   // already there: still success

	OO_CHECK(writeText(s / "file", "f"));
	auto blocked = fs::createDirectories(s / "file");
	OO_CHECK(!blocked && blocked.error() == std::errc::not_a_directory);
	OO_CHECK(!fs::createDirectories(s / "file" / "below").has_value());
}

OO_TEST(removeItemRemovesFilesAndTreesButNotNothing)
{
	Scratch s;
	OO_CHECK(writeText(s / "f", "f"));
	OO_CHECK(fs::removeItem(s / "f").has_value());
	OO_CHECK(!fs::fileExists(s / "f"));

	OO_CHECK(fs::createDirectories(s / "t" / "u").has_value());
	OO_CHECK(writeText(s / "t" / "u" / "leaf", "l"));
	OO_CHECK(fs::removeItem(s / "t").has_value());
	OO_CHECK(!fs::fileExists(s / "t"));

	auto missing = fs::removeItem(s / "t");
	OO_CHECK(!missing && missing.error() == std::errc::no_such_file_or_directory);
}

OO_TEST(moveItemRenamesButNeverOverwrites)
{
	Scratch s;
	OO_CHECK(writeText(s / "Latest.log", "new"));
	OO_CHECK(fs::moveItem(s / "Latest.log", s / "Previous.log").has_value());
	OO_CHECK(!fs::fileExists(s / "Latest.log"));
	OO_CHECK_EQ(readText(s / "Previous.log"), std::string("new"));

	OO_CHECK(writeText(s / "Latest.log", "newer"));
	auto clash = fs::moveItem(s / "Latest.log", s / "Previous.log");
	OO_CHECK(!clash && clash.error() == std::errc::file_exists);
	OO_CHECK_EQ(readText(s / "Previous.log"), std::string("new"));
	OO_CHECK_EQ(readText(s / "Latest.log"), std::string("newer"));

	auto missing = fs::moveItem(s / "absent", s / "elsewhere");
	OO_CHECK(!missing && missing.error() == std::errc::no_such_file_or_directory);

	OO_CHECK(fs::createDirectories(s / "d1" / "inside").has_value());
	OO_CHECK(fs::moveItem(s / "d1", s / "d2").has_value());
	OO_CHECK(fs::isDirectory(s / "d2" / "inside"));
}

OO_TEST(currentDirectoryCanBeChangedAndRestored)
{
	Scratch s;
	auto original = fs::currentDirectory();
	OO_CHECK(original.has_value());
	if (!original)  return;
	OO_CHECK(fs::setCurrentDirectory(s.root()).has_value());
	auto now = fs::currentDirectory();
	OO_CHECK(now && std::filesystem::equivalent(*now, s.root()));
	OO_CHECK(writeText("relative.txt", "r"));
	OO_CHECK(fs::fileExists(s / "relative.txt"));
	OO_CHECK(!fs::setCurrentDirectory(s / "missing").has_value());
	OO_CHECK(fs::setCurrentDirectory(*original).has_value());
	auto back = fs::currentDirectory();
	OO_CHECK(back && *back == *original);
}

OO_TEST(freeSpaceAndFileSize)
{
	Scratch s;
	auto space = fs::freeSpace(s.root());
	OO_CHECK(space.has_value() && *space > 0);
	OO_CHECK(!fs::fileSize(s / "missing").has_value());
	OO_CHECK(writeText(s / "five", "12345"));
	OO_CHECK(fs::fileSize(s / "five").value_or(0) == 5u);
}

OO_TEST_MAIN()
