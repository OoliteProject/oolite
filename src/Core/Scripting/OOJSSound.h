/*

OOJSSound.h (QuickJS-ng)

JavaScript sound object.

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

#include <optional>
#include <string>

@class OOSound;

void InitOOJSSound(JSContext* context, JSValueConst global);

/*	SoundFromJSValue()

        Convert a JS value to a sound. The value may be either a Sound object or a
        string specifying a sound name.
 */
OOSound* SoundFromJSValue(JSContext* context, JSValueConst value);

/*	The bodies of OOSound (OOJavaScriptExtentions), which the engine reaches by selector. Its
        methods are one-line forwarders to these in OOJSSound+ObjCBridge.mm until OOSound converts
        (proposed ADR-0056 amendments oo-ppc and oo-ykoy). OOJSSoundJSValueInContext returns a new
        Sound object owned by the caller (JS null for none).
*/
JSValue OOJSSoundJSValueInContext(OOSound* sound, JSContext* context);
std::optional<std::string> OOJSSoundJSDescription(OOSound* sound);
std::optional<std::string> OOJSSoundJSClassName(void);
