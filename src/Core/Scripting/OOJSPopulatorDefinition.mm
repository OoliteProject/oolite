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

/*	C++20 since bead oo-1h0h (proposed ADR-0056 amendment oo-o89): OOJSPopulatorDefinition.
        -init after [super init] is the constructor, -dealloc the destructor; the engine, the script
        stack and the owning script's weak reference are Objective-C and are messaged as before.
*/

OOJSPopulatorDefinition::OOJSPopulatorDefinition()
{
    _callback = JS_UNDEFINED;
    _callbackThis = JS_UNDEFINED;

    _owningScript = OOJSScript::currentlyRunningScript();

    // Stays registered until destruction, so values set after a reset are also released on the next one.
    oo::NotificationCenter::defaultCenter().addObserver(this, kOOJavaScriptEngineWillResetNotificationName,
        OOJavaScriptEngine::sharedEngine(),
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
        OOJavaScriptEngine::sharedEngine());

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
    ::OOJavaScriptEngine* engine = OOJavaScriptEngine::sharedEngine();
    JSContext* context = OOJSAcquireContext();
    JSValue rval = JS_UNDEFINED;

    if (!JS_IsFunction(context, _callback)) {
        // The callback was released by an engine reset.
        OOJSRelinquishContext(context);
        return;
    }

    JSValue loc = JS_UNDEFINED;
    VectorToJSValue(context, HPVectorToVector(location), &loc);

    const oo::WeakRef<OOJSScript> owner = _owningScript; // local copy needed
    OOJSScript::pushScript(owner);

    // Hold our own references in case the callback replaces them.
    JSValue callback = JS_DupValue(context, _callback);
    JSValue callbackThis = JS_IsObject(_callbackThis) ? JS_DupValue(context, _callbackThis) : JS_UNDEFINED;
    engine->callJSFunction(callback, callbackThis, 1, &loc, &rval);
    JS_FreeValue(context, callback);
    JS_FreeValue(context, callbackThis);

    OOJSScript::popScript(owner.get());

    JS_FreeValue(context, rval);
    JS_FreeValue(context, loc);
    OOJSRelinquishContext(context);
}

namespace {
class PopulatorDefinitionForeign final : public oo::PListForeign {
public:
    explicit PopulatorDefinitionForeign(oo::Ref<OOJSPopulatorDefinition> definition)
        : definition_(std::move(definition))
    {
    }
    OOJSPopulatorDefinition* definition() const noexcept { return definition_.get(); }
    std::string className() const override { return "OOJSPopulatorDefinition"; }
    std::string description() const override { return "<OOJSPopulatorDefinition>"; }

private:
    oo::Ref<OOJSPopulatorDefinition> definition_;
};
} // namespace

oo::PList OOJSPopulatorDefinitionToPList(oo::Ref<OOJSPopulatorDefinition> definition)
{
    if (!definition)
        return oo::PList();
    return oo::PList(oo::PList::Object(oo::makeRef<PopulatorDefinitionForeign>(std::move(definition))));
}

OOJSPopulatorDefinition* OOJSPopulatorDefinitionIn(const oo::PList& plist)
{
    if (const oo::PList::Object* node = plist.getIf<oo::PList::Object>()) {
        if (const auto* foreign = dynamic_cast<const PopulatorDefinitionForeign*>(node->get()))
            return foreign->definition();
    }
    return nullptr;
}
