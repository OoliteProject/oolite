//
//  OOCharacter.m
//  Oolite
/*
 *
 *  Oolite
 *
 *  Created by Giles Williams on Thu Nov 03 2004.
 *  Copyright (c) 2004 for aegidian.org. All rights reserved.
 *

Copyright (c) 2004, Giles C Williams
All rights reserved.

This work is licensed under the Creative Commons Attribution-NonCommercial-ShareAlike License.
To view a copy of this license, visit http://creativecommons.org/licenses/by-nc-sa/2.0/
or send a letter to Creative Commons, 559 Nathan Abbott Way, Stanford, California 94305, USA.

You are free:

•	to copy, distribute, display, and perform the work
•	to make derivative works

Under the following conditions:

•	Attribution. You must give the original author credit.

•	Noncommercial. You may not use this work for commercial purposes.

•	Share Alike. If you alter, transform, or build upon this work,
you may distribute the resulting work only under a license identical to this one.

For any reuse or distribution, you must make clear to others the license terms of this work.

Any of these conditions can be waived if you get permission from the copyright holder.

Your fair use and other rights are in no way affected by the above.

*/

#import "OOCharacter.h"


@implementation OOCharacter

- (void) dealloc
{
	if (name)
		[name release];
	if (shortDescription)
		[shortDescription release];
	if (longDescription)
		[longDescription release];
	[super dealloc];
}

- (id) initWithGenSeed:(Random_Seed) g_seed andOriginalSystemSeed:(Random_Seed) s_seed
{
	self = [super init];
	
	// do Pilot set-up
	
	return self;
}

- (id) initWithRole:(NSString*) role andOriginalSystemSeed:(Random_Seed) s_seed
{
	self = [super init];
	
	// do Pilot set-up
	
	return self;
}

- (NSString*)	name
{
	return name;
}
- (NSString*)	shortDescription
{
	return shortDescription;
}
- (NSString*)	longDescription
{
	return longDescription;
}
- (Random_Seed)	originSystemSeed
{
	return originSystemSeed;
}
- (Random_Seed)	genSeed
{
	return genSeed;
}
- (int)			legalStatus
{
	return legalStatus;
}
- (int)			insuranceCredits
{
	return insuranceCredits;
}

- setName: (NSString*) value
{
	if (name)
		[name autorelease];
	name = [value retain];
}
- setShortDescription: (NSString*) value
{
	if (shortDescription)
		[shortDescription autorelease];
	shortDescription = [value retain];
}
- setLongDescription: (NSString*) longDescription
{
	if (longDescription)
		[longDescription autorelease];
	longDescription = [value retain];
}
- setOriginSystemSeed: (Random_Seed) value
{
	originSystemSeed = value;
}
- setGenSeed: (Random_Seed) value
{
	genSeed = value;
}
- setLegalStatus: (int) value
{
	legalStatus = value;
}
- setInsuranceCredits; (int) value
{
	insuranceCredits = value;
}


@end
