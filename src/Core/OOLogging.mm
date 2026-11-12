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

#define OOLOG_POISON_NSLOG 0

#import "OOFunctionAttributes.h"
#import "OOLogHeader.h"
#import "OOLogOutputHandler.h"
#import "OOLoggingExtended.h"
#import "OOPListParsing.h"
#import "OOPListView.h"
#import "OOStringBridge.h"
#import "ResourceManager.h"

#include "oofnd/Log.hpp"

#include <string>
#include <utility>
#include <vector>

#undef NSLog // We need to be able to call the real NSLog.

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
    @autoreleasepool {
        OOLogOutputHandlerPrint(oo::NSStringFrom(line));
    }
}

// A message class as oo::log sees it; nil prints as %@ did.
std::string ClassString(NSString* messageClass)
{
    if (messageClass == nil)
        return "(null)";
    return oo::StdString(messageClass);
}

// A logcontrol dictionary as oo::log settings, in the dictionary's enumeration order.
std::vector<std::pair<std::string, oo::log::RawSetting>> SettingsFromDictionary(NSDictionary* dict)
{
    std::vector<std::pair<std::string, oo::log::RawSetting>> entries;
    id key = nil;
    foreachkey(key, dict)
    {
        id value = [dict objectForKey:key];
        std::string name = oo::StdString([key isKindOfClass:[NSString class]] ? (NSString*)key : [key description]);
        if ([value isKindOfClass:[NSString class]]) {
            entries.emplace_back(std::move(name), oo::log::RawSetting::string(oo::StdString(value)));
        } else if ([value respondsToSelector:@selector(boolValue)]) {
            entries.emplace_back(std::move(name), oo::log::RawSetting::boolean([value boolValue]));
        } else {
            entries.emplace_back(std::move(name), oo::log::RawSetting::other(oo::StdString([value description])));
        }
    }
    return entries;
}

} // namespace

static void LoadExplicitSettings(void);

BOOL OOLogWillDisplayMessagesInClass(NSString* inMessageClass)
{
    // The hot path (every OOLog call): a class name fits the buffer, so a cached answer costs no
    // allocation and no autoreleased object.
    char buffer[128];
    if (inMessageClass != nil && [inMessageClass getCString:buffer maxLength:sizeof buffer encoding:NSUTF8StringEncoding]) {
        return oo::log::willDisplay(buffer);
    }
    return oo::log::willDisplay(ClassString(inMessageClass));
}

void OOLogSetDisplayMessagesInClass(NSString* inClass, BOOL inFlag)
{
    oo::log::logger().setDisplay(ClassString(inClass), inFlag);
}

NSString* OOLogGetParentMessageClass(NSString* inClass)
{
    NSRange range;

    if (inClass == nil)
        return nil;

    range = [inClass rangeOfString:@"." options:NSCaseInsensitiveSearch | NSLiteralSearch | NSBackwardsSearch]; // Only NSBackwardsSearch is important, others are optimizations
    if (range.location == NSNotFound)
        return nil;

    return [inClass substringToIndex:range.location];
}

#if !OOLOG_SHORT_CIRCUIT

void OOLogIndentIf(NSString* inMessageClass)
{
    if (OOLogWillDisplayMessagesInClass(inMessageClass))
        OOLogIndent();
}

void OOLogOutdentIf(NSString* inMessageClass)
{
    if (OOLogWillDisplayMessagesInClass(inMessageClass))
        OOLogOutdent();
}

#endif

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

void OOLogWithPrefix(NSString* inMessageClass, const char* inFunction, const char* inFile, unsigned long inLine, NSString* inPrefix, NSString* inFormat, ...)
{
    if (!OOLogWillDisplayMessagesInClass(inMessageClass))
        return;
    va_list args;
    va_start(args, inFormat);
    OOLogWithFunctionFileAndLineAndArguments(inMessageClass, inFunction, inFile, inLine, [inPrefix stringByAppendingString:inFormat], args);
    va_end(args);
}

void OOLogWithFunctionFileAndLine(NSString* inMessageClass, const char* inFunction, const char* inFile, unsigned long inLine, NSString* inFormat, ...)
{
    va_list args;

    va_start(args, inFormat);
    OOLogWithFunctionFileAndLineAndArguments(inMessageClass, inFunction, inFile, inLine, inFormat, args);
    va_end(args);
}

