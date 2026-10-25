/*	oofnd/FileSystem.hpp
	oo::fs: file-system operations, the C++ shape of NSFileManager and of Oolite's
	NSFileManager (OOExtensions) category (bead oo-i9q). Built on std::filesystem, using only its
	non-throwing (std::error_code) overloads; every fallible call returns oo::Expected.

	    Foundation / NSFileManagerOOExtensions        oofnd
	    --------------------------------------------  ----------------------------------------------
	    NSString *path (a file-system path)           oo::fs::Path   (= std::filesystem::path)
	    NSString -> path                              oo::fs::pathFromUTF8([s UTF8String])
	    path -> NSString                              [NSString stringWithUTF8String:
	                                                       oo::fs::utf8String(p).c_str()]
	    [fm fileExistsAtPath:p]                       oo::fs::fileExists(p)
	    [fm fileExistsAtPath:p isDirectory:&dir]      oo::fs::fileType(p)  (none/regular/directory/other)
	    [fm oo_directoryContentsAtPath:p]             oo::fs::directoryContents(p)
	    [fm oo_createDirectoryAtPath:p attributes:nil] oo::fs::createDirectories(p)
	    [fm oo_removeItemAtPath:p]                    oo::fs::removeItem(p)
	    [fm oo_moveItemAtPath:a toPath:b]             oo::fs::moveItem(a, b)
	    [fm currentDirectoryPath]                     oo::fs::currentDirectory()
	    [fm changeCurrentDirectoryPath:p]             oo::fs::setCurrentDirectory(p)
	    [fm oo_fileSystemAttributesAtPath:p]
	        objectForKey:NSFileSystemFreeSize         oo::fs::freeSpace(p)
	    [[fm oo_fileAttributesAtPath:p ...] fileSize] oo::fs::fileSize(p)
	    [NSData dataWithContentsOfFile:p]             oo::fs::readFile(p)
	    +[NSData oo_dataWithOXZFile:] (path may        OODataFromOXZFile(path)  (declared below; defined in
	        pass through a .oxz zip component)          Core/OODataFromOXZFile.mm)
	    [data writeToFile:p atomically:YES / NO]      oo::fs::writeFile(p, data, WriteMode::atomic / direct)
	    [fm createFileAtPath:p contents:nil ...] +
	        [NSFileHandle fileHandleForWritingAtPath:p] oo::fs::createFileForWriting(p)  (a FILE *)
	    [handle synchronizeFile]                      oo::fs::synchronizeFile(file)
	    [fm displayNameAtPath:p]                      (GNUstep returns [p lastPathComponent]; a string op)
	    [fm enumeratorAtPath:p] + -skipDescendents    oo::fs::RecursiveDirectoryEnumerator
	    [attrs fileModificationDate] timeInterval...  oo::fs::modificationTimeSince1970(p)
	    [fm oo_oxzFileExistsAtPath:p]                 OOOxzFileExistsAtPath(path)

	SEMANTICS (proposed ADR-0028), each matching what GNUstep does today:

	  * Paths are UTF-8 at the Objective-C boundary. Never build a Path from a std::string
	    directly: on Windows that decodes it in the ANSI code page. pathFromUTF8 / utf8String are
	    the conversions; utf8String spells the path with '/' separators, as GNUstep's NSString
	    paths are on Windows too, so strings built from oofnd paths match today's byte for byte.
	  * fileExists / fileType follow symbolic links, as fileExistsAtPath: does; a dangling link
	    does not exist. They never fail: an unreadable path is FileType::none.
	  * directoryContents lists names (not paths), without "." and "..", in the order the OS
	    enumerates them (NTFS: sorted; others: unspecified), as directoryContentsAtPath: does.
	  * createDirectories creates intermediates and succeeds if the directory already exists
	    (withIntermediateDirectories:YES); a FILE in the way is std::errc::not_a_directory.
	  * removeItem removes a file or a whole tree; a missing path is an error
	    (no_such_file_or_directory), as removeFileAtPath:handler: returns NO for it.
	  * moveItem never overwrites: an existing destination is std::errc::file_exists, as
	    movePath:toPath:handler: refuses it. (std::filesystem::rename would replace a file.)
	  * writeFile(..., WriteMode::atomic) writes a sibling temporary file and renames it over the
	    destination, so readers see the old or the new contents, never a torn file.

	Header-only, C++20, compiles with -fno-exceptions.
*/

#ifndef OOFND_FILESYSTEM_HPP
#define OOFND_FILESYSTEM_HPP

