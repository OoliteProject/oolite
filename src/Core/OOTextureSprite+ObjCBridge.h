/*

OOTextureSprite+ObjCBridge.h

TRANSITIONAL (proposed ADR-0056, bead oo-ljhc): the Objective-C OOTextureSprite, a facade over the
C++ cxx::OOTextureSprite (OOTextureSprite.h), for callers that are not converted yet: GuiDisplayGen
makes and keeps its background and foreground sprites through it, and HeadUpDisplay its legend
sprites. Its interface is the one OOTextureSprite.h declared before the conversion, copied exactly
(same selectors, same types), so those callers compile and behave unchanged; each method forwards
to its C++ member. Imported as the last line of OOTextureSprite.h; do not import it directly.

oo::ToObjC gives the sprite's one live facade (oo::ObjCPeers), so identity survives a round trip;
a facade made by -initWithTexture: is that peer. Deleted, with namespace cxx in OOTextureSprite.h,
by the bridge's deletion bead once GuiDisplayGen and HeadUpDisplay are C++.

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

#ifndef OOTEXTURESPRITE_OBJCBRIDGE_H
#define OOTEXTURESPRITE_OBJCBRIDGE_H

#import "OOFoundation.h"
#import "oofnd/objc/OOObject.h"

@interface OOTextureSprite : OOObject {
@private
    oo::Ref<cxx::OOTextureSprite> _cxxSprite;
}

- (id)initWithTexture:(OOTexture*)texture;
- (id)initWithTexture:(OOTexture*)texture size:(NSSize)spriteSize;

- (NSSize)size;

- (void)blitToX:(float)x Y:(float)y Z:(float)z alpha:(float)a;
- (void)blitCentredToX:(float)x Y:(float)y Z:(float)z alpha:(float)a;
- (void)blitBackgroundCentredToX:(float)x Y:(float)y Z:(float)z alpha:(float)a;

@end

namespace oo {

// The sprite's Objective-C facade: its live one, else a new one; autoreleased. nil for null.
OOTextureSprite* ToObjC(cxx::OOTextureSprite* sprite);
inline OOTextureSprite* ToObjC(const Ref<cxx::OOTextureSprite>& sprite) { return ToObjC(sprite.get()); }

// The C++ sprite behind a facade, borrowed (the facade retains it); null for nil.
cxx::OOTextureSprite* ToCxx(OOTextureSprite* sprite);

} // namespace oo

#endif // OOTEXTURESPRITE_OBJCBRIDGE_H
