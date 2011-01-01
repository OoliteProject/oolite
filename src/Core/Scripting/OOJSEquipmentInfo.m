/*

OOJSEquipmentInfo.m


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

#import "OOJSEquipmentInfo.h"
#import "OOJavaScriptEngine.h"
#import "OOEquipmentType.h"
#import "OOJSPlayer.h"


static JSObject *sEquipmentInfoPrototype;


static JSBool EquipmentInfoGetProperty(OOJS_PROP_ARGS);
static JSBool EquipmentInfoSetProperty(OOJS_PROP_ARGS);

static JSBool EquipmentInfoGetAllEqipment(OOJS_PROP_ARGS);


// Methods
static JSBool EquipmentInfoStaticInfoForKey(OOJS_NATIVE_ARGS);


enum
{
	// Property IDs
	kEquipmentInfo_canBeDamaged,
	kEquipmentInfo_canCarryMultiple,
	kEquipmentInfo_description,
	kEquipmentInfo_effectiveTechLevel,
	kEquipmentInfo_equipmentKey,
	kEquipmentInfo_incompatibleEquipment,
	kEquipmentInfo_isAvailableToAll,
	kEquipmentInfo_isAvailableToNPCs,
	kEquipmentInfo_isAvailableToPlayer,
	kEquipmentInfo_isExternalStore,				// is missile or mine
	kEquipmentInfo_isPortableBetweenShips,
	kEquipmentInfo_isVisible,
	kEquipmentInfo_name,
	kEquipmentInfo_price,
	kEquipmentInfo_requiredCargoSpace,
	kEquipmentInfo_requiresAnyEquipment,
	kEquipmentInfo_requiresCleanLegalRecord,
	kEquipmentInfo_requiresEmptyPylon,
	kEquipmentInfo_requiresEquipment,
	kEquipmentInfo_requiresFreePassengerBerth,
	kEquipmentInfo_requiresFullFuel,
	kEquipmentInfo_requiresMountedPylon,
	kEquipmentInfo_requiresNonCleanLegalRecord,
	kEquipmentInfo_requiresNonFullFuel,
	kEquipmentInfo_scriptInfo,					// arbitrary data for scripts, dictionary, read-only
	kEquipmentInfo_scriptName,
	kEquipmentInfo_techLevel
};


static JSPropertySpec sEquipmentInfoProperties[] =
{
	// JS name							ID											flags
	{ "canBeDamaged",					kEquipmentInfo_canBeDamaged,				JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "canCarryMultiple",				kEquipmentInfo_canCarryMultiple,			JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "description",					kEquipmentInfo_description,					JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "effectiveTechLevel",				kEquipmentInfo_effectiveTechLevel,			JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "equipmentKey",					kEquipmentInfo_equipmentKey,				JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "incompatibleEquipment",			kEquipmentInfo_incompatibleEquipment,		JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "isAvailableToAll",				kEquipmentInfo_isAvailableToAll,			JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "isAvailableToNPCs",				kEquipmentInfo_isAvailableToNPCs,			JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "isAvailableToPlayer",			kEquipmentInfo_isAvailableToPlayer,			JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "isExternalStore",				kEquipmentInfo_isExternalStore,				JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "isPortableBetweenShips",			kEquipmentInfo_isPortableBetweenShips,		JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "isVisible",						kEquipmentInfo_isVisible,					JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "name",							kEquipmentInfo_name,						JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "price",							kEquipmentInfo_price,						JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "requiredCargoSpace",				kEquipmentInfo_requiredCargoSpace,			JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "requiresAnyEquipment",			kEquipmentInfo_requiresAnyEquipment,		JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "requiresCleanLegalRecord",		kEquipmentInfo_requiresCleanLegalRecord,	JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "requiresEmptyPylon",				kEquipmentInfo_requiresEmptyPylon,			JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "requiresEquipment",				kEquipmentInfo_requiresEquipment,			JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "requiresFreePassengerBerth",		kEquipmentInfo_requiresFreePassengerBerth,	JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "requiresFullFuel",				kEquipmentInfo_requiresFullFuel,			JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "requiresMountedPylon",			kEquipmentInfo_requiresMountedPylon,		JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "requiresNonCleanLegalRecord",	kEquipmentInfo_requiresNonCleanLegalRecord,	JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "requiresNonFullFuel",			kEquipmentInfo_requiresNonFullFuel,			JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "scriptInfo",						kEquipmentInfo_scriptInfo,					JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "scriptName",						kEquipmentInfo_scriptName,					JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "techLevel",						kEquipmentInfo_techLevel,					JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ 0 }
};


static JSFunctionSpec sEquipmentInfoStaticMethods[] =
{
	// JS name					Function						min args
	{ "toString",				JSObjectWrapperToString,		0, },
	{ "infoForKey",				EquipmentInfoStaticInfoForKey,	0, },
	{ 0 }
};


static JSClass sEquipmentInfoClass =
{
	"EquipmentInfo",
	JSCLASS_HAS_PRIVATE,

	JS_PropertyStub,			// addProperty
	JS_PropertyStub,			// delProperty
	EquipmentInfoGetProperty,	// getProperty
	EquipmentInfoSetProperty,	// setProperty
	JS_EnumerateStub,			// enumerate
	JS_ResolveStub,				// resolve
	JS_ConvertStub,				// convert
	JSObjectWrapperFinalize,	// finalize
	JSCLASS_NO_OPTIONAL_MEMBERS
};


DEFINE_JS_OBJECT_GETTER(JSEquipmentInfoGetEquipmentType, &sEquipmentInfoClass, sEquipmentInfoPrototype, OOEquipmentType);


// *** Public ***

void InitOOJSEquipmentInfo(JSContext *context, JSObject *global)
{
	sEquipmentInfoPrototype = JS_InitClass(context, global, NULL, &sEquipmentInfoClass, NULL, 0, sEquipmentInfoProperties, NULL, NULL, sEquipmentInfoStaticMethods);
	JS_DefineProperty(context, sEquipmentInfoPrototype, "allEquipment", JSVAL_NULL, EquipmentInfoGetAllEqipment, NULL, JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY);
	
	JSRegisterObjectConverter(&sEquipmentInfoClass, JSBasicPrivateObjectConverter);
}


OOEquipmentType *JSValueToEquipmentType(JSContext *context, jsval value)
{
	OOJS_PROFILE_ENTER
	
	if (JSVAL_IS_OBJECT(value))
	{
		JSObject *object = JSVAL_TO_OBJECT(value);
		if (JS_InstanceOf(context, JSVAL_TO_OBJECT(value), &sEquipmentInfoClass, NULL))
		{
			return (OOEquipmentType *)JS_GetPrivate(context, object);
		}
	}
	
	NSString *string = JSValToNSString(context, value);
	if (string != nil)  return [OOEquipmentType equipmentTypeWithIdentifier:string];
	return nil;
	
	OOJS_PROFILE_EXIT
}


NSString *JSValueToEquipmentKey(JSContext *context, jsval value)
{
	return [JSValueToEquipmentType(context, value) identifier];
}


NSString *JSValueToEquipmentKeyRelaxed(JSContext *context, jsval value, BOOL *outExists)
{
	OOJS_PROFILE_ENTER
	
	NSString *result = nil;
	BOOL exists = NO;
	id objValue = JSValueToObject(context, value);
	
	if ([objValue isKindOfClass:[OOEquipmentType class]])
	{
		result = [objValue identifier];
		exists = YES;
	}
	else if ([objValue isKindOfClass:[NSString class]])
	{
		/*	To enforce deliberate backwards incompatibility, reject strings
			ending with _DAMAGED unless someone actually named an equip that
			way.
		 */
		exists = [OOEquipmentType equipmentTypeWithIdentifier:objValue] != nil;
		if (exists || ![objValue hasSuffix:@"_DAMAGED"])
		{
			result = objValue;
		}
	}
	
	if (outExists != NULL)  *outExists = exists;
	return result;
	
	OOJS_PROFILE_EXIT
}


