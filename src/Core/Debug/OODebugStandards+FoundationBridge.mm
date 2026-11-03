/*

OODebugStandards+FoundationBridge.mm

TRANSITIONAL: see OODebugStandards+FoundationBridge.h. Each function forwards to its cxx_
counterpart. Every caller passes a string literal or a formatted string, never nil.

*/

#import "OODebugStandards.h" // declares the bridge functions at its end
#import "OOStringBridge.h"

void OOStandardsDeprecated(NSString* message)
{
    cxx_OOStandardsDeprecated(oo::StdString(message));
}

void OOStandardsError(NSString* message)
{
    cxx_OOStandardsError(oo::StdString(message));
}
