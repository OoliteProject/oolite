/*

OOLogging+FoundationBridge.mm

TRANSITIONAL: see OOLogging+FoundationBridge.h. The Foundation half of OOLogging, moved here
verbatim from OOLogging.mm: the NSString message-class entry points and the %@ formatting
(-initWithFormat:arguments:), handing finished text to oo::log as before, and the kOOLog* NSString
constants (the same text as their cxx_kOOLog* twins in OOLogging.mm).

*/

#import "OOFoundationException.h"
#import "OOLoggingExtended.h" // OOLogging.h, which declares the bridge at its end
#import "OOStringBridge.h"

#include "oofnd/Log.hpp"

#include <string>

namespace {

// A message class as oo::log sees it; nil prints as %@ did.
std::string ClassString(NSString* messageClass)
{
    if (messageClass == nil)
        return "(null)";
    return oo::StdString(messageClass);
}

} // namespace

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
        @catch (OOException* exception) {
            oo::log::logger().internal("OOLogWithFunctionFileAndLineAndArguments",
                oo::StdString([NSString stringWithFormat:@"***** Exception thrown during logging: %@ : %@", oo::NSStringFrom([exception name]), oo::NSStringFrom([exception reason])]));
        }
        @catch (OOFoundationException* exception) {
            oo::log::logger().internal("OOLogWithFunctionFileAndLineAndArguments",
                oo::StdString([NSString stringWithFormat:@"***** Exception thrown during logging: %@ : %@", [exception name], [exception reason]]));
        }
    }
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

/*	OOLogAbbreviatedFileName()
        Map full file paths provided by __FILE__ to more mananagable file names.
*/
NSString* OOLogAbbreviatedFileName(const char* inName)
{
    return oo::NSStringFrom(oo::log::abbreviatedFileName(inName));
}
