/*

OOCharacter.m

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

#import "OOCharacter.h"

#import "Universe.h"
#import "OOStringExpander.h"
#import "OOStringParsing.h"
#import "OOCollectionExtractors.h"
#import "OOJSScript.h"


@interface OOCharacter (Private)

- (id) initWithGenSeed:(Random_Seed)characterSeed andOriginalSystem:(OOSystemID)systemSeed;
- (void) setCharacterFromDictionary:(NSDictionary *)dict;

- (void)setOriginSystem:(OOSystemID)value;
- (Random_Seed)genSeed;

@end


@implementation OOCharacter

- (NSString *) descriptionComponents
{
	return [NSString stringWithFormat:@"%@, %@. bounty: %i insurance: %llu", [self name], [self shortDescription], [self legalStatus], [self insuranceCredits]];
}


- (NSString *) oo_jsClassName
{
	return @"Character";
}


- (void) dealloc
{
	[_name release];
	[_shortDescription release];
	[_scriptActions release];
	DESTROY(_script);
	
	[super dealloc];
}


- (id) initWithGenSeed:(Random_Seed)characterSeed andOriginalSystem:(OOSystemID)system
{
	if ((self = [super init]))
	{
		// do character set-up
		_genSeed = characterSeed;
		_originSystem = system;
		
		[self basicSetUp];
	}
	return self;
}


- (id) initWithRole:(NSString *)role andOriginalSystem:(OOSystemID)system
{
	Random_Seed seed;
	make_pseudo_random_seed(&seed);
	
	if ((self = [self initWithGenSeed:seed andOriginalSystem:system]))
	{
		[self castInRole:role];
	}
	
	return self;
}

+ (OOCharacter *) characterWithRole:(NSString *)role andOriginalSystem:(OOSystemID)system
{
	return [[[self alloc] initWithRole:role andOriginalSystem:system] autorelease];
}


+ (OOCharacter *) randomCharacterWithRole:(NSString *)role andOriginalSystem:(OOSystemID)system
{
	Random_Seed seed;
	
	seed.a = (Ranrot() & 0xff);
	seed.b = (Ranrot() & 0xff);
	seed.c = (Ranrot() & 0xff);
	seed.d = (Ranrot() & 0xff);
	seed.e = (Ranrot() & 0xff);
	seed.f = (Ranrot() & 0xff);
	
	OOCharacter	*character = [[[OOCharacter alloc] initWithGenSeed:seed andOriginalSystem:system] autorelease];
	[character castInRole:role];
	
	return character;
}


+ (OOCharacter *) characterWithDictionary:(NSDictionary *)dict
{
	OOCharacter	*character = [[[OOCharacter alloc] init] autorelease];
	[character setCharacterFromDictionary:dict];
	
	return character;
}


- (NSString *) planetOfOrigin
{
	// determine the planet of origin
	NSDictionary *originInfo = [UNIVERSE generateSystemData:[self planetIDOfOrigin]];
	return [originInfo objectForKey:KEY_NAME];
}


- (OOSystemID) planetIDOfOrigin
{
	// determine the planet of origin
	return _originSystem;
}


- (NSString *) species
{
	// determine the character's species
	int species = [self genSeed].f & 0x03;	// 0-1 native to home system, 2 human colonial, 3 other
	NSString* speciesString = nil;
	if (species == 3)  speciesString = [UNIVERSE getSystemInhabitants:[self genSeed].e plural:NO];
	else  speciesString = [UNIVERSE getSystemInhabitants:[self planetIDOfOrigin] plural:NO];
	
	if (![[UNIVERSE descriptions] oo_boolForKey:@"lowercase_ignore"])
	{
		speciesString = [speciesString lowercaseString];
	}
	
	return [speciesString stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
}


- (void) basicSetUp
{	
	// save random seeds for restoration later
	RNG_Seed savedRNGSeed = currentRandomSeed();
	RANROTSeed savedRANROTSeed = RANROTGetFullSeed();
	// set RNG to character seed
	Random_Seed genSeed = [self genSeed];
	seed_for_planet_description(genSeed);

	// determine the planet of origin
	NSDictionary *originInfo = [UNIVERSE generateSystemData:[self planetIDOfOrigin]];
	NSString *planet = [originInfo oo_stringForKey:KEY_NAME];
	OOGovernmentID government = [originInfo oo_intForKey:KEY_GOVERNMENT]; // 0 .. 7 (0 anarchic .. 7 most stable)
	int criminalTendency = government ^ 0x07;

	// determine the character's species
	NSString *species = [self species];
	
	// determine the character's name
	seed_RNG_only_for_planet_description(genSeed);
	NSString *genName = nil;
	if ([species hasPrefix:@"human"])
	{
		genName = [NSString stringWithFormat:@"%@ %@", OOExpandWithSeed(genSeed, @"%R"), OOExpandKeyWithSeed(genSeed, @"nom")];
	} else {
		/*	NOTE: we can't use "%R %R" because that will produce the same string
			twice. TODO: is there a reason not to use %N and kOOExpandGoodRNG
			here? Is there some context where we rely on being able to get the
			same name for a given genSeed?
		 */
		genName = [NSString stringWithFormat:@"%@ %@", OOExpandWithSeed(genSeed, @"%R"), OOExpandWithSeed(genSeed, @"%R")];
	}
	[self setName:genName];
	
	[self setShortDescription:OOExpandKeyWithSeed(genSeed, @"character-generic-description", species, planet)];
	
	// determine _legalStatus for a completely random character
	[self setLegalStatus:0];	// clean
	int legalIndex = gen_rnd_number() & gen_rnd_number() & 0x03;
	while (((gen_rnd_number() & 0xf) < criminalTendency) && (legalIndex < 3))
	{
		legalIndex++;
	}
	if (legalIndex == 3)
	{
		// criminal
		[self setLegalStatus:criminalTendency + criminalTendency * (gen_rnd_number() & 0x03) + (gen_rnd_number() & gen_rnd_number() & 0x7f)];
	}
	legalIndex = 0;
	if (_legalStatus > 0)  legalIndex = (_legalStatus <= 50) ? 1 : 2;

	// if clean - determine insurance level (if any)
	[self setInsuranceCredits:0];
	if (legalIndex == 0)
	{
		int insuranceIndex = gen_rnd_number() & gen_rnd_number() & 0x03;
		switch (insuranceIndex)
		{
			case 1:
				[self setInsuranceCredits:125];
				break;
			case 2:
				[self setInsuranceCredits:250];
				break;
			case 3:
				[self setInsuranceCredits:500];
		}
	}
	
	// restore random seed
	setRandomSeed( savedRNGSeed);
	RANROTSetFullSeed(savedRANROTSeed);
}