// Objective-C++ callers see OOCocoa.h's `#define true 1` / `#define false 0`; C++20 needs the
// keywords (requires-clauses, <=> in the standard headers this pulls in). Suspend the macros for
// this header and restore them at its end (proposed ADR-0028).
#pragma push_macro("true")
#pragma push_macro("false")
#undef true
#undef false

#include "oofnd/Data.hpp"
#include "oofnd/Expected.hpp"

#include <cerrno>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <filesystem>
#include <optional>
#include <string>
#include <string_view>
#include <system_error>
#include <vector>

#if defined(_WIN32)
#include <io.h>
#else
#include <unistd.h>
#endif

namespace oo::fs {

using Path = std::filesystem::path;
using Error = std::error_code;

template <class T>
using Result = oo::Expected<T, Error>;

// --- UTF-8 <-> Path -----------------------------------------------------------------------

inline Path pathFromUTF8(std::string_view utf8)
{
	const auto* p = reinterpret_cast<const char8_t*>(utf8.data());
	return Path(std::u8string_view(p, utf8.size()));
}

// The path as GNUstep spells it: UTF-8 with '/' separators on every platform (NSHomeDirectory()
// is "C:/Games/Oolite/oolite.app" even with GNUSTEP_PATH_HANDLING=windows), so a path that
// round-trips through oofnd into an NSString or a log line reads exactly as it did before.
inline std::string utf8String(const Path& path)
{
	const std::u8string u8 = path.generic_u8string();
	return std::string(reinterpret_cast<const char*>(u8.data()), u8.size());
}

// The path's own characters in UTF-8, separators untouched (for non-path text held in a Path).
inline std::string nativeUTF8String(const Path& path)
{
	const std::u8string u8 = path.u8string();
	return std::string(reinterpret_cast<const char*>(u8.data()), u8.size());
}

// --- Queries ------------------------------------------------------------------------------

enum class FileType
{
	none,            // does not exist (or cannot be examined)
	regular,
	directory,
	symbolic_link,   // only from RecursiveDirectoryEnumerator::entryType (symlink_status)
	other,           // a device, socket, fifo...
};

inline FileType fileType(const Path& path) noexcept
{
	std::error_code ec;
	const std::filesystem::file_status st = std::filesystem::status(path, ec);
	if (ec)  return FileType::none;
	switch (st.type())
	{
		case std::filesystem::file_type::regular:    return FileType::regular;
		case std::filesystem::file_type::directory:  return FileType::directory;
		case std::filesystem::file_type::not_found:
		case std::filesystem::file_type::none:       return FileType::none;
		default:                                      return FileType::other;
	}
}

inline bool fileExists(const Path& path) noexcept { return fileType(path) != FileType::none; }
inline bool isDirectory(const Path& path) noexcept { return fileType(path) == FileType::directory; }

inline Result<std::uintmax_t> fileSize(const Path& path)
{
	std::error_code ec;
	const std::uintmax_t size = std::filesystem::file_size(path, ec);
	if (ec)  return oo::Unexpected(ec);
	return size;
}

// Bytes available to this user on the volume holding path (NSFileSystemFreeSize).
inline Result<std::uintmax_t> freeSpace(const Path& path)
{
	std::error_code ec;
	const std::filesystem::space_info info = std::filesystem::space(path, ec);
	if (ec)  return oo::Unexpected(ec);
	return info.available;
}

// Seconds since the Unix epoch for the file's modification time (NSFileModificationDate's
// -timeIntervalSince1970). Follows symbolic links, as oo_fileAttributesAtPath:traverseLink:YES.
inline Result<double> modificationTimeSince1970(const Path& path)
{
	std::error_code ec;
	const std::filesystem::file_time_type ftime = std::filesystem::last_write_time(path, ec);
	if (ec)  return oo::Unexpected(ec);
	using namespace std::chrono;
	const auto systemNow = system_clock::now();
	const auto fileNow = std::filesystem::file_time_type::clock::now();
	const auto systemTime = time_point_cast<system_clock::duration>(ftime - fileNow + systemNow);
	return duration<double>(systemTime.time_since_epoch()).count();
}

// NSDirectoryEnumerator: relative paths under root, with skipDescendents(). entryType() uses
// symlink_status so a symlink is FileType::symbolic_link (as -[fileAttributes] fileType does).
class RecursiveDirectoryEnumerator
{
public:
	explicit RecursiveDirectoryEnumerator(const Path& root)
		: root_(root)
	{
		std::error_code ec;
		it_ = std::filesystem::recursive_directory_iterator(root_, std::filesystem::directory_options::none, ec);
		ok_ = !ec;
	}

