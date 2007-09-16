/*

OOCharacter.m

Oolite
Copyright (C) 2004-2007 Giles C Williams and contributors

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

#import "OOCharacter.h"

#import "Universe.h"
#import "OOBrain.h"
#import "OOStringParsing.h"

#include "legacy_random.h"

@implementation OOCharacter

- (NSString *) descriptionComponents
{
	return [NSString stringWithFormat:@"%@, %@. bounty: %i insurance:%i", [self name], [self shortDescription], [self legalStatus], [self insuranceCredits]];
}


- (NSString *) jsClassName
{
	return @"Character";
}


- (void) dealloc
{
	[name release];
	[shortDescription release];
	[longDescription release];
	[script_actions release];
	[brain release];
	
	[super dealloc];
}


- (id) initWithGenSeed:(Random_Seed) g_seed andOriginalSystemSeed:(Random_Seed) s_seed
{
	self = [super init];
	
	// do character set-up
	genSeed = g_seed;
	originSystemSeed = s_seed;
	
	[self basicSetUp];
	
	return self;
}


- (id) initWithRole:(NSString *) role andOriginalSystemSeed:(Random_Seed) s_seed
{
	self = [super init];
	
	// do character set-up
	originSystemSeed = s_seed;
	make_pseudo_random_seed( &genSeed);
	
	[self basicSetUp];
	
	[self castInRole: role];
	
	return self;
}

+ (OOCharacter *) characterWithRole:(NSString *) c_role andOriginalSystem:(Random_Seed) o_seed
{
	return [[[OOCharacter alloc] initWithRole: c_role andOriginalSystemSeed: o_seed] autorelease];
}

+ (OOCharacter *) randomCharacterWithRole:(NSString *) c_role andOriginalSystem:(Random_Seed) o_seed
{
	Random_Seed r_seed;
	
	r_seed.a = (ranrot_rand() & 0xff);
	r_seed.b = (ranrot_rand() & 0xff);
	r_seed.c = (ranrot_rand() & 0xff);
	r_seed.d = (ranrot_rand() & 0xff);
	r_seed.e = (ranrot_rand() & 0xff);
	r_seed.f = (ranrot_rand() & 0xff);
	
	OOCharacter	*castmember = [[[OOCharacter alloc] initWithGenSeed: r_seed andOriginalSystemSeed: o_seed] autorelease];
	
	if ([castmember castInRole: c_role])
		return castmember;
	else
	{
		return castmember;
	}
}

+ (OOCharacter *) characterWithDictionary:(NSDictionary *) c_dict
{
	OOCharacter	*castmember = [[[OOCharacter alloc] init] autorelease];
	[castmember setCharacterFromDictionary: c_dict];
	return castmember;
}


- (NSString *) planetOfOrigin
{
	// determine the planet of origin
	NSDictionary* originInfo = [UNIVERSE generateSystemData: originSystemSeed];
	return [originInfo objectForKey: KEY_NAME];
}


- (NSString *) species
{
	// determine the character's species
	int species = genSeed.f & 0x03;	// 0-1 native to home system, 2 human colonial, 3 other
	NSString* speciesString = (species == 3)? [UNIVERSE generateSystemInhabitants: genSeed plural:NO]:[UNIVERSE generateSystemInhabitants: originSystemSeed plural:NO];
	return [[speciesString lowercaseString] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
}


- (void) basicSetUp
{	
	// save random seeds for restoration later
	RNG_Seed saved_seed = currentRandomSeed();
	// set RNG to character seed
	seed_for_planet_description(genSeed);

	// determine the planet of origin
	NSDictionary* originInfo = [UNIVERSE generateSystemData: originSystemSeed];
	NSString* planetName = [originInfo objectForKey: KEY_NAME];
	int government = [[originInfo objectForKey:KEY_GOVERNMENT] intValue]; // 0 .. 7 (0 anarchic .. 7 most stable)
	int criminal_tendency = government ^ 0x07;

	// determine the character's species
	NSString* speciesString = [self species];
	
	// determine the character's name
	seed_RNG_only_for_planet_description(genSeed);
	NSString* genName;
	if ([speciesString hasPrefix:@"human"])
		genName = [NSString stringWithFormat:@"%@ %@", ExpandDescriptionForSeed(@"%R", genSeed), ExpandDescriptionForSeed(@"[nom]", genSeed)];
	else
		genName = [NSString stringWithFormat:@"%@ %@", ExpandDescriptionForSeed(@"%R", genSeed), ExpandDescriptionForSeed(@"%R", genSeed)];
	
	[self setName: genName];
	
	[self setShortDescription: [NSString stringWithFormat:ExpandDescriptionForSeed(@"[character-a-@-from-@]", genSeed), speciesString, planetName]];
	[self setLongDescription: [self shortDescription]];
	
	// determine legalStatus for a completely random character
	NSString *legalDesc;
	[self setLegalStatus: 0];	// clean
	int legal_index = gen_rnd_number() & gen_rnd_number() & 0x03;
	while (((gen_rnd_number() & 0xf) < criminal_tendency)&&(legal_index < 3))
		legal_index++;
	if (legal_index == 3)	// criminal
		[self setLegalStatus: criminal_tendency + criminal_tendency * (gen_rnd_number() & 0x03) + (gen_rnd_number() & gen_rnd_number() & 0x7f)];
	legal_index = 0;
	if (legalStatus)	legal_index = (legalStatus <= 50) ? 1 : 2;
	switch (legal_index)
	{
		case 0:
			legalDesc = @"clean";
			break;
		case 1:
			legalDesc = @"an offender";
			break;
		case 2:
			legalDesc = @"a fugitive";
			break;
		default:
			// never should get here
			legalDesc = @"an unperson";
	}

	// if clean - determine insurance level (if any)
	[self setInsuranceCredits: 0];
	if (legal_index == 0)
	{
		int insurance_index = gen_rnd_number() & gen_rnd_number() & 0x03;
		switch (insurance_index)
		{
			case 1:
				[self setInsuranceCredits: 125];
				break;
			case 2:
				[self setInsuranceCredits: 250];
				break;
			case 3:
				[self setInsuranceCredits: 500];
		}
	}
	
	// restore random seed
	setRandomSeed( saved_seed);
}


- (BOOL) castInRole:(NSString *) role
{
	BOOL specialSetUpDone = NO;
	
	NSString *legalDesc;
	if ([[role lowercaseString] isEqual:@"pirate"])
	{
		// determine legalStatus for a completely random character
		int sins = 0x08 | (genSeed.a & genSeed.b);
		[self setLegalStatus: sins & 0x7f];
		int legal_index = (legalStatus <= 50) ? 1 : 2;
		switch (legal_index)
		{
			case 1:
				legalDesc = @"offender";
				break;
			case 2:
				legalDesc = @"fugitive";
				break;
		}
		[self setLongDescription:
			ExpandDescriptionForSeed([NSString stringWithFormat:@"%@ is a [21] %@ from %@", [self name], legalDesc, [self planetOfOrigin]], genSeed)];
		
		specialSetUpDone = YES;
	}
	
	if ([[role lowercaseString] isEqual:@"trader"])
	{
		legalDesc = @"clean";
		[self setLegalStatus: 0];	// clean

		int insurance_index = gen_rnd_number() & 0x03;
		switch (insurance_index)
		{
			case 0:
				[self setInsuranceCredits: 0];
				break;
			case 1:
				[self setInsuranceCredits: 125];
				break;
			case 2:
				[self setInsuranceCredits: 250];
				break;
			case 3:
				[self setInsuranceCredits: 500];
		}
		specialSetUpDone = YES;
	}
	
	if ([[role lowercaseString] isEqual:@"hunter"])
	{
		legalDesc = @"clean";
		[self setLegalStatus: 0];	// clean
		int insurance_index = gen_rnd_number() & 0x03;
		if (insurance_index == 3)
			[self setInsuranceCredits: 500];
		specialSetUpDone = YES;
	}
	
	if ([[role lowercaseString] isEqual:@"police"])
	{
		legalDesc = @"clean";
		[self setLegalStatus: 0];	// clean
		[self setInsuranceCredits: 125];
		specialSetUpDone = YES;
	}
	
	if ([[role lowercaseString] isEqual:@"miner"])
	{
		legalDesc = @"clean";
		[self setLegalStatus: 0];	// clean
		[self setInsuranceCredits: 25];
		specialSetUpDone = YES;
	}
	
	if ([[role lowercaseString] isEqual:@"passenger"])
	{
		legalDesc = @"clean";
		[self setLegalStatus: 0];	// clean
		int insurance_index = gen_rnd_number() & 0x03;
		switch (insurance_index)
		{
			case 0:
				[self setInsuranceCredits: 25];
				break;
			case 1:
				[self setInsuranceCredits: 125];
				break;
			case 2:
				[self setInsuranceCredits: 250];
				break;
			case 3:
				[self setInsuranceCredits: 500];
		}
		specialSetUpDone = YES;
	}
	
	if ([[role lowercaseString] isEqual:@"slave"])
	{
		legalDesc = @"clean";
		[self setLegalStatus: 0];	// clean
		[self setInsuranceCredits: 0];
		specialSetUpDone = YES;
	}
	
	// do long description here
	//
	
	return specialSetUpDone;
}


- (NSString *)name
{
	return name;
}


- (NSString *)shortDescription
{
	return shortDescription;
}


- (NSString *)longDescription
{
	return longDescription;
}


- (Random_Seed)originSystemSeed
{
	return originSystemSeed;
}


- (Random_Seed)genSeed
{
	return genSeed;
}


- (int)legalStatus
{
	return legalStatus;
}


- (int)insuranceCredits
{
	return insuranceCredits;
}


- (NSArray *)script
{
	return script_actions;
}


- (OOBrain *)brain
{
	return brain;
}


- (void)setName:(NSString *)value
{
	if (name)
		[name autorelease];
	name = [value retain];
}


- (void)setShortDescription:(NSString *)value
{
	if (shortDescription)
		[shortDescription autorelease];
	shortDescription = [value retain];
}


- (void)setLongDescription:(NSString *)value
{
	if (longDescription)
		[longDescription autorelease];
	longDescription = [value retain];
}


- (void)setOriginSystemSeed:(Random_Seed)value
{
	originSystemSeed = value;
}


- (void)setGenSeed:(Random_Seed)value
{
	genSeed = value;
}


- (void)setLegalStatus:(int)value
{
	legalStatus = value;
}


- (void)setInsuranceCredits:(int)value
{
	insuranceCredits = value;
}


- (void)setScript:(NSArray *)some_actions
{
	if (script_actions)
		[script_actions autorelease];
	if (some_actions)
		script_actions = [some_actions retain];
	else
		script_actions = nil;
}


- (void) setBrain:(OOBrain *)aBrain
{
	if (brain)
		[brain release];
	brain = aBrain;
	if (brain)
	{
		[brain retain];
		[brain setOwner:self];
	}
}


- (void) setCharacterFromDictionary:(NSDictionary *) dict
{
	if ([dict objectForKey:@"origin"])
	{
		if (([[dict objectForKey:@"origin"] intValue] > 0) || [[dict objectForKey:@"origin"] isEqual:@"0"])
			[self setOriginSystemSeed:[UNIVERSE systemSeedForSystemNumber:[[dict objectForKey:@"origin"] intValue]]];
		else
			[self setOriginSystemSeed:[UNIVERSE systemSeedForSystemName:[dict objectForKey:@"origin"]]];
	}	
	if ([dict objectForKey:@"random_seed"])
	{
		Random_Seed g_seed = RandomSeedFromString([dict objectForKey:@"random_seed"]);
		[self setGenSeed: g_seed];
		[self basicSetUp];
	}
	
	if ([dict objectForKey:@"role"])  [self castInRole:[dict objectForKey:@"role"]];
	if ([dict objectForKey:@"name"])  [self setName:[dict objectForKey:@"name"]];
	if ([dict objectForKey:@"short_description"])  [self setShortDescription:[dict objectForKey:@"short_description"]];
	if ([dict objectForKey:@"long_description"])  [self setLongDescription:[dict objectForKey:@"long_description"]];
	if ([dict objectForKey:@"legal_status"])  [self setLegalStatus:[[dict objectForKey:@"legal_status"] intValue]];
	if ([dict objectForKey:@"bounty"])  [self setLegalStatus:[[dict objectForKey:@"bounty"] intValue]];
	if ([dict objectForKey:@"insurance"])  [self setInsuranceCredits:[[dict objectForKey:@"insurance"] intValue]];
	if ([dict objectForKey:@"script_actions"])  [self setScript:[dict objectForKey:@"script_actions"]];
		
}

@end
