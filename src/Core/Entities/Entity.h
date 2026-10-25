/*

Entity.h

Base class for entities, i.e. drawable world objects.

C++20 since bead oo-bj8, the Entities pattern seam (proposed ADR-0056, amendment oo-bj8). The
Objective-C Entity facade (Entity+ObjCBridge.h) is deleted (bead oo-dpyk8, oo-9ht.39 step 5k.4): the
C++ entity is its own identity and owns itself (oo::RefCounted; its last release runs what the
facade's -dealloc ran, willDispose()). EntityHelpers.h, imported at the end of this header, keeps
the facade's questions. The class left namespace cxx with bead oo-9ht.39.29.

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


#pragma once

#include "OOCocoa.h"
#include "ooscript/JSEngine.hpp"
#include "OOMaths.h"
#include "OOCacheManager.h"
#include "OOTypes.h"
#include "oofnd/Ref.hpp"
#include "OOColor.h"
#include "CollisionRegion.h"
#include "oofnd/StdLib.hpp"
#include "oofnd/Ref.hpp"
#include "OOEntityHold.h"	// the owning entity lists (bead oo-xn1j1)
#include "OOJSPrivateObject.h"
#include "EntityVirtualMembers.h"	// the virtual members (bead oo-9ht.39.8.21)

class Entity;
class Universe;
#include "OOTexture.h"	// allTextures() answers oo::Ref<OOTexture>, which needs the class (bead oo-9ht.99)
class OOVisualEffectEntity;	// C++ since bead oo-9ht.165
class ShipEntity;	// C++ since bead oo-9ht.144


#ifndef NDEBUG

extern uint32_t gLiveEntityCount;
extern size_t gTotalEntityMemory;

#endif


#define NO_DRAW_DISTANCE_FACTOR		1024.0
#define ABSOLUTE_NO_DRAW_DISTANCE2	(2500.0 * 2500.0 * NO_DRAW_DISTANCE_FACTOR * NO_DRAW_DISTANCE_FACTOR)
// ie. the furthest away thing we can draw is at 1280km (a 2.5km wide object would disappear at that range)


#define SCANNER_MAX_RANGE			25600.0
#define SCANNER_MAX_RANGE2			655360000.0

#define CLOSE_COLLISION_CHECK_MAX_RANGE2 1000000000.0


// OOEntityStatus, OOScanClass and their defaults (bead oo-9ht.64: plain header).
#include "OOEntityEnums.h"


/*	The base object for ships, stations, anything actually.

	Data members that were @public or @protected ivars are public: the game reads them directly
	(ent->position), and Objective-C subclasses cannot be granted protected access to a C++
	class. A getter that had its ivar's name is get + the name (-position is getPosition(),
	amendment oo-862e), so the bodies, and the subclasses' reads, keep the names. The members
	that subclasses override are virtual (amendment oo-cwz item 2).
*/
class Entity : public oo::RefCounted, public ::OOJSPrivateObject
{
public:
	Entity();

	// -init's body: the constructor runs it, and the facade runs it again when an initialised
	// entity is sent -init (PlayerEntity's deferred initialisation). Only then does it re-run.
	void init();

	// The facade's -dealloc zeroed the weak references to the C++ part where it dropped its own
	// weak reference (bead oo-9ht.39.5.2); willDispose() does so at the same points.
	using oo::RefCounted::dropWeakReferences;

	/*	The entity's object (bead oo-dpyk8): it "has" one from the creator that made its facade
		(oo::MadeEntity(), oo::NewShipObject(), ...) until its last release begins, which is when
		oo::ToObjC() answered non-nil. Holds, retains, descriptions and nodes of an entity without
		one answer as nil's did (EntityHelpers.h, OOEntityHold.h).
	*/
	bool hasObject() const noexcept  { return _hasObject && !_disposing; }
	void setMadeWithObject() noexcept  { _hasObject = true; }	// the creators' (oo::MadeEntity())

