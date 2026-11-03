/*

OOJSTimer.h

JavaScript timer class.

C++20 since bead oo-kdyh (proposed ADR-0056; amendment oo-ppc for the binding), converted with
its superclass OOScriptTimer. cxx::OOJSTimer has no caller outside OOJSTimer.mm, but the engine
messages the object in a Timer's private slot by selector (-oo_jsValueInContext:,
-cxx_oo_jsClassName) and the timer queue holds it, so it keeps an Objective-C facade,
OOJSTimer+ObjCBridge.h, imported at the end of this header: the facade of the root's peer table,
of this class, with no ivars (ADR-0056 amendment oo-up4b item 3).


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

#ifndef OOJSTIMER_H
#define OOJSTIMER_H

#import "OOScriptTimer.h"
#include "oofnd/objc/OOObjCRef.h"
#include <quickjs.h>

@class OOJSScript;

namespace cxx {

    JSValue _jsSelf; // The JS Timer object proxy for this OOJSTimer. Not owned (it owns us); cleared when finalized.

    BOOL _firing; // In the callback, during which the timer is still scheduled.
}

    ~OOJSTimer() override;

    std::optional<std::string> descriptionComponents() const override;
    std::optional<std::string> oo_jsClassName();

    void timerFired() override;

    // The Timer object, owned by the caller; JS null once it has been finalized.
    JSValue oo_jsValueInContext(JSContext* context);

    // For the Timer finalizer: forgets the JS Timer object.
    void clearJSSelf();

    /*	The reference created with the JS object by the initialiser belongs to
            whoever calls this, once (the constructor, which returns it).
            SpiderMonkey's unrooted _jsSelf pointer added no reference, so this is
            what lets the JS object be collected (and finalized) as before.
    */
    JSValue transferJSSelf();

private:
    OOJSTimer() = default;

    bool initWithDelay(OOTimeAbsolute delay, OOTimeDelta interval, JSContext* context, JSValueConst function, JSValueConst jsThis);
    // Notification handler: engine reset.
    void deleteJSPointers();
    void releaseJSValues();

    JSValue _function = JS_UNDEFINED; // Owned; released on engine reset.
    JSValue _jsThis = JS_UNDEFINED; // The object that is 'this' in the function call. Owned; may be JS_NULL.

    oo::ObjCRef<OOJSScript*> _owningScript; // a weak reference (-weakRetain)
    // The function's name, read once: the finalizer's description must not run JS code. nullopt
    // for an anonymous function.
    std::optional<std::string> _functionName;

    JSValue _jsSelf = JS_UNDEFINED; // The JS Timer object proxy for this OOJSTimer. Not owned (it owns us); cleared when finalized.
};

} // namespace cxx

void InitOOJSTimer(JSContext* context, JSValueConst global);

// Transitional: the Objective-C OOJSTimer facade. Deleted, with namespace cxx above, by the
// bridge's deletion bead.
#import "OOJSTimer+ObjCBridge.h"

#endif // OOJSTIMER_H
