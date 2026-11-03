/*

PlayerEntityScriptMethods.m

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

#import "PlayerEntityScriptMethods.h"
#import "PlayerEntityLoadSave.h"

#import "OOCommodities.h"
#import "OOConstToString.h"
#import "OOFoundationBridge.h"
#import "OOStringParsing.h"
#import "Universe.h"

#include "oofnd/PListGet.hpp"
#include "oofnd/String.hpp"

#import "OOStringExpander.h"
#import "OOSystemDescriptionManager.h"

#import "StationEntity.h"

namespace {

// A contract marker, as the four marker methods built it (the system a +numberWithInt:).
oo::PList MarkerFor(OOSystemID system, const char* color, const char* shape)
{
    oo::PList::Dict marker;
    marker["system"] = oo::PList::signedInteger(system);
    marker["name"] = oo::StdString(MISSION_DEST_LEGACY);
    marker["markerColor"] = color;
    marker["markerShape"] = shape;
    return oo::PList(std::move(marker));
}

// What -boolValue / -integerValue of the value an Objective-C dictionary held gave (NO / 0 for none).
BOOL BoolValueOf(const oo::PList* value)
{
    return value != nullptr ? [oo::ObjectFromPList(*value) boolValue] : NO;
}

NSInteger IntegerValueOf(const oo::PList* value)
{
    return value != nullptr ? [oo::ObjectFromPList(*value) integerValue] : 0;
}

} // namespace

@implementation PlayerEntity (ScriptMethods)

- (unsigned)score
{
    return ship_kills;
}

- (void)setScore:(unsigned)value
{
    ship_kills = value;
}

- (double)creditBalance
{
    return 0.1 * credits;
}

- (void)setCreditBalance:(double)value
{
    credits = OODeciCreditsFromDouble(value * 10.0);
}

- (std::optional<std::string>)cxx_dockedStationName
{
    return oo::OptionalString([[self dockedStation] name]);
}

- (std::optional<std::string>)cxx_dockedStationDisplayName
{
    return oo::OptionalString([[self dockedStation] displayName]);
}

- (BOOL)dockedAtMainStation
{
    return [self status] == STATUS_DOCKED && [self dockedStation] == [UNIVERSE station];
}

- (void)cxx_awardCommodityType:(const std::string&)type amount:(OOCargoQuantity)amount
{
    OOMassUnit unit;

    if (![[UNIVERSE commodities] goodDefined:oo::NSStringFrom(type)]) {
        return;
    }

    OOLog(@"script.debug.note.awardCargo", @"Going to award cargo: %d x '%@'", amount, oo::NSStringFrom(type));

    unit = [shipCommodityData massUnitForGood:oo::NSStringFrom(type)];

    if ([self status] != STATUS_DOCKED) {
        // in-flight
        while (amount) {
            if (unit != UNITS_TONS) {
                if (specialCargo) {
                    // is this correct behaviour?
                    [shipCommodityData cxx_addQuantity:amount forGood:type];
                } else {
                    int amount_per_container = (unit == UNITS_KILOGRAMS) ? 1000 : 1000000;
                    while (amount > 0) {
                        int smaller_quantity = 1 + ((amount - 1) % amount_per_container);
                        if (cargo.size() < [self maxAvailableCargoSpace]) {
                            ShipEntity* container = [UNIVERSE newShipWithRole:@"1t-cargopod"];
                            if (container) {
                                // the cargopod ship is just being set up. If ejected,  will call UNIVERSE addEntity
                                // [container wasAddedToUniverse]; // seems to be not needed anymore for pods
                                [container setScanClass:CLASS_CARGO];
                                [container setStatus:STATUS_IN_HOLD];
                                [container setCommodity:oo::NSStringFrom(type) andAmount:smaller_quantity];
                                cargo.emplace_back(container);
                                [container release];
                            }
                        }
                        amount -= smaller_quantity;
                    }
                }
            } else if (!specialCargo)
            // no adding TCs while special cargo in hold
            {
                // put each ton in a separate container
                while (amount) {
                    if (cargo.size() < [self maxAvailableCargoSpace]) {
                        ShipEntity* container = [UNIVERSE newShipWithRole:@"1t-cargopod"];
                        if (container) {
                            // the cargopod ship is just being set up. If ejected, will call UNIVERSE addEntity
                            // [container wasAddedToUniverse]; // seems to be not needed anymore for pods
                            [container setScanClass:CLASS_CARGO];
                            [container setStatus:STATUS_IN_HOLD];
                            [container setCommodity:oo::NSStringFrom(type) andAmount:1];
                            cargo.emplace_back(container);
                            [container release];
                        }
                    }
                    amount--;
                }
            }
        }
    } else { // docked
        // like purchasing a commodity
        int manifest_quantity = [shipCommodityData cxx_quantityForGood:type];
        while ((amount) && (current_cargo < [self maxAvailableCargoSpace])) {
            manifest_quantity++;
            amount--;
            if (unit == UNITS_TONS)
                current_cargo++;
        }
        [shipCommodityData cxx_setQuantity:manifest_quantity forGood:type];
    }
    [self calculateCurrentCargo];
}

- (void)resetScannerZoom
{
    scanner_zoom_rate = SCANNER_ZOOM_RATE_DOWN;
}

- (OOGalaxyID)currentGalaxyID
{
    return galaxy_number;
}

- (OOSystemID)currentSystemID
{
    if ([UNIVERSE sun] == nil)
        return -1; // Interstellar space
    return [UNIVERSE currentSystemID];
}

- (void)cxx_setMissionChoice:(const std::optional<std::string>&)newChoice
{
    [self cxx_setMissionChoice:newChoice keyPress:std::string() withEvent:YES];
}

- (void)cxx_setMissionChoice:(const std::optional<std::string>&)newChoice withEvent:(BOOL)withEvent
{
    [self cxx_setMissionChoice:newChoice keyPress:std::string() withEvent:withEvent];
}

- (void)cxx_setMissionChoice:(const std::optional<std::string>&)newChoice keyPress:(const std::optional<std::string>&)keyPress
{
    [self cxx_setMissionChoice:newChoice keyPress:keyPress withEvent:YES];
}

- (void)cxx_setMissionChoice:(const std::optional<std::string>&)newChoice keyPress:(const std::optional<std::string>&)keyPress withEvent:(BOOL)withEvent
{
    const std::optional<std::string> oldChoice = missionChoice;
    BOOL equal = newChoice == oldChoice; // Catch both being nil as well
    if (!equal) {
        if (!newChoice.has_value()) {
            missionChoice.reset();
            if (withEvent)
                [self doScriptEvent:OOJSID("missionChoiceWasReset") withArgument:oo::NSStringOrNil(oldChoice)];
        } else {
            missionChoice = newChoice;
        }
    }
    equal = keyPress == missionKeyPress;
    if (!equal) {
        missionKeyPress = keyPress;
    }
}

- (void)allowMissionInterrupt
{
    _missionAllowInterrupt = YES;
}

- (OOTimeDelta)scriptTimer
{
    return script_time;
}

/* FIXME: these next three functions seed the RNG when called. That
 * could cause unwanted effects - should save its state, and then
 * reset it after generating the number. */
