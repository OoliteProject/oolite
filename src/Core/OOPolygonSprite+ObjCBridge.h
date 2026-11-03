/*

OOPolygonSprite+ObjCBridge.h

TRANSITIONAL (proposed ADR-0056, bead oo-4111): the Objective-C OOPolygonSprite, a facade over the
C++ cxx::OOPolygonSprite (OOPolygonSprite.h), for callers that are not converted yet (the HUD's
missile icons, and the beacon icons of ShipEntity, OOVisualEffectEntity and OOWaypointEntity). Its
interface is the one OOPolygonSprite.h declared before the conversion, copied exactly (same
selectors, same types, and the HUD's OOHUDBeaconIcon category), so those callers compile and
behave unchanged; each method forwards to its C++ member. Imported as the last line of
OOPolygonSprite.h; do not import it directly.

The facade is also the sprite's OOGraphicsResetClient: the manager holds Objective-C clients,
unretained, so each facade registers itself while it lives and forwards -resetGraphicsState
(ADR-0056 amendment oo-4111). Converted code that makes a sprite keeps its facade alive while it
draws it, until OOGraphicsResetManager is C++.

        a caller that is                       holds / passes                  crosses with
        -------------------------------------  ------------------------------  ----------------------------
        still Objective-C                      OOPolygonSprite * (this facade) nothing: messages as before
        converted (C++)                        oo::Ref<cxx::OOPolygonSprite>, cxx::OOPolygonSprite *
          handing a sprite to Objective-C                                       oo::ToObjC(sprite)
          taking one from Objective-C                                           oo::ToCxx(objcSprite)

oo::ToObjC gives the sprite's one live facade (oo::ObjCPeers), so identity survives a round trip.
Never add to this file; converted code does not message the facade. Deleted by its deletion bead
once no file outside OOPolygonSprite.* names the Objective-C OOPolygonSprite.


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

#ifndef OOPOLYGONSPRITE_OBJCBRIDGE_H
#define OOPOLYGONSPRITE_OBJCBRIDGE_H

#import "OOFoundation.h"
#import "oofnd/objc/OOObject.h"

@interface OOPolygonSprite : OOObject {
@private
    oo::Ref<cxx::OOPolygonSprite> _cxxSprite;
}

/*	DataArray is either an array of pairs of numbers, or an array of such
        arrays (representing one or more contours), as property-list data.
        OutlineWidth is the width of the tesselated outline, in the same scale as
        the vertices.
        Name is used for debugging only.
*/
- (id)initWithDataArray:(const oo::PList&)dataArray outlineWidth:(GLfloat)outlineWidth name:(const std::string&)name;

- (void)drawFilled;
- (void)drawOutline;

@end

#import "HeadUpDisplay.h"

@interface OOPolygonSprite (OOHUDBeaconIcon) <OOHUDBeaconIcon>
@end

namespace oo {

// The sprite's Objective-C facade: its live one, else a new one; autoreleased. nil for null.
OOPolygonSprite* ToObjC(cxx::OOPolygonSprite* sprite);
inline OOPolygonSprite* ToObjC(const Ref<cxx::OOPolygonSprite>& sprite) { return ToObjC(sprite.get()); }

// The C++ sprite behind a facade, borrowed (the facade retains it); null for nil.
cxx::OOPolygonSprite* ToCxx(OOPolygonSprite* sprite);

} // namespace oo

#endif // OOPOLYGONSPRITE_OBJCBRIDGE_H
