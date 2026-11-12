/*

OOJSInterfaceDefinition.m (QuickJS-ng)


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

#include "OOJSInterfaceDefinition.h"

#include "OOJSScript.h"
#include "OOJavaScriptEngine.h"
#include "oofnd/Notification.hpp"
#include "oofnd/String.hpp"

namespace {
// -caseInsensitiveCompare: as the definitions used it: a nil receiver answers
// OOComparisonResult::kSame (a message to nil); a nil argument compares as the
// empty string.
static OOComparisonResult CaseInsensitiveCompare(
    const std::optional<std::string>& a, const std::optional<std::string>& b) {
  if (!a.has_value()) return OOComparisonResult::kSame;
  int order = oo::str::caseInsensitiveCompare(*a, b.value_or(std::string()));
  return (order < 0) ? OOComparisonResult::kAscending
                     : ((order > 0) ? OOComparisonResult::kDescending
                                    : OOComparisonResult::kSame);
}
}  // namespace

OOJSInterfaceDefinition::OOJSInterfaceDefinition() {
  _callback = JS_UNDEFINED;
  _callbackThis = JS_UNDEFINED;

  _owningScript = OOJSScript::currentlyRunningScript();

  // Stays registered until destruction, so values set after a reset are also
  // released on the next one.
  oo::NotificationCenter::defaultCenter().addObserver(
      this, kOOJavaScriptEngineWillResetNotificationName,
      OOJavaScriptEngine::sharedEngine(),
      [this](const oo::Notification&) { deleteJSPointers(); });
}

void OOJSInterfaceDefinition::deleteJSPointers() {
  JSContext* context = OOJSAcquireContext();
  JS_FreeValue(context, _callback);
  _callback = JS_UNDEFINED;
  JS_FreeValue(context, _callbackThis);
  _callbackThis = JS_UNDEFINED;
  OOJSRelinquishContext(context);
}

OOJSInterfaceDefinition::~OOJSInterfaceDefinition() {
  oo::NotificationCenter::defaultCenter().removeObserver(
      this, kOOJavaScriptEngineWillResetNotificationName,
      OOJavaScriptEngine::sharedEngine());

  _owningScript = nullptr;

  deleteJSPointers();
}

std::optional<std::string> OOJSInterfaceDefinition::title() { return _title; }

void OOJSInterfaceDefinition::setTitle(
    const std::optional<std::string>& title) {
  _title = title;
}

std::optional<std::string> OOJSInterfaceDefinition::category() {
  return _category;
}

void OOJSInterfaceDefinition::setCategory(const std::string& category) {
  _category = category;
}

std::optional<std::string> OOJSInterfaceDefinition::summary() {
  return _summary;
}

void OOJSInterfaceDefinition::setSummary(const std::string& summary) {
  _summary = summary;
}

JSValue OOJSInterfaceDefinition::callback() {
  return JS_DupValue(OOJSAcquireContext(), _callback);
}

void OOJSInterfaceDefinition::setCallback(JSValueConst callback) {
  JSContext* context = OOJSAcquireContext();
  JSValue old = _callback;
  _callback = JS_DupValue(context, callback);
  JS_FreeValue(context, old);
  OOJSRelinquishContext(context);
}

JSValue OOJSInterfaceDefinition::callbackThis() {
  return JS_DupValue(OOJSAcquireContext(), _callbackThis);
}

void OOJSInterfaceDefinition::setCallbackThis(JSValueConst callbackThis) {
  JSContext* context = OOJSAcquireContext();
  JSValue old = _callbackThis;
  _callbackThis = JS_DupValue(context, callbackThis);
  JS_FreeValue(context, old);
  OOJSRelinquishContext(context);
}

void OOJSInterfaceDefinition::runCallback(const std::string& key) {
  ::OOJavaScriptEngine* engine = OOJavaScriptEngine::sharedEngine();
  JSContext* context = OOJSAcquireContext();
  JSValue rval = JS_UNDEFINED;

  if (!JS_IsFunction(context, _callback)) {
    // The callback was released by an engine reset.
    OOJSRelinquishContext(context);
    return;
  }

  JSValue cKey = OOJSValueFromPList(context, oo::PList(key));

  const oo::WeakRef<OOJSScript> owner = _owningScript;  // local copy needed
  OOJSScript::pushScript(owner);

  // Hold our own references in case the callback replaces them.
  JSValue callback = JS_DupValue(context, _callback);
  JSValue callbackThis = JS_IsObject(_callbackThis)
                             ? JS_DupValue(context, _callbackThis)
                             : JS_UNDEFINED;
  engine->callJSFunction(callback, callbackThis, 1, &cKey, &rval);
  JS_FreeValue(context, callback);
  JS_FreeValue(context, callbackThis);

  OOJSScript::popScript(owner.get());

  JS_FreeValue(context, rval);
  JS_FreeValue(context, cKey);
  OOJSRelinquishContext(context);
}

OOComparisonResult OOJSInterfaceDefinition::interfaceCompare(
    OOJSInterfaceDefinition* other) {
  OOComparisonResult byCategory = CaseInsensitiveCompare(
      _category, (other != nullptr) ? other->category() : std::nullopt);
  if (byCategory == OOComparisonResult::kSame) {
    return CaseInsensitiveCompare(
        _title, (other != nullptr) ? other->title() : std::nullopt);
  } else {
    return byCategory;
  }
}
