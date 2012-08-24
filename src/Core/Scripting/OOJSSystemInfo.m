/*

OOJSSystemInfo.m

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


static JSBool SystemInfoDeleteProperty(JSContext *context, JSObject *this, jsid propID, jsval *value);
static JSBool SystemInfoGetProperty(JSContext *context, JSObject *this, jsid propID, jsval *value);
static JSBool SystemInfoSetProperty(JSContext *context, JSObject *this, jsid propID, JSBool strict, jsval *value);
static void SystemInfoFinalize(JSContext *context, JSObject *this);
static JSBool SystemInfoEnumerate(JSContext *context, JSObject *this, JSIterateOp enumOp, jsval *state, jsid *idp);

static JSBool SystemInfoDistanceToSystem(JSContext *context, uintN argc, jsval *vp);
static JSBool SystemInfoRouteToSystem(JSContext *context, uintN argc, jsval *vp);
static JSBool SystemInfoStaticFilteredSystems(JSContext *context, uintN argc, jsval *vp);


static JSClass sSystemInfoClass =
{
	"SystemInfo",
	JSCLASS_HAS_PRIVATE | JSCLASS_NEW_ENUMERATE,
	
	JS_PropertyStub,
	SystemInfoDeleteProperty,
	SystemInfoGetProperty,
	SystemInfoSetProperty,
	(JSEnumerateOp)SystemInfoEnumerate,
	JS_ResolveStub,
	JS_ConvertStub,
	SystemInfoFinalize,
	JSCLASS_NO_OPTIONAL_MEMBERS
};


enum
{
	// Property IDs
	kSystemInfo_coordinates,	// system coordinates (in LY), Vector3D (with z = 0), read-only
	kSystemInfo_internalCoordinates,	// system coordinates (unscaled), Vector3D (with z = 0), read-only
	kSystemInfo_galaxyID,		// galaxy number, integer, read-only
	kSystemInfo_systemID		// system number, integer, read-only
};


static JSPropertySpec sSystemInfoProperties[] =
{
	// JS name					ID									flags
	{ "coordinates",			kSystemInfo_coordinates,			OOJS_PROP_READONLY_CB },
	{ "internalCoordinates",	kSystemInfo_internalCoordinates,	OOJS_PROP_READONLY_CB },
	{ "galaxyID",				kSystemInfo_galaxyID,				OOJS_PROP_READONLY_CB },
	{ "systemID",				kSystemInfo_systemID,				OOJS_PROP_READONLY_CB },
	{ 0 }
};


static JSFunctionSpec sSystemInfoMethods[] =
{
	// JS name					Function					min args
	{ "toString",				OOJSObjectWrapperToString,	0 },
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
@private
	OOGalaxyID				_galaxy;
	OOSystemID				_system;
	NSString				*_planetKey;
}

- (id) initWithGalaxy:(OOGalaxyID)galaxy system:(OOSystemID)system;

- (id) valueForKey:(NSString *)key;
- (void) setValue:(id)value forKey:(NSString *)key;

- (NSArray *) allKeys;

- (OOGalaxyID) galaxy;
- (OOSystemID) system;
- (Random_Seed) systemSeed;

@end


DEFINE_JS_OBJECT_GETTER(JSSystemInfoGetSystemInfo, &sSystemInfoClass, sSystemInfoPrototype, OOSystemInfo);


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


- (NSString *) oo_jsClassName
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
	return [UNIVERSE systemDataForGalaxy:_galaxy planet:_system key:key];
}


- (void) setValue:(id)value forKey:(NSString *)key
{
	[UNIVERSE setSystemDataForGalaxy:_galaxy planet:_system key:key value:value];
}


- (NSArray *) allKeys
{
	if ([UNIVERSE inInterstellarSpace] && _system == -1) 
	{
		return [[UNIVERSE currentSystemData] allKeys];
	}
	return [UNIVERSE systemDataKeysForGalaxy:_galaxy planet:_system];
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
	NSAssert([PLAYER currentGalaxyID] == _galaxy, @"Attempt to use -[OOSystemInfo systemSeed] from a different galaxy.");
	return [UNIVERSE systemSeedForSystemNumber:_system];
}


- (NSPoint) coordinates
{
	if ([UNIVERSE inInterstellarSpace] && _system == -1) 
	{
		return [PLAYER galaxy_coordinates];
	}
	return [UNIVERSE coordinatesForSystem:[self systemSeed]];
}


- (jsval) oo_jsValueInContext:(JSContext *)context
{
	JSObject					*jsSelf = NULL;
	jsval						result = JSVAL_NULL;
	
	jsSelf = JS_NewObject(context, &sSystemInfoClass, sSystemInfoPrototype, NULL);
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
	sSystemInfoPrototype = JS_InitClass(context, global, NULL, &sSystemInfoClass, OOJSUnconstructableConstruct, 0, sSystemInfoProperties, sSystemInfoMethods, NULL, sSystemInfoStaticMethods);
	OOJSRegisterObjectConverter(&sSystemInfoClass, OOJSBasicPrivateObjectConverter);
}


jsval GetJSSystemInfoForSystem(JSContext *context, OOGalaxyID galaxy, OOSystemID system)
{
	OOJS_PROFILE_ENTER
	
	// Use cached object if possible.
	if (sCachedSystemInfo != NULL &&
		sCachedGalaxy == galaxy &&
		sCachedSystem == system)
	{
		return OBJECT_TO_JSVAL(sCachedSystemInfo);
	}
	
	// If not, create a new one.
	OOSystemInfo *info = nil;
	jsval result;
	OOJS_BEGIN_FULL_NATIVE(context)
	info = [[[OOSystemInfo alloc] initWithGalaxy:galaxy system:system] autorelease];
	OOJS_END_FULL_NATIVE
	
	if (EXPECT_NOT(info == nil))
	{
		OOJSReportWarning(context, @"Could not create system info object for galaxy %u, system %i.", galaxy, system);
	}
	
	result = OOJSValueFromNativeObject(context, info);
	
	// Cache is not a root; we clear it in finalize if necessary.
	sCachedSystemInfo = JSVAL_TO_OBJECT(result);
	sCachedGalaxy = galaxy;
	sCachedSystem = system;
	
	return result;
	
	OOJS_PROFILE_EXIT_JSVAL
}


static void SystemInfoFinalize(JSContext *context, JSObject *this)
{
	OOJS_PROFILE_ENTER
	
	[(id)JS_GetPrivate(context, this) release];
	JS_SetPrivate(context, this, nil);
	
	// Clear now-stale cache entry if appropriate.
	if (sCachedSystemInfo == this)  sCachedSystemInfo = NULL;
	
	OOJS_PROFILE_EXIT_VOID
}


static JSBool SystemInfoEnumerate(JSContext *context, JSObject *this, JSIterateOp enumOp, jsval *state, jsid *idp)
{
	OOJS_NATIVE_ENTER(context)
	
	NSEnumerator *enumerator = nil;
	
	switch (enumOp)
	{
		case JSENUMERATE_INIT:
		case JSENUMERATE_INIT_ALL:	// For ES5 Object.getOwnPropertyNames(). Since we have no non-enumerable properties, this is the same as _INIT.
		{
			OOSystemInfo *info = JS_GetPrivate(context, this);
			NSArray *keys = [info allKeys];
			enumerator = [[keys objectEnumerator] retain];
			*state = PRIVATE_TO_JSVAL(enumerator);
			
			if (idp != NULL)  *idp = INT_TO_JSID([keys count]);
			return YES;
		}
		
		case JSENUMERATE_NEXT:
		{
			enumerator = JSVAL_TO_PRIVATE(*state);
			NSString *next = [enumerator nextObject];
			if (next != nil)
			{
				jsval val = [next oo_jsValueInContext:context];
				return JS_ValueToId(context, val, idp);
			}
			// else:
			*state = JSVAL_NULL;
			// Fall through.
		}
		
		case JSENUMERATE_DESTROY:
		{
			if (enumerator == nil && JSVAL_IS_DOUBLE(*state))
			{
				enumerator = JSVAL_TO_PRIVATE(*state);
			}
			[enumerator release];
			
			if (idp != NULL)  *idp = JSID_VOID;
			return YES;
		}
	}
	
	
	
	OOJS_NATIVE_EXIT
}


static JSBool SystemInfoDeleteProperty(JSContext *context, JSObject *this, jsid propID, jsval *value)
{
	OOJS_PROFILE_ENTER	// Any exception will be converted in SystemInfoSetProperty()
	
	jsval v = JSVAL_VOID;
	return SystemInfoSetProperty(context, this, propID, NO, &v);
	
	OOJS_PROFILE_EXIT
}


static JSBool SystemInfoGetProperty(JSContext *context, JSObject *this, jsid propID, jsval *value)
{
	OOJS_NATIVE_ENTER(context)
	
	if (this == sSystemInfoPrototype)
	{
		// Let SpiderMonkey handle access to the prototype object (where info will be nil).
		return YES;
	}
	
	OOSystemInfo	*info = OOJSNativeObjectOfClassFromJSObject(context, this, [OOSystemInfo class]);
	// What if we're trying to access a saved witchspace systemInfo object?
	BOOL savedInterstellarInfo = ![UNIVERSE inInterstellarSpace] && [info system] == -1;
	BOOL sameGalaxy = [PLAYER currentGalaxyID] == [info galaxy];
	
	
	if (JSID_IS_INT(propID))
	{
		switch (JSID_TO_INT(propID))
		{
			case kSystemInfo_coordinates:
				if (sameGalaxy && !savedInterstellarInfo)
				{
					return VectorToJSValue(context, OOGalacticCoordinatesFromInternal([info coordinates]), value);
				}
				else
				{
					OOJSReportError(context, @"Cannot read systemInfo values for %@.", savedInterstellarInfo ? @"invalid interstellar space reference" : @"other galaxies");
					return NO;
				}
				break;
				
			case kSystemInfo_internalCoordinates:
				if (sameGalaxy && !savedInterstellarInfo)
				{
					return NSPointToVectorJSValue(context, [info coordinates], value);
				}
				else
				{
					OOJSReportError(context, @"Cannot read systemInfo values for %@.", savedInterstellarInfo ? @"invalid interstellar space reference" : @"other galaxies");
					return NO;
				}
				break;
				
			case kSystemInfo_galaxyID:
				*value = INT_TO_JSVAL([info galaxy]);
				return YES;
				
			case kSystemInfo_systemID:
				*value = INT_TO_JSVAL([info system]);
				return YES;
				
			default:
				OOJSReportBadPropertySelector(context, this, propID, sSystemInfoProperties);
				return NO;
		}
	}
	else if (JSID_IS_STRING(propID))
	{
		NSString *key = OOStringFromJSString(context, JSID_TO_STRING(propID));
		
		if (!sameGalaxy || savedInterstellarInfo)
		{
			OOJSReportError(context, @"Cannot read systemInfo values for %@.", savedInterstellarInfo ?  @"invalid interstellar space reference" : @"other galaxies");
			*value = JSVAL_VOID;
			return NO;
		}
		
		id propValue = [info valueForKey:key];
		
		if (propValue != nil)
		{
			if ([propValue isKindOfClass:[NSNumber class]] || OOIsNumberLiteral(propValue, YES))
			{
				BOOL OK = JS_NewNumberValue(context, [propValue doubleValue], value);
				if (!OK)
				{
					*value = JSVAL_VOID;
					return NO;
				}
			}
			else
			{
				*value = [propValue oo_jsValueInContext:context];
			}
		}
	}
	return YES;
	
	OOJS_NATIVE_EXIT
}


static JSBool SystemInfoSetProperty(JSContext *context, JSObject *this, jsid propID, JSBool strict, jsval *value)
{
	if (EXPECT_NOT(this == sSystemInfoPrototype))
	{
		// Let SpiderMonkey handle access to the prototype object (where info will be nil).
		return YES;
	}
	
	OOJS_NATIVE_ENTER(context);
	
	if (JSID_IS_STRING(propID))
	{
		NSString		*key = OOStringFromJSString(context, JSID_TO_STRING(propID));
		OOSystemInfo	*info = OOJSNativeObjectOfClassFromJSObject(context, this, [OOSystemInfo class]);
		
		[info setValue:OOStringFromJSValue(context, *value) forKey:key];
	}
	return YES;
	
	OOJS_NATIVE_EXIT
}


// distanceToSystem(sys : SystemInfo) : Number
static JSBool SystemInfoDistanceToSystem(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	OOSystemInfo			*thisInfo = nil;
	JSObject				*otherObj = NULL;
	OOSystemInfo			*otherInfo = nil;
	
	if (!JSSystemInfoGetSystemInfo(context, OOJS_THIS, &thisInfo))  return NO;
	if (argc < 1 || !JS_ValueToObject(context, OOJS_ARGV[0], &otherObj) || !JSSystemInfoGetSystemInfo(context, otherObj, &otherInfo))
	{
		OOJSReportBadArguments(context, @"SystemInfo", @"distanceToSystem", MIN(argc, 1U), OOJS_ARGV, nil, @"system info");
		return NO;
	}
	
	BOOL sameGalaxy = ([thisInfo galaxy] == [otherInfo galaxy]);
	if (!sameGalaxy)
	{
		OOJSReportErrorForCaller(context, @"SystemInfo", @"distanceToSystem", @"Cannot calculate distance for systems in other galaxies.");
		return NO;
	}
	
	NSPoint thisCoord = [thisInfo coordinates];
	NSPoint otherCoord = [otherInfo coordinates];
	
	OOJS_RETURN_DOUBLE(distanceBetweenPlanetPositions(thisCoord.x, thisCoord.y, otherCoord.x, otherCoord.y));
	
	OOJS_NATIVE_EXIT
}


// routeToSystem(sys : SystemInfo [, optimizedBy : String]) : Object
static JSBool SystemInfoRouteToSystem(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	OOSystemInfo			*thisInfo = nil;
	JSObject				*otherObj = NULL;
	OOSystemInfo			*otherInfo = nil;
	NSDictionary			*result = nil;
	OORouteType				routeType = OPTIMIZED_BY_JUMPS;
	
	if (!JSSystemInfoGetSystemInfo(context, OOJS_THIS, &thisInfo))  return NO;
	if (argc < 1 || !JS_ValueToObject(context, OOJS_ARGV[0], &otherObj) || !JSSystemInfoGetSystemInfo(context, otherObj, &otherInfo))
	{
		OOJSReportBadArguments(context, @"SystemInfo", @"routeToSystem", MIN(argc, 1U), OOJS_ARGV, nil, @"system info");
		return NO;
	}
	
	BOOL sameGalaxy = ([thisInfo galaxy] == [otherInfo galaxy]);
	if (!sameGalaxy)
	{
		OOJSReportErrorForCaller(context, @"SystemInfo", @"routeToSystem", @"Cannot calculate route for destinations in other galaxies.");
		return NO;
	}
	
	if (argc >= 2)
	{
		routeType = StringToRouteType(OOStringFromJSValue(context, OOJS_ARGV[1]));
	}
	
	OOJS_BEGIN_FULL_NATIVE(context)
	result = [UNIVERSE routeFromSystem:[thisInfo system] toSystem:[otherInfo system] optimizedBy:routeType];
	OOJS_END_FULL_NATIVE
	
	OOJS_RETURN_OBJECT(result);
	
	OOJS_NATIVE_EXIT
}


// filteredSystems(this : Object, predicate : Function) : Array
static JSBool SystemInfoStaticFilteredSystems(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	JSObject			*jsThis = NULL;
	
	// Get this and predicate arguments
	if (argc < 2 || !OOJSValueIsFunction(context, OOJS_ARGV[1]) || !JS_ValueToObject(context, OOJS_ARGV[0], &jsThis))
	{
		OOJSReportBadArguments(context, @"SystemInfo", @"filteredSystems", argc, OOJS_ARGV, nil, @"this and predicate function");
		return NO;
	}
	jsval predicate = OOJS_ARGV[1];
	
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSMutableArray *result = [NSMutableArray arrayWithCapacity:256];
	
	// Not OOJS_BEGIN_FULL_NATIVE() - we use JSAPI while paused.
	OOJSPauseTimeLimiter();
	
	// Iterate over systems.
	BOOL OK = result != nil;
	OOGalaxyID galaxy = [PLAYER currentGalaxyID];
	OOSystemID system;
	for (system = 0; system <= kOOMaximumSystemID; system++)
	{
		// NOTE: this deliberately bypasses the cache, since iteration is inherently unfriendly to a single-item cache.
		OOSystemInfo *info = [[[OOSystemInfo alloc] initWithGalaxy:galaxy system:system] autorelease];
		jsval args[1] = { OOJSValueFromNativeObject(context, info) };
		
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
		OOJS_SET_RVAL([result oo_jsValueInContext:context]);
	}
	else
	{
		OOJS_SET_RVAL(JSVAL_VOID);
	}

	[pool release];
	
	OOJSResumeTimeLimiter();
	return OK;
	
	OOJS_NATIVE_EXIT
}
