/*
OOJSWaypoint.m

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

#import "OOWaypointEntity.h"
#import "OOJSWaypoint.h"
#import "OOJSEntity.h"
#import "OOJSVector.h"
#import "OOJavaScriptEngine.h"
#import "OOCollectionExtractors.h"
#import "EntityOOJavaScriptExtensions.h"


static JSObject		*sWaypointPrototype;

static BOOL JSWaypointGetWaypointEntity(JSContext *context, JSObject *stationObj, OOWaypointEntity **outEntity);


static JSBool WaypointGetProperty(JSContext *context, JSObject *this, jsid propID, jsval *value);
static JSBool WaypointSetProperty(JSContext *context, JSObject *this, jsid propID, JSBool strict, jsval *value);


static JSClass sWaypointClass =
{
	"Waypoint",
	JSCLASS_HAS_PRIVATE,
	
	JS_PropertyStub,		// addProperty
	JS_PropertyStub,		// delProperty
	WaypointGetProperty,		// getProperty
	WaypointSetProperty,		// setProperty
	JS_EnumerateStub,		// enumerate
	JS_ResolveStub,			// resolve
	JS_ConvertStub,			// convert
	OOJSObjectWrapperFinalize,// finalize
	JSCLASS_NO_OPTIONAL_MEMBERS
};


enum
{
	// Property IDs
	kWaypoint_beaconCode,
	kWaypoint_beaconLabel,
	kWaypoint_size
};


static JSPropertySpec sWaypointProperties[] =
{
	// JS name						ID						flags
	{ "beaconCode",	    kWaypoint_beaconCode,	OOJS_PROP_READWRITE_CB },
	{ "beaconLabel",	kWaypoint_beaconLabel,	OOJS_PROP_READWRITE_CB },
	{ "size",	     	kWaypoint_size,	      	OOJS_PROP_READWRITE_CB },
	{ 0 }
};


static JSFunctionSpec sWaypointMethods[] =
{
	// JS name					Function						min args
//	{ "",     WaypointDoStuff,    0 },
	{ 0 }
};


void InitOOJSWaypoint(JSContext *context, JSObject *global)
{
	sWaypointPrototype = JS_InitClass(context, global, JSEntityPrototype(), &sWaypointClass, OOJSUnconstructableConstruct, 0, sWaypointProperties, sWaypointMethods, NULL, NULL);
	OOJSRegisterObjectConverter(&sWaypointClass, OOJSBasicPrivateObjectConverter);
	OOJSRegisterSubclass(&sWaypointClass, JSEntityClass());
}


static BOOL JSWaypointGetWaypointEntity(JSContext *context, JSObject *wormholeObj, OOWaypointEntity **outEntity)
{
	OOJS_PROFILE_ENTER
	
	BOOL						result;
	Entity						*entity = nil;
	
	if (outEntity == NULL)  return NO;
	*outEntity = nil;
	
	result = OOJSEntityGetEntity(context, wormholeObj, &entity);
	if (!result)  return NO;
	
	if (![entity isKindOfClass:[OOWaypointEntity class]])  return NO;
	
	*outEntity = (OOWaypointEntity *)entity;
	return YES;
	
	OOJS_PROFILE_EXIT
}


@implementation OOWaypointEntity (OOJavaScriptExtensions)

- (void)getJSClass:(JSClass **)outClass andPrototype:(JSObject **)outPrototype
{
	*outClass = &sWaypointClass;
	*outPrototype = sWaypointPrototype;
}


- (NSString *) oo_jsClassName
{
	return @"Waypoint";
}

- (BOOL) isVisibleToScripts
{
	return YES;
}

@end


static JSBool WaypointGetProperty(JSContext *context, JSObject *this, jsid propID, jsval *value)
{
	if (!JSID_IS_INT(propID))  return YES;
	
	OOJS_NATIVE_ENTER(context)
	
	OOWaypointEntity				*entity = nil;
	id result = nil;
	
	if (!JSWaypointGetWaypointEntity(context, this, &entity))  return NO;
	if (entity == nil)  { *value = JSVAL_VOID; return YES; }
	
	switch (JSID_TO_INT(propID))
	{
	case kWaypoint_beaconCode:
		result = [entity beaconCode];
		break;

	case kWaypoint_beaconLabel:
		result = [entity beaconLabel];
		break;
		
	case kWaypoint_size:
		return JS_NewNumberValue(context, [entity size], value);

	default:
		OOJSReportBadPropertySelector(context, this, propID, sWaypointProperties);
		return NO;
	}

	*value = OOJSValueFromNativeObject(context, result);
	return YES;
	
	OOJS_NATIVE_EXIT
}


static JSBool WaypointSetProperty(JSContext *context, JSObject *this, jsid propID, JSBool strict, jsval *value)
{
	if (!JSID_IS_INT(propID))  return YES;
	
	OOJS_NATIVE_ENTER(context)

	OOWaypointEntity				*entity = nil;
	jsdouble        fValue;
	NSString					*sValue = nil;

	if (!JSWaypointGetWaypointEntity(context, this, &entity)) return NO;
	if (entity == nil)  return YES;
	
	switch (JSID_TO_INT(propID))
	{
		case kWaypoint_beaconCode:
			sValue = OOStringFromJSValue(context,*value);
			if (sValue == nil || [sValue length] == 0) 
			{
				if ([entity isBeacon]) 
				{
					[UNIVERSE clearBeacon:entity];
					if ([PLAYER nextBeacon] == entity)
					{
						[PLAYER setCompassMode:COMPASS_MODE_PLANET];
					}
				}
			}
			else 
			{
				if ([entity isBeacon]) 
				{
					[entity setBeaconCode:sValue];
				}
				else // Universe needs to update beacon lists in this case only
				{
					[entity setBeaconCode:sValue];
					[UNIVERSE setNextBeacon:entity];
				}
			}
			return YES;
			break;

		case kWaypoint_beaconLabel:
			sValue = OOStringFromJSValue(context,*value);
			if (sValue != nil)
			{
				[entity setBeaconLabel:sValue];
				return YES;
			}
			break;

		case kWaypoint_size:
			if (JS_ValueToNumber(context, *value, &fValue))
			{
				if (fValue > 0.0)
				{
					[entity setSize:fValue];
					return YES;
				}
			}
			break;

		default:
			OOJSReportBadPropertySelector(context, this, propID, sWaypointProperties);
			return NO;
	}
	
	OOJSReportBadPropertyValue(context, this, propID, sWaypointProperties, *value);
	return NO;
	
	OOJS_NATIVE_EXIT
}


// *** Methods ***
