/*

OOJSPopulatorDefinition.m (QuickJS-ng)


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

#import "OOJSPopulatorDefinition.h"
#import "OOJSScript.h"
#import "OOJSVector.h"
#import "OOJavaScriptEngine.h"
#import "OOMaths.h"

#include "oofnd/Notification.hpp"

/*	C++20 since bead oo-1h0h (proposed ADR-0056 amendment oo-o89): cxx::OOJSPopulatorDefinition.
        -init after [super init] is the constructor, -dealloc the destructor; the engine, the script
        stack and the owning script's weak reference are Objective-C and are messaged as before.
*/

namespace cxx {

OOJSPopulatorDefinition::OOJSPopulatorDefinition()
{
    _callback = JS_UNDEFINED;
    _callbackThis = JS_UNDEFINED;

    _owningScript = oo::adoptObjC(static_cast<::OOJSScript*>([[::OOJSScript currentlyRunningScript] weakRetain]));

    // Stays registered until destruction, so values set after a reset are also released on the next one.
    oo::NotificationCenter::defaultCenter().addObserver(this, kOOJavaScriptEngineWillResetNotificationName,
        [::OOJavaScriptEngine sharedEngine],
        [this](const oo::Notification&) { deleteJSPointers(); });
}

void OOJSPopulatorDefinition::deleteJSPointers()
{
    JSContext* context = OOJSAcquireContext();
    JS_FreeValue(context, _callback);
    _callback = JS_UNDEFINED;
    JS_FreeValue(context, _callbackThis);
    _callbackThis = JS_UNDEFINED;
    OOJSRelinquishContext(context);
}

OOJSPopulatorDefinition::~OOJSPopulatorDefinition()
{
    oo::NotificationCenter::defaultCenter().removeObserver(this, kOOJavaScriptEngineWillResetNotificationName,
        [::OOJavaScriptEngine sharedEngine]);

    _owningScript = nullptr;

    deleteJSPointers();
}

JSValue OOJSPopulatorDefinition::callback()
{
    return JS_DupValue(OOJSAcquireContext(), _callback);
}

void OOJSPopulatorDefinition::setCallback(JSValueConst callback)
{
    JSContext* context = OOJSAcquireContext();
    JSValue old = _callback;
    _callback = JS_DupValue(context, callback);
    JS_FreeValue(context, old);
    OOJSRelinquishContext(context);
}

JSValue OOJSPopulatorDefinition::callbackThis()
{
    return JS_DupValue(OOJSAcquireContext(), _callbackThis);
}

void OOJSPopulatorDefinition::setCallbackThis(JSValueConst callbackThis)
{
    JSContext* context = OOJSAcquireContext();
    JSValue old = _callbackThis;
    _callbackThis = JS_DupValue(context, callbackThis);
    JS_FreeValue(context, old);
    OOJSRelinquishContext(context);
}

void OOJSPopulatorDefinition::runPopulatorCallback(HPVector location)
{
    ::OOJavaScriptEngine* engine = [::OOJavaScriptEngine sharedEngine];
    JSContext* context = OOJSAcquireContext();
    JSValue rval = JS_UNDEFINED;

    if (!JS_IsFunction(context, _callback)) {
        // The callback was released by an engine reset.
        OOJSRelinquishContext(context);
        return;
    }

    JSValue loc = JS_UNDEFINED;
    VectorToJSValue(context, HPVectorToVector(location), &loc);

    const oo::ObjCRef<::OOJSScript*> owner = _owningScript; // local copy needed
    [::OOJSScript pushScript:owner.get()];

    // Hold our own references in case the callback replaces them.
    JSValue callback = JS_DupValue(context, _callback);
    JSValue callbackThis = JS_IsObject(_callbackThis) ? JS_DupValue(context, _callbackThis) : JS_UNDEFINED;
    [engine callJSFunction:callback
                 forObject:callbackThis
                      argc:1
                      argv:&loc
                    result:&rval];
    JS_FreeValue(context, callback);
    JS_FreeValue(context, callbackThis);

    [::OOJSScript popScript:owner.get()];

    JS_FreeValue(context, rval);
    JS_FreeValue(context, loc);
    OOJSRelinquishContext(context);
}

} // namespace cxx
