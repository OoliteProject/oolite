/*

OOCommodityMarket+ObjCBridge.mm

TRANSITIONAL (proposed ADR-0056, bead oo-ih7y): the Objective-C OOCommodityMarket facade over
cxx::OOCommodityMarket. Every method forwards to its C++ member; -init makes the C++ market and
registers the facade as its peer (ADR-0056 amendment oo-8kx7). Deleted with
OOCommodityMarket+ObjCBridge.h.

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

@interface OOCommodityMarket (OOObjCBridgePrivate)

- (id)initWithCxxMarket:(cxx::OOCommodityMarket*)market;

@end

@implementation OOCommodityMarket

// Inside the @implementation for the private ivar.
OOCommodityMarket* oo::ToObjC(cxx::OOCommodityMarket* market)
{
    return Peers().peerFor(market, [market] { return [[OOCommodityMarket alloc] initWithCxxMarket:market]; });
}

cxx::OOCommodityMarket* oo::ToCxx(OOCommodityMarket* market)
{
    if (market == nil)
        return nullptr;
    return market->_cxxMarket.get();
}

- (id)initWithCxxMarket:(cxx::OOCommodityMarket*)market
{
    self = [super init];
    if (self != nil)
        _cxxMarket = oo::Ref<cxx::OOCommodityMarket>(market);
    return self;
}

// [[OOCommodityMarket alloc] init], as OOCommodities and its callers make markets: an empty one.
- (id)init
{
    oo::Ref<cxx::OOCommodityMarket> market = oo::makeRef<cxx::OOCommodityMarket>();
    self = [self initWithCxxMarket:market.get()];
    if (self != nil) {
        @autoreleasepool {
            Peers().peerFor(market.get(), [self] { return [self retain]; });
        }
    }
    return self;
}

- (void)dealloc
{
    Peers().forget(_cxxMarket.get());
    [super dealloc];
}

- (NSUInteger)count
{
    return _cxxMarket->count();
}

- (void)cxx_setGood:(const std::string&)key withInfo:(const oo::PList&)info
{
    _cxxMarket->setGood(key, info);
}

- (std::vector<std::string>)goods
{
    return _cxxMarket->goods();
}
- (oo::PList)dictionaryForScripting
{
    return _cxxMarket->dictionaryForScripting();
}

- (BOOL)cxx_setPrice:(OOCreditsQuantity)price forGood:(const std::string&)good
{
    return _cxxMarket->setPrice(price, good);
}
- (BOOL)cxx_setQuantity:(OOCargoQuantity)quantity forGood:(const std::string&)good
{
    return _cxxMarket->setQuantity(quantity, good);
}
- (BOOL)cxx_addQuantity:(OOCargoQuantity)quantity forGood:(const std::string&)good
{
    return _cxxMarket->addQuantity(quantity, good);
}
- (BOOL)cxx_removeQuantity:(OOCargoQuantity)quantity forGood:(const std::string&)good
{
    return _cxxMarket->removeQuantity(quantity, good);
}
- (void)removeAllGoods
{
    _cxxMarket->removeAllGoods();
}
- (BOOL)cxx_setComment:(const std::string&)comment forGood:(const std::string&)good
{
    return _cxxMarket->setComment(comment, good);
}
- (BOOL)cxx_setShortComment:(const std::string&)comment forGood:(const std::string&)good
{
    return _cxxMarket->setShortComment(comment, good);
}

- (std::optional<std::string>)cxx_nameForGood:(const std::string&)good
{
    return _cxxMarket->nameForGood(good);
}
- (std::optional<std::string>)cxx_commentForGood:(const std::string&)good
{
    return _cxxMarket->commentForGood(good);
}
- (std::optional<std::string>)cxx_shortCommentForGood:(const std::string&)good
{
    return _cxxMarket->shortCommentForGood(good);
}
- (OOCreditsQuantity)cxx_priceForGood:(const std::string&)good
{
    return _cxxMarket->priceForGood(good);
}
- (OOCargoQuantity)cxx_quantityForGood:(const std::string&)good
{
    return _cxxMarket->quantityForGood(good);
}
- (OOMassUnit)massUnitForGood:(const std::string&)good
{
    return _cxxMarket->massUnitForGood(good);
}
- (NSUInteger)cxx_exportLegalityForGood:(const std::string&)good
{
    return _cxxMarket->exportLegalityForGood(good);
}
- (NSUInteger)cxx_importLegalityForGood:(const std::string&)good
{
    return _cxxMarket->importLegalityForGood(good);
}
- (OOCargoQuantity)cxx_capacityForGood:(const std::string&)good
{
    return _cxxMarket->capacityForGood(good);
}
- (float)cxx_trumbleOpinionForGood:(const std::string&)good
{
    return _cxxMarket->trumbleOpinionForGood(good);
}

- (oo::PList)cxx_definitionForGood:(const std::string&)good
{
    return _cxxMarket->definitionForGood(good);
}

- (oo::PList)cxx_savePlayerAmounts
{
    return _cxxMarket->savePlayerAmounts();
}
- (void)cxx_loadPlayerAmounts:(const oo::PList&)amounts
{
    _cxxMarket->loadPlayerAmounts(amounts);
}

- (oo::PList)cxx_saveStationAmounts
{
    return _cxxMarket->saveStationAmounts();
}
- (void)cxx_loadStationAmounts:(const oo::PList&)amounts
{
    _cxxMarket->loadStationAmounts(amounts);
}

@end
