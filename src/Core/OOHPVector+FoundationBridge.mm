/*

OOHPVector+FoundationBridge.mm

TRANSITIONAL: see OOHPVector+FoundationBridge.h. Each function forwards to its cxx_ counterpart and
converts the result exactly as the old function produced it (the same NSNumber type, an immutable
array).

*/

#import "OOFoundationBridge.h"
#include "OOMaths.h" // declares the bridge functions (C linkage) at the end of OOHPVector.h

NSString* HPVectorDescription(HPVector vector)
{
    return oo::NSStringFrom(cxx_HPVectorDescription(vector));
}

NSArray* ArrayFromHPVector(HPVector vector)
{
    NSMutableArray* result = [NSMutableArray arrayWithCapacity:3];
    for (double component : cxx_ArrayFromHPVector(vector))
        [result addObject:[NSNumber numberWithDouble:component]];
    return [[result copy] autorelease]; // immutable, as +arrayWithObjects: was
}
