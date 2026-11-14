/*

GameController+FoundationBridge.mm

TRANSITIONAL: see GameController+FoundationBridge.h. Each method forwards to its cxx_ counterpart
and converts at the boundary (oo::StdString in: a nil file name arrives as "", which has no
.oolite-save extension, as before; nil for nullopt out).

*/

#import "GameController.h" // declares the bridge category at its end
#import "OOFoundationBridge.h"

@implementation GameController (OOFoundationBridge)

- (void)exitAppWithContext:(NSString*)context
{
    [self cxx_exitAppWithContext:oo::StdString(context)];
}

- (NSString*)playerFileToLoad
{
    return oo::NSStringOrNil([self cxx_playerFileToLoad]);
}

- (void)setPlayerFileToLoad:(NSString*)filename
{
    [self cxx_setPlayerFileToLoad:oo::StdString(filename)];
}

- (NSString*)playerFileDirectory
{
    return oo::NSStringOrNil([self cxx_playerFileDirectory]);
}

- (void)setPlayerFileDirectory:(NSString*)filename
{
    // nil clears the directory (and the default), which "" would not.
    [self cxx_setPlayerFileDirectory:oo::OptionalString(filename)];
}

- (void)logProgress:(NSString*)message
{
    [self cxx_logProgress:oo::StdString(message)];
}

#if OO_DEBUG
- (void)debugLogProgress:(NSString*)format, ...
{
    va_list args;
    va_start(args, format);
    [self debugLogProgress:format arguments:args];
    va_end(args);
}

- (void)debugLogProgress:(NSString*)format arguments:(va_list)arguments
{
    NSString* message = [[[NSString alloc] initWithFormat:format arguments:arguments] autorelease];
    [self cxx_debugLogProgress:oo::StdString(message)];
}

- (void)debugPushProgressMessage:(NSString*)format, ...
{
    va_list args;
    va_start(args, format);
    NSString* message = [[[NSString alloc] initWithFormat:format arguments:args] autorelease];
    va_end(args);
    [self cxx_debugPushProgressMessage:oo::StdString(message)];
}
#endif

@end
