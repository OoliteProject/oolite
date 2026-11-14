/*

HeadUpDisplay+ObjCBridge.h

TRANSITIONAL (proposed ADR-0056, beads oo-engam .. oo-0tx6c, the six slices of
docs/phases/3-slices/HeadUpDisplay.md): the Objective-C HeadUpDisplay, a facade over the C++
cxx::HeadUpDisplay (HeadUpDisplay.h), for the HUD's callers that are not converted yet (the
player, the universe, the scripting bindings: about 30 files reach it through [PLAYER hud]). Its
interface is the old one, copied exactly (same selectors, same types, same root). Each method
forwards to its C++ member. Imported as the last line of HeadUpDisplay.h; do not import it
directly.

        a caller that is                       holds / passes                       crosses with
        -------------------------------------  -----------------------------------  ------------------------
        still Objective-C                      HeadUpDisplay *                      (nothing)
        converted (C++)                        oo::Ref<cxx::HeadUpDisplay>          oo::ToObjC(hud)

The dials are called by name on the facade (OOCallByName, ADR-0055 item 5), so the facade answers
every dial selector (the OODials category, one forwarder each) until it is deleted. Below it are
the beacon code icon's facade and protocol, and the one-line sends of converted free functions to
classes that are still Objective-C (ADR-0056 amendment oo-9ht.139); each send goes with its
class's conversion.

Never add to this file except a forwarder or a send of that kind. Deleted, with namespace cxx in
HeadUpDisplay.h, by its deletion bead (oo-mwd58) once the callers are converted.

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

#ifndef HEADUPDISPLAY_OBJCBRIDGE_H
#define HEADUPDISPLAY_OBJCBRIDGE_H

#import "OOFoundation.h"
#import "oofnd/objc/OOObject.h"

#import "WormholeEntity.h" // WORMHOLE_SCANINFO (a bridge function below)

@class OOColor, GuiDisplayGen, MyOpenGLView, OOWeakReference, OOVisualEffectEntity;

// Moved verbatim from HeadUpDisplay.h (bead oo-2p1ug, amendment oo-jpd8 item 1): adopted by the
// facades below and by OOPolygonSprite's category, held by the entities' beacon drawables.
/*
        Protocol for things that can be used as HUD compass items. Really ought
        to grow into a general protocol for HUD elements.
*/
@protocol OOHUDBeaconIcon <OOObject>

- (void)oo_drawHUDBeaconIconAt:(NSPoint)where size:(NSSize)size alpha:(GLfloat)alpha z:(GLfloat)z;

@end

/*	The compass icon of a beacon whose code names no icon: the code's first character, drawn as
        text. It replaces the string class's OOHUDBeaconIcon category (bead oo-f9rf) the entities' beacon
        drawables used; the drawing is the category's.
*/
@interface OOHUDBeaconCodeIcon : OOObject <OOHUDBeaconIcon> {
@private
    oo::Ref<cxx::OOHUDBeaconCodeIcon> _cxxIcon;
}

- (id)initWithText:(const std::string&)text;

@end

@interface HeadUpDisplay : OOObject {
@private
    oo::Ref<cxx::HeadUpDisplay> _cxxHUD;
}

- (id)cxx_initWithDictionary:(const oo::PList&)hudinfo inFile:(const std::optional<std::string>&)hudFileName OO_RETURNS_RETAINED;

- (void)cxx_resetGuis:(const oo::PList&)info;

- (std::optional<std::string>)cxx_hudName;
- (void)setHudName:(const std::optional<std::string>&)newHudName; // nullopt is ignored, as nil was

- (GLfloat)scannerZoom;
- (void)setScannerZoom:(GLfloat)value;

- (GLfloat)overallAlpha;
- (void)setOverallAlpha:(GLfloat)newAlphaValue;

- (BOOL)reticleTargetSensitive;
- (void)setReticleTargetSensitive:(BOOL)newReticleTargetSensitiveValue;
- (oo::PList*)propertiesReticleTargetSensitive; // the live dictionary; nullptr for a nil receiver

- (BOOL)isHidden;
- (void)setHidden:(BOOL)newValue;

- (BOOL)allowBigGui;

- (BOOL)hasHidden:(const std::optional<std::string>&)selectorName; // nullopt (was nil): NO
- (void)cxx_setHiddenSelector:(const std::string&)selectorName hidden:(BOOL)hide;
- (void)clearHiddenSelectors;

