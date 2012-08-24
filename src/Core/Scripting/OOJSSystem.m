/*
 
 OOJSSystem.m
 
 
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
#import "OOFilteringEnumerator.h"


static JSObject *sSystemPrototype;


// Support functions for entity search methods.
static BOOL GetRelativeToAndRange(JSContext *context, NSString *methodName, uintN *ioArgc, jsval **ioArgv, Entity **outRelativeTo, double *outRange);
static NSArray *FindJSVisibleEntities(EntityFilterPredicate predicate, void *parameter, Entity *relativeTo, double range);
static NSArray *FindShips(EntityFilterPredicate predicate, void *parameter, Entity *relativeTo, double range);
static NSComparisonResult CompareEntitiesByDistance(id a, id b, void *relativeTo);

static JSBool SystemAddShipsOrGroup(JSContext *context, uintN argc, jsval *vp, BOOL isGroup);
static JSBool SystemAddShipsOrGroupToRoute(JSContext *context, uintN argc, jsval *vp, BOOL isGroup);


static JSBool SystemGetProperty(JSContext *context, JSObject *this, jsid propID, jsval *value);
static JSBool SystemSetProperty(JSContext *context, JSObject *this, jsid propID, JSBool strict, jsval *value);

static JSBool SystemToString(JSContext *context, uintN argc, jsval *vp);
static JSBool SystemAddPlanet(JSContext *context, uintN argc, jsval *vp);
static JSBool SystemAddMoon(JSContext *context, uintN argc, jsval *vp);
static JSBool SystemSendAllShipsAway(JSContext *context, uintN argc, jsval *vp);
static JSBool SystemCountShipsWithPrimaryRole(JSContext *context, uintN argc, jsval *vp);
static JSBool SystemCountShipsWithRole(JSContext *context, uintN argc, jsval *vp);
static JSBool SystemCountEntitiesWithScanClass(JSContext *context, uintN argc, jsval *vp);
static JSBool SystemShipsWithPrimaryRole(JSContext *context, uintN argc, jsval *vp);
static JSBool SystemShipsWithRole(JSContext *context, uintN argc, jsval *vp);
static JSBool SystemEntitiesWithScanClass(JSContext *context, uintN argc, jsval *vp);
static JSBool SystemFilteredEntities(JSContext *context, uintN argc, jsval *vp);

static JSBool SystemAddShips(JSContext *context, uintN argc, jsval *vp);
static JSBool SystemAddGroup(JSContext *context, uintN argc, jsval *vp);
static JSBool SystemAddShipsToRoute(JSContext *context, uintN argc, jsval *vp);
static JSBool SystemAddGroupToRoute(JSContext *context, uintN argc, jsval *vp);
static JSBool SystemAddVisualEffect(JSContext *context, uintN argc, jsval *vp);

static JSBool SystemLegacyAddShips(JSContext *context, uintN argc, jsval *vp);
static JSBool SystemLegacyAddSystemShips(JSContext *context, uintN argc, jsval *vp);
static JSBool SystemLegacyAddShipsAt(JSContext *context, uintN argc, jsval *vp);
static JSBool SystemLegacyAddShipsAtPrecisely(JSContext *context, uintN argc, jsval *vp);
static JSBool SystemLegacyAddShipsWithinRadius(JSContext *context, uintN argc, jsval *vp);
static JSBool SystemLegacySpawnShip(JSContext *context, uintN argc, jsval *vp);

static JSBool SystemStaticSystemNameForID(JSContext *context, uintN argc, jsval *vp);
static JSBool SystemStaticSystemIDForName(JSContext *context, uintN argc, jsval *vp);
static JSBool SystemStaticInfoForSystem(JSContext *context, uintN argc, jsval *vp);


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
	kSystem_allVisualEffects,				// VEs in system, array of VEs, read-only
	kSystem_breakPattern, // witchspace break pattern shown
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
	// JS name					ID								flags
	{ "allShips",				kSystem_allShips,				OOJS_PROP_READONLY_CB },
	{ "allVisualEffects",	 kSystem_allVisualEffects,		OOJS_PROP_READONLY_CB },
	{ "breakPattern",			kSystem_breakPattern,			OOJS_PROP_READWRITE_CB },
	{ "description",			kSystem_description,			OOJS_PROP_READWRITE_CB },
	{ "economy",				kSystem_economy,				OOJS_PROP_READWRITE_CB },
	{ "economyDescription",		kSystem_economyDescription,		OOJS_PROP_READONLY_CB },
	{ "government",				kSystem_government,				OOJS_PROP_READWRITE_CB },
	{ "governmentDescription",	kSystem_governmentDescription,	OOJS_PROP_READONLY_CB },
	{ "ID",						kSystem_ID,						OOJS_PROP_READONLY_CB },
	{ "info",					kSystem_info,					OOJS_PROP_READONLY_CB },
	{ "inhabitantsDescription",	kSystem_inhabitantsDescription,	OOJS_PROP_READWRITE_CB },
	{ "isInterstellarSpace",	kSystem_isInterstellarSpace,	OOJS_PROP_READONLY_CB},
	{ "mainPlanet",				kSystem_mainPlanet,				OOJS_PROP_READONLY_CB },
	{ "mainStation",			kSystem_mainStation,			OOJS_PROP_READONLY_CB },
	{ "name",					kSystem_name,					OOJS_PROP_READWRITE_CB },
	{ "planets",				kSystem_planets,				OOJS_PROP_READONLY_CB },
	{ "population",				kSystem_population,				OOJS_PROP_READWRITE_CB },
	{ "productivity",			kSystem_productivity,			OOJS_PROP_READWRITE_CB },
	{ "pseudoRandom100",		kSystem_pseudoRandom100,		OOJS_PROP_READONLY_CB },
	{ "pseudoRandom256",		kSystem_pseudoRandom256,		OOJS_PROP_READONLY_CB },
	{ "pseudoRandomNumber",		kSystem_pseudoRandomNumber,		OOJS_PROP_READONLY_CB },
	{ "sun",					kSystem_sun,					OOJS_PROP_READONLY_CB },
	{ "techLevel",				kSystem_techLevel,				OOJS_PROP_READWRITE_CB },
	{ 0 }
};


static JSFunctionSpec sSystemMethods[] =
{
	// JS name							Function							min args
	{ "toString",						SystemToString,						0 },
	{ "addGroup",						SystemAddGroup,						3 },
	{ "addGroupToRoute",				SystemAddGroupToRoute,				2 },
	{ "addMoon",						SystemAddMoon,						1 },
	{ "addPlanet",						SystemAddPlanet,					1 },
	{ "addShips",						SystemAddShips,						3 },
	{ "addShipsToRoute",				SystemAddShipsToRoute,				2 },
	{ "addVisualEffect",						SystemAddVisualEffect,						2 },
	{ "countEntitiesWithScanClass",		SystemCountEntitiesWithScanClass,	1 },
	{ "countShipsWithPrimaryRole",		SystemCountShipsWithPrimaryRole,	1 },
	{ "countShipsWithRole",				SystemCountShipsWithRole,			1 },
	{ "entitiesWithScanClass",			SystemEntitiesWithScanClass,		1 },
	{ "filteredEntities",				SystemFilteredEntities,				2 },
	// scrambledPseudoRandomNumber is implemented in oolite-global-prefix.js
	{ "sendAllShipsAway",				SystemSendAllShipsAway,				1 },
	{ "shipsWithPrimaryRole",			SystemShipsWithPrimaryRole,			1 },
	{ "shipsWithRole",					SystemShipsWithRole,				1 },
	
	{ "legacy_addShips",				SystemLegacyAddShips,				2 },
	{ "legacy_addSystemShips",			SystemLegacyAddSystemShips,			3 },
	{ "legacy_addShipsAt",				SystemLegacyAddShipsAt,				6 },
	{ "legacy_addShipsAtPrecisely",		SystemLegacyAddShipsAtPrecisely,	6 },
	{ "legacy_addShipsWithinRadius",	SystemLegacyAddShipsWithinRadius,	7 },
	{ "legacy_spawnShip",				SystemLegacySpawnShip,				1 },
	{ 0 }
};


static JSFunctionSpec sSystemStaticMethods[] =
{
	{ "infoForSystem",			SystemStaticInfoForSystem,					2 },
	{ "systemIDForName",		SystemStaticSystemIDForName,				1 },
	{ "systemNameForID",		SystemStaticSystemNameForID,				1 },
	{ 0 }
};


void InitOOJSSystem(JSContext *context, JSObject *global)
{
	sSystemPrototype = JS_InitClass(context, global, NULL, &sSystemClass, OOJSUnconstructableConstruct, 0, sSystemProperties, sSystemMethods, NULL, sSystemStaticMethods);
	
	// Create system object as a property of the global object.
	JS_DefineObject(context, global, "system", &sSystemClass, sSystemPrototype, OOJS_PROP_READONLY);
}


static JSBool SystemGetProperty(JSContext *context, JSObject *this, jsid propID, jsval *value)
{
	if (!JSID_IS_INT(propID))  return YES;
	
	OOJS_NATIVE_ENTER(context)
	
	id							result = nil;
	PlayerEntity				*player = nil;
	NSDictionary				*systemData = nil;
	BOOL						handled = NO;
	
	player = OOPlayerForScripting();
	
	// Handle cases which don't require systemData.
	switch (JSID_TO_INT(propID))
	{
		case kSystem_ID:
			*value = INT_TO_JSVAL([player currentSystemID]);
			return YES;
			
		case kSystem_isInterstellarSpace:
			*value = OOJSValueFromBOOL([UNIVERSE inInterstellarSpace]);
			return YES;
			
		case kSystem_mainStation:
			result = [UNIVERSE station];
			handled = YES;
			break;
			
		case kSystem_mainPlanet:
			result = [UNIVERSE planet];
			handled = YES;
			break;
			
		case kSystem_sun:
			result = [UNIVERSE sun];
			handled = YES;
			break;
			
		case kSystem_planets:
			result = [[[UNIVERSE planets] objectEnumeratorFilteredWithSelector:@selector(isVisibleToScripts)] allObjects];
			handled = YES;
			break;
			
		case kSystem_allShips:
			OOJS_BEGIN_FULL_NATIVE(context)
			result = [UNIVERSE findShipsMatchingPredicate:JSEntityIsJavaScriptSearchablePredicate parameter:NULL inRange:-1 ofEntity:nil];
			OOJS_END_FULL_NATIVE
			handled = YES;
			break;

		case kSystem_allVisualEffects:
			OOJS_BEGIN_FULL_NATIVE(context)
			result = [UNIVERSE findVisualEffectsMatchingPredicate:JSEntityIsJavaScriptSearchablePredicate parameter:NULL inRange:-1 ofEntity:nil];
			OOJS_END_FULL_NATIVE
			handled = YES;
			break;
			
		case kSystem_info:
			*value = GetJSSystemInfoForSystem(context, [player currentGalaxyID], [player currentSystemID]);
			return YES;
		
		case kSystem_pseudoRandomNumber:
			return JS_NewNumberValue(context, [player systemPseudoRandomFloat], value);
			
		case kSystem_pseudoRandom100:
			*value = INT_TO_JSVAL([player systemPseudoRandom100]);
			return YES;
			
		case kSystem_pseudoRandom256:
			*value = INT_TO_JSVAL([player systemPseudoRandom256]);
			return YES;

		case kSystem_breakPattern:
			*value = OOJSValueFromBOOL([UNIVERSE witchspaceBreakPattern]);
			return YES;
	}
	
	if (!handled)
	{
		// Handle cases which do require systemData.
		if (EXPECT (![UNIVERSE inInterstellarSpace]))
		{
			systemData = [UNIVERSE currentSystemData];
			
			switch (JSID_TO_INT(propID))
			{
				case kSystem_name:
					result = [systemData objectForKey:KEY_NAME];
					break;
					
				case kSystem_description:
					result = [systemData objectForKey:KEY_DESCRIPTION];
					break;
					
				case kSystem_inhabitantsDescription:
					result = [systemData objectForKey:KEY_INHABITANTS];
					break;
					
				case kSystem_government:
					*value = INT_TO_JSVAL([systemData oo_intForKey:KEY_GOVERNMENT]);
					return YES;
					
				case kSystem_governmentDescription:
					result = OODisplayStringFromGovernmentID([systemData oo_intForKey:KEY_GOVERNMENT]);
					if (result == nil)  result = DESC(@"not-applicable");
					break;
					
				case kSystem_economy:
					*value = INT_TO_JSVAL([systemData oo_intForKey:KEY_ECONOMY]);
					return YES;
					
				case kSystem_economyDescription:
					result = OODisplayStringFromEconomyID([systemData oo_intForKey:KEY_ECONOMY]);
					if (result == nil)  result = DESC(@"not-applicable");
					break;
				
				case kSystem_techLevel:
					*value = INT_TO_JSVAL([systemData oo_intForKey:KEY_TECHLEVEL]);
					return YES;
					
				case kSystem_population:
					*value = INT_TO_JSVAL([systemData oo_intForKey:KEY_POPULATION]);
					return YES;
					
				case kSystem_productivity:
					*value = INT_TO_JSVAL([systemData oo_intForKey:KEY_PRODUCTIVITY]);
					return YES;
					
				default:
					OOJSReportBadPropertySelector(context, this, propID, sSystemProperties);
					return NO;
			}
		}
		else
		{
			// if in interstellar space, systemData values are null & void!
			switch (JSID_TO_INT(propID))
			{
				case kSystem_name:
					result = DESC(@"interstellar-space");
					break;
					
				case kSystem_description:
					result = @"";
					break;
					
				case kSystem_inhabitantsDescription:
					result = DESC(@"not-applicable");
					break;
					
				case kSystem_government:
					*value = INT_TO_JSVAL(-1);
					return YES;
					
				case kSystem_governmentDescription:
					result = DESC(@"not-applicable");
					break;
					
				case kSystem_economy:
					*value = INT_TO_JSVAL(-1);
					return YES;
					
				case kSystem_economyDescription:
					result = DESC(@"not-applicable");
					break;
				
				case kSystem_techLevel:
					*value = INT_TO_JSVAL(-1);
					return YES;
					
				case kSystem_population:
					*value = INT_TO_JSVAL(0);
					return YES;
					
				case kSystem_productivity:
					*value = INT_TO_JSVAL(0);
					return YES;
					
				default:
					OOJSReportBadPropertySelector(context, this, propID, sSystemProperties);
					return NO;
			}
		}
	}
	
	*value = OOJSValueFromNativeObject(context, result);
	return YES;
	
	OOJS_NATIVE_EXIT
}


static JSBool SystemSetProperty(JSContext *context, JSObject *this, jsid propID, JSBool strict, jsval *value)
{
	if (!JSID_IS_INT(propID))  return YES;
	
	OOJS_NATIVE_ENTER(context)
	
	PlayerEntity				*player = nil;
	OOGalaxyID					galaxy;
	OOSystemID					system;
	NSString					*stringValue = nil;
	int32						iValue;
	JSBool            bValue;
	
	player = OOPlayerForScripting();
	
	galaxy = [player currentGalaxyID];
	system = [player currentSystemID];

	switch (JSID_TO_INT(propID))
	{
		case kSystem_breakPattern:
			if (JS_ValueToBoolean(context, *value, &bValue))
			{
				[UNIVERSE setWitchspaceBreakPattern:bValue];
				return YES;
			}

			break;
		default:
		{}// do nothing yet
	}

	
	if (system == -1)  return YES;	// Can't change anything else in interstellar space.
	
	switch (JSID_TO_INT(propID))
	{
		case kSystem_name:
			stringValue = OOStringFromJSValue(context, *value);
			if (stringValue != nil)
			{
				[UNIVERSE setSystemDataForGalaxy:galaxy planet:system key:KEY_NAME value:stringValue];
				return YES;
			}
			break;
			
		case kSystem_description:
			stringValue = OOStringFromJSValue(context, *value);
			if (stringValue != nil)
			{
				[UNIVERSE setSystemDataForGalaxy:galaxy planet:system key:KEY_DESCRIPTION value:stringValue];
				return YES;
			}
			break;
			
		case kSystem_inhabitantsDescription:
			stringValue = OOStringFromJSValue(context, *value);
			if (stringValue != nil)
			{
				[UNIVERSE setSystemDataForGalaxy:galaxy planet:system key:KEY_INHABITANTS value:stringValue];
				return YES;
			}
			break;
			
		case kSystem_government:
			if (JS_ValueToInt32(context, *value, &iValue))
			{
				if (iValue < 0)  iValue = 0;
				if (7 < iValue)  iValue = 7;
				[UNIVERSE setSystemDataForGalaxy:galaxy planet:system key:KEY_GOVERNMENT value:[NSNumber numberWithInt:iValue]];
				return YES;
			}
			break;
			
		case kSystem_economy:
			if (JS_ValueToInt32(context, *value, &iValue))
			{
				if (iValue < 0)  iValue = 0;
				if (7 < iValue)  iValue = 7;
				[UNIVERSE setSystemDataForGalaxy:galaxy planet:system key:KEY_ECONOMY value:[NSNumber numberWithInt:iValue]];
				return YES;
			}
			break;
			
		case kSystem_techLevel:
			if (JS_ValueToInt32(context, *value, &iValue))
			{
				if (iValue < 0)  iValue = 0;
				if (15 < iValue)  iValue = 15;
				[UNIVERSE setSystemDataForGalaxy:galaxy planet:system key:KEY_TECHLEVEL value:[NSNumber numberWithInt:iValue]];
				return YES;
			}
			break;
			
		case kSystem_population:
			if (JS_ValueToInt32(context, *value, &iValue))
			{
				[UNIVERSE setSystemDataForGalaxy:galaxy planet:system key:KEY_POPULATION value:[NSNumber numberWithInt:iValue]];
				return YES;
			}
			break;
			
		case kSystem_productivity:
			if (JS_ValueToInt32(context, *value, &iValue))
			{
				[UNIVERSE setSystemDataForGalaxy:galaxy planet:system key:KEY_PRODUCTIVITY value:[NSNumber numberWithInt:iValue]];
				return YES;
			}
			break;
			
		default:
			OOJSReportBadPropertySelector(context, this, propID, sSystemProperties);
			return NO;
	}
	
	OOJSReportBadPropertyValue(context, this, propID, sSystemProperties, *value);
	return NO;
	
	OOJS_NATIVE_EXIT
}


// *** Methods ***

// toString() : String
static JSBool SystemToString(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	PlayerEntity		*player = OOPlayerForScripting();
	NSString			*systemDesc = nil;
	
	systemDesc = [NSString stringWithFormat:@"[System %u:%u \"%@\"]", [player currentGalaxyID], [player currentSystemID], [[UNIVERSE currentSystemData] objectForKey:KEY_NAME]];
	OOJS_RETURN_OBJECT(systemDesc);
	
	OOJS_NATIVE_EXIT
}


// addPlanet(key : String) : Planet
static JSBool SystemAddPlanet(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	PlayerEntity		*player = OOPlayerForScripting();
	NSString			*key = nil;
	OOPlanetEntity		*planet = nil;
	
	if (argc > 0)  key = OOStringFromJSValue(context, OOJS_ARGV[0]);
	if (EXPECT_NOT(key == nil))
	{
		OOJSReportBadArguments(context, @"System", @"addPlanet", MIN(argc, 1U), OOJS_ARGV, nil, @"string (planet key)");
		return NO;
	}
	
	OOJS_BEGIN_FULL_NATIVE(context)
	planet = [player addPlanet:key];
	OOJS_END_FULL_NATIVE
	
	OOJS_RETURN_OBJECT(planet);
	
	OOJS_NATIVE_EXIT
}


// addMoon(key : String) : Planet
static JSBool SystemAddMoon(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	PlayerEntity		*player = OOPlayerForScripting();
	NSString			*key = nil;
	OOPlanetEntity		*planet = nil;
	
	if (argc > 0)  key = OOStringFromJSValue(context, OOJS_ARGV[0]);
	if (EXPECT_NOT(key == nil))
	{
		OOJSReportBadArguments(context, @"System", @"addMoon", MIN(argc, 1U), OOJS_ARGV, nil, @"string (planet key)");
		return NO;
	}
	
	OOJS_BEGIN_FULL_NATIVE(context)
	planet = [player addMoon:key];
	OOJS_END_FULL_NATIVE
	
	OOJS_RETURN_OBJECT(planet);
	
	OOJS_NATIVE_EXIT
}


// sendAllShipsAway()
static JSBool SystemSendAllShipsAway(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	PlayerEntity *player = OOPlayerForScripting();
	
	[player sendAllShipsAway];
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}


// countShipsWithPrimaryRole(role : String [, relativeTo : Entity [, range : Number]]) : Number
static JSBool SystemCountShipsWithPrimaryRole(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	NSString			*role = nil;
	Entity				*relativeTo = nil;
	double				range = -1;
	unsigned			result;
	
	if (argc > 0)  role = OOStringFromJSValue(context, OOJS_ARGV[0]);
	if (EXPECT_NOT(role == nil))
	{
		OOJSReportBadArguments(context, @"System", @"countShipsWithPrimaryRole", MIN(argc, 1U), OOJS_ARGV, nil, @"string (role)");
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
static JSBool SystemCountShipsWithRole(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	NSString			*role = nil;
	Entity				*relativeTo = nil;
	double				range = -1;
	unsigned			result;
	
	if (argc > 0)  role = OOStringFromJSValue(context, OOJS_ARGV[0]);
	if (EXPECT_NOT(role == nil))
	{
		OOJSReportBadArguments(context, @"System", @"countShipsWithRole", MIN(argc, 1U), OOJS_ARGV, nil, @"string (role)");
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
static JSBool SystemShipsWithPrimaryRole(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	NSString			*role = nil;
	Entity				*relativeTo = nil;
	double				range = -1;
	NSArray				*result = nil;
	
	if (argc > 0)  role = OOStringFromJSValue(context, OOJS_ARGV[0]);
	if (EXPECT_NOT(role == nil))
	{
		OOJSReportBadArguments(context, @"System", @"countShipsWithRole", MIN(argc, 1U), OOJS_ARGV, nil, @"string (role)");
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
static JSBool SystemShipsWithRole(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	NSString			*role = nil;
	Entity				*relativeTo = nil;
	double				range = -1;
	NSArray				*result = nil;
	
	if (argc > 0)  role = OOStringFromJSValue(context, OOJS_ARGV[0]);
	if (EXPECT_NOT(role == nil))
	{
		OOJSReportBadArguments(context, @"System", @"shipsWithRole", MIN(argc, 1U), OOJS_ARGV, nil, @"string (role)");
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
static JSBool SystemCountEntitiesWithScanClass(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	OOScanClass			scanClass = CLASS_NOT_SET;
	Entity				*relativeTo = nil;
	double				range = -1;
	unsigned			result;
	
	if (argc > 0)  scanClass = OOScanClassFromJSValue(context, OOJS_ARGV[0]);
	if (scanClass == CLASS_NOT_SET)
	{
		OOJSReportBadArguments(context, @"System", @"countEntitiesWithScanClass", MIN(argc, 1U), OOJS_ARGV, nil, @"string (scan class)");
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
static JSBool SystemEntitiesWithScanClass(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	OOScanClass			scanClass = CLASS_NOT_SET;
	Entity				*relativeTo = nil;
	double				range = -1;
	NSArray				*result = nil;
	
	if (argc > 0)  scanClass = OOScanClassFromJSValue(context, OOJS_ARGV[0]);
	if (scanClass == CLASS_NOT_SET)
	{
		OOJSReportBadArguments(context, @"System", @"countEntitiesWithScanClass", MIN(argc, 1U), OOJS_ARGV, nil, @"string (scan class)");
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
static JSBool SystemFilteredEntities(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	JSObject			*jsThis = NULL;
	jsval				predicate;
	Entity				*relativeTo = nil;
	double				range = -1;
	NSArray				*result = nil;
	
	// Get this and predicate arguments
	if (argc < 2 || !OOJSValueIsFunction(context, OOJS_ARGV[1]) || !JS_ValueToObject(context, OOJS_ARGV[0], &jsThis))
	{
		OOJSReportBadArguments(context, @"System", @"filteredEntities", argc, OOJS_ARGV, nil, @"this, predicate function, and optional reference entity and range");
		return NO;
	}
	predicate = OOJS_ARGV[1];
	
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
static JSBool SystemAddShips(JSContext *context, uintN argc, jsval *vp)
{
	return SystemAddShipsOrGroup(context, argc, vp, NO);
}


// addGroup(role : String, count : Number [, position: Vector [, radius: Number]]) : Array
static JSBool SystemAddGroup(JSContext *context, uintN argc, jsval *vp)
{
	return SystemAddShipsOrGroup(context, argc, vp, YES);
}


// addShipsToRoute(role : String, count : Number [, position: Number [, route: String]])
static JSBool SystemAddShipsToRoute(JSContext *context, uintN argc, jsval *vp)
{
	return SystemAddShipsOrGroupToRoute(context, argc, vp, NO);
}


// addGroupToRoute(role : String, count : Number,  position: Number[, route: String])
static JSBool SystemAddGroupToRoute(JSContext *context, uintN argc, jsval *vp)
{
	return SystemAddShipsOrGroupToRoute(context, argc, vp, YES);
}


// legacy_addShips(role : String, count : Number)
static JSBool SystemLegacyAddShips(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	NSString			*role = nil;
	int32				count;
	
	if (argc > 0)  role = OOStringFromJSValue(context, OOJS_ARGV[0]);
	if (EXPECT_NOT(role == nil ||
				   !JS_ValueToInt32(context, OOJS_ARGV[1], &count) ||
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
static JSBool SystemLegacyAddSystemShips(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	jsdouble			position;
	NSString			*role = nil;
	int32				count;
	
	if (argc > 0)  role = OOStringFromJSValue(context, OOJS_ARGV[0]);
	if (EXPECT_NOT(role == nil ||
				   !JS_ValueToInt32(context, OOJS_ARGV[1], &count) ||
				   count < 1 || 64 < count ||
				   argc < 3 ||
				   !JS_ValueToNumber(context, OOJS_ARGV[2], &position)))
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
static JSBool SystemLegacyAddShipsAt(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	PlayerEntity		*player = OOPlayerForScripting();
	Vector				where;
	NSString			*role = nil;
	int32				count;
	NSString			*coordScheme = nil;
	NSString			*arg = nil;
	
	if (argc > 0)  role = OOStringFromJSValue(context, OOJS_ARGV[0]);
	coordScheme = OOStringFromJSValue(context, OOJS_ARGV[2]);
	if (EXPECT_NOT(role == nil ||
				   !JS_ValueToInt32(context, OOJS_ARGV[1], &count) ||
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
static JSBool SystemLegacyAddShipsAtPrecisely(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	PlayerEntity		*player = OOPlayerForScripting();
	Vector				where;
	NSString			*role = nil;
	int32				count;
	NSString			*coordScheme = nil;
	NSString			*arg = nil;
	
	if (argc > 0)  role = OOStringFromJSValue(context, OOJS_ARGV[0]);
	coordScheme = OOStringFromJSValue(context, OOJS_ARGV[2]);
	if (EXPECT_NOT(role == nil ||
				   !JS_ValueToInt32(context, OOJS_ARGV[1], &count) ||
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
static JSBool SystemLegacyAddShipsWithinRadius(JSContext *context, uintN argc, jsval *vp)
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
	
	if (argc > 0)  role = OOStringFromJSValue(context, OOJS_ARGV[0]);
	if (argc > 2)  coordScheme = OOStringFromJSValue(context, OOJS_ARGV[2]);
	if (EXPECT_NOT(role == nil ||
				   !JS_ValueToInt32(context, OOJS_ARGV[1], &count) ||
				   count < 1 || 64 < count ||
				   coordScheme == nil ||
				   argc < 5 ||
				   !VectorFromArgumentListNoError(context, argc - 3, OOJS_ARGV + 3, &where, &consumed) ||
				   !JS_ValueToNumber(context, OOJS_ARGV[3 + consumed], &radius)))
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
static JSBool SystemLegacySpawnShip(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	NSString			*key = nil;
	OOPlayerForScripting();	// For backwards-compatibility
	
	if (argc > 0)  key = OOStringFromJSValue(context, OOJS_ARGV[0]);
	if (key == nil)
	{
		OOJSReportBadArguments(context, @"System", @"legacy_spawnShip", MIN(argc, 1U), OOJS_ARGV, nil, @"string (ship key)");
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
static JSBool SystemStaticSystemNameForID(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	int32				systemID;
	
	if (argc < 1 || !JS_ValueToInt32(context, OOJS_ARGV[0], &systemID) || systemID < -1 || kOOMaximumSystemID < systemID)	// -1 interstellar space!
	{
		OOJSReportBadArguments(context, @"System", @"systemNameForID", MIN(argc, 1U), OOJS_ARGV, nil, @"system ID");
		return NO;
	}
	
	if (systemID == -1)
		OOJS_RETURN_OBJECT(DESC(@"interstellar-space"));
	else
		OOJS_RETURN_OBJECT([UNIVERSE getSystemName:[UNIVERSE systemSeedForSystemNumber:systemID]]);
	
	OOJS_NATIVE_EXIT
}


// systemIDForName(name : String) : Number
static JSBool SystemStaticSystemIDForName(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	NSString			*name = nil;
	unsigned			result;
	
	if (argc > 0)  name = OOStringFromJSValue(context, OOJS_ARGV[0]);
	if (name == nil)
	{
		OOJSReportBadArguments(context, @"System", @"systemIDForName", MIN(argc, 1U), OOJS_ARGV, nil, @"string");
		return NO;
	}
	
	OOJS_BEGIN_FULL_NATIVE(context)

	result = [UNIVERSE systemIDForSystemSeed:[UNIVERSE systemSeedForSystemName:name]];

	OOJS_END_FULL_NATIVE
	
	OOJS_RETURN_INT(result);
	
	OOJS_NATIVE_EXIT
}


// infoForSystem(galaxyID : Number, systemID : Number) : SystemInfo
static JSBool SystemStaticInfoForSystem(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	int32				galaxyID;
	int32				systemID;
	
	if (argc < 2 || !JS_ValueToInt32(context, OOJS_ARGV[0], &galaxyID) || !JS_ValueToInt32(context, OOJS_ARGV[1], &systemID))
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


static JSBool SystemAddVisualEffect(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	NSString			*key = nil;
	Vector         where;
	
	uintN				consumed = 0;

	if (argc > 0)  key = OOStringFromJSValue(context, OOJS_ARGV[0]);
	if (key == nil)
	{
		OOJSReportBadArguments(context, @"System", @"addVisualEffect", MIN(argc, 1U), &OOJS_ARGV[0], nil, @"string (key)");
		return NO;
	}

	if (!VectorFromArgumentListNoError(context, argc - 1, OOJS_ARGV + 1, &where, &consumed))
	{
		OOJSReportBadArguments(context, @"System", @"addVisualEffect", MIN(argc - 1, 1U), &OOJS_ARGV[1], nil, @"vector");
		return NO;
	}

	OOVisualEffectEntity *result = nil;

	OOJS_BEGIN_FULL_NATIVE(context)

	result = [UNIVERSE addVisualEffectAt:where withKey:key];

	OOJS_END_FULL_NATIVE
	
	OOJS_RETURN_OBJECT(result);

	OOJS_NATIVE_EXIT
}

// *** Helper functions ***

// Shared implementation of addShips() and addGroup().
static JSBool SystemAddShipsOrGroup(JSContext *context, uintN argc, jsval *vp, BOOL isGroup)
{
	OOJS_NATIVE_ENTER(context)
	
	NSString			*role = nil;
	int32				count = 0;
	uintN				consumed = 0;
	Vector				where;
	double				radius = NSNotFound;	// a negative value means 
	id					result = nil;
	
	NSString			*func = isGroup ? @"addGroup" : @"addShips";
	
	if (argc > 0)  role = OOStringFromJSValue(context, OOJS_ARGV[0]);
	if (role == nil)
	{
		OOJSReportBadArguments(context, @"System", func, MIN(argc, 1U), &OOJS_ARGV[0], nil, @"string (role)");
		return NO;
	}
	if (argc < 2 || !JS_ValueToInt32(context, OOJS_ARGV[1], &count) || count < 1 || 64 < count)
	{
		OOJSReportBadArguments(context, @"System", func, MIN(argc - 1, 1U), &OOJS_ARGV[1], nil, @"number (positive count no greater than 64)");
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
			OOJSReportBadArguments(context, @"System", func, MIN(argc - 2, 1U), &OOJS_ARGV[2], nil, @"vector");
			return NO;
		}
		
		if (argc > 2 + consumed)
		{
			if (!JS_ValueToNumber(context, OOJS_ARGV[2 + consumed], &radius))
			{
				OOJSReportBadArguments(context, @"System", func, MIN(argc - 2 - consumed, 1U), &OOJS_ARGV[2 + consumed], nil, @"number (radius)");
				return NO;
			}
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


static JSBool SystemAddShipsOrGroupToRoute(JSContext *context, uintN argc, jsval *vp, BOOL isGroup)
{
	OOJS_NATIVE_ENTER(context)
	
	NSString			*role = nil;
	NSString			*route = @"st"; // default route witchpoint -> station. ("st" itself is not selectable by script)
	static NSSet		*validRoutes = nil;
	int32				count = 0;
	double				where = NSNotFound;		// a negative value means random positioning!
	id					result = nil;
	
	NSString			*func = isGroup ? @"addGroup" : @"addShips";
	
	if (argc > 0)  role = OOStringFromJSValue(context, OOJS_ARGV[0]);
	if (role == nil)
	{
		OOJSReportBadArguments(context, @"System", func, MIN(argc, 1U), &OOJS_ARGV[0], nil, @"string (role)");
		return NO;
	}
	if (argc < 2 || !JS_ValueToInt32(context, OOJS_ARGV[1], &count) || count < 1 || 64 < count)
	{
		OOJSReportBadArguments(context, @"System", func, MIN(argc - 1, 1U), &OOJS_ARGV[1], nil, @"number (positive count no greater than 64)");
		return NO;
	}
	
	if (argc > 2)
	{
		if (!JS_ValueToNumber(context, OOJS_ARGV[2], &where) || !isfinite(where) || where < 0.0f || where > 1.0f)
		{
			OOJSReportBadArguments(context, @"System", func, MIN(argc - 2, 1U), &OOJS_ARGV[2], nil, @"number (position along route)");
			return NO;
		}
		
		if (argc > 3)
		{
			route = [OOStringFromJSValue(context, OOJS_ARGV[3]) lowercaseString];
			
			if (validRoutes == nil)
			{
				validRoutes = [[NSSet alloc] initWithObjects:@"wp", @"pw", @"ws", @"sw", @"sp", @"ps", nil];
			}
			
			if (route == nil || ![validRoutes containsObject:route])
			{
				OOJSReportBadArguments(context, @"System", func, MIN(argc - 3, 1U), &OOJS_ARGV[3], nil, @"string (route specifier)");
				return NO;
			}
		}
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
