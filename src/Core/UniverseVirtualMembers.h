/*

UniverseVirtualMembers.h

The universe's virtual members (ADR-0056 amendment oo-ql9rn item 4): the members a whole-game
test's universe overrides, as the Objective-C subclasses of the deleted facade overrode their
selectors. They are declared once, here, in this order: Universe.h expands
OO_UNIVERSE_VIRTUAL_MEMBERS(;, ;) at the top of the class, and a narrow test's stand-in for the
class expands it with default bodies (tests/unit/core/UniverseStandIn.h), so the stand-in's vtable
has the same slots as the game's and a virtual call from the code under test reaches the test's
override. Add a member here only as a test seam; never reorder without rebuilding every test.

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

#ifndef UNIVERSE_VIRTUAL_MEMBERS_H
#define UNIVERSE_VIRTUAL_MEMBERS_H

#include "OOCocoa.h"
#include "OOMaths.h"
#include "OOTypes.h"
#include "oofnd/PList.hpp"
#include "OOEntityHold.h"	// owning entity references (bead oo-9ht.39.26)
#include "OOEntityEnums.h"	// OOScanClass
#include "OOSystemDescriptionManager.h"	// OOSystemLayer

#include <map>
#include <optional>
#include <string>
#include <vector>

class Entity;
class MyOpenGLView;
class StationEntity;
class OOPlanetEntity;
class OOSunEntity;
class GuiDisplayGen;
class Entity;
typedef BOOL (*EntityFilterPredicate)(Entity *entity, void *parameter);	// the C++ entity since bead oo-9ht.39.23


/*	VOID_BODY ends each member answering nothing, VALUE_BODY each member answering a value: ";"
	and ";" in the class, "{}" and "{ return {}; }" in a stand-in. The parameters are named in
	comments, so a stand-in's default bodies use none.
*/
#define OO_UNIVERSE_VIRTUAL_MEMBERS(VOID_BODY, VALUE_BODY) \
	/* Slice 5: lighting */ \
	virtual void setLighting() VOID_BODY \
	virtual void setMainLightPosition(Vector /*sunPos*/) VOID_BODY \
	/* Slice 7: role categories */ \
	virtual bool role(const std::string &/*role*/, const std::string &/*category*/) VALUE_BODY \
	/* Slice 8: the main station */ \
	virtual void unMagicMainStation() VOID_BODY \
	/* Slice 9: beacons, the sky colour, visual effects */ \
	virtual void setNextBeacon(Entity * /*beacon*/) VOID_BODY \
	virtual void clearBeacon(Entity * /*beacon*/) VOID_BODY \
	virtual void setSkyColorRed(GLfloat /*red*/, GLfloat /*green*/, GLfloat /*blue*/, GLfloat /*alpha*/) VOID_BODY \
	virtual Entity *newVisualEffectWithName(const std::string &/*effectKey*/) VALUE_BODY	/* the effect, its object +1 (bead oo-9ht.165) */ \
	/* Slice 10: cargo */ \
	virtual std::vector<oo::EntityHold> getContainersOfCommodity(const std::string &/*commodity_name*/, OOCargoQuantity /*how_much*/) VALUE_BODY \
	/* Slice 13: adding and removing entities */ \
	virtual bool addEntity(Entity * /**/) VALUE_BODY \
	virtual bool removeEntity(Entity * /**/) VALUE_BODY \
	/* Slice 14: routes */ \
	virtual Entity *hazardOnRouteFromEntity(Entity * /*e1*/, double /*dist*/, HPVector /*p2*/) VALUE_BODY \
	virtual HPVector getSafeVectorFromEntity(Entity * /*e1*/, double /*dist*/, HPVector /*p2*/) VALUE_BODY \
	/* Slice 15: finding entities */ \
	virtual std::vector<oo::EntityHold> findEntitiesMatchingPredicate(EntityFilterPredicate /*predicate*/, void * /*parameter*/, double /*range*/, Entity * /*e1*/) VALUE_BODY	/* the reference's C++ entity (bead oo-9ht.39.8.23) */ \
	/* Slice 20: system data and names */ \
	virtual oo::PList generateSystemData(OOSystemID /*s*/, bool /*useCache*/) VALUE_BODY \
	virtual void setSystemDataKey(const std::string &/*key*/, const oo::PList &/*value*/, const std::optional<std::string> &/*manifest*/) VOID_BODY \
	virtual std::optional<std::string> getSystemName(OOSystemID /*sys*/, OOGalaxyID /*gnum*/) VALUE_BODY \
	/* Slice 24: detail levels */ \
	virtual bool reducedDetail() VALUE_BODY \
	/* The whole-game JS tests' universes (test_OOJSSystem, test_OOJSPlayerShip, test_OOOXZManager) */ \
	virtual bool inInterstellarSpace() VALUE_BODY \
	virtual ::StationEntity *station() VALUE_BODY \
	virtual ::OOPlanetEntity *planet() VALUE_BODY \
	virtual ::OOSunEntity *sun() VALUE_BODY \
	virtual std::vector<oo::EntityHold> planets() VALUE_BODY \
	virtual std::vector<oo::EntityHold> stations() VALUE_BODY \
	virtual std::vector<oo::EntityHold> wormholes() VALUE_BODY \
	virtual std::map<std::string, oo::EntityHold, std::less<>> currentWaypoints() VALUE_BODY \
	virtual std::vector<oo::EntityHold> findShipsMatchingPredicate(EntityFilterPredicate /*predicate*/, void * /*parameter*/, double /*range*/, Entity * /**/) VALUE_BODY \
	virtual std::vector<oo::EntityHold> findVisualEffectsMatchingPredicate(EntityFilterPredicate /*predicate*/, void * /*parameter*/, double /*range*/, Entity * /**/) VALUE_BODY \
	virtual float getAmbientLightLevel() VALUE_BODY \
	virtual void setAmbientLightLevel(float /*newValue*/) VOID_BODY \
	virtual bool witchspaceBreakPattern() VALUE_BODY \
	virtual void setWitchspaceBreakPattern(bool /*newValue*/) VOID_BODY \
	virtual oo::PList getPopulatorSettings() VALUE_BODY \
	virtual oo::PList currentSystemData() VALUE_BODY \
	virtual const oo::PList *descriptions() VALUE_BODY \
	virtual std::optional<std::string> descriptionForKey(const std::string &/*key*/) VALUE_BODY \
	virtual void setSystemDataForGalaxy(OOGalaxyID /*gnum*/, OOSystemID /*pnum*/, const std::string &/*key*/, const oo::PList &/*value*/, const std::optional<std::string> &/*manifest*/, OOSystemLayer /*layer*/) VOID_BODY \
	virtual unsigned countShipsWithPrimaryRole(const std::string &/*role*/, double /*range*/, Entity * /*entity*/) VALUE_BODY \
	virtual unsigned countShipsWithRole(const std::string &/*role*/, double /*range*/, Entity * /*entity*/) VALUE_BODY \
	virtual unsigned countShipsWithScanClass(OOScanClass /*scanClass*/, double /*range*/, Entity * /*entity*/) VALUE_BODY \
	virtual HPVector locationByCode(const std::string &/*code*/, ::OOSunEntity * /*sun*/, ::OOPlanetEntity * /*planet*/) VALUE_BODY \
	virtual void witchspaceShipWithPrimaryRole(const std::string &/*role*/) VOID_BODY \
	virtual void addShipWithRole(const std::string &/*desc*/, double /*route_fraction*/) VOID_BODY \
	virtual bool spawnShip(const std::string &/*shipdesc*/) VALUE_BODY \
	virtual OOSystemID findSystemFromName(const std::string &/*sysName*/) VALUE_BODY \
	virtual Entity *addVisualEffectAt(HPVector /*pos*/, const std::string &/*key*/) VALUE_BODY \
	virtual void setPopulatorSetting(const std::string &/*key*/, const oo::PList &/*setting*/) VOID_BODY \
	virtual void defineWaypoint(const oo::PList &/*definition*/, const std::string &/*key*/) VOID_BODY \
	virtual HPVector getWitchspaceExitPosition() VALUE_BODY \
	virtual std::vector<oo::EntityHold> addShipsAt(HPVector /*pos*/, const std::string &/*role*/, unsigned /*count*/, GLfloat /*radius*/, bool /*isGroup*/) VALUE_BODY \
	virtual std::vector<oo::EntityHold> addShipsToRoute(const std::string &/*route*/, const std::string &/*role*/, unsigned /*count*/, double /*routeFraction*/, bool /*isGroup*/) VALUE_BODY \
	virtual OOViewID getViewDirection() VALUE_BODY \
	virtual ::GuiDisplayGen *messageGUI() VALUE_BODY \
	virtual OOCreditsQuantity tradeInValueForCommanderDictionary(const oo::PList &/*dict*/) VALUE_BODY \
	virtual ::GuiDisplayGen *getGui() VALUE_BODY \
	virtual void addMessage(const std::optional<std::string> &/*text*/, OOTimeDelta /*count*/) VOID_BODY \
	virtual ::MyOpenGLView *getGameView() VALUE_BODY \
	virtual ::OOSystemDescriptionManager *getSystemManager() VALUE_BODY \
	virtual bool reinitAndShowDemo(bool /*showDemo*/) VALUE_BODY

#endif	// UNIVERSE_VIRTUAL_MEMBERS_H
