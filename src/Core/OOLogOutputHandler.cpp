/*

OOLogOutputHandler.m
By Jens Ayton


Copyright (C) 2007-2013 Jens Ayton and contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

*/

#include "OOLogOutputHandler.h"

#include <SDL3/SDL_stdinc.h>
#include <stdio.h>
#include <stdlib.h>

#include <atomic>
#include <chrono>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <memory>
#include <optional>
#include <string>
#include <string_view>
#include <thread>

#include "OOFoundation.h"
#include "OOLogging.h"
#include "oofnd/Date.hpp"
#include "oofnd/Defaults.hpp"
#include "oofnd/FileSystem.hpp"
#include "oofnd/Log.hpp"
#include "oofnd/LogFile.hpp"
#include "oofnd/PListParsing.hpp"
#include "oofnd/ResourcePaths.hpp"
#include "oofnd/Thread.hpp"

/*	The Latest.log writer is oo::log::FileWriter (oofnd/LogFile.hpp): the
   rotation to Previous.log, the writer thread, CRLF, the 1 GiB saturation and
   the flush are its, byte for byte as OOAsyncLogger did them. What stays here
   is the glue: the log directory, the logging-echo-to-stderr / stdout switches
   and the flush deadline.
*/

namespace {

bool DirectoryExistCreatingIfNecessary(const std::string& path);
const std::optional<std::string>& LogBasePath();
std::optional<std::string> LogPath();
std::string AppendPathComponent(std::string base, const std::string& component);
std::unique_ptr<oo::log::FileWriter> StartLogger();
void AsyncLogMessage(std::string_view message);

}  // namespace

#define kFlushInterval \
  2.0  // Lower bound on interval between explicit log file flushes.

static bool sInited = false;
static bool sWriteToStderr = true;
static bool sWriteToStdout = false;

namespace {

std::atomic<bool> sSaturated{false};
std::unique_ptr<oo::log::FileWriter> sLogger;
const char* const kDefaultLogFileName = "Latest.log";
std::string sLogFileName;  // empty until first set: kDefaultLogFileName

}  // namespace

/*	The pending flush (was a one-shot run-loop timer): a deadline on
   std::chrono::steady_clock that the frame loop checks. The timer
   was scheduled on the logging thread's run loop, and only the main thread's
   run loop ever runs, so a flush first requested from another thread never
   fired and blocked later ones; kFlushNever keeps that.
*/
namespace {

const int64_t kFlushNever = INT64_MAX;
std::atomic<bool> sFlushPending{false};
std::atomic<int64_t> sFlushDeadline{
    kFlushNever};  // steady_clock ticks since its epoch

}  // namespace

void OOLogOutputHandlerInit() {
  if (sInited) return;

  sLogger = StartLogger();
  sInited = true;

  if (sLogger != nullptr) {
    sWriteToStderr =
        oo::Defaults::standard().boolForKey("logging-echo-to-stderr");
  } else {
    sWriteToStderr = true;
  }

  atexit(OOLogOutputHandlerClose);
}

namespace {

// -endLogging's postamble.
std::string Postamble() {
  return "\nClosing log at " + oo::date::description() + ".";
}

const std::string& LogFileName() {
  if (sLogFileName.empty()) sLogFileName = kDefaultLogFileName;
  return sLogFileName;
}

}  // namespace

void OOLogOutputHandlerClose() {
  if (sInited) {
    sWriteToStderr = true;
    sInited = false;

    if (sLogger != nullptr) sLogger->end(Postamble());
    sLogger.reset();
  }
}

void OOLogOutputHandlerStartLoggingToStdout() { sWriteToStdout = true; }
void OOLogOutputHandlerStopLoggingToStdout() { sWriteToStdout = false; }

void OOLogOutputHandlerFlushIfDue() {
  if (!sFlushPending || sLogger == nullptr) return;
  if (std::chrono::steady_clock::now().time_since_epoch().count() <
      sFlushDeadline)
    return;
  sFlushDeadline = kFlushNever;
  sFlushPending = false;
  sLogger->flush();
}

void OOLogOutputHandlerPrintLine(std::string_view line) {
  if (sInited && sLogger != nullptr && !sWriteToStdout) AsyncLogMessage(line);

  bool doCStringStuff = sWriteToStderr || sWriteToStdout;

  if (doCStringStuff) {
    const std::string cStr = oo::log::consoleBytes(line);
    if (sWriteToStdout)
      fputs(cStr.c_str(), stdout);
    else if (sWriteToStderr)
      fputs(cStr.c_str(), stderr);
  }
}

std::optional<std::string> OOLogHandlerGetLogPath() { return LogPath(); }

void OOLogOutputHandlerChangeLogFile(const std::string& name) {
  if (LogFileName() != name) {
    sLogFileName = name;
    if (sLogger != nullptr) {
      // -changeFile: end this file (postamble), start the new one (no
      // rotation).
      sLogger->end(Postamble());
      std::optional<std::string> path = LogPath();
      if (!path.has_value() || !sLogger->start(oo::fs::pathFromUTF8(*path))) {
        if (path.has_value())
          OO_LOG("unclassified",
                 "Log setup: could not open log at {}, will log to stdout "
                 "instead.",
                 *path);
        sWriteToStderr = true;
      }
    }
  }
}

