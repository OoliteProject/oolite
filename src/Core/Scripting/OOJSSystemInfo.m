/*

OOJSSystemInfo.m

Oolite
Copyright (C) 2004-2010 Giles C Williams and contributors

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

#import "OOJSSystemInfo.h"
#import "OOJavaScriptEngine.h"
#import "PlayerEntityScriptMethods.h"
#import "Universe.h"
#import "OOJSVector.h"
#import "OOIsNumberLiteral.h"
#import "OOConstToString.h"


static JSObject *sSystemInfoPrototype;
static JSObject *sCachedSystemInfo;
static OOGalaxyID sCachedGalaxy;
static OOSystemID sCachedSystem;


static JSBool SystemInfoDeleteProperty(JSContext *context, JSObject *this, jsval name, jsval *value);
static JSBool SystemInfoGetProperty(JSContext *context, JSObject *this, jsval name, jsval *outValue);
static JSBool SystemInfoSetProperty(JSContext *context, JSObject *this, jsval name, jsval *value);
static void SystemInfoFinalize(JSContext *context, JSObject *this);
static JSBool SystemInfoDistanceToSystem(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool SystemInfoRouteToSystem(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool SystemInfoStaticFilteredSystems(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);


static JSExtendedClass sSystemInfoClass =
{
	{
		"SystemInfo",
		JSCLASS_IS_ANONYMOUS | JSCLASS_HAS_PRIVATE | JSCLASS_IS_EXTENDED,
		
		JS_PropertyStub,
		SystemInfoDeleteProperty,
		SystemInfoGetProperty,
		SystemInfoSetProperty,
		JS_EnumerateStub,
		JS_ResolveStub,
		JS_ConvertStub,
		SystemInfoFinalize,
		JSCLASS_NO_OPTIONAL_MEMBERS
	},
	JSObjectWrapperEquality,	// equality
	NULL,						// outerObject
	NULL,						// innerObject
	JSCLASS_NO_RESERVED_MEMBERS
};


enum
{
	// Property IDs
	kSystemInfo_coordinates,	// system coordinates, Vector3D (with z=0), read-only
	kSystemInfo_galaxyID,		// galaxy number, integer, read-only
	kSystemInfo_systemID		// system number, integer, read-only
};


static JSPropertySpec sSystemInfoProperties[] =
{
	// JS name					ID							flags
	{ "coordinates",			kSystemInfo_coordinates,	JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "galaxyID",				kSystemInfo_galaxyID,		JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "systemID",				kSystemInfo_systemID,		JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ 0 }
};


static JSFunctionSpec sSystemInfoMethods[] =
{
	// JS name					Function					min args
	{ "toString",				JSObjectWrapperToString,	0 },
	{ "distanceToSystem",		SystemInfoDistanceToSystem,	1 },
	{ "routeToSystem",			SystemInfoRouteToSystem,	1 },
	{ 0 }
};


static JSFunctionSpec sSystemInfoStaticMethods[] =
{
	// JS name					Function					min args
	{ "filteredSystems",		SystemInfoStaticFilteredSystems, 2 },
	{ 0 }
};



// Helper class wrapped by JS SystemInfo objects
@interface OOSystemInfo: NSObject
{
	OOGalaxyID				_galaxy;
	OOSystemID				_system;
	NSString				*_planetKey;
}

- (id) initWithGalaxy:(OOGalaxyID)galaxy system:(OOSystemID)system;

- (id) valueForKey:(NSString *)key;
- (void) setValue:(id)value forKey:(NSString *)key;

- (OOGalaxyID) galaxy;
- (OOSystemID) system;
- (Random_Seed) systemSeed;

@end


@implementation OOSystemInfo

- (id) init
{
	[self release];
	return nil;
}


- (id) initWithGalaxy:(OOGalaxyID)galaxy system:(OOSystemID)system
{
	if (galaxy > kOOMaximumGalaxyID || system > kOOMaximumSystemID || system < kOOMinimumSystemID)
	{
		[self release];
		return nil;
	}
	
	if ((self = [super init]))
	{
		_galaxy = galaxy;
		_system = system;
		_planetKey = [[NSString stringWithFormat:@"%u %i", galaxy, system] retain];
	}
	return self;
}


- (void) dealloc
{
	[_planetKey release];
	
	[super dealloc];
}


- (NSString *) descriptionComponents
{
	return [NSString stringWithFormat:@"galaxy %u, system %i", _galaxy, _system];
}


- (NSString *) shortDescriptionComponents
{
	return _planetKey;
}


- (NSString *) jsClassName
{
	return @"SystemInfo";
}


- (BOOL) isEqual:(id)other
{
	return other == self ||
		   ([other isKindOfClass:[OOSystemInfo class]] &&
			[other galaxy] == _galaxy &&
			[other system] == _system);
					 
}


- (OOUInteger) hash
{
	OOUInteger hash = _galaxy;
	hash <<= 16;
	hash |= (uint16_t)_system;
	return hash;
}


- (id) valueForKey:(NSString *)key
{
	
	if ([UNIVERSE inInterstellarSpace] && _system == -1) 
	{
		return [[UNIVERSE currentSystemData] objectForKey:key];
	}
	return [UNIVERSE getSystemDataForGalaxy:_galaxy	planet:_system key:key];
}


- (void) setValue:(id)value forKey:(NSString *)key
{	
	[UNIVERSE setSystemDataForGalaxy:_galaxy planet:_system key:key value:value];
}


- (OOGalaxyID) galaxy
{
	return _galaxy;
}


- (OOSystemID) system
{
	return _system;
}


- (Random_Seed) systemSeed
{
	NSAssert([[PlayerEntity sharedPlayer] currentGalaxyID] == _galaxy, @"Attempt to use -[OOSystemInfo systemSeed] from a different galaxy.");
	return [UNIVERSE systemSeedForSystemNumber:_system];
}


- (NSPoint) coordinates
{
	if ([UNIVERSE inInterstellarSpace] && _system == -1) 
	{
		return [[PlayerEntity sharedPlayer] galaxy_coordinates];
	}
	return [UNIVERSE coordinatesForSystem:[self systemSeed]];
}


- (jsval) javaScriptValueInContext:(JSContext *)context
{
	JSObject					*jsSelf = NULL;
	jsval						result = JSVAL_NULL;
	
	jsSelf = JS_NewObject(context, &sSystemInfoClass.base, sSystemInfoPrototype, NULL);
	if (jsSelf != NULL)
	{
		if (!JS_SetPrivate(context, jsSelf, [self retain]))  jsSelf = NULL;
	}
	if (jsSelf != NULL)  result = OBJECT_TO_JSVAL(jsSelf);
	
	return result;
}

@end



void InitOOJSSystemInfo(JSContext *context, JSObject *global)
{
	sSystemInfoPrototype = JS_InitClass(context, global, NULL, &sSystemInfoClass.base, NULL, 0, sSystemInfoProperties, sSystemInfoMethods, NULL, sSystemInfoStaticMethods);
	JSRegisterObjectConverter(&sSystemInfoClass.base, JSBasicPrivateObjectConverter);
}


BOOL GetJSSystemInfoForCurrentSystem(JSContext *context, jsval *outInfo)
{
	PlayerEntity *player = [PlayerEntity sharedPlayer];
	return GetJSSystemInfoForSystem(context, [player currentGalaxyID], [player currentSystemID], outInfo);
}


BOOL GetJSSystemInfoForSystem(JSContext *context, OOGalaxyID galaxy, OOSystemID system, jsval *outInfo)
{
	// Use cached object if possible.
	if (sCachedSystemInfo != NULL &&
		sCachedGalaxy == galaxy &&
		sCachedSystem == system)
	{
		*outInfo = OBJECT_TO_JSVAL(sCachedSystemInfo);
		return YES;
	}
	
	// If not, create a new one.
	OOSystemInfo *info = [[[OOSystemInfo alloc] initWithGalaxy:galaxy system:system] autorelease];
	if (info == nil)
	{
		OOReportJSError(context, @"Could not create system info object for galaxy %u, system %i.", galaxy, system);
		return NO;
	}
	
	*outInfo = [info javaScriptValueInContext:context];
	if (JSVAL_IS_OBJECT(*outInfo) && !JSVAL_IS_NULL(*outInfo))
	{
		// Cache is not a root; we clear it in finalize if necessary.
		sCachedSystemInfo = JSVAL_TO_OBJECT(*outInfo);
		sCachedGalaxy = galaxy;
		sCachedSystem = system;
		return YES;
	}
	else  return NO;
}


static void SystemInfoFinalize(JSContext *context, JSObject *this)
{
	[(id)JS_GetPrivate(context, this) release];
	JS_SetPrivate(context, this, nil);
	
	// Clear now-stale cache entry if appropriate.
	if (sCachedSystemInfo == this)  sCachedSystemInfo = NULL;
}


static JSBool SystemInfoDeleteProperty(JSContext *context, JSObject *this, jsval name, jsval *value)
{
	jsval v = JSVAL_VOID;
	return SystemInfoSetProperty(context, this, name, &v);
}


static JSBool SystemInfoGetProperty(JSContext *context, JSObject *this, jsval name, jsval *outValue)
{
	if (this == sSystemInfoPrototype)
	{
		// Let SpiderMonkey handle access to the prototype object (where info will be nil).
		return YES;
	}
	
	OOSystemInfo	*info = JSObjectToObjectOfClass(context, this, [OOSystemInfo class]);
	// What if we're trying to access a saved witchspace systemInfo object?
	BOOL savedInterstellarInfo = ![UNIVERSE inInterstellarSpace] && [info system] == -1;
	BOOL sameGalaxy = [[PlayerEntity sharedPlayer] currentGalaxyID] == [info galaxy];
	
	
	if (JSVAL_IS_INT(name))
	{
		BOOL OK = NO;
		
		switch (JSVAL_TO_INT(name))
		{
			case kSystemInfo_coordinates:
				if (sameGalaxy && !savedInterstellarInfo)
				{
					NSPoint coords = [info coordinates];
					// Convert from internal scale to light years.
					coords.x *= 0.4;
					coords.y *= 0.2; // y-axis had a different scale than x-axis
					OK = NSPointToVectorJSValue(context, coords, outValue);
				}
				else
				{
					OOReportJSError(context, @"Cannot read systemInfo values for %@.", savedInterstellarInfo ? @"invalid interstellar space reference" : @"other galaxies");
					*outValue = JSVAL_VOID;
					// OK remains NO
				}
				break;
				
			case kSystemInfo_galaxyID:
				*outValue = INT_TO_JSVAL([info galaxy]);
				OK = YES;
				break;
				
			case kSystemInfo_systemID:
				*outValue = INT_TO_JSVAL([info system]);
				OK = YES;
				break;
				
			default:
				OOReportJSBadPropertySelector(context, @"SystemInfo", JSVAL_TO_INT(name));
		}
		
		return OK;
	}
	else if (JSVAL_IS_STRING(name))
	{
		NSString		*key = [NSString stringWithJavaScriptValue:name inContext:context];
		id				value = nil;
		
		if (!sameGalaxy || savedInterstellarInfo)
		{
			OOReportJSError(context, @"Cannot read systemInfo values for %@.", savedInterstellarInfo ?  @"invalid interstellar space reference" : @"other galaxies");
			*outValue = JSVAL_VOID;
			return NO;
		}
		
		value = [info valueForKey:key];
		
		if (value != nil)
		{
			if ([value isKindOfClass:[NSNumber class]] || OOIsNumberLiteral(value, YES))
			{
				BOOL OK = JS_NewDoubleValue(context, [value doubleValue], outValue);
				if (!OK)
				{
					*outValue = JSVAL_VOID;
					return NO;
				}
			}
			else
			{
				*outValue = [value javaScriptValueInContext:context];
			}
		}
	}
	return YES;
}


static JSBool SystemInfoSetProperty(JSContext *context, JSObject *this, jsval name, jsval *value)
{
	if (this == sSystemInfoPrototype)
	{
		// Let SpiderMonkey handle access to the prototype object (where info will be nil).
		return YES;
	}
	
	if (JSVAL_IS_STRING(name))
	{
		NSString		*key = [NSString stringWithJavaScriptValue:name inContext:context];
		OOSystemInfo	*info = JSObjectToObjectOfClass(context, this, [OOSystemInfo class]);
		
		[info setValue:JSValToNSString(context, *value) forKey:key];
	}
	return YES;
}


// distanceToSystem(sys : SystemInfo) : Number
static JSBool SystemInfoDistanceToSystem(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	if(!JSVAL_IS_OBJECT(argv[0]))
	{
		OOReportJSBadArguments(context, @"SystemInfo", @"distanceToSystem", argc, argv, nil, @"SystemInfo");
		return NO;
	}
	OOSystemInfo *thisInfo = JSObjectToObjectOfClass(context, this, [OOSystemInfo class]);
	OOSystemInfo *otherInfo  = JSObjectToObjectOfClass(context, JSVAL_TO_OBJECT(argv[0]), [OOSystemInfo class]);
	if (thisInfo == nil || otherInfo == nil)
	{
		OOReportJSBadArguments(context, @"SystemInfo", @"distanceToSystem", argc, argv, nil, @"SystemInfo");
		return NO;
	}
	
	BOOL sameGalaxy = ([thisInfo galaxy] == [otherInfo galaxy]);
	if (!sameGalaxy)
	{
		OOReportJSError(context, @"Cannot calculate distance for systems in other galaxies.");
		return NO;
	}
	
	NSPoint thisCoord = [thisInfo coordinates];
	NSPoint otherCoord = [otherInfo coordinates];
	
	return JS_NewDoubleValue(context, distanceBetweenPlanetPositions(thisCoord.x, thisCoord.y, otherCoord.x, otherCoord.y), outResult);
}


// routeToSystem(sys : SystemInfo [, optimizedBy : String]) : Dictionary
static JSBool SystemInfoRouteToSystem(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	NSDictionary *result = nil;
	OORouteType routeType = OPTIMIZED_BY_JUMPS;
	
	if(!JSVAL_IS_OBJECT(argv[0]))
	{
		OOReportJSBadArguments(context, @"SystemInfo", @"routeToSystem", argc, argv, nil, @"SystemInfo");
		return NO;
	}
	OOSystemInfo *thisInfo = JSObjectToObjectOfClass(context, this, [OOSystemInfo class]);
	OOSystemInfo *otherInfo  = JSObjectToObjectOfClass(context, JSVAL_TO_OBJECT(argv[0]), [OOSystemInfo class]);
	if (thisInfo == nil || otherInfo == nil)
	{
		OOReportJSBadArguments(context, @"SystemInfo", @"routeToSystem", argc, argv, nil, @"SystemInfo");
		return NO;
	}
	
	BOOL sameGalaxy = ([thisInfo galaxy] == [otherInfo galaxy]);
	if (!sameGalaxy)
	{
		OOReportJSError(context, @"Cannot calculate route for destinations in other galaxies.");
		return NO;
	}
	
	if (argc >= 2)
	{
		routeType = StringToRouteType(JSValToNSString(context, argv[1]));
	}
	
	result = [UNIVERSE routeFromSystem:[thisInfo system] toSystem:[otherInfo system] optimizedBy:routeType];
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


// filteredSystems(this : Object, predicate : Function) : Array
static JSBool SystemInfoStaticFilteredSystems(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	// Get this and predicate arguments.
	jsval predicate = argv[1];
	JSObject *jsThis = NULL;
	if (EXPECT_NOT(!JS_ObjectIsFunction(context, JSVAL_TO_OBJECT(predicate)) || !JS_ValueToObject(context, argv[0], &jsThis)))
	{
		OOReportJSBadArguments(context, @"SystemInfo", @"filteredSystems", argc, argv, nil, @"this and predicate function");
		return NO;
	}
	
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSMutableArray *result = [NSMutableArray arrayWithCapacity:256];
	
	OOJSPauseTimeLimiter();
	
	// Iterate over systems.
	BOOL OK = YES;
	OOGalaxyID galaxy = [[PlayerEntity sharedPlayer] currentGalaxyID];
	OOSystemID system;
	for (system = 0; system <= kOOMaximumSystemID; system++)
	{
		// NOTE: this deliberately bypasses the cache, since it's inherently unfriendly to a single-item cache.
		OOSystemInfo *info = [[[OOSystemInfo alloc] initWithGalaxy:galaxy system:system] autorelease];
		jsval args[1] = { [info javaScriptValueInContext:context] };
		
		jsval rval = JSVAL_VOID;
		OOJSResumeTimeLimiter();
		OK = JS_CallFunctionValue(context, jsThis, predicate, 1, args, &rval);
		OOJSPauseTimeLimiter();
		
		if (OK)
		{
			if (JS_IsExceptionPending(context))
			{
				JS_ReportPendingException(context);
				OK = NO;
			}
		}
		
		if (OK)
		{
			JSBool boolVal;
			if (JS_ValueToBoolean(context, rval, &boolVal) && boolVal)
			{
				[result addObject:info];
			}
		}
		
		if (!OK)  break;
	}
	
	if (OK)
	{
		*outResult = [result javaScriptValueInContext:context];
	}
	[pool release];
	
	OOJSResumeTimeLimiter();
	return OK;
}