- (BOOL)isCompassActive;
- (void)setCompassActive:(BOOL)newValue;

- (BOOL)isUpdating;
- (void)cxx_setDeferredHudName:(const std::optional<std::string>&)newDeferredHudName;
- (std::optional<std::string>)cxx_deferredHudName;
- (std::optional<std::string>)cxx_crosshairDefinition;
- (BOOL)cxx_setCrosshairDefinition:(const std::string&)newDefinition;

// Each takes one hud.plist entry; a null PList where the entry was not a dictionary.
- (void)addLegend:(const oo::PList&)info;
- (void)addDial:(const oo::PList&)info;
- (void)addMFD:(const oo::PList&)info;

- (NSUInteger)mfdCount;

- (void)renderHUD;

- (void)refreshLastTransmitter;

- (void)setLineWidth:(GLfloat)value;
- (GLfloat)lineWidth;

- (BOOL)minimalisticScanner;
- (void)setMinimalisticScanner:(BOOL)newValue;

+ (Vector)nonlinearScannerScale:(Vector)V Zoom:(GLfloat)zoom Scale:(double)scale;
- (BOOL)nonlinearScanner;
- (void)setNonlinearScanner:(BOOL)newValue;

- (BOOL)scannerUltraZoom;
- (void)setScannerUltraZoom:(BOOL)newValue;

- (OOColor*)reticleColorForIndex:(NSUInteger)idx;
- (BOOL)setReticleColorForIndex:(NSUInteger)idx toColor:(OOColor*)newColor;

@end

// The dials that are C++ members, called by name (ADR-0055 item 5): one forwarder each.
@interface HeadUpDisplay (OODials)

- (void)drawSurround:(const oo::PList&)info;
- (void)drawGreenSurround:(const oo::PList&)info;
- (void)drawYellowSurround:(const oo::PList&)info;
- (void)drawScanner:(const oo::PList&)info;
- (void)drawScannerZoomIndicator:(const oo::PList&)info;
- (void)drawCompass:(const oo::PList&)info;
- (void)drawAegis:(const oo::PList&)info;
- (void)drawTargetReticle:(const oo::PList&)info;
- (void)drawWaypoints:(const oo::PList&)info;
- (void)drawCustomBar:(const oo::PList&)info;
- (void)drawCustomText:(const oo::PList&)info;
- (void)drawCustomIndicator:(const oo::PList&)info;
- (void)drawCustomLight:(const oo::PList&)info;
- (void)drawCustomImage:(const oo::PList&)info;
- (void)drawSpeedBar:(const oo::PList&)info;
- (void)drawRollBar:(const oo::PList&)info;
- (void)drawPitchBar:(const oo::PList&)info;
- (void)drawYawBar:(const oo::PList&)info;
- (void)drawEnergyGauge:(const oo::PList&)info;
- (void)drawForwardShieldBar:(const oo::PList&)info;
- (void)drawAftShieldBar:(const oo::PList&)info;
- (void)drawFuelBar:(const oo::PList&)info;
- (void)drawWitchspaceDestination:(const oo::PList&)info;
- (void)drawCabinTempBar:(const oo::PList&)info;
- (void)drawWeaponTempBar:(const oo::PList&)info;
- (void)drawAltitudeBar:(const oo::PList&)info;
- (void)drawMissileDisplay:(const oo::PList&)info;
- (void)drawStatusLight:(const oo::PList&)info;
- (void)drawClock:(const oo::PList&)info;
- (void)drawPrimedEquipment:(const oo::PList&)info;
- (void)drawASCTarget:(const oo::PList&)info;
- (void)drawWeaponsOfflineText:(const oo::PList&)info;
- (void)drawFPSInfoCounter:(const oo::PList&)info;
- (void)drawScoopStatus:(const oo::PList&)info;
- (void)drawStickSensitivityIndicator:(const oo::PList&)info;
- (void)drawTrumbles:(const oo::PList&)info;

@end

namespace oo {

// The HUD's Objective-C facade: its live one, else a new one; autoreleased. nil for null.
HeadUpDisplay* ToObjC(cxx::HeadUpDisplay* hud);
inline HeadUpDisplay* ToObjC(const Ref<cxx::HeadUpDisplay>& hud) { return ToObjC(hud.get()); }
// The C++ HUD behind a facade, borrowed (the facade retains it); null for nil.
cxx::HeadUpDisplay* ToCxx(HeadUpDisplay* hud);

// The same for the beacon code icon.
OOHUDBeaconCodeIcon* ToObjC(cxx::OOHUDBeaconCodeIcon* icon);
inline OOHUDBeaconCodeIcon* ToObjC(const Ref<cxx::OOHUDBeaconCodeIcon>& icon) { return ToObjC(icon.get()); }
cxx::OOHUDBeaconCodeIcon* ToCxx(OOHUDBeaconCodeIcon* icon);

} // namespace oo

