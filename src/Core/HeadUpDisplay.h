/*

HeadUpDisplay.h

Class handling the player ship’s heads-up display, and 2D drawing functions.

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

#import "OOFoundation.h"
#import "OOOpenGL.h"
#import "oofnd/objc/OOObject.h"

#import "MyOpenGLView.h"
#import "OOMaths.h"
#import "OOTypes.h"
#import "ShipEntity.h"

#include "oofnd/PList.hpp"
#include "oofnd/Ref.hpp"
#include "oofnd/StdLib.hpp"
#include "oofnd/objc/OOObjCRef.h"

#include <optional>
#include <set>
#include <string>
#include <vector>

struct OOHUDWidget; // HeadUpDisplay.mm

@class OOColor;
class OOCrosshairs;

#define SCANNER_CENTRE_X 0
#define SCANNER_CENTRE_Y -180
#define SCANNER_SCALE 256
#define SCANNER_WIDTH 288
#define SCANNER_HEIGHT 72

#define SCANNER_MAX_ZOOM 5.0
#define SCANNER_ZOOM_LEVELS 5
#define ZOOM_INDICATOR_CENTRE_X 108
#define ZOOM_INDICATOR_CENTRE_Y -216
#define ZOOM_INDICATOR_WIDTH 11.0f
#define ZOOM_INDICATOR_HEIGHT 14.0f
#define ZOOM_LEVELS_IMAGE @"zoom.png"

#define COMPASS_IMAGE @"compass.png"
#define COMPASS_CENTRE_X 132
#define COMPASS_CENTRE_Y -216
#define COMPASS_SIZE 56
#define COMPASS_HALF_SIZE 28
#define COMPASS_REDDOT_IMAGE @"reddot.png"
#define COMPASS_GREENDOT_IMAGE @"greendot.png"
#define COMPASS_DOT_SIZE 16
#define COMPASS_HALF_DOT_SIZE 8

#define AEGIS_IMAGE @"aegis.png"
#define AEGIS_CENTRE_X -132
#define AEGIS_CENTRE_Y -216
#define AEGIS_WIDTH 24
#define AEGIS_HEIGHT 24

#define SPEED_BAR_CENTRE_X 200
#define SPEED_BAR_CENTRE_Y -145
#define SPEED_BAR_WIDTH 80
#define SPEED_BAR_HEIGHT 8
#define SPEED_BAR_DRAW_SURROUND YES

#define ROLL_BAR_CENTRE_X 200
#define ROLL_BAR_CENTRE_Y -160
#define ROLL_BAR_WIDTH 80
#define ROLL_BAR_HEIGHT 8
#define ROLL_BAR_DRAW_SURROUND YES

#define PITCH_BAR_CENTRE_X 200
#define PITCH_BAR_CENTRE_Y -170
#define PITCH_BAR_WIDTH 80
#define PITCH_BAR_HEIGHT 8
#define PITCH_BAR_DRAW_SURROUND YES

#define ENERGY_GAUGE_CENTRE_X 200
#define ENERGY_GAUGE_CENTRE_Y -205
#define ENERGY_GAUGE_WIDTH 80
#define ENERGY_GAUGE_HEIGHT 48
#define ENERGY_GAUGE_DRAW_SURROUND YES

#define FORWARD_SHIELD_BAR_CENTRE_X -200
#define FORWARD_SHIELD_BAR_CENTRE_Y -146
#define FORWARD_SHIELD_BAR_WIDTH 80
#define FORWARD_SHIELD_BAR_HEIGHT 8
#define FORWARD_SHIELD_BAR_DRAW_SURROUND YES

#define AFT_SHIELD_BAR_CENTRE_X -200
#define AFT_SHIELD_BAR_CENTRE_Y -162
#define AFT_SHIELD_BAR_WIDTH 80
#define AFT_SHIELD_BAR_HEIGHT 8
#define AFT_SHIELD_BAR_DRAW_SURROUND YES

#define FUEL_BAR_CENTRE_X -200
#define FUEL_BAR_CENTRE_Y -179
#define FUEL_BAR_WIDTH 80
#define FUEL_BAR_HEIGHT 8

#define WITCHDEST_CENTRE_X -200
#define WITCHDEST_CENTRE_Y -179
#define WITCHDEST_WIDTH 80
#define WITCHDEST_HEIGHT 8

#define CABIN_TEMP_BAR_CENTRE_X -200
#define CABIN_TEMP_BAR_CENTRE_Y -189
#define CABIN_TEMP_BAR_WIDTH 80
#define CABIN_TEMP_BAR_HEIGHT 8

#define WEAPON_TEMP_BAR_CENTRE_X -200
#define WEAPON_TEMP_BAR_CENTRE_Y -199
#define WEAPON_TEMP_BAR_WIDTH 80
#define WEAPON_TEMP_BAR_HEIGHT 8

#define ALTITUDE_BAR_CENTRE_X -200
#define ALTITUDE_BAR_CENTRE_Y -209
#define ALTITUDE_BAR_WIDTH 80
#define ALTITUDE_BAR_HEIGHT 8

#define MISSILES_DISPLAY_X -228
#define MISSILES_DISPLAY_Y -224
#define MISSILES_DISPLAY_SPACING 16
#define MISSILE_ICON_WIDTH 12
#define MISSILE_ICON_HEIGHT MISSILE_ICON_WIDTH

#define PRIMED_DISPLAY_X -144
#define PRIMED_DISPLAY_Y -256
#define PRIMED_DISPLAY_WIDTH 12
#define PRIMED_DISPLAY_HEIGHT 12

#define ASCTARGET_DISPLAY_X 64
#define ASCTARGET_DISPLAY_Y -234
#define ASCTARGET_DISPLAY_WIDTH 10
#define ASCTARGET_DISPLAY_HEIGHT 10

#define CLOCK_DISPLAY_X -44
#define CLOCK_DISPLAY_Y -234
#define CLOCK_DISPLAY_WIDTH 12
#define CLOCK_DISPLAY_HEIGHT 12

#define WEAPONSOFFLINETEXT_DISPLAY_X -175
#define WEAPONSOFFLINETEXT_DISPLAY_Y 2
#define WEAPONSOFFLINETEXT_WIDTH 8
#define WEAPONSOFFLINETEXT_HEIGHT 8

#define FPSINFO_DISPLAY_X -300
#define FPSINFO_DISPLAY_Y 220
#define FPSINFO_DISPLAY_WIDTH 12
#define FPSINFO_DISPLAY_HEIGHT 12

#define STATUS_LIGHT_CENTRE_X -108
#define STATUS_LIGHT_CENTRE_Y -216
#define STATUS_LIGHT_WIDTH 8
#define STATUS_LIGHT_HEIGHT 8

#define HIT_INDICATOR_CENTRE_X 200
#define HIT_INDICATOR_CENTRE_Y 0

#define SCOOPSTATUS_CENTRE_X -132
#define SCOOPSTATUS_CENTRE_Y -152
#define SCOOPSTATUS_WIDTH 16.0
#define SCOOPSTATUS_HEIGHT 16.0

#define MFD_TEXT_WIDTH 10
#define MFD_TEXT_HEIGHT 10

#define DIALS_KEY "dials"
#define LEGENDS_KEY "legends"
#define MFDS_KEY "multi_function_displays"
#define X_KEY "x"
#define Y_KEY "y"
#define X_ORIGIN_KEY "x_origin"
#define Y_ORIGIN_KEY "y_origin"
#define SPACING_KEY "spacing"
#define ALPHA_KEY "alpha"
#define SELECTOR_KEY "selector"
#define IMAGE_KEY "image"
#define WIDTH_KEY "width"
#define HEIGHT_KEY "height"
#define SPRITE_KEY "sprite"
#define DRAW_SURROUND_KEY "draw_surround"
#define EQUIPMENT_REQUIRED_KEY "equipment_required"
#define ALERT_CONDITIONS_KEY "alert_conditions"
#define VIEWSCREEN_KEY "viewscreen_only"
#define DIAL_REQUIRED_KEY "with_dial"
#define LABELLED_KEY "labelled"
#define TEXT_KEY "text"
#define RGB_COLOR_KEY "rgb_color"
#define COLOR_KEY "color"
#define COLOR_KEY_LOW "color_low"
#define COLOR_KEY_MEDIUM "color_medium"
#define COLOR_KEY_HIGH "color_high"
#define COLOR_KEY_CRITICAL "color_critical"
#define COLOR_KEY_SURROUND "color_surround"
#define N_BARS_KEY "n_bars"
#define CUSTOM_DIAL_KEY "data_source"

#define ROWS_KEY "rows"
#define COLUMNS_KEY "columns"
#define ROW_HEIGHT_KEY "row_height"
#define ROW_START_KEY "row_start"
#define TITLE_KEY "title"
#define BACKGROUND_RGBA_KEY "background_rgba"
#define OVERALL_ALPHA_KEY "overall_alpha"
#define NONLINEAR_SCANNER @"nonlinear_scanner"

#define Z1 [(MyOpenGLView*)[[player universe] gameView] display_z]

#define ONE_EIGHTH 0.125

#define MAX_ACCURACY_RANGE 7000 // 7.000km
#define ACCURACY_PROBABILITY_DECREASE_FACTOR 0.000035f // for every 1000km decrease by 3.5% the chance of high accuracy
#define MIN_PROBABILITY_ACCURACY 0.35f // floor value for probability of high accuracy is 35%

enum {
    OO_RETICLE_COLOR_TARGET = 0,
    OO_RETICLE_COLOR_TARGET_SENSITIVE,
    OO_RETICLE_COLOR_WORMHOLE
};

@class Entity, PlayerEntity, OOTextureSprite, GuiDisplayGen;

/*	The HUD itself (Phase 3, beads oo-engam .. oo-0tx6c: the six slices of
        docs/phases/3-slices/HeadUpDisplay.md). Its callers are still Objective-C and reach it through
        the facade HeadUpDisplay+ObjCBridge.h, which also answers the dials by name; the dial members
        and the state are public under "Internal" until the facade goes (ADR-0056 amendment oo-pni4
        item 1). Getters named after their state are get + the name (amendment oo-862e item 1).
*/
namespace cxx {

class OOColor;

class HeadUpDisplay : public oo::RefCounted {
public:
    HeadUpDisplay();
    ~HeadUpDisplay() override;

