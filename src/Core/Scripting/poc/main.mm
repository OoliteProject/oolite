/*

main.m

Test driver for the QuickJS-ng proof of concept (issue #580). Loads scripts
from the tests directory given on the command line, checks their behaviour
and the engine's error reporting, then destroys the runtime; debug builds of
QuickJS abort if any JS object has leaked.

Usage: oojs-quickjs-poc <tests directory>

*/

#import "OOJSScript.h"
#import "OOJavaScriptEngine.h"
#import "legacy_random.h"

#include <time.h>

NSArray* OOPocRecordedLogMessages(void);
void OOPocClearRecordedLogMessages(void);

static unsigned sFailures = 0;
static unsigned sChecks = 0;

static void Check(BOOL condition, NSString* description)
{
    sChecks++;
    if (!condition) {
        sFailures++;
        fprintf(stdout, "FAIL: %s\n", [description UTF8String]);
    } else {
        fprintf(stdout, "ok:   %s\n", [description UTF8String]);
    }
    fflush(stdout);
}

static BOOL LogContains(NSString* text)
{
    for (NSString* line in OOPocRecordedLogMessages()) {
        if ([line rangeOfString:text].location != NSNotFound)
            return YES;
    }
    return NO;
}

static double Now(void)
{
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    return now.tv_sec + now.tv_nsec * 1e-9;
}

// Call a script method and convert its result to a string; nil if the call failed.
static NSString* CallForString(OOJSScript* script, NSString* method)
{
    JSContext* context = OOJSAcquireContext();
    JSValue result;
    NSString* string = nil;

    if ([script callMethodNamed:method withArguments:NULL count:0 result:&result]) {
        string = OOStringFromJSValueEvenIfNull(context, result);
        JS_FreeValue(context, result);
    }
    return string;
}

static void RunBehaviourTests(NSString* testDir, NSString* fileName)
{
    OOJSScript* script = [OOJSScript scriptWithPath:[testDir stringByAppendingPathComponent:fileName]];
    Check(script != nil, [NSString stringWithFormat:@"%@ loads", fileName]);

    NSString* failures = CallForString(script, @"runTests");
    Check([failures isEqualToString:@"0"], [NSString stringWithFormat:@"%@ behaviour tests pass (failures: %@)", fileName, failures]);
}

static void RunScopeTests(NSString* testDir)
{
    OOJSScript* scriptA = [OOJSScript scriptWithPath:[testDir stringByAppendingPathComponent:@"scope_a.js"]];
    OOJSScript* scriptB = [OOJSScript scriptWithPath:[testDir stringByAppendingPathComponent:@"scope_b.js"]];
    Check(scriptA != nil && scriptB != nil, @"scripts with the same top-level const and var names both load");
    Check([[scriptA displayName] isEqualToString:@"poc_scope_a 1.2"], @"script name and version read after initial run");

    NSString* result = CallForString(scriptA, @"startUp");
    NSString* expected = @"1|ab..|poc_scope_a|1.2|a|a|undefined|late|strict|poc_scope_a";
    Check([result isEqualToString:expected], [NSString stringWithFormat:@"bare names resolve through the script object, strict mode kept (got %@)", result]);

    result = CallForString(scriptB, @"check");
    Check([result isEqualToString:@"bbpoc_scope_b"], [NSString stringWithFormat:@"second script sees its own top-level declarations (got %@)", result]);
}

static void RunErrorTests(NSString* testDir)
{
    OOPocClearRecordedLogMessages();
    OOJSScript* script = [OOJSScript scriptWithPath:[testDir stringByAppendingPathComponent:@"runtime_error.js"]];
    Check(CallForString(script, @"startUp") == nil, @"handler that throws reports failure");
    Check(LogContains(@"[script.javaScript.exception.ReferenceError]: ***** JavaScript exception (poc_runtime_error): ReferenceError: undefinedFunction is not defined"), @"runtime exception logged with class, script name and message");
    Check(LogContains(@"runtime_error.js, line 9."), @"runtime exception logged with correct file and line");

    OOPocClearRecordedLogMessages();
    script = [OOJSScript scriptWithPath:[testDir stringByAppendingPathComponent:@"syntax_error.js"]];
    Check(script == nil, @"script with syntax error fails to load");
    Check(LogContains(@"[script.javaScript.exception.SyntaxError]"), @"syntax error logged");
    Check(LogContains(@"syntax_error.js, line "), @"syntax error logged with file and line");
}

static void RunTimeLimiterTests(NSString* testDir)
{
    OOPocClearRecordedLogMessages();
    OOJSScript* script = [OOJSScript scriptWithPath:[testDir stringByAppendingPathComponent:@"runaway.js"]];

    double start = Now();
    NSString* result = CallForString(script, @"startUp");
    double elapsed = Now() - start;

    Check(result == nil, @"infinite loop is terminated");
    Check(elapsed >= 1.0 && elapsed < 3.0, [NSString stringWithFormat:@"termination after the 1 second limit (took %.2f s)", elapsed]);
    Check(LogContains(@"Script \"poc_runaway\" ran for"), @"termination logged");
    Check(!LogContains(@"JavaScript exception"), @"termination not also reported as an exception");
    Check([CallForString(script, @"ping") isEqualToString:@"pong"], @"engine still usable after termination");
}

int main(int argc, const char* argv[])
{
    if (argc < 2) {
        fprintf(stderr, "Usage: %s <tests directory>\n", argv[0]);
        return 2;
    }

    NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
    NSString* testDir = [NSString stringWithUTF8String:argv[1]];

    // As the game does at startup; an unseeded RANROT returns 0 forever.
    ranrot_srand((uint32_t)time(NULL));
    OOJavaScriptEngine* engine = [OOJavaScriptEngine sharedEngine];

    // Each group gets its own pool so all scripts are released before shutdown.
    NSAutoreleasePool* testPool = [[NSAutoreleasePool alloc] init];
    RunBehaviourTests(testDir, @"vector.js");
    RunBehaviourTests(testDir, @"quaternion.js");
    RunScopeTests(testDir);
    RunErrorTests(testDir);
    RunTimeLimiterTests(testDir);
    [testPool release];

    NSUInteger leaked = [engine shutDown];
    Check(leaked == 0, [NSString stringWithFormat:@"runtime destroyed with no leaked objects (%lu alive)", (unsigned long)leaked]);

    fprintf(stdout, "\n%u checks, %u failures\n", sChecks, sFailures);
    [pool release];
    return sFailures == 0 ? 0 : 1;
}
