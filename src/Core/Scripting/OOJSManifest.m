/*

OOJSManifest.m

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

#import "OOJSManifest.h"
#import "OOJavaScriptEngine.h"
#import "PlayerEntity.h"
#import "PlayerEntityScriptMethods.h"
#import "PlayerEntityContracts.h"
#import "Universe.h"
#import "OOJSPlayer.h"
#import "OOJSPlayerShip.h"
#import "OOIsNumberLiteral.h"


static JSObject *sManifestPrototype;
static JSObject	*sManifestObject;



static JSBool ManifestDeleteProperty(JSContext *context, JSObject *this, jsval name, jsval *value);
static JSBool ManifestGetProperty(JSContext *context, JSObject *this, jsval name, jsval *outValue);
static JSBool ManifestSetProperty(JSContext *context, JSObject *this, jsval name, jsval *value);

static JSBool ManifestToString(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);


static JSExtendedClass sManifestClass =
{
	{
		"Manifest",
		JSCLASS_HAS_PRIVATE | JSCLASS_IS_EXTENDED,
		
		JS_PropertyStub,
		ManifestDeleteProperty,
		ManifestGetProperty,
		ManifestSetProperty,
		JS_EnumerateStub,
		JS_ResolveStub,
		JS_ConvertStub,
		JSObjectWrapperFinalize,
		JSCLASS_NO_OPTIONAL_MEMBERS
	},
	JSObjectWrapperEquality,	// equality
	NULL,						// outerObject
	NULL,						// innerObject
	JSCLASS_NO_RESERVED_MEMBERS
};


enum
{
	// Property IDs
	kManifest_food,				// commodity quantity, integer, read/write
	kManifest_textiles,			// commodity quantity, integer, read/write
	kManifest_radioactives,		// commodity quantity, integer, read/write
	kManifest_slaves,			// commodity quantity, integer, read/write
	kManifest_liquorwines,		// commodity quantity, integer, read/write
	kManifest_luxuries,			// commodity quantity, integer, read/write
	kManifest_narcotics,		// commodity quantity, integer, read/write
	kManifest_computers,		// commodity quantity, integer, read/write
	kManifest_machinery,		// commodity quantity, integer, read/write
	kManifest_alloys,			// commodity quantity, integer, read/write
	kManifest_firearms,			// commodity quantity, integer, read/write
	kManifest_furs,				// commodity quantity, integer, read/write
	kManifest_minerals,			// commodity quantity, integer, read/write
	kManifest_alienitems,		// commodity quantity, integer, read/write
	kManifest_gold,				// commodity quantity, integer, read/write
	kManifest_platinum,			// commodity quantity, integer, read/write
	kManifest_gemstones,		// commodity quantity, integer, read/write
	
// Up to kManifest_gemstones, these properties are case insensitive.
// FIXME: there must be a better way of doing this.
	
	kManifest_gem_stones,		// standardised identifier commodity quantity, integer, read/write
	kManifest_gemStones,		// js style alias to previous commodity quantity, integer, read/write
	kManifest_liquor_wines,		// standardised identifier commodity quantity, integer, read/write
	kManifest_liquorWines,		// js style alias to previous commodity quantity, integer, read/write
	kManifest_alien_items,		// standardised identifier commodity quantity, integer, read/write
	kManifest_alienItems,		// js style alias to previous commodity quantity, integer, read/write
	
	kManifest_list				// manifest list, array of commodities: name, unit, quantity, displayName - read-only	
};


static JSPropertySpec sManifestProperties[] =
{
	// JS name					ID							flags
	{ "food",				kManifest_food,				JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "textiles",			kManifest_textiles,			JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "radioactives",		kManifest_radioactives,		JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "slaves",				kManifest_slaves,			JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "liquor/wines",		kManifest_liquorwines,		JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "luxuries",			kManifest_luxuries,			JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "narcotics",			kManifest_narcotics,		JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "computers",			kManifest_computers,		JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "machinery",			kManifest_machinery,		JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "alloys",				kManifest_alloys,			JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "firearms",			kManifest_firearms,			JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "furs",				kManifest_furs,				JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "minerals",			kManifest_minerals,			JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "alien items",		kManifest_alienitems,		JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "gold",				kManifest_gold,				JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "platinum",			kManifest_platinum,			JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "gem-stones",			kManifest_gemstones,		JSPROP_PERMANENT | JSPROP_ENUMERATE },

// There are 3 possible ways of accessing two-words commodities at the moment.
// We can either use the case insensitive original names - as above,
// or use one of the case sensitive variants below.

	{ "gem_stones",			kManifest_gem_stones,		JSPROP_PERMANENT | JSPROP_ENUMERATE },	// normalised
	{ "gemStones",			kManifest_gemStones,		JSPROP_PERMANENT | JSPROP_ENUMERATE },	// camelCase
	{ "liquor_wines",		kManifest_liquor_wines,		JSPROP_PERMANENT | JSPROP_ENUMERATE },	// normalised
	{ "liquorWines",		kManifest_liquorWines,		JSPROP_PERMANENT | JSPROP_ENUMERATE },	// camelCase
	{ "alien_items",		kManifest_alien_items,		JSPROP_PERMANENT | JSPROP_ENUMERATE },	// normalised
	{ "alienItems",			kManifest_alienItems,		JSPROP_PERMANENT | JSPROP_ENUMERATE },	// camelCase
	
	{ "list",				kManifest_list,				JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ 0 }
};


static JSFunctionSpec sManifestMethods[] =
{
	// JS name					Function					min args
	{ "toString",				ManifestToString,	0 },
	{ 0 }
};


// Helper class wrapped by JS Manifest objects
@interface OOManifest: NSObject


@end


@implementation OOManifest


- (void) dealloc
{
	
	[super dealloc];
}


- (NSString *) jsClassName
{
	return @"Manifest";
}


- (jsval) javaScriptValueInContext:(JSContext *)context
{
	JSObject					*jsSelf = NULL;
	jsval						result = JSVAL_NULL;
	
	jsSelf = JS_NewObject(context, &sManifestClass.base, sManifestPrototype, NULL);
	if (jsSelf != NULL)
	{
		if (!JS_SetPrivate(context, jsSelf, [self retain]))  jsSelf = NULL;
	}
	if (jsSelf != NULL)  result = OBJECT_TO_JSVAL(jsSelf);
	
	return result;
}

@end


void InitOOJSManifest(JSContext *context, JSObject *global)
{
	sManifestPrototype = JS_InitClass(context, global, NULL, &sManifestClass.base, NULL, 0, sManifestProperties, sManifestMethods, NULL, NULL);
	JSRegisterObjectConverter(&sManifestClass.base, JSBasicPrivateObjectConverter);
	
	// Create manifest object as a property of the player.ship object.
	sManifestObject = JS_DefineObject(context, JSPlayerShipObject(), "manifest", &sManifestClass.base, sManifestPrototype, JSPROP_ENUMERATE | JSPROP_READONLY | JSPROP_PERMANENT);
	JS_SetPrivate(context, sManifestObject, NULL);
	
	// Also define manifest object as a property of the global object.
	JS_DefineObject(context, global, "manifest", &sManifestClass.base, sManifestPrototype, JSPROP_ENUMERATE | JSPROP_READONLY | JSPROP_PERMANENT);
}


static JSBool ManifestDeleteProperty(JSContext *context, JSObject *this, jsval name, jsval *value)
{
	jsval v = JSVAL_VOID;
	return ManifestSetProperty(context, this, name, &v);
}


static JSBool ManifestGetProperty(JSContext *context, JSObject *this, jsval name, jsval *outValue)
{
	BOOL						OK = NO;
	id							result = nil;
	PlayerEntity				*entity = OOPlayerForScripting();
	
	if (JSVAL_IS_STRING(name))	// Is it a case insensitive commodity identifier?
	{
		//FIXME: there must be a better way of doing this.
		const char		*str = [[[NSString stringWithJavaScriptValue:name inContext:context] lowercaseString] UTF8String];
		int				i,len = kManifest_alienitems + 1;
		
		for (i=0; i<len; i++)
		{
			if (strcmp(sManifestProperties[i].name, str) == 0) 
			{
				name = INT_TO_JSVAL(sManifestProperties[i].tinyid);
				break;
			}
		}
	}
	
	if (!JSVAL_IS_INT(name))  return YES;
	//if (EXPECT_NOT(!JSShipGetShipEntity(context, this, &entity))) return NO;	// NOTE: to be added if we get NPCs with manifests.

	switch (JSVAL_TO_INT(name))
	{
		case kManifest_list:
			result = [entity cargoListForScripting];
			OK = YES;
			break;
			
		case kManifest_food:
			*outValue = INT_TO_JSVAL([entity cargoQuantityForType:COMMODITY_FOOD]);
			OK = YES;
			break;
			
		case kManifest_textiles:
			*outValue = INT_TO_JSVAL([entity cargoQuantityForType:COMMODITY_TEXTILES]);
			OK = YES;
			break;
			
		case kManifest_radioactives:
			*outValue = INT_TO_JSVAL([entity cargoQuantityForType:COMMODITY_RADIOACTIVES]);
			OK = YES;
			break;
			
		case kManifest_slaves:
			*outValue = INT_TO_JSVAL([entity cargoQuantityForType:COMMODITY_SLAVES]);
			OK = YES;
			break;
			
		case kManifest_liquor_wines:
		case kManifest_liquorwines:
		case kManifest_liquorWines:
			*outValue = INT_TO_JSVAL([entity cargoQuantityForType:COMMODITY_LIQUOR_WINES]);
			OK = YES;
			break;
			
		case kManifest_luxuries:
			*outValue = INT_TO_JSVAL([entity cargoQuantityForType:COMMODITY_LUXURIES]);
			OK = YES;
			break;
			
		case kManifest_narcotics:
			*outValue = INT_TO_JSVAL([entity cargoQuantityForType:COMMODITY_NARCOTICS]);
			OK = YES;
			break;
			
		case kManifest_computers:
			*outValue = INT_TO_JSVAL([entity cargoQuantityForType:COMMODITY_COMPUTERS]);
			OK = YES;
			break;
			
		case kManifest_machinery:
			*outValue = INT_TO_JSVAL([entity cargoQuantityForType:COMMODITY_MACHINERY]);
			OK = YES;
			break;
			
		case kManifest_alloys:
			*outValue = INT_TO_JSVAL([entity cargoQuantityForType:COMMODITY_ALLOYS]);
			OK = YES;
			break;
			
		case kManifest_firearms:
			*outValue = INT_TO_JSVAL([entity cargoQuantityForType:COMMODITY_FIREARMS]);
			OK = YES;
			break;
			
		case kManifest_furs:
			*outValue = INT_TO_JSVAL([entity cargoQuantityForType:COMMODITY_FURS]);
			OK = YES;
			break;
			
		case kManifest_minerals:
			*outValue = INT_TO_JSVAL([entity cargoQuantityForType:COMMODITY_MINERALS]);
			OK = YES;
			break;
			
		case kManifest_gold:
			*outValue = INT_TO_JSVAL([entity cargoQuantityForType:COMMODITY_GOLD]);
			OK = YES;
			break;
			
		case kManifest_platinum:
			*outValue = INT_TO_JSVAL([entity cargoQuantityForType:COMMODITY_PLATINUM]);
			OK = YES;
			break;
			
		case kManifest_gem_stones:
		case kManifest_gemstones:
		case kManifest_gemStones:
			*outValue = INT_TO_JSVAL([entity cargoQuantityForType:COMMODITY_GEM_STONES]);
			OK = YES;
			break;
			
		case kManifest_alien_items:
		case kManifest_alienitems:
		case kManifest_alienItems:
			*outValue = INT_TO_JSVAL([entity cargoQuantityForType:COMMODITY_ALIEN_ITEMS]);
			OK = YES;
			break;
			
		default:
			OOReportJSBadPropertySelector(context, @"Manifest", JSVAL_TO_INT(name));
	}

	if (OK && result != nil)  *outValue = [result javaScriptValueInContext:context];	
	return OK;

}


static JSBool ManifestSetProperty(JSContext *context, JSObject *this, jsval name, jsval *value)
{
	BOOL						OK = NO;
	PlayerEntity				*entity = OOPlayerForScripting();
	int32						iValue;
	int							commodity;
	
	if (JSVAL_IS_STRING(name))	// Is it a case insensitive commodity identifier?
	{
		//FIXME: there must be a better way of doing this.
		const char		*str = [[[NSString stringWithJavaScriptValue:name inContext:context] lowercaseString] UTF8String];
		int				i,len = kManifest_alienitems + 1;
		
		for (i=0; i<len; i++) {
			if (strcmp(sManifestProperties[i].name, str) == 0) 
			{
				name = INT_TO_JSVAL(sManifestProperties[i].tinyid);
				break;
			}
		}
	}
	
	if (!JSVAL_IS_INT(name))  return YES;
	//if (EXPECT_NOT(!JSShipGetShipEntity(context, this, &entity))) return NO;
	
	commodity = JSVAL_TO_INT(name);
	// we can always change gold, platinum & gem-stones quantities, even with special cargo
	if ([entity specialCargo] && (commodity < kManifest_gold || commodity > kManifest_gemStones))
	{
		OOReportJSWarning(context, @"PlayerShip.manifest['foo'] - cannot modify cargo tonnage when Special Cargo is in use.");
		return YES;
	}
	
	switch (commodity)
	{
		case kManifest_food:
			if (JS_ValueToInt32(context, *value, &iValue))
			{
				if (iValue < 0)  iValue = 0;
				[entity setCargoQuantityForType:COMMODITY_FOOD amount:iValue];
				OK = YES;
			}
			break;
		
		case kManifest_textiles:
			if (JS_ValueToInt32(context, *value, &iValue))
			{
				if (iValue < 0)  iValue = 0;
				[entity setCargoQuantityForType:COMMODITY_TEXTILES amount:iValue];
				OK = YES;
			}
			break;
		
		case kManifest_radioactives:
			if (JS_ValueToInt32(context, *value, &iValue))
			{
				if (iValue < 0)  iValue = 0;
				[entity setCargoQuantityForType:COMMODITY_RADIOACTIVES amount:iValue];
				OK = YES;
			}
			break;
		
		case kManifest_slaves:
			if (JS_ValueToInt32(context, *value, &iValue))
			{
				if (iValue < 0)  iValue = 0;
				[entity setCargoQuantityForType:COMMODITY_SLAVES amount:iValue];
				OK = YES;
			}
			break;
		
		case kManifest_liquor_wines:
		case kManifest_liquorwines:
		case kManifest_liquorWines:
			if (JS_ValueToInt32(context, *value, &iValue))
			{
				if (iValue < 0)  iValue = 0;
				[entity setCargoQuantityForType:COMMODITY_LIQUOR_WINES amount:iValue];
				OK = YES;
			}
			break;
		
		case kManifest_luxuries:
			if (JS_ValueToInt32(context, *value, &iValue))
			{
				if (iValue < 0)  iValue = 0;
				[entity setCargoQuantityForType:COMMODITY_LUXURIES amount:iValue];
				OK = YES;
			}
			break;
		
		case kManifest_narcotics:
			if (JS_ValueToInt32(context, *value, &iValue))
			{
				if (iValue < 0)  iValue = 0;
				[entity setCargoQuantityForType:COMMODITY_NARCOTICS amount:iValue];
				OK = YES;
			}
			break;
		
		case kManifest_computers:
			if (JS_ValueToInt32(context, *value, &iValue))
			{
				if (iValue < 0)  iValue = 0;
				[entity setCargoQuantityForType:COMMODITY_COMPUTERS amount:iValue];
				OK = YES;
			}
			break;
		
		case kManifest_machinery:
			if (JS_ValueToInt32(context, *value, &iValue))
			{
				if (iValue < 0)  iValue = 0;
				[entity setCargoQuantityForType:COMMODITY_MACHINERY amount:iValue];
				OK = YES;
			}
			break;
		
		case kManifest_alloys:
			if (JS_ValueToInt32(context, *value, &iValue))
			{
				if (iValue < 0)  iValue = 0;
				[entity setCargoQuantityForType:COMMODITY_ALLOYS amount:iValue];
				OK = YES;
			}
			break;
		
		case kManifest_firearms:
			if (JS_ValueToInt32(context, *value, &iValue))
			{
				if (iValue < 0)  iValue = 0;
				[entity setCargoQuantityForType:COMMODITY_FIREARMS amount:iValue];
				OK = YES;
			}
			break;
		
		case kManifest_furs:
			if (JS_ValueToInt32(context, *value, &iValue))
			{
				if (iValue < 0)  iValue = 0;
				[entity setCargoQuantityForType:COMMODITY_FURS amount:iValue];
				OK = YES;
			}
			break;
		
		case kManifest_minerals:
			if (JS_ValueToInt32(context, *value, &iValue))
			{
				if (iValue < 0)  iValue = 0;
				[entity setCargoQuantityForType:COMMODITY_MINERALS amount:iValue];
				OK = YES;
			}
			break;
		
		case kManifest_gold:
			if (JS_ValueToInt32(context, *value, &iValue))
			{
				if (iValue < 0)  iValue = 0;
				[entity setCargoQuantityForType:COMMODITY_GOLD amount:iValue];
				OK = YES;
			}
			break;
		
		case kManifest_platinum:
			if (JS_ValueToInt32(context, *value, &iValue))
			{
				if (iValue < 0)  iValue = 0;
				[entity setCargoQuantityForType:COMMODITY_PLATINUM amount:iValue];
				OK = YES;
			}
			break;
		
		case kManifest_gem_stones:
		case kManifest_gemstones:
		case kManifest_gemStones:
			if (JS_ValueToInt32(context, *value, &iValue))
			{
				if (iValue < 0)  iValue = 0;
				[entity setCargoQuantityForType:COMMODITY_GEM_STONES amount:iValue];
				OK = YES;
			}
			break;
		
		case kManifest_alien_items:
		case kManifest_alienitems:
		case kManifest_alienItems:
			if (JS_ValueToInt32(context, *value, &iValue))
			{
				if (iValue < 0)  iValue = 0;
				[entity setCargoQuantityForType:COMMODITY_ALIEN_ITEMS amount:iValue];
				OK = YES;
			}
			break;
		
		default:
			OOReportJSBadPropertySelector(context, @"Manifest", JSVAL_TO_INT(name));
	}
	
	return OK;

}


// *** Methods ***

// toString() : String
static JSBool ManifestToString(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	NSString			*ret = @"[Manifest Object]";
	
	*outResult = [ret javaScriptValueInContext:context];
	return YES;
}
