/*

PlayerEntity+ObjCBridge.h

TRANSITIONAL: the Objective-C PlayerEntity, the facade over the C++ cxx::PlayerEntity
(PlayerEntity.h) while the class converts slice by slice (docs/phases/3-slices/PlayerEntity.md).
It is a subclass of the ship's facade (ShipEntity+ObjCBridge.h), and the object's identity. Its
interface is the one PlayerEntity.h declared before slice 1, copied exactly; only +sharedPlayer
and -deferredInit moved, to the category that implements them beside -init and -dealloc. Its
methods keep their Objective-C bodies until their slice moves them to cxx::PlayerEntity and leaves
a forwarder here. It has one ivar, _cxxPlayer: the root's _cxxEntity, typed, borrowed (the root
owns the part), set by the initialiser beside the ship's _cxxShip; unconverted code reads the
player's members through it by their old names (_cxxPlayer->hud, player->_cxxPlayer->hud). Its
-init makes the player's adapter over cxx::PlayerEntity (oo::ObjCEntity<cxx::PlayerEntity>).
Imported as the last line of PlayerEntity.h; do not import it directly. Never add to this file.
Deleted once every slice and the categories are C++.

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

#ifndef PLAYERENTITY_OBJCBRIDGE_H
#define PLAYERENTITY_OBJCBRIDGE_H

@interface PlayerEntity : ShipEntity {
@public
    cxx::PlayerEntity* _cxxPlayer; // _cxxEntity, typed; borrowed, set by the initialiser
}

- (BOOL)setUpAndConfirmOK:(BOOL)stopOnError;
- (BOOL)setUpAndConfirmOK:(BOOL)stopOnError saveGame:(BOOL)loadingGame;
- (void)completeSetUp;
- (void)completeSetUpAndSetTarget:(BOOL)setTarget;
- (void)startUpComplete;

- (std::optional<std::string>)cxx_commanderName;
- (void)cxx_setCommanderName:(const std::optional<std::string>&)value; // never nullopt
- (std::optional<std::string>)cxx_lastsaveName;
- (void)cxx_setLastsaveName:(const std::optional<std::string>&)value; // never nullopt

- (BOOL)isDocked;

- (void)warnAboutHostiles;

- (void)unloadCargoPods;
- (void)loadCargoPods;
- (void)unloadAllCargoPodsForType:(const std::string&)type toManifest:(OOCommodityMarket*)manifest;
- (void)unloadCargoPodsForType:(const std::string&)type amount:(OOCargoQuantity)quantity;
- (void)loadCargoPodsForType:(const std::string&)type fromManifest:(OOCommodityMarket*)manifest;
- (void)loadCargoPodsForType:(const std::string&)type amount:(OOCargoQuantity)quantity;
- (OOCommodityMarket*)shipCommodityData;

- (OOCreditsQuantity)deciCredits;

- (int)random_factor;
- (void)setRandom_factor:(int)rf;
- (OOGalaxyID)galaxyNumber;
- (NSPoint)galaxy_coordinates;
- (void)setGalaxyCoordinates:(NSPoint)newPosition;
- (void)setCustomChartCentre:(NSPoint)coords;
- (NSPoint)cursor_coordinates;
- (NSPoint)chart_centre_coordinates;
- (NSPoint)custom_chart_centre_coordinates;
- (OOScalar)chart_zoom;
- (OOScalar)custom_chart_zoom;
- (void)setCustomChartZoom:(OOScalar)zoom;
- (NSPoint)adjusted_chart_centre;
- (OORouteType)ANAMode;

- (std::optional<std::string>)cxx_jumpCause;
- (void)cxx_setJumpCause:(const std::optional<std::string>&)value; // never nullopt

- (OOSystemID)systemID;
- (void)setSystemID:(OOSystemID)sid;
- (OOSystemID)targetSystemID;
- (void)setTargetSystemID:(OOSystemID)sid;
- (OOSystemID)previousSystemID;
- (void)setPreviousSystemID:(OOSystemID)sid;
- (OOSystemID)nextHopTargetSystemID;
- (OOSystemID)infoSystemID;
- (void)setInfoSystemID:(OOSystemID)sid moveChart:(BOOL)moveChart;
- (void)nextInfoSystem;
- (void)previousInfoSystem;
- (void)homeInfoSystem;
- (void)targetInfoSystem;
- (BOOL)infoSystemOnRoute;

- (oo::PList)cxx_commanderDataDictionary; // a Dict, as saved
- (BOOL)cxx_setCommanderDataFromDictionary:(const oo::PList&)dict;

- (void)addEquipmentWithScriptToCustomKeyArray:(const std::string&)equipmentKey;
- (void)validateCustomEquipActivationArray;

- (void)doBookkeeping:(double)delta_t;
- (BOOL)isValidTarget:(Entity*)target;

- (void)setMassLockable:(BOOL)newValue;
- (BOOL)massLockable;
- (BOOL)massLocked;
- (BOOL)atHyperspeed;

- (float)occlusionLevel;
- (void)setOcclusionLevel:(float)level;

- (void)setDockedAtMainStation;
- (StationEntity*)dockedStation;
// Dumb setter; callers are responsible for sanity.
- (void)setDockedStation:(StationEntity*)station;

- (void)performDockingRequest:(StationEntity*)stationForDocking;
- (void)requestDockingClearance:(StationEntity*)stationForDocking;
- (void)cancelDockingRequest:(StationEntity*)stationForDocking;
- (BOOL)engageAutopilotToStation:(StationEntity*)stationForDocking;
- (void)disengageAutopilot;

- (void)resetAutopilotAI;

- (void)setTargetDockStationTo:(StationEntity*)value;
- (StationEntity*)getTargetDockStation;

- (HeadUpDisplay*)hud;
- (BOOL)cxx_switchHudTo:(const std::string&)hudFileName;
- (void)resetHud;

- (float)cxx_dialCustomFloat:(const std::string&)dialKey;
- (std::string)cxx_dialCustomString:(const std::string&)dialKey;
- (OOColor*)cxx_dialCustomColor:(const std::string&)dialKey;
- (void)cxx_setDialCustom:(const oo::PList&)value forKey:(const std::string&)dialKey; // value: any script value, kept as given (live objects as Object nodes)

- (std::vector<std::optional<std::string>>)cxx_multiFunctionDisplayList; // nullopt = inactive MFD
- (std::optional<std::string>)cxx_multiFunctionText:(NSUInteger)index;
- (void)cxx_setMultiFunctionText:(const std::optional<std::string>&)text forKey:(const std::optional<std::string>&)key;
- (BOOL)cxx_setMultiFunctionDisplay:(NSUInteger)index toKey:(const std::optional<std::string>&)key;
- (void)cycleNextMultiFunctionDisplay:(NSUInteger)index;
- (void)cyclePreviousMultiFunctionDisplay:(NSUInteger)index;
- (void)selectNextMultiFunctionDisplay;
- (void)selectPreviousMultiFunctionDisplay;
- (NSUInteger)activeMFD;

- (void)setShowDemoShips:(BOOL)value;
- (BOOL)showDemoShips;

- (GLfloat)forwardShieldLevel;
- (GLfloat)aftShieldLevel;
- (GLfloat)baseMass;

- (void)setForwardShieldLevel:(GLfloat)level;
- (void)setAftShieldLevel:(GLfloat)level;

- (float)forwardShieldRechargeRate;
- (float)aftShieldRechargeRate;

- (void)setMaxForwardShieldLevel:(float)newValue;
- (void)setMaxAftShieldLevel:(float)newValue;
- (void)setForwardShieldRechargeRate:(float)newValue;
- (void)setAftShieldRechargeRate:(float)newValue;

// return keyconfig.plist settings for scripting
- (oo::PList)cxx_keyConfig;
- (BOOL)isMouseControlOn;

- (GLfloat)dialRoll;
- (GLfloat)dialPitch;
- (GLfloat)dialYaw;
- (GLfloat)dialSpeed;
- (GLfloat)dialHyperSpeed;

- (void)currentWeaponStats;

- (GLfloat)dialForwardShield;
- (GLfloat)dialAftShield;

- (GLfloat)dialEnergy;
- (GLfloat)dialMaxEnergy;

- (GLfloat)dialFuel;
- (GLfloat)dialHyperRange;

- (GLfloat)dialAltitude;

- (unsigned)countMissiles;
- (OOMissileStatus)dialMissileStatus;

- (OOFuelScoopStatus)dialFuelScoopStatus;

- (float)fuelLeakRate;
- (void)setFuelLeakRate:(float)value;

#if OO_VARIABLE_TORUS_SPEED
- (GLfloat)hyperspeedFactor;
#endif
- (BOOL)injectorsEngaged;
- (BOOL)hyperspeedEngaged;

- (std::vector<oo::PList>*)cxx_customEquipmentActivation; // the live entries

- (double)clockTime; // Note that this is not an OOTimeAbsolute
- (double)clockTimeAdjusted; // Note that this is not an OOTimeAbsolute
- (BOOL)clockAdjusting;
- (void)addToAdjustTime:(double)seconds;

- (double)escapePodRescueTime;
- (void)setEscapePodRescueTime:(double)seconds;

- (std::string)cxx_dial_clock;
- (std::string)cxx_dial_clock_adjusted;
- (std::string)cxx_dial_fpsinfo;
- (std::string)cxx_dial_objinfo;

- (std::vector<std::string>*)cxx_commLog; // the live log, trimmed first (ADR-0043 item 22)

- (Entity*)compassTarget;
- (void)setCompassTarget:(Entity*)value;
- (void)validateCompassTarget;

- (std::optional<std::string>)cxx_compassTargetLabel;

- (OOCompassMode)compassMode;
- (void)setCompassMode:(OOCompassMode)value;
- (void)setPrevCompassMode;
- (void)setNextCompassMode;

- (NSUInteger)activeMissile;
- (void)setActiveMissile:(NSUInteger)value;
- (NSUInteger)dialMaxMissiles;
- (BOOL)dialIdentEngaged;
- (void)setDialIdentEngaged:(BOOL)newValue;
- (std::optional<std::string>)cxx_specialCargo;
- (std::optional<std::string>)cxx_dialTargetName;
- (ShipEntity*)missileForPylon:(NSUInteger)value;
- (void)safeAllMissiles;
- (void)selectNextMissile;
- (void)tidyMissilePylons;
- (BOOL)removeFromPylon:(NSUInteger)pylon;
- (BOOL)cxx_assignToActivePylon:(const std::string&)identifierKey;

- (void)clearAlertFlags;
- (int)alertFlags;
- (void)setAlertFlag:(int)flag to:(BOOL)value;
- (OOAlertCondition)alertCondition;
- (OOPlayerFleeingStatus)fleeingStatus;

- (BOOL)mountMissile:(ShipEntity*)missile;
- (BOOL)cxx_mountMissileWithRole:(const std::string&)role;

- (OOEnergyUnitType)installedEnergyUnitType;
- (OOEnergyUnitType)energyUnitType;

- (ShipEntity*)launchMine:(ShipEntity*)mine;

- (BOOL)activateCloakingDevice;
- (void)deactivateCloakingDevice;

- (double)scannerFuzziness;

- (BOOL)weaponsOnline;
- (void)setWeaponsOnline:(BOOL)newValue;

- (BOOL)fireMainWeapon;

- (OOWeaponType)weaponForFacing:(OOWeaponFacing)facing;
- (OOWeaponType)currentWeapon;
- (std::vector<Vector>)cxx_currentLaserOffset;

- (void)rotateCargo;

- (BOOL)hasSufficientFuelForJump;

- (BOOL)witchJumpChecklist:(BOOL)isGalacticJump;
- (void)enterGalacticWitchspace;
- (void)setJumpType:(BOOL)isGalacticJump;

- (BOOL)takeInternalDamage;

- (BOOL)cxx_endScenario:(const std::string&)key;

- (std::vector<std::string>)cxx_roleWeights; // a copy
- (void)addRoleForAggression:(ShipEntity*)victim;
- (void)addRoleForMining;
- (void)cxx_addRoleToPlayer:(const std::string&)role;
- (void)cxx_addRoleToPlayer:(const std::string&)role inSlot:(NSUInteger)slot;
- (void)clearRoleFromPlayer:(BOOL)includingLongRange;
- (void)clearRolesFromPlayer:(float)chance;
- (NSUInteger)maxPlayerRoles;
- (void)updateSystemMemory;

- (void)loseTargetStatus;

- (void)docked;

- (void)setGuiToStatusScreen;
- (std::vector<oo::PList>)cxx_equipmentList; // Each entry is an Array: a string, a bool for availability (false = damaged), then a colour Object (absent for the default colour).
- (BOOL)cxx_setPrimedEquipment:(const std::string&)eqKey showMessage:(BOOL)showMsg;
- (std::optional<std::string>)cxx_primedEquipmentName:(NSInteger)offset;
- (std::string)cxx_currentPrimedEquipment; // "": primed-none
- (NSUInteger)primedEquipmentCount;
- (void)activatePrimableEquipment:(NSUInteger)index withMode:(OOPrimedEquipmentMode)mode;
- (std::optional<std::string>)cxx_fastEquipmentA;
- (std::optional<std::string>)cxx_fastEquipmentB;
- (void)cxx_setFastEquipmentA:(const std::optional<std::string>&)eqKey;
- (void)cxx_setFastEquipmentB:(const std::optional<std::string>&)eqKey;

- (OOCreditsQuantity)cxx_adjustPriceByScriptForEqKey:(const std::string&)eqKey withCurrent:(OOCreditsQuantity)price;

- (std::vector<std::string>)cxx_cargoList;
- (unsigned)legalStatusOfCargoList;

- (void)setGuiToSystemDataScreen;
- (void)setGuiToSystemDataScreenRefreshBackground:(BOOL)refreshBackground;
- (std::optional<std::map<int, std::vector<oo::PList>>>)cxx_markedDestinations; // marker Dicts by system ID, each list in the order the markers were added
- (void)setGuiToLongRangeChartScreen;
- (void)setGuiToShortRangeChartScreen;
- (void)setGuiToChartScreenFrom:(OOGUIScreenID)oldScreen;
- (void)setGuiToLoadSaveScreen;
- (void)setGuiToGameOptionsScreen;
- (OOWeaponFacingSet)availableFacings;
- (void)cxx_setGuiToEquipShipScreen:(int)skip selectingFacingFor:(const std::optional<std::string>&)eqKeyForSelectFacing; // nullopt: the normal list
- (void)setGuiToEquipShipScreen:(int)skip;

- (void)setGuiToInterfacesScreen:(int)skip;
- (void)showInformationForSelectedInterface;
- (void)activateSelectedInterface;

- (void)highlightEquipShipScreenKey:(const std::string&)key;
- (void)showInformationForSelectedUpgrade;
- (void)cxx_showInformationForSelectedUpgradeWithFormatString:(const std::optional<std::string>&)extraString; // a runtime format with one %@
- (BOOL)setWeaponMount:(OOWeaponFacing)chosen_weapon_facing toWeapon:(const std::string&)eqKey; // flipped with its family (bead oo-3rb.258)
- (BOOL)cxx_setWeaponMount:(OOWeaponFacing)facing toWeapon:(const std::string&)eqKey inContext:(const std::optional<std::string>&)context;

- (BOOL)changePassengerBerths:(int)addRemove;
- (OOCargoQuantity)cxx_cargoQuantityForType:(const std::string&)type;
- (OOCargoQuantity)cxx_setCargoQuantityForType:(const std::string&)type amount:(OOCargoQuantity)amount;
- (void)calculateCurrentCargo;
- (void)setGuiToMarketScreen;
- (void)setGuiToMarketInfoScreen;
- (std::vector<std::string>)cxx_applyMarketFilter:(const std::vector<std::string>&)goods onMarket:(OOCommodityMarket*)market;
- (std::vector<std::string>)cxx_applyMarketSorter:(const std::vector<std::string>&)goods onMarket:(OOCommodityMarket*)market;
- (OOCommodityMarket*)localMarket;

- (void)setupStartScreenGui;
- (void)setGuiToIntroFirstGo:(BOOL)justCobra;
- (void)setGuiToOXZManager;

- (void)noteGUIWillChangeTo:(OOGUIScreenID)toScreen;
- (void)noteGUIDidChangeFrom:(OOGUIScreenID)fromScreen to:(OOGUIScreenID)toScreen refresh:(BOOL)refresh;
- (void)noteGUIDidChangeFrom:(OOGUIScreenID)fromScreen to:(OOGUIScreenID)toScreen;
- (void)noteViewDidChangeFrom:(OOViewID)fromView toView:(OOViewID)toView;

- (OOGUIScreenID)guiScreen;

- (void)buySelectedItem;

- (BOOL)cxx_tryBuyingCommodity:(const std::string&)type all:(BOOL)all; // "<<<" / ">>>" page the market
- (BOOL)cxx_trySellingCommodity:(const std::string&)type all:(BOOL)all;

- (OOSpeechSettings)isSpeechOn;

- (void)addEquipmentFromCollection:(const oo::PList&)equipment; // equipment may be an array, a dictionary whose values are all YES, or a string.

- (void)getFined;
- (void)adjustTradeInFactorBy:(int)value;
- (int)tradeInFactor;
- (double)renovationCosts;
- (double)renovationFactor;

- (void)setDefaultViewOffsets;
- (void)setDefaultCustomViews;
- (Vector)weaponViewOffset;

- (void)setUpTrumbles;
- (void)addTrumble:(OOTrumble*)papaTrumble;
- (void)removeTrumble:(OOTrumble*)deadTrumble;
- (OOTrumble**)trumbleArray;
- (NSUInteger)trumbleCount;
// loading and saving trumbleCount
- (oo::PList)trumbleValue; // [count, hash, trumble records]
- (void)setTrumbleValueFrom:(const oo::PList&)trumbleValue; // null: none saved

- (float)trumbleAppetiteAccumulator;
- (void)setTrumbleAppetiteAccumulator:(float)value;

- (void)mungChecksumWithString:(const std::optional<std::string>&)str; // its UTF-16 units; nullopt does nothing

- (std::optional<std::string>)cxx_screenModeStringForWidth:(unsigned)inWidth height:(unsigned)inHeight refreshRate:(float)inRate;

- (void)suppressTargetLost;

- (void)setScoopsActive;

- (void)clearTargetMemory;
- (std::vector<oo::ObjCRef<OOWeakReference*>>)cxx_targetMemory; // a copy; a null ref is an empty slot
- (BOOL)moveTargetMemoryBy:(NSInteger)delta;

- (void)printIdentLockedOnForMissile:(BOOL)missile;

- (void)applyYaw:(GLfloat)yaw;

/* GILES custom viewpoints */

