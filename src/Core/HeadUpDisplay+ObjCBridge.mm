/*

HeadUpDisplay+ObjCBridge.mm

TRANSITIONAL (proposed ADR-0056, bead oo-engam): the Objective-C facade over cxx::HeadUpDisplay.
See HeadUpDisplay+ObjCBridge.h. The drawing is cxx::HeadUpDisplay's, in HeadUpDisplay.mm.

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

#import "GuiDisplayGen.h"
#import "HeadUpDisplay.h"
#import "OOColor.h"
#import "OOPolygonSprite.h"
#import "OOVisualEffectEntity.h"
#import "PlayerEntity.h"
#import "ResourceManager.h"
#import "Universe.h"

#include "oofnd/objc/OOObjCPeer.h"

namespace {

// Never destroyed: a facade may be released while the process exits.
oo::ObjCPeers& Peers()
{
    static oo::ObjCPeers* peers = new oo::ObjCPeers;
    return *peers;
}

} // namespace

@interface HeadUpDisplay (OOObjCBridgePrivate)

- (id)initWithCxxHUD:(cxx::HeadUpDisplay*)hud;

@end

@implementation HeadUpDisplay

// Inside the @implementation for the private ivar.
HeadUpDisplay* oo::ToObjC(cxx::HeadUpDisplay* hud)
{
    return Peers().peerFor(hud, [hud] { return [[HeadUpDisplay alloc] initWithCxxHUD:hud]; });
}

cxx::HeadUpDisplay* oo::ToCxx(HeadUpDisplay* hud)
{
    if (hud == nil)
        return nullptr;
    return hud->_cxxHUD.get();
}

/*	The facade is the HUD's peer before the C++ initialisation runs: the dial check asks the facade
        which dials it answers, and it must ask this object (amendment oo-8kx7).
*/
- (id)cxx_initWithDictionary:(const oo::PList&)hudinfo inFile:(const std::optional<std::string>&)hudFileName
{
    self = [super init];
    if (self == nil)
        return nil;

    _cxxHUD = oo::makeRef<cxx::HeadUpDisplay>();
    @autoreleasepool {
        Peers().peerFor(_cxxHUD.get(), [self] { return [self retain]; });
    }
    _cxxHUD->initWithDictionary(hudinfo, hudFileName);
    return self;
}

- (id)initWithCxxHUD:(cxx::HeadUpDisplay*)hud
{
    self = [super init];
    if (self != nil)
        _cxxHUD = oo::Ref<cxx::HeadUpDisplay>(hud);
    return self;
}

- (void)dealloc
{
    Peers().forget(_cxxHUD.get());
    [super dealloc];
}

- (void)cxx_resetGuis:(const oo::PList&)info
{
    _cxxHUD->resetGuis(info);
}

- (std::optional<std::string>)cxx_hudName
{
    return _cxxHUD->getHudName();
}
- (void)setHudName:(const std::optional<std::string>&)newHudName
{
    _cxxHUD->setHudName(newHudName);
}

- (GLfloat)scannerZoom
{
    return _cxxHUD->scannerZoom();
}
- (void)setScannerZoom:(GLfloat)value
{
    _cxxHUD->setScannerZoom(value);
}

- (GLfloat)overallAlpha
{
    return _cxxHUD->getOverallAlpha();
}
- (void)setOverallAlpha:(GLfloat)newAlphaValue
{
    _cxxHUD->setOverallAlpha(newAlphaValue);
}

- (BOOL)reticleTargetSensitive
{
    return _cxxHUD->getReticleTargetSensitive();
}
- (void)setReticleTargetSensitive:(BOOL)newReticleTargetSensitiveValue
{
    _cxxHUD->setReticleTargetSensitive(newReticleTargetSensitiveValue);
}
- (oo::PList*)propertiesReticleTargetSensitive
{
    return _cxxHUD->getPropertiesReticleTargetSensitive();
}

- (BOOL)isHidden
{
    return _cxxHUD->isHidden();
}
- (void)setHidden:(BOOL)newValue
{
    _cxxHUD->setHidden(newValue);
}

