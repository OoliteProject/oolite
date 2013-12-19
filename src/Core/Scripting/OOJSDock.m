/*
OOJSDock.m

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

#import "OOJSDock.h"
#import "OOJSEntity.h"
#import "OOJSShip.h"
#import "OOJSPlayer.h"
#import "OOJavaScriptEngine.h"

#import "DockEntity.h"
#import "GameController.h"


static JSObject		*sDockPrototype;

static BOOL JSDockGetDockEntity(JSContext *context, JSObject *stationObj, DockEntity **outEntity);
static BOOL JSDockGetShipEntity(JSContext *context, JSObject *shipObj, ShipEntity **outEntity);

static JSBool DockIsQueued(JSContext *context, uintN argc, jsval *vp);


static JSBool DockGetProperty(JSContext *context, JSObject *this, jsid propID, jsval *value);
static JSBool DockSetProperty(JSContext *context, JSObject *this, jsid propID, JSBool strict, jsval *value);


static JSClass sDockClass =
{
	"Dock",
	JSCLASS_HAS_PRIVATE,
	
	JS_PropertyStub,		// addProperty
	JS_PropertyStub,		// delProperty
	DockGetProperty,		// getProperty
	DockSetProperty,		// setProperty
	JS_EnumerateStub,		// enumerate
	JS_ResolveStub,			// resolve
	JS_ConvertStub,			// convert
	OOJSObjectWrapperFinalize,// finalize
	JSCLASS_NO_OPTIONAL_MEMBERS
};


enum
{
	// Property IDs
	kDock_allowsDocking,
	kDock_disallowedDockingCollides,
	kDock_allowsLaunching,
	kDock_dockingQueueLength,
	kDock_launchingQueueLength
};


static JSPropertySpec sDockProperties[] =
{
	// JS name						ID									flags
	{ "allowsDocking",				kDock_allowsDocking,			OOJS_PROP_READWRITE_CB },
	{ "disallowedDockingCollides",				kDock_disallowedDockingCollides,			OOJS_PROP_READWRITE_CB },
	{ "allowsLaunching",				kDock_allowsLaunching,			OOJS_PROP_READWRITE_CB },
	{ "dockingQueueLength",				kDock_dockingQueueLength,			OOJS_PROP_READONLY_CB },
	{ "launchingQueueLength",				kDock_launchingQueueLength,			OOJS_PROP_READONLY_CB },
	{ 0 }
};


static JSFunctionSpec sDockMethods[] =
{
	// JS name					Function						min args
	{ "isQueued",				DockIsQueued,					1 },
	{ 0 }
};


void InitOOJSDock(JSContext *context, JSObject *global)
{
	sDockPrototype = JS_InitClass(context, global, JSShipPrototype(), &sDockClass, OOJSUnconstructableConstruct, 0, sDockProperties, sDockMethods, NULL, NULL);
	OOJSRegisterObjectConverter(&sDockClass, OOJSBasicPrivateObjectConverter);
	OOJSRegisterSubclass(&sDockClass, JSShipClass());
}


static BOOL JSDockGetDockEntity(JSContext *context, JSObject *dockObj, DockEntity **outEntity)
{
	OOJS_PROFILE_ENTER
	
	BOOL						result;
	Entity						*entity = nil;
	
	if (outEntity == NULL)  return NO;
	*outEntity = nil;
	
	result = OOJSEntityGetEntity(context, dockObj, &entity);
	if (!result)  return NO;
	
	if (![entity isKindOfClass:[DockEntity class]])  return NO;
	
	*outEntity = (DockEntity *)entity;
	return YES;
	
	OOJS_PROFILE_EXIT
}


static BOOL JSDockGetShipEntity(JSContext *context, JSObject *shipObj, ShipEntity **outEntity)
{
	OOJS_PROFILE_ENTER
	
	BOOL						result;
	Entity						*entity = nil;
	
	if (outEntity == NULL)  return NO;
	*outEntity = nil;
	
	result = OOJSEntityGetEntity(context, shipObj, &entity);
	if (!result)  return NO;
	
	if (![entity isKindOfClass:[ShipEntity class]])  return NO;
	
	*outEntity = (ShipEntity *)entity;
	return YES;
	
	OOJS_PROFILE_EXIT
}


@implementation DockEntity (OOJavaScriptExtensions)

- (void)getJSClass:(JSClass **)outClass andPrototype:(JSObject **)outPrototype
{
	*outClass = &sDockClass;
	*outPrototype = sDockPrototype;
}


- (NSString *) oo_jsClassName
{
	return @"Dock";
}

@end


static JSBool DockGetProperty(JSContext *context, JSObject *this, jsid propID, jsval *value)
{
	if (!JSID_IS_INT(propID))  return YES;
	
	OOJS_NATIVE_ENTER(context)
	
	DockEntity				*entity = nil;
	
	if (!JSDockGetDockEntity(context, this, &entity))  return NO;
	if (entity == nil)  { *value = JSVAL_VOID; return YES; }
	
	switch (JSID_TO_INT(propID))
	{
		case kDock_allowsDocking:
			*value = OOJSValueFromBOOL([entity allowsDocking]);
			return YES;

		case kDock_disallowedDockingCollides:
			*value = OOJSValueFromBOOL([entity disallowedDockingCollides]);
			return YES;

		case kDock_allowsLaunching:
			*value = OOJSValueFromBOOL([entity allowsLaunching]);
			return YES;
		
		case kDock_dockingQueueLength:
			return JS_NewNumberValue(context, [entity countOfShipsInDockingQueue], value);

		case kDock_launchingQueueLength:
			return JS_NewNumberValue(context, [entity countOfShipsInLaunchQueue], value);
			
		default:
			OOJSReportBadPropertySelector(context, this, propID, sDockProperties);
			return NO;
	}
	
	OOJS_NATIVE_EXIT
}


static JSBool DockSetProperty(JSContext *context, JSObject *this, jsid propID, JSBool strict, jsval *value)
{
	if (!JSID_IS_INT(propID))  return YES;
	
	OOJS_NATIVE_ENTER(context)
	
	DockEntity				*entity = nil;
	JSBool						bValue;
//	int32						iValue;
	
	if (!JSDockGetDockEntity(context, this, &entity)) return NO;
	if (entity == nil)  return YES;
	
	switch (JSID_TO_INT(propID))
	{
		case kDock_allowsDocking:
			if (JS_ValueToBoolean(context, *value, &bValue))
			{
				[entity setAllowsDocking:bValue];
				return YES;
			}
			break;

		case kDock_allowsLaunching:
			if (JS_ValueToBoolean(context, *value, &bValue))
			{
				[entity setAllowsLaunching:bValue];
				return YES;
			}
			break;

		case kDock_disallowedDockingCollides:
			if (JS_ValueToBoolean(context, *value, &bValue))
			{
				[entity setDisallowedDockingCollides:bValue];
				return YES;
			}
			break;

		default:
			OOJSReportBadPropertySelector(context, this, propID, sDockProperties);
			return NO;
	}
	
	OOJSReportBadPropertyValue(context, this, propID, sDockProperties, *value);
	return NO;
	
	OOJS_NATIVE_EXIT
}


// *** Methods ***

static JSBool DockIsQueued(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	BOOL result = NO;
	DockEntity *dock = nil;

	JSDockGetDockEntity(context, OOJS_THIS, &dock); 
	if (argc == 0)
	{
		OOJSReportBadArguments(context, @"Dock", @"isQueued", MIN(argc, 1U), OOJS_ARGV, nil, @"ship");
		return NO;
	}
	ShipEntity *ship = nil;
	JSDockGetShipEntity(context, JSVAL_TO_OBJECT(OOJS_ARGV[0]), &ship);
	if (ship != nil)
	{
		result = [dock shipIsInDockingQueue:ship];
	}
	
	OOJS_RETURN_BOOL(result);
	
	OOJS_NATIVE_EXIT
}

