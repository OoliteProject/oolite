/*

Universe.m

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


#include "Universe.h"
#include "oofnd/Process.hpp"
#include "oofnd/Date.hpp"
#include "oofnd/Log.hpp"
#include "oofnd/Defaults.hpp"
#include "oofnd/objc/OOAssert.h"
#include "MyOpenGLView.h"
#include "GameController.h"
#include "ResourceManager.h"
#include "AI.h"
#include "GuiDisplayGen.h"
#include "HeadUpDisplay.h"
#include "OOSound.h"
#include "OOColor.h"
#include "OOCacheManager.h"
#include "OOStringExpander.h"
#include "OOStringParsing.h"
#include "OOConstToString.h"
#include "OOConstToJSString.h"
#include "OOOpenGLExtensionManager.h"
#include "OOOpenGLMatrixManager.h"
#include "OOCPUInfo.h"
#include "OOMaterial.h"
#include "OOTexture.h"
#include "OORoleSet.h"
#include "OOShipGroup.h"
#include "OODebugSupport.h"

#include "Octree.h"
#include "CollisionRegion.h"
#include "OOGraphicsResetManager.h"
#include "OODebugSupport.h"
#include "OOEntityFilterPredicate.h"

#include "OOCharacter.h"
#include "OOShipRegistry.h"
#include "OOProbabilitySet.h"
#include "OOEquipmentType.h"
#include "OOShipLibraryDescriptions.h"

#include "PlayerEntity.h"
#include "PlayerEntityContracts.h"
#include "PlayerEntityControls.h"
#include "PlayerEntityScriptMethods.h"
#include "StationEntity.h"
#include "DockEntity.h"
#include "SkyEntity.h"
#include "DustEntity.h"
#include "OOPlanetEntity.h"
#include "OOPlanetDrawable.h"	// oo::makeRef<OOPlanetEntity>() destroys its drawables (bead oo-9ht.129)
#include "OOVisualEffectEntity.h"
#include "OOWaypointEntity.h"
#include "OOSunEntity.h"
#include "WormholeEntity.h"
#include "OOBreakPatternEntity.h"
#include "ShipEntityAI.h"
#include "ProxyPlayerEntity.h"
#include "OORingEffectEntity.h"
#include "OOLightParticleEntity.h"
#include "OOFlashEffectEntity.h"
#include "OOExplosionCloudEntity.h"
#include "OOSystemDescriptionManager.h"
#include "OOMusicController.h"
#include "OOAsyncWorkManager.h"
#include "OODebugFlags.h"
#include "OODebugStandards.h"
#include "OOLoggingExtended.h"
#include "OOJSEngineTimeManagement.h"
#include "OOJoystickManager.h"
#include "OOScriptTimer.h"
#include "OOJSScript.h"
#include "OOJSFrameCallbacks.h"
#include "OOJSPopulatorDefinition.h"
#include "OOOpenGL.h"
#include "OOShaderProgram.h"
#include "oofnd/objc/OOException.h"
#include "OOObjCPList.h"


#if OO_LOCALIZATION_TOOLS
#include "OOConvertSystemDescriptions.h"
#include "OOPListGameTypes.h"
#include "oofnd/FileSystem.hpp"
#include "oofnd/PListParsing.hpp"
#include "oofnd/String.hpp"
#include "oofnd/Scanner.hpp"
#endif

enum
{
	DEMO_FLY_IN			= 101,
	DEMO_SHOW_THING,
	DEMO_FLY_OUT
};

#define DEMO2_VANISHING_DISTANCE	650.0
#define DEMO2_FLY_IN_STAGE_TIME	0.4


#define MAX_NUMBER_OF_ENTITIES				200
#define STANDARD_STATION_ROLL				0.4
// currently twice scanner radius
#define LANE_WIDTH			51200.0

static const char * const kOOLogUniversePopulateError			= "universe.populate.error";
static const char * const kOOLogUniversePopulateWitchspace	= "universe.populate.witchspace";
static const char * const kOOLogEntityVerificationError		= "entity.linkedList.verify.error";
static const char * const kOOLogEntityVerificationRebuild		= "entity.linkedList.verify.rebuild";



const GLfloat framebufferQuadVertices[] = {
	// positions  // texture coords
	 1.0f,  1.0f, 1.0f, 1.0f, // top right
	 1.0f, -1.0f, 1.0f, 0.0f, // bottom right
	-1.0f, -1.0f, 0.0f, 0.0f, // bottom left
	-1.0f,  1.0f, 0.0f, 1.0f  // top left 
};
const GLuint framebufferQuadIndices[] = {
	0, 1, 3, // first triangle
	1, 2, 3  // second triangle
};


Universe *gSharedUniverse = nil;

extern Entity *gOOJSPlayerIfStale;
Entity *gOOJSPlayerIfStale = nullptr;	// the player's C++ entity (bead oo-9ht.39.25)


static BOOL MaintainLinkedLists(Universe* uni);
namespace { OOINLINE BOOL EntityInRange(HPVector p1, Entity *e2, float range); }	// (the C++ entity since bead oo-9ht.39.26)

/* TODO: route calculation is really slow - find a way to safely enable this */
#undef CACHE_ROUTE_FROM_SYSTEM_RESULTS


namespace {

// The saved detailLevel preference as an OOGraphicsDetail. 0-3 are the levels themselves; any other
// number becomes DETAIL_LEVEL_MAXIMUM, which is what -setDetailLevelDirectly: made of it: the bare
// cast this replaces handed the enum (underlying type unsigned int on this toolchain) an
// out-of-range value, a negative one as a large unsigned number, and the setter clamped anything
// >= DETAIL_LEVEL_MAXIMUM to it. Clamping as an integer means the enum only ever holds one of its
// own values (the same idiom as OOSystemLayerFromNumber, bead oo-2eby).
OOGraphicsDetail OOGraphicsDetailFromNumber(unsigned int number)
{
	return (number > DETAIL_LEVEL_MAXIMUM) ? DETAIL_LEVEL_MAXIMUM : static_cast<OOGraphicsDetail>(number);
}


// Defined with the configuration readers and the shipyard helpers below.
oo::PList PListForKeyIn(const oo::PList &dict, std::string_view key);
std::string ExpandKeyWith(const std::string &key, const char *name, const oo::PList &value);


// -addObject: on a set of held entities (identity, as Entity keeps NSObject's -isEqual:; bead
// oo-9ht.39.26): once each, in the order added, the entity's object retained once. (Its form over
// Objective-C object references had no caller left and went with them, bead oo-dbz.2.)
void AddIfAbsent(std::vector<oo::EntityHold> &entities, Entity *entity)
{
	if (std::find(entities.begin(), entities.end(), entity) == entities.end())  entities.emplace_back(entity);
}


// An autoreleased list of held entities (bead oo-9ht.39.26): each hold's reference to the entity's
// object goes to the autorelease pool (retained, autoreleased, then the hold's own released),
// which releases it when it drains (the list itself released them then). The list is left empty.
void AutoreleaseAll(std::vector<oo::EntityHold> &entities)
{
	for (const oo::EntityHold &entity : entities)  oo::AutoreleaseEntity(oo::RetainEntity(entity.get()));
	entities.clear();
}


// A script-event argument: the string, or null for nullopt (what oo::NSStringOrNil's nil gave).
oo::PList StringOrNull(const std::optional<std::string> &string)
{
	return string.has_value() ? oo::PList(*string) : oo::PList();
}


// A script value's -doubleValue / -floatValue / -intValue, as the NSString or NSNumber it was
// answered them (anything else, which does not answer them, reads 0 as nil did).
double ScriptValueDouble(const oo::PList &value)
{
	if (const std::string *text = value.getIf<std::string>())  return oo::plist_get::doubleValue(oo::utf8ToUtf16(*text));
	return value.doubleValue();
}


float ScriptValueFloat(const oo::PList &value)
{
	if (const std::string *text = value.getIf<std::string>())  return static_cast<float>(oo::plist_get::doubleValue(oo::utf8ToUtf16(*text)));
	return value.isNumber() ? oo::plist_get::numberFloatValue(value) : 0.0f;
}


int ScriptValueInt(const oo::PList &value)
{
	if (const std::string *text = value.getIf<std::string>())  return oo::plist_get::intValue(oo::utf8ToUtf16(*text));
	return static_cast<int>(value.int64Value());
}


// -removeObjectAtIndex:0 on the wormhole list: an empty list raised a range exception.
void RemoveFirstWormhole(std::vector<oo::EntityHold> &wormholes)
{
	if (wormholes.empty())
	{
		OORaiseException(OORangeException, "Index 0 is out of range 0 (in 'removeObjectAtIndex:')");
	}
	wormholes.erase(wormholes.begin());
}


/*	[beaconCode rangeOfString:code options:NSCaseInsensitiveSearch].location != NSNotFound: the
	units compared lowercased (oo::str::lowercase maps unit for unit, so a byte search of the two
	lowercased strings finds the same places); an empty code is never found; a nil beacon code
	answered a zeroed range from messaging nil, location 0, which counted as found.
*/
bool BeaconCodeMatches(const std::optional<std::string> &beaconCode, const std::string &code)
{
	if (!beaconCode.has_value())  return true;
	if (code.empty())  return false;
	return oo::str::lowercase(*beaconCode).find(oo::str::lowercase(code)) != std::string::npos;
}

}


//------------------------------------------------------------------------------------//
//	The class (slice 1 of docs/phases/3-slices/Universe.md and the slices after it): Universe's
//	members. The Objective-C facade's initialiser and -dealloc are newUniverse() and the destructor
//	(bead oo-ql9rn).

Universe::Universe()
{
}


// The facade's -dealloc: the body, then the members go (as the runtime released the ivars).
Universe::~Universe()
{
	dealloc();
}


Universe *Universe::newUniverse(::MyOpenGLView *inGameView)
{
	/*	The universe first: one refused below is released at once, and its teardown runs the whole
		body as the facade's -dealloc did.
	*/
	Universe *universe = new Universe();

	if (gSharedUniverse != nullptr)
	{
		universe->release();
		OORaiseException(OOInternalInconsistencyException, "%s: expected only one Universe to exist at a time.", "-[Universe(OOObjCBridge) initWithGameView:]");
	}

	OO_DEBUG_PROGRESS("Universe initWithGameView:");

	universe->initWithGameView(inGameView);
	return universe;
}


/*	-initWithGameView: after [super init]: newUniverse() made the universe and checked that it is
	the only one. The body is the method's.
*/
void Universe::initWithGameView(::MyOpenGLView *inGameView)
{
	_doingStartUp = YES;

	OOInitReallyRandom(oo::date::timeIntervalSinceReferenceDate() * 1e9);

	oo::Defaults &prefs = oo::Defaults::standard();

	// prefs value no longer used - per save game but startup needs to
	// be non-strict
	useAddOns = std::string(SCENARIO_OXP_DEFINITION_ALL);

	setGameView(inGameView);
	gSharedUniverse = this;

	allPlanets.clear();
	allStations.clear();

	OOCPUInfoInit();
	OOJoystickManager::sharedStickHandler();

	// init OpenGL extension manager (must be done before any other threads might use it)
	OOOpenGLExtensionManager::sharedManager();
	setDetailLevelDirectly(OOGraphicsDetailFromNumber(prefs.object("detailLevel").isNull() ? OOOpenGLExtensionManager::sharedManager()->defaultDetailLevel() : static_cast<unsigned int>(prefs.integerForKey("detailLevel"))));

	initTargetFramebufferWithViewSize((gameView != nullptr ? gameView->backingViewSize() : NSSize{}));

	::OOMaterial::setUp();

	// Preload cache
	OOCacheManager::sharedCache();

#if OOLITE_SPEECH_SYNTH
	OO_LOG("speech.synthesis", "Spoken messages are {}.", (prefs.boolForKey("speech_on") ? "on" : "off"));
#endif

	// init the Resource Manager
	ResourceManager::setUseAddOns(useAddOns);	// also logs the paths if changed

	// Set up the internal game strings
	loadDescriptions();
	// DESC expansion is now possible!

	// load starting saves
	loadScenarios();

	autoSave = prefs.boolForKey("autosave");
	wireframeGraphics = prefs.boolForKey("wireframe-graphics");
	doProcedurallyTexturedPlanets = prefs.object("procedurally-textured-planets").isNull() ? YES : prefs.boolForKey("procedurally-textured-planets");
	if (inGameView != nullptr)  inGameView->setMsaa(prefs.boolForKey("anti-aliasing"));
	OO_LOG("MSAA.setup", "Multisample anti-aliasing {}requested.", (inGameView != nullptr ? inGameView->msaa() : false) ? "" : "not ");
	if (inGameView != nullptr)  inGameView->setFov(OOClamp_0_max_f(prefs.object("fov-value").isNull() ? 57.2f : prefs.floatForKey("fov-value"), MAX_FOV_DEG), NO);
	if ((inGameView != nullptr ? inGameView->fov(NO) : 0.0f) < MIN_FOV_DEG)  { if (inGameView != nullptr)  inGameView->setFov(MIN_FOV_DEG, NO); }

 	setECMVisualFXEnabled(prefs.object("ecm-visual-fx").isNull() ? YES : prefs.boolForKey("ecm-visual-fx"));

	// Set up speech synthesizer.
#if OOLITE_SPEECH_SYNTH
#if OOLITE_MAC_OS_X
	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0),
	^{
		/*
			NSSpeechSynthesizer can take over a second on an SSD and several
			seconds on an HDD for a cold start, and a third of a second upward
			for a warm start. There are no particular thread safety consider-
			ations documented for NSSpeechSynthesizer, so I'm assuming the
			default one-thread-at-a-time access rule applies.
			-- Ahruman 2012-09-13
		*/
		OO_LOG("speech.setup.begin", "Starting to set up speech synthesizer.");
		NSSpeechSynthesizer *synth = [[NSSpeechSynthesizer alloc] init];
		OO_LOG("speech.setup.end", "Finished setting up speech synthesizer.");
		speechSynthesizer = synth;
	});
#elif OOLITE_ESPEAK
	int volume = ::OOSound::masterVolume() * 100;
	espeak_SetParameter(espeakPUNCTUATION, espeakPUNCT_NONE, 0);
	espeak_SetParameter(espeakVOLUME, volume, 0);
	espeak_voices = espeak_ListVoices(NULL);
	for (espeak_voice_count = 0;
	     espeak_voices[espeak_voice_count];
	     ++espeak_voice_count)
		/**/;
#endif
#endif

	::GameController::sharedController()->logProgress(OO_DESC("loading-ships"));
	// Load ship data

	OOShipRegistry::sharedRegistry();

	entities.reserve(MAX_NUMBER_OF_ENTITIES);

	::GameController::sharedController()->logProgress(cxx_OOExpandKeyRandomized("loading-miscellany").value_or(std::string()));

	// this MUST have the default no. of rows else the GUI_ROW macros in PlayerEntity.h need modification
	gui = oo::makeRef<GuiDisplayGen>();
	comm_log_gui = oo::makeRef<GuiDisplayGen>();

	missiontext = ResourceManager::dictionaryFromFilesNamed("missiontext.plist", std::string("Config"), YES);

	waypoints.clear();

	setUpSettings();

	// can't do this here as it might lock an OXZ open
	// [self preloadSounds];	// Must be after setUpSettings.

	// Preload particle effect textures:
	::OOLightParticleEntity::setUpTexture();
	::OOFlashEffectEntity::setUpTexture();


	// set up cargopod templates
	setUpCargoPods();

	::PlayerEntity *player = ::PlayerEntity::sharedPlayer();
	player->deferredInit();
	addEntity(player);

	if (player != nullptr)  player->setStatus(STATUS_START_GAME);
	if (player != nullptr)  player->setShowDemoShips(YES);

	setUpInitialUniverse();

	universeRegion = oo::makeRef<::CollisionRegion>(::CollisionRegion::AsUniverse {});
	entitiesDeadThisUpdate.clear();
	framesDoneThisUpdate = 0;
	drawCounter = 0;

	::GameController::sharedController()->logProgress(OO_DESC("initializing-debug-support"));
	OOInitDebugSupport();

	::GameController::sharedController()->logProgress(OO_DESC("running-scripts"));
	if (player != nullptr)  player->completeSetUp();

	::GameController::sharedController()->logProgress(OO_DESC("populating-space"));
	populateNormalSpace();

	::GameController::sharedController()->logProgress(cxx_OOExpandKeyRandomized("loading-miscellany").value_or(std::string()));

#if OO_LOCALIZATION_TOOLS
	runLocalizationTools();
#if DEBUG_GRAPHVIZ
	dumpDebugGraphViz();
#endif
#endif

	if (player != nullptr)  player->startUpComplete();
	_doingStartUp = NO;
}


/*	-dealloc's body, run by the destructor (it was the facade's, bead oo-ql9rn deleted the facade,
	Universe+ObjCBridge.mm): what the universe still owns (the property lists, the names) is released
	then, as the runtime released the ivars after -dealloc.
*/
void Universe::dealloc()
{
	gSharedUniverse = nil;

	currentMessage.reset();

	gui = nullptr;
	message_gui = nullptr;
	comm_log_gui = nullptr;
	replacedGuis.clear();

	entities.clear();

	commodities = nullptr;
	replacedCommodities = nullptr;

	customSounds = oo::PList();
	globalSettings = oo::PList();
	systemManager = nullptr;
	replacedSystemManager = nullptr;
	demo_ships = oo::PList();
	screenBackgrounds = oo::PList();
	if (gameView != nullptr)  gameView->release();
	allPlanets.clear();
	allStations.clear();

	activeWormholes.clear();
	characterPool.clear();
	replacedCharacterPool.clear();
	universeRegion = nullptr;

	_firstBeacon = nullptr;
	_lastBeacon = nullptr;
	waypoints.clear();

	unsigned i;
	for (i = 0; i < 256; i++)  system_names[i].reset();

	entitiesDeadThisUpdate.clear();

	OOCacheManager::sharedCache()->flush();

#if OOLITE_SPEECH_SYNTH
	speechArray = oo::PList();
#if OOLITE_MAC_OS_X
	[speechSynthesizer release];
#elif OOLITE_ESPEAK
	espeak_Cancel();
#endif
#endif

	deleteOpenGLObjects();
}


// Flags needed when JS reset fails.
static int JSResetFlags = 0;


// track the position and status of the lights
static BOOL		object_light_on = NO;
static BOOL		demo_light_on = NO;
static			GLfloat sun_off[4] = {0.0, 0.0, 0.0, 1.0};
static GLfloat	demo_light_position[4] = { DEMO_LIGHT_POSITION, 1.0 };

#define DOCKED_AMBIENT_LEVEL	0.2f	// Was 0.05, 'temporarily' set to 0.2.
#define DOCKED_ILLUM_LEVEL		0.7f
static GLfloat	docked_light_ambient[4]	= { DOCKED_AMBIENT_LEVEL, DOCKED_AMBIENT_LEVEL, DOCKED_AMBIENT_LEVEL, 1.0f };
static GLfloat	docked_light_diffuse[4]	= { DOCKED_ILLUM_LEVEL, DOCKED_ILLUM_LEVEL, DOCKED_ILLUM_LEVEL, 1.0f };	// white
static GLfloat	docked_light_specular[4]	= { DOCKED_ILLUM_LEVEL, DOCKED_ILLUM_LEVEL, DOCKED_ILLUM_LEVEL * 0.75f, (GLfloat) 1.0f };	// yellow-white

// Weight of sun in ambient light calculation. 1.0 means only sun's diffuse is used for ambient, 0.0 means only sky colour is used.
// TODO: considering the size of the sun and the number of background stars might be worthwhile. -- Ahruman 20080322
#define SUN_AMBIENT_INFLUENCE		0.75
// How dark the default ambient level of 1.0 will be
#define SKY_AMBIENT_ADJUSTMENT		0.0625


namespace {

std::optional<std::string> OptionalStringIn(const oo::PList &dict, std::string_view key);	// defined with the other configuration readers below


// The demo ship entry at <index>, <subindex> of the demo list: null where the old array /
// dictionary lookup chain gave nil.
oo::PList DemoShipEntry(const oo::PList &demoShips, NSUInteger index, NSUInteger subindex)
{
	const oo::PList *subList = demoShips.at(index);
	const oo::PList *entry = (subList != nullptr && subList->isArray()) ? subList->at(subindex) : nullptr;
	return (entry != nullptr && entry->isDict()) ? *entry : oo::PList();
}


// -count of the demo class at <index> (0 where it was nil).
NSUInteger DemoClassCount(const oo::PList &demoShips, NSUInteger index)
{
	const oo::PList *subList = demoShips.at(index);
	return (subList != nullptr) ? subList->count() : 0;
}


// The class of the first ship of the demo class at <index>; "" where it was nil (oo::StdString(nil)).
std::string DemoClassAt(const oo::PList &demoShips, NSUInteger index)
{
	return OptionalStringIn(DemoShipEntry(demoShips, index, 0), kOODemoShipClass).value_or(std::string());
}


// A string setting of the library entry, <fallback> where absent; a null entry answered nil.
std::optional<std::string> LibrarySetting(const oo::PList &settings, std::string_view key, const char *fallback)
{
	if (settings.isNull())  return std::nullopt;
	const std::optional<std::string> value = OptionalStringIn(settings, key);
	if (value.has_value() || fallback == nullptr)  return value;
	return std::string(fallback);
}


// cxx_OOExpand(text).
std::optional<std::string> ExpandText(const std::string &text)
{
	return cxx_OOExpand(text);
}


// The DESC(descKey) format given cxx_OOExpand(override): a nil expansion printed "(null)".
std::string CustomLibraryText(const char *descKey, const std::string &override)
{
	const std::optional<std::string> expanded = ExpandText(override);
	return oo::str::formatRuntime(cxx_OOLookUpDescriptionPRIV(descKey), { expanded.has_value() ? oo::str::FormatArg(*expanded) : oo::str::FormatArg::null() });
}


// +arrayWithObjects:field1, field2, field3, nil: the fields up to the first nil.
std::vector<std::string> FieldsUpToNil(std::initializer_list<std::optional<std::string>> fields)
{
	std::vector<std::string> result;
	for (const std::optional<std::string> &field : fields)
	{
		if (!field.has_value())  break;
		result.push_back(*field);
	}
	return result;
}



BOOL IsCandidateMainStationPredicate(Entity *entity, void * /*parameter*/)
{
	return entity->getIsStation() && !entity->isExplicitlyNotMainStation;	// [entity isStation]
}


BOOL IsFriendlyStationPredicate(Entity *entity, void *parameter)
{
	return entity->getIsStation() && !oo::ToShip(entity)->isHostileTo(static_cast<Entity *>(parameter));	// the C++ entity since bead oo-9ht.39.26	// [entity isStation], -isHostileTo:
}

}	// namespace	(the two predicates joined it when their signatures changed, bead oo-9ht.39.23: misc-use-anonymous-namespace)


#define PROFILE_SHIP_SELECTION 0


// global rotation matrix definitions
static const OOMatrix	fwd_matrix =
						{{
							{ 1.0f,  0.0f,  0.0f,  0.0f },
							{ 0.0f,  1.0f,  0.0f,  0.0f },
							{ 0.0f,  0.0f,  1.0f,  0.0f },
							{ 0.0f,  0.0f,  0.0f,  1.0f }
						}};
static const OOMatrix	aft_matrix =
						{{
							{-1.0f,  0.0f,  0.0f,  0.0f },
							{ 0.0f,  1.0f,  0.0f,  0.0f },
							{ 0.0f,  0.0f, -1.0f,  0.0f },
							{ 0.0f,  0.0f,  0.0f,  1.0f }
						}};
static const OOMatrix	port_matrix =
						{{
							{ 0.0f,  0.0f, -1.0f,  0.0f },
							{ 0.0f,  1.0f,  0.0f,  0.0f },
							{ 1.0f,  0.0f,  0.0f,  0.0f },
							{ 0.0f,  0.0f,  0.0f,  1.0f }
						}};
static const OOMatrix	starboard_matrix =
						{{
							{ 0.0f,  0.0f,  1.0f,  0.0f },
							{ 0.0f,  1.0f,  0.0f,  0.0f },
							{-1.0f,  0.0f,  0.0f,  0.0f },
							{ 0.0f,  0.0f,  0.0f,  1.0f }
						}};


static BOOL MaintainLinkedLists(Universe *uni)
{
	OOCParameterAssert(uni != NULL);
	BOOL result = YES;
	
	// DEBUG check for loops and short lists
	if (uni->n_entities > 0)
	{
		int n;
		Entity	*checkEnt, *last;	// C++ parts (bead oo-9ht.39.4)
		
		last = nil;
		
		n = uni->n_entities;
		checkEnt = uni->x_list_start;
		while ((n--)&&(checkEnt))
		{
			last = checkEnt;
			checkEnt = checkEnt->x_next;
		}
		if ((checkEnt)||(n > 0))
		{
#ifndef NDEBUG
			OO_LOG(kOOLogEntityVerificationError, "Broken x_next {} list ({}) ***", oo::EntityDescription(uni->x_list_start), n);
#endif
			result = NO;
		}
		
		n = uni->n_entities;
		checkEnt = last;
		while ((n--)&&(checkEnt))	checkEnt = checkEnt->x_previous;
		if ((checkEnt)||(n > 0))
		{
#ifndef NDEBUG
			OO_LOG(kOOLogEntityVerificationError, "Broken x_previous {} list ({}) ***", oo::EntityDescription(uni->x_list_start), n);
#endif
			if (result)
			{
#ifndef NDEBUG
				OO_LOG(kOOLogEntityVerificationRebuild, "{}", "REBUILDING x_previous list from x_next list");
#endif
				checkEnt = uni->x_list_start;
				checkEnt->x_previous = nil;
				while (checkEnt->x_next)
				{
					last = checkEnt;
					checkEnt = checkEnt->x_next;
					checkEnt->x_previous = last;
				}
			}
		}
		
		n = uni->n_entities;
		checkEnt = uni->y_list_start;
		while ((n--)&&(checkEnt))
		{
			last = checkEnt;
			checkEnt = checkEnt->y_next;
		}
		if ((checkEnt)||(n > 0))
		{
#ifndef NDEBUG
			OO_LOG(kOOLogEntityVerificationError, "Broken *** broken y_next {} list ({}) ***", oo::EntityDescription(uni->y_list_start), n);
#endif
			result = NO;
		}
		
		n = uni->n_entities;
		checkEnt = last;
		while ((n--)&&(checkEnt))	checkEnt = checkEnt->y_previous;
		if ((checkEnt)||(n > 0))
		{
#ifndef NDEBUG
			OO_LOG(kOOLogEntityVerificationError, "Broken y_previous {} list ({}) ***", oo::EntityDescription(uni->y_list_start), n);
#endif
			if (result)
			{
#ifndef NDEBUG
				OO_LOG(kOOLogEntityVerificationRebuild, "{}", "REBUILDING y_previous list from y_next list");
#endif
				checkEnt = uni->y_list_start;
				checkEnt->y_previous = nil;
				while (checkEnt->y_next)
				{
					last = checkEnt;
					checkEnt = checkEnt->y_next;
					checkEnt->y_previous = last;
				}
			}
		}
		
		n = uni->n_entities;
		checkEnt = uni->z_list_start;
		while ((n--)&&(checkEnt))
		{
			last = checkEnt;
			checkEnt = checkEnt->z_next;
		}
		if ((checkEnt)||(n > 0))
		{
#ifndef NDEBUG
			OO_LOG(kOOLogEntityVerificationError, "Broken z_next {} list ({}) ***", oo::EntityDescription(uni->z_list_start), n);
#endif
			result = NO;
		}
		
		n = uni->n_entities;
		checkEnt = last;
		while ((n--)&&(checkEnt))	checkEnt = checkEnt->z_previous;
		if ((checkEnt)||(n > 0))
		{
#ifndef NDEBUG
			OO_LOG(kOOLogEntityVerificationError, "Broken z_previous {} list ({}) ***", oo::EntityDescription(uni->z_list_start), n);
#endif
			if (result)
			{
#ifndef NDEBUG
				OO_LOG(kOOLogEntityVerificationRebuild, "{}", "REBUILDING z_previous list from z_next list");
#endif
				checkEnt = uni->z_list_start;
				OOCAssert(checkEnt != nil, "Expected z-list to be non-empty.");	// Previously an implicit assumption. -- Ahruman 2011-01-25
				checkEnt->z_previous = nil;
				while (checkEnt->z_next)
				{
					last = checkEnt;
					checkEnt = checkEnt->z_next;
					checkEnt->z_previous = last;
				}
			}
		}
	}
	
	if (!result)
	{
#ifndef NDEBUG
		OO_LOG(kOOLogEntityVerificationRebuild, "{}", "Rebuilding all linked lists from scratch");
#endif
		const std::vector<oo::EntityHold> allEntities = uni->entities;	// a snapshot, as the enumeration was
		uni->x_list_start = nil;
		uni->y_list_start = nil;
		uni->z_list_start = nil;

		Entity *ent = nullptr;
		for (const oo::EntityHold &entry : allEntities)
		{
			ent = entry.get();
			ent->x_next = nil;
			ent->x_previous = nil;
			ent->y_next = nil;
			ent->y_previous = nil;
			ent->z_next = nil;
			ent->z_previous = nil;
			ent->addToLinkedLists();	// [ent addToLinkedLists]
		}
	}
	
	return result;
}


namespace {
OOINLINE BOOL EntityInRange(HPVector p1, Entity *e2, float range)
{
	if (range < 0)  return YES;
	float cr = range + e2->collision_radius;
	return HPdistance2(e2->position,p1) < cr * cr;
}
}	// namespace


namespace {

std::optional<std::string> OptionalStringAt(const oo::PList &array, std::size_t index);	// defined with the configuration readers below
std::optional<std::string> OptionalStringIn(const oo::PList &dict, std::string_view key);
std::string ExpandKey(const std::string &key);	// defined with the shipyard helpers below


// -[currentMessage isEqual:text]: both present and equal (a nil receiver or argument answered NO).
bool SameMessage(const std::optional<std::string> &current, const std::optional<std::string> &text)
{
	return current.has_value() && text.has_value() && *current == *text;
}

}	// namespace


namespace {

// Makes each assignment of a Universe's _descriptions distinguishable (see -cxx_descriptionsGeneration).
unsigned sDescriptionsGeneration = 0;


// +dictionaryWithContentsOfFile: of the dictionary class: the file's property list if it is a
// dictionary, else (missing, unreadable, unparsable, another kind) a null PList. As ResourceManager.mm.
oo::PList DictionaryWithContentsOfFile(const std::string &path)
{
	const auto data = oo::fs::readFile(oo::fs::pathFromUTF8(path));
	if (!data)  return oo::PList();
	auto plist = oo::parsePropertyListData(data->stringView());
	if (!plist || !plist->isDict())  return oo::PList();
	return std::move(*plist);
}


/*	A string element of an array, nullopt where oo_stringAtIndex: gave nil (past the end, or
	neither a string nor a number; a number reads as its -stringValue).
*/
std::optional<std::string> OptionalStringAt(const oo::PList &array, std::size_t index)
{
	const oo::PList *value = array.at(index);
	if (value == nullptr || !(value->isString() || value->isNumber()))  return std::nullopt;
	return array.at<std::string>(index);
}


/*	A string from a configuration dictionary, nullopt where oo_stringForKey: gave nil (the key is
	absent, or its value is neither a string nor a number; a number reads as its -stringValue).
*/
std::optional<std::string> OptionalStringIn(const oo::PList &dict, std::string_view key)
{
	const oo::PList *value = dict.find(key);
	if (value == nullptr || !(value->isString() || value->isNumber()))  return std::nullopt;
	return dict.get<std::string>(key);
}


/*	A configuration value as -objectForKey: gave it, a null PList where that gave nil (the key is
	absent), for +[OOColor cxx_colorWithDescription:] (null gives nil, as nil did) and Object nodes.
*/
oo::PList PListForKeyIn(const oo::PList &dict, std::string_view key)
{
	const oo::PList *value = dict.find(key);
	return (value != nullptr) ? *value : oo::PList();
}


// get<Vector> / get<HPVector>: OOVectorFromPList / OOHPVectorFromPList of the
// value; the zero vector for a null configuration (messaging nil).
Vector VectorIn(const oo::PList &dict, std::string_view key, Vector fallback)
{
	if (dict.isNull())  return kZeroVector;
	return OOVectorFromPList(dict.find(key), fallback);
}


HPVector HPVectorIn(const oo::PList &dict, std::string_view key, HPVector fallback)
{
	if (dict.isNull())  return kZeroHPVector;
	return OOHPVectorFromPList(dict.find(key), fallback);
}


// What %@ printed for a string that may be nil.
std::string TextOrNull(const std::optional<std::string> &text)
{
	return text.has_value() ? *text : std::string("(null)");
}


// An equipment entry's extra-info dictionary: the dictionary, or nullptr where the old read gave nil.
const oo::PList *EquipmentExtraInfo(const oo::PList &item)
{
	return item.at<oo::PList::Dict>(EQUIPMENT_EXTRA_INFO_INDEX);
}


// -[nil oo_unsignedLongLongForKey:defaultValue:] was 0, not the fallback.
unsigned long long ExtraInfoValue(const oo::PList *extra, std::string_view key, unsigned long long fallback)
{
	return (extra != nullptr) ? extra->get<unsigned long long>(key, fallback) : 0;
}


// equipment.plist order: explicit sort_order, then tech level, then price (ties keep file order).
bool equipmentSort(const oo::PList &one, const oo::PList &two)
{
	unsigned long long comp1 = ExtraInfoValue(EquipmentExtraInfo(one), "sort_order", 1000);
	unsigned long long comp2 = ExtraInfoValue(EquipmentExtraInfo(two), "sort_order", 1000);
	if (comp1 != comp2)  return comp1 < comp2;

	comp1 = one.at<unsigned long long>(EQUIPMENT_TECH_LEVEL_INDEX);
	comp2 = two.at<unsigned long long>(EQUIPMENT_TECH_LEVEL_INDEX);
	if (comp1 != comp2)  return comp1 < comp2;

	comp1 = one.at<unsigned long long>(EQUIPMENT_PRICE_INDEX);
	comp2 = two.at<unsigned long long>(EQUIPMENT_PRICE_INDEX);
	return comp1 < comp2;
}


// As equipmentSort, but purchase_sort_order (falling back to sort_order) first.
bool equipmentSortOutfitting(const oo::PList &one, const oo::PList &two)
{
	const oo::PList *extra1 = EquipmentExtraInfo(one);
	const oo::PList *extra2 = EquipmentExtraInfo(two);
	unsigned long long comp1 = ExtraInfoValue(extra1, "purchase_sort_order", ExtraInfoValue(extra1, "sort_order", 1000));
	unsigned long long comp2 = ExtraInfoValue(extra2, "purchase_sort_order", ExtraInfoValue(extra2, "sort_order", 1000));
	if (comp1 != comp2)  return comp1 < comp2;

	comp1 = one.at<unsigned long long>(EQUIPMENT_TECH_LEVEL_INDEX);
	comp2 = two.at<unsigned long long>(EQUIPMENT_TECH_LEVEL_INDEX);
	if (comp1 != comp2)  return comp1 < comp2;

	comp1 = one.at<unsigned long long>(EQUIPMENT_PRICE_INDEX);
	comp2 = two.at<unsigned long long>(EQUIPMENT_PRICE_INDEX);
	return comp1 < comp2;
}


// A string field of equipment entry j (nullopt where the old nested read gave nil).
std::optional<std::string> EquipmentItemString(const oo::PList &equipment, std::size_t j, std::size_t index)
{
	const oo::PList *item = equipment.at<oo::PList::Array>(j);
	return (item != nullptr) ? OptionalStringAt(*item, index) : std::nullopt;
}


// The populator blocks' order: ascending priority (100 when absent).
bool populatorPrioritySort(const oo::PList &one, const oo::PList &two)
{
	int pri_one = one.get<int>("priority", 100);
	int pri_two = two.get<int>("priority", 100);
	return pri_one < pri_two;
}


/*	oo_fuzzyBooleanForKey:defaultValue: on a configuration: NO for a null one (messaging nil), else
	OOFuzzyBooleanFromObject (not migrated yet) of the value as the object it was (nil when absent),
	which draws the same random number it drew before.
*/
BOOL FuzzyBooleanIn(const oo::PList &dict, std::string_view key, float fallback)
{
	if (dict.isNull())  return NO;
	const oo::PList *value = dict.find(key);
	return OOFuzzyBooleanFromPList(value, fallback);
}


/*	A system property the old code handed on as a string object (a system name, inhabitants): the
	string, nullopt where the property was absent (nil). Planetinfo names and inhabitants are
	strings; a number reads as its -stringValue.
*/
std::optional<std::string> SystemPropertyString(const oo::PList &property)
{
	if (const std::string *string = property.getIf<std::string>())  return *string;
	if (property.isNumber())  return oo::plist_get::numberStringValue(property);
	return std::nullopt;
}

}	// namespace


namespace {

void VerifyDesc(const std::string &key, const oo::PList &desc);


void VerifyDescString(const std::string &key, const std::string &desc)
{
	if (desc.find("%n") != std::string::npos)
	{
		OO_LOG("descriptions.verify.percentN", "***** FATAL: descriptions.plist entry \"{}\" contains the dangerous control sequence %n.", key);
		exit(EXIT_FAILURE);
	}
}


void VerifyDescArray(const std::string &key, const oo::PList &desc)
{
	for (const oo::PList &subDesc : *desc.getIf<oo::PList::Array>())
	{
		VerifyDesc(key, subDesc);
	}
}


void VerifyDesc(const std::string &key, const oo::PList &desc)
{
	if (desc.isString())
	{
		VerifyDescString(key, *desc.getIf<std::string>());
	}
	else if (desc.isArray())
	{
		VerifyDescArray(key, desc);
	}
	else if (desc.isNumber())
	{
		// No verification needed.
	}
	else
	{
		OO_LOG_ERR("descriptions.verify.badType", "***** FATAL: descriptions.plist entry for \"{}\" is neither a string nor an array.", key);
		exit(EXIT_FAILURE);
	}
}

}	// namespace


namespace {

/*	-removeObjectAtIndex: on the shipyard's candidate keys: an index past the end raised
	OORangeException (the conditions test below can remove the same slot twice).
*/
void RemoveKeyAt(std::vector<std::string> &keys, unsigned index)
{
	if (index >= keys.size())
	{
		OORaiseException(OORangeException, "Index %lu is out of range %lu (in 'removeObjectAtIndex:')", (unsigned long)index, (unsigned long)keys.size());
	}
	keys.erase(keys.begin() + index);
}


// -containsObject: on an equipment list: -isEqual: of two strings.
bool ContainsKey(const oo::PList::Array &list, const std::string &key)
{
	return std::find(list.begin(), list.end(), oo::PList(key)) != list.end();
}


// -removeObject: on the optional equipment: every equal entry goes; nil removed nothing.
void RemoveOption(std::vector<std::optional<std::string>> &options, const std::optional<std::string> &key)
{
	if (key.has_value())  std::erase(options, key);
}


// -setObject:forKey: on the offered ship's dictionary.
void SetInDict(oo::PList &dict, std::string_view key, const std::string &value)
{
	if (oo::PList::Dict *entries = dict.getIf<oo::PList::Dict>())  (*entries)[std::string(key)] = oo::PList(value);
}


/*	cxx_OOExpandKey(key, <name>): the macro hands the expander a one-entry argument dictionary
	keyed by the variable's name; a number keeps the number type cxx_OOCastParam boxed it as.
	Nothing expanded is "".
*/
std::string ExpandKeyWith(const std::string &key, const char *name, const oo::PList &value)
{
	return cxx_OOExpandDescriptionString(OOStringExpanderDefaultRandomSeed(), key,
		cxx_OOExpandArgumentDictionary({ { name, value } }), oo::PList(), std::nullopt, kOOExpandKey).value_or(std::string());
}


// cxx_OOExpandKey(key) with no arguments: no argument dictionary; nothing expanded is "".
std::string ExpandKey(const std::string &key)
{
	return cxx_OOExpandKey(key).value_or(std::string());
}


// -compare: of the two offers' price numbers (unsigned long long).
int comparePrice(const oo::PList &offer1, const oo::PList &offer2)
{
	const unsigned long long price1 = offer1.get<unsigned long long>(std::string(SHIPYARD_KEY_PRICE));
	const unsigned long long price2 = offer2.get<unsigned long long>(std::string(SHIPYARD_KEY_PRICE));
	return (price1 < price2) ? -1 : (price1 > price2) ? 1 : 0;
}


/*	The offered ships' lowercased names as -compare: ordered them, then the price. A missing name
	compares the same (messaging nil); ship definitions always carry one.
*/
int compareName(const oo::PList &offer1, const oo::PList &offer2)
{
	const oo::PList *ship1 = offer1.get<oo::PList::Dict>(std::string(SHIPYARD_KEY_SHIP));
	const oo::PList *ship2 = offer2.get<oo::PList::Dict>(std::string(SHIPYARD_KEY_SHIP));
	const std::optional<std::string> name1 = (ship1 != nullptr) ? OptionalStringIn(*ship1, std::string(KEY_NAME)) : std::nullopt;
	const std::optional<std::string> name2 = (ship2 != nullptr) ? OptionalStringIn(*ship2, std::string(KEY_NAME)) : std::nullopt;

	const int result = (name1.has_value() && name2.has_value()) ? oo::str::compare(oo::str::lowercase(*name1), oo::str::lowercase(*name2)) : 0;
	if (result != 0)
		return result;
	else
		return comparePrice(offer1, offer2);
}

}	// namespace


static void PreloadOneSound(const std::string &soundName)
{
	if (!oo::str::hasPrefix(soundName, "[") && !oo::str::hasSuffix(soundName, "]"))
	{
		ResourceManager::ooSoundNamed(soundName, std::string("Sounds"));
	}
}


#if OO_LOCALIZATION_TOOLS

#if DEBUG_GRAPHVIZ


namespace {

/*	EscapedGraphVizString(OOStringifySystemDescriptionLine(line, keyMap, NO)); a missing line
	escaped to nil, which %@ printed as "(null)".
*/
std::string StringifiedLabel(const std::optional<std::string> &line, const oo::PList &keyMap)
{
	if (!line.has_value())  return "(null)";
	return cxx_EscapedGraphVizString(OOStringifySystemDescriptionLine(*line, keyMap, NO));
}

}	// namespace
#endif	// DEBUG_GRAPHVIZ
#endif


namespace {

// A cached array of condition script names: its strings, as oo::StringsFrom kept them (none when
// absent).
std::vector<std::string> CachedConditionScripts(const std::string &key)
{
	std::vector<std::string> scripts;
	const oo::PList names = OOCacheManager::sharedCache()->pListForKey(key, "condition scripts");
	if (const oo::PList::Array *entries = names.getIf<oo::PList::Array>())
	{
		for (const oo::PList &entry : *entries)
		{
			if (const std::string *name = entry.getIf<std::string>())  scripts.push_back(*name);
		}
	}
	return scripts;
}

}	// namespace


/*	The custom-sound categories of OOSound and OOSoundSource on converted classes' facades
	(slice 26 of docs/phases/3-slices/Universe.md, bead oo-32kcu): their bodies are free functions,
	which the categories forwarded to from Universe+ObjCBridge.mm (ADR-0056 amendments oo-6ia4
	item 3, oo-9fwb, oo-7jhs5) until beads oo-9ht.68 and oo-9ht.88 deleted the two facades; the
	callers call them.
*/

// +[OOSound cxx_soundWithCustomSoundKey:]: the sound for a customsounds.plist key, borrowed (the
// resource manager's cache keeps it; was autoreleased); null for none.
::OOSound *OOSoundWithCustomSoundKey(const std::string &key)
{
	const std::optional<std::string> fileName = OOUniverseSoundNameForCustomSoundKey(key);
	if (!fileName.has_value())  return nil;
	return ResourceManager::ooSoundNamed(*fileName, std::string("Sounds"));
}


// -[OOSoundSource cxx_playCustomSoundWithKey:]
void OOSoundSourcePlayCustomSoundWithKey(::OOSoundSource *source, const std::string &key)
{
	if (source == nullptr)  return;	// a message to nil
	::OOSound *theSound = OOSoundWithCustomSoundKey(key);
	if (theSound != nullptr)  source->playOOSound(theSound);
}

std::string cxx_OOLookUpDescriptionPRIV(const std::string &key)
{
	std::optional<std::string> result = OOUniverseDescriptionForKey(key);
	if (!result.has_value())  result = key;
	return *result;
}


// There's a hint of gettext about this...
std::string cxx_OOLookUpPluralDescriptionPRIV(const std::string &key, NSInteger count)
{
	const oo::PList *descriptions = OOUniverseDescriptions();
	const oo::PList *conditions = (descriptions != nullptr) ? descriptions->get<oo::PList::Array>("plural-rules") : nullptr;

	// are we using an older descriptions.plist (1.72.x) ?
	std::optional<std::string> tmp = OOUniverseDescriptionForKey(key);
	if (tmp.has_value())
	{
		static std::set<std::string> warned;

		if (!warned.contains(*tmp))
		{
			OO_LOG_WARN("localization.plurals", "'{}' found in descriptions.plist, should be '{}%0'. Localization data needs updating.", key, key);
			warned.insert(*tmp);
		}
	}

	if (conditions == nullptr)
	{
		if (!tmp.has_value()) // this should mean that descriptions.plist is from 1.73 or above.
			return cxx_OOLookUpDescriptionPRIV(oo::str::format("%s%%%d", key.c_str(), (int)(count != 1)));
		// still using an older descriptions.plist
		return *tmp;
	}
	int unsigned i;
	long int index;

	for (index = i = 0; i < conditions->count(); ++index, ++i)
	{
		const std::optional<std::string> condition = OptionalStringAt(*conditions, i);
		if (!condition.has_value())
			break;
		const char *cond = condition->c_str();
		
		long int input = count;
		BOOL flag = NO; // we XOR test results with this
		
		while (isspace (*cond))
			++cond;
		
		for (;;)
		{
			while (isspace (*cond))
				++cond;
			
			char command = *cond++;
			
			switch (command)
			{
				case 0:
					goto passed; // end of string
					
				case '~':
					flag = !flag;
					continue;
			}
			
			long int param = strtol(cond, (char **)&cond, 10);
			
			switch (command)
			{
				case '#':
					index = param;
					continue;
					
				case '%':
					if (param < 2)
						break; // ouch - fail this!
					input %= param;
					continue;
					
				case '=':
					if (flag ^ (input == param))
						continue;
					break;
				case '!':
					if (flag ^ (input != param))
						continue;
					break;
					
				case '<':
					if (flag ^ (input < param))
						continue;
					break;
				case '>':
					if (flag ^ (input > param))
						continue;
					break;
			}
			// if we arrive here, we have an unknown test or a test has failed
			break;
		}
	}
	
passed:
	return cxx_OOLookUpDescriptionPRIV(oo::str::format("%s%%%ld", key.c_str(), index));
}


// Slice 3 of docs/phases/3-slices/Universe.md (bead oo-ef6rc): pause and quit, carrying the player
// on, set-up from station / witchspace / misjump, witchspace and planet set-up. The facade forwards
// each selector (until oo-ql9rn); sends to self were sends (ADR-0056 amendment oo-27jxj).

void Universe::pauseGame()
{
	// deal with the machine going to sleep, or player pressing 'p'.
	::PlayerEntity 	*player = PLAYER;
	
	setPauseMessageVisible(NO);
	const std::optional<std::string> pauseKey = (PLAYER != nullptr ? PLAYER->keyBindingDescription2("key_pausebutton") : std::optional<std::string>());
	
	if ((player != nullptr ? player->status() : OOEntityStatus{}) == STATUS_DOCKED)
	{
		if (gui != nullptr && gui->setForegroundTextureKey("paused_docked_overlay"))	// a nil GUI answered NO
		{
			gui->drawGUI(1.0, NO);
		}
		else
		{
			setPauseMessageVisible(YES);
			addMessage(ExpandKeyWith("game-paused-docked", "pauseKey", pauseKey.has_value() ? oo::PList(*pauseKey) : oo::PList()), 1.0);
		}
	}
	else
	{
		if ((player != nullptr ? player->guiScreen() : OOGUIScreenID{}) != GUI_SCREEN_MAIN && gui != nullptr && gui->setForegroundTextureKey("paused_overlay"))
		{
			gui->drawGUI(1.0, NO);
		}
		else
		{
			setPauseMessageVisible(YES);
			addMessage(ExpandKeyWith("game-paused", "pauseKey", pauseKey.has_value() ? oo::PList(*pauseKey) : oo::PList()), 1.0);
		}
	}
	
	if (gameController() != nullptr)  gameController()->setGamePaused(YES);
}


void Universe::quitGame()
{
	OO_LOG("universe.quit", "{}", "Quit command received by Universe.");
	if (gameController() != nullptr)  gameController()->exitAppWithContext("Universe Request");
}


void Universe::carryPlayerOn(::StationEntity * /*carrier */, ::WormholeEntity *wormhole)
{
		::PlayerEntity	*player = PLAYER;
		OOSystemID dest = (wormhole != nullptr ? wormhole->getDestination() : 0);

		if (player != nullptr)  player->setWormhole(wormhole);
		if (player != nullptr)  player->addScannedWormhole(wormhole);
		ooscript::Context context = OOJSAcquireContext();
		if (player != nullptr)  player->setJumpCause("carried");
		if (player != nullptr)  player->setPreviousSystemID((player != nullptr ? player->systemID() : 0));
		ShipScriptEvent(context, player, "shipWillEnterWitchspace", ooscript::stringValue(ooscript::internString(context, (player != nullptr ? player->jumpCause() : std::optional<std::string>()).value_or("").c_str())), ooscript::int32Value(dest));
		OOJSRelinquishContext(context);
	
		allShipsDoScriptEvent(OOJSID("playerWillEnterWitchspace"), "PLAYER WITCHSPACE");

		if (player != nullptr)  player->setRandom_factor((ranrot_rand() & 255));						// random factor for market values is reset

// misjump on wormhole sets correct travel time if needed
		if (player != nullptr)  player->addToAdjustTime((wormhole != nullptr ? wormhole->travelTime() : 0.0));
// clear old entities
		removeAllEntitiesExceptPlayer();

// should we add wear-and-tear to the player ship if they're not doing
// the jump themselves? Left out for now. - CIM

		if (!(wormhole != nullptr ? wormhole->withMisjump() : false))
		{
			if (player != nullptr)  player->setSystemID(dest);
			setSystemTo(dest);
			
			setUpSpace();
			populateNormalSpace();
			if (player != nullptr)  player->setBounty(((player != nullptr ? player->getLegalStatus() : int{})/2), kOOLegalStatusReasonNewSystem);
			if ((player != nullptr ? player->random_factor() : int{}) < 8) { if (player != nullptr)  player->erodeReputation(); }		// every 32 systems or so, dro
		}
		else
		{
			if (player != nullptr)  player->setGalaxyCoordinates((wormhole != nullptr ? wormhole->destinationCoordinates() : NSPoint{}));

			setUpWitchspaceBetweenSystem((wormhole != nullptr ? wormhole->getOrigin() : 0), (wormhole != nullptr ? wormhole->getDestination() : 0));

			if (randf() < 0.1) { if (player != nullptr)  player->erodeReputation(); }		// once every 10 misjumps - should be much rarer than successful jumps!
		}
		// which will kick the ship out of the wormhole with the
		// player still aboard
		if (wormhole != nullptr)  wormhole->disgorgeShips();

		//reset atmospherics in case carrier was in atmosphere
		if (UNIVERSE != nullptr)  UNIVERSE->setSkyColorRed(0.0f,		// back to black
											 0.0f,
												0.0f,
											 0.0f);

		setWitchspaceBreakPattern(YES);
		if (player != nullptr)  player->doScriptEvent(OOJSID("shipWillExitWitchspace"), { StringOrNull((player != nullptr ? player->jumpCause() : std::optional<std::string>())) });
		if (player != nullptr)  player->doScriptEvent(OOJSID("shipExitedWitchspace"), { StringOrNull((player != nullptr ? player->jumpCause() : std::optional<std::string>())) });
		if (player != nullptr)  player->setWormhole(nullptr);

}


void Universe::setUpUniverseFromStation()
{
	if (!sun())
	{
		// we're in witchspace...		
		
		::PlayerEntity	*player = PLAYER;
		::StationEntity	*dockedStation = (player != nullptr ? player->dockedStation() : (::StationEntity *)nullptr);
		NSPoint			coords = (player != nullptr ? player->getGalaxy_coordinates() : NSPoint{});
		// check the nearest system
		OOSystemID sys = findSystemNumberAtCoords(coords, (player != nullptr ? player->galaxyNumber() : OOGalaxyID{}), YES);
		BOOL interstel =(dockedStation != nullptr ? dockedStation->getInterstellarUndockingAllowed() : false);// && (s_seed.d != coords.x || s_seed.b != coords.y); - Nikos 20110623: Do we really need the commented out check?
		if (player != nullptr)  player->setPreviousSystemID((player != nullptr ? player->currentSystemID() : 0));

		// remove everything except the player and the docked station
		if (dockedStation && !interstel)
		{	// jump to the nearest system
			if (player != nullptr)  player->setSystemID(sys);
			closeSystems.reset();
			setSystemTo(sys);
			int index = 0;
			while (entities.size() > 2)
			{
				Entity *ent = entities[index].get();
				if ((ent != player)&&(ent != dockedStation))
				{
					if (ent->isStation)  // clear out queues
						if (oo::ToStation(ent) != nullptr)  oo::ToStation(ent)->clear();
					removeEntity(ent);
				}
				else
				{
					index++;	// leave that one alone
				}
			}
		}
		else
		{
			if (dockedStation == nil)  removeAllEntitiesExceptPlayer();	// get rid of witchspace sky etc. if still extant
		}
		
		if (!dockedStation || !interstel) 
		{
			setUpSpace();	// launching from station that jumped from interstellar space to normal space.
			populateNormalSpace();
			if (dockedStation)
			{
				if ((dockedStation != nullptr ? dockedStation->getMaxFlightSpeed() : 0.0f) > 0) // we are a carrier: exit near the WitchspaceExitPosition
				{
					float		d1 = randomDistanceWithinScanner();
					HPVector		pos = (UNIVERSE != nullptr ? UNIVERSE->getWitchspaceExitPosition() : HPVector{});		// no need to reset the PRNG
					Quaternion	q1;
					
					quaternion_set_random(&q1);
					if (abs((int)d1) < 2750)	
					{
						d1 += ((d1 > 0.0)? 2750.0f: -2750.0f); // no closer than 2750m. Carriers are bigger than player ships.
					}
					Vector		v1 = vector_forward_from_quaternion(q1);
					pos.x += v1.x * d1; // randomise exit position
					pos.y += v1.y * d1;
					pos.z += v1.z * d1;
					
					if (dockedStation != nullptr)  dockedStation->setPosition(pos);
				}
				setWitchspaceBreakPattern(YES);
				if (player != nullptr)  player->setJumpCause("carried");
				if (player != nullptr)  player->doScriptEvent(OOJSID("shipWillExitWitchspace"), { StringOrNull((player != nullptr ? player->jumpCause() : std::optional<std::string>())) });
				if (player != nullptr)  player->doScriptEvent(OOJSID("shipExitedWitchspace"), { StringOrNull((player != nullptr ? player->jumpCause() : std::optional<std::string>())) });
			}
		}
	}
	
	if(!autoSaveNow) setViewDirection(VIEW_FORWARD);
	displayGUI = NO;
	
	//reset atmospherics in case we ejected while we were in the atmophere
	if (UNIVERSE != nullptr)  UNIVERSE->setSkyColorRed(0.0f,		// back to black
					   0.0f,
						0.0f,
					   0.0f);
}


void Universe::setUpUniverseFromWitchspace()
{
	::PlayerEntity		*player;
	::ShipEntity		*playerObject;	// the player's Objective-C object (the ship's facade, bead oo-9ht.177)

	//
	// check the player is still around!
	//
	if (entities.empty())
	{
		/*- the player ship -*/
		playerObject = ::PlayerEntity::newPlayerObject();	// alloc retains!

		addEntity(playerObject);

		/*--*/
	}
	else
	{
		playerObject = oo::ToShip(oo::RetainEntity(PLAYER));	// retained here (its object)
	}
	player = static_cast<::PlayerEntity *>(playerObject);

	setUpSpace();
	populateNormalSpace();
	
	if (player != nullptr)  player->leaveWitchspace();
	if (playerObject != nullptr)  oo::ReleaseEntity(playerObject);									// released here

	setViewDirection(VIEW_FORWARD);
	
	// the printed lines go to the player's comm log
	std::vector<std::string> printedLines;
	if (comm_log_gui != nullptr)  comm_log_gui->printLongText(oo::str::format("%s %s", TextOrNull(getSystemName(systemID)).c_str(), (player != nullptr ? player->dial_clock_adjusted() : std::string()).c_str()), GUI_ALIGN_CENTER, OOColor::whiteColor().get(), 0, std::nullopt, &printedLines);
	std::vector<std::string> *commLog = (player != nullptr ? player->getCommLog() : (std::vector<std::string> *)nullptr);
	if (commLog != nullptr)  commLog->insert(commLog->end(), printedLines.begin(), printedLines.end());
	
	displayGUI = NO;
}


void Universe::setUpUniverseFromMisjump()
{
	::PlayerEntity		*player;
	::ShipEntity		*playerObject;	// the player's Objective-C object (the ship's facade, bead oo-9ht.177)

	//
	// check the player is still around!
	//
	if (entities.empty())
	{
		/*- the player ship -*/
		playerObject = ::PlayerEntity::newPlayerObject();	// alloc retains!

		addEntity(playerObject);

		/*--*/
	}
	else
	{
		playerObject = oo::ToShip(oo::RetainEntity(PLAYER));	// retained here (its object)
	}
	player = static_cast<::PlayerEntity *>(playerObject);

	setUpWitchspace();
	// ensure that if we got here from a jump within a planet's atmosphere,
	// we don't get any residual air friction
	setAirResistanceFactor(0.0f);
	
	if (player != nullptr)  player->leaveWitchspace();
	if (playerObject != nullptr)  oo::ReleaseEntity(playerObject);									// released here
	
	setViewDirection(VIEW_FORWARD);
	
	displayGUI = NO;
}


void Universe::setUpWitchspace()
{
	setUpWitchspaceBetweenSystem((PLAYER != nullptr ? PLAYER->systemID() : 0), (PLAYER != nullptr ? PLAYER->nextHopTargetSystemID() : 0));
}


void Universe::setUpWitchspaceBetweenSystem(OOSystemID s1, OOSystemID s2)
{
	// new system is hyper-centric : witchspace exit point is origin
	
	Entity				*thing;	// its object retained by hand where +alloc's was (bead oo-9ht.39.26)
	::PlayerEntity*		player = PLAYER;
	Quaternion			randomQ;
	
	const std::string	override_key = *keyForInterstellarOverridesForSystems(s1, s2, galaxyID);

	const oo::PList systeminfo = (systemManager != nullptr ? systemManager->getPropertiesForSystemKey(override_key) : oo::PList());
	
	if (universeRegion != nullptr)  universeRegion->clearSubregions();	// none yet while the initial universe is set up (a nil message did nothing)
	
	// fixed entities (part of the graphics system really) come first...
	
	/*- the sky backdrop -*/
	oo::Ref<OOColor>	col1 = OOColor::colorWithRed(0.0, 1.0, 0.5, 1.0);
	oo::Ref<OOColor>	col2 = OOColor::colorWithRed(0.0, 1.0, 0.0, 1.0);
	{
		// The sky is C++ (bead oo-9ht.109): its object first, retained as +alloc's was, then the body.
		oo::Ref<::SkyEntity> skyRef = oo::makeRef<::SkyEntity>();
		thing = oo::RetainEntity(oo::MadeEntity(skyRef));	// alloc retains!
		skyRef->initWithColors(col1.get(), col2.get(), systeminfo);
	}
	thing->setScanClass(CLASS_NO_DRAW);
	quaternion_set_random(&randomQ);
	thing->setOrientation(randomQ);
	addEntity(thing);
	oo::ReleaseEntity(thing);
	
	/*- the dust particle system -*/
	oo::Ref<DustEntity> dust = oo::makeRef<DustEntity>();
	dust->init();
	dust->setScanClass(CLASS_NO_DRAW);
	thing = oo::MadeEntity(dust);
	addEntity(thing);
	
	ambientLightLevel = systeminfo.get<float>("ambient_level", 1.0);
	setLighting();	// also sets initial lights positions.

	OO_LOG(kOOLogUniversePopulateWitchspace, "{}", "Populating witchspace ...");
	oo::log::indentIf(kOOLogUniversePopulateWitchspace);

	clearSystemPopulator();
	const std::string populator = systeminfo.get<std::string>("populator", "interstellarSpaceWillPopulate");
	system_repopulator = systeminfo.get<std::string>("repopulator", "interstellarSpaceWillRepopulate");
	ooscript::Context context = OOJSAcquireContext();
	if (PLAYER != nullptr)  PLAYER->doWorldScriptEvent(cxx_OOJSIDFromString(populator), context, NULL, 0, kOOJSLongTimeLimit);
	OOJSRelinquishContext(context);
	populateSystemFromDictionariesWithSun(nullptr, nullptr);

	// systeminfo might have a 'script_actions' resource we want to activate now...
	const oo::PList *script_actions = systeminfo.get<oo::PList::Array>("script_actions");
	if (script_actions != nullptr)
	{
		cxx_OOStandardsDeprecated(oo::str::format("The script_actions system info key is deprecated for %s.",override_key.c_str()));
		if (!OOEnforceStandards())
		{
			if (player != nullptr)  player->runUnsanitizedScriptActions(*script_actions, NO, "<witchspace script_actions>", nullptr);
		}
	}
	
	next_repopulation = randf() * SYSTEM_REPOPULATION_INTERVAL;

	oo::log::outdentIf(kOOLogUniversePopulateWitchspace);
}


::OOPlanetEntity * Universe::setUpPlanet()
{
	// set the system seed for random number generation
	Random_Seed systemSeed = (systemManager != nullptr ? systemManager->getRandomSeedForCurrentSystem() : Random_Seed());
	seed_for_planet_description(systemSeed);

	// a copy of the system data, marked as the main planet (a bool, as -oo_setBool:forKey: stored it)
	oo::PList planetDict = (systemManager != nullptr ? systemManager->getPropertiesForCurrentSystem() : oo::PList());
	if (!planetDict.isDict())  planetDict = oo::PList(oo::PList::Dict{});
	(*planetDict.getIf<oo::PList::Dict>())["mainForLocalSystem"] = oo::PList(true);
	::OOPlanetEntity *a_planet = nullptr;
	{
		// +alloc/-initFromDictionary:withAtmosphere:andSeed:forSystem:: a new C++ planet and its
		// Objective-C object, +1 (the facade went with bead oo-9ht.129).
		oo::Ref<::OOPlanetEntity> planetRef = oo::makeRef<::OOPlanetEntity>();
		oo::RetainEntity(oo::MadeEntity(planetRef));
		planetRef->initFromDictionary(planetDict, planetDict.get<bool>("has_atmosphere", YES), systemSeed, systemID);
		a_planet = planetRef.get();
	}

	double planet_zpos = planetDict.get<float>("planet_distance", 500000);
	planet_zpos *= planetDict.get<float>("planet_distance_multiplier", 1.0);
	
#ifdef OO_DUMP_PLANETINFO
	OO_LOG("planetinfo.record", "planet zpos = {:f}", planet_zpos);
#endif
	if (a_planet != nullptr)  a_planet->setPosition((HPVector){ 0, 0, planet_zpos });
	if (a_planet != nullptr)  a_planet->setEnergy(1000000.0);
	
	if (allPlanets.size()>0)	// F7 sets [UNIVERSE planet], which can lead to some trouble! TODO: track down where exactly that happens!
	{
		Entity *tmp=allPlanets[0].get();
		addEntity(a_planet);
		std::erase(allPlanets, static_cast<Entity *>(a_planet));
		cachedPlanet=a_planet;
		allPlanets[0] = oo::EntityHold(a_planet);
		removeEntity(tmp);
	}
	else
	{
		addEntity(a_planet);
	}
	oo::AutoreleaseEntity(a_planet);
	return a_planet;
}




// Slice 4 of docs/phases/3-slices/Universe.md (bead oo-ni9u8): setUpSpace, populating normal space,
// the system populator. The facade forwarded each selector (until oo-ql9rn); sends to self
// were sends (ADR-0056 amendment oo-27jxj).

/* At any time other than game start, any call to this must be followed
 * by populateNormalSpace(). However, at game start, they need to be
 * separated to allow Javascript startUp routines to be run in-between */
void Universe::setUpSpace()
{
	Entity				*thing;	// its object retained by hand where +alloc's was (bead oo-9ht.39.26)
//	ShipEntity			*nav_buoy;
	::ShipEntity			*stationObject;	// the station's object (the ship's facade since bead oo-9ht.175), retained
	::StationEntity		*a_station;
	::OOSunEntity			*a_sun;
	::OOPlanetEntity		*a_planet;
	
	HPVector				stationPos;
	
	Vector				vf;
	oo::PList	dict_object;

	const oo::PList		systeminfo = (systemManager != nullptr ? systemManager->getPropertiesForCurrentSystem() : oo::PList());
	unsigned			techlevel = systeminfo.get<unsigned int>(std::string(KEY_TECHLEVEL));
	std::optional<std::string>	stationDesc, defaultStationDesc;	// the default is never set: nullopt, as nil
	oo::Ref<OOColor>	bgcolor;
	oo::Ref<OOColor>	pale_bgcolor;
	BOOL				sunGoneNova;
	
	Random_Seed systemSeed = (systemManager != nullptr ? systemManager->getRandomSeedForCurrentSystem() : Random_Seed());

	::GameController::sharedController()->logProgress(OO_DESC("populating-space"));
	
	sunGoneNova = systeminfo.get<bool>("sun_gone_nova", NO);

	OO_DEBUG_PUSH_PROGRESS("setUpSpace - clearSubRegions, sky, dust");
	if (universeRegion != nullptr)  universeRegion->clearSubregions();	// none yet while the initial universe is set up (a nil message did nothing)
	
	// fixed entities (part of the graphics system really) come first...
	setSkyColorRed(0.0f, 0.0f, 0.0f, 0.0f);

	
#ifdef OO_DUMP_PLANETINFO
	OO_LOG("planetinfo.record", "seed = {} {} {} {}", system_seed.c, system_seed.d, system_seed.e, system_seed.f);
	OO_LOG("planetinfo.record", "coordinates = {} {}", system_seed.d, system_seed.b);

#define SPROP(PROP)	OO_LOG("planetinfo.record", #PROP " = \"{}\";", OptionalStringIn(systeminfo, "" #PROP).value_or("(null)"));
#define IPROP(PROP)	OO_LOG("planetinfo.record", #PROP " = {};", systeminfo.get<int>(#PROP));
#define FPROP(PROP)	OO_LOG("planetinfo.record", #PROP " = {:f};", systeminfo.get<float>("" #PROP));
	IPROP(government);
	IPROP(economy);
	IPROP(techlevel);
	IPROP(population);
	IPROP(productivity);
	SPROP(name);
	SPROP(inhabitant);
	SPROP(inhabitants);
	SPROP(description);
#endif

	// set the system seed for random number generation
	seed_for_planet_description(systemSeed);
	
	/*- the sky backdrop -*/
	// colors...
	float h1 = randf();
	float h2 = h1 + 1.0 / (1.0 + (Ranrot() % 5));
	while (h2 > 1.0)
		h2 -= 1.0;
	float s1 = randf();	// one draw per local, in the order Clang evaluates the arguments (ADR-0063 item 5)
	double b1 = 0.5 + randf()/2.0;
	oo::Ref<OOColor>	col1 = OOColor::colorWithHue(h1, s1, b1, 1.0);
	double s2 = 0.5 + randf()/2.0;
	double b2 = 0.5 + randf()/2.0;
	oo::Ref<OOColor>	col2 = OOColor::colorWithHue(h2, s2, b2, 1.0);
	
	{
		// The sky is C++ (bead oo-9ht.109): its object first, retained as +alloc's was, then the body.
		oo::Ref<::SkyEntity> skyRef = oo::makeRef<::SkyEntity>();
		thing = oo::RetainEntity(oo::MadeEntity(skyRef));	// alloc retains!
		skyRef->initWithColors(col1.get(), col2.get(), systeminfo);
	}
	thing->setScanClass(CLASS_NO_DRAW);
	addEntity(thing);
//	bgcolor = [(SkyEntity *)thing skyColor];
//
	h1 = randf()/3.0;
	if (h1 > 0.17)
	{
		h1 += 0.33;
	}
	
	ambientLightLevel = systeminfo.get<float>("ambient_level", 1.0);

	// pick a main sequence colour

	dict_object=PListForKeyIn(systeminfo, "sun_color");
	if (!dict_object.isNull())
	{
		bgcolor = OOColor::colorWithDescription(dict_object);
	}
	else
	{
		double saturation = 0.75*randf();	// one draw per local, in the order Clang evaluates the arguments (ADR-0063 item 5)
		double brightness = 0.65+randf()/5.0;
		bgcolor = OOColor::colorWithHue(h1, saturation, brightness, 1.0);
	}

	pale_bgcolor = (bgcolor != nullptr) ? bgcolor->blendedColorWithFraction(0.5, OOColor::whiteColor().get()) : nullptr;	// nil stayed nil
	oo::ReleaseEntity(thing);
	/*--*/
	
	/*- the dust particle system -*/
	oo::Ref<DustEntity> dust = oo::makeRef<DustEntity>();
	dust->init();
	dust->setScanClass(CLASS_NO_DRAW);
	thing = oo::MadeEntity(dust);
	addEntity(thing);
	dust->setDustColor(pale_bgcolor.get());
	/*--*/

	float defaultSunFlare = randf()*0.1;
	float defaultSunHues = 0.5+randf()*0.5;
	OO_DEBUG_POP_PROGRESS();
	
	// actual entities next...
	
	OO_DEBUG_PUSH_PROGRESS("setUpSpace - planet");
	a_planet=setUpPlanet(); // resets RNG when called
	double planet_radius = (a_planet != nullptr ? a_planet->radius() : 0.0);
	OO_DEBUG_POP_PROGRESS();
	
	// set the system seed for random number generation
	seed_for_planet_description(systemSeed);
	
	OO_DEBUG_PUSH_PROGRESS("setUpSpace - sun");
	/*- space sun -*/
	double		sun_radius;
	double		sun_distance;
	double		sunDistanceModifier;
	double		safeDistance;
	HPVector		sunPos;
	
	sunDistanceModifier = systeminfo.get<oo::NonNegative<double>>("sun_distance_modifier", 0.0);
	if (sunDistanceModifier < 6.0) // <6 isn't valid
	{
		sun_distance = systeminfo.get<oo::NonNegative<double>>("sun_distance", (planet_radius*20));
		// note, old property was _modifier, new property is _multiplier
		sun_distance *= systeminfo.get<oo::NonNegative<double>>("sun_distance_multiplier", 1);
	} 
	else
	{
		sun_distance = planet_radius * sunDistanceModifier;
	}

	sun_radius = systeminfo.get<oo::NonNegative<double>>("sun_radius", 2.5 * planet_radius);
	// clamp the sun radius
	if ((sun_radius < 1000.0) || (sun_radius > sun_distance / 2  && !sunGoneNova))
	{
		OO_LOG_WARN("universe.setup.badSun", "Sun radius of {:f} is not valid for this system", sun_radius);
		sun_radius = sun_radius < 1000.0 ? 1000.0 : (sun_distance / 2);
	}
#ifdef OO_DUMP_PLANETINFO
	OO_LOG("planetinfo.record", "sun_radius = {:f}", sun_radius);
#endif
	safeDistance=36 * sun_radius * sun_radius; // 6 times the sun radius
	
	// here we need to check if the sun collides with (or is too close to) the witchpoint
	// otherwise at (for example) Maregais in Galaxy 1 we go BANG!
	HPVector sun_dir = HPVectorIn(systeminfo, "sun_vector", kZeroHPVector);
	sun_distance /= 2.0;
	do
	{
		sun_distance *= 2.0;
		sunPos = HPvector_subtract((a_planet != nullptr ? a_planet->getPosition() : HPVector{}),
							  HPvector_multiply_scalar(sun_dir,sun_distance));
		
		// if not in the safe distance, multiply by two and try again
	} 
	while (HPmagnitude2(sunPos) < safeDistance);

	// set planetary axial tilt to 0 degrees
	// TODO: allow this to vary
	if (a_planet != nullptr)  a_planet->setOrientation(quaternion_rotation_betweenHP(sun_dir,make_HPvector(1.0,0.0,0.0)));

#ifdef OO_DUMP_PLANETINFO
	OO_LOG("planetinfo.record", "sun_vector = {:.3f} {:.3f} {:.3f}", vf.x, vf.y, vf.z);
	OO_LOG("planetinfo.record", "sun_distance = {:.0f}", sun_distance);
#endif
	

	
	// the sun's settings: the values as they were in the system info, else the defaults (floats,
	// as +numberWithFloat: stored them: item 15); the radius a double
	oo::PList::Dict sunSettings;
	sunSettings["sun_radius"] = oo::PList(sun_radius);
	if (const oo::PList *value = systeminfo.find("corona_shimmer"))  sunSettings["corona_shimmer"] = *value;
	if (const oo::PList *value = systeminfo.find("corona_hues"))
	{
		sunSettings["corona_hues"] = *value;
	}
	else
	{
		sunSettings["corona_hues"] = oo::PList::singleReal(defaultSunHues);
	}
	if (const oo::PList *value = systeminfo.find("corona_flare"))
	{
		sunSettings["corona_flare"] = *value;
	}
	else
	{
		sunSettings["corona_flare"] = oo::PList::singleReal(defaultSunFlare);
	}
	if (const oo::PList *value = systeminfo.find(std::string(KEY_SUNNAME)))
	{
		sunSettings[std::string(KEY_SUNNAME)] = *value;
	}
	const oo::PList sun_dict(std::move(sunSettings));
#ifdef OO_DUMP_PLANETINFO
	OO_LOG("planetinfo.record", "corona_flare = {:f}", sun_dict.get<float>("corona_flare"));
	OO_LOG("planetinfo.record", "corona_hues = {:f}", sun_dict.get<float>("corona_hues"));
	OO_LOG("planetinfo.record", "sun_color = {}", (bgcolor != nullptr ? bgcolor->descriptionComponents() : std::nullopt).value_or("(null)"));
#endif
	{
		// +alloc/-initSunWithColor:andDictionary:: a new C++ sun and its Objective-C object, +1 (the
		// facade went with bead oo-9ht.111).
		oo::Ref<OOSunEntity> sunRef = oo::makeRef<OOSunEntity>();
		oo::RetainEntity(oo::MadeEntity(sunRef));	// alloc retains!
		sunRef->initSunWithColor(bgcolor.get(), sun_dict);
		a_sun = sunRef.get();
	}
	
	if (a_sun != nullptr)  a_sun->setStatus(STATUS_ACTIVE);
	if (a_sun != nullptr)  a_sun->setPosition(sunPos); // sets also light origin
	if (a_sun != nullptr)  a_sun->setEnergy(1000000.0);
	addEntity(a_sun);
	
	if (sunGoneNova)
	{
		if (a_sun != nullptr)  a_sun->setRadius(sun_radius, 0.3);
		if (a_sun != nullptr)  a_sun->setThrowSparks(YES);
		if (a_sun != nullptr)  a_sun->setVelocity(kZeroVector);
	}
	
	// set the lighting only after we know which sun we have.
	setLighting();
	OO_DEBUG_POP_PROGRESS();
	
	OO_DEBUG_PUSH_PROGRESS("setUpSpace - main station");
	/*- space station -*/
	stationPos = (a_planet != nullptr ? a_planet->getPosition() : HPVector{});

	vf = VectorIn(systeminfo, "station_vector", kZeroVector);
#ifdef OO_DUMP_PLANETINFO
	OO_LOG("planetinfo.record", "station_vector = {:.3f} {:.3f} {:.3f}", vf.x, vf.y, vf.z);
#endif
	stationPos = HPvector_subtract(stationPos, vectorToHPVector(vector_multiply_scalar(vf, 2.0 * planet_radius)));
	

	//// possibly systeminfo has an override for the station
	stationDesc = systeminfo.get<std::string>("station", "coriolis");
#ifdef OO_DUMP_PLANETINFO
	OO_LOG("planetinfo.record", "station = {}", stationDesc.value_or("(null)"));
#endif

	// a missing role (the unset default) gives no ship, as a nil role did
	stationObject = stationDesc.has_value() ? newShipWithRole(*stationDesc) : nil;			// retain count = 1
	
	/*	Sanity check: ensure that only stations are generated here. This is an
		attempt to fix exceptions of the form:
			OOInvalidArgumentException : *** -[ShipEntity setPlanet:]: selector
			not recognized [self = 0x19b7e000] *****
		which I presume to be originating here since all other uses of
		setPlanet: are guarded by isStation checks. This error could happen if
		a ship that is not a station has a station role, or equivalently if an
		OXP sets a system's station role to a role used by non-stations.
		-- Ahruman 20080303
	*/
	if (!(stationObject != nullptr ? stationObject->getIsStation() : false) || !(stationObject != nullptr ? stationObject->validForAddToUniverse() : false))
	{
		if (stationObject == nil)
		{
			// Should have had a more specific error already, just specify context
			OO_LOG("universe.setup.badStation", "Failed to set up a ship for role \"{}\" as system station, trying again with \"{}\".", stationDesc.value_or("(null)"), defaultStationDesc.value_or("(null)"));
		}
		else
		{
			OO_LOG("universe.setup.badStation", "***** ERROR: Attempt to use non-station ship of type \"{}\" for role \"{}\" as system station, trying again with \"{}\".", (stationObject != nullptr ? stationObject->getName() : std::optional<std::string>()).value_or("(null)"), stationDesc.value_or("(null)"), defaultStationDesc.value_or("(null)"));
		}
		if (stationObject != nullptr)  oo::ReleaseEntity(stationObject);
		stationDesc = defaultStationDesc;
		stationObject = stationDesc.has_value() ? newShipWithRole(*stationDesc) : nil;		 // retain count = 1
		
		if (!(stationObject != nullptr ? stationObject->getIsStation() : false) || !(stationObject != nullptr ? stationObject->validForAddToUniverse() : false))
		{
			if (stationObject == nil)
			{
				OO_LOG("universe.setup.badStation", "On retry, failed to set up a ship for role \"{}\" as system station. Trying to fall back to built-in Coriolis station.", stationDesc.value_or("(null)"));
			}
			else
			{
				OO_LOG("universe.setup.badStation", "***** ERROR: On retry, rolled non-station ship of type \"{}\" for role \"{}\". Non-station ships should not have this role! Trying to fall back to built-in Coriolis station.", (stationObject != nullptr ? stationObject->getName() : std::optional<std::string>()).value_or("(null)"), stationDesc.value_or("(null)"));
			}
			if (stationObject != nullptr)  oo::ReleaseEntity(stationObject);

			stationObject = newShipWithName("coriolis-station");
			if (!(stationObject != nullptr ? stationObject->getIsStation() : false) || !(stationObject != nullptr ? stationObject->validForAddToUniverse() : false))
			{
				OO_LOG("universe.setup.badStation", "{}", "Could not create built-in Coriolis station! Generating a stationless system.");
				oo::ReleaseEntity(stationObject);	// DESTROY(stationObject)
				stationObject = nullptr;
			}
		}
	}
	a_station = oo::ToStation(stationObject);
	
	if (a_station != nil)
	{
		if (a_station != nullptr)  a_station->setOrientation(quaternion_rotation_between(vf,make_vector(0.0,0.0,1.0)));
		if (a_station != nullptr)  a_station->setPosition(stationPos);
		if (a_station != nullptr)  a_station->setPitch(0.0);
		if (a_station != nullptr)  a_station->setScanClass(CLASS_STATION);
		//[a_station setPlanet:[self planet]];	// done inside addEntity.
		if (a_station != nullptr)  a_station->setEquivalentTechLevel(techlevel);
		addEntity(stationObject);		// STATUS_IN_FLIGHT, AI state GLOBAL
		if (a_station != nullptr)  a_station->setStatus(STATUS_ACTIVE);	// For backward compatibility. Might not be needed.
		if (a_station != nullptr)  a_station->setAllowsFastDocking(true);	// Main stations always allow fast docking.
		if (a_station != nullptr)  a_station->setAllegiance("galcop"); // Main station is galcop controlled
	}
	OO_DEBUG_POP_PROGRESS();
	
	cachedSun = a_sun;
	cachedPlanet = a_planet;
	cachedStation = a_station;
	closeSystems.reset();
	OO_DEBUG_POP_PROGRESS();
	
	
	OO_DEBUG_PUSH_PROGRESS("setUpSpace - populate from wormholes");
	populateSpaceFromActiveWormholes();
	OO_DEBUG_POP_PROGRESS();

	oo::ReleaseEntity(a_sun);
	if (stationObject != nullptr)  oo::ReleaseEntity(stationObject);
}


void Universe::populateNormalSpace()
{
	const oo::PList		systeminfo = (systemManager != nullptr ? systemManager->getPropertiesForCurrentSystem() : oo::PList());

	BOOL sunGoneNova = systeminfo.get<bool>("sun_gone_nova");
	// check for nova
	if (sunGoneNova)
	{
	 	OO_DEBUG_PUSH_PROGRESS("setUpSpace - post-nova");
		
	 	HPVector v0 = make_HPvector(0,0,34567.89);
	 	double min_safe_dist2 = 6000000.0 * 6000000.0;
		HPVector sunPos = (cachedSun != nullptr ? cachedSun->getPosition() : HPVector{});
	 	while (HPmagnitude2(cachedSun->position) < min_safe_dist2)	// back off the planetary bodies
	 	{
	 		v0.z *= 2.0;
			
	 		sunPos = HPvector_add(sunPos, v0);
	 		if (cachedSun != nullptr)  cachedSun->setPosition(sunPos);  // also sets light origin
			
	 	}
		
	 	removeEntity(cachedPlanet);	// and Poof! it's gone
	 	cachedPlanet = nil;	
	 	removeEntity(cachedStation);	// also remove main station
	 	cachedStation = nil;	
	}

	OO_DEBUG_PUSH_PROGRESS("setUpSpace - populate from hyperpoint");
//	[self populateSpaceFromHyperPoint:witchPos toPlanetPosition: a_planet->position andSunPosition: a_sun->position];
	clearSystemPopulator();

	if ((PLAYER != nullptr ? PLAYER->status() : OOEntityStatus{}) != STATUS_START_GAME)
	{
		const std::string populator = systeminfo.get<std::string>("populator", (sunGoneNova)?"novaSystemWillPopulate":"systemWillPopulate");
		system_repopulator = systeminfo.get<std::string>("repopulator", (sunGoneNova)?"novaSystemWillRepopulate":"systemWillRepopulate");

		ooscript::Context context = OOJSAcquireContext();
		if (PLAYER != nullptr)  PLAYER->doWorldScriptEvent(cxx_OOJSIDFromString(populator), context, NULL, 0, kOOJSLongTimeLimit);
		OOJSRelinquishContext(context);
		populateSystemFromDictionariesWithSun(cachedSun, cachedPlanet);
	}

	OO_DEBUG_POP_PROGRESS();

	// systeminfo might have a 'script_actions' resource we want to activate now...
	const oo::PList *script_actions = systeminfo.get<oo::PList::Array>("script_actions");
	if (script_actions != nullptr)
	{
		cxx_OOStandardsDeprecated(oo::str::format("The script_actions system info key is deprecated for %s.",TextOrNull(getSystemName(systemID)).c_str()));
		if (!OOEnforceStandards())
		{
			OO_DEBUG_PUSH_PROGRESS("setUpSpace - legacy script_actions");
			if (PLAYER != nullptr)  PLAYER->runUnsanitizedScriptActions(*script_actions, NO, "<system script_actions>", nullptr);
			OO_DEBUG_POP_PROGRESS();
		}
	}

	next_repopulation = randf() * SYSTEM_REPOPULATION_INTERVAL;
}


void Universe::clearSystemPopulator()
{
	populatorSettings = oo::PList(oo::PList::Dict{});
}


oo::PList Universe::getPopulatorSettings()
{
	return populatorSettings;
}


void Universe::setPopulatorSetting(const std::string &key, const oo::PList &setting)
{
	if (!populatorSettings.isDict())  populatorSettings = oo::PList(oo::PList::Dict{});
	oo::PList::Dict &settings = *populatorSettings.getIf<oo::PList::Dict>();
	if (setting.isNull())
	{
		settings.erase(key);
	}
	else
	{
		settings[key] = setting;
	}
}


bool Universe::deterministicPopulation()
{
	return deterministic_population;
}


void Universe::populateSystemFromDictionariesWithSun(::OOSunEntity *sun, ::OOPlanetEntity *planet)
{
	Random_Seed systemSeed = (systemManager != nullptr ? systemManager->getRandomSeedForCurrentSystem() : Random_Seed());
	// A copy of the blocks (the callbacks may change the settings), in key byte order (was the
	// dictionary's hash order), then stably sorted by priority: order-sensitive, the goldens decide.
	std::vector<oo::PList> sortedBlocks;
	if (const oo::PList::Dict *blocks = populatorSettings.getIf<oo::PList::Dict>())
	{
		for (const auto &[key, block] : *blocks)  sortedBlocks.push_back(block);
	}
	std::stable_sort(sortedBlocks.begin(), sortedBlocks.end(), populatorPrioritySort);
	HPVector location = kZeroHPVector;
	uint32_t i, locationSeed, groupCount, rndvalue;
	RANROTSeed rndcache = RANROTGetFullSeed();
	RANROTSeed rndlocal = RANROTGetFullSeed();
	std::string locationCode;
	OOJSPopulatorDefinition *pdef = nullptr;
	for (const oo::PList &populator : sortedBlocks)
	{
		deterministic_population = populator.get<bool>("deterministic", NO);
		if (EXPECT_NOT(sun == nil || planet == nil))
		{
			// needs to be a non-nova system, and not interstellar space
			deterministic_population = NO;
		}

		locationSeed = populator.get<unsigned int>("locationSeed", 0);
		groupCount = populator.get<unsigned int>("groupCount", 1);

		for (i = 0; i < groupCount; i++)
		{
			locationCode = populator.get<std::string>("location", "COORDINATES");
			if (locationCode == "COORDINATES")
			{
				location = HPVectorIn(populator, "coordinates", kZeroHPVector);
			}
			else
			{
				if (locationSeed != 0)
				{
					rndcache = RANROTGetFullSeed();
					// different place for each system
					rndlocal = RanrotSeedFromRandomSeed(systemSeed);
					rndvalue = RanrotWithSeed(&rndlocal);
					// ...for location seed
					rndlocal = MakeRanrotSeed(rndvalue+locationSeed);
					rndvalue = RanrotWithSeed(&rndlocal);
					// ...for iteration (63647 is nothing special, just a largish prime)
					RANROTSetFullSeed(MakeRanrotSeed(rndvalue+(i*63647)));
				}
				else
				{
					// not fixed coordinates and not seeded RNG; can't
					// be deterministic
					deterministic_population = NO;
				}
				if (sun == nil || planet == nil)
				{
					// all interstellar space and nova locations equal to WITCHPOINT
					location = locationByCode("WITCHPOINT", nullptr, nullptr);
				}
				else
				{
					location = locationByCode(locationCode, sun, planet);
				}
				if(locationSeed != 0)
				{
					// go back to the main random sequence
					RANROTSetFullSeed(rndcache);
				}			
			}
			// location now contains a Vector coordinate, one way or another
			pdef = OOJSPopulatorDefinitionIn(PListForKeyIn(populator, "callbackObj"));	// an Object node: the populator definition itself
			if (pdef != nullptr)  pdef->runPopulatorCallback(location);	// a message to nil did nothing
		}
	}
	// nothing is deterministic once the populator is done
	deterministic_population = NO;
}




// Slice 5 of docs/phases/3-slices/Universe.md (bead oo-d0i7y): locations by code, lighting, adding
// ships by role, coordinate systems. The facade forwarded each selector (until oo-ql9rn);
// sends to self were sends (ADR-0056 amendment oo-27jxj).

/* Generates a position within one of the named regions:
 *
 * WITCHPOINT: within scanner of witchpoint
 * LANE_*: within two scanner of lane, not too near each end
 * STATION_AEGIS: within two scanner of main station, not in planet
 * *_ORBIT_*: around the object, in a shell relative to object radius
 * TRIANGLE: somewhere in the triangle defined by W, P, S
 * INNER_SYSTEM: closer to the sun than the planet is
 * OUTER_SYSTEM: further from the sun than the planet is
 * *_OFFPLANE: like the above, but not on the orbital plane
 *
 * Can be called with nil sun or planet, but if so the calling function
 * must make sure the location code is WITCHPOINT.
 */
HPVector Universe::locationByCode(const std::string &code, ::OOSunEntity *sun, ::OOPlanetEntity *planet)
{
	HPVector result = kZeroHPVector;
	if (code == "WITCHPOINT" || sun == nil || planet == nil || (sun != nullptr ? sun->goneNova() : false))
	{
		result = OOHPVectorRandomSpatial(SCANNER_MAX_RANGE);
	}
	// past this point, can assume non-nil sun, planet
	else
	{ 
		if (code == "LANE_WPS")
		{	
			// pick position on one of the lanes, weighted by lane length
			double l1 = HPmagnitude((planet != nullptr ? planet->getPosition() : HPVector{}));
			double l2 = HPmagnitude(HPvector_subtract((sun != nullptr ? sun->getPosition() : HPVector{}),(planet != nullptr ? planet->getPosition() : HPVector{})));
			double l3 = HPmagnitude((sun != nullptr ? sun->getPosition() : HPVector{}));
			double total = l1+l2+l3;
			float choice = randf();
			if (choice < l1/total)
			{
				return locationByCode("LANE_WP", sun, planet);
			}
			else if (choice < (l1+l2)/total)
			{
				return locationByCode("LANE_PS", sun, planet);
			}
			else
			{
				return locationByCode("LANE_WS", sun, planet);
			}
		}
		else if (code == "LANE_WP")
		{
			result = OORandomPositionInCylinder(kZeroHPVector,SCANNER_MAX_RANGE,(planet != nullptr ? planet->getPosition() : HPVector{}),(planet != nullptr ? planet->radius() : 0.0)*3,LANE_WIDTH);
		}
		else if (code == "LANE_WS")
		{
			result = OORandomPositionInCylinder(kZeroHPVector,SCANNER_MAX_RANGE,(sun != nullptr ? sun->getPosition() : HPVector{}),(sun != nullptr ? sun->radius() : 0.0)*3,LANE_WIDTH);
		}
		else if (code == "LANE_PS")
		{
			result = OORandomPositionInCylinder((planet != nullptr ? planet->getPosition() : HPVector{}),(planet != nullptr ? planet->radius() : 0.0)*3,(sun != nullptr ? sun->getPosition() : HPVector{}),(sun != nullptr ? sun->radius() : 0.0)*3,LANE_WIDTH);
		}
		else if (code == "STATION_AEGIS")
		{
			do 
			{
				result = OORandomPositionInShell((station() != nullptr ? station()->getPosition() : HPVector{}),(station() != nullptr ? station()->collisionRadius() : 0.0f)*1.2,SCANNER_MAX_RANGE*2.0);
			} while(HPdistance2(result,(planet != nullptr ? planet->getPosition() : HPVector{}))<(planet != nullptr ? planet->radius() : 0.0)*(planet != nullptr ? planet->radius() : 0.0)*1.5);
			// loop to make sure not generated too close to the planet's surface
		}
		else if (code == "PLANET_ORBIT_LOW")
		{
			result = OORandomPositionInShell((planet != nullptr ? planet->getPosition() : HPVector{}),(planet != nullptr ? planet->radius() : 0.0)*1.1,(planet != nullptr ? planet->radius() : 0.0)*2.0);
		}
		else if (code == "PLANET_ORBIT")
		{
			result = OORandomPositionInShell((planet != nullptr ? planet->getPosition() : HPVector{}),(planet != nullptr ? planet->radius() : 0.0)*2.0,(planet != nullptr ? planet->radius() : 0.0)*4.0);
		}
		else if (code == "PLANET_ORBIT_HIGH")
		{
			result = OORandomPositionInShell((planet != nullptr ? planet->getPosition() : HPVector{}),(planet != nullptr ? planet->radius() : 0.0)*4.0,(planet != nullptr ? planet->radius() : 0.0)*8.0);
		}
		else if (code == "STAR_ORBIT_LOW")
		{
			result = OORandomPositionInShell((sun != nullptr ? sun->getPosition() : HPVector{}),(sun != nullptr ? sun->radius() : 0.0)*1.1,(sun != nullptr ? sun->radius() : 0.0)*2.0);
		}
		else if (code == "STAR_ORBIT")
		{
			result = OORandomPositionInShell((sun != nullptr ? sun->getPosition() : HPVector{}),(sun != nullptr ? sun->radius() : 0.0)*2.0,(sun != nullptr ? sun->radius() : 0.0)*4.0);
		}
		else if (code == "STAR_ORBIT_HIGH")
		{
			result = OORandomPositionInShell((sun != nullptr ? sun->getPosition() : HPVector{}),(sun != nullptr ? sun->radius() : 0.0)*4.0,(sun != nullptr ? sun->radius() : 0.0)*8.0);
		}
		else if (code == "TRIANGLE")
		{
			do {
				// pick random point in triangle by algorithm at
				// http://adamswaab.wordpress.com/2009/12/11/random-point-in-a-triangle-barycentric-coordinates/
				// simplified by using the origin as A
				OOScalar r = randf();
				OOScalar s = randf();
				if (r+s >= 1)
				{
					r = 1-r;
					s = 1-s;
				}
				result = HPvector_add(HPvector_multiply_scalar((planet != nullptr ? planet->getPosition() : HPVector{}),r),HPvector_multiply_scalar((sun != nullptr ? sun->getPosition() : HPVector{}),s));
			}
			// make sure at least 3 radii from vertices
			while(HPdistance2(result,(sun != nullptr ? sun->getPosition() : HPVector{})) < (sun != nullptr ? sun->radius() : 0.0)*(sun != nullptr ? sun->radius() : 0.0)*9.0 || HPdistance2(result,(planet != nullptr ? planet->getPosition() : HPVector{})) < (planet != nullptr ? planet->radius() : 0.0)*(planet != nullptr ? planet->radius() : 0.0)*9.0 || HPmagnitude2(result) < SCANNER_MAX_RANGE2 * 9.0);
		}
		else if (code == "INNER_SYSTEM")
		{
			do {
				result = OORandomPositionInShell((sun != nullptr ? sun->getPosition() : HPVector{}),(sun != nullptr ? sun->radius() : 0.0)*3.0,HPdistance((sun != nullptr ? sun->getPosition() : HPVector{}),(planet != nullptr ? planet->getPosition() : HPVector{})));
				result = OOProjectHPVectorToPlane(result,kZeroHPVector,HPcross_product((sun != nullptr ? sun->getPosition() : HPVector{}),(planet != nullptr ? planet->getPosition() : HPVector{})));
				result = HPvector_add(result,OOHPVectorRandomSpatial((planet != nullptr ? planet->radius() : 0.0)));
				// projection to plane could bring back too close to sun
			} while (HPdistance2(result,(sun != nullptr ? sun->getPosition() : HPVector{})) < (sun != nullptr ? sun->radius() : 0.0)*(sun != nullptr ? sun->radius() : 0.0)*9.0);
		}
		else if (code == "INNER_SYSTEM_OFFPLANE")
		{
			result = OORandomPositionInShell((sun != nullptr ? sun->getPosition() : HPVector{}),(sun != nullptr ? sun->radius() : 0.0)*3.0,HPdistance((sun != nullptr ? sun->getPosition() : HPVector{}),(planet != nullptr ? planet->getPosition() : HPVector{})));
		}
		else if (code == "OUTER_SYSTEM")
		{
			result = OORandomPositionInShell((sun != nullptr ? sun->getPosition() : HPVector{}),HPdistance((sun != nullptr ? sun->getPosition() : HPVector{}),(planet != nullptr ? planet->getPosition() : HPVector{})),HPdistance((sun != nullptr ? sun->getPosition() : HPVector{}),(planet != nullptr ? planet->getPosition() : HPVector{}))*10.0); // no more than 10 AU out
			result = OOProjectHPVectorToPlane(result,kZeroHPVector,HPcross_product((sun != nullptr ? sun->getPosition() : HPVector{}),(planet != nullptr ? planet->getPosition() : HPVector{})));
			result = HPvector_add(result,OOHPVectorRandomSpatial(0.01*HPdistance(result,(sun != nullptr ? sun->getPosition() : HPVector{})))); // within 1% of plane
		}
		else if (code == "OUTER_SYSTEM_OFFPLANE")
		{
			result = OORandomPositionInShell((sun != nullptr ? sun->getPosition() : HPVector{}),HPdistance((sun != nullptr ? sun->getPosition() : HPVector{}),(planet != nullptr ? planet->getPosition() : HPVector{})),HPdistance((sun != nullptr ? sun->getPosition() : HPVector{}),(planet != nullptr ? planet->getPosition() : HPVector{}))*10.0); // no more than 10 AU out
		}
		else
		{
			OO_LOG(kOOLogUniversePopulateError, "Named populator region {} is not implemented, falling back to WITCHPOINT", code); 
			result = OOHPVectorRandomSpatial(SCANNER_MAX_RANGE);
		}
	}
	return result;
}


void Universe::setAmbientLightLevel(float newValue)
{
	OOCAssert(UNIVERSE != nil, "Attempt to set ambient light level with a non yet existent universe.");
	
	ambientLightLevel = OOClamp_0_max_f(newValue, 10.0f);
	return;
}


float Universe::getAmbientLightLevel()
{
	return ambientLightLevel;
}


void Universe::setLighting()
{
	/*
	
	GL_LIGHT1 is the sun and is active while a sun exists in space
	where there is no sun (witch/interstellar space) this is placed at the origin
	
	Shaders: this light is also used inside the station and needs to have its position reset
	relative to the player whenever demo ships or background scenes are to be shown -- 20100111
	
	
	GL_LIGHT0 is the light for inside the station and needs to have its position reset
	relative to the player whenever demo ships or background scenes are to be shown
	
	Shaders: this light is not used.  -- 20100111
	
	*/
	
	::OOSunEntity		*the_sun = sun();
	::SkyEntity		*the_sky = nullptr;
	GLfloat			sun_pos[] = {0.0, 0.0, 0.0, 1.0};	// equivalent to kZeroVector - for interstellar space.
	GLfloat			sun_ambient[] = {0.0, 0.0, 0.0, 1.0};	// overridden later in code
	int i;
	
	// The sky is C++ since bead oo-9ht.109: found by its C++ part (it was -isKindOfClass:).
	for (i = n_entities - 1; i > 0; i--)
		if (sortedEntities[i] != nil)
			if (::SkyEntity *sky = dynamic_cast<::SkyEntity *>(sortedEntities[i]))
				the_sky = sky;
	
	if (the_sun)
	{
		if (the_sun != nullptr)  the_sun->getDiffuseComponents(sun_diffuse);
		if (the_sun != nullptr)  the_sun->getSpecularComponents(sun_specular);
		OOGL(glLightfv(GL_LIGHT1, GL_AMBIENT, sun_ambient));
		OOGL(glLightfv(GL_LIGHT1, GL_DIFFUSE, sun_diffuse));
		OOGL(glLightfv(GL_LIGHT1, GL_SPECULAR, sun_specular));
		sun_pos[0] = the_sun->position.x;
		sun_pos[1] = the_sun->position.y;
		sun_pos[2] = the_sun->position.z;
	}
	else
	{
		// witchspace
		stars_ambient[0] = 0.05;	stars_ambient[1] = 0.20;	stars_ambient[2] = 0.05;	stars_ambient[3] = 1.0;
		sun_diffuse[0] = 0.85;	sun_diffuse[1] = 1.0;	sun_diffuse[2] = 0.85;	sun_diffuse[3] = 1.0;
		sun_specular[0] = 0.95;	sun_specular[1] = 1.0;	sun_specular[2] = 0.95;	sun_specular[3] = 1.0;
		OOGL(glLightfv(GL_LIGHT1, GL_AMBIENT, sun_ambient));
		OOGL(glLightfv(GL_LIGHT1, GL_DIFFUSE, sun_diffuse));
		OOGL(glLightfv(GL_LIGHT1, GL_SPECULAR, sun_specular));
	}
	
	OOGL(glLightfv(GL_LIGHT1, GL_POSITION, sun_pos));
	
	if (the_sky)
	{
		// ambient lighting!
		GLfloat r,g,b,a;
		if (::OOColor *skyColor = the_sky->getSkyColor())  skyColor->getRed(&r, &g, &b, &a);
		else  r = g = b = a = 0.0f;	// a nil colour wrote nothing; zero, as a message to nil answers
		r = r * (1.0 - SUN_AMBIENT_INFLUENCE) + sun_diffuse[0] * SUN_AMBIENT_INFLUENCE;
		g = g * (1.0 - SUN_AMBIENT_INFLUENCE) + sun_diffuse[1] * SUN_AMBIENT_INFLUENCE;
		b = b * (1.0 - SUN_AMBIENT_INFLUENCE) + sun_diffuse[2] * SUN_AMBIENT_INFLUENCE;
		GLfloat ambient_level = getAmbientLightLevel();
		stars_ambient[0] = ambient_level * SKY_AMBIENT_ADJUSTMENT * (1.0 + r) * (1.0 + r);
		stars_ambient[1] = ambient_level * SKY_AMBIENT_ADJUSTMENT * (1.0 + g) * (1.0 + g);
		stars_ambient[2] = ambient_level * SKY_AMBIENT_ADJUSTMENT * (1.0 + b) * (1.0 + b);
		stars_ambient[3] = 1.0;
	}
	
	// light for demo ships display..
	OOGL(glLightfv(GL_LIGHT0, GL_AMBIENT, docked_light_ambient));
	OOGL(glLightfv(GL_LIGHT0, GL_DIFFUSE, docked_light_diffuse));
	OOGL(glLightfv(GL_LIGHT0, GL_SPECULAR, docked_light_specular));
	OOGL(glLightfv(GL_LIGHT0, GL_POSITION, demo_light_position));	
	OOGL(glLightModelfv(GL_LIGHT_MODEL_AMBIENT, stars_ambient));
}


// Call this method to avoid lighting glich after windowed/fullscreen transition on macs.
void Universe::forceLightSwitch()
{
	demo_light_on = !demo_light_on;
}


void Universe::setMainLightPosition(Vector sunPos)
{
	main_light_position[0] = sunPos.x;
	main_light_position[1] = sunPos.y;
	main_light_position[2] = sunPos.z;
	main_light_position[3] = 1.0;
}


::ShipEntity * Universe::addShipWithRole(const std::string &desc, HPVector launchPos, GLfloat rfactor)
{
	if (rfactor != 0.0)
	{
		// Calculate the position as soon as possible, to minimise 'lollipop flash'
	 	launchPos.x += 2 * rfactor * (randf() - 0.5);
		launchPos.y += 2 * rfactor * (randf() - 0.5);
		launchPos.z += 2 * rfactor * (randf() - 0.5);
	}
	
	::ShipEntity  *ship = newShipWithRole(desc);   // retain count = 1

	if (ship)
	{
		if (ship != nullptr)  ship->setPosition(launchPos);	// minimise 'lollipop flash'

		// Deal with scripted cargopods and ensure they are filled with something.
		if ((ship != nullptr ? ship->hasRole("cargopod") : false))  fillCargopodWithRandomCargo(ship);

		// Ensure piloted ships have pilots.
		if (!(ship != nullptr ? ship->getCrew() : std::optional<std::vector<oo::Ref<OOCharacter>>>()).has_value() && !(ship != nullptr ? ship->isUnpiloted() : false))
			if (ship != nullptr)  ship->setCrew(std::vector<oo::Ref<OOCharacter>>{ oo::Ref<OOCharacter>( OOCharacter::randomCharacterWithRole(desc, Ranrot() & 255)) });
		
		if ((ship != nullptr ? ship->getScanClass() : OOScanClass{}) == CLASS_NOT_SET)
		{
			if (ship != nullptr)  ship->setScanClass(CLASS_NEUTRAL);
		}
		addEntity(ship);	// STATUS_IN_FLIGHT, AI state GLOBAL
		if (ship != nullptr)  oo::ReleaseEntity(ship);
		return ship;
	}
	return nil;
}


void Universe::addShipWithRole(const std::string &desc, double route_fraction)
{
	// adds a ship within scanner range of a point on route 1
	
	::StationEntity	*theStation = station();
	if (!theStation)
	{
		return;
	}
	
	HPVector	launchPos = OOHPVectorInterpolate(getWitchspaceExitPosition(), theStation->getPosition(), route_fraction);
	
	addShipWithRole(desc, launchPos, SCANNER_MAX_RANGE);
}


HPVector Universe::coordinatesForPosition(HPVector pos, const std::string &system, GLfloat *my_scalar)
{
	/*	the point is described using a system selected by a string
		consisting of a three letter code.
		
		The first letter indicates the feature that is the origin of the coordinate system.
			w => witchpoint
			s => sun
			p => planet
			
		The next letter indicates the feature on the 'z' axis of the coordinate system.
			w => witchpoint
			s => sun
			p => planet
			
		Then the 'y' axis of the system is normal to the plane formed by the planet, sun and witchpoint.
		And the 'x' axis of the system is normal to the y and z axes.
		So:
			ps:		z axis = (planet -> sun)		y axis = normal to (planet - sun - witchpoint)	x axis = normal to y and z axes
			pw:		z axis = (planet -> witchpoint)	y axis = normal to (planet - witchpoint - sun)	x axis = normal to y and z axes
			sp:		z axis = (sun -> planet)		y axis = normal to (sun - planet - witchpoint)	x axis = normal to y and z axes
			sw:		z axis = (sun -> witchpoint)	y axis = normal to (sun - witchpoint - planet)	x axis = normal to y and z axes
			wp:		z axis = (witchpoint -> planet)	y axis = normal to (witchpoint - planet - sun)	x axis = normal to y and z axes
			ws:		z axis = (witchpoint -> sun)	y axis = normal to (witchpoint - sun - planet)	x axis = normal to y and z axes
			
		The third letter denotes the units used:
			m:		meters
			p:		planetary radii
			s:		solar radii
			u:		distance between first two features indicated (eg. spu means that u = distance from sun to the planet)
		
		in interstellar space (== no sun) coordinates are absolute irrespective of the system used.
		
		[1.71] The position code "abs" can also be used for absolute coordinates.
		
	*/
	
	const std::string l_sys = oo::str::lowercase(system);
	if (oo::str::length(l_sys) != 3)	// UTF-16 units, as -length counted
		return kZeroHPVector;
	::OOPlanetEntity* the_planet = planet();
	::OOSunEntity* the_sun = sun();
	if (the_planet == nil || the_sun == nil || l_sys == "abs")
	{
		if (my_scalar)  *my_scalar = 1.0;
		return pos;
	}
	HPVector  w_pos = getWitchspaceExitPosition();	// don't reset PRNG
	HPVector  p_pos = the_planet->position;	// the planet is C++ since bead oo-9ht.129
	HPVector  s_pos = the_sun->position;

	const char* c_sys = l_sys.c_str();
	HPVector p0, p1, p2;
	
	switch (c_sys[0])
	{
		case 'w':
			p0 = w_pos;
			switch (c_sys[1])
			{
				case 'p':
					p1 = p_pos;	p2 = s_pos;	break;
				case 's':
					p1 = s_pos;	p2 = p_pos;	break;
				default:
					return kZeroHPVector;
			}
			break;
		case 'p':		
			p0 = p_pos;
			switch (c_sys[1])
			{
				case 'w':
					p1 = w_pos;	p2 = s_pos;	break;
				case 's':
					p1 = s_pos;	p2 = w_pos;	break;
				default:
					return kZeroHPVector;
			}
			break;
		case 's':
			p0 = s_pos;
			switch (c_sys[1])
			{
				case 'w':
					p1 = w_pos;	p2 = p_pos;	break;
				case 'p':
					p1 = p_pos;	p2 = w_pos;	break;
				default:
					return kZeroHPVector;
			}
			break;
		default:
			return kZeroHPVector;
	}
	HPVector k = HPvector_normal_or_zbasis(HPvector_subtract(p1, p0));	// 'forward'
	HPVector v = HPvector_normal_or_xbasis(HPvector_subtract(p2, p0));	// temporary vector in plane of 'forward' and 'right'
	
	HPVector j = HPcross_product(k, v);	// 'up'
	HPVector i = HPcross_product(j, k);	// 'right'
	
	GLfloat scale = 1.0;
	switch (c_sys[2])
	{
		case 'p':
			scale = (the_planet != nullptr ? the_planet->radius() : 0.0);
			break;
			
		case 's':
			scale = (the_sun != nullptr ? the_sun->radius() : 0.0);
			break;
			
		case 'u':
			scale = HPmagnitude(HPvector_subtract(p1, p0));
			break;
			
		case 'm':
			scale = 1.0f;
			break;
			
		default:
			return kZeroHPVector;
	}
	if (my_scalar)
		*my_scalar = scale;
	
	// result = p0 + ijk
	HPVector result = p0;	// origin
	result.x += scale * (pos.x * i.x + pos.y * j.x + pos.z * k.x);
	result.y += scale * (pos.x * i.y + pos.y * j.y + pos.z * k.y);
	result.z += scale * (pos.x * i.z + pos.y * j.z + pos.z * k.z);
	
	return result;
}


std::optional<std::string> Universe::expressPosition(HPVector pos, const std::string &system)
{
	HPVector result = legacyPositionFrom(pos, system);
	return oo::str::format("%s %.2f %.2f %.2f", system.c_str(), result.x, result.y, result.z);
}




// Slice 6 of docs/phases/3-slices/Universe.md (bead oo-15e3o): legacy positions, adding ships at /
// near positions and in boxes, spawning, visual effects. The facade forwarded each selector
// (until oo-ql9rn); sends to self were sends (ADR-0056 amendment oo-27jxj).

HPVector Universe::legacyPositionFrom(HPVector pos, const std::string &system)
{
	const std::string l_sys = oo::str::lowercase(system);
	if (oo::str::length(l_sys) != 3)	// UTF-16 units, as -length counted
		return kZeroHPVector;
	::OOPlanetEntity* the_planet = planet();
	::OOSunEntity* the_sun = sun();
	if (the_planet == nil || the_sun == nil || l_sys == "abs")
	{
		return pos;
	}
	HPVector  w_pos = getWitchspaceExitPosition();	// don't reset PRNG
	HPVector  p_pos = the_planet->position;	// the planet is C++ since bead oo-9ht.129
	HPVector  s_pos = the_sun->position;

	const char* c_sys = l_sys.c_str();
	HPVector p0, p1, p2;
	
	switch (c_sys[0])
	{
		case 'w':
			p0 = w_pos;
			switch (c_sys[1])
			{
				case 'p':
					p1 = p_pos;	p2 = s_pos;	break;
				case 's':
					p1 = s_pos;	p2 = p_pos;	break;
				default:
					return kZeroHPVector;
			}
			break;
		case 'p':		
			p0 = p_pos;
			switch (c_sys[1])
			{
				case 'w':
					p1 = w_pos;	p2 = s_pos;	break;
				case 's':
					p1 = s_pos;	p2 = w_pos;	break;
				default:
					return kZeroHPVector;
			}
			break;
		case 's':
			p0 = s_pos;
			switch (c_sys[1])
			{
				case 'w':
					p1 = w_pos;	p2 = p_pos;	break;
				case 'p':
					p1 = p_pos;	p2 = w_pos;	break;
				default:
					return kZeroHPVector;
			}
			break;
		default:
			return kZeroHPVector;
	}
	HPVector k = HPvector_normal_or_zbasis(HPvector_subtract(p1, p0));	// 'z' axis in m
	HPVector v = HPvector_normal_or_xbasis(HPvector_subtract(p2, p0));	// temporary vector in plane of 'forward' and 'right'
	
	HPVector j = HPcross_product(k, v);	// 'y' axis in m
	HPVector i = HPcross_product(j, k);	// 'x' axis in m
	
	GLfloat scale = 1.0;
	switch (c_sys[2])
	{
		case 'p':
		{
			scale = 1.0f / (the_planet != nullptr ? the_planet->radius() : 0.0);
			break;
		}
		case 's':
		{
			scale = 1.0f / (the_sun != nullptr ? the_sun->radius() : 0.0);
			break;
		}
			
		case 'u':
			scale = 1.0f / HPdistance(p1, p0);
			break;
			
		case 'm':
			scale = 1.0f;
			break;
			
		default:
			return kZeroHPVector;
	}
	
	// result = p0 + ijk
	HPVector r_pos = HPvector_subtract(pos, p0);
	HPVector result = make_HPvector(scale * (r_pos.x * i.x + r_pos.y * i.y + r_pos.z * i.z),
								scale * (r_pos.x * j.x + r_pos.y * j.y + r_pos.z * j.z),
								scale * (r_pos.x * k.x + r_pos.y * k.y + r_pos.z * k.z) ); // scale * dot_products
	
	return result;
}


HPVector Universe::coordinatesFromCoordinateSystemString(const std::string &system_x_y_z)
{
	const std::vector<std::string> tokens = oo::str::tokens(system_x_y_z);
	if (tokens.size() != 4)
	{
		// Not necessarily an error.
		return make_HPvector(0,0,0);
	}
	// each number read as at<float> read the token string before
	oo::PList::Array tokenList;
	for (const std::string &token : tokens)  tokenList.push_back(oo::PList(token));
	const oo::PList tokenPList(std::move(tokenList));
	GLfloat dummy;
	return coordinatesForPosition(make_HPvector(tokenPList.at<float>(1), tokenPList.at<float>(2), tokenPList.at<float>(3)), tokens[0], &dummy);
}


bool Universe::addShipWithRole(const std::string &desc, HPVector pos, const std::string &system)
{
	// initial position
	GLfloat scalar = 1.0;
	HPVector launchPos = coordinatesForPosition(pos, system, &scalar);
	//	randomise
	GLfloat rfactor = scalar;
	if (rfactor > SCANNER_MAX_RANGE)
		rfactor = SCANNER_MAX_RANGE;
	if (rfactor < 1000)
		rfactor = 1000;
	
	return (addShipWithRole(desc, launchPos, rfactor) != nil);
}


bool Universe::addShipsAtPosition(int howMany, const std::string &desc, HPVector pos, const std::string &system)
{
	// initial bounding box
	GLfloat scalar = 1.0;
	HPVector launchPos = coordinatesForPosition(pos, system, &scalar);
	GLfloat distance_from_center = 0.0;
	HPVector v_from_center, ship_pos;
	std::vector<HPVector> ship_positions(howMany);
	int i = 0;
	int	scale_up_after = 0;
	int	current_shell = 0;
	GLfloat	walk_factor = 2.0;
	while (i < howMany)
	{
	 	::ShipEntity  *ship = addShipWithRole(desc, launchPos, 0.0);
		if (ship == nil) return NO;
		OOScanClass scanClass = (ship != nullptr ? ship->getScanClass() : OOScanClass{});
		if (ship != nullptr)  ship->setScanClass(CLASS_NO_DRAW);	// avoid lollipop flash
		
		GLfloat		safe_distance2 = ship->collision_radius * ship->collision_radius * SAFE_ADDITION_FACTOR2;
		BOOL		safe;
		int			limit_count = 8;
		
		v_from_center = kZeroHPVector;
		do
		{
			do
			{
				v_from_center.x += walk_factor * (randf() - 0.5);
				v_from_center.y += walk_factor * (randf() - 0.5);
				v_from_center.z += walk_factor * (randf() - 0.5);	// drunkards walk
			} while ((v_from_center.x == 0.0)&&(v_from_center.y == 0.0)&&(v_from_center.z == 0.0));
			v_from_center = HPvector_normal(v_from_center);	// guaranteed non-zero
			
			ship_pos = make_HPvector(	launchPos.x + distance_from_center * v_from_center.x,
									launchPos.y + distance_from_center * v_from_center.y,
									launchPos.z + distance_from_center * v_from_center.z);
			
			// check this position against previous ship positions in this shell
			safe = YES;
			int j = i - 1;
			while (safe && (j >= current_shell))
			{
				safe = (safe && (HPdistance2(ship_pos, ship_positions[j]) > safe_distance2));
				j--;
			}
			if (!safe)
			{
				limit_count--;
				if (!limit_count)	// give up and expand the shell
				{
					limit_count = 8;
					distance_from_center += sqrt(safe_distance2);	// expand to the next distance
				}
			}
			
		} while (!safe);
		
		if (ship != nullptr)  ship->setPosition(ship_pos);
		if (ship != nullptr)  ship->setScanClass(scanClass == CLASS_NOT_SET ? CLASS_NEUTRAL : scanClass);
		
		Quaternion qr;
		quaternion_set_random(&qr);
		if (ship != nullptr)  ship->setOrientation(qr);
		
		// [self addEntity:ship];	// STATUS_IN_FLIGHT, AI state GLOBAL
		
		ship_positions[i] = ship_pos;
		i++;
		if (i > scale_up_after)
		{
			current_shell = i;
			scale_up_after += 1 + 2 * i;
			distance_from_center += sqrt(safe_distance2);	// fill the next shell
		}
	}
	return YES;
}


bool Universe::addShipsNearPosition(int howMany, const std::string &desc, HPVector pos, const std::string &system)
{
	// initial bounding box
	GLfloat scalar = 1.0;
	HPVector launchPos = coordinatesForPosition(pos, system, &scalar);
	GLfloat rfactor = scalar;
	if (rfactor > SCANNER_MAX_RANGE)
		rfactor = SCANNER_MAX_RANGE;
	if (rfactor < 1000)
		rfactor = 1000;
	BoundingBox	launch_bbox;
	bounding_box_reset_to_vector(&launch_bbox, make_vector(launchPos.x - rfactor, launchPos.y - rfactor, launchPos.z - rfactor));
	bounding_box_add_xyz(&launch_bbox, launchPos.x + rfactor, launchPos.y + rfactor, launchPos.z + rfactor);
	
	return addShips(howMany, desc, launch_bbox);
}


bool Universe::addShipsNearPosition(int howMany, const std::string &desc, HPVector pos, const std::string &system, GLfloat radius)
{
	// initial bounding box
	GLfloat scalar = 1.0;
	HPVector launchPos = coordinatesForPosition(pos, system, &scalar);
	GLfloat rfactor = radius;
	if (rfactor < 1000)
		rfactor = 1000;
	BoundingBox	launch_bbox;
	bounding_box_reset_to_vector(&launch_bbox, make_vector(launchPos.x - rfactor, launchPos.y - rfactor, launchPos.z - rfactor));
	bounding_box_add_xyz(&launch_bbox, launchPos.x + rfactor, launchPos.y + rfactor, launchPos.z + rfactor);
	
	return addShips(howMany, desc, launch_bbox);
}


bool Universe::addShips(int howMany, const std::string &desc, BoundingBox bbox)
{
	if (howMany < 1)
		return YES;
	if (howMany > 1)
	{
		// divide the number of ships in two
		int h0 = howMany / 2;
		int h1 = howMany - h0;
		// split the bounding box into two along its longest dimension
		GLfloat lx = bbox.max.x - bbox.min.x;
		GLfloat ly = bbox.max.y - bbox.min.y;
		GLfloat lz = bbox.max.z - bbox.min.z;
		BoundingBox bbox0 = bbox;
		BoundingBox bbox1 = bbox;
		if ((lx > lz)&&(lx > ly))	// longest dimension is x
		{
			bbox0.min.x += 0.5 * lx;
			bbox1.max.x -= 0.5 * lx;
		}
		else
		{
			if (ly > lz)	// longest dimension is y
			{
				bbox0.min.y += 0.5 * ly;
				bbox1.max.y -= 0.5 * ly;
			}
			else			// longest dimension is z
			{
				bbox0.min.z += 0.5 * lz;
				bbox1.max.z -= 0.5 * lz;
			}
		}
		// place half the ships into each bounding box
		return (addShips(h0, desc, bbox0) && addShips(h1, desc, bbox1));
	}
	
	//	randomise within the bounding box (biased towards the center of the box)
	HPVector pos = make_HPvector(bbox.min.x, bbox.min.y, bbox.min.z);
	pos.x += 0.5 * (randf() + randf()) * (bbox.max.x - bbox.min.x);
	pos.y += 0.5 * (randf() + randf()) * (bbox.max.y - bbox.min.y);
	pos.z += 0.5 * (randf() + randf()) * (bbox.max.z - bbox.min.z);
	
	return (addShipWithRole(desc, pos, 0.0) != nil);
}


bool Universe::spawnShip(const std::string &shipdesc)
{
	// no need to do any more than log - enforcing modes wouldn't even have
	// loaded the legacy script
	cxx_OOStandardsDeprecated(oo::str::format("'spawn' via legacy script is deprecated as a way of adding ships for %s", shipdesc.c_str()));

	::ShipEntity		*ship;
	oo::PList		shipdict;

	shipdict = OOShipRegistry::sharedRegistry()->shipInfoForKey(shipdesc);
	if (shipdict.isNull())  return NO;

	ship = newShipWithName(shipdesc);	// retain count is 1

	if (ship == nil)  return NO;

	// set any spawning characteristics
	const oo::PList	*spawnEntry = shipdict.get<oo::PList::Dict>("spawn");
	const oo::PList	spawndict = (spawnEntry != nullptr) ? *spawnEntry : oo::PList();
	HPVector			pos, rpos, spos;
	std::optional<std::string>	positionString;

	// position
	positionString = OptionalStringIn(spawndict, "position");
	if (positionString.has_value())
	{
		if(oo::str::hasPrefix(*positionString, "abs ") && (planet() != nil || sun() !=nil))
		{
			OO_LOG_WARN("script.deprecated", "setting {} for {} '{}' in 'abs' inside .plists can cause compatibility issues across Oolite versions. Use coordinates relative to main system objects instead.", "position", "entity", shipdesc);
		}

		pos = coordinatesFromCoordinateSystemString(*positionString);
	}
	else
	{
		// without position defined, the ship will be added on top of the witchpoint buoy.
		pos = OOHPVectorRandomRadial(SCANNER_MAX_RANGE);
		OO_LOG_ERR("universe.spawnShip.error", "***** ERROR: failed to find a spawn position for ship {}.", shipdesc);
	}
	if (ship != nullptr)  ship->setPosition(pos);

	// facing_position
	positionString = OptionalStringIn(spawndict, "facing_position");
	if (positionString.has_value())
	{
		if(oo::str::hasPrefix(*positionString, "abs ") && (planet() != nil || sun() !=nil))
		{
			OO_LOG_WARN("script.deprecated", "setting {} for {} '{}' in 'abs' inside .plists can cause compatibility issues across Oolite versions. Use coordinates relative to main system objects instead.", "facing_position", "entity", shipdesc);
		}

		spos = (ship != nullptr ? ship->getPosition() : HPVector{});
		Quaternion q1;
		rpos = coordinatesFromCoordinateSystemString(*positionString);
		rpos = HPvector_subtract(rpos, spos); // position relative to ship
		
		if (!HPvector_equal(rpos, kZeroHPVector))
		{
			rpos = HPvector_normal(rpos);
			
			if (!HPvector_equal(rpos, HPvector_flip(kBasisZHPVector)))
			{
				q1 = quaternion_rotation_between(HPVectorToVector(rpos), kBasisZVector);
			}
			else
			{
				// for the inverse of the kBasisZVector the rotation is undefined, so we select one.
				q1 = make_quaternion(0,1,0,0);
			}
			
						
			if (ship != nullptr)  ship->setOrientation(q1);
		}
	}
	
	addEntity(ship);	// STATUS_IN_FLIGHT, AI state GLOBAL
	if (ship != nullptr)  oo::ReleaseEntity(ship);
	
	return YES;
}


void Universe::witchspaceShipWithPrimaryRole(const std::string &role)
{
	// adds a ship exiting witchspace (corollary of when ships leave the system)
	::ShipEntity			*ship = nil;
	oo::PList			systeminfo;
	OOGovernmentID		government;

	systeminfo = currentSystemData();
 	government = systeminfo.get<unsigned char>(std::string(KEY_GOVERNMENT));

	ship = newShipWithRole(role);   // retain count = 1
	
	// Deal with scripted cargopods and ensure they are filled with something.
	if (ship && (ship != nullptr ? ship->hasRole("cargopod") : false))
	{		
		fillCargopodWithRandomCargo(ship);
	}
	
	if (ship)
	{
		if (((ship != nullptr ? ship->getScanClass() : OOScanClass{}) == CLASS_NO_DRAW)||((ship != nullptr ? ship->getScanClass() : OOScanClass{}) == CLASS_NOT_SET))
			if (ship != nullptr)  ship->setScanClass(CLASS_NEUTRAL);
		if (role == "trader")
		{
			if (ship != nullptr)  ship->setCargoFlag(CARGO_FLAG_FULL_SCARCE);
			if ((ship != nullptr ? ship->hasRole("sunskim-trader") : false) && randf() < 0.25) // select 1/4 of the traders suitable for sunskimming.
			{
				if (ship != nullptr)  ship->setCargoFlag(CARGO_FLAG_FULL_PLENTIFUL);
				makeSunSkimmer(ship, YES);
			}
			else
			{
				if (ship != nullptr)  ship->switchAITo("oolite-traderAI.js");
			}
			
			if (((ship != nullptr ? ship->pendingEscortCount() : uint8_t{}) > 0)&&((Ranrot() % 7) < government))	// remove escorts if we feel safe
			{
				int nx = (ship != nullptr ? ship->pendingEscortCount() : uint8_t{}) - 2 * (1 + (Ranrot() & 3));	// remove 2,4,6, or 8 escorts
				if (ship != nullptr)  ship->setPendingEscortCount((nx > 0) ? nx : 0);
			}
		}
		if (role == "pirate")
		{
			if (ship != nullptr)  ship->setCargoFlag(CARGO_FLAG_PIRATE);
			if (ship != nullptr)  ship->setBounty((Ranrot() & 7) + (Ranrot() & 7) + ((randf() < 0.05)? 63 : 23), kOOLegalStatusReasonSetup);	// they already have a price on their heads
		}
		if (!(ship != nullptr ? ship->getCrew() : std::optional<std::vector<oo::Ref<OOCharacter>>>()).has_value() && !(ship != nullptr ? ship->isUnpiloted() : false))
			if (ship != nullptr)  ship->setCrew(std::vector<oo::Ref<OOCharacter>>{ oo::Ref<OOCharacter>( OOCharacter::randomCharacterWithRole(role, Ranrot() & 255)) });
		// The following is set inside leaveWitchspace: AI state GLOBAL, STATUS_EXITING_WITCHSPACE, ai message: EXITED_WITCHSPACE, then STATUS_IN_FLIGHT
		if (ship != nullptr)  ship->leaveWitchspace();
		if (ship != nullptr)  oo::ReleaseEntity(ship);
	}
}


// adds a ship within the collision radius of the other entity
::ShipEntity * Universe::spawnShipWithRole(const std::string &desc, Entity *entity)
{
	if (entity == nullptr)  return nil;
	
	::ShipEntity  *ship = nil;
	HPVector		spawn_pos;
	Quaternion	spawn_q;
	GLfloat		offset = (randf() + randf()) * entity->collision_radius;
	
	quaternion_set_random(&spawn_q);
	spawn_pos = HPvector_add(entity->getPosition(), vectorToHPVector(vector_multiply_scalar(vector_forward_from_quaternion(spawn_q), offset)));
	
	ship = addShipWithRole(desc, spawn_pos, 0.0);
	if (ship != nullptr)  ship->setOrientation(spawn_q);
	
	return ship;
}


Entity * Universe::addVisualEffectAt(HPVector pos, const std::string &key)
{
	OOJS_PROFILE_ENTER

	// minimise the time between creating ship & assigning position.

	Entity  		*vis = newVisualEffectWithName(key); // is retained (the effect's object, bead oo-9ht.165)
	BOOL				success = NO;
	if (vis != nullptr)
	{
		vis->setPosition(pos);
		vis->setOrientation(OORandomQuaternion());
		
		success = addEntity(vis); // retained globally now
		
		oo::ReleaseEntity(vis);
	}
	return success ? vis : nullptr;
	
	OOJS_PROFILE_EXIT
}




// Slice 7 of docs/phases/3-slices/Universe.md (bead oo-49wmm): adding ships within a radius and on
// routes, role categories, witchspace entries and effects, break patterns, the docking clearance
// protocol, game over. The facade forwarded each selector (until oo-ql9rn); sends to self
// were sends (ADR-0056 amendment oo-27jxj).

::ShipEntity * Universe::addShipAt(HPVector pos, const std::string &role, GLfloat radius)
{
	OOJS_PROFILE_ENTER

	// minimise the time between creating ship & assigning position.
	if (radius == static_cast<GLfloat>(NSNotFound))
	{
		GLfloat scalar = 1.0;
		coordinatesForPosition(pos, "abs", &scalar);
		//	randomise
		GLfloat rfactor = scalar;
		if (rfactor > SCANNER_MAX_RANGE)
			rfactor = SCANNER_MAX_RANGE;
		if (rfactor < 1000)
			rfactor = 1000;
		pos.x += rfactor*(randf() - randf());
		pos.y += rfactor*(randf() - randf());
		pos.z += rfactor*(randf() - randf());
	}
	else
	{
		pos = HPvector_add(pos, OOHPVectorRandomSpatial(radius));
	}
	
	::ShipEntity  		*ship = newShipWithRole(role); // is retained
	BOOL				success = NO;
	
	if (ship != nil)
	{
		if (ship != nullptr)  ship->setPosition(pos);
		if ((ship != nullptr ? ship->hasRole("cargopod") : false)) fillCargopodWithRandomCargo(ship);
		OOScanClass scanClass = (ship != nullptr ? ship->getScanClass() : OOScanClass{});
		if (scanClass == CLASS_NOT_SET)
		{
			scanClass = CLASS_NEUTRAL;
			if (ship != nullptr)  ship->setScanClass(scanClass);
		}
		
		if (!(ship != nullptr ? ship->getCrew() : std::optional<std::vector<oo::Ref<OOCharacter>>>()).has_value() && !(ship != nullptr ? ship->isUnpiloted() : false))
		{
			if (ship != nullptr)  ship->setCrew(std::vector<oo::Ref<OOCharacter>>{ oo::Ref<OOCharacter>( OOCharacter::randomCharacterWithRole(role, Ranrot() & 255)) });
		}
		
		if (ship != nullptr)  ship->setOrientation(OORandomQuaternion());
		
		BOOL trader = role == "trader";
		if (trader)
		{
			// half of traders created anywhere will now have cargo. 
			if (randf() > 0.5f)
			{
				if (ship != nullptr)  ship->setCargoFlag((randf() < 0.66f ? CARGO_FLAG_FULL_PLENTIFUL : CARGO_FLAG_FULL_SCARCE));	// most of them will carry the cargo produced in-system.
			}
			
			uint8_t pendingEscortCount = (ship != nullptr ? ship->pendingEscortCount() : uint8_t{});
			if (pendingEscortCount > 0)
			{
				OOGovernmentID government = currentSystemData().get<unsigned char>(std::string(KEY_GOVERNMENT));
				if ((Ranrot() % 7) < government)	// remove escorts if we feel safe
				{
					int nx = pendingEscortCount - 2 * (1 + (Ranrot() & 3));	// remove 2,4,6, or 8 escorts
					if (ship != nullptr)  ship->setPendingEscortCount((nx > 0) ? nx : 0);
				}
			}
		}
		
		if (HPdistance(getWitchspaceExitPosition(), pos) > SCANNER_MAX_RANGE)
		{
			// nothing extra to do
			success = addEntity(ship);	// STATUS_IN_FLIGHT, AI state GLOBAL - ship is retained globally			
		}
		else	// witchspace incoming traders & pirates need extra settings.
		{
			if (trader)
			{
				if (ship != nullptr)  ship->setCargoFlag(CARGO_FLAG_FULL_SCARCE);
				if ((ship != nullptr ? ship->hasRole("sunskim-trader") : false) && randf() < 0.25) 
				{
					if (ship != nullptr)  ship->setCargoFlag(CARGO_FLAG_FULL_PLENTIFUL);
					makeSunSkimmer(ship, YES);
				}
				else
				{
					if (ship != nullptr)  ship->switchAITo("oolite-traderAI.js");
				}
			}
			else if (role == "pirate")
			{
				if (ship != nullptr)  ship->setBounty((Ranrot() & 7) + (Ranrot() & 7) + ((randf() < 0.05)? 63 : 23), kOOLegalStatusReasonSetup);	// they already have a price on their heads
			}
			
			// Status changes inside the following call: AI state GLOBAL, then STATUS_EXITING_WITCHSPACE, 
			// with the EXITED_WITCHSPACE message sent to the AI. At last we set STATUS_IN_FLIGHT.
			// Includes addEntity, so ship is retained globally.
			success = (ship != nullptr ? ship->witchspaceLeavingEffects() : false);
		}
		
		if (ship != nullptr)  oo::ReleaseEntity(ship);
	}
	return success ? ship : (::ShipEntity *)nil;
	
	OOJS_PROFILE_EXIT
}


std::vector<oo::EntityHold> Universe::addShipsAt(HPVector pos, const std::string &role, unsigned count, GLfloat radius, bool isGroup)
{
	OOJS_PROFILE_ENTER

	std::vector<oo::EntityHold>	ships;
	ships.reserve(count);
	::ShipEntity			*ship = nil;
	oo::Ref<::OOShipGroup>	group;	// kept for the pass, as the autoreleased facade was

	if (isGroup)
	{
		group = OOShipGroup::groupWithName(oo::str::format("%s group", role.c_str()));
	}

	while (count--)
	{
		ship = addShipAt(pos, role, radius);
		if (ship != nil)
		{
			// TODO: avoid collisions!!!
			if (isGroup) { if (ship != nullptr)  ship->setGroup(group.get()); }
			ships.push_back(oo::EntityHold(ship));
		}
	}

	return ships;	// empty where nil was returned

	OOJS_PROFILE_EXIT_VAL(std::vector<oo::EntityHold>())
}


std::vector<oo::EntityHold> Universe::addShipsToRoute(const std::string &route, const std::string &role, unsigned count, double routeFraction, bool isGroup)
{
	std::vector<oo::EntityHold>	ships;
	ships.reserve(count);
	::ShipEntity				*ship = nil;
	Entity				*entity = nullptr;	// the planet or the sun (bead oo-9ht.39.26)
	HPVector					pos = kZeroHPVector, direction = kZeroHPVector, point0 = kZeroHPVector, point1 = kZeroHPVector;
	double					radius = 0;
	
	if (route == "pw" || route == "sw" || route == "ps")
	{
		routeFraction = 1.0f - routeFraction;
	}

	// which route is it?
	if (route == "wp" || route == "pw")
	{
		point0 = getWitchspaceExitPosition();
		entity = planet();	// the planet is C++ since bead oo-9ht.129
		if (entity == nil)  return {};
		point1 = entity->getPosition();
		radius = OOStellarBodyRadius(entity);
	}
	else if (route == "ws" || route == "sw")
	{
		point0 = getWitchspaceExitPosition();
		entity = sun();	// the sun is C++ since bead oo-9ht.111
		if (entity == nil)  return {};
		point1 = entity->getPosition();
		radius = OOStellarBodyRadius(entity);
	}
	else if (route == "sp" || route == "ps")
	{
		entity = sun();	// the sun is C++ since bead oo-9ht.111
		if (entity == nil)  return {};
		point0 = entity->getPosition();
		double radius0 = OOStellarBodyRadius(entity);

		entity = planet();	// the planet is C++ since bead oo-9ht.129
		if (entity == nil)  return {};
		point1 = entity->getPosition();
		radius = OOStellarBodyRadius(entity);
		
		// shorten the route by scanner range & sun radius, otherwise ships could be created inside it.
		direction = HPvector_normal(HPvector_subtract(point0, point1));
		point0 = HPvector_subtract(point0, HPvector_multiply_scalar(direction, radius0 + SCANNER_MAX_RANGE * 1.1f));
	}
	else if (route == "st")
	{
		point0 = getWitchspaceExitPosition();
		if (station() == nil)  return {};
		point1 = (station() != nullptr ? station()->getPosition() : HPVector{});
		radius = (station() != nullptr ? station()->collisionRadius() : 0.0f);
	}
	else return {};	// no route specifier? We shouldn't be here!
	
	// shorten the route by scanner range & radius, otherwise ships could be created inside the route destination.
	direction = HPvector_normal(HPvector_subtract(point1, point0));
	point1 = HPvector_subtract(point1, HPvector_multiply_scalar(direction, radius + SCANNER_MAX_RANGE * 1.1f));
	
	pos = fractionalPositionFrom(point0, point1, routeFraction);
	if(isGroup)
	{	
		return addShipsAt(pos, role, count, (SCANNER_MAX_RANGE / 10.0f), YES);
	}
	else
	{
		while (count--)
		{
			ship = addShipAt(pos, role, 0); // no radius because pos is already randomised with SCANNER_MAX_RANGE.
			if (ship != nil) ships.push_back(oo::EntityHold(ship));
			if (count > 0) pos = fractionalPositionFrom(point0, point1, routeFraction);
		}
	}

	return ships;	// empty where nil was returned
}


bool Universe::roleIsPirateVictim(const std::string &role)
{
	return this->role(role, "oolite-pirate-victim");
}


bool Universe::role(const std::string &role, const std::string &category)
{
	const oo::PList *categoryInfo = roleCategories.get<oo::PList::Array>(category);	// the category's roles, each once
	if (categoryInfo == nullptr)
	{
		return NO;
	}
	for (const oo::PList &member : *categoryInfo->getIf<oo::PList::Array>())
	{
		if (const std::string *memberRole = member.getIf<std::string>(); memberRole != nullptr && *memberRole == role)  return YES;
	}
	return NO;
}


// used to avoid having lost escorts when player advances clock while docked
void Universe::forceWitchspaceEntries()
{
	unsigned i;
	for (i = 0; i < n_entities; i++)
	{
		if (sortedEntities[i]->isShip)
		{
			::ShipEntity *my_ship = oo::ToShip(sortedEntities[i]);
			Entity *my_target = oo::WithObject((my_ship != nullptr ? my_ship->primaryTarget() : (Entity *)nullptr));
			if (my_target != nullptr && my_target->getIsWormhole())	// what -isWormhole forwarded to (bead oo-dpyk8)
			{
				if (my_ship != nullptr)  my_ship->enterTargetWormhole();
			}
			else if ((my_ship != nullptr && my_ship->getAI() != nullptr ? my_ship->getAI()->state() : std::optional<std::string>()) == "ENTER_WORMHOLE")
			{
				if (my_ship != nullptr)  my_ship->enterTargetWormhole();
			}
		}
	}
}


void Universe::addWitchspaceJumpEffectForShip(::ShipEntity *ship)
{
	// don't add rings when system is being populated
	if ((PLAYER != nullptr ? PLAYER->status() : OOEntityStatus{}) != STATUS_ENTERING_WITCHSPACE && (PLAYER != nullptr ? PLAYER->status() : OOEntityStatus{}) != STATUS_EXITING_WITCHSPACE)
	{
		addEntity(oo::MadeEntity(OORingEffectEntity::ringFromEntity(ship)));
		addEntity(oo::MadeEntity(OORingEffectEntity::shrinkingRingFromEntity(ship)));
	}
}


GLfloat Universe::safeWitchspaceExitDistance()
{
	for (unsigned i = 0; i < n_entities; i++)
	{
		Entity *e2 = sortedEntities[i];
		if (oo::EntityIsShip(e2) && (oo::ToShip(e2) != nullptr ? oo::ToShip(e2)->hasPrimaryRole("buoy-witchpoint") : false))
		{
			return (oo::ToShip(e2) != nullptr ? oo::ToShip(e2)->collisionRadius() : 0.0f) + MIN_DISTANCE_TO_BUOY;
		}
	}
	return MIN_DISTANCE_TO_BUOY;
}


void Universe::setUpBreakPattern(HPVector pos, Quaternion q, bool forDocking)
{
	int						i;
	oo::Ref<OOBreakPatternEntity>	ring;
	oo::PList				colorDesc;
	oo::Ref<OOColor>	color;
	
	setViewDirection(VIEW_FORWARD);
	
	q.w = -q.w;		// reverse the quaternion because this is from the player's viewpoint
	
	Vector			v = vector_forward_from_quaternion(q);
	Vector			vel = vector_multiply_scalar(v, -BREAK_PATTERN_RING_SPEED);
	
	// hyperspace colours
	
	oo::Ref<OOColor>	col1 = OOColor::colorWithRed(1.0, 0.0, 0.0, 0.5);	//standard tunnel colour
	oo::Ref<OOColor>	col2 = OOColor::colorWithRed(0.0, 0.0, 1.0, 0.25);	//standard tunnel colour
	
	colorDesc = PListForKeyIn(globalSettings, "hyperspace_tunnel_color_1");	// +cxx_colorWithDescription: takes any description
	if (!colorDesc.isNull())
	{
		color = OOColor::colorWithDescription(colorDesc);
		if (color != nil)  col1 = color;
		else  OO_LOG_WARN("hyperspaceTunnel.fromDict", "could not interpret \"{}\" as a colour.", oo::DescriptionOf(colorDesc));
	}

	colorDesc = PListForKeyIn(globalSettings, "hyperspace_tunnel_color_2");
	if (!colorDesc.isNull())
	{
		color = OOColor::colorWithDescription(colorDesc);
		if (color != nil)  col2 = color;
		else  OO_LOG_WARN("hyperspaceTunnel.fromDict", "could not interpret \"{}\" as a colour.", oo::DescriptionOf(colorDesc));
	}
	
	unsigned	sides = kOOBreakPatternMaxSides;
	GLfloat		startAngle = 0;
	GLfloat		aspectRatio = 1;
	
	if (forDocking)
	{
		const oo::PList info = ((PLAYER != nullptr ? PLAYER->dockedStation() : (::StationEntity *)nullptr) != nullptr ? (PLAYER != nullptr ? PLAYER->dockedStation() : (::StationEntity *)nullptr)->shipInfoDictionary() : oo::PList());
		sides = info.get<unsigned int>("tunnel_corners", 4);
		startAngle = info.get<float>("tunnel_start_angle", 45.0f);
		aspectRatio = info.get<float>("tunnel_aspect_ratio", 2.67f);
	}
	
	for (i = 1; i < 11; i++)
	{
		ring = OOBreakPatternEntity::breakPatternWithPolygonSides(sides, startAngle, aspectRatio);
		if (!forDocking)
		{
			ring->setInnerColor(col1.get(), col2.get());
		}
		
		Vector offset = vector_multiply_scalar(v, i * BREAK_PATTERN_RING_SPACING);
		ring->setPosition(HPvector_add(pos, vectorToHPVector(offset)));  // ahead of the player
		ring->setOrientation(q);
		ring->setVelocity(vel);
		ring->setLifetime(i * BREAK_PATTERN_RING_SPACING);
		
		// FIXME: better would be to have break pattern timing not depend on
		// these ring objects existing in the first place. - CIM
		if (forDocking && !((PLAYER != nullptr ? PLAYER->dockedStation() : (::StationEntity *)nullptr) != nullptr ? (PLAYER != nullptr ? PLAYER->dockedStation() : (::StationEntity *)nullptr)->getHasBreakPattern() : false))
		{
			ring->isImmuneToBreakPatternHide = NO;
		}
		else if (!forDocking && !witchspaceBreakPattern())
		{
			ring->isImmuneToBreakPatternHide = NO;
		}
		addEntity(oo::MadeEntity(ring));
		breakPatternCounter++;
	}
}


bool Universe::witchspaceBreakPattern()
{
	return _witchspaceBreakPattern;
}


void Universe::setWitchspaceBreakPattern(bool newValue)
{
	_witchspaceBreakPattern = !!newValue;
}


bool Universe::dockingClearanceProtocolActive()
{
	return _dockingClearanceProtocolActive;
}


void Universe::setDockingClearanceProtocolActive(bool newValue)
{
	::OOShipRegistry	*registry = OOShipRegistry::sharedRegistry();
	::StationEntity	*station = nil;

	/* CIM: picking a random ship type which can take the same primary
	 * role as the station to determine whether it has no set docking
	 * clearance requirements seems unlikely to work entirely
	 * correctly. To be fixed. */
						   
	for (const oo::EntityHold &entry : allStations)
	{
		station = oo::ToStation(entry.get());
		const std::optional<std::string>	stationKey = registry->randomShipKeyForRole((station != nullptr ? station->getPrimaryRole() : std::optional<std::string>()).value_or(""));
		const oo::PList	stationInfo = stationKey.has_value() ? registry->shipInfoForKey(*stationKey) : oo::PList();
		if (stationInfo.find("requires_docking_clearance") == nullptr)
		{
			if (station != nullptr)  station->setRequiresDockingClearance(!!newValue);
		}
	}
	
	_dockingClearanceProtocolActive = !!newValue;
}


void Universe::handleGameOver()
{
	if ((gameController() != nullptr ? gameController()->playerFileToLoad() : std::optional<std::string>()).has_value())
	{
		if (gameController() != nullptr)  gameController()->loadPlayerIfRequired();
	}
	else
	{
		setUseAddOns(std::string(SCENARIO_OXP_DEFINITION_ALL), NO, YES); // calls reinitAndShowDemo
	} 
}




// Slice 8 of docs/phases/3-slices/Universe.md (bead oo-m0rz6): the intro and demo ships, the ship
// library text, station and planet look-ups. The facade forwarded each selector
// (until oo-ql9rn); sends to self were sends (ADR-0056 amendment oo-27jxj).

void Universe::setupIntroFirstGo(bool justCobra)
{
	::PlayerEntity	*player = PLAYER;
	::ShipEntity		*ship = nil;
	Quaternion		q2 = { 0.0f, 0.0f, 1.0f, 0.0f }; // w,x,y,z

	// in status demo draw ships and display text
	if (!justCobra)
	{
		demo_ships = OOShipRegistry::sharedRegistry()->demoShipKeys();
		// always, even if it's the cobra, because it's repositioned
		removeDemoShips();
	}
	if (justCobra)
	{
		if (player != nullptr)  player->setStatus(STATUS_START_GAME);
	}
	if (player != nullptr)  player->setShowDemoShips(YES);
	displayGUI = YES;

	if (justCobra)
	{
		/*- cobra - intro1 -*/
		ship = newShipWithName(std::string(PLAYER_SHIP_DESC), YES);
	}
	else
	{
		/*- demo ships - intro2 -*/

		demo_ship_index = 0;
		demo_ship_subindex = 0;

		/* Try to set the initial list position to Cobra III if
		 * available, and at least the Ships category. */
		const oo::PList::Array *demoClasses = demo_ships.getIf<oo::PList::Array>();
		if (demoClasses != nullptr)
		{
			for (NSUInteger k = 0; k < demoClasses->size(); k++)
			{
				const oo::PList &subList = (*demoClasses)[k];
				if (OptionalStringIn(DemoShipEntry(demo_ships, k, 0), kOODemoShipClass) == "ship")
				{
					demo_ship_index = std::find(demoClasses->begin(), demoClasses->end(), subList) - demoClasses->begin();	// -indexOfObject:
					const oo::PList::Array *shipEntries = subList.getIf<oo::PList::Array>();	// an array: its first entry was found above
					for (const oo::PList &shipEntry : *shipEntries)
					{
						if (OptionalStringIn(shipEntry, kOODemoShipKey) == "cobra3-trader")
						{
							demo_ship_subindex = std::find(shipEntries->begin(), shipEntries->end(), shipEntry) - shipEntries->begin();	// -indexOfObject:
							break;
						}
					}
					break;
				}
			}
		}


		if (!demo_ship)	ship = newShipWithName(OptionalStringIn(DemoShipEntry(demo_ships, demo_ship_index, demo_ship_subindex), kOODemoShipKey).value_or(std::string()), NO);
		// stop consistency problems on the ship library screen
		if (ship != nullptr)  ship->removeEquipmentItem("EQ_SHIELD_BOOSTER");
		if (ship != nullptr)  ship->removeEquipmentItem("EQ_SHIELD_ENHANCER");
	}

	if (ship)
	{
		if (ship != nullptr)  ship->setOrientation(q2);
		if (!justCobra)
		{
			if (ship != nullptr)  ship->setPositionX(0.0f, 0.0f, DEMO2_VANISHING_DISTANCE * ship->collision_radius * 0.01);
			if (ship != nullptr)  ship->setDestination(ship->position);	// ideal position
		}
		else
		{
			// main screen Cobra is closer
			if (ship != nullptr)  ship->setPositionX(0.0f, 0.0f, 3.6 * ship->collision_radius);
		}
		if (ship != nullptr)  ship->setDemoShip(1.0f);
		if (ship != nullptr)  ship->setDemoStartTime(universal_time);
		if (ship != nullptr)  ship->setScanClass(CLASS_NO_DRAW);
		if (ship != nullptr)  ship->switchAITo("nullAI.plist");
		if((ship != nullptr ? ship->pendingEscortCount() : uint8_t{}) > 0) { if (ship != nullptr)  ship->setPendingEscortCount(0); }
		addEntity(ship);	// STATUS_IN_FLIGHT, AI state GLOBAL
		// now override status
		if (ship != nullptr)  ship->setStatus(STATUS_COCKPIT_DISPLAY);
		demo_ship = ship;

		if (ship != nullptr)  oo::ReleaseEntity(ship);
	}

	if (!justCobra)
	{
//		[gui setText:[demo_ship displayName] forRow:19 align:GUI_ALIGN_CENTER];
		setLibraryTextForDemoShip();
	}

	enterGUIViewModeWithMouseInteraction(NO);
	if (!justCobra)
	{
		demo_stage = DEMO_SHOW_THING;
		demo_stage_time = universal_time + 300.0;
	}
}


oo::PList Universe::demoShipData()
{
	return DemoShipEntry(demo_ships, demo_ship_index, demo_ship_subindex);
}


void Universe::setLibraryTextForDemoShip()
{
	OOGUITabSettings tab_stops;
	tab_stops[0] = 0;
	tab_stops[1] = 170;
	tab_stops[2] = 340;
	if (gui == nullptr)  return;	// the messages to nil did nothing, and the rest only writes the GUI
	gui->setTabStops(tab_stops);

/*	[gui setText:[demo_ship displayName] forRow:19 align:GUI_ALIGN_CENTER];
	[gui setColor:[OOColor whiteColor] forRow:19]; */

	const oo::PList librarySettings = demoShipData();

	OOGUIRow descRow = 7;

	std::optional<std::string> field1;
	std::optional<std::string> field2;
	std::optional<std::string> field3;
	std::optional<std::string> override;

	// clear rows
	for (NSUInteger i=1;i<=26;i++)
	{
		gui->setText("", i);
	}

	/* Row 1: ScanClass, Name, Summary */
	override = LibrarySetting(librarySettings, kOODemoShipClass, "ship");
	field1 = OOShipLibraryCategorySingular(override.value_or(std::string()));


	field2 = (demo_ship != nullptr ? demo_ship->getShipClassName() : std::optional<std::string>());


	override = LibrarySetting(librarySettings, kOODemoShipSummary, nullptr);
	if (override.has_value())
	{
		field3 = ExpandText(*override);
	}
	else
	{
		field3 = std::string();
	}
	gui->setArray(FieldsUpToNil({field1,field2,field3}), 1);
	gui->setColor(OOColor::greenColor().get(), 1);

	// ship_data defaults to true for "ship" class, false for everything else
	if (!librarySettings.get<bool>(kOODemoShipShipData, LibrarySetting(librarySettings, kOODemoShipClass, "ship") == "ship"))
	{
		descRow = 3;
	}
	else
	{
		/* Row 2: Speed, Turn Rate, Cargo */

		override = LibrarySetting(librarySettings, kOODemoShipSpeed, nullptr);
		if (override.has_value())
		{
			if (override->empty())
			{
				field1 = std::string();
			}
			else
			{
				field1 = CustomLibraryText("oolite-ship-library-speed-custom", *override);
			}
		}
		else
		{
			field1 = OOShipLibrarySpeed(demo_ship);
		}


		override = LibrarySetting(librarySettings, kOODemoShipTurnRate, nullptr);
		if (override.has_value())
		{
			if (override->empty())
			{
				field2 = std::string();
			}
			else
			{
				field2 = CustomLibraryText("oolite-ship-library-turn-custom", *override);
			}
		}
		else
		{
			field2 = OOShipLibraryTurnRate(demo_ship);
		}


		override = LibrarySetting(librarySettings, kOODemoShipCargo, nullptr);
		if (override.has_value())
		{
			if (override->empty())
			{
				field3 = std::string();
			}
			else
			{
				field3 = CustomLibraryText("oolite-ship-library-cargo-custom", *override);
			}
		}
		else
		{
			field3 = OOShipLibraryCargo(demo_ship);
		}


		gui->setArray(FieldsUpToNil({field1,field2,field3}), 3);

		/* Row 3: recharge rate, energy banks, witchspace */
		override = LibrarySetting(librarySettings, kOODemoShipGenerator, nullptr);
		if (override.has_value())
		{
			if (override->empty())
			{
				field1 = std::string();
			}
			else
			{
				field1 = CustomLibraryText("oolite-ship-library-generator-custom", *override);
			}
		}
		else
		{
			field1 = OOShipLibraryGenerator(demo_ship);
		}


		override = LibrarySetting(librarySettings, kOODemoShipShields, nullptr);
		if (override.has_value())
		{
			if (override->empty())
			{
				field2 = std::string();
			}
			else
			{
				field2 = CustomLibraryText("oolite-ship-library-shields-custom", *override);
			}
		}
		else
		{
			field2 = OOShipLibraryShields(demo_ship);
		}


		override = LibrarySetting(librarySettings, kOODemoShipWitchspace, nullptr);
		if (override.has_value())
		{
			if (override->empty())
			{
				field3 = std::string();
			}
			else
			{
				field3 = CustomLibraryText("oolite-ship-library-witchspace-custom", *override);
			}
		}
		else
		{
			field3 = OOShipLibraryWitchspace(demo_ship);
		}


		gui->setArray(FieldsUpToNil({field1,field2,field3}), 4);


		/* Row 4: weapons, turrets, size */
		override = LibrarySetting(librarySettings, kOODemoShipWeapons, nullptr);
		if (override.has_value())
		{
			if (override->empty())
			{
				field1 = std::string();
			}
			else
			{
				field1 = CustomLibraryText("oolite-ship-library-weapons-custom", *override);
			}
		}
		else
		{
			field1 = OOShipLibraryWeapons(demo_ship);
		}

		override = LibrarySetting(librarySettings, kOODemoShipTurrets, nullptr);
		if (override.has_value())
		{
			if (override->empty())
			{
				field2 = std::string();
			}
			else
			{
				field2 = CustomLibraryText("oolite-ship-library-turrets-custom", *override);
			}
		}
		else
		{
			field2 = OOShipLibraryTurrets(demo_ship);
		}

		override = LibrarySetting(librarySettings, kOODemoShipSize, nullptr);
		if (override.has_value())
		{
			if (override->empty())
			{
				field3 = std::string();
			}
			else
			{
				field3 = CustomLibraryText("oolite-ship-library-size-custom", *override);
			}
		}
		else
		{
			field3 = OOShipLibrarySize(demo_ship);
		}

		gui->setArray(FieldsUpToNil({field1,field2,field3}), 5);
	}

	override = LibrarySetting(librarySettings, kOODemoShipDescription, nullptr);
	if (override.has_value())
	{
		gui->addLongText(ExpandText(*override), descRow, GUI_ALIGN_LEFT);
	}


	// line 19: ship categories
	field1 = oo::str::format("<-- %s",OOShipLibraryCategoryPlural(DemoClassAt(demo_ships, (demo_ship_index+demo_ships.count()-1)%demo_ships.count())).c_str());
	field2 = OOShipLibraryCategoryPlural(DemoClassAt(demo_ships, demo_ship_index));
	field3 = oo::str::format("%s -->",OOShipLibraryCategoryPlural(DemoClassAt(demo_ships, (demo_ship_index+1)%demo_ships.count())).c_str());

	gui->setArray(FieldsUpToNil({field1,field2,field3}), 19);
	gui->setColor(OOColor::greenColor().get(), 19);

	// lines 21-25: ship names
	const oo::PList *subListEntry = demo_ships.at(demo_ship_index);
	const oo::PList subList = (subListEntry != nullptr) ? *subListEntry : oo::PList();
	NSUInteger i,start = demo_ship_subindex - (demo_ship_subindex%5);
	NSUInteger end = start + 4;
	if (end >= subList.count())
	{
		end = subList.count() - 1;
	}
	OOGUIRow row = 21;
	field1 = std::string();
	field3 = std::string();
	for (i = start ; i <= end ; i++)
	{
		const oo::PList *shipEntry = subList.at(i);
		field2 = (shipEntry != nullptr) ? OptionalStringIn(*shipEntry, kOODemoShipName) : std::nullopt;
		gui->setArray(FieldsUpToNil({field1,field2,field3}), row);
		if (i == demo_ship_subindex)
		{
			gui->setColor(OOColor::yellowColor().get(), row);
		}
		else
		{
			gui->setColor(OOColor::whiteColor().get(), row);
		}
		row++;
	}

	field2 = "...";
	if (start > 0)
	{
		gui->setArray(FieldsUpToNil({field1,field2,field3}), 20);
		gui->setColor(OOColor::whiteColor().get(), 20);
	}
	if (end < subList.count()-1)
	{
		gui->setArray(FieldsUpToNil({field1,field2,field3}), 26);
		gui->setColor(OOColor::whiteColor().get(), 26);
	}

}


void Universe::selectIntro2Previous()
{
	demo_stage = DEMO_SHOW_THING;
	NSUInteger subcount = DemoClassCount(demo_ships, demo_ship_index);
	demo_ship_subindex = (demo_ship_subindex + subcount - 2) % subcount;
	demo_stage_time  = universal_time - 1.0;	// force change
}


void Universe::selectIntro2PreviousCategory()
{
	demo_stage = DEMO_SHOW_THING;
	demo_ship_index = (demo_ship_index + demo_ships.count() - 1) % demo_ships.count();
	demo_ship_subindex = DemoClassCount(demo_ships, demo_ship_index) - 1;
	demo_stage_time  = universal_time - 1.0;	// force change
}


void Universe::selectIntro2NextCategory()
{
	demo_stage = DEMO_SHOW_THING;
 	demo_ship_index = (demo_ship_index + 1) % demo_ships.count();
	demo_ship_subindex = DemoClassCount(demo_ships, demo_ship_index) - 1;
	demo_stage_time  = universal_time - 1.0;	// force change
}


void Universe::selectIntro2Next()
{
	demo_stage = DEMO_SHOW_THING;
	demo_stage_time  = universal_time - 1.0;	// force change
}


::StationEntity * Universe::station()
{
	if (cachedSun != nil && cachedStation == nil)
	{
		cachedStation = oo::ToStation(findOneEntityMatchingPredicate(IsCandidateMainStationPredicate, nullptr));
	}
	return cachedStation;
}


::StationEntity * Universe::stationWithRole(const std::string &role, HPVector position)
{
	if (role.empty())
	{
		return nil;
	}

	float range = 1000000; // allow a little variation in position

	const std::vector<oo::EntityHold> stations = this->stations();
	::StationEntity *station = nil;
	for (const oo::EntityHold &entry : stations)
	{
		station = oo::ToStation(entry.get());
		if (HPdistance2(position,(station != nullptr ? station->getPosition() : HPVector{})) < range)
		{
			if ((station != nullptr ? station->getPrimaryRole() : std::optional<std::string>()).value_or("") == role)
			{
				return station;
			}
		}
	}
	return nil;
}


::StationEntity * Universe::stationFriendlyTo(::ShipEntity *ship)
{
	// In interstellar space we select a random friendly carrier as mainStation.
	// No caching: friendly status can change!
	return oo::ToStation(findOneEntityMatchingPredicate(IsFriendlyStationPredicate, static_cast<Entity *>(ship)));	// the C++ entity (bead oo-9ht.39.26)
}


::OOPlanetEntity * Universe::planet()
{
	if (cachedPlanet == nil && allPlanets.size() > 0)
	{
		cachedPlanet = static_cast<::OOPlanetEntity *>(allPlanets[0].get());	// the list holds only planets
	}
	return cachedPlanet;
}


::OOSunEntity * Universe::sun()
{
	if (cachedSun == nil)
	{
		cachedSun = static_cast<OOSunEntity *>(findOneEntityMatchingPredicate(IsSunPredicate, nullptr));	// -isSun
	}
	return cachedSun;
}


std::vector<oo::EntityHold> Universe::planets()
{
	return allPlanets;
}


std::vector<oo::EntityHold> Universe::stations()
{
	return allStations;
}




// Slice 9 of docs/phases/3-slices/Universe.md (bead oo-hkvet): wormholes, the main station,
// beacons, waypoints, sky colour, the break pattern, making ships by role and name, default AIs,
// cargo capacity. The facade forwarded each selector (until oo-ql9rn); sends to self were
// sends (ADR-0056 amendment oo-27jxj).

std::vector<oo::EntityHold> Universe::wormholes()
{
	return activeWormholes;
}


void Universe::unMagicMainStation()
{
	/*	During the demo screens, the player must remain docked in order for the
		UI to work. This means either enforcing invulnerability or launching
		the player when the station is destroyed even if on the "new game Y/N"
		screen.
		
		The latter is a) weirder and b) harder. If your OXP relies on being
		able to destroy the main station before the game has even started,
		your OXP sucks.
	*/
	OOEntityStatus playerStatus = (PLAYER != nullptr ? PLAYER->status() : OOEntityStatus{});
	if (playerStatus == STATUS_START_GAME)  return;
	
	::StationEntity *theStation = station();
	if (theStation != nil)  theStation->isExplicitlyNotMainStation = YES;
	cachedStation = nil;
}


// The beacon list holds the C++ entities (bead oo-9ht.39.26): the links are still each beacon's
// own, set and read through its object's messages (oo::PrevBeacon() and the rest, Entity+ObjCBridge).
void Universe::resetBeacons()
{
	Entity *beaconShip = firstBeacon(), *next = nullptr;
	while (beaconShip)
	{
		next = oo::NextBeacon(beaconShip);
		oo::SetPrevBeacon(beaconShip, nullptr);
		oo::SetNextBeacon(beaconShip, nullptr);
		beaconShip = next;
	}
	
	setFirstBeacon(nullptr);
	setLastBeacon(nullptr);
}


Entity * Universe::firstBeacon()
{
	return oo::LiveEntity(_firstBeacon);	// what the object's weak reference read (+0), its C++ entity
}


void Universe::setFirstBeacon(Entity *beacon)
{
	if (beacon != firstBeacon())
	{
		oo::SetPrevBeacon(beacon, nullptr);
		oo::SetNextBeacon(beacon, firstBeacon());
		oo::SetPrevBeacon(firstBeacon(), beacon);
		_firstBeacon = oo::WeakRef<Entity>(beacon);	// oo::WeakEntityRef() of its object
	}
}


Entity * Universe::lastBeacon()
{
	return oo::LiveEntity(_lastBeacon);
}


void Universe::setLastBeacon(Entity *beacon)
{
	if (beacon != lastBeacon())
	{
		oo::SetNextBeacon(beacon, nullptr);
		oo::SetPrevBeacon(beacon, lastBeacon());
		oo::SetNextBeacon(lastBeacon(), beacon);
		_lastBeacon = oo::WeakRef<Entity>(beacon);
	}
}


void Universe::setNextBeacon(Entity *beacon)
{
	// The C++ entity (beads oo-9ht.39.8.10, oo-9ht.39.26).
	if (oo::EntityIsBeacon(beacon))
	{
		setLastBeacon(beacon);
		if (firstBeacon() == nullptr)  setFirstBeacon(beacon);
	}
	else
	{
		OO_LOG("universe.beacon.error", "***** ERROR: Universe setNextBeacon '{}'. The ship has no beacon code set.", oo::EntityDescription(beacon));
	}
}


void Universe::clearBeacon(Entity *beacon)
{
	// The C++ entity (beads oo-9ht.39.8.10, oo-9ht.39.26).
	Entity				*tmp = nullptr;

	if (oo::EntityIsBeacon(beacon))
	{
		if (firstBeacon() == beacon)
		{
			tmp = oo::NextBeacon(oo::NextBeacon(beacon));
			setFirstBeacon(oo::NextBeacon(beacon));
			oo::SetNextBeacon(oo::PrevBeacon(beacon), tmp);
		}
		else if (lastBeacon() == beacon)
		{
			tmp = oo::PrevBeacon(oo::PrevBeacon(beacon));
			setLastBeacon(oo::PrevBeacon(beacon));
			oo::SetPrevBeacon(oo::NextBeacon(beacon), tmp);
		}
		else
		{
			oo::SetPrevBeacon(oo::NextBeacon(beacon), oo::PrevBeacon(beacon));
			oo::SetNextBeacon(oo::PrevBeacon(beacon), oo::NextBeacon(beacon));
		}
		oo::SetBeaconCode(beacon, std::nullopt);	// not nil: nil built a std::string from a null char* (bead oo-2o5x)
	}
}


std::map<std::string, oo::EntityHold, std::less<>> Universe::currentWaypoints()
{
	return waypoints;
}


void Universe::defineWaypoint(const oo::PList &definition, const std::string &key)
{
	Entity *waypoint = nullptr;	// the C++ waypoint (bead oo-9ht.39.26; its object is the root's facade since bead oo-9ht.108)
	BOOL preserveCompass = NO;
	const auto existing = waypoints.find(key);
	if (existing != waypoints.end())  waypoint = existing->second.get();
	if (waypoint != nullptr)
	{
		if ((PLAYER != nullptr ? PLAYER->getCompassTargetEntity() : nullptr) == waypoint)
		{
			preserveCompass = YES;
		}
		removeEntity(waypoint);
		waypoints.erase(key);
	}
	if (!definition.isNull())
	{
		waypoint = oo::MadeEntity(::OOWaypointEntity::waypointWithDictionary(definition));
		if (waypoint != nullptr)
		{
			addEntity(waypoint);
			waypoints[key] = oo::EntityHold(waypoint);
			if (preserveCompass)
			{
				if (PLAYER != nullptr)  PLAYER->setCompassTargetEntity(waypoint);
				if (PLAYER != nullptr)  PLAYER->setNextBeacon(waypoint);
			}
		}
	}
}


GLfloat * Universe::getSkyClearColor()
{
	return skyClearColor;
}


void Universe::setSkyColorRed(GLfloat red, GLfloat green, GLfloat blue, GLfloat alpha)
{
	skyClearColor[0] = red;
	skyClearColor[1] = green;
	skyClearColor[2] = blue;
	skyClearColor[3] = alpha;
	setAirResistanceFactor(alpha);
}


bool Universe::breakPatternOver()
{
	return (breakPatternCounter == 0);
}


bool Universe::breakPatternHide()
{
	::PlayerEntity *player = PLAYER;
	return ((breakPatternCounter > 5)||(!player)||(oo::EntityStatus(player) == STATUS_DOCKING));
}


bool Universe::canInstantiateShip(const std::string &shipKey)
{
	oo::PList				shipInfo;
	const oo::PList			*conditions = nullptr;
	std::optional<std::string>	condition_script;
	shipInfo = OOShipRegistry::sharedRegistry()->shipInfoForKey(shipKey);

	condition_script = OptionalStringIn(shipInfo, "condition_script");
	if (condition_script.has_value())
	{
		::OOScript *condScript = getConditionScript(*condition_script);
		if (condScript != nil) // should always be non-nil, but just in case
		{
			ooscript::Context context = OOJSAcquireContext();
			BOOL OK;
			bool allow_instantiation;
			ooscript::Value result;
			ooscript::Value args[] = { OOJSValueFromPList(context, oo::PList(shipKey)) };
			
			OK = (condScript != nullptr ? condScript->callMethod(OOJSID("allowSpawnShip"), context, args, sizeof args / sizeof *args, &result) : false);

			if (OK) OK = ooscript::valueToBoolean(context, result, &allow_instantiation);
			
			OOJSRelinquishContext(context);

			if (OK && !allow_instantiation)
			{
				/* if the script exists, the function exists, the function
				 * returns a bool, and that bool is false, block
				 * instantiation. Otherwise allow it as default */
				return NO;
			}
		}
	}

	conditions = shipInfo.get<oo::PList::Array>("conditions");
	if (conditions == nullptr)  return YES;

	// Check conditions
	return (PLAYER != nullptr ? PLAYER->scriptTestConditions(*conditions) : false);
}


std::optional<std::string> Universe::randomShipKeyForRoleRespectingConditions(const std::string &role)
{
	OOJS_PROFILE_ENTER

	::OOShipRegistry			*registry = OOShipRegistry::sharedRegistry();
	std::optional<std::string>	shipKey;
	oo::Ref<OOMutableProbabilitySet>	pset;
	
#if PROFILE_SHIP_SELECTION
	static unsigned long	profTotal = 0, profSlowPath = 0;
	++profTotal;
#endif
	
	// Select a ship, check conditions and return it if possible.
	shipKey = registry->randomShipKeyForRole(role);
	if (!shipKey.has_value())  return std::nullopt;	// no ship has the role (a nil key passed the check and was returned)
	if (canInstantiateShip(*shipKey))  return shipKey;
	
	/*	If we got here, condition check failed.
		We now need to keep trying until we either find an acceptable ship or
		run out of candidates.
		This is special-cased because it has more overhead than the more
		common conditionless lookup.
	*/
	
#if PROFILE_SHIP_SELECTION
	++profSlowPath;
	if ((profSlowPath % 10) == 0)	// Only print every tenth slow path, to reduce spamminess.
	{
		OO_LOG("shipRegistry.selection.profile", "Hit slow path in ship selection for role \"{}\", having selected ship \"{}\". Now {} of {} on slow path ({:f}%).", role, shipKey.value_or("(null)"), static_cast<size_t>(profSlowPath), static_cast<size_t>(profTotal), ((double)profSlowPath)/((double)profTotal) * 100.0f);
	}
#endif
	
	if (OOProbabilitySet *set = registry->probabilitySetForRole(role))  pset = set->mutableCopy();

	while (pset != nullptr && pset->count() > 0)
	{
		// Select a ship, check conditions and return it if possible.
		const oo::PList shipKeyObject = pset->randomObject();	// a ship key (a string); null when no weight is positive
		const std::string *shipKeyString = shipKeyObject.getIf<std::string>();
		std::string candidate = (shipKeyString != nullptr) ? *shipKeyString : std::string();	// "" as StdString(nil) gave
		if (canInstantiateShip(candidate))  return candidate;

		// Condition failed -> remove ship from consideration.
		pset->removeObject(shipKeyObject);
	}

	// If we got here, some ships existed but all failed conditions test.
	return std::nullopt;

	OOJS_PROFILE_EXIT_VAL(std::nullopt)
}


::ShipEntity * Universe::newShipWithRole(const std::string &role)
{
	OOJS_PROFILE_ENTER

	::ShipEntity				*ship = nil;
	std::optional<std::string>	shipKey;
	oo::PList				shipInfo;
	std::optional<std::string>	autoAI;

	shipKey = randomShipKeyForRoleRespectingConditions(role);
	if (shipKey.has_value())
	{
		ship = newShipWithName(*shipKey);
		if (ship != nil)
		{
			if (ship != nullptr)  ship->setPrimaryRole(role);

			shipInfo = OOShipRegistry::sharedRegistry()->shipInfoForKey(*shipKey);
			if (FuzzyBooleanIn(shipInfo, "auto_ai", YES))
			{
				// Set AI based on role
				autoAI = defaultAIForRole(role);
				if (autoAI.has_value())
				{
					if (ship != nullptr)  ship->setAITo(*autoAI);
					// Nikos 20090604
					// Pirate, trader or police with auto_ai? Follow populator rules for them.
					if (role == "pirate") { if (ship != nullptr)  ship->setBounty(20 + randf() * 50, kOOLegalStatusReasonSetup); }
					if (role == "trader") { if (ship != nullptr)  ship->setBounty(0, kOOLegalStatusReasonSetup); }
					if (role == "police") { if (ship != nullptr)  ship->setScanClass(CLASS_POLICE); }
					if (role == "interceptor")
					{
						if (ship != nullptr)  ship->setScanClass(CLASS_POLICE);
						if (ship != nullptr)  ship->setPrimaryRole("police"); // to make sure interceptors get the correct pilot later on.
					}
				}
				if (role == "thargoid") { if (ship != nullptr)  ship->setScanClass(CLASS_THARGOID); } // thargoids are not on the autoAIMap
			}
		}
	}
	
	return ship;
	
	OOJS_PROFILE_EXIT
}


Entity * Universe::newVisualEffectWithName(const std::string &effectKey)
{
	OOJS_PROFILE_ENTER

	oo::PList				effectDict;
	Entity	*effect = nullptr;	// the effect, its object +1 (beads oo-9ht.165, oo-9ht.39.26)

	effectDict = OOShipRegistry::sharedRegistry()->effectInfoForKey(effectKey);
	if (effectDict.isNull())  return nil;

	try
	{
		effect = oo::NewVisualEffect(effectKey, effectDict);
	}
	catch (...)
	{
		const auto exception = oo::CurrentOOException();
		if (!exception)  throw;	// not an OOException: it goes on up, as before
		if (strcmp(exception->name(), OOLITE_EXCEPTION_DATA_NOT_FOUND) == 0)
		{
			OO_LOG(cxx_kOOLogException, "***** Oolite Exception : '{}' in [Universe newVisualEffectWithName: {} ] *****", exception->reason(), effectKey);
		}
		else  throw;
	}
	
	return effect;
	
	OOJS_PROFILE_EXIT
}


::ShipEntity * Universe::newSubentityWithName(const std::string &shipKey, float scale)
{
	return newShipWithName(shipKey, NO, YES, scale);
}


::ShipEntity * Universe::newShipWithName(const std::string &shipKey, bool usePlayerProxy)
{
	return newShipWithName(shipKey, usePlayerProxy, NO);
}


::ShipEntity * Universe::newShipWithName(const std::string &shipKey, bool usePlayerProxy, bool isSubentity)
{
	return newShipWithName(shipKey, usePlayerProxy, isSubentity, 1.0f);
}


::ShipEntity * Universe::newShipWithName(const std::string &shipKey, bool usePlayerProxy, bool isSubentity, float scale)
{
	OOJS_PROFILE_ENTER

	oo::PList		shipDict;
	::ShipEntity		*ship = nil;

	shipDict = OOShipRegistry::sharedRegistry()->shipInfoForKey(shipKey);
	if (shipDict.isNull())  return nil;
	
	volatile BOOL makeStation = NO;	// a station is made in C++ since bead oo-9ht.175 (it was its class)
	volatile BOOL makeProxy = NO;	// a proxy is made in C++ since bead oo-9ht.183 (it was its class)
	if (!isSubentity)
	{
		makeStation = isStationShipDictionary(shipDict);
		if (usePlayerProxy && !makeStation)
		{
			makeProxy = YES;
		}
	}
	
	try
	{
		if (scale != 1.0f)
		{
			// a copy with the scale, a float as +numberWithFloat: stored it (ADR-0043 item 15)
			(*shipDict.getIf<oo::PList::Dict>())["model_scale_factor"] = oo::PList::singleReal(scale);
		}
		if (makeProxy)
		{
			ship = ::ProxyPlayerEntity::newProxyObject(shipKey, shipDict);
		}
		else if (makeStation)
		{
			ship = ::StationEntity::newStationObject(shipKey, shipDict);
		}
		else
		{
			ship = oo::ToShip(oo::NewShipObject(oo::makeRef<::ShipEntity>(), shipKey, shipDict));
		}
	}
	catch (...)
	{
		const auto exception = oo::CurrentOOException();
		if (!exception)  throw;	// not an OOException: it goes on up, as before
		if (strcmp(exception->name(), OOLITE_EXCEPTION_DATA_NOT_FOUND) == 0)
		{
			OO_LOG(cxx_kOOLogException, "***** Oolite Exception : '{}' in [Universe newShipWithName: {} ] *****", exception->reason(), shipKey);
		}
		else  throw;
	}

	// Set primary role to same as ship name, if ship name is also a role.
	// Otherwise, if caller doesn't set a role, one will be selected randomly.
	if ((ship != nullptr ? ship->hasRole(shipKey) : false))  { if (ship != nullptr)  ship->setPrimaryRole(shipKey); }
	
	return ship;
	
	OOJS_PROFILE_EXIT
}


::ShipEntity * Universe::newDockWithName(const std::string &shipDataKey, float scale)
{
	OOJS_PROFILE_ENTER

	oo::PList		shipDict;
	::ShipEntity		*dock = nil;	// its object

	shipDict = OOShipRegistry::sharedRegistry()->shipInfoForKey(shipDataKey);
	if (shipDict.isNull())  return nil;

	try
	{
		if (scale != 1.0f)
		{
			// a copy with the scale, a float as +numberWithFloat: stored it (ADR-0043 item 15)
			(*shipDict.getIf<oo::PList::Dict>())["model_scale_factor"] = oo::PList::singleReal(scale);
		}
		dock = ::DockEntity::newDockObject(shipDataKey, shipDict);	// [[DockEntity alloc] cxx_initWithKey:definition:] until bead oo-9ht.180
	}
	catch (...)
	{
		const auto exception = oo::CurrentOOException();
		if (!exception)  throw;	// not an OOException: it goes on up, as before
		if (strcmp(exception->name(), OOLITE_EXCEPTION_DATA_NOT_FOUND) == 0)
		{
			OO_LOG(cxx_kOOLogException, "***** Oolite Exception : '{}' in [Universe newDockWithName: {} ] *****", exception->reason(), shipDataKey);
		}
		else  throw;
	}

	// Set primary role to same as name, if ship name is also a role.
	// Otherwise, if caller doesn't set a role, one will be selected randomly.
	if ((dock != nullptr ? dock->hasRole(shipDataKey) : false))  { if (dock != nullptr)  dock->setPrimaryRole(shipDataKey); }
	
	return dock;
	
	OOJS_PROFILE_EXIT
}


::ShipEntity * Universe::newShipWithName(const std::string &shipKey)
{
	return newShipWithName(shipKey, NO);
}


bool Universe::isStationShipDictionary(const oo::PList &dict)
{
	OOJS_PROFILE_ENTER

	if (dict.isNull())  return NO;

	BOOL		isStation = NO;
	std::optional<std::string>	shipRoles = OptionalStringIn(dict, "roles");

	if (shipRoles.has_value())
	{
		isStation = shipRoles->find("station") != std::string::npos ||
		shipRoles->find("carrier") != std::string::npos;
	}

	// Note priority here: is_carrier overrides isCarrier which overrides roles.
	isStation = dict.get<bool>("isCarrier", isStation);
	isStation = dict.get<bool>("is_carrier", isStation);


	return isStation;

	OOJS_PROFILE_EXIT
}


std::optional<std::string> Universe::defaultAIForRole(const std::string &role)
{
	return OptionalStringIn(autoAIMap, role);
}


OOCargoQuantity Universe::maxCargoForShip(const std::string &desc)
{
	return OOShipRegistry::sharedRegistry()->shipInfoForKey(desc).get<unsigned int>("max_cargo", 0);
}




// Slice 10 of docs/phases/3-slices/Universe.md (bead oo-e9enf): equipment prices, commodities and
// cargo pods, the game view and controller, settings, entity lighting, the active view matrix. The
// facade forwarded each selector (until oo-ql9rn); sends to self were sends (ADR-0056
// amendment oo-27jxj).

/*
 * Price for an item expressed in 10ths of credits (divide by 10 to get credits)
 */
OOCreditsQuantity Universe::getEquipmentPriceForKey(const std::string &eq_key)
{
	if (const oo::PList::Array *items = equipmentData.getIf<oo::PList::Array>())
	{
		for (const oo::PList &itemData : *items)
		{
			std::optional<std::string> itemType = OptionalStringAt(itemData, EQUIPMENT_KEY_INDEX);

			if (itemType.has_value() && *itemType == eq_key)
			{
				return itemData.at<unsigned long long>(EQUIPMENT_PRICE_INDEX);
			}
		}
	}
	return 0;
}


::OOCommodities * Universe::getCommodities()
{
	return commodities.get();
}


/* Converts template cargo pods to real ones */
::ShipEntity * Universe::reifyCargoPod(::ShipEntity *cargoObj)
{
	if ((cargoObj != nullptr ? cargoObj->isTemplateCargoPod() : false))
	{
		return (UNIVERSE != nullptr ? UNIVERSE->cargoPodFromTemplate(cargoObj) : (::ShipEntity *)nil);
	}
	else
	{
		return cargoObj;
	}
}


::ShipEntity * Universe::cargoPodFromTemplate(::ShipEntity *cargoObj)
{
	::ShipEntity *container = nil;
	// this is a template container, so we need to make a real one
	const std::optional<std::string> co_type = (cargoObj != nullptr ? cargoObj->commodityType() : std::optional<std::string>());
	OOCargoQuantity co_amount = co_type.has_value() ? (UNIVERSE != nullptr ? UNIVERSE->getRandomAmountOfCommodity(*co_type) : 0) : 0;
	if (randf() < 0.5) // stops OXP monopolising pods for commodities
	{
		container = co_type.has_value() ? (UNIVERSE != nullptr ? UNIVERSE->newShipWithRole(*co_type) : (::ShipEntity *)nil) : nil; // newShipWithRole returns retained object
	}
	if (container == nil)
	{
		container = (UNIVERSE != nullptr ? UNIVERSE->newShipWithRole("cargopod") : (::ShipEntity *)nil);
	}
	if (co_type.has_value())  { if (container != nullptr)  container->setCommodity(*co_type, co_amount); }	// nil: no change, as before
	return (container != nullptr ? oo::ToShip(oo::AutoreleaseEntity(container)) : (::ShipEntity *)nil);
}


std::vector<oo::EntityHold> Universe::getContainersOfGoods(OOCargoQuantity how_many, bool scarce, bool legal)
{
	/*	build list of goods allocating 0..100 for each based on how much of
		each quantity there is. Use a ratio of n x 100/64 for plentiful goods;
		reverse the probabilities for scarce goods.
	*/
	std::vector<oo::EntityHold>	accumulator;
	accumulator.reserve(how_many);
	NSUInteger		i=0, commodityCount = (commodityMarket != nullptr ? commodityMarket->count() : 0);
	std::vector<OOCargoQuantity> quantities(commodityCount);
	OOCargoQuantity total_quantity = 0;

	const std::vector<std::string>	goodsKeys = (commodityMarket != nullptr ? commodityMarket->goods() : std::vector<std::string>());

	for (const std::string &goodsKey : goodsKeys)
	{
		OOCargoQuantity q = (commodityMarket != nullptr ? commodityMarket->quantityForGood(goodsKey) : 0);
		if (scarce)
		{
			if (q < 64)  q = 64 - q;
			else  q = 0;
		}
		// legal YES restricts (almost) only to legal goods
		// legal NO allows illegal goods, but not necessarily a full hold
		if (legal && (commodityMarket != nullptr ? commodityMarket->exportLegalityForGood(goodsKey) : 0) > 0)
		{
			q &= 1; // keep a very small chance, sometimes
		}
		if (q > 64) q = 64;
		q *= 100;   q/= 64;
		quantities[i++] = q;
		total_quantity += q;
	}
	// quantities is now used to determine which good get into the containers
	for (i = 0; i < how_many; i++)
	{
		NSUInteger co_type = 0;
		
		int qr=0;
		if(total_quantity)
		{
			qr = 1+(Ranrot() % total_quantity);
			co_type = 0;
			while (qr > 0)
			{
				OOCAssert((NSUInteger)co_type < commodityCount, "Commodity type index out of range.");
				qr -= quantities[co_type++];
			}
			co_type--;
		}

		const std::optional<std::string> goodsKey = (co_type < goodsKeys.size()) ? std::optional<std::string>(goodsKeys[co_type]) : std::nullopt;
		::ShipEntity *container = nil;
		if (goodsKey.has_value())
		{
			const auto pod = cargoPods.find(*goodsKey);
			if (pod != cargoPods.end())  container = oo::ToShip(pod->second.get());
		}

		if (container != nil)
		{
			accumulator.push_back(oo::EntityHold(container));
		}
		else
		{
			OO_LOG("universe.createContainer.failed", "***** ERROR: failed to find a container to fill with {} ({}).", goodsKey.value_or("(null)"), static_cast<size_t>(co_type));

		}
	}
	return accumulator;
}


std::vector<oo::EntityHold> Universe::getContainersOfCommodity(const std::string &commodity_name, OOCargoQuantity how_much)
{
	std::vector<oo::EntityHold>	accumulator;
	accumulator.reserve(how_much);
	if (!(commodities != nullptr ? commodities->goodDefined(commodity_name) : false))
	{
		return accumulator; // empty array
	}

	::ShipEntity *container = nil;
	const auto pod = cargoPods.find(commodity_name);
	if (pod != cargoPods.end())  container = oo::ToShip(pod->second.get());
	while (how_much > 0)
	{
		if (container)
		{
			accumulator.push_back(oo::EntityHold(container));
		}
		else
		{
			OO_LOG("universe.createContainer.failed", "***** ERROR: failed to find a container to fill with {}", commodity_name);
		}

		how_much--;
	}
	return accumulator;
}


void Universe::fillCargopodWithRandomCargo(::ShipEntity *cargopod)
{
	if (cargopod == nil || !(cargopod != nullptr ? cargopod->hasRole("cargopod") : false) || (cargopod != nullptr && cargopod->cargoType() == CARGO_SCRIPTED_ITEM))  return;

	if (!(cargopod != nullptr ? cargopod->commodityType() : std::optional<std::string>()).has_value() || !(cargopod != nullptr ? cargopod->commodityAmount() : 0))
	{
		const std::string aCommodity = getRandomCommodity();
		OOCargoQuantity aQuantity = getRandomAmountOfCommodity(aCommodity);
		if (cargopod != nullptr)  cargopod->setCommodity(aCommodity, aQuantity);
	}
}


std::string Universe::getRandomCommodity()
{
	return (commodities != nullptr ? commodities->getRandomCommodity() : std::string());
}


OOCargoQuantity Universe::getRandomAmountOfCommodity(const std::string &co_type)
{
	OOMassUnit		units;

	units = (commodities != nullptr ? commodities->massUnitForGood(co_type) : UNITS_TONS);
	switch (units)
	{
		case 0 :	// TONNES
			return 1;
		case 1 :	// KILOGRAMS
			return 1 + (Ranrot() % 6) + (Ranrot() % 6) + (Ranrot() % 6);
		case 2 :	// GRAMS
			return 4 + (Ranrot() % 16) + (Ranrot() % 11) + (Ranrot() % 6);
		case UNITS_UNKNOWN :	// not a unit (ADR-0036): warned about below, as any other value was
			break;
	}
	OO_LOG("universe.commodityAmount.warning", "Commodity {} has an unrecognised mass unit, assuming tonnes", co_type);
	return 1;
}


oo::PList Universe::commodityDataForType(const std::string &type)
{
	return (commodityMarket != nullptr ? commodityMarket->definitionForGood(type) : oo::PList());
}


std::optional<std::string> Universe::displayNameForCommodity(const std::string &co_type)
{
	return (commodityMarket != nullptr ? commodityMarket->nameForGood(co_type) : std::optional<std::string>());
}


std::optional<std::string> Universe::describeCommodity(const std::string &co_type, OOCargoQuantity co_amount)
{
	int				units;
	std::string		unitDesc;
	std::optional<std::string>	typeDesc;
	const oo::PList	commodity = commodityDataForType(co_type);

	if (commodity.isNull()) return std::string();

	units = (commodityMarket != nullptr ? commodityMarket->massUnitForGood(co_type) : UNITS_TONS);
	if (co_amount == 1)
	{
		switch (units)
		{
			case UNITS_KILOGRAMS :	// KILOGRAM
				unitDesc = cxx_OOLookUpDescriptionPRIV("cargo-kilogram");
				break;
			case UNITS_GRAMS :	// GRAM
				unitDesc = cxx_OOLookUpDescriptionPRIV("cargo-gram");
				break;
			case UNITS_TONS :	// TONNE
			default :
				unitDesc = cxx_OOLookUpDescriptionPRIV("cargo-ton");
				break;
		}
	}
	else
	{
		switch (units)
		{
			case UNITS_KILOGRAMS :	// KILOGRAMS
				unitDesc = cxx_OOLookUpDescriptionPRIV("cargo-kilograms");
				break;
			case UNITS_GRAMS :	// GRAMS
				unitDesc = cxx_OOLookUpDescriptionPRIV("cargo-grams");
				break;
			case UNITS_TONS :	// TONNES
			default :
				unitDesc = cxx_OOLookUpDescriptionPRIV("cargo-tons");
				break;
		}
	}

	typeDesc = (commodityMarket != nullptr ? commodityMarket->nameForGood(co_type) : std::optional<std::string>());

	return oo::str::format("%d %s %s",co_amount, unitDesc.c_str(), TextOrNull(typeDesc).c_str());
}


////////////////////////////////////////////////////

void Universe::setGameView(::MyOpenGLView *view)
{
	if (gameView != nullptr)  gameView->release();
	if (view != nullptr)  view->retain();
	gameView = view;
}


::MyOpenGLView * Universe::getGameView()
{
	return gameView;
}


::GameController * Universe::gameController()
{
	return (getGameView() != nullptr ? getGameView()->getGameController() : (::GameController *)nullptr);
}


// The number kinds the old dictionary held: oo_setInteger: a signed integer, oo_setBool: a
// boolean, oo_setFloat: / +numberWithFloat: a single-precision real.
oo::PList Universe::gameSettings()
{
	oo::PList::Dict result;

	result["speechOn"] = oo::PList::signedInteger((PLAYER != nullptr ? PLAYER->getIsSpeechOn() : OOSpeechSettings{}));
	result["autosave"] = oo::PList(static_cast<bool>(autoSave));
	result["wireframeGraphics"] = oo::PList(static_cast<bool>(wireframeGraphics));
	result["procedurallyTexturedPlanets"] = oo::PList(static_cast<bool>(doProcedurallyTexturedPlanets));

	result["fovValue"] = oo::PList::singleReal((gameView != nullptr ? gameView->fov(NO) : 0.0f));

#if OOLITE_WINDOWS
	if ((gameView != nullptr ? gameView->hdrOutput() : false))
	{
		result["hdr-max-brightness"] = oo::PList::singleReal((gameView != nullptr ? gameView->hdrMaxBrightness() : 0.0f));
		result["hdr-paperwhite-brightness"] = oo::PList::singleReal((gameView != nullptr ? gameView->hdrPaperWhiteBrightness() : 0.0f));
		result["hdr-tone-mapper"] = oo::PList(cxx_OOStringFromHDRToneMapper((gameView != nullptr ? gameView->hdrToneMapper() : OOHDRToneMapper{})));
	}
#endif

	result["sdr-tone-mapper"] = oo::PList(cxx_OOStringFromSDRToneMapper((gameView != nullptr ? gameView->sdrToneMapper() : OOSDRToneMapper{})));

	result["detailLevel"] = oo::PList(cxx_OOStringFromGraphicsDetail(getDetailLevel()));

	const char *desc = "UNDEFINED";
	switch (OOMusicController::sharedController()->mode())
	{
		case kOOMusicOff:		desc = "MUSIC_OFF"; break;
		case kOOMusicOn:		desc = "MUSIC_ON"; break;
		case kOOMusicITunes:	desc = "MUSIC_ITUNES"; break;
	}
	result["musicMode"] = oo::PList(desc);

	result["gameWindow"] = oo::PList(oo::PList::Dict{
		{ "width", oo::PList::singleReal((gameView != nullptr ? gameView->backingViewSize() : NSSize{}).width) },
		{ "height", oo::PList::singleReal((gameView != nullptr ? gameView->backingViewSize() : NSSize{}).height) },
		{ "fullScreen", oo::PList(static_cast<bool>((gameController() != nullptr ? gameController()->inFullScreenMode() : false))) },
	});

	result["keyConfig"] = (PLAYER != nullptr ? PLAYER->keyConfig() : oo::PList());

	return oo::PList(std::move(result));
}


void Universe::useGUILightSource(bool GUILight)
{
	if (GUILight != demo_light_on)
	{
		if (!useShaders())
		{
			if (GUILight) 
			{
				OOGL(glEnable(GL_LIGHT0));
				OOGL(glDisable(GL_LIGHT1));
			}
			else
			{
				OOGL(glEnable(GL_LIGHT1));
				OOGL(glDisable(GL_LIGHT0));
			}
		}
		// There should be nothing to do for shaders, they use the same (always on) light source
		// both in flight & in gui mode. According to the standard, shaders should treat lights as
		// always enabled. At least one non-standard shader implementation (windows' X3100 Intel
		// core with GM965 chipset and version 6.14.10.4990 driver) does _not_ use glDisabled lights,
		// making the following line necessary.
		
		else OOGL(glEnable(GL_LIGHT1)); // make sure we have a light, even with shaders (!)
		
		demo_light_on = GUILight;
	}
}


void Universe::lightForEntity(bool isLit)
{
	if (isLit != object_light_on)
	{
		if (useShaders())
		{
			if (isLit)
			{
				OOGL(glLightfv(GL_LIGHT1, GL_DIFFUSE, sun_diffuse));
				OOGL(glLightfv(GL_LIGHT1, GL_SPECULAR, sun_specular));
			}
			else
			{
				OOGL(glLightfv(GL_LIGHT1, GL_DIFFUSE, sun_off));
				OOGL(glLightfv(GL_LIGHT1, GL_SPECULAR, sun_off));
			}
		}
		else
		{
			if (!demo_light_on)
			{
				if (isLit) OOGL(glEnable(GL_LIGHT1));
				else OOGL(glDisable(GL_LIGHT1));
			}
			else
			{
				// If we're in demo/GUI mode we should always have a lit object.
				OOGL(glEnable(GL_LIGHT0));
				
				// Redundant, see above.
				//if (isLit)  OOGL(glEnable(GL_LIGHT0));
				//else  OOGL(glDisable(GL_LIGHT0));
			}
		}
		
		object_light_on = isLit;
	}
}


void Universe::getActiveViewMatrix(OOMatrix *outMatrix, Vector *outForward, Vector *outUp)
{
	assert(outMatrix != NULL && outForward != NULL && outUp != NULL);
	
	::PlayerEntity			*player = nil;
	
	switch (viewDirection)
	{
		case VIEW_AFT:
			*outMatrix = aft_matrix;
			*outForward = vector_flip(kBasisZVector);
			*outUp = kBasisYVector;
			return;
			
		case VIEW_PORT:
			*outMatrix = port_matrix;
			*outForward = vector_flip(kBasisXVector);
			*outUp = kBasisYVector;
			return;
			
		case VIEW_STARBOARD:
			*outMatrix = starboard_matrix;
			*outForward = kBasisXVector;
			*outUp = kBasisYVector;
			return;
			
		case VIEW_CUSTOM:
			OOCParameterAssert(outUp != nullptr);	// as the assert above (the analyser follows this one)
			player = PLAYER;
			*outMatrix = (player != nullptr ? player->getCustomViewMatrix() : OOMatrix{});
			*outForward = (player != nullptr ? player->getCustomViewForwardVector() : Vector{});
			*outUp = (player != nullptr ? player->getCustomViewUpVector() : Vector{});
			return;
			
		case VIEW_FORWARD:
		case VIEW_NONE:
		case VIEW_GUI_DISPLAY:
		case VIEW_BREAK_PATTERN:
			;
	}
	
	*outMatrix = fwd_matrix;
	*outForward = kBasisZVector;
	*outUp = kBasisYVector;
}


OOMatrix Universe::activeViewMatrix()
{
	OOMatrix			m;
	Vector				f, u;
	
	getActiveViewMatrix(&m, &f, &u);
	return m;
}




// Slice 11 of docs/phases/3-slices/Universe.md (bead oo-8rsqz): the view frustum. The facade
// forwarded each selector (until oo-ql9rn); sends to self were sends (ADR-0056 amendment
// oo-27jxj).

/* Code adapted from http://www.crownandcutlass.com/features/technicaldetails/frustum.html
 * Original license is: "This page and its contents are Copyright 2000 by Mark Morley
 * Unless otherwise noted, you may use any and all code examples provided herein in any way you want."
*/

void Universe::defineFrustum()
{
	OOMatrix clip;
	GLfloat   rt;
	
	clip = OOGLGetModelViewProjection();
	
	/* Extract the numbers for the RIGHT plane */
	frustum[0][0] = clip.m[0][3] - clip.m[0][0];
	frustum[0][1] = clip.m[1][3] - clip.m[1][0];
	frustum[0][2] = clip.m[2][3] - clip.m[2][0];
	frustum[0][3] = clip.m[3][3] - clip.m[3][0];
	
	/* Normalize the result */
	rt = 1.0f / sqrt(frustum[0][0] * frustum[0][0] + frustum[0][1] * frustum[0][1] + frustum[0][2] * frustum[0][2]);
	frustum[0][0] *= rt;
	frustum[0][1] *= rt;
	frustum[0][2] *= rt;
	frustum[0][3] *= rt;
	
	/* Extract the numbers for the LEFT plane */
	frustum[1][0] = clip.m[0][3] + clip.m[0][0];
	frustum[1][1] = clip.m[1][3] + clip.m[1][0];
	frustum[1][2] = clip.m[2][3] + clip.m[2][0];
	frustum[1][3] = clip.m[3][3] + clip.m[3][0];
	
	/* Normalize the result */
	rt = 1.0f / sqrt(frustum[1][0] * frustum[1][0] + frustum[1][1] * frustum[1][1] + frustum[1][2] * frustum[1][2]);
	frustum[1][0] *= rt;
	frustum[1][1] *= rt;
	frustum[1][2] *= rt;
	frustum[1][3] *= rt;

	/* Extract the BOTTOM plane */
	frustum[2][0] = clip.m[0][3] + clip.m[0][1];
	frustum[2][1] = clip.m[1][3] + clip.m[1][1];
	frustum[2][2] = clip.m[2][3] + clip.m[2][1];
	frustum[2][3] = clip.m[3][3] + clip.m[3][1];

	/* Normalize the result */
	rt = 1.0 / sqrt(frustum[2][0] * frustum[2][0] + frustum[2][1] * frustum[2][1] + frustum[2][2] * frustum[2][2]);
	frustum[2][0] *= rt;
	frustum[2][1] *= rt;
	frustum[2][2] *= rt;
	frustum[2][3] *= rt;

	/* Extract the TOP plane */
	frustum[3][0] = clip.m[0][3] - clip.m[0][1];
	frustum[3][1] = clip.m[1][3] - clip.m[1][1];
	frustum[3][2] = clip.m[2][3] - clip.m[2][1];
	frustum[3][3] = clip.m[3][3] - clip.m[3][1];

	/* Normalize the result */
	rt = 1.0 / sqrt(frustum[3][0] * frustum[3][0] + frustum[3][1] * frustum[3][1] + frustum[3][2] * frustum[3][2]);
	frustum[3][0] *= rt;
	frustum[3][1] *= rt;
	frustum[3][2] *= rt;
	frustum[3][3] *= rt;

	/* Extract the FAR plane */
	frustum[4][0] = clip.m[0][3] - clip.m[0][2];
	frustum[4][1] = clip.m[1][3] - clip.m[1][2];
	frustum[4][2] = clip.m[2][3] - clip.m[2][2];
	frustum[4][3] = clip.m[3][3] - clip.m[3][2];

	/* Normalize the result */
	rt = sqrt(frustum[4][0] * frustum[4][0] + frustum[4][1] * frustum[4][1] + frustum[4][2] * frustum[4][2]);
	frustum[4][0] *= rt;
	frustum[4][1] *= rt;
	frustum[4][2] *= rt;
	frustum[4][3] *= rt;

	/* Extract the NEAR plane */
	frustum[5][0] = clip.m[0][3] + clip.m[0][2];
	frustum[5][1] = clip.m[1][3] + clip.m[1][2];
	frustum[5][2] = clip.m[2][3] + clip.m[2][2];
	frustum[5][3] = clip.m[3][3] + clip.m[3][2];

	/* Normalize the result */
	rt = sqrt(frustum[5][0] * frustum[5][0] + frustum[5][1] * frustum[5][1] + frustum[5][2] * frustum[5][2]);
	frustum[5][0] *= rt;
	frustum[5][1] *= rt;
	frustum[5][2] *= rt;
	frustum[5][3] *= rt;
}


bool Universe::viewFrustumIntersectsSphereAt(Vector position, GLfloat radius)
{
	// position is the relative position between the camera and the object
	int p;
	for (p = 0; p < 6; p++)
	{
		if (frustum[p][0] * position.x + frustum[p][1] * position.y + frustum[p][2] * position.z + frustum[p][3] <= -radius)
		{
			return NO;
		}
	}
	return YES;
}




// Slice 12 of docs/phases/3-slices/Universe.md (bead oo-9lucq): drawUniverse, framebuffer
// preparation, frame counters, the view matrix. The facade forwarded each selector
// (until oo-ql9rn); sends to self were sends (ADR-0056 amendment oo-27jxj).

void Universe::drawUniverse()
{
	int currentPostFX = this->currentPostFX();
	BOOL hudSeparateRenderPass =  useShaders() && (currentPostFX == OO_POSTFX_NONE || ((currentPostFX == OO_POSTFX_CLOAK || currentPostFX == OO_POSTFX_CRTBADSIGNAL) && colorblindMode() == OO_POSTFX_NONE));
 	NSSize  viewSize = (gameView != nullptr ? gameView->backingViewSize() : NSSize{});
	OO_LOG("universe.profile.draw", "{}", "Begin draw");
	
	if (!no_update)
	{
		if ((int)targetFramebufferSize.width != (int)viewSize.width || (int)targetFramebufferSize.height != (int)viewSize.height)
		{
			resizeTargetFramebufferWithViewSize(viewSize);
		}
	
		if(useShaders())
		{
			if ((gameView != nullptr ? gameView->msaa() : false))
			{
				OOGL(glBindFramebuffer(GL_FRAMEBUFFER, msaaFramebufferID));
			}
			else
			{
				OOGL(glBindFramebuffer(GL_FRAMEBUFFER, targetFramebufferID));
			}
		}
		try
		{
			no_update = YES;	// block other attempts to draw
			
			int				i, v_status, vdist;
			Vector			view_dir, view_up;
			OOMatrix		view_matrix;
			int				ent_count =	n_entities;
			std::vector<Entity *> my_entities(ent_count);	// each one's object retained and autoreleased (bead oo-9ht.39.26)
			int				draw_count = 0;
			::PlayerEntity	*player = PLAYER;
			Entity		*drawthing = nullptr;
			BOOL			demoShipMode = (player != nullptr ? player->getShowDemoShips() : false);
			
			float   aspect = viewSize.height/viewSize.width;

			if (!displayGUI && wasDisplayGUI)
			{
				// reset light1 position for the shaders
				if (cachedSun) { if (UNIVERSE != nullptr)  UNIVERSE->setMainLightPosition(HPVectorToVector((cachedSun != nullptr ? cachedSun->getPosition() : HPVector{}))); } // the main light is the sun.
				else { if (UNIVERSE != nullptr)  UNIVERSE->setMainLightPosition(kZeroVector); }
			}
			wasDisplayGUI = displayGUI;
			// use a non-mutable copy so this can't be changed under us.
			for (i = 0; i < ent_count; i++)
			{
				/* BUG: this list is ordered nearest to furthest from
				 * the player, and we just assume that the camera is
				 * on/near the player. So long as everything uses
				 * depth tests, we'll get away with it; it'll just
				 * occasionally be inefficient. - CIM */
				Entity *e = sortedEntities[i]; // ordered NEAREST -> FURTHEST AWAY
				if (e->isVisible())
				{
					my_entities[draw_count++] = oo::AutoreleaseEntity(oo::RetainEntity(e));
				}
			}
			
			v_status = (player != nullptr ? player->status() : OOEntityStatus{});
			
			cxx_OOCheckOpenGLErrors("Universe before doing anything");
			
			OOSetOpenGLState(OPENGL_STATE_OPAQUE);  // FIXME: should be redundant.
			
			OOGL(glClear(GL_COLOR_BUFFER_BIT));

			if (!displayGUI)
			{
				OOGL(glClearColor(skyClearColor[0], skyClearColor[1], skyClearColor[2], skyClearColor[3]));
			}
			else
			{
				OOGL(glClearColor(0.0, 0.0, 0.0, 0.0));
				// If set, display background GUI image. Must be done before enabling lights to avoid dim backgrounds
				OOGLResetProjection();
				OOGLFrustum(-0.5, 0.5, -aspect*0.5, aspect*0.5, 1.0, MAX_CLEAR_DEPTH);
				if (gui != nullptr)  gui->drawGUIBackground();
			
			}

			BOOL		fogging, bpHide = breakPatternHide();

			drawCounter++;
			float breakPlane = INTERMEDIATE_CLEAR_DEPTH;
			for( int i = 0; i < draw_count; i++ )
			{
				if (my_entities[i]->cameraRangeFront() > breakPlane)
				{
					continue;
				}
				if (my_entities[i]->cameraRangeBack() > breakPlane)
				{
					breakPlane = my_entities[i]->cameraRangeBack();
				}
			}

			// We need to bring forward the near plane of the frustum on the long distance pass by this factor to avoid clipping objects at the corner of the window
			float distanceFactor = sqrt(1 + ((gameView != nullptr ? gameView->fov(YES) : 0.0f)*(gameView != nullptr ? gameView->fov(YES) : 0.0f) * (1.0 + 1.0/(aspect*aspect)))); 

			for (vdist=0;vdist<=1;vdist++)
			{
				float   nearPlane = vdist ? 1.0 : INTERMEDIATE_CLEAR_DEPTH;
				float   farPlane = vdist ? breakPlane : MAX_CLEAR_DEPTH;
				float   ratio = (displayGUI ? 0.5 : (gameView != nullptr ? gameView->fov(YES) : 0.0f)) * nearPlane / distanceFactor; // 0.5 is field of view ratio for GUIs
				
				OOGLResetProjection();
				if ((displayGUI && 4*aspect >= 3) || (!displayGUI && 4*aspect <= 3))
				{
					OOGLFrustum(-ratio, ratio, -aspect*ratio, aspect*ratio, nearPlane / distanceFactor, farPlane);
				}
				else
				{
					OOGLFrustum(-3*ratio/aspect/4, 3*ratio/aspect/4, -3*ratio/4, 3*ratio/4, nearPlane / distanceFactor, farPlane);
				}

				getActiveViewMatrix(&view_matrix, &view_dir, &view_up);

				OOGLResetModelView();	// reset matrix
				OOGLLookAt(kZeroVector, kBasisZVector, kBasisYVector);
			
				// HACK BUSTED
				OOGLMultModelView(OOMatrixForScale(-1.0,1.0,1.0)); // flip left and right
				OOGLPushModelView(); // save this flat viewpoint

				/* OpenGL viewpoints: 
				 *
				 * Oolite used to transform the viewpoint by the inverse of the
				 * view position, and then transform the objects by the inverse
				 * of their position, to get the correct view. However, as
				 * OpenGL only uses single-precision floats, this causes
				 * noticeable display inaccuracies relatively close to the
				 * origin.
				 *
				 * Instead, we now calculate the difference between the view
				 * position and the object using high-precision vectors, convert
				 * the difference to a low-precision vector (since if you can
				 * see it, it's close enough for the loss of precision not to
				 * matter) and use that relative vector for the OpenGL transform
				 *
				 * Objects which reset the view matrix in their display need to be
				 * handled a little more carefully than before.
				 */

				OOSetOpenGLState(OPENGL_STATE_OPAQUE); 
				// clearing the depth buffer waits until we've set
				// STATE_OPAQUE so that depth writes are definitely
				// available.
				OOGL(glClear(GL_DEPTH_BUFFER_BIT));
		

				// Set up view transformation matrix
				OOMatrix flipMatrix = kIdentityMatrix;
				flipMatrix.m[2][2] = -1;
				view_matrix = OOMatrixMultiply(view_matrix, flipMatrix);
				Vector viewOffset = (player != nullptr ? player->viewpointOffset() : Vector{});
			
				OOGLLookAt(view_dir, kZeroVector, view_up); 

				if (EXPECT(!displayGUI || demoShipMode))
				{
					if (EXPECT(!demoShipMode))	// we're in flight
					{
						// rotate the view
						OOGLMultModelView((player != nullptr ? player->rotationMatrix() : OOMatrix{}));
						// translate the view
						// HPVect: camera-relative position
						OOGL(glLightModelfv(GL_LIGHT_MODEL_AMBIENT, stars_ambient));
						// main light position, no shaders, in-flight / shaders, in-flight and docked.
						if (cachedSun)
						{
							setMainLightPosition((cachedSun != nullptr ? cachedSun->getCameraRelativePosition() : Vector{}));
						}
						else
						{
							// in witchspace
							setMainLightPosition(HPVectorToVector(HPvector_flip((PLAYER != nullptr ? PLAYER->viewpointPosition() : HPVector{}))));
						}
						OOGL(glLightfv(GL_LIGHT1, GL_POSITION, main_light_position));	
					}
					else
					{
						OOGL(glLightModelfv(GL_LIGHT_MODEL_AMBIENT, docked_light_ambient));
						// main_light_position no shaders, docked/GUI.
						OOGL(glLightfv(GL_LIGHT0, GL_POSITION, main_light_position));
						// main light position, no shaders, in-flight / shaders, in-flight and docked.		
						OOGL(glLightfv(GL_LIGHT1, GL_POSITION, main_light_position));
					}
				
				
					OOGL(useGUILightSource(demoShipMode));
				
					// HACK: store view matrix for absolute drawing of active subentities (i.e., turrets, flashers).
					viewMatrix = OOGLGetModelView();

					int			furthest = draw_count - 1;
					int			nearest = 0;
					BOOL		inAtmosphere = airResistanceFactor > 0.01;
					GLfloat		fogFactor = 0.5 / airResistanceFactor;
					double 		fog_scale, half_scale;
					GLfloat 	flat_ambdiff[4]	= {1.0, 1.0, 1.0, 1.0};   // for alpha
					GLfloat 	mat_no[4]		= {0.0, 0.0, 0.0, 1.0};   // nothing
					GLfloat		fog_blend;
				
					OOGL(glHint(GL_FOG_HINT, reducedDetail() ? GL_FASTEST : GL_NICEST));

					defineFrustum(); // camera is set up for this frame

					OOVerifyOpenGLState();
					cxx_OOCheckOpenGLErrors("Universe after setting up for opaque pass");
					OO_LOG("universe.profile.draw", "{}", "Begin opaque pass");

				
					//		DRAW ALL THE OPAQUE ENTITIES
					for (i = furthest; i >= nearest; i--)
					{
						drawthing = my_entities[i];
						OOEntityStatus d_status = oo::EntityStatus(drawthing);
					
						if (bpHide && !drawthing->isImmuneToBreakPatternHide)  continue;
						if (drawthing->getLastDrawCounter() == drawCounter) continue;
						if (vdist == 0 && drawthing->cameraRangeFront() < nearPlane)
						{
							continue;
						}

						if (!((d_status == STATUS_COCKPIT_DISPLAY) ^ demoShipMode)) // either demo ship mode or in flight
						{
							// reset material properties
							// FIXME: should be part of SetState
							OOGL(glMaterialfv(GL_FRONT_AND_BACK, GL_AMBIENT_AND_DIFFUSE, flat_ambdiff));
							OOGL(glMaterialfv(GL_FRONT_AND_BACK, GL_EMISSION, mat_no));
						
							OOGLPushModelView();
							if (EXPECT(drawthing != player))
							{
								//translate the object
								// HPVect: camera relative
								drawthing->updateCameraRelativePosition();
								OOGLTranslateModelView(drawthing->getCameraRelativePosition());
								//rotate the object
								OOGLMultModelView(drawthing->drawRotationMatrix());
							}
							else
							{
								// Load transformation matrix
								OOGLLoadModelView(view_matrix);
								//translate the object  from the viewpoint
								OOGLTranslateModelView(vector_flip(viewOffset));
							}
						
							// atmospheric fog
							fogging = (inAtmosphere && !drawthing->isStellarObject());
						
							if (fogging)
							{
								fog_scale = BILLBOARD_DEPTH * fogFactor;
								half_scale = fog_scale * 0.50;
								OOGL(glEnable(GL_FOG));
								OOGL(glFogi(GL_FOG_MODE, GL_LINEAR));
								OOGL(glFogfv(GL_FOG_COLOR, skyClearColor));
								OOGL(glFogf(GL_FOG_START, half_scale));
								OOGL(glFogf(GL_FOG_END, fog_scale));
								fog_blend = OOClamp_0_1_f((magnitude(drawthing->getCameraRelativePosition()) - half_scale)/half_scale);
								drawthing->setAtmosphereFogging(OOColor::colorWithRed(skyClearColor[0], skyClearColor[1], skyClearColor[2], fog_blend).get());
							}
						
							lightForEntity(demoShipMode || drawthing->isSunlit);
						
							// draw the thing
							drawthing->setLastDrawCounter(drawCounter);
							drawthing->drawImmediate(false, false);
						
							OOGLPopModelView();

							// atmospheric fog
							if (fogging)
							{
								drawthing->setAtmosphereFogging(OOColor::colorWithRed(0.0, 0.0, 0.0, 0.0).get());
								OOGL(glDisable(GL_FOG));
							}
						
						}
				
						if (!((d_status == STATUS_COCKPIT_DISPLAY) ^ demoShipMode)) // either in flight or in demo ship mode
						{
							OOGLPushModelView();
							if (EXPECT(drawthing != player))
							{
								//translate the object
								// HPVect: camera relative positions
								drawthing->updateCameraRelativePosition();
								OOGLTranslateModelView(drawthing->getCameraRelativePosition());
								//rotate the object
								OOGLMultModelView(drawthing->drawRotationMatrix());
							}
							else
							{
								// Load transformation matrix
								OOGLLoadModelView(view_matrix);
								//translate the object  from the viewpoint
								OOGLTranslateModelView(vector_flip(viewOffset));
							}
						
							// experimental - atmospheric fog
							fogging = (inAtmosphere && !drawthing->isStellarObject());
						
							if (fogging)
							{
								fog_scale = BILLBOARD_DEPTH * fogFactor;
								half_scale = fog_scale * 0.50;
								OOGL(glEnable(GL_FOG));
								OOGL(glFogi(GL_FOG_MODE, GL_LINEAR));
								OOGL(glFogfv(GL_FOG_COLOR, skyClearColor));
								OOGL(glFogf(GL_FOG_START, half_scale));
								OOGL(glFogf(GL_FOG_END, fog_scale));
								fog_blend = OOClamp_0_1_f((magnitude(drawthing->getCameraRelativePosition()) - half_scale)/half_scale);
								drawthing->setAtmosphereFogging(OOColor::colorWithRed(skyClearColor[0], skyClearColor[1], skyClearColor[2], fog_blend).get());
							}
						
							// draw the thing
							drawthing->setLastDrawCounter(drawCounter);
							drawthing->drawImmediate(false, true);
						
							// atmospheric fog
							if (fogging)
							{
								drawthing->setAtmosphereFogging(OOColor::colorWithRed(0.0, 0.0, 0.0, 0.0).get());
								OOGL(glDisable(GL_FOG));
							}
						
							OOGLPopModelView();
						}
					}
				}

				OOGLPopModelView();
			}
			
			// glare effects covering the entire game window
			OOGLResetProjection();
			OOGLFrustum(-0.5, 0.5, -aspect*0.5, aspect*0.5, 1.0, MAX_CLEAR_DEPTH);
			OOSetOpenGLState(OPENGL_STATE_OVERLAY);  // FIXME: should be redundant.
			if (EXPECT(!displayGUI))
			{
				if (!bpHide && cachedSun)
				{
					if (cachedSun != nullptr)  cachedSun->drawDirectVisionSunGlare();
					if (cachedSun != nullptr)  cachedSun->drawStarGlare();
				}
			}
			
			// actions when the HUD should be rendered separately from the 3d universe
			if (hudSeparateRenderPass)
			{
				cxx_OOCheckOpenGLErrors("Universe after drawing entities");
				OOSetOpenGLState(OPENGL_STATE_OVERLAY);  // FIXME: should be redundant.
				
				prepareToRenderIntoDefaultFramebuffer();	
				OOGL(glBindFramebuffer(GL_FRAMEBUFFER, defaultDrawFBO));
				
				OO_LOG("universe.profile.secondPassDraw", "{}", "Begin second pass draw");
				drawTargetTextureIntoDefaultFramebuffer();
				cxx_OOCheckOpenGLErrors("Universe after drawing from custom framebuffer to screen framebuffer");
				OO_LOG("universe.profile.secondPassDraw", "{}", "End second pass drawing");
	
				OO_LOG("universe.profile.drawHUD", "{}", "Begin HUD drawing");
			}
			
			/* Reset for HUD drawing */
			cxx_OOCheckOpenGLErrors("Universe after drawing entities");
			OO_LOG("universe.profile.draw", "{}", "Begin HUD");
			
			GLfloat	lineWidth = (gameView != nullptr ? gameView->backingViewSize() : NSSize{}).width / 1024.0; // restore line size
			if (lineWidth < 1.0)  lineWidth = 1.0;
			if (lineWidth > 1.5)  lineWidth = 1.5; // don't overscale; think of ultra-wide screen setups
			OOGL(GLScaledLineWidth(lineWidth));

			::HeadUpDisplay *theHUD = (player != nullptr ? player->getHud() : (HeadUpDisplay *)nullptr);
			
			// If the HUD has a non-nil deferred name string, it means that a HUD switch was requested while it was being rendered.
			// If so, execute the deferred HUD switch now - Nikos 20110628
			if (theHUD != nullptr && theHUD->getDeferredHudName().has_value())	// a nil HUD answered nil
			{
				const std::string deferredName = *theHUD->getDeferredHudName();	// a copy: the switch releases the HUD
				if (player != nullptr)  player->switchHudTo(deferredName);
				theHUD = (player != nullptr ? player->getHud() : (HeadUpDisplay *)nullptr);	// HUD has been changed, so point to its new address
			}
			
			// Hiding HUD: has been a regular - non-debug - feature as of r2749, about 2 yrs ago! --Kaks 2011.10.14
			static float sPrevHudAlpha = -1.0f;
			if (theHUD != nullptr && theHUD->isHidden())
			{
				if (sPrevHudAlpha < 0.0f)
				{
					sPrevHudAlpha = theHUD->getOverallAlpha();
				}
				theHUD->setOverallAlpha(0.0f);
			}
			else if (sPrevHudAlpha >= 0.0f)
			{
				if (theHUD != nullptr)  theHUD->setOverallAlpha(sPrevHudAlpha);
				sPrevHudAlpha = -1.0f;
			}
			
			switch (v_status) {
			case STATUS_DEAD:
			case STATUS_ESCAPE_SEQUENCE:
			case STATUS_START_GAME:
				// no HUD rendering in these modes
				break;
			default:
				switch ((player != nullptr ? player->guiScreen() : OOGUIScreenID{}))
				{
				//case GUI_SCREEN_KEYBOARD:
					// no HUD rendering on this screen
					//break;
				default:
					if (theHUD != nullptr)
					{
						theHUD->setLineWidth(lineWidth);
						theHUD->renderHUD();
					}
				}
			}

			// should come after the HUD to avoid it being overlapped by it
			drawMessage();
			
#if (defined (DEV_RELEASE))
			drawWatermarkString("Development version " OO_VERSION_FULL);
#endif
			
			OO_LOG("universe.profile.drawHUD", "{}", "End HUD drawing");
			cxx_OOCheckOpenGLErrors("Universe after drawing HUD");
			
			OOGL(glFlush());	// don't wait around for drawing to complete
			
			no_update = NO;	// allow other attempts to draw
			
			// frame complete, when it is time to update the fps_counter, updateClocks:delta_t
			// in PlayerEntity.m will take care of resetting the processed frames number to 0.
			if (!(gameController() != nullptr ? gameController()->isGamePaused() : false))
			{
				framesDoneThisUpdate++;
			}
		}
		catch (...)
		{
			const auto exception = oo::CurrentOOException();
			if (!exception)  throw;	// not an OOException: it goes on up, as before
			no_update = NO;	// make sure we don't get stuck in all subsequent frames.
			
			if (strncmp(exception->name(), "Oolite", 6) == 0)
			{
				handleOoliteException(exception->object());
			}
			else
			{
				OO_LOG(cxx_kOOLogException, "***** Exception: {} : {} *****", exception->name(), exception->reason());
				throw;
			}
		}
	}
	
	OO_LOG("universe.profile.draw", "{}", "End drawing");
	
	// actions when the HUD should be rendered together with the 3d universe
	if(!hudSeparateRenderPass)
	{
		if(useShaders())
		{
			prepareToRenderIntoDefaultFramebuffer();
			OOGL(glBindFramebuffer(GL_FRAMEBUFFER, defaultDrawFBO));
			
			OO_LOG("universe.profile.secondPassDraw", "{}", "Begin second pass draw");
			drawTargetTextureIntoDefaultFramebuffer();
			OO_LOG("universe.profile.secondPassDraw", "{}", "End second pass drawing");
		}
	}
}


void Universe::prepareToRenderIntoDefaultFramebuffer()
{
	NSSize viewSize = (gameView != nullptr ? gameView->backingViewSize() : NSSize{});
	if(useShaders())
	{
		if ((gameView != nullptr ? gameView->msaa() : false))
		{
			// resolve MSAA framebuffer to target framebuffer
			OOGL(glBindFramebuffer(GL_READ_FRAMEBUFFER, msaaFramebufferID));
			OOGL(glBindFramebuffer(GL_DRAW_FRAMEBUFFER, targetFramebufferID));
			OOGL(glBlitFramebuffer(0, 0, (GLint)viewSize.width, (GLint)viewSize.height, 0, 0, (GLint)viewSize.width, (GLint)viewSize.height, GL_COLOR_BUFFER_BIT, GL_NEAREST));
		}
	}
}


int Universe::getFramesDoneThisUpdate()
{
	return framesDoneThisUpdate;
}


void Universe::resetFramesDoneThisUpdate()
{
	framesDoneThisUpdate = 0;
}


OOMatrix Universe::getViewMatrix()
{
	return viewMatrix;
}




// Slice 13 of docs/phases/3-slices/Universe.md (bead oo-0uz9w): messages and the watermark, entity
// look-up, the linked lists, adding and removing entities, demo ships. The facade forwarded each
// selector (until oo-ql9rn); sends to self were sends (ADR-0056 amendment oo-27jxj).

void Universe::drawMessage()
{
	OOSetOpenGLState(OPENGL_STATE_OVERLAY);
	
	OOGL(glDisable(GL_TEXTURE_2D));	// for background sheets
	
	HeadUpDisplay *hud = (PLAYER != nullptr ? PLAYER->getHud() : (HeadUpDisplay *)nullptr);
	float overallAlpha = (hud != nullptr) ? hud->getOverallAlpha() : 0.0f;	// a nil HUD answered 0
	if (displayGUI)
	{
		if ((gameController() != nullptr ? gameController()->mouseInteractionMode() : OOMouseInteractionMode{}) == MOUSE_MODE_UI_SCREEN_WITH_INTERACTION)
		{
			cursor_row = (gui != nullptr) ? gui->drawGUI(1.0, YES) : 0;	// a nil GUI answered 0
		}
		else
		{
			if (gui != nullptr)  gui->drawGUI(1.0, NO);
		}
	}
	
	if (message_gui != nullptr)  message_gui->drawGUI(message_gui->alpha() * overallAlpha, NO);
	if (comm_log_gui != nullptr)  comm_log_gui->drawGUI(comm_log_gui->alpha() * overallAlpha, NO);
	
	OOVerifyOpenGLState();
}


void Universe::drawWatermarkString(const std::string &watermarkString)
{
	NSSize watermarkStringSize = cxx_OORectFromString(watermarkString, 0.0f, 0.0f, NSMakeSize(10, 10)).size;

	OOGL(glColor4f(0.0, 1.0, 0.0, 1.0));
	// position the watermark string on the top right hand corner of the game window and right-align it
	const int halfGuiWidth = MAIN_GUI_PIXEL_WIDTH / 2, halfGuiHeight = MAIN_GUI_PIXEL_HEIGHT / 2;	// integer halves, as before
	cxx_OODrawString(watermarkString, halfGuiWidth - watermarkStringSize.width + 80,
						halfGuiHeight - watermarkStringSize.height, (gameView != nullptr ? gameView->getDisplay_z() : 0.0f), NSMakeSize(10,10));
}


Entity *Universe::entityForUniversalID(OOUniversalID u_id)
{
	if (u_id == 100)
		return PLAYER;	// the player
	
	if (MAX_ENTITY_UID < u_id)
	{
		OO_LOG("universe.badUID", "Attempt to retrieve entity for out-of-range UID {}. (This is an internal programming error, please report it.)", static_cast<unsigned>(u_id));
		return nil;
	}
	
	if ((u_id == NO_TARGET)||(!entity_for_uid[u_id]))
		return nil;
	
	Entity *ent = entity_for_uid[u_id];
	if (ent->isEffect())	// effects SHOULD NOT HAVE U_IDs!
	{
		return nil;
	}
	
	if (oo::EntityStatus(ent) == STATUS_DEAD || oo::EntityStatus(ent) == STATUS_DOCKED)
	{
		return nil;
	}
	
	return ent;
}


bool Universe::addEntity(Entity *entity)
{
	if (entity)
	{
		::ShipEntity *se = nil;
		
		if (!entity->validForAddToUniverse())  return NO;
		
		// don't add things twice!
		if (std::find(entities.begin(), entities.end(), entity) != entities.end())
			return YES;
		
		if (n_entities >= UNIVERSE_MAX_ENTITIES - 1)
		{
			// throw an exception here...
			OO_LOG("universe.addEntity.failed", "***** Universe cannot addEntity:{} -- Universe is full ({} entities out of {})", oo::EntityDescription(entity), static_cast<int>(n_entities), static_cast<int>(UNIVERSE_MAX_ENTITIES));
#ifndef NDEBUG
			if (oo::log::willDisplay("universe.maxEntitiesDump")) debugDumpEntities();
#endif
			return NO;
		}
		
		if (!entity->isEffect())
		{
			unsigned limiter = UNIVERSE_MAX_ENTITIES;
			while (entity_for_uid[next_universal_id] != nil)	// skip allocated numbers
			{
				next_universal_id++;						// increment keeps idkeys unique
				if (next_universal_id >= MAX_ENTITY_UID)
				{
					next_universal_id = MIN_ENTITY_UID;
				}
				if (limiter-- == 0)
				{
					// Every slot has been tried! This should not happen due to previous test, but there was a problem here in 1.70.
					OO_LOG("universe.addEntity.failed", "***** Universe cannot addEntity:{} -- Could not find free slot for entity.", oo::EntityDescription(entity));
					return NO;
				}
			}
			entity->setUniversalID(next_universal_id);
			entity_for_uid[next_universal_id] = entity;
			if (oo::EntityIsShip(entity))
			{
				se = oo::ToShip(entity);
				if ((se != nullptr ? se->isBeacon() : false))
				{
					setNextBeacon(se);	// the C++ ship (bead oo-9ht.39.8.10)
				}
				if ((se != nullptr ? se->getIsStation() : false))
				{
					// check if it is a proper rotating station (ie. roles contains the word "station")
					if ((oo::ToStation(se) != nullptr ? oo::ToStation(se)->isRotatingStation() : false))
					{
						double stationRoll = 0.0;
						// check for station_roll override
						const oo::PList shipInfo = (se != nullptr ? se->shipInfoDictionary() : oo::PList());
						const oo::PList *definedRoll = shipInfo.find("station_roll");
						
						if (definedRoll != nullptr)
						{
							stationRoll = oo::plist_get::realFrom<double>(definedRoll, stationRoll);	// OODoubleFromObject
						}
						else
						{
							stationRoll = currentSystemData().get<double>("station_roll", STANDARD_STATION_ROLL);
						}
						
						if (se != nullptr)  se->setRoll(stationRoll);
					}
					else
					{
						if (se != nullptr)  se->setRoll(0.0);
					}
					if (oo::ToStation(se) != nullptr)  oo::ToStation(se)->setPlanet(planet());
					if ((se != nullptr ? se->getMaxFlightSpeed() : 0.0f) > 0) se->isExplicitlyNotMainStation = YES; // we never want carriers to become main stations.
				}
				// stations used to have STATUS_ACTIVE, they're all STATUS_IN_FLIGHT now.
				if ((se != nullptr ? se->status() : OOEntityStatus{}) != STATUS_COCKPIT_DISPLAY)
				{
					if (se != nullptr)  se->setStatus(STATUS_IN_FLIGHT);
				}
			}
		}
		else
		{
			entity->setUniversalID(NO_TARGET);
			if (entity->getIsVisualEffect() || entity->isWaypoint())	// (an effect, else a waypoint: the same, bead oo-9ht.39.26)
			{
				if (oo::EntityIsBeacon(entity))
				{
					setNextBeacon(entity);	// the C++ effect or waypoint (bead oo-9ht.39.26)
				}
			}
		}
		
		// lighting considerations
		entity->isSunlit = YES;
		entity->shadingEntityID = NO_TARGET;
		
		// add it to the universe
		entities.emplace_back(entity);
		entity->wasAddedToUniverse();
		
		// maintain sorted list (and for the scanner relative position)
		HPVector entity_pos = entity->position;
		HPVector delta = HPvector_between(entity_pos, PLAYER->position);
		double z_distance = HPmagnitude2(delta);
		entity->zero_distance = z_distance;
		unsigned index = n_entities;
		sortedEntities[index] = entity;
		entity->zero_index = index;
		while ((index > 0)&&(z_distance < sortedEntities[index - 1]->zero_distance))	// bubble into place
		{
			sortedEntities[index] = sortedEntities[index - 1];
			sortedEntities[index]->zero_index = index;
			index--;
			sortedEntities[index] = entity;
			entity->zero_index = index;
		}
		
		// increase n_entities...
		n_entities++;
		
		// add entity to linked lists
		entity->addToLinkedLists();	// position and universe have been set - so we can do this
		if (entity->canCollide())	// filter only collidables disappearing
		{
			doLinkedListMaintenanceThisUpdate = YES;
		}
		
		if (entity->getIsWormhole())
		{
			activeWormholes.emplace_back(entity);	// the wormhole's Objective-C object (C++ since bead oo-9ht.112)
		}
		else if (oo::EntityIsPlanet(entity))
		{
			allPlanets.emplace_back(entity);	// the planet's Objective-C object (C++ since bead oo-9ht.129)
		}
		else if (oo::EntityIsShip(entity))
		{
			if (se != nullptr && se->getAI() != nullptr)  se->getAI()->setOwner(se);
			if (se != nullptr && se->getAI() != nullptr)  se->getAI()->setState("GLOBAL");
			if (entity->getIsStation())
			{
				AddIfAbsent(allStations, entity);
			}
		}
		
		return YES;
	}
	return NO;
}


bool Universe::removeEntity(Entity *entity)
{
	if (entity != nil && !oo::EntityIsPlayer(entity))
	{
		/*	Ensure entity won't actually be dealloced until the end of this
			update (or the next update if none is in progress), because
			there may be things pointing to it but not retaining it.
		*/
		AddIfAbsent(entitiesDeadThisUpdate, entity);
		if (entity->getIsStation())
		{
			std::erase(allStations, entity);
			if ((PLAYER != nullptr ? PLAYER->getTargetDockStation() : (::StationEntity *)nullptr) == entity)
			{
				if (PLAYER != nullptr)  PLAYER->setDockingClearanceStatus(DOCKING_CLEARANCE_STATUS_NONE);
			}
		}
		return doRemoveEntity(entity);
	}
	return NO;
}


void Universe::ensureEntityReallyRemoved(Entity *entity)
{
	// Its log line ("universe.unremovedEntity") is the facade's -dealloc's, which describes the object
	// before calling this (bead oo-9ht.39.26): the peer map no longer answers the dying object there.
	if (entity->getUniversalID() != NO_TARGET)
	{
		doRemoveEntity(entity);
	}
}


void Universe::removeAllEntitiesExceptPlayer()
{
	BOOL updating = no_update;
	no_update = YES;			// no drawing while we do this!
	
#ifndef NDEBUG
	Entity *p0 = entities[0].get();
	if (!(p0->isPlayer))
	{
		OO_LOG(cxx_kOOLogInconsistentState, "{}", "***** First entity is not the player in Universe.removeAllEntitiesExceptPlayer - exiting.");
		exit(EXIT_FAILURE);
	}
#endif
	
	// preserve wormholes
	std::vector<oo::EntityHold> savedWormholes = activeWormholes;

	while (entities.size() > 1)
	{
		Entity *ent = entities[1].get();
		if (ent->isStation)  // clear out queues
			if (oo::ToStation(ent) != nullptr)  oo::ToStation(ent)->clear();
		if (EXPECT(!ent->getIsVisualEffect()))
		{
			removeEntity(ent);
		}
		else
		{
			// this will ensure the effectRemoved script event will run
			oo::ToEffect(ent)->remove();
		}
	}
	
	activeWormholes = std::move(savedWormholes);	// will be cleared out by populateSpaceFromActiveWormholes
	
	// maintain sorted list
	n_entities = 1;
	
	cachedSun = nil;
	cachedPlanet = nil;
	cachedStation = nil;
	closeSystems.reset();
	
	resetBeacons();
	waypoints.clear();
	
	no_update = updating;	// restore drawing
}


void Universe::removeDemoShips()
{
	int i;
	int ent_count = n_entities;
	if (ent_count > 0)
	{
		Entity *ent;
		for (i = 0; i < ent_count; i++)
		{
			ent = sortedEntities[i];
			if (oo::EntityStatus(ent) == STATUS_COCKPIT_DISPLAY && !oo::EntityIsPlayer(ent))
			{
				removeEntity(ent);
			}
		}
	}
	demo_ship = nil;
}




// Slice 14 of docs/phases/3-slices/Universe.md (bead oo-7jhs5): making demo ships, safe vectors, hazards on route, wreckage, laser hits. The facade forwards
// each selector (until oo-ql9rn); sends to self were sends (ADR-0056 amendments oo-riqmz,
// oo-mvzmb).

::ShipEntity *Universe::makeDemoShipWithRole(const std::string &role, bool spinning)
{
	if ((PLAYER != nullptr ? PLAYER->dockedStation() : (::StationEntity *)nullptr) == nil)  return nil;
	
	removeDemoShips();	// get rid of any pre-existing models on display
	
	if (PLAYER != nullptr)  PLAYER->setShowDemoShips(YES);
	Quaternion q2 = { (GLfloat)M_SQRT1_2, (GLfloat)M_SQRT1_2, (GLfloat)0.0, (GLfloat)0.0 };
	
	::ShipEntity *ship = newShipWithRole(role);   // retain count = 1
	if (ship)
	{
		double cr = (ship != nullptr ? ship->collisionRadius() : 0.0f);
		if (ship != nullptr)  ship->setOrientation(q2);
		if (ship != nullptr)  ship->setPositionX(0.0f, 0.0f, 3.6f * cr);
		if (ship != nullptr)  ship->setScanClass(CLASS_NO_DRAW);
		if (ship != nullptr)  ship->switchAITo("nullAI.plist");
		if (ship != nullptr)  ship->setPendingEscortCount(0);
		
		if (UNIVERSE != nullptr)  UNIVERSE->addEntity(ship);		// STATUS_IN_FLIGHT, AI state GLOBAL

		if (spinning)
		{
			if (ship != nullptr)  ship->setDemoShip(1.0f);
		}
		else
		{
			if (ship != nullptr)  ship->setDemoShip(0.0f);
		}
		if (ship != nullptr)  ship->setStatus(STATUS_COCKPIT_DISPLAY);
		// stop problems on the ship library screen
		// demo ships shouldn't have this equipment
		if (ship != nullptr)  ship->removeEquipmentItem("EQ_SHIELD_BOOSTER");
		if (ship != nullptr)  ship->removeEquipmentItem("EQ_SHIELD_ENHANCER");
	}
	
	return (ship != nullptr ? oo::ToShip(oo::AutoreleaseEntity(ship)) : (::ShipEntity *)nil);
}


bool Universe::isVectorClearFromEntity(Entity *e1, double dist, HPVector p2)
{
	if (!e1)
		return NO;
	
	HPVector  f1;
	HPVector p1 = e1->position;
	HPVector v1 = p2;
	v1.x -= p1.x;   v1.y -= p1.y;   v1.z -= p1.z;   // vector from entity to p2
	
	double  nearest = sqrt(v1.x*v1.x + v1.y*v1.y + v1.z*v1.z) - dist;  // length of vector
	
	if (nearest < 0.0)
		return YES;			// within range already!
	
	int i;
	int ent_count = n_entities;
	std::vector<Entity *> my_entities(ent_count);	// each one's object retained (bead oo-9ht.39.26)
	for (i = 0; i < ent_count; i++)
		my_entities[i] = oo::RetainEntity(sortedEntities[i]); //	retained
	
	if (v1.x || v1.y || v1.z)
		f1 = HPvector_normal(v1);   // unit vector in direction of p2 from p1
	else
		f1 = make_HPvector(0, 0, 1);
	
	for (i = 0; i < ent_count ; i++)
	{
		Entity *e2 = my_entities[i];
		if ((e2 != e1)&&(e2->canCollide()))
		{
			HPVector epos = e2->position;
			epos.x -= p1.x;	epos.y -= p1.y;	epos.z -= p1.z; // epos now holds vector from p1 to this entities position
			
			double d_forward = HPdot_product(epos,f1);	// distance along f1 which is nearest to e2's position
			
			if ((d_forward > 0)&&(d_forward < nearest))
			{
				double cr = 1.10 * (e2->collision_radius + e1->collision_radius); //  10% safety margin
				HPVector p0 = e1->position;
				p0.x += d_forward * f1.x;	p0.y += d_forward * f1.y;	p0.z += d_forward * f1.z;
				// p0 holds nearest point on current course to center of incident object
				HPVector epos = e2->position;
				p0.x -= epos.x;	p0.y -= epos.y;	p0.z -= epos.z;
				// compare with center of incident object
				double  dist2 = p0.x * p0.x + p0.y * p0.y + p0.z * p0.z;
				if (dist2 < cr*cr)
				{
					for (i = 0; i < ent_count; i++)
						oo::ReleaseEntity(my_entities[i]); //	released
					return NO;
				}
			}
		}
	}
	for (i = 0; i < ent_count; i++)
		oo::ReleaseEntity(my_entities[i]); //	released
	return YES;
}


// The C++ entity, and its hazard's (bead oo-9ht.39.8.6): the list is still walked on the entities' objects.
Entity *Universe::hazardOnRouteFromEntity(Entity *e1, double dist, HPVector p2)
{
	if (!e1)
		return nil;
	
	HPVector f1;
	HPVector p1 = e1->position;
	HPVector v1 = p2;
	v1.x -= p1.x;   v1.y -= p1.y;   v1.z -= p1.z;   // vector from entity to p2
	
	double  nearest = HPmagnitude(v1) - dist;  // length of vector
	
	if (nearest < 0.0)
		return nil;			// within range already!
	
	Entity *result = nullptr;
	int i;
	int ent_count = n_entities;
	std::vector<Entity *> my_entities(ent_count);	// each one's object retained (bead oo-9ht.39.26)
	for (i = 0; i < ent_count; i++)
		my_entities[i] = oo::RetainEntity(sortedEntities[i]); //	retained
	
	if (v1.x || v1.y || v1.z)
		f1 = HPvector_normal(v1);   // unit vector in direction of p2 from p1
	else
		f1 = make_HPvector(0, 0, 1);
	
	for (i = 0; (i < ent_count) && (!result) ; i++)
	{
		Entity *e2 = my_entities[i];
		if ((e2 != e1)&&(e2->canCollide()))
		{
			HPVector epos = e2->position;
			epos.x -= p1.x;	epos.y -= p1.y;	epos.z -= p1.z; // epos now holds vector from p1 to this entities position
			
			double d_forward = HPdot_product(epos,f1);	// distance along f1 which is nearest to e2's position
			
			if ((d_forward > 0)&&(d_forward < nearest))
			{
				double cr = 1.10 * (e2->collision_radius + e1->collision_radius); //  10% safety margin
				HPVector p0 = e1->position;
				p0.x += d_forward * f1.x;	p0.y += d_forward * f1.y;	p0.z += d_forward * f1.z;
				// p0 holds nearest point on current course to center of incident object
				HPVector epos = e2->position;
				p0.x -= epos.x;	p0.y -= epos.y;	p0.z -= epos.z;
				// compare with center of incident object
				double  dist2 = HPmagnitude2(p0);
				if (dist2 < cr*cr)
					result = e2;
			}
		}
	}
	for (i = 0; i < ent_count; i++)
		oo::ReleaseEntity(my_entities[i]); //	released
	return result;
}


// The C++ entity (bead oo-9ht.39.8.6): the list is still walked on the entities' objects.
HPVector Universe::getSafeVectorFromEntity(Entity *e1, double dist, HPVector p2)
{
	// heuristic three
	
	if (!e1)
	{
		OO_LOG(cxx_kOOLogParameterError, "{}", "***** No entity set in Universe getSafeVectorFromEntity:toDistance:fromPoint:");
		return kZeroHPVector;
	}
	
	HPVector  f1;
	HPVector  result = p2;
	int i;
	int ent_count = n_entities;
	std::vector<Entity *> my_entities(ent_count);	// each one's object retained (bead oo-9ht.39.26)
	for (i = 0; i < ent_count; i++)
		my_entities[i] = oo::RetainEntity(sortedEntities[i]);	// retained
	HPVector p1 = e1->position;
	HPVector v1 = p2;
	v1.x -= p1.x;   v1.y -= p1.y;   v1.z -= p1.z;   // vector from entity to p2
	
	double  nearest = sqrt(v1.x*v1.x + v1.y*v1.y + v1.z*v1.z) - dist;  // length of vector
	
	if (v1.x || v1.y || v1.z)
		f1 = HPvector_normal(v1);   // unit vector in direction of p2 from p1
	else
		f1 = make_HPvector(0, 0, 1);
	
	for (i = 0; i < ent_count; i++)
	{
		Entity *e2 = my_entities[i];
		if ((e2 != e1)&&(e2->canCollide()))
		{
			HPVector epos = e2->position;
			epos.x -= p1.x;	epos.y -= p1.y;	epos.z -= p1.z;
			double d_forward = HPdot_product(epos,f1);
			if ((d_forward > 0)&&(d_forward < nearest))
			{
				double cr = 1.20 * (e2->collision_radius + e1->collision_radius); //  20% safety margin
				
				HPVector p0 = e1->position;
				p0.x += d_forward * f1.x;	p0.y += d_forward * f1.y;	p0.z += d_forward * f1.z;
				// p0 holds nearest point on current course to center of incident object
				
				HPVector epos = e2->position;
				p0.x -= epos.x;	p0.y -= epos.y;	p0.z -= epos.z;
				// compare with center of incident object
				
				double  dist2 = p0.x * p0.x + p0.y * p0.y + p0.z * p0.z;
				
				if (dist2 < cr*cr)
				{
					result = e2->position;			// center of incident object
					nearest = d_forward;
					
					if (dist2 == 0.0)
					{
						// ie. we're on a line through the object's center !
						// jitter the position somewhat!
						result.x += ((int)(Ranrot() % 1024) - 512)/512.0; //   -1.0 .. +1.0
						result.y += ((int)(Ranrot() % 1024) - 512)/512.0; //   -1.0 .. +1.0
						result.z += ((int)(Ranrot() % 1024) - 512)/512.0; //   -1.0 .. +1.0
					}
					
					HPVector  nearest_point = p1;
					nearest_point.x += d_forward * f1.x;	nearest_point.y += d_forward * f1.y;	nearest_point.z += d_forward * f1.z;
					// nearest point now holds nearest point on line to center of incident object
					
					HPVector outward = nearest_point;
					outward.x -= result.x;	outward.y -= result.y;	outward.z -= result.z;
					if (outward.x||outward.y||outward.z)
						outward = HPvector_normal(outward);
					else
						outward.y = 1.0;
					// outward holds unit vector through the nearest point on the line from the center of incident object
					
					HPVector backward = p1;
					backward.x -= result.x;	backward.y -= result.y;	backward.z -= result.z;
					if (backward.x||backward.y||backward.z)
						backward = HPvector_normal(backward);
					else
						backward.z = -1.0;
					// backward holds unit vector from center of the incident object to the center of the ship
					
					HPVector dd = result;
					dd.x -= p1.x; dd.y -= p1.y; dd.z -= p1.z;
					double current_distance = HPmagnitude(dd);
					
					// sanity check current_distance
					if (current_distance < cr * 1.25)	// 25% safety margin
						current_distance = cr * 1.25;
					if (current_distance > cr * 5.0)	// up to 2 diameters away 
						current_distance = cr * 5.0;
					
					// choose a point that's three parts backward and one part outward
					
					result.x += 0.25 * (outward.x * current_distance) + 0.75 * (backward.x * current_distance);		// push 'out' by this amount
					result.y += 0.25 * (outward.y * current_distance) + 0.75 * (backward.y * current_distance);
					result.z += 0.25 * (outward.z * current_distance) + 0.75 * (backward.z * current_distance);
					
				}
			}
		}
	}
	for (i = 0; i < ent_count; i++)
		oo::ReleaseEntity(my_entities[i]); //	released
	return result;
}


::ShipEntity *Universe::addWreckageFrom(::ShipEntity *ship, const std::string &wreckRole, HPVector rpos, GLfloat scale, GLfloat lifetime)
{
	::ShipEntity* wreck = (UNIVERSE != nullptr ? UNIVERSE->newShipWithRole(wreckRole) : (::ShipEntity *)nil);   // retain count = 1
	Quaternion q;
	if (wreck)
	{
		GLfloat expected_mass = 0.1f * (ship != nullptr ? ship->getMass() : 0.0f) * (0.75 + 0.5 * randf());
		GLfloat wreck_mass = (wreck != nullptr ? wreck->getMass() : 0.0f);
		GLfloat scale_factor = powf(expected_mass / wreck_mass, 0.33333333f) * scale;	// cube root of volume ratio
		if (wreck != nullptr)  wreck->rescaleBy(scale_factor, NO);

		if (wreck != nullptr)  wreck->setPosition(rpos);

		if (wreck != nullptr)  wreck->setVelocity((ship != nullptr ? ship->getVelocity() : Vector{}));

		quaternion_set_random(&q);
		if (wreck != nullptr)  wreck->setOrientation(q);
							
		if (wreck != nullptr)  wreck->setTemperature(1000.0);		// take 1000e heat damage per second
		if (wreck != nullptr)  wreck->setHeatInsulation(1.0e7);	// very large! so it won't cool down
		if (wreck != nullptr)  wreck->setEnergy(lifetime);
							
		if (wreck != nullptr)  wreck->setIsWreckage(YES);

		if (UNIVERSE != nullptr)  UNIVERSE->addEntity(wreck);	// STATUS_IN_FLIGHT, AI state GLOBAL
		if (wreck != nullptr)  wreck->performTumble();
		//	[wreck rescaleBy: 1.0/scale_factor];
		if (wreck != nullptr)  oo::ReleaseEntity(wreck);
	}
	return wreck;
}


void Universe::addLaserHitEffectsAt(HPVector pos, ::ShipEntity *target, float damage, ::OOColor *color)
{
	// low energy, start getting small surface explosions
	if ((target != nullptr ? target->showDamage() : false) && (target != nullptr ? target->getEnergy() : 0.0f) < (target != nullptr ? target->getMaxEnergy() : 0.0f)/2)
	{
		const char *key = (randf() < 0.5) ? "oolite-hull-spark" : "oolite-hull-spark-b";
		const oo::PList settings = (UNIVERSE != nullptr ? UNIVERSE->explosionSetting(key) : oo::PList());
		oo::Ref<::OOExplosionCloudEntity> burst = ::OOExplosionCloudEntity::explosionCloudFromEntity(target, settings);
		if (burst != nullptr)  burst->setPosition(pos);
		addEntity(oo::MadeEntity(burst));
		if ((target != nullptr ? target->getEnergy() : 0.0f) * randf() < damage)
		{
			::ShipEntity *wreck = addWreckageFrom(target, "oolite-wreckage-chunk", pos, 0.05, (125.0+(randf()*200.0)));
			if (wreck)
			{
				Vector direction = HPVectorToVector(HPvector_normal(HPvector_subtract(pos,(target != nullptr ? target->getPosition() : HPVector{}))));
				if (wreck != nullptr)  wreck->setVelocity(vector_add((wreck != nullptr ? wreck->getVelocity() : Vector{}),vector_multiply_scalar(direction,10+20*randf())));
			}
		}
	}
	else
	{
		addEntity(oo::MadeEntity(::OOFlashEffectEntity::laserFlashWithPosition(pos, (target != nullptr ? target->getVelocity() : Vector{}), color)));
	}
}


::ShipEntity *Universe::firstShipHitByLaserFromShip(::ShipEntity *srcEntity, OOWeaponFacing direction, Vector offset, GLfloat *range_ptr)
{
	if (srcEntity == nil) return nil;
	
	::ShipEntity		*hit_entity = nil;
	::ShipEntity		*hit_subentity = nil;
	HPVector			p0 = (srcEntity != nullptr ? srcEntity->getPosition() : HPVector{});
	Quaternion		q1 = (srcEntity != nullptr ? srcEntity->normalOrientation() : Quaternion{});
	::ShipEntity		*parent = oo::ToShip((srcEntity != nullptr ? srcEntity->parentEntity() : (Entity *)nullptr));
	
	if (parent)
	{
		// we're a subentity!
		BoundingBox bbox = (srcEntity != nullptr ? srcEntity->getBoundingBox() : BoundingBox{});
		HPVector midfrontplane = make_HPvector(0.5 * (bbox.max.x + bbox.min.x), 0.5 * (bbox.max.y + bbox.min.y), bbox.max.z);
		p0 = (srcEntity != nullptr ? srcEntity->absolutePositionForSubentityOffset(midfrontplane) : HPVector{});
		q1 = (parent != nullptr ? parent->getOrientation() : Quaternion{});
		if ((parent != nullptr ? parent->getIsPlayer() : false))  q1.w = -q1.w;
	}
	
	double			nearest = (srcEntity != nullptr ? srcEntity->getWeaponRange() : 0.0f);
	int				i;
	int				ent_count = n_entities;
	int				ship_count = 0;
	std::vector<::ShipEntity*> my_entities(ent_count);
	
	for (i = 0; i < ent_count; i++)
	{
		Entity *ent = sortedEntities[i];
		if (ent != srcEntity && ent != parent && oo::EntityIsShip(ent) && ent->canCollide())
		{
			my_entities[ship_count++] = (oo::ToShip(ent) != nullptr ? oo::ToShip(oo::RetainEntity(oo::ToShip(ent))) : (::ShipEntity *)nil);
		}
	}
	
	
	Vector u1, f1, r1;
	basis_vectors_from_quaternion(q1, &r1, &u1, &f1);
	p0 = HPvector_add(p0, vectorToHPVector(OOVectorMultiplyMatrix(offset, OOMatrixFromBasisVectors(r1, u1, f1))));
	
	switch (direction)
	{
		case WEAPON_FACING_FORWARD:
		case WEAPON_FACING_NONE:
			break;
			
		case WEAPON_FACING_AFT:
			quaternion_rotate_about_axis(&q1, u1, M_PI);
			break;
			
		case WEAPON_FACING_PORT:
			quaternion_rotate_about_axis(&q1, u1, M_PI/2.0);
			break;
			
		case WEAPON_FACING_STARBOARD:
			quaternion_rotate_about_axis(&q1, u1, -M_PI/2.0);
			break;
	}
	
	basis_vectors_from_quaternion(q1, &r1, NULL, &f1);
	HPVector p1 = HPvector_add(p0, vectorToHPVector(vector_multiply_scalar(f1, nearest)));	//endpoint
	
	for (i = 0; i < ship_count; i++)
	{
		::ShipEntity *e2 = my_entities[i];
		if (e2 == nullptr)  continue;	// (every one is a ship: the list holds the ships)
		
		// check outermost bounding sphere
		GLfloat cr = e2->collision_radius;
		Vector rpos = HPVectorToVector(HPvector_subtract(e2->position, p0));
		Vector v_off = make_vector(dot_product(rpos, r1), dot_product(rpos, u1), dot_product(rpos, f1));
		if (v_off.z > 0.0 && v_off.z < nearest + cr &&								// ahead AND within range
			v_off.x < cr && v_off.x > -cr && v_off.y < cr && v_off.y > -cr &&		// AND not off to one side or another
			v_off.x * v_off.x + v_off.y * v_off.y < cr * cr)						// AND not off to both sides
		{
			::ShipEntity *entHit = nil;
			GLfloat hit = (oo::ToShip(e2) != nullptr ? oo::ToShip(e2)->doesHitLine(p0, p1, &entHit) : 0.0f);	// octree detection
			
			if (hit > 0.0 && hit < nearest)
			{
				if ((entHit != nullptr ? entHit->getIsSubEntity() : false))
				{
					hit_subentity = entHit;
				}
				hit_entity = e2;
				nearest = hit;
				p1 = HPvector_add(p0, vectorToHPVector(vector_multiply_scalar(f1, nearest)));
			}
		}
	}
	
	if (hit_entity)
	{
		// I think the above code does not guarantee that the closest hit_subentity belongs to the closest hit_entity.
		if (hit_subentity && oo::LiveOwner(hit_subentity) == hit_entity)  { if (hit_entity != nullptr)  hit_entity->setSubEntityTakingDamage(hit_subentity); }
		
		if (range_ptr != NULL)
		{
			*range_ptr = nearest;
		}
	}
	
	for (i = 0; i < ship_count; i++)  { if (my_entities[i] != nullptr)  oo::ReleaseEntity(my_entities[i]); } //	released
	
	return hit_entity;
}



// Slice 15 of docs/phases/3-slices/Universe.md (bead oo-dg9d1): player targeting, entities in range, counting and finding ships by role and predicate, time, collisions, view direction. The facade forwards
// each selector (until oo-ql9rn); sends to self were sends (ADR-0056 amendments oo-riqmz,
// oo-mvzmb).

Entity *Universe::firstEntityTargetedByPlayer()
{
	::PlayerEntity	*player = PLAYER;
	Entity		*hit_entity = nullptr;
	OOScalar		nearest2 = SCANNER_MAX_RANGE - 100;	// 100m shorter than range at which target is lost
	nearest2 *= nearest2;
	int				i;
	int				ent_count = n_entities;
	int				ship_count = 0;
	std::vector<Entity *> my_entities(ent_count);	// each one's object retained (bead oo-9ht.39.26)
	
	for (i = 0; i < ent_count; i++)
	{
		if ((oo::EntityIsShip(sortedEntities[i]) && !oo::EntityIsPlayer(sortedEntities[i])) || sortedEntities[i]->getIsWormhole())
		{
			my_entities[ship_count++] = oo::RetainEntity(sortedEntities[i]);
		}
	}
	
	Quaternion q1 = (player != nullptr ? player->normalOrientation() : Quaternion{});
	Vector u1, f1, r1;
	basis_vectors_from_quaternion(q1, &r1, &u1, &f1);
	Vector offset = (player != nullptr ? player->weaponViewOffset() : Vector{});
	
	HPVector p1 = HPvector_add((player != nullptr ? player->getPosition() : HPVector{}), vectorToHPVector(OOVectorMultiplyMatrix(offset, OOMatrixFromBasisVectors(r1, u1, f1))));
	
	// Note: deliberately tied to view direction, not weapon facing. All custom views count as forward for targeting.
	switch (viewDirection)
	{
		case VIEW_AFT :
			quaternion_rotate_about_axis(&q1, u1, M_PI);
			break;
		case VIEW_PORT :
			quaternion_rotate_about_axis(&q1, u1, 0.5 * M_PI);
			break;
		case VIEW_STARBOARD :
			quaternion_rotate_about_axis(&q1, u1, -0.5 * M_PI);
			break;
		default:
			break;
	}
	basis_vectors_from_quaternion(q1, &r1, NULL, &f1);
	
	for (i = 0; i < ship_count; i++)
	{
		Entity *e2 = my_entities[i];
		if (e2->canCollide() && e2->getScanClass() != CLASS_NO_DRAW)
		{
			Vector rp = HPVectorToVector(HPvector_subtract(e2->getPosition(), p1));
			OOScalar dist2 = magnitude2(rp);
			if (dist2 < nearest2)
			{
				OOScalar df = dot_product(f1, rp);
				if (df > 0.0 && df * df < nearest2)
				{
					OOScalar du = dot_product(u1, rp);
					OOScalar dr = dot_product(r1, rp);
					OOScalar cr = e2->collisionRadius();
					if (du * du + dr * dr < cr * cr)
					{
						hit_entity = e2;
						nearest2 = dist2;
					}
				}
			}
		}
	}
	// check for MASC'M
	if (hit_entity != nullptr && oo::EntityIsShip(hit_entity))
	{
		::ShipEntity* ship = oo::ToShip(hit_entity);
		if ((ship != nullptr ? ship->isJammingScanning() : false) && !(player != nullptr ? player->hasMilitaryScannerFilter() : false))
		{
			hit_entity = nullptr;
		}
	}
	
	for (i = 0; i < ship_count; i++)
	{
		oo::ReleaseEntity(my_entities[i]);
	}
	
	return hit_entity;
}


Entity *Universe::firstEntityTargetedByPlayerPrecisely()
{
	OOWeaponFacing targetFacing;
	Vector laserPortOffset = kZeroVector;
	::PlayerEntity *player = PLAYER;
	// The first weapon offset, or the zero vector for none (as -oo_vectorAtIndex:0 of the old array).
	const auto firstWeaponOffset = [](const std::vector<Vector> &offsets) { return offsets.empty() ? kZeroVector : offsets.front(); };

	switch (viewDirection)
	{
		case VIEW_FORWARD:
			targetFacing = WEAPON_FACING_FORWARD;
			laserPortOffset = firstWeaponOffset((player != nullptr ? player->getForwardWeaponOffset() : std::vector<Vector>()));
			break;
			
		case VIEW_AFT:
			targetFacing = WEAPON_FACING_AFT;
			laserPortOffset = firstWeaponOffset((player != nullptr ? player->getAftWeaponOffset() : std::vector<Vector>()));
			break;
			
		case VIEW_PORT:
			targetFacing = WEAPON_FACING_PORT;
			laserPortOffset = firstWeaponOffset((player != nullptr ? player->getPortWeaponOffset() : std::vector<Vector>()));
			break;
			
		case VIEW_STARBOARD:
			targetFacing = WEAPON_FACING_STARBOARD;
			laserPortOffset = firstWeaponOffset((player != nullptr ? player->getStarboardWeaponOffset() : std::vector<Vector>()));
			break;
			
		default:
			// Match behaviour of -firstEntityTargetedByPlayer.
			targetFacing = WEAPON_FACING_FORWARD;
			laserPortOffset = firstWeaponOffset((player != nullptr ? player->getForwardWeaponOffset() : std::vector<Vector>()));
	}
	
	return firstShipHitByLaserFromShip(PLAYER, targetFacing, laserPortOffset, NULL);
}


std::vector<oo::EntityHold> Universe::entitiesWithinRange(double range, Entity *entity)
{
	if (entity == nil)  return {};

	return findShipsMatchingPredicate(YESPredicate, NULL, range, entity);
}


// The role predicates read a std::string, held here for the call.
// The reference entity is the C++ entity (bead oo-9ht.39.8.23); the count reads the C++ entities (bead oo-9ht.39.26).
unsigned Universe::countShipsWithRole(const std::string &role, double range, Entity *entity)
{
	std::string roleParameter = role;
	return countShipsMatchingPredicate(HasRolePredicate, &roleParameter, range, entity);
}


unsigned Universe::countShipsWithRole(const std::string &role)
{
	return countShipsWithRole(role, -1, nullptr);
}


unsigned Universe::countShipsWithPrimaryRole(const std::string &role, double range, Entity *entity)
{
	std::string roleParameter = role;
	return countShipsMatchingPredicate(HasPrimaryRolePredicate, &roleParameter, range, entity);
}


// HasScanClassPredicate reads the scan class as an OOScanClass.
unsigned Universe::countShipsWithScanClass(OOScanClass scanClass, double range, Entity *entity)
{
	return countShipsMatchingPredicate(HasScanClassPredicate, &scanClass, range, entity);
}


unsigned Universe::countShipsWithPrimaryRole(const std::string &role)
{
	return countShipsWithPrimaryRole(role, -1, nullptr);
}


unsigned Universe::countEntitiesMatchingPredicate(EntityFilterPredicate predicate, void *parameter, double range, Entity *e1)
{
	unsigned		i, found = 0;
	HPVector			p1;
	double			distance, cr;
	
	if (predicate == NULL)  predicate = YESPredicate;
	
	if (e1 != nil)  p1 = e1->position;
	else  p1 = kZeroHPVector;
	
	for (i = 0; i < n_entities; i++)
	{
		Entity *e2 = sortedEntities[i];
		if (e2 != e1 && predicate(e2, parameter))
		{
			if (range < 0)  distance = -1;	// Negative range means infinity
			else
			{
				cr = range + e2->collision_radius;
				distance = HPdistance2(e2->position, p1) - cr * cr;
			}
			if (distance < 0)
			{
				found++;
			}
		}
	}
	
	return found;
}


unsigned Universe::countShipsMatchingPredicate(EntityFilterPredicate predicate, void *parameter, double range, Entity *entity)
{
	if (predicate != NULL)
	{
		BinaryOperationPredicateParameter param =
		{
			IsShipPredicate, NULL,
			predicate, parameter
		};
		
		return countEntitiesMatchingPredicate(ANDPredicate, &param, range, entity);
	}
	else
	{
		return countEntitiesMatchingPredicate(IsShipPredicate, NULL, range, entity);
	}
}


// NOTE: OOJSSystem relies on this returning entities in distance-from-player order.
// This can be easily changed by removing the [reference isPlayer] conditions in FindJSVisibleEntities().
// The reference entity is the C++ entity (bead oo-9ht.39.8.23): its position is what -position answered, and
// the entity the list holds for it is skipped, as its object was.
std::vector<oo::EntityHold> Universe::findEntitiesMatchingPredicate(EntityFilterPredicate predicate, void *parameter, double range, Entity *e1)
{
	OOJS_PROFILE_ENTER

	unsigned		i;
	HPVector			p1;
	std::vector<oo::EntityHold>	result;

	OOJSPauseTimeLimiter();

	if (predicate == NULL)  predicate = YESPredicate;

	result.reserve(n_entities);
	
	if (e1 != nullptr)  p1 = e1->getPosition();
	else  p1 = kZeroHPVector;
	
	for (i = 0; i < n_entities; i++)
	{
		Entity *e2 = sortedEntities[i];
		
		if (e1 != e2 &&
			EntityInRange(p1, e2, range) &&
			predicate(e2, parameter))
		{
			result.emplace_back(e2);
		}
	}

	OOJSResumeTimeLimiter();

	return result;

	OOJS_PROFILE_EXIT_VAL(std::vector<oo::EntityHold>())
}


Entity *Universe::findOneEntityMatchingPredicate(EntityFilterPredicate predicate, void *parameter)
{
	unsigned		i;
	Entity		*candidate = nullptr;
	
	OOJSPauseTimeLimiter();
	
	if (predicate == NULL)  predicate = YESPredicate;
	
	for (i = 0; i < n_entities; i++)
	{
		candidate = sortedEntities[i];
		if (predicate(candidate, parameter))  return candidate;
	}
	
	OOJSResumeTimeLimiter();
	
	return nil;
}


std::vector<oo::EntityHold> Universe::findShipsMatchingPredicate(EntityFilterPredicate predicate, void *parameter, double range, Entity *entity)
{
	if (predicate != NULL)
	{
		BinaryOperationPredicateParameter param =
		{
			IsShipPredicate, NULL,
			predicate, parameter
		};

		return findEntitiesMatchingPredicate(ANDPredicate, &param, range, entity);
	}
	else
	{
		return findEntitiesMatchingPredicate(IsShipPredicate, NULL, range, entity);
	}
}


std::vector<oo::EntityHold> Universe::findVisualEffectsMatchingPredicate(EntityFilterPredicate predicate, void *parameter, double range, Entity *entity)
{
	if (predicate != NULL)
	{
		BinaryOperationPredicateParameter param =
		{
			IsVisualEffectPredicate, NULL,
			predicate, parameter
		};

		return findEntitiesMatchingPredicate(ANDPredicate, &param, range, entity);
	}
	else
	{
		return findEntitiesMatchingPredicate(IsVisualEffectPredicate, NULL, range, entity);
	}
}


Entity *Universe::nearestEntityMatchingPredicate(EntityFilterPredicate predicate, void *parameter, Entity *entity)
{
	unsigned		i;
	HPVector			p1;
	float			rangeSq = INFINITY;
	Entity		*result = nullptr;
	
	if (predicate == NULL)  predicate = YESPredicate;
	
	if (entity != nullptr)  p1 = entity->getPosition();
	else  p1 = kZeroHPVector;
	
	for (i = 0; i < n_entities; i++)
	{
		Entity *e2 = sortedEntities[i];
		float distanceToReferenceEntitySquared = (float)HPdistance2(p1, e2->getPosition());
		
		if (entity != e2 &&
			distanceToReferenceEntitySquared < rangeSq &&
			predicate(e2, parameter))
		{
			result = e2;
			rangeSq = distanceToReferenceEntitySquared;
		}
	}
	
	return oo::AutoreleaseEntity(oo::RetainEntity(result));	// [[result retain] autorelease]
}


Entity *Universe::nearestShipMatchingPredicate(EntityFilterPredicate predicate, void *parameter, Entity *entity)
{
	if (predicate != NULL)
	{
		BinaryOperationPredicateParameter param =
		{
			IsShipPredicate, NULL,
			predicate, parameter
		};
		
		return nearestEntityMatchingPredicate(ANDPredicate, &param, entity);
	}
	else
	{
		return nearestEntityMatchingPredicate(IsShipPredicate, NULL, entity);
	}
}


OOTimeAbsolute Universe::getTime()
{
	return universal_time;
}


OOTimeDelta Universe::getTimeDelta()
{
	return time_delta;
}


void Universe::findCollisionsAndShadows()
{
	unsigned i;
	
	// The region is made after the initial universe is set up; until then there is nothing to do,
	// as the messages to the nil region did nothing.
	if (universeRegion == nullptr)  return;

	universeRegion->clearEntityList();
	
	for (i = 0; i < n_entities; i++)
	{
		universeRegion->checkEntity(sortedEntities[i]);	// sorts out which region it's in
	}
	
	if (!(gameController() != nullptr ? gameController()->isGamePaused() : false))
	{
		universeRegion->findCollisions();
	}
	
	// do check for entities that can't see the sun!
	universeRegion->findShadowedEntities();
}


std::string Universe::collisionDescription()
{
	if (universeRegion != nullptr)  return universeRegion->collisionDescription();
	else  return "-";
}


void Universe::dumpCollisions()
{
	dumpCollisionInfo = YES;
}


OOViewID Universe::getViewDirection()
{
	return viewDirection;
}



// Slice 16 of docs/phases/3-slices/Universe.md (bead oo-focfo): setting the view direction, GUI view mode, custom sounds, screen textures, messages and comms, delayed messages, repopulating. The facade forwards
// each selector (until oo-ql9rn); sends to self were sends (ADR-0056 amendments oo-riqmz,
// oo-mvzmb).

void Universe::setViewDirection(OOViewID vd)
{
	std::optional<std::string>	ms;
	BOOL			guiSelected = NO;
	
	if ((viewDirection == vd) && (vd != VIEW_CUSTOM) && (!displayGUI))
		return;
	
	switch (vd)
	{
		case VIEW_FORWARD:
			ms = cxx_OOLookUpDescriptionPRIV("forward-view-string");
			break;
			
		case VIEW_AFT:
			ms = cxx_OOLookUpDescriptionPRIV("aft-view-string");
			break;
			
		case VIEW_PORT:
			ms = cxx_OOLookUpDescriptionPRIV("port-view-string");
			break;
			
		case VIEW_STARBOARD:
			ms = cxx_OOLookUpDescriptionPRIV("starboard-view-string");
			break;
			
		case VIEW_CUSTOM:
			ms = (PLAYER != nullptr ? PLAYER->getCustomViewDescription() : std::optional<std::string>());
			break;
			
		case VIEW_GUI_DISPLAY:
			setDisplayText(YES);
			setMainLightPosition((Vector){ DEMO_LIGHT_POSITION });
			guiSelected = YES;
			break;
			
		default:
			guiSelected = YES;
			break;
	}
	
	if (guiSelected)
	{
		if (gameController() != nullptr)  gameController()->setMouseInteractionModeForUIWithMouseInteraction(NO);
	}
	else
	{
		displayGUI = NO;   // switch off any text displays
		if (gameController() != nullptr)  gameController()->setMouseInteractionModeForFlight();
	}
	
	if (viewDirection != vd || viewDirection == VIEW_CUSTOM)
	{
		#if (ALLOW_CUSTOM_VIEWS_WHILE_PAUSED)
		BOOL gamePaused = (gameController() != nullptr ? gameController()->isGamePaused() : false);
		#else
		BOOL gamePaused = NO;
		#endif
		// view notifications for when the player switches to/from gui!
		//if (EXPECT(viewDirection == VIEW_GUI_DISPLAY || vd == VIEW_GUI_DISPLAY )) [PLAYER noteViewDidChangeFrom:viewDirection toView:vd];
		viewDirection = vd;
		if (ms.has_value() && !gamePaused)
		{
			addMessage(ms, 3);
		}
		else if (gamePaused)
		{
			if (message_gui != nullptr)  message_gui->clear();
		}
	}
}


void Universe::enterGUIViewModeWithMouseInteraction(bool mouseInteraction)
{
	OOViewID vd = viewDirection;
	setViewDirection(VIEW_GUI_DISPLAY);
	if (viewDirection != vd) {
		::PlayerEntity	*player = PLAYER;
		ooscript::Context context = OOJSAcquireContext();
		ShipScriptEvent(context, player, "viewDirectionChanged", OOJSValueFromViewID(context, viewDirection), OOJSValueFromViewID(context, vd));
		OOJSRelinquishContext(context);
	}
	if (gameController() != nullptr)  gameController()->setMouseInteractionModeForUIWithMouseInteraction(mouseInteraction);
}


// Resolved names are cached by key; a nil key (an array entry that is neither a string nor a
// number) is cached as "", as the cache took a nil key.
std::optional<std::string> Universe::soundNameForCustomSoundKey(const std::string &soundKey)
{
	std::optional<std::string>	key = soundKey;
	std::optional<std::string>	result;
	std::set<std::string>		seen;
	const oo::PList				*object = customSounds.find(*key);

	if (object != nullptr && object->isArray() && object->count() > 0)
	{
		key = OptionalStringAt(*object, Ranrot() % object->count());
	}
	else
	{
		object = nullptr;
	}

	// the cache holds the resolved names as strings (set below)
	const oo::PList cachedName = OOCacheManager::sharedCache()->pListForKey(key.value_or(std::string()), "resolved custom sounds");
	if (const std::string *name = cachedName.getIf<std::string>())  result = *name;
	if (!result.has_value())
	{
		// Resolve sound, allowing indirection within customsounds.plist
		result = key;
		if (object == nullptr || (result.has_value() && oo::str::hasPrefix(*result, "[") && oo::str::hasSuffix(*result, "]")))
		{
			for (;;)
			{
				seen.insert(*result);
				object = customSounds.find(*result);
				if (object != nullptr && object->isArray() && object->count() > 0)
				{
					result = OptionalStringAt(*object, Ranrot() % object->count());
					if (key.has_value() && oo::str::hasPrefix(*key, "[") && oo::str::hasSuffix(*key, "]")) key=result;
				}
				else
				{
					if (object != nullptr && object->isString())
						result = *object->getIf<std::string>();
					else
						result = std::nullopt;
				}
				if (!result.has_value() || !oo::str::hasPrefix(*result, "[") || !oo::str::hasSuffix(*result, "]"))  break;
				if (seen.contains(*result))
				{
					OO_LOG_ERR("sound.customSounds.recursion", "recursion in customsounds.plist for '{}' (at '{}'), no sound will be played.", key.value_or("(null)"), *result);
					result = std::nullopt;
					break;
				}
			}
		}

		if (!result.has_value())  result = std::string("__oolite-no-sound");
		OOCacheManager::sharedCache()->setPList(oo::PList(*result), key.value_or(std::string()), "resolved custom sounds");
	}

	if (*result == "__oolite-no-sound")
	{
		OO_LOG("sound.customSounds", "Could not resolve sound name in customsounds.plist for '{}', no sound will be played.", key.value_or("(null)"));
		result = std::nullopt;
	}
	return result;
}


oo::PList Universe::screenTextureDescriptorForKey(const std::string &key)
{
	const oo::PList *entry = screenBackgrounds.find(key);
	oo::PList value = (entry != nullptr) ? *entry : oo::PList();
	while (value.isArray())
	{
		const oo::PList *chosen = value.at(Ranrot() % value.count());
		oo::PList next = (chosen != nullptr) ? *chosen : oo::PList();
		value = std::move(next);
	}

	if (value.isString())  value = oo::PList(oo::PList::Dict{ { "name", value } });
	else if (!value.isDict())  value = oo::PList();

	// Start loading the texture, and return nil if it doesn't exist.
	::GuiDisplayGen *theGui = getGui();
	if (theGui == nullptr || !theGui->preloadGUITexture(value))  value = oo::PList();	// a nil GUI answered NO

	return value;
}


// Unloaded backgrounds (null) stay unloaded, as messaging nil changed nothing.
void Universe::setScreenTextureDescriptorForKey(const std::string &key, const oo::PList &desc)
{
	oo::PList::Dict *backgrounds = screenBackgrounds.getIf<oo::PList::Dict>();
	if (backgrounds == nullptr)  return;
	if (desc.isNull())
	{
		backgrounds->erase(key);
	}
	else
	{
		(*backgrounds)[key] = desc;
	}
}


void Universe::clearPreviousMessage()
{
	currentMessage.reset();
}


void Universe::setMessageGuiBackgroundColor(::OOColor *some_color)
{
	if (message_gui == nullptr)  return;	// a message to nil did nothing
	message_gui->setBackgroundColor(some_color);
}


void Universe::displayMessage(const std::optional<std::string> &text, OOTimeDelta count)
{
	if (!SameMessage(currentMessage, text) || universal_time >= messageRepeatTime)
	{
		currentMessage = text;
		messageRepeatTime=universal_time + 6.0;
		showGUIMessage(text, YES, (message_gui != nullptr ? message_gui->getTextColor() : nullptr), count);
	}
}


void Universe::displayCountdownMessage(const std::optional<std::string> &text, OOTimeDelta count)
{
	if (!SameMessage(currentMessage, text) && universal_time >= countdown_messageRepeatTime)
	{
		currentMessage = text;
		countdown_messageRepeatTime=universal_time + count;
		showGUIMessage(text, NO, (message_gui != nullptr ? message_gui->getTextColor() : nullptr), count);
	}
}


// The deferred call's argument carries the dictionary -addDelayedMessage: reads (a missing text
// leaves the message out: the delayed call then shows nothing; setting a nil text raised).
void Universe::addDelayedMessage(const std::optional<std::string> &text, OOTimeDelta count, double delay)
{
	oo::PList::Dict msgDict;
	if (text.has_value())  msgDict["message"] = oo::PList(*text);
	msgDict["duration"] = oo::PList(count);
	// The call carries the dictionary and hands it to UNIVERSE when it runs (the target was the
	// facade, bead oo-ql9rn; the Objective-C holder OOUniverseDelayedMessage until bead oo-pvhrh).
	OOScheduleDeferredCall([message = oo::PList(std::move(msgDict))]() { if (UNIVERSE != nullptr)  UNIVERSE->addDelayedMessage(message); }, delay);
}


void Universe::addDelayedMessage(const oo::PList &message)
{
	std::optional<std::string>	msg;
	OOTimeDelta		msg_duration;

	msg = OptionalStringIn(message, "message");
	if (!msg.has_value())  return;
	msg_duration = message.get<oo::NonNegative<double>>("duration", 3.0);

	addMessage(msg, msg_duration);
}


void Universe::addMessage(const std::optional<std::string> &text, OOTimeDelta count)
{
	addMessage(text, count, NO);
}


void Universe::speakWithSubstitutions(const std::optional<std::string> &text)
{
#if OOLITE_SPEECH_SYNTH
	//speech synthesis

	::PlayerEntity* player = PLAYER;
	if ((player != nullptr ? player->getIsSpeechOn() : OOSpeechSettings{}) > OOSPEECHSETTINGS_OFF)
	{
		std::optional<std::string>	systemSaid;
		std::optional<std::string>	h_systemSaid;

		const std::optional<std::string>	systemName = getSystemName(systemID);

		systemSaid = systemName;

		const std::optional<std::string>	h_systemName = getSystemName((player != nullptr ? player->targetSystemID() : 0));
		h_systemSaid = h_systemName;

		std::optional<std::string>	spokenText = text;
		if (!speechArray.isNull())
		{
			const oo::PList::Array *pairs = speechArray.getIf<oo::PList::Array>();
			if (pairs != nullptr)  for (const oo::PList &thePair : *pairs)
			{
				const std::optional<std::string> original_phrase = OptionalStringAt(thePair, 0);

				NSUInteger replacementIndex;
#if OOLITE_MAC_OS_X
				replacementIndex = 1;
#elif OOLITE_ESPEAK
				replacementIndex = thePair.count() > 2 ? 2 : 1;
#endif

				const std::optional<std::string> replacement_phrase = OptionalStringAt(thePair, replacementIndex);
				// An empty or missing phrase replaced nothing (a missing replacement or a nil text stayed nil).
				if (replacement_phrase != "_" && spokenText.has_value() && original_phrase.has_value() && !original_phrase->empty() && replacement_phrase.has_value())
				{
					spokenText = oo::str::replaceOccurrences(*spokenText, *original_phrase, *replacement_phrase);
				}
			}
			if (spokenText.has_value() && systemName.has_value() && !systemName->empty())  spokenText = oo::str::replaceOccurrences(*spokenText, *systemName, systemSaid.value_or(std::string()));
			if (spokenText.has_value() && h_systemName.has_value() && !h_systemName->empty())  spokenText = oo::str::replaceOccurrences(*spokenText, *h_systemName, h_systemSaid.value_or(std::string()));
		}
		stopSpeaking();
		if (spokenText.has_value())  startSpeakingString(*spokenText);	// a nil text said nothing
	}
#endif	// OOLITE_SPEECH_SYNTH
}


void Universe::addMessage(const std::optional<std::string> &text, OOTimeDelta count, bool forceDisplay)
{
	if (!SameMessage(currentMessage, text) || forceDisplay || universal_time >= messageRepeatTime)
	{
		if ((PLAYER != nullptr ? PLAYER->getIsSpeechOn() : OOSpeechSettings{}) == OOSPEECHSETTINGS_ALL)
		{
			speakWithSubstitutions(text);
		}

		showGUIMessage(text, YES, (message_gui != nullptr ? message_gui->getTextColor() : nullptr), count);

		if (PLAYER != nullptr)  PLAYER->doScriptEvent(OOJSID("consoleMessageReceived"), { StringOrNull(text) });

		currentMessage = text;
		messageRepeatTime=universal_time + 6.0;
	}
}


void Universe::addCommsMessage(const std::optional<std::string> &text, OOTimeDelta count)
{
	addCommsMessage(text, count, _autoCommLog, NO);
}


void Universe::addCommsMessage(const std::optional<std::string> &text, OOTimeDelta count, bool showComms, bool logOnly)
{
	if ((PLAYER != nullptr ? PLAYER->getShowDemoShips() : false)) return;

	const std::optional<std::string> expandedMessage = text.has_value() ? cxx_OOExpand(*text) : std::nullopt;

	if (!SameMessage(currentMessage, expandedMessage) || universal_time >= messageRepeatTime)
	{
		::PlayerEntity* player = PLAYER;

		if (!logOnly)
		{
			if ((player != nullptr ? player->getIsSpeechOn() : OOSpeechSettings{}) >= OOSPEECHSETTINGS_COMMS)
			{
				// EMMSTRAN: should say "Incoming message from ..." when prefixed with sender name.
				const std::string format = ExpandKey("speech-synthesis-incoming-message-@");
				speakWithSubstitutions(oo::str::formatRuntime(format, { expandedMessage.has_value() ? oo::str::FormatArg(*expandedMessage) : oo::str::FormatArg::null() }));
			}

			showGUIMessage(expandedMessage, YES, (message_gui != nullptr ? message_gui->getTextCommsColor() : nullptr), count);

			currentMessage = expandedMessage;
			messageRepeatTime=universal_time + 6.0;
		}

		// the printed lines go to the player's comm log
		std::vector<std::string> printedLines;
		if (comm_log_gui != nullptr)  comm_log_gui->printLongText(expandedMessage, GUI_ALIGN_LEFT, nil, 0.0, std::nullopt, &printedLines);
		std::vector<std::string> *commLog = (player != nullptr ? player->getCommLog() : (std::vector<std::string> *)nullptr);
		if (commLog != nullptr)  commLog->insert(commLog->end(), printedLines.begin(), printedLines.end());

		if (showComms)  showCommsLog(6.0);
	}
}


void Universe::showCommsLog(OOTimeDelta how_long)
{
	if (comm_log_gui == nullptr)  return;	// messages to nil did nothing
	comm_log_gui->setAlpha(1.0);
	if (!permanentCommLog()) comm_log_gui->fadeOutFromTime(getTime(), how_long);
}


void Universe::showGUIMessage(const std::optional<std::string> &text, bool scroll, ::OOColor *selectedColor, OOTimeDelta how_long)
{
	if (message_gui == nullptr)  return;	// messages to nil did nothing
	if (scroll)
	{
		message_gui->printLongText(text, GUI_ALIGN_CENTER, selectedColor, how_long, std::nullopt, nullptr);
	}
	else
	{
		message_gui->printLineNoScroll(text, GUI_ALIGN_CENTER, selectedColor, how_long, std::nullopt, nullptr);
	}
	message_gui->setAlpha(1.0f);
}


void Universe::repopulateSystem()
{
	if (EXPECT_NOT((PLAYER != nullptr ? PLAYER->status() : OOEntityStatus{}) == STATUS_START_GAME))
	{
		return; // no need to be adding ships as this is not a "real" game
	}
	ooscript::Context context = OOJSAcquireContext();
	if (PLAYER != nullptr)  PLAYER->doWorldScriptEvent((system_repopulator.has_value() ? cxx_OOJSIDFromString(*system_repopulator) : ooscript::voidId()), context, NULL, 0, kOOJSLongTimeLimit);
	OOJSRelinquishContext(context);
	next_repopulation = SYSTEM_REPOPULATION_INTERVAL;
}



// Slice 17 of docs/phases/3-slices/Universe.md (bead oo-gr7a2): update:, time acceleration, ECM visual effects. The facade forwards
// each selector (until oo-ql9rn); sends to self were sends (ADR-0056 amendments oo-riqmz,
// oo-mvzmb).

void Universe::update(OOTimeDelta inDeltaT)
{
	volatile OOTimeDelta delta_t = inDeltaT * getTimeAccelerationFactor();
	NSUInteger sessionID = _sessionID;
	OO_LOG("universe.profile.update", "{}", "Begin update");
	if (EXPECT(!no_update))
	{
		next_repopulation -= delta_t;
		if (next_repopulation < 0)
		{
			repopulateSystem();
		}

		unsigned	i, ent_count = n_entities;
		std::vector<Entity *> my_entities(ent_count);	// each one's object retained (bead oo-9ht.39.26)
		
		verifyEntitySessionIDs();
		
		// use a retained copy so this can't be changed under us.
		for (i = 0; i < ent_count; i++)
		{
			my_entities[i] = oo::RetainEntity(sortedEntities[i]);	// explicitly retain each one
		}
		
		const char * volatile update_stage = "initialisation";
#ifndef NDEBUG
		Entity * volatile update_stage_param = nullptr;	// the C++ entity (bead oo-9ht.39.26)
#endif
		
		try
		{
			::PlayerEntity *player = PLAYER;
			
			skyClearColor[0] = 0.0;
			skyClearColor[1] = 0.0;
			skyClearColor[2] = 0.0;
			skyClearColor[3] = 0.0;
			
			time_delta = delta_t;
			universal_time += delta_t;
			
			if (EXPECT_NOT((player != nullptr ? player->getShowDemoShips() : false) && (player != nullptr ? player->guiScreen() : OOGUIScreenID{}) == GUI_SCREEN_SHIPLIBRARY))
			{
				update_stage = "demo management";
				
				if (universal_time >= demo_stage_time)
				{
					if (ent_count > 1)
					{
						Vector		vel;
						Quaternion	q2 = kIdentityQuaternion;
						
						quaternion_rotate_about_y(&q2,M_PI);
						
						switch (demo_stage)
						{
							case DEMO_FLY_IN:
								if (demo_ship != nullptr)  demo_ship->setPosition((demo_ship != nullptr ? demo_ship->destination() : HPVector{}));	// ideal position
								demo_stage = DEMO_SHOW_THING;
								demo_stage_time = universal_time + 300.0;
								break;
							case DEMO_SHOW_THING:
								vel = make_vector(0, 0, DEMO2_VANISHING_DISTANCE * demo_ship->collision_radius * 6.0);
								if (demo_ship != nullptr)  demo_ship->setVelocity(vel);
								demo_stage = DEMO_FLY_OUT;
								demo_stage_time = universal_time + 0.25;
								break;
							case DEMO_FLY_OUT:
								// change the demo_ship here
								removeEntity(demo_ship);
								demo_ship = nil;
								
								demo_ship_subindex = (demo_ship_subindex + 1) % DemoClassCount(demo_ships, demo_ship_index);
								demo_ship = newShipWithName(OptionalStringIn(demoShipData(), kOODemoShipKey).value_or(std::string()), NO);	// a missing key asked for "", as nil did
								
								if (demo_ship != nil)
								{
									if (demo_ship != nullptr)  demo_ship->removeEquipmentItem("EQ_SHIELD_BOOSTER");
									if (demo_ship != nullptr)  demo_ship->removeEquipmentItem("EQ_SHIELD_ENHANCER");

									if (demo_ship != nullptr)  demo_ship->switchAITo("nullAI.plist");
									if (demo_ship != nullptr)  demo_ship->setOrientation(q2);
									if (demo_ship != nullptr)  demo_ship->setScanClass(CLASS_NO_DRAW);
									if (demo_ship != nullptr)  demo_ship->setStatus(STATUS_COCKPIT_DISPLAY); // prevents it getting escorts on addition
									if (demo_ship != nullptr)  demo_ship->setDemoShip(1.0f);
									if (demo_ship != nullptr)  demo_ship->setDemoStartTime(universal_time);
									if (addEntity(demo_ship))
									{
										if (demo_ship != nullptr)  oo::ReleaseEntity(demo_ship);		// We now own a reference through the entity list.
										if (demo_ship != nullptr)  demo_ship->setStatus(STATUS_COCKPIT_DISPLAY);
										demo_start_z=DEMO2_VANISHING_DISTANCE * demo_ship->collision_radius;
										if (demo_ship != nullptr)  demo_ship->setPositionX(0.0f, 0.0f, demo_start_z);
										if (demo_ship != nullptr)  demo_ship->setDestination(make_HPvector(0.0f, 0.0f, demo_start_z * 0.01f));	// ideal position
										if (demo_ship != nullptr)  demo_ship->setVelocity(kZeroVector);
										if (demo_ship != nullptr)  demo_ship->setScanClass(CLASS_NO_DRAW);
//										[gui setText:shipName != nil ? shipName : [demo_ship displayName] forRow:19 align:GUI_ALIGN_CENTER];
										
										setLibraryTextForDemoShip();

										demo_stage = DEMO_FLY_IN;
										demo_start_time=universal_time;
										demo_stage_time = demo_start_time + DEMO2_FLY_IN_STAGE_TIME;
									}
									else
									{
										demo_ship = nil;
									}
								}
								break;
						}
					}
				}
				else if (demo_stage == DEMO_FLY_IN)
				{
					GLfloat delta = (universal_time - demo_start_time) / DEMO2_FLY_IN_STAGE_TIME;
					if (demo_ship != nullptr)  demo_ship->setPositionX(0.0f, (demo_ship != nullptr ? demo_ship->destination() : HPVector{}).y * delta, demo_start_z + ((demo_ship != nullptr ? demo_ship->destination() : HPVector{}).z - demo_start_z) * delta);
				}
			}
			
			update_stage = "update:entity";
			std::vector<oo::EntityHold> zombies;	// each once, in the order found
			OO_LOG("universe.profile.update", "{}", const_cast<const char *>(update_stage));
			for (i = 0; i < ent_count; i++)
			{
				Entity *thing = my_entities[i];
#ifndef NDEBUG
				update_stage_param = thing;
				update_stage = "update:entity [%@]";
#endif
				// Game Over code depends on regular delta_t updates to the dead player entity. Ignore the player entity, even when dead.
				if (EXPECT_NOT(oo::EntityStatus(thing) == STATUS_DEAD && std::find(entitiesDeadThisUpdate.begin(), entitiesDeadThisUpdate.end(), thing) == entitiesDeadThisUpdate.end() && !oo::EntityIsPlayer(thing)))
				{
					AddIfAbsent(zombies, thing);
					continue;
				}
				
				thing->update(delta_t);
				if (EXPECT_NOT(sessionID != _sessionID))
				{
					// Game was reset (in player update); end this update: cycle.
					break;
				}
				
#ifndef NDEBUG
				update_stage = "update:list maintenance [%@]";
#endif
				
				// maintain distance-from-player list
				GLfloat z_distance = thing->zero_distance;
				
				int index = thing->zero_index;
				while (index > 0 && z_distance < sortedEntities[index - 1]->zero_distance)
				{
					sortedEntities[index] = sortedEntities[index - 1];	// bubble up the list, usually by just one position
					sortedEntities[index - 1] = thing;
					thing->zero_index = index - 1;
					sortedEntities[index]->zero_index = index;
					index--;
				}
				
				// update deterministic AI
				if (oo::EntityIsShip(thing))
				{
#ifndef NDEBUG
					update_stage = "update:think [%@]";
#endif
					::AI* theShipsAI = (oo::ToShip(thing) != nullptr ? oo::ToShip(thing)->getAI() : (::AI *)nullptr);
					if (theShipsAI)
					{
						double thinkTime = (theShipsAI != nullptr ? theShipsAI->getNextThinkTime() : OOTimeAbsolute{});
						if ((universal_time > thinkTime)||(thinkTime == 0.0))
						{
							if (theShipsAI != nullptr)  theShipsAI->setNextThinkTime(universal_time + (theShipsAI != nullptr ? theShipsAI->getThinkTimeInterval() : OOTimeDelta{}));
							if (theShipsAI != nullptr)  theShipsAI->think();
						}
					}
				}
			}
#ifndef NDEBUG
		update_stage_param = nullptr;
#endif
			
			if (!zombies.empty())
			{
				update_stage = "shootin' zombies";
				Entity *zombie = nullptr;
				for (const oo::EntityHold &entry : zombies)
				{
					zombie = entry.get();
					OO_LOG_ERR("universe.zombie", "Found dead entity {} in active entity list, removing. This is an internal error, please report it.", oo::EntityDescription(zombie));
					removeEntity(zombie);
				}
			}
			
			// Maintain x/y/z order lists
			update_stage = "updating linked lists";
			OO_LOG("universe.profile.update", "{}", const_cast<const char *>(update_stage));
			for (i = 0; i < ent_count; i++)
			{
				my_entities[i]->updateLinkedLists();
			}
			
			// detect collisions and light ships that can see the sun
			
			update_stage = "collision and shadow detection";
			OO_LOG("universe.profile.update", "{}", const_cast<const char *>(update_stage));
			filterSortedLists();
			findCollisionsAndShadows();
			
			// do any required check and maintenance of linked lists
			
			if (doLinkedListMaintenanceThisUpdate)
			{
				MaintainLinkedLists(this);
				doLinkedListMaintenanceThisUpdate = NO;
			}
		}
		catch (...)
		{
			const auto exception = oo::CurrentOOException();
			if (!exception)  throw;	// not an OOException: it goes on up, as before
			if (strncmp(exception->name(), "Oolite", 6) == 0)
			{
				handleOoliteException(exception->object());
			}
			else
			{
				std::string stage = update_stage;
#ifndef NDEBUG
				if (update_stage_param != nullptr)  stage = oo::str::formatRuntime(stage, { oo::EntityDescription(update_stage_param) });
#endif
				OO_LOG(cxx_kOOLogException, "***** Exception during [{}] in [Universe update:] : {} : {} *****", stage, exception->name(), exception->reason());
				throw;
			}
		}
		
		// dispose of the non-mutable copy and everything it references neatly
		update_stage = "clean up";
		OO_LOG("universe.profile.update", "{}", const_cast<const char *>(update_stage));
		for (i = 0; i < ent_count; i++)
		{
			oo::ReleaseEntity(my_entities[i]);	// explicitly release each one
		}
		/* Garbage collection is going to result in a significant
		 * pause when it happens. Doing it here is better than doing
		 * it in the middle of the update when it might slow a
		 * function into the timelimiter through no fault of its
		 * own. ooscript::maybeGC will only run a GC when it's
		 * necessary. Merely checking is not significant in terms of
		 * time. - CIM: 4/8/2013
		 */
		update_stage = "JS Garbage Collection";
		OO_LOG("universe.profile.update", "{}", const_cast<const char *>(update_stage)); 
#ifndef NDEBUG
		ooscript::Context context = OOJSAcquireContext(); 
		uint32_t gcbytes1 = ooscript::getGCParameter(ooscript::getRuntime(context),ooscript::GCParam::Bytes);
		OOJSRelinquishContext(context);
#endif
		OOJavaScriptEngine::sharedEngine()->garbageCollectionOpportunity(NO);
#ifndef NDEBUG
		context = OOJSAcquireContext(); 
		uint32_t gcbytes2 = ooscript::getGCParameter(ooscript::getRuntime(context),ooscript::GCParam::Bytes);
		OOJSRelinquishContext(context);
		if (gcbytes2 < gcbytes1)
		{
			OO_LOG("universe.profile.jsgc", "Unplanned JS Garbage Collection from {} to {}", gcbytes1, gcbytes2);
		}
#endif


	}
	else
	{
		// always perform player's dead updates: allows deferred JS resets.
		if ((PLAYER != nullptr ? PLAYER->status() : OOEntityStatus{}) == STATUS_DEAD)  { if (PLAYER != nullptr)  PLAYER->update(delta_t); }
	}
	
	// The dead stay alive until the autorelease pool drains, as the autoreleased set kept them.
	AutoreleaseAll(entitiesDeadThisUpdate);
	entitiesDeadThisUpdate.reserve(n_entities);
	
	prunePreloadingPlanetMaterials();

	OO_LOG("universe.profile.update", "{}", "Update complete");
}


#ifndef NDEBUG
double Universe::getTimeAccelerationFactor()
{
	return timeAccelerationFactor;
}


void Universe::setTimeAccelerationFactor(double newTimeAccelerationFactor)
{
	if (newTimeAccelerationFactor < TIME_ACCELERATION_FACTOR_MIN || newTimeAccelerationFactor > TIME_ACCELERATION_FACTOR_MAX)
	{
		newTimeAccelerationFactor = TIME_ACCELERATION_FACTOR_DEFAULT;
	}
	timeAccelerationFactor = newTimeAccelerationFactor;
}
#else
double Universe::getTimeAccelerationFactor()
{
	return 1.0;
}


void Universe::setTimeAccelerationFactor(double /*newTimeAccelerationFactor*/)
{
}
#endif


bool Universe::getECMVisualFXEnabled()
{
	return ECMVisualFXEnabled;
}


void Universe::setECMVisualFXEnabled(bool isEnabled)
{
	ECMVisualFXEnabled = isEnabled;
}



// Slice 18 of docs/phases/3-slices/Universe.md (bead oo-tail0): filterSortedLists, setGalaxyTo:. The facade forwards
// each selector (until oo-ql9rn); sends to self were sends (ADR-0056 amendments oo-riqmz,
// oo-mvzmb).

void Universe::filterSortedLists()
{
	/*
	Eric, 17-10-2010: raised the area to be not filtered out, from the combined collision size to 2x this size.
	This allows this filtered list to be used also for proximity_alert and not only for collisions. Before the
	proximity_alert could only trigger when already very near a collision. To late for ships to react.
	This does raise the number of entities in the collision chain with as result that the number of pairs to compair
	becomes significant larger. However, almost all of these extra pairs are dealt with by a simple distance check.
	I currently see no noticeable negative effect while playing, but this change might still give some trouble I missed.
	*/
	Entity	*e0, *next, *prev;	// C++ parts (bead oo-9ht.39.4)
	OOHPScalar start, finish, next_start, next_finish, prev_start, prev_finish;
	
	// using the z_list - set or clear collisionTestFilter and clear collision_chain
	e0 = z_list_start;
	while (e0)
	{
		e0->collisionTestFilter = e0->canCollide()?0:3;
		e0->collision_chain = nil;
		e0 = e0->z_next;
	}
	// done.
	
	/* We need to check the lists in both ascending and descending order
	 * to catch some cases with interposition of entities. We set cTF =
	 * 1 on the way up, and |= 2 on the way down. Therefore it's only 3
	 * at the end of the list if it was caught both ways on the same
	 * list. - CIM: 7/11/2012 */

	// start with the z_list
	e0 = z_list_start;
	while (e0)
	{
		// here we are either at the start of the list or just past a gap
		start = e0->position.z - 2.0f * e0->collision_radius;
		finish = start + 4.0f * e0->collision_radius;
		next = e0->z_next;
		while ((next)&&(next->collisionTestFilter == 3))	// next has been eliminated from the list of possible colliders - so skip it
			next = next->z_next;
		if (next)
		{
			next_start = next->position.z - 2.0f * next->collision_radius;
			if (next_start < finish)
			{
				// e0 and next overlap
				while ((next)&&(next_start < finish))
				{
					// skip forward to the next gap or the end of the list
					next_finish = next_start + 4.0f * next->collision_radius;
					if (next_finish > finish)
						finish = next_finish;
					e0 = next;
					next = e0->z_next;
					while ((next)&&(next->collisionTestFilter==3))	// next has been eliminated - so skip it
						next = next->z_next;
					if (next)
						next_start = next->position.z - 2.0f * next->collision_radius;
				}
				// now either (next == nil) or (next_start >= finish)-which would imply a gap!
			}
			else
			{
				// e0 is a singleton
				e0->collisionTestFilter = 1;
			}
		}
		else // (next == nil)
		{
			// at the end of the list so e0 is a singleton
			e0->collisionTestFilter = 1;
		}
		e0 = next;
	}
	// list filtered upwards, now filter downwards
	// e0 currently = end of z list
	while (e0)
	{
		// here we are either at the start of the list or just past a gap
		start = e0->position.z + 2.0f * e0->collision_radius;
		finish = start - 4.0f * e0->collision_radius;
		prev = e0->z_previous;
		while ((prev)&&(prev->collisionTestFilter == 3))	// next has been eliminated from the list of possible colliders - so skip it
			prev = prev->z_previous;
		if (prev)
		{
			prev_start = prev->position.z + 2.0f * prev->collision_radius;
			if (prev_start > finish)
			{
				// e0 and next overlap
				while ((prev)&&(prev_start > finish))
				{
					// skip forward to the next gap or the end of the list
					prev_finish = prev_start - 4.0f * prev->collision_radius;
					if (prev_finish < finish)
						finish = prev_finish;
					e0 = prev;
					prev = e0->z_previous;
					while ((prev)&&(prev->collisionTestFilter==3))	// next has been eliminated - so skip it
						prev = prev->z_previous;
					if (prev)
						prev_start = prev->position.z + 2.0f * prev->collision_radius;
				}
				// now either (prev == nil) or (prev_start <= finish)-which would imply a gap!
			}
			else
			{
				// e0 is a singleton
				e0->collisionTestFilter |= 2;
			}
		}
		else // (prev == nil)
		{
			// at the end of the list so e0 is a singleton
			e0->collisionTestFilter |= 2;
		}
		e0 = prev;
	}
	// done! list filtered
	
	// then with the y_list, z_list singletons now create more gaps..
	e0 = y_list_start;
	while (e0)
	{
		// here we are either at the start of the list or just past a gap
		start = e0->position.y - 2.0f * e0->collision_radius;
		finish = start + 4.0f * e0->collision_radius;
		next = e0->y_next;
		while ((next)&&(next->collisionTestFilter==3))	// next has been eliminated from the list of possible colliders - so skip it
			next = next->y_next;
		if (next)
		{
			
			next_start = next->position.y - 2.0f * next->collision_radius;
			if (next_start < finish)
			{
				// e0 and next overlap
				while ((next)&&(next_start < finish))
				{
					// skip forward to the next gap or the end of the list
					next_finish = next_start + 4.0f * next->collision_radius;
					if (next_finish > finish)
						finish = next_finish;
					e0 = next;
					next = e0->y_next;
					while ((next)&&(next->collisionTestFilter==3))	// next has been eliminated - so skip it
						next = next->y_next;
					if (next)
						next_start = next->position.y - 2.0f * next->collision_radius;
				}
				// now either (next == nil) or (next_start >= finish)-which would imply a gap!
			}
			else
			{
				// e0 is a singleton
				e0->collisionTestFilter = 1;
			}
		}
		else // (next == nil)
		{
			// at the end of the list so e0 is a singleton
			e0->collisionTestFilter = 1;
		}
		e0 = next;
	}
	// list filtered upwards, now filter downwards
	// e0 currently = end of y list
	while (e0)
	{
		// here we are either at the start of the list or just past a gap
		start = e0->position.y + 2.0f * e0->collision_radius;
		finish = start - 4.0f * e0->collision_radius;
		prev = e0->y_previous;
		while ((prev)&&(prev->collisionTestFilter == 3))	// next has been eliminated from the list of possible colliders - so skip it
			prev = prev->y_previous;
		if (prev)
		{
			prev_start = prev->position.y + 2.0f * prev->collision_radius;
			if (prev_start > finish)
			{
				// e0 and next overlap
				while ((prev)&&(prev_start > finish))
				{
					// skip forward to the next gap or the end of the list
					prev_finish = prev_start - 4.0f * prev->collision_radius;
					if (prev_finish < finish)
						finish = prev_finish;
					e0 = prev;
					prev = e0->y_previous;
					while ((prev)&&(prev->collisionTestFilter==3))	// next has been eliminated - so skip it
						prev = prev->y_previous;
					if (prev)
						prev_start = prev->position.y + 2.0f * prev->collision_radius;
				}
				// now either (prev == nil) or (prev_start <= finish)-which would imply a gap!
			}
			else
			{
				// e0 is a singleton
				e0->collisionTestFilter |= 2;
			}
		}
		else // (prev == nil)
		{
			// at the end of the list so e0 is a singleton
			e0->collisionTestFilter |= 2;
		}
		e0 = prev;
	}
	// done! list filtered
	
	// finish with the x_list
	e0 = x_list_start;
	while (e0)
	{
		// here we are either at the start of the list or just past a gap
		start = e0->position.x - 2.0f * e0->collision_radius;
		finish = start + 4.0f * e0->collision_radius;
		next = e0->x_next;
		while ((next)&&(next->collisionTestFilter==3))	// next has been eliminated from the list of possible colliders - so skip it
			next = next->x_next;
		if (next)
		{
			next_start = next->position.x - 2.0f * next->collision_radius;
			if (next_start < finish)
			{
				// e0 and next overlap
				while ((next)&&(next_start < finish))
				{
					// skip forward to the next gap or the end of the list
					next_finish = next_start + 4.0f * next->collision_radius;
					if (next_finish > finish)
						finish = next_finish;
					e0 = next;
					next = e0->x_next;
					while ((next)&&(next->collisionTestFilter==3))	// next has been eliminated - so skip it
						next = next->x_next;
					if (next)
						next_start = next->position.x - 2.0f * next->collision_radius;
				}
				// now either (next == nil) or (next_start >= finish)-which would imply a gap!
			}
			else
			{
				// e0 is a singleton
				e0->collisionTestFilter = 1;
			}
		}
		else // (next == nil)
		{
			// at the end of the list so e0 is a singleton
			e0->collisionTestFilter = 1;
		}
		e0 = next;
	}
	// list filtered upwards, now filter downwards
	// e0 currently = end of x list
	while (e0)
	{
		// here we are either at the start of the list or just past a gap
		start = e0->position.x + 2.0f * e0->collision_radius;
		finish = start - 4.0f * e0->collision_radius;
		prev = e0->x_previous;
		while ((prev)&&(prev->collisionTestFilter == 3))	// next has been eliminated from the list of possible colliders - so skip it
			prev = prev->x_previous;
		if (prev)
		{
			prev_start = prev->position.x + 2.0f * prev->collision_radius;
			if (prev_start > finish)
			{
				// e0 and next overlap
				while ((prev)&&(prev_start > finish))
				{
					// skip forward to the next gap or the end of the list
					prev_finish = prev_start - 4.0f * prev->collision_radius;
					if (prev_finish < finish)
						finish = prev_finish;
					e0 = prev;
					prev = e0->x_previous;
					while ((prev)&&(prev->collisionTestFilter==3))	// next has been eliminated - so skip it
						prev = prev->x_previous;
					if (prev)
						prev_start = prev->position.x + 2.0f * prev->collision_radius;
				}
				// now either (prev == nil) or (prev_start <= finish)-which would imply a gap!
			}
			else
			{
				// e0 is a singleton
				e0->collisionTestFilter |= 2;
			}
		}
		else // (prev == nil)
		{
			// at the end of the list so e0 is a singleton
			e0->collisionTestFilter |= 2;
		}
		e0 = prev;
	}
	// done! list filtered
	
	// repeat the y_list - so gaps from the x_list influence singletons
	e0 = y_list_start;
	while (e0)
	{
		// here we are either at the start of the list or just past a gap
		start = e0->position.y - 2.0f * e0->collision_radius;
		finish = start + 4.0f * e0->collision_radius;
		next = e0->y_next;
		while ((next)&&(next->collisionTestFilter==3))	// next has been eliminated from the list of possible colliders - so skip it
			next = next->y_next;
		if (next)
		{
			next_start = next->position.y - 2.0f * next->collision_radius;
			if (next_start < finish)
			{
				// e0 and next overlap
				while ((next)&&(next_start < finish))
				{
					// skip forward to the next gap or the end of the list
					next_finish = next_start + 4.0f * next->collision_radius;
					if (next_finish > finish)
						finish = next_finish;
					e0 = next;
					next = e0->y_next;
					while ((next)&&(next->collisionTestFilter==3))	// next has been eliminated - so skip it
						next = next->y_next;
					if (next)
						next_start = next->position.y - 2.0f * next->collision_radius;
				}
				// now either (next == nil) or (next_start >= finish)-which would imply a gap!
			}
			else
			{
				// e0 is a singleton
				e0->collisionTestFilter = 1;
			}
		}
		else // (next == nil)
		{
			// at the end of the list so e0 is a singleton
			e0->collisionTestFilter = 1;
		}
		e0 = next;
	}
	// e0 currently = end of y list
	while (e0)
	{
		// here we are either at the start of the list or just past a gap
		start = e0->position.y + 2.0f * e0->collision_radius;
		finish = start - 4.0f * e0->collision_radius;
		prev = e0->y_previous;
		while ((prev)&&(prev->collisionTestFilter == 3))	// next has been eliminated from the list of possible colliders - so skip it
			prev = prev->y_previous;
		if (prev)
		{
			prev_start = prev->position.y + 2.0f * prev->collision_radius;
			if (prev_start > finish)
			{
				// e0 and next overlap
				while ((prev)&&(prev_start > finish))
				{
					// skip forward to the next gap or the end of the list
					prev_finish = prev_start - 4.0f * prev->collision_radius;
					if (prev_finish < finish)
						finish = prev_finish;
					e0 = prev;
					prev = e0->y_previous;
					while ((prev)&&(prev->collisionTestFilter==3))	// next has been eliminated - so skip it
						prev = prev->y_previous;
					if (prev)
						prev_start = prev->position.y + 2.0f * prev->collision_radius;
				}
				// now either (prev == nil) or (prev_start <= finish)-which would imply a gap!
			}
			else
			{
				// e0 is a singleton
				e0->collisionTestFilter |= 2;
			}
		}
		else // (prev == nil)
		{
			// at the end of the list so e0 is a singleton
			e0->collisionTestFilter |= 2;
		}
		e0 = prev;
	}
	// done! list filtered
	
	// finally, repeat the z_list - this time building collision chains...
	e0 = z_list_start;
	while (e0)
	{
		// here we are either at the start of the list or just past a gap
		start = e0->position.z - 2.0f * e0->collision_radius;
		finish = start + 4.0f * e0->collision_radius;
		next = e0->z_next;
		while ((next)&&(next->collisionTestFilter==3))	// next has been eliminated from the list of possible colliders - so skip it
			next = next->z_next;
		if (next)
		{
			next_start = next->position.z - 2.0f * next->collision_radius;
			if (next_start < finish)
			{
				// e0 and next overlap
				while ((next)&&(next_start < finish))
				{
					// chain e0 to next in collision
					e0->collision_chain = next;
					// skip forward to the next gap or the end of the list
					next_finish = next_start + 4.0f * next->collision_radius;
					if (next_finish > finish)
						finish = next_finish;
					e0 = next;
					next = e0->z_next;
					while ((next)&&(next->collisionTestFilter==3))	// next has been eliminated - so skip it
						next = next->z_next;
					if (next)
						next_start = next->position.z - 2.0f * next->collision_radius;
				}
				// now either (next == nil) or (next_start >= finish)-which would imply a gap!
				e0->collision_chain = nil;	// end the collision chain
			}
			else
			{
				// e0 is a singleton
				e0->collisionTestFilter = 1;
			}
		}
		else // (next == nil)
		{
			// at the end of the list so e0 is a singleton
			e0->collisionTestFilter = 1;
		}
		e0 = next;
	}
	// e0 currently = end of z list
	while (e0)
	{
		// here we are either at the start of the list or just past a gap
		start = e0->position.z + 2.0f * e0->collision_radius;
		finish = start - 4.0f * e0->collision_radius;
		prev = e0->z_previous;
		while ((prev)&&(prev->collisionTestFilter == 3))	// next has been eliminated from the list of possible colliders - so skip it
			prev = prev->z_previous;
		if (prev)
		{
			prev_start = prev->position.z + 2.0f * prev->collision_radius;
			if (prev_start > finish)
			{
				// e0 and next overlap
				while ((prev)&&(prev_start > finish))
				{
					// e0 probably already in collision chain at this point, but if it
					// isn't we have to insert it
					if (prev->collision_chain != e0)
					{
						if (prev->collision_chain == nil)
						{
							// easy, just add it onto the start of the chain
							prev->collision_chain = e0;
						}
						else
						{
							/* not nil and not e0 shouldn't be possible, I think.
							 * if it is, that implies that e0->collision_chain is nil, though
							 * so: */
							if (e0->collision_chain == nil)
							{
								e0->collision_chain = prev->collision_chain;
								prev->collision_chain = e0;
							}
							else
							{
								/* This shouldn't happen... If it does, we accept
								 * missing collision checks and move on */
								OO_LOG("general.error.inconsistentState", "Unexpected state in collision chain builder prev={}, prev->c={}, e0={}, e0->c={}", oo::EntityDescription(prev), oo::EntityDescription(prev->collision_chain), oo::EntityDescription(e0), oo::EntityDescription(e0->collision_chain));
							}
						}
					}
					// skip forward to the next gap or the end of the list
					prev_finish = prev_start - 4.0f * prev->collision_radius;
					if (prev_finish < finish)
						finish = prev_finish;
					e0 = prev;
					prev = e0->z_previous;
					while ((prev)&&(prev->collisionTestFilter==3))	// next has been eliminated - so skip it
						prev = prev->z_previous;
					if (prev)
						prev_start = prev->position.z + 2.0f * prev->collision_radius;
				}
				// now either (prev == nil) or (prev_start <= finish)-which would imply a gap!

				// all the collision chains are already terminated somewhere
				// at this point so no need to set e0->collision_chain = nil
			}
			else
			{
				// e0 is a singleton
				e0->collisionTestFilter |= 2;
			}
		}
		else // (prev == nil)
		{
			// at the end of the list so e0 is a singleton
			e0->collisionTestFilter |= 2;
		}
		e0 = prev;
	}
	// done! list filtered
}


void Universe::setGalaxyTo(OOGalaxyID g)
{
	setGalaxyTo(g, NO);
}



// Slice 19 of docs/phases/3-slices/Universe.md (bead oo-z3u03): galaxy and system changes, descriptions, scenarios, characters, mission text, system data and names, finding systems. The facade forwards
// each selector (until oo-ql9rn); sends to self were sends (ADR-0056 amendments oo-riqmz,
// oo-mvzmb).

void Universe::setGalaxyTo(OOGalaxyID g, bool forced)
{
	int						i;
	
	if (galaxyID != g || forced) {
		galaxyID = g;
		
		// systems
		{
			for (i = 0; i < 256; i++)
			{
				system_names[i] = SystemPropertyString((systemManager != nullptr ? systemManager->getProperty("name", i, g) : oo::PList()));

			}
		}
	}
}


void Universe::setSystemTo(OOSystemID s)
{
	oo::PList		systemData;
	::PlayerEntity	*player = PLAYER;
	OOEconomyID		economy;
	std::optional<std::string>	scriptName;

	setGalaxyTo((player != nullptr ? player->galaxyNumber() : OOGalaxyID{}));

	systemID = s;
	targetSystemID = s;

	systemData = generateSystemData(targetSystemID);
	economy = systemData.get<unsigned char>(std::string(KEY_ECONOMY));
	scriptName = OptionalStringIn(systemData, "market_script");

	commodityMarket = (commodities != nullptr ? commodities->generateMarketForSystemWithEconomy(economy, scriptName) : oo::Ref<OOCommodityMarket>());
}


OOSystemID Universe::currentSystemID()
{
	return systemID;
}


const oo::PList *Universe::descriptions()
{
	if (_descriptions.isNull())
	{
		// Load internal descriptions.plist for use in early init, OXP verifier etc.
		// It will be replaced by merged version later if running the game normally.
		_descriptions = DictionaryWithContentsOfFile(oo::str::appendingPathComponent(oo::str::appendingPathComponent(*ResourceManager::builtInPath(), "Config"), "descriptions.plist"));
		_descriptionsGeneration = ++sDescriptionsGeneration;

		verifyDescriptions();
	}
	return &_descriptions;
}


unsigned Universe::descriptionsGeneration()
{
	return _descriptionsGeneration;
}


void Universe::verifyDescriptions()
{
	/*
		Ensure that no descriptions.plist entries contain the %n format code,
		which can be used to smash the stack and potentially call arbitrary
		functions.
		
		%n is deliberately not supported in Foundation/CoreFoundation under
		Mac OS X, but unfortunately GNUstep implements it.
		-- Ahruman 2011-05-05
	*/
	
	if (_descriptions.isNull())
	{
		OO_LOG("descriptions.verify", "{}", "***** FATAL: Tried to verify descriptions, but descriptions was nil - unable to load any descriptions.plist file.");
		exit(EXIT_FAILURE);
	}
	// Byte order of the key (was hash order): it decides only which bad entry is reported first.
	if (const oo::PList::Dict *entries = _descriptions.getIf<oo::PList::Dict>())
	{
		for (const auto &[key, value] : *entries)
		{
			VerifyDesc(key, value);
		}
	}
}


void Universe::loadDescriptions()
{
	_descriptions = ResourceManager::dictionaryFromFilesNamed("descriptions.plist", std::string("Config"), YES);
	_descriptionsGeneration = ++sDescriptionsGeneration;
	verifyDescriptions();
}


oo::PList Universe::explosionSetting(const std::string &explosion)
{
	const oo::PList *setting = explosionSettings.get<oo::PList::Dict>(explosion);
	return (setting != nullptr) ? *setting : oo::PList();
}


oo::PList Universe::scenarios()
{
	return _scenarios;
}


void Universe::loadScenarios()
{
	_scenarios = ResourceManager::arrayFromFilesNamed("scenarios.plist", std::string("Config"), YES);
}


oo::PList Universe::getCharacters()
{
	return characters;
}


oo::PList Universe::getMissiontext()
{
	return missiontext;
}


std::optional<std::string> Universe::descriptionForKey(const std::string &key)
{
	return chooseStringForKey(key, *descriptions());
}


std::optional<std::string> Universe::descriptionForArrayKey(const std::string &key, unsigned index)
{
	const oo::PList *array = descriptions()->get<oo::PList::Array>(key);
	if (array == nullptr || array->count() <= index)  return std::nullopt;	// Catches a missing array
	return OptionalStringAt(*array, index);
}


bool Universe::descriptionBooleanForKey(const std::string &key)
{
	return descriptions()->get<bool>(key);
}


::OOSystemDescriptionManager *Universe::getSystemManager()
{
	return systemManager.get();
}


std::optional<std::string> Universe::keyForPlanetOverridesForSystem(OOSystemID s, OOGalaxyID g)
{
	return oo::str::format("%d %d", g, s);
}


std::optional<std::string> Universe::keyForInterstellarOverridesForSystems(OOSystemID s1, OOSystemID s2, OOGalaxyID g)
{
	return oo::str::format("interstellar: %d %d %d", g, s1, s2);
}


oo::PList Universe::generateSystemData(OOSystemID s)
{
	return generateSystemData(s, YES);
}


// cache isn't handled this way any more
oo::PList Universe::generateSystemData(OOSystemID s, bool /*useCache*/)
{
	OOJS_PROFILE_ENTER

// TODO: At the moment this method is only called for systems in the
// same galaxy. At some point probably needs generalising to have a
// galaxynumber parameter.
	const std::string systemKey = oo::str::format("%u %u",(PLAYER != nullptr ? PLAYER->galaxyNumber() : OOGalaxyID{}),s);

	return (systemManager != nullptr ? systemManager->getPropertiesForSystemKey(systemKey) : oo::PList());

	OOJS_PROFILE_EXIT_VAL(oo::PList())
}


oo::PList Universe::currentSystemData()
{
	OOJS_PROFILE_ENTER

	if (!inInterstellarSpace())
	{
		return generateSystemData(systemID);
	}
	else
	{
		static oo::PList interstellarDict;	// null until built
		if (interstellarDict.isNull())
		{
			const std::string interstellarName = cxx_OOLookUpDescriptionPRIV("interstellar-space");
			const std::string notApplicable = cxx_OOLookUpDescriptionPRIV("not-applicable");
			// signed integers, as +numberWithInt: made them
			const oo::PList minusOne = oo::PList::signedInteger(-1);
			const oo::PList zero = oo::PList::signedInteger(0);
			interstellarDict = oo::PList(oo::PList::Dict{
								{ std::string(KEY_NAME), oo::PList(interstellarName) },
								{ std::string(KEY_GOVERNMENT), minusOne },
								{ std::string(KEY_ECONOMY), minusOne },
								{ std::string(KEY_TECHLEVEL), minusOne },
								{ std::string(KEY_POPULATION), zero },
								{ std::string(KEY_PRODUCTIVITY), zero },
								{ std::string(KEY_RADIUS), zero },
								{ std::string(KEY_INHABITANTS), oo::PList(notApplicable) },
								{ std::string(KEY_DESCRIPTION), oo::PList(notApplicable) } });
		}

		return interstellarDict;
	}

	OOJS_PROFILE_EXIT_VAL(oo::PList())
}


bool Universe::inInterstellarSpace()
{
	return sun() == nil;
}


// layer 2
// used by legacy script engine and sun going nova
void Universe::setSystemDataKey(const std::string &key, const oo::PList &value, const std::optional<std::string> &manifest)
{
	setSystemDataForGalaxy(galaxyID, systemID, key, value, manifest, OO_LAYER_OXP_DYNAMIC);
}


void Universe::setSystemDataForGalaxy(OOGalaxyID gnum, OOSystemID pnum, const std::string &key, const oo::PList &value, const std::optional<std::string> &manifest, OOSystemLayer layer)
{
	oo::PList	object = value;	// the script value, as the Objective-C object it was (null: nil)
	static BOOL sysdataLocked = NO;
	if (sysdataLocked)
	{
		OO_LOG_ERR("script.error", "{}", "System properties cannot be set during 'systemInformationChanged' events to avoid infinite loops.");
		return;
	}

	BOOL sameGalaxy = (gnum == (PLAYER != nullptr ? PLAYER->currentGalaxyID() : OOGalaxyID{}));
	BOOL sameSystem = (sameGalaxy && pnum == currentSystemID());

	// trying to set  unsettable properties?  
	if (key == std::string(KEY_RADIUS) && sameGalaxy && sameSystem) // buggy if we allow this key to be set while in the system
	{
		OO_LOG_ERR("script.error", "System property '{}' cannot be set while in the system.", key);
		return;
	}

	if (key == "coordinates") // setting this in game would be very confusing
	{
		OO_LOG_ERR("script.error", "System property '{}' cannot be set.", key);
		return;
	}


	const std::string	overrideKey = oo::str::format("%u %u", gnum, pnum);
	oo::PList	sysInfo;

	// short range map fix
	if (gui != nullptr)  gui->refreshStarChart();

	if (!object.isNull()) {
		// long range map fixes
		if (key == std::string(KEY_NAME))
		{
			// -lowercaseString / -capitalizedString of the name (a script string)
			const std::string *text = object.getIf<std::string>();
			const std::string name = oo::str::capitalized(oo::str::lowercase(text != nullptr ? *text : std::string()));
			object = oo::PList(name);
			if(sameGalaxy)
			{
				system_names[pnum] = name;
			}
		}
		else if (key == "sun_radius")
		{
			if (ScriptValueDouble(object) < 1000.0 || ScriptValueDouble(object) > 10000000.0 )
			{
				object = oo::PList(ScriptValueDouble(object) < 1000.0 ? "1000.0" : "10000000.0"); // works!
			}
		}
		else if (oo::str::hasPrefix(key, "corona_"))
		{
			object = oo::PList(oo::str::format("%f",OOClamp_0_1_f(ScriptValueFloat(object))));
		}
	}

	// a null value removes the property, as nil did
	if (systemManager != nullptr)  systemManager->setProperty(key, overrideKey, layer, object, manifest);


	// Apply changes that can be effective immediately, issue warning if they can't be changed just now
	if (sameSystem)
	{
		sysInfo = (systemManager != nullptr ? systemManager->getPropertiesForCurrentSystem() : oo::PList());

		::OOSunEntity* the_sun = sun();
		/* KEY_ECONOMY used to be here, but resetting the main station
		 * market while the player is in the system is likely to cause
		 * more trouble than it's worth. Let them leave and come back
		 * - CIM */
		if (key == std::string(KEY_TECHLEVEL))
		{	
			if(station()){
				if (station() != nullptr)  station()->setEquivalentTechLevel(ScriptValueInt(object));
				const oo::PList shipyard = shipsForSaleForSystem(systemID, ScriptValueInt(object), (PLAYER != nullptr ? PLAYER->clockTime() : 0.0));
				const oo::PList::Array *entries = shipyard.getIf<oo::PList::Array>();
				if (station() != nullptr)  station()->setLocalShipyard(entries != nullptr ? *entries : oo::PList::Array());
			}
		}
		else if (key == "sun_color" || key == "star_count_multiplier" ||
				key == "nebula_count_multiplier" || oo::str::hasPrefix(key, "sky_"))
		{
			::SkyEntity	*the_sky = nullptr;
			int i;
			
			// The sky is C++ since bead oo-9ht.109: found by its C++ part (it was -isKindOfClass:).
			for (i = n_entities - 1; i > 0; i--)
				if (sortedEntities[i] != nil)
					if (::SkyEntity *sky = dynamic_cast<::SkyEntity *>(sortedEntities[i]))
						the_sky = sky;
			
			if (the_sky != nullptr)
			{
				the_sky->changeProperty(key, sysInfo);

				if (key == "sun_color")
				{
					::OOColor *color = the_sky->getSkyColor();
					if (the_sun != nil)
					{
						if (the_sun != nullptr)  the_sun->setSunColor(color);
						if (the_sun != nullptr)  the_sun->getDiffuseComponents(sun_diffuse);
						if (the_sun != nullptr)  the_sun->getSpecularComponents(sun_specular);
					}
					for (i = n_entities - 1; i > 0; i--)
						if (sortedEntities[i])
							if (DustEntity *dust = dynamic_cast<DustEntity *>(sortedEntities[i]))
								dust->setDustColor((color != nullptr) ? color->blendedColorWithFraction(0.5, OOColor::whiteColor().get()).get() : nullptr);
				}
			}
		}
		else if (the_sun != nil && (oo::str::hasPrefix(key, "sun_") || oo::str::hasPrefix(key, "corona_")))
		{
			if (the_sun != nullptr)  the_sun->changeSunProperty(key, sysInfo);
		}
		else if (key == "texture")
		{
			const std::string *texture = object.getIf<std::string>();	// a texture name (a script string)
			if (planet() != nullptr)  planet()->setUpPlanetFromTexture((texture != nullptr) ? std::optional<std::string>(*texture) : std::nullopt);
		}
		else if (key == "texture_hsb_color")
		{
			if (planet() != nullptr)  planet()->setUpPlanetFromTexture((planet() != nullptr ? planet()->textureFileName() : std::optional<std::string>()));
		}
		else if (key == "air_color")
		{
			if (planet() != nullptr)  planet()->setAirColor(OOColor::brightColorWithDescription(object).get());
		}
		else if (key == "illumination_color")
		{
			if (planet() != nullptr)  planet()->setIlluminationColor(OOColor::colorWithDescription(object).get());
		}
		else if (key == "air_color_mix_ratio")
		{
			if (planet() != nullptr)  planet()->setAirColorMixRatio(sysInfo.get<float>(key));
		}
	}
	
	sysdataLocked = YES;
	// the same arguments (a nil value ends the list, as it did)
	std::vector<oo::PList> arguments{ oo::PList::signedInteger(gnum), oo::PList::signedInteger(pnum), oo::PList(key) };
	if (!object.isNull())  arguments.push_back(object);
	if (PLAYER != nullptr)  PLAYER->doScriptEvent(OOJSID("systemInformationChanged"), arguments);
	sysdataLocked = NO;

}


oo::PList Universe::generateSystemDataForGalaxy(OOGalaxyID gnum, OOSystemID pnum)
{
	const std::optional<std::string> systemKey = keyForPlanetOverridesForSystem(pnum, gnum);
	return (systemManager != nullptr ? systemManager->getPropertiesForSystemKey(*systemKey) : oo::PList());
}


// Byte order of the key (was the dictionary's -allKeys, hash order).
std::vector<std::string> Universe::systemDataKeysForGalaxy(OOGalaxyID gnum, OOSystemID pnum)
{
	std::vector<std::string> keys;
	const oo::PList systemData = generateSystemDataForGalaxy(gnum, pnum);
	if (const oo::PList::Dict *entries = systemData.getIf<oo::PList::Dict>())
	{
		for (const auto &[key, value] : *entries)  keys.push_back(key);
	}
	return keys;
}


/* Only called from OOJSSystemInfo. */
oo::PList Universe::systemDataForGalaxy(OOGalaxyID gnum, OOSystemID pnum, const std::string &key)
{
	return (systemManager != nullptr ? systemManager->getProperty(key, pnum, gnum) : oo::PList());
}


std::optional<std::string> Universe::getSystemName(OOSystemID sys)
{
	return getSystemName(sys, galaxyID);
}


std::optional<std::string> Universe::getSystemName(OOSystemID sys, OOGalaxyID gnum)
{
	return SystemPropertyString((systemManager != nullptr ? systemManager->getProperty("name", sys, gnum) : oo::PList()));
}


OOGovernmentID Universe::getSystemGovernment(OOSystemID sys)
{
	// -unsignedCharValue of the number (nil, where there is none, gave 0)
	return static_cast<unsigned char>((systemManager != nullptr ? systemManager->getProperty("government", sys, galaxyID) : oo::PList()).int64Value());
}


std::optional<std::string> Universe::getSystemInhabitants(OOSystemID sys)
{
	return getSystemInhabitants(sys, YES);
}


std::optional<std::string> Universe::getSystemInhabitants(OOSystemID sys, bool plural)
{
	std::optional<std::string> ret;
	if (!plural)
	{
		ret = SystemPropertyString((systemManager != nullptr ? systemManager->getProperty(std::string(KEY_INHABITANT), sys, galaxyID) : oo::PList()));
	}
	if (ret.has_value()) // the singular form might be absent.
	{
		return ret;
	}
	else
	{
		return SystemPropertyString((systemManager != nullptr ? systemManager->getProperty(std::string(KEY_INHABITANTS), sys, galaxyID) : oo::PList()));
	}
}


NSPoint Universe::coordinatesForSystem(OOSystemID s)
{
	return (systemManager != nullptr ? systemManager->getCoordinatesForSystem(s, galaxyID) : NSMakePoint(0, 0));
}


OOSystemID Universe::findSystemFromName(const std::string &sysName)
{
	const std::string match = oo::str::lowercase(sysName);
	int i;
	for (i = 0; i < 256; i++)
	{
		// a missing name matched nothing
		if (system_names[i].has_value() && oo::str::lowercase(*system_names[i]) == match)
		{
			return i;
		}
	}
	return -1;	// no match found!
}


OOSystemID Universe::findSystemAtCoords(NSPoint coords, OOGalaxyID g)
{
	OO_LOG("deprecated.function", "{}", "findSystemAtCoords");
	return findSystemNumberAtCoords(coords, g, YES);
}



/*	A node of -cxx_routeFromSystem:toSystem:optimizedBy:'s search (slice 20 of
	docs/phases/3-slices/Universe.md, bead oo-lftoq): the Objective-C RouteElement as a C++ class,
	its accessors by the same names (ADR-0056 amendment oo-7jhs5).
*/
namespace {

class RouteElement : public oo::RefCounted
{
public:
	static oo::Ref<RouteElement> elementWithLocation(OOSystemID location, OOSystemID parent, double cost, double distance, double time, int jumps);
	OOSystemID parent();
	OOSystemID location();
	double cost();
	double distance();
	double time();
	int jumps();

private:
	OOSystemID _location = 0, _parent = 0;
	double _cost = 0, _distance = 0, _time = 0;
	int _jumps = 0;
};


oo::Ref<RouteElement> RouteElement::elementWithLocation(OOSystemID location, OOSystemID parent, double cost, double distance, double time, int jumps)
{
	oo::Ref<RouteElement> r = oo::makeRef<RouteElement>();

	r->_location = location;
	r->_parent = parent;
	r->_cost = cost;
	r->_distance = distance;
	r->_time = time;
	r->_jumps = jumps;

	return r;
}

OOSystemID RouteElement::parent() { return _parent; }
OOSystemID RouteElement::location() { return _location; }
double RouteElement::cost() { return _cost; }
double RouteElement::distance() { return _distance; }
double RouteElement::time() { return _time; }
int RouteElement::jumps() { return _jumps; }

}	// namespace


// Slice 20 of docs/phases/3-slices/Universe.md (bead oo-lftoq): neighbouring systems, system-name look-up, routes (with RouteElement), planet textures, global and equipment data, the commodity market, time descriptions. The facade forwards
// each selector (until oo-ql9rn); sends to self were sends (ADR-0056 amendments oo-riqmz,
// oo-mvzmb).

oo::PList Universe::nearbyDestinationsWithinRange(double range)
{
	oo::PList::Array result;
	
	range = OOClamp_0_max_d(range, MAX_JUMP_RANGE); // limit to systems within 7LY
	NSPoint here = (PLAYER != nullptr ? PLAYER->getGalaxy_coordinates() : NSPoint{});
	
	for (unsigned short i = 0; i < 256; i++)
	{
		NSPoint there = coordinatesForSystem(i);
		double dist = distanceBetweenPlanetPositions(here.x, here.y, there.x, there.y);
		if (dist <= range && (i != systemID || inInterstellarSpace())) // if we are in interstellar space, it's OK to include the system we (mis)jumped from
		{
			// the number kinds it held: a double, a signed integer
			result.push_back(oo::PList(oo::PList::Dict{
								{ "distance", oo::PList(dist) },
								{ "sysID", oo::PList::signedInteger(i) },
								{ "nova", oo::PList(generateSystemData(i).get<std::string>("sun_gone_nova", "0")) } }));
		}
	}

	return oo::PList(std::move(result));
}


OOSystemID Universe::findNeighbouringSystemToCoords(NSPoint coords, OOGalaxyID g)
{

	double distance;
	int n,i,j;
	double min_dist = 10000.0;
	
	// make list of connected systems
	BOOL connected[256];
	for (i = 0; i < 256; i++)
		connected[i] = NO;
	connected[0] = YES;			// system zero is always connected (true for galaxies 0..7)
	for (n = 0; n < 3; n++)		//repeat three times for surety
	{
		for (i = 0; i < 256; i++)   // flood fill out from system zero
		{
			NSPoint ipos = (systemManager != nullptr ? systemManager->getCoordinatesForSystem(i, g) : NSMakePoint(0, 0));
			for (j = 0; j < 256; j++)
			{
				NSPoint jpos = (systemManager != nullptr ? systemManager->getCoordinatesForSystem(j, g) : NSMakePoint(0, 0));
				double dist = distanceBetweenPlanetPositions(ipos.x,ipos.y,jpos.x,jpos.y);
				if (dist <= MAX_JUMP_RANGE)
				{
					connected[j] |= connected[i];
					connected[i] |= connected[j];
				}
			}
		}
	}
	OOSystemID system = 0;
	for (i = 0; i < 256; i++)
	{
		NSPoint ipos = (systemManager != nullptr ? systemManager->getCoordinatesForSystem(i, g) : NSMakePoint(0, 0));
		distance = distanceBetweenPlanetPositions((int)coords.x, (int)coords.y, ipos.x, ipos.y);
		if ((connected[i])&&(distance < min_dist)&&(distance != 0.0))
		{
			min_dist = distance;
			system = i;
		}
	}
	
	return system;
}


/* This differs from the above function in that it can return a system
 * exactly at the specified coordinates */
OOSystemID Universe::findConnectedSystemAtCoords(NSPoint coords, OOGalaxyID g)
{

	double distance;
	int n,i,j;
	double min_dist = 10000.0;
	
	// make list of connected systems
	BOOL connected[256];
	for (i = 0; i < 256; i++)
		connected[i] = NO;
	connected[0] = YES;			// system zero is always connected (true for galaxies 0..7)
	for (n = 0; n < 3; n++)		//repeat three times for surety
	{
		for (i = 0; i < 256; i++)   // flood fill out from system zero
		{
			NSPoint ipos = (systemManager != nullptr ? systemManager->getCoordinatesForSystem(i, g) : NSMakePoint(0, 0));
			for (j = 0; j < 256; j++)
			{
				NSPoint jpos = (systemManager != nullptr ? systemManager->getCoordinatesForSystem(j, g) : NSMakePoint(0, 0));
				double dist = distanceBetweenPlanetPositions(ipos.x,ipos.y,jpos.x,jpos.y);
				if (dist <= MAX_JUMP_RANGE)
				{
					connected[j] |= connected[i];
					connected[i] |= connected[j];
				}
			}
		}
	}
	OOSystemID system = 0;
	for (i = 0; i < 256; i++)
	{
		NSPoint ipos = (systemManager != nullptr ? systemManager->getCoordinatesForSystem(i, g) : NSMakePoint(0, 0));
		distance = distanceBetweenPlanetPositions((int)coords.x, (int)coords.y, ipos.x, ipos.y);
		if ((connected[i])&&(distance < min_dist))
		{
			min_dist = distance;
			system = i;
		}
	}
	
	return system;	
}


OOSystemID Universe::findSystemNumberAtCoords(NSPoint coords, OOGalaxyID g, bool hidden)
{
	/*
		NOTE: this previously used NSNotFound as the default value, but
		returned an int, which would truncate on 64-bit systems. I assume
		no-one was using it in a context where the default value was returned.
		-- Ahruman 2012-08-25
	*/
	OOSystemID	system = kOOMinimumSystemID;
	unsigned	distance, dx, dy;
	OOSystemID	i;
	unsigned	min_dist = 10000;
	
	for (i = 0; i < 256; i++)
	{
		if (!hidden) {
			const oo::PList systemInfo = (systemManager != nullptr ? systemManager->getPropertiesForSystem(i, g) : oo::PList());
			NSInteger concealment = systemInfo.get<int>("concealment", OO_SYSTEMCONCEALMENT_NONE);
			if (concealment >= OO_SYSTEMCONCEALMENT_NOTHING) {
				// system is not known
				continue;
			}
		}
		NSPoint ipos = (systemManager != nullptr ? systemManager->getCoordinatesForSystem(i, g) : NSMakePoint(0, 0));
		dx = ABS(coords.x - ipos.x);
		dy = ABS(coords.y - ipos.y);
		
		if (dx > dy)	distance = (dx + dx + dy) / 2;
		else			distance = (dx + dy + dy) / 2;
		
		if (distance < min_dist)
		{
			min_dist = distance;
			system = i;
		}
		// with coincident systems choose only if ABOVE
		if ((distance == min_dist)&&(coords.y > ipos.y))
		{
			system = i;
		}
		// or if EQUAL but already selected
		else if ((distance == min_dist)&&(coords.y == ipos.y)&&(i==(PLAYER != nullptr ? PLAYER->targetSystemID() : 0)))
		{
			system = i;
		}
	}
	return system;
}


NSPoint Universe::findSystemCoordinatesWithPrefix(const std::string &p_fix)
{
	return findSystemCoordinatesWithPrefix(p_fix, NO);
}


NSPoint Universe::findSystemCoordinatesWithPrefix(const std::string &p_fix, bool exactMatch)
{
	std::string	system_name;
	NSPoint 	system_coords = NSMakePoint(-1.0,-1.0);
	int i;
	int result = -1;
	for (i = 0; i < 256; i++)
	{
		system_found[i] = NO;
		if (!system_names[i].has_value())  continue;	// a missing name matched nothing
		system_name = oo::str::lowercase(*system_names[i]);
		if ((exactMatch && system_name == p_fix) || (!exactMatch && oo::str::hasPrefix(system_name, p_fix)))
		{
			/* Only used in player-based search routines */
			const oo::PList systemInfo = (systemManager != nullptr ? systemManager->getPropertiesForSystem(i, galaxyID) : oo::PList());
			NSInteger concealment = systemInfo.get<int>("concealment", OO_SYSTEMCONCEALMENT_NONE);
			if (concealment >= OO_SYSTEMCONCEALMENT_NONAME) {
				// system is not known
				continue;
			}
			
			system_found[i] = YES;
			if (result < 0)
			{
				system_coords = (systemManager != nullptr ? systemManager->getCoordinatesForSystem(i, galaxyID) : NSMakePoint(0, 0));
				result = i;
			}
		}
	}
	return system_coords;
}


BOOL *Universe::systemsFound()
{
	return (BOOL*)system_found;
}


std::optional<std::string> Universe::systemNameIndex(OOSystemID index)
{
	return system_names[index & 255];
}


oo::PList Universe::routeFromSystem(OOSystemID start, OOSystemID goal, OORouteType optimizeBy)
{
	/*
	 time_cost = distance * distance
	 jump_cost = jumps * max_total_distance + distance = max_total_tistance + distance
	 
	 max_total_distance is 7 * 256
	 
	 max_time_cost = max_planets * max_time_cost = 256 * (7 * 7)
	 max_jump_cost = max_planets * max_jump_cost = 256 * (7 * 256 + 7)
	 */
	
	// no interstellar space for start and/or goal please
	if (start == -1 || goal == -1)  return oo::PList();

#ifdef CACHE_ROUTE_FROM_SYSTEM_RESULTS

	static oo::PList c_route;
	static OOSystemID c_start, c_goal;
	static OORouteType c_optimizeBy;

	if (!c_route.isNull() && c_start == start && c_goal == goal && c_optimizeBy == optimizeBy)
	{
		return c_route;
	}

#endif

	unsigned i, j;

	if (start > 255 || goal > 255) return oo::PList();

	std::vector<OOSystemID> neighbours[256];
	BOOL concealed[256];
	for (i = 0; i < 256; i++)
	{
		const oo::PList systemInfo = (systemManager != nullptr ? systemManager->getPropertiesForSystem(i, galaxyID) : oo::PList());
		NSInteger concealment = systemInfo.get<int>("concealment", OO_SYSTEMCONCEALMENT_NONE);
		if (concealment >= OO_SYSTEMCONCEALMENT_NOTHING) {
			// system is not known
			neighbours[i].clear();
			concealed[i] = YES;
		}
		else
		{
			neighbours[i] = neighboursToSystem(i);
			concealed[i] = NO;
		}
	}
	
	oo::Ref<::RouteElement> cheapest[256];	// keeps each element, as the autorelease pool did
	
	double maxCost = optimizeBy == OPTIMIZED_BY_TIME ? 256 * (7 * 7) : 256 * (7 * 256 + 7);
	
	std::vector<oo::Ref<::RouteElement>> curr;
	curr.reserve(256);
	curr.push_back(cheapest[start] = ::RouteElement::elementWithLocation(start, -1, 0, 0, 0, 0));

	std::vector<oo::Ref<::RouteElement>> next;
	next.reserve(256);
	while (curr.size() != 0)
	{
		for (i = 0; i < curr.size(); i++) {
			::RouteElement *elemI = curr[i].get();
			const std::vector<OOSystemID> &ns = neighbours[elemI->location()];
			for (j = 0; j < ns.size(); j++)
			{
				::RouteElement *ce = cheapest[elemI->location()].get();
				OOSystemID n = ns[j];
				if (concealed[n])
				{
					continue;
				}
				OOSystemID c = ce->location();
				
				NSPoint cpos = (systemManager != nullptr ? systemManager->getCoordinatesForSystem(c, galaxyID) : NSMakePoint(0, 0));
				NSPoint npos = (systemManager != nullptr ? systemManager->getCoordinatesForSystem(n, galaxyID) : NSMakePoint(0, 0));

				double lastDistance = distanceBetweenPlanetPositions(npos.x,npos.y,cpos.x,cpos.y);
				double lastTime = lastDistance * lastDistance;
				
				double distance = ce->distance() + lastDistance;
				double time = ce->time() + lastTime;
				double cost = ce->cost() + (optimizeBy == OPTIMIZED_BY_TIME ? lastTime : 7 * 256 + lastDistance);
				int jumps = ce->jumps() + 1;
				
				if (cost < maxCost && (cheapest[n] == nullptr || cheapest[n]->cost() > cost)) {
					oo::Ref<::RouteElement> e = ::RouteElement::elementWithLocation(n, c, cost, distance, time, jumps);
					cheapest[n] = e;
					next.push_back(e);
					
					if (n == goal && cost < maxCost)
						maxCost = cost;
				}
			}
		}
		curr = next;
		next.clear();
	}


	if (!cheapest[goal]) return oo::PList();

	oo::PList::Array route;	// system IDs as signed integers, as +numberWithInt: made them
	::RouteElement *e = cheapest[goal].get();
	for (;;)
	{
		route.insert(route.begin(), oo::PList::signedInteger(e->location()));
		if (e->parent() == -1) break;
		e = cheapest[e->parent()].get();
	}

#ifdef CACHE_ROUTE_FROM_SYSTEM_RESULTS
	c_start = start;
	c_goal = goal;
	c_optimizeBy = optimizeBy;
	c_route = oo::PList(oo::PList::Dict{ { "route", oo::PList(std::move(route)) }, { "distance", oo::PList((double)cheapest[goal]->distance()) } });

	return c_route;
#else
	return oo::PList(oo::PList::Dict{
			{ "route", oo::PList(std::move(route)) },
			{ "distance", oo::PList((double)cheapest[goal]->distance()) },
			{ "time", oo::PList((double)cheapest[goal]->time()) },
			{ "jumps", oo::PList::signedInteger(cheapest[goal]->jumps()) } });
#endif
}


std::vector<OOSystemID> Universe::neighboursToSystem(OOSystemID s)
{
	if (s == systemID && closeSystems.has_value())
	{
		return *closeSystems;
	}
	std::vector<OOSystemID> neighbours = (systemManager != nullptr ? systemManager->getNeighbourIDsForSystem(s, galaxyID) : std::vector<OOSystemID>());

	if (s == systemID)
	{
		closeSystems = neighbours;
		return *closeSystems;
	}
	return neighbours;
}


/*
	Planet texture preloading.
	
	In order to hide the cost of synthesizing textures, we want to start
	rendering them asynchronously as soon as there's a hint they may be needed
	soon: when a system is selected on one of the charts, and when beginning a
	jump. However, it would be a Bad Idea™ to allow an arbitrary number of
	planets to be queued, since you can click on lots of systems quite
	quickly on the long-range chart.
	
	To rate-limit this, we track the materials that are being preloaded and
	only queue the ones for a new system if there are no more than two in the
	queue. (Currently, each system will have at most two materials, the main
	planet and the main planet's atmosphere, but it may be worth adding the
	ability to declare planets in planetinfo.plist instead of using scripts so
	that they can also benefit from preloading.)
	
	The preloading materials list is pruned before preloading, and also once
	per frame so textures can fall out of the regular cache.
	-- Ahruman 2009-12-19
	
	DISABLED due to crashes on some Windows systems. Textures generated here
	remain in the sRecentTextures cache when released, suggesting a retain
	imbalance somewhere. Cannot reproduce under Mac OS X. Needs further
	analysis before reenabling.
	http://www.aegidian.org/bb/viewtopic.php?f=3&t=12109
	-- Ahruman 2012-06-29
*/
void Universe::preloadPlanetTexturesForSystem(OOSystemID /*s*/)
{
// #if NEW_PLANETS
#if 0
	prunePreloadingPlanetMaterials();
	
	if (_preloadingPlanetMaterials.size() < 3)
	{
		
		::OOPlanetEntity *planet = [[::OOPlanetEntity alloc] initAsMainPlanetForSystem:s];
		::OOMaterial *surface = [planet material];
		// can be nil if texture mis-defined
		if (surface != nil)
		{
			// if it's already loaded, no need to continue
			if (![surface isFinishedLoading])
			{
				_preloadingPlanetMaterials.push_back(oo::Ref<::OOMaterial>(surface));
		
				// In some instances (retextured planets atm), the main planet might not have an atmosphere defined.
				// Trying to add nil to _preloadingPlanetMaterials will prematurely terminate the calling function.(!) --Kaks 20100107
				::OOMaterial *atmo = [planet atmosphereMaterial];
				if (atmo != nil)  _preloadingPlanetMaterials.push_back(oo::Ref<::OOMaterial>(atmo));
			}
		}
		
		[planet release];
	}
#endif
}


oo::PList Universe::getGlobalSettings()
{
	return globalSettings;
}


oo::PList Universe::getEquipmentData()
{
	return equipmentData;
}


oo::PList Universe::getEquipmentDataOutfitting()
{
	return equipmentDataOutfitting;
}


::OOCommodityMarket *Universe::getCommodityMarket()
{
	return commodityMarket.get();
}


std::optional<std::string> Universe::timeDescription(double interval)
{
	double r_time = interval;
	std::string result;

	if (r_time > 86400)
	{
		int days = floor(r_time / 86400);
		r_time -= 86400 * days;
		result = oo::str::format("%s %d day%s", result.c_str(), days, (days > 1) ? "s" : "");
	}
	if (r_time > 3600)
	{
		int hours = floor(r_time / 3600);
		r_time -= 3600 * hours;
		result = oo::str::format("%s %d hour%s", result.c_str(), hours, (hours > 1) ? "s" : "");
	}
	if (r_time > 60)
	{
		int mins = floor(r_time / 60);
		r_time -= 60 * mins;
		result = oo::str::format("%s %d minute%s", result.c_str(), mins, (mins > 1) ? "s" : "");
	}
	if (r_time > 0)
	{
		int secs = floor(r_time);
		result = oo::str::format("%s %d second%s", result.c_str(), secs, (secs > 1) ? "s" : "");
	}
	return oo::str::trim(result, oo::str::CharacterSet::whitespace());
}



// Slice 21 of docs/phases/3-slices/Universe.md (bead oo-enek8): short time descriptions, sun skimmers, station markets. The facade forwards
// each selector (until oo-ql9rn); sends to self were sends (ADR-0056 amendments oo-riqmz,
// oo-mvzmb).

std::optional<std::string> Universe::shortTimeDescription(double interval)
{
	double r_time = interval;
	std::string result;
	int parts = 0;

	if (interval <= 0.0)
		return cxx_OOLookUpDescriptionPRIV("contracts-no-time");

	if (r_time > 86400)
	{
		int days = floor(r_time / 86400);
		r_time -= 86400 * days;
		result = oo::str::format("%s %d %s", result.c_str(), days, cxx_OOLookUpPluralDescriptionPRIV("contracts-day-word", days).c_str());
		parts++;
	}
	if (r_time > 3600)
	{
		int hours = floor(r_time / 3600);
		r_time -= 3600 * hours;
		result = oo::str::format("%s %d %s", result.c_str(), hours, cxx_OOLookUpPluralDescriptionPRIV("contracts-hour-word", hours).c_str());
		parts++;
	}
	if (parts < 2 && r_time > 60)
	{
		int mins = floor(r_time / 60);
		r_time -= 60 * mins;
		result = oo::str::format("%s %d %s", result.c_str(), mins, cxx_OOLookUpPluralDescriptionPRIV("contracts-minute-word", mins).c_str());
		parts++;
	}
	if (parts < 2 && r_time > 0)
	{
		int secs = floor(r_time);
		result = oo::str::format("%s %d %s", result.c_str(), secs, cxx_OOLookUpPluralDescriptionPRIV("contracts-second-word", secs).c_str());
	}
	return oo::str::trim(result, oo::str::CharacterSet::whitespace());
}


void Universe::makeSunSkimmer(::ShipEntity *ship, bool setAI)
{
	if (setAI) { if (ship != nullptr)  ship->switchAITo("oolite-traderAI.js"); }	// perfectly acceptable for both route 2 & 3
	if (ship != nullptr)  ship->setFuel((Ranrot()&31));
	// slow ships need extra insulation or they will burn up when sunskimming. (Tested at biggest sun in G3: Aenqute)
	float minInsulation = 1000 / (ship != nullptr ? ship->getMaxFlightSpeed() : 0.0f) + 1;
	if ((ship != nullptr ? ship->heatInsulation() : 0.0f) < minInsulation) { if (ship != nullptr)  ship->setHeatInsulation(minInsulation); }
}


Random_Seed Universe::marketSeed()
{
	Random_Seed		ret = (systemManager != nullptr ? systemManager->getRandomSeedForCurrentSystem() : Random_Seed());
	
	// adjust basic seed by market random factor
	// which for (very bad) historical reasons is 0x80

	ret.f ^= 0x80;	// XOR back to front
	ret.e ^= ret.f;	// XOR
	ret.d ^= ret.e;	// XOR
	ret.c ^= ret.d;	// XOR
	ret.b ^= ret.c;	// XOR
	ret.a ^= ret.b;	// XOR
	
	return ret;
}


void Universe::loadStationMarkets(const oo::PList &marketData)
{
	if (marketData.isNull())
	{
		return;
	}

	const oo::PList::Array *savedMarkets = marketData.getIf<oo::PList::Array>();
	if (savedMarkets == nullptr)  return;
	for (const oo::PList &savedMarket : *savedMarkets)
	{
		HPVector pos = HPVectorIn(savedMarket, "position", kZeroHPVector);
		for (const oo::EntityHold &entry : stations())	// a snapshot
		{
			::StationEntity *station = oo::ToStation(entry.get());
			// must be deterministic and secondary
			if ((station != nullptr ? station->getAllowsSaving() : false) && station != (UNIVERSE != nullptr ? UNIVERSE->station() : nullptr))
			{
				// allow a km of drift just in case
				if (HPdistance2(pos,(station != nullptr ? station->getPosition() : HPVector{})) < 1000000)
				{
					const oo::PList *market = savedMarket.get<oo::PList::Array>("market");
					if (station != nullptr)  station->setLocalMarket((market != nullptr) ? *market : oo::PList());
					break;
				}
			}
		}
	}

}


// Saved in the savegame: the market rows as OOCommodityMarket saves them, the position as the
// doubles from cxx_ArrayFromHPVector stored.
oo::PList Universe::getStationMarkets()
{
	oo::PList::Array markets;

	::OOCommodityMarket *stationMarket = nil;

	for (const oo::EntityHold &entry : stations())	// a snapshot
	{
		::StationEntity *station = oo::ToStation(entry.get());
		// must be deterministic and secondary
		if ((station != nullptr ? station->getAllowsSaving() : false) && station != (UNIVERSE != nullptr ? UNIVERSE->station() : nullptr))
		{
			stationMarket = (station != nullptr ? station->getLocalMarket() : (OOCommodityMarket *)nullptr);
			if (stationMarket != nil)
			{
				const HPVector position = (station != nullptr ? station->getPosition() : HPVector{});
				markets.push_back(oo::PList(oo::PList::Dict{
					{ "market", stationMarket->saveStationAmounts() },
					{ "position", oo::PList(oo::PList::Array{ oo::PList((double)position.x), oo::PList((double)position.y), oo::PList((double)position.z) }) } }));
			}
		}
	}

	return oo::PList(std::move(markets));
}



// Slice 22 of docs/phases/3-slices/Universe.md (bead oo-05ow5): ships for sale (cxx_shipsForSaleForSystem:withTL:atTime:). The facade forwards
// each selector (until oo-ql9rn); sends to self were sends (ADR-0056 amendments oo-riqmz,
// oo-mvzmb).

oo::PList Universe::shipsForSaleForSystem(OOSystemID s, OOTechLevelID specialTL, OOTimeAbsolute current_time)
{
	RANROTSeed saved_seed = RANROTGetFullSeed();
	Random_Seed ship_seed = marketSeed();

	std::map<std::string, oo::PList>	resultDictionary;	// by ship ID

	float					tech_price_boost = (ship_seed.a + ship_seed.b) / 256.0;
	unsigned				i;
	::PlayerEntity			*player = PLAYER;
	::OOShipRegistry			*registry = OOShipRegistry::sharedRegistry();
	RANROTSeed				personalitySeed = RanrotSeedFromRandomSeed(ship_seed);

	for (i = 0; i < 256; i++)
	{
		long long reference_time = 0x1000000 * floor(current_time / 0x1000000);

		long long c_time = ship_seed.a * 0x10000 + ship_seed.b * 0x100 + ship_seed.c;
		double ship_sold_time = reference_time + c_time;

		if (ship_sold_time < 0)
			ship_sold_time += 0x1000000;	// wraparound

		double days_until_sale = (ship_sold_time - current_time) / 86400.0;

		std::vector<std::string>	keysForShips = registry->playerShipKeys();
		unsigned		si;
		for (si = 0; si < keysForShips.size(); si++)
		{
			//eliminate any ships that fail a 'conditions test'
			const std::string	key = keysForShips[si];
			const oo::PList		dict = registry->shipyardInfoForKey(key);
			const oo::PList		*conditions = dict.get<oo::PList::Array>("conditions");

			if (!(player != nullptr ? player->scriptTestConditions((conditions != nullptr) ? *conditions : oo::PList()) : false))
			{
				RemoveKeyAt(keysForShips, si--);
			}
			std::optional<std::string> condition_script = OptionalStringIn(dict, "condition_script");
			if (condition_script.has_value())
			{
				::OOScript *condScript = getConditionScript(*condition_script);
				if (condScript != nil) // should always be non-nil, but just in case
				{
					ooscript::Context context = OOJSAcquireContext();
					BOOL OK;
					bool allow_purchase;
					ooscript::Value result;
					ooscript::Value args[] = { OOJSValueFromPList(context, oo::PList(key)) };

					OK = (condScript != nullptr ? condScript->callMethod(OOJSID("allowOfferShip"), context, args, sizeof args / sizeof *args, &result) : false);

					if (OK) OK = ooscript::valueToBoolean(context, result, &allow_purchase);

					OOJSRelinquishContext(context);

					if (OK && !allow_purchase)
					{
						/* if the script exists, the function exists, the function
						 * returns a bool, and that bool is false, block
						 * purchase. Otherwise allow it as default */
						RemoveKeyAt(keysForShips, si--);
					}
				}
			}

		}

		const oo::PList	systemInfo = generateSystemData(s);
		OOTechLevelID	techlevel;
		if (specialTL != NSNotFound)
		{
			//if we are passed a tech level use that
			techlevel = specialTL;
		}
		else
		{
			//otherwise use default for system
			techlevel = systemInfo.get<unsigned int>(std::string(KEY_TECHLEVEL));
		}
		unsigned		ship_index = (ship_seed.d * 0x100 + ship_seed.e) % keysForShips.size();
		const std::string	ship_key = keysForShips[ship_index];
		const oo::PList	ship_info = registry->shipyardInfoForKey(ship_key);
		OOTechLevelID	ship_techlevel = ship_info.get<int>(std::string(KEY_TECHLEVEL));

		double chance = 1.0 - pow(1.0 - ship_info.get<double>(std::string(KEY_CHANCE)), MAX((OOTechLevelID)1, techlevel - ship_techlevel));

		// seed random number generator
		int superRand1 = ship_seed.a * 0x10000 + ship_seed.c * 0x100 + ship_seed.e;
		uint32_t superRand2 = ship_seed.b * 0x10000 + ship_seed.d * 0x100 + ship_seed.f;
		ranrot_srand(superRand2);

		const oo::PList shipBaseDict = OOShipRegistry::sharedRegistry()->shipInfoForKey(ship_key);

		if ((days_until_sale > 0.0) && (days_until_sale < 30.0) && (ship_techlevel <= techlevel) && (randf() < chance) && !shipBaseDict.isNull())
		{
			oo::PList shipDict = shipBaseDict;
			std::string shortShipDescription;
			std::optional<std::string> shipName = OptionalStringIn(shipDict, "display_name");
			if (!shipName.has_value())  shipName = OptionalStringIn(shipDict, std::string(KEY_NAME));
			OOCreditsQuantity price = ship_info.get<unsigned int>(std::string(KEY_PRICE));
			OOCreditsQuantity base_price = price;
			const oo::PList *standardEquipment = ship_info.get<oo::PList::Dict>(std::string(KEY_STANDARD_EQUIPMENT));
			const oo::PList *standardExtras = (standardEquipment != nullptr) ? standardEquipment->get<oo::PList::Array>(std::string(KEY_EQUIPMENT_EXTRAS)) : nullptr;
			oo::PList::Array extras = (standardExtras != nullptr) ? *standardExtras->getIf<oo::PList::Array>() : oo::PList::Array();
			std::optional<std::string> fwdWeaponString = (standardEquipment != nullptr) ? OptionalStringIn(*standardEquipment, std::string(KEY_EQUIPMENT_FORWARD_WEAPON)) : std::nullopt;
			std::optional<std::string> aftWeaponString = (standardEquipment != nullptr) ? OptionalStringIn(*standardEquipment, std::string(KEY_EQUIPMENT_AFT_WEAPON)) : std::nullopt;

			const oo::PList *optionalEquipment = ship_info.get<oo::PList::Array>(std::string(KEY_OPTIONAL_EQUIPMENT));
			std::vector<std::optional<std::string>> options;
			if (optionalEquipment != nullptr)
			{
				for (std::size_t k = 0; k < optionalEquipment->count(); k++)  options.push_back(OptionalStringAt(*optionalEquipment, k));
			}
			OOCargoQuantity maxCargo = shipDict.get<unsigned int>("max_cargo");

			// more info for potential purchasers - how to reveal this I'm not yet sure...
			//std::optional<std::string> brochure_desc = [self brochureDescriptionWithDictionary:shipDict standardEquipment:extras optionalEquipment:options];
			//OO_LOG("shipyard.brochure", "{} Brochure description : \"{}\"", oo::DescriptionOf([ship name]), brochure_desc);

			shortShipDescription += TextOrNull(shipName) + ":";

			OOWeaponFacingSet availableFacings = ship_info.get<unsigned int>(std::string(KEY_WEAPON_FACINGS), VALID_WEAPON_FACINGS) & VALID_WEAPON_FACINGS;

			OOWeaponType fwdWeapon = cxx_OOWeaponTypeFromEquipmentIdentifierSloppy(fwdWeaponString.value_or(""));
			OOWeaponType aftWeapon = cxx_OOWeaponTypeFromEquipmentIdentifierSloppy(aftWeaponString.value_or(""));
			//port and starboard weapons are not modified in the shipyard
			// apply fwd and aft weapons to the ship
			if (fwdWeapon && fwdWeaponString) SetInDict(shipDict, std::string(KEY_EQUIPMENT_FORWARD_WEAPON), *fwdWeaponString);
			if (aftWeapon && aftWeaponString) SetInDict(shipDict, std::string(KEY_EQUIPMENT_AFT_WEAPON), *aftWeaponString);

			int passengerBerthCount = 0;
			BOOL customised = NO;
			BOOL weaponCustomized = NO;

			std::optional<std::string> fwdWeaponDesc;

			std::string shortExtrasKey = "shipyard-first-extra";

			// for testing condition scripts
			::ShipEntity *testship = ::ProxyPlayerEntity::newProxyObject(ship_key, shipDict);	// [[ProxyPlayerEntity alloc] cxx_initWithKey:definition:] until bead oo-9ht.183
			// customise the ship (if chance = 1, then ship will get all possible add ons)
			while ((randf() < chance) && (options.size()))
			{
				chance *= chance;	//decrease the chance of a further customisation (unless it is 1, which might be a bug)
				int				optionIndex = Ranrot() % options.size();
				const std::optional<std::string>	equipmentKey = options[optionIndex];
				::OOEquipmentType	*item = equipmentKey.has_value() ? OOEquipmentType::equipmentTypeWithIdentifier(*equipmentKey).get() : nil;

				if (item != nil)
				{
					OOTechLevelID		eqTechLevel = (item != nullptr ? item->techLevel() : 0);
					OOCreditsQuantity	eqPrice = (item != nullptr ? item->price() : 0) / 10;	// all amounts are x/10 due to being represented in tenths of credits.
					std::optional<std::string>	eqShortDesc = (item != nullptr ? item->name() : std::optional<std::string>());

					if ((item != nullptr ? item->techLevel() : 0) > techlevel)
					{
						// Cap maximum tech level.
						eqTechLevel = MIN(eqTechLevel, 15U);

						// Higher tech items are rarer!
						if (randf() * (eqTechLevel - techlevel) < 1.0)
						{
							// All included equip has a 10% discount.
							eqPrice *= (tech_price_boost + eqTechLevel - techlevel) * 90 / 100;
						}
						else
							break;	// Bar this upgrade.
					}

					if ((item != nullptr ? item->incompatibleEquipment() : std::optional<std::vector<std::string>>()).has_value())
					{
						BOOL						incompatible = NO;
						const std::vector<std::string>	incompatibleKeys = *(item != nullptr ? item->incompatibleEquipment() : std::optional<std::vector<std::string>>());

						for (const std::string &key : incompatibleKeys)
						{
							if (ContainsKey(extras, key))
							{
								RemoveOption(options, equipmentKey);
								incompatible = YES;
								break;
							}
						}
						if (incompatible) break;

						// make sure the incompatible equipment is not choosen later on.
						for (const std::string &key : incompatibleKeys)
						{
							RemoveOption(options, key);
						}
					}

					/* Check condition scripts */
					std::optional<std::string> condition_script = (item != nullptr ? item->conditionScript() : std::optional<std::string>());
					if (condition_script.has_value())
					{
						::OOScript *condScript = getConditionScript(*condition_script);
						if (condScript != nil) // should always be non-nil, but just in case
						{
							ooscript::Context JScontext = OOJSAcquireContext();
							BOOL OK;
							bool allow_addition;
							ooscript::Value result;
							ooscript::Value args[] = { OOJSValueFromPList(JScontext, oo::PList(*equipmentKey)) , OOJSValueFromCxxObject(JScontext, testship) , OOJSValueFromPList(JScontext, oo::PList("newShip"))};

							OK = (condScript != nullptr ? condScript->callMethod(OOJSID("allowAwardEquipment"), JScontext, args, sizeof args / sizeof *args, &result) : false);

							if (OK) OK = ooscript::valueToBoolean(JScontext, result, &allow_addition);

							OOJSRelinquishContext(JScontext);

							if (OK && !allow_addition)
							{
								/* if the script exists, the function exists, the function
								 * returns a bool, and that bool is false, block
								 * addition. Otherwise allow it as default */
								break;
							}
						}
					}


					if ((item != nullptr ? item->requiresEquipment() : std::optional<std::vector<std::string>>()).has_value())
					{
						BOOL						missing = NO;

						for (const std::string &key : (item != nullptr ? item->requiresEquipment() : std::optional<std::vector<std::string>>()).value_or(std::vector<std::string>()))
						{
							if (!ContainsKey(extras, key))
							{
								missing = YES;
							}
						}
						if (missing) break;
					}

					if ((item != nullptr ? item->requiresAnyEquipment() : std::optional<std::vector<std::string>>()).has_value())
					{
						BOOL						missing = YES;

						for (const std::string &key : (item != nullptr ? item->requiresAnyEquipment() : std::optional<std::vector<std::string>>()).value_or(std::vector<std::string>()))
						{
							if (ContainsKey(extras, key))
							{
								missing = NO;
							}
						}
						if (missing) break;
					}

					// Special case, NEU has to be compatible with EEU inside equipment.plist
					// but we can only have either one or the other on board.
					if (*equipmentKey == "EQ_NAVAL_ENERGY_UNIT")
					{
						if (ContainsKey(extras, "EQ_ENERGY_UNIT"))
						{
							RemoveOption(options, equipmentKey);
							break;
						}
					}

					if (oo::str::hasPrefix(*equipmentKey, "EQ_WEAPON"))
					{
						OOWeaponType new_weapon = cxx_OOWeaponTypeFromEquipmentIdentifierSloppy(*equipmentKey);
						//fit best weapon forward
						if (availableFacings & WEAPON_FACING_FORWARD && (new_weapon != nullptr ? new_weapon->weaponThreatAssessment() : 0.0f) > (fwdWeapon != nullptr ? fwdWeapon->weaponThreatAssessment() : 0.0f))
						{
							//again remember to divide price by 10 to get credits from tenths of credit
							price -= (fwdWeaponString ? getEquipmentPriceForKey(*fwdWeaponString) : 0) * 90 / 1000;	// 90% credits
							price += eqPrice;
							fwdWeaponString = equipmentKey;
							fwdWeapon = new_weapon;
							SetInDict(shipDict, std::string(KEY_EQUIPMENT_FORWARD_WEAPON), *fwdWeaponString);
							weaponCustomized = YES;
							fwdWeaponDesc = eqShortDesc;
						}
						else
						{
							//if less good than current forward, try fitting is to rear
							if (availableFacings & WEAPON_FACING_AFT && (isWeaponNone(aftWeapon) || (new_weapon != nullptr ? new_weapon->weaponThreatAssessment() : 0.0f) > (aftWeapon != nullptr ? aftWeapon->weaponThreatAssessment() : 0.0f)))
							{
								price -= (aftWeaponString ? getEquipmentPriceForKey(*aftWeaponString) : 0) * 90 / 1000;	// 90% credits
								price += eqPrice;
								aftWeaponString = equipmentKey;
								aftWeapon = new_weapon;
								SetInDict(shipDict, std::string(KEY_EQUIPMENT_AFT_WEAPON), *aftWeaponString);
							}
							else
							{
								RemoveOption(options, equipmentKey); //dont try again
							}
						}

					}
					else
					{
						if (*equipmentKey == "EQ_PASSENGER_BERTH")
						{
							if ((maxCargo >= PASSENGER_BERTH_SPACE) && (randf() < chance))
							{
								maxCargo -= PASSENGER_BERTH_SPACE;
								price += eqPrice;
								extras.push_back(oo::PList(*equipmentKey));
								passengerBerthCount++;
								customised = YES;
							}
							else
							{
								// remove the option if there's no space left
								RemoveOption(options, equipmentKey);
							}
						}
						else
						{
							price += eqPrice;
							extras.push_back(oo::PList(*equipmentKey));
							if ((item != nullptr ? item->isVisible() : false))
							{
								shortShipDescription += ExpandKeyWith(shortExtrasKey, "item", eqShortDesc ? oo::PList(*eqShortDesc) : oo::PList());
								shortExtrasKey = "shipyard-additional-extra";
							}
							customised = YES;
							RemoveOption(options, equipmentKey); //dont add twice
						}
					}
				}
				else
				{
					RemoveOption(options, equipmentKey);
				}
			} // end adding optional equipment
			if (testship != nullptr)  oo::ReleaseEntity(testship);
			// i18n: Some languages require that no conversion to lower case string takes place.
			BOOL lowercaseIgnore = descriptions()->get<bool>("lowercase_ignore");

			if (passengerBerthCount)
			{
				std::string npb = (passengerBerthCount > 1)? oo::str::format("%d ", passengerBerthCount) : std::string();
				std::string ppb = cxx_OOLookUpPluralDescriptionPRIV("passenger-berth", passengerBerthCount);
				std::string extraPassengerBerthsDescription = oo::str::formatRuntime(cxx_OOLookUpDescriptionPRIV("extra-@-@-(passenger-berths)"), { npb, ppb });
				shortShipDescription += ExpandKeyWith(shortExtrasKey, "item", oo::PList(extraPassengerBerthsDescription));
				shortExtrasKey = "shipyard-additional-extra";
			}

			if (!customised)
			{
				shortShipDescription += ExpandKey("shipyard-standard-customer-model");
			}

			if (weaponCustomized)
			{
				std::optional<std::string> weapon = fwdWeaponDesc;
				if (!lowercaseIgnore && weapon.has_value())  weapon = oo::str::lowercase(*weapon);
				shortShipDescription += ExpandKeyWith("shipyard-forward-weapon-upgraded", "weapon", weapon ? oo::PList(*weapon) : oo::PList());
			}
			if (price > base_price)
			{
				price = base_price + cunningFee(price - base_price, 0.05);
			}

			shortShipDescription += ExpandKeyWith("shipyard-price", "price", oo::PList(price));

			std::string shipID = oo::str::format("%06x-%06x", superRand1, superRand2);

			uint16_t personality = RanrotWithSeed(&personalitySeed) & ENTITY_PERSONALITY_MAX;

			oo::PList::Dict ship_info_dictionary;
			ship_info_dictionary[std::string(SHIPYARD_KEY_ID)] = oo::PList(shipID);
			ship_info_dictionary[std::string(SHIPYARD_KEY_SHIPDATA_KEY)] = oo::PList(ship_key);
			ship_info_dictionary[std::string(SHIPYARD_KEY_SHIP)] = shipDict;
			ship_info_dictionary[std::string(KEY_SHORT_DESCRIPTION)] = oo::PList(shortShipDescription);
			ship_info_dictionary[std::string(SHIPYARD_KEY_PRICE)] = oo::PList(price);
			ship_info_dictionary[std::string(KEY_EQUIPMENT_EXTRAS)] = oo::PList(extras);
			ship_info_dictionary[std::string(SHIPYARD_KEY_PERSONALITY)] = oo::PList(personality);

			resultDictionary[shipID] = oo::PList(std::move(ship_info_dictionary));	// should order them fairly randomly
		}

		// next contract
		rotate_seed(&ship_seed);
		rotate_seed(&ship_seed);
		rotate_seed(&ship_seed);
		rotate_seed(&ship_seed);
	}

	oo::PList::Array resultArray;
	for (auto &entry : resultDictionary)  resultArray.push_back(std::move(entry.second));
	std::stable_sort(resultArray.begin(), resultArray.end(), [](const oo::PList &a, const oo::PList &b) { return compareName(a, b) < 0; });

	// remove identically priced ships of the same name
	i = 1;

	while (i < resultArray.size())
	{
		if (compareName(resultArray[i - 1], resultArray[i]) == 0)
		{
			resultArray.erase(resultArray.begin() + i);
		}
		else
		{
			i++;
		}
	}

	RANROTSetFullSeed(saved_seed);

	return oo::PList(std::move(resultArray));
}



// Slice 23 of docs/phases/3-slices/Universe.md (bead oo-ni1hw): trade-in value, brochure descriptions, witchspace exit and sun-skim positions, beacons by code, script events to all ships, the GUIs, FPS and autosave. The facade forwards
// each selector (until oo-ql9rn); sends to self were sends (ADR-0056 amendments oo-riqmz,
// oo-mvzmb).

OOCreditsQuantity Universe::tradeInValueForCommanderDictionary(const oo::PList &dict)
{
	// get basic information about the craft
	OOCreditsQuantity	base_price = 0ULL;
	std::optional<std::string>	ship_desc = OptionalStringIn(dict, "ship_desc");
	const oo::PList		shipyard_info = ship_desc.has_value() ? OOShipRegistry::sharedRegistry()->shipyardInfoForKey(*ship_desc) : oo::PList();
	// This checks a rare, but possible case. If the ship for which we are trying to calculate a trade in value
	// does not have a shipyard dictionary entry, report it and set its base price to 0 -- Nikos 20090613.
	if (shipyard_info.isNull())
	{
		OO_LOG_ERR("universe.tradeInValueForCommanderDictionary.valueCalculationError", "Shipyard dictionary entry for ship {} required for trade in value calculation, but does not exist. Setting ship value to 0.", ship_desc.value_or("(null)"));
	}
	else
	{
		base_price = shipyard_info.get<unsigned long long>(std::string(SHIPYARD_KEY_PRICE), 0ULL);
	}

	if(base_price == 0ULL) return base_price;

	// A missing key was priced as nothing ([UNIVERSE getEquipmentPriceForKey:nil]).
	auto priceOf = [](const std::optional<std::string> &key) -> OOCreditsQuantity
	{
		return key.has_value() ? (UNIVERSE != nullptr ? UNIVERSE->getEquipmentPriceForKey(*key) : 0) : 0;
	};

	OOCreditsQuantity	scrap_value = 351; // translates to 250 cr.

	auto weaponTypeForKey = [&dict](const char *key) -> OOWeaponType	// nil for a missing key
	{
		const std::optional<std::string> identifier = OptionalStringIn(dict, key);
		return identifier.has_value() ? OOEquipmentType::equipmentTypeWithIdentifier(*identifier).get() : nil;
	};
	OOWeaponType		ship_fwd_weapon = weaponTypeForKey("forward_weapon");
	OOWeaponType		ship_aft_weapon = weaponTypeForKey("aft_weapon");
	OOWeaponType		ship_port_weapon = weaponTypeForKey("port_weapon");
	OOWeaponType		ship_starboard_weapon = weaponTypeForKey("starboard_weapon");
	unsigned			ship_missiles = dict.get<unsigned int>("missiles");
	unsigned			ship_max_passengers = dict.get<unsigned int>("max_passengers");
	std::vector<std::string>	ship_extra_equipment;
	if (const oo::PList *extraEquipment = dict.get<oo::PList::Dict>("extra_equipment"))
	{
		for (const auto &entry : *extraEquipment->getIf<oo::PList::Dict>())  ship_extra_equipment.push_back(entry.first);
	}

	const oo::PList		*basicInfoEntry = shipyard_info.get<oo::PList::Dict>(std::string(KEY_STANDARD_EQUIPMENT));
	const oo::PList		basic_info = (basicInfoEntry != nullptr) ? *basicInfoEntry : oo::PList();
	unsigned			base_missiles = basic_info.get<unsigned int>(std::string(KEY_EQUIPMENT_MISSILES));
	OOCreditsQuantity	base_missiles_value = base_missiles * (UNIVERSE != nullptr ? UNIVERSE->getEquipmentPriceForKey("EQ_MISSILE") : 0) / 10;
	std::optional<std::string>	base_weapon_key = OptionalStringIn(basic_info, std::string(KEY_EQUIPMENT_FORWARD_WEAPON));
	OOCreditsQuantity	base_weapons_value = priceOf(base_weapon_key) / 10;
	std::vector<std::optional<std::string>>	base_extra_equipment;
	if (const oo::PList *baseExtras = basic_info.get<oo::PList::Array>(std::string(KEY_EQUIPMENT_EXTRAS)))
	{
		for (std::size_t k = 0; k < baseExtras->count(); k++)  base_extra_equipment.push_back(OptionalStringAt(*baseExtras, k));
	}
	std::string			weapon_key;

	// was aft_weapon defined as standard equipment ?
	base_weapon_key = OptionalStringIn(basic_info, std::string(KEY_EQUIPMENT_AFT_WEAPON));
	if (base_weapon_key.has_value())
		base_weapons_value += priceOf(base_weapon_key) / 10;

	OOCreditsQuantity	ship_main_weapons_value = 0;
	OOCreditsQuantity	ship_other_weapons_value = 0;
	OOCreditsQuantity	ship_missiles_value = 0;

	// calculate the actual value for the missiles present on board.
	const oo::PList *missileRoles = dict.get<oo::PList::Array>("missile_roles");
	if (missileRoles != nullptr)
	{
		unsigned i;
		for (i = 0; i < ship_missiles; i++)
		{
			std::optional<std::string> missile_desc = OptionalStringAt(*missileRoles, i);
			if (missile_desc.has_value() && *missile_desc != "NONE")
			{
				ship_missiles_value += (UNIVERSE != nullptr ? UNIVERSE->getEquipmentPriceForKey(*missile_desc) : 0) / 10;
			}
		}
	}
	else
		ship_missiles_value = ship_missiles * (UNIVERSE != nullptr ? UNIVERSE->getEquipmentPriceForKey("EQ_MISSILE") : 0) / 10;

	// needs to be a signed value, we can then subtract from the base price, if less than standard equipment.
	long long extra_equipment_value = ship_max_passengers * (UNIVERSE != nullptr ? UNIVERSE->getEquipmentPriceForKey("EQ_PASSENGER_BERTH") : 0)/10;

	// add on missile values
	extra_equipment_value += ship_missiles_value - base_missiles_value;

	// work out weapon values
	if (ship_fwd_weapon)
	{
		weapon_key = cxx_OOEquipmentIdentifierFromWeaponType(ship_fwd_weapon).value_or("");
		ship_main_weapons_value = (UNIVERSE != nullptr ? UNIVERSE->getEquipmentPriceForKey(weapon_key) : 0) / 10;
	}
	if (ship_aft_weapon)
	{
		weapon_key = cxx_OOEquipmentIdentifierFromWeaponType(ship_aft_weapon).value_or("");
		if (base_weapon_key.has_value()) // aft weapon was defined as a base weapon
		{
			ship_main_weapons_value += (UNIVERSE != nullptr ? UNIVERSE->getEquipmentPriceForKey(weapon_key) : 0) / 10;	//take weapon downgrades into account
		}
		else
		{
			ship_other_weapons_value += (UNIVERSE != nullptr ? UNIVERSE->getEquipmentPriceForKey(weapon_key) : 0) / 10;
		}
	}
	if (ship_port_weapon)
	{
		weapon_key = cxx_OOEquipmentIdentifierFromWeaponType(ship_port_weapon).value_or("");
		ship_other_weapons_value += (UNIVERSE != nullptr ? UNIVERSE->getEquipmentPriceForKey(weapon_key) : 0) / 10;
	}
	if (ship_starboard_weapon)
	{
		weapon_key = cxx_OOEquipmentIdentifierFromWeaponType(ship_starboard_weapon).value_or("");
		ship_other_weapons_value += (UNIVERSE != nullptr ? UNIVERSE->getEquipmentPriceForKey(weapon_key) : 0) / 10;
	}

	// add on extra weapons, take away the value of the base weapons
	extra_equipment_value += ship_other_weapons_value;
	extra_equipment_value += ship_main_weapons_value - base_weapons_value;

	NSInteger i;
	std::optional<std::string> eq_key;

	// shipyard.plist settings might have duplicate keys.
	// cull possible duplicates from inside base equipment
	// (the search range 0..i-2, as NSMakeRange(0, i-1) gave it, never looks at the entry just before)
	for (i = (NSInteger)base_extra_equipment.size()-1; i > 0;i--)
	{
		eq_key = base_extra_equipment[i];
		const auto searchEnd = base_extra_equipment.begin() + (i - 1);
		if (eq_key.has_value() && std::find(base_extra_equipment.begin(), searchEnd, eq_key) != searchEnd)
								base_extra_equipment.erase(base_extra_equipment.begin() + i);
	}

	// do we at least have the same equipment as a standard ship?
	for (i = (NSInteger)base_extra_equipment.size()-1; i >= 0; i--)
	{
		eq_key = base_extra_equipment[i];
		if (eq_key.has_value() && std::find(ship_extra_equipment.begin(), ship_extra_equipment.end(), *eq_key) != ship_extra_equipment.end())
				std::erase(ship_extra_equipment, *eq_key);
		else // if the ship has less equipment than standard, deduct the missing equipent's price
				extra_equipment_value -= (priceOf(eq_key) / 10);
	}

	// remove portable equipment from the totals
	::OOEquipmentType	*item = nil;

	for (i = (NSInteger)ship_extra_equipment.size()-1; i >= 0; i--)
	{
		item = OOEquipmentType::equipmentTypeWithIdentifier(ship_extra_equipment[i]).get();
		if ((item != nullptr ? item->isPortableBetweenShips() : false)) ship_extra_equipment.erase(ship_extra_equipment.begin() + i);
	}

	// add up what we've got left.
	for (i = (NSInteger)ship_extra_equipment.size()-1; i >= 0; i--)
		extra_equipment_value += ((UNIVERSE != nullptr ? UNIVERSE->getEquipmentPriceForKey(ship_extra_equipment[i]) : 0) / 10);

	// 10% discount for second hand value, steeper reduction if worse than standard.
	extra_equipment_value *= extra_equipment_value < 0 ? 1.4 : 0.9;

	// we'll return at least the scrap value
	// TODO: calculate scrap value based on the size of the ship.
	if ((long long)scrap_value > (long long)base_price + extra_equipment_value) return scrap_value;

	return base_price + extra_equipment_value;
}


std::optional<std::string> Universe::brochureDescriptionWithDictionary(const oo::PList &dict, const std::vector<std::string> &extras, const std::vector<std::string> &options)
{
	std::vector<std::string>	mut_extras = extras;
	std::string		allOptions;
	for (std::size_t k = 0; k < options.size(); k++)
	{
		if (k > 0)  allOptions += " ";
		allOptions += options[k];
	}

	std::string		desc = "The " + TextOrNull(OptionalStringIn(dict, std::string(KEY_NAME))) + ".";

	// cargo capacity and expansion
	OOCargoQuantity	max_cargo = dict.get<unsigned int>("max_cargo");
	if (max_cargo)
	{
		OOCargoQuantity	extra_cargo = dict.get<unsigned int>("extra_cargo", 15);
		desc += oo::str::format(" Cargo capacity %dt", max_cargo);
		BOOL canExpand = (allOptions.find("EQ_CARGO_BAY") != std::string::npos);
		if (canExpand)
			desc += oo::str::format(" (expandable to %dt at most starports)", max_cargo + extra_cargo);
		desc += ".";
	}

	// speed
	float top_speed = dict.get<int>("max_flight_speed");
	desc += oo::str::format(" Top speed %.3fLS.", 0.001 * top_speed);

	// passenger berths
	if (mut_extras.size())
	{
		unsigned n_berths = 0;
		unsigned i;
		for (i = 0; i < mut_extras.size(); i++)
		{
			if (mut_extras[i] == "EQ_PASSENGER_BERTH")
			{
				n_berths++;
				mut_extras.erase(mut_extras.begin() + i--);
			}
		}
		if (n_berths)
		{
			if (n_berths == 1)
				desc += " Includes luxury accomodation for a single passenger.";
			else
				desc += oo::str::format(" Includes luxury accomodation for %d passengers.", n_berths);
		}
	}

	// standard fittings
	if (mut_extras.size())
	{
		desc += "\nComes with";
		unsigned i, j;
		for (i = 0; i < mut_extras.size(); i++)
		{
			const std::string &item_key = mut_extras[i];
			std::optional<std::string> item_desc;
			for (j = 0; ((j < equipmentData.count())&&(!item_desc)) ; j++)
			{
				std::optional<std::string> eq_type = EquipmentItemString(equipmentData, j, EQUIPMENT_KEY_INDEX);
				if (eq_type == item_key)
					item_desc = EquipmentItemString(equipmentData, j, EQUIPMENT_SHORT_DESC_INDEX);
			}
			if (item_desc)
			{
				switch (mut_extras.size() - i)
				{
					case 1:
						desc += " " + *item_desc + " fitted as standard.";
						break;
					case 2:
						desc += " " + *item_desc + " and";
						break;
					default:
						desc += " " + *item_desc + ",";
						break;
				}
			}
		}
	}

	// optional fittings
	if (options.size())
	{
		desc += "\nCan additionally be outfitted with";
		unsigned i, j;
		for (i = 0; i < options.size(); i++)
		{
			const std::string &item_key = options[i];
			std::optional<std::string> item_desc;
			for (j = 0; ((j < equipmentData.count())&&(!item_desc)) ; j++)
			{
				std::optional<std::string> eq_type = EquipmentItemString(equipmentData, j, EQUIPMENT_KEY_INDEX);
				if (eq_type == item_key)
					item_desc = EquipmentItemString(equipmentData, j, EQUIPMENT_SHORT_DESC_INDEX);
			}
			if (item_desc)
			{
				switch (options.size() - i)
				{
					case 1:
						desc += " " + *item_desc + " at suitably equipped starports.";
						break;
					case 2:
						desc += " " + *item_desc + " and/or";
						break;
					default:
						desc += " " + *item_desc + ",";
						break;
				}
			}
		}
	}

	return desc;
}


HPVector Universe::getWitchspaceExitPosition()
{
	return kZeroHPVector;
}


Quaternion Universe::getWitchspaceExitRotation()
{
	// this should be fairly close to {0,0,0,1}
	Quaternion q_result;

// CIM: seems to be no reason why this should be a per-system constant
//  - trying it without resetting the RNG for now
//	seed_RNG_only_for_planet_description(system_seed);
	
	q_result.x = (gen_rnd_number() - 128)/1024.0;
	q_result.y = (gen_rnd_number() - 128)/1024.0;
	q_result.z = (gen_rnd_number() - 128)/1024.0;
	q_result.w = 1.0;
	quaternion_normalize(&q_result);
	
	return q_result;
}


// FIXME: should use vector functions
HPVector Universe::getSunSkimStartPositionForShip(::ShipEntity *ship)
{
	if (!ship)
	{
		OO_LOG(cxx_kOOLogParameterError, "{}", "***** No ship set in Universe getSunSkimStartPositionForShip:");
		return kZeroHPVector;
	}
	::OOSunEntity* the_sun = sun();
	// get vector from sun position to ship
	if (!the_sun)
	{
		OO_LOG(cxx_kOOLogInconsistentState, "{}", "***** No sun set in Universe getSunSkimStartPositionForShip:");
		return kZeroHPVector;
	}
	HPVector v0 = the_sun->position;
	HPVector v1 = ship->position;
	v1.x -= v0.x;	v1.y -= v0.y;	v1.z -= v0.z;	// vector from sun to ship
	if (v1.x||v1.y||v1.z)
		v1 = HPvector_normal(v1);
	else
		v1.z = 1.0;
	double radius = SUN_SKIM_RADIUS_FACTOR * the_sun->collision_radius - 250.0; // 250 m inside the skim radius
	v1.x *= radius;	v1.y *= radius;	v1.z *= radius;
	v1.x += v0.x;	v1.y += v0.y;	v1.z += v0.z;
	
	return v1;
}


// FIXME: should use vector functions
HPVector Universe::getSunSkimEndPositionForShip(::ShipEntity *ship)
{
	::OOSunEntity* the_sun = sun();
	if (!ship)
	{
		OO_LOG(cxx_kOOLogParameterError, "{}", "***** No ship set in Universe getSunSkimEndPositionForShip:");
		return kZeroHPVector;
	}
	// get vector from sun position to ship
	if (!the_sun)
	{
		OO_LOG(cxx_kOOLogInconsistentState, "{}", "***** No sun set in Universe getSunSkimEndPositionForShip:");
		return kZeroHPVector;
	}
	HPVector v0 = the_sun->position;
	HPVector v1 = ship->position;
	v1.x -= v0.x;	v1.y -= v0.y;	v1.z -= v0.z;
	if (v1.x||v1.y||v1.z)
		v1 = HPvector_normal(v1);
	else
		v1.z = 1.0;
	double rx = randf()-0.5;	// one draw per local, in the order Clang evaluates the arguments (ADR-0063 item 5)
	double ry = randf()-0.5;
	double rz = randf()-0.5;
	HPVector v2 = make_HPvector(rx, ry, rz);	// random vector
	if (v2.x||v2.y||v2.z)
		v2 = HPvector_normal(v2);
	else
		v2.x = 1.0;
	HPVector v3 = HPcross_product(v1, v2);	// random vector at 90 degrees to v1 and v2 (random Vector)
	if (v3.x||v3.y||v3.z)
		v3 = HPvector_normal(v3);
	else
		v3.y = 1.0;
	double radius = SUN_SKIM_RADIUS_FACTOR * the_sun->collision_radius - 250.0; // 250 m inside the skim radius
	v1.x *= radius;	v1.y *= radius;	v1.z *= radius;
	v1.x += v0.x;	v1.y += v0.y;	v1.z += v0.z;
	v1.x += 15000 * v3.x;	v1.y += 15000 * v3.y;	v1.z += 15000 * v3.z;	// point 15000m at a tangent to sun from v1
	v1.x -= v0.x;	v1.y -= v0.y;	v1.z -= v0.z;
	if (v1.x||v1.y||v1.z)
		v1 = HPvector_normal(v1);
	else
		v1.z = 1.0;
	v1.x *= radius;	v1.y *= radius;	v1.z *= radius;
	v1.x += v0.x;	v1.y += v0.y;	v1.z += v0.z;
	
	return v1;
}


std::vector<oo::EntityHold> Universe::listBeaconsWithCode(const std::string &code)
{
	std::vector<oo::EntityHold>	result;	// held C++ entities (bead oo-9ht.39.26)
	Entity		*beacon = firstBeacon();

	while (beacon != nullptr)
	{
		const std::optional<std::string> beaconCode = oo::BeaconCode(beacon);
		if (BeaconCodeMatches(beaconCode, code))
		{
			result.emplace_back(beacon);
		}
		beacon = oo::NextBeacon(beacon);
	}

	// ORDER-SENSITIVE (decision D): beacons whose codes compare the same keep their list order.
	std::stable_sort(result.begin(), result.end(), [](const oo::EntityHold &a, const oo::EntityHold &b)
	{
		return oo::CompareBeaconCodes(a.get(), b.get()) == OOOrderedAscending;
	});
	return result;
}


void Universe::allShipsDoScriptEvent(ooscript::PropertyId event, const std::optional<std::string> &message)
{
	int i;
	int ent_count = n_entities;
	int ship_count = 0;
	std::vector<::ShipEntity*> my_ships(ent_count);
	for (i = 0; i < ent_count; i++)
	{
		if (sortedEntities[i]->isShip)
		{
			my_ships[ship_count++] = oo::ToShip(oo::RetainEntity(sortedEntities[i]));	// retained (its object)
		}
	}
	
	for (i = 0; i < ship_count; i++)
	{
		::ShipEntity* se = my_ships[i];
		if (se != nullptr)  se->doScriptEvent(event);
		if (message.has_value())  { if (se != nullptr && se->getAI() != nullptr)  se->getAI()->reactToMessage(*message, "global message"); }
		if (se != nullptr)  oo::ReleaseEntity(se); //	released
	}
}


///////////////////////////////////////

::GuiDisplayGen *Universe::getGui()
{
	return gui.get();
}


::GuiDisplayGen *Universe::commLogGUI()
{
	return comm_log_gui.get();
}


::GuiDisplayGen *Universe::messageGUI()
{
	return message_gui.get();
}


void Universe::clearGUIs()
{
	if (gui != nullptr)  gui->clear();	// messages to nil did nothing
	if (message_gui != nullptr)  message_gui->clear();
	if (comm_log_gui == nullptr)  return;
	comm_log_gui->clear();
	comm_log_gui->printLongText(OO_DESC("communications-log-string"), GUI_ALIGN_CENTER, OOColor::yellowColor().get(), 0, std::nullopt, nullptr);
}


void Universe::resetCommsLogColor()
{
	comm_log_gui->setTextColor(OOColor::whiteColor().get());
}


void Universe::setDisplayText(bool value)
{
	displayGUI = !!value;
}


bool Universe::getDisplayGUI()
{
	return displayGUI;
}


void Universe::setDisplayFPS(bool value)
{
	displayFPS = !!value;
}


bool Universe::getDisplayFPS()
{
	return displayFPS;
}


void Universe::setAutoSave(bool value)
{
	autoSave = !!value;
	oo::Defaults::standard().setBool("autosave", autoSave);
}


bool Universe::getAutoSave()
{
	return autoSave;
}


void Universe::setAutoSaveNow(bool value)
{
	autoSaveNow = !!value;
}



// Slice 24 of docs/phases/3-slices/Universe.md (bead oo-jxitg): autosave, wireframe and detail levels, shaders, exceptions, air resistance, speech (eSpeak and none), message logs, settings, cargo pods, session IDs. The facade forwards
// each selector (until oo-ql9rn); sends to self were sends (ADR-0056 amendments oo-riqmz,
// oo-mvzmb).

bool Universe::getAutoSaveNow()
{
	return autoSaveNow;
}


void Universe::setWireframeGraphics(bool value)
{
	wireframeGraphics = !!value;
	oo::Defaults::standard().setBool("wireframe-graphics", wireframeGraphics);
}


bool Universe::getWireframeGraphics()
{
	return wireframeGraphics;
}


bool Universe::reducedDetail()
{
	return detailLevel == DETAIL_LEVEL_MINIMUM;
}


/* Only to be called directly at initialisation */
void Universe::setDetailLevelDirectly(OOGraphicsDetail value)
{
	if (value >= DETAIL_LEVEL_MAXIMUM)
	{
		value = DETAIL_LEVEL_MAXIMUM;
	}
	else if (value <= DETAIL_LEVEL_MINIMUM)
	{
		value = DETAIL_LEVEL_MINIMUM;
	}
	if (!OOOpenGLExtensionManager::sharedManager()->shadersSupported())
	{
		value = DETAIL_LEVEL_MINIMUM;
	}
	detailLevel = value;
}


void Universe::setDetailLevel(OOGraphicsDetail value)
{
	OOGraphicsDetail old = detailLevel;
	setDetailLevelDirectly(value);
	oo::Defaults::standard().setInteger("detailLevel", detailLevel);
	// if changed then reset graphics state
	// (some items now require this even if shader on/off mode unchanged)
	if (old != detailLevel)
	{
		OO_LOG("rendering.detail-level", "Detail level set to {}.", cxx_OOStringFromGraphicsDetail(detailLevel));
		::OOGraphicsResetManager::sharedManager()->resetGraphicsState();
	}

}


OOGraphicsDetail Universe::getDetailLevel()
{
	return detailLevel;
}


bool Universe::useShaders()
{
	return detailLevel >= DETAIL_LEVEL_SHADERS;
}


void Universe::handleOoliteException(const oo::Exception *exception)
{
	if (exception != nullptr)
	{
		const oo::CaughtOOException caught(exception);
		if (strcmp(caught.name(), OOLITE_EXCEPTION_FATAL) == 0)
		{
			::PlayerEntity *player = PLAYER;
			if (player != nullptr)  player->setStatus(STATUS_HANDLING_ERROR);
			
			OO_LOG(cxx_kOOLogException, "***** Handling Fatal : {} : {} *****", caught.name(), caught.reason());
			std::string exception_msg = oo::str::format("Exception : %s : %s Please take a screenshot and/or press esc or Q to quit.", caught.name(), caught.reason());
			addMessage(exception_msg, 30.0);
			if (gameController() != nullptr)  gameController()->setGamePaused(YES);
		}
		else
		{
			OO_LOG(cxx_kOOLogException, "***** Handling Non-fatal : {} : {} *****", caught.name(), caught.reason());
		}
	}
}


GLfloat Universe::getAirResistanceFactor()
{
	return airResistanceFactor;
}


void Universe::setAirResistanceFactor(GLfloat newFactor)
{
	airResistanceFactor = OOClamp_0_1_f(newFactor);
}


// The speech arms. The Mac's moved here from the facade's class body with its deletion (bead
// oo-ql9rn), bodies verbatim; it is not built (docs/phases/3-slices/Universe.md "mac-only"; Phase 5
// rewrites the Mac layer).
#if OOLITE_MAC_OS_X

void Universe::startSpeakingString(const std::string &text)
{
	[speechSynthesizer startSpeakingString:oo::NSStringFrom(oo::str::format("[[volm %.3f]]%s", 0.3333333f * OOSound::masterVolume(), text.c_str()))];
}


void Universe::stopSpeaking()
{
	if ([speechSynthesizer respondsToSelector:@selector(stopSpeakingAtBoundary:)])
	{
		[speechSynthesizer stopSpeakingAtBoundary:NSSpeechWordBoundary];
	}
	else
	{
		[speechSynthesizer stopSpeaking];
	}
}


bool Universe::isSpeaking()
{
	return [speechSynthesizer isSpeaking];
}

#elif OOLITE_ESPEAK

void Universe::startSpeakingString(const std::string &text)
{
	// the UTF-8 bytes of the text
	const char *stringToSay = text.c_str();
	espeak_Synth(stringToSay, strlen(stringToSay) + 1 /* inc. NULL */, 0, POS_CHARACTER, 0, espeakCHARS_UTF8 | espeakPHONEMES | espeakENDPAUSE, NULL, NULL);
}


void Universe::stopSpeaking()
{
	espeak_Cancel();
}


bool Universe::isSpeaking()
{
	return espeak_IsPlaying();
}


std::optional<std::string> Universe::voiceName(unsigned int index)
{
	if (index >= espeak_voice_count)
		return std::string("-");
	return std::string(espeak_voices[index]->name);
}


unsigned int Universe::voiceNumber(const std::string &name)
{
	const char *const label = name.c_str();

	// clang-tidy's own fixes (bugprone-inc-dec-in-conditions, bugprone-suspicious-string-compare),
	// as the line changed: the same search from the first voice (ADR-0056 amendment oo-7jhs5).
	unsigned int index = 0;
	while (espeak_voices[index] && strcmp (espeak_voices[index]->name, label) != 0)
		++index;
	return (index < espeak_voice_count) ? index : UINT_MAX;
}


unsigned int Universe::nextVoice(unsigned int index)
{
	if (++index >= espeak_voice_count)
		index = 0;
	return index;
}


unsigned int Universe::prevVoice(unsigned int index)
{
	if (--index >= espeak_voice_count)
		index = espeak_voice_count - 1;
	return index;
}


unsigned int Universe::setVoice(unsigned int index, bool isMale)
{
	if (index == UINT_MAX)
		index = voiceNumber(cxx_OOLookUpDescriptionPRIV("espeak-default-voice"));

	if (index < espeak_voice_count)
	{
		espeak_VOICE voice = { espeak_voices[index]->name, NULL, NULL, (unsigned char)(isMale ? 1 : 2), 0, 0, 0, 0, NULL };
		espeak_SetVoiceByProperties (&voice);
	}

	return index;
}

#else

void Universe::startSpeakingString(const std::string & /*text*/)  {}

void Universe::stopSpeaking() {}

bool Universe::isSpeaking()
{
	return NO;
}
#endif


bool Universe::pauseMessageVisible()
{
	return _pauseMessage;
}


void Universe::setPauseMessageVisible(bool value)
{
	_pauseMessage = value;
}


bool Universe::permanentMessageLog()
{
	return _permanentMessageLog;
}


void Universe::setPermanentMessageLog(bool value)
{
	_permanentMessageLog = value;
}


bool Universe::autoMessageLogBg()
{
	return _autoMessageLogBg;
}


void Universe::setAutoMessageLogBg(bool value)
{
	_autoMessageLogBg = !!value;
}


bool Universe::permanentCommLog()
{
	return _permanentCommLog;
}


void Universe::setPermanentCommLog(bool value)
{
	_permanentCommLog = value;
}


void Universe::setAutoCommLog(bool value)
{
	_autoCommLog = value;
}


bool Universe::blockJSPlayerShipProps()
{
	return gOOJSPlayerIfStale != nullptr;
}


void Universe::setBlockJSPlayerShipProps(bool value)
{
	if (value)
	{
		gOOJSPlayerIfStale = PLAYER;
	}
	else
	{
		gOOJSPlayerIfStale = nullptr;
	}
}


void Universe::setUpSettings()
{
	resetBeacons();
	
	next_universal_id = 100;	// start arbitrarily above zero
	memset(entity_for_uid, 0, sizeof entity_for_uid);
	
	setMainLightPosition(kZeroVector);

	replacedGuis.clear();
	if (gui)  replacedGuis.push_back(gui);	// [gui autorelease]
	gui = oo::makeRef<GuiDisplayGen>();
	const oo::PList guiSettings = gui->userSettings();
	const oo::PList *defaultTextColor = guiSettings.find(cxx_kGuiDefaultTextColor);
	gui->setTextColor(OOColor::colorWithDescription((defaultTextColor != nullptr) ? *defaultTextColor : oo::PList()).get());

	// message_gui and comm_log_gui defaults are set up inside [hud resetGuis:] ( via [player deferredInit], called from the code that calls this method). 
	if (message_gui)  replacedGuis.push_back(message_gui);	// [message_gui autorelease]
	message_gui = oo::makeRef<GuiDisplayGen>(NSMakeSize(480, 160),
							  1,	// columns
							  9,	// rows
							  19,	// rowHeight
							  20,	// rowStart
							  std::nullopt);	// title
	
	if (comm_log_gui)  replacedGuis.push_back(comm_log_gui);	// [comm_log_gui autorelease]
	comm_log_gui = oo::makeRef<GuiDisplayGen>(NSMakeSize(360, 120),
							  1,	// columns
							  10,	// rows
							  12,	// rowHeight
							  12,	// rowStart
							  std::nullopt);	// title
	
	//
	
	time_delta = 0.0;
#ifndef NDEBUG
	setTimeAccelerationFactor(TIME_ACCELERATION_FACTOR_DEFAULT);
#endif
	universal_time = 0.0;
	messageRepeatTime = 0.0;
	countdown_messageRepeatTime = 0.0;
	
#if OOLITE_SPEECH_SYNTH
	speechArray = ResourceManager::arrayFromFilesNamed("speech_pronunciation_guide.plist", std::string("Config"), YES);
#endif
	
	replacedCommodities = std::move(commodities);	// [commodities autorelease]
	commodities = oo::makeRef<OOCommodities>();

	
	loadDescriptions();
	
	characters = ResourceManager::dictionaryFromFilesNamed("characters.plist", std::string("Config"), YES);
	
	customSounds = ResourceManager::dictionaryFromFilesNamed("customsounds.plist", std::string("Config"), YES);
	
	globalSettings = ResourceManager::dictionaryFromFilesNamed("global-settings.plist", std::string("Config"), MERGE_SMART, YES);

	
	replacedSystemManager = std::move(systemManager);	// [systemManager autorelease]
	systemManager = ResourceManager::systemDescriptionManager();

	screenBackgrounds = ResourceManager::dictionaryFromFilesNamed("screenbackgrounds.plist", std::string("Config"), YES);

	// role-categories.plist and pirate-victim-roles.plist
	roleCategories = ResourceManager::roleCategoriesDictionary();
	
	autoAIMap = ResourceManager::dictionaryFromFilesNamed("autoAImap.plist", std::string("Config"), YES);
	
	// ORDER-SENSITIVE: std::stable_sort, so entries that compare equal keep their file order.
	const oo::PList equipmentTemp = ResourceManager::arrayFromFilesNamed("equipment.plist", std::string("Config"), YES);
	oo::PList::Array sortedEquipment;
	if (const oo::PList::Array *items = equipmentTemp.getIf<oo::PList::Array>())  sortedEquipment = *items;
	oo::PList::Array sortedOutfitting = sortedEquipment;
	std::stable_sort(sortedEquipment.begin(), sortedEquipment.end(), equipmentSort);
	std::stable_sort(sortedOutfitting.begin(), sortedOutfitting.end(), equipmentSortOutfitting);
	equipmentData = oo::PList(std::move(sortedEquipment));
	equipmentDataOutfitting = oo::PList(std::move(sortedOutfitting));
	
	OOEquipmentType::loadEquipment();

	explosionSettings = ResourceManager::dictionaryFromFilesNamed("explosions.plist", std::string("Config"), YES);

}


void Universe::setUpCargoPods()
{
	std::map<std::string, oo::EntityHold, std::less<>> tmp;
	for (const std::string &type : (commodities != nullptr ? commodities->goods() : std::vector<std::string>()))
	{
		::ShipEntity *container = newShipWithRole("oolite-template-cargopod");
		if (container != nullptr)  container->setScanClass(CLASS_CARGO);
		if (container != nullptr)  container->setCommodity(type, 1);
		if (container != nil)  { tmp[type] = oo::EntityHold(container);  oo::ReleaseEntity(container); }	// the +1 handed to the list; a nil container was an exception before
	}
	cargoPods = std::move(tmp);
}


void Universe::verifyEntitySessionIDs()
{
#ifndef NDEBUG
	std::vector<oo::EntityHold> badEntities;
	Entity *entity = nullptr;
	
	unsigned i;
	for (i = 0; i < n_entities; i++)
	{
		entity = sortedEntities[i];
		if (entity->sessionID() != _sessionID)
		{
			OO_LOG_ERR("universe.sessionIDs.verify.failed", "Invalid entity {} (came from session {}, current session is {}).", oo::EntityShortDescription(entity), static_cast<size_t>(entity->sessionID()), static_cast<size_t>(_sessionID));
			badEntities.emplace_back(entity);
		}
	}

	for (const oo::EntityHold &entry : badEntities)
	{
		removeEntity(entry.get());
	}
#endif
}



// Slice 25 of docs/phases/3-slices/Universe.md (bead oo-wmc72): reinitialising and the demo, the initial universe, random positions, removing entities, preloading sounds, wormhole population, graph dumps. The facade forwards
// each selector (until oo-ql9rn); sends to self were sends (ADR-0056 amendments oo-riqmz,
// oo-mvzmb).

// FIXME: needs less redundancy?
bool Universe::reinitAndShowDemo(bool showDemo)
{
	no_update = YES;
	::PlayerEntity* player = PLAYER;
	assert(player != nil);
	
	if (JSResetFlags != 0)	// JS reset failed, remember previous settings 
	{
		showDemo = (JSResetFlags & 2) > 0;	// binary 10, a.k.a. 1 << 1
	}
	else
	{
		JSResetFlags = (showDemo << 1);
	}
	
	removeAllEntitiesExceptPlayer();
	OOTexture::clearCache();
	
	_sessionID++;	// Must be after removing old entities and before adding new ones.
	
	ResourceManager::setUseAddOns(useAddOns);	// also logs the paths
	//ResourceManager::loadScripts(); // initialised inside [player setUp]!
	
	// NOTE: Anything in the sharedCache is now trashed and must be
	//       reloaded. Ideally anything using the sharedCache should
	//       be aware of cache flushes so it can automatically
	//       reinitialize itself - mwerle 20081107.
	OOShipRegistry::reload();
	if (gameController() != nullptr)  gameController()->setGamePaused(NO);
	if (gameController() != nullptr)  gameController()->setMouseInteractionModeForUIWithMouseInteraction(NO);
	if (PLAYER != nullptr)  PLAYER->setSpeed(0.0);
	
	loadDescriptions();
	loadScenarios();
	
	missiontext = ResourceManager::dictionaryFromFilesNamed("missiontext.plist", std::string("Config"), YES);
	
	
	if(showDemo)
	{
		demo_ships = OOShipRegistry::sharedRegistry()->demoShipKeys();
		demo_ship_index = 0;
		demo_ship_subindex = 0;
	}
	
	breakPatternCounter = 0;
	
	cachedSun = nil;
	cachedPlanet = nil;
	cachedStation = nil;
	
	setUpSettings();

	// reset these in case OXP set has changed

	// set up cargopod templates
	setUpCargoPods();
	
	if (!(player != nullptr ? player->setUpAndConfirmOK(YES) : false)) 
	{
		// reinitAndShowDemo rescheduled inside setUpAndConfirmOK...
		return NO;	// Abort!
	}
	
	// we can forget the previous settings now.
	JSResetFlags = 0;
	
	addEntity(player);
	demo_ship = nil;
	if (gameController() != nullptr)  gameController()->setPlayerFileToLoad("");		// reset Quicksave
	
	setUpInitialUniverse();
	autoSaveNow = NO;	// don't autosave immediately after restarting a game
	
	if (station() != nullptr)  station()->initialiseLocalMarket();
	
	if(showDemo)
	{
		if (player != nullptr)  player->setStatus(STATUS_START_GAME);
		// re-read keyconfig.plist just in case we've loaded a keyboard
		// configuration expansion
		if (player != nullptr)  player->initControls();
	}
	else
	{
		if (player != nullptr)  player->setDockedAtMainStation();
	}
	
	if (player != nullptr)  player->completeSetUp();
	if(showDemo)
	{
		if (player != nullptr)  player->setGuiToIntroFirstGo(YES);
	}
	else
	{
		// no need to do these if showing the demo as the only way out
		// now is to load a game
		populateNormalSpace();

		if (player != nullptr)  player->startUpComplete();
	}

	if(!showDemo)
	{
		if (player != nullptr)  player->setGuiToStatusScreen();
		if (player != nullptr)  player->doWorldEventUntilMissionScreen(OOJSID("missionScreenOpportunity"));
	}
	
	verifyEntitySessionIDs();

	no_update = NO;
	return YES;
}


void Universe::setUpInitialUniverse()
{
	::PlayerEntity* player = PLAYER;
	
	OO_DEBUG_PUSH_PROGRESS("Wormhole and character reset");
	AutoreleaseAll(activeWormholes);	// the old list was autoreleased
	activeWormholes.reserve(16);
	replacedCharacterPool = std::move(characterPool);	// the old pool was autoreleased
	characterPool.clear();
	characterPool.reserve(256);
	OO_DEBUG_POP_PROGRESS();
	
	OO_DEBUG_PUSH_PROGRESS("Galaxy reset");
	setGalaxyTo((player != nullptr ? player->galaxyNumber() : OOGalaxyID{}), YES);
	systemID = (player != nullptr ? player->systemID() : 0);
	OO_DEBUG_POP_PROGRESS();
	
	OO_DEBUG_PUSH_PROGRESS("Player init: setUpShipFromDictionary");
	if (player != nullptr)  player->setUpShipFromDictionary(OOShipRegistry::sharedRegistry()->shipInfoForKey((player != nullptr ? player->shipDataKey() : std::optional<std::string>()).value_or(std::string())));	// the standard cobra at this point
	if (player != nullptr)  player->baseMass(); // bootstrap the base mass used in all fuel charge calculations.
	OO_DEBUG_POP_PROGRESS();
	
	// Player init above finishes initialising all standard player ship properties. Now that the base mass is set, we can run setUpSpace! 
	setUpSpace();
	
	setDockingClearanceProtocolActive(currentSystemData().get<bool>("stations_require_docking_clearance", YES));

	enterGUIViewModeWithMouseInteraction(NO);
	if (player != nullptr)  player->setPosition((station() != nullptr ? station()->getPosition() : HPVector{}));
	if (player != nullptr)  player->setOrientation(kIdentityQuaternion);
}


float Universe::randomDistanceWithinScanner()
{
	return SCANNER_MAX_RANGE * ((Ranrot() & 255) / 256.0 - 0.5);
}


Vector Universe::randomPlaceWithinScannerFrom(Vector pos, Vector route, double offset)
{
	pos.x += offset * route.x + randomDistanceWithinScanner();
	pos.y += offset * route.y + randomDistanceWithinScanner();
	pos.z += offset * route.z + randomDistanceWithinScanner();
	
	return pos;
}


HPVector Universe::fractionalPositionFrom(HPVector point0, HPVector point1, double routeFraction)
{
	if (routeFraction == static_cast<double>(NSNotFound)) routeFraction = randf();
	
	point1 = OOHPVectorInterpolate(point0, point1, routeFraction);
	
	point1.x += 2 * SCANNER_MAX_RANGE * (randf() - 0.5);
	point1.y += 2 * SCANNER_MAX_RANGE * (randf() - 0.5);
	point1.z += 2 * SCANNER_MAX_RANGE * (randf() - 0.5);
	
	return point1;
}


bool Universe::doRemoveEntity(Entity *entity)
{
	// remove reference to entity in linked lists
	if (entity->canCollide())	// filter only collidables disappearing
	{
		doLinkedListMaintenanceThisUpdate = YES;
	}
	
	entity->removeFromLinkedLists();
	
	// moved forward ^^
	// remove from the reference dictionary
	int old_id = entity->getUniversalID();
	entity_for_uid[old_id] = nil;
	entity->setUniversalID(NO_TARGET);
	entity->wasRemovedFromUniverse();
	
	// maintain sorted lists
	int index = entity->zero_index;
	
	int n = 1;
	if (index >= 0)
	{
		if (sortedEntities[index] != entity)
		{
			OO_LOG(cxx_kOOLogInconsistentState, "DEBUG: Universe removeEntity:{} ENTITY IS NOT IN THE RIGHT PLACE IN THE ZERO_DISTANCE SORTED LIST -- FIXING...", oo::EntityDescription(entity));
			unsigned i;
			index = -1;
			for (i = 0; (i < n_entities)&&(index == -1); i++)
				if (sortedEntities[i] == entity)
					index = i;
			if (index == -1)
				 OO_LOG(cxx_kOOLogInconsistentState, "DEBUG: Universe removeEntity:{} ENTITY IS NOT IN THE ZERO_DISTANCE SORTED LIST -- CONTINUING...", oo::EntityDescription(entity));
		}
		if (index != -1)
		{
			while ((unsigned)index < n_entities)
			{
				while (((unsigned)index + n < n_entities)&&(sortedEntities[index + n] == entity))
				{
					n++;	// ie there's a duplicate entry for this entity
				}
				
				/*
					BUG: when n_entities == UNIVERSE_MAX_ENTITIES, this read
					off the end of the array and copied n_entities, as an entity pointer, =
					0x800 into the list. The subsequent update of zero_index
					derferenced 0x800 and crashed.
					FIX: add an extra unused slot to sortedEntities, which is
					always nil.
					EFFICIENCY CONCERNS: this could have been an alignment
					issue since UNIVERSE_MAX_ENTITIES == 2048, but it isn't
					really. sortedEntities is part of the object, not malloced,
					it isn't aligned, and the end of it is only live in
					degenerate cases.
					-- Ahruman 2012-07-11
				*/
				sortedEntities[index] = sortedEntities[index + n];	// copy entity[index + n] -> entity[index] (preserves sort order)
				if (sortedEntities[index])
				{
					sortedEntities[index]->zero_index = index;				// give it its correct position
				}
				index++;
			}
			if (n > 1)
				 OO_LOG(cxx_kOOLogInconsistentState, "DEBUG: Universe removeEntity: REMOVED {} EXTRA COPIES OF {} FROM THE ZERO_DISTANCE SORTED LIST", n - 1, oo::EntityDescription(entity));
			while (n--)
			{
				n_entities--;
				sortedEntities[n_entities] = nil;
			}
		}
		entity->zero_index = -1;	// it's GONE!
	}
	
	// remove from the definitive list
	if (std::find(entities.begin(), entities.end(), entity) != entities.end())
	{
		// FIXME: better approach needed for core break patterns - CIM
		if (dynamic_cast<OOBreakPatternEntity *>(entity) != nullptr)
		{
			breakPatternCounter--;
		}
		
		if (oo::EntityIsShip(entity))
		{
			::ShipEntity *se = oo::ToShip(entity);
			clearBeacon(se);	// the C++ ship (bead oo-9ht.39.8.10)
		}
		if (entity->isWaypoint())
		{
			clearBeacon(entity);	// the C++ waypoint (bead oo-9ht.39.26)
		}
		if (entity->getIsVisualEffect())
		{
			clearBeacon(entity);	// the C++ effect (bead oo-9ht.39.26)
		}
		
		if (entity->getIsWormhole())
		{
			std::erase(activeWormholes, entity);
		}
		else if (oo::EntityIsPlanet(entity))
		{
			std::erase(allPlanets, entity);
		}

		std::erase(entities, entity);
		return YES;
	}
	
	return NO;
}


// ORDER-SENSITIVE (decision D): the keys in byte order (was the dictionary's hash order).
void Universe::preloadSounds()
{
	// Preload sounds to avoid loading stutter.
	if (const oo::PList::Dict *sounds = customSounds.getIf<oo::PList::Dict>())
	{
		for (const auto &[key, object] : *sounds)
		{
			if (object.isString())
			{
				PreloadOneSound(*object.getIf<std::string>());
			}
			else if (object.isArray() && object.count() > 0)
			{
				for (const oo::PList &soundName : *object.getIf<oo::PList::Array>())
				{
					if (soundName.isString())
					{
						PreloadOneSound(*soundName.getIf<std::string>());
					}
				}
			}
		}
	}

	// Afterburner sound doesn't go through customsounds.plist.
	PreloadOneSound("afterburner1.ogg");
}


void Universe::populateSpaceFromActiveWormholes()
{
	while (!activeWormholes.empty())
	{
		{
			oo::AutoreleaseScope pool;	// was @autoreleasepool (oo-31u.8)
			try
			{
				WormholeEntity* whole = static_cast<WormholeEntity *>(activeWormholes[0].get());
				// If the wormhole has been scanned by the player then the
				// PlayerEntity will take care of it
				if (!(whole != nullptr ? whole->isScanned() : false) &&
					NSEqualPoints((PLAYER != nullptr ? PLAYER->getGalaxy_coordinates() : NSPoint{}), (whole != nullptr ? whole->destinationCoordinates() : NSPoint{})) )
				{
					// this is a wormhole to this system
					if (whole != nullptr)  whole->disgorgeShips();
				}
				RemoveFirstWormhole(activeWormholes);	// empty it out
			}
			catch (...)
			{
				const auto exception = oo::CurrentOOException();
				if (!exception)  throw;	// not an OOException: it goes on up, as before
				OO_LOG(cxx_kOOLogException, "Squashing exception during wormhole unpickling ({}: {}).", exception->name(), exception->reason());
			}
		}
	}
}


std::optional<std::string> Universe::chooseStringForKey(const std::string &key, const oo::PList &dictionary)
{
	const oo::PList *object = dictionary.find(key);
	if (object == nullptr)  return std::nullopt;
	if (object->isString())  return *object->getIf<std::string>();
	else if (object->isArray() && object->count() > 0)  return OptionalStringAt(*object, Ranrot() % object->count());
	return std::nullopt;
}


#if OO_LOCALIZATION_TOOLS && DEBUG_GRAPHVIZ
void Universe::dumpDebugGraphViz()
{
	if (oo::Defaults::standard().boolForKey("universe-dump-debug-graphviz"))
	{
		dumpSystemDescriptionGraphViz();
	}
}


void Universe::dumpSystemDescriptionGraphViz()
{
	std::string					graphViz;
	const oo::PList				*systemDescriptions = nullptr;
	const oo::PList				*thisDesc = nullptr;
	NSUInteger					i, count, j, subCount;
	std::string					descLine;
	const oo::PList				*curses = nullptr;
	std::string					label;
	oo::PList					keyMap;

	keyMap = ResourceManager::dictionaryFromFilesNamed("sysdesc_key_table.plist", std::string("Config"), NO);

	graphViz = "// System description grammar:\n\n"
				"digraph system_descriptions\n"
				"{\n"
				"\tgraph [charset=\"UTF-8\", label=\"System description grammar\", labelloc=t, labeljust=l rankdir=LR compound=true nodesep=0.02 ranksep=1.5 concentrate=true fontname=Helvetica]\n"
				"\tedge [arrowhead=dot]\n"
				"\tnode [shape=none height=0.2 width=3 fontname=Helvetica]\n\t\n";

	systemDescriptions = descriptions()->get<oo::PList::Array>("system_description");
	count = (systemDescriptions != nullptr) ? systemDescriptions->count() : 0;

	// Add system-description-string as special node (it's the one thing that ties [14] to everything else).
	descLine = cxx_OOLookUpDescriptionPRIV("system-description-string");
	graphViz += oo::str::format("\tsystem_description_string [label=\"%s\" shape=ellipse]\n", StringifiedLabel(descLine, keyMap).c_str());
	addNumericRefsInString(descLine, graphViz, "system_description_string", count);
	graphViz += "\t\n";

	// Add special nodes for formatting codes
	graphViz +=
	 "\tpercent_I [label=\"%I\\nInhabitants\" shape=diamond]\n"
	 "\tpercent_H [label=\"%H\\nSystem name\" shape=diamond]\n"
	 "\tpercent_RN [label=\"%R/%N\\nRandom name\" shape=diamond]\n"
	 "\tpercent_J [label=\"%J\\nNumbered system name\" shape=diamond]\n"
	 "\tpercent_G [label=\"%G\\nNumbered system name in chart number\" shape=diamond]\n\t\n";

	// Toss in the Thargoid curses, too
	graphViz += "\tsubgraph cluster_thargoid_curses\n\t{\n\t\tlabel = \"Thargoid curses\"\n";
	curses = descriptions()->get<oo::PList::Array>("thargoid_curses");
	subCount = (curses != nullptr) ? curses->count() : 0;
	for (j = 0; j < subCount; ++j)
	{
		graphViz += oo::str::format("\t\tthargoid_curse_%zu [label=\"%s\"]\n", j, StringifiedLabel(OptionalStringAt(*curses, j), keyMap).c_str());
	}
	graphViz += "\t}\n";
	for (j = 0; j < subCount; ++j)
	{
		addNumericRefsInString(OptionalStringAt(*curses, j).value_or(std::string()), graphViz, oo::str::format("thargoid_curse_%zu", j), count);
	}
	graphViz += "\t\n";

	// The main show: the bits of systemDescriptions itself.
	// Define the nodes
	for (i = 0; i < count; ++i)
	{
		// Build label, using sysdesc_key_table.plist if available
		const oo::PList *keyLabel = keyMap.find(oo::str::format("%zu", i));
		if (keyLabel == nullptr)  label = oo::str::format("[%zu]", i);
		else  label = oo::str::format("[%zu] (%s)", i, oo::DescriptionOf(*keyLabel).c_str());

		graphViz += oo::str::format("\tsubgraph cluster_%zu\n\t{\n\t\tlabel=\"%s\"\n", i, cxx_EscapedGraphVizString(label).c_str());

		thisDesc = systemDescriptions->at<oo::PList::Array>(i);
		subCount = (thisDesc != nullptr) ? thisDesc->count() : 0;
		for (j = 0; j < subCount; ++j)
		{
			graphViz += oo::str::format("\t\tn%zu_%zu [label=\"\\\"%s\\\"\"]\n", i, j, StringifiedLabel(OptionalStringAt(*thisDesc, j), keyMap).c_str());
		}

		graphViz += "\t}\n";
	}
	graphViz += "\t\n";

	// Define the edges
	for (i = 0; i != count; ++i)
	{
		thisDesc = systemDescriptions->at<oo::PList::Array>(i);
		subCount = (thisDesc != nullptr) ? thisDesc->count() : 0;
		for (j = 0; j != subCount; ++j)
		{
			descLine = OptionalStringAt(*thisDesc, j).value_or(std::string());
			addNumericRefsInString(descLine, graphViz, oo::str::format("n%zu_%zu", i, j), count);
		}
	}

	// Write file
	graphViz += "\t}\n";
	ResourceManager::writeDiagnosticData(oo::Data(graphViz.data(), graphViz.size()), "SystemDescription.dot");
}
#endif



#if OO_LOCALIZATION_TOOLS
// Slice 26 of docs/phases/3-slices/Universe.md (bead oo-32kcu): graph-viz references, localisation tools, planet-material pruning, condition scripts, the custom-sound categories of OOSound and OOSoundSource, description look-ups. The facade forwards
// each selector (until oo-ql9rn); sends to self were sends (ADR-0056 amendments oo-riqmz,
// oo-mvzmb).

// A missing line is "" here (the old nil receiver answered zeroed ranges and never ended the scan).
void Universe::addNumericRefsInString(const std::string &string, std::string &graphViz, const std::string &fromNode, NSUInteger nodeCount)
{
	std::size_t					start, end, remaining = 0;
	unsigned					i;

	for (;;)
	{
		const std::size_t open = string.find('[', remaining);
		if (open == std::string::npos)  break;
		start = open + 1;
		remaining = start;

		const std::size_t close = string.find(']', remaining);
		if (close == std::string::npos)  break;
		end = close;
		remaining = end;

		const std::string index = string.substr(start, end - start);
		i = oo::str::intValue(index);

		// Each node gets a colour for its incoming edges. The multiplication and mod shuffle them to avoid adjacent nodes having similar colours.
		graphViz += oo::str::format("\t%s -> n%u_0 [color=\"%f,0.75,0.8\" lhead=cluster_%u]\n", fromNode.c_str(), i, ((float)(i * 511 % nodeCount)) / ((float)nodeCount), i);
	}

	if (string.find("%I") != std::string::npos)
	{
		graphViz += oo::str::format("\t%s -> percent_I [color=\"0,0,0.25\"]\n", fromNode.c_str());
	}
	if (string.find("%H") != std::string::npos)
	{
		graphViz += oo::str::format("\t%s -> percent_H [color=\"0,0,0.45\"]\n", fromNode.c_str());
	}
	if (string.find("%R") != std::string::npos || string.find("%N") != std::string::npos)
	{
		graphViz += oo::str::format("\t%s -> percent_RN [color=\"0,0,0.65\"]\n", fromNode.c_str());
	}

	// TODO: test graphViz output for "%Jxxx" and "%Gxxxxxx"
	if (string.find("%J") != std::string::npos)
	{
		graphViz += oo::str::format("\t%s -> percent_J [color=\"0,0,0.75\"]\n", fromNode.c_str());
	}

	if (string.find("%G") != std::string::npos)
	{
		graphViz += oo::str::format("\t%s -> percent_G [color=\"0,0,0.85\"]\n", fromNode.c_str());
	}
}


void Universe::runLocalizationTools()
{
	// Handle command line options to transform system_description array for easier localization
	
	BOOL				compileSysDesc = NO, exportSysDesc = NO, xml = NO;

	for (const std::string &arg : oo::process::arguments())
	{
		if (arg == "--compile-sysdesc")  compileSysDesc = YES;
		else if (arg == "--export-sysdesc")  exportSysDesc = YES;
		else if (arg == "--xml")  xml = YES;
		else if (arg == "--openstep")  xml = NO;
	}
	
	if (compileSysDesc)  CompileSystemDescriptions(xml);
	if (exportSysDesc)  ExportSystemDescriptions(xml);
}
#endif


// See notes at preloadPlanetTexturesForSystem:.
void Universe::prunePreloadingPlanetMaterials()
{
	OOAsyncWorkManager::sharedAsyncWorkManager()->completePendingTasks();
	
	NSUInteger i = _preloadingPlanetMaterials.size();
	while (i--)
	{
		if (_preloadingPlanetMaterials[i]->isFinishedLoading())
		{
			_preloadingPlanetMaterials.erase(_preloadingPlanetMaterials.begin() + i);
		}
	}
}


void Universe::loadConditionScripts()
{
	conditionScripts.clear();
	// get list of names from cache manager (arrays of script names)
	addConditionScripts(CachedConditionScripts("equipment conditions"));

	addConditionScripts(CachedConditionScripts("ship conditions"));

	addConditionScripts(CachedConditionScripts("demoship conditions"));
}


void Universe::addConditionScripts(const std::vector<std::string> &scripts)
{
	for (const std::string &scriptname : scripts)
	{
		if (!conditionScripts.contains(scriptname))
		{
			oo::Ref<OOScript> script = OOScript::jsScriptFromFileNamed(scriptname, oo::PList());
			if (script != nullptr)
			{
				conditionScripts[scriptname] = std::move(script);
			}
		}
	}
}


::OOScript *Universe::getConditionScript(const std::string &scriptname)
{
	const auto found = conditionScripts.find(scriptname);
	return (found != conditionScripts.end()) ? found->second.get() : nullptr;
}



// Slice 2 of docs/phases/3-slices/Universe.md (bead oo-27jxj): post-processing FX and colour-blind
// modes, the target framebuffer, start-up flags, add-ons, the entity list. The facade forwarded each
// selector (until oo-ql9rn); sends to self were sends (ADR-0056 amendment oo-27jxj).

bool Universe::bloom()
{
	return _bloom && getDetailLevel() >= DETAIL_LEVEL_EXTRAS;
}


void Universe::setBloom(bool newBloom)
{
	_bloom = !!newBloom;
}


int Universe::currentPostFX()
{
	return _currentPostFX;
}


void Universe::setCurrentPostFX(int newCurrentPostFX)
{
	if (newCurrentPostFX < 1 || newCurrentPostFX > OO_POSTFX_ENDOFLIST - 1)
	{
		newCurrentPostFX = OO_POSTFX_NONE;
	}
	
	if	(OO_POSTFX_NONE <= newCurrentPostFX && newCurrentPostFX <= OO_POSTFX_COLORBLINDNESS_TRITAN)
	{
		_colorblindMode = newCurrentPostFX;
	}		
	
	_currentPostFX = newCurrentPostFX;
}


void Universe::terminatePostFX(int postFX)
{
	if (currentPostFX() == postFX)
	{
		setCurrentPostFX(colorblindMode());
	}
}


int Universe::nextColorblindMode(int index)
{
	if (++index > OO_POSTFX_COLORBLINDNESS_TRITAN)
		index = OO_POSTFX_NONE;
	
	return index;
}


int Universe::prevColorblindMode(int index)
{
	if (--index < OO_POSTFX_NONE)
		index = OO_POSTFX_COLORBLINDNESS_TRITAN;
	
	return index;
}


int Universe::colorblindMode()
{
	return _colorblindMode;
}


void Universe::initTargetFramebufferWithViewSize(NSSize viewSize)
{
	// liberate us from the 0.0 to 1.0 rgb range!
	OOGL(glClampColor(GL_CLAMP_VERTEX_COLOR, GL_FALSE));
	OOGL(glClampColor(GL_CLAMP_READ_COLOR, GL_FALSE));
	OOGL(glClampColor(GL_CLAMP_FRAGMENT_COLOR, GL_FALSE));

	// have to do this because on my machine the default framebuffer is not zero
	OOGL(glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, &defaultDrawFBO));

	GLint previousProgramID;
	OOGL(glGetIntegerv(GL_CURRENT_PROGRAM, &previousProgramID));
	GLint previousTextureID;
	OOGL(glGetIntegerv(GL_TEXTURE_BINDING_2D, &previousTextureID));
	GLint previousVAO;
	OOGL(glGetIntegerv(GL_VERTEX_ARRAY_BINDING, &previousVAO));
	GLint previousArrayBuffer;
	OOGL(glGetIntegerv(GL_ARRAY_BUFFER_BINDING, &previousArrayBuffer));
	GLint previousElementBuffer;
	OOGL(glGetIntegerv(GL_ELEMENT_ARRAY_BUFFER_BINDING, &previousElementBuffer));

	// create MSAA framebuffer and attach MSAA texture and depth buffer to framebuffer
	OOGL(glGenFramebuffers(1, &msaaFramebufferID));
	OOGL(glBindFramebuffer(GL_FRAMEBUFFER, msaaFramebufferID));
	
	// creating MSAA texture that should be rendered into
	OOGL(glGenTextures(1, &msaaTextureID));
	OOGL(glBindTexture(GL_TEXTURE_2D_MULTISAMPLE, msaaTextureID));
	OOGL(glTexImage2DMultisample(GL_TEXTURE_2D_MULTISAMPLE, 4, GL_RGBA16F, (GLsizei)viewSize.width, (GLsizei)viewSize.height, GL_TRUE));
	OOGL(glBindTexture(GL_TEXTURE_2D_MULTISAMPLE, 0));
	OOGL(glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D_MULTISAMPLE, msaaTextureID, 0));
	
	// create necessary MSAA depth render buffer
	OOGL(glGenRenderbuffers(1, &msaaDepthBufferID));
	OOGL(glBindRenderbuffer(GL_RENDERBUFFER, msaaDepthBufferID));
	OOGL(glRenderbufferStorageMultisample(GL_RENDERBUFFER, 4, GL_DEPTH_COMPONENT32F, (GLsizei)viewSize.width, (GLsizei)viewSize.height));
	OOGL(glBindRenderbuffer(GL_RENDERBUFFER, 0));
	OOGL(glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, msaaDepthBufferID));
	
	if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE)
	{
		OO_LOG_ERR("initTargetFramebufferWithViewSize.result", "{}", "***** Error: Multisample framebuffer not complete");
	}
	
	// create framebuffer and attach texture and depth buffer to framebuffer
	OOGL(glGenFramebuffers(1, &targetFramebufferID));
	OOGL(glBindFramebuffer(GL_FRAMEBUFFER, targetFramebufferID));
	
	// creating texture that should be rendered into
	OOGL(glGenTextures(1, &targetTextureID));
	OOGL(glBindTexture(GL_TEXTURE_2D, targetTextureID));
	OOGL(glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA16F, (GLsizei)viewSize.width, (GLsizei)viewSize.height, 0, GL_RGBA, GL_FLOAT, NULL));
	OOGL(glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR));
	OOGL(glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR));
	OOGL(glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE));
	OOGL(glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE));
	OOGL(glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, targetTextureID, 0));
	
	// create necessary depth render buffer
	OOGL(glGenRenderbuffers(1, &targetDepthBufferID));
	OOGL(glBindRenderbuffer(GL_RENDERBUFFER, targetDepthBufferID));
	OOGL(glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH_COMPONENT32F, (GLsizei)viewSize.width, (GLsizei)viewSize.height));
	OOGL(glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, targetDepthBufferID));
	
	GLenum attachment[1] = { GL_COLOR_ATTACHMENT0 };
	OOGL(glDrawBuffers(1, attachment));
	
	if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE)
	{
		OO_LOG_ERR("initTargetFramebufferWithViewSize.result", "{}", "***** Error: Framebuffer not complete");
	}
	
	OOGL(glBindFramebuffer(GL_FRAMEBUFFER, defaultDrawFBO));
	
	targetFramebufferSize = viewSize;
	
	// passthrough buffer
	// This is a framebuffer whose sole purpose is to pass on the texture rendered from the game to the blur and the final bloom
	// shaders. We need it in order to be able to use the OpenGL 3.3 layout (location = x) out vec4 outVector; construct, which allows
	// us to perform multiple render target operations needed for bloom. The alternative would be to not use this and change all our
	// shaders to be OpenGL 3.3 compatible, but given how Oolite synthesizes them and the work needed to port them over, well yeah no,
	// not doing it at this time - Nikos 20220814.
	OOGL(glGenFramebuffers(1, &passthroughFramebufferID));
	OOGL(glBindFramebuffer(GL_FRAMEBUFFER, passthroughFramebufferID));
	
	// creating textures that should be rendered into
	OOGL(glGenTextures(2, passthroughTextureID));
	for (unsigned int i = 0; i < 2; i++)
	{
		OOGL(glBindTexture(GL_TEXTURE_2D, passthroughTextureID[i]));
		OOGL(glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA16F, (GLsizei)viewSize.width, (GLsizei)viewSize.height, 0, GL_RGBA, GL_FLOAT, NULL));
		OOGL(glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR));
		OOGL(glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR));
		OOGL(glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE));
		OOGL(glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE));
		OOGL(glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0 + i, GL_TEXTURE_2D, passthroughTextureID[i], 0));
	}
	
	GLenum attachments[2] = { GL_COLOR_ATTACHMENT0, GL_COLOR_ATTACHMENT1 };
	OOGL(glDrawBuffers(2, attachments));
	
	if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE)
	{
		OO_LOG_ERR("initTargetFramebufferWithViewSize.result", "{}", "***** Error: Passthrough framebuffer not complete");
	}
	OOGL(glBindFramebuffer(GL_FRAMEBUFFER, defaultDrawFBO));
	
	// ping-pong-framebuffer for blurring
    OOGL(glGenFramebuffers(2, pingpongFBO));
    OOGL(glGenTextures(2, pingpongColorbuffers));
    for (unsigned int i = 0; i < 2; i++)
    {
        OOGL(glBindFramebuffer(GL_FRAMEBUFFER, pingpongFBO[i]));
        OOGL(glBindTexture(GL_TEXTURE_2D, pingpongColorbuffers[i]));
        OOGL(glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA16F, (GLsizei)viewSize.width, (GLsizei)viewSize.height, 0, GL_RGBA, GL_FLOAT, NULL));
        OOGL(glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR));
        OOGL(glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR));
        OOGL(glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE)); // we clamp to the edge as the blur filter would otherwise sample repeated texture values!
        OOGL(glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE));
        OOGL(glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, pingpongColorbuffers[i], 0));
        // check if framebuffers are complete (no need for depth buffer)
        if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE)
		{
            OO_LOG_ERR("initTargetFramebufferWithViewSize.result", "{}", "***** Error: Pingpong framebuffers not complete");
		}
    }
	OOGL(glBindFramebuffer(GL_FRAMEBUFFER, defaultDrawFBO));
	
	_bloom = getDetailLevel() >= DETAIL_LEVEL_EXTRAS;
	_currentPostFX = _colorblindMode = OO_POSTFX_NONE;

	/* TODO (upstream; OOEnvironmentCubeMap.m was never built and was deleted as dead code, bead oo-v7ob,
	   decision oo-9wpwn - kept for a revival): in OOEnvironmentCubeMap.m call these bind functions not with 0 but with "previousXxxID"s:
	  - OOGL(glBindTexture(GL_TEXTURE_CUBE_MAP, 0));
	  - OOGL(glBindFramebufferEXT(GL_FRAMEBUFFER_EXT, 0));
	  - OOGL(glBindRenderbufferEXT(GL_RENDERBUFFER_EXT, 0));
	*/
	
	// shader for drawing a textured quad on the passthrough framebuffer and preparing it for bloom using MRT
	if (!OOOpenGLExtensionManager::sharedManager()->shadersForceDisabled())
	{
		textureProgram = OOShaderProgram::shaderProgramWithVertexShaderName("oolite-texture.vertex",
													"oolite-texture.fragment",
													"#version 330\n",
													oo::PList(oo::PList::Dict{}));
		// shader for blurring the over-threshold brightness image generated from the previous step using Gaussian filter
		blurProgram = OOShaderProgram::shaderProgramWithVertexShaderName("oolite-blur.vertex",
													"oolite-blur.fragment",
													"#version 330\n",
													oo::PList(oo::PList::Dict{}));
		// shader for applying bloom and any necessary post-proc fx, tonemapping and gamma correction
		finalProgram = OOShaderProgram::shaderProgramWithVertexShaderName("oolite-final.vertex",
#if OOLITE_WINDOWS
													(UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr ? UNIVERSE->getGameView()->hdrOutput() : false) ? "oolite-final-hdr.fragment" : "oolite-final.fragment",
#else
													"oolite-final.fragment",
#endif
													"#version 330\n",
													oo::PList(oo::PList::Dict{}));
	}
	
	OOGL(glGenVertexArrays(1, &quadTextureVAO));
	OOGL(glGenBuffers(1, &quadTextureVBO));
	OOGL(glGenBuffers(1, &quadTextureEBO));

	OOGL(glBindVertexArray(quadTextureVAO));

	OOGL(glBindBuffer(GL_ARRAY_BUFFER, quadTextureVBO));
	OOGL(glBufferData(GL_ARRAY_BUFFER, sizeof(framebufferQuadVertices), framebufferQuadVertices, GL_STATIC_DRAW));

	OOGL(glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, quadTextureEBO));
	OOGL(glBufferData(GL_ELEMENT_ARRAY_BUFFER, sizeof(framebufferQuadIndices), framebufferQuadIndices, GL_STATIC_DRAW));

	OOGL(glEnableVertexAttribArray(0));
	// position attribute
	OOGL(glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 4 * sizeof(float), (void*)0));
	OOGL(glEnableVertexAttribArray(1));
	// texture coord attribute
	OOGL(glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, 4 * sizeof(float), (void*)(2 * sizeof(float))));


	// restoring previous bindings
	OOGL(glUseProgram(previousProgramID));
	OOGL(glBindTexture(GL_TEXTURE_2D, previousTextureID));
	OOGL(glBindVertexArray(previousVAO));
	OOGL(glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, previousElementBuffer));
	OOGL(glBindBuffer(GL_ARRAY_BUFFER, previousArrayBuffer));

}


void Universe::deleteOpenGLObjects()
{
	OOGL(glDeleteTextures(1, &msaaTextureID));
	OOGL(glDeleteTextures(1, &targetTextureID));
	OOGL(glDeleteTextures(2, passthroughTextureID));
	OOGL(glDeleteTextures(2, pingpongColorbuffers));
	OOGL(glDeleteRenderbuffers(1, &msaaDepthBufferID));
	OOGL(glDeleteRenderbuffers(1, &targetDepthBufferID));
	OOGL(glDeleteFramebuffers(1, &msaaFramebufferID));
	OOGL(glDeleteFramebuffers(1, &targetFramebufferID));
	OOGL(glDeleteFramebuffers(2, pingpongFBO));
	OOGL(glDeleteFramebuffers(1, &passthroughFramebufferID));
	OOGL(glDeleteVertexArrays(1, &quadTextureVAO));
	OOGL(glDeleteBuffers(1, &quadTextureVBO));
	OOGL(glDeleteBuffers(1, &quadTextureEBO));
	textureProgram = nullptr;
	blurProgram = nullptr;
	finalProgram = nullptr;
}


void Universe::resizeTargetFramebufferWithViewSize(NSSize viewSize)
{
	int i;
	// resize MSAA color attachment
	OOGL(glBindTexture(GL_TEXTURE_2D_MULTISAMPLE, msaaTextureID));
	OOGL(glTexImage2DMultisample(GL_TEXTURE_2D_MULTISAMPLE, 4, GL_RGBA16F, (GLsizei)viewSize.width, (GLsizei)viewSize.height, GL_TRUE));
	OOGL(glBindTexture(GL_TEXTURE_2D_MULTISAMPLE, 0));
	
	// resize MSAA depth attachment
	OOGL(glBindRenderbuffer(GL_RENDERBUFFER, msaaDepthBufferID));
	OOGL(glRenderbufferStorageMultisample(GL_RENDERBUFFER, 4, GL_DEPTH_COMPONENT32F, (GLsizei)viewSize.width, (GLsizei)viewSize.height));
	OOGL(glBindRenderbuffer(GL_RENDERBUFFER, 0));
	
	// resize color attachments
	OOGL(glBindTexture(GL_TEXTURE_2D, targetTextureID));
	OOGL(glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA16F, (GLsizei)viewSize.width, (GLsizei)viewSize.height, 0, GL_RGBA, GL_FLOAT, NULL));
	OOGL(glBindTexture(GL_TEXTURE_2D, 0));
	
	for (i = 0; i < 2; i++)
	{
		OOGL(glBindTexture(GL_TEXTURE_2D, pingpongColorbuffers[i]));
		OOGL(glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA16F, (GLsizei)viewSize.width, (GLsizei)viewSize.height, 0, GL_RGBA, GL_FLOAT, NULL));
		OOGL(glBindTexture(GL_TEXTURE_2D, 0));
	}
	
	for (i = 0; i < 2; i++)
	{
		OOGL(glBindTexture(GL_TEXTURE_2D, passthroughTextureID[i]));
		OOGL(glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA16F, (GLsizei)viewSize.width, (GLsizei)viewSize.height, 0, GL_RGBA, GL_FLOAT, NULL));
		OOGL(glBindTexture(GL_TEXTURE_2D, 0));
	}
	
	// resize depth attachment
	OOGL(glBindRenderbuffer(GL_RENDERBUFFER, targetDepthBufferID));
	OOGL(glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH_COMPONENT32F, (GLsizei)viewSize.width, (GLsizei)viewSize.height));
	OOGL(glBindRenderbuffer(GL_RENDERBUFFER, 0));
	
	targetFramebufferSize.width = viewSize.width;
	targetFramebufferSize.height = viewSize.height;
}


void Universe::drawTargetTextureIntoDefaultFramebuffer()
{
	// save previous bindings state
	GLint previousFBO;
	OOGL(glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, &previousFBO));
	GLint previousProgramID;
	OOGL(glGetIntegerv(GL_CURRENT_PROGRAM, &previousProgramID));
	GLint previousTextureID;
	OOGL(glGetIntegerv(GL_TEXTURE_BINDING_2D, &previousTextureID));
	GLint previousVAO;
	OOGL(glGetIntegerv(GL_VERTEX_ARRAY_BINDING, &previousVAO));
	GLint previousActiveTexture;
	OOGL(glGetIntegerv(GL_ACTIVE_TEXTURE, &previousActiveTexture));	
	
	OOGL(glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT));
	// fixes transparency issue for some reason
	OOGL(glDisable(GL_BLEND));
	
	GLhandleARB program = textureProgram->program();
	GLhandleARB blur = blurProgram->program();
	GLhandleARB final = finalProgram->program();
	NSSize viewSize = (gameView != nullptr ? gameView->backingViewSize() : NSSize{});
	float fboResolution[2] = {(float)viewSize.width, (float)viewSize.height};

	OOGL(glBindFramebuffer(GL_FRAMEBUFFER, passthroughFramebufferID));
	OOGL(glClear(GL_COLOR_BUFFER_BIT));

	OOGL(glUseProgram(program));
	OOGL(glBindTexture(GL_TEXTURE_2D, targetTextureID));
	OOGL(glUniform1i(glGetUniformLocation(program, "image"), 0));
	
	
	OOGL(glBindVertexArray(quadTextureVAO));
	OOGL(glDrawElements(GL_TRIANGLES, 6, GL_UNSIGNED_INT, 0));
	OOGL(glBindVertexArray(0));
	
	OOGL(glBindFramebuffer(GL_FRAMEBUFFER, defaultDrawFBO));
	
		
	BOOL horizontal = YES, firstIteration = YES;
	unsigned int amount = bloom() ? 10 : 0; // if not blooming, why bother with the heavy calculations?
	OOGL(glUseProgram(blur));
	for (unsigned int i = 0; i < amount; i++)
	{
		OOGL(glBindFramebuffer(GL_FRAMEBUFFER, pingpongFBO[horizontal]));
		OOGL(glUniform1i(glGetUniformLocation(blur, "horizontal"), horizontal));
		OOGL(glActiveTexture(GL_TEXTURE0));
		// bind texture of other framebuffer (or scene if first iteration)
		OOGL(glBindTexture(GL_TEXTURE_2D, firstIteration ? passthroughTextureID[1] : pingpongColorbuffers[!horizontal]));  
		OOGL(glUniform1i(glGetUniformLocation(blurProgram->program(), "imageIn"), 0));
		OOGL(glBindVertexArray(quadTextureVAO));
		OOGL(glDrawElements(GL_TRIANGLES, 6, GL_UNSIGNED_INT, 0));
		OOGL(glBindVertexArray(0));
		horizontal = !horizontal;
		firstIteration = NO;
	}
	OOGL(glBindFramebuffer(GL_FRAMEBUFFER, defaultDrawFBO));
	
	
	OOGL(glUseProgram(final));

	OOGL(glActiveTexture(GL_TEXTURE0));
	OOGL(glBindTexture(GL_TEXTURE_2D, passthroughTextureID[0]));
	OOGL(glUniform1i(glGetUniformLocation(final, "scene"), 0));
	OOGL(glUniform1i(glGetUniformLocation(final, "bloom"), bloom()));
	OOGL(glUniform1f(glGetUniformLocation(final, "uTime"), getTime()));
	OOGL(glUniform2fv(glGetUniformLocation(final, "uResolution"), 1, fboResolution));
	OOGL(glUniform1i(glGetUniformLocation(final, "uPostFX"), currentPostFX()));
#if OOLITE_WINDOWS
	if((gameView != nullptr ? gameView->hdrOutput() : false))
	{
		OOGL(glUniform1f(glGetUniformLocation(final, "uMaxBrightness"), (gameView != nullptr ? gameView->hdrMaxBrightness() : 0.0f)));
		OOGL(glUniform1f(glGetUniformLocation(final, "uPaperWhiteBrightness"), (gameView != nullptr ? gameView->hdrPaperWhiteBrightness() : 0.0f)));
		OOGL(glUniform1i(glGetUniformLocation(final, "uHDRToneMapper"), (gameView != nullptr ? gameView->hdrToneMapper() : OOHDRToneMapper{})));
	}
#endif
	OOGL(glUniform1i(glGetUniformLocation(final, "uSDRToneMapper"), (gameView != nullptr ? gameView->sdrToneMapper() : OOSDRToneMapper{})));
	
	OOGL(glActiveTexture(GL_TEXTURE1));
	OOGL(glBindTexture(GL_TEXTURE_2D, pingpongColorbuffers[!horizontal]));
	OOGL(glUniform1i(glGetUniformLocation(final, "bloomBlur"), 1));
	OOGL(glUniform1f(glGetUniformLocation(final, "uSaturation"), (gameView != nullptr ? gameView->colorSaturation() : 0.0f)));
	
	OOGL(glBindVertexArray(quadTextureVAO));
	OOGL(glDrawElements(GL_TRIANGLES, 6, GL_UNSIGNED_INT, 0));
	
	// restore GL_TEXTURE1 to 0, just in case we are returning from a
	// DETAIL_LEVEL_NORMAL to DETAIL_LEVEL_SHADERS
	OOGL(glBindTexture(GL_TEXTURE_2D, 0));

	// restore previous bindings
	OOGL(glBindFramebuffer(GL_FRAMEBUFFER, previousFBO));
	OOGL(glActiveTexture(previousActiveTexture));
	OOGL(glBindTexture(GL_TEXTURE_2D, previousTextureID));
	OOGL(glUseProgram(previousProgramID));
	OOGL(glBindVertexArray(previousVAO));
	OOGL(glEnable(GL_BLEND));
}


NSUInteger Universe::sessionID()
{
	return _sessionID;
}


bool Universe::doingStartUp()
{
	return _doingStartUp;
}


bool Universe::getDoProcedurallyTexturedPlanets()
{
	return doProcedurallyTexturedPlanets;
}


void Universe::setDoProcedurallyTexturedPlanets(bool value)
{
	doProcedurallyTexturedPlanets = !!value;	// ensure yes or no
	oo::Defaults::standard().setBool("procedurally-textured-planets", doProcedurallyTexturedPlanets);
}


std::optional<std::string> Universe::getUseAddOns()
{
	return useAddOns;
}


bool Universe::setUseAddOns(const std::string &newUse, bool saveGame)
{
	return setUseAddOns(newUse, saveGame, NO);
}


bool Universe::setUseAddOns(const std::string &newUse, bool saveGame, bool force)
{
	if (!force && newUse == useAddOns)
	{
		return YES;
	}
	useAddOns = newUse;

	return reinitAndShowDemo(!saveGame);
}


NSUInteger Universe::entityCount()
{
	return entities.size();
}


#ifndef NDEBUG
void Universe::debugDumpEntities()
{
	int				i;
	int				show_count = n_entities;
	
	if (!oo::log::willDisplay("universe.objectDump"))  return;
	
	OO_LOG("universe.objectDump", "DEBUG: Entity Dump - [entities count] = {},\tn_entities = {}", static_cast<size_t>(entities.size()), static_cast<unsigned>(n_entities));
	
	OOLogIndent();
	for (i = 0; i < show_count; i++)
	{
		OO_LOG("universe.objectDump", "Ent:{:4}  {}", static_cast<unsigned>(i), sortedEntities[i]->descriptionForObjDump().value_or("(null)"));
	}
	OOLogOutdent();
	
	if (entities.size() != n_entities)
	{
		OO_LOG("universe.objectDump", "entities = {}", oo::DescriptionOf(oo::EntityNodesFrom(entities)));
	}
}


std::vector<oo::EntityHold> Universe::entityList()
{
	return entities;
}
#endif