- (BOOL)allowBigGui
{
    return _cxxHUD->getAllowBigGui();
}

- (BOOL)hasHidden:(const std::optional<std::string>&)selectorName
{
    return _cxxHUD->hasHidden(selectorName);
}
- (void)cxx_setHiddenSelector:(const std::string&)selectorName hidden:(BOOL)hide
{
    _cxxHUD->setHiddenSelector(selectorName, hide);
}
- (void)clearHiddenSelectors
{
    _cxxHUD->clearHiddenSelectors();
}

- (BOOL)isCompassActive
{
    return _cxxHUD->isCompassActive();
}
- (void)setCompassActive:(BOOL)newValue
{
    _cxxHUD->setCompassActive(newValue);
}

- (BOOL)isUpdating
{
    return _cxxHUD->isUpdating();
}
- (void)cxx_setDeferredHudName:(const std::optional<std::string>&)newDeferredHudName
{
    _cxxHUD->setDeferredHudName(newDeferredHudName);
}
- (std::optional<std::string>)cxx_deferredHudName
{
    return _cxxHUD->getDeferredHudName();
}
- (std::optional<std::string>)cxx_crosshairDefinition
{
    return _cxxHUD->getCrosshairDefinition();
}
- (BOOL)cxx_setCrosshairDefinition:(const std::string&)newDefinition
{
    return _cxxHUD->setCrosshairDefinition(newDefinition);
}

- (void)addLegend:(const oo::PList&)info
{
    _cxxHUD->addLegend(info);
}
- (void)addDial:(const oo::PList&)info
{
    _cxxHUD->addDial(info);
}
- (void)addMFD:(const oo::PList&)info
{
    _cxxHUD->addMFD(info);
}

- (NSUInteger)mfdCount
{
    return _cxxHUD->mfdCount();
}

- (void)renderHUD
{
    _cxxHUD->renderHUD();
}

- (void)refreshLastTransmitter
{
    _cxxHUD->refreshLastTransmitter();
}

- (void)setLineWidth:(GLfloat)value
{
    _cxxHUD->setLineWidth(value);
}
- (GLfloat)lineWidth
{
    return _cxxHUD->getLineWidth();
}

- (BOOL)minimalisticScanner
{
    return _cxxHUD->minimalisticScanner();
}
- (void)setMinimalisticScanner:(BOOL)newValue
{
    _cxxHUD->setMinimalisticScanner(newValue);
}

+ (Vector)nonlinearScannerScale:(Vector)V Zoom:(GLfloat)zoom Scale:(double)scale
{
    return cxx::HeadUpDisplay::nonlinearScannerScale(V, zoom, scale);
}
- (BOOL)nonlinearScanner
{
    return _cxxHUD->nonlinearScanner();
}
- (void)setNonlinearScanner:(BOOL)newValue
{
    _cxxHUD->setNonlinearScanner(newValue);
}

- (BOOL)scannerUltraZoom
{
    return _cxxHUD->scannerUltraZoom();
}
- (void)setScannerUltraZoom:(BOOL)newValue
{
    _cxxHUD->setScannerUltraZoom(newValue);
}

- (OOColor*)reticleColorForIndex:(NSUInteger)idx
{
    return oo::ToObjC(_cxxHUD->reticleColorForIndex(idx));
}
- (BOOL)setReticleColorForIndex:(NSUInteger)idx toColor:(OOColor*)newColor
{
    return _cxxHUD->setReticleColorForIndex(idx, oo::ToCxx(newColor));
}

@end

@implementation HeadUpDisplay (OODials)

