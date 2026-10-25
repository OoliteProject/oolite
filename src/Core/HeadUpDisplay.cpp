/*

HeadUpDisplay.m

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

#include "OOCocoa.h"
#include "oofnd/objc/OOException.h"
#include "HeadUpDisplay.h"
#include "GameController.h"
#include "ResourceManager.h"
#include "PlayerEntity.h"
#include "OOSunEntity.h"
#include "OOPlanetEntity.h"
#include "StationEntity.h"
#include "OOVisualEffectEntity.h"
#include "OOQuiriumCascadeEntity.h"
#include "OOWaypointEntity.h"
#include "Universe.h"
#include "OOTrumble.h"
#include "OOColor.h"
#include "GuiDisplayGen.h"
#include "OOTexture.h"
#include "OOTextureSprite.h"
#include "OOPolygonSprite.h"
#include "OOEncodingConverter.h"
#include "OOCrosshairs.h"
#include "OOConstToString.h"
#include "OOStringParsing.h"
#include "OOJoystickManager.h"
#include "OOJavaScriptEngine.h"
#include "OOStringExpander.h"

#include "oofnd/Log.hpp"
#include "oofnd/StdLib.hpp"
#include "oofnd/objc/OOAssert.h"
#include "OOObjCPList.h"
#include "oofnd/String.hpp"


#define ONE_SIXTEENTH				0.0625
#define ONE_SIXTYFOURTH				0.015625
#define DEFAULT_OVERALL_ALPHA		0.75
#define GLYPH_SCALE_FACTOR			0.13		// 0.13 is an inherited magic number
#define IDENTIFY_SCANNER_LOLLIPOPS	(	0	&& OOLITE_DEBUG)


#define NOT_DEFINED					INFINITY

/* Convenience macros to make set-colour-or-default quicker. 'info' must be the configuration (an oo::PList) and 'alpha' must be the overall alpha or these won't work */
#define DO_SET_COLOR(t,d)		SetGLColourFromInfo(info,t,d,alpha)
#define SET_COLOR(d)			DO_SET_COLOR(COLOR_KEY,d)
#define SET_COLOR_LOW(d)		DO_SET_COLOR(COLOR_KEY_LOW,d)
#define SET_COLOR_MEDIUM(d)		DO_SET_COLOR(COLOR_KEY_MEDIUM,d)
#define SET_COLOR_HIGH(d)		DO_SET_COLOR(COLOR_KEY_HIGH,d)
#define SET_COLOR_CRITICAL(d)	DO_SET_COLOR(COLOR_KEY_CRITICAL,d)
#define SET_COLOR_SURROUND(d)	DO_SET_COLOR(COLOR_KEY_SURROUND,d)

struct CachedInfo
{
	float x, y, x0, y0;
	float width, height, alpha;
};

// A dial: a member called by name with its hud.plist entry (ADR-0055 item 5).
typedef void (HeadUpDisplay::*OOHUDDial)(const oo::PList &info);

/*	One legend, dial or MFD. Was an array tuple [info, boxed CachedInfo, boxed SEL,
	selector name] (bead oo-3rb.49); the widget lists are std::vectors of these, in the
	same order, filled only while the HUD is initialised.
*/
struct OOHUDWidget
{
	oo::PList			info;				// the hud.plist entry
	struct CachedInfo	cache;
	BOOL				hasCache;			// NO only for an MFD whose info was not a dictionary (below)
	OOHUDDial			dial;				// dials only: the member the selector names (DialNamed())
	std::string			selectorString;		// dials only
	oo::Ref<OOTextureSprite>	sprite;		// legends only: the image legend's sprite (the entry held its facade until bead oo-9ht.71)
};

namespace {

const OOHUDWidget *sCurrentDrawItem;


/*	The current widget's cached geometry. An MFD entry that is not a dictionary was a tuple
	built with arrayWithObjects: starting at its nil info, i.e. an empty array, and reading
	its cache raised this exception (caught by Universe's render loop); keep that.
*/
void GetCurrentCachedInfo(struct CachedInfo *cached)
{
	if (EXPECT_NOT(!sCurrentDrawItem->hasCache))
	{
		OORaiseException(OORangeException, "Index 1 is out of range 0 (in 'objectAtIndex:')");
	}
	*cached = sCurrentDrawItem->cache;
}


void AddHUDWidget(std::vector<OOHUDWidget> &widgets, const oo::PList &info, const struct CachedInfo *cache, OOHUDDial dial, const std::string &selectorString)
{
	widgets.push_back(OOHUDWidget{ info, *cache, !info.isNull(), dial, selectorString, {} });
}


/*	The dials by selector name (bead oo-mwd58, proposed ADR-0056 amendment oo-9ht.1): exactly the
	selectors the HUD's Objective-C facade answered (its OODials category, one forwarder per dial
	member), so a whitelisted name the facade did not answer is still "not implemented".
*/
const struct
{
	std::string_view	name;
	OOHUDDial			dial;
} kDials[] =
{
	{ "drawSurround:", &HeadUpDisplay::drawSurround },
	{ "drawGreenSurround:", &HeadUpDisplay::drawGreenSurround },
	{ "drawYellowSurround:", &HeadUpDisplay::drawYellowSurround },
	{ "drawScanner:", &HeadUpDisplay::drawScanner },
	{ "drawScannerZoomIndicator:", &HeadUpDisplay::drawScannerZoomIndicator },
	{ "drawCompass:", &HeadUpDisplay::drawCompass },
	{ "drawAegis:", &HeadUpDisplay::drawAegis },
	{ "drawTargetReticle:", &HeadUpDisplay::drawTargetReticle },
	{ "drawWaypoints:", &HeadUpDisplay::drawWaypoints },
	{ "drawCustomBar:", &HeadUpDisplay::drawCustomBar },
	{ "drawCustomText:", &HeadUpDisplay::drawCustomText },
	{ "drawCustomIndicator:", &HeadUpDisplay::drawCustomIndicator },
	{ "drawCustomLight:", &HeadUpDisplay::drawCustomLight },
	{ "drawCustomImage:", &HeadUpDisplay::drawCustomImage },
	{ "drawSpeedBar:", &HeadUpDisplay::drawSpeedBar },
	{ "drawRollBar:", &HeadUpDisplay::drawRollBar },
	{ "drawPitchBar:", &HeadUpDisplay::drawPitchBar },
	{ "drawYawBar:", &HeadUpDisplay::drawYawBar },
	{ "drawEnergyGauge:", &HeadUpDisplay::drawEnergyGauge },
	{ "drawForwardShieldBar:", &HeadUpDisplay::drawForwardShieldBar },
	{ "drawAftShieldBar:", &HeadUpDisplay::drawAftShieldBar },
	{ "drawFuelBar:", &HeadUpDisplay::drawFuelBar },
	{ "drawWitchspaceDestination:", &HeadUpDisplay::drawWitchspaceDestination },
	{ "drawCabinTempBar:", &HeadUpDisplay::drawCabinTempBar },
	{ "drawWeaponTempBar:", &HeadUpDisplay::drawWeaponTempBar },
	{ "drawAltitudeBar:", &HeadUpDisplay::drawAltitudeBar },
	{ "drawMissileDisplay:", &HeadUpDisplay::drawMissileDisplay },
	{ "drawStatusLight:", &HeadUpDisplay::drawStatusLight },
	{ "drawClock:", &HeadUpDisplay::drawClock },
	{ "drawPrimedEquipment:", &HeadUpDisplay::drawPrimedEquipment },
	{ "drawASCTarget:", &HeadUpDisplay::drawASCTarget },
	{ "drawWeaponsOfflineText:", &HeadUpDisplay::drawWeaponsOfflineText },
	{ "drawFPSInfoCounter:", &HeadUpDisplay::drawFPSInfoCounter },
	{ "drawScoopStatus:", &HeadUpDisplay::drawScoopStatus },
	{ "drawStickSensitivityIndicator:", &HeadUpDisplay::drawStickSensitivityIndicator },
	{ "drawTrumbles:", &HeadUpDisplay::drawTrumbles },
};


// The dial member a selector names; nullptr if the HUD has none (-respondsToSelector: was NO).
OOHUDDial DialNamed(std::string_view name)
{
	for (const auto &entry : kDials)
	{
		if (entry.name == name)  return entry.dial;
	}
	return nullptr;
}


void ReleaseHUDWidgets(std::vector<OOHUDWidget> &widgets)
{
	widgets.clear();
}


/*	A string from the configuration, nullopt where oo_stringForKey: gave nil: the key is absent,
	or its value is neither a string nor a number (a number reads as its -stringValue).
*/
std::optional<std::string> OptionalStringIn(const oo::PList &info, std::string_view key)
{
	const oo::PList *value = info.find(key);
	if (value == nullptr || !(value->isString() || value->isNumber()))  return std::nullopt;
	return info.get<std::string>(key);
}


/*	A value from the configuration as -objectForKey: gave it, a null PList where that gave nil
	(the key is absent), for +[OOColor cxx_colorWithDescription:] (null gives nil, as nil did).
*/
oo::PList PListForKeyIn(const oo::PList &info, std::string_view key)
{
	const oo::PList *value = info.find(key);
	return (value != nullptr) ? *value : oo::PList();
}


/*	A string element of an array, nullopt where oo_stringAtIndex: gave nil (past the end, or
	neither a string nor a number).
*/
std::optional<std::string> OptionalStringAt(const oo::PList &array, std::size_t index)
{
	const oo::PList *value = array.at(index);
	if (value == nullptr || !(value->isString() || value->isNumber()))  return std::nullopt;
	return array.at<std::string>(index);
}


/*	-objectAtIndex: on the reticle colours. They are built as +arrayWithObjects: built them,
	stopping at the first colour that did not parse, so the list may be short; an index past its
	end raised, and still does, with the same text.
*/
OOColor *ReticleColorAt(const std::vector<oo::Ref<OOColor>> &colors, NSUInteger index)
{
	if (EXPECT_NOT(index >= colors.size()))
	{
		OORaiseException(OORangeException, "Index %lu is out of range %lu (in 'objectAtIndex:')", (unsigned long)index, (unsigned long)colors.size());
	}
	return colors[index].get();
}

}	// namespace

OOINLINE float useDefined(float val, float validVal) 
{
	return (val == NOT_DEFINED) ? validVal : val;
}


static void DrawSpecialOval(GLfloat x, GLfloat y, GLfloat z, NSSize siz, GLfloat step, GLfloat* color4v);

namespace {
void SetGLColourFromInfo(const oo::PList &info, const char *key, const GLfloat defaultColor[4], GLfloat alpha);
void GetRGBAArrayFromInfo(const oo::PList &info, GLfloat ioColor[4]);
}	// namespace

static void hudDrawIndicatorAt(GLfloat x, GLfloat y, GLfloat z, NSSize siz, GLfloat amount);
static void hudDrawMarkerAt(GLfloat x, GLfloat y, GLfloat z, NSSize siz, GLfloat amount);
static void hudDrawBarAt(GLfloat x, GLfloat y, GLfloat z, NSSize siz, GLfloat amount);
static void hudDrawSurroundAt(GLfloat x, GLfloat y, GLfloat z, NSSize siz);
static void hudDrawStatusIconAt(int x, int y, int z, NSSize siz);
namespace { void hudDrawReticleOnTarget(Entity* target, PlayerEntity* player1, GLfloat z1,
				GLfloat alpha, BOOL reticleTargetSensitive, oo::PList *propertiesReticleTargetSensitive,
				BOOL colourFromScannerColour, BOOL showText, const oo::PList &info, const std::vector<oo::Ref<OOColor>> &reticleColors); }	// the C++ target (bead oo-9ht.39.27)
namespace { void hudDrawWaypoint(Entity *waypoint, PlayerEntity *player1, GLfloat z1, GLfloat alpha, BOOL selected, GLfloat scale); }	// the C++ waypoint (bead oo-9ht.39.27)
static void hudRotateViewpointForVirtualDepth(PlayerEntity * player1, Vector p1);
static void drawScannerGrid(GLfloat x, GLfloat y, GLfloat z, NSSize siz, int v_dir, GLfloat thickness, GLfloat zoom, BOOL nonlinear, BOOL minimalistic);
static GLfloat nonlinearScannerFunc(GLfloat distance, GLfloat zoom, GLfloat scale);
static void GLDrawNonlinearCascadeWeapon( GLfloat x, GLfloat y, GLfloat z, NSSize siz, Vector centre, GLfloat radius, GLfloat zoom, GLfloat alpha );

static OOTexture			*sFontTexture = nil;
static OOEncodingConverter	*sEncodingCoverter = nil;


enum
{
	kFontTextureOptions = kOOTextureMinFilterMipMap | kOOTextureMagFilterLinear | kOOTextureNoShrink | kOOTextureAlphaMask
};


static const GLfloat red_color[4] =			{1.0, 0.0, 0.0, 1.0};
static const GLfloat redplus_color[4] =		{1.0, 0.0, 0.5, 1.0};
static const GLfloat yellow_color[4] =  	{1.0, 1.0, 0.0, 1.0};
static const GLfloat green_color[4] =		{0.0, 1.0, 0.0, 1.0};
static const GLfloat darkgreen_color[4] =	{0.0, 0.75, 0.0, 1.0};
static const GLfloat blue_color[4] =		{0.0, 0.0, 1.0, 1.0};
static const GLfloat black_color[4] =		{0.0, 0.0, 0.0, 1.0};
static const GLfloat lightgray_color[4] =	{0.25, 0.25, 0.25, 1.0};

static float	sGlyphWidths[256];
static float    sF6KernGovt;
static float    sF6KernTL;
static BOOL		_compassUpdated;


static GLfloat drawCharacterQuad(uint8_t chr, GLfloat x, GLfloat y, GLfloat z, NSSize siz);

static void InitTextEngine(void);

namespace {
void prefetchData(const oo::PList &info, struct CachedInfo *data);
}	// namespace


OOINLINE void GLColorWithOverallAlpha(const GLfloat *color, GLfloat alpha)
{
	// NO OOGL(), this is called within immediate mode blocks.
	glColor4f(color[0], color[1], color[2], color[3] * alpha);
}
//------------------------------------------------------------------------------------//
//	The class shell (slice 1): HeadUpDisplay's members. The drawing (slices 2-6) follows; the
//	facade (HeadUpDisplay+ObjCBridge) was deleted by bead oo-mwd58.

HeadUpDisplay::HeadUpDisplay() = default;


HeadUpDisplay::~HeadUpDisplay()
{
	ReleaseHUDWidgets(legendArray);
	ReleaseHUDWidgets(dialArray);
	ReleaseHUDWidgets(mfdArray);
}


void HeadUpDisplay::initWithDictionary(const oo::PList &hudinfo, const std::optional<std::string> &hudFileName)
{
	unsigned		i;
	bool			isCompassToBeDrawn = false;
	bool			areTrumblesToBeDrawn = false;
	const oo::PList	&info = hudinfo;

	lineWidth = 1.0;

	if (sFontTexture == nil)  InitTextEngine();

	deferredHudName.reset();	// if engaged, it means that we have a deferred HUD which is to be drawn at first available opportunity
	hudName = hudFileName;

	// init arrays
	dialArray.reserve(16);
	legendArray.reserve(16);
	mfdArray.reserve(8);

	_reticleColors.clear();
	bool reticleColorsSet = false;

	// populate arrays
	const oo::PList *dials = info.get<oo::PList::Array>(DIALS_KEY);
	const oo::PList noEntry;	// an entry that is not a dictionary, as nil was
	for (i = 0; dials != nullptr && i < dials->count(); i++)
	{
		const oo::PList	*dialEntry = dials->at<oo::PList::Dict>(i);
		const oo::PList	&dial_info = (dialEntry != nullptr) ? *dialEntry : noEntry;
		if (!areTrumblesToBeDrawn && dial_info.get<std::string>(SELECTOR_KEY) == "drawTrumbles:")  areTrumblesToBeDrawn = true;
		if (!isCompassToBeDrawn && dial_info.get<std::string>(SELECTOR_KEY) == "drawCompass:")  isCompassToBeDrawn = true;
		if (dial_info.get<std::string>(SELECTOR_KEY) == "drawTargetReticle:")
		{
			oo::PList targetColor = PListForKeyIn(dial_info, "target_rgba");
			oo::PList targetSensitiveColor = PListForKeyIn(dial_info, "target_sensitive_rgba");
			oo::PList wormholeColor = PListForKeyIn(dial_info, "wormhole_rgba");
			if (targetColor.isNull())  targetColor = oo::PList("greenColor");
			if (targetSensitiveColor.isNull())  targetSensitiveColor = oo::PList("redColor");
			if (wormholeColor.isNull())  wormholeColor = oo::PList("cyanColor");
			oo::Ref<OOColor> colors[3] = { OOColor::colorWithDescription(targetColor),
										   OOColor::colorWithDescription(targetSensitiveColor),
										   OOColor::colorWithDescription(wormholeColor) };
			_reticleColors.clear();
			for (const oo::Ref<OOColor> &color : colors)
			{
				if (color == nullptr)  break;	// the list stops at the first nil, as +arrayWithObjects: did
				_reticleColors.push_back(color);
			}
			reticleColorsSet = true;
		}
		addDial(dial_info);
	}

	// reticle colors should be set at this point, but just be safe in case they are not
	if (!reticleColorsSet)
	{
		_reticleColors = { OOColor::greenColor(), OOColor::redColor(), OOColor::cyanColor() };
	}

	if (!areTrumblesToBeDrawn)	// naughty - a hud with no built-in drawTrumbles: - one must be added!
	{
		const oo::PList	trumble_dial_info(oo::PList::Dict{ { SELECTOR_KEY, oo::PList(std::string("drawTrumbles:")) } });
		addDial(trumble_dial_info);
	}

	_compassActive = isCompassToBeDrawn;

	_lastWeaponType = nullptr;

	const oo::PList *legends = info.get<oo::PList::Array>(LEGENDS_KEY);
	for (i = 0; legends != nullptr && i < legends->count(); i++)
	{
		const oo::PList *legend = legends->at<oo::PList::Dict>(i);
		addLegend((legend != nullptr) ? *legend : noEntry);
	}

	const oo::PList *mfds = info.get<oo::PList::Array>(MFDS_KEY);
	for (i = 0; mfds != nullptr && i < mfds->count(); i++)
	{
		const oo::PList *mfd = mfds->at<oo::PList::Dict>(i);
		addMFD((mfd != nullptr) ? *mfd : noEntry);
	}


	hudHidden = false;

	_hiddenSelectors.clear();

	hudUpdating = false;

	overallAlpha = info.get<float>("overall_alpha", DEFAULT_OVERALL_ALPHA);

	reticleTargetSensitive = info.get<bool>("reticle_target_sensitive", false);
	propertiesReticleTargetSensitive = oo::PList(oo::PList::Dict{
										{ "isAccurate", oo::PList(static_cast<bool>(true)) },
										{ "timeLastAccuracyProbabilityCalculation", oo::PList(static_cast<double>((UNIVERSE != nullptr ? UNIVERSE->getTime() : 0.0))) } });

	cloakIndicatorOnStatusLight = info.get<bool>("cloak_indicator_on_status_light", true);

	allowBigGui = info.get<bool>("allow_big_gui", false);

	last_transmitter = NO_TARGET;

	crosshairDefinition.reset();

	std::optional<std::string> crossfile = OptionalStringIn(info, "crosshair_file");
	if (!crossfile.has_value())
	{
		const oo::PList *crosshairs = info.get<oo::PList::Dict>("crosshairs");
		_crosshairOverrides = (crosshairs != nullptr) ? *crosshairs : oo::PList();
		crosshairDefinition.reset();
	}
	else
	{
		setCrosshairDefinition(*crossfile);
	}

	oo::PList crosshairColor = PListForKeyIn(info, "crosshair_color");
	if (crosshairColor.isNull())  crosshairColor = oo::PList("greenColor");
	_crosshairColor = OOColor::colorWithDescription(crosshairColor);
	_crosshairScale = info.get<float>("crosshair_scale", 32.0f);
	_crosshairWidth = info.get<float>("crosshair_width", 1.5f);

	minimalistic_scanner = info.get<bool>("scanner_minimalistic", false);

	nonlinear_scanner = info.get<bool>("scanner_non_linear", false);
	scanner_ultra_zoom = info.get<bool>("scanner_ultra_zoom", false);
}

//------------------------------------------------------------------------------------//


void HeadUpDisplay::resetGui(::GuiDisplayGen *gui, const oo::PList &gui_info)
{
	resetGuiPosition(gui, gui_info);

	NSSize		siz =	gui->size();
	int			rht =	gui->rowHeight();
	std::optional<std::string>	title =	gui->getTitle();
	if (gui_info.find(WIDTH_KEY) != nullptr)
		siz.width = gui_info.get<float>(WIDTH_KEY);
	if (gui_info.find(HEIGHT_KEY) != nullptr)
		siz.height = gui_info.get<float>(HEIGHT_KEY);
	if (gui_info.find(ROW_HEIGHT_KEY) != nullptr)
		rht = gui_info.get<float>(ROW_HEIGHT_KEY);
	if (gui_info.find(TITLE_KEY) != nullptr)
		title = OptionalStringIn(gui_info, TITLE_KEY);
	gui->resizeTo(siz, rht, title);
	if (gui_info.find(BACKGROUND_RGBA_KEY) != nullptr)
		gui->setBackgroundColor(OOColor::colorFromString(gui_info.get<std::string>(BACKGROUND_RGBA_KEY)).get());
	if (gui_info.find(ALPHA_KEY) != nullptr)
		gui->setMaxAlpha(OOClamp_0_max_f(gui_info.get<float>(ALPHA_KEY),1.0f));
	else
		gui->setMaxAlpha(1.0f);
}


void HeadUpDisplay::resetGuiPosition(::GuiDisplayGen *gui, const oo::PList &gui_info)
{
	Vector pos = gui->getDrawPosition();
	if (gui_info.find(X_KEY) != nullptr)
		pos.x = gui_info.get<float>(X_KEY) +
			(UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr ? UNIVERSE->getGameView()->getX_offset() : 0.0f) *
			gui_info.get<float>(X_ORIGIN_KEY, 0.0);
	if (gui_info.find(Y_KEY) != nullptr)
		pos.y = gui_info.get<float>(Y_KEY) +
			(UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr ? UNIVERSE->getGameView()->getY_offset() : 0.0f) *
			gui_info.get<float>(Y_ORIGIN_KEY, 0.0);

	gui->setDrawPosition(pos);
}


