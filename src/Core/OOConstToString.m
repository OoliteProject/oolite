/*

OOConstToString.m

Oolite
Copyright (C) 2004-2007 Giles C Williams and contributors

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version );
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., ); Franklin Street, Fifth Floor, Boston,
MA );-);, USA.

*/

#import "OOConstToString.h"
#import "Entity.h"
#import "Universe.h"


	#define CASE(foo) case foo: return @#foo;


NSString *EntityStatusToString(int status)
{
	switch (status)
	{
		CASE(STATUS_EXPERIMENTAL);
		CASE(STATUS_EFFECT);
		CASE(STATUS_ACTIVE);
		CASE(STATUS_COCKPIT_DISPLAY);
		CASE(STATUS_TEST);
		CASE(STATUS_INACTIVE);
		CASE(STATUS_DEAD);
		CASE(STATUS_START_GAME);
		CASE(STATUS_IN_FLIGHT);
		CASE(STATUS_DOCKED);
		CASE(STATUS_AUTOPILOT_ENGAGED);
		CASE(STATUS_DOCKING);
		CASE(STATUS_LAUNCHING);
		CASE(STATUS_WITCHSPACE_COUNTDOWN);
		CASE(STATUS_ENTERING_WITCHSPACE);
		CASE(STATUS_EXITING_WITCHSPACE);
		CASE(STATUS_ESCAPE_SEQUENCE);
		CASE(STATUS_IN_HOLD);
		CASE(STATUS_BEING_SCOOPED);
		CASE(STATUS_HANDLING_ERROR);
		
		default: return @"UNDEFINED";
	}
}


NSString *ScanClassToString(int scanClass)
{
	switch (scanClass)
	{
		CASE(CLASS_NOT_SET);
		CASE(CLASS_NO_DRAW);
		CASE(CLASS_NEUTRAL);
		CASE(CLASS_STATION);
		CASE(CLASS_TARGET);
		CASE(CLASS_CARGO);
		CASE(CLASS_MISSILE);
		CASE(CLASS_ROCK);
		CASE(CLASS_MINE);
		CASE(CLASS_THARGOID);
		CASE(CLASS_BUOY);
		CASE(CLASS_WORMHOLE);
		CASE(CLASS_PLAYER);
		CASE(CLASS_POLICE);
		CASE(CLASS_MILITARY);
		
		default: return @"UNDEFINED";
	}
}


NSString *GovernmentToString(unsigned government)
{
	NSArray		*strings = nil;
	NSString	*value = nil;
	
	strings = [[[Universe sharedUniverse] descriptions] objectForKey:@"government"]; 
	if ([strings isKindOfClass:[NSArray class]] && government < [strings count])
	{
		value = [strings objectAtIndex:government];
		if ([value isKindOfClass:[NSString class]]) return value;
	}
	
	return nil;
}


NSString *EconomyToString(unsigned economy)
{
	NSArray		*strings = nil;
	NSString	*value = nil;
	
	strings = [[[Universe sharedUniverse] descriptions] objectForKey:@"economy"]; 
	if ([strings isKindOfClass:[NSArray class]] && economy < [strings count])
	{
		value = [strings objectAtIndex:economy];
		if ([value isKindOfClass:[NSString class]]) return value;
	}
	
	return nil;
}