- (BOOL) castInRole:(NSString *)role
{
	BOOL specialSetUpDone = NO;
	
	role = [role lowercaseString];
	if ([role hasPrefix:@"pirate"])
	{
		// determine _legalStatus for a completely random character
		Random_Seed genSeed = [self genSeed];
		int sins = 0x08 | (genSeed.a & genSeed.b);
		[self setLegalStatus:sins & 0x7f];
		
		specialSetUpDone = YES;
	}
	else if ([role hasPrefix:@"trader"])
	{
		[self setLegalStatus:0];	// clean

		int insuranceIndex = gen_rnd_number() & 0x03;
		switch (insuranceIndex)
		{
			case 0:
				[self setInsuranceCredits:0];
				break;
			case 1:
				[self setInsuranceCredits:125];
				break;
			case 2:
				[self setInsuranceCredits:250];
				break;
			case 3:
				[self setInsuranceCredits:500];
		}
		specialSetUpDone = YES;
	}
	else if ([role hasPrefix:@"hunter"])
	{
		[self setLegalStatus:0];	// clean
		int insuranceIndex = gen_rnd_number() & 0x03;
		if (insuranceIndex == 3)
			[self setInsuranceCredits:500];
		specialSetUpDone = YES;
	}
	else if ([role hasPrefix:@"police"])
	{
		[self setLegalStatus:0];	// clean
		[self setInsuranceCredits:125];
		specialSetUpDone = YES;
	}
	else if ([role isEqual:@"miner"])
	{
		[self setLegalStatus:0];	// clean
		[self setInsuranceCredits:25];
		specialSetUpDone = YES;
	}
	else if ([role isEqual:@"passenger"])
	{
		[self setLegalStatus:0];	// clean
		int insuranceIndex = gen_rnd_number() & 0x03;
		switch (insuranceIndex)
		{
			case 0:
				[self setInsuranceCredits:25];
				break;
			case 1:
				[self setInsuranceCredits:125];
				break;
			case 2:
				[self setInsuranceCredits:250];
				break;
			case 3:
				[self setInsuranceCredits:500];
		}
		specialSetUpDone = YES;
	}
	else if ([role isEqual:@"slave"])
	{
		[self setLegalStatus:0];	// clean
		[self setInsuranceCredits:0];
		specialSetUpDone = YES;
	}
	else if ([role isEqual:@"thargoid"])
	{
		[self setLegalStatus:100];
		[self setInsuranceCredits:0];
		[self setName:DESC(@"character-thargoid-name")];
		[self setShortDescription:DESC(@"character-a-thargoid")];
		specialSetUpDone = YES;
	}
	
	// do long description here
	
	return specialSetUpDone;
}


- (NSString *)name
{
	return _name;
}


- (NSString *)shortDescription
{
	return _shortDescription;
}


