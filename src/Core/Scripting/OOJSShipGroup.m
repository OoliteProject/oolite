/*

OOShipGroup.m


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

#import "OOShipGroup.h"
#import "OOJavaScriptEngine.h"
#import "OOShipGroup.h"
#import "Universe.h"


static JSObject *sShipGroupPrototype;


static JSBool ShipGroupGetProperty(OOJS_PROP_ARGS);
static JSBool ShipGroupSetProperty(OOJS_PROP_ARGS);
static JSBool ShipGroupConstruct(OOJS_NATIVE_ARGS);

// Methods
static JSBool ShipGroupAddShip(OOJS_NATIVE_ARGS);
static JSBool ShipGroupRemoveShip(OOJS_NATIVE_ARGS);
static JSBool ShipGroupContainsShip(OOJS_NATIVE_ARGS);


static JSClass sShipGroupClass =
{
	"ShipGroup",
	JSCLASS_HAS_PRIVATE,
	
	JS_PropertyStub,		// addProperty
	JS_PropertyStub,		// delProperty
	ShipGroupGetProperty,	// getProperty
	ShipGroupSetProperty,	// setProperty
	JS_EnumerateStub,		// enumerate
	JS_ResolveStub,			// resolve
	JS_ConvertStub,			// convert
	JSObjectWrapperFinalize,// finalize
	JSCLASS_NO_OPTIONAL_MEMBERS
};


enum
{
	// Property IDs
	kShipGroup_ships,			// array of ships, double, read-only
	kShipGroup_leader,			// leader, Ship, read/write
	kShipGroup_name,			// name, string, read/write
	kShipGroup_count,			// number of ships, integer, read-only
};


static JSPropertySpec sShipGroupProperties[] =
{
	// JS name					ID							flags
	{ "ships",					kShipGroup_ships,			JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "leader",					kShipGroup_leader,			JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "name",					kShipGroup_name,			JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "count",					kShipGroup_count,			JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ 0 }
};


static JSFunctionSpec sShipGroupMethods[] =
{
	// JS name					Function					min args
	{ "toString",				JSObjectWrapperToString,	0 },
	{ "addShip",				ShipGroupAddShip,			1 },
	{ "removeShip",				ShipGroupRemoveShip,		1 },
	{ "containsShip",			ShipGroupContainsShip,		1 },
	{ 0 }
};


void InitOOJSShipGroup(JSContext *context, JSObject *global)
{
	sShipGroupPrototype = JS_InitClass(context, global, NULL, &sShipGroupClass, ShipGroupConstruct, 0, sShipGroupProperties, sShipGroupMethods, NULL, NULL);
	JSRegisterObjectConverter(&sShipGroupClass, JSBasicPrivateObjectConverter);
}


static BOOL JSShipGroupGetShipGroup(JSContext *context, JSObject *entityObj, OOShipGroup **outShipGroup)
{
	id						value = nil;
	
	value = JSObjectToObjectOfClass(context, entityObj, [OOShipGroup class]);
	if (value != nil && outShipGroup != NULL)
	{
		*outShipGroup = value;
		return YES;
	}
	return NO;
}


static JSBool ShipGroupGetProperty(OOJS_PROP_ARGS)
{
	if (!OOJS_PROPID_IS_INT)  return YES;
	
	OOJS_NATIVE_ENTER(context)
	
	OOShipGroup				*group = nil;
	BOOL					OK = NO;
	id						result = nil;
	
	if (EXPECT_NOT(!JSShipGroupGetShipGroup(context, this, &group))) return NO;
	
	switch (OOJS_PROPID_INT)
	{
		case kShipGroup_ships:
			result = [group memberArray];
			if (result == nil)  result = [NSArray array];
			break;
			
		case kShipGroup_leader:
			result = [group leader];
			break;
			
		case kShipGroup_name:
			result = [group name];
			if (result == nil)  result = [NSNull null];
			break;
			
		case kShipGroup_count:
			*value = INT_TO_JSVAL([group count]);
			OK = YES;
			break;
			
		default:
			OOReportJSBadPropertySelector(context, @"ShipGroup", OOJS_PROPID_INT);
	}
	
	if (!OK && result != nil)
	{
		*value = [result javaScriptValueInContext:context];
		OK = YES;
	}
	
	return OK;
	
	OOJS_NATIVE_EXIT
}


static JSBool ShipGroupSetProperty(OOJS_PROP_ARGS)
{
	if (!OOJS_PROPID_IS_INT)  return YES;
	
	OOJS_NATIVE_ENTER(context)
	
	BOOL					OK = NO;
	OOShipGroup			*group = nil;
	ShipEntity				*shipValue = nil;
	
	if (EXPECT_NOT(!JSShipGroupGetShipGroup(context, this, &group))) return NO;
	
	switch (OOJS_PROPID_INT)
	{
		case kShipGroup_leader:
			shipValue = JSValueToObjectOfClass(context, *value, [ShipEntity class]);
			if (shipValue != nil || JSVAL_IS_NULL(*value))
			{
				[group setLeader:shipValue];
				OK = YES;
			}
			break;
			
		case kShipGroup_name:
			[group setName:[NSString stringWithJavaScriptValue:*value inContext:context]];
			OK = YES;
			break;
			
		default:
			OOReportJSBadPropertySelector(context, @"ShipGroup", OOJS_PROPID_INT);
	}
	
	return OK;
	
	OOJS_NATIVE_EXIT
}


// new ShipGroup([name : String [, leader : Ship]]) : ShipGroup
static JSBool ShipGroupConstruct(JSContext *context, JSObject *inThis, uintN argc, jsval *argv, jsval *outResult)
{
	OOJS_NATIVE_ENTER(context)
	
	NSString				*name = nil;
	ShipEntity				*leader = nil;
	OOShipGroup				*group = nil;
	
	if (argc >= 1)
	{
		if (!JSVAL_IS_STRING(argv[0]))
		{
			OOReportJSBadArguments(context, nil, @"ShipGroup()", 1, argv, @"Could not create ShipGroup", @"group name");
			return NO;
		}
		name = [NSString stringWithJavaScriptValue:argv[0] inContext:context];
	}
	
	if (argc >= 2)
	{
		leader = JSValueToObjectOfClass(context, argv[1], [ShipEntity class]);
		if (leader == nil && !JSVAL_IS_NULL(argv[1]))
		{
			OOReportJSBadArguments(context, nil, @"ShipGroup()", 1, argv + 1, @"Could not create ShipGroup", @"ship");
			return NO;
		}
	}
	
	
	group = [OOShipGroup groupWithName:name leader:leader];
	*outResult = [group javaScriptValueInContext:context];
	
	return YES;
	
	OOJS_NATIVE_EXIT
}


@implementation OOShipGroup (OOJavaScriptExtensions)

- (jsval) javaScriptValueInContext:(JSContext *)context
{
	jsval					result = JSVAL_NULL;
	
	if (_jsSelf == NULL)
	{
		_jsSelf = JS_NewObject(context, &sShipGroupClass, sShipGroupPrototype, NULL);
		if (_jsSelf != NULL)
		{
			if (!JS_SetPrivate(context, _jsSelf, [self retain]))  _jsSelf = NULL;
		}
	}
	
	if (_jsSelf != NULL)  result = OBJECT_TO_JSVAL(_jsSelf);
	
	return result;
}


- (void) oo_clearJSSelf:(JSObject *)selfVal
{
	if (_jsSelf == selfVal)  _jsSelf = NULL;
}

@end



// *** Methods ***

// addShip(ship : Ship)
static JSBool ShipGroupAddShip(OOJS_NATIVE_ARGS)
{
	OOJS_NATIVE_ENTER(context)
	
	OOShipGroup				*thisGroup = nil;
	ShipEntity				*ship = nil;
	
	if (EXPECT_NOT(!JSShipGroupGetShipGroup(context, this, &thisGroup)))  return NO;
	
	ship = JSValueToObjectOfClass(context, argv[0], [ShipEntity class]);
	if (ship == nil)
	{
		if (JSVAL_IS_NULL(argv[0]))  return YES;	// OK, do nothing for null ship.
		
		OOReportJSBadArguments(context, @"ShipGroup", @"addShip", 1, argv, nil, @"ship");
		return NO;
	}
	
	[thisGroup addShip:ship];
	return YES;
	
	OOJS_NATIVE_EXIT
}


// removeShip(ship : Ship)
static JSBool ShipGroupRemoveShip(OOJS_NATIVE_ARGS)
{
	OOJS_NATIVE_ENTER(context)
	
	OOShipGroup				*thisGroup = nil;
	ShipEntity				*ship = nil;
	
	if (EXPECT_NOT(!JSShipGroupGetShipGroup(context, this, &thisGroup)))  return NO;
	
	ship = JSValueToObjectOfClass(context, argv[0], [ShipEntity class]);
	if (ship == nil)
	{
		if (JSVAL_IS_NULL(argv[0]))  return YES;	// OK, do nothing for null ship.
		
		OOReportJSBadArguments(context, @"ShipGroup", @"removeShip", 1, argv, nil, @"ship");
		return NO;
	}
	
	[thisGroup removeShip:ship];
	return YES;
	
	OOJS_NATIVE_EXIT
}


// containsShip(ship : Ship) : Boolean
static JSBool ShipGroupContainsShip(OOJS_NATIVE_ARGS)
{
	OOJS_NATIVE_ENTER(context)
	
	OOShipGroup				*thisGroup = nil;
	ShipEntity				*ship = nil;
	
	if (EXPECT_NOT(!JSShipGroupGetShipGroup(context, this, &thisGroup)))  return NO;
	
	ship = JSValueToObjectOfClass(context, argv[0], [ShipEntity class]);
	if (ship == nil)
	{
		if (JSVAL_IS_NULL(argv[0]))
		{
			// OK, return false for null ship.
			*outResult = JSVAL_FALSE;
			return YES;
		}
		
		OOReportJSBadArguments(context, @"ShipGroup", @"containsShip", 1, argv, nil, @"ship");
		return NO;
	}
	
	*outResult = BOOLEAN_TO_JSVAL([thisGroup containsShip:ship]);
	return YES;
	
	OOJS_NATIVE_EXIT
}
