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


#include "OOCocoa.h"
#include "OOLogOutputHandler.h"
#include "OOLogging.h"
#include <stdlib.h>
#include <stdio.h>
#include "oofnd/Date.hpp"
#include "oofnd/Defaults.hpp"
#include "oofnd/FileSystem.hpp"
#include "oofnd/Log.hpp"
#include "oofnd/PListParsing.hpp"
#include "oofnd/LogFile.hpp"
#include "oofnd/ResourcePaths.hpp"
#include "oofnd/StdLib.hpp"
#include <SDL3/SDL_stdinc.h>
#include <atomic>
#include <chrono>
#include <memory>
#include <optional>
#include <string>
#include <thread>


/*	The Latest.log writer is oo::log::FileWriter (oofnd/LogFile.hpp, bead oo-3rb.64, proposed
	ADR-0042): the rotation to Previous.log, the writer thread, CRLF, the 1 GiB saturation and
	the flush are its, byte for byte as OOAsyncLogger did them. What stays here is the glue: the
	log directory, the logging-echo-to-stderr / stdout switches and the flush deadline of ADR-0033.
*/


#if OOLITE_MAC_OS_X

#include <dlfcn.h>

#ifndef NDEBUG

#define SET_CRASH_REPORTER_INFO 1

// Function to set "Application Specific Information" field in crash reporter log in Leopard.
// Extremely unsupported, so not used in release builds.
static void InitCrashReporterInfo(void);
static void SetCrashReporterInfo(const char *info);
static BOOL sCrashReporterInfoAvailable = NO;

#endif


typedef void (*LogCStringFunctionProc)(const char *string, unsigned length, BOOL withSyslogBanner);
typedef LogCStringFunctionProc (*LogCStringFunctionGetterProc)(void);
typedef void (*LogCStringFunctionSetterProc)(LogCStringFunctionProc);

static LogCStringFunctionGetterProc _NSLogCStringFunction = NULL;
static LogCStringFunctionSetterProc _NSSetLogCStringFunction = NULL;

static void LoadLogCStringFunctions(void);
static void OONSLogCStringFunction(const char *string, unsigned length, BOOL withSyslogBanner);

static std::string GetAppName(void);

static LogCStringFunctionProc	sDefaultLogCStringFunction = NULL;

#elif !OOLITE_GNUSTEP
#error Unknown platform!
#endif

namespace {

bool DirectoryExistCreatingIfNecessary(const std::string &path);
const std::optional<std::string> &LogBasePath(void);
std::optional<std::string> LogPath(void);
std::string AppendPathComponent(std::string base, const std::string &component);
std::unique_ptr<oo::log::FileWriter> StartLogger(void);
void AsyncLogMessage(std::string_view message);

}	// namespace


#define kFlushInterval	2.0		// Lower bound on interval between explicit log file flushes.


static BOOL						sInited = NO;
static BOOL						sWriteToStderr = YES;
static BOOL						sWriteToStdout = NO;

namespace {

std::atomic<bool>				sSaturated{false};
std::unique_ptr<oo::log::FileWriter> sLogger;
const char * const				kDefaultLogFileName = "Latest.log";
std::string						sLogFileName;	// empty until first set: kDefaultLogFileName

}	// namespace

/*	The pending flush (was a one-shot run-loop timer, proposed ADR-0033): a deadline on
	std::chrono::steady_clock that the frame loop checks. The timer was
	scheduled on the logging thread's run loop, and only the main thread's run
	loop ever runs, so a flush first requested from another thread never fired
	and blocked later ones; kFlushNever keeps that.
*/
namespace {

const int64_t						kFlushNever = INT64_MAX;
std::atomic<bool>					sFlushPending{false};
std::atomic<int64_t>				sFlushDeadline{kFlushNever};	// steady_clock ticks since its epoch
std::thread::id						sMainThreadID;

}	// namespace


void OOLogOutputHandlerInit(void)
{
	if (sInited)  return;

#if SET_CRASH_REPORTER_INFO
	InitCrashReporterInfo();
#endif

	sMainThreadID = std::this_thread::get_id();
	sLogger = StartLogger();
	sInited = YES;

	if (sLogger != nullptr)
	{
		sWriteToStderr = oo::Defaults::standard().boolForKey("logging-echo-to-stderr");
	}
	else
	{
		sWriteToStderr = YES;
	}

#if OOLITE_MAC_OS_X
	LoadLogCStringFunctions();
	if (_NSSetLogCStringFunction != NULL)
	{
		sDefaultLogCStringFunction = _NSLogCStringFunction();
		_NSSetLogCStringFunction(OONSLogCStringFunction);
	}
	else
	{
		OO_LOG("logging.nsLogFilter.install.failed", "{}", "Failed to install Foundation log filter; system messages will not be logged in log file.");
	}
#endif

	atexit(OOLogOutputHandlerClose);
}