	// What the facade's -dealloc ran before the C++ part went (bead oo-dpyk8), for an entity that
	// had its object: the last release runs it (oo::RefCounted::willDispose()).
	void willDispose() noexcept override;

	// The virtual members, declared once in EntityVirtualMembers.h in this order (bead oo-9ht.39.8.21),
	// so that a narrow test's stand-in for the class has the same vtable (tests/unit/core/EntityStandIn.h).
	OO_ENTITY_VIRTUAL_MEMBERS(;, ;)
	OO_ENTITY_DEBUG_VIRTUAL_MEMBERS(;, ;)

	// The session in which the entity was created.
	// sessionID(): virtual, in OO_ENTITY_VIRTUAL_MEMBERS (EntityVirtualMembers.h)

	bool getIsShip();
	// isDock(): virtual, in OO_ENTITY_VIRTUAL_MEMBERS (EntityVirtualMembers.h)
	bool getIsStation();
	bool getIsSubEntity();
	bool getIsPlayer();
	// isPlanet(): virtual, in OO_ENTITY_VIRTUAL_MEMBERS (EntityVirtualMembers.h)
	// isSun(): virtual, in OO_ENTITY_VIRTUAL_MEMBERS (EntityVirtualMembers.h)
	bool getIsSunlit();
	bool isStellarObject();
	// isSky(): virtual, in OO_ENTITY_VIRTUAL_MEMBERS (EntityVirtualMembers.h)
	bool getIsWormhole();
	// isEffect(): virtual, in OO_ENTITY_VIRTUAL_MEMBERS (EntityVirtualMembers.h)
	// getIsVisualEffect(): virtual, in OO_ENTITY_VIRTUAL_MEMBERS (EntityVirtualMembers.h)
	// isWaypoint(): virtual, in OO_ENTITY_VIRTUAL_MEMBERS (EntityVirtualMembers.h)

	// validForAddToUniverse(): virtual, in OO_ENTITY_VIRTUAL_MEMBERS (EntityVirtualMembers.h)
	void addToLinkedLists();
	void removeFromLinkedLists();

	void updateLinkedLists();

	// wasAddedToUniverse(): virtual, in OO_ENTITY_VIRTUAL_MEMBERS (EntityVirtualMembers.h)
	// wasRemovedFromUniverse(): virtual, in OO_ENTITY_VIRTUAL_MEMBERS (EntityVirtualMembers.h)

	// warnAboutHostiles(): virtual, in OO_ENTITY_VIRTUAL_MEMBERS (EntityVirtualMembers.h)

	CollisionRegion *getCollisionRegion();
	void setCollisionRegion(CollisionRegion *region);

	void setUniversalID(OOUniversalID uid);
	OOUniversalID getUniversalID();

	bool throwingSparks();
	void setThrowSparks(bool value);
	// throwSparks(): virtual, in OO_ENTITY_VIRTUAL_MEMBERS (EntityVirtualMembers.h)

	// setOwner(): virtual, in OO_ENTITY_VIRTUAL_MEMBERS (EntityVirtualMembers.h)
	Entity *owner();		// the owner while it has its object, null for none or once it has gone (what -owner answered the object of, +0; bead oo-dpyk8)
	Entity *ownerEntity();	// the owner's C++ entity, null once it has gone (bead oo-9ht.39.8.21)
	// The objects (a ship's, or a visual effect's for its subentities: the Objective-C ShipEntity the
	// declarations named was the type, not the answer; bead oo-9ht.144).
	Entity *parentEntity();		// owner if self is subentity of owner, otherwise null (the C++ entity since bead oo-9ht.39.24).
	Entity *rootShipEntity();	// like parentEntity, but recursive.
	Entity *superShaderBindingTarget();	// the parent entity, +0 (what -superShaderBindingTarget answered the object of; bead oo-dpyk8)

