/*

OOJSSoundSource.h (QuickJS-ng)

JavaScript sound source object.

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

#import "OOFoundation.h"
#include <quickjs.h>

#include <optional>
#include <string>

@class OOSoundSource;

void InitOOJSSoundSource(JSContext* context, JSValueConst global);

/*	The bodies of OOSoundSource (OOJavaScriptExtentions), which the engine reaches by selector.
        Its methods are one-line forwarders to these in OOJSSoundSource+ObjCBridge.mm until
        OOSoundSource converts (proposed ADR-0056 amendments oo-ppc and oo-ykoy).
        OOJSSoundSourceJSValueInContext returns a new SoundSource object owned by the caller (JS
        null for none).
*/
JSValue OOJSSoundSourceJSValueInContext(OOSoundSource* source, JSContext* context);
std::optional<std::string> OOJSSoundSourceJSClassName(void);