- (Random_Seed)genSeed
{
	return _genSeed;
}


- (int)legalStatus
{
	return _legalStatus;
}


- (OOCreditsQuantity)insuranceCredits
{
	return _insuranceCredits;
}


- (NSArray *)legacyScript
{
	return _scriptActions;
}


- (NSDictionary *) infoForScripting
{
	return [NSDictionary dictionaryWithObjectsAndKeys:
		  [self name], @"name",
		  [self shortDescription], @"description",
		  [self species], @"species",
		  [NSNumber numberWithInt:[self legalStatus]], @"legalStatus",
	      [NSNumber numberWithUnsignedLongLong:[self insuranceCredits]], @"insuranceCredits",
		  [NSNumber numberWithInt:[self planetIDOfOrigin]], @"homeSystem",
		  nil];
}


- (void)setName:(NSString *)value
{
	[_name autorelease];
	_name = [value copy];
}


- (void)setShortDescription:(NSString *)value
{
	[_shortDescription autorelease];
	_shortDescription = [value copy];
}


- (void)setOriginSystem:(OOSystemID)value
{
	_originSystem = value;
}


- (void)setGenSeed:(Random_Seed)value
{
	_genSeed = value;
}


- (void)setLegalStatus:(int)value
{
	_legalStatus = value;
}


- (void)setInsuranceCredits:(OOCreditsQuantity)value
{
	_insuranceCredits = value;
}


- (void)setLegacyScript:(NSArray *)some_actions
{
	[_scriptActions autorelease];
	_scriptActions = [some_actions copy];
}


- (OOJSScript *)script
{
	return _script;
}


- (void) setCharacterScript:(NSString *)scriptName
{
	[_script autorelease];
	_script = [OOScript jsScriptFromFileNamed:scriptName
								   properties:[NSDictionary dictionaryWithObject:self forKey:@"character"]];
	[_script retain];
}


- (void) doScriptEvent:(jsid)message
{
	JSContext *context = OOJSAcquireContext();
	[_script callMethod:message inContext:context withArguments:NULL count:0 result:NULL];
	OOJSRelinquishContext(context);
}


- (void) setCharacterFromDictionary:(NSDictionary *)dict
{
	id					origin = nil;
	Random_Seed			seed;
	
	origin = [dict objectForKey:@"origin"];
	if ([origin isKindOfClass:[NSNumber class]] ||
		([origin respondsToSelector:@selector(intValue)] && ([origin intValue] != 0 || [origin isEqual:@"0"])))
	{
		// Number or numerical string
		[self setOriginSystem:[origin intValue]];
	}
	else if ([origin isKindOfClass:[NSString class]])
	{
		OOSystemID sys = [UNIVERSE findSystemFromName:origin];
		if (sys < 0)
		{
			OOLogERR(@"character.load.unknownSystem", @"could not find a system named '%@' in this galaxy.", origin);
			[self setOriginSystem:(ranrot_rand() & 0xff)];
		}
		else
		{
			[self setOriginSystem:sys];
		}
	}
	else
	{
		// no origin defined, select one at random.
		[self setOriginSystem:(ranrot_rand() & 0xff)];
	}

	if ([dict objectForKey:@"random_seed"])
	{
		seed = RandomSeedFromString([dict oo_stringForKey:@"random_seed"]);  // returns kNilRandomSeed on failure
	}
	else
	{
		seed.a = (ranrot_rand() & 0xff);
		seed.b = (ranrot_rand() & 0xff);
		seed.c = (ranrot_rand() & 0xff);
		seed.d = (ranrot_rand() & 0xff);
		seed.e = (ranrot_rand() & 0xff);
		seed.f = (ranrot_rand() & 0xff);
	}
	[self setGenSeed:seed];
	[self basicSetUp];
	
	if ([dict oo_stringForKey:@"role"])  [self castInRole:[dict oo_stringForKey:@"role"]];
	if ([dict oo_stringForKey:@"name"])  [self setName:[dict oo_stringForKey:@"name"]];
	if ([dict oo_stringForKey:@"short_description"])  [self setShortDescription:[dict oo_stringForKey:@"short_description"]];
	if ([dict objectForKey:@"legal_status"])  [self setLegalStatus:[dict oo_intForKey:@"legal_status"]];
	if ([dict objectForKey:@"bounty"])  [self setLegalStatus:[dict oo_intForKey:@"bounty"]];
	if ([dict objectForKey:@"insurance"])  [self setInsuranceCredits:[dict oo_unsignedLongLongForKey:@"insurance"]];
	if ([dict oo_stringForKey:@"script"]) [self setCharacterScript:[dict oo_stringForKey:@"script"]];
	if ([dict oo_arrayForKey:@"script_actions"])  [self setLegacyScript:[dict oo_arrayForKey:@"script_actions"]];
	
}

@end
