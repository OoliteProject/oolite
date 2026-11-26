/*

PlayerEntityScriptMethods.h

Methods for use by scripting mechanisms.


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

#import "PlayerEntity.h"

#include "oofnd/PList.hpp"
#include "oofnd/StdLib.hpp"

/*	Foundation sweep (proposed ADR-0043, bead oo-8mxr): the Foundation-typed selectors of this
        category have more direct callers than the sizing rule allows (PlayerEntity.mm,
        PlayerEntityControls.mm, PlayerEntityLegacyScriptEngine.mm, PlayerEntityKeyMapper.mm,
        OOStringExpander.mm, OOJSMission.mm, OOJSGlobal.mm, Universe.mm), so they are cxx_ twins here.
        Strings that could be nil are std::optional; a marker is an oo::PList Dict (null where it was
        nil).
*/
@interface PlayerEntity (ScriptMethods)

- (unsigned)score;
- (void)setScore:(unsigned)value;

- (double)creditBalance;
- (void)setCreditBalance:(double)value;

- (std::optional<std::string>)cxx_dockedStationName;
- (std::optional<std::string>)cxx_dockedStationDisplayName;
- (BOOL)dockedAtMainStation;

- (void)cxx_awardCommodityType:(const std::string&)type amount:(OOCargoQuantity)amount;

- (void)resetScannerZoom;

- (OOGalaxyID)currentGalaxyID;
- (OOSystemID)currentSystemID;

- (void)cxx_setMissionChoice:(const std::optional<std::string>&)newChoice;
- (void)cxx_setMissionChoice:(const std::optional<std::string>&)newChoice withEvent:(BOOL)withEvent;
- (void)cxx_setMissionChoice:(const std::optional<std::string>&)newChoice keyPress:(const std::optional<std::string>&)keyPress;
- (void)cxx_setMissionChoice:(const std::optional<std::string>&)newChoice keyPress:(const std::optional<std::string>&)keyPress withEvent:(BOOL)withEvent;
- (void)allowMissionInterrupt;

- (OOTimeDelta)scriptTimer;

- (unsigned)systemPseudoRandom100;
- (unsigned)systemPseudoRandom256;
- (double)systemPseudoRandomFloat;

- (oo::PList)cxx_passengerContractMarker:(OOSystemID)system;
- (oo::PList)cxx_parcelContractMarker:(OOSystemID)system;
- (oo::PList)cxx_cargoContractMarker:(OOSystemID)system;
- (oo::PList)cxx_defaultMarker:(OOSystemID)system;
- (oo::PList)cxx_validatedMarker:(const oo::PList&)marker;

- (std::optional<std::string>)cxx_keyBindingDescription2:(const std::string&)binding;
- (std::optional<std::string>)cxx_getKeyBindingDescription:(const oo::PList&)keyList;
- (std::optional<std::string>)cxx_keyCodeDescription:(OOKeyCode)code;
- (std::optional<std::string>)cxx_keyCodeDescriptionShort:(OOKeyCode)code;

- (std::optional<std::string>)cxx_commanderKillsAsString;
- (std::optional<std::string>)cxx_commanderBountyAsString;
- (std::optional<std::string>)cxx_creditsFormattedForSubstitution;
- (std::optional<std::string>)cxx_creditsFormattedForLegacySubstitution;
// OOStringExpander's special substitution table sends these by name: the cxx_ result above as an
// Objective-C string, or nil.
- (oo::PList)commanderKillsAsString; // called by name (ADR-0043 item 21)
- (oo::PList)commanderBountyAsString; // called by name (ADR-0043 item 21)
- (oo::PList)creditsFormattedForSubstitution; // called by name (ADR-0043 item 21)
- (oo::PList)creditsFormattedForLegacySubstitution; // called by name (ADR-0043 item 21)

@end

/*	OOGalacticCoordinatesFromInternal()
        Given internal coordinates ranging from 0 to 255 on each axis, return
        corresponding coordinates in user-meaningful coordinates by scaling by
        0.4 on the X axis and 0.2 on the Y axis.

        OOInternalCoordinatesFromGalactic()
        Inverse operation.

        For valid floating-point comparisons, it is imperative that the same
        calculation be used consistently.
 */
#ifdef __cplusplus
extern "C" {
#endif

Vector OOGalacticCoordinatesFromInternal(NSPoint internalCoordinates);
NSPoint OOInternalCoordinatesFromGalactic(Vector galacticCoordinates);

#ifdef __cplusplus
}
#endif
