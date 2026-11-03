/*

PlayerEntityContracts+FoundationBridge.mm

TRANSITIONAL: see PlayerEntityContracts+FoundationBridge.h. Each method forwards to its cxx_
counterpart and converts the result exactly as the old method produced it (the same NSNumber
type, nil for nil).

*/

#import "OOFoundationBridge.h"
#import "PlayerEntityContracts.h" // declares the bridge category at its end

@implementation PlayerEntity (ContractsFoundationBridge)

// oo-3rb.179 (chunk 1): report strings

- (NSString*)processEscapePods
{
    return oo::NSStringOrNil([self cxx_processEscapePods]);
}

- (NSString*)checkPassengerContracts
{
    return oo::NSStringOrNil([self cxx_checkPassengerContracts]);
}

- (void)addMessageToReport:(NSString*)report
{
    [self cxx_addMessageToReport:oo::StdString(report)]; // nil adds nothing, as an empty string
}

// oo-3rb.181 (chunk 3): passengers (a nil name arrives as "": OOJSPlayerShip validates it first)

- (BOOL)addPassenger:(NSString*)Name start:(unsigned)start destination:(unsigned)destination eta:(double)eta fee:(double)fee advance:(double)advance risk:(unsigned)risk
{
    return [self cxx_addPassenger:oo::StdString(Name) start:start destination:destination eta:eta fee:fee advance:advance risk:risk];
}

- (BOOL)removePassenger:(NSString*)Name
{
    return [self cxx_removePassenger:oo::StdString(Name)];
}

// oo-3rb.182 (chunk 4): parcels (a nil name arrives as "": OOJSPlayerShip validates it first)

- (BOOL)addParcel:(NSString*)Name start:(unsigned)start destination:(unsigned)destination eta:(double)eta fee:(double)fee premium:(double)premium risk:(unsigned)risk
{
    return [self cxx_addParcel:oo::StdString(Name) start:start destination:destination eta:eta fee:fee premium:premium risk:risk];
}

- (BOOL)removeParcel:(NSString*)Name
{
    return [self cxx_removeParcel:oo::StdString(Name)];
}

// oo-3rb.183 (chunk 5): cargo contracts and manifest lists (a nil commodity arrives as "")

- (OOCargoQuantity)contractedVolumeForGood:(OOCommodityType)good
{
    return [self cxx_contractedVolumeForGood:oo::StdString(good)];
}

- (BOOL)awardContract:(unsigned)qty commodity:(NSString*)commodity start:(unsigned)start destination:(unsigned)destination eta:(double)eta fee:(double)fee premium:(double)premium
{
    return [self cxx_awardContract:qty commodity:oo::StdString(commodity) start:start destination:destination eta:eta fee:fee premium:premium];
}

- (BOOL)removeContract:(NSString*)commodity destination:(unsigned)destination
{
    return [self cxx_removeContract:oo::StdString(commodity) destination:destination];
}

- (NSArray*)passengerList
{
    return oo::NSArrayFromStrings([self cxx_passengerList]);
}

- (NSArray*)parcelList
{
    return oo::NSArrayFromStrings([self cxx_parcelList]);
}

- (NSArray*)contractList
{
    return oo::NSArrayFromStrings([self cxx_contractList]);
}

// oo-3rb.184 (chunk 6): shipyard (a nil key arrives as "", which no shipyard entry or ship has)

- (void)showShipyardModel:(NSString*)shipKey shipData:(NSDictionary*)shipDict personality:(uint16_t)personality
{
    if (shipKey == nil)
        return;
    [self cxx_showShipyardModel:oo::StdString(shipKey) shipData:oo::PListFrom(shipDict) personality:personality];
}

- (OOCreditsQuantity)priceForShipKey:(NSString*)key
{
    return [self cxx_priceForShipKey:oo::StdString(key)];
}

- (BOOL)replaceShipWithNamedShip:(NSString*)shipName
{
    return [self cxx_replaceShipWithNamedShip:oo::StdString(shipName)];
}

@end
