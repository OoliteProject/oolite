/*

OOTextureLoader+FoundationBridge.mm

TRANSITIONAL: see OOTextureLoader+FoundationBridge.h. Each method forwards to its cxx_
counterpart and converts the result exactly as the old method produced it (nil for nil).

*/

#import "OOFoundationBridge.h"
#import "OOTextureLoader.h" // declares the bridge category at its end

@implementation OOTextureLoader (OOFoundationBridge)

+ (id)loaderWithPath:(NSString*)path options:(uint32_t)options
{
    return [self cxx_loaderWithPath:oo::OptionalString(path) options:options];
}

+ (id)loaderWithTextureSpecifier:(id)specifier extraOptions:(uint32_t)extraOptions folder:(NSString*)folder
{
    return [self cxx_loaderWithTextureSpecifier:oo::PListFrom(specifier) extraOptions:extraOptions folder:oo::OptionalString(folder)];
}

- (id)initWithPath:(NSString*)path options:(uint32_t)options
{
    return [self cxx_initWithPath:oo::OptionalString(path) options:options];
}

- (NSString*)path
{
    return oo::NSStringOrNil([self cxx_path]);
}

@end
