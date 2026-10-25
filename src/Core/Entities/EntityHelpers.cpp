/*

EntityHelpers.mm

The questions the deleted root entity facade answered (EntityHelpers.h, bead oo-dpyk8): its
categories' and its helpers' bodies, asked of the C++ entity, and the entities' own counts
(OOEntityHold.h): what -retain, -release, -autorelease and the facade's creation did.

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

#include "Entity.h"
#include "OOWaypointEntity.h"
#include "OOVisualEffectEntity.h"
#include "ShipEntity.h"
#include "oofnd/String.hpp"
#include "oofnd/Ref.hpp"	// oo::autorelease (oo-31u.6)

#include <cstdlib>
#include <cxxabi.h>
#include <typeinfo>


#ifndef NDEBUG
extern uint32_t gLiveEntityCount;
extern size_t gTotalEntityMemory;
#endif


namespace {

// The parts the facade's categories asked (ShipPart, EffectPart, the waypoint): each is nullptr for
// any other entity.
ShipEntity *ShipPart(Entity *entity)						{ return dynamic_cast<ShipEntity *>(entity); }
OOVisualEffectEntity *EffectPart(Entity *entity)			{ return dynamic_cast<OOVisualEffectEntity *>(entity); }
OOWaypointEntity *WaypointPart(Entity *entity)				{ return dynamic_cast<OOWaypointEntity *>(entity); }

}	// namespace


Entity *oo::WithObject(Entity *entity)
{
	return (entity != nullptr && entity->hasObject()) ? entity : nullptr;
}


// --- Counts (OOEntityHold.h) ----------------------------------------------------------------------

bool oo::detail::EntityHasObject(const Entity *entity) noexcept  { return entity != nullptr && entity->hasObject(); }
void oo::detail::EntityRetain(Entity *entity) noexcept  { if (entity != nullptr)  entity->retain(); }
void oo::detail::EntityRelease(Entity *entity) noexcept  { if (entity != nullptr)  entity->release(); }


Entity *oo::RetainEntity(Entity *entity)
{
	if (WithObject(entity) != nullptr)  entity->retain();
	return entity;
}


void oo::ReleaseEntity(Entity *entity)
{
	if (WithObject(entity) != nullptr)  entity->release();
}


Entity *oo::AutoreleaseEntity(Entity *entity)
{
	// The caller's +1 goes to the innermost oo::AutoreleaseScope, released at the same drain and in
	// the same order as -autorelease's object (beads oo-pvhrh, oo-31u.6).
	if (WithObject(entity) != nullptr)  oo::autorelease(entity);
	return entity;
}


Entity *oo::MadeEntityRetained(const Ref<Entity> &entity)
{
	if (entity == nullptr)  return nullptr;
	// The facade's -initWithCxxEntity:: from here the entity has its object, and it is counted.
	entity->setMadeWithObject();
#ifndef NDEBUG
	gLiveEntityCount++;
	gTotalEntityMemory += EntityObjectSize(entity.get());
#endif
	entity->retain();	// +alloc's object
	return entity.get();
}


Entity *oo::MadeEntity(const Ref<Entity> &entity)
{
	return AutoreleaseEntity(MadeEntityRetained(entity));	// [[... alloc] init...] autorelease]
}


Entity *oo::EntityInitAgain(Entity *entity)
{
	entity->init();
#ifndef NDEBUG
	gLiveEntityCount++;
	gTotalEntityMemory += EntityObjectSize(entity);
#endif
	return entity;
}


// --- Descriptions ---------------------------------------------------------------------------------

std::string oo::EntityClassName(Entity *entity)
{
	int status = 0;
	char *demangled = abi::__cxa_demangle(typeid(*entity).name(), nullptr, nullptr, &status);
	std::string result = (status == 0 && demangled != nullptr) ? demangled : typeid(*entity).name();
	std::free(demangled);
	if (result.starts_with("cxx::"))  result.erase(0, 5);
	return result;
}


std::string oo::EntityOwnDescription(Entity *entity)
{
	if (entity == nullptr)  return "(null)";
	// The facade's -cxx_description: the C++ class's name and components.
	std::string result = str::format("<%s %s>", EntityClassName(entity).c_str(), str::pointerDescription(entity).c_str());
	if (const std::optional<std::string> components = entity->descriptionComponents())  result += "{" + *components + "}";
	return result;
}


std::string oo::EntityDescription(Entity *entity)
{
	return EntityOwnDescription(WithObject(entity));	// "(null)", as DescriptionOf(nil), without its object
}


std::string oo::EntityShortDescription(Entity *entity)
{
	// OOObject's -cxx_shortDescription, which the facade did not override: its class (the root
	// facade's, Entity) and address, no components.
	if (WithObject(entity) == nullptr)  return "(null)";
	return str::format("<Entity %s>", str::pointerDescription(entity).c_str());
}


void oo::InspectEntity(Entity *entity)
{
	if (WithObject(entity) != nullptr)  entity->inspect();
}


// --- The categories' questions -------------------------------------------------------------------

bool oo::EntityIsShipWithSubEntityShip(Entity *entity, Entity *other)
{
	if (ShipEntity *ship = ShipPart(entity))  return ship->isShipWithSubEntityShip(other);
	OOVisualEffectEntity *effect = EffectPart(entity);
	return effect != nullptr ? effect->isShipWithSubEntityShip(other) : NO;
}


bool oo::EntityIsBeacon(Entity *entity)
{
	if (ShipEntity *ship = ShipPart(entity))  return ship->isBeacon();
	if (OOVisualEffectEntity *effect = EffectPart(entity))  return effect->isBeacon();
	OOWaypointEntity *waypoint = WaypointPart(entity);
	return waypoint != nullptr ? waypoint->isBeacon() : NO;
}


/*	The beacon category (Entity (OOWaypointBeacon)) answered these for the ship's, the visual
	effect's and the waypoint's part, and zero for any other entity; a message to an entity without
	its object answered nil's zero. The links it answered were the linked entities' objects (+0), so
	an entity without its object is none.
*/
Entity *oo::PrevBeacon(Entity *beacon)
{
	beacon = WithObject(beacon);
	if (ShipEntity *ship = ShipPart(beacon))  return WithObject(ship->prevBeacon());
	if (OOVisualEffectEntity *effect = EffectPart(beacon))  return WithObject(effect->prevBeacon());
	if (OOWaypointEntity *waypoint = WaypointPart(beacon))  return WithObject(waypoint->prevBeacon());
	return nullptr;
}


