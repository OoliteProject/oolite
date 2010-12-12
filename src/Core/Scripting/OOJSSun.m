/*

OOJSSun.m


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

#import "OOJSSun.h"
#import "OOJSEntity.h"
#import "OOJavaScriptEngine.h"

#import "OOSunEntity.h"


DEFINE_JS_OBJECT_GETTER(JSSunGetSunEntity, OOSunEntity)


static JSObject		*sSunPrototype;


static JSBool SunGetProperty(JSContext *context, JSObject *this, jsval name, jsval *outValue);
static JSBool SunGoNova(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool SunCancelNova(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);


static JSClass sSunClass =
{
	"Sun",
	JSCLASS_HAS_PRIVATE,
	
	JS_PropertyStub,		// addProperty
	JS_PropertyStub,		// delProperty
	SunGetProperty,			// getProperty
	JS_PropertyStub,		// setProperty
	JS_EnumerateStub,		// enumerate
	JS_ResolveStub,			// resolve
	JS_ConvertStub,			// convert
	JSObjectWrapperFinalize,// finalize
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
	{ "radius",					kSun_radius,				JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "hasGoneNova",			kSun_hasGoneNova,			JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "isGoingNova",			kSun_isGoingNova,			JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ 0 }
};


static JSFunctionSpec sSunMethods[] =
{
	// JS name					Function					min args
	{ "goNova",					SunGoNova,					1 },
	{ "cancelNova",				SunCancelNova,				0 },
	{ 0 }
};


void InitOOJSSun(JSContext *context, JSObject *global)
{
	sSunPrototype = JS_InitClass(context, global, JSEntityPrototype(), &sSunClass, NULL, 0, sSunProperties, sSunMethods, NULL, NULL);
	JSRegisterObjectConverter(&sSunClass, JSBasicPrivateObjectConverter);
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


- (NSString *)jsClassName
{
	return @"Sun";
}

@end


static JSBool SunGetProperty(JSContext *context, JSObject *this, jsval name, jsval *outValue)
{
	if (!JSVAL_IS_INT(name))  return YES;
	
	OOJS_NATIVE_ENTER(context)
	
	BOOL						OK = NO;
	OOSunEntity					*sun = nil;
	
	if (EXPECT_NOT(!JSSunGetSunEntity(context, this, &sun))) return NO;
	
	switch (JSVAL_TO_INT(name))
	{
			
		case kSun_radius:
			OK = JS_NewDoubleValue(context, [sun radius], outValue);
			break;
			
		case kSun_hasGoneNova:
			*outValue = BOOLToJSVal([sun goneNova]);
			OK = YES;
			break;
			
		case kSun_isGoingNova:
			*outValue = BOOLToJSVal([sun willGoNova] && ![sun goneNova]);
			OK = YES;
			break;
			
		default:
			OOReportJSBadPropertySelector(context, @"Sun", JSVAL_TO_INT(name));
	}
	return OK;
	
	OOJS_NATIVE_EXIT
}


// *** Methods ***

// goNova([delay : Number])
static JSBool SunGoNova(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	OOJS_NATIVE_ENTER(context)
	
	OOSunEntity					*sun = nil;
	jsdouble					delay = 0;
	
	if (EXPECT_NOT(!JSSunGetSunEntity(context, this, &sun))) return NO;
	if (argc > 0 && EXPECT_NOT(!JS_ValueToNumber(context, argv[0], &delay)))  return NO;
	
	[sun setGoingNova:YES inTime:delay];
	return YES;
	
	OOJS_NATIVE_EXIT
}


// cancelNova()
static JSBool SunCancelNova(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	OOJS_NATIVE_ENTER(context)
	
	OOSunEntity					*sun = nil;
	
	if (EXPECT_NOT(!JSSunGetSunEntity(context, this, &sun))) return NO;
	
	if ([sun willGoNova] && ![sun goneNova])
	{
		[sun setGoingNova:NO inTime:0];
	}
	return YES;
	
	OOJS_NATIVE_EXIT
}
