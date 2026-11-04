/*

OOEntityFilterPredicate.h

Filters used to select entities in various contexts.


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

#include "OOEntityFilterPredicate.h"

#include "Entity.h"
#include "OOPlanetEntity.h"
#include "OORoleSet.h"
#include "ShipEntity.h"

bool YESPredicate(Entity* /*entity*/, void* /*parameter*/) { return true; }

bool NOPredicate(Entity* /*entity*/, void* /*parameter*/) { return false; }

bool NOTPredicate(Entity* entity, void* parameter) {
  ChainedEntityPredicateParameter* param =
      (ChainedEntityPredicateParameter*)parameter;
  if (param == NULL || param->predicate == NULL) return false;

  return !param->predicate(entity, param->parameter);
}

bool ANDPredicate(Entity* entity, void* parameter) {
  BinaryOperationPredicateParameter* param =
      (BinaryOperationPredicateParameter*)parameter;

  if (!param->predicate1(entity, param->parameter1)) return false;
  if (!param->predicate2(entity, param->parameter2)) return false;
  return true;
}

bool ORPredicate(Entity* entity, void* parameter) {
  BinaryOperationPredicateParameter* param =
      (BinaryOperationPredicateParameter*)parameter;

  if (param->predicate1(entity, param->parameter1)) return true;
  if (param->predicate2(entity, param->parameter2)) return true;
  return false;
}

bool NORPredicate(Entity* entity, void* parameter) {
  BinaryOperationPredicateParameter* param =
      (BinaryOperationPredicateParameter*)parameter;

  if (param->predicate1(entity, param->parameter1)) return false;
  if (param->predicate2(entity, param->parameter2)) return false;
  return true;
}

bool XORPredicate(Entity* entity, void* parameter) {
  BinaryOperationPredicateParameter* param =
      (BinaryOperationPredicateParameter*)parameter;
  bool A, B;

  A = param->predicate1(entity, param->parameter1);
  B = param->predicate2(entity, param->parameter2);

  return (A || B) && !(A && B);
}

bool NANDPredicate(Entity* entity, void* parameter) {
  BinaryOperationPredicateParameter* param =
      (BinaryOperationPredicateParameter*)parameter;
  bool A, B;

  A = param->predicate1(entity, param->parameter1);
  B = param->predicate2(entity, param->parameter2);

  return !(A && B);
}

/*	The predicates ask the C++ entity directly.
 */
bool HasScanClassPredicate(Entity* entity, void* parameter) {
  return *static_cast<const OOScanClass*>(parameter) ==
         (entity != nullptr
              ? entity->getScanClass()
              : OOScanClass{});  // an OOScanClass, as the callers pass it
}

bool IsShipPredicate(Entity* entity, void* /*parameter*/) {
  return entity != nullptr && entity->getIsShip() && !entity->getIsSubEntity();
}

bool IsStationPredicate(Entity* entity, void* /*parameter*/) {
  return entity != nullptr && entity->getIsStation();
}

bool IsPlanetPredicate(Entity* entity, void* /*parameter*/) {
  if (!(entity != nullptr && entity->isPlanet())) return false;
  OOStellarBodyType type = OOStellarBodyPlanetType(entity);
  return (type == STELLAR_TYPE_NORMAL_PLANET || type == STELLAR_TYPE_MOON);
}

bool IsSunPredicate(Entity* entity, void* /*parameter*/) {
  return entity != nullptr && entity->isSun();
}

bool IsVisualEffectPredicate(Entity* entity, void* /*parameter*/) {
  return entity != nullptr && entity->getIsVisualEffect() &&
         !entity->getIsSubEntity();
}

bool HasRolePredicate(Entity* ship, void* parameter) {
  const std::string* role = static_cast<const std::string*>(
      parameter);  // a role, as the callers pass it; null for none
  return role != nullptr &&
         (oo::ToShip(ship) != nullptr ? oo::ToShip(ship)->hasRole(*role)
                                      : false);
}

bool HasPrimaryRolePredicate(Entity* ship, void* parameter) {
  const std::string* role = static_cast<const std::string*>(
      parameter);  // a role, as the callers pass it; null for none
  if (role == nullptr) {
    if (ShipEntity* s = oo::ToShip(ship))
      (void)s->getPrimaryRole();  // still chooses a primary role if there is
                                  // none, as before
    return false;                 // -isEqual: nil was NO
  }
  return (oo::ToShip(ship) != nullptr ? oo::ToShip(ship)->hasPrimaryRole(*role)
                                      : false);
}

bool HasRoleInSetPredicate(Entity* ship, void* parameter) {
  // parameter: the role strings, as the callers pass them (none empty);
  // -intersectsSet: of them
  const std::vector<std::string>& roles =
      *static_cast<const std::vector<std::string>*>(parameter);
  const oo::Ref<OORoleSet> roleSet = oo::ToShip(ship)->getRoleSet();
  if (roleSet == nullptr) return false;
  return std::any_of(
      roles.begin(), roles.end(),
      [&roleSet](const std::string& role) { return roleSet->hasRole(role); });
}

bool HasPrimaryRoleInSetPredicate(Entity* ship, void* parameter) {
  // parameter: the role strings, as the callers pass them; membership by string
  // value, as -containsObject: tested it. A nil primary role is in no set.
  const std::optional<std::string> primaryRole =
      (oo::ToShip(ship) != nullptr ? oo::ToShip(ship)->getPrimaryRole()
                                   : std::optional<std::string>());
  if (!primaryRole.has_value()) return false;
  const std::vector<std::string>& roles =
      *static_cast<const std::vector<std::string>*>(parameter);
  return std::find(roles.begin(), roles.end(), *primaryRole) != roles.end();
}

bool IsHostileAgainstTargetPredicate(Entity* ship, void* parameter) {
  return (oo::ToShip(ship) != nullptr ? oo::ToShip(ship)->hasHostileTarget()
                                      : false) &&
         (oo::ToShip(ship) != nullptr
              ? oo::ToShip(ship)->primaryTarget()
              : (Entity*)nullptr) == static_cast<::ShipEntity*>(parameter);
}