	// setPosition(): virtual, in OO_ENTITY_VIRTUAL_MEMBERS (EntityVirtualMembers.h)
	void setPositionX(OOHPScalar x, OOHPScalar y, OOHPScalar z);
	HPVector getPosition();
	Vector getCameraRelativePosition();
	// cameraRangeFront(): virtual, in OO_ENTITY_VIRTUAL_MEMBERS (EntityVirtualMembers.h)
	// cameraRangeBack(): virtual, in OO_ENTITY_VIRTUAL_MEMBERS (EntityVirtualMembers.h)

	// Exposed to uniform bindings.
	Vector relativePosition();

	// updateCameraRelativePosition(): virtual, in OO_ENTITY_VIRTUAL_MEMBERS (EntityVirtualMembers.h)
	// gets a low-position relative vector
	Vector vectorTo(Entity *entity);

	HPVector absolutePositionForSubentity();
	HPVector absolutePositionForSubentityOffset(HPVector offset);

	double zeroDistance();
	double camZeroDistance();
	// compareZeroDistance(): virtual, in OO_ENTITY_VIRTUAL_MEMBERS (EntityVirtualMembers.h)

	BoundingBox getBoundingBox();

	GLfloat getMass();

	Quaternion getOrientation();
	// setOrientation(): virtual, in OO_ENTITY_VIRTUAL_MEMBERS (EntityVirtualMembers.h)
	// normalOrientation(): virtual, in OO_ENTITY_VIRTUAL_MEMBERS (EntityVirtualMembers.h)
	// setNormalOrientation(): virtual, in OO_ENTITY_VIRTUAL_MEMBERS (EntityVirtualMembers.h)
	// orientationChanged(): virtual, in OO_ENTITY_VIRTUAL_MEMBERS (EntityVirtualMembers.h)

	void setVelocity(Vector vel);
	// getVelocity(): virtual, in OO_ENTITY_VIRTUAL_MEMBERS (EntityVirtualMembers.h)
	double speed();

	GLfloat getDistanceTravelled();
	void setDistanceTravelled(GLfloat value);


	// setStatus(): virtual, in OO_ENTITY_VIRTUAL_MEMBERS (EntityVirtualMembers.h)
	OOEntityStatus status();

	void setScanClass(OOScanClass sClass);
	// getScanClass(): virtual, in OO_ENTITY_VIRTUAL_MEMBERS (EntityVirtualMembers.h)

	void setEnergy(GLfloat amount);
	GLfloat getEnergy();

	void setMaxEnergy(GLfloat amount);
	GLfloat getMaxEnergy();

	// applyRoll(): virtual, in OO_ENTITY_VIRTUAL_MEMBERS (EntityVirtualMembers.h)
	// applyRoll(): virtual, in OO_ENTITY_VIRTUAL_MEMBERS (EntityVirtualMembers.h)
	// moveForward(): virtual, in OO_ENTITY_VIRTUAL_MEMBERS (EntityVirtualMembers.h)

	OOMatrix rotationMatrix();
	// drawRotationMatrix(): virtual, in OO_ENTITY_VIRTUAL_MEMBERS (EntityVirtualMembers.h)
	OOMatrix transformationMatrix();
	// drawTransformationMatrix(): virtual, in OO_ENTITY_VIRTUAL_MEMBERS (EntityVirtualMembers.h)

	// canCollide(): virtual, in OO_ENTITY_VIRTUAL_MEMBERS (EntityVirtualMembers.h)
	// collisionRadius(): virtual, in OO_ENTITY_VIRTUAL_MEMBERS (EntityVirtualMembers.h)
	// frustumRadius(): virtual, in OO_ENTITY_VIRTUAL_MEMBERS (EntityVirtualMembers.h)
	void setCollisionRadius(GLfloat amount);
	std::vector<oo::EntityHold> *getCollidingEntities();	// the live list (ADR-0043 item 22)

	// update(): virtual, in OO_ENTITY_VIRTUAL_MEMBERS (EntityVirtualMembers.h)

	void applyVelocity(OOTimeDelta delta_t);
	// checkCloseCollisionWith(): virtual, in OO_ENTITY_VIRTUAL_MEMBERS (EntityVirtualMembers.h)

