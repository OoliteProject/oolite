/*

OOJSSoundSource.h

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

#pragma once

#include "OOCocoa.h"
#include "ooscript/JSEngine.hpp"
#include "oofnd/Ref.hpp"
#include "OOJSPrivateObject.h"
class OOSoundSource;	// C++ since bead oo-9ht.88 deleted its facade


#ifdef __cplusplus
extern "C" {
#endif

void InitOOJSSoundSource(ooscript::Context context, ooscript::Object global);

#ifdef __cplusplus
}
#endif


/*	The bodies of OOSoundSource (OOJavaScriptExtentions), which the engine reached by selector
	until bead oo-9ht.88 deleted the source's facade (and the Scripting bridge file, which held
	the category's forwarders): a new SoundSource object for the source (JS null for none) and the
	JS class name. The binding and the Sound binding call them.
*/
ooscript::Value OOJSSoundSourceJSValueInContext(OOSoundSource *source, ooscript::Context context);
std::optional<std::string> OOJSSoundSourceJSClassName(void);


/*	What a SoundSource object's private slot holds (bead oo-9ht.88: it held the source's facade,
	retained). -oo_jsValueInContext: made a new SoundSource object each time, so each object has its
	own holder, which retains the source; the slot retains the holder (OOJSSetCxxPrivate) and the
	finalizer releases it (OOJSCxxObjectWrapperFinalize). Its toString() is what the facade's
	-cxx_oo_jsDescription answered (OOObject (OOJavaScriptConversion)): the JS class name and the
	source's components (ADR-0056 amendment oo-9ht.68 item 2). Defined in OOJSSoundSource.mm; only
	the binding makes one.
*/
class OOJSSoundSourceHolder final : public oo::RefCounted, public OOJSPrivateObject
{
public:
	explicit OOJSSoundSourceHolder(OOSoundSource *inSource);
	~OOJSSoundSourceHolder() override;

	OOSoundSource *source() const;

	ooscript::Value jsValueInContext(ooscript::Context context) override;
	void clearJSSelf(ooscript::Object selfVal) override;
	std::optional<std::string> jsDescription() override;

private:
	oo::Ref<OOSoundSource>	_source;
};
