/*
OOJSExhaustPlume.m

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

#import "OOExhaustPlumeEntity.h"
#import "OOJSExhaustPlume.h"
#import "OOJSEntity.h"
#import "OOJSVector.h"
#import "OOJavaScriptEngine.h"
#import "EntityOOJavaScriptExtensions.h"
#import "ShipEntity.h"


static JSObject		*sExhaustPlumePrototype;

static BOOL JSExhaustPlumeGetExhaustPlumeEntity(JSContext *context, JSObject *jsobj, OOExhaustPlumeEntity **outEntity);


static JSBool ExhaustPlumeGetProperty(JSContext *context, JSObject *this, jsid propID, jsval *value);
static JSBool ExhaustPlumeSetProperty(JSContext *context, JSObject *this, jsid propID, JSBool strict, jsval *value);

static JSBool ExhaustPlumeRemove(JSContext *context, uintN argc, jsval *vp);


static JSClass sExhaustPlumeClass =
{
	"ExhaustPlume",
	JSCLASS_HAS_PRIVATE,
	
	JS_PropertyStub,		// addProperty
	JS_PropertyStub,		// delProperty
	ExhaustPlumeGetProperty,		// getProperty
	ExhaustPlumeSetProperty,		// setProperty
	JS_EnumerateStub,		// enumerate
	JS_ResolveStub,			// resolve
	JS_ConvertStub,			// convert
	OOJSObjectWrapperFinalize,// finalize
	JSCLASS_NO_OPTIONAL_MEMBERS
};


enum
{
	// Property IDs
	kExhaustPlume_size
};


static JSPropertySpec sExhaustPlumeProperties[] =
{
	// JS name						ID									flags
	{ "size",	   			kExhaustPlume_size,	  		OOJS_PROP_READWRITE_CB },
	{ 0 }
};


static JSFunctionSpec sExhaustPlumeMethods[] =
{
	// JS name					Function						min args
	{ "remove",         ExhaustPlumeRemove,    0 },

	{ 0 }
};


void InitOOJSExhaustPlume(JSContext *context, JSObject *global)
{
	sExhaustPlumePrototype = JS_InitClass(context, global, JSEntityPrototype(), &sExhaustPlumeClass, OOJSUnconstructableConstruct, 0, sExhaustPlumeProperties, sExhaustPlumeMethods, NULL, NULL);
	OOJSRegisterObjectConverter(&sExhaustPlumeClass, OOJSBasicPrivateObjectConverter);
	OOJSRegisterSubclass(&sExhaustPlumeClass, JSEntityClass());
}


static BOOL JSExhaustPlumeGetExhaustPlumeEntity(JSContext *context, JSObject *jsobj, OOExhaustPlumeEntity **outEntity)
{
	OOJS_PROFILE_ENTER
	
	BOOL						result;
	Entity						*entity = nil;
	
	if (outEntity == NULL)  return NO;
	*outEntity = nil;
	
	result = OOJSEntityGetEntity(context, jsobj, &entity);
	if (!result)  return NO;
	
	if (![entity isKindOfClass:[OOExhaustPlumeEntity class]])  return NO;
	
	*outEntity = (OOExhaustPlumeEntity *)entity;
	return YES;
	
	OOJS_PROFILE_EXIT
}


@implementation OOExhaustPlumeEntity (OOJavaScriptExtensions)

- (void)getJSClass:(JSClass **)outClass andPrototype:(JSObject **)outPrototype
{
	*outClass = &sExhaustPlumeClass;
	*outPrototype = sExhaustPlumePrototype;
}


- (NSString *) oo_jsClassName
{
	return @"ExhaustPlume";
}

- (BOOL) isVisibleToScripts
{
	return YES;
}

@end


static JSBool ExhaustPlumeGetProperty(JSContext *context, JSObject *this, jsid propID, jsval *value)
{
	if (!JSID_IS_INT(propID))  return YES;
	
	OOJS_NATIVE_ENTER(context)
	
	OOExhaustPlumeEntity				*entity = nil;
	id result = nil;
	
	if (!JSExhaustPlumeGetExhaustPlumeEntity(context, this, &entity))  return NO;
	if (entity == nil)  { *value = JSVAL_VOID; return YES; }
	
	switch (JSID_TO_INT(propID))
	{
		case kExhaustPlume_size:
			return VectorToJSValue(context, [entity scale], value);

		default:
			OOJSReportBadPropertySelector(context, this, propID, sExhaustPlumeProperties);
			return NO;
	}

	*value = OOJSValueFromNativeObject(context, result);
	return YES;
	
	OOJS_NATIVE_EXIT
}


static JSBool ExhaustPlumeSetProperty(JSContext *context, JSObject *this, jsid propID, JSBool strict, jsval *value)
{
	if (!JSID_IS_INT(propID))  return YES;
	
	OOJS_NATIVE_ENTER(context)
	
	OOExhaustPlumeEntity				*entity = nil;
	Vector          vValue;
	
	if (!JSExhaustPlumeGetExhaustPlumeEntity(context, this, &entity)) return NO;
	if (entity == nil)  return YES;
	
	switch (JSID_TO_INT(propID))
	{
		case kExhaustPlume_size:
			if (JSValueToVector(context, *value, &vValue))
			{
				[entity setScale:vValue];
				return YES;
			}
			break;

		default:
			OOJSReportBadPropertySelector(context, this, propID, sExhaustPlumeProperties);
			return NO;
	}
	
	OOJSReportBadPropertyValue(context, this, propID, sExhaustPlumeProperties, *value);
	return NO;
	
	OOJS_NATIVE_EXIT
}


// *** Methods ***

#define GET_THIS_EXHAUSTPLUME(THISENT) do { \
	if (EXPECT_NOT(!JSExhaustPlumeGetExhaustPlumeEntity(context, OOJS_THIS, &THISENT)))  return NO; /* Exception */ \
	if (OOIsStaleEntity(THISENT))  OOJS_RETURN_VOID; \
} while (0)


static JSBool ExhaustPlumeRemove(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	OOExhaustPlumeEntity				*thisEnt = nil;
	GET_THIS_EXHAUSTPLUME(thisEnt);
	
	ShipEntity				*parent = [thisEnt owner];
	[parent removeExhaust:thisEnt];

	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}


