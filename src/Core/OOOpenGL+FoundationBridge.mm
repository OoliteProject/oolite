/*

OOOpenGL+FoundationBridge.mm

TRANSITIONAL: see OOOpenGL+FoundationBridge.h. OOCheckOpenGLErrors() forwards to the function
form of cxx_OOCheckOpenGLErrors with a context that formats the %@ format and its arguments with
-initWithFormat:arguments: (nil reads "<unknown>"), only when an error is found, so the callers
stay as lazy and their log text as before.

*/

#import "OOOpenGL.h" // declares the bridge at its end
#import "OOStringBridge.h"

BOOL OOCheckOpenGLErrors(NSString* format, ...)
{
    va_list args;

    va_start(args, format);
    BOOL errorOccurred = cxx_OOCheckOpenGLErrors([format, &args]() -> std::string {
        if (format == nil)
            return "<unknown>";
        va_list copy;
        va_copy(copy, args);
        NSString* context = [[[NSString alloc] initWithFormat:format arguments:copy] autorelease];
        va_end(copy);
        return oo::StdString(context);
    });
    va_end(args);

    return errorOccurred;
}