    // -cxx_initWithDictionary:inFile:, run by the facade once it is the HUD's peer (the dial check
    // asks the facade which dials it answers).
    void initWithDictionary(const oo::PList& hudinfo, const std::optional<std::string>& hudFileName);

    void resetGuis(const oo::PList& info);

    std::optional<std::string> getHudName();
    void setHudName(const std::optional<std::string>& newHudName); // nullopt is ignored, as nil was

    GLfloat scannerZoom();
    void setScannerZoom(GLfloat value);

    GLfloat getOverallAlpha();
    void setOverallAlpha(GLfloat newAlphaValue);

    bool getReticleTargetSensitive();
    void setReticleTargetSensitive(bool newReticleTargetSensitiveValue);
    oo::PList* getPropertiesReticleTargetSensitive(); // the live dictionary

    bool isHidden();
    void setHidden(bool newValue);

    bool getAllowBigGui();

    bool hasHidden(const std::optional<std::string>& selectorName); // nullopt (was nil): false
    void setHiddenSelector(const std::string& selectorName, bool hide);
    void clearHiddenSelectors();

    bool isCompassActive();
    void setCompassActive(bool newValue);

    bool isUpdating();
    void setDeferredHudName(const std::optional<std::string>& newDeferredHudName);
    std::optional<std::string> getDeferredHudName();
    std::optional<std::string> getCrosshairDefinition();
    bool setCrosshairDefinition(const std::string& newDefinition);