Entity *oo::NextBeacon(Entity *beacon)
{
	beacon = WithObject(beacon);
	if (ShipEntity *ship = ShipPart(beacon))  return WithObject(ship->nextBeacon());
	if (OOVisualEffectEntity *effect = EffectPart(beacon))  return WithObject(effect->nextBeacon());
	if (OOWaypointEntity *waypoint = WaypointPart(beacon))  return WithObject(waypoint->nextBeacon());
	return nullptr;
}


void oo::SetPrevBeacon(Entity *beacon, Entity *other)
{
	beacon = WithObject(beacon);
	other = WithObject(other);
	if (ShipEntity *ship = ShipPart(beacon))  ship->setPrevBeacon(other);
	else if (OOVisualEffectEntity *effect = EffectPart(beacon))  effect->setPrevBeacon(other);
	else if (OOWaypointEntity *waypoint = WaypointPart(beacon))  waypoint->setPrevBeacon(other);
}


void oo::SetNextBeacon(Entity *beacon, Entity *other)
{
	beacon = WithObject(beacon);
	other = WithObject(other);
	if (ShipEntity *ship = ShipPart(beacon))  ship->setNextBeacon(other);
	else if (OOVisualEffectEntity *effect = EffectPart(beacon))  effect->setNextBeacon(other);
	else if (OOWaypointEntity *waypoint = WaypointPart(beacon))  waypoint->setNextBeacon(other);
}


std::optional<std::string> oo::BeaconCode(Entity *beacon)
{
	beacon = WithObject(beacon);
	if (ShipEntity *ship = ShipPart(beacon))  return ship->beaconCode();
	if (OOVisualEffectEntity *effect = EffectPart(beacon))  return effect->beaconCode();
	if (OOWaypointEntity *waypoint = WaypointPart(beacon))  return waypoint->beaconCode();
	return std::nullopt;
}


void oo::SetBeaconCode(Entity *beacon, const std::optional<std::string> &code)
{
	beacon = WithObject(beacon);
	if (ShipEntity *ship = ShipPart(beacon))  ship->setBeaconCode(code);
	else if (OOVisualEffectEntity *effect = EffectPart(beacon))  effect->setBeaconCode(code);
	else if (OOWaypointEntity *waypoint = WaypointPart(beacon))  waypoint->setBeaconCode(code);
}


OOComparisonResult oo::CompareBeaconCodes(Entity *beacon, Entity *other)
{
	beacon = WithObject(beacon);
	other = WithObject(other);
	if (ShipEntity *ship = ShipPart(beacon))  return ship->compareBeaconCodeWith(other);
	if (OOVisualEffectEntity *effect = EffectPart(beacon))  return effect->compareBeaconCodeWith(other);
	if (OOWaypointEntity *waypoint = WaypointPart(beacon))  return waypoint->compareBeaconCodeWith(other);
	return (OOComparisonResult)0;
}


bool oo::BeaconIsJammingScanning(Entity *beacon)
{
	beacon = WithObject(beacon);
	if (ShipEntity *ship = ShipPart(beacon))  return ship->isJammingScanning();
	if (OOVisualEffectEntity *effect = EffectPart(beacon))  return effect->isJammingScanning();
	if (OOWaypointEntity *waypoint = WaypointPart(beacon))  return waypoint->isJammingScanning();
	return NO;
}


OOHUDBeaconIcon *oo::BeaconDrawable(Entity *beacon)
{
	beacon = WithObject(beacon);
	if (ShipEntity *ship = ShipPart(beacon))  return ship->beaconDrawable();
	if (OOVisualEffectEntity *effect = EffectPart(beacon))  return effect->beaconDrawable();
	if (OOWaypointEntity *waypoint = WaypointPart(beacon))  return waypoint->beaconDrawable();
	return nullptr;
}


std::optional<std::string> oo::BeaconLabel(Entity *beacon)
{
	beacon = WithObject(beacon);
	if (ShipEntity *ship = ShipPart(beacon))  return ship->beaconLabel();
	if (OOVisualEffectEntity *effect = EffectPart(beacon))  return effect->beaconLabel();
	if (OOWaypointEntity *waypoint = WaypointPart(beacon))  return waypoint->beaconLabel();
	return std::nullopt;
}