// custom view points
- (Quaternion)customViewQuaternion;
- (void)setCustomViewQuaternion:(Quaternion)q1;
- (OOMatrix)customViewMatrix;
- (Vector)customViewOffset;
- (void)setCustomViewOffset:(Vector)offset;
- (Vector)customViewRotationCenter;
- (void)setCustomViewRotationCenter:(Vector)center;
- (void)customViewZoomOut:(OOScalar)rate;
- (void)customViewZoomIn:(OOScalar)rate;
- (void)customViewRotateLeft:(OOScalar)angle;
- (void)customViewRotateRight:(OOScalar)angle;
- (void)customViewRotateUp:(OOScalar)angle;
- (void)customViewRotateDown:(OOScalar)angle;
- (void)customViewRollLeft:(OOScalar)angle;
- (void)customViewRollRight:(OOScalar)angle;
- (void)customViewPanUp:(OOScalar)angle;
- (void)customViewPanDown:(OOScalar)angle;
- (void)customViewPanLeft:(OOScalar)angle;
- (void)customViewPanRight:(OOScalar)angle;
- (Vector)customViewForwardVector;
- (Vector)customViewUpVector;
- (Vector)customViewRightVector;
- (std::optional<std::string>)cxx_customViewDescription;
- (void)resetCustomView;
- (void)setCustomViewData;
- (void)cxx_setCustomViewDataFromDictionary:(const oo::PList&)viewDict withScaling:(BOOL)withScaling; // a null viewDict (was nil) resets the matrix and offset only
- (HPVector)viewpointPosition;
- (HPVector)breakPatternPosition;
- (Vector)viewpointOffset;
- (Vector)viewpointOffsetAft;
- (Vector)viewpointOffsetForward;
- (Vector)viewpointOffsetPort;
- (Vector)viewpointOffsetStarboard;