// *** Implementation stuff ***

static JSBool EquipmentInfoGetProperty(OOJS_PROP_ARGS)
{
	if (!OOJS_PROPID_IS_INT)  return YES;
	
	OOJS_NATIVE_ENTER(context)
	
	OOEquipmentType				*eqType = nil;
	id							result = nil;
	
	if (EXPECT_NOT(!JSEquipmentInfoGetEquipmentType(context, this, &eqType)))  return NO;
	
	switch (OOJS_PROPID_INT)
	{
		case kEquipmentInfo_equipmentKey:
			result = [eqType identifier];
			break;
			
		case kEquipmentInfo_name:
			result = [eqType name];
			break;
			
		case kEquipmentInfo_canCarryMultiple:
			*value = BOOLToJSVal([eqType canCarryMultiple]);
			break;
			
		case kEquipmentInfo_canBeDamaged:
			*value = BOOLToJSVal([eqType canBeDamaged]);
			break;
			
		case kEquipmentInfo_description:
			result = [eqType descriptiveText];
			break;
			
		case kEquipmentInfo_techLevel:
			*value = INT_TO_JSVAL([eqType techLevel]);
			break;
			
		case kEquipmentInfo_effectiveTechLevel:
			*value = INT_TO_JSVAL([eqType effectiveTechLevel]);
			break;
			
		case kEquipmentInfo_price:
			*value = INT_TO_JSVAL([eqType price]);
			break;
			
		case kEquipmentInfo_isAvailableToAll:
			*value = BOOLToJSVal([eqType isAvailableToAll]);
			break;
			
		case kEquipmentInfo_isAvailableToNPCs:
			*value = BOOLToJSVal([eqType isAvailableToNPCs]);
			break;
			
		case kEquipmentInfo_isAvailableToPlayer:
			*value = BOOLToJSVal([eqType isAvailableToPlayer]);
			break;
			
		case kEquipmentInfo_requiresEmptyPylon:
			*value = BOOLToJSVal([eqType requiresEmptyPylon]);
			break;
			
		case kEquipmentInfo_requiresMountedPylon:
			*value = BOOLToJSVal([eqType requiresMountedPylon]);
			break;
			
		case kEquipmentInfo_requiresCleanLegalRecord:
			*value = BOOLToJSVal([eqType requiresCleanLegalRecord]);
			break;
			
		case kEquipmentInfo_requiresNonCleanLegalRecord:
			*value = BOOLToJSVal([eqType requiresNonCleanLegalRecord]);
			break;
			
		case kEquipmentInfo_requiresFreePassengerBerth:
			*value = BOOLToJSVal([eqType requiresFreePassengerBerth]);
			break;
			
		case kEquipmentInfo_requiresFullFuel:
			*value = BOOLToJSVal([eqType requiresFullFuel]);
			break;
			
		case kEquipmentInfo_requiresNonFullFuel:
			*value = BOOLToJSVal([eqType requiresNonFullFuel]);
			break;
			
		case kEquipmentInfo_isExternalStore:
			*value = BOOLToJSVal([eqType isMissileOrMine]);
			break;
			
		case kEquipmentInfo_isPortableBetweenShips:
			*value = BOOLToJSVal([eqType isPortableBetweenShips]);
			break;
			
		case kEquipmentInfo_isVisible:
			*value = BOOLToJSVal([eqType isVisible]);
			break;
			
		case kEquipmentInfo_requiredCargoSpace:
			*value = BOOLToJSVal([eqType requiredCargoSpace]);
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
			
		case kEquipmentInfo_scriptInfo:
			result = [eqType scriptInfo];
			if (result == nil)  result = [NSDictionary dictionary];	// empty rather than undefined
			break;
			
		case kEquipmentInfo_scriptName:
			result = [eqType scriptName];
			if (result == nil) result = @"";
			break;
			
		default:
			OOReportJSBadPropertySelector(context, @"EquipmentInfo", OOJS_PROPID_INT);
			return NO;
	}
	
	if (result != nil)
	{
		*value = [result javaScriptValueInContext:context];
	}
	return YES;
	
	OOJS_NATIVE_EXIT
}


