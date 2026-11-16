/*

OOJSPlayerShip+ObjCBridge.h

TRANSITIONAL (proposed ADR-0056, amendments oo-ppc, oo-ykoy and oo-9ht.139; beads oo-ft5n, oo-9t14
and oo-1qr5, the slices of docs/phases/3-slices/OOJSPlayerShip.md): the sends of the PlayerShip
binding's converted natives to classes that are still Objective-C (the player, the universe, the
message GUI, the engine), one function per send, named after the file and the selector, the body
the send verbatim. The binding's category on PlayerEntity, whose bodies are the free functions
declared in OOJSPlayerShip.h, is implemented by one-line forwarders in OOJSPlayerShip+ObjCBridge.mm.
OOJSPlayerShip.mm has no class of its own, so there is no facade here. Imported by
OOJSPlayerShip.mm only.

Never add to this file except a send of that kind. Each function goes with its class's conversion
(PlayerEntity, Universe, GuiDisplayGen, OOJavaScriptEngine, OONull); the file is deleted by its
deletion bead once none is left.

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

#ifndef OOJSPLAYERSHIP_OBJCBRIDGE_H
#define OOJSPLAYERSHIP_OBJCBRIDGE_H

#import "PlayerEntity.h"
#import "Universe.h"

@class OOJavaScriptEngine;

// The engine and the player as InitOOJSPlayerShip() and the category's bodies reach them.
OOJavaScriptEngine* OOJSPlayerShipSharedEngine();
PlayerEntity* OOJSPlayerShipSharedPlayer();
id OOJSPlayerShipPlayerWeakRetain(PlayerEntity* player);
// -deleteJSSelf (Entity (OOJavaScriptExtensions)), which -setJSSelf:context: sends first.
void OOJSPlayerShipPlayerDeleteJSSelf(PlayerEntity* player);
// [OONull null] (PlayerShipGetProperty(): an inactive MFD).
id OOJSPlayerShipNull();

// The player, as PlayerShipGetProperty() reads it.
NSUInteger OOJSPlayerShipPlayerActiveMissile(PlayerEntity* player);
float OOJSPlayerShipPlayerFuelLeakRate(PlayerEntity* player);
bool OOJSPlayerShipPlayerIsDocked(PlayerEntity* player);
StationEntity* OOJSPlayerShipPlayerDockedStation(PlayerEntity* player);
std::optional<std::string> OOJSPlayerShipPlayerSpecialCargo(PlayerEntity* player);
HeadUpDisplay* OOJSPlayerShipPlayerHud(PlayerEntity* player);
OOGalacticHyperspaceBehaviour OOJSPlayerShipPlayerGalacticHyperspaceBehaviour(PlayerEntity* player);
NSPoint OOJSPlayerShipPlayerGalacticHyperspaceFixedCoords(PlayerEntity* player);
std::optional<std::string> OOJSPlayerShipPlayerFastEquipmentA(PlayerEntity* player);
std::optional<std::string> OOJSPlayerShipPlayerFastEquipmentB(PlayerEntity* player);
std::string OOJSPlayerShipPlayerCurrentPrimedEquipment(PlayerEntity* player);
GLfloat OOJSPlayerShipPlayerForwardShieldLevel(PlayerEntity* player);
GLfloat OOJSPlayerShipPlayerAftShieldLevel(PlayerEntity* player);
float OOJSPlayerShipPlayerMaxForwardShieldLevel(PlayerEntity* player);
float OOJSPlayerShipPlayerMaxAftShieldLevel(PlayerEntity* player);
float OOJSPlayerShipPlayerForwardShieldRechargeRate(PlayerEntity* player);
float OOJSPlayerShipPlayerAftShieldRechargeRate(PlayerEntity* player);
std::vector<std::optional<std::string>> OOJSPlayerShipPlayerMultiFunctionDisplayList(PlayerEntity* player);
bool OOJSPlayerShipPlayerDialIdentEngaged(PlayerEntity* player);
OOLongRangeChartMode OOJSPlayerShipPlayerLongRangeChartMode(PlayerEntity* player);
NSPoint OOJSPlayerShipPlayerGalaxyCoordinates(PlayerEntity* player);
NSPoint OOJSPlayerShipPlayerCursorCoordinates(PlayerEntity* player);
OOSystemID OOJSPlayerShipPlayerTargetSystemID(PlayerEntity* player);
OOSystemID OOJSPlayerShipPlayerNextHopTargetSystemID(PlayerEntity* player);
OOSystemID OOJSPlayerShipPlayerInfoSystemID(PlayerEntity* player);
OOSystemID OOJSPlayerShipPlayerPreviousSystemID(PlayerEntity* player);
OORouteType OOJSPlayerShipPlayerANAMode(PlayerEntity* player);
bool OOJSPlayerShipPlayerScoopOverride(PlayerEntity* player);
bool OOJSPlayerShipPlayerInjectorsEngaged(PlayerEntity* player);
bool OOJSPlayerShipPlayerMassLockable(PlayerEntity* player);
bool OOJSPlayerShipPlayerHyperspeedEngaged(PlayerEntity* player);
Entity* OOJSPlayerShipPlayerCompassTarget(PlayerEntity* player);
OOCompassMode OOJSPlayerShipPlayerCompassMode(PlayerEntity* player);
bool OOJSPlayerShipPlayerWeaponsOnline(PlayerEntity* player);
Vector OOJSPlayerShipPlayerViewpointOffsetAft(PlayerEntity* player);
Vector OOJSPlayerShipPlayerViewpointOffsetForward(PlayerEntity* player);
Vector OOJSPlayerShipPlayerViewpointOffsetPort(PlayerEntity* player);
Vector OOJSPlayerShipPlayerViewpointOffsetStarboard(PlayerEntity* player);
OOWeaponFacing OOJSPlayerShipPlayerCurrentWeaponFacing(PlayerEntity* player);
OOEquipmentType* OOJSPlayerShipPlayerWeaponTypeForFacing(PlayerEntity* player, OOWeaponFacing facing, bool strict);
oo::PList OOJSPlayerShipPlayerCommanderDataDictionary(PlayerEntity* player);
int OOJSPlayerShipPlayerTradeInFactor(PlayerEntity* player);
double OOJSPlayerShipPlayerRenovationCosts(PlayerEntity* player);
double OOJSPlayerShipPlayerRenovationFactor(PlayerEntity* player);
GLfloat OOJSPlayerShipPlayerFlightPitch(PlayerEntity* player);
GLfloat OOJSPlayerShipPlayerFlightRoll(PlayerEntity* player);
GLfloat OOJSPlayerShipPlayerFlightYaw(PlayerEntity* player);

// The universe and its message GUI, as PlayerShipGetProperty() reads them.
OOViewID OOJSPlayerShipUniverseViewDirection();
OOCreditsQuantity OOJSPlayerShipUniverseTradeInValueForCommanderDictionary(const oo::PList& cmdrDict);
OOColor* OOJSPlayerShipUniverseMessageGUITextColor();
OOColor* OOJSPlayerShipUniverseMessageGUITextCommsColor();

// The player's passengers, parcels and contracts (the contract methods and ValidateContracts()).
NSUInteger OOJSPlayerShipPlayerPassengerCount(PlayerEntity* player);
NSUInteger OOJSPlayerShipPlayerPassengerCapacity(PlayerEntity* player);
NSUInteger OOJSPlayerShipPlayerParcelCount(PlayerEntity* player);
bool OOJSPlayerShipPlayerAddPassenger(PlayerEntity* player, const std::string& name, unsigned start, unsigned destination, double eta, double fee, double advance, unsigned risk);
bool OOJSPlayerShipPlayerRemovePassenger(PlayerEntity* player, const std::string& name);
bool OOJSPlayerShipPlayerAddParcel(PlayerEntity* player, const std::string& name, unsigned start, unsigned destination, double eta, double fee, double premium, unsigned risk);
bool OOJSPlayerShipPlayerRemoveParcel(PlayerEntity* player, const std::string& name);
bool OOJSPlayerShipPlayerAwardContract(PlayerEntity* player, unsigned qty, const std::string& commodity, unsigned start, unsigned destination, double eta, double fee, double premium);
bool OOJSPlayerShipPlayerRemoveContract(PlayerEntity* player, const std::string& commodity, unsigned destination);
double OOJSPlayerShipPlayerClockTime(PlayerEntity* player);

// The player, the universe and the message GUI as the property setter, launch, cargo, autopilot, docking and pylon methods reach them (slice 2).
void OOJSPlayerShipPlayerSetFuelLeakRate(PlayerEntity* player, float value);
void OOJSPlayerShipPlayerSetMassLockable(PlayerEntity* player, bool newValue);
void OOJSPlayerShipPlayerSetLongRangeChartMode(PlayerEntity* player, OOLongRangeChartMode mode);
void OOJSPlayerShipPlayerDoScriptEvent(PlayerEntity* player, OOJSPropID message, const std::vector<oo::PList>& arguments);
void OOJSPlayerShipPlayerSetCompassMode(PlayerEntity* player, OOCompassMode value);
void OOJSPlayerShipPlayerValidateCompassTarget(PlayerEntity* player);
void OOJSPlayerShipPlayerSetNextCompassMode(PlayerEntity* player);
bool OOJSPlayerShipPlayerHasEquipmentItemProviding(PlayerEntity* player, const std::string& equipmentType);
void OOJSPlayerShipPlayerSetGalacticHyperspaceBehaviour(PlayerEntity* player, OOGalacticHyperspaceBehaviour galacticHyperspaceBehaviour);
void OOJSPlayerShipPlayerSetGalacticHyperspaceFixedCoords(PlayerEntity* player, NSPoint point);
void OOJSPlayerShipPlayerSetFastEquipmentA(PlayerEntity* player, const std::optional<std::string>& eqKey);
void OOJSPlayerShipPlayerSetFastEquipmentB(PlayerEntity* player, const std::optional<std::string>& eqKey);
bool OOJSPlayerShipPlayerSetPrimedEquipment(PlayerEntity* player, const std::string& eqKey, bool showMsg);
void OOJSPlayerShipPlayerDecreaseFlightPitch(PlayerEntity* player, double delta);
void OOJSPlayerShipPlayerDecreaseFlightRoll(PlayerEntity* player, double delta);
void OOJSPlayerShipPlayerDecreaseFlightYaw(PlayerEntity* player, double delta);
void OOJSPlayerShipPlayerSetForwardShieldLevel(PlayerEntity* player, GLfloat level);
void OOJSPlayerShipPlayerSetAftShieldLevel(PlayerEntity* player, GLfloat level);
void OOJSPlayerShipPlayerSetMaxForwardShieldLevel(PlayerEntity* player, float newValue);
void OOJSPlayerShipPlayerSetMaxAftShieldLevel(PlayerEntity* player, float newValue);
void OOJSPlayerShipPlayerSetForwardShieldRechargeRate(PlayerEntity* player, float newValue);
void OOJSPlayerShipPlayerSetAftShieldRechargeRate(PlayerEntity* player, float newValue);
void OOJSPlayerShipPlayerSetScoopOverride(PlayerEntity* player, bool newValue);
bool OOJSPlayerShipPlayerSwitchHudTo(PlayerEntity* player, const std::string& hudFileName);
void OOJSPlayerShipPlayerResetHud(PlayerEntity* player);
void OOJSPlayerShipPlayerAdjustTradeInFactorBy(PlayerEntity* player, int value);
bool OOJSPlayerShipPlayerSetWeaponMount(PlayerEntity* player, OOWeaponFacing facing, const std::string& eqKey, const std::optional<std::string>& context);
OOEntityStatus OOJSPlayerShipPlayerStatus(PlayerEntity* player);
void OOJSPlayerShipPlayerSetTargetSystemID(PlayerEntity* player, OOSystemID sid);
void OOJSPlayerShipPlayerSetInfoSystemID(PlayerEntity* player, OOSystemID sid, bool moveChart);
void OOJSPlayerShipUniverseMessageGUISetTextColor(OOColor* color);
void OOJSPlayerShipUniverseMessageGUISetTextCommsColor(OOColor* color);
void OOJSPlayerShipPlayerLaunchFromStation(PlayerEntity* player);
void OOJSPlayerShipPlayerRemoveAllCargo(PlayerEntity* player);
void OOJSPlayerShipPlayerUseSpecialCargo(PlayerEntity* player, const std::string& descriptionString);
Class OOJSPlayerShipStationEntityClass();
bool OOJSPlayerShipPlayerEngageAutopilotToStation(PlayerEntity* player, StationEntity* stationForDocking);
void OOJSPlayerShipPlayerDisengageAutopilot(PlayerEntity* player);
void OOJSPlayerShipPlayerRequestDockingClearance(PlayerEntity* player, StationEntity* stationForDocking);
void OOJSPlayerShipPlayerCancelDockingRequest(PlayerEntity* player, StationEntity* stationForDocking);
bool OOJSPlayerShipPlayerAssignToActivePylon(PlayerEntity* player, const std::string& identifierKey);

// The views, the hyperspace countdowns, the MFDs, primed equipment and the HUD dials (slice 3).
void OOJSPlayerShipPlayerSetCustomViewDataFromDictionary(PlayerEntity* player, const oo::PList& viewDict, bool withScaling);
void OOJSPlayerShipPlayerNoteSwitchToView(PlayerEntity* player, OOViewID toView, OOViewID fromView);
void OOJSPlayerShipPlayerResetCustomView(PlayerEntity* player);
void OOJSPlayerShipPlayerResetScannerZoom(PlayerEntity* player);
bool OOJSPlayerShipPlayerTakeInternalDamage(PlayerEntity* player);
bool OOJSPlayerShipPlayerHasHyperspaceMotor(PlayerEntity* player);
void OOJSPlayerShipPlayerSetStatus(PlayerEntity* player, OOEntityStatus stat);
bool OOJSPlayerShipPlayerWitchJumpChecklist(PlayerEntity* player, bool isGalacticJump);
void OOJSPlayerShipPlayerBeginWitchspaceCountdown(PlayerEntity* player, int spinTime);
void OOJSPlayerShipPlayerCancelWitchspaceCountdown(PlayerEntity* player);
void OOJSPlayerShipPlayerSetJumpType(PlayerEntity* player, bool isGalacticJump);
void OOJSPlayerShipPlayerSetWitchspaceCountdown(PlayerEntity* player, int spinTime);
void OOJSPlayerShipPlayerPlayGalacticHyperspace(PlayerEntity* player);
bool OOJSPlayerShipPlayerSetMultiFunctionDisplay(PlayerEntity* player, NSUInteger index, const std::optional<std::string>& key);
void OOJSPlayerShipPlayerSetMultiFunctionText(PlayerEntity* player, const std::optional<std::string>& text, const std::optional<std::string>& key);
void OOJSPlayerShipPlayerSetDialCustom(PlayerEntity* player, const oo::PList& value, const std::string& dialKey);
void OOJSPlayerShipUniverseAddMessage(const std::optional<std::string>& text, OOTimeDelta count);
GuiDisplayGen* OOJSPlayerShipUniverseGui();
std::optional<std::string> OOJSPlayerShipGuiReflowTextForMFD(GuiDisplayGen* gui, const std::optional<std::string>& input);

#endif // OOJSPLAYERSHIP_OBJCBRIDGE_H
