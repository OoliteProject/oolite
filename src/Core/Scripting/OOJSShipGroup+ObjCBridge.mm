/*

OOJSShipGroup+ObjCBridge.mm

The Objective-C left over from OOJSShipGroup.mm (bead oo-n64m; proposed ADR-0056 amendments oo-ppc,
oo-ykoy and oo-bwrq): OOShipGroup (OOJavaScriptExtensions), the category through which the engine
asks a group's façade for its JS object by selector, and tells it that object is gone. Its methods
stay methods of the façade, each forwarding in one line to the C++ function in OOJSShipGroup.mm
that holds its old body, with the façade's _jsSelf ivar, the group's JS object, passed by
reference. Deleted with the façade (oo-9ht.19), once the engine's object wrappers hold C++ objects
(amendment oo-ppc, item 5) and the JS object lives in the C++ group.

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

#import "OOJSShipGroup.h"
#import "OOShipGroup.h"

@implementation OOShipGroup (OOJavaScriptExtensions)

- (JSValue)oo_jsValueInContext:(JSContext*)context
{
    return ::OOJSShipGroupJSValueInContext(self, _jsSelf, context);
}

- (void)oo_clearJSSelf:(JSValueConst)selfVal
{
    ::OOJSShipGroupClearJSSelf(_jsSelf, selfVal);
}

@end
