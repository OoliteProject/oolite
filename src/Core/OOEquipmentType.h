/*

OOEquipmentType.h

Class representing a type of ship equipment. Exposed to JavaScript as
EquipmentInfo.


Copyright (C) 2008-2013 Jens Ayton and contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

*/

#import "OOCocoa.h"
#import "OOTypes.h"
#import "OOScript.h"
#import "Universe.h"


@interface OOEquipmentType: NSObject <NSCopying>
{
@private
	OOTechLevelID			_techLevel;
	OOCreditsQuantity		_price;
	NSString				*_name;
	NSString				*_identifier;
	NSString				*_description;
	unsigned				_isAvailableToAll: 1,
							_requiresEmptyPylon: 1,
							_requiresMountedPylon: 1,
							_requiresClean: 1,
							_requiresNotClean: 1,
							_portableBetweenShips: 1,
							_requiresFreePassengerBerth: 1,
							_requiresFullFuel: 1,
							_requiresNonFullFuel: 1,
							_isMissileOrMine: 1,
							_isVisible: 1,
							_isAvailableToPlayer: 1,
							_isAvailableToNPCs: 1;
	GLfloat     _damageProbability;
	OOCargoQuantity			_requiredCargoSpace;
	NSSet					*_requiresEquipment;
	NSSet					*_requiresAnyEquipment;
	NSSet					*_incompatibleEquipment;
	NSArray					*_conditions;
	NSDictionary			*_scriptInfo;
	NSString				*_script;
	NSString				*_condition_script;
	
	struct JSObject			*_jsSelf;
}

+ (void) loadEquipment;			// Load equipment data; called on loading and when changing to/from strict mode.
+ (void) addEquipmentWithInfo:(NSArray *)itemInfo;	// Used to generate equipment from missile_role entries.

+ (NSString *) getMissileRegistryRoleForShip:(NSString *)shipKey;
+ (void) setMissileRegistryRole:(NSString *)roles forShip:(NSString *)shipKey;

+ (NSArray *) allEquipmentTypes;
+ (NSEnumerator *) equipmentEnumerator;

+ (OOEquipmentType *) equipmentTypeWithIdentifier:(NSString *)identifier;

- (NSString *) identifier;
- (NSString *) damagedIdentifier;
- (NSString *) name;			// localized
- (NSString *) descriptiveText;	// localized
- (OOTechLevelID) techLevel;
- (OOCreditsQuantity) price;	// Tenths of credits

- (BOOL) isAvailableToAll;
- (BOOL) requiresEmptyPylon;
- (BOOL) requiresMountedPylon;
- (BOOL) requiresCleanLegalRecord;
- (BOOL) requiresNonCleanLegalRecord;
- (BOOL) requiresFreePassengerBerth;
- (BOOL) requiresFullFuel;
- (BOOL) requiresNonFullFuel;
- (BOOL) isPrimaryWeapon;
- (BOOL) isMissileOrMine;
- (BOOL) isPortableBetweenShips;

- (BOOL) canCarryMultiple;
- (GLfloat) damageProbability;
- (BOOL) canBeDamaged;
- (BOOL) isVisible;				// Visible in UI?

- (BOOL) isAvailableToPlayer;
- (BOOL) isAvailableToNPCs;

- (OOCargoQuantity) requiredCargoSpace;
- (NSSet *) requiresEquipment;		// Set of equipment identifiers; all items required
- (NSSet *) requiresAnyEquipment;	// Set of equipment identifiers; any item required
- (NSSet *) incompatibleEquipment;	// Set of equipment identifiers; all items prohibited

// FIXME: should have general mechanism to handle scripts or legacy conditions.
- (NSArray *) conditions;

- (NSString *) conditionScript;

- (NSDictionary *) scriptInfo;
- (NSString *) scriptName;

@end


@interface OOEquipmentType (Conveniences)

- (OOTechLevelID) effectiveTechLevel;

@end