    // Each takes one hud.plist entry; a null PList where the entry was not a dictionary.
    void addLegend(const oo::PList& info);
    void addDial(const oo::PList& info);
    void addMFD(const oo::PList& info);

    NSUInteger mfdCount();

    void renderHUD();

    void refreshLastTransmitter();

    void setLineWidth(GLfloat value);
    GLfloat getLineWidth();

    bool minimalisticScanner();
    void setMinimalisticScanner(bool newValue);

    static Vector nonlinearScannerScale(Vector V, GLfloat zoom, double scale);
    bool nonlinearScanner();
    void setNonlinearScanner(bool newValue);

    bool scannerUltraZoom();
    void setScannerUltraZoom(bool newValue);

    oo::Ref<OOColor> reticleColorForIndex(NSUInteger idx);
    bool setReticleColorForIndex(NSUInteger idx, OOColor* newColor);

    bool checkPlayerInFlight();
    bool checkPlayerInSystemFlight();

    // Internal: dials, called by name on the facade (ADR-0055 item 5), which forwards them.
    void drawSurround(const oo::PList& info);
    void drawGreenSurround(const oo::PList& info);
    void drawYellowSurround(const oo::PList& info);
    void drawScanner(const oo::PList& info);
    void drawScannerZoomIndicator(const oo::PList& info);
    void drawCompass(const oo::PList& info);
    void drawAegis(const oo::PList& info);
    void drawTargetReticle(const oo::PList& info);
    void drawWaypoints(const oo::PList& info);
    void drawCustomBar(const oo::PList& info);
    void drawCustomText(const oo::PList& info);
    void drawCustomIndicator(const oo::PList& info);
    void drawCustomLight(const oo::PList& info);
    void drawCustomImage(const oo::PList& info);
    void drawSpeedBar(const oo::PList& info);
    void drawRollBar(const oo::PList& info);
    void drawPitchBar(const oo::PList& info);
    void drawYawBar(const oo::PList& info);
    void drawEnergyGauge(const oo::PList& info);
    void drawForwardShieldBar(const oo::PList& info);
    void drawAftShieldBar(const oo::PList& info);
    void drawFuelBar(const oo::PList& info);
    void drawWitchspaceDestination(const oo::PList& info);
    void drawCabinTempBar(const oo::PList& info);
    void drawWeaponTempBar(const oo::PList& info);
    void drawAltitudeBar(const oo::PList& info);
    void drawMissileDisplay(const oo::PList& info);
    void drawStatusLight(const oo::PList& info);
    void drawClock(const oo::PList& info);
    void drawPrimedEquipment(const oo::PList& info);
    void drawASCTarget(const oo::PList& info);
    void drawWeaponsOfflineText(const oo::PList& info);
    void drawFPSInfoCounter(const oo::PList& info);
    void drawScoopStatus(const oo::PList& info);
    void drawStickSensitivityIndicator(const oo::PList& info);
    void drawTrumbles(const oo::PList& info);

