/*

OOJSGuiScreenKeyDefinition.h (QuickJS-ng)


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

#import "OOJSScript.h"
#include <quickjs.h>

#include "oofnd/PList.hpp"
#include "oofnd/StdLib.hpp"

/*	The definition owns references to its callback and callbackThis, which are
        released on dealloc and when the JavaScript engine is reset.
*/
@interface OOJSGuiScreenKeyDefinition : OOWeakRefObject {
@private
    JSValue _callback; // Owned.
    JSValue _callbackThis; // Owned.
    OOJSScript* _owningScript;

    std::optional<std::string> _name; // nullopt until set (was nil)
    oo::PList _registerKeys; // key name -> key definitions; null until set (was nil)
}

- (std::optional<std::string>)cxx_name; // nullopt until set (bead oo-3rb.289.7)
- (void)cxx_setName:(const std::optional<std::string>&)name;
- (oo::PList)registerKeys;
- (void)setRegisterKeys:(const oo::PList&)registerKeys;
// Returned values are owned by the caller.
- (JSValue)callback;
- (void)setCallback:(JSValueConst)callback;
- (JSValue)callbackThis;
- (void)setCallbackThis:(JSValueConst)callbackthis;

- (void)runCallback:(const std::string&)key;

- (OOComparisonResult)interfaceCompare:(OOJSGuiScreenKeyDefinition*)other;

@end
