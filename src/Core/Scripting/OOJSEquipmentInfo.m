/*

OOJSEquipmentInfo.m


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

#import "OOJSEquipmentInfo.h"
#import "OOJavaScriptEngine.h"
#import "OOEquipmentType.h"
#import "OOJSPlayer.h"


static JSObject *sEquipmentInfoPrototype;


static JSBool EquipmentInfoGetProperty(JSContext *context, JSObject *this, jsid propID, jsval *value);
static JSBool EquipmentInfoSetProperty(JSContext *context, JSObject *this, jsid propID, JSBool strict, jsval *value);

static JSBool EquipmentInfoGetAllEqipment(JSContext *context, JSObject *this, jsid propID, jsval *value);


// Methods
static JSBool EquipmentInfoStaticInfoForKey(JSContext *context, uintN argc, jsval *vp);


enum
{
	// Property IDs
	kEquipmentInfo_canBeDamaged,
	kEquipmentInfo_canCarryMultiple,
	kEquipmentInfo_damageProbability,
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
	{ "canBeDamaged",					kEquipmentInfo_canBeDamaged,				OOJS_PROP_READONLY_CB },
	{ "canCarryMultiple",				kEquipmentInfo_canCarryMultiple,			OOJS_PROP_READONLY_CB },
	{ "damageProbability",					kEquipmentInfo_damageProbability,				OOJS_PROP_READONLY_CB },
	{ "description",					kEquipmentInfo_description,					OOJS_PROP_READONLY_CB },
	{ "effectiveTechLevel",				kEquipmentInfo_effectiveTechLevel,			OOJS_PROP_READWRITE_CB },
	{ "equipmentKey",					kEquipmentInfo_equipmentKey,				OOJS_PROP_READONLY_CB },
	{ "incompatibleEquipment",			kEquipmentInfo_incompatibleEquipment,		OOJS_PROP_READONLY_CB },
	{ "isAvailableToAll",				kEquipmentInfo_isAvailableToAll,			OOJS_PROP_READONLY_CB },
	{ "isAvailableToNPCs",				kEquipmentInfo_isAvailableToNPCs,			OOJS_PROP_READONLY_CB },
	{ "isAvailableToPlayer",			kEquipmentInfo_isAvailableToPlayer,			OOJS_PROP_READONLY_CB },
	{ "isExternalStore",				kEquipmentInfo_isExternalStore,				OOJS_PROP_READONLY_CB },
	{ "isPortableBetweenShips",			kEquipmentInfo_isPortableBetweenShips,		OOJS_PROP_READONLY_CB },
	{ "isVisible",						kEquipmentInfo_isVisible,					OOJS_PROP_READONLY_CB },
	{ "name",							kEquipmentInfo_name,						OOJS_PROP_READONLY_CB },
	{ "price",							kEquipmentInfo_price,						OOJS_PROP_READONLY_CB },
	{ "requiredCargoSpace",				kEquipmentInfo_requiredCargoSpace,			OOJS_PROP_READONLY_CB },
	{ "requiresAnyEquipment",			kEquipmentInfo_requiresAnyEquipment,		OOJS_PROP_READONLY_CB },
	{ "requiresCleanLegalRecord",		kEquipmentInfo_requiresCleanLegalRecord,	OOJS_PROP_READONLY_CB },
	{ "requiresEmptyPylon",				kEquipmentInfo_requiresEmptyPylon,			OOJS_PROP_READONLY_CB },
	{ "requiresEquipment",				kEquipmentInfo_requiresEquipment,			OOJS_PROP_READONLY_CB },
	{ "requiresFreePassengerBerth",		kEquipmentInfo_requiresFreePassengerBerth,	OOJS_PROP_READONLY_CB },
	{ "requiresFullFuel",				kEquipmentInfo_requiresFullFuel,			OOJS_PROP_READONLY_CB },
	{ "requiresMountedPylon",			kEquipmentInfo_requiresMountedPylon,		OOJS_PROP_READONLY_CB },
	{ "requiresNonCleanLegalRecord",	kEquipmentInfo_requiresNonCleanLegalRecord,	OOJS_PROP_READONLY_CB },
	{ "requiresNonFullFuel",			kEquipmentInfo_requiresNonFullFuel,			OOJS_PROP_READONLY_CB },
	{ "scriptInfo",						kEquipmentInfo_scriptInfo,					OOJS_PROP_READONLY_CB },
	{ "scriptName",						kEquipmentInfo_scriptName,					OOJS_PROP_READONLY_CB },
	{ "techLevel",						kEquipmentInfo_techLevel,					OOJS_PROP_READONLY_CB },
	{ 0 }
};


static JSPropertySpec sEquipmentInfoStaticProperties[] =
{
	{ "allEquipment",					0, OOJS_PROP_READONLY_CB, EquipmentInfoGetAllEqipment },
	{ 0 }
};


static JSFunctionSpec sEquipmentInfoMethods[] =
{
	// JS name					Function						min args
	{ "toString",				OOJSObjectWrapperToString,		0 },
	{ 0 }
};


static JSFunctionSpec sEquipmentInfoStaticMethods[] =
{
	// JS name					Function						min args
	{ "infoForKey",				EquipmentInfoStaticInfoForKey,	0 },
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
	OOJSObjectWrapperFinalize,	// finalize
	JSCLASS_NO_OPTIONAL_MEMBERS
};


DEFINE_JS_OBJECT_GETTER(JSEquipmentInfoGetEquipmentType, &sEquipmentInfoClass, sEquipmentInfoPrototype, OOEquipmentType);


// *** Public ***

void InitOOJSEquipmentInfo(JSContext *context, JSObject *global)
{
	sEquipmentInfoPrototype = JS_InitClass(context, global, NULL, &sEquipmentInfoClass, OOJSUnconstructableConstruct, 0, sEquipmentInfoProperties, sEquipmentInfoMethods, sEquipmentInfoStaticProperties, sEquipmentInfoStaticMethods);
	
	OOJSRegisterObjectConverter(&sEquipmentInfoClass, OOJSBasicPrivateObjectConverter);
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
	
	NSString *string = OOStringFromJSValue(context, value);
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
	id objValue = OOJSNativeObjectFromJSValue(context, value);
	
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

static JSBool EquipmentInfoGetProperty(JSContext *context, JSObject *this, jsid propID, jsval *value)
{
	if (!JSID_IS_INT(propID))  return YES;
	
	OOJS_NATIVE_ENTER(context)
	
	OOEquipmentType				*eqType = nil;
	id							result = nil;
	
	if (EXPECT_NOT(!JSEquipmentInfoGetEquipmentType(context, this, &eqType)))  return NO;
	
	switch (JSID_TO_INT(propID))
	{
		case kEquipmentInfo_equipmentKey:
			result = [eqType identifier];
			break;
			
		case kEquipmentInfo_name:
			result = [eqType name];
			break;
			
		case kEquipmentInfo_canCarryMultiple:
			*value = OOJSValueFromBOOL([eqType canCarryMultiple]);
			return YES;
			
		case kEquipmentInfo_canBeDamaged:
			*value = OOJSValueFromBOOL([eqType canBeDamaged]);
			return YES;
			
		case kEquipmentInfo_description:
			result = [eqType descriptiveText];
			break;
			
		case kEquipmentInfo_damageProbability:
			return JS_NewNumberValue(context, [eqType damageProbability], value);

		case kEquipmentInfo_techLevel:
			*value = INT_TO_JSVAL((int32_t)[eqType techLevel]);
			return YES;
			
		case kEquipmentInfo_effectiveTechLevel:
			*value = INT_TO_JSVAL((int32_t)[eqType effectiveTechLevel]);
			return YES;
			
		case kEquipmentInfo_price:
			return JS_NewNumberValue(context, [eqType price], value);
			
		case kEquipmentInfo_isAvailableToAll:
			*value = OOJSValueFromBOOL([eqType isAvailableToAll]);
			return YES;
			
		case kEquipmentInfo_isAvailableToNPCs:
			*value = OOJSValueFromBOOL([eqType isAvailableToNPCs]);
			return YES;
			
		case kEquipmentInfo_isAvailableToPlayer:
			*value = OOJSValueFromBOOL([eqType isAvailableToPlayer]);
			return YES;
			
		case kEquipmentInfo_requiresEmptyPylon:
			*value = OOJSValueFromBOOL([eqType requiresEmptyPylon]);
			return YES;
			
		case kEquipmentInfo_requiresMountedPylon:
			*value = OOJSValueFromBOOL([eqType requiresMountedPylon]);
			return YES;
			
		case kEquipmentInfo_requiresCleanLegalRecord:
			*value = OOJSValueFromBOOL([eqType requiresCleanLegalRecord]);
			return YES;
			
		case kEquipmentInfo_requiresNonCleanLegalRecord:
			*value = OOJSValueFromBOOL([eqType requiresNonCleanLegalRecord]);
			return YES;
			
		case kEquipmentInfo_requiresFreePassengerBerth:
			*value = OOJSValueFromBOOL([eqType requiresFreePassengerBerth]);
			return YES;
			
		case kEquipmentInfo_requiresFullFuel:
			*value = OOJSValueFromBOOL([eqType requiresFullFuel]);
			return YES;
			
		case kEquipmentInfo_requiresNonFullFuel:
			*value = OOJSValueFromBOOL([eqType requiresNonFullFuel]);
			return YES;
			
		case kEquipmentInfo_isExternalStore:
			*value = OOJSValueFromBOOL([eqType isMissileOrMine]);
			return YES;
			
		case kEquipmentInfo_isPortableBetweenShips:
			*value = OOJSValueFromBOOL([eqType isPortableBetweenShips]);
			return YES;
			
		case kEquipmentInfo_isVisible:
			*value = OOJSValueFromBOOL([eqType isVisible]);
			return YES;
			
		case kEquipmentInfo_requiredCargoSpace:
			*value = OOJSValueFromBOOL([eqType requiredCargoSpace]);
			return YES;
			
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
			if (result == nil)  result = [NSDictionary dictionary];	// empty rather than null
			break;
			
		case kEquipmentInfo_scriptName:
			result = [eqType scriptName];
			if (result == nil) result = @"";
			break;
			
		default:
			OOJSReportBadPropertySelector(context, this, propID, sEquipmentInfoProperties);
			return NO;
	}
	
	*value = OOJSValueFromNativeObject(context, result);
	return YES;
	
	OOJS_NATIVE_EXIT
}


static JSBool EquipmentInfoSetProperty(JSContext *context, JSObject *this, jsid propID, JSBool strict, jsval *value)
{
	if (!JSID_IS_INT(propID))  return YES;
	
	OOJS_NATIVE_ENTER(context)
	
	OOEquipmentType				*eqType = nil;
	int32						iValue;
	
	if (EXPECT_NOT(!JSEquipmentInfoGetEquipmentType(context, this, &eqType)))  return NO;
	
	switch (JSID_TO_INT(propID))
	{
		case kEquipmentInfo_effectiveTechLevel:
			if ([eqType techLevel] == kOOVariableTechLevel)
			{
				if (JSVAL_IS_NULL(*value)) 
				{
					// reset mission variable
					[OOPlayerForScripting() setMissionVariable:nil
														forKey:[@"mission_TL_FOR_" stringByAppendingString:[eqType identifier]]];
					return YES;
				}
				if (JS_ValueToInt32(context, *value, &iValue))
				{
					if (iValue < 0)  iValue = 0;
					if (15 < iValue && iValue != kOOVariableTechLevel)  iValue = 15;
					[OOPlayerForScripting() setMissionVariable:[NSString stringWithFormat:@"%u", iValue]
														forKey:[@"mission_TL_FOR_" stringByAppendingString:[eqType identifier]]];
					return YES;
				}
			}
			else
			{
				OOJSReportWarning(context, @"Cannot modify effective tech level for %@, because its base tech level is not 99.", [eqType identifier]);
				return YES;
			}
			break;
			
		default:
			OOJSReportBadPropertySelector(context, this, propID, sEquipmentInfoProperties);
			return NO;
	}
	
	OOJSReportBadPropertyValue(context, this, propID, sEquipmentInfoProperties, *value);
	return NO;
	
	OOJS_NATIVE_EXIT
}


static JSBool EquipmentInfoGetAllEqipment(JSContext *context, JSObject *this, jsid propID, jsval *value)
{
	OOJS_NATIVE_ENTER(context)
	
	*value = OOJSValueFromNativeObject(context, [OOEquipmentType allEquipmentTypes]);
	return YES;
	
	OOJS_NATIVE_EXIT
}
	

@implementation OOEquipmentType (OOJavaScriptExtensions)

- (jsval) oo_jsValueInContext:(JSContext *)context
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


- (NSString *) oo_jsClassName
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
static JSBool EquipmentInfoStaticInfoForKey(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	NSString					*key = nil;
	
	if (argc > 0)  key = OOStringFromJSValue(context, OOJS_ARGV[0]);
	if (key == nil)
	{
		OOJSReportBadArguments(context, @"EquipmentInfo", @"infoForKey", MIN(argc, 1U), OOJS_ARGV, nil, @"string");
		return NO;
	}
	
	OOJS_RETURN_OBJECT([OOEquipmentType equipmentTypeWithIdentifier:key]);
	
	OOJS_NATIVE_EXIT
}
