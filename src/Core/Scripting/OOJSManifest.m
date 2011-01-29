/*

OOJSManifest.m

Oolite
Copyright (C) 2004-2011 Giles C Williams and contributors

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



static JSBool ManifestDeleteProperty(OOJS_PROP_ARGS);
static JSBool ManifestGetProperty(OOJS_PROP_ARGS);
static JSBool ManifestSetProperty(OOJS_PROP_ARGS);


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
	{ "liquor/wines",		kManifest_liquorwines,		OOJS_PROP_READWRITE_CB },
	{ "luxuries",			kManifest_luxuries,			OOJS_PROP_READWRITE_CB },
	{ "narcotics",			kManifest_narcotics,		OOJS_PROP_READWRITE_CB },
	{ "computers",			kManifest_computers,		OOJS_PROP_READWRITE_CB },
	{ "machinery",			kManifest_machinery,		OOJS_PROP_READWRITE_CB },
	{ "alloys",				kManifest_alloys,			OOJS_PROP_READWRITE_CB },
	{ "firearms",			kManifest_firearms,			OOJS_PROP_READWRITE_CB },
	{ "furs",				kManifest_furs,				OOJS_PROP_READWRITE_CB },
	{ "minerals",			kManifest_minerals,			OOJS_PROP_READWRITE_CB },
	{ "alien items",		kManifest_alienitems,		OOJS_PROP_READWRITE_CB },
	{ "gold",				kManifest_gold,				OOJS_PROP_READWRITE_CB },
	{ "platinum",			kManifest_platinum,			OOJS_PROP_READWRITE_CB },
	{ "gem-stones",			kManifest_gemstones,		OOJS_PROP_READWRITE_CB },

// There are 3 possible ways of accessing two-words commodities at the moment.
// We can either use the case insensitive original names - as above,
// or use one of the case sensitive variants below.

	{ "gem_stones",			kManifest_gem_stones,		OOJS_PROP_READWRITE_CB },	// normalised
	{ "gemStones",			kManifest_gemStones,		OOJS_PROP_READWRITE_CB },	// camelCase
	{ "liquor_wines",		kManifest_liquor_wines,		OOJS_PROP_READWRITE_CB },	// normalised
	{ "liquorWines",		kManifest_liquorWines,		OOJS_PROP_READWRITE_CB },	// camelCase
	{ "alien_items",		kManifest_alien_items,		OOJS_PROP_READWRITE_CB },	// normalised
	{ "alienItems",			kManifest_alienItems,		OOJS_PROP_READWRITE_CB },	// camelCase
	
	{ "list",				kManifest_list,				OOJS_PROP_READONLY_CB },
	{ 0 }
};


static const unsigned kManifestCaseInsensitiveLimit = kManifest_gemstones + 1;


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
	
	sManifestNameMap = [[NSMutableDictionary alloc] initWithDictionary:manifestNameMap];
}


static JSBool ManifestDeleteProperty(OOJS_PROP_ARGS)
{
	jsval v = JSVAL_VOID;
	return ManifestSetProperty(context, this, propID, &v);
}


#if OO_NEW_JS
typedef jsid PropertyID;
#define PROP_IS_INT JSID_IS_INT
#define PROP_TO_INT JSID_TO_INT
#define PROP_IS_STRING JSID_IS_STRING
#define PROP_TO_STRING JSID_TO_STRING
#else
typedef jsval PropertyID;
#define PROP_IS_INT JSVAL_IS_INT
#define PROP_TO_INT JSVAL_TO_INT
#define PROP_IS_STRING JSVAL_IS_STRING
#define PROP_TO_STRING JSVAL_TO_STRING
#endif

static BOOL GetCommodityID(JSContext *context, PropertyID property, unsigned *outCommodity)
{
	NSCParameterAssert(outCommodity != NULL);
	
	if (PROP_IS_INT(property))
	{
		*outCommodity = PROP_TO_INT(property);
		return *outCommodity < kManifestCaseInsensitiveLimit;
	}
	else if (PROP_IS_STRING(property))
	{
		NSString *key = [OOStringFromJSString(context, PROP_TO_STRING(property)) lowercaseString];
		NSNumber *value = [sManifestNameMap objectForKey:key];
		if (value == nil)  return NO;
		
		*outCommodity = [value intValue];
		return YES;
	}
	
	return NO;
}


static JSBool ManifestGetProperty(OOJS_PROP_ARGS)
{
	OOJS_NATIVE_ENTER(context)
	
	BOOL						OK = NO;
	id							result = nil;
	PlayerEntity				*entity = OOPlayerForScripting();
	unsigned					commodity;
	
	if (GetCommodityID(context, propID, &commodity))
	{
		switch (commodity)
		{
				
			case kManifest_food:
				*value = INT_TO_JSVAL([entity cargoQuantityForType:COMMODITY_FOOD]);
				OK = YES;
				break;
				
			case kManifest_textiles:
				*value = INT_TO_JSVAL([entity cargoQuantityForType:COMMODITY_TEXTILES]);
				OK = YES;
				break;
				
			case kManifest_radioactives:
				*value = INT_TO_JSVAL([entity cargoQuantityForType:COMMODITY_RADIOACTIVES]);
				OK = YES;
				break;
				
			case kManifest_slaves:
				*value = INT_TO_JSVAL([entity cargoQuantityForType:COMMODITY_SLAVES]);
				OK = YES;
				break;
				
			case kManifest_liquor_wines:
			case kManifest_liquorwines:
			case kManifest_liquorWines:
				*value = INT_TO_JSVAL([entity cargoQuantityForType:COMMODITY_LIQUOR_WINES]);
				OK = YES;
				break;
				
			case kManifest_luxuries:
				*value = INT_TO_JSVAL([entity cargoQuantityForType:COMMODITY_LUXURIES]);
				OK = YES;
				break;
				
			case kManifest_narcotics:
				*value = INT_TO_JSVAL([entity cargoQuantityForType:COMMODITY_NARCOTICS]);
				OK = YES;
				break;
				
			case kManifest_computers:
				*value = INT_TO_JSVAL([entity cargoQuantityForType:COMMODITY_COMPUTERS]);
				OK = YES;
				break;
				
			case kManifest_machinery:
				*value = INT_TO_JSVAL([entity cargoQuantityForType:COMMODITY_MACHINERY]);
				OK = YES;
				break;
				
			case kManifest_alloys:
				*value = INT_TO_JSVAL([entity cargoQuantityForType:COMMODITY_ALLOYS]);
				OK = YES;
				break;
				
			case kManifest_firearms:
				*value = INT_TO_JSVAL([entity cargoQuantityForType:COMMODITY_FIREARMS]);
				OK = YES;
				break;
				
			case kManifest_furs:
				*value = INT_TO_JSVAL([entity cargoQuantityForType:COMMODITY_FURS]);
				OK = YES;
				break;
				
			case kManifest_minerals:
				*value = INT_TO_JSVAL([entity cargoQuantityForType:COMMODITY_MINERALS]);
				OK = YES;
				break;
				
			case kManifest_gold:
				*value = INT_TO_JSVAL([entity cargoQuantityForType:COMMODITY_GOLD]);
				OK = YES;
				break;
				
			case kManifest_platinum:
				*value = INT_TO_JSVAL([entity cargoQuantityForType:COMMODITY_PLATINUM]);
				OK = YES;
				break;
				
			case kManifest_gem_stones:
			case kManifest_gemstones:
			case kManifest_gemStones:
				*value = INT_TO_JSVAL([entity cargoQuantityForType:COMMODITY_GEM_STONES]);
				OK = YES;
				break;
				
			case kManifest_alien_items:
			case kManifest_alienitems:
			case kManifest_alienItems:
				*value = INT_TO_JSVAL([entity cargoQuantityForType:COMMODITY_ALIEN_ITEMS]);
				OK = YES;
				break;
		}
	}
	else
	{
		if (!OOJS_PROPID_IS_INT)  return YES;
		
		switch (OOJS_PROPID_INT)
		{
			case kManifest_list:
				result = [entity cargoListForScripting];
				OK = YES;
				break;
				
			default:
				OOJSReportBadPropertySelector(context, @"Manifest", OOJS_PROPID_INT);
		}
	}
		
	if (OK && result != nil)  *value = [result oo_jsValueInContext:context];	
	return OK;
	
	OOJS_NATIVE_EXIT
}


static JSBool ManifestSetProperty(OOJS_PROP_ARGS)
{
	OOJS_NATIVE_ENTER(context)
	
	BOOL						OK = NO;
	PlayerEntity				*entity = OOPlayerForScripting();
	int32						iValue;
	unsigned					commodity;
	
	if (!GetCommodityID(context, propID, &commodity))  return YES;
	
	// we can always change gold, platinum & gem-stones quantities, even with special cargo
	if ([entity specialCargo] && (commodity < kManifest_gold || commodity > kManifest_gemStones))
	{
		OOJSReportWarning(context, @"PlayerShip.manifest['foo'] - cannot modify cargo tonnage when Special Cargo is in use.");
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
			OOJSReportBadPropertySelector(context, @"Manifest", commodity);
	}
	
	return OK;
	
	OOJS_NATIVE_EXIT
}