void HeadUpDisplay::resetGuis(const oo::PList &info)
{
	// check for entries in hud.plist for message_gui and comm_log_gui
	// then resize and reposition them accordingly.

	::GuiDisplayGen*	gui = (UNIVERSE != nullptr ? UNIVERSE->messageGUI() : nullptr);
	const oo::PList	*gui_info = info.get<oo::PList::Dict>("message_gui");	// nullptr where nil was
	if (gui && gui_info != nullptr && gui_info->count() > 0)
	{
		/*
			If switching message guis, remember the last 2 message lines.
			Present GUI limitations make it impractical to transfer anything
			more...

			TODO: a more usable GUI code! - Kaks 2011.11.05
		*/

		const oo::PList	lastLines = gui->getLastLines();	// text, colour, fade time - text, colour, fade time
		bool		line1 = OptionalStringAt(lastLines, 0) != "";	// a missing line counted as not empty
		resetGui(gui, *gui_info);

		bool permanent = gui_info->get<bool>("permanent", false);
		if (UNIVERSE != nullptr)  UNIVERSE->setPermanentMessageLog(permanent);

		bool automaticBg = gui_info->get<bool>("background_automatic", true);
		if (UNIVERSE != nullptr)  UNIVERSE->setAutoMessageLogBg(automaticBg);

		// set message gui text colors - one for standard messages, one for incoming comms
		// incoming comms message color must default to green for compatibility with older huds that
		// don't have this key
		gui->setTextColor(OOColor::colorWithDescription(PListForKeyIn(*gui_info, "text_color")).get());
		oo::Ref<OOColor> textCommsColor = OOColor::colorWithDescription(PListForKeyIn(*gui_info, "text_comms_color"));
		if (!textCommsColor)  textCommsColor = OOColor::greenColor();
		gui->setTextCommsColor(textCommsColor.get());

		if (line1)
		{
			gui->printLongText(OptionalStringAt(lastLines, 0), GUI_ALIGN_CENTER, OOColor::colorFromString(lastLines.at<std::string>(1)).get(), (permanent?0.0:lastLines.at<float>(2)), std::nullopt, nullptr);
		}
		if (lastLines.count() > 3 && (line1 || OptionalStringAt(lastLines, 3) != ""))
		{
			gui->printLongText(OptionalStringAt(lastLines, 3), GUI_ALIGN_CENTER, OOColor::colorFromString(lastLines.at<std::string>(4)).get(), (permanent?0.0:lastLines.at<float>(5)), std::nullopt, nullptr);
		}
	}

	if (gui_info != nullptr && gui_info->count() == 0)
	{
		// exists and it's empty. complete reset.
		if (gui != nullptr)	// messages to nil did nothing
		{
			gui->setCurrentRow(8);
			gui->setDrawPosition(make_vector(0.0, -40.0, 640.0));
			gui->resizeTo(NSMakeSize(480, 160), 19, std::nullopt);
			gui->setCharacterSize(NSMakeSize(16,20));	// narrow characters
			gui->setTextColor(OOColor::yellowColor().get());
			gui->setTextCommsColor(OOColor::greenColor().get());
		}
		if (UNIVERSE != nullptr)  UNIVERSE->setPermanentMessageLog(NO);
		if (UNIVERSE != nullptr)  UNIVERSE->setAutoMessageLogBg(YES);
	}

	if (gui != nullptr)  gui->setAlpha(1.0f);	// message_gui is always visible.

	// And now set up the comms log

	gui = (UNIVERSE != nullptr ? UNIVERSE->commLogGUI() : nullptr);
	gui_info = info.get<oo::PList::Dict>("comm_log_gui");

	if (gui && gui_info != nullptr && gui_info->count() > 0)
	{
		if (UNIVERSE != nullptr)  UNIVERSE->setAutoCommLog(gui_info->get<bool>("automatic", true));
		if (UNIVERSE != nullptr)  UNIVERSE->setPermanentCommLog(gui_info->get<bool>("permanent", false));

		/*
			We need to repopulate the comms log after resetting it.

			At the moment the colour information is set on a per-line basis, rather than a per-text basis.
			A comms message can span multiple lines, and two consecutive messages can share the same colour,
			so trying to match the colour information from the GUI with each message won't work.

			Bottom line: colour information is lost on comms log gui reset.
			And yes, this is yet another reason for the following

			TODO: a more usable GUI code! - Kaks 2011.11.05
		*/

		const std::vector<std::string> *liveLog = (PLAYER != nullptr ? PLAYER->getCommLog() : (std::vector<std::string> *)nullptr);
		const std::vector<std::string> cLog = (liveLog != nullptr) ? *liveLog : std::vector<std::string>();
		NSUInteger i, commCount = cLog.size();

		resetGui(gui, *gui_info);

		for (i = 0; i < commCount; i++)
		{
			gui->printLongText(cLog[i], GUI_ALIGN_LEFT, nil, 0.0, std::nullopt, nullptr);
		}
	}

	if (gui_info != nullptr && gui_info->count() == 0)
	{
		// exists and it's empty. complete reset.
		if (UNIVERSE != nullptr)  UNIVERSE->setAutoCommLog(YES);
		if (UNIVERSE != nullptr)  UNIVERSE->setPermanentCommLog(NO);
		if (gui != nullptr)	// messages to nil did nothing
		{
			gui->setCurrentRow(9);
			gui->setDrawPosition(make_vector(0.0, 180.0, 640.0));
			gui->resizeTo(NSMakeSize(360, 120), 12, std::nullopt);
			gui->setBackgroundColor(OOColor::colorWithRed(0.0, 0.05, 0.45, 0.5).get());
			gui->setTextColor(OOColor::whiteColor().get());
			gui->printLongText(OO_DESC("communications-log-string"), GUI_ALIGN_CENTER, OOColor::yellowColor().get(), 0, std::nullopt, nullptr);
		}
	}

	if (gui == nullptr)  return;	// messages to nil did nothing
	if ((UNIVERSE != nullptr ? UNIVERSE->permanentCommLog() : false))
	{
		gui->stopFadeOuts();
		gui->setAlpha(1.0);
	}
	else
	{
		gui->setAlpha(0.0);
	}
}


std::optional<std::string> HeadUpDisplay::getHudName()
{
	return hudName;
}


void HeadUpDisplay::setHudName(const std::optional<std::string> &newHudName)
{
	if (newHudName.has_value())
	{
		hudName = newHudName;
	}
}


oo::Ref<OOColor> HeadUpDisplay::reticleColorForIndex(NSUInteger idx)
{
	if (idx < _reticleColors.size())
	{
		return _reticleColors[idx];
	}
	return nullptr;
}


bool HeadUpDisplay::setReticleColorForIndex(NSUInteger idx, OOColor *newColor)
{
	if (newColor && idx < _reticleColors.size())
	{
		_reticleColors[idx] = oo::Ref<OOColor>(newColor);
		return true;
	}
	return false;
}


GLfloat HeadUpDisplay::scannerZoom()
{
	return scanner_zoom;
}


void HeadUpDisplay::setScannerZoom(GLfloat value)
{
	scanner_zoom = value;
}

GLfloat HeadUpDisplay::getOverallAlpha()
{
	return overallAlpha;
}


void HeadUpDisplay::setOverallAlpha(GLfloat newAlphaValue)
{
	overallAlpha = OOClamp_0_1_f(newAlphaValue);
}


bool HeadUpDisplay::getReticleTargetSensitive()
{
	return reticleTargetSensitive;
}


void HeadUpDisplay::setReticleTargetSensitive(bool newReticleTargetSensitiveValue)
{
	reticleTargetSensitive = !!newReticleTargetSensitiveValue; // ensure YES or NO.
}


oo::PList *HeadUpDisplay::getPropertiesReticleTargetSensitive()
{
	return &propertiesReticleTargetSensitive;
}


bool HeadUpDisplay::isHidden()
{
	return hudHidden;
}


void HeadUpDisplay::setHidden(bool newValue)
{
	hudHidden = !!newValue;	// ensure YES or NO
}


bool HeadUpDisplay::getAllowBigGui()
{
	return allowBigGui || hudHidden;
}


bool HeadUpDisplay::hasHidden(const std::optional<std::string> &selectorName)
{
	if (!selectorName.has_value())
	{
		return false;
	}
	return _hiddenSelectors.contains(*selectorName);
}


void HeadUpDisplay::setHiddenSelector(const std::string &selectorName, bool hide)
{
	if (hide)
	{
		_hiddenSelectors.insert(selectorName);
	}
	else
	{
		_hiddenSelectors.erase(selectorName);
	}
}


void HeadUpDisplay::clearHiddenSelectors()
{
	_hiddenSelectors.clear();
}


bool HeadUpDisplay::isCompassActive()
{
	return _compassActive;
}


void HeadUpDisplay::setCompassActive(bool newValue)
{
	_compassActive = !!newValue;
}


bool HeadUpDisplay::isUpdating()
{
	return hudUpdating;
}


void HeadUpDisplay::setDeferredHudName(const std::optional<std::string> &newDeferredHudName)
{
	deferredHudName = newDeferredHudName;
}


std::optional<std::string> HeadUpDisplay::getDeferredHudName()
{
	return deferredHudName;
}


void HeadUpDisplay::addLegend(const oo::PList &info)
{
	std::optional<std::string>	imageName;
	oo::Ref<OOTexture>	texture;
	NSSize				imageSize;
	oo::Ref<OOTextureSprite>	legendSprite;
	struct CachedInfo	cache;

	// prefetch data associated with this legend
	prefetchData(info, &cache);

	imageName = OptionalStringIn(info, IMAGE_KEY);
	if (imageName.has_value())
	{
		texture = OOTexture::textureWithName(imageName,
											 std::string("Images"),
											 kOOTextureDefaultOptions | kOOTextureNoShrink,
											 kOOTextureDefaultAnisotropy,
											 kOOTextureDefaultLODBias);
		if (texture == nullptr)
		{
			OO_LOG_ERR(cxx_kOOLogFileNotFound, "HeadUpDisplay couldn't get an image texture name for {}", *imageName);
			return;
		}

		imageSize = texture->dimensions();
		imageSize.width = info.get<float>(WIDTH_KEY, imageSize.width);
		imageSize.height = info.get<float>(HEIGHT_KEY, imageSize.height);

 		legendSprite = OOTextureSprite::initWithTexture(texture.get(), imageSize);

		// add info and cache to the list; the widget holds the sprite
		AddHUDWidget(legendArray, info, &cache, nullptr, "");
		legendArray.back().sprite = legendSprite;
	}
	else if (OptionalStringIn(info, TEXT_KEY).has_value())
	{
		// add info and cache to the list
		AddHUDWidget(legendArray, info, &cache, nullptr, "");

	}
}


void HeadUpDisplay::addDial(const oo::PList &info)
{
	static std::set<std::string> allowedSelectors;
	static bool allowedSelectorsLoaded = false;
	if (!allowedSelectorsLoaded)
	{
		const oo::PList whitelist = ResourceManager::whitelistDictionary();
		const oo::PList *dialMethods = whitelist.get<oo::PList::Array>("hud_dial_methods");
		// the set held what the array held; only strings can match a selector name
		for (std::size_t j = 0; dialMethods != nullptr && j < dialMethods->count(); j++)
		{
			if (const std::string *name = dialMethods->at(j)->getIf<std::string>())  allowedSelectors.insert(*name);
		}
		allowedSelectorsLoaded = true;
	}

	std::optional<std::string> selectorString = OptionalStringIn(info, SELECTOR_KEY);
	if (!selectorString.has_value())
	{
		OO_LOG_ERR("hud.dial.noSelector", "HUD dial in {} is missing selector.", hudName.value_or("(null)"));
		return;
	}

	if (!allowedSelectors.contains(*selectorString))
	{
		OO_LOG_ERR("hud.dial.invalidSelector", "HUD dial in {} uses selector \"{}\" which is not in whitelist, and will be ignored.", hudName.value_or("(null)"), *selectorString);
		return;
	}

	// the dials are members, called by name through the dial table (ADR-0055 item 5; bead oo-mwd58)
	const OOHUDDial dial = DialNamed(*selectorString);
	OOCAssert(dial != nullptr, "HUD dial in %s uses selector \"%s\" which is in whitelist, but not implemented.", hudName.value_or("(null)").c_str(), selectorString->c_str());

	//  handle the case above with NS_BLOCK_ASSERTIONS too.
	if (dial == nullptr)
	{
		OO_LOG_ERR("hud.dial.invalidSelector", "HUD dial in {} uses selector \"{}\"  which is in whitelist, but not implemented, and will be ignored.", hudName.value_or("(null)"), *selectorString);
		return;
	}

	// valid dial, now prefetch data
	struct CachedInfo cache;
	prefetchData(info, &cache);
	// add info, cache, selector and selector name to the list
	AddHUDWidget(dialArray, info, &cache, dial, *selectorString);
}


void HeadUpDisplay::addMFD(const oo::PList &info)
{
	struct CachedInfo cache;
	prefetchData(info, &cache);
	AddHUDWidget(mfdArray, info, &cache, nullptr, "");
}


NSUInteger HeadUpDisplay::mfdCount()
{
	return mfdArray.size();
}


std::optional<std::string> HeadUpDisplay::getCrosshairDefinition()
{
	return crosshairDefinition;
}


bool HeadUpDisplay::checkPlayerInFlight()
{
	return (PLAYER != nullptr ? PLAYER->isInSpace() : false) && (PLAYER != nullptr ? PLAYER->status() : OOEntityStatus{}) != STATUS_DOCKING;
}


bool HeadUpDisplay::checkPlayerInSystemFlight()
{
	::OOSunEntity		*the_sun = (UNIVERSE != nullptr ? UNIVERSE->sun() : nullptr);
	::OOPlanetEntity	*the_planet = (UNIVERSE != nullptr ? UNIVERSE->planet() : nullptr);

	return checkPlayerInFlight()		// be in the right mode
		&& the_sun && the_planet		// and be in a system
		&& !the_sun->goneNova();	// C++ since bead oo-9ht.111
}


bool HeadUpDisplay::minimalisticScanner()
{
	return minimalistic_scanner;
}


void HeadUpDisplay::setMinimalisticScanner(bool newValue)
{
	minimalistic_scanner = !!newValue;
}


Vector HeadUpDisplay::nonlinearScannerScale(Vector V, GLfloat zoom, double scale)
{
	OOScalar mag = magnitude(V);
	Vector unit = vector_normal(V);
	return vector_multiply_scalar(unit, nonlinearScannerFunc(mag, zoom, scale));
}


bool HeadUpDisplay::nonlinearScanner()
{
	return nonlinear_scanner;
}


void HeadUpDisplay::setNonlinearScanner(bool newValue)
{
	nonlinear_scanner = !!newValue;
}


bool HeadUpDisplay::scannerUltraZoom()
{
	return scanner_ultra_zoom;
}


void HeadUpDisplay::setScannerUltraZoom(bool newValue)
{
	scanner_ultra_zoom = !!newValue;
}


void HeadUpDisplay::refreshLastTransmitter()
{
	Entity *lt = (UNIVERSE != nullptr ? UNIVERSE->entityForUniversalID(last_transmitter) : nullptr);
	if ((lt == nullptr)||(!(lt->isShip)))
		return;
	::ShipEntity* st = oo::ToShip(lt);
	if ((st != nullptr ? st->getMessageTime() : 0.0) <= 0.0)
		if (st != nullptr)  st->setMessageTime(2.5);
}


void HeadUpDisplay::setLineWidth(GLfloat value)
{
	lineWidth = value;
}


GLfloat HeadUpDisplay::getLineWidth()
{
	return lineWidth;
}


/*
	SLOW_CODE
	As of 2012-09-13 (r5320), HUD rendering is taking 25%-30% of rendering time,
	or 15%-20% of game tick time, as tested on a couple of Macs using the
	default HUD and models. This could be worse - there used to be a note here
	saying 30%-40% of tick time - but could still improve.
	
	In a top-down perspective, of HUD rendering time, 67% is in -drawDials and
	27% is in -drawLegends.
	
	Bottom-up, one profile shows:
	21.2%	OODrawString()
			(Caching the glyph conversion here was a win, but caching geometry
			in vertex arrays/VBOs would be better.)
	8.9%	-[HeadUpDisplay drawHudItem:]
	5.1%	OOFloatFromObject
			(Reifying HUD info instead of parsing plists each frame would be
			a win.)
	4.4%	hudDrawBarAt()
			(Using fixed geometery and a vertex shader could help here,
			especially if bars are grouped together and drawn at once if
			possible.)
	4.3%	-[OOCrosshairs render]
			(Uses vertex arrays, but does more GL state manipulation than
			strictly necessary.)
	
*/
void HeadUpDisplay::renderHUD()
{
	hudUpdating = YES;
	
	OOVerifyOpenGLState();
	
	if ((_crosshairWidth * lineWidth) > 0)
	{
		OOGL(GLScaledLineWidth(_crosshairWidth * lineWidth));
		drawCrosshairs();
	}
	
	if (lineWidth > 0)
	{
		OOGL(GLScaledLineWidth(lineWidth));
		drawLegends();
	}
	
	drawDials();
	drawMFDs();
	cxx_OOCheckOpenGLErrors("After drawing HUD");
	
	OOVerifyOpenGLState();
	
	hudUpdating = NO;
}


void HeadUpDisplay::drawLegends()
{
	/* Since the order of legend drawing is significant, this loop must be kept
	 * as an incrementing one for compatibility with previous Oolite versions.
	 * CIM: 28/9/12 */
	z1 = (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr ? UNIVERSE->getGameView()->getDisplay_z() : 0.0f);
	NSUInteger i, nLegends = legendArray.size();
	for (i = 0; i < nLegends; i++)
	{
		sCurrentDrawItem = &legendArray[i];
		drawLegend(sCurrentDrawItem->info);
	}
}


void HeadUpDisplay::drawDials()
{	
	z1 = (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr ? UNIVERSE->getGameView()->getDisplay_z() : 0.0f);
	// reset drawScanner flag.
	_compassUpdated = NO;
	
	// tight loop, we assume dialArray doesn't change in mid-draw.
	NSUInteger i, nDials = dialArray.size();
	for (i = 0; i < nDials; i++)
	{
		sCurrentDrawItem = &dialArray[i];
		drawHUDItem(sCurrentDrawItem->info);
	}
	
	if (EXPECT_NOT(!_compassUpdated && _compassActive && checkPlayerInSystemFlight()))	// compass gone / broken / disabled ?
	{
		// trigger the targetChanged event with whom == null
		_compassActive = NO;
		if (PLAYER != nullptr)  PLAYER->doScriptEvent(OOJSID("compassTargetChanged"), { oo::PList(), oo::PList(cxx_OOStringFromCompassMode((PLAYER != nullptr ? PLAYER->getCompassMode() : OOCompassMode{}))) });	// null, as OONull gave
	}
	
}


void HeadUpDisplay::drawMFDs()
{
	NSUInteger i, nMFDs = mfdArray.size();
	std::optional<std::string> text;
	for (i = 0; i < nMFDs; i++)
	{
		text = (PLAYER != nullptr ? PLAYER->multiFunctionText(i) : std::optional<std::string>());
		if (text.has_value())
		{
			sCurrentDrawItem = &mfdArray[i];
			drawMultiFunctionDisplay(sCurrentDrawItem->info, *text, i);
		}
	}
}


void HeadUpDisplay::drawCrosshairs()
{
	OOViewID					viewID = (UNIVERSE != nullptr ? UNIVERSE->getViewDirection() : OOViewID{});
	OOWeaponType				weapon = (PLAYER != nullptr ? PLAYER->currentWeapon() : OOWeaponType{});
	BOOL						weaponsOnline = (PLAYER != nullptr ? PLAYER->weaponsOnline() : false);
	oo::PList					points;
	
	if (viewID == VIEW_CUSTOM ||
		overallAlpha == 0.0f ||
		!((PLAYER != nullptr ? PLAYER->status() : OOEntityStatus{}) == STATUS_IN_FLIGHT || (PLAYER != nullptr ? PLAYER->status() : OOEntityStatus{}) == STATUS_WITCHSPACE_COUNTDOWN) ||
		(UNIVERSE != nullptr ? UNIVERSE->getDisplayGUI() : false)
		)
	{
		// Don't draw crosshairs
		return;
	}
	
	if (weapon != _lastWeaponType || overallAlpha != _lastOverallAlpha || weaponsOnline != _lastWeaponsOnline)
	{
		_crosshairs = nullptr;
	}
	
	if (_crosshairs == nullptr)
	{
		GLfloat useAlpha = weaponsOnline ? overallAlpha : overallAlpha * 0.5f;
		
		// Make new crosshairs object
		points = crosshairDefinitionForWeaponType(weapon);
		
		_crosshairs = oo::makeRef<OOCrosshairs>(points, _crosshairScale, _crosshairColor.get(), useAlpha);
		_lastWeaponType = weapon;
		_lastOverallAlpha = useAlpha;
		_lastWeaponsOnline = weaponsOnline;
	}
	
	_crosshairs->render();
}


bool HeadUpDisplay::setCrosshairDefinition(const std::string &newDefinition)
{
	// force crosshair redraw
	_crosshairs = nullptr;

	_crosshairOverrides = ResourceManager::dictionaryFromFilesNamed(newDefinition, std::string("Config"), YES);
	if (_crosshairOverrides.count() == 0)
	{ // invalid file (none found, or empty)
		_crosshairOverrides = ResourceManager::dictionaryFromFilesNamed("crosshairs.plist", std::string("Config"), YES);
		crosshairDefinition = "crosshairs.plist";
		return NO;
	}
	crosshairDefinition = newDefinition;
	return YES;
}


oo::PList HeadUpDisplay::crosshairDefinitionForWeaponType(OOWeaponType weapon)
{
	std::string					weaponName;
	std::string					weaponName2;
	static						oo::PList crosshairDefs;	// null until loaded
	const oo::PList				*result = nullptr;
	
	/*	Search order:
	 (hud.plist).crosshairs.WEAPON_NAME
	 (hud.plist).crosshairs.OTHER
	 (crosshairs.plist).WEAPON_NAME
	 (crosshairs.plist).OTHER
	 */
	
	weaponName = cxx_OOStringFromWeaponType(weapon).value_or("");
	weaponName2 = weaponName.substr(3); // strip "EQ_"
	result = _crosshairOverrides.get<oo::PList::Array>(weaponName);
	if (result == nullptr)
	{
		result = _crosshairOverrides.get<oo::PList::Array>(weaponName2);
	}
	if (result == nullptr)  result = _crosshairOverrides.get<oo::PList::Array>("OTHER");
	if (result == nullptr)
	{
		if (crosshairDefs.isNull())
		{
			crosshairDefs = ResourceManager::dictionaryFromFilesNamed("crosshairs.plist", std::string("Config"), YES);
		}

		result = crosshairDefs.get<oo::PList::Array>(weaponName);
		if (result == nullptr)
		{
			result = crosshairDefs.get<oo::PList::Array>(weaponName2);
		}
		if (result == nullptr)  result = crosshairDefs.get<oo::PList::Array>("OTHER");
	}

	return (result != nullptr) ? *result : oo::PList();
}


void HeadUpDisplay::drawLegend(const oo::PList &info)
{
	// check if equipment is required
	std::optional<std::string> equipmentRequired = OptionalStringIn(info, EQUIPMENT_REQUIRED_KEY);
	if (equipmentRequired.has_value() && !(PLAYER != nullptr ? PLAYER->hasEquipmentItemProviding(*equipmentRequired) : false))
	{
		return;
	}

	// check alert condition
	NSUInteger alertMask = info.get<unsigned int>(ALERT_CONDITIONS_KEY, 15);
	// 1=docked, 2=green, 4=yellow, 8=red
	if (alertMask < 15)
	{
		OOAlertCondition alertCondition = (PLAYER != nullptr ? PLAYER->getAlertCondition() : OOAlertCondition{});
		if (~alertMask & (1 << alertCondition)) {
			return;
		}
	}

	BOOL viewOnly = info.get<bool>(VIEWSCREEN_KEY, NO);
	// 1=docked, 2=green, 4=yellow, 8=red
	if (viewOnly && (PLAYER != nullptr ? PLAYER->guiScreen() : OOGUIScreenID{}) != GUI_SCREEN_MAIN)
	{
		return;
	}

	// check association with hidden dials
	if (hasHidden(OptionalStringIn(info, DIAL_REQUIRED_KEY)))
	{
		return;
	}

	OOTextureSprite				*legendSprite = nullptr;	// the sprite the legend's widget holds
	std::optional<std::string>	legendText;
	float						x, y;
	NSSize						size;
	GLfloat						alpha = overallAlpha;
	struct CachedInfo			cached;
	
	GetCurrentCachedInfo(&cached);
	
	// if either x or y is missing, use 0 instead
	
	x = useDefined(cached.x, 0.0f) + (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr ? UNIVERSE->getGameView()->getX_offset() : 0.0f) * cached.x0;
	y = useDefined(cached.y, 0.0f) + (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr ? UNIVERSE->getGameView()->getY_offset() : 0.0f) * cached.y0;
	alpha *= cached.alpha;
	
	legendSprite = sCurrentDrawItem->sprite.get();
	if (legendSprite != nullptr)
	{
		legendSprite->blitCentredToX(x, y, z1, alpha);
	}
	else
	{
		legendText = OptionalStringIn(info, TEXT_KEY);
		if (legendText.has_value())
		{
			// randomly chosen default width & height
			size.width = useDefined(cached.width, 14.0f);
			size.height = useDefined(cached.height, 8.0f);
			SET_COLOR(green_color);
			if (info.get<int>("align") == 1)
			{
				cxx_OODrawStringAligned(*legendText, x, y, z1, size, YES);
			}
			else
			{
				cxx_OODrawStringAligned(*legendText, x, y, z1, size, NO);
			}
		}
	}
}


void HeadUpDisplay::drawHUDItem(const oo::PList &info)
{
	std::optional<std::string>	equipment = OptionalStringIn(info, EQUIPMENT_REQUIRED_KEY);

	if (equipment.has_value() && !(PLAYER != nullptr ? PLAYER->hasEquipmentItemProviding(*equipment) : false))
	{
		return;
	}

	// check alert condition
	NSUInteger alertMask = info.get<unsigned int>(ALERT_CONDITIONS_KEY, 15);
	// 1=docked, 2=green, 4=yellow, 8=red
	if (alertMask < 15)
	{
		OOAlertCondition alertCondition = (PLAYER != nullptr ? PLAYER->getAlertCondition() : OOAlertCondition{});
		if (~alertMask & (1 << alertCondition)) {
			return;
		}
	}

	BOOL viewOnly = info.get<bool>(VIEWSCREEN_KEY, NO);

	// 1=docked, 2=green, 4=yellow, 8=red
	if (viewOnly && (PLAYER != nullptr ? PLAYER->guiScreen() : OOGUIScreenID{}) != GUI_SCREEN_MAIN)
	{
		return;
	}

	if (EXPECT_NOT(hasHidden(sCurrentDrawItem->selectorString)))
	{
		return;
	}

	// use the dial stored during init; the dial is called by name with its configuration
	// (ADR-0055 item 5), through the dial table since bead oo-mwd58.
	(this->*(sCurrentDrawItem->dial))(sCurrentDrawItem->info);
	cxx_OOCheckOpenGLErrors([&]() -> std::string { return "HeadUpDisplay after drawHUDItem " + oo::DescriptionOf(sCurrentDrawItem->info); });
	
	OOVerifyOpenGLState();
}


void HeadUpDisplay::drawSurroundInternal(const oo::PList & /*info*/, const GLfloat color[4])	// the geometry is the current item's cached info
{
	NSInteger			x, y;
	NSSize				siz;
	GLfloat				alpha = overallAlpha;
	struct CachedInfo	cached;
	
	GetCurrentCachedInfo(&cached);
	
	if (cached.x == NOT_DEFINED || cached.y == NOT_DEFINED || cached.width == NOT_DEFINED || cached.height == NOT_DEFINED)
	{
		return;
	}
		
	x = cached.x + (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr ? UNIVERSE->getGameView()->getX_offset() : 0.0f) * cached.x0;
	y = cached.y + (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr ? UNIVERSE->getGameView()->getY_offset() : 0.0f) * cached.y0;
	siz.width = useDefined(cached.width, WEAPONSOFFLINETEXT_WIDTH);
	siz.height = useDefined(cached.height, WEAPONSOFFLINETEXT_HEIGHT);
	alpha *= cached.alpha;
	
	// draw the surround
	GLColorWithOverallAlpha(color, alpha);
	hudDrawSurroundAt(x, y, z1, siz);
}


