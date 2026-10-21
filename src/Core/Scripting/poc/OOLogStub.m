/*

OOLogStub.m

Minimal OOLogging implementation for the QuickJS-ng proof-of-concept
harness. Messages are printed in Oolite's log format and recorded so tests
can check what was logged.

*/

#import "OOLogging.h"

static NSMutableArray* sRecordedMessages;

NSArray* OOPocRecordedLogMessages(void)
{
    return sRecordedMessages;
}

void OOPocClearRecordedLogMessages(void)
{
    [sRecordedMessages removeAllObjects];
}

BOOL OOLogWillDisplayMessagesInClass(NSString* inMessageClass)
{
    return YES;
}

void OOLogIndent(void) { }
void OOLogOutdent(void) { }
void OOLogPushIndent(void) { }
void OOLogPopIndent(void) { }

void OOLogWithFunctionFileAndLineAndArguments(NSString* inMessageClass, const char* inFunction, const char* inFile, unsigned long inLine, NSString* inFormat, va_list inArguments)
{
    NSString* message = [[[NSString alloc] initWithFormat:inFormat arguments:inArguments] autorelease];
    NSString* line = [NSString stringWithFormat:@"[%@]: %@", inMessageClass, message];

    if (sRecordedMessages == nil)
        sRecordedMessages = [[NSMutableArray alloc] init];
    [sRecordedMessages addObject:line];

    fprintf(stdout, "%s\n", [line UTF8String]);
    fflush(stdout);
}

void OOLogWithFunctionFileAndLine(NSString* inMessageClass, const char* inFunction, const char* inFile, unsigned long inLine, NSString* inFormat, ...)
{
    va_list args;
    va_start(args, inFormat);
    OOLogWithFunctionFileAndLineAndArguments(inMessageClass, inFunction, inFile, inLine, inFormat, args);
    va_end(args);
}

void OOLogWithPrefix(NSString* inMessageClass, const char* inFunction, const char* inFile, unsigned long inLine, NSString* inPrefix, NSString* inFormat, ...)
{
    va_list args;
    va_start(args, inFormat);
    NSString* format = [inPrefix stringByAppendingString:inFormat];
    OOLogWithFunctionFileAndLineAndArguments(inMessageClass, inFunction, inFile, inLine, format, args);
    va_end(args);
}

void OOLogGenericParameterErrorForFunction(const char* inFunction)
{
    OOLog(kOOLogParameterError, @"***** %s: bad parameters. (This is an internal programming error, please report it.)", inFunction);
}

void OOLogGenericSubclassResponsibilityForFunction(const char* inFunction)
{
    OOLog(kOOLogSubclassResponsibility, @"***** %s is a subclass responsibility. (This is an internal programming error, please report it.)", inFunction);
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
