/*

OOLogging.m


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

#include "OOFunctionAttributes.h"
#include "OOLogHeader.h"
#include "OOLogOutputHandler.h"
#include "OOLoggingExtended.h"
#include "OOPListParsing.h"
#include "ResourceManager.h"

#include "oofnd/Defaults.hpp"
#include "oofnd/Log.hpp"

#include "oofnd/String.hpp"
#include <string>
#include <utility>
#include <vector>

/*	The message-class settings, their resolution and cache, per-thread indentation, the line
        layout and OOLogging's own diagnostics live in oofnd/Log.hpp (oo::log, bead oo-qpb), shared
        with the std::format call sites (OO_LOG). What stays here is Objective-C: reading
        logcontrol.plist and the logging-show-* defaults, formatting %@ messages, and the sink that
        hands finished lines to OOLogOutputHandler.
*/

static BOOL sInited = NO;

namespace {

// Finished lines go to the output handler (Latest.log, stderr). Installed by OOLoggingInit();
// before it oo::log writes to stderr, which is what the output handler did before its init.
void LogSink(std::string_view line)
{
    OOLogOutputHandlerPrintLine(line);
}

// A logcontrol dictionary as oo::log settings, in the dictionary's key order (byte order; was
// hash order).
std::vector<std::pair<std::string, oo::log::RawSetting>> SettingsFromDictionary(const oo::PList& dict)
{
    std::vector<std::pair<std::string, oo::log::RawSetting>> entries;
    const oo::PList::Dict* settings = dict.getIf<oo::PList::Dict>();
    if (settings == nullptr)
        return entries;
    entries.reserve(settings->size());
    for (const auto& [name, value] : *settings) {
        if (const std::string* text = value.getIf<std::string>()) {
            entries.emplace_back(name, oo::log::RawSetting::string(*text));
        } else if (value.isNumber()) {
            // -boolValue
            entries.emplace_back(name, oo::log::RawSetting::boolean(value.boolValue()));
        } else {
            // the text %@ printed
            entries.emplace_back(name, oo::log::RawSetting::other(oo::DescriptionOf(value)));
        }
    }
    return entries;
}

} // namespace

static void LoadExplicitSettings(void);

void OOLogPushIndent(void)
{
    oo::log::pushIndent();
}

void OOLogPopIndent(void)
{
    oo::log::popIndent();
}

void OOLogIndent(void)
{
    oo::log::indent();
}

void OOLogOutdent(void)
{
    oo::log::outdent();
}

void OOLogGenericParameterErrorForFunction(const char* inFunction)
{
    OO_LOG(cxx_kOOLogParameterError, "***** {}: bad parameters. (This is an internal programming error, please report it.)", inFunction != NULL ? inFunction : "(null)");
}

void OOLogGenericSubclassResponsibilityForFunction(const char* inFunction)
{
    OO_LOG(cxx_kOOLogSubclassResponsibility, "***** {} is a subclass responsibility. (This is an internal programming error, please report it.)", inFunction != NULL ? inFunction : "(null)");
}

BOOL OOLogShowFunction(void)
{
    return oo::log::logger().options().showFunction;
}

void OOLogSetShowFunction(BOOL flag)
{
    flag = !!flag; // YES or NO, not 42.

    oo::log::Options options = oo::log::logger().options();
    if (flag != options.showFunction) {
        options.showFunction = flag;
        oo::log::logger().setOptions(options);
        oo::Defaults::standard().setBool("logging-show-function", flag);
    }
}

BOOL OOLogShowFileAndLine(void)
{
    return oo::log::logger().options().showFileAndLine;
}

void OOLogSetShowFileAndLine(BOOL flag)
{
    flag = !!flag; // YES or NO, not 42.

    oo::log::Options options = oo::log::logger().options();
    if (flag != options.showFileAndLine) {
        options.showFileAndLine = flag;
        oo::log::logger().setOptions(options);
        oo::Defaults::standard().setBool("logging-show-file-and-line", flag);
    }
}

BOOL OOLogShowTime(void)
{
    return oo::log::logger().options().showTime;
}

void OOLogSetShowTime(BOOL flag)
{
    flag = !!flag; // YES or NO, not 42.

    oo::log::Options options = oo::log::logger().options();
    if (flag != options.showTime) {
        options.showTime = flag;
        oo::log::logger().setOptions(options);
        oo::Defaults::standard().setBool("logging-show-time", flag);
    }
}

BOOL OOLogShowMessageClass(void)
{
    return oo::log::logger().options().showClass;
}