namespace {

// -endLogging's postamble.
std::string Postamble(void)
{
	return "\nClosing log at " + oo::date::description() + ".";
}


const std::string &LogFileName(void)
{
	if (sLogFileName.empty())  sLogFileName = kDefaultLogFileName;
	return sLogFileName;
}

}	// namespace


void OOLogOutputHandlerClose(void)
{
	if (sInited)
	{
		sWriteToStderr = YES;
		sInited = NO;

		if (sLogger != nullptr)  sLogger->end(Postamble());
		sLogger.reset();

#if OOLITE_MAC_OS_X
		if (sDefaultLogCStringFunction != NULL && _NSSetLogCStringFunction != NULL)
		{
			_NSSetLogCStringFunction(sDefaultLogCStringFunction);
			sDefaultLogCStringFunction = NULL;
		}
#endif
	}
}

void OOLogOutputHandlerStartLoggingToStdout()
{
	sWriteToStdout = true;
}
void OOLogOutputHandlerStopLoggingToStdout()
{
	sWriteToStdout = false;
}

void OOLogOutputHandlerFlushIfDue(void)
{
	if (!sFlushPending || sLogger == nullptr)  return;
	if (std::chrono::steady_clock::now().time_since_epoch().count() < sFlushDeadline)  return;
	sFlushDeadline = kFlushNever;
	sFlushPending = false;
	sLogger->flush();
}


void OOLogOutputHandlerPrintLine(std::string_view line)
{
	if (sInited && sLogger != nullptr && !sWriteToStdout)  AsyncLogMessage(line);

	BOOL doCStringStuff = sWriteToStderr || sWriteToStdout;
#if SET_CRASH_REPORTER_INFO
	doCStringStuff = doCStringStuff || sCrashReporterInfoAvailable;
#endif

	if (doCStringStuff)
	{
		const std::string cStr = oo::log::consoleBytes(line);
		if (sWriteToStdout)
			fputs(cStr.c_str(), stdout);
		else if (sWriteToStderr)
			fputs(cStr.c_str(), stderr);

#if SET_CRASH_REPORTER_INFO
		if (sCrashReporterInfoAvailable)  SetCrashReporterInfo(cStr.c_str());
#endif
	}

}


std::optional<std::string> cxx_OOLogHandlerGetLogPath(void)
{
	return LogPath();
}


void cxx_OOLogOutputHandlerChangeLogFile(const std::string &name)
{
	if (LogFileName() != name)
	{
		sLogFileName = name;
		if (sLogger != nullptr)
		{
			// -changeFile: end this file (postamble), start the new one (no rotation).
			sLogger->end(Postamble());
			std::optional<std::string> path = LogPath();
			if (!path.has_value() || !sLogger->start(oo::fs::pathFromUTF8(*path)))
			{
				if (path.has_value())  OO_LOG("unclassified", "Log setup: could not open log at {}, will log to stdout instead.", *path);
				sWriteToStderr = YES;
			}
		}
	}
}


/*	-[OOAsyncLogger init] and -startLogging: move an existing log to Previous.log, create the
	new one and start the writer. nullptr when that fails; the handler then logs to stderr.
*/
namespace {

std::unique_ptr<oo::log::FileWriter> StartLogger(void)
{
	std::optional<std::string> logPath = LogPath();
	if (!logPath.has_value())  return nullptr;

	const oo::fs::Path latest = oo::fs::pathFromUTF8(*logPath);
	const oo::fs::Path previous = oo::fs::pathFromUTF8(AppendPathComponent(*LogBasePath(), "Previous.log"));
	if (!oo::log::rotateToPrevious(latest, previous))
	{
		OO_LOG("unclassified", "Log setup: could not move or delete existing log at {}, will log to stdout instead.", *logPath);
		return nullptr;
	}

	auto logger = std::make_unique<oo::log::FileWriter>(sSaturated);
	if (!logger->start(latest))
	{
		OO_LOG("unclassified", "Log setup: could not open log at {}, will log to stdout instead.", *logPath);
		return nullptr;
	}
	return logger;
}

}	// namespace


// -asyncLogMessage:: the line to the writer, and the flush deadline.
namespace {

void AsyncLogMessage(std::string_view message)
{
	// Don't log if saturated flag is set.
	if (sSaturated)  return;

	sLogger->write(message);

	if (!sFlushPending.exchange(true))
	{
		// No pending flush
		if (std::this_thread::get_id() == sMainThreadID)
		{
			std::chrono::steady_clock::time_point deadline = std::chrono::steady_clock::now() + std::chrono::duration_cast<std::chrono::steady_clock::duration>(std::chrono::duration<double>(kFlushInterval));
			sFlushDeadline = deadline.time_since_epoch().count();
		}
	}
}

}	// namespace


