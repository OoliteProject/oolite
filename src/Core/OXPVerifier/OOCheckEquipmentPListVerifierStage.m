/*

OOCheckEquipmentPListVerifierStage.m


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

#import "OOCheckEquipmentPListVerifierStage.h"

#if OO_OXP_VERIFIER_ENABLED

#import "OOFileScannerVerifierStage.h"
#import "Universe.h"
#import "OOCollectionExtractors.h"

static NSString * const kStageName	= @"Checking equipment.plist";


@interface OOCheckEquipmentPListVerifierStage (OOPrivate)

- (void)runCheckWithEquipment:(NSArray *)equipmentPList;

@end


@implementation OOCheckEquipmentPListVerifierStage

- (NSString *)name
{
	return kStageName;
}


- (BOOL)shouldRun
{
	OOFileScannerVerifierStage	*fileScanner = nil;
	
	fileScanner = [[self verifier] fileScannerStage];
	return [fileScanner fileExists:@"equipment.plist"
						  inFolder:@"Config"
					referencedFrom:nil
					  checkBuiltIn:NO];
}


- (void)run
{
	OOFileScannerVerifierStage	*fileScanner = nil;
	NSArray						*equipmentPList = nil;
	
	fileScanner = [[self verifier] fileScannerStage];
	
	equipmentPList = [fileScanner plistNamed:@"equipment.plist"
									inFolder:@"Config"
							  referencedFrom:nil
								checkBuiltIn:NO];
	
	if (equipmentPList == nil)  return;
	
	// Check that it's an array
	if (![equipmentPList isKindOfClass:[NSArray class]])
	{
		OOLog(@"verifyOXP.equipmentPList.notArray", @"***** ERROR: equipment.plist is not an array.");
		return;
	}
	
	
	[self runCheckWithEquipment:equipmentPList];
}

@end


@implementation OOCheckEquipmentPListVerifierStage (OOPrivate)

- (void)runCheckWithEquipment:(NSArray *)equipmentPList
{
	NSEnumerator				*entryEnum = nil;
	NSArray						*entry = nil;
	unsigned					entryIndex = 0;
	NSUInteger					elemCount;
	NSString					*name = nil;
	NSString					*entryDesc = nil;
	
	for (entryEnum = [equipmentPList objectEnumerator]; (entry = [entryEnum nextObject]); )
	{
		++entryIndex;
		
		// Entries should be arrays.
		if (![entry isKindOfClass:[NSArray class]])
		{
			OOLog(@"verifyOXP.equipmentPList.entryNotArray", @"***** ERROR: equipment.plist entry %u of equipment.plist is not an array.", entryIndex);
			continue;
		}
		
		elemCount = [entry count];
		
		// Make a name for entry for display purposes.
		if (EQUIPMENT_KEY_INDEX < elemCount)  name = [entry oo_stringAtIndex:EQUIPMENT_KEY_INDEX];
		else  name = nil;
		
		if (name != nil)  entryDesc = [NSString stringWithFormat:@"%u (\"%@\")", entryIndex, name];
		else  entryDesc = [NSString stringWithFormat:@"%u", entryIndex];
		
		// Check that the entry has an acceptable number of elements.
		if (elemCount < 5)
		{
			OOLog(@"verifyOXP.equipmentPList.badEntrySize", @"***** ERROR: equipment.plist entry %@ has too few elements (%lu, should be 5 or 6).", entryDesc, elemCount);
			continue;
		}
		if (6 < elemCount)
		{
			OOLog(@"verifyOXP.equipmentPList.badEntrySize", @"----- WARNING: equipment.plist entry %@ has too many elements (%lu, should be 5 or 6).", entryDesc, elemCount);
		}
		
		/*	Check element types. The numbers are required to be unsigned
			integers; the use of a negative default will catch both negative
			values and unconvertable values.
		*/
		if ([entry oo_longAtIndex:EQUIPMENT_TECH_LEVEL_INDEX defaultValue:-1] < 0)
		{
			OOLog(@"verifyOXP.equipmentPList.badElementType", @"***** ERROR: tech level for entry %@ of equipment.plist is not a positive integer.", entryDesc);
		}
		if ([entry oo_longAtIndex:EQUIPMENT_PRICE_INDEX defaultValue:-1] < 0)
		{
			OOLog(@"verifyOXP.equipmentPList.badElementType", @"***** ERROR: price for entry %@ of equipment.plist is not a positive integer.", entryDesc);
		}
		if ([entry oo_stringAtIndex:EQUIPMENT_SHORT_DESC_INDEX] == nil)
		{
			OOLog(@"verifyOXP.equipmentPList.badElementType", @"***** ERROR: short description for entry %@ of equipment.plist is not a string.", entryDesc);
		}
		if ([entry oo_stringAtIndex:EQUIPMENT_KEY_INDEX] == nil)
		{
			OOLog(@"verifyOXP.equipmentPList.badElementType", @"***** ERROR: key for entry %@ of equipment.plist is not a string.", entryDesc);
		}
		if ([entry oo_stringAtIndex:EQUIPMENT_LONG_DESC_INDEX] == nil)
		{
			OOLog(@"verifyOXP.equipmentPList.badElementType", @"***** ERROR: long description for entry %@ of equipment.plist is not a string.", entryDesc);
		}
		
		if (5 < elemCount)
		{
			if ([entry oo_dictionaryAtIndex:EQUIPMENT_EXTRA_INFO_INDEX] == nil)
			{
				OOLog(@"verifyOXP.equipmentPList.badElementType", @"***** ERROR: equipment.plist entry %@'s extra information dictionary is not a dictionary.", entryDesc);
			}
			// TODO: verify contents of extra info dictionary.
		}
	}
}

@end

#endif