static JSBool EquipmentInfoSetProperty(OOJS_PROP_ARGS)
{
	if (!OOJS_PROPID_IS_INT)  return YES;
	
	OOJS_NATIVE_ENTER(context)
	
	BOOL						OK = NO;
	OOEquipmentType				*eqType = nil;
	int32						iValue;
	
	if (EXPECT_NOT(!JSEquipmentInfoGetEquipmentType(context, this, &eqType)))  return NO;
	
	switch (OOJS_PROPID_INT)
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
			OOReportJSBadPropertySelector(context, @"EquipmentInfo", OOJS_PROPID_INT);
	}
	
	return OK;
	
	OOJS_NATIVE_EXIT
}


static JSBool EquipmentInfoGetAllEqipment(OOJS_PROP_ARGS)
{
	OOJS_NATIVE_ENTER(context)
	
	*value = [[OOEquipmentType allEquipmentTypes] javaScriptValueInContext:context];
	return YES;
	
	OOJS_NATIVE_EXIT
}
	

@implementation OOEquipmentType (OOJavaScriptExtensions)

- (jsval) javaScriptValueInContext:(JSContext *)context
{
	if (_jsSelf == NULL)
	{
		_jsSelf = JS_NewObject(context, &sEquipmentInfoClass, sEquipmentInfoPrototype, NULL);
		if (_jsSelf != NULL)
		{
			if (!JS_SetPrivate(context, _jsSelf, [self retain]))  _jsSelf = NULL;
		}
	}
	
	return OBJECT_TO_JSVAL(_jsSelf);
}


- (NSString *) jsClassName
{
	return @"EquipmentInfo";
}


- (void) oo_clearJSSelf:(JSObject *)selfVal
{
	if (_jsSelf == selfVal)  _jsSelf = NULL;
}

@end


// *** Static methods ***

// infoForKey(key : String): EquipmentInfo
static JSBool EquipmentInfoStaticInfoForKey(OOJS_NATIVE_ARGS)
{
	OOJS_NATIVE_ENTER(context)
	
	NSString					*key = nil;
	
	key = JSValToNSString(context, OOJS_ARG(0));
	if (key == nil)
	{
		OOReportJSBadArguments(context, @"EquipmentInfo", @"infoForKey", argc, OOJS_ARGV, nil, @"string");
		return NO;
	}
	
	OOJS_RETURN_OBJECT([OOEquipmentType equipmentTypeWithIdentifier:key]);
	
	OOJS_NATIVE_EXIT
}