#if OOLITE_MAC_OS_X

/*	LoadLogCStringFunctions()
	
	We wish to make NSLogv() call our custom function OONSLogCStringFunction()
	rather than printing to stdout, by calling _NSSetLogCStringFunction().
	Additionally, in order to close the logger cleanly, we wish to be able to
	restore the standard logger, which requires us to call
	_NSLogCStringFunction(). These functions are private.
	_NSLogCStringFunction() is undocumented. _NSSetLogCStringFunction() is
	documented at http://docs.info.apple.com/article.html?artnum=70081 ,
	with the warning:
	
		Be aware that this code references private APIs; this is an
		unsupported workaround and users should use these instructions at
		their own risk. Apple will not guarantee or provide support for
		this procedure.
	
	The approach taken here is to load the functions dynamically. This makes
	us safe in the case of Apple removing the functions. In the unlikely event
	that they change the functions' paramters without renaming them, we would
	have a problem.
*/
static void LoadLogCStringFunctions(void)
{
	CFBundleRef						foundationBundle = NULL;
	LogCStringFunctionGetterProc	getter = NULL;
	LogCStringFunctionSetterProc	setter = NULL;
	
	foundationBundle = CFBundleGetBundleWithIdentifier(CFSTR("com.apple.Foundation"));
	if (foundationBundle != NULL)
	{
		getter = CFBundleGetFunctionPointerForName(foundationBundle, CFSTR("_NSLogCStringFunction"));
		setter = CFBundleGetFunctionPointerForName(foundationBundle, CFSTR("_NSSetLogCStringFunction"));
		
		if (getter != NULL && setter != NULL)
		{
			_NSLogCStringFunction = getter;
			_NSSetLogCStringFunction = setter;
		}
	}
}


static void OONSLogCStringFunction(const char *string, unsigned length, BOOL withSyslogBanner)
{
	if (oo::log::willDisplay("system"))
	{
		oo::log::logger().write("system", NULL, NULL, 0, string != NULL ? string : "(null)");
	}
}

#endif



namespace {

bool DirectoryExistCreatingIfNecessary(const std::string &path)
{
	const oo::fs::FileType type = oo::fs::fileType(oo::fs::pathFromUTF8(path));

	if (type != oo::fs::FileType::none && type != oo::fs::FileType::directory)
	{
		OO_LOG("unclassified", "Log setup: expected {} to be a folder, but it is a file.", path);
		return false;
	}
	if (type == oo::fs::FileType::none)
	{
		if (!oo::fs::createDirectories(oo::fs::pathFromUTF8(path)))
		{
			OO_LOG("unclassified", "Log setup: could not create folder {}.", path);
			return false;
		}
	}

	return true;
}

}	// namespace


#if OOLITE_MAC_OS_X
static void ExcludeFromTimeMachine(const std::string &path)
{
	OSStatus (*CSBackupSetItemExcluded)(NSURL *item, Boolean exclude, Boolean excludeByPath) = NULL;
	CFBundleRef carbonCoreBundle = CFBundleGetBundleWithIdentifier(CFSTR("com.apple.CoreServices.CarbonCore"));
	if (carbonCoreBundle)
	{
		CSBackupSetItemExcluded = CFBundleGetFunctionPointerForName(carbonCoreBundle, CFSTR("CSBackupSetItemExcluded"));
		if (CSBackupSetItemExcluded != NULL)
		{
			(void)CSBackupSetItemExcluded([NSURL fileURLWithPath:oo::NSStringFrom(path)], YES, NO);
		}
	}
}

static std::string GetAppName(void)
{
	static std::optional<std::string>	appName;

	if (!appName.has_value())
	{
		const oo::fs::Path plistPath = oo::ResourcePaths::current().builtInResourcesDirectory() / "Info-gnustep.plist";
		oo::PList info;
		if (const oo::fs::Result<oo::Data> bytes = oo::fs::readFile(plistPath); bytes && !bytes->empty())
		{
			if (oo::Expected<oo::PList, oo::PListError> parsed = oo::parsePropertyList(bytes->stringView());
			    parsed && parsed->isDict())
				info = std::move(*parsed);
		}
		if (const oo::PList *name = info.find("CFBundleName"); name && name->isString())
			appName = *name->getIf<std::string>();
		if (!appName.has_value())
		{
			if (const oo::PList *ident = info.find("CFBundleIdentifier"); ident && ident->isString())
				appName = *ident->getIf<std::string>();
		}
		if (!appName.has_value())  appName = "<unknown application>";
	}

	return *appName;
}
#endif

