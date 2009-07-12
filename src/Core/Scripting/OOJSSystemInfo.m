/*

OOJSSystemInfo.m

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

#import "OOJSSystemInfo.h"
#import "OOJavaScriptEngine.h"
#import "PlayerEntityScriptMethods.h"
#import "Universe.h"


static JSObject *sSystemInfoPrototype;
static JSObject *sCachedSystemInfo;
static OOGalaxyID sCachedGalaxy;
static OOSystemID sCachedSystem;


static JSBool SystemInfoDeleteProperty(JSContext *context, JSObject *this, jsval name, jsval *value);
static JSBool SystemInfoGetProperty(JSContext *context, JSObject *this, jsval name, jsval *outValue);
static JSBool SystemInfoSetProperty(JSContext *context, JSObject *this, jsval name, jsval *value);
static void SystemInfoFinalize(JSContext *context, JSObject *this);


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
	// FIXME
	return nil;
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
	sSystemInfoPrototype = JS_InitClass(context, global, NULL, &sSystemInfoClass.base, NULL, 0, NULL, NULL, NULL, NULL);
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
	if (JSVAL_IS_STRING(name))
	{
		NSString		*key = [NSString stringWithJavaScriptValue:name inContext:context];
		OOSystemInfo	*info = JSObjectToObjectOfClass(context, this, [OOSystemInfo class]);
		id				value = nil;
		
		value = [info valueForKey:key];
		*outValue = [value javaScriptValueInContext:context];
	}
	return YES;
}


static JSBool SystemInfoSetProperty(JSContext *context, JSObject *this, jsval name, jsval *value)
{
	if (JSVAL_IS_STRING(name))
	{
		NSString		*key = [NSString stringWithJavaScriptValue:name inContext:context];
		OOSystemInfo	*info = JSObjectToObjectOfClass(context, this, [OOSystemInfo class]);
		
		[info setValue:JSValToNSString(context, *value) forKey:key];
	}
	return YES;
}
