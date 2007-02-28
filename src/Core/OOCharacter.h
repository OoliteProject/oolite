/*

OOCharacter.h

Represents an NPC person (as opposed to an NPC ship).

For Oolite
Copyright (C) 2006  Giles Williams

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

#import <Foundation/Foundation.h>

#import "legacy_random.h"

@class OOBrain, Universe;

@interface OOCharacter : NSObject
{
	NSString*	name;
	NSString*	shortDescription;
	NSString*	longDescription;
	Random_Seed	originSystemSeed;
	Random_Seed	genSeed;
	int			legalStatus;
	int			insuranceCredits;
	
	OOBrain*	brain;				// brain of character
	
	Universe*	universe;
	NSArray*	script_actions;
}

- (id) initWithGenSeed:(Random_Seed) g_seed andOriginalSystemSeed:(Random_Seed) s_seed inUniverse:(Universe*) uni;
- (id) initWithRole:(NSString*) role andOriginalSystemSeed:(Random_Seed) s_seed  inUniverse:(Universe*) uni;

+ (OOCharacter*) characterWithRole:(NSString*) c_role andOriginalSystem:(Random_Seed) o_seed inUniverse:(Universe*) uni;
+ (OOCharacter*) randomCharacterWithRole:(NSString*) c_role andOriginalSystem:(Random_Seed) o_seed inUniverse:(Universe*) uni;
+ (OOCharacter*) characterWithDictionary:(NSDictionary*) c_dict inUniverse:(Universe*) uni;

- (NSString*) planetOfOrigin;
- (NSString*) species;

- (void) basicSetUp;
- (BOOL) castInRole:(NSString*) role;

- (NSString*)	name;
- (NSString*)	shortDescription;
- (NSString*)	longDescription;
- (Random_Seed)	originSystemSeed;
- (Random_Seed)	genSeed;
- (int)			legalStatus;
- (int)			insuranceCredits;
- (NSArray*)	script;
- (OOBrain*)	brain;

- (void) setUniverse: (Universe*) uni;
- (void) setName: (NSString*) value;
- (void) setShortDescription: (NSString*) value;
- (void) setLongDescription: (NSString*) value;
- (void) setOriginSystemSeed: (Random_Seed) value;
- (void) setGenSeed: (Random_Seed) value;
- (void) setLegalStatus: (int) value;
- (void) setInsuranceCredits: (int) value;
- (void) setScript: (NSArray*) some_actions;

- (void) setBrain: (OOBrain*) aBrain;

- (void) setCharacterFromDictionary:(NSDictionary*) dict;

@end