- (unsigned)systemPseudoRandom100
{
    seed_RNG_only_for_planet_description([[UNIVERSE systemManager] getRandomSeedForCurrentSystem]);
    return (gen_rnd_number() * 256 + gen_rnd_number()) % 100;
}

- (unsigned)systemPseudoRandom256
{
    seed_RNG_only_for_planet_description([[UNIVERSE systemManager] getRandomSeedForCurrentSystem]);
    return gen_rnd_number();
}

- (double)systemPseudoRandomFloat
{
    seed_RNG_only_for_planet_description([[UNIVERSE systemManager] getRandomSeedForCurrentSystem]);
    unsigned a = gen_rnd_number();
    unsigned b = gen_rnd_number();
    unsigned c = gen_rnd_number();

    a = (a << 16) | (b << 8) | c;
    return (double)a / (double)0x01000000;
}

- (oo::PList)cxx_passengerContractMarker:(OOSystemID)system
{
    return MarkerFor(system, "orangeColor", "MARKER_DIAMOND");
}

- (oo::PList)cxx_parcelContractMarker:(OOSystemID)system
{
    return MarkerFor(system, "orangeColor", "MARKER_PLUS");
}

- (oo::PList)cxx_cargoContractMarker:(OOSystemID)system
{
    return MarkerFor(system, "orangeColor", "MARKER_SQUARE");
}

