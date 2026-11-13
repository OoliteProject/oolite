/*

OOJSGuiScreenKeyDefinition.m (QuickJS-ng)


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

#include "OOJSGuiScreenKeyDefinition.h"

#include "OOJSScript.h"
#include "OOJavaScriptEngine.h"
#include "oofnd/Notification.hpp"
#include "oofnd/String.hpp"

// namespace

OOJSGuiScreenKeyDefinition::OOJSGuiScreenKeyDefinition() {
  _callback = JS_UNDEFINED;
  _callbackThis = JS_UNDEFINED;

  _owningScript = oo::share(OOJSScript::currentlyRunningScript());

  // Stays registered until destruction, so values set after a reset are also
  // released on the next one.
  oo::NotificationCenter::defaultCenter().addObserver(
      this, kOOJavaScriptEngineWillResetNotificationName,
      OOJavaScriptEngine::sharedEngine(),
      [this](const oo::Notification&) { deleteJSPointers(); });
}

void OOJSGuiScreenKeyDefinition::deleteJSPointers() {
  JSContext* context = OOJSAcquireContext();
  JS_FreeValue(context, _callback);
  _callback = JS_UNDEFINED;
  JS_FreeValue(context, _callbackThis);
  _callbackThis = JS_UNDEFINED;
  OOJSRelinquishContext(context);
}

OOJSGuiScreenKeyDefinition::~OOJSGuiScreenKeyDefinition() {
  oo::NotificationCenter::defaultCenter().removeObserver(
      this, kOOJavaScriptEngineWillResetNotificationName,
      OOJavaScriptEngine::sharedEngine());

  _owningScript.reset();

  deleteJSPointers();
}

std::optional<std::string> OOJSGuiScreenKeyDefinition::name() { return _name; }

void OOJSGuiScreenKeyDefinition::setName(
    const std::optional<std::string>& name) {
  _name = name;
}

oo::PList OOJSGuiScreenKeyDefinition::registerKeys() { return _registerKeys; }

void OOJSGuiScreenKeyDefinition::setRegisterKeys(
    const oo::PList& registerKeys) {
  _registerKeys = registerKeys;
}

JSValue OOJSGuiScreenKeyDefinition::callback() {
  return JS_DupValue(OOJSAcquireContext(), _callback);
}

void OOJSGuiScreenKeyDefinition::setCallback(JSValueConst callback) {
  JSContext* context = OOJSAcquireContext();
  JSValue old = _callback;
  _callback = JS_DupValue(context, callback);
  JS_FreeValue(context, old);
  OOJSRelinquishContext(context);
}

JSValue OOJSGuiScreenKeyDefinition::callbackThis() {
  return JS_DupValue(OOJSAcquireContext(), _callbackThis);
}

void OOJSGuiScreenKeyDefinition::setCallbackThis(JSValueConst callbackThis) {
  JSContext* context = OOJSAcquireContext();
  JSValue old = _callbackThis;
  _callbackThis = JS_DupValue(context, callbackThis);
  JS_FreeValue(context, old);
  OOJSRelinquishContext(context);
}

void OOJSGuiScreenKeyDefinition::runCallback(const std::string& key) {
  ::OOJavaScriptEngine* engine = OOJavaScriptEngine::sharedEngine();
  JSContext* context = OOJSAcquireContext();
  JSValue rval = JS_UNDEFINED;

  if (!JS_IsFunction(context, _callback)) {
    // The callback was released by an engine reset.
    OOJSRelinquishContext(context);
    return;
  }

  JSValue cKey = OOJSValueFromPList(context, oo::PList(key));

  const std::weak_ptr<OOJSScript> owner = _owningScript;  // local copy needed
  OOJSScript::pushScript(owner);

  // Hold our own references in case the callback replaces them.
  JSValue callback = JS_DupValue(context, _callback);
  JSValue callbackThis = JS_IsObject(_callbackThis)
                             ? JS_DupValue(context, _callbackThis)
                             : JS_UNDEFINED;
  engine->callJSFunction(callback, callbackThis, 1, &cKey, &rval);
  JS_FreeValue(context, callback);
  JS_FreeValue(context, callbackThis);

  OOJSScript::popScript(owner.lock().get());

  JS_FreeValue(context, rval);
  JS_FreeValue(context, cKey);
  OOJSRelinquishContext(context);
}

OOComparisonResult OOJSGuiScreenKeyDefinition::interfaceCompare(
    OOJSGuiScreenKeyDefinition* other) {
  // -caseInsensitiveCompare: as it was sent: a nil name answers
  // OOComparisonResult::kSame (a message to nil); a nil other name compares as
  // the empty string.
  if (!_name.has_value()) return OOComparisonResult::kSame;
  int order = oo::str::caseInsensitiveCompare(
      *_name, ((other != nullptr) ? other->name() : std::nullopt)
                  .value_or(std::string()));
  return (order < 0) ? OOComparisonResult::kAscending
                     : ((order > 0) ? OOComparisonResult::kDescending
                                    : OOComparisonResult::kSame);
}
