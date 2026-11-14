/*

OOObject+OOJavaScript.mm

TRANSITIONAL: see OOObject+OOJavaScript.h. The category on OOObject that forwards to the free
functions holding its bodies (amendment oo-ppc item 3), and the one-line bridges of
OOJavaScriptEngine.mm's free functions (amendment oo-9ht.139), moved verbatim from
OOJavaScriptEngine+ObjCBridge.mm when the engine's facade was deleted.

JavaScript support for Oolite
Copyright (C) 2007-2013 David Taylor and Jens Ayton.

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
#import "OOJavaScriptEngine.h"
#import "OOPlanetEntity.h"
#import "OOVector.h"
#import "OOWeakReference.h"

// The root class's JS glue (amendment oo-ppc item 3): the bodies are in OOJavaScriptEngine.mm.
@implementation OOObject (OOJavaScriptConversion)

- (JSValue)oo_jsValueInContext:(JSContext*)context
{
    return OOObjectJSValueInContext(context);
}
- (std::optional<std::string>)cxx_oo_jsClassName
{
    return OOObjectJSClassName();
}
- (std::optional<std::string>)cxx_oo_jsDescription
{
    return OOObjectJSDescription(self);
}
- (std::optional<std::string>)cxx_oo_jsDescriptionWithClassName:(const std::optional<std::string>&)className
{
    return OOObjectJSDescriptionWithClassName(self, className);
}
- (void)oo_clearJSSelf:(JSValueConst)selfVal
{
    OOObjectClearJSSelf(selfVal);
}

@end

id OOJavaScriptEngineWeakRefUnderlyingObject(id object)
{
    return [object weakRefUnderlyingObject];
}

Class OOJavaScriptEngineClass(id object)
{
    return [object class];
}

/*	An entity's object, or a weak reference to one, was not asked by selector: its JS value and class
        name were its C++ entity's. Since the root facade's deletion no entity has an Objective-C
        object, and no weak reference refers to one: every object is asked.
*/
JSValue OOJavaScriptEngineJSValueInContext(id object, JSContext* context)
{
    return [object oo_jsValueInContext:context];
}

std::optional<std::string> OOJavaScriptEngineJSClassName(id object)
{
    return [object cxx_oo_jsClassName];
}

std::optional<std::string> OOJavaScriptEngineJSDescriptionWithClassName(id object, const std::optional<std::string>& className)
{
    return [object cxx_oo_jsDescriptionWithClassName:className];
}

std::optional<std::string> OOJavaScriptEngineDescriptionComponents(id object)
{
    return [object cxx_descriptionComponents];
}

Class OOJavaScriptEngineOOObjectClass()
{
    return [OOObject class];
}

std::optional<std::string> OOJavaScriptEngineJSDescription(id object)
{
    return [object cxx_oo_jsDescription];
}

void OOJavaScriptEngineClearJSSelf(id object, JSValueConst selfVal)
{
    [object oo_clearJSSelf:selfVal];
}

bool OOJavaScriptEngineIsKindOfClass(id object, Class requiredClass)
{
    return [object isKindOfClass:requiredClass];
}

#if !OOJS_POC_HARNESS
bool OOJavaScriptEngineIsVisibleToScripts(Entity* entity)
{
    return OOJSEntityIsVisibleToScripts(entity); // the C++ entity's answer, which the root facade's selector forwarded to
}

// The root facade's -isShip, -isSubEntity, -isPlanet and -status forwarded to these members.
bool OOJavaScriptEngineIsShip(Entity* entity)
{
    return entity != nullptr && entity->getIsShip();
}

bool OOJavaScriptEngineIsSubEntity(Entity* entity)
{
    return entity != nullptr && entity->getIsSubEntity();
}

bool OOJavaScriptEngineIsPlanet(Entity* entity)
{
    return entity != nullptr && entity->isPlanet();
}

OOEntityStatus OOJavaScriptEngineStatus(Entity* entity)
{
    return entity != nullptr ? entity->status() : OOEntityStatus { };
}
#endif
