/*

EntityOOJavaScriptExtensions.m (QuickJS-ng)

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

#import "EntityOOJavaScriptExtensions.h"
#import "DockEntity.h"
#import "OOJSDock.h"
#import "OOJSEntity.h"
#import "OOJSShip.h"
#import "OOJSStation.h"
#import "OOJSVisualEffect.h"
#import "OOJSWormhole.h"
#import "OOPlanetEntity.h"
#import "StationEntity.h"
#import "WormholeEntity.h"

@implementation Entity (OOJavaScriptExtensions)

- (BOOL)isVisibleToScripts
{
    return NO;
}

- (NSString*)oo_jsClassName
{
    return @"Entity";
}

- (JSValue)oo_jsValueInContext:(JSContext*)context
{
    if (!JS_IsObject(_jsSelf) && [self isVisibleToScripts]) {
        // Create JS object. The entity keeps a reference to it for as long as the entity exists.
        _jsSelf = JS_NewObjectClass(context, (int)[self oo_jsClassID]);
        if (JS_IsException(_jsSelf)) {
            JS_FreeValue(context, JS_GetException(context));
            _jsSelf = JS_UNDEFINED;
        } else {
            JS_SetOpaque(_jsSelf, OOConsumeReference([self weakRetain]));

            [[NSNotificationCenter defaultCenter] addObserver:self
                                                     selector:@selector(deleteJSSelf)
                                                         name:kOOJavaScriptEngineWillResetNotification
                                                       object:[OOJavaScriptEngine sharedEngine]];
        }
    }

    if (JS_IsObject(_jsSelf))
        return JS_DupValue(context, _jsSelf);

    return JS_NULL;
    // Analyzer: object leaked. [Expected, object is retained by JS object.]
}

- (JSClassID)oo_jsClassID
{
    return JSEntityClassID();
}

- (void)deleteJSSelf
{
    if (JS_IsObject(_jsSelf)) {
        /*	Scripts may still hold the JS object. Its private data is a weak
                reference, so it becomes stale (isValid false) when the entity is
                deallocated.
        */
        JS_FreeValue(OOJSAcquireContext(), _jsSelf);
        _jsSelf = JS_UNDEFINED;

        [[NSNotificationCenter defaultCenter] removeObserver:self
                                                        name:kOOJavaScriptEngineWillResetNotification
                                                      object:[OOJavaScriptEngine sharedEngine]];
    }
}

@end

@implementation ShipEntity (OOJavaScriptExtensions)

- (BOOL)isVisibleToScripts
{
    return YES;
}

- (JSClassID)oo_jsClassID
{
    return JSShipClassID();
}

- (NSString*)oo_jsClassName
{
    return @"Ship";
}

- (NSArray*)subEntitiesForScript
{
    return [[self shipSubEntityEnumerator] allObjects];
}

- (void)setTargetForScript:(ShipEntity*)target
{
    ShipEntity* me = self;

    // Ensure coherence by not fiddling with subentities.
    while ([me isSubEntity]) {
        if (me == [me owner] || [me owner] == nil)
            break;
        me = (ShipEntity*)[me owner];
    }
    while ([target isSubEntity]) {
        if (target == [target owner] || [target owner] == nil)
            break;
        target = (ShipEntity*)[target owner];
    }
    if (![me isKindOfClass:[ShipEntity class]])
        return;
    if (target != nil) {
        [me addTarget:target];
    } else
        [me removeTarget:[me primaryTarget]];
}

@end
