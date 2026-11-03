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

#import "OOEntityFilterPredicate.h"
#import "Entity.h"
#import "OOFoundationBridge.h"
#import "OOPlanetEntity.h"
#import "OORoleSet.h"
#import "ShipEntity.h"

BOOL YESPredicate(Entity* entity, void* parameter)
{
    return YES;
}

BOOL NOPredicate(Entity* entity, void* parameter)
{
    return NO;
}

BOOL NOTPredicate(Entity* entity, void* parameter)
{
    ChainedEntityPredicateParameter* param = (ChainedEntityPredicateParameter*)parameter;
    if (param == NULL || param->predicate == NULL)
        return NO;

    return !param->predicate(entity, param->parameter);
}

BOOL ANDPredicate(Entity* entity, void* parameter)
{
    BinaryOperationPredicateParameter* param = (BinaryOperationPredicateParameter*)parameter;

    if (!param->predicate1(entity, param->parameter1))
        return NO;
    if (!param->predicate2(entity, param->parameter2))
        return NO;
    return YES;
}

BOOL ORPredicate(Entity* entity, void* parameter)
{
    BinaryOperationPredicateParameter* param = (BinaryOperationPredicateParameter*)parameter;

    if (param->predicate1(entity, param->parameter1))
        return YES;
    if (param->predicate2(entity, param->parameter2))
        return YES;
    return NO;
}

BOOL NORPredicate(Entity* entity, void* parameter)
{
    BinaryOperationPredicateParameter* param = (BinaryOperationPredicateParameter*)parameter;

    if (param->predicate1(entity, param->parameter1))
        return NO;
    if (param->predicate2(entity, param->parameter2))
        return NO;
    return YES;
}

BOOL XORPredicate(Entity* entity, void* parameter)
{
    BinaryOperationPredicateParameter* param = (BinaryOperationPredicateParameter*)parameter;
    BOOL A, B;

    A = param->predicate1(entity, param->parameter1);
    B = param->predicate2(entity, param->parameter2);

    return (A || B) && !(A && B);
}

BOOL NANDPredicate(Entity* entity, void* parameter)
{
    BinaryOperationPredicateParameter* param = (BinaryOperationPredicateParameter*)parameter;
    BOOL A, B;

    A = param->predicate1(entity, param->parameter1);
    B = param->predicate2(entity, param->parameter2);

    return !(A && B);
}

BOOL HasScanClassPredicate(Entity* entity, void* parameter)
{
    return [(id)parameter intValue] == [entity scanClass];
}

BOOL HasClassPredicate(Entity* entity, void* parameter)
{
    return [entity isKindOfClass:(Class)parameter];
}

BOOL IsShipPredicate(Entity* entity, void* parameter)
{
    return [entity isShip] && ![entity isSubEntity];
}

BOOL IsStationPredicate(Entity* entity, void* parameter)
{
    return [entity isStation];
}

BOOL IsPlanetPredicate(Entity* entity, void* parameter)
{
    if (![entity isPlanet])
        return NO;
    OOStellarBodyType type = [(OOPlanetEntity*)entity planetType];
    return (type == STELLAR_TYPE_NORMAL_PLANET || type == STELLAR_TYPE_MOON);
}

BOOL IsSunPredicate(Entity* entity, void* parameter)
{
    return [entity isSun];
}

BOOL IsVisualEffectPredicate(Entity* entity, void* parameter)
{
    return [entity isVisualEffect] && ![entity isSubEntity];
}

BOOL HasRolePredicate(Entity* ship, void* parameter)
{
    const std::string* role = static_cast<const std::string*>(parameter); // a role, as the callers pass it; null for none
    return role != nullptr && [(ShipEntity*)ship hasRole:*role];
}

BOOL HasPrimaryRolePredicate(Entity* ship, void* parameter)
{
    const std::string* role = static_cast<const std::string*>(parameter); // a role, as the callers pass it; null for none
    if (role == nullptr) {
        (void)[(ShipEntity*)ship cxx_primaryRole]; // still chooses a primary role if there is none, as before
        return NO; // -isEqual: nil was NO
    }
    return [(ShipEntity*)ship cxx_hasPrimaryRole:*role];
}

BOOL HasRoleInSetPredicate(Entity* ship, void* parameter)
{
    return [[(ShipEntity*)ship roleSet] intersectsSet:(id)parameter]; // an Objective-C set of strings; -intersectsSet: is a shared selector (proposed ADR-0043)
}

BOOL HasPrimaryRoleInSetPredicate(Entity* ship, void* parameter)
{
    // parameter: an Objective-C set of role strings, as the callers pass it; membership by string
    // value, as -containsObject: tested it. A nil primary role is in no set.
    const std::optional<std::string> primaryRole = [(ShipEntity*)ship cxx_primaryRole];
    if (!primaryRole.has_value())
        return NO;
    const std::vector<std::string> roles = oo::StringsFrom((id)parameter);
    return std::find(roles.begin(), roles.end(), *primaryRole) != roles.end();
}

BOOL IsHostileAgainstTargetPredicate(Entity* ship, void* parameter)
{
    return [(ShipEntity*)ship hasHostileTarget] && [(ShipEntity*)ship primaryTarget] == (ShipEntity*)parameter;
}