    // Internal: the state (the old ivars).
    // Widgets in draw order; were mutable arrays of array tuples (bead oo-3rb.49).
    std::vector<OOHUDWidget> legendArray;
    std::vector<OOHUDWidget> dialArray;
    std::vector<OOHUDWidget> mfdArray;

    // zoom level
    GLfloat scanner_zoom = { };

    // where to draw it
    GLfloat z1 = { };
    GLfloat lineWidth = { };

    std::optional<std::string> hudName;
    std::optional<std::string> deferredHudName; // Usually it will be nullopt. If engaged, then it means that we have a deferred HUD waiting to be drawn This may happen
                                                // for example when a script handler attempts to switch HUD while it is being rendered. - Nikos 20110628
    bool hudUpdating = { };

    GLfloat overallAlpha = { };

    bool reticleTargetSensitive = { }; // TO DO: Move this into the propertiesReticleTargetSensitive structure (Getafix - 2010/08/21)
    oo::PList propertiesReticleTargetSensitive; // isAccurate (bool), timeLastAccuracyProbabilityCalculation (double)

    bool cloakIndicatorOnStatusLight = { };

    bool hudHidden = { };

    bool allowBigGui = { };

    int last_transmitter = { };

    std::set<std::string> _hiddenSelectors;

    // Crosshairs
    oo::Ref<OOCrosshairs> _crosshairs;
    OOWeaponType _lastWeaponType = { };
    GLfloat _lastOverallAlpha = { };
    bool _lastWeaponsOnline = { };
    oo::PList _crosshairOverrides; // null for none
    oo::Ref<OOColor> _crosshairColor;
    GLfloat _crosshairScale = { };
    GLfloat _crosshairWidth = { };
    std::optional<std::string> crosshairDefinition;
    bool _compassActive = { };

    std::vector<oo::Ref<OOColor>> _reticleColors;

    // essentially scanner without gridlines
    bool minimalistic_scanner = { };

    // Nonlinear scanner
    bool nonlinear_scanner = { };
    bool scanner_ultra_zoom = { };

private:
    void drawCrosshairs();
    void drawLegends();
    void drawDials();
    void drawMFDs();

    void drawLegend(const oo::PList& info);
    void drawHUDItem(const oo::PList& info);

    void drawMultiFunctionDisplay(const oo::PList& info, const std::string& text, NSUInteger index);

    void drawSurroundInternal(const oo::PList& info, const GLfloat color[4]);

    void drawCompassPlanetBlipAt(Vector relativePosition, NSSize siz, GLfloat alpha);
    void drawCompassStationBlipAt(Vector relativePosition, NSSize siz, GLfloat alpha);
    void drawCompassSunBlipAt(Vector relativePosition, NSSize siz, GLfloat alpha);
    void drawCompassTargetBlipAt(Vector relativePosition, NSSize siz, GLfloat alpha);
    void drawCompassBeaconBlipAt(Vector relativePosition, NSSize siz, GLfloat alpha);