	// takeEnergyDamage(): virtual, in OO_ENTITY_VIRTUAL_MEMBERS (EntityVirtualMembers.h)

	void dumpState();		// General "describe situtation verbosely in log" command.
	// dumpSelfState(): virtual, in OO_ENTITY_VIRTUAL_MEMBERS (EntityVirtualMembers.h)

	// subEntityReallyDied(): virtual, in OO_ENTITY_VIRTUAL_MEMBERS (EntityVirtualMembers.h)

	NSUInteger getLastDrawCounter();
	void setLastDrawCounter(NSUInteger drawCounter);

	// Subclass repsonsibilities
	// findCollisionRadius(): virtual, in OO_ENTITY_VIRTUAL_MEMBERS (EntityVirtualMembers.h)
	// drawImmediate(): virtual, in OO_ENTITY_VIRTUAL_MEMBERS (EntityVirtualMembers.h)
	// isVisible(): virtual, in OO_ENTITY_VIRTUAL_MEMBERS (EntityVirtualMembers.h)
	bool isInSpace();
	bool getIsImmuneToBreakPatternHide();

	// For shader bindings.
	GLfloat universalTime();
	GLfloat getSpawnTime();
	GLfloat timeElapsedSinceSpawn();
	void setAtmosphereFogging(OOColor *fogging);
	oo::Ref<OOColor> fogUniform();

	// The category ShaderBindings (EntityShaderBindings.mm, bead oo-aeev; amendment oo-9fwb): more
	// values the shader uniforms bind to by name, through the entities' shader binding member table
	// (Entity+ObjCBridge.mm, bead oo-9ht.158) since bead oo-9ht.127 deleted the category's forwarders.
	GLfloat clock();
	unsigned pseudoFixedD100();
	unsigned pseudoFixedD256();
	unsigned systemGovernment();
	unsigned systemEconomy();
	unsigned systemTechLevel();
	unsigned systemPopulation();
	unsigned systemProductivity();

	// What "%@" prints between the braces of <Class 0x...>{...} (OODescription.h).
	// descriptionComponents(): virtual, in OO_ENTITY_VIRTUAL_MEMBERS (EntityVirtualMembers.h)

	/*	The class questions the engine asked an entity's object by selector (the deleted category
		Entity (OOJavaScriptExtensions)): a C++ entity answers for its class by overriding them
		(ADR-0056 amendment oo-9ht.107). The defaults are the category's bodies
		(EntityOOJavaScriptExtensions.h). Since bead oo-9ht.39.8.9 the engine asks the C++ entity
		(OOJSEntityIsVisibleToScripts(), OOJSEntityJSClassName(), OOJSEntityGetJSClass()); an
		Objective-C entity's class that implements the selectors still answers first.
		oo::ObjCEntity must not forward these: those functions reach them only for an Objective-C
		entity with no override of its own, and a forwarding adapter would send the selector back.
	*/
	// getJSClass(): virtual, in OO_ENTITY_VIRTUAL_MEMBERS (EntityVirtualMembers.h)
	// jsClassName(): virtual, in OO_ENTITY_VIRTUAL_MEMBERS (EntityVirtualMembers.h)
	// isVisibleToScripts(): virtual, in OO_ENTITY_VIRTUAL_MEMBERS (EntityVirtualMembers.h)

