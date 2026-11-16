/*

main.m

Oolite
Copyright (C) 2004-2013 Giles C Williams and contributors

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
MA 02110-1301, USA.

*/

#include "GameController.h"
#include "OOLoggingExtended.h"
#include "oofnd/Process.hpp"
#include "oofnd/Ref.hpp"  // oo::AutoreleaseScope
#include "oofnd/String.hpp"
#include "oofnd/objc/OOException.h"
#include "oofnd/objc/OOObject.h"

// gnustep-base's GSConfig.h gave these (used by the -help text below).
#ifndef STRINGIFY
#define XSTRINGIFY(s) #s
#define STRINGIFY(s) XSTRINGIFY(s)
#endif

#if OOLITE_WINDOWS
#include <SDL3/SDL_main.h>
#include <SDL3/SDL_stdinc.h>
#include <locale.h>

#include <cstring>
#include <optional>
#include <string>
// Make sure that a high performance GPU is
// selected, if more than one are available
__declspec(dllexport) DWORD NvOptimusEnablement = 0x00000001;
__declspec(dllexport) int AmdPowerXpressRequestHighPerformance = 1;
#elif OOLITE_LINUX
#include <unistd.h>
#elif OOLITE_MACOS
#include <mach-o/dyld.h>
#include <unistd.h>
#endif

namespace {
// The controller lives to the end of the process and is never destroyed, as
// upstream's GameController *controller was never released: the game exits with
// exit(0) from inside it, and a namespace-scope oo::Ref would tear the universe
// down during static destruction, after function-local statics such as
// oo::log's logger have died.
GameController* controller = nullptr;
}  // namespace

#ifdef OO_DEBUG_MONITOR_ENABLED
uint32_t gDebugFlags = 0;
#endif

#ifndef STRINGIFY  // provided by GNUstep
#define STRINGIFY_(s) #s
#define STRINGIFY(s) STRINGIFY_(s)
#endif

// This macro is normally defined in the build command
#ifndef OO_VERSION_FULL
#define OO_VERSION_FULL "Undefined"
#endif

/**
 * \ingroup cli
 * Entry point for Linux and Windows systems.
 * Initializes logging. If -load is passed, the argument after that is loaded
 * as savegame.
 *
 * @param argc the number of command line arguments
 * @param argv the string array values of the command line arguments
 * @return returns 0 on success, or EXITFAILURE when an exception is caught
 */