- (oo::PList)cxx_missionOverlayDescriptor;
- (oo::PList)cxx_missionOverlayDescriptorOrDefault;
- (void)cxx_setMissionOverlayDescriptor:(const oo::PList&)descriptor;

- (oo::PList)cxx_missionBackgroundDescriptor;
- (oo::PList)cxx_missionBackgroundDescriptorOrDefault;
- (void)cxx_setMissionBackgroundDescriptor:(const oo::PList&)descriptor;
- (OOGUIBackgroundSpecial)missionBackgroundSpecial;
- (void)cxx_setMissionBackgroundSpecial:(const std::string&)special; // "" (was nil) = none
- (void)setMissionExitScreen:(OOGUIScreenID)screen;
- (OOGUIScreenID)missionExitScreen;
- (void)clearExtraMissionKeys;
- (void)cxx_setExtraMissionKeys:(const oo::PList&)keys; // a Dict of key name -> key definitions

- (void)cxx_clearExtraGuiScreenKeys:(OOGUIScreenID)gui key:(const std::string&)key;
- (BOOL)setExtraGuiScreenKeys:(OOGUIScreenID)gui definition:(OOJSGuiScreenKeyDefinition*)definition;

// Nasty hack to keep background textures around while on equip screens.
- (oo::PList)cxx_equipScreenBackgroundDescriptor;
- (void)cxx_setEquipScreenBackgroundDescriptor:(const oo::PList&)descriptor;

