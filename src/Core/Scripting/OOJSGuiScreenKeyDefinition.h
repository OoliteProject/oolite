/*

OOJSGuiScreenKeyDefinition.h (QuickJS-ng)

C++20 since bead oo-xg7g (proposed ADR-0056, the OOColor house style). Its superclass,
OOWeakRefObject, is still Objective-C (the weak-reference support that OOWeakReference+ObjCBridge
keeps), so the class is cxx::OOJSGuiScreenKeyDefinition holding only its own ivars and methods, and
OOJSGuiScreenKeyDefinition+ObjCBridge.h, imported at the end of this header, keeps the Objective-C
OOJSGuiScreenKeyDefinition : OOWeakRefObject that the JS player object makes and PlayerEntity keeps and messages
(ADR-0056 amendment oo-o89). The bridge's deletion bead waits for OOWeakRefObject's retirement.


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

#ifndef OOJSGUISCREENKEYDEFINITION_H
#define OOJSGUISCREENKEYDEFINITION_H

#import "OOFoundation.h"
#include <quickjs.h>

#include "oofnd/PList.hpp"
#include "oofnd/StdLib.hpp"

#include "oofnd/Ref.hpp"
#include "oofnd/objc/OOObjCRef.h"
#include <optional>
#include <string>

@class OOJSScript; // imported by the .mm, so that a test can stand in for it (ADR-0056 amendment oo-fg7i item 5)

namespace cxx {

/*	The definition owns references to its callback and callbackThis, which are
        released on destruction and when the JavaScript engine is reset.
*/
class OOJSGuiScreenKeyDefinition : public oo::RefCounted {
public:
    // The old -init after [super init]. Made only by the facade (amendment oo-o89 item 2), until
    // OOWeakRefObject is retired.
    OOJSGuiScreenKeyDefinition();
    ~OOJSGuiScreenKeyDefinition() override;

    std::optional<std::string> name(); // nullopt until set (bead oo-3rb.289.7)
    void setName(const std::optional<std::string>& name);
    oo::PList registerKeys();
    void setRegisterKeys(const oo::PList& registerKeys);
    // Returned values are owned by the caller.
    JSValue callback();
    void setCallback(JSValueConst callback);
    JSValue callbackThis();
    void setCallbackThis(JSValueConst callbackthis);

    void runCallback(const std::string& key);

    OOComparisonResult interfaceCompare(OOJSGuiScreenKeyDefinition* other);

private:
    void deleteJSPointers();

    JSValue _callback = JS_UNDEFINED; // Owned.
    JSValue _callbackThis = JS_UNDEFINED; // Owned.
    oo::ObjCRef<::OOJSScript*> _owningScript; // a weak reference (-weakRetain)

    std::optional<std::string> _name; // nullopt until set (was nil)
    oo::PList _registerKeys; // key name -> key definitions; null until set (was nil)
};

} // namespace cxx

// Transitional: the Objective-C OOJSGuiScreenKeyDefinition, for callers not yet converted. Deleted,
// with namespace cxx above, by the bridge's deletion bead.
#import "OOJSGuiScreenKeyDefinition+ObjCBridge.h"

#endif // OOJSGUISCREENKEYDEFINITION_H