	/*	The entity's JS glue (OOJSPrivateObject, bead oo-9ht.39.3; ADR-0056 amendment oo-9ht.39.3):
		what the root facade's -oo_jsValueInContext:, -oo_clearJSSelf: and -cxx_oo_jsDescription
		answered, so the engine wraps a C++ entity with OOJSValueFromCxxObject(). Its JS object's
		private slot holds an OOJSEntityHolder (OOJSEntity.h), a weak reference to the entity, as
		the slot held the facade's weak reference. The bodies are EntityOOJavaScriptExtensions.mm's.
		deleteJSSelf() is what the deleted -deleteJSSelf forwarded to (the engine's reset; the
		facade's -dealloc calls it; bead oo-9ht.39.8.9).
	*/
	// jsValueInContext(): virtual, in OO_ENTITY_VIRTUAL_MEMBERS (EntityVirtualMembers.h)
	// clearJSSelf(): virtual, in OO_ENTITY_VIRTUAL_MEMBERS (EntityVirtualMembers.h)
	// jsDescription(): virtual, in OO_ENTITY_VIRTUAL_MEMBERS (EntityVirtualMembers.h)
	void deleteJSSelf();

#ifndef NDEBUG
	std::optional<std::string> descriptionForObjDumpBasic();
	// descriptionForObjDump(): virtual, in OO_ENTITY_DEBUG_VIRTUAL_MEMBERS (EntityVirtualMembers.h)

	// allTextures(): virtual, in OO_ENTITY_DEBUG_VIRTUAL_MEMBERS (EntityVirtualMembers.h)
#endif

	// the base object for ships/stations/anything actually
	//////////////////////////////////////////////////////
	//
	// @public variables:
	//
	// we forego encapsulation for some variables in order to
	// lose the overheads of Obj-C accessor methods...
	//
	OOUniversalID			universalID = {};			// used to reference the entity

	unsigned				isShip: 1 = 0,
							isStation: 1 = 0,
							isPlayer: 1 = 0,
							isWormhole: 1 = 0,
							isSubEntity: 1 = 0,
							hasMoved: 1 = 0,
							hasRotated: 1 = 0,
							hasCollided: 1 = 0,
							isSunlit: 1 = 0,
							collisionTestFilter: 2 = 0,
							throw_sparks: 1 = 0,
							isImmuneToBreakPatternHide: 1 = 0,
							isExplicitlyNotMainStation: 1 = 0,
							isVisualEffect: 1 = 0;

	OOScanClass				scanClass = {};

	GLfloat					zero_distance = {};
	GLfloat					cam_zero_distance = {};
	GLfloat					no_draw_distance = {};		// 10 km initially
	GLfloat					collision_radius = {};
	HPVector					position = {}; // use high-precision vectors for global position
	Vector						cameraRelativePosition = {};
	Quaternion				orientation = {};
	oo::Ref<OOColor>		atmosphereFogging;

	int						zero_index = {};

	// Linked lists of entites, sorted by position on each (world) axis. Pointers to other entities
	// are their C++ parts, borrowed as the objects were (bead oo-9ht.39.4).
	Entity					*x_previous = {}, *x_next = {};
	Entity					*y_previous = {}, *y_next = {};
	Entity					*z_previous = {}, *z_next = {};

	Entity					*collision_chain = {};

	OOUniversalID			shadingEntityID = {};

	Entity					*collider = {};

	oo::Ref<CollisionRegion>	collisionRegion;		// initially nil - then maintained

	// @protected in Objective-C: public while Objective-C subclasses read them.
	HPVector					lastPosition = {};
	Quaternion				lastOrientation = {};

	GLfloat					distanceTravelled = {};		// set to zero initially

	OOMatrix				rotMatrix = {};

	Vector					velocity = {};

	GLfloat					energy = {};
	GLfloat					maxEnergy = {};

	BoundingBox				boundingBox = {};
	GLfloat					mass = {};

	std::vector<oo::EntityHold>	collidingEntities;	// filled by CollisionRegion each frame

	OOTimeAbsolute			spawnTime = {};

	ooscript::Object _jsSelf = {};
	NSUInteger				lastDrawCounter = {};

private:
	bool checkLinkedLists();

	bool					_hasObject = false;		// made by a creator (the facade's -initWithCxxEntity:)
	bool					_disposing = false;		// in its last release (-dealloc)

	NSUInteger				_sessionID = {};

	oo::WeakRef<Entity>		_owner;	// the owner's C++ part (bead oo-9ht.39.5.2; was its object's weak reference)
	OOEntityStatus			_status = {};
};