- (BOOL)scriptsLoaded;
- (std::vector<std::string>)cxx_worldScriptNames; // in load order
- (std::vector<std::pair<std::string, oo::ObjCRef<OOScript*>>>)cxx_worldScriptsByName; // in load order

- (OOScript*)cxx_commodityScriptNamed:(const std::optional<std::string>&)script; // nullopt: nil

// *** World script events.
// In general, script events should be sent through doScriptEvent:..., which
// will forward to the world scripts.
- (BOOL)doWorldEventUntilMissionScreen:(OOJSPropID)message;
// argv is borrowed: the caller remains responsible for freeing the values.
- (void)doWorldScriptEvent:(OOJSPropID)message inContext:(JSContext*)context withArguments:(JSValue*)argv count:(int)argc timeLimit:(OOTimeDelta)limit;

- (BOOL)showInfoFlag;

- (void)setGalacticHyperspaceBehaviour:(OOGalacticHyperspaceBehaviour)galacticHyperspaceBehaviour;
- (OOGalacticHyperspaceBehaviour)galacticHyperspaceBehaviour;
- (void)setGalacticHyperspaceFixedCoords:(NSPoint)point;
- (void)setGalacticHyperspaceFixedCoordsX:(unsigned char)x y:(unsigned char)y;
- (NSPoint)galacticHyperspaceFixedCoords;
- (void)setWitchspaceCountdown:(int)spin_time;