/*	Foundation's -stringByAppendingPathComponent: as GNUstep 1.31.1 answers it on Windows for the
	paths used here (probed): trailing '/' and '\' of <base> are dropped, except a root's ("/",
	"C:/"), and one '/' joins; an empty base gives the component, "C:" gives "C:<component>".
	(A UNC root's separator is not normalised here as GNUstep does; no default path is one.)
*/
namespace {

std::string AppendPathComponent(std::string base, const std::string &component)
{
	if (base.empty())  return component;
	const auto isSeparator = [](char c) { return c == '/' || c == '\\'; };
	const size_t root = (base.size() >= 2 && base[1] == ':') ? 3 : 1;
	while (base.size() > root && isSeparator(base.back()))  base.pop_back();
	if (base.size() == 2 && base[1] == ':')  return base + component;
	if (isSeparator(base.back()))  return base + component;
	return base + "/" + component;
}

}	// namespace


/*	The log directory as a UTF-8 path string, spelled as Foundation's string path methods spelled it:
	$OO_LOGSDIR as given, else <home>/Logs (Windows) or <home>/.Oolite/Logs (Linux), creating the
	directories. Cached once found; nullopt (and tried again next time) when a directory cannot
	be created.
*/
namespace {

const std::optional<std::string> &LogBasePath(void)
{
	static std::optional<std::string> basePath;

	if (!basePath.has_value())
	{
		std::string path;
		const char *logdirEnv = SDL_getenv("OO_LOGSDIR");

		if (logdirEnv)
		{
			path = logdirEnv;
		}
		else
		{
#if OOLITE_MAC_OS_X
			// ~/Library
			path = oo::StdString([NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES) objectAtIndex:0]);
#elif OOLITE_LINUX
			// ~/.Oolite
			path = AppendPathComponent(oo::fs::utf8String(oo::ResourcePaths::current().homeDirectory()), ".Oolite");
			if (!DirectoryExistCreatingIfNecessary(path))  return basePath;
#elif OOLITE_WINDOWS
			// <Install path>\Oolite
			path = oo::fs::utf8String(oo::ResourcePaths::current().homeDirectory());
#endif

			// .../Logs
			path = AppendPathComponent(path, "Logs");
			if (!DirectoryExistCreatingIfNecessary(path))  return basePath;

#if OOLITE_MAC_OS_X
			// ~/Library/Logs/Oolite
			path = AppendPathComponent(path, GetAppName());
			if (!DirectoryExistCreatingIfNecessary(path))  return basePath;
#endif
		}
#if OOLITE_MAC_OS_X
		ExcludeFromTimeMachine(path);
#endif
		basePath = path;
	}

	return basePath;
}

}	// namespace


std::optional<std::string> cxx_OOLogHandlerGetLogBasePath(void)
{
	return LogBasePath();
}


namespace {

std::optional<std::string> LogPath(void)
{
	const std::optional<std::string> &base = LogBasePath();
	if (!base.has_value())  return std::nullopt;
	return AppendPathComponent(*base, LogFileName());
}

}	// namespace


#if SET_CRASH_REPORTER_INFO

static char **sCrashReporterInfo = NULL;
static char *sOldCrashReporterInfo = NULL;
static std::mutex sCrashReporterInfoLock;

// Evil hackery based on http://www.allocinit.net/blog/2008/01/04/application-specific-information-in-leopard-crash-reports/
static void InitCrashReporterInfo(void)
{
	sCrashReporterInfo = dlsym(RTLD_DEFAULT, "__crashreporter_info__");
	if (sCrashReporterInfo != NULL)
	{
		sCrashReporterInfoAvailable = YES;
	}
}

static void SetCrashReporterInfo(const char *info)
{
	char					*copy = NULL, *old = NULL;
	
	/*	Don't do anything if setup failed or the string is NULL or empty.
		(The NULL and empty checks may not be desirable in other uses.)
	*/
	if (!sCrashReporterInfoAvailable || info == NULL || *info == '\0')  return;
	
	// Copy the string, which we assume to be dynamic...
	copy = strdup(info);
	if (copy == NULL)  return;
	
	/*	...and swap it in.
		Note that we keep a separate pointer to the old value, in case
		something else overwrites __crashreporter_info__.
	*/
	sCrashReporterInfoLock.lock();
	*sCrashReporterInfo = copy;
	old = sOldCrashReporterInfo;
	sOldCrashReporterInfo = copy;
	sCrashReporterInfoLock.unlock();
	
	// Delete our old string.
	if (old != NULL)  free(old);
}

#endif
