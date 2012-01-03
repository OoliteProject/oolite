/*

OOJSManifest.m

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



static JSBool ManifestDeleteProperty(JSContext *context, JSObject *this, jsid propID, jsval *value);
static JSBool ManifestGetProperty(JSContext *context, JSObject *this, jsid propID, jsval *value);
static JSBool ManifestSetProperty(JSContext *context, JSObject *this, jsid propID, JSBool strict, jsval *value);


static JSClass sManifestClass =
{
	"Manifest",
	JSCLASS_HAS_PRIVATE,
	
	JS_PropertyStub,
	ManifestDeleteProperty,
	ManifestGetProperty,
	ManifestSetProperty,
	JS_EnumerateStub,
	JS_ResolveStub,
	JS_ConvertStub,
	OOJSObjectWrapperFinalize,
	JSCLASS_NO_OPTIONAL_MEMBERS
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
	{ "food",				kManifest_food,				OOJS_PROP_READWRITE_CB },
	{ "textiles",			kManifest_textiles,			OOJS_PROP_READWRITE_CB },
	{ "radioactives",		kManifest_radioactives,		OOJS_PROP_READWRITE_CB },
	{ "slaves",				kManifest_slaves,			OOJS_PROP_READWRITE_CB },
	{ "liquor/wines",		kManifest_liquorwines,		OOJS_PROP_HIDDEN_READWRITE_CB },
	{ "luxuries",			kManifest_luxuries,			OOJS_PROP_READWRITE_CB },
	{ "narcotics",			kManifest_narcotics,		OOJS_PROP_READWRITE_CB },
	{ "computers",			kManifest_computers,		OOJS_PROP_READWRITE_CB },
	{ "machinery",			kManifest_machinery,		OOJS_PROP_READWRITE_CB },
	{ "alloys",				kManifest_alloys,			OOJS_PROP_READWRITE_CB },
	{ "firearms",			kManifest_firearms,			OOJS_PROP_READWRITE_CB },
	{ "furs",				kManifest_furs,				OOJS_PROP_READWRITE_CB },
	{ "minerals",			kManifest_minerals,			OOJS_PROP_READWRITE_CB },
	{ "alien items",		kManifest_alienitems,		OOJS_PROP_HIDDEN_READWRITE_CB },
	{ "gold",				kManifest_gold,				OOJS_PROP_READWRITE_CB },
	{ "platinum",			kManifest_platinum,			OOJS_PROP_READWRITE_CB },
	{ "gem-stones",			kManifest_gemstones,		OOJS_PROP_HIDDEN_READWRITE_CB },
	
// There are 3 possible ways of accessing two-words commodities at the moment.
// We can either use the case insensitive original names - as above,
// or use one of the case sensitive variants below.
	
	{ "gem_stones",			kManifest_gem_stones,		OOJS_PROP_HIDDEN_READWRITE_CB },	// normalised
	{ "gemStones",			kManifest_gemStones,		OOJS_PROP_READWRITE_CB },			// camelCase
	{ "liquor_wines",		kManifest_liquor_wines,		OOJS_PROP_HIDDEN_READWRITE_CB },	// normalised
	{ "liquorWines",		kManifest_liquorWines,		OOJS_PROP_READWRITE_CB },			// camelCase
	{ "alien_items",		kManifest_alien_items,		OOJS_PROP_HIDDEN_READWRITE_CB },	// normalised
	{ "alienItems",			kManifest_alienItems,		OOJS_PROP_READWRITE_CB },			// camelCase
	
	{ "list",				kManifest_list,				OOJS_PROP_READONLY_CB },
	{ 0 }
};


static const unsigned kManifestCaseInsensitiveLimit = kManifest_gemstones + 1;
static const unsigned kManifestTinyIDLimit = kManifest_alienItems + 1;


static NSDictionary *sManifestNameMap;


// Helper class wrapped by JS Manifest objects
@interface OOManifest: NSObject
@end


@implementation OOManifest

- (void) dealloc
{
	[super dealloc];
}


- (NSString *) oo_jsClassName
{
	return @"Manifest";
}


- (jsval) oo_jsValueInContext:(JSContext *)context
{
	JSObject					*jsSelf = NULL;
	jsval						result = JSVAL_NULL;
	
	jsSelf = JS_NewObject(context, &sManifestClass, sManifestPrototype, NULL);
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
	sManifestPrototype = JS_InitClass(context, global, NULL, &sManifestClass, OOJSUnconstructableConstruct, 0, sManifestProperties, NULL, NULL, NULL);
	OOJSRegisterObjectConverter(&sManifestClass, OOJSBasicPrivateObjectConverter);
	
	// Create manifest object as a property of the player.ship object.
	sManifestObject = JS_DefineObject(context, JSPlayerShipObject(), "manifest", &sManifestClass, sManifestPrototype, OOJS_PROP_READONLY);
	JS_SetPrivate(context, sManifestObject, NULL);
	
	// Also define manifest object as a property of the global object.
	// Wait, what? Why? Oh well, too late now. Deprecate for EMMSTRAN? -- Ahruman 2011-02-10
	JS_DefineObject(context, global, "manifest", &sManifestClass, sManifestPrototype, OOJS_PROP_READONLY);
	
	// Create dictionary mapping commodity names to tinyids.
	NSMutableDictionary *manifestNameMap = [NSMutableDictionary dictionaryWithCapacity:kManifestCaseInsensitiveLimit];
	unsigned i;
	for (i = 0; i < kManifestCaseInsensitiveLimit; i++)
	{
		NSString *key = [NSString stringWithUTF8String:sManifestProperties[i].name];
		NSNumber *value = [NSNumber numberWithInt:sManifestProperties[i].tinyid];
		[manifestNameMap setObject:value forKey:key];
	}
	
	// EMMSTRAN: use NSMapTable. -- Ahruman 2011-02-10
	sManifestNameMap = [[NSMutableDictionary alloc] initWithDictionary:manifestNameMap];
}


static JSBool ManifestDeleteProperty(JSContext *context, JSObject *this, jsid propID, jsval *value)
{
	jsval v = JSVAL_VOID;
	return ManifestSetProperty(context, this, propID, NO, &v);
}


static BOOL GetCommodityID(JSContext *context, jsid property, unsigned *outCommodity)
{
	NSCParameterAssert(outCommodity != NULL);
	
	if (JSID_IS_INT(property))
	{
		*outCommodity = JSID_TO_INT(property);
		return *outCommodity < kManifestTinyIDLimit;
	}
	else if (JSID_IS_STRING(property))
	{
		NSString *key = [OOStringFromJSString(context, JSID_TO_STRING(property)) lowercaseString];
		NSNumber *value = [sManifestNameMap objectForKey:key];
		if (value == nil)  return NO;
		
		*outCommodity = [value intValue];
		return YES;
	}
	
	return NO;
}


static BOOL GetCommodityType(JSContext *context, unsigned tinyID, jsid propID, OOCommodityType *outType)
{
	NSCParameterAssert(outType != NULL);
	
	switch (tinyID)
	{
		case kManifest_food:
			*outType = COMMODITY_FOOD;
			return YES;
			
		case kManifest_textiles:
			*outType = COMMODITY_TEXTILES;
			return YES;
			
		case kManifest_radioactives:
			*outType = COMMODITY_RADIOACTIVES;
			return YES;
			
		case kManifest_slaves:
			*outType = COMMODITY_SLAVES;
			return YES;
			
		case kManifest_liquor_wines:
		case kManifest_liquorwines:
		case kManifest_liquorWines:
			*outType = COMMODITY_LIQUOR_WINES;
			return YES;
			
		case kManifest_luxuries:
			*outType = COMMODITY_LUXURIES;
			return YES;
			
		case kManifest_narcotics:
			*outType = COMMODITY_NARCOTICS;
			return YES;
			
		case kManifest_computers:
			*outType = COMMODITY_COMPUTERS;
			return YES;
			
		case kManifest_machinery:
			*outType = COMMODITY_MACHINERY;
			return YES;
			
		case kManifest_alloys:
			*outType = COMMODITY_ALLOYS;
			return YES;
			
		case kManifest_firearms:
			*outType = COMMODITY_FIREARMS;
			return YES;
			
		case kManifest_furs:
			*outType = COMMODITY_FURS;
			return YES;
			
		case kManifest_minerals:
			*outType = COMMODITY_MINERALS;
			return YES;
			
		case kManifest_gold:
			*outType = COMMODITY_GOLD;
			return YES;
			
		case kManifest_platinum:
			*outType = COMMODITY_PLATINUM;
			return YES;
			
		case kManifest_gem_stones:
		case kManifest_gemstones:
		case kManifest_gemStones:
			*outType = COMMODITY_GEM_STONES;
			return YES;
			
		case kManifest_alien_items:
		case kManifest_alienitems:
		case kManifest_alienItems:
			*outType = COMMODITY_ALIEN_ITEMS;
			return YES;
			
		default:
			OOJSReportWarning(context, @"BUG: unknown commodity tinyID %u for property ID %@. This is an internal error in Oolite, please report it.", tinyID, OOStringFromJSPropertyIDAndSpec(context, propID, sManifestProperties));
			return NO;
	}
}


static JSBool ManifestGetProperty(JSContext *context, JSObject *this, jsid propID, jsval *value)
{
	OOJS_NATIVE_ENTER(context)
	
	id							result = nil;
	PlayerEntity				*entity = OOPlayerForScripting();
	unsigned					commodity;
	
	if (GetCommodityID(context, propID, &commodity))
	{
		OOCommodityType type;
		if (GetCommodityType(context, commodity, propID, &type))
		{
			*value = INT_TO_JSVAL([entity cargoQuantityForType:type]);
			return YES;
		}
		else
		{
			*value = INT_TO_JSVAL(0);
			return YES;
		}
	}
	else
	{
		if (!JSID_IS_INT(propID))  return YES;
		
		switch (JSID_TO_INT(propID))
		{
			case kManifest_list:
				result = [entity cargoListForScripting];
				break;
				
			default:
				OOJSReportBadPropertySelector(context, this, propID, sManifestProperties);
				return NO;
		}
	}
	
	*value = OOJSValueFromNativeObject(context, result);
	return YES;
	
	OOJS_NATIVE_EXIT
}


static JSBool ManifestSetProperty(JSContext *context, JSObject *this, jsid propID, JSBool strict, jsval *value)
{
	OOJS_NATIVE_ENTER(context)
	
	PlayerEntity				*entity = OOPlayerForScripting();
	int32						iValue;
	unsigned					commodity;
	
	if (!GetCommodityID(context, propID, &commodity))  return YES;
	
	// we can always change gold, platinum & gem-stones quantities, even with special cargo
	if ((commodity < kManifest_gold || commodity > kManifest_gemStones) && [entity specialCargo])
	{
		OOJSReportWarning(context, @"PlayerShip.manifest['foo'] - cannot modify cargo tonnage when Special Cargo is in use.");
		return YES;
	}
	
	OOCommodityType type;
	if (GetCommodityType(context, commodity, propID, &type))
	{
		if (JS_ValueToInt32(context, *value, &iValue))
		{
			if (iValue < 0)  iValue = 0;
			[entity setCargoQuantityForType:type amount:iValue];
		}
		else
		{
			OOJSReportBadPropertyValue(context, this, propID, sManifestProperties, *value);
		}
	}
	return YES;
	
	OOJS_NATIVE_EXIT
}