- (oo::PList)cxx_defaultMarker:(OOSystemID)system
{
    return MarkerFor(system, "redColor", "MARKER_X");
}

- (oo::PList)cxx_validatedMarker:(const oo::PList&)marker
{
    if (marker.isNull()) {
        // Messaging nil read system 0, and the nil name ended +dictionaryWithObjectsAndKeys: after it.
        oo::PList::Dict result;
        result["system"] = oo::PList::signedInteger(0);
        return oo::PList(std::move(result));
    }
    OOSystemID dest = marker.get<int>("system");
    // FIXME: parameters
    if (dest < 0 || dest > kOOMaximumSystemID) {
        return oo::PList();
    }
    std::string group = marker.get<std::string>("name", oo::StdString(MISSION_DEST_LEGACY));

    oo::PList::Dict result;
    result["system"] = oo::PList::signedInteger(dest);
    result["name"] = std::move(group);
    result["markerColor"] = marker.get<std::string>("markerColor", "redColor");
    result["markerShape"] = marker.get<std::string>("markerShape", "MARKER_X");
    result["markerScale"] = oo::PList::singleReal(marker.get<float>("markerScale", 1.0)); // +numberWithFloat:
    return oo::PList(std::move(result));
}

// Implements string expansion code [credits_number].
- (std::optional<std::string>)cxx_creditsFormattedForSubstitution
{
    return oo::OptionalString(OOStringFromDeciCredits([self deciCredits], YES, NO));
}

/*	Implements string expansion code [_oo_legacy_credits_number].

        Literal uses of [credits_number] in legacy scripts are converted to
        [_oo_legacy_credits_number] in the script sanitizer. These are shown
        unlocalized because legacy scripts may use it for arithmetic.
*/
- (std::optional<std::string>)cxx_creditsFormattedForLegacySubstitution
{
    OOCreditsQuantity tenthsOfCredits = [self deciCredits];
    unsigned long long integerCredits = tenthsOfCredits / 10;
    unsigned long long tenths = tenthsOfCredits % 10;

    return oo::str::format("%llu.%llu", integerCredits, tenths);
}

// Implements string expansion code [commander_bounty].
- (std::optional<std::string>)cxx_commanderBountyAsString
{
    return oo::str::format("%i", [self legalStatus]);
}

// Implements string expansion code [commander_kills].
- (std::optional<std::string>)cxx_commanderKillsAsString
{
    return oo::str::format("%i", [self score]);
}

// utilising new keyconfig2.plist data
- (std::optional<std::string>)cxx_keyBindingDescription2:(const std::string&)binding
{
    const auto keyEntry = keyconfig2_settings.find(binding);
    const oo::PList keyList = (keyEntry != keyconfig2_settings.end()) ? keyEntry->second : oo::PList();
    if (keyList.isNull()) {
        // no such setting
        return std::nullopt;
    }
    return [self cxx_getKeyBindingDescription:keyList];
}

