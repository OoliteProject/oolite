/*

OOStringExpander+FoundationBridge.mm

TRANSITIONAL: see OOStringExpander+FoundationBridge.h. Each function forwards to its cxx_
counterpart, converting at the boundary: the overrides and legacy locals once per call with
oo::PListFrom (mixed values, Object nodes for anything else), strings with oo::StdString /
oo::OptionalString in and oo::NSStringOrNil out (nil for nullopt).

*/

#import "OOFoundationBridge.h"
#import "OOStringExpander.h" // declares the bridge functions at its end

NSString* OOExpandDescriptionString(Random_Seed seed, NSString* string, NSDictionary* overrides, NSDictionary* legacyLocals, NSString* systemName, OOExpandOptions options)
{
    if (string == nil)
        return nil;
    return oo::NSStringOrNil(cxx_OOExpandDescriptionString(seed, oo::StdString(string), oo::PListFrom(overrides), oo::PListFrom(legacyLocals), oo::OptionalString(systemName), options));
}

NSString* OOGenerateSystemDescription(Random_Seed seed, NSString* name)
{
    return oo::NSStringOrNil(cxx_OOGenerateSystemDescription(seed, oo::OptionalString(name)));
}
