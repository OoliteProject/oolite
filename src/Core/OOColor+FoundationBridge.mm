/*

OOColor+FoundationBridge.mm

TRANSITIONAL: see OOColor+FoundationBridge.h. Each method forwards to its cxx_ counterpart and
converts the result exactly as the old method produced it (the same NSNumber type, nil for nil).

*/

#import "OOColor.h" // declares the bridge category at its end
#import "OOFoundationBridge.h"

@implementation OOColor (OOFoundationBridge)

+ (OOColor*)colorFromString:(NSString*)colorFloatString
{
    return [self cxx_colorFromString:oo::StdString(colorFloatString)];
}

- (NSArray*)normalizedArray
{
    NSMutableArray* result = [NSMutableArray arrayWithCapacity:4];
    for (float component : [self cxx_normalizedArray])
        [result addObject:[NSNumber numberWithFloat:component]];
    return [[result copy] autorelease]; // immutable, as +arrayWithObjects: was
}

- (NSString*)rgbaDescription
{
    return oo::NSStringOrNil([self cxx_rgbaDescription]);
}

- (NSString*)hsbaDescription
{
    return oo::NSStringOrNil([self cxx_hsbaDescription]);
}

@end

NSString* OORGBAComponentsDescription(OORGBAComponents components)
{
    return oo::NSStringFrom(cxx_OORGBAComponentsDescription(components));
}

NSString* OOHSBAComponentsDescription(OOHSBAComponents components)
{
    return oo::NSStringFrom(cxx_OOHSBAComponentsDescription(components));
}