void HeadUpDisplay::drawSurround(const oo::PList &info)
{
	GLfloat	itemColor[4] = { 0.0f, 1.0f, 0.0f, 1.0f };
	oo::PList	colorDesc = PListForKeyIn(info, COLOR_KEY);
	if (!colorDesc.isNull())
	{
		oo::Ref<OOColor> color = OOColor::colorWithDescription(colorDesc);
		if (color != nullptr)
		{
			itemColor[0] = color->redComponent();
			itemColor[1] = color->greenComponent();
			itemColor[2] = color->blueComponent();
		}
	}

	drawSurroundInternal(info, itemColor);
}


void HeadUpDisplay::drawGreenSurround(const oo::PList &info)
{
	drawSurroundInternal(info, green_color);
}


void HeadUpDisplay::drawYellowSurround(const oo::PList &info)
{
	drawSurroundInternal(info, yellow_color);
}


void HeadUpDisplay::drawMultiFunctionDisplay(const oo::PList &info, const std::string &text, NSUInteger index)
{
	::PlayerEntity		*player1 = PLAYER;
	struct CachedInfo	cached;
	NSInteger			i, x, y;
	NSSize				siz, tmpsiz;
	if ((player1 != nullptr ? player1->guiScreen() : OOGUIScreenID{}) != GUI_SCREEN_MAIN)	// don't draw on text screens
	{
		return;
	}
	GLfloat alpha = info.get<oo::NonNegative<float>>(ALPHA_KEY, 1.0f) * overallAlpha;
	
	GLfloat mfd_color[4] =		{0.0, 1.0, 0.0, (GLfloat)(0.9*alpha)};
	oo::Ref<OOColor> mfdcol = OOColor::colorWithDescription(PListForKeyIn(info, COLOR_KEY));
	if (mfdcol != nullptr) 
	{
		mfdcol->getRed(&mfd_color[0], &mfd_color[1], &mfd_color[2], &mfd_color[3]);
	}
	if (index != (player1 != nullptr ? player1->getActiveMFD() : 0))
	{
		mfd_color[3] *= 0.75;
	}
	drawSurroundInternal(info, mfd_color);

	GetCurrentCachedInfo(&cached);
	x = cached.x + (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr ? UNIVERSE->getGameView()->getX_offset() : 0.0f) * cached.x0;
	y = cached.y + (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr ? UNIVERSE->getGameView()->getY_offset() : 0.0f) * cached.y0;
	
	siz.width = useDefined(cached.width / 15, MFD_TEXT_WIDTH);
	siz.height = useDefined(cached.height / 10, MFD_TEXT_HEIGHT);

	GLfloat x0 = (GLfloat)(x - cached.width/2);
	GLfloat y0 = (GLfloat)(y + cached.height/2);
	GLfloat x1 = (GLfloat)(x + cached.width/2);
	GLfloat y1 = (GLfloat)(y - cached.height/2);
	GLColorWithOverallAlpha(mfd_color, alpha*0.3);
	OOGLBEGIN(GL_QUADS);
		glVertex3f(x0-2,y0+2,z1);
		glVertex3f(x0-2,y1-2,z1);
		glVertex3f(x1+2,y1-2,z1);
		glVertex3f(x1+2,y0+2,z1);
	OOGLEND();

	const std::vector<std::string> lines = oo::str::split(text, "\n");
	// text at full opacity
	GLColorWithOverallAlpha(mfd_color, alpha);
	for (i = 0; i < 10 ; i++)
	{
		if ((std::size_t)i < lines.size())
		{
			const std::string &line = lines[i];
			y0 -= siz.height;
			// all lines should be shorter than the size of the MFD
			GLfloat textwidth = cxx_OORectFromString(line, 0.0f, 0.0f, siz).size.width;
			if (textwidth <= cached.width)
			{
				cxx_OODrawString(line, x0, y0, z1, siz);
			}
			else
			{
				// compress it so it fits
				tmpsiz.height = siz.height;
				tmpsiz.width = siz.width * cached.width / textwidth;
				cxx_OODrawString(line, x0, y0, z1, tmpsiz);
			}
		}
		else
		{
			break;
		}
	}
}


//---------------------------------------------------------------------//

void HeadUpDisplay::drawScanner(const oo::PList &info)
{
	int				i, x, y;
	NSSize			siz;
	GLfloat			scanner_color[4] = { 1.0, 0.0, 0.0, 1.0 };
	
	BOOL			emptyDial = (info.get<float>(ALPHA_KEY) == 0.0f);
		
	BOOL			isHostile = NO;

 	BOOL			inColorBlindMode = (UNIVERSE != nullptr ? UNIVERSE->colorblindMode() : 0) != OO_POSTFX_NONE;
	
	if (emptyDial)
	{
		// we can skip a lot of code.
		x = y = 0;
		scanner_color[3] = 0.0;			// nothing to see!
		siz = NSMakeSize(1.0, 1.0);		// avoid divide by 0s
	}
	else
	{
		struct CachedInfo	cached;
	
		GetCurrentCachedInfo(&cached);
		
		x = useDefined(cached.x, SCANNER_CENTRE_X) + (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr ? UNIVERSE->getGameView()->getX_offset() : 0.0f) * cached.x0;
		y = useDefined(cached.y, SCANNER_CENTRE_Y) + (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr ? UNIVERSE->getGameView()->getY_offset() : 0.0f) * cached.y0;
		siz.width = useDefined(cached.width, SCANNER_WIDTH);
		siz.height = useDefined(cached.height, SCANNER_HEIGHT);

		GetRGBAArrayFromInfo(info, scanner_color);
		
		scanner_color[3] *= overallAlpha;
	}
	
	GLfloat			alpha = scanner_color[3];
	GLfloat			col[4] = { 1.0, 1.0, 1.0, alpha };	// temporary colour variable
	
	GLfloat			z_factor = siz.height / siz.width;	// approx 1/4
	GLfloat			y_factor = 1.0 - sqrt(z_factor);	// approx 1/2
	
	int				scanner_cx = x;
	int				scanner_cy = y;
	
	int				scannerFootprint = SCANNER_MAX_RANGE * 2.5 / siz.width;
	
	GLfloat			zoom = scanner_zoom;
	if (scanner_ultra_zoom)
		zoom = pow(2, zoom - 1.0);
	GLfloat			max_zoomed_range2 = SCANNER_SCALE * SCANNER_SCALE * 10000.0;
	if (!nonlinear_scanner)
	{
		max_zoomed_range2 /= zoom * zoom;
	}
	GLfloat			max_zoomed_range = sqrt(max_zoomed_range2);
	
	if (PLAYER == nil)  return;
	
	OOMatrix		rotMatrix = (PLAYER != nullptr ? PLAYER->rotationMatrix() : OOMatrix{});
	Vector			relativePosition;
	int				flash = ((int)((UNIVERSE != nullptr ? UNIVERSE->getTime() : 0.0) * 4))&1;
	
	// use a non-mutable copy so this can't be changed under us.
	int				ent_count		= UNIVERSE->n_entities;
	Entity			**uni_entities	= UNIVERSE->sortedEntities;	// grab the public sorted list
	std::vector<Entity *>	my_entities(ent_count);	// the C++ entities, their objects retained (bead oo-9ht.39.27)
	Entity			*scannedEntity = nullptr;
	
	for (i = 0; i < ent_count; i++)
	{
		my_entities[i] = oo::RetainEntity(uni_entities[i]);	// retained
	}
	
	if (!emptyDial)
	{
		OOGL(glColor4fv(scanner_color));
		drawScannerGrid(x, y, z1, siz, (UNIVERSE != nullptr ? UNIVERSE->getViewDirection() : OOViewID{}), lineWidth, zoom, nonlinear_scanner, minimalistic_scanner);
	}
	
	if (checkPlayerInFlight())
	{
		GLfloat upscale = zoom * 1.25 / scannerFootprint;
		GLfloat max_blip = 0.0;
		int drawClass;
		
		OOVerifyOpenGLState();
		
		// Debugging code for nonlinear scanner - draws three fake cascade weapons, which looks pretty and enables me
		// to debug the code without the mass slaughter of innocent civillians.
		//if (nonlinear_scanner)
		//{
		//	Vector p = OOVectorMultiplyMatrix(make_vector(10000.0, 0.0, 0.0), rotMatrix);
		//	GLDrawNonlinearCascadeWeapon( scanner_cx, scanner_cy, z1, siz, p, 5000, zoom, alpha );
		//	p = OOVectorMultiplyMatrix(make_vector(10000.0, 4500.0, 0.0), rotMatrix);
		//	GLDrawNonlinearCascadeWeapon( scanner_cx, scanner_cy, z1, siz, p, 2000, zoom, alpha );
		//	p = OOVectorMultiplyMatrix(make_vector(0.0, 0.0, 20000.0), rotMatrix);
		//	GLDrawNonlinearCascadeWeapon( scanner_cx, scanner_cy, z1, siz, p, 6000, zoom, alpha );
		//}
		for (i = 0; i < ent_count; i++)  // scanner lollypops
		{
			scannedEntity = my_entities[i];
			
			drawClass = scannedEntity->getScanClass();
			
			// cloaked ships - and your own one - don't show up on the scanner.
			if (EXPECT_NOT(drawClass == CLASS_PLAYER || (oo::EntityIsShip(scannedEntity) && (oo::ToShip(scannedEntity) != nullptr ? oo::ToShip(scannedEntity)->isCloaked() : false))))
			{
				drawClass = CLASS_NO_DRAW;
			}
			
			if (drawClass != CLASS_NO_DRAW)
			{
				GLfloat x1,y1,y2;
				float	ms_blip = 0.0;
				
				if (emptyDial)  continue;
				
				if (isnan(scannedEntity->zero_distance))
					continue;
				
				// exit if it's too far away
				GLfloat	act_dist = sqrt(scannedEntity->zero_distance);
				GLfloat	lim_dist = act_dist - scannedEntity->collision_radius;
				
				// for efficiency, assume no scannable entity > 10km radius
				if (act_dist > max_zoomed_range + 10000.0)
					break;

				if (lim_dist > max_zoomed_range)
					continue;
				
				// has it sent a recent message
				//
				if (oo::EntityIsShip(scannedEntity)) 
					ms_blip = 2.0 * (oo::ToShip(scannedEntity) != nullptr ? oo::ToShip(scannedEntity)->getMessageTime() : 0.0);
				if (ms_blip > max_blip)
				{
					max_blip = ms_blip;
					last_transmitter = scannedEntity->getUniversalID();
				}
				ms_blip -= floor(ms_blip);
				
				relativePosition = (PLAYER != nullptr ? PLAYER->vectorTo(scannedEntity) : Vector{});
				double fuzz = (PLAYER != nullptr ? PLAYER->scannerFuzziness() : 0.0);
				if (fuzz > 0 && !(UNIVERSE != nullptr && UNIVERSE->gameController() != nullptr ? UNIVERSE->gameController()->isGamePaused() : false))
				{
					relativePosition = vector_add(relativePosition,OOVectorRandomRadial(fuzz));
				}

				Vector rp = relativePosition;
				
				if (act_dist > max_zoomed_range)
					scale_vector(&relativePosition, max_zoomed_range / act_dist);
				
				// rotate the view
				relativePosition = OOVectorMultiplyMatrix(relativePosition, rotMatrix);
				Vector rrp = relativePosition;
				// scale the view
				if (nonlinear_scanner)
				{
					relativePosition = nonlinearScannerScale(relativePosition, zoom, 0.5*siz.width);
				}
				else
				{
					scale_vector(&relativePosition, upscale);
				}
				
				x1 = relativePosition.x;
				y1 = z_factor * relativePosition.z;
				y2 = y1 + y_factor * relativePosition.y;
				
				isHostile = NO;
				if (oo::EntityIsShip(scannedEntity))
				{
					::ShipEntity *ship = oo::ToShip(scannedEntity);
					isHostile = (((ship != nullptr ? ship->hasHostileTarget() : false))&&((ship != nullptr ? ship->primaryTarget() : (Entity *)nullptr) == PLAYER));
					GLfloat *base_col = (ship != nullptr ? ship->scannerDisplayColorForShip(PLAYER, isHostile, flash, (ship != nullptr ? ship->scannerDisplayColor1() : (OOColor *)nullptr), (ship != nullptr ? ship->scannerDisplayColor2() : (OOColor *)nullptr), (ship != nullptr ? ship->scannerDisplayColorHostile1() : (OOColor *)nullptr), (ship != nullptr ? ship->scannerDisplayColorHostile2() : (OOColor *)nullptr)) : (GLfloat *)nullptr);
					col[0] = base_col[0];	col[1] = base_col[1];	col[2] = base_col[2];	col[3] = alpha * base_col[3];
				}
				else if (scannedEntity->getIsVisualEffect())
				{
					OOVisualEffectEntity *vis = oo::ToEffect(scannedEntity);	// C++ since bead oo-9ht.165
					GLfloat* base_col = (vis != nullptr ? vis->scannerDisplayColorForShip(flash, vis->scannerDisplayColor1(), vis->scannerDisplayColor2()) : (GLfloat *)nullptr);
					col[0] = base_col[0];	col[1] = base_col[1];	col[2] = base_col[2];	col[3] = alpha * base_col[3];
				}

				if (scannedEntity->getIsWormhole())
				{
					col[0] = blue_color[0];	col[1] = (flash)? 1.0 : blue_color[1];	col[2] = blue_color[2];	col[3] = alpha * blue_color[3];
				}
				
				// position the scanner
				x1 += scanner_cx;   y1 += scanner_cy;   y2 += scanner_cy;

				if (oo::EntityIsShip(scannedEntity))
				{
					::ShipEntity* ship = oo::ToShip(scannedEntity);
					if ((!nonlinear_scanner && ship->collision_radius * upscale > 4.5) ||
						(nonlinear_scanner && nonlinearScannerFunc(act_dist, zoom, siz.width) - nonlinearScannerFunc(lim_dist, zoom, siz.width) > 4.5 ))
					{
						Vector bounds[6];
						BoundingBox bb = ship->totalBoundingBox;
						bounds[0] = ship->v_forward;	scale_vector(&bounds[0], bb.max.z);
						bounds[1] = ship->v_forward;	scale_vector(&bounds[1], bb.min.z);
						bounds[2] = ship->v_right;		scale_vector(&bounds[2], bb.max.x);
						bounds[3] = ship->v_right;		scale_vector(&bounds[3], bb.min.x);
						bounds[4] = ship->v_up;			scale_vector(&bounds[4], bb.max.y);
						bounds[5] = ship->v_up;			scale_vector(&bounds[5], bb.min.y);
						// rotate the view
						int i;
						for (i = 0; i < 6; i++)
						{
							bounds[i] = OOVectorMultiplyMatrix(vector_add(bounds[i], rp), rotMatrix);
							if (nonlinear_scanner)
							{
								bounds[i] = nonlinearScannerScale(bounds[i], zoom, 0.5*siz.width);
							}
							else
							{
								scale_vector(&bounds[i], upscale);
							}
							bounds[i] = make_vector(bounds[i].x + scanner_cx, bounds[i].z * z_factor + bounds[i].y * y_factor + scanner_cy, z1 );
						}
						// draw the diamond
						//
						OOGLBEGIN(GL_QUADS);
							glColor4f(col[0], col[1], col[2], 0.33333 * col[3]);
							glVertex3f(bounds[0].x, bounds[0].y, bounds[0].z);	glVertex3f(bounds[4].x, bounds[4].y, bounds[4].z);
							glVertex3f(bounds[1].x, bounds[1].y, bounds[1].z);	glVertex3f(bounds[5].x, bounds[5].y, bounds[5].z);
							glVertex3f(bounds[2].x, bounds[2].y, bounds[2].z);	glVertex3f(bounds[4].x, bounds[4].y, bounds[4].z);
							glVertex3f(bounds[3].x, bounds[3].y, bounds[3].z);	glVertex3f(bounds[5].x, bounds[5].y, bounds[5].z);
							glVertex3f(bounds[2].x, bounds[2].y, bounds[2].z);	glVertex3f(bounds[0].x, bounds[0].y, bounds[0].z);
							glVertex3f(bounds[3].x, bounds[3].y, bounds[3].z);	glVertex3f(bounds[1].x, bounds[1].y, bounds[1].z);
						OOGLEND();
					}
				}
				
				if (ms_blip > 0.0)
				{
					DrawSpecialOval(x1 - 0.5, y2 + 1.5, z1, NSMakeSize(16.0 * (1.0 - ms_blip), 8.0 * (1.0 - ms_blip)), 30, col);
				}
				if (OOEntityIsCascadeWeapon(scannedEntity))
				{
					if (nonlinear_scanner)
					{
						GLDrawNonlinearCascadeWeapon( scanner_cx, scanner_cy, z1, siz, rrp, scannedEntity->collision_radius, zoom, alpha );
					}
					else
					{
						GLfloat r1 = 2.5 + scannedEntity->collision_radius * upscale;
						GLfloat l2 = r1 * r1 - relativePosition.y * relativePosition.y;
						GLfloat r0 = (l2 > 0)? sqrt(l2): 0;
						if (r0 > 0)
						{
							OOGL(glColor4f(1.0, 0.5, 1.0, alpha));
							GLDrawOval(x1  - 0.5, y1 + 1.5, z1, NSMakeSize(r0, r0 * siz.height / siz.width), 20);
						}
						OOGL(glColor4f(0.5, 0.0, 1.0, 0.33333 * alpha));
						GLDrawFilledOval(x1  - 0.5, y2 + 1.5, z1, NSMakeSize(r1, r1), 15);
					}
				}
				else
				{

#if IDENTIFY_SCANNER_LOLLIPOPS
					if (oo::EntityIsShip(scannedEntity))
					{
						glColor4f(1.0, 1.0, 0.5, alpha);
						cxx_OODrawString([oo::ToShip(scannedEntity) displayName].value_or(""), x1 + 2, y2 + 2, z1, NSMakeSize(8, 8));
					}
#endif
					glColor4fv(col);
					if (inColorBlindMode && isHostile)
					{
						// in colorblind mode turn hostile blips into X shapes for easier recognition
						OOGLBEGIN(GL_LINES);
						glVertex3f(x1+2, y2+3, z1);	glVertex3f(x1-3, y2, z1);	glVertex3f(x1+2, y2, z1);	glVertex3f(x1-3, y2+3, z1);
						OOGLEND();
					}
					else
					{
						OOGLBEGIN(GL_QUADS);
						glVertex3f(x1-3, y2, z1);	glVertex3f(x1+2, y2, z1);	glVertex3f(x1+2, y2+3, z1);	glVertex3f(x1-3, y2+3, z1);	
						OOGLEND();
					}
					OOGLBEGIN(GL_QUADS); // lollipop tail
						col[3] *= 0.3333; // one third the alpha
						glColor4fv(col);
						glVertex3f(x1, y1, z1);	glVertex3f(x1+2, y1, z1);	glVertex3f(x1+2, y2, z1);	glVertex3f(x1, y2, z1);
					OOGLEND();
				}
			}
		}
		
	}
	
	for (i = 0; i < ent_count; i++)
	{
		oo::ReleaseEntity(my_entities[i]);	//	released
	}
	
	OOVerifyOpenGLState();
	
}


void HeadUpDisplay::drawScannerZoomIndicator(const oo::PList &info)
{
	int					x, y;
	NSSize				siz;
	GLfloat				alpha;
	GLfloat				zoom_color[4] = { 1.0f, 0.1f, 0.0f, 1.0f };
	struct CachedInfo	cached;
	
	GetCurrentCachedInfo(&cached);
	
	x = useDefined(cached.x, ZOOM_INDICATOR_CENTRE_X) + (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr ? UNIVERSE->getGameView()->getX_offset() : 0.0f) * cached.x0;
	y = useDefined(cached.y, ZOOM_INDICATOR_CENTRE_Y) + (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr ? UNIVERSE->getGameView()->getY_offset() : 0.0f) * cached.y0;
	siz.width = useDefined(cached.width, ZOOM_INDICATOR_WIDTH);
	siz.height = useDefined(cached.height, ZOOM_INDICATOR_HEIGHT);
	
	GetRGBAArrayFromInfo(info, zoom_color);
	zoom_color[3] *= overallAlpha;
	alpha = zoom_color[3];
	
	GLfloat cx = x - 0.3 * siz.width;
	GLfloat cy = y - 0.75 * siz.height;
	
	int zoomLevel = scanner_zoom;	// was zl, which reads as the member z1 (clang-tidy misc-confusable-identifiers)
	if (zoomLevel < 1) zoomLevel = 1;
	if (zoomLevel > SCANNER_ZOOM_LEVELS) zoomLevel = SCANNER_ZOOM_LEVELS;
	if (zoomLevel == 1) zoom_color[3] *= 0.75;
	if (scanner_ultra_zoom)
		zoomLevel = pow(2, zoomLevel - 1);
	GLColorWithOverallAlpha(zoom_color, alpha);
	OOGL(glEnable(GL_TEXTURE_2D));
	if (sFontTexture != nullptr)  sFontTexture->apply();	// a message to nil did nothing
	
	OOGLBEGIN(GL_QUADS);
		if (zoomLevel / 10 > 0)
			drawCharacterQuad(48 + zoomLevel / 10, cx - 0.8 * siz.width, cy, z1, siz);
		drawCharacterQuad(48 + zoomLevel % 10, cx - 0.4 * siz.width, cy, z1, siz);
		drawCharacterQuad(58, cx, cy, z1, siz);
		drawCharacterQuad(49, cx + 0.3 * siz.width, cy, z1, siz);
	OOGLEND();
	
	OOTexture::applyNone();
	OOGL(glDisable(GL_TEXTURE_2D));
}


void HeadUpDisplay::drawCompass(const oo::PList &info)
{
	int					x, y;
	NSSize				siz;
	GLfloat				alpha;
	GLfloat				compass_color[4] = { 0.0f, 0.0f, 1.0f, 1.0f };
	struct CachedInfo	cached;
	
	GetCurrentCachedInfo(&cached);
	
	x = useDefined(cached.x, COMPASS_CENTRE_X) + (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr ? UNIVERSE->getGameView()->getX_offset() : 0.0f) * cached.x0;
	y = useDefined(cached.y, COMPASS_CENTRE_Y) + (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr ? UNIVERSE->getGameView()->getY_offset() : 0.0f) * cached.y0;
	siz.width = useDefined(cached.width, COMPASS_HALF_SIZE);
	siz.height = useDefined(cached.height, COMPASS_HALF_SIZE);
	
	GetRGBAArrayFromInfo(info, compass_color);
	compass_color[3] *= overallAlpha;
	alpha = compass_color[3];
	
	// draw the compass
	OOMatrix		rotMatrix = (PLAYER != nullptr ? PLAYER->rotationMatrix() : OOMatrix{});
	
	GLfloat h1 = siz.height * 0.125;
	GLfloat h3 = siz.height * 0.375;
	GLfloat w1 = siz.width * 0.125;
	GLfloat w3 = siz.width * 0.375;
	OOGL(GLScaledLineWidth(2.0 * lineWidth));	// thicker
	OOGL(glColor4f(compass_color[0], compass_color[1], compass_color[2], alpha));
	GLDrawOval(x, y, z1, siz, 12);	
	OOGL(glColor4f(compass_color[0], compass_color[1], compass_color[2], 0.5f * alpha));
	OOGLBEGIN(GL_LINES);
		glVertex3f(x - w1, y, z1);	glVertex3f(x - w3, y, z1);
		glVertex3f(x + w1, y, z1);	glVertex3f(x + w3, y, z1);
		glVertex3f(x, y - h1, z1);	glVertex3f(x, y - h3, z1);
		glVertex3f(x, y + h1, z1);	glVertex3f(x, y + h3, z1);
	OOGLEND();
	OOGL(GLScaledLineWidth(lineWidth));	// thinner
	
	if (checkPlayerInSystemFlight() && (PLAYER != nullptr ? PLAYER->status() : OOEntityStatus{}) != STATUS_LAUNCHING) // normal system
	{
		Entity *reference = (PLAYER != nullptr ? PLAYER->getCompassTargetEntity() : (Entity *)nullptr);	// the C++ entity (bead oo-9ht.39.27)
		
		// translate and rotate the view

		Vector relativePosition = (PLAYER != nullptr ? PLAYER->vectorTo(reference) : Vector{});
		relativePosition = OOVectorMultiplyMatrix(relativePosition, rotMatrix);
		relativePosition = vector_normal_or_fallback(relativePosition, kBasisZVector);
		
		relativePosition.x *= siz.width * 0.4;
		relativePosition.y *= siz.height * 0.4;
		relativePosition.x += x;
		relativePosition.y += y;
		
		siz.width *= 0.2;
		siz.height *= 0.2;
		OOGL(GLScaledLineWidth(2.0*lineWidth));
		switch ((PLAYER != nullptr ? PLAYER->getCompassMode() : OOCompassMode{}))
		{
			case COMPASS_MODE_INACTIVE:
				break;
			
			case COMPASS_MODE_BASIC:
				if (reference != nullptr && reference->getIsStation()) // validateCompassTarget in PlayerEntity.m changes COMPASS_BASIC_MODE target to the main station when inside the planetary aegis or in docking range of the main station
					drawCompassStationBlipAt(relativePosition, siz, alpha);
				else
					drawCompassPlanetBlipAt(relativePosition, siz, alpha);
				break;
				
			case COMPASS_MODE_PLANET:
				drawCompassPlanetBlipAt(relativePosition, siz, alpha);
				break;
				
			case COMPASS_MODE_STATION:
				drawCompassStationBlipAt(relativePosition, siz, alpha);
				break;
				
			case COMPASS_MODE_SUN:
				drawCompassSunBlipAt(relativePosition, siz, alpha);
				break;
				
			case COMPASS_MODE_TARGET:
				drawCompassTargetBlipAt(relativePosition, siz, alpha);
				break;
				
			case COMPASS_MODE_BEACONS:
				drawCompassBeaconBlipAt(relativePosition, siz, alpha);
				Entity		*beacon = (PLAYER != nullptr ? PLAYER->nextBeacon() : nullptr);
				OOHUDBeaconIcon	*beaconIcon = oo::BeaconDrawable(beacon);	// nil beacon or drawable: nothing, as the message to nil (bead oo-w9pi2)
				if (beaconIcon != nullptr)  beaconIcon->drawHUDBeaconIconAt(NSMakePoint(x, y), siz, alpha, z1);
				break;
		}
		OOGL(GLScaledLineWidth(lineWidth));	// reset

		_compassUpdated = YES;
		_compassActive = YES;
	}
}