void OOLogSetShowMessageClass(BOOL flag)
{
    flag = !!flag; // YES or NO, not 42.

    oo::log::Options options = oo::log::logger().options();
    if (flag != options.showClass) {
        options.showClass = flag;
        oo::log::logger().setOptions(options);
        oo::Defaults::standard().setBool("logging-show-class", flag);
    }
}

void OOLogSetShowMessageClassTemporary(BOOL flag)
{
    oo::log::logger().setShowClassTemporarily(flag);
}

void OOLoggingInit(void)
{
    if (sInited)
        return;

    {
        sInited = YES; // Must be before OOLogOutputHandlerInit().
        oo::log::logger().setSink(LogSink);
        oo::log::logger().setInitialized(true);
        OOLogOutputHandlerInit();

        OOPrintLogHeader();

        LoadExplicitSettings();
    }
}

void OOLoggingTerminate(void)
{
    if (!sInited)
        return;

    OOLogOutputHandlerClose();

    /*	We do not set sInited to NO. Instead, the output handler is required
            to be able to handle working even after being closed. Under OS X, this
            is done by writing to stderr in this case; on other platforms, NSLog()
            is used and OOLogOutputHandlerClose() is a no-op.
    */
}

void OOLoggingReloadSettings(void)
{
    LoadExplicitSettings();
}

void OOLogInsertMarker(void)
{
    oo::log::logger().insertMarker();
}

const char* const cxx_kOOLogSubclassResponsibility = "general.error.subclassResponsibility";
const char* const cxx_kOOLogParameterError = "general.error.parameterError";
const char* const cxx_kOOLogDeprecatedMethod = "general.error.deprecatedMethod";
const char* const cxx_kOOLogAllocationFailure = "general.error.allocationFailure";
const char* const cxx_kOOLogInconsistentState = "general.error.inconsistentState";
const char* const cxx_kOOLogException = "exception";
const char* const cxx_kOOLogFileNotFound = "files.notFound";
const char* const cxx_kOOLogFileNotLoaded = "files.notLoaded";
const char* const cxx_kOOLogOpenGLError = "rendering.opengl.error";
const char* const cxx_kOOLogUnconvertedNSLog = "unclassified";

/*	LoadExplicitSettings()
        Read settings from logcontrol.plists, merge in settings from preferences.

        Log settings are loaded from the following locations, from lowest to
        highest priority:
                * logcontrol.plist inside OXPs, but only in hierarchies not defined
                  by the built-in plist.
                * Built-in logcontrol.plist.
                * Loose logcontrol.plist files in AddOns folders.
                * Preferences (settable through the debug console).

        Because the settings are loaded very early (OOLoggingInit() time), before
        the state of strict mode has been set, OXP settings are always loaded.
        Since these generally shouldn't have any effect in strict mode, that's
        fine.
*/
static void LoadExplicitSettings(void)
{
    // Load display settings.
    oo::Defaults& prefs = oo::Defaults::standard();
    oo::log::Options options;
    options.showFunction = prefs.object("logging-show-function").isNull() ? NO : prefs.boolForKey("logging-show-function");
    options.showFileAndLine = prefs.object("logging-show-file-and-line").isNull() ? NO : prefs.boolForKey("logging-show-file-and-line");
    options.showTime = prefs.object("logging-show-time").isNull() ? YES : prefs.boolForKey("logging-show-time");
    options.showClass = prefs.object("logging-show-class").isNull() ? YES : prefs.boolForKey("logging-show-class");
    oo::log::logger().setOptions(options);

    /*
            HACK: we look up search paths while loading settings, which touches
            the cache, which logs stuff. To avoid spam like dataCache.retrieve.success,
            we first load the built-in logcontrol.plist only and use it while
            loading the full settings.
    */
    // (no built-in path: no path, so no settings, as messaging nil gave)
    const std::optional<std::string> builtInPath = ResourceManager::builtInPath();
    oo::PList builtInSettings;
    if (builtInPath.has_value()) {
        const std::string path = oo::str::appendingPathComponent(oo::str::appendingPathComponent(*builtInPath, "Config"), "logcontrol.plist");
        builtInSettings = cxx_OOPropertyListFromFile(path);
        if (!builtInSettings.isDict())
            builtInSettings = oo::PList(); // a dictionary or nothing, as OODictionaryFromFile answered (its plist.wrongType line, which named the Foundation class, is not kept)
    }
    oo::log::logger().replaceSettings(SettingsFromDictionary(builtInSettings), false);

    // Load new settings; take out _default and _override, and invalidate the cache.
    oo::log::logger().replaceSettings(SettingsFromDictionary(ResourceManager::logControlDictionary()), true);
}