namespace cxx {

/*	The protocol OOSubEntity's methods, for a C++ subentity whose own façade is gone (ADR-0056
	amendment oo-9ht.107): the owner that sent a subentity -rescaleBy: or
	-drawSubEntityImmediate:translucent: calls these when the subentity's C++ part adopts this
	interface, and sends the selector otherwise. (Not named OOSubEntity: inside namespace cxx the
	protocol-qualified type Entity<OOSubEntity> would then name a class as its argument.)
*/
class OOSubEntityInterface
{
public:
	virtual ~OOSubEntityInterface() = default;

	virtual void rescaleBy(GLfloat factor) = 0;
	virtual void rescaleBy(GLfloat factor, bool writeToCache) = 0;
	virtual void drawSubEntityImmediate(bool immediate, bool translucent) = 0;
};

}	// namespace cxx


#ifdef __cplusplus
#include "oofnd/StdLib.hpp"

// C++ forms, defined in OOConstToString.mm (bead oo-nts1, chunk oo-3rb.161): std::string results
// (never nil), const std::string & parameters (nil arrived as "" and matched nothing: the defaults).
// Former Foundation forms lived in a transitional bridge (deleted by oo-a8xp).
std::string cxx_OOStringFromEntityStatus(OOEntityStatus status);
OOEntityStatus cxx_OOEntityStatusFromString(const std::string &string);

std::string cxx_OOStringFromScanClass(OOScanClass scanClass);
OOScanClass cxx_OOScanClassFromString(const std::string &string);

/*	The entities' shader binding member table (EntityShaderBindings.mm; beads oo-9ht.158 and
	oo-9ht.39.6.1, ADR-0056 amendment oo-9ht.39.6.1): the binding a uniform bound to the property
	name on this entity makes, reading the entity itself. False where no row has the name, the row
	does not apply to this entity, or its type is not bindable (as the selector path failed).
*/
struct OOShaderMemberBinding;	// OOShaderUniformMethodType.h
bool EntityShaderMemberBindingFor(Entity *entity, const char *property, OOShaderMemberBinding *outBinding);


#include "oofnd/PList.hpp"

namespace oo {

/*	An entity carried WEAKLY through plist data (bead oo-w9pi2): what oo::PListObject() of the
	entity's object's weak reference made (the docking instructions' station, the collision-avoidance
	condition's primary target; the weak-reference class went with bead oo-9ht.22). The payload holds a weak reference to the C++ entity, which reads
	null exactly when the object's weak reference did (the facade's -dealloc drops both at one
	point), so the node keeps nothing alive, as before. Its JS value is the entity's, undefined
	once it has gone (OOJSValueFromPList), as the weak reference forwarded.
*/
class EntityWeakPListForeign final : public PListForeign
{
public:
	explicit EntityWeakPListForeign(Entity *entity) : _entity(entity) {}
	Entity *entity() const noexcept  { return _entity.get(); }
	std::string className() const override  { return "OOWeakReference"; }	// what the proxy's class was
	std::string description() const override;	// the entity's description, or <Dead OOWeakReference 0x...> (Entity.mm)

private:
	WeakRef<Entity>	_entity;
};

// The entity's weak node; a null PList for null.
inline PList EntityWeakNode(Entity *entity)
{
	if (entity == nullptr)  return PList();
	return PList(PList::Object(makeRef<EntityWeakPListForeign>(entity)));
}

// The live C++ entity of a weak node; null once it has gone, and for any other node.
inline Entity *EntityInWeakNode(const PList &plist)
{
	const PList::Object *node = plist.getIf<PList::Object>();
	if (node == nullptr)  return nullptr;
	const auto *payload = dynamic_cast<const EntityWeakPListForeign *>(node->get());
	return payload != nullptr ? payload->entity() : nullptr;
}

}	// namespace oo
#endif



// What the deleted facade's header kept for its callers: the questions it answered (bead oo-dpyk8).
#include "EntityHelpers.h"