void HeadUpDisplay::drawAegis(const oo::PList & /*info*/)	// the geometry is the current item's cached info
{
	if (((UNIVERSE != nullptr ? UNIVERSE->getViewDirection() : OOViewID{}) == VIEW_GUI_DISPLAY)||((UNIVERSE != nullptr ? UNIVERSE->sun() : nullptr) == nil)||((PLAYER != nullptr ? PLAYER->checkForAegis() : OOAegisStatus{}) != AEGIS_IN_DOCKING_RANGE))
		return;	// don't draw
	
	int					x, y;
	NSSize				siz;
	GLfloat				alpha = 0.5f * overallAlpha;
	struct CachedInfo	cached;
	
	GetCurrentCachedInfo(&cached);
	
	x = useDefined(cached.x, AEGIS_CENTRE_X) + (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr ? UNIVERSE->getGameView()->getX_offset() : 0.0f) * cached.x0;
	y = useDefined(cached.y, AEGIS_CENTRE_Y) + (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr ? UNIVERSE->getGameView()->getY_offset() : 0.0f) * cached.y0;
	siz.width = useDefined(cached.width, AEGIS_WIDTH);
	siz.height = useDefined(cached.height, AEGIS_HEIGHT);
	alpha *= cached.alpha;
	
	// draw the aegis indicator
	//
	GLfloat	w = siz.width / 16.0;
	GLfloat	h = siz.height / 16.0;
	
	GLfloat strip[] = { -7,8, -6,5, 5,8, 3,5, 7,2, 4,2, 6,-1, 4,2, -4,-1, -6,2, -4,-1, -7,-1, -3,-4, -5,-7, 6,-4, 7,-7 };
	
#if 1
	OOGL(glColor4f(0.0f, 1.0f, 0.0f, alpha));
	OOGLBEGIN(GL_QUAD_STRIP);
		int i;
		for (i = 0; i < 32; i += 2)
		{
			glVertex3f(x + w * strip[i], y - h * strip[i + 1], z1);
		}
	OOGLEND();
#else
	OOGLPushModelView();
	OOGLTranslateModelView(make_vector(x, y, z1));
	OOGLScaleModelView(make_vector(w, -h, 1.0f));
	
	OOGL(glColor4f(0.0f, 1.0f, 0.0f, alpha));
	OOGL(glVertexPointer(2, GL_FLOAT, 0, strip));
	OOGL(glEnableClientState(GL_VERTEX_ARRAY));
	OOGL(glDisableClientState(GL_COLOR_ARRAY));
	
	OOGL(glDrawArrays(GL_QUAD_STRIP, 0, sizeof strip / sizeof *strip / 2));
	OOGL(glDisableClientState(GL_VERTEX_ARRAY));

	OOGLPopModelView();
#endif
}


void HeadUpDisplay::drawTargetReticle(const oo::PList &info)
{
	GLfloat alpha = info.get<oo::NonNegative<float>>(ALPHA_KEY, 1.0f) * overallAlpha;
	
	if ((PLAYER != nullptr ? PLAYER->primaryTarget() : (Entity *)nullptr) != nil)
	{
		hudDrawReticleOnTarget((PLAYER != nullptr ? PLAYER->primaryTarget() : (Entity *)nullptr), PLAYER, z1, alpha, reticleTargetSensitive, &propertiesReticleTargetSensitive, NO, YES, info, _reticleColors);
		drawDirectionCue(info);
	}
	// extra feature if extra equipment installed
	if ((PLAYER != nullptr ? PLAYER->hasEquipmentItemProviding("EQ_INTEGRATED_TARGETING_SYSTEM") : false))
	{
		drawSecondaryTargetReticle(info);
	}
}


void HeadUpDisplay::drawSecondaryTargetReticle(const oo::PList &info)
{
	GLfloat alpha = info.get<oo::NonNegative<float>>(ALPHA_KEY, 1.0f) * overallAlpha * 0.4;
	
	::PlayerEntity *player = PLAYER;
	if ((player != nullptr ? player->hasEquipmentItemProviding("EQ_TARGET_MEMORY") : false))
	{
		// needs target memory to be working in addition to any other equipment
		// this item may be bound to
		Entity *primary = (player != nullptr ? player->primaryTarget() : (Entity *)nullptr);	// the C++ entities: a target may be any entity (beads oo-9ht.144, oo-9ht.39.27)
		for (unsigned i = 0; i < PLAYER_TARGET_MEMORY_SIZE; i++)
		{
			const oo::WeakRef<Entity> sec_ref = (player != nullptr ? player->targetMemory() : std::vector<oo::WeakRef<Entity>>()).at(i);	// an empty slot (was OONull) is an empty ref (bead oo-9ht.39.5.2)
			// isProxy = weakref ; not = OONull (in this case...)
			// can't use isKindOfClass because that throws
			// OOInvalidArgumentException when called on a weakref
			// with a dropped object.
			// TODO: fix the weak reference proxy so isKindOfClass works (moot for oo::WeakRef)
			if (sec_ref != oo::WeakRef<Entity>())	// a weak reference (-isProxy), not an empty slot
			{
				Entity *secondary = oo::LiveEntity(sec_ref);	// +0, null once its object has gone
				if (secondary != nullptr && secondary != primary)
				{
					if (secondary->zeroDistance() <= SCANNER_MAX_RANGE2 && secondary->isInSpace())
					{
						hudDrawReticleOnTarget(secondary, PLAYER, z1, alpha, NO, nullptr, YES, NO, info, _reticleColors);	
					}			
				}
			}
		}
	}
}


void HeadUpDisplay::drawWaypoints(const oo::PList &info)
{
	GLfloat alpha = info.get<oo::NonNegative<float>>(ALPHA_KEY, 1.0f) * overallAlpha;
	GLfloat scale = info.get<float>("reticle_scale", ONE_SIXTYFOURTH);

	Entity *compass = (PLAYER != nullptr ? PLAYER->getCompassTargetEntity() : (Entity *)nullptr);
	
	for (const auto &[waypointKey, waypointRef] : (UNIVERSE != nullptr ? UNIVERSE->currentWaypoints() : std::map<std::string, oo::EntityHold, std::less<>>()))
	{
		Entity *waypoint = waypointRef.get();	// the universe holds the C++ waypoint (bead oo-9ht.39.26)
		hudDrawWaypoint(waypoint, PLAYER, z1, alpha, waypoint==compass, scale);
	}

}


void HeadUpDisplay::drawCustomBar(const oo::PList &info)
{
	int					x, y;
	NSSize				siz;
	BOOL				draw_surround;
	GLfloat				alpha = overallAlpha;
	GLfloat				ds = OOClamp_0_1_f((PLAYER != nullptr ? PLAYER->dialCustomFloat(OptionalStringIn(info, CUSTOM_DIAL_KEY).value_or("")) : 0.0f));
	struct CachedInfo	cached;
	
	GetCurrentCachedInfo(&cached);
	
	x = useDefined(cached.x, 0) + (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr ? UNIVERSE->getGameView()->getX_offset() : 0.0f) * cached.x0;
	y = useDefined(cached.y, 0) + (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr ? UNIVERSE->getGameView()->getY_offset() : 0.0f) * cached.y0;
	siz.width = useDefined(cached.width, 50);
	siz.height = useDefined(cached.height, 8);
	alpha *= cached.alpha;
	
	draw_surround = info.get<bool>(DRAW_SURROUND_KEY, NO);
	
	SET_COLOR_SURROUND(green_color);
	if (draw_surround)
	{
		// draw custom surround
		hudDrawSurroundAt(x, y, z1, siz);
	}
	// draw custom bar
	if (ds > .75)
	{
		SET_COLOR_HIGH(green_color);
	}
	else if (ds > .25)
	{
		SET_COLOR_MEDIUM(yellow_color);
	}
	else
	{
		SET_COLOR_LOW(red_color);
	}

	hudDrawBarAt(x, y, z1, siz, ds);
}


void HeadUpDisplay::drawCustomText(const oo::PList &info)
{
	int					x, y;
	NSSize				size;
	GLfloat				alpha = overallAlpha;
	std::string			text = (PLAYER != nullptr ? PLAYER->dialCustomString(OptionalStringIn(info, CUSTOM_DIAL_KEY).value_or("")) : std::string());	// nil drew nothing, as "" does
	struct CachedInfo	cached;
	
	GetCurrentCachedInfo(&cached);
	
	x = useDefined(cached.x, 0) + (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr ? UNIVERSE->getGameView()->getX_offset() : 0.0f) * cached.x0;
	y = useDefined(cached.y, 0) + (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr ? UNIVERSE->getGameView()->getY_offset() : 0.0f) * cached.y0;
	alpha *= cached.alpha;
	
	SET_COLOR(yellow_color);

	size.width = useDefined(cached.width, 10.0f);
	size.height = useDefined(cached.height, 10.0f);

	if (info.get<int>("align") == 1)
	{
		cxx_OODrawStringAligned(text, x, y, z1, size, YES);
	}
	else
	{
		cxx_OODrawStringAligned(text, x, y, z1, size, NO);
	}

}


void HeadUpDisplay::drawCustomIndicator(const oo::PList &info)
{
	int					x, y;
	NSSize				siz;
	BOOL				draw_surround;
	GLfloat				alpha = overallAlpha;
	GLfloat				iv = OOClamp_n1_1_f((PLAYER != nullptr ? PLAYER->dialCustomFloat(OptionalStringIn(info, CUSTOM_DIAL_KEY).value_or("")) : 0.0f));

	struct CachedInfo	cached;
	
	GetCurrentCachedInfo(&cached);
	
	x = useDefined(cached.x, 0) + (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr ? UNIVERSE->getGameView()->getX_offset() : 0.0f) * cached.x0;
	y = useDefined(cached.y, 0) + (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr ? UNIVERSE->getGameView()->getY_offset() : 0.0f) * cached.y0;
	siz.width = useDefined(cached.width, 50);
	siz.height = useDefined(cached.height, 8);
	alpha *= cached.alpha;
	draw_surround = info.get<bool>(DRAW_SURROUND_KEY, NO);
	
	if (draw_surround)
	{
		// draw custom surround
		SET_COLOR_SURROUND(green_color);
		hudDrawSurroundAt(x, y, z1, siz);
	}
	// draw custom indicator
	SET_COLOR(yellow_color);
	hudDrawIndicatorAt(x, y, z1, siz, iv);
}


void HeadUpDisplay::drawCustomLight(const oo::PList &info)
{
	int					x, y;
	NSSize				siz;
	GLfloat				alpha = overallAlpha;

	struct CachedInfo	cached;
	
	GetCurrentCachedInfo(&cached);
	
	x = useDefined(cached.x, 0) + (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr ? UNIVERSE->getGameView()->getX_offset() : 0.0f) * cached.x0;
	y = useDefined(cached.y, 0) + (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr ? UNIVERSE->getGameView()->getY_offset() : 0.0f) * cached.y0;
	siz.width = useDefined(cached.width, 8);
	siz.height = useDefined(cached.height, 8);
	alpha *= cached.alpha;
	
	GLfloat light_color[4] = { 0.25, 0.25, 0.25, 0.0};
	
	oo::Ref<OOColor> color = (PLAYER != nullptr ? PLAYER->dialCustomColor(OptionalStringIn(info, CUSTOM_DIAL_KEY).value_or("")) : oo::Ref<OOColor>());
	if (color != nullptr)	// a message to nil left the colour as it was
	{
		color->getRed(&light_color[0],
								 &light_color[1],
								 &light_color[2],
								 &light_color[3]);
	}

	GLColorWithOverallAlpha(light_color, alpha);
	OOGLBEGIN(GL_POLYGON);
	hudDrawStatusIconAt(x, y, z1, siz);
	OOGLEND();
	OOGL(glColor4f(0.25, 0.25, 0.25, alpha));
	OOGLBEGIN(GL_LINE_LOOP);
		hudDrawStatusIconAt(x, y, z1, siz);
	OOGLEND();
}


void HeadUpDisplay::drawCustomImage(const oo::PList &info)
{
	int					x, y;
	GLfloat				alpha = overallAlpha;

	struct CachedInfo	cached;
	
	GetCurrentCachedInfo(&cached);
	
	x = useDefined(cached.x, 0) + (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr ? UNIVERSE->getGameView()->getX_offset() : 0.0f) * cached.x0;
	y = useDefined(cached.y, 0) + (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr ? UNIVERSE->getGameView()->getY_offset() : 0.0f) * cached.y0;
	alpha *= cached.alpha;

	std::optional<std::string> textureFile = std::optional<std::string>((PLAYER != nullptr ? PLAYER->dialCustomString(OptionalStringIn(info, CUSTOM_DIAL_KEY).value_or("")) : std::string()));
	if (!textureFile.has_value() || textureFile->empty()) {
		return;
	}

	oo::Ref<OOTexture> texture = OOTexture::textureWithName(textureFile,
																std::string("Images"),
																kOOTextureDefaultOptions | kOOTextureNoShrink,
																kOOTextureDefaultAnisotropy,
																kOOTextureDefaultLODBias);
	if (texture == nullptr)
	{
		OO_LOG_ERR(cxx_kOOLogFileNotFound, "HeadUpDisplay couldn't get an image texture name for {}", *textureFile);
		return;
	}
		
	NSSize imageSize = texture->dimensions();
	imageSize.width = useDefined(cached.width, imageSize.width);
	imageSize.height = useDefined(cached.height, imageSize.height);

	/* There's possibly some optimisation which could be done by
	 * caching the sprite, but regenerating it each frame doesn't
	 * appear to take any significant amount of time compared with the
	 * time taken to actually render it and the texture will be
	 * returned from the cache anyway. - CIM */
	oo::Ref<OOTextureSprite> sprite = OOTextureSprite::initWithTexture(texture.get(), imageSize);

	if (sprite != nullptr)  sprite->blitCentredToX(x, y, z1, alpha);	// a message to nil did nothing

}


void HeadUpDisplay::drawSpeedBar(const oo::PList &info)
{
	int					x, y;
	NSSize				siz;
	BOOL				draw_surround;
	GLfloat				alpha = overallAlpha;
	GLfloat				ds = (PLAYER != nullptr ? PLAYER->dialSpeed() : 0.0f);
	struct CachedInfo	cached;
	
	GetCurrentCachedInfo(&cached);
	
	x = useDefined(cached.x, SPEED_BAR_CENTRE_X) + (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr ? UNIVERSE->getGameView()->getX_offset() : 0.0f) * cached.x0;
	y = useDefined(cached.y, SPEED_BAR_CENTRE_Y) + (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr ? UNIVERSE->getGameView()->getY_offset() : 0.0f) * cached.y0;
	siz.width = useDefined(cached.width, SPEED_BAR_WIDTH);
	siz.height = useDefined(cached.height, SPEED_BAR_HEIGHT);
	alpha *= cached.alpha;
	
	draw_surround = info.get<bool>(DRAW_SURROUND_KEY, SPEED_BAR_DRAW_SURROUND);
	
	
	SET_COLOR_SURROUND(green_color);
	if (draw_surround)
	{
		// draw speed surround
		hudDrawSurroundAt(x, y, z1, siz);
	}
	// draw speed bar
	if (ds > .80)
	{
		SET_COLOR_HIGH(red_color);
	}
	else if (ds > .25)
	{
		SET_COLOR_MEDIUM(yellow_color);
	}
	else
	{
		SET_COLOR_LOW(green_color);
	}

	hudDrawBarAt(x, y, z1, siz, ds);
}


void HeadUpDisplay::drawRollBar(const oo::PList &info)
{
	int					x, y;
	NSSize				siz;
	BOOL				draw_surround;
	GLfloat				alpha = overallAlpha;
	struct CachedInfo	cached;
	
	GetCurrentCachedInfo(&cached);
	
	x = useDefined(cached.x, ROLL_BAR_CENTRE_X) + (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr ? UNIVERSE->getGameView()->getX_offset() : 0.0f) * cached.x0;
	y = useDefined(cached.y, ROLL_BAR_CENTRE_Y) + (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr ? UNIVERSE->getGameView()->getY_offset() : 0.0f) * cached.y0;
	siz.width = useDefined(cached.width, ROLL_BAR_WIDTH);
	siz.height = useDefined(cached.height, ROLL_BAR_HEIGHT);
	alpha *= cached.alpha;
	draw_surround = info.get<bool>(DRAW_SURROUND_KEY, ROLL_BAR_DRAW_SURROUND);
	
	if (draw_surround)
	{
		// draw ROLL surround
		SET_COLOR_SURROUND(green_color);
		hudDrawSurroundAt(x, y, z1, siz);
	}
	// draw ROLL bar
	SET_COLOR(yellow_color);
	hudDrawIndicatorAt(x, y, z1, siz, (PLAYER != nullptr ? PLAYER->dialRoll() : 0.0f));
}


void HeadUpDisplay::drawPitchBar(const oo::PList &info)
{
	int					x, y;
	NSSize				siz;
	BOOL				draw_surround;
	GLfloat				alpha = overallAlpha;
	struct CachedInfo	cached;
	
	GetCurrentCachedInfo(&cached);
	
	x = useDefined(cached.x, PITCH_BAR_CENTRE_X) + (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr ? UNIVERSE->getGameView()->getX_offset() : 0.0f) * cached.x0;
	y = useDefined(cached.y, PITCH_BAR_CENTRE_Y) + (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr ? UNIVERSE->getGameView()->getY_offset() : 0.0f) * cached.y0;
	siz.width = useDefined(cached.width, PITCH_BAR_WIDTH);
	siz.height = useDefined(cached.height, PITCH_BAR_HEIGHT);
	alpha *= cached.alpha;
	draw_surround = info.get<bool>(DRAW_SURROUND_KEY, PITCH_BAR_DRAW_SURROUND);
	
	if (draw_surround)
	{
		// draw PITCH surround
		SET_COLOR_SURROUND(green_color);
		hudDrawSurroundAt(x, y, z1, siz);
	}
	// draw PITCH bar
	SET_COLOR(yellow_color);
	hudDrawIndicatorAt(x, y, z1, siz, (PLAYER != nullptr ? PLAYER->dialPitch() : 0.0f));
}


void HeadUpDisplay::drawYawBar(const oo::PList &info)
{
	int					x, y;
	NSSize				siz;
	BOOL				draw_surround;
	GLfloat				alpha = overallAlpha;
	struct CachedInfo	cached;
	
	GetCurrentCachedInfo(&cached);
	
	// No standard YAW definitions - using PITCH ones instead.
	x = useDefined(cached.x, PITCH_BAR_CENTRE_X) + (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr ? UNIVERSE->getGameView()->getX_offset() : 0.0f) * cached.x0;
	y = useDefined(cached.y, PITCH_BAR_CENTRE_Y) + (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr ? UNIVERSE->getGameView()->getY_offset() : 0.0f) * cached.y0;
	siz.width = useDefined(cached.width, PITCH_BAR_WIDTH);
	siz.height = useDefined(cached.height, PITCH_BAR_HEIGHT);
	alpha *= cached.alpha;
	draw_surround = info.get<bool>(DRAW_SURROUND_KEY, PITCH_BAR_DRAW_SURROUND);
	
	if (draw_surround)
	{
		// draw YAW surround
		SET_COLOR_SURROUND(green_color);
		hudDrawSurroundAt(x, y, z1, siz);
	}
	// draw YAW bar
	SET_COLOR(yellow_color);
	hudDrawIndicatorAt(x, y, z1, siz, (PLAYER != nullptr ? PLAYER->dialYaw() : 0.0f));
}


void HeadUpDisplay::drawEnergyGauge(const oo::PList &info)
{
	int					x, y;
	unsigned			i;
	NSSize				siz;
	BOOL				drawSurround, labelled, energyCritical = NO;
	GLfloat				alpha = overallAlpha;
	GLfloat				bankHeight, bankY;
	::PlayerEntity *player = PLAYER;

	unsigned n_bars = (player != nullptr ? player->dialMaxEnergy() : 0.0f)/64.0;
	n_bars = info.get<unsigned int>(N_BARS_KEY, n_bars);
	if (n_bars < 1)
	{
		n_bars = 1;
	}
	GLfloat				energy = (player != nullptr ? player->dialEnergy() : 0.0f) * n_bars;
	struct CachedInfo	cached;
	
	GetCurrentCachedInfo(&cached);
	
	x = useDefined(cached.x, ENERGY_GAUGE_CENTRE_X) + (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr ? UNIVERSE->getGameView()->getX_offset() : 0.0f) * cached.x0;
	y = useDefined(cached.y, ENERGY_GAUGE_CENTRE_Y) + (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr ? UNIVERSE->getGameView()->getY_offset() : 0.0f) * cached.y0;
	siz.width = useDefined(cached.width, ENERGY_GAUGE_WIDTH);
	siz.height = useDefined(cached.height, ENERGY_GAUGE_HEIGHT);
	alpha *= cached.alpha;
	drawSurround = info.get<bool>(DRAW_SURROUND_KEY, ENERGY_GAUGE_DRAW_SURROUND);
	labelled = info.get<bool>(LABELLED_KEY, YES);
	if (n_bars > 8)  labelled = NO;
	
	if (drawSurround)
	{
		// draw energy surround
		SET_COLOR_SURROUND(yellow_color);
		hudDrawSurroundAt(x, y, z1, siz);
	}
	
	bankHeight = siz.height / n_bars;
	// draw energy banks	
	NSSize barSize = NSMakeSize(siz.width, bankHeight - 2.0);		// leave a gap between bars
	GLfloat midBank = bankHeight / 2.0f;
	bankY = y - (n_bars - 1) * midBank - 1.0;
	
	// avoid constant colour switching...
	if (labelled)
	{
		GLColorWithOverallAlpha(green_color, alpha);
		GLfloat labelStartX = x + 0.5f * barSize.width + 3.0f;
		NSSize labelSize = NSMakeSize(9.0, (bankHeight < 18.0)? bankHeight : 18.0);
		for (i = 0; i < n_bars; i++)
		{
			cxx_OODrawString(oo::str::format("E%x", n_bars - i), labelStartX, bankY - midBank, z1, labelSize);
			bankY += bankHeight;
		}
	}
	
	if (energyCritical)
	{
		SET_COLOR_LOW(red_color);
	}
	else
	{
		SET_COLOR_MEDIUM(yellow_color);
	}
	bankY = y - (n_bars - 1) * midBank;
	for (i = 0; i < n_bars; i++)
	{
		if (energy > 1.0)
		{
			hudDrawBarAt(x, bankY, z1, barSize, 1.0);
		}
		else if (energy > 0.0)
		{
			hudDrawBarAt(x, bankY, z1, barSize, energy);
		}
		
		energy -= 1.0;
		bankY += bankHeight;
	}
}


void HeadUpDisplay::drawForwardShieldBar(const oo::PList &info)
{
	int					x, y;
	NSSize				siz;
	BOOL				draw_surround;
	GLfloat				alpha = overallAlpha;
	GLfloat				shield = (PLAYER != nullptr ? PLAYER->dialForwardShield() : 0.0f);
	struct CachedInfo	cached;
	
	GetCurrentCachedInfo(&cached);
	
	x = useDefined(cached.x, FORWARD_SHIELD_BAR_CENTRE_X) + (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr ? UNIVERSE->getGameView()->getX_offset() : 0.0f) * cached.x0;
	y = useDefined(cached.y, FORWARD_SHIELD_BAR_CENTRE_Y) + (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr ? UNIVERSE->getGameView()->getY_offset() : 0.0f) * cached.y0;
	siz.width = useDefined(cached.width, FORWARD_SHIELD_BAR_WIDTH);
	siz.height = useDefined(cached.height, FORWARD_SHIELD_BAR_HEIGHT);
	alpha *= cached.alpha;
	draw_surround = info.get<bool>(DRAW_SURROUND_KEY, FORWARD_SHIELD_BAR_DRAW_SURROUND);
	
	if (draw_surround)
	{
		// draw forward_shield surround
		SET_COLOR_SURROUND(green_color);
		hudDrawSurroundAt(x, y, z1, siz);
	}
	// draw forward_shield bar
	if (shield < .25)
	{
		SET_COLOR_LOW(red_color);
	}
	else if (shield < .80)
	{
		SET_COLOR_MEDIUM(yellow_color);
	} 
	else
	{
		SET_COLOR_HIGH(green_color);
	}
	hudDrawBarAt(x, y, z1, siz, shield);
}


