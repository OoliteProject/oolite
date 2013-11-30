/*
OOJSFlasher.m

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

#import "OOFlasherEntity.h"
#import "OOJSFlasher.h"
#import "OOJSEntity.h"
#import "OOJSVector.h"
#import "OOJavaScriptEngine.h"
#import "EntityOOJavaScriptExtensions.h"
#import "ShipEntity.h"
#import "OOVisualEffectEntity.h"


static JSObject		*sFlasherPrototype;

static BOOL JSFlasherGetFlasherEntity(JSContext *context, JSObject *jsobj, OOFlasherEntity **outEntity);


static JSBool FlasherGetProperty(JSContext *context, JSObject *this, jsid propID, jsval *value);
static JSBool FlasherSetProperty(JSContext *context, JSObject *this, jsid propID, JSBool strict, jsval *value);

static JSBool FlasherRemove(JSContext *context, uintN argc, jsval *vp);


static JSClass sFlasherClass =
{
	"Flasher",
	JSCLASS_HAS_PRIVATE,
	
	JS_PropertyStub,		// addProperty
	JS_PropertyStub,		// delProperty
	FlasherGetProperty,		// getProperty
	FlasherSetProperty,		// setProperty
	JS_EnumerateStub,		// enumerate
	JS_ResolveStub,			// resolve
	JS_ConvertStub,			// convert
	OOJSObjectWrapperFinalize,// finalize
	JSCLASS_NO_OPTIONAL_MEMBERS
};


enum
{
	// Property IDs
	kFlasher_active,
	kFlasher_color,
	kFlasher_fraction,
	kFlasher_frequency,
	kFlasher_phase,
	kFlasher_size
};


static JSPropertySpec sFlasherProperties[] =
{
	// JS name						ID									flags
	{ "active",	   			kFlasher_active,  		OOJS_PROP_READWRITE_CB },
	{ "color",	   			kFlasher_color,	  		OOJS_PROP_READWRITE_CB },
	{ "fraction",  			kFlasher_fraction,		OOJS_PROP_READWRITE_CB },
	{ "frequency", 			kFlasher_frequency,		OOJS_PROP_READWRITE_CB },
	{ "phase",	   			kFlasher_phase,	  		OOJS_PROP_READWRITE_CB },
	{ "size",	   			kFlasher_size,	  		OOJS_PROP_READWRITE_CB },
	{ 0 }
};


static JSFunctionSpec sFlasherMethods[] =
{
	// JS name					Function						min args
	{ "remove",         FlasherRemove,    0 },

	{ 0 }
};


void InitOOJSFlasher(JSContext *context, JSObject *global)
{
	sFlasherPrototype = JS_InitClass(context, global, JSEntityPrototype(), &sFlasherClass, OOJSUnconstructableConstruct, 0, sFlasherProperties, sFlasherMethods, NULL, NULL);
	OOJSRegisterObjectConverter(&sFlasherClass, OOJSBasicPrivateObjectConverter);
	OOJSRegisterSubclass(&sFlasherClass, JSEntityClass());
}


static BOOL JSFlasherGetFlasherEntity(JSContext *context, JSObject *jsobj, OOFlasherEntity **outEntity)
{
	OOJS_PROFILE_ENTER
	
	BOOL						result;
	Entity						*entity = nil;
	
	if (outEntity == NULL)  return NO;
	*outEntity = nil;
	
	result = OOJSEntityGetEntity(context, jsobj, &entity);
	if (!result)  return NO;
	
	if (![entity isKindOfClass:[OOFlasherEntity class]])  return NO;
	
	*outEntity = (OOFlasherEntity *)entity;
	return YES;
	
	OOJS_PROFILE_EXIT
}


@implementation OOFlasherEntity (OOJavaScriptExtensions)

- (void)getJSClass:(JSClass **)outClass andPrototype:(JSObject **)outPrototype
{
	*outClass = &sFlasherClass;
	*outPrototype = sFlasherPrototype;
}


- (NSString *) oo_jsClassName
{
	return @"Flasher";
}

- (BOOL) isVisibleToScripts
{
	return YES;
}

@end


static JSBool FlasherGetProperty(JSContext *context, JSObject *this, jsid propID, jsval *value)
{
	if (!JSID_IS_INT(propID))  return YES;
	
	OOJS_NATIVE_ENTER(context)
	
	OOFlasherEntity				*entity = nil;
	id result = nil;
	
	if (!JSFlasherGetFlasherEntity(context, this, &entity))  return NO;
	if (entity == nil)  { *value = JSVAL_VOID; return YES; }
	
	switch (JSID_TO_INT(propID))
	{
		case kFlasher_active:
			*value = OOJSValueFromBOOL([entity isActive]);
			return YES;

		case kFlasher_color:
			result = [[entity color] normalizedArray];
			break;

		case kFlasher_frequency:
			return JS_NewNumberValue(context, [entity frequency], value);

		case kFlasher_fraction:
			return JS_NewNumberValue(context, [entity fraction], value);

		case kFlasher_phase:
			return JS_NewNumberValue(context, [entity phase], value);

		case kFlasher_size:
			return JS_NewNumberValue(context, [entity diameter], value);

		default:
			OOJSReportBadPropertySelector(context, this, propID, sFlasherProperties);
			return NO;
	}

	*value = OOJSValueFromNativeObject(context, result);
	return YES;
	
	OOJS_NATIVE_EXIT
}


static JSBool FlasherSetProperty(JSContext *context, JSObject *this, jsid propID, JSBool strict, jsval *value)
{
	if (!JSID_IS_INT(propID))  return YES;
	
	OOJS_NATIVE_ENTER(context)
	
	OOFlasherEntity		*entity = nil;
	jsdouble          	fValue;
	JSBool				bValue;
	OOColor				*colorForScript = nil;
	
	if (!JSFlasherGetFlasherEntity(context, this, &entity)) return NO;
	if (entity == nil)  return YES;
	
	switch (JSID_TO_INT(propID))
	{
		case kFlasher_active:
			if (JS_ValueToBoolean(context, *value, &bValue))
			{
				[entity setActive:bValue];
				return YES;
			}
			break;

		case kFlasher_color:
			colorForScript = [OOColor colorWithDescription:OOJSNativeObjectFromJSValue(context, *value)];
			if (colorForScript != nil || JSVAL_IS_NULL(*value))
			{
				[entity setColor:colorForScript];
				return YES;
			}
			break;

		case kFlasher_frequency:
			if (JS_ValueToNumber(context, *value, &fValue))
			{
				if (fValue >= 0.0)
				{
					[entity setFrequency:fValue];
					return YES;
				}
			}
			break;

		case kFlasher_fraction:
			if (JS_ValueToNumber(context, *value, &fValue))
			{
				if (fValue > 0.0 && fValue <= 1.0)
				{
					[entity setFraction:fValue];
					return YES;
				}
			}
			break;

		case kFlasher_phase:
			if (JS_ValueToNumber(context, *value, &fValue))
			{
				[entity setPhase:fValue];
				return YES;
			}
			break;

		case kFlasher_size:
			if (JS_ValueToNumber(context, *value, &fValue))
			{
				if (fValue > 0.0)
				{
					[entity setDiameter:fValue];
					return YES;
				}
			}
			break;

		default:
			OOJSReportBadPropertySelector(context, this, propID, sFlasherProperties);
			return NO;
	}
	
	OOJSReportBadPropertyValue(context, this, propID, sFlasherProperties, *value);
	return NO;
	
	OOJS_NATIVE_EXIT
}


// *** Methods ***

#define GET_THIS_FLASHER(THISENT) do { \
	if (EXPECT_NOT(!JSFlasherGetFlasherEntity(context, OOJS_THIS, &THISENT)))  return NO; /* Exception */ \
	if (OOIsStaleEntity(THISENT))  OOJS_RETURN_VOID; \
} while (0)


static JSBool FlasherRemove(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	OOFlasherEntity				*thisEnt = nil;
	GET_THIS_FLASHER(thisEnt);
	
	Entity				*parent = [thisEnt owner];
	if ([parent isShip])
	{
		[(ShipEntity *)parent removeFlasher:thisEnt];
	}
	else
	{
		[(OOVisualEffectEntity *)parent removeSubEntity:thisEnt];
	}

	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}


