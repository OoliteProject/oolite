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
#include "OOFoundation.h"
#include <quickjs.h>

#include <optional>
#include <string>

#include "OOJSPrivateObject.h"
#include "oofnd/Ref.hpp"

class OOSound; // C++: it has no Objective-C facade

void InitOOJSSound(JSContext* context, JSValueConst global);

/*	SoundFromJSValue()

        Convert a JS value to a sound. The value may be either a Sound object or a
        string specifying a sound name.
 */
OOSound* SoundFromJSValue(JSContext* context, JSValueConst value);

/*	The bodies of OOSound (OOJavaScriptExtentions), which the engine reached by selector while the
        sound had an Objective-C facade: a new Sound object for the sound (owned by the caller; JS
        null for none), its toString() text and its JS class name. The binding and the SoundSource
        binding call them.
*/
JSValue OOJSSoundJSValueInContext(OOSound* sound, JSContext* context);
std::optional<std::string> OOJSSoundJSDescription(OOSound* sound);
std::optional<std::string> OOJSSoundJSClassName(void);

/*	What a Sound object's private slot holds (it held the sound's facade, retained).
        -oo_jsValueInContext: made a new Sound object each time, so each object has its own holder,
        which retains the sound; the slot retains the holder (OOJSSetCxxPrivate) and the finalizer
        releases it (OOJSCxxObjectWrapperFinalize). Its toString() is the sound's. Defined in
        OOJSSound.mm; only the binding makes one.
*/
class OOJSSoundHolder final : public oo::RefCounted, public OOJSPrivateObject {
public:
    explicit OOJSSoundHolder(OOSound* inSound);
    ~OOJSSoundHolder() override;

    OOSound* sound() const;

    JSValue jsValueInContext(JSContext* context) override; // owned
    void clearJSSelf(JSValueConst selfVal) override;
    std::optional<std::string> jsDescription() override;

private:
    oo::Ref<OOSound> _sound;
};