void HeadUpDisplay::drawAftShieldBar(const oo::PList &info)
{
	int					x, y;
	NSSize				siz;
	BOOL				draw_surround;
	GLfloat				alpha = overallAlpha;
	GLfloat				shield = (PLAYER != nullptr ? PLAYER->dialAftShield() : 0.0f);
	struct CachedInfo	cached;
	
	GetCurrentCachedInfo(&cached);
	
	x = useDefined(cached.x, AFT_SHIELD_BAR_CENTRE_X) + (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr ? UNIVERSE->getGameView()->getX_offset() : 0.0f) * cached.x0;
	y = useDefined(cached.y, AFT_SHIELD_BAR_CENTRE_Y) + (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr ? UNIVERSE->getGameView()->getY_offset() : 0.0f) * cached.y0;
	siz.width = useDefined(cached.width, AFT_SHIELD_BAR_WIDTH);
	siz.height = useDefined(cached.height, AFT_SHIELD_BAR_HEIGHT);
	alpha *= cached.alpha;
	draw_surround = info.get<bool>(DRAW_SURROUND_KEY, AFT_SHIELD_BAR_DRAW_SURROUND);
	
	if (draw_surround)
	{
		// draw forward_shield surround
		SET_COLOR_SURROUND(green_color);
		hudDrawSurroundAt(x, y, z1, siz);
	}
	// draw forward_shield bar
	if (shield < .25)
	{
		SET_COLOR_LOW(red_color);
	}
	else if (shield < .80)
	{
		SET_COLOR_MEDIUM(yellow_color);
	} 
	else
	{
		SET_COLOR_HIGH(green_color);
	}
	hudDrawBarAt(x, y, z1, siz, shield);
}


void HeadUpDisplay::drawFuelBar(const oo::PList &info)
{
	int					x, y;
	NSSize				siz;
	BOOL				draw_surround;
	float				fu, hr;
	GLfloat				alpha = overallAlpha;
	struct CachedInfo	cached;
	
	GetCurrentCachedInfo(&cached);
	
	x = useDefined(cached.x, FUEL_BAR_CENTRE_X) + (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr ? UNIVERSE->getGameView()->getX_offset() : 0.0f) * cached.x0;
	y = useDefined(cached.y, FUEL_BAR_CENTRE_Y) + (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr ? UNIVERSE->getGameView()->getY_offset() : 0.0f) * cached.y0;
	siz.width = useDefined(cached.width, FUEL_BAR_WIDTH);
	siz.height = useDefined(cached.height, FUEL_BAR_HEIGHT);
	alpha *= cached.alpha;
	draw_surround = info.get<bool>(DRAW_SURROUND_KEY, NO);
	
	if (draw_surround)
	{
		SET_COLOR_SURROUND(green_color);
		hudDrawSurroundAt(x, y, z1, siz);
	}
	
	fu = (PLAYER != nullptr ? PLAYER->dialFuel() : 0.0f);
	hr = (PLAYER != nullptr ? PLAYER->dialHyperRange() : 0.0f);
	
	// draw fuel bar
	SET_COLOR_MEDIUM(yellow_color);
	hudDrawBarAt(x, y, z1, siz, fu);
	
	// draw range indicator
	if (hr > 0.0f && hr <= 1.0f)
	{
		if ((PLAYER != nullptr ? PLAYER->hasSufficientFuelForJump() : false))
		{
			SET_COLOR_HIGH(green_color);
		}
		else
		{
			SET_COLOR_LOW(red_color);
		}
		hudDrawMarkerAt(x, y, z1, siz, hr);
	}

}


void HeadUpDisplay::drawWitchspaceDestination(const oo::PList &info)
{
	// A zero-distance jump counts as 0.1LY
	if ((PLAYER != nullptr ? PLAYER->dialHyperRange() : 0.0f) == 0.0f)
	{
		return;
	}

	int					x, y;
	NSSize				siz;
	GLfloat				alpha = overallAlpha;

	struct CachedInfo	cached;

	GetCurrentCachedInfo(&cached);
	
	x = useDefined(cached.x, WITCHDEST_CENTRE_X) + (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr ? UNIVERSE->getGameView()->getX_offset() : 0.0f) * cached.x0;
	y = useDefined(cached.y, WITCHDEST_CENTRE_Y) + (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr ? UNIVERSE->getGameView()->getY_offset() : 0.0f) * cached.y0;
	siz.width = useDefined(cached.width, WITCHDEST_WIDTH);
	siz.height = useDefined(cached.height, WITCHDEST_HEIGHT);
	alpha *= cached.alpha;
	std::string dest = (UNIVERSE != nullptr ? UNIVERSE->getSystemName((PLAYER != nullptr ? PLAYER->targetSystemID() : 0)) : std::optional<std::string>()).value_or("");	// nil drew nothing, as "" does
	NSInteger concealment = ((UNIVERSE != nullptr ? UNIVERSE->getSystemManager() : nullptr) != nullptr ? UNIVERSE->getSystemManager()->getPropertiesForSystem((PLAYER != nullptr ? PLAYER->targetSystemID() : 0), (PLAYER != nullptr ? PLAYER->galaxyNumber() : OOGalaxyID{})) : oo::PList()).get<int>("concealment", OO_SYSTEMCONCEALMENT_NONE);
	if (concealment >= OO_SYSTEMCONCEALMENT_NONAME) dest = OO_DESC("status-unknown-system");

	SET_COLOR(green_color);
	
	if (info.get<int>("align") == 1)
	{
		cxx_OODrawStringAligned(dest, x, y, z1, siz, YES);
	}
	else
	{
		cxx_OODrawStringAligned(dest, x, y, z1, siz, NO);
	}

}


void HeadUpDisplay::drawCabinTempBar(const oo::PList &info)
{
	int					x, y;
	NSSize				siz;
	BOOL				draw_surround;
	GLfloat				temp = (PLAYER != nullptr ? PLAYER->hullHeatLevel() : 0.0f);
	GLfloat				alpha = overallAlpha;
	struct CachedInfo	cached;
	
	GetCurrentCachedInfo(&cached);
	
	x = useDefined(cached.x, CABIN_TEMP_BAR_CENTRE_X) + (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr ? UNIVERSE->getGameView()->getX_offset() : 0.0f) * cached.x0;
	y = useDefined(cached.y, CABIN_TEMP_BAR_CENTRE_Y) + (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr ? UNIVERSE->getGameView()->getY_offset() : 0.0f) * cached.y0;
	siz.width = useDefined(cached.width, CABIN_TEMP_BAR_WIDTH);
	siz.height = useDefined(cached.height, CABIN_TEMP_BAR_HEIGHT);
	alpha *= cached.alpha;
	draw_surround = info.get<bool>(DRAW_SURROUND_KEY, NO);
	
	if (draw_surround)
	{
		SET_COLOR_SURROUND(green_color);
		hudDrawSurroundAt(x, y, z1, siz);
	}
	
	int flash = (int)((UNIVERSE != nullptr ? UNIVERSE->getTime() : 0.0) * 4);
	flash &= 1;
	// what color are we?
	if (temp > .80)
	{
		if (temp > .90 && flash)
			SET_COLOR_CRITICAL(redplus_color);
		else
			SET_COLOR_HIGH(red_color);
	}
	else
	{
		if (temp > .25)
			SET_COLOR_MEDIUM(yellow_color);
		else
			SET_COLOR_LOW(green_color);
	}

	
	hudDrawBarAt(x, y, z1, siz, temp);
}


void HeadUpDisplay::drawWeaponTempBar(const oo::PList &info)
{
	int					x, y;
	NSSize				siz;
	BOOL				draw_surround;
	GLfloat				temp = (PLAYER != nullptr ? PLAYER->laserHeatLevel() : 0.0f);
	GLfloat				alpha = overallAlpha;
	struct CachedInfo	cached;
	
	GetCurrentCachedInfo(&cached);
	
	x = useDefined(cached.x, WEAPON_TEMP_BAR_CENTRE_X) + (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr ? UNIVERSE->getGameView()->getX_offset() : 0.0f) * cached.x0;
	y = useDefined(cached.y, WEAPON_TEMP_BAR_CENTRE_Y) + (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr ? UNIVERSE->getGameView()->getY_offset() : 0.0f) * cached.y0;
	siz.width = useDefined(cached.width, WEAPON_TEMP_BAR_WIDTH);
	siz.height = useDefined(cached.height, WEAPON_TEMP_BAR_HEIGHT);
	alpha *= cached.alpha;
	draw_surround = info.get<bool>(DRAW_SURROUND_KEY, NO);
	
	if (draw_surround)
	{
		SET_COLOR_SURROUND(green_color);
		hudDrawSurroundAt(x, y, z1, siz);
	}
	
	// draw weapon_temp bar (only need to call GLColor() once!)
	if (temp > .80)
		SET_COLOR_HIGH(red_color);
	else if (temp > .25)
		SET_COLOR_MEDIUM(yellow_color);
	else
		SET_COLOR_LOW(green_color);
	hudDrawBarAt(x, y, z1, siz, temp);
}


void HeadUpDisplay::drawAltitudeBar(const oo::PList &info)
{
	int					x, y;
	NSSize				siz;
	BOOL				draw_surround;
	GLfloat				alt = (PLAYER != nullptr ? PLAYER->dialAltitude() : 0.0f);
	GLfloat				alpha = overallAlpha;
	struct CachedInfo	cached;
	
	GetCurrentCachedInfo(&cached);
	
	x = useDefined(cached.x, ALTITUDE_BAR_CENTRE_X) + (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr ? UNIVERSE->getGameView()->getX_offset() : 0.0f) * cached.x0;
	y = useDefined(cached.y, ALTITUDE_BAR_CENTRE_Y) + (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr ? UNIVERSE->getGameView()->getY_offset() : 0.0f) * cached.y0;
	siz.width = useDefined(cached.width, ALTITUDE_BAR_WIDTH);
	siz.height = useDefined(cached.height, ALTITUDE_BAR_HEIGHT);
	alpha *= cached.alpha;
	draw_surround = info.get<bool>(DRAW_SURROUND_KEY, NO);
	
	if (draw_surround)
	{
		SET_COLOR_SURROUND(yellow_color);
		hudDrawSurroundAt(x, y, z1, siz);
	}
	
	int flash = (int)((UNIVERSE != nullptr ? UNIVERSE->getTime() : 0.0) * 4);
	flash &= 1;
	
	// draw altitude bar (evaluating the least amount of ifs per go)
	if (alt < .25)
	{
		if (alt < .10 && flash)
			SET_COLOR_CRITICAL(redplus_color);
		else
			SET_COLOR_HIGH(red_color);
	}
	else
	{
		if (alt < .75)
			SET_COLOR_MEDIUM(yellow_color);
		else
			SET_COLOR_LOW(green_color);
	}
	
	hudDrawBarAt(x, y, z1, siz, alt);
	
}


static constexpr const char *kDefaultMissileIconKey = "oolite-default-missile-icon";
static constexpr const char *kDefaultMineIconKey = "oolite-default-mine-icon";
static const GLfloat kOutlineWidth = 0.5f;


namespace {

/*	An icon definition from descriptions.plist: the entry if it is an array, else a null PList (as
	oo_arrayForKey: gave nil).
*/
oo::PList MissileIconDefinition(const std::string &key)
{
	const oo::PList *iconDef = HeadUpDisplayUniverseDescriptions()->find(key);
	return (iconDef != nullptr && iconDef->isArray()) ? *iconDef : oo::PList();
}


OOPolygonSprite *IconForMissileRole(const std::string &role)
{
	static std::map<std::string, oo::Ref<OOPolygonSprite>, std::less<>>	sIcons;
	OOPolygonSprite		*result = nullptr;

	auto cached = sIcons.find(role);
	if (cached != sIcons.end())  result = cached->second.get();
	if (result == nullptr)
	{
		std::string key = role;
		oo::PList iconDef = MissileIconDefinition(key);
		oo::Ref<OOPolygonSprite> made;
		if (!iconDef.isNull())  made = OOPolygonSprite::initWithDataArray(iconDef, kOutlineWidth, key);
		if (made == nullptr)	// No custom icon or bad data
		{
			/*	Backwards compatibility note:
				The old implementation used suffixes "MISSILE" and "MINE" (without
				the underscore), and didn't draw anything if neither was found. I
				believe any difference in practical behavour due to the change here
				will be positive.
				-- Ahruman 2009-10-09
			*/
			if (oo::str::hasSuffix(role, "_MISSILE"))  key = kDefaultMissileIconKey;
			else  key = kDefaultMineIconKey;

			iconDef = MissileIconDefinition(key);
			made = OOPolygonSprite::initWithDataArray(iconDef, kOutlineWidth, key);
		}

		if (made != nullptr)
		{
			result = made.get();
			sIcons[role] = std::move(made);
		}
	}
	
	return result;
}

}	// namespace


void HeadUpDisplay::drawIconForMissile(::ShipEntity *missile, bool selected, int status, int x, int y, GLfloat width, GLfloat height, GLfloat alpha)
{
	OOPolygonSprite *sprite = IconForMissileRole((missile != nullptr ? missile->getPrimaryRole() : std::optional<std::string>()).value_or(""));
	
	if (selected)
	{
		// Draw yellow outline.
		OOGLPushModelView();
		OOGLTranslateModelView(make_vector(x - width * 2.0f, y - height * 2.0f, z1));
		OOGLScaleModelView(make_vector(width, height, 1.0f));
		GLColorWithOverallAlpha(yellow_color, alpha);
		if (sprite != nullptr)  sprite->drawOutline();	// a message to nil did nothing
		OOGLPopModelView();
		
		// Draw black backing, so outline colour isn’t blended into missile colour.
		OOGLPushModelView();
		OOGLTranslateModelView(make_vector(x - width * 2.0f, y - height * 2.0f, z1));
		OOGLScaleModelView(make_vector(width, height, 1.0f));
		GLColorWithOverallAlpha(black_color, alpha);
		if (sprite != nullptr)  sprite->drawFilled();	// a message to nil did nothing
		OOGLPopModelView();
		
		switch (status)
		{
			case MISSILE_STATUS_SAFE:
				GLColorWithOverallAlpha(green_color, alpha);	break;
			case MISSILE_STATUS_ARMED:
				GLColorWithOverallAlpha(yellow_color, alpha);	break;
			case MISSILE_STATUS_TARGET_LOCKED:
				GLColorWithOverallAlpha(red_color, alpha);		break;
		}
	}
	else
	{
		if ((missile != nullptr ? missile->primaryTarget() : (Entity *)nullptr) == nil)  GLColorWithOverallAlpha(green_color, alpha);
		else  GLColorWithOverallAlpha(red_color, alpha);
	}
	
	OOGLPushModelView();
	OOGLTranslateModelView(make_vector(x - width * 2.0f, y - height * 2.0f, z1));
	OOGLScaleModelView(make_vector(width, height, 1.0f));
	if (sprite != nullptr)  sprite->drawFilled();	// a message to nil did nothing
	OOGLPopModelView();
}


void HeadUpDisplay::drawIconForEmptyPylonAtX(int x, int y, GLfloat width, GLfloat height, GLfloat alpha)
{
	OOPolygonSprite *sprite = IconForMissileRole(kDefaultMissileIconKey);
	
	// Draw gray outline.
	OOGLPushModelView();
	OOGLTranslateModelView(make_vector(x - width * 2.0f, y - height * 2.0f, z1));
	OOGLScaleModelView(make_vector(width, height, 1.0f));
	GLColorWithOverallAlpha(lightgray_color, alpha);
	if (sprite != nullptr)  sprite->drawOutline();	// a message to nil did nothing
	OOGLPopModelView();
}


void HeadUpDisplay::drawMissileDisplay(const oo::PList &info)
{
	int					x, y, sp;
	NSSize				siz;
	GLfloat				alpha = overallAlpha;
	struct CachedInfo	cached;
	
	GetCurrentCachedInfo(&cached);
	
	x = useDefined(cached.x, MISSILES_DISPLAY_X) + (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr ? UNIVERSE->getGameView()->getX_offset() : 0.0f) * cached.x0;
	y = useDefined(cached.y, MISSILES_DISPLAY_Y) + (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr ? UNIVERSE->getGameView()->getY_offset() : 0.0f) * cached.y0;
	siz.width = useDefined(cached.width, MISSILE_ICON_WIDTH);
	siz.height = useDefined(cached.height, MISSILE_ICON_HEIGHT);
	alpha *= cached.alpha;
	sp = info.get<unsigned int>(SPACING_KEY, MISSILES_DISPLAY_SPACING);
	
	BOOL weaponsOnline = (PLAYER != nullptr ? PLAYER->weaponsOnline() : false);
	if (!weaponsOnline)  alpha *= 0.2f;	// darken missile display if weapons are offline
	
	if (!(PLAYER != nullptr ? PLAYER->dialIdentEngaged() : false))
	{
		OOMissileStatus status = (PLAYER != nullptr ? PLAYER->dialMissileStatus() : OOMissileStatus{});
		NSUInteger i, n_mis = (PLAYER != nullptr ? PLAYER->dialMaxMissiles() : 0);
		for (i = 0; i < n_mis; i++)
		{
			::ShipEntity *missile = (PLAYER != nullptr ? PLAYER->missileForPylon(i) : (::ShipEntity *)nil);
			if (missile)
			{
				drawIconForMissile(missile,
								   weaponsOnline && i == (PLAYER != nullptr ? PLAYER->getActiveMissile() : 0),
								   status,
								   x + (int)i * sp + 2, y,
								   siz.width * 0.25f, siz.height * 0.25f,
								   alpha);
			}
			else
			{
				drawIconForEmptyPylonAtX(x + (int)i * sp + 2, y,
									 siz.width * 0.25f, siz.height * 0.25f, alpha);
			}
		}
	}
	else
	{
		x -= siz.width;
		y -= siz.height * 0.75;
		siz.width *= 0.80;
		sp *= 0.75;
		switch ((PLAYER != nullptr ? PLAYER->dialMissileStatus() : OOMissileStatus{}))
		{
			case MISSILE_STATUS_SAFE:
				GLColorWithOverallAlpha(green_color, alpha);	break;
			case MISSILE_STATUS_ARMED:
				GLColorWithOverallAlpha(yellow_color, alpha);	break;
			case MISSILE_STATUS_TARGET_LOCKED:
				GLColorWithOverallAlpha(red_color, alpha);		break;
		}
		OOGLBEGIN(GL_QUADS);
			glVertex3i(x , y, z1);
			glVertex3i(x + siz.width, y, z1);
			glVertex3i(x + siz.width, y + siz.height, z1);
			glVertex3i(x , y + siz.height, z1);
		OOGLEND();
		GLColorWithOverallAlpha(green_color, alpha);
		cxx_OODrawString((PLAYER != nullptr ? PLAYER->dialTargetName() : std::optional<std::string>()).value_or(""), x + sp, y - 1, z1, NSMakeSize(siz.width, siz.height));
	}
	
}


void HeadUpDisplay::drawStatusLight(const oo::PList & /*info*/)
{
	int					x, y;
	NSSize				siz;
	GLfloat				alpha = overallAlpha;
	BOOL				blueAlert = cloakIndicatorOnStatusLight && (PLAYER != nullptr ? PLAYER->isCloaked() : false);
	struct CachedInfo	cached;
	
	GetCurrentCachedInfo(&cached);
	
	x = useDefined(cached.x, STATUS_LIGHT_CENTRE_X) + (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr ? UNIVERSE->getGameView()->getX_offset() : 0.0f) * cached.x0;
	y = useDefined(cached.y, STATUS_LIGHT_CENTRE_Y) + (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr ? UNIVERSE->getGameView()->getY_offset() : 0.0f) * cached.y0;
	siz.width = useDefined(cached.width, STATUS_LIGHT_HEIGHT);
	siz.height = useDefined(cached.height, STATUS_LIGHT_HEIGHT);
	alpha *= cached.alpha;
	
	GLfloat status_color[4] = { 0.25, 0.25, 0.25, 1.0};
	int alertCondition = (PLAYER != nullptr ? PLAYER->getAlertCondition() : OOAlertCondition{});
	GLfloat flash_alpha = 0.333 * (2.0f + sin((GLfloat)(UNIVERSE != nullptr ? UNIVERSE->getTime() : 0.0) * 2.5f * alertCondition));
	
	switch(alertCondition)
	{
		case ALERT_CONDITION_RED:
			status_color[0] = red_color[0];
			status_color[1] = red_color[1];
			status_color[2] = blueAlert ? blue_color[2] : red_color[2];
			break;
			
		case ALERT_CONDITION_GREEN:
			status_color[0] = green_color[0];
			status_color[1] = green_color[1];
			status_color[2] = blueAlert ? blue_color[2] : green_color[2];
			break;
			
		case ALERT_CONDITION_YELLOW:
			status_color[0] = yellow_color[0];
			status_color[1] = yellow_color[1];
			status_color[2] = blueAlert ? blue_color[2] : yellow_color[2];
			break;
			
		default:
		case ALERT_CONDITION_DOCKED:
			break;
	}
	status_color[3] = flash_alpha;
	GLColorWithOverallAlpha(status_color, alpha);
	OOGLBEGIN(GL_POLYGON);
	hudDrawStatusIconAt(x, y, z1, siz);
	OOGLEND();
	OOGL(glColor4f(0.25, 0.25, 0.25, alpha));
	OOGLBEGIN(GL_LINE_LOOP);
		hudDrawStatusIconAt(x, y, z1, siz);
	OOGLEND();
}


void HeadUpDisplay::drawDirectionCue(const oo::PList & /*info*/)
{
	GLfloat				alpha = overallAlpha;
	struct CachedInfo	cached;
	
	GetCurrentCachedInfo(&cached);
	
	alpha *= cached.alpha;
	
	if ((UNIVERSE != nullptr ? UNIVERSE->getDisplayGUI() : false))  return;
	
	Entity		*target = (PLAYER != nullptr ? PLAYER->primaryTarget() : (Entity *)nullptr);	// the C++ entity (its object until bead oo-zwnvp)
	if (target == nullptr)  return;
	
	// draw the direction cue
	OOMatrix	rotMatrix;
	
	rotMatrix = (PLAYER != nullptr ? PLAYER->rotationMatrix() : OOMatrix{});
	
	if ((UNIVERSE != nullptr ? UNIVERSE->getViewDirection() : OOViewID{}) != VIEW_GUI_DISPLAY)
	{
		const GLfloat innerSize = CROSSHAIR_SIZE;
		const GLfloat width = CROSSHAIR_SIZE * ONE_EIGHTH;
		const GLfloat outerSize = CROSSHAIR_SIZE * (1.0f + ONE_EIGHTH + ONE_EIGHTH);
		const float visMin = 0.994521895368273f;	// cos(6 degrees)
		const float visMax = 0.984807753012208f;	// cos(10 degrees)
		
		// Transform the view
		Vector rpn = (PLAYER != nullptr ? PLAYER->vectorTo(target) : Vector{});
		rpn = OOVectorMultiplyMatrix(rpn, rotMatrix);
		Vector drawPos = rpn;
		Vector forward = kZeroVector;
		
		switch ((UNIVERSE != nullptr ? UNIVERSE->getViewDirection() : OOViewID{}))
		{
			case VIEW_FORWARD:
				forward = kBasisZVector;
				break;
			case VIEW_AFT:
				drawPos.x = - drawPos.x;
				forward = vector_flip(kBasisZVector);
				break;
			case VIEW_PORT:
				drawPos.x = drawPos.z;
				forward = vector_flip(kBasisXVector);
				break;
			case VIEW_STARBOARD:
				drawPos.x = -drawPos.z;
				forward = kBasisXVector;
				break;
			case VIEW_CUSTOM:
				return;
			
			default:
				break;
		}
		
		float cosAngle = dot_product(vector_normal(rpn), forward);
		float visibility = 1.0f - ((visMax - cosAngle) * (1.0f / (visMax - visMin)));
		alpha *= OOClamp_0_1_f(visibility);
		
		if (alpha > 0.0f)
		{
			NSUInteger cueColorIndex = target->getIsWormhole() ? OO_RETICLE_COLOR_WORMHOLE : OO_RETICLE_COLOR_TARGET;
			OOColor *directionCueColor = ReticleColorAt(_reticleColors, cueColorIndex);	// never null: it raises past the end
			GLfloat	clearColorArray[4] =	{directionCueColor->redComponent(),
											directionCueColor->greenComponent(),
											directionCueColor->blueComponent(),
											0.0f};
			GLfloat directionCueColorArray[4] = {directionCueColor->redComponent(),
												directionCueColor->greenComponent(),
												directionCueColor->blueComponent(),
												directionCueColor->alphaComponent()};
			drawPos.z = 0.0f;	// flatten vector
			drawPos = vector_normal(drawPos);
			OOGLBEGIN(GL_LINE_STRIP);
				glColor4fv(clearColorArray);
				glVertex3f(drawPos.x * innerSize - drawPos.y * width, drawPos.y * innerSize + drawPos.x * width, z1);
				GLColorWithOverallAlpha(directionCueColorArray, alpha);
				glVertex3f(drawPos.x * outerSize, drawPos.y * outerSize, z1);
				glColor4fv(clearColorArray);
				glVertex3f(drawPos.x * innerSize + drawPos.y * width, drawPos.y * innerSize - drawPos.x * width, z1);
			OOGLEND();
		}
	}
}