- (void)drawSurround:(const oo::PList&)info
{
    _cxxHUD->drawSurround(info);
}
- (void)drawGreenSurround:(const oo::PList&)info
{
    _cxxHUD->drawGreenSurround(info);
}
- (void)drawYellowSurround:(const oo::PList&)info
{
    _cxxHUD->drawYellowSurround(info);
}
- (void)drawScanner:(const oo::PList&)info
{
    _cxxHUD->drawScanner(info);
}
- (void)drawScannerZoomIndicator:(const oo::PList&)info
{
    _cxxHUD->drawScannerZoomIndicator(info);
}
- (void)drawCompass:(const oo::PList&)info
{
    _cxxHUD->drawCompass(info);
}
- (void)drawAegis:(const oo::PList&)info
{
    _cxxHUD->drawAegis(info);
}
- (void)drawTargetReticle:(const oo::PList&)info
{
    _cxxHUD->drawTargetReticle(info);
}
- (void)drawWaypoints:(const oo::PList&)info
{
    _cxxHUD->drawWaypoints(info);
}

- (void)drawCustomBar:(const oo::PList&)info
{
    _cxxHUD->drawCustomBar(info);
}
- (void)drawCustomText:(const oo::PList&)info
{
    _cxxHUD->drawCustomText(info);
}
- (void)drawCustomIndicator:(const oo::PList&)info
{
    _cxxHUD->drawCustomIndicator(info);
}
- (void)drawCustomLight:(const oo::PList&)info
{
    _cxxHUD->drawCustomLight(info);
}
- (void)drawCustomImage:(const oo::PList&)info
{
    _cxxHUD->drawCustomImage(info);
}
- (void)drawSpeedBar:(const oo::PList&)info
{
    _cxxHUD->drawSpeedBar(info);
}
- (void)drawRollBar:(const oo::PList&)info
{
    _cxxHUD->drawRollBar(info);
}
- (void)drawPitchBar:(const oo::PList&)info
{
    _cxxHUD->drawPitchBar(info);
}
- (void)drawYawBar:(const oo::PList&)info
{
    _cxxHUD->drawYawBar(info);
}
- (void)drawEnergyGauge:(const oo::PList&)info
{
    _cxxHUD->drawEnergyGauge(info);
}
- (void)drawForwardShieldBar:(const oo::PList&)info
{
    _cxxHUD->drawForwardShieldBar(info);
}
- (void)drawAftShieldBar:(const oo::PList&)info
{
    _cxxHUD->drawAftShieldBar(info);
}
- (void)drawFuelBar:(const oo::PList&)info
{
    _cxxHUD->drawFuelBar(info);
}
- (void)drawWitchspaceDestination:(const oo::PList&)info
{
    _cxxHUD->drawWitchspaceDestination(info);
}
- (void)drawCabinTempBar:(const oo::PList&)info
{
    _cxxHUD->drawCabinTempBar(info);
}
- (void)drawWeaponTempBar:(const oo::PList&)info
{
    _cxxHUD->drawWeaponTempBar(info);
}
- (void)drawAltitudeBar:(const oo::PList&)info
{
    _cxxHUD->drawAltitudeBar(info);
}
- (void)drawMissileDisplay:(const oo::PList&)info
{
    _cxxHUD->drawMissileDisplay(info);
}
- (void)drawStatusLight:(const oo::PList&)info
{
    _cxxHUD->drawStatusLight(info);
}
- (void)drawClock:(const oo::PList&)info
{
    _cxxHUD->drawClock(info);
}
- (void)drawPrimedEquipment:(const oo::PList&)info
{
    _cxxHUD->drawPrimedEquipment(info);
}
- (void)drawASCTarget:(const oo::PList&)info
{
    _cxxHUD->drawASCTarget(info);
}
- (void)drawWeaponsOfflineText:(const oo::PList&)info
{
    _cxxHUD->drawWeaponsOfflineText(info);
}
- (void)drawFPSInfoCounter:(const oo::PList&)info
{
    _cxxHUD->drawFPSInfoCounter(info);
}
- (void)drawScoopStatus:(const oo::PList&)info
{
    _cxxHUD->drawScoopStatus(info);
}
- (void)drawStickSensitivityIndicator:(const oo::PList&)info
{
    _cxxHUD->drawStickSensitivityIndicator(info);
}
- (void)drawTrumbles:(const oo::PList&)info
{
    _cxxHUD->drawTrumbles(info);
}

