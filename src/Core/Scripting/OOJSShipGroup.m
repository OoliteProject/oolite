/*

OOShipGroup.m


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

#import "OOShipGroup.h"
#import "OOJavaScriptEngine.h"
#import "OOShipGroup.h"
#import "Universe.h"


static JSObject *sShipGroupPrototype;


static JSBool ShipGroupGetProperty(JSContext *context, JSObject *this, jsid propID, jsval *value);
static JSBool ShipGroupSetProperty(JSContext *context, JSObject *this, jsid propID, JSBool strict, jsval *value);
static JSBool ShipGroupConstruct(JSContext *context, uintN argc, jsval *vp);

// Methods
static JSBool ShipGroupAddShip(JSContext *context, uintN argc, jsval *vp);
static JSBool ShipGroupRemoveShip(JSContext *context, uintN argc, jsval *vp);
static JSBool ShipGroupContainsShip(JSContext *context, uintN argc, jsval *vp);


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
	OOJSObjectWrapperFinalize,// finalize
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
	{ "count",					kShipGroup_count,			OOJS_PROP_READONLY_CB },
	{ "leader",					kShipGroup_leader,			OOJS_PROP_READWRITE_CB },
	{ "name",					kShipGroup_name,			OOJS_PROP_READWRITE_CB },
	{ "ships",					kShipGroup_ships,			OOJS_PROP_READONLY_CB },
	{ 0 }
};


static JSFunctionSpec sShipGroupMethods[] =
{
	// JS name					Function					min args
	{ "toString",				OOJSObjectWrapperToString,	0 },
	{ "addShip",				ShipGroupAddShip,			1 },
	{ "containsShip",			ShipGroupContainsShip,		1 },
	{ "removeShip",				ShipGroupRemoveShip,		1 },
	{ 0 }
};


DEFINE_JS_OBJECT_GETTER(JSShipGroupGetShipGroup, &sShipGroupClass, sShipGroupPrototype, OOShipGroup);


void InitOOJSShipGroup(JSContext *context, JSObject *global)
{
	sShipGroupPrototype = JS_InitClass(context, global, NULL, &sShipGroupClass, ShipGroupConstruct, 0, sShipGroupProperties, sShipGroupMethods, NULL, NULL);
	OOJSRegisterObjectConverter(&sShipGroupClass, OOJSBasicPrivateObjectConverter);
}


static JSBool ShipGroupGetProperty(JSContext *context, JSObject *this, jsid propID, jsval *value)
{
	if (!JSID_IS_INT(propID))  return YES;
	
	OOJS_NATIVE_ENTER(context)
	
	OOShipGroup				*group = nil;
	id						result = nil;
	
	if (EXPECT_NOT(!JSShipGroupGetShipGroup(context, this, &group)))  return NO;
	
	switch (JSID_TO_INT(propID))
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
			return YES;
			
		default:
			OOJSReportBadPropertySelector(context, this, propID, sShipGroupProperties);
			return NO;
	}
	
	*value = OOJSValueFromNativeObject(context, result);
	return YES;
	
	OOJS_NATIVE_EXIT
}


static JSBool ShipGroupSetProperty(JSContext *context, JSObject *this, jsid propID, JSBool strict, jsval *value)
{
	if (!JSID_IS_INT(propID))  return YES;
	
	OOJS_NATIVE_ENTER(context)
	
	OOShipGroup				*group = nil;
	ShipEntity				*shipValue = nil;
	
	if (EXPECT_NOT(!JSShipGroupGetShipGroup(context, this, &group)))  return NO;
	
	switch (JSID_TO_INT(propID))
	{
		case kShipGroup_leader:
			shipValue = OOJSNativeObjectOfClassFromJSValue(context, *value, [ShipEntity class]);
			if (shipValue != nil || JSVAL_IS_NULL(*value))
			{
				[group setLeader:shipValue];
				return YES;
			}
			break;
			
		case kShipGroup_name:
			[group setName:OOStringFromJSValueEvenIfNull(context, *value)];
			return YES;
			break;
			
		default:
			OOJSReportBadPropertySelector(context, this, propID, sShipGroupProperties);
			return NO;
	}
	
	OOJSReportBadPropertyValue(context, this, propID, sShipGroupProperties, *value);
	return NO;
	
	OOJS_NATIVE_EXIT
}


// new ShipGroup([name : String [, leader : Ship]]) : ShipGroup
static JSBool ShipGroupConstruct(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	if (EXPECT_NOT(!JS_IsConstructing(context, vp)))
	{
		OOJSReportError(context, @"ShipGroup() cannot be called as a function, it must be used as a constructor (as in new ShipGroup(...)).");
		return NO;
	}
	
	NSString				*name = nil;
	ShipEntity				*leader = nil;
	
	if (argc >= 1)
	{
		if (!JSVAL_IS_STRING(OOJS_ARGV[0]))
		{
			OOJSReportBadArguments(context, nil, @"ShipGroup()", 1, OOJS_ARGV, @"Could not create ShipGroup", @"group name");
			return NO;
		}
		name = OOStringFromJSValue(context, OOJS_ARGV[0]);
	}
	
	if (argc >= 2)
	{
		leader = OOJSNativeObjectOfClassFromJSValue(context, OOJS_ARGV[1], [ShipEntity class]);
		if (leader == nil && !JSVAL_IS_NULL(OOJS_ARGV[1]))
		{
			OOJSReportBadArguments(context, nil, @"ShipGroup()", 1, OOJS_ARGV + 1, @"Could not create ShipGroup", @"ship");
			return NO;
		}
	}
	
	OOJS_RETURN_OBJECT([OOShipGroup groupWithName:name leader:leader]);
	
	OOJS_NATIVE_EXIT
}


@implementation OOShipGroup (OOJavaScriptExtensions)

- (jsval) oo_jsValueInContext:(JSContext *)context
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
static JSBool ShipGroupAddShip(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	OOShipGroup				*thisGroup = nil;
	ShipEntity				*ship = nil;
	BOOL					OK = YES;
	
	if (EXPECT_NOT(!JSShipGroupGetShipGroup(context, OOJS_THIS, &thisGroup)))  return NO;
	
	if (argc > 0)  ship = OOJSNativeObjectOfClassFromJSValue(context, OOJS_ARGV[0], [ShipEntity class]);
	if (ship == nil)
	{
		if (argc > 0 && JSVAL_IS_NULL(OOJS_ARGV[0]))  OOJS_RETURN_VOID;	// OK, do nothing for null ship.
		
		OOJSReportBadArguments(context, @"ShipGroup", @"addShip", MIN(argc, 1U), OOJS_ARGV, nil, @"ship");
		return NO;
	}
	
	if ([thisGroup containsShip:ship])
	{
		// nothing to do...
		OOJS_RETURN_VOID;
	}
	else
	{
		ShipEntity				*thisGroupLeader = [thisGroup leader];
		
		if ([thisGroupLeader escortGroup] == thisGroup) // escort group!
		{
			if ([thisGroup count] > 1) // already with some escorts
			{
				OOShipGroup			*thatGroup = [ship group];
				if ([thatGroup count] > 1 && [[thatGroup leader] escortGroup] == thatGroup)	// new escort already escorting!
				{
					OOJSReportWarningForCaller(context, @"ShipGroup", @"addShip", @"Ship %@ cannot be assigned to two escort groups, ignoring.", ship);
					OK = NO;
				}
				else
				{
					OK = [thisGroupLeader acceptAsEscort:ship];
				}
			}
			else // [thisGroup count] == 1, default unescorted ship?
			{
				if ([thisGroupLeader escortGroup] == [thisGroupLeader group])
				{
					// Default unescorted, unescortable, ship. Create new group and use that instead.
					[thisGroupLeader setGroup:[[OOShipGroup alloc] initWithName:@"ship group"]];
					thisGroup = [thisGroupLeader group];
				}
				else
				{
					// Unescorted ship with custom group. See if it accepts escorts.
					OK = [thisGroupLeader acceptAsEscort:ship];
				}
			}
		}
		if (OK)
		{
			OOJS_RETURN_BOOL([thisGroup addShip:ship]);	// if ship is there already, noop & YES
		}
		else  OOJS_RETURN_BOOL(NO);
	}
	
	OOJS_NATIVE_EXIT
}


// removeShip(ship : Ship)
static JSBool ShipGroupRemoveShip(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	OOShipGroup				*thisGroup = nil;
	ShipEntity				*ship = nil;
	
	if (EXPECT_NOT(!JSShipGroupGetShipGroup(context, OOJS_THIS, &thisGroup)))  return NO;
	
	if (argc > 0)  ship = OOJSNativeObjectOfClassFromJSValue(context, OOJS_ARGV[0], [ShipEntity class]);
	if (ship == nil)
	{
		if (argc > 0 && JSVAL_IS_NULL(OOJS_ARGV[0]))  OOJS_RETURN_VOID;	// OK, do nothing for null ship.
		
		OOJSReportBadArguments(context, @"ShipGroup", @"removeShip", MIN(argc, 1U), OOJS_ARGV, nil, @"ship");
		return NO;
	}
	
	OOJS_RETURN_BOOL([thisGroup removeShip:ship]);
	
	OOJS_NATIVE_EXIT
}


// containsShip(ship : Ship) : Boolean
static JSBool ShipGroupContainsShip(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	OOShipGroup				*thisGroup = nil;
	ShipEntity				*ship = nil;
	
	if (EXPECT_NOT(!JSShipGroupGetShipGroup(context, OOJS_THIS, &thisGroup)))  return NO;
	
	if (argc > 0)  ship = OOJSNativeObjectOfClassFromJSValue(context, OOJS_ARGV[0], [ShipEntity class]);
	if (ship == nil)
	{
		if (argc > 0 && JSVAL_IS_NULL(OOJS_ARGV[0]))  OOJS_RETURN_BOOL(NO); // OK, return false for null ship.
		
		OOJSReportBadArguments(context, @"ShipGroup", @"containsShip", MIN(argc, 1U), OOJS_ARGV, nil, @"ship");
		return NO;
	}
	
	OOJS_RETURN_BOOL([thisGroup containsShip:ship]);
	
	OOJS_NATIVE_EXIT
}