void HeadUpDisplay::drawClock(const oo::PList &info)
{
	int					x, y;
	NSSize				siz;
	GLfloat				itemColor[4] = { 0.0f, 1.0f, 0.0f, 1.0f };
	struct CachedInfo	cached;
	
	GetCurrentCachedInfo(&cached);
	
	x = useDefined(cached.x, CLOCK_DISPLAY_X) + (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr ? UNIVERSE->getGameView()->getX_offset() : 0.0f) * cached.x0;
	y = useDefined(cached.y, CLOCK_DISPLAY_Y) + (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr ? UNIVERSE->getGameView()->getY_offset() : 0.0f) * cached.y0;
	siz.width = useDefined(cached.width, CLOCK_DISPLAY_WIDTH);
	siz.height = useDefined(cached.height, CLOCK_DISPLAY_HEIGHT);
	
	GetRGBAArrayFromInfo(info, itemColor);
	itemColor[3] *= overallAlpha;
	
	OOGL(glColor4f(itemColor[0], itemColor[1], itemColor[2], itemColor[3]));
	cxx_OODrawString((PLAYER != nullptr ? PLAYER->dial_clock() : std::string()), x, y, z1, siz);
}


void HeadUpDisplay::drawPrimedEquipment(const oo::PList &info)
{
	if ((PLAYER != nullptr ? PLAYER->status() : OOEntityStatus{}) == STATUS_DOCKED)
	{
		// Can't activate equipment while docked
		return;
	}
	
	GLfloat				itemColor[4] = { 0.0f, 1.0f, 0.0f, 1.0f };
	struct CachedInfo	cached;
	
	NSUInteger lines = info.get<int>("n_bars", 1);
	NSInteger pec = (NSInteger)(PLAYER != nullptr ? PLAYER->primedEquipmentCount() : 0);

	GetCurrentCachedInfo(&cached);
	
	NSInteger x = useDefined(cached.x, PRIMED_DISPLAY_X) + (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr ? UNIVERSE->getGameView()->getX_offset() : 0.0f) * cached.x0;
	NSInteger y = useDefined(cached.y, PRIMED_DISPLAY_Y) + (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr ? UNIVERSE->getGameView()->getY_offset() : 0.0f) * cached.y0;
	
	NSSize size =
	{
		.width = useDefined(cached.width, PRIMED_DISPLAY_WIDTH),
		.height = useDefined(cached.height, PRIMED_DISPLAY_HEIGHT)
	};

	if (pec == 0)
	{
		// Don't display if no primed equipment fitted
		return;
	}

	GetRGBAArrayFromInfo(info, itemColor);
	itemColor[3] *= overallAlpha;

	if (lines == 1)
	{
		OOGL(glColor4f(itemColor[0], itemColor[1], itemColor[2], itemColor[3]));
		const std::optional<std::string> equipmentName = (PLAYER != nullptr ? PLAYER->primedEquipmentName(0) : std::optional<std::string>());
		cxx_OODrawString(cxx_OOExpandKey("equipment-primed-hud", equipmentName).value_or(std::string()), x, y, z1, size);
	}
	else
	{
		NSInteger negative = (lines - 1) / 2;
		NSInteger positive = lines / 2;
		for (NSInteger i = -negative; i <= positive; i++)
		{
			if (i >= -(pec) / 2 && i <= (pec + 1) / 2)
			{
				// don't display loops if we have more equipment than lines
				// instead compact the display towards its centre
				GLfloat alphaScale = 1.0/((i<0)?(1.0-i):(1.0+i));
				OOGL(glColor4f(itemColor[0], itemColor[1], itemColor[2], itemColor[3]*alphaScale));
				cxx_OODrawString((PLAYER != nullptr ? PLAYER->primedEquipmentName(i) : std::optional<std::string>()).value_or(""), x, y, z1, size);
			}
			y -= size.height;
		}	
	}
}


void HeadUpDisplay::drawASCTarget(const oo::PList &info)
{
	if (!(checkPlayerInSystemFlight() && (PLAYER != nullptr ? PLAYER->status() : OOEntityStatus{}) != STATUS_LAUNCHING)) // normal system
	{
		// Can't have compass target when docked, etc. (matches blip condition)
		return;
	}
	
	GLfloat				itemColor[4] = { 0.0f, 0.0f, 1.0f, 1.0f };
	struct CachedInfo	cached;
	
	GetCurrentCachedInfo(&cached);

	NSInteger x = useDefined(cached.x, ASCTARGET_DISPLAY_X) + (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr ? UNIVERSE->getGameView()->getX_offset() : 0.0f) * cached.x0;
	NSInteger y = useDefined(cached.y, ASCTARGET_DISPLAY_Y) + (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr ? UNIVERSE->getGameView()->getY_offset() : 0.0f) * cached.y0;
	
	NSSize size =
	{
		.width = useDefined(cached.width, ASCTARGET_DISPLAY_WIDTH),
		.height = useDefined(cached.height, ASCTARGET_DISPLAY_HEIGHT)
	};

	GetRGBAArrayFromInfo(info, itemColor);
	itemColor[3] *= overallAlpha;

	OOGL(glColor4f(itemColor[0], itemColor[1], itemColor[2], itemColor[3]));
	if (info.get<int>("align") == 1)
	{
		cxx_OODrawStringAligned((PLAYER != nullptr ? PLAYER->compassTargetLabel() : std::optional<std::string>()).value_or(""), x, y, z1, size,YES);
	}
	else
	{
		cxx_OODrawStringAligned((PLAYER != nullptr ? PLAYER->compassTargetLabel() : std::optional<std::string>()).value_or(""), x, y, z1, size,NO);
	}
	
}


void HeadUpDisplay::drawWeaponsOfflineText(const oo::PList &info)
{
	OOViewID					viewID = (UNIVERSE != nullptr ? UNIVERSE->getViewDirection() : OOViewID{});
	GLfloat						textColor[4] = {0.0f, 1.0f, 0.0f, 1.0f};

	if (viewID == VIEW_CUSTOM ||
		overallAlpha == 0.0f ||
		!((PLAYER != nullptr ? PLAYER->status() : OOEntityStatus{}) == STATUS_IN_FLIGHT || (PLAYER != nullptr ? PLAYER->status() : OOEntityStatus{}) == STATUS_WITCHSPACE_COUNTDOWN) ||
		(UNIVERSE != nullptr ? UNIVERSE->getDisplayGUI() : false)
		)
	{
		// Don't draw weapons offline text
		return;
	}

	if (!(PLAYER != nullptr ? PLAYER->weaponsOnline() : false))
	{
		int					x, y;
		NSSize				siz;
		struct CachedInfo	cached;
	
		GetCurrentCachedInfo(&cached);
		
		x = useDefined(cached.x, WEAPONSOFFLINETEXT_DISPLAY_X) + (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr ? UNIVERSE->getGameView()->getX_offset() : 0.0f) * cached.x0;
		y = useDefined(cached.y, WEAPONSOFFLINETEXT_DISPLAY_Y) + (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr ? UNIVERSE->getGameView()->getY_offset() : 0.0f) * cached.y0;
		siz.width = useDefined(cached.width, WEAPONSOFFLINETEXT_WIDTH);
		siz.height = useDefined(cached.height, WEAPONSOFFLINETEXT_HEIGHT);
		
		GetRGBAArrayFromInfo(info, textColor);
		textColor[3] *= overallAlpha;
		
		OOGL(glColor4f(textColor[0], textColor[1], textColor[2], textColor[3]));
		// TODO: some caching required...
		cxx_OODrawString(OO_DESC("weapons-systems-offline"), x, y, z1, siz);
	}
}


void HeadUpDisplay::drawFPSInfoCounter(const oo::PList &info)
{
	if (!(UNIVERSE != nullptr ? UNIVERSE->getDisplayFPS() : false))  return;
	
	int					x, y;
	NSSize				siz;
	struct CachedInfo	cached;
	GLfloat				textColor[4] = {0.0, 1.0, 0.0, 1.0};
	
	GetCurrentCachedInfo(&cached);
	
	x = useDefined(cached.x, FPSINFO_DISPLAY_X) + (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr ? UNIVERSE->getGameView()->getX_offset() : 0.0f) * cached.x0;
	y = useDefined(cached.y, FPSINFO_DISPLAY_Y) + (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr ? UNIVERSE->getGameView()->getY_offset() : 0.0f) * cached.y0;
	siz.width = useDefined(cached.width, FPSINFO_DISPLAY_WIDTH);
	siz.height = useDefined(cached.height, FPSINFO_DISPLAY_HEIGHT);
	
	HPVector playerPos = (PLAYER != nullptr ? PLAYER->getPosition() : HPVector{});
	std::string positionInfo = oo::str::format("abs %.2f %.2f %.2f / %s", playerPos.x, playerPos.y, playerPos.z, (UNIVERSE != nullptr ? UNIVERSE->expressPosition(playerPos, "pwm") : std::optional<std::string>()).value_or("(null)").c_str());
	
	// We would normally set a variable alpha value here, but in this case we don't.
	// We prefer the FPS counter to be always visible - Nikos 20100405
	GetRGBAArrayFromInfo(info, textColor);
	OOGL(glColor4f(textColor[0], textColor[1], textColor[2], 1.0f));
	cxx_OODrawString((PLAYER != nullptr ? PLAYER->dial_fpsinfo() : std::string()), x, y, z1, siz);
	
#ifndef NDEBUG
	NSSize siz08 = NSMakeSize(0.8 * siz.width, 0.8 * siz.width);
	std::string collDebugInfo = oo::str::format("%s - %s", (PLAYER != nullptr ? PLAYER->dial_objinfo() : std::string()).c_str(), (UNIVERSE != nullptr ? UNIVERSE->collisionDescription() : std::string()).c_str());
	cxx_OODrawString(collDebugInfo, x, y - siz.height, z1, siz);

	cxx_OODrawString(positionInfo, x, y - 1.8 * siz.height, z1, siz08);

	std::string timeAccelerationFactorInfo = oo::str::format("TAF: %s%.2f", OO_DESC("multiplication-sign").c_str(), (UNIVERSE != nullptr ? UNIVERSE->getTimeAccelerationFactor() : 0.0));
	cxx_OODrawString(timeAccelerationFactorInfo, x, y - 3.2 * siz08.height, z1, siz08);
#endif
}


void HeadUpDisplay::drawScoopStatus(const oo::PList &info)
{
	int					i, x, y;
	NSSize				siz;
	GLfloat				alpha;
	struct CachedInfo	cached;
	
	GetCurrentCachedInfo(&cached);
	
	x = useDefined(cached.x, SCOOPSTATUS_CENTRE_X) + (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr ? UNIVERSE->getGameView()->getX_offset() : 0.0f) * cached.x0;
	y = useDefined(cached.y, SCOOPSTATUS_CENTRE_Y) + (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr ? UNIVERSE->getGameView()->getY_offset() : 0.0f) * cached.y0;
	siz.width = useDefined(cached.width, SCOOPSTATUS_WIDTH);
	siz.height = useDefined(cached.height, SCOOPSTATUS_HEIGHT);
	// default alpha value different from all others, won't use cached.alpha
	alpha = info.get<oo::NonNegative<float>>(ALPHA_KEY, 0.75f);
	
	const GLfloat* s0_color = red_color;
	GLfloat	s1c[4] = { 0.0f, 0.0f, 0.0f, 0.0f };
	GLfloat	s2c[4] = { 0.0f, 0.0f, 0.0f, 0.0f };
	GLfloat	s3c[4] = { 0.0f, 0.0f, 0.0f, 0.0f };
	int scoop_status = (PLAYER != nullptr ? PLAYER->dialFuelScoopStatus() : OOFuelScoopStatus{});
	GLfloat t = (UNIVERSE != nullptr ? UNIVERSE->getTime() : 0.0);
	GLfloat a1 = alpha * 0.5f * (1.0f + sin(t * 8.0f));
	GLfloat a2 = alpha * 0.5f * (1.0f + sin(t * 8.0f - 1.0f));
	GLfloat a3 = alpha * 0.5f * (1.0f + sin(t * 8.0f - 2.0f));
	
	switch (scoop_status)
	{
		case SCOOP_STATUS_NOT_INSTALLED:
			return;	// don't draw
			
		case SCOOP_STATUS_FULL_HOLD:
			s0_color = darkgreen_color;
			alpha *= 0.75;
			break;
			
		case SCOOP_STATUS_ACTIVE:
		case SCOOP_STATUS_OKAY:
			s0_color = green_color;
			break;
	}
	
	for (i = 0; i < 3; i++)
	{
		s1c[i] = s0_color[i];
		s2c[i] = s0_color[i];
		s3c[i] = s0_color[i];
	}
	if (scoop_status == SCOOP_STATUS_FULL_HOLD)
	{
		s3c[0] = red_color[0];
		s3c[1] = red_color[1];
		s3c[2] = red_color[2];
	}
	if (scoop_status == SCOOP_STATUS_ACTIVE)
	{
		s1c[3] = alpha * a1;
		s2c[3] = alpha * a2;
		s3c[3] = alpha * a3;
	}
	else
	{
		s1c[3] = alpha;
		s2c[3] = alpha;
		s3c[3] = alpha;
	}
	
	GLfloat w1 = siz.width / 8.0;
	GLfloat w2 = 2.0 * w1;
//	GLfloat w3 = 3.0 * w1;
	GLfloat w4 = 4.0 * w1;
	GLfloat h1 = siz.height / 8.0;
	GLfloat h2 = 2.0 * h1;
	GLfloat h3 = 3.0 * h1;
	GLfloat h4 = 4.0 * h1;
	
	OOGL(glDisable(GL_TEXTURE_2D));
	OOGLBEGIN(GL_QUADS);
	// section 1
		GLColorWithOverallAlpha(s1c, overallAlpha);
		glVertex3f(x, y + h1, z1);	glVertex3f(x - w2, y + h2, z1);	glVertex3f(x, y + h3, z1);	glVertex3f(x + w2, y + h2, z1);
	// section 2
		GLColorWithOverallAlpha(s2c, overallAlpha);
		glVertex3f(x, y - h1, z1);	glVertex3f(x - w4, y + h1, z1);	glVertex3f(x - w4, y + h2, z1);	glVertex3f(x, y, z1);
		glVertex3f(x, y - h1, z1);	glVertex3f(x + w4, y + h1, z1);	glVertex3f(x + w4, y + h2, z1);	glVertex3f(x, y, z1);
	// section 3
		GLColorWithOverallAlpha(s3c, overallAlpha);
		glVertex3f(x, y - h4, z1);	glVertex3f(x - w2, y - h2, z1);	glVertex3f(x - w2, y - h1, z1);	glVertex3f(x, y - h2, z1);
		glVertex3f(x, y - h4, z1);	glVertex3f(x + w2, y - h2, z1);	glVertex3f(x + w2, y - h1, z1);	glVertex3f(x, y - h2, z1);
	OOGLEND();
}


void HeadUpDisplay::drawStickSensitivityIndicator(const oo::PList & /*info*/)
{
	GLfloat				x, y;
	NSSize				siz;
	GLfloat				alpha = overallAlpha;
	BOOL				mouse = (PLAYER != nullptr ? PLAYER->isMouseControlOn() : false);
	OOJoystickManager	*stickHandler = OOJoystickManager::sharedStickHandler();	// made by the platform's registered factory (amendment oo-6bux; bead oo-9ht.69)
	struct CachedInfo	cached;
	
	if (stickHandler == nullptr || !stickHandler->joystickCount())	// a message to nil answered 0
	{
		return; // no need to draw if no joystick fitted
	}

	GetCurrentCachedInfo(&cached);
	
	x = useDefined(cached.x, STATUS_LIGHT_CENTRE_X) + (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr ? UNIVERSE->getGameView()->getX_offset() : 0.0f) * cached.x0;
	y = useDefined(cached.y, STATUS_LIGHT_CENTRE_Y) + (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr ? UNIVERSE->getGameView()->getY_offset() : 0.0f) * cached.y0;
	siz.width = useDefined(cached.width, STATUS_LIGHT_HEIGHT);
	siz.height = useDefined(cached.height, STATUS_LIGHT_HEIGHT);
	alpha *= cached.alpha;
	
	GLfloat div = stickHandler->getSensitivity();
	
	GLColorWithOverallAlpha(black_color, alpha / 4);
	GLDrawFilledOval(x, y, z1, siz, 10);
	
	GLColorWithOverallAlpha((div < 1.0 || mouse) ? lightgray_color : green_color, alpha);
	OOGL(GLScaledLineWidth(_crosshairWidth * lineWidth));
	
	if (div >= 1.0)
	{
		if (!mouse)
		{
			NSSize siz8th = { siz.width / 8, siz.height / 8 };
			GLDrawFilledOval(x, y, z1, siz8th, 30);
			
			if (div == 1.0) // normal mode
				GLColorWithOverallAlpha(lightgray_color, alpha);
		}
		
		siz.width -= _crosshairWidth * lineWidth / 2;
		siz.height -= _crosshairWidth * lineWidth / 2;
		GLDrawOval(x, y, z1, siz, 10);
	}
	else if (div < 1.0) // insensitive mode (shouldn't happen)
		GLDrawFilledOval(x, y, z1, siz, 10);

	OOGL(GLScaledLineWidth(lineWidth)); // reset
}


void HeadUpDisplay::drawTrumbles(const oo::PList & /*info*/)
{
	PlayerEntity *player = PLAYER;
	oo::Ref<OOTrumble> *trumbles = player->trumbleArray();
	NSUInteger i;
	for (i = player->getTrumbleCount(); i > 0; i--)
	{
		trumbles[i - 1]->drawTrumble(z1);
	}
}


namespace {

void prefetchData(const oo::PList &info, struct CachedInfo *data)
{
	data->x = info.get<float>(X_KEY, NOT_DEFINED);
	data->x0 = info.get<float>(X_ORIGIN_KEY, 0.0);
	data->y = info.get<float>(Y_KEY, NOT_DEFINED);
	data->y0 = info.get<float>(Y_ORIGIN_KEY, 0.0);
	data->width = info.get<float>(WIDTH_KEY, NOT_DEFINED);
	data->height = info.get<float>(HEIGHT_KEY, NOT_DEFINED);
	data->alpha = info.get<oo::NonNegative<float>>(ALPHA_KEY, 1.0f);	
}

}	// namespace


OOINLINE void SetCompassBlipColor(GLfloat relativeZ, GLfloat alpha)
{
	if (relativeZ >= 0.0f)
	{
		OOGL(glColor4f(0.0f, 1.0f, 0.0f, alpha));
	}
	else
	{
		OOGL(glColor4f(1.0f, 0.0f, 0.0f, alpha));
	}
}


void HeadUpDisplay::drawCompassPlanetBlipAt(Vector relativePosition, NSSize siz, GLfloat alpha)
{
	if (relativePosition.z >= 0)
	{
		OOGL(glColor4f(0.0,1.0,0.0,0.75 * alpha));
		GLDrawFilledOval(relativePosition.x, relativePosition.y, z1, siz, 30);
		OOGL(glColor4f(0.0,1.0,0.0,alpha));
		GLDrawOval(relativePosition.x, relativePosition.y, z1, siz, 30);
	}
	else
	{
		OOGL(glColor4f(1.0,0.0,0.0,alpha));
		GLDrawOval(relativePosition.x, relativePosition.y, z1, siz, 30);
	}
}


void HeadUpDisplay::drawCompassStationBlipAt(Vector relativePosition, NSSize siz, GLfloat alpha)
{
	SetCompassBlipColor(relativePosition.z, alpha);
	
	OOGLBEGIN(GL_LINE_LOOP);
		glVertex3f(relativePosition.x - 0.5 * siz.width, relativePosition.y - 0.5 * siz.height, z1);
		glVertex3f(relativePosition.x + 0.5 * siz.width, relativePosition.y - 0.5 * siz.height, z1);
		glVertex3f(relativePosition.x + 0.5 * siz.width, relativePosition.y + 0.5 * siz.height, z1);
		glVertex3f(relativePosition.x - 0.5 * siz.width, relativePosition.y + 0.5 * siz.height, z1);
	OOGLEND();
}


void HeadUpDisplay::drawCompassSunBlipAt(Vector relativePosition, NSSize siz, GLfloat alpha)
{
	OOGL(glColor4f(1.0, 1.0, 0.0, 0.75 * alpha));
	GLDrawFilledOval(relativePosition.x, relativePosition.y, z1, siz, 30);
	
	SetCompassBlipColor(relativePosition.z, alpha);
	
	GLDrawOval(relativePosition.x, relativePosition.y, z1, siz, 30);
}


void HeadUpDisplay::drawCompassTargetBlipAt(Vector relativePosition, NSSize siz, GLfloat alpha)
{
	SetCompassBlipColor(relativePosition.z, alpha);
	
	OOGLBEGIN(GL_LINES);
		glVertex3f(relativePosition.x - siz.width, relativePosition.y, z1);
		glVertex3f(relativePosition.x + siz.width, relativePosition.y, z1);
		glVertex3f(relativePosition.x, relativePosition.y - siz.height, z1);
		glVertex3f(relativePosition.x, relativePosition.y + siz.height, z1);
	OOGLEND();
	
	GLDrawOval(relativePosition.x, relativePosition.y, z1, siz, 30);
}


void HeadUpDisplay::drawCompassBeaconBlipAt(Vector relativePosition, NSSize siz, GLfloat alpha)
{
	SetCompassBlipColor(relativePosition.z, alpha);
	
	OOGLBEGIN(GL_LINES);
	/*		glVertex3f(relativePosition.x - 0.5 * siz.width, relativePosition.y - 0.5 * siz.height, z1);
		glVertex3f(relativePosition.x, relativePosition.y + 0.5 * siz.height, z1);
		
		glVertex3f(relativePosition.x + 0.5 * siz.width, relativePosition.y - 0.5 * siz.height, z1);
		glVertex3f(relativePosition.x, relativePosition.y + 0.5 * siz.height, z1);
		
		glVertex3f(relativePosition.x - 0.5 * siz.width, relativePosition.y - 0.5 * siz.height, z1);
		glVertex3f(relativePosition.x + 0.5 * siz.width, relativePosition.y - 0.5 * siz.height, z1); */
	glVertex3f(relativePosition.x + 0.6 * siz.width, relativePosition.y, z1);
	glVertex3f(relativePosition.x, relativePosition.y + 0.6 * siz.height, z1);

	glVertex3f(relativePosition.x - 0.6 * siz.width, relativePosition.y, z1);
	glVertex3f(relativePosition.x, relativePosition.y + 0.6 * siz.height, z1);

	glVertex3f(relativePosition.x + 0.6 * siz.width, relativePosition.y, z1);
	glVertex3f(relativePosition.x, relativePosition.y - 0.6 * siz.height, z1);

	glVertex3f(relativePosition.x - 0.6 * siz.width, relativePosition.y, z1);
	glVertex3f(relativePosition.x, relativePosition.y - 0.6 * siz.height, z1);

	OOGLEND();
}




//---------------------------------------------------------------------//

static void hudDrawIndicatorAt(GLfloat x, GLfloat y, GLfloat z, NSSize siz, GLfloat amount)
{
	if (siz.width > siz.height)
	{
		GLfloat dial_oy =   y - siz.height/2;
		GLfloat position =  x + amount * siz.width / 2;
		OOGLBEGIN(GL_QUADS);
			glVertex3f(position, dial_oy, z);
			glVertex3f(position+2, y, z);
			glVertex3f(position, dial_oy+siz.height, z);
			glVertex3f(position-2, y, z);
		OOGLEND();
	}
	else
	{
		GLfloat dial_ox =   x - siz.width/2;
		GLfloat position =  y + amount * siz.height / 2;
		OOGLBEGIN(GL_QUADS);
			glVertex3f(dial_ox, position, z);
			glVertex3f(x, position+2, z);
			glVertex3f(dial_ox + siz.width, position, z);
			glVertex3f(x, position-2, z);
		OOGLEND();
	}
}


static void hudDrawMarkerAt(GLfloat x, GLfloat y, GLfloat z, NSSize siz, GLfloat amount)
{
	if (siz.width > siz.height)
	{
		GLfloat dial_oy =   y - siz.height/2;
		GLfloat position =  x + amount * siz.width - siz.width/2;
		OOGLBEGIN(GL_QUADS);
			glVertex3f(position+1, dial_oy+1, z);
			glVertex3f(position+1, dial_oy+siz.height-1, z);
			glVertex3f(position-1, dial_oy+siz.height-1, z);
			glVertex3f(position-1, dial_oy+1, z);
		OOGLEND();
	}
	else
	{
		GLfloat dial_ox =   x - siz.width/2;
		GLfloat position =  y + amount * siz.height - siz.height/2;
		OOGLBEGIN(GL_QUADS);
			glVertex3f(dial_ox+1, position+1, z);
			glVertex3f(dial_ox + siz.width-1, position+1, z);
			glVertex3f(dial_ox + siz.width-1, position-1, z);
			glVertex3f(dial_ox+1, position-1, z);
		OOGLEND();
	}
}


