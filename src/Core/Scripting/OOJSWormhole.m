/*
OOJSWormhole.m

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

#import "WormholeEntity.h"
#import "OOJSWormhole.h"
#import "OOJSEntity.h"
#import "OOJSVector.h"
#import "OOJavaScriptEngine.h"
#import "OOCollectionExtractors.h"
#import "EntityOOJavaScriptExtensions.h"


static JSObject		*sWormholePrototype;

static BOOL JSWormholeGetWormholeEntity(JSContext *context, JSObject *stationObj, WormholeEntity **outEntity);


static JSBool WormholeGetProperty(JSContext *context, JSObject *this, jsid propID, jsval *value);
static JSBool WormholeSetProperty(JSContext *context, JSObject *this, jsid propID, JSBool strict, jsval *value);


static JSClass sWormholeClass =
{
	"Wormhole",
	JSCLASS_HAS_PRIVATE,
	
	JS_PropertyStub,		// addProperty
	JS_PropertyStub,		// delProperty
	WormholeGetProperty,		// getProperty
	WormholeSetProperty,		// setProperty
	JS_EnumerateStub,		// enumerate
	JS_ResolveStub,			// resolve
	JS_ConvertStub,			// convert
	OOJSObjectWrapperFinalize,// finalize
	JSCLASS_NO_OPTIONAL_MEMBERS
};


enum
{
	// Property IDs
	kWormhole_arrivalTime,
	kWormhole_destination,
	kWormhole_expiryTime,
	kWormhole_origin

};


static JSPropertySpec sWormholeProperties[] =
{
	// JS name						ID									flags
	{ "arrivalTime",	     kWormhole_arrivalTime,	      OOJS_PROP_READONLY_CB },
	{ "destination",	     kWormhole_destination,	      OOJS_PROP_READONLY_CB },
	{ "expiryTime",	     kWormhole_expiryTime,	      OOJS_PROP_READONLY_CB },
	{ "origin",	     kWormhole_origin,	      OOJS_PROP_READONLY_CB },
	{ 0 }
};


static JSFunctionSpec sWormholeMethods[] =
{
	// JS name					Function						min args
//	{ "",     WormholeDoStuff,    0 },
	{ 0 }
};


void InitOOJSWormhole(JSContext *context, JSObject *global)
{
	sWormholePrototype = JS_InitClass(context, global, JSEntityPrototype(), &sWormholeClass, OOJSUnconstructableConstruct, 0, sWormholeProperties, sWormholeMethods, NULL, NULL);
	OOJSRegisterObjectConverter(&sWormholeClass, OOJSBasicPrivateObjectConverter);
	OOJSRegisterSubclass(&sWormholeClass, JSEntityClass());
}


static BOOL JSWormholeGetWormholeEntity(JSContext *context, JSObject *wormholeObj, WormholeEntity **outEntity)
{
	OOJS_PROFILE_ENTER
	
	BOOL						result;
	Entity						*entity = nil;
	
	if (outEntity == NULL)  return NO;
	*outEntity = nil;
	
	result = OOJSEntityGetEntity(context, wormholeObj, &entity);
	if (!result)  return NO;
	
	if (![entity isKindOfClass:[WormholeEntity class]])  return NO;
	
	*outEntity = (WormholeEntity *)entity;
	return YES;
	
	OOJS_PROFILE_EXIT
}


@implementation WormholeEntity (OOJavaScriptExtensions)

- (void)getJSClass:(JSClass **)outClass andPrototype:(JSObject **)outPrototype
{
	*outClass = &sWormholeClass;
	*outPrototype = sWormholePrototype;
}


- (NSString *) oo_jsClassName
{
	return @"Wormhole";
}

- (BOOL) isVisibleToScripts
{
	return YES;
}

@end


static JSBool WormholeGetProperty(JSContext *context, JSObject *this, jsid propID, jsval *value)
{
	if (!JSID_IS_INT(propID))  return YES;
	
	OOJS_NATIVE_ENTER(context)
	
	WormholeEntity				*entity = nil;
	id result = nil;
	
	if (!JSWormholeGetWormholeEntity(context, this, &entity))  return NO;
	if (entity == nil)  { *value = JSVAL_VOID; return YES; }
	
	switch (JSID_TO_INT(propID))
	{
  case kWormhole_arrivalTime:
		return JS_NewNumberValue(context, [entity arrivalTime], value);

  case kWormhole_destination:
		return JS_NewNumberValue(context, [entity destination], value);

  case kWormhole_expiryTime:
		return JS_NewNumberValue(context, [entity expiryTime], value);
		
  case kWormhole_origin:
		return JS_NewNumberValue(context, [entity origin], value);

	default:
		OOJSReportBadPropertySelector(context, this, propID, sWormholeProperties);
		return NO;
	}

	*value = OOJSValueFromNativeObject(context, result);
	return YES;
	
	OOJS_NATIVE_EXIT
}


static JSBool WormholeSetProperty(JSContext *context, JSObject *this, jsid propID, JSBool strict, jsval *value)
{
	if (!JSID_IS_INT(propID))  return YES;
	
	OOJS_NATIVE_ENTER(context)

	WormholeEntity				*entity = nil;

	if (!JSWormholeGetWormholeEntity(context, this, &entity)) return NO;
	if (entity == nil)  return YES;
	
	switch (JSID_TO_INT(propID))
	{

		default:
			OOJSReportBadPropertySelector(context, this, propID, sWormholeProperties);
			return NO;
	}
	
	OOJSReportBadPropertyValue(context, this, propID, sWormholeProperties, *value);
	return NO;
	
	OOJS_NATIVE_EXIT
}


// *** Methods ***
