/*	oofnd/ResourcePaths.hpp
	oo::ResourcePaths: where the game finds its built-in Resources, its AddOns roots and its
	per-user directories (saves, snapshots, logs, caches, managed OXZs). Replaces the NSBundle /
	NSHomeDirectory() / NSSearchPathForDirectoriesInDomains() lookups (bead oo-i9q).

	Every answer reproduces what the game computes TODAY on the SDL platforms (Windows, Linux),
	including the OO_* environment overrides, so a consumer can switch without moving a file:

	    today (Objective-C)                                      oofnd
	    -------------------------------------------------------  ---------------------------------
	    NSHomeDirectory()                                        homeDirectory()
	    [fm defaultCommanderPath] (before its mkdir/fallback)    saveDirectory()
	      OO_SAVEDIR | ~/oolite-saves
	    chdirToSnapshotPath's directory                          snapshotDirectory()
	      OO_SNAPSHOTSDIR | ~/oolite-saves/snapshots
	    OOLogHandlerGetLogBasePath()  (before its mkdirs)        logDirectory()
	      OO_LOGSDIR | Windows ~/Logs, Linux ~/.Oolite/Logs
	    NSSearchPathForDirectoriesInDomains(NSLibraryDirectory)  userLibraryDirectory()
	      ~/GNUstep/Library   (GNUstep's default user layout)
	    ...(NSApplicationSupportDirectory)                       applicationSupportDirectory()
	      ~/GNUstep/Library/ApplicationSupport
	    ...(NSCachesDirectory)                                   cachesDirectory()
	      ~/GNUstep/Library/Caches
	    [[OOOXZManager sharedManager] installPath]               managedAddOnsDirectory()
	      OO_MANAGEDADDONSDIR | <ApplicationSupport>/Oolite/ManagedAddOns
	    [[OOOXZManager sharedManager] extractAddOnsPath]         extractAddOnsDirectory()
	      OO_ADDONSEXTRACTDIR | Windows "../AddOns" (relative, as today) or, when built with
	      OO_GAME_DATA_TO_USER_FOLDER, %LOCALAPPDATA%\Oolite\AddOns | Linux ~/.Oolite/AddOns
	    [[OOOXZManager sharedManager] additionalAddOnsPaths]     additionalAddOnsDirectories()
	      OO_ADDITIONALADDONSDIRS split on ','
	    [ResourceManager builtInPath]                            builtInResourcesDirectory()
	      <cwd>/Resources if it is a directory, else <cwd>/../share/oolite/Resources
	    [ResourceManager userRootPaths]                          userRootDirectories()
	    [ResourceManager rootPaths]                              rootDirectories()

	"~" is homeDirectory(). On Windows that is GNUstep's rule: %HOMEPATH% (prefixed with
	%HOMEDRIVE% unless it already starts with a drive letter), else %USERPROFILE%. SDL/main.mm
	points HOMEPATH at the executable's directory (or %LOCALAPPDATA%\Oolite\oolite.app under
	OO_GAME_DATA_TO_USER_FOLDER) before anything reads it, which is why saves, Logs and
	GNUstep/Library all live next to oolite.exe. On Linux it is $HOME. With neither, the current
	directory. The macOS (Cocoa) layout is not reproduced: that platform is outside ADR-0017.
	The home and GNUstep/Library rules were probed against gnustep-base 1.31 on this toolchain
	(HOMEPATH with and without a drive, NSSearchPathForDirectoriesInDomains); the rest transcribe
	the Objective-C cited above. fs::utf8String() of an answer is the string the Objective-C
	code produces today, '/' separators included.

	ResourcePaths is a pure function of a PathEnvironment (platform, environment lookup, current
	directory), so tests drive it with a fake environment; PathEnvironment::process() is the real
	one. The environment is read through GetEnvironmentVariableW on Windows so that variables set
	at run time with SetEnvironmentVariable (SDL_setenv_unsafe does) are seen, as GNUstep and SDL
	see them; the CRT's getenv() copy would miss them. Nothing here creates a directory: creating
	and falling back is the consumer's job, as it is today (oofnd/FileSystem.hpp).

	Header-only, C++20, compiles with -fno-exceptions. Proposed ADR-0028 records the choices.
*/