    void drawSecondaryTargetReticle(const oo::PList& info);

    // status: an OOMissileStatus (PlayerEntity.h, which this header does not import: it would close an import cycle).
    void drawIconForMissile(::ShipEntity* missile, bool selected, int status, int x, int y, GLfloat width, GLfloat height, GLfloat alpha);
    void drawIconForEmptyPylonAtX(int x, int y, GLfloat width, GLfloat height, GLfloat alpha);
    void drawDirectionCue(const oo::PList& info);

    oo::PList crosshairDefinitionForWeaponType(OOWeaponType weapon); // a null PList for none

    void resetGui(::GuiDisplayGen* gui, const oo::PList& gui_info);
    void resetGuiPosition(::GuiDisplayGen* gui, const oo::PList& gui_info);
};

} // namespace cxx

/*	The compass icon of a beacon whose code names no icon: the code's first character, drawn as
        text. It replaces the NSString (OOHUDBeaconIcon) category (bead oo-f9rf) the entities' beacon
        drawables used; the drawing is the category's. The entities hold it by the OOHUDBeaconIcon
        protocol (HeadUpDisplay+ObjCBridge.h) through its facade (bead oo-2p1ug; ADR-0056 amendments
        oo-jpd8, oo-4nhg).
*/
namespace cxx {

class OOPolygonSprite;

class OOHUDBeaconCodeIcon : public oo::RefCounted {
public:
    explicit OOHUDBeaconCodeIcon(const std::string& text); // -initWithText:

    void drawHUDBeaconIconAt(NSPoint where, NSSize size, GLfloat alpha, GLfloat z); // -oo_drawHUDBeaconIconAt:size:alpha:z:

private:
    std::string _text;
};

} // namespace cxx

// -[OOPolygonSprite oo_drawHUDBeaconIconAt:size:alpha:z:] (the sprite's OOHUDBeaconIcon category).
void OOPolygonSpriteDrawHUDBeaconIcon(cxx::OOPolygonSprite* sprite, NSPoint where, NSSize size, GLfloat alpha, GLfloat z);

void cxx_OODrawString(const std::string& text, GLfloat x, GLfloat y, GLfloat z, NSSize siz);
void cxx_OODrawStringAligned(const std::string& text, GLfloat x, GLfloat y, GLfloat z, NSSize siz, BOOL rightAlign);

/* cxx_OODrawString(Aligned) handles all the string drawing, but because
 * it does texture application and GL_QUADS beginning once per string
 * it's quite slow.
 *
 * Where efficiency is needed, call OOStartDrawingStrings(), then
 * cxx_OODrawStringQuadsAligned for each bit of text, then
 * OOStopDrawingStrings().
 *
 * Trying to draw anything else between OOStartDrawingStrings() and
 * OOStopDrawingStrings() will have messy results. You can safely call
 * Stop, draw the other thing you want, then call Start again - it's
 * just a little inefficient. Similarly calling
 * cxx_OODrawStringQuadsAligned() without calling OOStartDrawingStrings()
 * won't work very well.
 *
 * - CIM
 */
void OOStartDrawingStrings(void);
void cxx_OODrawStringQuadsAligned(const std::string& text, GLfloat x, GLfloat y, GLfloat z, NSSize siz, BOOL rightAlign);
void OOStopDrawingStrings(void);

void cxx_OODrawHilightedString(const std::string& text, GLfloat x, GLfloat y, GLfloat z, NSSize siz);
void OODrawPlanetInfo(int gov, int eco, int tec, GLfloat x, GLfloat y, GLfloat z, NSSize siz);
void OODrawHilightedPlanetInfo(int gov, int eco, int tec, GLfloat x, GLfloat y, GLfloat z, NSSize siz);
NSRect cxx_OORectFromString(const std::string& text, GLfloat x, GLfloat y, NSSize siz);

#include "OOStringWidth.h" // cxx_OOStringWidthInEm() (bead oo-9ht.72: plain header)

void OOHUDResetTextEngine(void);

// Transitional: the Objective-C facade, for the callers that are still Objective-C.
// Deleted, with namespace cxx above, by the bridge's deletion bead.
#import "HeadUpDisplay+ObjCBridge.h"
