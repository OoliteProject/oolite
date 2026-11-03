/*

OOTextureSprite+ObjCBridge.mm

TRANSITIONAL (proposed ADR-0056, bead oo-ljhc): the Objective-C OOTextureSprite facade. See
OOTextureSprite+ObjCBridge.h.

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

#import "OOTextureSprite.h"

#include "oofnd/objc/OOObjCPeer.h"

namespace {

// Never destroyed: a facade may be released while the process exits.
oo::ObjCPeers& Peers()
{
    static oo::ObjCPeers* peers = new oo::ObjCPeers;
    return *peers;
}

} // namespace

@interface OOTextureSprite (OOObjCBridgePrivate)

- (id)initWithCxxSprite:(cxx::OOTextureSprite*)sprite;
- (id)initWithNewCxxSprite:(const oo::Ref<cxx::OOTextureSprite>&)sprite;

@end

@implementation OOTextureSprite

// Inside the @implementation for the private ivar.
OOTextureSprite* oo::ToObjC(cxx::OOTextureSprite* sprite)
{
    return Peers().peerFor(sprite, [sprite] { return [[OOTextureSprite alloc] initWithCxxSprite:sprite]; });
}

cxx::OOTextureSprite* oo::ToCxx(OOTextureSprite* sprite)
{
    if (sprite == nil)
        return nullptr;
    return sprite->_cxxSprite.get();
}

- (id)initWithCxxSprite:(cxx::OOTextureSprite*)sprite
{
    self = [super init];
    if (self != nil)
        _cxxSprite = oo::Ref<cxx::OOTextureSprite>(sprite);
    return self;
}

// An initialiser's C++ sprite, made before the facade: the facade is its peer, and nil (no
// texture) answers nil, as the initialiser did.
- (id)initWithNewCxxSprite:(const oo::Ref<cxx::OOTextureSprite>&)sprite
{
    if (sprite.get() == nullptr) {
        [self release];
        return nil;
    }

    self = [self initWithCxxSprite:sprite.get()];
    if (self != nil) {
        @autoreleasepool {
            Peers().peerFor(sprite.get(), [self] { return [self retain]; });
        }
    }
    return self;
}

- (id)initWithTexture:(OOTexture*)texture
{
    return [self initWithNewCxxSprite:cxx::OOTextureSprite::initWithTexture(texture)];
}

- (id)initWithTexture:(OOTexture*)texture size:(NSSize)spriteSize
{
    return [self initWithNewCxxSprite:cxx::OOTextureSprite::initWithTexture(texture, spriteSize)];
}

- (void)dealloc
{
    Peers().forget(_cxxSprite.get());
    [super dealloc];
}

- (NSSize)size
{
    return _cxxSprite->getSize();
}

- (void)blitToX:(float)x Y:(float)y Z:(float)z alpha:(float)a
{
    _cxxSprite->blitToX(x, y, z, a);
}

- (void)blitCentredToX:(float)x Y:(float)y Z:(float)z alpha:(float)a
{
    _cxxSprite->blitCentredToX(x, y, z, a);
}

- (void)blitBackgroundCentredToX:(float)x Y:(float)y Z:(float)z alpha:(float)a
{
    _cxxSprite->blitBackgroundCentredToX(x, y, z, a);
}

@end