- (std::optional<std::string>)cxx_getKeyBindingDescription:(const oo::PList&)keyList
{
    NSUInteger i = 0;
    std::string final;
    const NSUInteger count = keyList.isArray() ? keyList.count() : 0; // -objectAtIndex: raised on anything else
    for (i = 0; i < count; i++) {
        if (i != 0)
            final += " or ";
        const oo::PList* def = keyList.at(i);
        OOKeyCode k_int = (OOKeyCode)IntegerValueOf(def->find("key"));
        const std::string desc = [self cxx_keyCodeDescription:k_int].value_or("(null)"); // %@ of nil
        // 0 = key not set
        if (k_int != 0) {
            if (BoolValueOf(def->find("mod2")) == YES)
                final += keyMod2Text + "+";
            if (BoolValueOf(def->find("mod1")) == YES)
                final += keyMod1Text + "+";
            if (BoolValueOf(def->find("shift")) == YES)
                final += keyShiftText + "+";
            final += desc;
        }
    }
    return final;
}

- (std::optional<std::string>)cxx_keyCodeDescription:(OOKeyCode)code
{
    switch (code) {
    case 0:
        return oo::OptionalString(DESC(@"oolite-keycode-unset"));
    case 9:
        return oo::OptionalString(DESC(@"oolite-keycode-tab"));
    case 13:
        return oo::OptionalString(DESC(@"oolite-keycode-enter"));
    case 27:
        return oo::OptionalString(DESC(@"oolite-keycode-esc"));
    case 32:
        return oo::OptionalString(DESC(@"oolite-keycode-space"));
    case gvFunctionKey1:
        return oo::OptionalString(DESC(@"oolite-keycode-f1"));
    case gvFunctionKey2:
        return oo::OptionalString(DESC(@"oolite-keycode-f2"));
    case gvFunctionKey3:
        return oo::OptionalString(DESC(@"oolite-keycode-f3"));
    case gvFunctionKey4:
        return oo::OptionalString(DESC(@"oolite-keycode-f4"));
    case gvFunctionKey5:
        return oo::OptionalString(DESC(@"oolite-keycode-f5"));
    case gvFunctionKey6:
        return oo::OptionalString(DESC(@"oolite-keycode-f6"));
    case gvFunctionKey7:
        return oo::OptionalString(DESC(@"oolite-keycode-f7"));
    case gvFunctionKey8:
        return oo::OptionalString(DESC(@"oolite-keycode-f8"));
    case gvFunctionKey9:
        return oo::OptionalString(DESC(@"oolite-keycode-f9"));
    case gvFunctionKey10:
        return oo::OptionalString(DESC(@"oolite-keycode-f10"));
    case gvFunctionKey11:
        return oo::OptionalString(DESC(@"oolite-keycode-f11"));
    case gvArrowKeyRight:
        return oo::OptionalString(DESC(@"oolite-keycode-right"));
    case gvArrowKeyLeft:
        return oo::OptionalString(DESC(@"oolite-keycode-left"));
    case gvArrowKeyDown:
        return oo::OptionalString(DESC(@"oolite-keycode-down"));
    case gvArrowKeyUp:
        return oo::OptionalString(DESC(@"oolite-keycode-up"));
    case gvHomeKey:
        return oo::OptionalString(DESC(@"oolite-keycode-home"));
    case gvEndKey:
        return oo::OptionalString(DESC(@"oolite-keycode-end"));
    case gvInsertKey:
        return oo::OptionalString(DESC(@"oolite-keycode-insert"));
    case gvDeleteKey:
        return oo::OptionalString(DESC(@"oolite-keycode-delete"));
    case gvPageUpKey:
        return oo::OptionalString(DESC(@"oolite-keycode-pageup"));
    case gvPageDownKey:
        return oo::OptionalString(DESC(@"oolite-keycode-pagedown"));
    case gvNumberPadKey0:
        return oo::OptionalString(DESC(@"oolite-keycode-numpad0"));
    case gvNumberPadKey1:
        return oo::OptionalString(DESC(@"oolite-keycode-numpad1"));
    case gvNumberPadKey2:
        return oo::OptionalString(DESC(@"oolite-keycode-numpad2"));
    case gvNumberPadKey3:
        return oo::OptionalString(DESC(@"oolite-keycode-numpad3"));
    case gvNumberPadKey4:
        return oo::OptionalString(DESC(@"oolite-keycode-numpad4"));
    case gvNumberPadKey5:
        return oo::OptionalString(DESC(@"oolite-keycode-numpad5"));
    case gvNumberPadKey6:
        return oo::OptionalString(DESC(@"oolite-keycode-numpad6"));
    case gvNumberPadKey7:
        return oo::OptionalString(DESC(@"oolite-keycode-numpad7"));
    case gvNumberPadKey8:
        return oo::OptionalString(DESC(@"oolite-keycode-numpad8"));
    case gvNumberPadKey9:
        return oo::OptionalString(DESC(@"oolite-keycode-numpad9"));
    case gvPrintScreenKey:
        return oo::OptionalString(DESC(@"oolite-keycode-printscreen"));
    case gvPauseKey:
        return oo::OptionalString(DESC(@"oolite-keycode-pause"));
    case gvNumberPadKeyDivide:
        return oo::OptionalString(DESC(@"oolite-keycode-numpad/"));
    case gvNumberPadKeyEquals:
        return oo::OptionalString(DESC(@"oolite-keycode-numpad="));
    case gvNumberPadKeyMinus:
        return oo::OptionalString(DESC(@"oolite-keycode-numpad-"));
    case gvNumberPadKeyMultiply:
        return oo::OptionalString(DESC(@"oolite-keycode-numpad*"));
    case gvNumberPadKeyPeriod:
        return oo::OptionalString(DESC(@"oolite-keycode-numpad."));
    case gvNumberPadKeyPlus:
        return oo::OptionalString(DESC(@"oolite-keycode-numpad+"));
    case gvNumberPadKeyEnter:
        return oo::OptionalString(DESC(@"oolite-keycode-numpadenter"));

    default:
        return oo::utf16ToUtf8(std::u16string(1, static_cast<char16_t>(code))); // %C
    }
}

