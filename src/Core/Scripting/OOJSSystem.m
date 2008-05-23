/*
 
 OOJSSystem.m
 
 
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
 
 */

#import "OOJSSystem.h"
#import "OOJavaScriptEngine.h"

#import "OOJSVector.h"
#import "OOJSEntity.h"
#import "OOJSPlayer.h"
#import "Universe.h"
#import "PlanetEntity.h"
#import "PlayerEntityScriptMethods.h"

#import "OOCollectionExtractors.h"
#import "OOConstToString.h"
#import "OOEntityFilterPredicate.h"


// system.addShips not yet implemented
#define ADD_SHIPS			0


static JSObject *sSystemPrototype;

static Random_Seed sCurrentSystem;
static NSDictionary *sPlanetInfo;


// Support functions for entity search methods.
static BOOL GetRelativeToAndRange(JSContext *context, uintN *ioArgc, jsval **ioArgv, Entity **outRelativeTo, double *outRange) NONNULL_FUNC;
static NSArray *FindJSVisibleEntities(EntityFilterPredicate predicate, void *parameter, Entity *relativeTo, double range);
static NSArray *FindShips(EntityFilterPredicate predicate, void *parameter, Entity *relativeTo, double range);
static int CompareEntitiesByDistance(id a, id b, void *relativeTo);


static JSBool SystemGetProperty(JSContext *context, JSObject *this, jsval name, jsval *outValue);
static JSBool SystemSetProperty(JSContext *context, JSObject *this, jsval name, jsval *value);