static void hudDrawBarAt(GLfloat x, GLfloat y, GLfloat z, NSSize siz, GLfloat amount)
{
	GLfloat dial_ox =   x - siz.width/2;
	GLfloat dial_oy =   y - siz.height/2;
	if (fabs(siz.width) > fabs(siz.height))
	{
		GLfloat position =  dial_ox + amount * siz.width;
		
		OOGLBEGIN(GL_QUADS);
			glVertex3f(dial_ox, dial_oy, z);
			glVertex3f(position, dial_oy, z);
			glVertex3f(position, dial_oy+siz.height, z);
			glVertex3f(dial_ox, dial_oy+siz.height, z);
		OOGLEND();
	}
	else
	{
		GLfloat position =  dial_oy + amount * siz.height;
		
		OOGLBEGIN(GL_QUADS);
			glVertex3f(dial_ox, dial_oy, z);
			glVertex3f(dial_ox, position, z);
			glVertex3f(dial_ox+siz.width, position, z);
			glVertex3f(dial_ox+siz.width, dial_oy, z);
		OOGLEND();
	}
}


static void hudDrawSurroundAt(GLfloat x, GLfloat y, GLfloat z, NSSize siz)
{
	GLfloat dial_ox = x - siz.width/2;
	GLfloat dial_oy = y - siz.height/2;
	
	OOGLBEGIN(GL_LINE_LOOP);
		glVertex3f(dial_ox-2, dial_oy-2, z);
		glVertex3f(dial_ox+siz.width+2, dial_oy-2, z);
		glVertex3f(dial_ox+siz.width+2, dial_oy+siz.height+2, z);
		glVertex3f(dial_ox-2, dial_oy+siz.height+2, z);
	OOGLEND();
}


static void hudDrawStatusIconAt(int x, int y, int z, NSSize siz)
{
	int ox = x - siz.width / 2.0;
	int oy = y - siz.height / 2.0;
	int w = siz.width / 4.0;
	int h = siz.height / 4.0; 

	glVertex3i(ox, oy + h, z);
	glVertex3i(ox, oy + 3 * h, z);
	glVertex3i(ox + w, oy + 4 * h, z);
	glVertex3i(ox + 3 * w, oy + 4 * h, z);
	glVertex3i(ox + 4 * w, oy + 3 * h, z);
	glVertex3i(ox + 4 * w, oy + h, z);
	glVertex3i(ox + 3 * w, oy, z);
	glVertex3i(ox + w, oy, z);
}


namespace {

void hudDrawReticleOnTarget(Entity *target, PlayerEntity *player1, GLfloat /*z1*/, 
				GLfloat alpha, BOOL reticleTargetSensitive, oo::PList *propertiesReticleTargetSensitive,
				BOOL colourFromScannerColour, BOOL showText, const oo::PList &info, const std::vector<oo::Ref<OOColor>> &reticleColors)
{
	if (target == nil || player1 == nil)  
	{
		return;
	}
	if (HeadUpDisplayPlayerGuiScreen(player1) != GUI_SCREEN_MAIN)	// don't draw on text screens
	{
		return;
	}

	ShipEntity		*target_ship = nil;
	std::optional<std::string>	legal_desc;
	
	GLfloat			scale = info.get<float>("reticle_scale", ONE_SIXTYFOURTH);
	

	if (HeadUpDisplayEntityIsShip(target))
	{
		target_ship = oo::ToShip(target);
		legal_desc = HeadUpDisplayShipScanDescription(target_ship);
	}

	if (HeadUpDisplayShipIsCloaked(target_ship))  return;
	
	
	Vector			p1;
	
	// by definition close enough that single precision is fine
	p1 = HPVectorToVector(HPvector_subtract(HeadUpDisplayEntityPosition(target), HeadUpDisplayPlayerViewpointPosition(player1)));
	
	GLfloat			rdist = magnitude(p1);
	GLfloat			rsize = HeadUpDisplayEntityCollisionRadius(target) / (2 * (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr ? UNIVERSE->getGameView()->fov(YES) : 0.0f)); // FIXME integrate 2 into fov to remove magic number
	
	if (rsize < rdist * scale)
		rsize = rdist * scale;
	
	GLfloat			rs0 = rsize;
	GLfloat			rs2 = rsize * 0.50;
	
	OOGLPushModelView();
	hudRotateViewpointForVirtualDepth(player1,p1);

	// draw the reticle
	float range = sqrt(target->zero_distance) - target->collision_radius;
	
	int flash = (int)(HeadUpDisplayUniverseGetTime() * 4);
	flash &= 1;

	// Draw reticle cyan for Wormholes
	if (HeadUpDisplayEntityIsWormhole(target))
	{
		OOColor *wormholeReticleColor = ReticleColorAt(reticleColors, OO_RETICLE_COLOR_WORMHOLE);	// never null: it raises past the end
		GLfloat wormholeReticleColorArray[4] = {wormholeReticleColor->redComponent(),
												wormholeReticleColor->greenComponent(),
												wormholeReticleColor->blueComponent(),
												wormholeReticleColor->alphaComponent()};
		GLColorWithOverallAlpha(wormholeReticleColorArray, alpha);
	}
	else
	{
		// Reticle sensitivity accuracy calculation
		BOOL			isTargeted = NO;
		GLfloat			probabilityAccuracy;
		
		if (propertiesReticleTargetSensitive != nullptr)
		{
			// Only if target is within player's weapon range, we mind for reticle accuracy
			if (range < HeadUpDisplayPlayerWeaponRange(player1))
			{
				// After MAX_ACCURACY_RANGE km start decreasing high accuracy probability by ACCURACY_PROBABILITY_DECREASE_FACTOR%
				if (range > MAX_ACCURACY_RANGE)   
				{
					// Every one second re-evaluate accuracy
					if (HeadUpDisplayUniverseGetTime() > propertiesReticleTargetSensitive->get<double>("timeLastAccuracyProbabilityCalculation") + 1) 
					{
						probabilityAccuracy = 1-(range-MAX_ACCURACY_RANGE)*ACCURACY_PROBABILITY_DECREASE_FACTOR; 
						// Make sure probability does not go below a minimum
						probabilityAccuracy = probabilityAccuracy < MIN_PROBABILITY_ACCURACY ? MIN_PROBABILITY_ACCURACY : probabilityAccuracy;
						(*propertiesReticleTargetSensitive->getIf<oo::PList::Dict>())["isAccurate"] = oo::PList(static_cast<bool>((randf() < probabilityAccuracy) ? YES : NO));
			
						// Store the time the last accuracy probability has been performed
						(*propertiesReticleTargetSensitive->getIf<oo::PList::Dict>())["timeLastAccuracyProbabilityCalculation"] = oo::PList(static_cast<double>(HeadUpDisplayUniverseGetTime()));
					}			
					if (propertiesReticleTargetSensitive->get<bool>("isAccurate"))
					{
						// high accuracy reticle
						isTargeted = (HeadUpDisplayUniverseFirstEntityTargetedByPlayerPrecisely() == target);
					}
					else
					{
						// low accuracy reticle
						isTargeted = (HeadUpDisplayUniverseFirstEntityTargetedByPlayer() == target);
					}
				}
				else
				{
					// high accuracy reticle
					isTargeted = (HeadUpDisplayUniverseFirstEntityTargetedByPlayerPrecisely() == target);
				}
			}
		}
		
		// If reticle is target sensitive, draw target box in red 
		// when target passes through laser hit-point(with decreasing accuracy) 
		// and is within hit-range.
		//
		// NOTE: The following condition also considers (indirectly) the player's weapon range.
		//       'isTargeted' is initialised to FALSE. Only if target is within the player's weapon range,
		//       it might change value. Therefore, it is not necessary to add '&& range < [player1 weaponRange]'
		//       to the following condition.
		if (colourFromScannerColour)
		{
			if (HeadUpDisplayEntityIsShip(target))
			{
				ShipEntity *ship = oo::ToShip(target);
				BOOL isHostile = HeadUpDisplayShipIsHostileToPlayer(ship);
				GLColorWithOverallAlpha(HeadUpDisplayShipScannerDisplayColor(ship, isHostile, flash),alpha);
			}
			else if (HeadUpDisplayEntityIsVisualEffect(target))
			{
				OOVisualEffectEntity *vis = oo::ToEffect(target);	// C++ since bead oo-9ht.165
				GLColorWithOverallAlpha(HeadUpDisplayVisualEffectScannerDisplayColor(vis, flash),alpha);
			}
			else
			{
				GLColorWithOverallAlpha(green_color, alpha);
			}
		}
		else
		{
			oo::Ref<OOColor> reticleDisplayColor;
			if (reticleTargetSensitive && isTargeted)
			{
				reticleDisplayColor = oo::Ref<OOColor>(ReticleColorAt(reticleColors, OO_RETICLE_COLOR_TARGET_SENSITIVE));
				if (!reticleDisplayColor)  reticleDisplayColor = OOColor::redColor();
			}
			else
			{
				reticleDisplayColor = oo::Ref<OOColor>(ReticleColorAt(reticleColors, OO_RETICLE_COLOR_TARGET));
				if (!reticleDisplayColor)  reticleDisplayColor = OOColor::greenColor();
			}
			GLfloat reticleDisplayColorArray[4] = {	reticleDisplayColor->redComponent(),
													reticleDisplayColor->greenComponent(),
													reticleDisplayColor->blueComponent(),
													reticleDisplayColor->alphaComponent() };
			GLColorWithOverallAlpha(reticleDisplayColorArray, alpha);
		}
	}
	OOGLBEGIN(GL_LINES);
		glVertex2f(rs0,rs2);	glVertex2f(rs0,rs0);
		glVertex2f(rs0,rs0);	glVertex2f(rs2,rs0);
		
		glVertex2f(rs0,-rs2);	glVertex2f(rs0,-rs0);
		glVertex2f(rs0,-rs0);	glVertex2f(rs2,-rs0);
		
		glVertex2f(-rs0,rs2);	glVertex2f(-rs0,rs0);
		glVertex2f(-rs0,rs0);	glVertex2f(-rs2,rs0);
		
		glVertex2f(-rs0,-rs2);	glVertex2f(-rs0,-rs0);
		glVertex2f(-rs0,-rs0);	glVertex2f(-rs2,-rs0);
	OOGLEND();
	
	if (showText)
	{
		// add text for reticle here
		range *= 0.001f;
		if (range < 0.001f) range = 0.0f;	// avoids the occasional -0.001 km distance.
		NSSize textsize = NSMakeSize(rdist * scale, rdist * scale);
		float line_height = rdist * scale;
		std::string	infoline = oo::str::format("%0.3f km", range);
		if (legal_desc.has_value()) infoline = oo::str::format("%s (%s)", infoline.c_str(), legal_desc->c_str());
		// no need to set colour here
		cxx_OODrawString(HeadUpDisplayPlayerDialTargetName(player1).value_or(""), rs0, 0.5 * rs2, 0, textsize);
		cxx_OODrawString(infoline, rs0, 0.5 * rs2 - line_height, 0, textsize);
	
		if (HeadUpDisplayEntityIsWormhole(target))
		{
			// Note: No break statements in the following switch() since every case
			//       falls through to the next.  Cases arranged in reverse order.
			switch(HeadUpDisplayWormholeScanInfo(static_cast<WormholeEntity *>(target)))
			{
			case WH_SCANINFO_SHIP:
				// TOOD: Render anything on the HUD for this?
			case WH_SCANINFO_DESTINATION:
				// Rendered above in dialTargetName, so no need to do anything here
				// unless we want a separate line Destination: XXX ?
			case WH_SCANINFO_ARRIVAL_TIME:
			{
				// a format read at run time (ADR-0043 item 19)
				const std::string etaFormat = OO_DESC("wormhole-ETA-@");	// the format first, as Clang evaluates the arguments: a description that is an array draws (ADR-0063 item 5)
				std::string wormholeETA = oo::str::formatRuntime(etaFormat, { cxx_ClockToString(HeadUpDisplayWormholeEstimatedArrivalTime(static_cast<WormholeEntity *>(target)), NO) });
				cxx_OODrawString(wormholeETA, rs0, 0.5 * rs2 - 3 * line_height, 0, textsize);
			}
			case WH_SCANINFO_COLLAPSE_TIME:
			{
				OOTimeDelta timeForCollapsing = HeadUpDisplayWormholeExpiryTime(static_cast<WormholeEntity *>(target)) - HeadUpDisplayPlayerClockTimeAdjusted(player1);
				int minutesToCollapse = floor (timeForCollapsing / 60.0);
				int secondsToCollapse = (int)timeForCollapsing % 60;
				
				std::string wormholeExpiringIn = oo::str::formatRuntime(OO_DESC("wormhole-collapsing-in-mm:ss"), { minutesToCollapse, secondsToCollapse });
				cxx_OODrawString(wormholeExpiringIn, rs0, 0.5 * rs2 - 2 * line_height, 0, textsize);
			}
			case WH_SCANINFO_SCANNED:
			case WH_SCANINFO_NONE:
				break;
			}
		}
	}
	
	OOGLPopModelView();
}


void hudDrawWaypoint(Entity *waypoint, PlayerEntity *player1, GLfloat /*z1*/, GLfloat alpha, BOOL selected, GLfloat scale)
{
	if (HeadUpDisplayPlayerGuiScreen(player1) != GUI_SCREEN_MAIN)	// don't draw on text screens
	{
		return;
	}
	

	Vector	p1 = HPVectorToVector(HPvector_subtract(HeadUpDisplayEntityPosition(waypoint), HeadUpDisplayPlayerViewpointPosition(player1)));

	OOGLPushModelView();
	hudRotateViewpointForVirtualDepth(player1,p1);
	
	// either close enough that single precision is fine or far enough
	// away that precision is irrelevant
	
	GLfloat	rdist = magnitude(p1);
	GLfloat	rsize = rdist * scale;
	
	GLfloat	rs0 = rsize;
	GLfloat	rs2 = rsize * 0.50;

	if (selected)
	{
		GLColorWithOverallAlpha(blue_color, alpha);
	}
	else
	{
		GLColorWithOverallAlpha(blue_color, alpha*0.25);
	}

	OOGLBEGIN(GL_LINES);
		glVertex2f(rs0,rs2);	glVertex2f(rs2,rs2);
		glVertex2f(rs2,rs0);	glVertex2f(rs2,rs2);

		glVertex2f(-rs0,rs2);	glVertex2f(-rs2,rs2);
		glVertex2f(-rs2,rs0);	glVertex2f(-rs2,rs2);

		glVertex2f(-rs0,-rs2);	glVertex2f(-rs2,-rs2);
		glVertex2f(-rs2,-rs0);	glVertex2f(-rs2,-rs2);

		glVertex2f(rs0,-rs2);	glVertex2f(rs2,-rs2);
		glVertex2f(rs2,-rs0);	glVertex2f(rs2,-rs2);

//		glVertex2f(0,-rs2);	glVertex2f(0,rs2);
//		glVertex2f(rs2,0);	glVertex2f(-rs2,0);
	OOGLEND();
	
	if (selected)
	{
		GLfloat range = HPdistance(HeadUpDisplayEntityPosition(player1),HeadUpDisplayEntityPosition(waypoint)) * 0.001f;
		if (range < 0.001f) range = 0.0f;	// avoids the occasional -0.001 km distance.
		NSSize textsize = NSMakeSize(rdist * scale, rdist * scale);
		float line_height = rdist * scale;
		std::string	infoline = oo::str::format("%0.3f km", range);
		cxx_OODrawString(infoline, rs0 * 0.5, -rs2 - line_height, 0, textsize);
	}

	OOGLPopModelView();
}

}	// namespace

static void hudRotateViewpointForVirtualDepth(PlayerEntity * player1, Vector p1)
{
	Quaternion		back_q = HeadUpDisplayEntityOrientation(player1);
	back_q.w = -back_q.w;   // invert
	Vector			v1 = vector_up_from_quaternion(back_q);
	NSSize			viewSize = (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr ? UNIVERSE->getGameView()->getViewSize() : NSSize{});
	float			aspect = viewSize.width / viewSize.height;

	// The field of view transformation is really a scale operation on the view window.
	// We must unapply it through these transformations for them to be right.
	// We must also take into account the window aspect ratio.
	float ratio = 2 * (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr ? UNIVERSE->getGameView()->fov(YES) : 0.0f); // FIXME 2 is magic number; fov should integrate it
	if (3.0f * aspect >= 4.0f)
	{
		OOGLScaleModelView(make_vector(1/ratio, 1/ratio, 1.0f));
	}
	else
	{
		OOGLScaleModelView(make_vector((4.0f/3.0f)/(aspect*ratio), (4.0f/3.0f)/(aspect*ratio), 1.0f));
	}

	// deal with view directions
	Vector view_dir, view_up = kBasisYVector;
	switch (HeadUpDisplayUniverseViewDirection())
	{
		default:
		case VIEW_FORWARD:
			view_dir.x = 0.0;   view_dir.y = 0.0;   view_dir.z = 1.0;
			break;
			
		case VIEW_AFT:
			view_dir.x = 0.0;   view_dir.y = 0.0;   view_dir.z = -1.0;
			quaternion_rotate_about_axis(&back_q, v1, M_PI);
			break;
			
		case VIEW_PORT:
			view_dir.x = -1.0;   view_dir.y = 0.0;   view_dir.z = 0.0;
			quaternion_rotate_about_axis(&back_q, v1, 0.5 * M_PI);
			break;
			
		case VIEW_STARBOARD:
			view_dir.x = 1.0;   view_dir.y = 0.0;   view_dir.z = 0.0;
			quaternion_rotate_about_axis(&back_q, v1, -0.5 * M_PI);
			break;
			
		case VIEW_CUSTOM:
			view_dir = HeadUpDisplayPlayerCustomViewForwardVector(player1);
			view_up = HeadUpDisplayPlayerCustomViewUpVector(player1);
			back_q = quaternion_multiply(HeadUpDisplayPlayerCustomViewQuaternion(player1), back_q);
			break;
	}
	OOGLLookAt(view_dir, kZeroVector, view_up);

	// rotate the view
	OOGLMultModelView(HeadUpDisplayPlayerRotationMatrix(player1));
	// translate the view
	OOGLTranslateModelView(p1);
	// rotate to face player1
	OOGLMultModelView(OOMatrixForQuaternionRotation(back_q));

	// We come back now to the previous scale.
	OOGLScaleModelView(make_vector(ratio, ratio, 1.0f));
	// draw the waypoint
}


static void InitTextEngine(void)
{
	oo::PList				fontSpec;
	const oo::PList			*widths = nullptr;
	std::string				texName;
	NSUInteger				i, count;

	fontSpec = ResourceManager::dictionaryFromFilesNamed("oolite-font.plist", std::string("Config"), NO);

	texName = fontSpec.get<std::string>("texture", "oolite-font.png");
	sFontTexture = OOTexture::textureWithName(texName,
												   std::string("Textures"),
												   kFontTextureOptions,
												   0.0f,
												   -0.75f).leakRef();	// retained, as -retain kept it

	sF6KernGovt = fontSpec.get<float>("f6KernGovernment", 1.0);
	sF6KernTL = fontSpec.get<float>("f6KernTechLevel", 2.0);

	sEncodingCoverter = oo::makeRef<OOEncodingConverter>(fontSpec).leakRef();
	widths = fontSpec.find("widths");	// used only if it is an array, as before
	count = (widths != nullptr && widths->isArray()) ? widths->count() : 0;
	if (count > 256)  count = 256;
	for (i = 0; i != count; ++i)
	{
		sGlyphWidths[i] = widths->at<float>(i) * GLYPH_SCALE_FACTOR;
	}
}


namespace {

/*	The display-encoded bytes of text (empty where the conversion failed, or before the font is
	loaded: a message to nil).
*/
oo::Data ConvertedString(const std::string &text)
{
	if (sEncodingCoverter == nullptr)  return oo::Data();
	return sEncodingCoverter->convertString(text);
}

}	// namespace


void OOHUDResetTextEngine(void)
{
	OOTexture *fontTexture = sFontTexture;	// DESTROY(): cleared before the release
	sFontTexture = nullptr;
	oo::release(fontTexture);
	OOEncodingConverter *encodingConverter = sEncodingCoverter;	// DESTROY(): cleared before the release
	sEncodingCoverter = nullptr;
	oo::release(encodingConverter);
}


static GLfloat drawCharacterQuad(uint8_t chr, GLfloat x, GLfloat y, GLfloat z, NSSize siz)
{
	// 31 (narrow space) and 32 (space) are non-printing characters, so
	// don't print them, just return their width to move the pointer
	if (chr > 32 || chr < 31) {
		GLfloat texture_x = ONE_SIXTEENTH * (chr & 0x0f);
		GLfloat texture_y = ONE_SIXTEENTH * (chr >> 4);
		if (chr > 32)  y += ONE_EIGHTH * siz.height;	// Adjust for baseline offset change in 1.71 (needed to keep accented characters in box)
	
		glTexCoord2f(texture_x, texture_y + ONE_SIXTEENTH);
		glVertex3f(x, y, z);
		glTexCoord2f(texture_x + ONE_SIXTEENTH, texture_y + ONE_SIXTEENTH);
		glVertex3f(x + siz.width, y, z);
		glTexCoord2f(texture_x + ONE_SIXTEENTH, texture_y);
		glVertex3f(x + siz.width, y + siz.height, z);
		glTexCoord2f(texture_x, texture_y);
		glVertex3f(x, y + siz.height, z);
	}
	return siz.width * sGlyphWidths[chr];
}


NSRect cxx_OORectFromString(const std::string &text, GLfloat x, GLfloat y, NSSize siz)
{
	GLfloat				w = 0;
	oo::Data			data;
	const uint8_t		*bytes = NULL;
	NSUInteger			i, length;

	data = ConvertedString(text);
	bytes = (const uint8_t *)data.bytes();
	length = data.length();
	
	for (i = 0; i < length; i++)
	{
		w += siz.width * sGlyphWidths[bytes[i]];
	}
	
	return NSMakeRect(x, y, w, siz.height);
}


CGFloat cxx_OOStringWidthInEm(const std::string &text)
{
	return cxx_OORectFromString(text, 0, 0, NSMakeSize(1.0 / (GLYPH_SCALE_FACTOR * 8.0), 1.0)).size.width;
}


void drawHighlight(GLfloat x, GLfloat y, GLfloat z, NSSize siz, GLfloat alpha)
{
	// Rounded corners, fading 'shadow' version
	OOGL(glColor4f(0.0f, 0.0f, 0.0f, alpha * 0.4f));	// dark translucent shadow
	
	OOGLBEGIN(GL_POLYGON);
		// thin 'halo' around the 'solid' highlight
		glVertex3f(x + 1.0f , y + siz.height + 2.5f, z);
		glVertex3f(x + siz.width + 3.0f, y + siz.height + 2.5f, z);
		glVertex3f(x + siz.width + 4.5f, y + siz.height + 1.0f, z);
		glVertex3f(x + siz.width + 4.5f, y + 3.0f, z);
		glVertex3f(x + siz.width + 3.0f, y + 1.5f, z);
		glVertex3f(x + 1.0f, y + 1.5f, z);
		glVertex3f(x - 0.5f, y + 3.0f, z);
		glVertex3f(x - 0.5f, y + siz.height + 1.0f, z);
	OOGLEND();

	
	OOGLBEGIN(GL_POLYGON);
		glVertex3f(x + 1.0f, y + siz.height + 2.0f, z);
		glVertex3f(x + siz.width + 3.0f, y + siz.height + 2.0f, z);
		glVertex3f(x + siz.width + 4.0f, y + siz.height + 1.0f, z);
		glVertex3f(x + siz.width + 4.0f, y + 3.0f, z);
		glVertex3f(x + siz.width + 3.0f, y + 2.0f, z);
		glVertex3f(x + 1.0f, y + 2.0f, z);
		glVertex3f(x, y + 3.0f, z);
		glVertex3f(x, y + siz.height + 1.0f, z);
	OOGLEND();
}


void cxx_OODrawString(const std::string &text, GLfloat x, GLfloat y, GLfloat z, NSSize siz)
{
	cxx_OODrawStringAligned(text,x,y,z,siz,NO);
}


void cxx_OODrawStringAligned(const std::string &text, GLfloat x, GLfloat y, GLfloat z, NSSize siz, BOOL rightAlign)
{
	OOStartDrawingStrings();
	cxx_OODrawStringQuadsAligned(text,x,y,z,siz,rightAlign);
	OOStopDrawingStrings();
}

void OOStartDrawingStrings() {
	OOSetOpenGLState(OPENGL_STATE_OVERLAY);
	
	OOGL(glEnable(GL_TEXTURE_2D));
	if (sFontTexture != nullptr)  sFontTexture->apply();	// a message to nil did nothing
	OOGLBEGIN(GL_QUADS);

}