- (OOLongRangeChartMode)longRangeChartMode;
- (void)setLongRangeChartMode:(OOLongRangeChartMode)mode;

- (BOOL)scoopOverride;
- (void)setScoopOverride:(BOOL)newValue;
- (void)setDockTarget:(ShipEntity*)entity;

- (BOOL)clearedToDock;
- (void)setDockingClearanceStatus:(OODockingClearanceStatus)newValue;
- (OODockingClearanceStatus)getDockingClearanceStatus;
- (void)penaltyForUnauthorizedDocking;

- (std::vector<oo::ObjCRef<WormholeEntity*>>)cxx_scannedWormholes;

- (WormholeEntity*)wormhole;
- (void)setWormhole:(WormholeEntity*)newWormhole;
- (void)addScannedWormhole:(WormholeEntity*)wormhole;

- (void)initialiseMissionDestinations:(const oo::PList&)destinations andLegacy:(const oo::PList&)legacy; // used only if a Dict / an Array
- (std::optional<std::string>)markerKey:(const oo::PList&)marker;
- (void)cxx_addMissionDestinationMarker:(const oo::PList&)marker;
- (BOOL)cxx_removeMissionDestinationMarker:(const oo::PList&)marker;
- (oo::PList)cxx_getMissionDestinations; // a snapshot Dict

