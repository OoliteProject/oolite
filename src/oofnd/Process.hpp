/*	oofnd/Process.hpp
	oo::process: what Oolite asked of NSProcessInfo (bead oo-3rb.18, proposed ADR-0029 Decision 5).

	    Foundation                                        oofnd
	    ------------------------------------------------  --------------------------------------------
	    [[NSProcessInfo processInfo] arguments]           oo::process::arguments()  (UTF-8 strings)
	    [arguments containsObject:@"-x"]                  oo::process::hasArgument("-x")
	    [[pi environment] objectForKey:@"NAME"]           oo::env("NAME")  (std::optional, UTF-8)
	    [pi processorCount]                               oo::process::processorCount()
	    [pi operatingSystemVersionString]                 oo::process::operatingSystemVersionString()
	    [pi processName]                                  oo::process::processName()

	SEMANTICS (measured against gnustep-base 1.31 on Windows):

	  * arguments() is argv as main() received it, captured by setArguments(argc, argv) first thing
	    in main(), argv[0] included. GNUstep's -arguments is CommandLineToArgvW(GetCommandLineW())
	    in UTF-8 (argv[0] is the first token of the command line as typed, not the module path);
	    the game's main() is SDL3's SDL_main on Windows, whose argv is built the same way, so the
	    two agree. Empty until setArguments() runs.
	  * processName() is the last path component of argv[0] without its extension ("pi.exe" and
	    "C:\x\pi.exe" give "pi"), as GNUstep's.
	  * operatingSystemVersionString() is GNUstep's: "<major>.<minor>" on Windows (from the
	    version the process is shown, so "6.2" for an unmanifested process on Windows 10/11), the
	    uname() release elsewhere.
	  * processorCount() is std::thread::hardware_concurrency() (GNUstep: the logical processor
	    count, 24 on the fleet machine for both), at least 1.
	  * env() reads the process environment as it is now (Foundation snapshotted it at first use);
	    on Windows through _wgetenv, so non-ASCII values arrive as UTF-8.

	Header-only, C++20; compiles with -fno-exceptions.
*/

#ifndef OOFND_PROCESS_HPP
#define OOFND_PROCESS_HPP

// Objective-C++ callers see OOCocoa.h's `#define true 1` / `#define false 0`; suspend them for the
// standard headers (as oofnd/Data.hpp does, proposed ADR-0028).
#pragma push_macro("true")
#pragma push_macro("false")
#undef true
#undef false

#include <cstdlib>
#include <optional>
#include <string>
#include <string_view>
#include <thread>
#include <vector>

#if defined(_WIN32)
// Declared exactly as the Windows headers declare them (DWORD = unsigned long, UINT = unsigned
// int, BOOL = int), so this header does not pull <windows.h> into Objective-C++ game code.
extern "C" {
__declspec(dllimport) unsigned long __stdcall GetVersion(void);
__declspec(dllimport) int __stdcall WideCharToMultiByte(unsigned int CodePage, unsigned long dwFlags, const wchar_t *lpWideCharStr, int cchWideChar, char *lpMultiByteStr, int cbMultiByte, const char *lpDefaultChar, int *lpUsedDefaultChar);
__declspec(dllimport) int __stdcall MultiByteToWideChar(unsigned int CodePage, unsigned long dwFlags, const char *lpMultiByteStr, int cbMultiByte, wchar_t *lpWideCharStr, int cchWideChar);
}
#else
#include <sys/utsname.h>
#endif

namespace oo {

namespace process {

namespace detail {

inline std::vector<std::string>& argumentStore()
{
	static std::vector<std::string> store;
	return store;
}

} // namespace detail

// Call once, first thing in main(), with main's own argc/argv.
inline void setArguments(int argc, const char *const *argv)
{
	std::vector<std::string>& store = detail::argumentStore();
	store.clear();
	for (int i = 0; i < argc; i++)
	{
		store.emplace_back(argv[i] != nullptr ? argv[i] : "");
	}
}

inline const std::vector<std::string>& arguments()
{
	return detail::argumentStore();
}

inline bool hasArgument(std::string_view argument)
{
	for (const std::string& a : arguments())
	{
		if (a == argument)  return true;
	}
	return false;
}

inline std::string processName()
{
	const std::vector<std::string>& args = arguments();
	if (args.empty())  return std::string();
	std::string_view name = args[0];
#if defined(_WIN32)
	const size_t slash = name.find_last_of("/\\");
#else
	const size_t slash = name.find_last_of('/');
#endif
	if (slash != std::string_view::npos)  name.remove_prefix(slash + 1);
	const size_t dot = name.find_last_of('.');
	if (dot != std::string_view::npos && dot != 0)  name = name.substr(0, dot);
	return std::string(name);
}

inline unsigned processorCount()
{
	const unsigned n = std::thread::hardware_concurrency();
	return n != 0 ? n : 1;
}

inline std::string operatingSystemVersionString()
{
#if defined(_WIN32)
	const unsigned long version = GetVersion();
	return std::to_string(version & 0xFFu) + "." + std::to_string((version >> 8) & 0xFFu);
#else
	struct utsname uts;
	if (uname(&uts) != 0)  return std::string();
	return std::string(uts.release);
#endif
}

} // namespace process

// The value of environment variable `name`, or nullopt if it is not set.
inline std::optional<std::string> env(const char *name)
{
	if (name == nullptr)  return std::nullopt;
#if defined(_WIN32)
	const unsigned int kCP_UTF8 = 65001;
	int units = MultiByteToWideChar(kCP_UTF8, 0, name, -1, nullptr, 0);
	if (units <= 0)  return std::nullopt;
	std::wstring wideName(static_cast<size_t>(units), L'\0');
	MultiByteToWideChar(kCP_UTF8, 0, name, -1, wideName.data(), units);
	const wchar_t *value = _wgetenv(wideName.c_str());
	if (value == nullptr)  return std::nullopt;
	int bytes = WideCharToMultiByte(kCP_UTF8, 0, value, -1, nullptr, 0, nullptr, nullptr);
	if (bytes <= 0)  return std::string();
	std::string result(static_cast<size_t>(bytes), '\0');
	WideCharToMultiByte(kCP_UTF8, 0, value, -1, result.data(), bytes, nullptr, nullptr);
	result.resize(static_cast<size_t>(bytes) - 1);   // drop the terminator
	return result;
#else
	const char *value = std::getenv(name);
	if (value == nullptr)  return std::nullopt;
	return std::string(value);
#endif
}

} // namespace oo

#pragma pop_macro("false")
#pragma pop_macro("true")

#endif	// OOFND_PROCESS_HPP
