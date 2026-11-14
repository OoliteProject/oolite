/*

OOJSWaypoint.h (QuickJS-ng)

JavaScript proxy for OOWaypointEntities.

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

#import "OOFoundation.h"
#include <quickjs.h>

@class OOWaypointEntity;

void InitOOJSWaypoint(JSContext* context, JSValueConst global);

JSClassID JSWaypointClassID(void);

/*	The bodies of OOWaypointEntity (OOJavaScriptExtensions), which the engine reaches by selector.
        Its methods are one-line forwarders to these on the OOWaypointEntity facade, in
        OOWaypointEntity+ObjCBridge.mm (bead oo-9ht.50), until that facade goes (oo-9ht.108; proposed
        ADR-0056 amendments oo-ppc, oo-ykoy and oo-6ia4). Its -oo_jsClassID answers
        JSWaypointClassID().
*/
std::optional<std::string> OOJSWaypointJSClassName(void);
bool OOJSWaypointIsVisibleToScripts(void);
