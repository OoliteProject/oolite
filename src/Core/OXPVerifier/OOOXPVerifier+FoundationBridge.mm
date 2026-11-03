/*

OOOXPVerifier+FoundationBridge.mm

TRANSITIONAL: see OOOXPVerifier+FoundationBridge.h. Each method forwards to its cxx_ counterpart
and converts the result exactly as the old method produced it (nil for nil).

*/

#import "OOOXPVerifier.h" // declares the bridge category at its end

#if OO_OXP_VERIFIER_ENABLED

#import "OOFoundationBridge.h"

@implementation OOOXPVerifier (OOFoundationBridge)

- (NSString*)oxpPath
{
    return oo::NSStringOrNil([self cxx_oxpPath]);
}

- (NSString*)oxpDisplayName
{
    return oo::NSStringOrNil([self cxx_oxpDisplayName]);
}

- (id)stageWithName:(NSString*)name
{
    if (name == nil)
        return nil;

    return [self cxx_stageWithName:oo::StdString(name)];
}

- (NSArray*)configurationArrayForKey:(NSString*)key
{
    return oo::ObjectFromPList([self cxx_configurationArrayForKey:oo::StdString(key)]);
}

- (NSDictionary*)configurationDictionaryForKey:(NSString*)key
{
    return oo::ObjectFromPList([self cxx_configurationDictionaryForKey:oo::StdString(key)]);
}

- (NSString*)configurationStringForKey:(NSString*)key
{
    return oo::NSStringOrNil([self cxx_configurationStringForKey:oo::StdString(key)]);
}

- (NSSet*)configurationSetForKey:(NSString*)key
{
    const std::optional<std::vector<std::string>> strings = [self cxx_configurationSetForKey:oo::StdString(key)];
    return strings.has_value() ? oo::NSSetFromStrings(*strings) : nil;
}

@end

#endif