/*	Sends of converted free functions to classes that are still Objective-C (ADR-0056 amendment
        oo-9ht.139), one function per send, the body the send verbatim. Members keep their sends
        (amendment oo-ppc item 4). Each goes with its class's conversion.
*/
// +[ResourceManager cxx_dictionaryFromFilesNamed:inFolder:andMerge:] (InitTextEngine()).
oo::PList HeadUpDisplayDictionaryFromFilesNamed(const std::string& fileName, const std::optional<std::string>& folderName, bool mergeFiles);
// -[[UNIVERSE gui] cxx_setGLColorFromSetting:defaultValue:alpha:] (OODrawPlanetInfo()).
void HeadUpDisplayUniverseGUISetGLColorFromSetting(const std::optional<std::string>& setting, OOColor* defaultValue, GLfloat alpha);
// [UNIVERSE gameView], -[MyOpenGLView fov:] and -[MyOpenGLView viewSize] (drawScannerGrid()).
MyOpenGLView* HeadUpDisplayUniverseGameView();
GLfloat HeadUpDisplayGameViewFov(MyOpenGLView* gameView, bool inFraction);
NSSize HeadUpDisplayGameViewViewSize(MyOpenGLView* gameView);
// The player, entities and universe as the reticles and waypoints read them (hudDrawReticleOnTarget(),
// hudDrawWaypoint(), hudRotateViewpointForVirtualDepth()).
OOGUIScreenID HeadUpDisplayPlayerGuiScreen(PlayerEntity* player);
HPVector HeadUpDisplayPlayerViewpointPosition(PlayerEntity* player);
GLfloat HeadUpDisplayPlayerWeaponRange(PlayerEntity* player);
std::optional<std::string> HeadUpDisplayPlayerDialTargetName(PlayerEntity* player);
double HeadUpDisplayPlayerClockTimeAdjusted(PlayerEntity* player);
Vector HeadUpDisplayPlayerCustomViewForwardVector(PlayerEntity* player);
Vector HeadUpDisplayPlayerCustomViewUpVector(PlayerEntity* player);
Quaternion HeadUpDisplayPlayerCustomViewQuaternion(PlayerEntity* player);
OOMatrix HeadUpDisplayPlayerRotationMatrix(PlayerEntity* player);
bool HeadUpDisplayEntityIsShip(Entity* entity);
bool HeadUpDisplayEntityIsWormhole(Entity* entity);
bool HeadUpDisplayEntityIsVisualEffect(Entity* entity);
HPVector HeadUpDisplayEntityPosition(Entity* entity);
GLfloat HeadUpDisplayEntityCollisionRadius(Entity* entity);
Quaternion HeadUpDisplayEntityOrientation(Entity* entity);
std::optional<std::string> HeadUpDisplayShipScanDescription(ShipEntity* ship);
bool HeadUpDisplayShipIsCloaked(ShipEntity* ship);
bool HeadUpDisplayShipIsHostileToPlayer(ShipEntity* ship);
GLfloat* HeadUpDisplayShipScannerDisplayColor(ShipEntity* ship, BOOL isHostile, BOOL flash);
GLfloat* HeadUpDisplayVisualEffectScannerDisplayColor(OOVisualEffectEntity* vis, BOOL flash);
WORMHOLE_SCANINFO HeadUpDisplayWormholeScanInfo(WormholeEntity* wormhole);
double HeadUpDisplayWormholeEstimatedArrivalTime(WormholeEntity* wormhole);
double HeadUpDisplayWormholeExpiryTime(WormholeEntity* wormhole);
OOTimeAbsolute HeadUpDisplayUniverseGetTime();
const oo::PList* HeadUpDisplayUniverseDescriptions(); // MissileIconDefinition()
OOViewID HeadUpDisplayUniverseViewDirection();
Entity* HeadUpDisplayUniverseFirstEntityTargetedByPlayer();
Entity* HeadUpDisplayUniverseFirstEntityTargetedByPlayerPrecisely();

#endif // HEADUPDISPLAY_OBJCBRIDGE_H
