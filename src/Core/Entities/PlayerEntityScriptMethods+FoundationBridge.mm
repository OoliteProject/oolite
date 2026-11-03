/*

PlayerEntityScriptMethods+FoundationBridge.mm

TRANSITIONAL: see PlayerEntityScriptMethods+FoundationBridge.h. Each method forwards to its cxx_
counterpart and converts the result exactly as the old method produced it (nil for nil, immutable
dictionaries, the system number a +numberWithInt: and the marker scale a +numberWithFloat:).

*/

#import "OOFoundationBridge.h"
#import "PlayerEntityScriptMethods.h" // declares the bridge category at its end

namespace {

// A marker as the old methods built it: nil for none, the system a +numberWithInt:.
NSDictionary* MarkerObject(const oo::PList& marker)
{
    if (marker.isNull())
        return nil;
    NSMutableDictionary* result = [NSMutableDictionary dictionaryWithDictionary:oo::ObjectFromPList(marker)];
    [result setObject:[NSNumber numberWithInt:marker.get<int>("system")] forKey:@"system"];
    return [[result copy] autorelease];
}

} // namespace

@implementation PlayerEntity (ScriptMethodsFoundationBridge)

- (NSString*)dockedStationName
{
    return oo::NSStringOrNil([self cxx_dockedStationName]);
}

- (NSString*)dockedStationDisplayName
{
    return oo::NSStringOrNil([self cxx_dockedStationDisplayName]);
}

- (void)awardCommodityType:(NSString*)type amount:(OOCargoQuantity)amount
{
    [self cxx_awardCommodityType:oo::StdString(type) amount:amount];
}

- (void)setMissionChoice:(NSString*)newChoice
{
    [self cxx_setMissionChoice:oo::OptionalString(newChoice)];
}

- (void)setMissionChoice:(NSString*)newChoice withEvent:(BOOL)withEvent
{
    [self cxx_setMissionChoice:oo::OptionalString(newChoice) withEvent:withEvent];
}

- (void)setMissionChoice:(NSString*)newChoice keyPress:(NSString*)keyPress
{
    [self cxx_setMissionChoice:oo::OptionalString(newChoice) keyPress:oo::OptionalString(keyPress)];
}

- (void)setMissionChoice:(NSString*)newChoice keyPress:(NSString*)keyPress withEvent:(BOOL)withEvent
{
    [self cxx_setMissionChoice:oo::OptionalString(newChoice) keyPress:oo::OptionalString(keyPress) withEvent:withEvent];
}

- (NSDictionary*)passengerContractMarker:(OOSystemID)system
{
    return MarkerObject([self cxx_passengerContractMarker:system]);
}

- (NSDictionary*)parcelContractMarker:(OOSystemID)system
{
    return MarkerObject([self cxx_parcelContractMarker:system]);
}

- (NSDictionary*)cargoContractMarker:(OOSystemID)system
{
    return MarkerObject([self cxx_cargoContractMarker:system]);
}

- (NSDictionary*)defaultMarker:(OOSystemID)system
{
    return MarkerObject([self cxx_defaultMarker:system]);
}

- (NSDictionary*)validatedMarker:(NSDictionary*)marker
{
    return MarkerObject([self cxx_validatedMarker:oo::PListFrom(marker)]);
}

- (NSString*)keyBindingDescription2:(NSString*)binding
{
    return oo::NSStringOrNil([self cxx_keyBindingDescription2:oo::StdString(binding)]);
}

- (NSString*)getKeyBindingDescription:(NSArray*)keyList
{
    return oo::NSStringOrNil([self cxx_getKeyBindingDescription:oo::PListFrom(keyList)]);
}

- (NSString*)keyCodeDescription:(OOKeyCode)code
{
    return oo::NSStringOrNil([self cxx_keyCodeDescription:code]);
}

- (NSString*)keyCodeDescriptionShort:(OOKeyCode)code
{
    return oo::NSStringOrNil([self cxx_keyCodeDescriptionShort:code]);
}

- (NSString*)commanderKillsAsString
{
    return oo::NSStringOrNil([self cxx_commanderKillsAsString]);
}

- (NSString*)commanderBountyAsString
{
    return oo::NSStringOrNil([self cxx_commanderBountyAsString]);
}

- (NSString*)creditsFormattedForSubstitution
{
    return oo::NSStringOrNil([self cxx_creditsFormattedForSubstitution]);
}

- (NSString*)creditsFormattedForLegacySubstitution
{
    return oo::NSStringOrNil([self cxx_creditsFormattedForLegacySubstitution]);
}

@end
