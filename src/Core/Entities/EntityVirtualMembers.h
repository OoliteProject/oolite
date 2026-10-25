/*

EntityVirtualMembers.h

The root entity's virtual members (ADR-0056 amendment oo-9ht.39.8.21), as UniverseVirtualMembers.h
declares the universe's (amendment oo-ql9rn item 4): the members the converted subclasses (and the
Objective-C entities' adapter, oo::ObjCEntity) override. They are declared once, here, in the order
Entity.h declared them: Entity.h expands OO_ENTITY_VIRTUAL_MEMBERS(;, ;) and
OO_ENTITY_DEBUG_VIRTUAL_MEMBERS(;, ;) where its first virtual member was, and a narrow test's
stand-in for the class expands them with default bodies (tests/unit/core/EntityStandIn.h), so the
stand-in's vtable has the same slots as the game's and a virtual call from the code under test
reaches the test's override. Never reorder without rebuilding every test.

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

#ifndef ENTITY_VIRTUAL_MEMBERS_H
#define ENTITY_VIRTUAL_MEMBERS_H

#include "OOCocoa.h"
#include "OOMaths.h"
#include "OOTypes.h"
#include "OOEntityEnums.h"	// OOEntityStatus, OOScanClass
#include "ooscript/JSEngine.hpp"
#include "oofnd/Ref.hpp"
#include "OOTexture.h"	// allTextures() answers oo::Ref<OOTexture>

#include <optional>
#include <string>
#include <vector>

class ShipEntity;	// C++ since bead oo-9ht.144
class Entity;


/*	VOID_BODY ends each member answering nothing, VALUE_BODY each member answering a value: ";"
	and ";" in the class, "{}" and "{ return {}; }" in a stand-in. The parameters are named in
	comments, so a stand-in's default bodies use none. The three overrides of OOJSPrivateObject
	(the entity's JS glue) keep their place: the class and a stand-in derive from oo::RefCounted
	and ::OOJSPrivateObject, in that order.
*/
#define OO_ENTITY_VIRTUAL_MEMBERS(VOID_BODY, VALUE_BODY) \
	/* The session in which the entity was created. */ \
	virtual NSUInteger sessionID() VALUE_BODY \
	virtual bool isDock() VALUE_BODY \
	virtual bool isPlanet() VALUE_BODY \
	virtual bool isSun() VALUE_BODY \
	virtual bool isSky() VALUE_BODY \
	virtual bool isEffect() VALUE_BODY \
	virtual bool getIsVisualEffect() VALUE_BODY \
	virtual bool isWaypoint() VALUE_BODY \
	virtual bool validForAddToUniverse() VALUE_BODY \
	virtual void wasAddedToUniverse() VOID_BODY \
	virtual void wasRemovedFromUniverse() VOID_BODY \
	virtual void warnAboutHostiles() VOID_BODY \
	virtual void throwSparks() VOID_BODY \
	virtual void setOwner(Entity * /*ent*/) VOID_BODY \
	virtual void setPosition(HPVector /*posn*/) VOID_BODY \
	virtual GLfloat cameraRangeFront() VALUE_BODY \
	virtual GLfloat cameraRangeBack() VALUE_BODY \
	virtual void updateCameraRelativePosition() VOID_BODY \
	virtual OOComparisonResult compareZeroDistance(Entity * /*otherEntity*/) VALUE_BODY \
	virtual void setOrientation(Quaternion /*quat*/) VOID_BODY \
	/* Historical wart: orientation.w is reversed for player; normalOrientation() corrects this. */ \
	virtual Quaternion normalOrientation() VALUE_BODY \
	virtual void setNormalOrientation(Quaternion /*quat*/) VOID_BODY \
	virtual void orientationChanged() VOID_BODY \
	virtual Vector getVelocity() VALUE_BODY \
	virtual void setStatus(OOEntityStatus /*stat*/) VOID_BODY \
	virtual OOScanClass getScanClass() VALUE_BODY \
	virtual void applyRoll(GLfloat /*roll*/, GLfloat /*climb*/) VOID_BODY \
	virtual void applyRoll(GLfloat /*roll*/, GLfloat /*climb*/, GLfloat /*yaw*/) VOID_BODY \
	virtual void moveForward(double /*amount*/) VOID_BODY \
	virtual OOMatrix drawRotationMatrix() VALUE_BODY \
	virtual OOMatrix drawTransformationMatrix() VALUE_BODY \
	virtual bool canCollide() VALUE_BODY \
	virtual GLfloat collisionRadius() VALUE_BODY \
	virtual GLfloat frustumRadius() VALUE_BODY \
	virtual void update(OOTimeDelta /*delta_t*/) VOID_BODY \
	virtual bool checkCloseCollisionWith(Entity * /*other*/) VALUE_BODY \
	virtual void takeEnergyDamage(double /*amount*/, Entity * /*ent*/, Entity * /*other*/, const std::string &/*weaponIdentifier*/) VOID_BODY \
	/* Subclasses should override this, not dumpState(), and call through to the base first. */ \
	virtual void dumpSelfState() VOID_BODY \
	virtual void subEntityReallyDied(::ShipEntity * /*sub*/) VOID_BODY \
	/* Subclass responsibilities */ \
	virtual double findCollisionRadius() VALUE_BODY \
	virtual void drawImmediate(bool /*immediate*/, bool /*translucent*/) VOID_BODY \
	virtual bool isVisible() VALUE_BODY \
	/* What "%@" prints between the braces of <Class 0x...>{...} (OODescription.h). */ \
	virtual std::optional<std::string> descriptionComponents() const VALUE_BODY \
	/* Entity (OOJavaScriptExtensions)'s class questions (ADR-0056 amendment oo-9ht.107; Entity.h). */ \
	virtual void getJSClass(ooscript::ClassDef ** /*outClass*/, ooscript::Object * /*outPrototype*/) VOID_BODY \
	virtual std::optional<std::string> jsClassName() VALUE_BODY \
	virtual bool isVisibleToScripts() VALUE_BODY 	/* The Mac debug OXP's inspector's -inspect (the console's inspectEntity(); bead oo-dpyk8): nothing unless overridden. */ 	virtual void inspect() VOID_BODY \
	/* The entity's JS glue (OOJSPrivateObject, bead oo-9ht.39.3; Entity.h). */ \
	ooscript::Value jsValueInContext(ooscript::Context /*context*/) override VALUE_BODY \
	void clearJSSelf(ooscript::Object /*selfVal*/) override VOID_BODY \
	std::optional<std::string> jsDescription() override VALUE_BODY

#ifndef NDEBUG
#define OO_ENTITY_DEBUG_VIRTUAL_MEMBERS(VOID_BODY, VALUE_BODY) \
	virtual std::optional<std::string> descriptionForObjDump() VALUE_BODY \
	virtual std::vector<oo::Ref<OOTexture>> allTextures() VALUE_BODY
#else
#define OO_ENTITY_DEBUG_VIRTUAL_MEMBERS(VOID_BODY, VALUE_BODY)
#endif

#endif	// ENTITY_VIRTUAL_MEMBERS_H
