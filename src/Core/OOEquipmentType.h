/*

OOEquipmentType.h

Manage the set of installed ships.


Oolite
Copyright (C) 2004-2008 Giles C Williams and contributors

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


This file may also be distributed under the MIT/X11 license:

Copyright (C) 2008 Jens Ayton

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

*/

#import "OOCocoa.h"
#import "OOTypes.h"


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
							_isMissileOrMine: 1;
	OOCargoQuantity			_requiredCargoSpace;
	NSSet					*_requiresEquipment;
	NSSet					*_requiresAnyEquipment;
	NSSet					*_incompatibleEquipment;
	NSArray					*_conditions;
}

+ (void) loadEquipment;			// Load equipment data; called on loading and when changing to/from strict mode.

+ (NSArray *) allEquipmentTypes;
+ (OOEquipmentType *) equipmentTypeWithIdentifier:(NSString *)identifier;

- (NSString *) identifier;
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
- (BOOL) isMissileOrMine;
- (BOOL) isPortableBetweenShips;

- (OOCargoQuantity) requiredCargoSpace;
- (NSSet *) requiresEquipment;		// Set of equipment identifiers; all items required
- (NSSet *) requiresAnyEquipment;	// Set of equipment identifiers; any item required
- (NSSet *) incompatibleEquipment;	// Set of equipment identifiers; all items prohibited

// FIXME: should have general mechanism to handle scripts or legacy conditions.
- (NSArray *) conditions;

@end