#ifndef OOFND_RESOURCEPATHS_HPP
#define OOFND_RESOURCEPATHS_HPP

// Objective-C++ callers see OOCocoa.h's `#define true 1` / `#define false 0`; C++20 needs the
// keywords (requires-clauses, <=> in the standard headers this pulls in). Suspend the macros for
// this header and restore them at its end (proposed ADR-0028).
#pragma push_macro("true")
#pragma push_macro("false")
#undef true
#undef false

#include "oofnd/FileSystem.hpp"

#include <cstdlib>
#include <functional>
#include <optional>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

#if defined(_WIN32)
// Declared here rather than by including <windows.h>, which would drag min/max macros and the
// whole Win32 API into every Objective-C++ file that includes oofnd. Identical to the SDK's.
extern "C" __declspec(dllimport) unsigned long __stdcall GetEnvironmentVariableW(const wchar_t* name, wchar_t* buffer, unsigned long size);
#endif

namespace oo {

struct PathEnvironment
{
	enum class Platform
	{
		windows,
		posix,       // Linux and the other SDL POSIX builds
	};

	using Getenv = std::function<std::optional<std::string>(const std::string& name)>;

	Platform platform = Platform::posix;
	Getenv getenv;                        // UTF-8 value of a variable, or nullopt when unset
	fs::Path currentDirectory;
	bool gameDataToUserFolder = false;    // the OO_GAME_DATA_TO_USER_FOLDER build setting

	// The running process: its platform, environment and current directory right now.
	static PathEnvironment process()
	{
		PathEnvironment env;
#if defined(_WIN32)
		env.platform = Platform::windows;
#else
		env.platform = Platform::posix;
#endif
		env.getenv = &processGetenv;
		env.currentDirectory = fs::currentDirectory().value_or(fs::Path());
#if defined(OO_GAME_DATA_TO_USER_FOLDER) && OO_GAME_DATA_TO_USER_FOLDER
		env.gameDataToUserFolder = true;
#endif
		return env;
	}

	static std::optional<std::string> processGetenv(const std::string& name)
	{
#if defined(_WIN32)
		const std::wstring wname = fs::pathFromUTF8(name).native();
		std::wstring value(256, L'\0');
		for (;;)
		{
			const unsigned long n = ::GetEnvironmentVariableW(wname.c_str(), value.data(), static_cast<unsigned long>(value.size()));
			if (n == 0)  return std::nullopt;     // unset (an empty value also reads as unset, as in SDL_getenv)
			if (n < value.size())
			{
				value.resize(n);
				return fs::nativeUTF8String(fs::Path(value));   // raw: a variable is not always a path
			}
			value.assign(n, L'\0');                // n is the size needed, terminator included
		}
#else
		const char* value = std::getenv(name.c_str());
		if (value == nullptr)  return std::nullopt;
		return std::string(value);
#endif
	}
};

class ResourcePaths
{
public:
	explicit ResourcePaths(PathEnvironment env) : env_(std::move(env)) {}

	// For the running process (reads the environment and current directory at call time).
	static ResourcePaths current() { return ResourcePaths(PathEnvironment::process()); }

	const PathEnvironment& environment() const noexcept { return env_; }

	fs::Path homeDirectory() const
	{
		if (windows())
		{
			if (std::optional<std::string> homePath = get("HOMEPATH"))
			{
				const bool hasDrive = homePath->size() >= 2 && (*homePath)[1] == ':';
				if (!hasDrive)  *homePath = get("HOMEDRIVE").value_or(std::string()) + *homePath;
				return fs::pathFromUTF8(*homePath);
			}
			if (std::optional<std::string> profile = get("USERPROFILE"))  return fs::pathFromUTF8(*profile);
		}
		else if (std::optional<std::string> home = get("HOME"))
		{
			return fs::pathFromUTF8(*home);
		}
		return env_.currentDirectory;
	}