- (oo::PList::Dict*)cxx_shipyardRecord;

- (void)cxx_setLastShot:(const std::vector<oo::ObjCRef<OOLaserShotEntity*>>&)shot;

- (void)cxx_showShipModelWithKey:(const std::string&)shipKey shipData:(const oo::PList&)shipData personality:(uint16_t)personality factorX:(GLfloat)factorX factorY:(GLfloat)factorY factorZ:(GLfloat)factorZ inContext:(const std::optional<std::string>&)context; // null shipData: the registry's

/* Fractional expression of amount of entry inside a planet's atmosphere. 0.0f is out of atmosphere,
   1.0f is fully in and is normally associated with the point of ship destruct due to altitude.
*/
- (GLfloat)insideAtmosphereFraction;

@end

// Implemented by the facade's category in PlayerEntity+ObjCBridge.mm with -init and -dealloc (they
// need the Objective-C object as self), while the class's @implementation is still PlayerEntity.mm;
// declared in the class's interface before slice 1.
@interface PlayerEntity (OOObjCBridge)

+ (PlayerEntity*)sharedPlayer;
- (void)deferredInit;

@end

namespace oo {

// The root's crossings, typed.
inline cxx::PlayerEntity* ToCxx(::PlayerEntity* entity)
{
    return static_cast<cxx::PlayerEntity*>(ToCxx(static_cast<::ShipEntity*>(entity)));
}

inline ::PlayerEntity* ToObjC(cxx::PlayerEntity* entity)
{
    return (::PlayerEntity*)ToObjC(static_cast<cxx::ShipEntity*>(entity));
}

} // namespace oo

#endif // PLAYERENTITY_OBJCBRIDGE_H