static JSBool SystemToString(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool SystemAddPlanet(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool SystemAddMoon(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool SystemSendAllShipsAway(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool SystemCountShipsWithRole(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool SystemShipsWithPrimaryRole(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool SystemShipsWithRole(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool SystemEntitiesWithScanClass(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool SystemFilteredEntities(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);

#if ADD_SHIPS
static JSBool SystemAddShips(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
#endif

static JSBool SystemLegacyAddShips(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool SystemLegacyAddSystemShips(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool SystemLegacyAddShipsAt(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool SystemLegacyAddShipsAtPrecisely(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool SystemLegacyAddShipsWithinRadius(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool SystemLegacySpawnShip(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);

static JSBool SystemStaticSystemNameForID(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool SystemStaticSystemIDForName(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);


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
	kSystem_ID,					// planet number, integer, read-only
	kSystem_name,				// name, string, read/write
	kSystem_description,		// description, string, read/write
	kSystem_inhabitantsDescription, // description of inhabitant species, string, read/write
	kSystem_goingNova,			// sun is going nova, boolean, read-only (should be moved to sun)
	kSystem_goneNova,			// sun has gone nova, boolean, read-only (should be moved to sun)
	kSystem_government,			// government ID, integer, read/write
	kSystem_governmentDescription,	// government ID description, string, read-only
	kSystem_economy,			// economy ID, integer, read/write
	kSystem_economyDescription,	// economy ID description, string, read-only
	kSystem_techLevel,			// tech level ID, integer, read/write
	kSystem_population,			// population, integer, read/write
	kSystem_productivity,		// productivity, integer, read/write
	kSystem_isInterstellarSpace, // is interstellar space, boolean, read-only
	kSystem_mainStation,		// system's main station, Station, read-only
	kSystem_mainPlanet,			// system's main planet, Planet, read-only
	kSystem_sun,				// system's sun, Planet, read-only
	kSystem_planets,			// planets in system, array of Planet, read-only
	kSystem_allShips			// ships in system, array of Ship, read-only
};


static JSPropertySpec sSystemProperties[] =
{
	// JS name					ID							flags
	{ "ID",						kSystem_ID,					JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "name",					kSystem_name,				JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "description",			kSystem_description,		JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "inhabitantsDescription",	kSystem_inhabitantsDescription, JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "goingNova",				kSystem_goingNova,			JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "goneNova",				kSystem_goneNova,			JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "government",				kSystem_government,			JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "governmentDescription",	kSystem_governmentDescription, JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "economy",				kSystem_economy,			JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "economyDescription",		kSystem_economyDescription,	JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "techLevel",				kSystem_techLevel,			JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "population",				kSystem_population,			JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "productivity",			kSystem_productivity,		JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "isInterstellarSpace",	kSystem_isInterstellarSpace, JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "mainStation",			kSystem_mainStation,		JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "mainPlanet",				kSystem_mainPlanet,			JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "sun",					kSystem_sun,				JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "planets",				kSystem_planets,			JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "allShips",				kSystem_allShips,			JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ 0 }
};


static JSFunctionSpec sSystemMethods[] =
{
	// JS name					Function					min args
	{ "toString",				SystemToString,				0 },
	{ "addPlanet",				SystemAddPlanet,			1 },
	{ "addMoon",				SystemAddMoon,				1 },
	{ "sendAllShipsAway",		SystemSendAllShipsAway,		1 },
	{ "countShipsWithRole",		SystemCountShipsWithRole,	1 },
	{ "shipsWithPrimaryRole",	SystemShipsWithPrimaryRole,	1 },
	{ "shipsWithRole",			SystemShipsWithRole,		1 },
	{ "entitiesWithScanClass",	SystemEntitiesWithScanClass, 1 },
	{ "filteredEntities",		SystemFilteredEntities,		2 },
	
#if ADD_SHIPS
	{ "addShips",				SystemAddShips,				3 },
#endif
	
	{ "legacy_addShips",		SystemLegacyAddShips,		2 },
	{ "legacy_addSystemShips",	SystemLegacyAddSystemShips,	3 },
	{ "legacy_addShipsAt",		SystemLegacyAddShipsAt,		6 },
	{ "legacy_addShipsAtPrecisely", SystemLegacyAddShipsAtPrecisely, 6 },
	{ "legacy_addShipsWithinRadius", SystemLegacyAddShipsWithinRadius, 7 },
	{ "legacy_spawnShip",		SystemLegacySpawnShip,		1 },
	{ 0 }
};


static JSFunctionSpec sSystemStaticMethods[] =
{
	{ "systemNameForID",		SystemStaticSystemNameForID, 1 },
	{ "systemIDForName",		SystemStaticSystemIDForName, 1 },
	{ 0 }
};


void InitOOJSSystem(JSContext *context, JSObject *global)
{
    sSystemPrototype = JS_InitClass(context, global, NULL, &sSystemClass, NULL, 0, sSystemProperties, sSystemMethods, NULL, sSystemStaticMethods);
	
	// Create system object as a property of the global object.
	JS_DefineObject(context, global, "system", &sSystemClass, sSystemPrototype, JSPROP_ENUMERATE | JSPROP_READONLY | JSPROP_PERMANENT);
}


static JSBool SystemGetProperty(JSContext *context, JSObject *this, jsval name, jsval *outValue)
{
	id							result = nil;
	PlayerEntity				*player = nil;
	
	if (!JSVAL_IS_INT(name))  return YES;
	
	player = OOPlayerForScripting();
	if (!equal_seeds(sCurrentSystem, player->system_seed))
	{
		sCurrentSystem = player->system_seed;
	}
	[sPlanetInfo release];
	sPlanetInfo = [[UNIVERSE generateSystemData:sCurrentSystem] retain];
	
	switch (JSVAL_TO_INT(name))
	{
		case kSystem_ID:
			*outValue = INT_TO_JSVAL([player currentSystemID]);
			break;
		
		case kSystem_name:
			if ([UNIVERSE sun] != nil)
			{
				result = [sPlanetInfo objectForKey:KEY_NAME];
				if (result == nil)  result = [NSNull null];
			}
			else
			{
				result = @"Interstellar space";
			}
			break;
			
		case kSystem_description:
			result = [sPlanetInfo objectForKey:KEY_DESCRIPTION];
			if (result == nil)  result = [NSNull null];
			break;
			
		case kSystem_inhabitantsDescription:
			result = [sPlanetInfo objectForKey:KEY_INHABITANTS];
			if (result == nil)  result = [NSNull null];
			break;
		
		case kSystem_goingNova:
			*outValue = BOOLToJSVal([[UNIVERSE sun] willGoNova]);
			break;
		
		case kSystem_goneNova:
			*outValue = BOOLToJSVal([[UNIVERSE sun] goneNova]);
			break;
			
		case kSystem_government:
			*outValue = INT_TO_JSVAL([sPlanetInfo intForKey:KEY_GOVERNMENT]);
			break;
			
		case kSystem_governmentDescription:
			result = GovernmentToString([sPlanetInfo intForKey:KEY_GOVERNMENT]);
			if (result == nil)  result = [NSNull null];
			break;
			
		case kSystem_economy:
			*outValue = INT_TO_JSVAL([sPlanetInfo intForKey:KEY_ECONOMY]);
			break;
			
		case kSystem_economyDescription:
			result = EconomyToString([sPlanetInfo intForKey:KEY_ECONOMY]);
			if (result == nil)  result = [NSNull null];
			break;
		
		case kSystem_techLevel:
			*outValue = INT_TO_JSVAL([sPlanetInfo intForKey:KEY_TECHLEVEL]);
			break;
			
		case kSystem_population:
			*outValue = INT_TO_JSVAL([sPlanetInfo intForKey:KEY_POPULATION]);
			break;
			
		case kSystem_productivity:
			*outValue = INT_TO_JSVAL([sPlanetInfo intForKey:KEY_PRODUCTIVITY]);
			break;
			
		case kSystem_isInterstellarSpace:
			*outValue = BOOLToJSVal([UNIVERSE sun] == nil);
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
			result = [UNIVERSE findShipsMatchingPredicate:NULL parameter:NULL inRange:-1 ofEntity:nil];
			break;
			
		default:
			OOReportJSBadPropertySelector(context, @"System", JSVAL_TO_INT(name));
			return NO;
	}
	
	if (result != nil)  *outValue = [result javaScriptValueInContext:context];
	return YES;
}


static JSBool SystemSetProperty(JSContext *context, JSObject *this, jsval name, jsval *value)
{
	BOOL						OK = NO;
	PlayerEntity				*player = nil;
	OOGalaxyID					galaxy;
	OOSystemID					system;
	NSString					*stringValue = nil;
	int32						iValue;
	
	if (!JSVAL_IS_INT(name))  return YES;
	
	player = OOPlayerForScripting();
	if (!equal_seeds(sCurrentSystem, player->system_seed))
	{
		sCurrentSystem = player->system_seed;
	}
	[sPlanetInfo release];
	sPlanetInfo = [[UNIVERSE generateSystemData:sCurrentSystem] retain];
	
	galaxy = [player currentGalaxyID];
	system = [player currentSystemID];
	
	if (system == -1)  return YES;	// Can't change anything in interstellar space.
	
	switch (JSVAL_TO_INT(name))
	{
		case kSystem_name:
			stringValue = JSValToNSString(context, *value);
			if (stringValue != nil)
			{
				[UNIVERSE setSystemDataForGalaxy:galaxy planet:system key:KEY_NAME value:stringValue];
				OK = YES;
			}
			break;
			
		case kSystem_description:
			stringValue = JSValToNSString(context, *value);
			if (stringValue != nil)
			{
				[UNIVERSE setSystemDataForGalaxy:galaxy planet:system key:KEY_DESCRIPTION value:stringValue];
				OK = YES;
			}
			break;
			
		case kSystem_inhabitantsDescription:
			stringValue = JSValToNSString(context, *value);
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
			OOReportJSBadPropertySelector(context, @"System", JSVAL_TO_INT(name));
	}
	
	// Hmm, what are these for? Who put them here? -- Ahruman 20080523
	[UNIVERSE generateSystemData:kNilRandomSeed];
	[UNIVERSE generateSystemData:sCurrentSystem];
	return OK;
}


// *** Methods ***

// toString() : String
static JSBool SystemToString(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	PlayerEntity		*player = OOPlayerForScripting();
	NSString			*systemDesc = nil;
	
	systemDesc = [NSString stringWithFormat:@"[System %u:%u \"%@\"]", [player currentGalaxyID], [player currentSystemID], [[UNIVERSE currentSystemData] objectForKey:KEY_NAME]];
	*outResult = [systemDesc javaScriptValueInContext:context];
	return YES;
}


// addPlanet(key : String)
static JSBool SystemAddPlanet(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	PlayerEntity		*player = OOPlayerForScripting();
	NSString			*key = nil;
	
	key = JSValToNSString(context, argv[0]);
	if (EXPECT_NOT(key == nil))
	{
		OOReportJSBadArguments(context, @"System", @"addPlanet", argc, argv, @"Expected planet key, got", nil);
		return NO;
	}
	
	[player addPlanet:key];
	return YES;
}


// addMoon(key : String)
static JSBool SystemAddMoon(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	PlayerEntity		*player = OOPlayerForScripting();
	NSString			*key = nil;
	
	key = JSValToNSString(context, argv[0]);
	if (EXPECT_NOT(key == nil))
	{
		OOReportJSBadArguments(context, @"System", @"addMoon", argc, argv, @"Expected planet key, got", nil);
		return NO;
	}
	
	[player addMoon:key];
	return YES;
}


// sendAllShipsAway()
static JSBool SystemSendAllShipsAway(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	PlayerEntity *player = OOPlayerForScripting();
	
	[player sendAllShipsAway];
	return YES;
}


// countShipsWithRole(role : String) : Number
static JSBool SystemCountShipsWithRole(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	NSString			*role = nil;
	
	role = JSValToNSString(context, argv[0]);
	if (EXPECT_NOT(role == nil))
	{
		OOReportJSBadArguments(context, @"System", @"countShipsWithRole", argc, argv, @"Invalid arguments", @"role");
		return NO;
	}
	
	*outResult = INT_TO_JSVAL([UNIVERSE countShipsWithRole:role]);
	return YES;
}


// shipsWithPrimaryRole(role : String [, relativeTo : Entity [, range : Number]]) : Array (Entity)
static JSBool SystemShipsWithPrimaryRole(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	NSString			*role = nil;
	Entity				*relativeTo = nil;
	double				range = -1;
	NSArray				*result = nil;
	
	role = JSValToNSString(context, *argv);
	if (EXPECT_NOT(role == nil))
	{
		OOReportJSBadArguments(context, @"System", @"shipsWithPrimaryRole", argc, argv, @"Invalid arguments", @"role and optional reference entity and range");
		return NO;
	}
	
	// Get optional arguments
	if (!GetRelativeToAndRange(context, &argc, &argv, &relativeTo, &range))  return NO;
	
	// Search for entities
	result = FindShips(HasPrimaryRolePredicate, role, relativeTo, range);
	if (result != nil)
	{
		*outResult = [result javaScriptValueInContext:context];
		return YES;
	}
	else
	{
		return NO;
	}
}


// shipsWithRole(role : String [, relativeTo : Entity [, range : Number]]) : Array (Entity)
static JSBool SystemShipsWithRole(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	NSString			*role = nil;
	Entity				*relativeTo = nil;
	double				range = -1;
	NSArray				*result = nil;
	
	role = JSValToNSString(context, *argv);
	if (EXPECT_NOT(role == nil))
	{
		OOReportJSBadArguments(context, @"System", @"shipsWithRole", argc, argv, @"Invalid arguments", @"role and optional reference entity and range");
		return NO;
	}
	
	// Get optional arguments
	if (EXPECT_NOT(!GetRelativeToAndRange(context, &argc, &argv, &relativeTo, &range)))  return NO;
	
	// Search for entities
	result = FindShips(HasRolePredicate, role, relativeTo, range);
	if (result != nil)
	{
		*outResult = [result javaScriptValueInContext:context];
		return YES;
	}
	else
	{
		return NO;
	}
}


// entitiesWithScanClass(scanClass : String [, relativeTo : Entity [, range : Number]]) : Array (Entity)
static JSBool SystemEntitiesWithScanClass(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	NSString			*scString = nil;
	OOScanClass			scanClass = CLASS_NOT_SET;
	Entity				*relativeTo = nil;
	double				range = -1;
	NSArray				*result = nil;
	
	scString = JSValToNSString(context, *argv);
	if (scString == nil)
	{
		OOReportJSBadArguments(context, @"System", @"entitiesWithScanClass", argc, argv, @"Invalid arguments", @"scan class and optional reference entity and range");
		return NO;
	}
	
	scanClass = StringToScanClass(scString);
	if (EXPECT_NOT(scanClass == CLASS_NOT_SET))
	{
		OOReportJSErrorForCaller(context, @"System", @"entitiesWithScanClass", @"Invalid scan class specifier \"%@\"", scString);
		return NO;
	}
	
	// Get optional arguments
	if (EXPECT_NOT(!GetRelativeToAndRange(context, &argc, &argv, &relativeTo, &range)))  return NO;
	
	// Search for entities
	result = FindJSVisibleEntities(HasScanClassPredicate, [NSNumber numberWithInt:scanClass], relativeTo, range);
	if (result != nil)
	{
		*outResult = [result javaScriptValueInContext:context];
		return YES;
	}
	else
	{
		return NO;
	}
}


// filteredEntities(this : Object, predicate : Function [, relativeTo : Entity [, range : Number]]) : Array (Entity)
static JSBool SystemFilteredEntities(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	JSObject			*jsThis = NULL;
	JSFunction			*function = NULL;
	Entity				*relativeTo = nil;
	double				range = -1;
	NSArray				*result = nil;
	
	// Get this and predicate arguments
	function = JS_ValueToFunction(context, argv[1]);
	if (EXPECT_NOT(function == NULL || !JS_ValueToObject(context, argv[0], &jsThis)))
	{
		OOReportJSBadArguments(context, @"System", @"filteredEntities", argc, argv, @"Invalid arguments", @"this, predicate function, and optional reference entity and range");
		return NO;
	}
	
	// Get optional arguments
	if (EXPECT_NOT(!GetRelativeToAndRange(context, &argc, &argv, &relativeTo, &range)))  return NO;
	
	// Search for entities
	JSFunctionPredicateParameter param = { context, function, jsThis, NO };
	result = FindJSVisibleEntities(JSFunctionPredicate, &param, relativeTo, range);
	if (EXPECT_NOT(param.errorFlag))  return NO;
	
	if (result != nil)
	{
		*outResult = [result javaScriptValueInContext:context];
		return YES;
	}
	else
	{
		return NO;
	}
}


#define DEFAULT_RADIUS 500.0

#if ADD_SHIPS
static JSBool SystemAddShips(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	NSString			*role = nil;
	int32				count;
	Vector				where;
	double				radius = DEFAULT_RADIUS;
	uintN				consumed;
	
	role = JSValToNSString(context, argv[0]);
	if (!JS_ValueToInt32(context, argv[1], &count) || count < 1 || 64 < count)
	{
		OOReportJSError(context, @"System.%@(): expected positive count, got %@.", @"addShips", JSValToNSString(context, argv[1]));
		return YES;
	}
	
	if (!VectorFromArgumentList(context, @"System", @"addShips", argc - 2, argv + 2, &where, &consumed))  return YES;
	argc += 2 + consumed;
	argv += 2 + consumed;
	
	if (argc != 0 && JS_ValueToNumber(context, argv[0], &radius))
	{
		
	}
	
	// Note: need a way to specify the use of witchspace-in effects (as in legacy_addShips).
	OOReportJSError(context, @"System.addShips(): not implemented.");
	
	return YES;
}
#endif

// legacy_addShips(role : String, count : Number)
static JSBool SystemLegacyAddShips(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	NSString			*role = nil;
	int32				count;
	
	role = JSValToNSString(context, argv[0]);
	if (EXPECT_NOT(role == nil ||
				   !JS_ValueToInt32(context, argv[1], &count) ||
				   count < 1 || 64 < count))
	{
		OOReportJSBadArguments(context, @"System", @"legacy_addShips", argc, argv, @"Invalid arguments", @"role and positive count no greater than 64");
		return NO;
	}
	
	while (count--)  [UNIVERSE witchspaceShipWithPrimaryRole:role];
	
	return YES;
}


// legacy_addSystemShips(role : String, count : Number, location : Number)
static JSBool SystemLegacyAddSystemShips(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	jsdouble			position;
	NSString			*role = nil;
	int32				count;
	
	role = JSValToNSString(context, argv[0]);
	if (EXPECT_NOT(role == nil ||
				   !JS_ValueToInt32(context, argv[1], &count) ||
				   count < 1 || 64 < count ||
				   !JS_ValueToNumber(context, argv[2], &position)))
	{
		OOReportJSBadArguments(context, @"System", @"legacy_addSystemShips", argc, argv, @"Invalid arguments", @"role, positive count no greater than 64, and position along route");
		return NO;
	}
	
	while (count--)  [UNIVERSE addShipWithRole:role nearRouteOneAt:position];
	
	return YES;
}


// legacy_addShipsAt(role : String, count : Number, coordScheme : Number, coords : vectorExpression)
static JSBool SystemLegacyAddShipsAt(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	PlayerEntity		*player = OOPlayerForScripting();
	Vector				where;
	NSString			*role = nil;
	int32				count;
	NSString			*coordScheme = nil;
	NSString			*arg = nil;
	
	role = JSValToNSString(context, argv[0]);
	coordScheme = JSValToNSString(context, argv[2]);
	if (EXPECT_NOT(role == nil ||
				   !JS_ValueToInt32(context, argv[1], &count) ||
				   count < 1 || 64 < count ||
				   coordScheme == nil ||
				   !VectorFromArgumentListNoError(context, argc - 3, argv + 3, &where, NULL)))
	{
		OOReportJSBadArguments(context, @"System", @"legacy_addShipsAt", argc, argv, @"Invalid arguments", @"role, positive count no greater than 64, coordinate scheme and coordinates");
		return NO;
	}
	
	arg = [NSString stringWithFormat:@"%@ %d %@ %f %f %f", role, count, coordScheme, where.x, where.y, where.z];
	[player addShipsAt:arg];
	
	return YES;
}


// legacy_addShipsAtPrecisely(role : String, count : Number, coordScheme : Number, coords : vectorExpression)
static JSBool SystemLegacyAddShipsAtPrecisely(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	PlayerEntity		*player = OOPlayerForScripting();
	Vector				where;
	NSString			*role = nil;
	int32				count;
	NSString			*coordScheme = nil;
	NSString			*arg = nil;
	
	role = JSValToNSString(context, argv[0]);
	coordScheme = JSValToNSString(context, argv[2]);
	if (EXPECT_NOT(role == nil ||
				   !JS_ValueToInt32(context, argv[1], &count) ||
				   count < 1 || 64 < count ||
				   coordScheme == nil ||
				   !VectorFromArgumentListNoError(context, argc - 3, argv + 3, &where, NULL)))
	{
		OOReportJSBadArguments(context, @"System", @"legacy_addShipsAtPrecisely", argc, argv, @"Invalid arguments", @"role, positive count no greater than 64, coordinate scheme and coordinates");
		return NO;
	}
	
	arg = [NSString stringWithFormat:@"%@ %d %@ %f %f %f", role, count, coordScheme, where.x, where.y, where.z];
	[player addShipsAtPrecisely:arg];
	
	return YES;
}


// legacy_addShipsWithinRadius(role : String, count : Number, coordScheme : Number, coords : vectorExpression, radius : Number)
static JSBool SystemLegacyAddShipsWithinRadius(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	PlayerEntity		*player = OOPlayerForScripting();
	Vector				where;
	jsdouble			radius;
	NSString			*role = nil;
	int32				count;
	NSString			*coordScheme = nil;
	NSString			*arg = nil;
	uintN				consumed = 0;
	
	role = JSValToNSString(context, argv[0]);
	coordScheme = JSValToNSString(context, argv[2]);
	if (EXPECT_NOT(role == nil ||
				   !JS_ValueToInt32(context, argv[1], &count) ||
				   count < 1 || 64 < count ||
				   coordScheme == nil ||
				   !VectorFromArgumentListNoError(context, argc - 3, argv + 3, &where, &consumed) ||
				   !JS_ValueToNumber(context, argv[3 + consumed], &radius)))
	{
		OOReportJSBadArguments(context, @"System", @"legacy_addShipWithinRadius", argc, argv, @"Invalid arguments", @"role, positive count no greater than 64, coordinate scheme, coordinates and radius");
		return NO;
	}
	
	arg = [NSString stringWithFormat:@"%@ %d %@ %f %f %f %f", role, count, coordScheme, where.x, where.y, where.z, radius];
	[player addShipsWithinRadius:arg];
	
	return YES;
}


// legacy_spawnShip(key : string)
static JSBool SystemLegacySpawnShip(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	NSString			*key = nil;
	OOPlayerForScripting();	// For backwards-compatibility
	
	key = JSValToNSString(context, argv[0]);
	if (key == nil)
	{
		OOReportJSBadArguments(context, @"System", @"legacy_addShipWithinRadius", argc, argv, @"Invalid arguments", @"ship key");
		return NO;
	}
	
	[UNIVERSE spawnShip:key];
	return YES;
}


// *** Helper functions ***

static BOOL GetRelativeToAndRange(JSContext *context, uintN *ioArgc, jsval **ioArgv, Entity **outRelativeTo, double *outRange)
{
	// No NULL arguments accepted.
	assert(ioArgc && ioArgv && outRelativeTo && outRange);
	
	// Get optional argument relativeTo : Entity
	if (*ioArgc != 0)
	{
		if (!JSValueToEntity(context, **ioArgv, outRelativeTo))  return NO;
		(*ioArgv)++; (*ioArgc)--;
	}
	
	// Get optional argument range : Number
	if (*ioArgc != 0)
	{
		if (!JS_ValueToNumber(context, **ioArgv, outRange))  return NO;
		(*ioArgv)++; (*ioArgc)--;
	}
	
	return YES;
}


static NSArray *FindJSVisibleEntities(EntityFilterPredicate predicate, void *parameter, Entity *relativeTo, double range)
{
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
}


static NSArray *FindShips(EntityFilterPredicate predicate, void *parameter, Entity *relativeTo, double range)
{
	BinaryOperationPredicateParameter	param =
	{
		IsShipPredicate, NULL,
		predicate, parameter
	};
	return FindJSVisibleEntities(ANDPredicate, &param, relativeTo, range);
}


static int CompareEntitiesByDistance(id a, id b, void *relativeTo)
{
	Entity				*ea = a,
						*eb = b,
						*r = (id)relativeTo;
	float				d1, d2;
	
	d1 = distance2(ea->position, r->position);
	d2 = distance2(eb->position, r->position);
	
	if (d1 < d2)  return NSOrderedAscending;
	else if (d1 > d2)  return NSOrderedDescending;
	else return NSOrderedSame;
}


// systemNameForID(ID : Number) : String
static JSBool SystemStaticSystemNameForID(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	int32				systemID;
	
	if (!JS_ValueToInt32(context, argv[0], &systemID) || systemID < 0 || 255 < systemID)
	{
		OOReportJSError(context, @"%@(): expected system ID from 0 to 255, got %@.", @"systemNameForID", JSValToNSString(context, argv[0]));
		return YES;
	}
	
	*outResult = [[UNIVERSE generateSystemName:[UNIVERSE systemSeedForSystemNumber:systemID]] javaScriptValueInContext:context];
	
	return YES;
}


// systemIDForName(name : String) : Number
static JSBool SystemStaticSystemIDForName(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	NSString			*name = nil;
	
	name = JSValToNSString(context, argv[0]);
	*outResult = INT_TO_JSVAL([UNIVERSE systemIDForSystemSeed:[UNIVERSE systemSeedForSystemName:name]]);
	return YES;
}
