/*

PlayerEntityControls+FoundationBridge.mm

TRANSITIONAL: see PlayerEntityControls+FoundationBridge.h. Each method forwards to its cxx_
counterpart and converts the result exactly as the old method produced it.

*/

#import "OOFoundationBridge.h"
#import "PlayerEntityControls.h" // declares the bridge category at its end

@implementation PlayerEntity (ControlsFoundationBridge)

// oo-3rb.214 (chunk 1): the old method returned a +1 array (its callers release it)

- (NSArray*)processKeyCode:(NSArray*)key_def
{
    return [oo::ObjectFromPList([self cxx_processKeyCode:oo::PListFrom(key_def)]) retain];
}

@end
