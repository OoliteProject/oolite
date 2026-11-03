/*

OOJSScript+ObjCBridge.mm

TRANSITIONAL (proposed ADR-0056; bead oo-u61e.4): the Objective-C OOJSScript facade over
cxx::OOJSScript, and the category OOScript (JavaScriptEvents). See OOJSScript+ObjCBridge.h.
Deleted with it.

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

#import "OOJSScript.h"

// A facade of this class is only ever made by its own -initWithPath:properties:, which records it
// as the peer, so the root's oo::ToObjC answers it (and never makes a plain OOScript for it while
// it lives, which is as long as its C++ object).
::OOJSScript* oo::ToObjC(cxx::OOJSScript* script)
{
    return static_cast<::OOJSScript*>(oo::ToObjC(static_cast<cxx::OOScript*>(script)));
}

cxx::OOJSScript* oo::ToCxx(::OOJSScript* script)
{
    return static_cast<cxx::OOJSScript*>(oo::ToCxx(static_cast<::OOScript*>(script)));
}

@implementation OOJSScript

+ (id)scriptWithPath:(const std::optional<std::string>&)path properties:(const oo::PList&)properties
{
    return [[[self alloc] initWithPath:path properties:properties] autorelease];
}

- (id)initWithPath:(const std::optional<std::string>&)path properties:(const oo::PList&)properties
{
    self = [super initWithCxxRootScript:oo::makeRef<cxx::OOJSScript>().get()];
    if (self == nil) {
        OO_LOG("script.javaScript.load.failed", "***** Error loading JavaScript script {} -- {}", path.value_or("(null)"), "allocation failure");
        return nil;
    }
    if (!oo::ToCxx(self)->initWithPath(path, properties))
        DESTROY(self);
    return self;
}

- (void)dealloc
{
    oo::ToCxx(self)->willDealloc();
    [super dealloc];
}

- (std::optional<std::string>)cxx_oo_jsClassName
{
    return oo::ToCxx(self)->jsClassName();
}
- (JSValue)oo_jsValueInContext:(JSContext*)context
{
    return oo::ToCxx(self)->jsValueInContext(context);
}

- (id)weakRetain
{
    return oo::ToCxx(self)->weakRetain();
}
- (void)weakRefDied:(OOWeakReference*)weakRef
{
    oo::ToCxx(self)->weakRefDied(weakRef);
}

+ (OOJSScript*)currentlyRunningScript
{
    return cxx::OOJSScript::currentlyRunningScript();
}
+ (std::vector<oo::ObjCRef<OOJSScript*>>)scriptStack
{
    return cxx::OOJSScript::scriptStack();
}
+ (void)pushScript:(OOJSScript*)script
{
    cxx::OOJSScript::pushScript(script);
}
+ (void)popScript:(OOJSScript*)script
{
    cxx::OOJSScript::popScript(script);
}

- (BOOL)callMethod:(JSAtom)methodID
         inContext:(JSContext*)context
     withArguments:(JSValueConst*)argv
             count:(int)argc
            result:(JSValue*)outResult
{
    return oo::ToCxx(self)->callMethod(methodID, context, argv, argc, outResult);
}

- (oo::PList)cxx_propertyWithID:(JSAtom)propID inContext:(JSContext*)context
{
    return oo::ToCxx(self)->propertyWithID(propID, context);
}

- (BOOL)setProperty:(const oo::PList&)value withID:(JSAtom)propID inContext:(JSContext*)context
{
    return oo::ToCxx(self)->setProperty(value, propID, context);
}

- (BOOL)defineProperty:(const oo::PList&)value withID:(JSAtom)propID inContext:(JSContext*)context
{
    return oo::ToCxx(self)->defineProperty(value, propID, context);
}

- (oo::PList)cxx_propertyNamed:(const std::string&)propName
{
    return oo::ToCxx(self)->propertyNamed(propName);
}
- (BOOL)setProperty:(const oo::PList&)value named:(const std::string&)propName
{
    return oo::ToCxx(self)->setProperty(value, propName);
}
- (BOOL)defineProperty:(const oo::PList&)value named:(const std::string&)propName
{
    return oo::ToCxx(self)->defineProperty(value, propName);
}

@end

@implementation OOScript (JavaScriptEvents)

- (BOOL)callMethod:(JSAtom)methodID
         inContext:(JSContext*)context
     withArguments:(JSValueConst*)argv
             count:(int)argc
            result:(JSValue*)outResult
{
    if (outResult != NULL)
        *outResult = JS_UNDEFINED;
    return NO;
}

@end
