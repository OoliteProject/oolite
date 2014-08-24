/*

OOJSManifest.m

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
	kManifest_list				// manifest list, array of commodities: name, unit, quantity, displayName - read-only	
};


static JSPropertySpec sManifestProperties[] =
{
	// JS name					ID							flags
	{ "list",				kManifest_list,				OOJS_PROP_READONLY_CB },
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
	
}


static JSBool ManifestDeleteProperty(JSContext *context, JSObject *this, jsid propID, jsval *value)
{
	jsval v = JSVAL_VOID;
	return ManifestSetProperty(context, this, propID, NO, &v);
}


static JSBool ManifestGetProperty(JSContext *context, JSObject *this, jsid propID, jsval *value)
{
	OOJS_NATIVE_ENTER(context)
	
	id							result = nil;
	PlayerEntity				*entity = OOPlayerForScripting();
	
	if (JSID_IS_INT(propID))
	{
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
	else if (JSID_IS_STRING(propID))
	{
		/* 'list' property is hard-coded
		 * others map to the commodity keys in trade-goods.plist
		 * compatible-ish with 1.80 and earlier except that
		 * alienItems and similar aliases don't work */
		NSString *key = OOStringFromJSString(context, JSID_TO_STRING(propID));
		*value = INT_TO_JSVAL([entity cargoQuantityForType:key]);
		return YES;
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
	
	if (JSID_IS_STRING(propID))
	{
		NSString *key = OOStringFromJSString(context, JSID_TO_STRING(propID));

		OOMassUnit unit = [[UNIVERSE commodityMarket] massUnitForGood:key];
		// we can always change gold, platinum & gem-stones quantities, even with special cargo
		if (unit == UNITS_TONS && [entity specialCargo])
		{
			OOJSReportWarning(context, @"PlayerShip.manifest['foo'] - cannot modify cargo tonnage when Special Cargo is in use.");
			return YES;
		}
	
		if (JS_ValueToInt32(context, *value, &iValue))
		{
			if (iValue < 0)  iValue = 0;
			[entity setCargoQuantityForType:key amount:iValue];
		}
		else
		{
			OOJSReportBadPropertyValue(context, this, propID, sManifestProperties, *value);
		}
	}
	return YES;
	
	OOJS_NATIVE_EXIT
}