void cxx_OODrawStringQuadsAligned(const std::string &text, GLfloat x, GLfloat y, GLfloat z, NSSize siz, BOOL rightAlign)
{
	GLfloat			cx = x;
	NSInteger		i, length;
	oo::Data		data;
	const uint8_t	*bytes = NULL;

	data = ConvertedString(text);
	length = data.length();
	bytes = (const uint8_t *)data.bytes();

	if (EXPECT_NOT(rightAlign))
	{
		cx -= cxx_OORectFromString(text, 0.0f, 0.0f, siz).size.width;
	}

	for (i = 0; i < length; i++)
	{
		cx += drawCharacterQuad(bytes[i], cx, y, z, siz);
	}
}

void OOStopDrawingStrings() {
	OOGLEND();
	
	OOTexture::applyNone();
	OOGL(glDisable(GL_TEXTURE_2D));
	
	OOVerifyOpenGLState();
}


void cxx_OODrawHilightedString(const std::string &text, GLfloat x, GLfloat y, GLfloat z, NSSize siz)
{
	GLfloat color[4];

	// get the physical dimensions of the string
	NSSize strsize = cxx_OORectFromString(text, 0.0f, 0.0f, siz).size;
	strsize.width += 0.5f;
	
	OOSetOpenGLState(OPENGL_STATE_OVERLAY);
	
	OOGL(glPushAttrib(GL_CURRENT_BIT));	// save the text colour
	OOGL(glGetFloatv(GL_CURRENT_COLOR, color));	// we need the original colour's alpha.
	
	drawHighlight(x, y, z, strsize, color[3]);
	
	OOGL(glPopAttrib());	//restore the colour

	cxx_OODrawString(text, x, y, z, siz);
	
	OOVerifyOpenGLState();
}


void OODrawPlanetInfo(int gov, int eco, int tec, GLfloat x, GLfloat y, GLfloat z, NSSize siz)
{
	GLfloat govcol[] = {	0.5, 0.0, 0.7,
							0.7, 0.5, 0.3,
							0.0, 1.0, 0.3,
							1.0, 0.8, 0.1,
							1.0, 0.0, 0.0,
							0.1, 0.5, 1.0,
							0.7, 0.7, 0.7,
							0.7, 1.0, 1.0};
	
	GLfloat cx = x;
	int tl = tec + 1;
	GLfloat ce1 = 1.0f - 0.125f * eco;
	
	OOSetOpenGLState(OPENGL_STATE_OVERLAY);
	
	OOGL(glEnable(GL_TEXTURE_2D));
	if (sFontTexture != nullptr)  sFontTexture->apply();	// a message to nil did nothing

	OOGLBEGIN(GL_QUADS);
	{
		HeadUpDisplayUniverseGUISetGLColorFromSetting(oo::str::format(cxx_kGuiChartEconomyUColor, (size_t)eco),
													  OOColor::colorWithRed(ce1, 1.0f, 0.0f, 1.0f).get(),
													  1.0);

		// see OODrawHilightedPlanetInfo
		cx += drawCharacterQuad(23 - eco, cx, y, z, siz);	// characters 16..23 are economy symbols
		HeadUpDisplayUniverseGUISetGLColorFromSetting(oo::str::format(cxx_kGuiChartGovernmentUColor, (size_t)gov),
													  OOColor::colorWithRed(govcol[static_cast<std::size_t>(gov)*3], govcol[1+(gov*3)], govcol[2+(gov*3)], 1.0f).get(),
													  1.0);

		cx += drawCharacterQuad(gov, cx, y, z, siz) - sF6KernGovt;		// charcters 0..7 are government symbols
		HeadUpDisplayUniverseGUISetGLColorFromSetting(cxx_kGuiChartTechColor,
													  OOColor::colorWithRed(0.5, 1.0f, 1.0f, 1.0f).get(),
													  1.0);

		if (tl > 9)
		{
			// display TL clamped between 1..16, this must be a '1'!
			cx += drawCharacterQuad(49, cx, y - 2, z, siz) - sF6KernTL;
		}
		cx += drawCharacterQuad(48 + (tl % 10), cx, y - 2.0f, z, siz);
	}
	OOGLEND();
	
	(void)cx;	// Suppress "value not used" analyzer issue.
	
	OOTexture::applyNone();
	OOGL(glDisable(GL_TEXTURE_2D));
	
	OOVerifyOpenGLState();
}


void OODrawHilightedPlanetInfo(int gov, int eco, int tec, GLfloat x, GLfloat y, GLfloat z, NSSize siz)
{
	float	color[4];
	int		tl = tec + 1;
	
	NSSize	hisize;
	
	// get the physical dimensions
	hisize.height = siz.height;
	hisize.width = 0.0f;
	
	// see OODrawPlanetInfo
	hisize.width += siz.width * sGlyphWidths[23 - eco];
	hisize.width += siz.width * sGlyphWidths[gov] - 1.0;
	if (tl > 9) hisize.width += siz.width * sGlyphWidths[49] - 2.0;
	hisize.width += siz.width * sGlyphWidths[48 + (tl % 10)];
	
	OOSetOpenGLState(OPENGL_STATE_OVERLAY);
	
	OOGL(glPushAttrib(GL_CURRENT_BIT));	// save the text colour
	OOGL(glGetFloatv(GL_CURRENT_COLOR, color));	// we need the original colour's alpha.
	
	drawHighlight(x, y - 2.0f, z, hisize, color[3]);
	
	OOGL(glPopAttrib());	//restore the colour
	
	OODrawPlanetInfo(gov, eco, tec, x, y, z, siz);
	
	OOVerifyOpenGLState();
}

static void GLDrawNonlinearCascadeWeapon( GLfloat x, GLfloat y, GLfloat z, NSSize siz, Vector centre, GLfloat radius, GLfloat zoom, GLfloat alpha )
{
	Vector spacepos, scannerpos;
	GLfloat theta, phi;
	GLfloat z_factor = siz.height / siz.width;	// approx 1/4
	GLfloat y_factor = 1.0 - sqrt(z_factor);	// approx 1/2
	OOGLVector *points = (OOGLVector *)malloc(sizeof(OOGLVector)*25);
	int i, j;
	
	if (radius*radius > centre.y*centre.y)
	{
		GLfloat r0 = sqrt(radius*radius-centre.y*centre.y);
		OOGL(glColor4f(1.0, 0.5, 1.0, alpha));
		spacepos.y = 0;
		for (i = 0; i < 24; i++)
		{
			theta = i*2*M_PI/24;
			spacepos.x = centre.x + r0 * cos(theta);
			spacepos.z = centre.z + r0 * sin(theta);
			scannerpos = HeadUpDisplay::nonlinearScannerScale(spacepos, zoom, 0.5*siz.width);
			points[i].x = x + scannerpos.x;
			points[i].y = y + scannerpos.z * z_factor + scannerpos.y * y_factor;
			points[i].z = z;
		}
		spacepos.x = centre.x + r0;
		spacepos.y = 0;
		spacepos.z = centre.z;
		scannerpos = HeadUpDisplay::nonlinearScannerScale(spacepos, zoom, 0.5*siz.width);
		points[24].x = x + scannerpos.x;
		points[24].y = y + scannerpos.z * z_factor + scannerpos.y * y_factor;
		points[24].z = z;
		GLDrawPoints(points,25);
	}
	OOGL(glColor4f(0.5, 0.0, 1.0, 0.33333 * alpha));
	free(points);
	// Here, we draw a sphere distorted by the nonlinear function. We draw the sphere as a set of horizontal strips
	// The even indices of points are the points on the upper edge of the strip, while odd indices are points
	// on the bottom edge.
	points = (OOGLVector *)malloc(sizeof(OOGLVector)*50);
	spacepos.x = centre.x;
	spacepos.y = centre.y + radius;
	spacepos.z = centre.z;
	scannerpos = HeadUpDisplay::nonlinearScannerScale(spacepos, zoom, 0.5*siz.width);
	for (i = 0; i <= 24; i++)
	{
		points[2*i+1].x = x + scannerpos.x;
		points[2*i+1].y = y + scannerpos.y * y_factor + scannerpos.z * z_factor;
		points[2*i+1].z = z;
	}
	for (i = 1; i <= 24; i++)
	{
		theta = i*M_PI/24;
		for (j = 0; j <= 24; j++)
		{
			phi = j*M_PI/12;
			// copy point from bottom edge of previous strip into top edge position
			points[2*j] = points[2*j+1];

			spacepos.x = centre.x + radius * sin(theta) * cos(phi);
			spacepos.y = centre.y + radius * cos(theta);
			spacepos.z = centre.z + radius * sin(theta) * sin(phi);
			scannerpos = HeadUpDisplay::nonlinearScannerScale(spacepos, zoom, 0.5*siz.width);
			points[2*j+1].x = x + scannerpos.x;
			points[2*j+1].y = y + scannerpos.y * y_factor + scannerpos.z * z_factor;
			points[2*j+1].z = z;
		}
		GLDrawQuadStrip(points, 50);
	}
	free(points);
	return;
}

static GLfloat nonlinearScannerFunc( GLfloat distance, GLfloat zoom, GLfloat scale )
{
	GLfloat x = fabs(distance / SCANNER_MAX_RANGE);
	if (x >= 1.0)
		return scale;
	if (zoom <= 1.0)
		return scale * x;
	GLfloat c = 1 / ( zoom - 1 );
	GLfloat b = c * ( c + 1 );
	GLfloat a = c + 1;
	return scale * ( a - b / ( x + c ) );
}


static void drawScannerGrid(GLfloat x, GLfloat y, GLfloat z, NSSize siz, int v_dir, GLfloat thickness, GLfloat zoom, BOOL nonlinear, BOOL minimalistic)
{
	OOSetOpenGLState(OPENGL_STATE_OVERLAY);

	MyOpenGLView* gameView = (UNIVERSE != nullptr ? UNIVERSE->getGameView() : nullptr);

	GLfloat w1, h1;
	GLfloat ww = 0.5 * siz.width;
	GLfloat hh = 0.5 * siz.height;
	
	GLfloat km_scan;
	GLfloat hdiv;
	GLfloat wdiv;
	BOOL drawdiv = NO, drawdiv1 = NO, drawdiv5 = NO;
	
	int i, ii;
	
	OOGL(GLScaledLineWidth(2.0 * thickness));
	GLDrawOval(x, y, z, siz, 4);
	OOGL(GLScaledLineWidth(thickness)); // reset (thickness = lineWidth)
	
	OOGLBEGIN(GL_LINES);
		if (!minimalistic)
		{
			glVertex3f(x, y - hh, z);	glVertex3f(x, y + hh, z);
			glVertex3f(x - ww, y, z);	glVertex3f(x + ww, y, z);
	
			if (nonlinear)
			{
				if (nonlinearScannerFunc(4000.0, zoom, hh)-nonlinearScannerFunc(3000.0, zoom ,hh) > 2) drawdiv1 = YES;
				if (nonlinearScannerFunc(10000.0, zoom, hh)-nonlinearScannerFunc(5000.0, zoom, hh) > 2) drawdiv5 = YES;
				wdiv = ww/(0.001*SCANNER_MAX_RANGE);
				for (i = 1; 1000.0*i < SCANNER_MAX_RANGE; i++)
				{
					drawdiv = drawdiv1;
					w1 = wdiv;
					if (i % 10 == 0)
					{
						w1 = wdiv*4;
						drawdiv = YES;
						if (nonlinearScannerFunc((i+5)*1000,zoom,hh) - nonlinearScannerFunc(i*1000.0,zoom,hh)>2)
						{
							drawdiv5 = YES;
						}
						else
						{
							drawdiv5 = NO;
						}
					}
					else if (i % 5 == 0)
					{
						w1 = wdiv*2;
						drawdiv = drawdiv5;
						if (nonlinearScannerFunc((i+1)*1000,zoom,hh) - nonlinearScannerFunc(i*1000.0,zoom,hh)>2)
						{
							drawdiv1 = YES;
						}
						else
						{
							drawdiv1 = NO;
						}
					}
					if (drawdiv)
					{
						h1 = nonlinearScannerFunc(i*1000.0,zoom,hh);
						glVertex3f(x - w1, y + h1, z);	glVertex3f(x + w1, y + h1, z);
						glVertex3f(x - w1, y - h1, z);	glVertex3f(x + w1, y - h1, z);
					}
				}
			}
			else
			{
				km_scan = 0.001 * SCANNER_MAX_RANGE / zoom;	// calculate kilometer divisions
				hdiv = 0.5 * siz.height / km_scan;
				wdiv = 0.25 * siz.width / km_scan;
				if (wdiv < 4.0)
				{
					wdiv *= 2.0;
					ii = 5;
				}
				else
				{
					ii = 1;
				}
		
				for (i = ii; 2.0 * hdiv * i < siz.height; i += ii)
				{
					h1 = i * hdiv;
					w1 = wdiv;
					if (i % 5 == 0)
						w1 = w1 * 2.5;
					if (i % 10 == 0)
						w1 = w1 * 2.0;
					if (w1 > 3.5)	// don't draw tiny marks
					{
						glVertex3f(x - w1, y + h1, z);	glVertex3f(x + w1, y + h1, z);
						glVertex3f(x - w1, y - h1, z);	glVertex3f(x + w1, y - h1, z);
					}
				}
			}
		}

		double tanfov = (gameView != nullptr ? gameView->fov(YES) : 0.0f);
		GLfloat aspect = (gameView != nullptr ? gameView->getViewSize() : NSSize{}).width / (gameView != nullptr ? gameView->getViewSize() : NSSize{}).height;
		if (aspect < 4.0/3.0)
		{
			tanfov *= 0.75 * aspect;
		}
		double cosfov = 1.0/sqrt(1+tanfov*tanfov);
		double sinfov = tanfov * cosfov;

		switch (v_dir)
		{
			case VIEW_BREAK_PATTERN:
			case VIEW_GUI_DISPLAY:
			case VIEW_FORWARD:
			case VIEW_NONE:
				glVertex3f(x, y, z); glVertex3f(x - ww * sinfov, y + hh * cosfov, z);
				glVertex3f(x, y, z); glVertex3f(x + ww * sinfov, y + hh * cosfov, z);
				break;
				
			case VIEW_AFT:
				glVertex3f(x, y, z); glVertex3f(x - ww * sinfov, y - hh * cosfov, z);
				glVertex3f(x, y, z); glVertex3f(x + ww * sinfov, y - hh * cosfov, z);
				break;
				
			case VIEW_PORT:
				glVertex3f(x, y, z); glVertex3f(x - ww * cosfov, y + hh * sinfov, z);
				glVertex3f(x, y, z); glVertex3f(x - ww * cosfov, y - hh * sinfov, z);
				break;
				
			case VIEW_STARBOARD:
				glVertex3f(x, y, z); glVertex3f(x + ww * cosfov, y + hh * sinfov, z);
				glVertex3f(x, y, z); glVertex3f(x + ww * cosfov, y - hh * sinfov, z);
				break;
		}
	OOGLEND();
	
	OOVerifyOpenGLState();
}


static void DrawSpecialOval(GLfloat x, GLfloat y, GLfloat z, NSSize siz, GLfloat step, GLfloat *color4v)
{
	GLfloat			ww = 0.5 * siz.width;
	GLfloat			hh = 0.5 * siz.height;
	GLfloat			theta;
	GLfloat			delta;
	GLfloat			s;
	
	delta = step * M_PI / 180.0f;
	
	OOGLBEGIN(GL_LINE_LOOP);
		for (theta = 0.0f; theta < (2.0f * M_PI); theta += delta)
		{
			s = sin(theta);
			glColor4f(color4v[0], color4v[1], color4v[2], fabs(s * color4v[3]));
			glVertex3f(x + ww * s, y + hh * cos(theta), z);
		}
	OOGLEND();
}


/*	The beacon icons (slice 4). OOPolygonSprite's OOHUDBeaconIcon category is a free function on the
	converted sprite (ADR-0056 amendments oo-6ia4 item 3, oo-9fwb), which the sprite's
	OOHUDBeaconIcon member calls (bead oo-7ae4p: the protocol and the facades are gone; the entities
	hold their beacon drawables by the C++ interface).
*/
void OOPolygonSprite::drawHUDBeaconIconAt(NSPoint where, NSSize size, GLfloat alpha, GLfloat z)
{
	OOPolygonSpriteDrawHUDBeaconIcon(this, where, size, alpha, z);
}


void OOPolygonSpriteDrawHUDBeaconIcon(OOPolygonSprite *sprite, NSPoint where, NSSize size, GLfloat alpha, GLfloat z)
{
	GLfloat x = where.x - size.width;
	GLfloat y = where.y - 1.5 * size.height;

	GLfloat ox = x - size.width * 0.5;
	GLfloat oy = y - size.height * 0.5;
	GLfloat width = size.width * (1.0f / 6.0f);
	GLfloat height = size.height * (1.0f / 6.0f);

	OOGLPushModelView();
	OOGLTranslateModelView(make_vector(ox, oy, z));
	OOGLScaleModelView(make_vector(width, height, 1.0f));
	sprite->drawFilled();
	glColor4f(0.0, 0.0, 0.0, 0.5 * alpha);
	sprite->drawOutline();
	OOGLPopModelView();
}


OOHUDBeaconCodeIcon::OOHUDBeaconCodeIcon(const std::string &text)
{
	_text = text;
}


void OOHUDBeaconCodeIcon::drawHUDBeaconIconAt(NSPoint where, NSSize size, GLfloat /*alpha*/, GLfloat z)
{
	cxx_OODrawString(_text, where.x - 2.5 * size.width, where.y - 3.0 * size.height, z, NSMakeSize(size.width * 2, size.height * 2));
}


namespace {

void SetGLColourFromInfo(const oo::PList &info, const char *key, const GLfloat defaultColor[4], GLfloat alpha)
{
	oo::Ref<OOColor>	color;
	const oo::PList colorDesc = PListForKeyIn(info, key);
	if (!colorDesc.isNull())
	{
		color = OOColor::colorWithDescription(colorDesc);
		if (color != nullptr)
		{
			GLfloat ioColor[4];
			color->getRed(&ioColor[0], &ioColor[1], &ioColor[2], &ioColor[3]);
			GLColorWithOverallAlpha(ioColor,alpha);
			return;
		}	
	}	
	GLColorWithOverallAlpha(defaultColor,alpha);
}


void GetRGBAArrayFromInfo(const oo::PList &info, GLfloat ioColor[4])
{
	oo::Ref<OOColor>	color;

	// First, look for general colour specifier.
	const oo::PList colorDesc = PListForKeyIn(info, RGB_COLOR_KEY);
	if (!colorDesc.isNull() && info.find(ALPHA_KEY) == nullptr)
	{
		color = OOColor::colorWithDescription(colorDesc);
		if (color != nullptr)
		{
			color->getRed(&ioColor[0], &ioColor[1], &ioColor[2], &ioColor[3]);
			return;
		}
	}
	
	// Failing that, look for rgb_color and alpha.
	const oo::PList *components = info.get<oo::PList::Array>(RGB_COLOR_KEY);
	if (components != nullptr && components->count() == 3)
	{
		ioColor[0] = components->at<oo::NonNegative<float>>(0);
		ioColor[1] = components->at<oo::NonNegative<float>>(1);
		ioColor[2] = components->at<oo::NonNegative<float>>(2);
	}
	ioColor[3] = info.get<oo::NonNegative<float>>(ALPHA_KEY, ioColor[3]);
}

}	// namespace


// --- One-line sends to classes still behind facades (amendment oo-9ht.139), moved from the HUD's
// deleted facade (bead oo-mwd58).

void HeadUpDisplayUniverseGUISetGLColorFromSetting(const std::optional<std::string> &setting, OOColor *defaultValue, GLfloat alpha)
{
	UNIVERSE->getGui()->setGLColorFromSetting(setting, defaultValue, alpha);
}


// --- Sends of the reticles and waypoints (hudDrawReticleOnTarget(), hudDrawWaypoint(), hudRotateViewpointForVirtualDepth())

OOGUIScreenID HeadUpDisplayPlayerGuiScreen(PlayerEntity *player)	{ return (player != nullptr ? player->guiScreen() : OOGUIScreenID{}); }
HPVector HeadUpDisplayPlayerViewpointPosition(PlayerEntity *player)	{ return (player != nullptr ? player->viewpointPosition() : HPVector{}); }
GLfloat HeadUpDisplayPlayerWeaponRange(PlayerEntity *player)	{ return (player != nullptr ? player->getWeaponRange() : 0.0f); }
std::optional<std::string> HeadUpDisplayPlayerDialTargetName(PlayerEntity *player)	{ return (player != nullptr ? player->dialTargetName() : std::optional<std::string>()); }
double HeadUpDisplayPlayerClockTimeAdjusted(PlayerEntity *player)	{ return (player != nullptr ? player->clockTimeAdjusted() : 0.0); }
Vector HeadUpDisplayPlayerCustomViewForwardVector(PlayerEntity *player)	{ return (player != nullptr ? player->getCustomViewForwardVector() : Vector{}); }
Vector HeadUpDisplayPlayerCustomViewUpVector(PlayerEntity *player)	{ return (player != nullptr ? player->getCustomViewUpVector() : Vector{}); }
Quaternion HeadUpDisplayPlayerCustomViewQuaternion(PlayerEntity *player)	{ return (player != nullptr ? player->getCustomViewQuaternion() : Quaternion{}); }
OOMatrix HeadUpDisplayPlayerRotationMatrix(PlayerEntity *player)	{ return (player != nullptr ? player->rotationMatrix() : OOMatrix{}); }
// The members the facade's selectors forwarded to (bead oo-9ht.39.27): nil's answer for none.
bool HeadUpDisplayEntityIsShip(Entity *entity)	{ return oo::EntityIsShip(entity); }
bool HeadUpDisplayEntityIsWormhole(Entity *entity)	{ return entity != nullptr && entity->getIsWormhole(); }
bool HeadUpDisplayEntityIsVisualEffect(Entity *entity)	{ return entity != nullptr && entity->getIsVisualEffect(); }
HPVector HeadUpDisplayEntityPosition(Entity *entity)	{ return entity != nullptr ? entity->getPosition() : kZeroHPVector; }
GLfloat HeadUpDisplayEntityCollisionRadius(Entity *entity)	{ return entity != nullptr ? entity->collisionRadius() : 0.0f; }
Quaternion HeadUpDisplayEntityOrientation(Entity *entity)	{ return entity != nullptr ? entity->getOrientation() : Quaternion{}; }
std::optional<std::string> HeadUpDisplayShipScanDescription(ShipEntity *ship)	{ return (ship != nullptr ? ship->scanDescription() : std::optional<std::string>()); }
bool HeadUpDisplayShipIsCloaked(ShipEntity *ship)	{ return (ship != nullptr ? ship->isCloaked() : false); }
bool HeadUpDisplayShipIsHostileToPlayer(ShipEntity *ship)	{ return (((ship != nullptr ? ship->hasHostileTarget() : false))&&((ship != nullptr ? ship->primaryTarget() : (Entity *)nullptr) == PLAYER)); }
GLfloat *HeadUpDisplayShipScannerDisplayColor(ShipEntity *ship, BOOL isHostile, BOOL flash)	{ return (ship != nullptr ? ship->scannerDisplayColorForShip(PLAYER, isHostile, flash, (ship != nullptr ? ship->scannerDisplayColor1() : (OOColor *)nullptr), (ship != nullptr ? ship->scannerDisplayColor2() : (OOColor *)nullptr), (ship != nullptr ? ship->scannerDisplayColorHostile1() : (OOColor *)nullptr), (ship != nullptr ? ship->scannerDisplayColorHostile2() : (OOColor *)nullptr)) : (GLfloat *)nullptr); }
GLfloat *HeadUpDisplayVisualEffectScannerDisplayColor(OOVisualEffectEntity *vis, BOOL flash)	{ return (vis != nullptr ? vis->scannerDisplayColorForShip(flash, vis->scannerDisplayColor1(), vis->scannerDisplayColor2()) : (GLfloat *)nullptr); }
WORMHOLE_SCANINFO HeadUpDisplayWormholeScanInfo(WormholeEntity *wormhole)	{ return (wormhole != nullptr ? wormhole->scanInfo() : WORMHOLE_SCANINFO{}); }
double HeadUpDisplayWormholeEstimatedArrivalTime(WormholeEntity *wormhole)	{ return (wormhole != nullptr ? wormhole->estimatedArrivalTime() : 0.0); }
double HeadUpDisplayWormholeExpiryTime(WormholeEntity *wormhole)	{ return (wormhole != nullptr ? wormhole->expiryTime() : 0.0); }
OOTimeAbsolute HeadUpDisplayUniverseGetTime()	{ return (UNIVERSE != nullptr ? UNIVERSE->getTime() : 0.0); }
const oo::PList *HeadUpDisplayUniverseDescriptions()	{ return (UNIVERSE != nullptr ? UNIVERSE->descriptions() : nullptr); }
OOViewID HeadUpDisplayUniverseViewDirection()	{ return (UNIVERSE != nullptr ? UNIVERSE->getViewDirection() : OOViewID{}); }
Entity *HeadUpDisplayUniverseFirstEntityTargetedByPlayer()	{ return (UNIVERSE != nullptr ? UNIVERSE->firstEntityTargetedByPlayer() : nullptr); }	// its object (the universe answers the C++ entity, bead oo-9ht.39.26)
Entity *HeadUpDisplayUniverseFirstEntityTargetedByPlayerPrecisely()	{ return (UNIVERSE != nullptr ? UNIVERSE->firstEntityTargetedByPlayerPrecisely() : nullptr); }