@end

oo::PList HeadUpDisplayDictionaryFromFilesNamed(const std::string& fileName, const std::optional<std::string>& folderName, bool mergeFiles)
{
    return [ResourceManager cxx_dictionaryFromFilesNamed:fileName inFolder:folderName andMerge:mergeFiles];
}

void HeadUpDisplayUniverseGUISetGLColorFromSetting(const std::optional<std::string>& setting, OOColor* defaultValue, GLfloat alpha)
{
    [[UNIVERSE gui] cxx_setGLColorFromSetting:setting defaultValue:defaultValue alpha:alpha];
}

MyOpenGLView* HeadUpDisplayUniverseGameView()
{
    return [UNIVERSE gameView];
}

GLfloat HeadUpDisplayGameViewFov(MyOpenGLView* gameView, bool inFraction)
{
    return [gameView fov:inFraction];
}

NSSize HeadUpDisplayGameViewViewSize(MyOpenGLView* gameView)
{
    return [gameView viewSize];
}

// --- The beacon icons (bead oo-2p1ug) ---------------------------------------------------------

namespace {

// Never destroyed: a facade may be released while the process exits.
oo::ObjCPeers& IconPeers()
{
    static oo::ObjCPeers* peers = new oo::ObjCPeers;
    return *peers;
}

} // namespace

@interface OOHUDBeaconCodeIcon (OOObjCBridgePrivate)

- (id)initWithCxxIcon:(cxx::OOHUDBeaconCodeIcon*)icon;

@end

@implementation OOHUDBeaconCodeIcon

OOHUDBeaconCodeIcon* oo::ToObjC(cxx::OOHUDBeaconCodeIcon* icon)
{
    return IconPeers().peerFor(icon, [icon] { return [[OOHUDBeaconCodeIcon alloc] initWithCxxIcon:icon]; });
}

cxx::OOHUDBeaconCodeIcon* oo::ToCxx(OOHUDBeaconCodeIcon* icon)
{
    if (icon == nil)
        return nullptr;
    return icon->_cxxIcon.get();
}

- (id)initWithText:(const std::string&)text
{
    self = [super init];
    if (self == nil)
        return nil;

    _cxxIcon = oo::makeRef<cxx::OOHUDBeaconCodeIcon>(text);
    @autoreleasepool {
        IconPeers().peerFor(_cxxIcon.get(), [self] { return [self retain]; });
    }
    return self;
}

- (id)initWithCxxIcon:(cxx::OOHUDBeaconCodeIcon*)icon
{
    self = [super init];
    if (self != nil)
        _cxxIcon = oo::Ref<cxx::OOHUDBeaconCodeIcon>(icon);
    return self;
}

- (void)dealloc
{
    IconPeers().forget(_cxxIcon.get());
    [super dealloc];
}

- (void)oo_drawHUDBeaconIconAt:(NSPoint)where size:(NSSize)size alpha:(GLfloat)alpha z:(GLfloat)z
{
    _cxxIcon->drawHUDBeaconIconAt(where, size, alpha, z);
}

@end

// Declared in OOPolygonSprite+ObjCBridge.h; the drawing is OOPolygonSpriteDrawHUDBeaconIcon() in HeadUpDisplay.mm.
@implementation OOPolygonSprite (OOHUDBeaconIcon)

- (void)oo_drawHUDBeaconIconAt:(NSPoint)where size:(NSSize)size alpha:(GLfloat)alpha z:(GLfloat)z
{
    OOPolygonSpriteDrawHUDBeaconIcon(oo::ToCxx(self), where, size, alpha, z);
}

@end

// --- Sends of the reticles and waypoints (hudDrawReticleOnTarget(), hudDrawWaypoint(), hudRotateViewpointForVirtualDepth())