void OOLogWithFunctionFileAndLineAndArguments(NSString* inMessageClass, const char* inFunction, const char* inFile, unsigned long inLine, NSString* inFormat, va_list inArguments)
{
    if (inFormat == nil)
        return;

#if !OOLOG_SHORT_CIRCUIT
    if (!OOLogWillDisplayMessagesInClass(inMessageClass))
        return;
#endif

    @autoreleasepool {
        @try {
            // Do argument substitution; oo::log applies the prefixes, time and indentation.
            NSString* formattedMessage = [[[NSString alloc] initWithFormat:inFormat arguments:inArguments] autorelease];
            oo::log::logger().write(ClassString(inMessageClass), inFunction, inFile, inLine, oo::StdString(formattedMessage));
        }
        @catch (NSException* exception) {
            oo::log::logger().internal("OOLogWithFunctionFileAndLineAndArguments",
                oo::StdString([NSString stringWithFormat:@"***** Exception thrown during logging: %@ : %@", [exception name], [exception reason]]));
        }
    }
}

void OOLogGenericParameterErrorForFunction(const char* inFunction)
{
    OOLog(kOOLogParameterError, @"***** %s: bad parameters. (This is an internal programming error, please report it.)", inFunction);
}

void OOLogGenericSubclassResponsibilityForFunction(const char* inFunction)
{
    OOLog(kOOLogSubclassResponsibility, @"***** %s is a subclass responsibility. (This is an internal programming error, please report it.)", inFunction);
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
        [[NSUserDefaults standardUserDefaults] setBool:flag forKey:@"logging-show-function"];
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
        [[NSUserDefaults standardUserDefaults] setBool:flag forKey:@"logging-show-file-and-line"];
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
        [[NSUserDefaults standardUserDefaults] setBool:flag forKey:@"logging-show-time"];
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
        [[NSUserDefaults standardUserDefaults] setBool:flag forKey:@"logging-show-class"];
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

    @autoreleasepool {
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

NSString* const kOOLogSubclassResponsibility = @"general.error.subclassResponsibility";
NSString* const kOOLogParameterError = @"general.error.parameterError";
NSString* const kOOLogDeprecatedMethod = @"general.error.deprecatedMethod";
NSString* const kOOLogAllocationFailure = @"general.error.allocationFailure";
NSString* const kOOLogInconsistentState = @"general.error.inconsistentState";
NSString* const kOOLogException = @"exception";
NSString* const kOOLogFileNotFound = @"files.notFound";
NSString* const kOOLogFileNotLoaded = @"files.notLoaded";
NSString* const kOOLogOpenGLError = @"rendering.opengl.error";
NSString* const kOOLogUnconvertedNSLog = @"unclassified";

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
    NSUserDefaults* prefs = [NSUserDefaults standardUserDefaults];
    oo::log::Options options;
    options.showFunction = oo::PListView(prefs).get<bool>(@"logging-show-function", NO);
    options.showFileAndLine = oo::PListView(prefs).get<bool>(@"logging-show-file-and-line", NO);
    options.showTime = oo::PListView(prefs).get<bool>(@"logging-show-time", YES);
    options.showClass = oo::PListView(prefs).get<bool>(@"logging-show-class", YES);
    oo::log::logger().setOptions(options);

    /*
            HACK: we look up search paths while loading settings, which touches
            the cache, which logs stuff. To avoid spam like dataCache.retrieve.success,
            we first load the built-in logcontrol.plist only and use it while
            loading the full settings.
    */
    NSString* path = [[[ResourceManager builtInPath] stringByAppendingPathComponent:@"Config"]
        stringByAppendingPathComponent:@"logcontrol.plist"];
    oo::log::logger().replaceSettings(SettingsFromDictionary(OODictionaryFromFile(path)), false);

    // Load new settings; take out _default and _override, and invalidate the cache.
    oo::log::logger().replaceSettings(SettingsFromDictionary([ResourceManager logControlDictionary]), true);
}

/*	OOLogAbbreviatedFileName()
        Map full file paths provided by __FILE__ to more mananagable file names.
*/
NSString* OOLogAbbreviatedFileName(const char* inName)
{
    return oo::NSStringFrom(oo::log::abbreviatedFileName(inName));
}
