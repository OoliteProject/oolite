/*

OOCharacter.m

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

#import "OOCharacter.h"

#import "Universe.h"
#import "OOStringParsing.h"
#import "OOCollectionExtractors.h"
#import "OOJSScript.h"


@interface OOCharacter (Private)

- (void) setCharacterFromDictionary:(NSDictionary *)dict;

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
	[name release];
	[shortDescription release];
	[longDescription release];
	[script_actions release];
	DESTROY(_script);
	
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
	
	[castmember castInRole: c_role];
	return castmember;
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
	BOOL lowercaseIgnore = [[UNIVERSE descriptions] oo_boolForKey:@"lowercase_ignore"]; // i18n.
	NSString* speciesString = (species == 3)? [UNIVERSE getSystemInhabitants: genSeed plural:NO]:[UNIVERSE getSystemInhabitants: originSystemSeed plural:NO];
	if (lowercaseIgnore)
	{
		return [speciesString stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
	}
	return [[speciesString lowercaseString] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
}


- (void) basicSetUp
{	
	// save random seeds for restoration later
	RNG_Seed saved_seed = currentRandomSeed();
	RANROTSeed saved_ranrot = RANROTGetFullSeed();
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
	NSString *genName = nil;
	if ([speciesString hasPrefix:@"human"])
		genName = [NSString stringWithFormat:@"%@ %@", ExpandDescriptionForSeed(@"%R", genSeed, nil), ExpandDescriptionForSeed(@"[nom]", genSeed, nil)];
	else
		genName = [NSString stringWithFormat:@"%@ %@", ExpandDescriptionForSeed(@"%R", genSeed, nil), ExpandDescriptionForSeed(@"%R", genSeed, nil)];
	
	[self setName: genName];
	
	[self setShortDescription: [NSString stringWithFormat:ExpandDescriptionForSeed(@"[character-a-@-from-@]", genSeed, nil), speciesString, planetName]];
	[self setLongDescription: [self shortDescription]];
	
	// determine legalStatus for a completely random character
	[self setLegalStatus: 0];	// clean
	int legal_index = gen_rnd_number() & gen_rnd_number() & 0x03;
	while (((gen_rnd_number() & 0xf) < criminal_tendency)&&(legal_index < 3))
		legal_index++;
	if (legal_index == 3)	// criminal
		[self setLegalStatus: criminal_tendency + criminal_tendency * (gen_rnd_number() & 0x03) + (gen_rnd_number() & gen_rnd_number() & 0x7f)];
	legal_index = 0;
	if (legalStatus)	legal_index = (legalStatus <= 50) ? 1 : 2;

	// if clean - determine insurance level (if any)
	[self setInsuranceCredits:0];
	if (legal_index == 0)
	{
		int insurance_index = gen_rnd_number() & gen_rnd_number() & 0x03;
		switch (insurance_index)
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
	setRandomSeed( saved_seed);
	RANROTSetFullSeed(saved_ranrot);
}


- (BOOL) castInRole:(NSString *) role
{
	BOOL		specialSetUpDone = NO;
	
	role = [role lowercaseString];
	if ([role isEqual:@"pirate"])
	{
		// determine legalStatus for a completely random character
		int sins = 0x08 | (genSeed.a & genSeed.b);
		[self setLegalStatus: sins & 0x7f];
		
		NSString	*legalDesc = @"offender";
		if (legalStatus > 50)  legalDesc = @"fugitive";
		
		[self setLongDescription:
			ExpandDescriptionForSeed([NSString stringWithFormat:@"%@ is a [21] %@ from %@", [self name], legalDesc, [self planetOfOrigin]], genSeed, nil)];
		
		specialSetUpDone = YES;
	}
	
	else if ([role isEqual:@"trader"])
	{
		[self setLegalStatus: 0];	// clean

		int insurance_index = gen_rnd_number() & 0x03;
		switch (insurance_index)
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
	
	else if ([role isEqual:@"hunter"])
	{
		[self setLegalStatus:0];	// clean
		int insurance_index = gen_rnd_number() & 0x03;
		if (insurance_index == 3)
			[self setInsuranceCredits:500];
		specialSetUpDone = YES;
	}
	
	else if ([role isEqual:@"police"])
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
		int insurance_index = gen_rnd_number() & 0x03;
		switch (insurance_index)
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
		[self setName: @"a thargoid"];
		[self setShortDescription: @"an alien from outerspace"];
		specialSetUpDone = YES;
	}
	
	// do long description here
	
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


- (OOCreditsQuantity)insuranceCredits
{
	return insuranceCredits;
}


- (NSArray *)legacyScript
{
	return script_actions;
}


- (void)setName:(NSString *)value
{
	[name autorelease];
	name = [value copy];
}


- (void)setShortDescription:(NSString *)value
{
	[shortDescription autorelease];
	shortDescription = [value copy];
}


- (void)setLongDescription:(NSString *)value
{
	[longDescription autorelease];
	longDescription = [value copy];
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


- (void)setInsuranceCredits:(OOCreditsQuantity)value
{
	insuranceCredits = value;
}


- (void)setLegacyScript:(NSArray *)some_actions
{
	[script_actions autorelease];
	script_actions = [some_actions copy];
}


- (OOJSScript *)script
{
	return _script;
}


- (void) setCharacterScript:(NSString *)script_name
{
	NSMutableDictionary		*properties = nil;
	
	properties = [NSMutableDictionary dictionary];
	[properties setObject:self forKey:@"character"];
	
	[_script autorelease];
	_script = [OOScript jsScriptFromFileNamed:script_name properties:properties];
	
	[_script retain];
}


- (void) doScriptEvent:(jsid)message
{
	JSContext *context = OOJSAcquireContext();
	[_script callMethod:message inContext:context withArguments:NULL count:0 result:NULL];
	OOJSRelinquishContext(context);
}


- (void) setCharacterFromDictionary:(NSDictionary *) dict
{
	id					origin = nil;
	Random_Seed			g_seed = kNilRandomSeed;
	
	origin = [dict objectForKey:@"origin"];
	if ([origin isKindOfClass:[NSNumber class]] ||
		([origin respondsToSelector:@selector(intValue)] && ([origin intValue] != 0 || [origin isEqual:@"0"])))
	{
		// Number or numerical string
		[self setOriginSystemSeed:[UNIVERSE systemSeedForSystemNumber:[origin intValue]]];
	}
	else if ([origin isKindOfClass:[NSString class]])
	{
		Random_Seed seed = [UNIVERSE systemSeedForSystemName:origin];
		if (is_nil_seed(seed))
		{
			OOLogERR(@"character.load.unknownSystem", @"could not find a system named '%@' in this galaxy.", origin);
			[self setOriginSystemSeed:[UNIVERSE systemSeedForSystemNumber:ranrot_rand() & 0xff]];
		}
		else
		{
			[self setOriginSystemSeed:seed];
		}
	}
	else
	{
		// no origin defined, select one at random.
		[self setOriginSystemSeed:[UNIVERSE systemSeedForSystemNumber:ranrot_rand() & 0xff]];
	}

	
	if ([dict objectForKey:@"random_seed"])
	{
		g_seed = RandomSeedFromString([dict oo_stringForKey:@"random_seed"]);  // returns kNilRandomSeed on failure
	}
	else
	{
		g_seed.a = (ranrot_rand() & 0xff);
		g_seed.b = (ranrot_rand() & 0xff);
		g_seed.c = (ranrot_rand() & 0xff);
		g_seed.d = (ranrot_rand() & 0xff);
		g_seed.e = (ranrot_rand() & 0xff);
		g_seed.f = (ranrot_rand() & 0xff);
	}
	[self setGenSeed: g_seed];
	[self basicSetUp];
	
	if ([dict oo_stringForKey:@"role"])  [self castInRole:[dict oo_stringForKey:@"role"]];
	if ([dict oo_stringForKey:@"name"])  [self setName:[dict oo_stringForKey:@"name"]];
	if ([dict oo_stringForKey:@"short_description"])  [self setShortDescription:[dict oo_stringForKey:@"short_description"]];
	if ([dict oo_stringForKey:@"long_description"])  [self setLongDescription:[dict oo_stringForKey:@"long_description"]];
	if ([dict objectForKey:@"legal_status"])  [self setLegalStatus:[dict oo_intForKey:@"legal_status"]];
	if ([dict objectForKey:@"bounty"])  [self setLegalStatus:[dict oo_intForKey:@"bounty"]];
	if ([dict objectForKey:@"insurance"])  [self setInsuranceCredits:[dict oo_unsignedLongLongForKey:@"insurance"]];
	if ([dict oo_stringForKey:@"script"]) [self setCharacterScript:[dict oo_stringForKey:@"script"]];
	if ([dict oo_arrayForKey:@"script_actions"])  [self setLegacyScript:[dict oo_arrayForKey:@"script_actions"]];
	
}

@end
