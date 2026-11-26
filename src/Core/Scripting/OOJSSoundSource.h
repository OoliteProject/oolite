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

#pragma once

#include <quickjs.h>

#include <optional>
#include <string>

#include "OOFoundation.h"
#include "OOJSPrivateObject.h"
#include "oofnd/Ref.hpp"

class OOSoundSource;

void InitOOJSSoundSource(JSContext* context, JSValueConst global);

/*	The bodies of OOSoundSource (OOJavaScriptExtentions): a new SoundSource
   object for the source (owned by the caller; JS null for none) and the JS
   class name. The binding and the Sound binding call them.
*/
JSValue OOJSSoundSourceJSValueInContext(OOSoundSource* source,
                                        JSContext* context);
std::optional<std::string> OOJSSoundSourceJSClassName(void);

/*	What a SoundSource object's private slot holds. Each SoundSource object
   has its own holder, which retains the source; the slot retains the holder
   (OOJSSetCxxPrivate) and the finalizer releases it
   (OOJSCxxObjectWrapperFinalize). Its toString() is the JS class name and the
   source's components. Defined in OOJSSoundSource.mm; only the binding makes
   one.
*/
class OOJSSoundSourceHolder final : public oo::RefCounted,
                                    public OOJSPrivateObject {
 public:
  explicit OOJSSoundSourceHolder(OOSoundSource* inSource);
  ~OOJSSoundSourceHolder() override;

  OOSoundSource* source() const;

  JSValue jsValueInContext(JSContext* context) override;  // owned
  void clearJSSelf(JSValueConst selfVal) override;
  std::optional<std::string> jsDescription() override;

 private:
  oo::Ref<OOSoundSource> _source;
};