	fs::Path saveDirectory() const
	{
		return overridden("OO_SAVEDIR", [&] { return homeDirectory() / "oolite-saves"; });
	}

	fs::Path snapshotDirectory() const
	{
		return overridden("OO_SNAPSHOTSDIR", [&] { return homeDirectory() / "oolite-saves" / "snapshots"; });
	}

	fs::Path logDirectory() const
	{
		return overridden("OO_LOGSDIR", [&] {
			return windows() ? homeDirectory() / "Logs" : homeDirectory() / ".Oolite" / "Logs";
		});
	}

	fs::Path userLibraryDirectory() const { return homeDirectory() / "GNUstep" / "Library"; }
	fs::Path applicationSupportDirectory() const { return userLibraryDirectory() / "ApplicationSupport"; }
	fs::Path cachesDirectory() const { return userLibraryDirectory() / "Caches"; }

	fs::Path managedAddOnsDirectory() const
	{
		return overridden("OO_MANAGEDADDONSDIR", [&] { return applicationSupportDirectory() / "Oolite" / "ManagedAddOns"; });
	}

	fs::Path extractAddOnsDirectory() const
	{
		return overridden("OO_ADDONSEXTRACTDIR", [&] {
			if (!windows())  return homeDirectory() / ".Oolite" / "AddOns";
			if (env_.gameDataToUserFolder)  return fs::pathFromUTF8(get("LOCALAPPDATA").value_or(std::string())) / "Oolite" / "AddOns";
			return fs::Path("../AddOns");
		});
	}

	std::vector<fs::Path> additionalAddOnsDirectories() const
	{
		std::vector<fs::Path> result;
		const std::optional<std::string> list = get("OO_ADDITIONALADDONSDIRS");
		if (!list)  return result;
		// componentsSeparatedByString:@"," keeps empty components, and so does this.
		std::string_view rest = *list;
		for (;;)
		{
			const std::size_t comma = rest.find(',');
			result.push_back(fs::pathFromUTF8(rest.substr(0, comma)));
			if (comma == std::string_view::npos)  break;
			rest.remove_prefix(comma + 1);
		}
		return result;
	}

	fs::Path builtInResourcesDirectory() const
	{
		const fs::Path primary = env_.currentDirectory / "Resources";
		if (fs::isDirectory(primary))  return primary;
		return (env_.currentDirectory.parent_path() / "share" / "oolite" / "Resources").lexically_normal();
	}

	// Additional AddOns roots, then <cwd>/../share/oolite/AddOns, <cwd>/AddOns, the extract dir.
	std::vector<fs::Path> userRootDirectories() const
	{
		std::vector<fs::Path> result = additionalAddOnsDirectories();
		result.push_back(env_.currentDirectory.parent_path() / "share" / "oolite" / "AddOns");
		result.push_back(env_.currentDirectory / "AddOns");
		result.push_back(extractAddOnsDirectory());
		return result;
	}

	// Built-in data, then managed OXZs, then the user roots: ResourceManager's search order.
	std::vector<fs::Path> rootDirectories() const
	{
		std::vector<fs::Path> result{builtInResourcesDirectory(), managedAddOnsDirectory()};
		for (fs::Path& p : userRootDirectories())  result.push_back(std::move(p));
		return result;
	}

private:
	bool windows() const noexcept { return env_.platform == PathEnvironment::Platform::windows; }

	std::optional<std::string> get(const std::string& name) const
	{
		if (!env_.getenv)  return std::nullopt;
		return env_.getenv(name);
	}

	template <class Default>
	fs::Path overridden(const std::string& variable, Default fallback) const
	{
		if (std::optional<std::string> value = get(variable))  return fs::pathFromUTF8(*value);
		return fallback();
	}

	PathEnvironment env_;
};

} // namespace oo

#pragma pop_macro("false")
#pragma pop_macro("true")

#endif // OOFND_RESOURCEPATHS_HPP