/*	Opening the async logger moves an existing log to
   Previous.log, create the new one and start the writer. nullptr when that
   fails; the handler then logs to stderr.
*/
namespace {

std::unique_ptr<oo::log::FileWriter> StartLogger() {
  std::optional<std::string> logPath = LogPath();
  if (!logPath.has_value()) return nullptr;

  const oo::fs::Path latest = oo::fs::pathFromUTF8(*logPath);
  const oo::fs::Path previous =
      oo::fs::pathFromUTF8(AppendPathComponent(*LogBasePath(), "Previous.log"));
  if (!oo::log::rotateToPrevious(latest, previous)) {
    OO_LOG("unclassified",
           "Log setup: could not move or delete existing log at {}, will log "
           "to stdout instead.",
           *logPath);
    return nullptr;
  }

  auto logger = std::make_unique<oo::log::FileWriter>(sSaturated);
  if (!logger->start(latest)) {
    OO_LOG("unclassified",
           "Log setup: could not open log at {}, will log to stdout instead.",
           *logPath);
    return nullptr;
  }
  return logger;
}

}  // namespace

// -asyncLogMessage:: the line to the writer, and the flush deadline.
namespace {

void AsyncLogMessage(std::string_view message) {
  // Don't log if saturated flag is set.
  if (sSaturated) return;

  sLogger->write(message);

  if (!sFlushPending.exchange(true)) {
    // No pending flush
    if (oo::thread::isMainThread()) {
      std::chrono::steady_clock::time_point deadline =
          std::chrono::steady_clock::now() +
          std::chrono::duration_cast<std::chrono::steady_clock::duration>(
              std::chrono::duration<double>(kFlushInterval));
      sFlushDeadline = deadline.time_since_epoch().count();
    }
  }
}

}  // namespace

namespace {

bool DirectoryExistCreatingIfNecessary(const std::string& path) {
  const oo::fs::FileType type = oo::fs::fileType(oo::fs::pathFromUTF8(path));

  if (type != oo::fs::FileType::kNone && type != oo::fs::FileType::kDirectory) {
    OO_LOG("unclassified",
           "Log setup: expected {} to be a folder, but it is a file.", path);
    return false;
  }
  if (type == oo::fs::FileType::kNone) {
    if (!oo::fs::createDirectories(oo::fs::pathFromUTF8(path))) {
      OO_LOG("unclassified", "Log setup: could not create folder {}.", path);
      return false;
    }
  }

  return true;
}

}  // namespace

/*	Foundation's -stringByAppendingPathComponent: as GNUstep 1.31.1 answers
   it on Windows for the paths used here (probed): trailing '/' and '\' of
   <base> are dropped, except a root's ("/", "C:/"), and one '/' joins; an empty
   base gives the component, "C:" gives "C:<component>". (A UNC root's separator
   is not normalised here as GNUstep does; no default path is one.)
*/
namespace {

std::string AppendPathComponent(std::string base,
                                const std::string& component) {
  if (base.empty()) return component;
  const auto isSeparator = [](char c) { return c == '/' || c == '\\'; };
  const size_t root = (base.size() >= 2 && base[1] == ':') ? 3 : 1;
  while (base.size() > root && isSeparator(base.back())) base.pop_back();
  if (base.size() == 2 && base[1] == ':') return base + component;
  if (isSeparator(base.back())) return base + component;
  return base + "/" + component;
}

}  // namespace

/*	The log directory as a UTF-8 path string, spelled as Foundation's string
   path methods spelled it: $OO_LOGSDIR as given, else <home>/Logs (Windows) or
   <home>/.Oolite/Logs (Linux), creating the directories. Cached once found;
   nullopt (and tried again next time) when a directory cannot be created.
*/
namespace {

const std::optional<std::string>& LogBasePath() {
  static std::optional<std::string> basePath;

  if (!basePath.has_value()) {
    std::string path;
    const char* logdirEnv = SDL_getenv("OO_LOGSDIR");

    if (logdirEnv) {
      path = logdirEnv;
    } else {
#if OOLITE_LINUX
      // ~/.Oolite
      path = AppendPathComponent(
          oo::fs::utf8String(oo::ResourcePaths::current().homeDirectory()),
          ".Oolite");
      if (!DirectoryExistCreatingIfNecessary(path)) return basePath;
#elif OOLITE_WINDOWS
      // <Install path>\Oolite
      path = oo::fs::utf8String(oo::ResourcePaths::current().homeDirectory());
#endif

      // .../Logs
      path = AppendPathComponent(path, "Logs");
      if (!DirectoryExistCreatingIfNecessary(path)) return basePath;
    }
    basePath = path;
  }

  return basePath;
}

}  // namespace

std::optional<std::string> OOLogHandlerGetLogBasePath() {
  return LogBasePath();
}

namespace {

std::optional<std::string> LogPath() {
  const std::optional<std::string>& base = LogBasePath();
  if (!base.has_value()) return std::nullopt;
  return AppendPathComponent(*base, LogFileName());
}

}  // namespace
