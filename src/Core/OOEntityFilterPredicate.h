/*

OOEntityFilterPredicate.h

Filters used to select entities in various contexts. Callers are required to
ensure that the "entity" argument is non-nil and the "parameter" argument is
valid and relevant.

To reduce header spaghetti, the EntityFilterPredicate type is declared in
Universe.h, which is included just about everywhere anyway. This file just
declares a set of widely-useful predicates.


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

#include "Universe.h"

typedef struct
{
    EntityFilterPredicate predicate;
    void* parameter;
} ChainedEntityPredicateParameter;

typedef struct
{
    EntityFilterPredicate predicate1;
    void* parameter1;
    EntityFilterPredicate predicate2;
    void* parameter2;
} BinaryOperationPredicateParameter;

bool YESPredicate(Entity* entity,
    void* parameter); // Parameter: ignored. Always returns YES.
bool NOPredicate(Entity* entity,
    void* parameter); // Parameter: ignored. Always returns NO.

bool NOTPredicate(
    Entity* entity,
    void* parameter); // Parameter: ChainedEntityPredicateParameter. Reverses
                      // effect of chained predicate.

bool ANDPredicate(
    Entity* entity,
    void* parameter); // Parameter: BinaryOperationPredicateParameter.
                      // Short-circuiting AND operator.
bool ORPredicate(
    Entity* entity,
    void* parameter); // Parameter: BinaryOperationPredicateParameter.
                      // Short-circuiting OR operator.
bool NORPredicate(
    Entity* entity,
    void* parameter); // Parameter: BinaryOperationPredicateParameter.
                      // Short-circuiting NOR operator.
bool XORPredicate(
    Entity* entity,
    void* parameter); // Parameter: BinaryOperationPredicateParameter. XOR
                      // operator.
bool NANDPredicate(
    Entity* entity,
    void* parameter); // Parameter: BinaryOperationPredicateParameter. NAND
                      // operator.

bool HasScanClassPredicate(Entity* entity,
    void* parameter); // Parameter: an OOScanClass
bool IsShipPredicate(
    Entity* entity,
    void* parameter); // Parameter: ignored. Tests isShip and !isSubentity.
bool IsStationPredicate(
    Entity* entity, void* parameter); // Parameter: ignored. Tests isStation.
bool IsPlanetPredicate(
    Entity* entity,
    void* parameter); // Parameter: ignored. Tests isPlanet and planetType ==
                      // STELLAR_TYPE_NORMAL_PLANET.
bool IsSunPredicate(Entity* entity,
    void* parameter); // Parameter: ignored. Tests isSun.
bool IsVisualEffectPredicate(
    Entity* entity, void* parameter); // Parameter: ignored. Tests
                                      // isVisualEffect and !isSubentity.

// These predicates assume their parameter is a ShipEntity.
bool HasRolePredicate(
    Entity* ship, void* parameter); // Parameter: a std::string (null: none)
bool HasPrimaryRolePredicate(
    Entity* ship, void* parameter); // Parameter: a std::string (null: none)
bool HasRoleInSetPredicate(
    Entity* ship,
    void* parameter); // Parameter: a std::vector<std::string> of roles
bool HasPrimaryRoleInSetPredicate(
    Entity* ship,
    void* parameter); // Parameter: a std::vector<std::string> of roles
bool IsHostileAgainstTargetPredicate(Entity* ship,
    void* parameter); // Parameter: ShipEntity
