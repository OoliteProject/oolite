/*

OOJSTimer.h

JavaScript timer class.

OOJSTimer is a subclass of OOScriptTimer and has no caller outside
OOJSTimer.cpp; a Timer's private slot holds it (OOJSPrivateObject.h).


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

#pragma once

#include <quickjs.h>

#include "OOJSPrivateObject.h"
#include "OOScriptTimer.h"

class OOJSScript;

// A Timer JS object's private slot holds the timer.
class OOJSTimer : public OOScriptTimer, public ::OOJSPrivateObject {
 public:
  // [[OOJSTimer alloc] initWithDelay:interval:context:function:this:], for the
  // Timer constructor: null where the initialiser answered nil. function and
  // jsThis are borrowed (the timer takes its own references); jsThis may be JS
  // null.
  static oo::Ref<OOJSTimer> timerWithDelay(OOTimeAbsolute delay,
                                           OOTimeDelta interval,
                                           JSContext* context,
                                           JSValueConst function,
                                           JSValueConst jsThis);

  ~OOJSTimer() override;

  std::optional<std::string> descriptionComponents() const override;
  std::string className() const override { return "OOJSTimer"; }
  std::optional<std::string> oo_jsClassName() override;

  void timerFired() override;

  // The JS glue (OOJSPrivateObject): the Timer object, made by the initialiser
  // (owned by the caller; JS null once it has been finalized); forgetting it
  // when it is finalized, with a warning if the timer still runs; "[Timer
  // <components>]".
  JSValue jsValueInContext(JSContext* context) override;
  void clearJSSelf(JSValueConst selfVal) override;
  std::optional<std::string> jsDescription() override;

  // A one-shot timer whose callback is running: it is dropped once the callback
  // returns.
  bool willNotFireAgain();

  /*	The reference created with the JS object by the initialiser belongs to
          whoever calls this, once (the constructor, which returns it).
          SpiderMonkey's unrooted _jsSelf pointer added no reference, so this is
          what lets the JS object be collected (and finalized) as before.
  */
  JSValue transferJSSelf();

 private:
  OOJSTimer() = default;

  bool initWithDelay(OOTimeAbsolute delay, OOTimeDelta interval,
                     JSContext* context, JSValueConst function,
                     JSValueConst jsThis);
  // Notification handler: engine reset.
  void deleteJSPointers();
  void releaseJSValues();

  JSValue _function = JS_UNDEFINED;  // Owned; released on engine reset.
  JSValue _jsThis = JS_UNDEFINED;  // The object that is 'this' in the function
                                   // call. Owned; may be JS_NULL.

  oo::WeakRef<OOJSScript> _owningScript;  // a weak reference
  // The function's name, read once: the finalizer's description must not run JS
  // code. nullopt for an anonymous function.
  std::optional<std::string> _functionName;

  JSValue _jsSelf =
      JS_UNDEFINED;  // The JS Timer object proxy for this OOJSTimer. Not owned
                     // (it owns us); cleared when finalized.

  bool _firing =
      false;  // In the callback, during which the timer is still scheduled.
};

void InitOOJSTimer(JSContext* context, JSValueConst global);
