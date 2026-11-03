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
            [data writeToFile:p atomically:YES / NO]      oo::fs::writeFile(p, data, WriteMode::atomic / direct)
            [fm displayNameAtPath:p]                      (GNUstep returns [p lastPathComponent]; a string op)

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
#include <cstdint>
#include <cstdio>
#include <filesystem>
#include <string>
#include <string_view>
#include <system_error>
#include <vector>

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

enum class FileType {
    none, // does not exist (or cannot be examined)
    regular,
    directory,
    other, // a device, socket, fifo...
};

inline FileType fileType(const Path& path) noexcept
{
    std::error_code ec;
    const std::filesystem::file_status st = std::filesystem::status(path, ec);
    if (ec)
        return FileType::none;
    switch (st.type()) {
    case std::filesystem::file_type::regular:
        return FileType::regular;
    case std::filesystem::file_type::directory:
        return FileType::directory;
    case std::filesystem::file_type::not_found:
    case std::filesystem::file_type::none:
        return FileType::none;
    default:
        return FileType::other;
    }
}

inline bool fileExists(const Path& path) noexcept { return fileType(path) != FileType::none; }
inline bool isDirectory(const Path& path) noexcept { return fileType(path) == FileType::directory; }

inline Result<std::uintmax_t> fileSize(const Path& path)
{
    std::error_code ec;
    const std::uintmax_t size = std::filesystem::file_size(path, ec);
    if (ec)
        return oo::Unexpected(ec);
    return size;
}

// Bytes available to this user on the volume holding path (NSFileSystemFreeSize).
inline Result<std::uintmax_t> freeSpace(const Path& path)
{
    std::error_code ec;
    const std::filesystem::space_info info = std::filesystem::space(path, ec);
    if (ec)
        return oo::Unexpected(ec);
    return info.available;
}

inline Result<std::vector<std::string>> directoryContents(const Path& path)
{
    std::error_code ec;
    std::filesystem::directory_iterator it(path, ec);
    if (ec)
        return oo::Unexpected(ec);
    std::vector<std::string> names;
    for (const std::filesystem::directory_iterator end; it != end; it.increment(ec)) {
        if (ec)
            return oo::Unexpected(ec);
        names.push_back(utf8String(it->path().filename()));
    }
    if (ec)
        return oo::Unexpected(ec);
    return names;
}

// --- Directory and item operations --------------------------------------------------------

inline Result<void> createDirectories(const Path& path)
{
    std::error_code ec;
    std::filesystem::create_directories(path, ec);
    if (ec) {
        if (fileExists(path) && !isDirectory(path))
            return oo::Unexpected(std::make_error_code(std::errc::not_a_directory));
        return oo::Unexpected(ec);
    }
    if (!isDirectory(path))
        return oo::Unexpected(std::make_error_code(std::errc::not_a_directory));
    return { };
}

inline Result<void> removeItem(const Path& path)
{
    std::error_code ec;
    const std::filesystem::file_status st = std::filesystem::symlink_status(path, ec);
    if (ec || !std::filesystem::exists(st))
        return oo::Unexpected(std::make_error_code(std::errc::no_such_file_or_directory));
    std::filesystem::remove_all(path, ec);
    if (ec)
        return oo::Unexpected(ec);
    return { };
}

inline Result<void> moveItem(const Path& from, const Path& to)
{
    std::error_code ec;
    if (!std::filesystem::exists(std::filesystem::symlink_status(from, ec))) {
        return oo::Unexpected(std::make_error_code(std::errc::no_such_file_or_directory));
    }
    if (std::filesystem::exists(std::filesystem::symlink_status(to, ec))) {
        return oo::Unexpected(std::make_error_code(std::errc::file_exists));
    }
    std::filesystem::rename(from, to, ec);
    if (ec)
        return oo::Unexpected(ec);
    return { };
}

inline Result<Path> currentDirectory()
{
    std::error_code ec;
    Path cwd = std::filesystem::current_path(ec);
    if (ec)
        return oo::Unexpected(ec);
    return cwd;
}

inline Result<void> setCurrentDirectory(const Path& path)
{
    std::error_code ec;
    std::filesystem::current_path(path, ec);
    if (ec)
        return oo::Unexpected(ec);
    return { };
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
    switch (fileType(path)) {
    case FileType::none:
        return oo::Unexpected(std::make_error_code(std::errc::no_such_file_or_directory));
    case FileType::directory:
        return oo::Unexpected(std::make_error_code(std::errc::is_a_directory));
    default:
        break;
    }
    errno = 0;
    std::FILE* f = detail::openFile(path, false);
    if (f == nullptr)
        return oo::Unexpected(detail::lastError(EACCES));

    std::vector<std::uint8_t> bytes;
    unsigned char buffer[64 * 1024];
    for (;;) {
        const std::size_t n = std::fread(buffer, 1, sizeof buffer, f);
        bytes.insert(bytes.end(), buffer, buffer + n);
        if (n < sizeof buffer)
            break;
    }
    const bool failed = std::ferror(f) != 0;
    std::fclose(f);
    if (failed)
        return oo::Unexpected(std::make_error_code(std::errc::io_error));
    return Data(std::move(bytes));
}

enum class WriteMode {
    direct, // truncate and write in place (writeToFile:atomically:NO)
    atomic, // write a sibling temporary, then rename it over the file (atomically:YES)
};

inline Result<void> writeFile(const Path& path, const Data& data, WriteMode mode = WriteMode::atomic)
{
    Path target = path;
    if (mode == WriteMode::atomic) {
        target += ".oofnd-tmp";
    }

    errno = 0;
    std::FILE* f = detail::openFile(target, true);
    if (f == nullptr)
        return oo::Unexpected(detail::lastError(EACCES));
    const bool wrote = data.empty() || std::fwrite(data.bytes(), 1, data.length(), f) == data.length();
    const bool closed = std::fclose(f) == 0;
    std::error_code ec;
    if (!wrote || !closed) {
        if (mode == WriteMode::atomic)
            std::filesystem::remove(target, ec);
        return oo::Unexpected(std::make_error_code(std::errc::io_error));
    }

    if (mode == WriteMode::atomic) {
        std::filesystem::rename(target, path, ec); // replaces an existing file
        if (ec) {
            std::error_code ignored;
            std::filesystem::remove(target, ignored);
            return oo::Unexpected(ec);
        }
    }
    return { };
}

} // namespace oo::fs

#pragma pop_macro("false")
#pragma pop_macro("true")

#endif // OOFND_FILESYSTEM_HPP