	std::optional<std::string> next()
	{
		if (!ok_)  return std::nullopt;
		std::error_code ec;
		if (advanced_)
		{
			it_.increment(ec);
			if (ec)
			{
				ok_ = false;
				return std::nullopt;
			}
		}
		else
		{
			advanced_ = true;
		}
		if (it_ == end_)  return std::nullopt;

		entryPath_ = it_->path();
		type_ = typeFromSymlinkStatus(entryPath_);
		std::error_code relEc;
		const Path rel = std::filesystem::relative(entryPath_, root_, relEc);
		relative_ = relEc ? utf8String(entryPath_.filename()) : utf8String(rel);
		return relative_;
	}

	void skipDescendents()
	{
		if (ok_ && it_ != end_)  it_.disable_recursion_pending();
	}

	FileType entryType() const noexcept { return type_; }
	const Path& entryPath() const noexcept { return entryPath_; }

private:
	static FileType typeFromSymlinkStatus(const Path& path) noexcept
	{
		std::error_code ec;
		const std::filesystem::file_status st = std::filesystem::symlink_status(path, ec);
		if (ec)  return FileType::none;
		if (std::filesystem::is_symlink(st))  return FileType::symbolic_link;
		switch (st.type())
		{
			case std::filesystem::file_type::regular:    return FileType::regular;
			case std::filesystem::file_type::directory:  return FileType::directory;
			case std::filesystem::file_type::not_found:
			case std::filesystem::file_type::none:       return FileType::none;
			default:                                      return FileType::other;
		}
	}

