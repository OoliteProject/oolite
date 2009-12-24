/*

OOJSEquipmentInfo.m


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

#import "OOJSEquipmentInfo.h"
#import "OOJavaScriptEngine.h"
#import "OOEquipmentType.h"
#import "OOJSPlayer.h"


static JSObject *sEquipmentInfoPrototype;


static JSBool EquipmentInfoGetProperty(JSContext *context, JSObject *this, jsval name, jsval *outValue);
static JSBool EquipmentInfoSetProperty(JSContext *context, JSObject *this, jsval name, jsval *outValue);

// Methods
static JSBool EquipmentInfoStaticInfoForKey(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);


enum
{
	// Property IDs
	kEquipmentInfo_equipmentKey,
	kEquipmentInfo_name,
	kEquipmentInfo_description,
	kEquipmentInfo_techLevel,
	kEquipmentInfo_effectiveTechLevel,
	kEquipmentInfo_price,
	kEquipmentInfo_isAvailableToAll,
	kEquipmentInfo_requiresEmptyPylon,
	kEquipmentInfo_requiresMountedPylon,
	kEquipmentInfo_requiresCleanLegalRecord,
	kEquipmentInfo_requiresNonCleanLegalRecord,
	kEquipmentInfo_requiresFreePassengerBerth,
	kEquipmentInfo_requiresFullFuel,
	kEquipmentInfo_requiresNonFullFuel,
	kEquipmentInfo_isExternalStore,		// is missile or mine
	kEquipmentInfo_isPortableBetweenShips,
	kEquipmentInfo_requiredCargoSpace,
	kEquipmentInfo_requiresEquipment,
	kEquipmentInfo_requiresAnyEquipment,
	kEquipmentInfo_incompatibleEquipment
};


static JSPropertySpec sEquipmentInfoProperties[] =
{
	// JS name							ID											flags
	{ "equipmentKey",					kEquipmentInfo_equipmentKey,				JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "name",							kEquipmentInfo_name,						JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "description",					kEquipmentInfo_description,					JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "techLevel",						kEquipmentInfo_techLevel,					JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "effectiveTechLevel",				kEquipmentInfo_effectiveTechLevel,			JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "price",							kEquipmentInfo_price,						JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "isAvailableToAll",				kEquipmentInfo_isAvailableToAll,			JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "requiresEmptyPylon",				kEquipmentInfo_requiresEmptyPylon,			JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "requiresMountedPylon",			kEquipmentInfo_requiresMountedPylon,		JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "requiresCleanLegalRecord",		kEquipmentInfo_requiresCleanLegalRecord,	JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "requiresNonCleanLegalRecord",	kEquipmentInfo_requiresNonCleanLegalRecord,	JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "requiresFreePassengerBerth",		kEquipmentInfo_requiresFreePassengerBerth,	JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "requiresFullFuel",				kEquipmentInfo_requiresFullFuel,			JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "requiresNonFullFuel",			kEquipmentInfo_requiresNonFullFuel,			JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "isExternalStore",				kEquipmentInfo_isExternalStore,				JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "isPortableBetweenShips",			kEquipmentInfo_isPortableBetweenShips,		JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "requiredCargoSpace",				kEquipmentInfo_requiredCargoSpace,			JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "requiresEquipment",				kEquipmentInfo_requiresEquipment,			JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "requiresAnyEquipment",			kEquipmentInfo_requiresAnyEquipment,		JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "incompatibleEquipment",			kEquipmentInfo_incompatibleEquipment,		JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ 0 }
};


static JSFunctionSpec sEquipmentInfoStaticMethods[] =
{
	// JS name					Function						min args
	{ "toString",				JSObjectWrapperToString,		0, },
	{ "infoForKey",				EquipmentInfoStaticInfoForKey,	0, },
	{ 0 }
};


static JSExtendedClass sEquipmentInfoClass =
{
	{
		"EquipmentInfo",
		JSCLASS_HAS_PRIVATE | JSCLASS_IS_EXTENDED,

		JS_PropertyStub,			// addProperty
		JS_PropertyStub,			// delProperty
		EquipmentInfoGetProperty,	// getProperty
		EquipmentInfoSetProperty,	// setProperty
		JS_EnumerateStub,			// enumerate
		JS_ResolveStub,				// resolve
		JS_ConvertStub,				// convert
		JSObjectWrapperFinalize,	// finalize
		JSCLASS_NO_OPTIONAL_MEMBERS
	},
	JSObjectWrapperEquality,		// equality
	NULL,							// outerObject
	NULL,							// innerObject
	JSCLASS_NO_RESERVED_MEMBERS
};


// *** Public ***

void InitOOJSEquipmentInfo(JSContext *context, JSObject *global)
{
	sEquipmentInfoPrototype = JS_InitClass(context, global, NULL, &sEquipmentInfoClass.base, NULL, 0, sEquipmentInfoProperties, NULL, NULL, sEquipmentInfoStaticMethods);
	JSRegisterObjectConverter(&sEquipmentInfoClass.base, JSBasicPrivateObjectConverter);
}


// *** Implementation stuff ***

static JSBool EquipmentInfoGetProperty(JSContext *context, JSObject *this, jsval name, jsval *outValue)
{
	OOEquipmentType				*eqType = nil;
	id							result = nil;
	
	if (!JSVAL_IS_INT(name))  return YES;
	eqType = JSObjectToObjectOfClass(context, this, [OOEquipmentType class]);
	if (EXPECT_NOT(eqType == nil))  return NO;
	
	switch (JSVAL_TO_INT(name))
	{
		case kEquipmentInfo_equipmentKey:
			result = [eqType identifier];
			break;
			
		case kEquipmentInfo_name:
			result = [eqType name];
			break;
			
		case kEquipmentInfo_description:
			result = [eqType descriptiveText];
			break;
			
		case kEquipmentInfo_techLevel:
			*outValue = INT_TO_JSVAL([eqType techLevel]);
			break;
			
		case kEquipmentInfo_effectiveTechLevel:
			*outValue = INT_TO_JSVAL([eqType effectiveTechLevel]);
			break;
			
		case kEquipmentInfo_price:
			*outValue = INT_TO_JSVAL([eqType price]);
			break;
			
		case kEquipmentInfo_isAvailableToAll:
			*outValue = BOOLToJSVal([eqType isAvailableToAll]);
			break;
			
		case kEquipmentInfo_requiresEmptyPylon:
			*outValue = BOOLToJSVal([eqType requiresEmptyPylon]);
			break;
			
		case kEquipmentInfo_requiresMountedPylon:
			*outValue = BOOLToJSVal([eqType requiresMountedPylon]);
			break;
			
		case kEquipmentInfo_requiresCleanLegalRecord:
			*outValue = BOOLToJSVal([eqType requiresCleanLegalRecord]);
			break;
			
		case kEquipmentInfo_requiresNonCleanLegalRecord:
			*outValue = BOOLToJSVal([eqType requiresNonCleanLegalRecord]);
			break;
			
		case kEquipmentInfo_requiresFreePassengerBerth:
			*outValue = BOOLToJSVal([eqType requiresFreePassengerBerth]);
			break;
			
		case kEquipmentInfo_requiresFullFuel:
			*outValue = BOOLToJSVal([eqType requiresFullFuel]);
			break;
			
		case kEquipmentInfo_requiresNonFullFuel:
			*outValue = BOOLToJSVal([eqType requiresNonFullFuel]);
			break;
			
		case kEquipmentInfo_isExternalStore:
			*outValue = BOOLToJSVal([eqType isMissileOrMine]);
			break;
			
		case kEquipmentInfo_isPortableBetweenShips:
			*outValue = BOOLToJSVal([eqType isPortableBetweenShips]);
			break;
			
		case kEquipmentInfo_requiredCargoSpace:
			*outValue = BOOLToJSVal([eqType requiredCargoSpace]);
			break;
			
		case kEquipmentInfo_requiresEquipment:
			result = [[eqType requiresEquipment] allObjects];
			break;
			
		case kEquipmentInfo_requiresAnyEquipment:
			result = [[eqType requiresAnyEquipment] allObjects];
			break;
			
		case kEquipmentInfo_incompatibleEquipment:
			result = [[eqType incompatibleEquipment] allObjects];
			break;
			
		default:
			OOReportJSBadPropertySelector(context, @"EquipmentInfo", JSVAL_TO_INT(name));
			return NO;
	}
	
	if (result != nil)
	{
		*outValue = [result javaScriptValueInContext:context];
	}
	return YES;
}


static JSBool EquipmentInfoSetProperty(JSContext *context, JSObject *this, jsval name, jsval *value)
{
	BOOL						OK = NO;
	OOEquipmentType				*eqType = nil;
	int32						iValue;
	
	if (!JSVAL_IS_INT(name))  return YES;
	eqType = JSObjectToObjectOfClass(context, this, [OOEquipmentType class]);
	if (EXPECT_NOT(eqType == nil))  return NO;
	
	switch (JSVAL_TO_INT(name))
	{
		case kEquipmentInfo_effectiveTechLevel:
			if ([eqType techLevel] != kOOVariableTechLevel)  return YES;	// Only TL-99 items can be modified in this way
			if (JSVAL_IS_NULL(*value)) 
			{
				// reset mission variable
				[OOPlayerForScripting() setMissionVariable:nil
													forKey:[@"mission_TL_FOR_" stringByAppendingString:[eqType identifier]]];
				OK = YES;
				break;
			}
			if (JS_ValueToInt32(context, *value, &iValue))
			{
				if (iValue < 0)  iValue = 0;
				if (14 < iValue && iValue != kOOVariableTechLevel)  iValue = 14;
				[OOPlayerForScripting() setMissionVariable:[NSString stringWithFormat:@"%u", iValue]
													forKey:[@"mission_TL_FOR_" stringByAppendingString:[eqType identifier]]];
				OK = YES;
			}
			break;
			
		default:
			OOReportJSBadPropertySelector(context, @"EquipmentInfo", JSVAL_TO_INT(name));
	}
	
	return OK;
}
	


@implementation OOEquipmentType (OOJavaScriptExtensions)

- (jsval) javaScriptValueInContext:(JSContext *)context
{
	if (_jsSelf == NULL)
	{
		_jsSelf = JS_NewObject(context, &sEquipmentInfoClass.base, sEquipmentInfoPrototype, NULL);
		if (_jsSelf != NULL)
		{
			if (!JS_SetPrivate(context, _jsSelf, [self retain]))  _jsSelf = NULL;
		}
	}
	
	return OBJECT_TO_JSVAL(_jsSelf);
}

@end


// *** Static methods ***

// infoForKey(key : String): EquipmentInfo
static JSBool EquipmentInfoStaticInfoForKey(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	NSString					*key = nil;
	
	key = JSValToNSString(context, argv[0]);
	if (key == nil)
	{
		OOReportJSBadArguments(context, @"EquipmentInfo", @"infoForKey", argc, argv, nil, @"string");
		return NO;
	}
	
	*outResult = [[OOEquipmentType equipmentTypeWithIdentifier:key] javaScriptValueInContext:context];
	
	return YES;
}
