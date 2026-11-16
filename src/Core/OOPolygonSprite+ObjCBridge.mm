/*

OOPolygonSprite+ObjCBridge.mm

TRANSITIONAL (proposed ADR-0056, bead oo-4111): the Objective-C OOPolygonSprite facade over
cxx::OOPolygonSprite. Every method forwards to its C++ member. -initWithDataArray:outlineWidth:name:
makes and owns the C++ sprite and records the facade as its peer (ADR-0056 amendment oo-86ek), or
answers nil as before. Every facade is an OOGraphicsResetClient while it lives (amendment oo-4111).
Deleted with OOPolygonSprite+ObjCBridge.h.


Copyright (C) 2009-2013 Jens Ayton

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

*/

#import "OOGraphicsResetManager.h"
#import "OOPolygonSprite.h"

#include "oofnd/objc/OOObjCPeer.h"

namespace {

// Never destroyed: a facade may be released while the process exits.
oo::ObjCPeers& Peers()
{
    static oo::ObjCPeers* peers = new oo::ObjCPeers;
    return *peers;
}

} // namespace

@interface OOPolygonSprite (OOObjCBridgePrivate) <OOGraphicsResetClient>

- (id)initWithCxxSprite:(cxx::OOPolygonSprite*)sprite;

@end

@implementation OOPolygonSprite

// Inside the @implementation for the private ivar.
OOPolygonSprite* oo::ToObjC(cxx::OOPolygonSprite* sprite)
{
    return Peers().peerFor(sprite, [sprite] { return [[OOPolygonSprite alloc] initWithCxxSprite:sprite]; });
}

cxx::OOPolygonSprite* oo::ToCxx(OOPolygonSprite* sprite)
{
    if (sprite == nil)
        return nullptr;
    return sprite->_cxxSprite.get();
}

- (id)initWithCxxSprite:(cxx::OOPolygonSprite*)sprite
{
    self = [super init];
    if (self != nil) {
        _cxxSprite = oo::Ref<cxx::OOPolygonSprite>(sprite);
        [[OOGraphicsResetManager sharedManager] registerClient:self];
    }
    return self;
}

- (id)initWithDataArray:(const oo::PList&)dataArray outlineWidth:(GLfloat)outlineWidth name:(const std::string&)name
{
    oo::Ref<cxx::OOPolygonSprite> sprite = cxx::OOPolygonSprite::initWithDataArray(dataArray, outlineWidth, name);
    if (sprite.get() == nullptr) {
        [self release];
        return nil;
    }

    self = [super init];
    if (self == nil)
        return nil;

    _cxxSprite = std::move(sprite);
    @autoreleasepool {
        Peers().peerFor(_cxxSprite.get(), [self] { return [self retain]; });
    }
    [[OOGraphicsResetManager sharedManager] registerClient:self];
    return self;
}

- (void)dealloc
{
    [[OOGraphicsResetManager sharedManager] unregisterClient:self];
    Peers().forget(_cxxSprite.get());
    [super dealloc];
}

#ifndef NDEBUG
- (std::optional<std::string>)cxx_descriptionComponents
{
    return _cxxSprite->descriptionComponents();
}
#endif

- (void)drawFilled
{
    _cxxSprite->drawFilled();
}

- (void)drawOutline
{
    _cxxSprite->drawOutline();
}

- (void)resetGraphicsState
{
    _cxxSprite->resetGraphicsState();
}

@end