int main(int argc, char* argv[]) {
  // Foundation's process-info -arguments, now captured here: argv as SDL_main
  // built it (UTF-8 on Windows).
  oo::process::setArguments(argc, argv);

  int i;

#if OOLITE_WINDOWS

#define OO_SHOW_MSG(ooMsg, ooMsgTitle, ooMsgFlags) \
  MessageBox(NULL, ooMsg, ooMsgTitle, ooMsgFlags)
#define TABS1 "\t"
#define TABS2 "\t\t"
#define TABS3 "\t\t\t"
#define TABS4 ""

  // Detect current working directory and set up GNUstep environment variables
  // (32767 characters is the longest path Windows allows).
  std::string currentWorkingDir(32768, '\0');
  DWORD bufferSize = static_cast<DWORD>(currentWorkingDir.size());

  if (QueryFullProcessImageName(GetCurrentProcess(), 0,
                                currentWorkingDir.data(), &bufferSize)) {
    currentWorkingDir.resize(bufferSize);
  } else {
    currentWorkingDir.clear();
  }
  // Strip the exe filename (from last backslash onwards), leave just the path
  const size_t probe = currentWorkingDir.rfind('\\');
  if (probe != std::string::npos)
    currentWorkingDir.resize(probe);  // now the path we need

  // Prepend system PATH env variable with our own executable's path
  const char* pathEnvVar = "Path";
  const char* systemPath = SDL_getenv(pathEnvVar);
  if (!systemPath) {
    pathEnvVar = "PATH";
    systemPath = SDL_getenv(pathEnvVar);
  }
  std::string finalPath = currentWorkingDir;
  if (systemPath) {
    finalPath += ';';
    finalPath += systemPath;
  }

  SDL_setenv_unsafe("GNUSTEP_PATH_HANDLING", "windows", true);
  SDL_setenv_unsafe(pathEnvVar, finalPath.c_str(), true);
  SDL_setenv_unsafe("GNUSTEP_SYSTEM_ROOT", currentWorkingDir.c_str(), true);
  SDL_setenv_unsafe("GNUSTEP_LOCAL_ROOT", currentWorkingDir.c_str(), true);
  SDL_setenv_unsafe("GNUSTEP_NETWORK_ROOT", currentWorkingDir.c_str(), true);
  SDL_setenv_unsafe("GNUSTEP_USERS_ROOT", currentWorkingDir.c_str(), true);
#if OO_GAME_DATA_TO_USER_FOLDER
  // The path is built in a string of its own; LOCALAPPDATA is the
  // environment's buffer and must not be appended to.
  const char* localAppData = SDL_getenv("LOCALAPPDATA");
  const std::string userHome =
      localAppData ? std::string(localAppData) + "\\Oolite\\oolite.app"
                   : currentWorkingDir;
  SDL_setenv_unsafe("HOMEPATH", userHome.c_str(), true);
#else
  SDL_setenv_unsafe("HOMEPATH", currentWorkingDir.c_str(), true);
#endif

  SetCurrentDirectory(currentWorkingDir.c_str());

  /*	Windows ambitiously starts apps with the C library locale set to the
          system locale rather than the "C" locale as per spec. Fixing here so
          numbers don't behave strangely.
  */
  setlocale(LC_ALL, "C");

#else  // Linux and Mac
#if OOLITE_LINUX
  char result[PATH_MAX];
  ssize_t count = readlink("/proc/self/exe", result, PATH_MAX - 1);
  result[count] = '\0';
  char* last_slash = strrchr(result, '/');
  if (last_slash != NULL) {
    *last_slash =
        '\0';  // Chop off the executable name, leaving just the directory
  }
  if (chdir(result) != 0) {
    // As before: if the executable's directory cannot be entered, the game
    // starts where it is.
  }
#elif OOLITE_MACOS
  // Run from the folder holding Resources and AddOns: Contents in an app bundle
  // (executable in Contents/MacOS), otherwise the folder holding the
  // executable.
  char result[PATH_MAX];
  uint32_t resultSize = sizeof(result);
  char resolved[PATH_MAX];
  if (_NSGetExecutablePath(result, &resultSize) == 0 &&
      realpath(result, resolved) != nullptr) {
    char* last_slash = strrchr(resolved, '/');
    if (last_slash != nullptr) {
      *last_slash = '\0';
    }
    if (chdir(resolved) != 0) {
      // As on Linux: the game starts where it is.
    }
    size_t length = strlen(resolved);
    if (length >= 15 &&
        strcmp(resolved + length - 15, "/Contents/MacOS") == 0) {
      if (chdir("..") != 0) {
        // The game starts in Contents/MacOS.
      }
    }
  }
#endif
#define OO_SHOW_MSG(ooMsg, ooTitle, ooFlags) fprintf(stdout, "%s", ooMsg)
#define TABS1 "\t\t"
#define TABS2 "\t\t\t"
#define TABS3 "\t\t\t\t"
#define TABS4 "\t"
#endif

  // Need this because we're not using the default run loop's autorelease
  // pool.
  // (Popped below, before applicationDidFinishLaunching.)
  std::optional<oo::AutoreleaseScope> pool;
  pool.emplace();
  OOLoggingInit();

  try {
    // dajt: allocate and set the NSApplication delegate manually because not
    // using NIB to do this
    controller =
        oo::makeRef<GameController>().leakRef();  // never released (see above)

    for (i = 1; i < argc; i++) {
      if (strcmp("-load", argv[i]) == 0) {
        i++;
      }
      // argv is UTF-8 (SDL_main); an argument past the end reads as nothing, as
      // nil did.
      const std::string argument = (i < argc) ? argv[i] : "";
      if (i < argc &&
          oo::str::hasSuffix(oo::str::lowercase(argument), ".oolite-save")) {
        controller->setPlayerFileToLoad(argument);
      }

      if (argument == "-help" || argument == "--help") {
        std::string processNameString = oo::process::processName();
        char const* processName = processNameString.c_str();
        char s[2048];
        snprintf(s, sizeof(s),
                 "Usage: %s [options]\n\n"
                 "Options can be any of the following: \n\n"
                 "--compile-sysdesc" TABS2
                 "Compile system descriptions *\n"
                 "--export-sysdesc" TABS2
                 "Export system descriptions *\n"
#if OOLITE_WINDOWS
                 "-hdr" TABS3
                 "Start up in HDR mode\n"
#endif
                 "-load [filepath]" TABS2
                 "Load commander from [filepath]\n" TABS3 TABS4
                 "(\"-load\" is optional)\n"
                 "-message [messageString]" TABS1
                 "Display [messageString] at startup\n"
                 "-nodust    " TABS2 TABS4
                 "Do not draw space dust\n"
                 "-noshaders" TABS2 TABS4
                 "Start up with shaders disabled\n"
                 "-nosplash    " TABS2 TABS4
                 "Force disable splash screen on startup\n"
                 "-nosound    " TABS2 TABS4
                 "Start up with sound disabled\n"
                 "-novsync" TABS3
                 "Force disable V-Sync\n"
                 "--openstep" TABS2 TABS4
                 "When compiling or exporting\n" TABS3 TABS4
                 "system descriptions, use openstep\n" TABS3 TABS4
                 "format *\n"
                 "-showversion" TABS2 TABS4
                 "Display version at startup screen\n"
                 "-splash" TABS3 TABS4
                 "Force splash screen on startup\n"
                 "-verify-oxp [filepath]    " TABS1
                 "Verify OXP at [filepath] *\n"
                 "--xml" TABS3 TABS4 "When compiling or exporting\n" TABS3 TABS4
                 "system descriptions, use xml\n" TABS3 TABS4
                 "format *\n"
                 "\n"
                 "Options marked with \"*\" are available only in Test Release "
                 "configuration.\n"
                 "Version " OO_VERSION_FULL
                 "\n"
                 "Debug functionality enabled (Test Release): "
#ifdef OO_DEBUG_MONITOR_ENABLED
                 "yes\n"
#else
                 "no\n"
#endif
                 "Built with "
#if OOLITE_HAVE_CLANG
                 "Clang version " STRINGIFY(__clang_major__) "." STRINGIFY(
                     __clang_minor__) "." STRINGIFY(__clang_patchlevel__)
#else
                 "GCC version " STRINGIFY(__GNUC__) "." STRINGIFY(
                     __GNUC_MINOR__) "." STRINGIFY(__GNUC_PATCHLEVEL__)
#endif
                     "\n\n",
                 processName);
        OO_SHOW_MSG(s, processName, MB_OK);
        OO_LOG(
            "process.args",
            "{} option detected, exiting after help page has been displayed.",
            argument);
        return 0;
      }
    }

    // Release anything allocated during the controller initialisation that
    // is no longer required.
    pool.reset();

    // Call applicationDidFinishLaunching because NSApp is not running in
    // GNUstep port.
    controller->applicationDidFinishLaunching();
  } catch (...) {
    const auto exception = oo::CurrentOOException();
    if (!exception) throw;  // not an OOException: it goes on up, as before
    OO_LOG_ERR(cxx_kOOLogException,
               "Root exception handler hit - terminating. This is an internal "
               "error, please report it. Exception name: {}, reason: {}",
               exception->name(), exception->reason());
    return EXIT_FAILURE;
  }

  // never reached
  return 0;
}
