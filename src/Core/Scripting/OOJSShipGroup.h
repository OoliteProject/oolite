/*

OOJSShipGroup.h (QuickJS-ng)

JavaScript wrapper for ship group objects.


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

#include <quickjs.h>

#import "OOFoundation.h"
@class OOShipGroup;

void InitOOJSShipGroup(JSContext* context, JSValueConst global);

/*	The bodies of OOShipGroup (OOJavaScriptExtensions), which the engine reaches by selector. Its
        methods are one-line forwarders to these in OOJSShipGroup+ObjCBridge.mm, which pass the façade's
        _jsSelf ivar by reference, until the façade goes (proposed ADR-0056 amendments oo-ppc, oo-ykoy
        and oo-bwrq).
*/
JSValue OOJSShipGroupJSValueInContext(OOShipGroup* group, JSValue& jsSelf, JSContext* context);
void OOJSShipGroupClearJSSelf(JSValue& jsSelf, JSValueConst selfVal);
