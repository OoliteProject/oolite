/*

OOJSSound.h

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

#include "OOCocoa.h"
#include "ooscript/JSEngine.hpp"
#include "oofnd/Ref.hpp"
#include "OOJSPrivateObject.h"
class OOSound;	// C++ since bead oo-9ht.68 deleted its facade


#ifdef __cplusplus
extern "C" {
#endif

void InitOOJSSound(ooscript::Context context, ooscript::Object global);


/*	SoundFromJSValue()
	
	Convert a JS value to a sound. The value may be either a Sound object or a
	string specifying a sound name.
 */
OOSound *SoundFromJSValue(ooscript::Context context, ooscript::Value value);

#ifdef __cplusplus
}
#endif


/*	The bodies of OOSound (OOJavaScriptExtentions), which the engine reached by selector until bead
	oo-9ht.68 deleted the sound's facade (and the Scripting bridge file, which held the category's
	forwarders): a new Sound object for the sound (JS null for none), its toString() text and its
	JS class name. The binding and the SoundSource binding call them.
*/
ooscript::Value OOJSSoundJSValueInContext(OOSound *sound, ooscript::Context context);
std::optional<std::string> OOJSSoundJSDescription(OOSound *sound);
std::optional<std::string> OOJSSoundJSClassName(void);


/*	What a Sound object's private slot holds (bead oo-9ht.68: it held the sound's facade, retained).
	-oo_jsValueInContext: made a new Sound object each time, so each object has its own holder,
	which retains the sound; the slot retains the holder (OOJSSetCxxPrivate) and the finalizer
	releases it (OOJSCxxObjectWrapperFinalize). Its toString() is the sound's (ADR-0056 amendment
	oo-9ht.68 item 2). Defined in OOJSSound.mm; only the binding makes one.
*/
class OOJSSoundHolder final : public oo::RefCounted, public OOJSPrivateObject
{
public:
	explicit OOJSSoundHolder(OOSound *inSound);
	~OOJSSoundHolder() override;

	OOSound *sound() const;

	ooscript::Value jsValueInContext(ooscript::Context context) override;
	void clearJSSelf(ooscript::Object selfVal) override;
	std::optional<std::string> jsDescription() override;

private:
	oo::Ref<OOSound>	_sound;
};