	Path root_;
	std::filesystem::recursive_directory_iterator it_{};
	std::filesystem::recursive_directory_iterator end_{};
	bool ok_ = false;
	bool advanced_ = false;
	FileType type_ = FileType::none;
	Path entryPath_;
	std::string relative_;
};

inline Result<std::vector<std::string>> directoryContents(const Path& path)
{
	std::error_code ec;
	std::filesystem::directory_iterator it(path, ec);
	if (ec)  return oo::Unexpected(ec);
	std::vector<std::string> names;
	for (const std::filesystem::directory_iterator end; it != end; it.increment(ec))
	{
		if (ec)  return oo::Unexpected(ec);
		names.push_back(utf8String(it->path().filename()));
	}
	if (ec)  return oo::Unexpected(ec);
	return names;
}

// --- Directory and item operations --------------------------------------------------------

inline Result<void> createDirectories(const Path& path)
{
	std::error_code ec;
	std::filesystem::create_directories(path, ec);
	if (ec)
	{
		if (fileExists(path) && !isDirectory(path))  return oo::Unexpected(std::make_error_code(std::errc::not_a_directory));
		return oo::Unexpected(ec);
	}
	if (!isDirectory(path))  return oo::Unexpected(std::make_error_code(std::errc::not_a_directory));
	return {};
}

inline Result<void> removeItem(const Path& path)
{
	std::error_code ec;
	const std::filesystem::file_status st = std::filesystem::symlink_status(path, ec);
	if (ec || !std::filesystem::exists(st))  return oo::Unexpected(std::make_error_code(std::errc::no_such_file_or_directory));
	std::filesystem::remove_all(path, ec);
	if (ec)  return oo::Unexpected(ec);
	return {};
}

inline Result<void> moveItem(const Path& from, const Path& to)
{
	std::error_code ec;
	if (!std::filesystem::exists(std::filesystem::symlink_status(from, ec)))
	{
		return oo::Unexpected(std::make_error_code(std::errc::no_such_file_or_directory));
	}
	if (std::filesystem::exists(std::filesystem::symlink_status(to, ec)))
	{
		return oo::Unexpected(std::make_error_code(std::errc::file_exists));
	}
	std::filesystem::rename(from, to, ec);
	if (ec)  return oo::Unexpected(ec);
	return {};
}

inline Result<Path> currentDirectory()
{
	std::error_code ec;
	Path cwd = std::filesystem::current_path(ec);
	if (ec)  return oo::Unexpected(ec);
	return cwd;
}

inline Result<void> setCurrentDirectory(const Path& path)
{
	std::error_code ec;
	std::filesystem::current_path(path, ec);
	if (ec)  return oo::Unexpected(ec);
	return {};
}

// --- Whole-file I/O -----------------------------------------------------------------------

namespace detail {

inline std::FILE* openFile(const Path& path, bool forWriting) noexcept
{
#if defined(_WIN32)
	return ::_wfopen(path.c_str(), forWriting ? L"wb" : L"rb");
#else
	return std::fopen(path.c_str(), forWriting ? "wb" : "rb");
#endif
}

inline Error lastError(int fallback) noexcept
{
	const int e = errno;
	return std::error_code(e != 0 ? e : fallback, std::generic_category());
}

} // namespace detail

inline Result<Data> readFile(const Path& path)
{
	switch (fileType(path))
	{
		case FileType::none:       return oo::Unexpected(std::make_error_code(std::errc::no_such_file_or_directory));
		case FileType::directory:  return oo::Unexpected(std::make_error_code(std::errc::is_a_directory));
		default:                   break;
	}
	errno = 0;
	std::FILE* f = detail::openFile(path, false);
	if (f == nullptr)  return oo::Unexpected(detail::lastError(EACCES));

	std::vector<std::uint8_t> bytes;
	unsigned char buffer[64 * 1024];
	for (;;)
	{
		const std::size_t n = std::fread(buffer, 1, sizeof buffer, f);
		bytes.insert(bytes.end(), buffer, buffer + n);
		if (n < sizeof buffer)  break;
	}
	const bool failed = std::ferror(f) != 0;
	std::fclose(f);
	if (failed)  return oo::Unexpected(std::make_error_code(std::errc::io_error));
	return Data(std::move(bytes));
}

enum class WriteMode
{
	direct,   // truncate and write in place (writeToFile:atomically:NO)
	atomic,   // write a sibling temporary, then rename it over the file (atomically:YES)
};

inline Result<void> writeFile(const Path& path, const Data& data, WriteMode mode = WriteMode::atomic)
{
	Path target = path;
	if (mode == WriteMode::atomic)
	{
		target += ".oofnd-tmp";
	}

	errno = 0;
	std::FILE* f = detail::openFile(target, true);
	if (f == nullptr)  return oo::Unexpected(detail::lastError(EACCES));
	const bool wrote = data.empty() || std::fwrite(data.bytes(), 1, data.length(), f) == data.length();
	const bool closed = std::fclose(f) == 0;
	std::error_code ec;
	if (!wrote || !closed)
	{
		if (mode == WriteMode::atomic)  std::filesystem::remove(target, ec);
		return oo::Unexpected(std::make_error_code(std::errc::io_error));
	}

	if (mode == WriteMode::atomic)
	{
		std::filesystem::rename(target, path, ec);   // replaces an existing file
		if (ec)
		{
			std::error_code ignored;
			std::filesystem::remove(target, ignored);
			return oo::Unexpected(ec);
		}
	}
	return {};
}

// An empty file open for writing (created, or truncated if it exists), or nullptr: what
// -createFileAtPath:contents:nil attributes:nil followed by +fileHandleForWritingAtPath: gave the
// OXZ manager's download (bead oo-3rb.13). The caller writes with fwrite and closes with fclose.
inline std::FILE* createFileForWriting(const Path& path) noexcept
{
	return detail::openFile(path, true);
}

// -[NSFileHandle synchronizeFile]: flush the stream, then commit the file to disk.
inline bool synchronizeFile(std::FILE* file) noexcept
{
	if (file == nullptr || std::fflush(file) != 0)  return false;
#if defined(_WIN32)
	return ::_commit(::_fileno(file)) == 0;
#else
	return ::fsync(::fileno(file)) == 0;
#endif
}

} // namespace oo::fs

/*	The contents of the file at path, where a path component with the extension .oxz (any case)
	is a zip archive and the rest of the path names a file inside it (bead oo-3rb.131). nullopt
	where +oo_dataWithOXZFile: returned nil: no such file, a directory, an empty plain file, or an
	archive or entry that cannot be read (with the same log lines). Defined in Core
	(OODataFromOXZFile.mm); uses MiniZip for .oxz segments.
*/
std::optional<oo::Data> OODataFromOXZFile(const std::string &path);

/*	True when the path names an existing non-directory file, including a path that crosses a
	.oxz zip component (bead oo-1ddr). Same answers as the file manager's -oo_oxzFileExistsAtPath:.
	Defined in Core (OODataFromOXZFile.mm).
*/
bool OOOxzFileExistsAtPath(const std::string &path);

#pragma pop_macro("false")
#pragma pop_macro("true")

#endif // OOFND_FILESYSTEM_HPP
