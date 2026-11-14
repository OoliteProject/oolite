/*

OOCommodities+ObjCBridge.mm

TRANSITIONAL (proposed ADR-0056, bead oo-fqyw): the Objective-C OOCommodities facade over
cxx::OOCommodities. Every method forwards to its C++ member; a market comes back through
oo::ToObjC. -init makes the C++ object (which reads trade-goods.plist) and registers the facade as
its peer (ADR-0056 amendment oo-8kx7). Deleted with OOCommodities+ObjCBridge.h.

Oolite
Copyright (C) 2004-2013 Giles C Williams and contributors

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
MA 02110-1301, USA.

*/

#import "OOCommodities.h"
#import "OOCommodityMarket.h"

#include "oofnd/objc/OOObjCPeer.h"

namespace {

// Never destroyed: a facade may be released while the process exits.
oo::ObjCPeers& Peers()
{
    static oo::ObjCPeers* peers = new oo::ObjCPeers;
    return *peers;
}

} // namespace

@interface OOCommodities (OOObjCBridgePrivate)

- (id)initWithCxxCommodities:(cxx::OOCommodities*)commodities;

@end

@implementation OOCommodities

// Inside the @implementation for the private ivar.
OOCommodities* oo::ToObjC(cxx::OOCommodities* commodities)
{
    return Peers().peerFor(commodities, [commodities] { return [[OOCommodities alloc] initWithCxxCommodities:commodities]; });
}

cxx::OOCommodities* oo::ToCxx(OOCommodities* commodities)
{
    if (commodities == nil)
        return nullptr;
    return commodities->_cxxCommodities.get();
}

- (id)initWithCxxCommodities:(cxx::OOCommodities*)commodities
{
    self = [super init];
    if (self != nil)
        _cxxCommodities = oo::Ref<cxx::OOCommodities>(commodities);
    return self;
}

- (id)init
{
    oo::Ref<cxx::OOCommodities> commodities = oo::makeRef<cxx::OOCommodities>();
    self = [self initWithCxxCommodities:commodities.get()];
    if (self != nil) {
        @autoreleasepool {
            Peers().peerFor(commodities.get(), [self] { return [self retain]; });
        }
    }
    return self;
}

- (void)dealloc
{
    Peers().forget(_cxxCommodities.get());
    [super dealloc];
}

+ (std::optional<std::string>)cxx_legacyCommodityType:(NSUInteger)i
{
    return cxx::OOCommodities::legacyCommodityType(i);
}

- (OOCommodityMarket*)generateManifestForPlayer
{
    return oo::ToObjC(_cxxCommodities->generateManifestForPlayer());
}
- (OOCommodityMarket*)generateBlankMarket
{
    return oo::ToObjC(_cxxCommodities->generateBlankMarket());
}

- (OOCommodityMarket*)cxx_generateMarketForSystemWithEconomy:(OOEconomyID)economy andScript:(const std::optional<std::string>&)scriptName
{
    return oo::ToObjC(_cxxCommodities->generateMarketForSystemWithEconomy(economy, scriptName));
}

- (OOCommodityMarket*)generateMarketForStation:(StationEntity*)station
{
    return oo::ToObjC(_cxxCommodities->generateMarketForStation(station));
}

- (OOCreditsQuantity)cxx_samplePriceForCommodity:(const std::string&)commodity inEconomy:(OOEconomyID)economy withScript:(const std::optional<std::string>&)scriptName inSystem:(OOSystemID)system
{
    return _cxxCommodities->samplePriceForCommodity(commodity, economy, scriptName, system);
}

- (NSUInteger)count
{
    return _cxxCommodities->count();
}
- (std::vector<std::string>)goods
{
    return _cxxCommodities->goods();
}
- (BOOL)cxx_goodDefined:(const std::string&)key
{
    return _cxxCommodities->goodDefined(key);
}
- (std::optional<std::string>)cxx_goodNamed:(const std::string&)name
{
    return _cxxCommodities->goodNamed(name);
}
- (std::string)getRandomCommodity
{
    return _cxxCommodities->getRandomCommodity();
}
- (OOMassUnit)massUnitForGood:(const std::string&)good
{
    return _cxxCommodities->massUnitForGood(good);
}

@end