OOGUIScreenID HeadUpDisplayPlayerGuiScreen(PlayerEntity* player) { return [player guiScreen]; }
HPVector HeadUpDisplayPlayerViewpointPosition(PlayerEntity* player) { return [player viewpointPosition]; }
GLfloat HeadUpDisplayPlayerWeaponRange(PlayerEntity* player) { return [player weaponRange]; }
std::optional<std::string> HeadUpDisplayPlayerDialTargetName(PlayerEntity* player) { return [player cxx_dialTargetName]; }
double HeadUpDisplayPlayerClockTimeAdjusted(PlayerEntity* player) { return [player clockTimeAdjusted]; }
Vector HeadUpDisplayPlayerCustomViewForwardVector(PlayerEntity* player) { return [player customViewForwardVector]; }
Vector HeadUpDisplayPlayerCustomViewUpVector(PlayerEntity* player) { return [player customViewUpVector]; }
Quaternion HeadUpDisplayPlayerCustomViewQuaternion(PlayerEntity* player) { return [player customViewQuaternion]; }
OOMatrix HeadUpDisplayPlayerRotationMatrix(PlayerEntity* player) { return [player rotationMatrix]; }
bool HeadUpDisplayEntityIsShip(Entity* entity) { return [entity isShip]; }
bool HeadUpDisplayEntityIsWormhole(Entity* entity) { return [entity isWormhole]; }
bool HeadUpDisplayEntityIsVisualEffect(Entity* entity) { return [entity isVisualEffect]; }
HPVector HeadUpDisplayEntityPosition(Entity* entity) { return [entity position]; }
GLfloat HeadUpDisplayEntityCollisionRadius(Entity* entity) { return [entity collisionRadius]; }
Quaternion HeadUpDisplayEntityOrientation(Entity* entity) { return [entity orientation]; }
std::optional<std::string> HeadUpDisplayShipScanDescription(ShipEntity* ship) { return [ship cxx_scanDescription]; }
bool HeadUpDisplayShipIsCloaked(ShipEntity* ship) { return [ship isCloaked]; }
bool HeadUpDisplayShipIsHostileToPlayer(ShipEntity* ship) { return (([ship hasHostileTarget]) && ([ship primaryTarget] == PLAYER)); }
GLfloat* HeadUpDisplayShipScannerDisplayColor(ShipEntity* ship, BOOL isHostile, BOOL flash) { return [ship scannerDisplayColorForShip:PLAYER isHostile:isHostile flash:flash scannerDisplayColor1:[ship scannerDisplayColor1] scannerDisplayColor2:[ship scannerDisplayColor2] scannerDisplayColorH1:[ship scannerDisplayColorHostile1] scannerDisplayColorH2:[ship scannerDisplayColorHostile2]]; }
GLfloat* HeadUpDisplayVisualEffectScannerDisplayColor(OOVisualEffectEntity* vis, BOOL flash) { return [vis scannerDisplayColorForShip:flash scannerDisplayColor1:[vis scannerDisplayColor1] scannerDisplayColor2:[vis scannerDisplayColor2]]; }
WORMHOLE_SCANINFO HeadUpDisplayWormholeScanInfo(WormholeEntity* wormhole) { return [wormhole scanInfo]; }
double HeadUpDisplayWormholeEstimatedArrivalTime(WormholeEntity* wormhole) { return [wormhole estimatedArrivalTime]; }
double HeadUpDisplayWormholeExpiryTime(WormholeEntity* wormhole) { return [wormhole expiryTime]; }
OOTimeAbsolute HeadUpDisplayUniverseGetTime() { return [UNIVERSE getTime]; }
const oo::PList* HeadUpDisplayUniverseDescriptions() { return [UNIVERSE cxx_descriptions]; }
OOViewID HeadUpDisplayUniverseViewDirection() { return [UNIVERSE viewDirection]; }
Entity* HeadUpDisplayUniverseFirstEntityTargetedByPlayer() { return [UNIVERSE firstEntityTargetedByPlayer]; }
Entity* HeadUpDisplayUniverseFirstEntityTargetedByPlayerPrecisely() { return [UNIVERSE firstEntityTargetedByPlayerPrecisely]; }
