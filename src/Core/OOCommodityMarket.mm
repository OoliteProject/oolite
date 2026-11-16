/*

OOCommodityMarket.m

Oolite
Copyright (C) 2004-2014 Giles C Williams and contributors

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
#import "OOCommodities.h"
#import "OOFoundationBridge.h"
#import "OOStringExpander.h"

namespace {

// The trade-goods.plist keys of OOCommodities.h (kOOCommodityName & co.), as C++ strings.
constexpr std::string_view kName = "name";
constexpr std::string_view kContainer = "quantity_unit";
constexpr std::string_view kPriceCurrent = "price";
constexpr std::string_view kQuantityCurrent = "quantity";
constexpr std::string_view kLegalityExport = "legality_export";
constexpr std::string_view kLegalityImport = "legality_import";
constexpr std::string_view kTrumbleOpinion = "trumble_opinion";
constexpr std::string_view kSortOrder = "sort_order";
constexpr std::string_view kCapacity = "capacity";
constexpr std::string_view kComment = "comment";
constexpr std::string_view kShortComment = "short_comment";

// A string element of a saved-game entry, or nullopt where -oo_stringAtIndex: gave nil.
std::optional<std::string> SavedGoodKey(const oo::PList& entry)
{
    const oo::PList* value = entry.isNull() ? nullptr : entry.at(0);
    if (value == nullptr || !(value->isString() || value->isNumber()))
        return std::nullopt;
    return entry.at<std::string>(0);
}

} // namespace

@interface OOCommodityMarket (OOPrivate)

// nullptr: no such good (a nil definition).
- (oo::PList*)definitionPointerForGood:(const std::string&)good;
- (std::vector<std::string>)sortedGoodKeys;

@end

@implementation OOCommodityMarket

- (id)init
{
    self = [super init];
    if (self == nil)
        return nil;

    return self;
}

- (NSUInteger)count
{
    return _commodityList.size();
}

- (void)cxx_setGood:(const std::string&)key withInfo:(const oo::PList&)info
{
    // A nil info made an empty definition, as +dictionaryWithDictionary:nil did.
    _commodityList[key] = info.isDict() ? info : oo::PList(oo::PList::Dict { });
    _sortedKeys.reset(); // reset
}

- (id)goods
{
    return oo::NSArrayFromStrings([self sortedGoodKeys]);
}

- (id)dictionaryForScripting
{
    return oo::ObjectFromPList(oo::PList(oo::PList::Dict(_commodityList.begin(), _commodityList.end())));
}

- (BOOL)cxx_setPrice:(OOCreditsQuantity)price forGood:(const std::string&)good
{
    oo::PList* definition = [self definitionPointerForGood:good];
    if (definition == nullptr) {
        return NO;
    }
    (*definition->getIf<oo::PList::Dict>())[std::string(kPriceCurrent)] = oo::PList::unsignedInteger(price);
    return YES;
}

- (BOOL)cxx_setQuantity:(OOCargoQuantity)quantity forGood:(const std::string&)good
{
    oo::PList* definition = [self definitionPointerForGood:good];
    if (definition == nullptr || quantity > [self cxx_capacityForGood:good]) {
        return NO;
    }
    (*definition->getIf<oo::PList::Dict>())[std::string(kQuantityCurrent)] = oo::PList::unsignedInteger(quantity);
    return YES;
}

- (BOOL)cxx_addQuantity:(OOCargoQuantity)quantity forGood:(const std::string&)good
{
    OOCargoQuantity current = [self cxx_quantityForGood:good];
    if (current + quantity > [self cxx_capacityForGood:good]) {
        return NO;
    }
    [self cxx_setQuantity:(current + quantity) forGood:good];
    return YES;
}

- (BOOL)cxx_removeQuantity:(OOCargoQuantity)quantity forGood:(const std::string&)good
{
    OOCargoQuantity current = [self cxx_quantityForGood:good];
    if (current < quantity) {
        return NO;
    }
    [self cxx_setQuantity:(current - quantity) forGood:good];
    return YES;
}

- (void)removeAllGoods
{
    for (const auto& entry : _commodityList) {
        [self cxx_setQuantity:0 forGood:entry.first];
    }
}

- (BOOL)cxx_setComment:(const std::string&)comment forGood:(const std::string&)good
{
    oo::PList* definition = [self definitionPointerForGood:good];
    if (definition == nullptr) {
        return NO;
    }
    (*definition->getIf<oo::PList::Dict>())[std::string(kComment)] = oo::PList(comment);
    return YES;
}

- (BOOL)cxx_setShortComment:(const std::string&)comment forGood:(const std::string&)good
{
    oo::PList* definition = [self definitionPointerForGood:good];
    if (definition == nullptr) {
        return NO;
    }
    (*definition->getIf<oo::PList::Dict>())[std::string(kShortComment)] = oo::PList(comment);
    return YES;
}

- (std::optional<std::string>)cxx_nameForGood:(const std::string&)good
{
    const oo::PList* definition = [self definitionPointerForGood:good];
    if (definition == nullptr) {
        return oo::OptionalString(OOExpand(@"[oolite-unknown-commodity-name]"));
    }
    return oo::OptionalString(OOExpand(oo::NSStringFrom(definition->get<std::string>(kName, "[oolite-unknown-commodity-name]"))));
}

- (std::optional<std::string>)cxx_commentForGood:(const std::string&)good
{
    const oo::PList* definition = [self definitionPointerForGood:good];
    if (definition == nullptr) {
        return oo::OptionalString(OOExpand(@"[oolite-unknown-commodity-name]"));
    }
    return oo::OptionalString(OOExpand(oo::NSStringFrom(definition->get<std::string>(kComment, "[oolite-commodity-no-comment]"))));
}

- (std::optional<std::string>)cxx_shortCommentForGood:(const std::string&)good
{
    const oo::PList* definition = [self definitionPointerForGood:good];
    if (definition == nullptr) {
        return oo::OptionalString(OOExpand(@"[oolite-unknown-commodity-name]"));
    }
    return oo::OptionalString(OOExpand(oo::NSStringFrom(definition->get<std::string>(kShortComment, "[oolite-commodity-no-short-comment]"))));
}

- (OOCreditsQuantity)cxx_priceForGood:(const std::string&)good
{
    const oo::PList* definition = [self definitionPointerForGood:good];
    if (definition == nullptr) {
        return 0;
    }
    return definition->get<unsigned long long>(kPriceCurrent);
}

- (OOCargoQuantity)cxx_quantityForGood:(const std::string&)good
{
    const oo::PList* definition = [self definitionPointerForGood:good];
    if (definition == nullptr) {
        return 0;
    }
    return definition->get<unsigned int>(kQuantityCurrent);
}

- (OOMassUnit)massUnitForGood:(id)good
{
    const oo::PList* definition = [self definitionPointerForGood:oo::StdString(good)];
    if (definition == nullptr) {
        return UNITS_TONS;
    }
    return OOMassUnitFromNumber(definition->get<unsigned int>(kContainer));
}

- (NSUInteger)cxx_exportLegalityForGood:(const std::string&)good
{
    const oo::PList* definition = [self definitionPointerForGood:good];
    if (definition == nullptr) {
        return 0;
    }
    return definition->get<unsigned long long>(kLegalityExport);
}

- (NSUInteger)cxx_importLegalityForGood:(const std::string&)good
{
    const oo::PList* definition = [self definitionPointerForGood:good];
    if (definition == nullptr) {
        return 0;
    }
    return definition->get<unsigned long long>(kLegalityImport);
}

- (OOCargoQuantity)cxx_capacityForGood:(const std::string&)good
{
    const oo::PList* definition = [self definitionPointerForGood:good];
    if (definition == nullptr) {
        return 0;
    }
    // should only be undefined for main system markets, not secondary stations
    // meaningless for player ship, though
    return definition->get<unsigned int>(kCapacity, MAIN_SYSTEM_MARKET_LIMIT);
}

- (float)cxx_trumbleOpinionForGood:(const std::string&)good
{
    const oo::PList* definition = [self definitionPointerForGood:good];
    if (definition == nullptr) {
        return 0;
    }
    return definition->get<float>(kTrumbleOpinion);
}

- (oo::PList)cxx_definitionForGood:(const std::string&)good
{
    const oo::PList* definition = [self definitionPointerForGood:good];
    return definition != nullptr ? *definition : oo::PList();
}

- (oo::PList)cxx_savePlayerAmounts
{
    oo::PList::Array amounts;
    for (const std::string& good : [self sortedGoodKeys]) {
        amounts.push_back(oo::PList(oo::PList::Array { oo::PList(good), oo::PList::unsignedInteger([self cxx_quantityForGood:good]) }));
    }
    return oo::PList(std::move(amounts));
}

- (void)cxx_loadPlayerAmounts:(const oo::PList&)amounts
{
    OOCargoQuantity q;
    BOOL loadedOK;
    for (const std::string& good : [self sortedGoodKeys]) {
        // make sure that any goods not defined in the save game are zeroed
        [self cxx_setQuantity:0 forGood:good];
    }

    const oo::PList::Array* loadedAmounts = amounts.getIf<oo::PList::Array>();
    for (const oo::PList& loaded : loadedAmounts != nullptr ? *loadedAmounts : oo::PList::Array()) {
        loadedOK = NO;
        const std::optional<std::string> good = SavedGoodKey(loaded);
        q = loaded.at<unsigned int>(1);
        // old save games might have more in the array, but we don't care
        if (!good.has_value() || ![self cxx_setQuantity:q forGood:*good]) {
            // then it's an array from a 1.80-or-earlier save game and
            // the good name is the description string (maybe a
            // translated one)
            for (const std::string& key : [self sortedGoodKeys]) {
                if (good.has_value() && good == [self cxx_nameForGood:key]) {
                    [self cxx_setQuantity:q forGood:key];
                    loadedOK = YES;
                    break;
                }
            }
        } else {
            loadedOK = YES;
        }
        if (!loadedOK) {
            OOLog(@"setCommanderDataFromDictionary.warning.cargo", @"Cargo %@ (%u units) could not be loaded from the saved game, as it is no longer defined", oo::NSStringOrNil(good), q);
        }
    }
}

- (oo::PList)cxx_saveStationAmounts
{
    oo::PList::Array amounts;
    for (const std::string& good : [self sortedGoodKeys]) {
        amounts.push_back(oo::PList(oo::PList::Array { oo::PList(good), oo::PList::unsignedInteger([self cxx_quantityForGood:good]), oo::PList::unsignedInteger([self cxx_priceForGood:good]) }));
    }
    return oo::PList(std::move(amounts));
}

- (void)cxx_loadStationAmounts:(const oo::PList&)amounts
{
    OOCargoQuantity q;
    OOCreditsQuantity p;
    BOOL loadedOK;

    const oo::PList::Array* loadedAmounts = amounts.getIf<oo::PList::Array>();
    for (const oo::PList& loaded : loadedAmounts != nullptr ? *loadedAmounts : oo::PList::Array()) {
        loadedOK = NO;
        const std::optional<std::string> good = SavedGoodKey(loaded);
        q = loaded.at<unsigned int>(1);
        p = loaded.at<unsigned long long>(2);
        // old save games might have more in the array, but we don't care
        if (!good.has_value() || ![self cxx_setQuantity:q forGood:*good]) {
            // then it's an array from a 1.80-or-earlier save game and
            // the good name is the description string (maybe a
            // translated one)
            for (const std::string& key : [self sortedGoodKeys]) {
                if (good.has_value() && good == [self cxx_nameForGood:key]) {
                    [self cxx_setQuantity:q forGood:key];
                    [self cxx_setPrice:p forGood:key];
                    loadedOK = YES;
                    break;
                }
            }
        } else {
            [self cxx_setPrice:p forGood:*good];
            loadedOK = YES;
        }
        if (!loadedOK) {
            OOLog(@"load.warning.cargo", @"Station market good %@ (%u units) could not be loaded from the saved game, as it is no longer defined", oo::NSStringOrNil(good), q);
        }
    }
}

@end

@implementation OOCommodityMarket (OOPrivate)

- (oo::PList*)definitionPointerForGood:(const std::string&)good
{
    const auto it = _commodityList.find(good);
    return it != _commodityList.end() ? &it->second : nullptr;
}

// The goods in sort_order; goods of equal sort_order in byte order of their key (the Foundation
// version sorted -allKeys, in hash order).
- (std::vector<std::string>)sortedGoodKeys
{
    if (!_sortedKeys.has_value()) {
        std::vector<std::string> keys;
        for (const auto& entry : _commodityList)
            keys.push_back(entry.first);
        std::stable_sort(keys.begin(), keys.end(), [self](const std::string& a, const std::string& b) {
            return _commodityList.find(a)->second.get<int>(kSortOrder) < _commodityList.find(b)->second.get<int>(kSortOrder);
        });
        _sortedKeys = std::move(keys);
    }
    return *_sortedKeys;
}

@end
