/*

OOJSSun.m


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

#import "OOJSSun.h"
#import "OOJSEntity.h"
#import "OOJavaScriptEngine.h"

#import "OOSunEntity.h"


static JSObject		*sSunPrototype;


static JSBool SunGetProperty(JSContext *context, JSObject *this, jsid propID, jsval *value);
static JSBool SunGoNova(JSContext *context, uintN argc, jsval *vp);
static JSBool SunCancelNova(JSContext *context, uintN argc, jsval *vp);


static JSClass sSunClass =
{
	"Sun",
	JSCLASS_HAS_PRIVATE,
	
	JS_PropertyStub,		// addProperty
	JS_PropertyStub,		// delProperty
	SunGetProperty,			// getProperty
	JS_StrictPropertyStub,	// setProperty
	JS_EnumerateStub,		// enumerate
	JS_ResolveStub,			// resolve
	JS_ConvertStub,			// convert
	OOJSObjectWrapperFinalize,// finalize
	JSCLASS_NO_OPTIONAL_MEMBERS
};


enum
{
	// Property IDs
	kSun_radius,				// Radius of sun in metres, number, read-only
	kSun_hasGoneNova,			// Has sun gone nova, boolean, read-only
	kSun_isGoingNova			// Will sun go nova, boolean, read-only
};


static JSPropertySpec sSunProperties[] =
{
	// JS name					ID							flags
	{ "hasGoneNova",			kSun_hasGoneNova,			OOJS_PROP_READONLY_CB },
	{ "isGoingNova",			kSun_isGoingNova,			OOJS_PROP_READONLY_CB },
	{ "radius",					kSun_radius,				OOJS_PROP_READONLY_CB },
	{ 0 }
};


static JSFunctionSpec sSunMethods[] =
{
	// JS name					Function					min args
	{ "cancelNova",				SunCancelNova,				0 },
	{ "goNova",					SunGoNova,					1 },
	{ 0 }
};


DEFINE_JS_OBJECT_GETTER(JSSunGetSunEntity, &sSunClass, sSunPrototype, OOSunEntity)


void InitOOJSSun(JSContext *context, JSObject *global)
{
	sSunPrototype = JS_InitClass(context, global, JSEntityPrototype(), &sSunClass, OOJSUnconstructableConstruct, 0, sSunProperties, sSunMethods, NULL, NULL);
	OOJSRegisterObjectConverter(&sSunClass, OOJSBasicPrivateObjectConverter);
	OOJSRegisterSubclass(&sSunClass, JSEntityClass());
}


@implementation OOSunEntity (OOJavaScriptExtensions)

- (BOOL) isVisibleToScripts
{
	return YES;
}


- (void)getJSClass:(JSClass **)outClass andPrototype:(JSObject **)outPrototype
{
	*outClass = &sSunClass;
	*outPrototype = sSunPrototype;
}


- (NSString *) oo_jsClassName
{
	return @"Sun";
}

@end


static JSBool SunGetProperty(JSContext *context, JSObject *this, jsid propID, jsval *value)
{
	if (!JSID_IS_INT(propID))  return YES;
	
	OOJS_NATIVE_ENTER(context)
	
	OOSunEntity					*sun = nil;
	
	if (EXPECT_NOT(!JSSunGetSunEntity(context, this, &sun)))  return NO;
	
	switch (JSID_TO_INT(propID))
	{
		case kSun_radius:
			return JS_NewNumberValue(context, [sun radius], value);
			
		case kSun_hasGoneNova:
			*value = OOJSValueFromBOOL([sun goneNova]);
			return YES;
			
		case kSun_isGoingNova:
			*value = OOJSValueFromBOOL([sun willGoNova] && ![sun goneNova]);
			return YES;
			
		default:
			OOJSReportBadPropertySelector(context, this, propID, sSunProperties);
			return NO;
	}
	
	OOJS_NATIVE_EXIT
}


// *** Methods ***

// goNova([delay : Number])
static JSBool SunGoNova(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	OOSunEntity					*sun = nil;
	jsdouble					delay = 0;
	
	if (EXPECT_NOT(!JSSunGetSunEntity(context, OOJS_THIS, &sun)))  return NO;
	if (argc > 0 && EXPECT_NOT(!JS_ValueToNumber(context, OOJS_ARGV[0], &delay)))  return NO;
	
	[sun setGoingNova:YES inTime:delay];
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}


// cancelNova()
static JSBool SunCancelNova(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	OOSunEntity					*sun = nil;
	
	if (EXPECT_NOT(!JSSunGetSunEntity(context, OOJS_THIS, &sun)))  return NO;
	
	if ([sun willGoNova] && ![sun goneNova])
	{
		[sun setGoingNova:NO inTime:0];
	}
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}
