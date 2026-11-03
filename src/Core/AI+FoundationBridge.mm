/*

AI+FoundationBridge.mm

TRANSITIONAL: see AI+FoundationBridge.h. Each method forwards to its cxx_ counterpart and converts
arguments and results at the boundary (nil for nil).

*/

#import "AI.h" // declares the bridge category at its end
#import "OOFoundationBridge.h"

@implementation AI (OOFoundationBridge)

- (void)setStateMachine:(NSString*)smName withJSScript:(NSString*)script
{
    [self cxx_setStateMachine:oo::StdString(smName) withJSScript:oo::StdString(script)];
}

- (void)setState:(NSString*)stateName
{
    [self cxx_setState:oo::StdString(stateName)];
}

- (void)setStateMachine:(NSString*)smName afterDelay:(NSTimeInterval)delay
{
    [self cxx_setStateMachine:oo::StdString(smName) afterDelay:delay];
}

- (void)setState:(NSString*)stateName afterDelay:(NSTimeInterval)delay
{
    [self cxx_setState:oo::StdString(stateName) afterDelay:delay];
}

- (id)initWithStateMachine:(NSString*)smName andState:(NSString*)stateName
{
    return [self cxx_initWithStateMachine:oo::OptionalString(smName) andState:oo::OptionalString(stateName)];
}

- (void)exitStateMachineWithMessage:(NSString*)message
{
    [self cxx_exitStateMachineWithMessage:oo::OptionalString(message)];
}

+ (NSString*)currentlyRunningAIDescription
{
    return oo::NSStringOrNil([self cxx_currentlyRunningAIDescription]);
}

- (NSString*)associatedJS
{
    return oo::NSStringOrNil([self cxx_associatedJS]);
}

- (void)reactToMessage:(NSString*)message context:(NSString*)debugContext
{
    if (message == nil)
        return; // as the old dispatcher did first
    [self cxx_reactToMessage:oo::StdString(message) context:oo::OptionalString(debugContext)];
}

- (void)takeAction:(NSString*)action
{
    [self cxx_takeAction:oo::StdString(action)];
}

- (void)dropMessage:(NSString*)ms
{
    [self cxx_dropMessage:oo::StdString(ms)];
}

@end