- (std::optional<std::string>)cxx_keyCodeDescriptionShort:(OOKeyCode)code
{
    switch (code) {
    case 0:
        return oo::OptionalString(DESC(@"oolite-keycode-short-unset"));
    case 9:
        return oo::OptionalString(DESC(@"oolite-keycode-short-tab"));
    case 13:
        return oo::OptionalString(DESC(@"oolite-keycode-short-enter"));
    case 27:
        return oo::OptionalString(DESC(@"oolite-keycode-short-esc"));
    case 32:
        return oo::OptionalString(DESC(@"oolite-keycode-short-space"));
    case gvFunctionKey1:
        return oo::OptionalString(DESC(@"oolite-keycode-short-f1"));
    case gvFunctionKey2:
        return oo::OptionalString(DESC(@"oolite-keycode-short-f2"));
    case gvFunctionKey3:
        return oo::OptionalString(DESC(@"oolite-keycode-short-f3"));
    case gvFunctionKey4:
        return oo::OptionalString(DESC(@"oolite-keycode-short-f4"));
    case gvFunctionKey5:
        return oo::OptionalString(DESC(@"oolite-keycode-short-f5"));
    case gvFunctionKey6:
        return oo::OptionalString(DESC(@"oolite-keycode-short-f6"));
    case gvFunctionKey7:
        return oo::OptionalString(DESC(@"oolite-keycode-short-f7"));
    case gvFunctionKey8:
        return oo::OptionalString(DESC(@"oolite-keycode-short-f8"));
    case gvFunctionKey9:
        return oo::OptionalString(DESC(@"oolite-keycode-short-f9"));
    case gvFunctionKey10:
        return oo::OptionalString(DESC(@"oolite-keycode-short-f10"));
    case gvFunctionKey11:
        return oo::OptionalString(DESC(@"oolite-keycode-short-f11"));
    case gvArrowKeyRight:
        return oo::OptionalString(DESC(@"oolite-keycode-short-right"));
    case gvArrowKeyLeft:
        return oo::OptionalString(DESC(@"oolite-keycode-short-left"));
    case gvArrowKeyDown:
        return oo::OptionalString(DESC(@"oolite-keycode-short-down"));
    case gvArrowKeyUp:
        return oo::OptionalString(DESC(@"oolite-keycode-short-up"));
    case gvHomeKey:
        return oo::OptionalString(DESC(@"oolite-keycode-short-home"));
    case gvEndKey:
        return oo::OptionalString(DESC(@"oolite-keycode-short-end"));
    case gvInsertKey:
        return oo::OptionalString(DESC(@"oolite-keycode-short-insert"));
    case gvDeleteKey:
        return oo::OptionalString(DESC(@"oolite-keycode-short-delete"));
    case gvPageUpKey:
        return oo::OptionalString(DESC(@"oolite-keycode-short-pageup"));
    case gvPageDownKey:
        return oo::OptionalString(DESC(@"oolite-keycode-short-pagedown"));
    case gvNumberPadKey0:
        return oo::OptionalString(DESC(@"oolite-keycode-short-numpad0"));
    case gvNumberPadKey1:
        return oo::OptionalString(DESC(@"oolite-keycode-short-numpad1"));
    case gvNumberPadKey2:
        return oo::OptionalString(DESC(@"oolite-keycode-short-numpad2"));
    case gvNumberPadKey3:
        return oo::OptionalString(DESC(@"oolite-keycode-short-numpad3"));
    case gvNumberPadKey4:
        return oo::OptionalString(DESC(@"oolite-keycode-short-numpad4"));
    case gvNumberPadKey5:
        return oo::OptionalString(DESC(@"oolite-keycode-short-numpad5"));
    case gvNumberPadKey6:
        return oo::OptionalString(DESC(@"oolite-keycode-short-numpad6"));
    case gvNumberPadKey7:
        return oo::OptionalString(DESC(@"oolite-keycode-short-numpad7"));
    case gvNumberPadKey8:
        return oo::OptionalString(DESC(@"oolite-keycode-short-numpad8"));
    case gvNumberPadKey9:
        return oo::OptionalString(DESC(@"oolite-keycode-short-numpad9"));
    case gvPrintScreenKey:
        return oo::OptionalString(DESC(@"oolite-keycode-short-printscreen"));
    case gvPauseKey:
        return oo::OptionalString(DESC(@"oolite-keycode-short-pause"));
    case gvNumberPadKeyDivide:
        return oo::OptionalString(DESC(@"oolite-keycode-short-numpad/"));
    case gvNumberPadKeyEquals:
        return oo::OptionalString(DESC(@"oolite-keycode-short-numpad="));
    case gvNumberPadKeyMinus:
        return oo::OptionalString(DESC(@"oolite-keycode-short-numpad-"));
    case gvNumberPadKeyMultiply:
        return oo::OptionalString(DESC(@"oolite-keycode-short-numpad*"));
    case gvNumberPadKeyPeriod:
        return oo::OptionalString(DESC(@"oolite-keycode-short-numpad."));
    case gvNumberPadKeyPlus:
        return oo::OptionalString(DESC(@"oolite-keycode-short-numpad+"));
    case gvNumberPadKeyEnter:
        return oo::OptionalString(DESC(@"oolite-keycode-short-numpadenter"));
    default:
        return oo::utf16ToUtf8(std::u16string(1, static_cast<char16_t>(code))); // %C
    }
}

@end

Vector OOGalacticCoordinatesFromInternal(NSPoint internalCoordinates)
{
    return (Vector) { (float)internalCoordinates.x * 0.4f, (float)internalCoordinates.y * 0.2f, 0.0f };
}

NSPoint OOInternalCoordinatesFromGalactic(Vector galacticCoordinates)
{
    return (NSPoint) { (float)galacticCoordinates.x * 2.5f, (float)galacticCoordinates.y * 5.0f };
}
