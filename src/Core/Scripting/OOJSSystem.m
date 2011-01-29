/*
 
 OOJSSystem.m
 
 
 Oolite
 Copyright (C) 2004-2011 Giles C Williams and contributors
 
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

#import "OOJSSystem.h"
#import "OOJavaScriptEngine.h"

#import "OOJSVector.h"
#import "OOJSEntity.h"
#import "OOJSPlayer.h"
#import "Universe.h"
#import "OOPlanetEntity.h"
#import "PlayerEntityScriptMethods.h"
#import "OOJSSystemInfo.h"

#import "OOCollectionExtractors.h"
#import "OOConstToString.h"
#import "OOConstToJSString.h"
#import "OOEntityFilterPredicate.h"


static JSObject *sSystemPrototype;


// Support functions for entity search methods.
static BOOL GetRelativeToAndRange(JSContext *context, NSString *methodName, uintN *ioArgc, jsval **ioArgv, Entity **outRelativeTo, double *outRange);
static NSArray *FindJSVisibleEntities(EntityFilterPredicate predicate, void *parameter, Entity *relativeTo, double range);
static NSArray *FindShips(EntityFilterPredicate predicate, void *parameter, Entity *relativeTo, double range);
static NSComparisonResult CompareEntitiesByDistance(id a, id b, void *relativeTo);

static JSBool SystemAddShipsOrGroup(OOJS_NATIVE_ARGS, BOOL isGroup);
static JSBool SystemAddShipsOrGroupToRoute(OOJS_NATIVE_ARGS, BOOL isGroup);


static JSBool SystemGetProperty(OOJS_PROP_ARGS);
static JSBool SystemSetProperty(OOJS_PROP_ARGS);

static JSBool SystemToString(OOJS_NATIVE_ARGS);
static JSBool SystemAddPlanet(OOJS_NATIVE_ARGS);
static JSBool SystemAddMoon(OOJS_NATIVE_ARGS);
static JSBool SystemSendAllShipsAway(OOJS_NATIVE_ARGS);
static JSBool SystemCountShipsWithPrimaryRole(OOJS_NATIVE_ARGS);
static JSBool SystemCountShipsWithRole(OOJS_NATIVE_ARGS);
static JSBool SystemCountEntitiesWithScanClass(OOJS_NATIVE_ARGS);
static JSBool SystemShipsWithPrimaryRole(OOJS_NATIVE_ARGS);
static JSBool SystemShipsWithRole(OOJS_NATIVE_ARGS);
static JSBool SystemEntitiesWithScanClass(OOJS_NATIVE_ARGS);
static JSBool SystemFilteredEntities(OOJS_NATIVE_ARGS);

static JSBool SystemAddShips(OOJS_NATIVE_ARGS);
static JSBool SystemAddGroup(OOJS_NATIVE_ARGS);
static JSBool SystemAddShipsToRoute(OOJS_NATIVE_ARGS);
static JSBool SystemAddGroupToRoute(OOJS_NATIVE_ARGS);

static JSBool SystemLegacyAddShips(OOJS_NATIVE_ARGS);
static JSBool SystemLegacyAddSystemShips(OOJS_NATIVE_ARGS);
static JSBool SystemLegacyAddShipsAt(OOJS_NATIVE_ARGS);
static JSBool SystemLegacyAddShipsAtPrecisely(OOJS_NATIVE_ARGS);
static JSBool SystemLegacyAddShipsWithinRadius(OOJS_NATIVE_ARGS);
static JSBool SystemLegacySpawnShip(OOJS_NATIVE_ARGS);

static JSBool SystemStaticSystemNameForID(OOJS_NATIVE_ARGS);
static JSBool SystemStaticSystemIDForName(OOJS_NATIVE_ARGS);
static JSBool SystemStaticInfoForSystem(OOJS_NATIVE_ARGS);


static JSClass sSystemClass =
{
	"System",
	0,
	
	JS_PropertyStub,
	JS_PropertyStub,
	SystemGetProperty,
	SystemSetProperty,
	JS_EnumerateStub,
	JS_ResolveStub,
	JS_ConvertStub,
	JS_FinalizeStub
};


enum
{
	// Property IDs
	kSystem_allShips,				// ships in system, array of Ship, read-only
	kSystem_description,			// description, string, read/write
	kSystem_economy,				// economy ID, integer, read/write
	kSystem_economyDescription,		// economy ID description, string, read-only
	kSystem_government,				// government ID, integer, read/write
	kSystem_governmentDescription,	// government ID description, string, read-only
	kSystem_ID,						// planet number, integer, read-only
	kSystem_info,					// system info dictionary, SystemInfo, read/write
	kSystem_inhabitantsDescription,	// description of inhabitant species, string, read/write
	kSystem_isInterstellarSpace,	// is interstellar space, boolean, read-only
	kSystem_mainPlanet,				// system's main planet, Planet, read-only
	kSystem_mainStation,			// system's main station, Station, read-only
	kSystem_name,					// name, string, read/write
	kSystem_planets,				// planets in system, array of Planet, read-only
	kSystem_population,				// population, integer, read/write
	kSystem_productivity,			// productivity, integer, read/write
	kSystem_pseudoRandom100,		// constant-per-system pseudorandom number in [0..100), integer, read-only
	kSystem_pseudoRandom256,		// constant-per-system pseudorandom number in [0..256), integer, read-only
	kSystem_pseudoRandomNumber,		// constant-per-system pseudorandom number in [0..1), double, read-only
	kSystem_sun,					// system's sun, Planet, read-only
	kSystem_techLevel,				// tech level ID, integer, read/write
};


static JSPropertySpec sSystemProperties[] =
{
	// JS name					ID							flags
	{ "ID",						kSystem_ID,					OOJS_PROP_READONLY_CB },
	{ "name",					kSystem_name,				OOJS_PROP_READWRITE_CB },
	{ "description",			kSystem_description,		OOJS_PROP_READWRITE_CB },
	{ "inhabitantsDescription",	kSystem_inhabitantsDescription, OOJS_PROP_READWRITE_CB },
	{ "government",				kSystem_government,			OOJS_PROP_READWRITE_CB },
	{ "governmentDescription",	kSystem_governmentDescription, OOJS_PROP_READONLY_CB },
	{ "economy",				kSystem_economy,			OOJS_PROP_READWRITE_CB },
	{ "economyDescription",		kSystem_economyDescription,	OOJS_PROP_READONLY_CB },
	{ "techLevel",				kSystem_techLevel,			OOJS_PROP_READWRITE_CB },
	{ "population",				kSystem_population,			OOJS_PROP_READWRITE_CB },
	{ "productivity",			kSystem_productivity,		OOJS_PROP_READWRITE_CB },
	{ "isInterstellarSpace",	kSystem_isInterstellarSpace, OOJS_PROP_READONLY_CB},
	{ "mainStation",			kSystem_mainStation,		OOJS_PROP_READONLY_CB },
	{ "mainPlanet",				kSystem_mainPlanet,			OOJS_PROP_READONLY_CB },
	{ "sun",					kSystem_sun,				OOJS_PROP_READONLY_CB },
	{ "planets",				kSystem_planets,			OOJS_PROP_READONLY_CB },
	{ "allShips",				kSystem_allShips,			OOJS_PROP_READONLY_CB },
	{ "info",					kSystem_info,				OOJS_PROP_READONLY_CB },
	{ "pseudoRandomNumber",		kSystem_pseudoRandomNumber,	OOJS_PROP_READONLY_CB },
	{ "pseudoRandom100",		kSystem_pseudoRandom100,	OOJS_PROP_READONLY_CB },
	{ "pseudoRandom256",		kSystem_pseudoRandom256,	OOJS_PROP_READONLY_CB },
	{ 0 }
};


static JSFunctionSpec sSystemMethods[] =
{
	// JS name					Function					min args
	{ "toString",						SystemToString,				0 },
	{ "addGroup",						SystemAddGroup,				3 },
	{ "addGroupToRoute",				SystemAddGroupToRoute,		2 },
	{ "addMoon",						SystemAddMoon,				1 },
	{ "addPlanet",						SystemAddPlanet,			1 },
	{ "addShips",						SystemAddShips,				3 },
	{ "addShipsToRoute",				SystemAddShipsToRoute,		2 },
	{ "countShipsWithPrimaryRole",		SystemCountShipsWithPrimaryRole, 1 },
	{ "countShipsWithRole",				SystemCountShipsWithRole,	1 },
	{ "countEntitiesWithScanClass",		SystemCountEntitiesWithScanClass,	1 },
	{ "entitiesWithScanClass",			SystemEntitiesWithScanClass, 1 },
	{ "filteredEntities",				SystemFilteredEntities,		2 },
	{ "sendAllShipsAway",				SystemSendAllShipsAway,		1 },
	{ "shipsWithPrimaryRole",			SystemShipsWithPrimaryRole,	1 },
	{ "shipsWithRole",					SystemShipsWithRole,		1 },
	
	{ "legacy_addShips",				SystemLegacyAddShips,		2 },
	{ "legacy_addSystemShips",			SystemLegacyAddSystemShips,	3 },
	{ "legacy_addShipsAt",				SystemLegacyAddShipsAt,		6 },
	{ "legacy_addShipsAtPrecisely",		SystemLegacyAddShipsAtPrecisely, 6 },
	{ "legacy_addShipsWithinRadius",	SystemLegacyAddShipsWithinRadius, 7 },
	{ "legacy_spawnShip",				SystemLegacySpawnShip,		1 },
	{ 0 }
};


static JSFunctionSpec sSystemStaticMethods[] =
{
	{ "systemNameForID",		SystemStaticSystemNameForID, 1 },
	{ "systemIDForName",		SystemStaticSystemIDForName, 1 },
	{ "infoForSystem",			SystemStaticInfoForSystem,	2 },
	{ 0 }
};


void InitOOJSSystem(JSContext *context, JSObject *global)
{
	sSystemPrototype = JS_InitClass(context, global, NULL, &sSystemClass, OOJSUnconstructableConstruct, 0, sSystemProperties, sSystemMethods, NULL, sSystemStaticMethods);
	
	// Create system object as a property of the global object.
	JS_DefineObject(context, global, "system", &sSystemClass, sSystemPrototype, OOJS_PROP_READONLY);
}


static JSBool SystemGetProperty(OOJS_PROP_ARGS)
{
	if (!OOJS_PROPID_IS_INT)  return YES;
	
	OOJS_NATIVE_ENTER(context)
	
	id							result = nil;
	PlayerEntity				*player = nil;
	NSDictionary				*systemData = nil;
	static Random_Seed 			sCurrentSystem = {0};
	
	player = OOPlayerForScripting();
	
	if (!equal_seeds(sCurrentSystem, player->system_seed))
	{
		sCurrentSystem = player->system_seed;
	}
	
	systemData = [UNIVERSE generateSystemData:sCurrentSystem];
	
	switch (OOJS_PROPID_INT)
	{
		case kSystem_ID:
			*value = INT_TO_JSVAL([player currentSystemID]);
			break;
		
		case kSystem_name:
			result = [systemData objectForKey:KEY_NAME];
			if (result == nil)  result = [NSNull null];
			break;
			
		case kSystem_description:
			result = [systemData objectForKey:KEY_DESCRIPTION];
			if (result == nil)  result = [NSNull null];
			break;
			
		case kSystem_inhabitantsDescription:
			result = [systemData objectForKey:KEY_INHABITANTS];
			if (result == nil)  result = [NSNull null];
			break;
			
		case kSystem_government:
			*value = INT_TO_JSVAL([systemData oo_intForKey:KEY_GOVERNMENT]);
			break;
			
		case kSystem_governmentDescription:
			result = OODisplayStringFromGovernmentID([systemData oo_intForKey:KEY_GOVERNMENT]);
			if (result == nil && [UNIVERSE inInterstellarSpace])  result = DESC(@"not-applicable");
			if (result == nil)  result = [NSNull null];
			break;
			
		case kSystem_economy:
			*value = INT_TO_JSVAL([systemData oo_intForKey:KEY_ECONOMY]);
			break;
			
		case kSystem_economyDescription:
			result = OODisplayStringFromEconomyID([systemData oo_intForKey:KEY_ECONOMY]);
			if (result == nil && [UNIVERSE inInterstellarSpace])  result = DESC(@"not-applicable");
			if (result == nil)  result = [NSNull null];
			break;
		
		case kSystem_techLevel:
			*value = INT_TO_JSVAL([systemData oo_intForKey:KEY_TECHLEVEL]);
			break;
			
		case kSystem_population:
			*value = INT_TO_JSVAL([systemData oo_intForKey:KEY_POPULATION]);
			break;
			
		case kSystem_productivity:
			*value = INT_TO_JSVAL([systemData oo_intForKey:KEY_PRODUCTIVITY]);
			break;
			
		case kSystem_isInterstellarSpace:
			*value = OOJSValueFromBOOL([UNIVERSE inInterstellarSpace]);
			break;
			
		case kSystem_mainStation:
			result = [UNIVERSE station];
			if (result == nil)  result = [NSNull null];
			break;
			
		case kSystem_mainPlanet:
			result = [UNIVERSE planet];
			if (result == nil)  result = [NSNull null];
			break;
			
		case kSystem_sun:
			result = [UNIVERSE sun];
			if (result == nil)  result = [NSNull null];
			break;
			
		case kSystem_planets:
			result = [UNIVERSE planets];
			if (result == nil)  result = [NSArray array];
			break;
			
		case kSystem_allShips:
			OOJS_BEGIN_FULL_NATIVE(context)
			result = [UNIVERSE findShipsMatchingPredicate:JSEntityIsJavaScriptSearchablePredicate parameter:NULL inRange:-1 ofEntity:nil];
			OOJS_END_FULL_NATIVE
			break;
			
		case kSystem_info:
			*value = GetJSSystemInfoForSystem(context, [player currentGalaxyID], [player currentSystemID]);
			break;
		
		case kSystem_pseudoRandomNumber:
			JS_NewDoubleValue(context, [player systemPseudoRandomFloat], value);
			break;
			
		case kSystem_pseudoRandom100:
			*value = INT_TO_JSVAL([player systemPseudoRandom100]);
			break;
			
		case kSystem_pseudoRandom256:
			*value = INT_TO_JSVAL([player systemPseudoRandom256]);
			break;
			
		default:
			OOJSReportBadPropertySelector(context, @"System", OOJS_PROPID_INT);
			return NO;
	}
	
	if (result != nil)  *value = [result oo_jsValueInContext:context];
	return YES;
	
	OOJS_NATIVE_EXIT
}


static JSBool SystemSetProperty(OOJS_PROP_ARGS)
{
	if (!OOJS_PROPID_IS_INT)  return YES;
	
	OOJS_NATIVE_ENTER(context)
	
	BOOL						OK = NO;
	PlayerEntity				*player = nil;
	OOGalaxyID					galaxy;
	OOSystemID					system;
	NSString					*stringValue = nil;
	int32						iValue;
	
	player = OOPlayerForScripting();
	
	galaxy = [player currentGalaxyID];
	system = [player currentSystemID];
	
	if (system == -1)  return YES;	// Can't change anything in interstellar space.
	
	switch (OOJS_PROPID_INT)
	{
		case kSystem_name:
			stringValue = OOStringFromJSValue(context, *value);
			if (stringValue != nil)
			{
				[UNIVERSE setSystemDataForGalaxy:galaxy planet:system key:KEY_NAME value:stringValue];
				OK = YES;
			}
			break;
			
		case kSystem_description:
			stringValue = OOStringFromJSValue(context, *value);
			if (stringValue != nil)
			{
				[UNIVERSE setSystemDataForGalaxy:galaxy planet:system key:KEY_DESCRIPTION value:stringValue];
				OK = YES;
			}
			break;
			
		case kSystem_inhabitantsDescription:
			stringValue = OOStringFromJSValue(context, *value);
			if (stringValue != nil)
			{
				[UNIVERSE setSystemDataForGalaxy:galaxy planet:system key:KEY_INHABITANTS value:stringValue];
				OK = YES;
			}
			break;
			
		case kSystem_government:
			if (JS_ValueToInt32(context, *value, &iValue))
			{
				if (iValue < 0)  iValue = 0;
				if (7 < iValue)  iValue = 7;
				[UNIVERSE setSystemDataForGalaxy:galaxy planet:system key:KEY_GOVERNMENT value:[NSNumber numberWithInt:iValue]];
				OK = YES;
			}
			break;
			
		case kSystem_economy:
			if (JS_ValueToInt32(context, *value, &iValue))
			{
				if (iValue < 0)  iValue = 0;
				if (7 < iValue)  iValue = 7;
				[UNIVERSE setSystemDataForGalaxy:galaxy planet:system key:KEY_ECONOMY value:[NSNumber numberWithInt:iValue]];
				OK = YES;
			}
			break;
			
		case kSystem_techLevel:
			if (JS_ValueToInt32(context, *value, &iValue))
			{
				if (iValue < 0)  iValue = 0;
				if (15 < iValue)  iValue = 15;
				[UNIVERSE setSystemDataForGalaxy:galaxy planet:system key:KEY_TECHLEVEL value:[NSNumber numberWithInt:iValue]];
				OK = YES;
			}
			break;
			
		case kSystem_population:
			if (JS_ValueToInt32(context, *value, &iValue))
			{
				[UNIVERSE setSystemDataForGalaxy:galaxy planet:system key:KEY_POPULATION value:[NSNumber numberWithInt:iValue]];
				OK = YES;
			}
			break;
			
		case kSystem_productivity:
			if (JS_ValueToInt32(context, *value, &iValue))
			{
				[UNIVERSE setSystemDataForGalaxy:galaxy planet:system key:KEY_PRODUCTIVITY value:[NSNumber numberWithInt:iValue]];
				OK = YES;
			}
			break;
			
		default:
			OOJSReportBadPropertySelector(context, @"System", OOJS_PROPID_INT);
	}
	
	return OK;
	
	OOJS_NATIVE_EXIT
}


// *** Methods ***

// toString() : String
static JSBool SystemToString(OOJS_NATIVE_ARGS)
{
	OOJS_NATIVE_ENTER(context)
	
	PlayerEntity		*player = OOPlayerForScripting();
	NSString			*systemDesc = nil;
	
	systemDesc = [NSString stringWithFormat:@"[System %u:%u \"%@\"]", [player currentGalaxyID], [player currentSystemID], [[UNIVERSE currentSystemData] objectForKey:KEY_NAME]];
	OOJS_RETURN_OBJECT(systemDesc);
	
	OOJS_NATIVE_EXIT
}


// addPlanet(key : String) : Planet
static JSBool SystemAddPlanet(OOJS_NATIVE_ARGS)
{
	OOJS_NATIVE_ENTER(context)
	
	PlayerEntity		*player = OOPlayerForScripting();
	NSString			*key = nil;
	OOPlanetEntity		*planet = nil;
	
	key = OOStringFromJSValue(context, OOJS_ARG(0));
	if (EXPECT_NOT(key == nil))
	{
		OOJSReportBadArguments(context, @"System", @"addPlanet", argc, OOJS_ARGV, @"Expected planet key, got", nil);
		return NO;
	}
	
	OOJS_BEGIN_FULL_NATIVE(context)
	planet = [player addPlanet:key];
	OOJS_END_FULL_NATIVE
	
	OOJS_RETURN_OBJECT(planet);
	
	OOJS_NATIVE_EXIT
}


// addMoon(key : String) : Planet
static JSBool SystemAddMoon(OOJS_NATIVE_ARGS)
{
	OOJS_NATIVE_ENTER(context)
	
	PlayerEntity		*player = OOPlayerForScripting();
	NSString			*key = nil;
	OOPlanetEntity		*planet = nil;
	
	key = OOStringFromJSValue(context, OOJS_ARG(0));
	if (EXPECT_NOT(key == nil))
	{
		OOJSReportBadArguments(context, @"System", @"addMoon", argc, OOJS_ARGV, @"Expected planet key, got", nil);
		return NO;
	}
	
	OOJS_BEGIN_FULL_NATIVE(context)
	planet = [player addMoon:key];
	OOJS_END_FULL_NATIVE
	
	OOJS_RETURN_OBJECT(planet);
	
	OOJS_NATIVE_EXIT
}


// sendAllShipsAway()
static JSBool SystemSendAllShipsAway(OOJS_NATIVE_ARGS)
{
	OOJS_NATIVE_ENTER(context)
	
	PlayerEntity *player = OOPlayerForScripting();
	
	[player sendAllShipsAway];
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}


// countShipsWithPrimaryRole(role : String [, relativeTo : Entity [, range : Number]]) : Number
static JSBool SystemCountShipsWithPrimaryRole(OOJS_NATIVE_ARGS)
{
	OOJS_NATIVE_ENTER(context)
	
	NSString			*role = nil;
	Entity				*relativeTo = nil;
	double				range = -1;
	unsigned			result;
	
	role = OOStringFromJSValue(context, OOJS_ARG(0));
	if (EXPECT_NOT(role == nil))
	{
		OOJSReportBadArguments(context, @"System", @"countShipsWithPrimaryRole", argc, OOJS_ARGV, nil, @"role");
		return NO;
	}
	
	// Get optional arguments
	argc -= 1;
	jsval *argv = OOJS_ARGV + 1;
	if (EXPECT_NOT(!GetRelativeToAndRange(context, @"countShipsWithPrimaryRole", &argc, &argv, &relativeTo, &range)))  return NO;
	
	OOJS_BEGIN_FULL_NATIVE(context)
	result = [UNIVERSE countShipsWithPrimaryRole:role inRange:range ofEntity:relativeTo];
	OOJS_END_FULL_NATIVE
	
	OOJS_RETURN_INT(result);
	
	OOJS_NATIVE_EXIT
}


// countShipsWithRole(role : String [, relativeTo : Entity [, range : Number]]) : Number
static JSBool SystemCountShipsWithRole(OOJS_NATIVE_ARGS)
{
	OOJS_NATIVE_ENTER(context)
	
	NSString			*role = nil;
	Entity				*relativeTo = nil;
	double				range = -1;
	unsigned			result;
	
	role = OOStringFromJSValue(context, OOJS_ARG(0));
	if (EXPECT_NOT(role == nil))
	{
		OOJSReportBadArguments(context, @"System", @"countShipsWithRole", argc, OOJS_ARGV, nil, @"role");
		return NO;
	}
	
	// Get optional arguments
	argc -= 1;
	jsval *argv = OOJS_ARGV + 1;
	if (EXPECT_NOT(!GetRelativeToAndRange(context, @"countShipsWithRole", &argc, &argv, &relativeTo, &range)))  return NO;
	
	OOJS_BEGIN_FULL_NATIVE(context)
	result = [UNIVERSE countShipsWithRole:role inRange:range ofEntity:relativeTo];
	OOJS_END_FULL_NATIVE
	
	OOJS_RETURN_INT(result);
	
	OOJS_NATIVE_EXIT
}


// shipsWithPrimaryRole(role : String [, relativeTo : Entity [, range : Number]]) : Array (Entity)
static JSBool SystemShipsWithPrimaryRole(OOJS_NATIVE_ARGS)
{
	OOJS_NATIVE_ENTER(context)
	
	NSString			*role = nil;
	Entity				*relativeTo = nil;
	double				range = -1;
	NSArray				*result = nil;
	
	role = OOStringFromJSValue(context, OOJS_ARG(0));
	if (EXPECT_NOT(role == nil))
	{
		OOJSReportBadArguments(context, @"System", @"shipsWithPrimaryRole", argc, OOJS_ARGV, nil, @"role and optional reference entity and range");
		return NO;
	}
	
	// Get optional arguments
	argc -= 1;
	jsval *argv = OOJS_ARGV + 1;
	if (EXPECT_NOT(!GetRelativeToAndRange(context, @"shipsWithPrimaryRole", &argc, &argv, &relativeTo, &range)))  return NO;
	
	// Search for entities
	OOJS_BEGIN_FULL_NATIVE(context)
	result = FindShips(HasPrimaryRolePredicate, role, relativeTo, range);
	OOJS_END_FULL_NATIVE
	
	OOJS_RETURN_OBJECT(result);
	
	OOJS_NATIVE_EXIT
}


// shipsWithRole(role : String [, relativeTo : Entity [, range : Number]]) : Array (Entity)
static JSBool SystemShipsWithRole(OOJS_NATIVE_ARGS)
{
	OOJS_NATIVE_ENTER(context)
	
	NSString			*role = nil;
	Entity				*relativeTo = nil;
	double				range = -1;
	NSArray				*result = nil;
	
	role = OOStringFromJSValue(context, OOJS_ARG(0));
	if (EXPECT_NOT(role == nil))
	{
		OOJSReportBadArguments(context, @"System", @"shipsWithRole", argc, OOJS_ARGV, nil, @"role and optional reference entity and range");
		return NO;
	}
	
	// Get optional arguments
	argc -= 1;
	jsval *subargv = OOJS_ARGV + 1;
	if (EXPECT_NOT(!GetRelativeToAndRange(context, @"shipsWithRole", &argc, &subargv, &relativeTo, &range)))  return NO;
	
	// Search for entities
	OOJS_BEGIN_FULL_NATIVE(context)
	result = FindShips(HasRolePredicate, role, relativeTo, range);
	OOJS_END_FULL_NATIVE
	
	OOJS_RETURN_OBJECT(result);
	
	OOJS_NATIVE_EXIT
}


// countEntitiesWithScanClass(scanClass : String [, relativeTo : Entity [, range : Number]]) : Number
static JSBool SystemCountEntitiesWithScanClass(OOJS_NATIVE_ARGS)
{
	OOJS_NATIVE_ENTER(context)
	
	Entity				*relativeTo = nil;
	double				range = -1;
	unsigned			result;
	
	OOScanClass scanClass = OOScanClassFromJSValue(context, OOJS_ARG(0));
	if (scanClass == CLASS_NOT_SET)
	{
		OOJSReportBadArguments(context, @"System", @"countEntitiesWithScanClass", 1, OOJS_ARGV, nil, @"scan class specifier");
		return NO;
	}
	
	// Get optional arguments
	argc -= 1;
	jsval *argv = OOJS_ARGV + 1;
	if (EXPECT_NOT(!GetRelativeToAndRange(context, @"countEntitiesWithScanClass", &argc, &argv, &relativeTo, &range)))  return NO;
	
	OOJS_BEGIN_FULL_NATIVE(context)
	result = [UNIVERSE countShipsWithScanClass:scanClass inRange:range ofEntity:relativeTo];
	OOJS_END_FULL_NATIVE
	
	OOJS_RETURN_INT(result);
	
	OOJS_NATIVE_EXIT
}


// entitiesWithScanClass(scanClass : String [, relativeTo : Entity [, range : Number]]) : Array (Entity)
static JSBool SystemEntitiesWithScanClass(OOJS_NATIVE_ARGS)
{
	OOJS_NATIVE_ENTER(context)
	
	Entity				*relativeTo = nil;
	double				range = -1;
	NSArray				*result = nil;
	
	OOScanClass scanClass = OOScanClassFromJSValue(context, OOJS_ARG(0));
	if (scanClass == CLASS_NOT_SET)
	{
		OOJSReportBadArguments(context, @"System", @"countEntitiesWithScanClass", 1, OOJS_ARGV, nil, @"scan class specifier");
		return NO;
	}
	
	// Get optional arguments
	argc -= 1;
	jsval *argv = OOJS_ARGV + 1;
	if (EXPECT_NOT(!GetRelativeToAndRange(context, @"entitiesWithScanClass", &argc, &argv, &relativeTo, &range)))  return NO;
	
	// Search for entities
	OOJS_BEGIN_FULL_NATIVE(context)
	result = FindJSVisibleEntities(HasScanClassPredicate, [NSNumber numberWithInt:scanClass], relativeTo, range);
	OOJS_END_FULL_NATIVE
	
	OOJS_RETURN_OBJECT(result);
	
	OOJS_NATIVE_EXIT
}


// filteredEntities(this : Object, predicate : Function [, relativeTo : Entity [, range : Number]]) : Array (Entity)
static JSBool SystemFilteredEntities(OOJS_NATIVE_ARGS)
{
	OOJS_NATIVE_ENTER(context)
	
	JSObject			*jsThis = NULL;
	jsval				predicate = JSVAL_VOID;
	Entity				*relativeTo = nil;
	double				range = -1;
	NSArray				*result = nil;
	
	// Get this and predicate arguments
	predicate = OOJS_ARG(1);
	if (!OOJSValueIsFunction(context, predicate) || !JS_ValueToObject(context, OOJS_ARG(0), &jsThis))
	{
		OOJSReportBadArguments(context, @"System", @"filteredEntities", argc, OOJS_ARGV, nil, @"this, predicate function, and optional reference entity and range");
		return NO;
	}
	
	// Get optional arguments
	argc -= 2;
	jsval *argv = OOJS_ARGV + 2;
	if (EXPECT_NOT(!GetRelativeToAndRange(context, @"filteredEntities", &argc, &argv, &relativeTo, &range)))  return NO;
	
	// Search for entities
	JSFunctionPredicateParameter param = { context, predicate, jsThis, NO };
	OOJSPauseTimeLimiter();
	result = FindJSVisibleEntities(JSFunctionPredicate, &param, relativeTo, range);
	OOJSResumeTimeLimiter();
	
	if (EXPECT_NOT(param.errorFlag))  return NO;
	
	OOJS_RETURN_OBJECT(result);
	
	OOJS_NATIVE_EXIT
}


// addShips(role : String, count : Number [, position: Vector [, radius: Number]]) : Array
static JSBool SystemAddShips(OOJS_NATIVE_ARGS)
{
	return SystemAddShipsOrGroup(OOJS_NATIVE_CALLTHROUGH, NO);
}


// addGroup(role : String, count : Number [, position: Vector [, radius: Number]]) : Array
static JSBool SystemAddGroup(OOJS_NATIVE_ARGS)
{
	return SystemAddShipsOrGroup(OOJS_NATIVE_CALLTHROUGH, YES);
}


// addShipsToRoute(role : String, count : Number [, position: Number [, route: String]])
static JSBool SystemAddShipsToRoute(OOJS_NATIVE_ARGS)
{
	return SystemAddShipsOrGroupToRoute(OOJS_NATIVE_CALLTHROUGH, NO);
}


// addGroupToRoute(role : String, count : Number,  position: Number[, route: String])
static JSBool SystemAddGroupToRoute(OOJS_NATIVE_ARGS)
{
	return SystemAddShipsOrGroupToRoute(OOJS_NATIVE_CALLTHROUGH, YES);
}


// legacy_addShips(role : String, count : Number)
static JSBool SystemLegacyAddShips(OOJS_NATIVE_ARGS)
{
	OOJS_NATIVE_ENTER(context)
	
	NSString			*role = nil;
	int32				count;
	
	role = OOStringFromJSValue(context, OOJS_ARG(0));
	if (EXPECT_NOT(role == nil ||
				   !JS_ValueToInt32(context, OOJS_ARG(1), &count) ||
				   argc < 2 ||
				   count < 1 || 64 < count))
	{
		OOJSReportBadArguments(context, @"System", @"legacy_addShips", argc, OOJS_ARGV, nil, @"role and positive count no greater than 64");
		return NO;
	}
	
	OOJS_BEGIN_FULL_NATIVE(context)
	while (count--)  [UNIVERSE witchspaceShipWithPrimaryRole:role];
	OOJS_END_FULL_NATIVE
	
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}


// legacy_addSystemShips(role : String, count : Number, location : Number)
static JSBool SystemLegacyAddSystemShips(OOJS_NATIVE_ARGS)
{
	OOJS_NATIVE_ENTER(context)
	
	jsdouble			position;
	NSString			*role = nil;
	int32				count;
	
	role = OOStringFromJSValue(context, OOJS_ARG(0));
	if (EXPECT_NOT(role == nil ||
				   !JS_ValueToInt32(context, OOJS_ARG(1), &count) ||
				   count < 1 || 64 < count ||
				   argc < 3 ||
				   !JS_ValueToNumber(context, OOJS_ARG(2), &position)))
	{
		OOJSReportBadArguments(context, @"System", @"legacy_addSystemShips", argc, OOJS_ARGV, nil, @"role, positive count no greater than 64, and position along route");
		return NO;
	}
	
	OOJS_BEGIN_FULL_NATIVE(context)
	while (count--)  [UNIVERSE addShipWithRole:role nearRouteOneAt:position];
	OOJS_END_FULL_NATIVE
	
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}


// legacy_addShipsAt(role : String, count : Number, coordScheme : String, coords : vectorExpression)
static JSBool SystemLegacyAddShipsAt(OOJS_NATIVE_ARGS)
{
	OOJS_NATIVE_ENTER(context)
	
	PlayerEntity		*player = OOPlayerForScripting();
	Vector				where;
	NSString			*role = nil;
	int32				count;
	NSString			*coordScheme = nil;
	NSString			*arg = nil;
	
	role = OOStringFromJSValue(context, OOJS_ARG(0));
	coordScheme = OOStringFromJSValue(context, OOJS_ARG(2));
	if (EXPECT_NOT(role == nil ||
				   !JS_ValueToInt32(context, OOJS_ARG(1), &count) ||
				   count < 1 || 64 < count ||
				   coordScheme == nil ||
				   argc < 4 ||
				   !VectorFromArgumentListNoError(context, argc - 3, OOJS_ARGV + 3, &where, NULL)))
	{
		OOJSReportBadArguments(context, @"System", @"legacy_addShipsAt", argc, OOJS_ARGV, nil, @"role, positive count no greater than 64, coordinate scheme and coordinates");
		return NO;
	}
	
	OOJS_BEGIN_FULL_NATIVE(context)
	arg = [NSString stringWithFormat:@"%@ %d %@ %f %f %f", role, count, coordScheme, where.x, where.y, where.z];
	[player addShipsAt:arg];
	OOJS_END_FULL_NATIVE
	
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}


// legacy_addShipsAtPrecisely(role : String, count : Number, coordScheme : String, coords : vectorExpression)
static JSBool SystemLegacyAddShipsAtPrecisely(OOJS_NATIVE_ARGS)
{
	OOJS_NATIVE_ENTER(context)
	
	PlayerEntity		*player = OOPlayerForScripting();
	Vector				where;
	NSString			*role = nil;
	int32				count;
	NSString			*coordScheme = nil;
	NSString			*arg = nil;
	
	role = OOStringFromJSValue(context, OOJS_ARG(0));
	coordScheme = OOStringFromJSValue(context, OOJS_ARG(2));
	if (EXPECT_NOT(role == nil ||
				   !JS_ValueToInt32(context, OOJS_ARG(1), &count) ||
				   count < 1 || 64 < count ||
				   coordScheme == nil ||
				   argc < 4 ||
				   !VectorFromArgumentListNoError(context, argc - 3, OOJS_ARGV + 3, &where, NULL)))
	{
		OOJSReportBadArguments(context, @"System", @"legacy_addShipsAtPrecisely", argc, OOJS_ARGV, nil, @"role, positive count no greater than 64, coordinate scheme and coordinates");
		return NO;
	}
	
	OOJS_BEGIN_FULL_NATIVE(context)
	arg = [NSString stringWithFormat:@"%@ %d %@ %f %f %f", role, count, coordScheme, where.x, where.y, where.z];
	[player addShipsAtPrecisely:arg];
	OOJS_END_FULL_NATIVE
	
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}


// legacy_addShipsWithinRadius(role : String, count : Number, coordScheme : String, coords : vectorExpression, radius : Number)
static JSBool SystemLegacyAddShipsWithinRadius(OOJS_NATIVE_ARGS)
{
	OOJS_NATIVE_ENTER(context)
	
	PlayerEntity		*player = OOPlayerForScripting();
	Vector				where;
	jsdouble			radius;
	NSString			*role = nil;
	int32				count;
	NSString			*coordScheme = nil;
	NSString			*arg = nil;
	uintN				consumed = 0;
	
	role = OOStringFromJSValue(context, OOJS_ARG(0));
	coordScheme = OOStringFromJSValue(context, OOJS_ARG(2));
	if (EXPECT_NOT(role == nil ||
				   !JS_ValueToInt32(context, OOJS_ARG(1), &count) ||
				   count < 1 || 64 < count ||
				   coordScheme == nil ||
				   argc < 5 ||
				   !VectorFromArgumentListNoError(context, argc - 3, OOJS_ARGV + 3, &where, &consumed) ||
				   !JS_ValueToNumber(context, OOJS_ARG(3 + consumed), &radius)))
	{
		OOJSReportBadArguments(context, @"System", @"legacy_addShipWithinRadius", argc, OOJS_ARGV, nil, @"role, positive count no greater than 64, coordinate scheme, coordinates and radius");
		return NO;
	}
	
	OOJS_BEGIN_FULL_NATIVE(context)
	arg = [NSString stringWithFormat:@"%@ %d %@ %f %f %f %f", role, count, coordScheme, where.x, where.y, where.z, radius];
	[player addShipsWithinRadius:arg];
	OOJS_END_FULL_NATIVE
	
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}


// legacy_spawnShip(key : string)
static JSBool SystemLegacySpawnShip(OOJS_NATIVE_ARGS)
{
	OOJS_NATIVE_ENTER(context)
	
	NSString			*key = nil;
	OOPlayerForScripting();	// For backwards-compatibility
	
	key = OOStringFromJSValue(context, OOJS_ARG(0));
	if (key == nil)
	{
		OOJSReportBadArguments(context, @"System", @"legacy_addShipWithinRadius", argc, OOJS_ARGV, nil, @"ship key");
		return NO;
	}
	
	OOJS_BEGIN_FULL_NATIVE(context)
	[UNIVERSE spawnShip:key];
	OOJS_END_FULL_NATIVE
	
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}


// *** Static methods ***

// systemNameForID(ID : Number) : String
static JSBool SystemStaticSystemNameForID(OOJS_NATIVE_ARGS)
{
	OOJS_NATIVE_ENTER(context)
	
	int32				systemID;
	
	if (!JS_ValueToInt32(context, OOJS_ARG(0), &systemID) || systemID < 0 || 255 < systemID)
	{
		OOJSReportBadArguments(context, @"System", @"systemNameForID", argc, OOJS_ARGV, nil, @"system ID");
		return NO;
	}
	
	OOJS_RETURN_OBJECT([UNIVERSE getSystemName:[UNIVERSE systemSeedForSystemNumber:systemID]]);
	
	OOJS_NATIVE_EXIT
}


// systemIDForName(name : String) : Number
static JSBool SystemStaticSystemIDForName(OOJS_NATIVE_ARGS)
{
	OOJS_NATIVE_ENTER(context)
	
	NSString			*name = nil;
	unsigned			result;
	
	name = OOStringFromJSValue(context, OOJS_ARG(0));
	if (name == nil)
	{
		OOJSReportBadArguments(context, @"System", @"systemIDForName", argc, OOJS_ARGV, nil, @"string");
		return NO;
	}
	
	OOJS_BEGIN_FULL_NATIVE(context)
	result = [UNIVERSE systemIDForSystemSeed:[UNIVERSE systemSeedForSystemName:name]];
	OOJS_END_FULL_NATIVE
	
	OOJS_RETURN_INT(result);
	
	OOJS_NATIVE_EXIT
}


// infoForSystem(galaxyID : Number, systemID : Number) : SystemInfo
static JSBool SystemStaticInfoForSystem(OOJS_NATIVE_ARGS)
{
	OOJS_NATIVE_ENTER(context)
	
	int32				galaxyID;
	int32				systemID;
	
	if (argc < 2 || !JS_ValueToInt32(context, OOJS_ARG(0), &galaxyID) || !JS_ValueToInt32(context, OOJS_ARG(1), &systemID))
	{
		OOJSReportBadArguments(context, @"System", @"infoForSystem", argc, OOJS_ARGV, nil, @"galaxy ID and system ID");
		return NO;
	}
	
	if (galaxyID < 0 || galaxyID > kOOMaximumGalaxyID)
	{
		OOJSReportBadArguments(context, @"System", @"infoForSystem", 1, OOJS_ARGV, @"Invalid galaxy ID", [NSString stringWithFormat:@"number in the range 0 to %u", kOOMaximumGalaxyID]);
		return NO;
	}
	
	if (systemID < kOOMinimumSystemID || systemID > kOOMaximumSystemID)
	{
		OOJSReportBadArguments(context, @"System", @"infoForSystem", 1, OOJS_ARGV + 1, @"Invalid system ID", [NSString stringWithFormat:@"number in the range %i to %i", kOOMinimumSystemID, kOOMaximumSystemID]);
		return NO;
	}
	
	OOJS_RETURN(GetJSSystemInfoForSystem(context, galaxyID, systemID));
	
	OOJS_NATIVE_EXIT
}


// *** Helper functions ***

// Shared implementation of addShips() and addGroup().
static JSBool SystemAddShipsOrGroup(OOJS_NATIVE_ARGS, BOOL isGroup)
{
	OOJS_NATIVE_ENTER(context)
	
	NSString			*role = nil;
	int32				count = 0;
	uintN				consumed = 0;
	Vector				where;
	double				radius = NSNotFound;	// a negative value means 
	id					result = nil;
	
	NSString			*func = isGroup ? @"addGroup" : @"addShips";
	
	role = OOStringFromJSValue(context, OOJS_ARG(0));
	if (role == nil)
	{
		OOJSReportError(context, @"System.%@(): role not defined.", func);
		return NO;
	}
	if (!JS_ValueToInt32(context, OOJS_ARG(1), &count) || count < 1 || 64 < count)
	{
		OOJSReportError(context, @"System.%@(): expected %@, got '%@'.", func, @"positive count no greater than 64", [NSString stringWithJavaScriptValue:OOJS_ARG(1) inContext:context]);
		return NO;
	}
	
	if (argc < 3)
	{
		where = [UNIVERSE getWitchspaceExitPosition];
		radius = SCANNER_MAX_RANGE;
	}
	else
	{
		if (!VectorFromArgumentListNoError(context, argc - 2, OOJS_ARGV + 2, &where, &consumed))
		{
			OOJSReportError(context, @"System.%@(): expected %@, got '%@'.", func, @"position", [NSString stringWithJavaScriptValue:OOJS_ARG(2) inContext:context]);
			return NO;
		}
		
		if (argc > 2 + consumed)
		{
			if (!JSVAL_IS_NUMBER(OOJS_ARG(2 + consumed)))
			{
				OOJSReportError(context, @"System.%@(): expected %@, got '%@'.", func, @"radius", [NSString stringWithJavaScriptValue:OOJS_ARG(2 + consumed) inContext:context]);
				return NO;
			}
			JS_ValueToNumber(context, OOJS_ARG(2 + consumed), &radius);
		}
	}
	
	OOJS_BEGIN_FULL_NATIVE(context)
	// Note: the use of witchspace-in effects (as in legacy_addShips) depends on proximity to the witchpoint.
	result = [UNIVERSE addShipsAt:where withRole:role quantity:count withinRadius:radius asGroup:isGroup];
	
	if (isGroup)
	{
		NSArray *array = result;
		if ([array count] > 0)  result = [(ShipEntity *)[array objectAtIndex:0] group];
		else  result = nil;
	}
	OOJS_END_FULL_NATIVE
	
	OOJS_RETURN_OBJECT(result);
	
	OOJS_NATIVE_EXIT
}


static JSBool SystemAddShipsOrGroupToRoute(OOJS_NATIVE_ARGS, BOOL isGroup)
{
	OOJS_NATIVE_ENTER(context)
	
	NSString			*role = nil;
	NSString			*route = @"st"; // default route witchpoint -> station. ("st" itself is not selectable by script)
	NSString			*routes = @" wp pw ws sw sp ps";
	int32				count = 0;
	double				where = NSNotFound;		// a negative value means random positioning!
	id					result = nil;
	
	NSString			*func = isGroup ? @"addGroup" : @"addShips";
	
	role = OOStringFromJSValue(context, OOJS_ARG(0));
	if (role == nil)
	{
		OOJSReportError(context, @"System.%@(): role not defined.", func);
		return NO;
	}
	if (!JS_ValueToInt32(context, OOJS_ARG(1), &count) || count < 1 || 64 < count)
	{
		OOJSReportError(context, @"System.%@(): expected %@, got '%@'.", func, @"positive count no greater than 64", [NSString stringWithJavaScriptValue:OOJS_ARG(1) inContext:context]);
		return NO;
	}
	
	if (argc > 2 && !JSVAL_IS_NULL(OOJS_ARG(2)))
	{
		JS_ValueToNumber(context, OOJS_ARG(2), &where);
		if (!JSVAL_IS_NUMBER(OOJS_ARG(2)) || where < 0.0f || where > 1.0f)
		{
			OOJSReportError(context, @"System.%@(): expected %@, got '%@'.", func, @"position along route", [NSString stringWithJavaScriptValue:OOJS_ARG(2) inContext:context]);
			return NO;
		}
	}
	
	if (argc > 3 && !JSVAL_IS_NULL(OOJS_ARG(3)))
	{
		route = OOStringFromJSValue(context, OOJS_ARG(3));
		if (!JSVAL_IS_STRING(OOJS_ARG(3)) || route == nil || [routes rangeOfString:[NSString stringWithFormat:@" %@",route] options:NSCaseInsensitiveSearch].length !=3)
		{
			OOJSReportError(context, @"System.%@(): expected %@, got '%@'.", func, @"route string", [NSString stringWithJavaScriptValue:OOJS_ARG(3) inContext:context]);
			return NO;
		}
		route = [route lowercaseString];
	}
	
	OOJS_BEGIN_FULL_NATIVE(context)
	// Note: the use of witchspace-in effects (as in legacy_addShips) depends on proximity to the witchpoint.	
	result = [UNIVERSE addShipsToRoute:route withRole:role quantity:count routeFraction:where asGroup:isGroup];
	
	if (isGroup)
	{
		NSArray *array = result;
		if ([array count] > 0)  result = [(ShipEntity *)[array objectAtIndex:0] group];
		else  result = nil;
	}
	OOJS_END_FULL_NATIVE
	
	OOJS_RETURN_OBJECT(result);
	
	OOJS_NATIVE_EXIT
}


static BOOL GetRelativeToAndRange(JSContext *context, NSString *methodName, uintN *ioArgc, jsval **ioArgv, Entity **outRelativeTo, double *outRange)
{
	OOJS_PROFILE_ENTER
	
	// No NULL arguments accepted.
	assert(ioArgc && ioArgv && outRelativeTo && outRange);
	
	// Get optional argument relativeTo : Entity
	if (*ioArgc != 0)
	{
		if (EXPECT_NOT(!JSValueToEntity(context, **ioArgv, outRelativeTo)))
		{
			OOJSReportBadArguments(context, @"System", methodName, 1, *ioArgv, nil, @"entity");
			return NO;
		}
		(*ioArgv)++; (*ioArgc)--;
	}
	
	// Get optional argument range : Number
	if (*ioArgc != 0)
	{
		if (!EXPECT_NOT(JS_ValueToNumber(context, **ioArgv, outRange)))
		{
			OOJSReportBadArguments(context, @"System", methodName, 1, *ioArgv, nil, @"number");
			return NO;
		}
		(*ioArgv)++; (*ioArgc)--;
	}
	
	return YES;
	
	OOJS_PROFILE_EXIT
}


static NSArray *FindJSVisibleEntities(EntityFilterPredicate predicate, void *parameter, Entity *relativeTo, double range)
{
	OOJS_PROFILE_ENTER
	
	NSMutableArray						*result = nil;
	BinaryOperationPredicateParameter	param =
	{
		JSEntityIsJavaScriptSearchablePredicate, NULL,
		predicate, parameter
	};
	
	result = [UNIVERSE findEntitiesMatchingPredicate:ANDPredicate
										   parameter:&param
											 inRange:range
											ofEntity:relativeTo];
	
	if (result != nil && relativeTo != nil && ![relativeTo isPlayer])
	{
		[result sortUsingFunction:CompareEntitiesByDistance context:relativeTo];
	}
	if (result == nil)  result = [NSArray array];
	return result;
	
	OOJS_PROFILE_EXIT
}


static NSArray *FindShips(EntityFilterPredicate predicate, void *parameter, Entity *relativeTo, double range)
{
	OOJS_PROFILE_ENTER
	
	BinaryOperationPredicateParameter	param =
	{
		IsShipPredicate, NULL,
		predicate, parameter
	};
	return FindJSVisibleEntities(ANDPredicate, &param, relativeTo, range);
	
	OOJS_PROFILE_EXIT
}


static NSComparisonResult CompareEntitiesByDistance(id a, id b, void *relativeTo)
{
	OOJS_PROFILE_ENTER
	
	Entity				*ea = a,
	*eb = b,
	*r = (id)relativeTo;
	float				d1, d2;
	
	d1 = distance2(ea->position, r->position);
	d2 = distance2(eb->position, r->position);
	
	if (d1 < d2)  return NSOrderedAscending;
	else if (d1 > d2)  return NSOrderedDescending;
	else return NSOrderedSame;
	
	OOJS_PROFILE_EXIT
}
