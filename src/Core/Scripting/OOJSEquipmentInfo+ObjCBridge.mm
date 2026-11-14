/*

OOJSEquipmentInfo+ObjCBridge.mm

The Objective-C left over from OOJSEquipmentInfo.mm (bead oo-supk; proposed ADR-0056 amendments
oo-ppc, oo-ykoy, oo-bwrq and oo-6ia4 item 3): OOEquipmentType (OOJavaScriptExtensions), the
category through which the engine asks an equipment type's façade for its JS object and class name
by selector, and tells it that object is gone. Its methods stay methods of the façade, each
forwarding in one line to the C++ function in OOJSEquipmentInfo.mm that holds its old body, with
the façade's _jsSelf ivar, the type's JS object, passed by reference. Deleted by oo-9ht.102, once
the engine's object wrappers hold C++ objects (amendment oo-ppc, item 5) and the JS object lives in
the C++ equipment type; the façade's own deletion (oo-9ht.28) waits for it.

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

#import "OOEquipmentType.h"
#import "OOJSEquipmentInfo.h"

@implementation OOEquipmentType (OOJavaScriptExtensions)

- (JSValue)oo_jsValueInContext:(JSContext*)context
{
    return ::OOJSEquipmentInfoJSValueInContext(self, _jsSelf, context);
}

- (std::optional<std::string>)cxx_oo_jsClassName
{
    return ::OOJSEquipmentInfoJSClassName();
}

- (void)oo_clearJSSelf:(JSValueConst)selfVal
{
    ::OOJSEquipmentInfoClearJSSelf(_jsSelf, selfVal);
}

@end
