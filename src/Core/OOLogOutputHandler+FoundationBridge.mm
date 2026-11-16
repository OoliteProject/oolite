/*

OOLogOutputHandler+FoundationBridge.mm

TRANSITIONAL: see OOLogOutputHandler+FoundationBridge.h. The NSLog hook moved here unchanged from
OOLogOutputHandler.mm. Foundation-typed forwarders were removed by oo-vors.

*/

#import "OOLogOutputHandler.h" // declares the bridge at its end
#import "OOLogging.h"

#if OOLITE_GNUSTEP

namespace {

void OONSLogPrintfHandler(NSString* message)
{
    if (OOLogWillDisplayMessagesInClass(@"gnustep")) {
        OOLogWithFunctionFileAndLine(@"gnustep", NULL, NULL, 0, @"%@", message);
    }
}

} // namespace

#endif

void OOLogOutputHandlerInstallNSLogHook(void)
{
#if OOLITE_GNUSTEP
    // gnustep-base's own NSLog lock, not ours to replace: it goes with the NSLog hook (oo-qps).
    [GSLogLock() lock];
    _NSLog_printf_handler = OONSLogPrintfHandler;
    [GSLogLock() unlock];
#endif
}

void OOLogOutputHandlerRemoveNSLogHook(void)
{
#if OOLITE_GNUSTEP
    [GSLogLock() lock];
    _NSLog_printf_handler = NULL;
    [GSLogLock() unlock];
#endif
}
