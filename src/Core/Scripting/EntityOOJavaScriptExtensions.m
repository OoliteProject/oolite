/*

EntityOOJavaScriptExtensions.m

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


#import "EntityOOJavaScriptExtensions.h"
#import "OOJSEntity.h"
#import "OOJSShip.h"
#import "OOJSStation.h"
#import "StationEntity.h"
#import "OOPlanetEntity.h"


@implementation Entity (OOJavaScriptExtensions)

- (BOOL) isVisibleToScripts
{
	return NO;
}


- (NSString *) jsClassName
{
	return @"Entity";
}


- (jsval) javaScriptValueInContext:(JSContext *)context
{
	JSClass					*class = NULL;
	JSObject				*prototype = NULL;
	jsval					result = JSVAL_NULL;
	
	if (jsSelf == NULL && [self isVisibleToScripts])
	{
		// Create JS object
		[self getJSClass:&class andPrototype:&prototype];
		
		jsSelf = JS_NewObject(context, class, prototype, NULL);
		if (jsSelf != NULL)
		{
			if (!JS_SetPrivate(context, jsSelf, [self weakRetain]))  jsSelf = NULL;
		}
		
		if (jsSelf != NULL)  JS_AddNamedRoot(context, &jsSelf, "Entity jsSelf");
	}
	
	if (jsSelf != NULL)  result = OBJECT_TO_JSVAL(jsSelf);
	
	return result;
	// Analyzer: object leaked. [Expected, object is retained by JS object.]
}


- (void) getJSClass:(JSClass **)outClass andPrototype:(JSObject **)outPrototype
{
	*outClass = JSEntityClass();
	*outPrototype = JSEntityPrototype();
}


- (void) deleteJSSelf
{
	if (jsSelf != NULL)
	{
		[[OOJavaScriptEngine sharedEngine] removeGCRoot:&jsSelf];
		jsSelf = NULL;
	}
}

@end


@implementation ShipEntity (OOJavaScriptExtensions)

- (BOOL) isVisibleToScripts
{
	return YES;
}


- (void) getJSClass:(JSClass **)outClass andPrototype:(JSObject **)outPrototype
{
	*outClass = JSShipClass();
	*outPrototype = JSShipPrototype();
}


- (NSString *) jsClassName
{
	return @"Ship";
}


- (NSArray *) subEntitiesForScript
{
	return [[self shipSubEntityEnumerator] allObjects];
}


- (void) setTargetForScript:(ShipEntity *)target
{
	ShipEntity *me = self;
	
	// Ensure coherence by not fiddling with subentities
	while ([me isSubEntity])  {
		if (me == [me owner] || [me owner] == nil) break;
		me = (ShipEntity *)[me owner];
	}
	while ([target isSubEntity]) {
		if (target == [target owner] || [target owner] == nil) break;
		target = (ShipEntity *)[target owner];
	}
	if (![me isKindOfClass:[ShipEntity class]])  return;
	if (target != nil)  [me addTarget:target];
	else  [me removeTarget:[me primaryTarget]];
}

@end
