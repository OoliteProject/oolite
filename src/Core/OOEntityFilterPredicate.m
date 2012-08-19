/*

OOEntityFilterPredicate.h

Filters used to select entities in various contexts.


Oolite
Copyright (C) 2004-2012 Giles C Williams and contributors

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
#import "ShipEntity.h"
#import "OOPlanetEntity.h"
#import "OORoleSet.h"


BOOL YESPredicate(Entity *entity, void *parameter)
{
	return YES;
}


BOOL NOPredicate(Entity *entity, void *parameter)
{
	return NO;
}


BOOL NOTPredicate(Entity *entity, void *parameter)
{
	ChainedEntityPredicateParameter *param = parameter;
	if (param == NULL || param->predicate == NULL)  return NO;
	
	return !param->predicate(entity, param->parameter);
}


BOOL ANDPredicate(Entity *entity, void *parameter)
{
	BinaryOperationPredicateParameter *param = parameter;
	
	if (!param->predicate1(entity, param->parameter1))  return NO;
	if (!param->predicate2(entity, param->parameter2))  return NO;
	return YES;
}


BOOL ORPredicate(Entity *entity, void *parameter)
{
	BinaryOperationPredicateParameter *param = parameter;
	
	if (param->predicate1(entity, param->parameter1))  return YES;
	if (param->predicate2(entity, param->parameter2))  return YES;
	return NO;
}


BOOL NORPredicate(Entity *entity, void *parameter)
{
	BinaryOperationPredicateParameter *param = parameter;
	
	if (param->predicate1(entity, param->parameter1))  return NO;
	if (param->predicate2(entity, param->parameter2))  return NO;
	return YES;
}


BOOL XORPredicate(Entity *entity, void *parameter)
{
	BinaryOperationPredicateParameter *param = parameter;
	BOOL A, B;
	
	A = param->predicate1(entity, param->parameter1);
	B = param->predicate2(entity, param->parameter2);
	
	return (A || B) && !(A && B);
}


BOOL NANDPredicate(Entity *entity, void *parameter)
{
	BinaryOperationPredicateParameter *param = parameter;
	BOOL A, B;
	
	A = param->predicate1(entity, param->parameter1);
	B = param->predicate2(entity, param->parameter2);
	
	return !(A && B);
}


BOOL HasScanClassPredicate(Entity *entity, void *parameter)
{
	return [(id)parameter intValue] == [entity scanClass];
}


BOOL HasClassPredicate(Entity *entity, void *parameter)
{
	return [entity isKindOfClass:(Class)parameter];
}


BOOL IsShipPredicate(Entity *entity, void *parameter)
{
	return [entity isShip] && ![entity isSubEntity];
}


BOOL IsStationPredicate(Entity *entity, void *parameter)
{
	return [entity isStation];
}


BOOL IsPlanetPredicate(Entity *entity, void *parameter)
{
	if (![entity isPlanet])  return NO;
	OOStellarBodyType type = [(OOPlanetEntity *)entity planetType];
	return (type == STELLAR_TYPE_NORMAL_PLANET || type == STELLAR_TYPE_MOON);
}


BOOL IsSunPredicate(Entity *entity, void *parameter)
{
	return [entity isSun];
}


BOOL IsVisualEffectPredicate(Entity *entity, void *parameter)
{
	return [entity isVisualEffect] && ![entity isSubEntity];
}


BOOL HasRolePredicate(Entity *ship, void *parameter)
{
	return [(ShipEntity *)ship hasRole:(NSString *)parameter];
}


BOOL HasPrimaryRolePredicate(Entity *ship, void *parameter)
{
	return [(ShipEntity *)ship hasPrimaryRole:(NSString *)parameter];
}


BOOL HasRoleInSetPredicate(Entity *ship, void *parameter)
{
	return [[(ShipEntity *)ship roleSet] intersectsSet:(NSSet *)parameter];
}


BOOL HasPrimaryRoleInSetPredicate(Entity *ship, void *parameter)
{
	return [(NSSet *)parameter containsObject:[(ShipEntity *)ship primaryRole]];
}


BOOL IsHostileAgainstTargetPredicate(Entity *ship, void *parameter)
{
	return [(ShipEntity *)ship hasHostileTarget] && [(ShipEntity *)ship primaryTarget] == (ShipEntity *)parameter;
}
