/*

OOColor+ObjCBridge.mm

TRANSITIONAL (proposed ADR-0056, bead oo-11m): the Objective-C OOColor facade over cxx::OOColor.
Every method forwards to its C++ member: arguments that were OOColor * go through oo::ToCxx,
results that were OOColor * come back through oo::ToObjC. Deleted with OOColor+ObjCBridge.h.

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

#import "OOColor.h"

#include "oofnd/objc/OOObjCPeer.h"

namespace {

// Never destroyed: a facade may be released while the process exits.
oo::ObjCPeers& Peers()
{
    static oo::ObjCPeers* peers = new oo::ObjCPeers;
    return *peers;
}

} // namespace

@interface OOColor (OOObjCBridgePrivate)

- (id)initWithCxxColor:(cxx::OOColor*)color;

@end

@implementation OOColor

// Inside the @implementation for the private ivar.
OOColor* oo::ToObjC(cxx::OOColor* color)
{
    return Peers().peerFor(color, [color] { return [[OOColor alloc] initWithCxxColor:color]; });
}

cxx::OOColor* oo::ToCxx(OOColor* color)
{
    if (color == nil)
        return nullptr;
    return color->_cxxColor.get();
}

- (id)initWithCxxColor:(cxx::OOColor*)color
{
    self = [super init];
    if (self != nil)
        _cxxColor = oo::Ref<cxx::OOColor>(color);
    return self;
}

- (void)dealloc
{
    Peers().forget(_cxxColor.get());
    [super dealloc];
}

- (id)copyWithZone:(OOZone*)zone
{
    // Copy is implemented as retain since OOColor is immutable.
    return [self retain];
}

+ (OOColor*)colorWithHue:(float)hue saturation:(float)saturation brightness:(float)brightness alpha:(float)alpha
{
    return oo::ToObjC(cxx::OOColor::colorWithHue(hue, saturation, brightness, alpha));
}

+ (OOColor*)colorWithRed:(float)red green:(float)green blue:(float)blue alpha:(float)alpha
{
    return oo::ToObjC(cxx::OOColor::colorWithRed(red, green, blue, alpha));
}

+ (OOColor*)colorWithWhite:(float)white alpha:(float)alpha
{
    return oo::ToObjC(cxx::OOColor::colorWithWhite(white, alpha));
}

+ (OOColor*)colorWithRGBAComponents:(OORGBAComponents)components
{
    return oo::ToObjC(cxx::OOColor::colorWithRGBAComponents(components));
}

+ (OOColor*)colorWithHSBAComponents:(OOHSBAComponents)components
{
    return oo::ToObjC(cxx::OOColor::colorWithHSBAComponents(components));
}

+ (OOColor*)cxx_colorWithDescription:(const oo::PList&)description
{
    return oo::ToObjC(cxx::OOColor::colorWithDescription(description));
}

+ (OOColor*)cxx_colorWithDescription:(const oo::PList&)description saturationFactor:(float)factor
{
    return oo::ToObjC(cxx::OOColor::colorWithDescription(description, factor));
}

+ (OOColor*)cxx_brightColorWithDescription:(const oo::PList&)description
{
    return oo::ToObjC(cxx::OOColor::brightColorWithDescription(description));
}

+ (OOColor*)cxx_colorFromString:(const std::string&)colorFloatString
{
    return oo::ToObjC(cxx::OOColor::colorFromString(colorFloatString));
}

+ (OOColor*)blackColor
{
    return oo::ToObjC(cxx::OOColor::blackColor());
}
+ (OOColor*)darkGrayColor
{
    return oo::ToObjC(cxx::OOColor::darkGrayColor());
}
+ (OOColor*)lightGrayColor
{
    return oo::ToObjC(cxx::OOColor::lightGrayColor());
}
+ (OOColor*)whiteColor
{
    return oo::ToObjC(cxx::OOColor::whiteColor());
}
+ (OOColor*)grayColor
{
    return oo::ToObjC(cxx::OOColor::grayColor());
}
+ (OOColor*)redColor
{
    return oo::ToObjC(cxx::OOColor::redColor());
}
+ (OOColor*)greenColor
{
    return oo::ToObjC(cxx::OOColor::greenColor());
}
+ (OOColor*)blueColor
{
    return oo::ToObjC(cxx::OOColor::blueColor());
}
+ (OOColor*)cyanColor
{
    return oo::ToObjC(cxx::OOColor::cyanColor());
}
+ (OOColor*)yellowColor
{
    return oo::ToObjC(cxx::OOColor::yellowColor());
}
+ (OOColor*)magentaColor
{
    return oo::ToObjC(cxx::OOColor::magentaColor());
}
+ (OOColor*)orangeColor
{
    return oo::ToObjC(cxx::OOColor::orangeColor());
}
+ (OOColor*)purpleColor
{
    return oo::ToObjC(cxx::OOColor::purpleColor());
}
+ (OOColor*)brownColor
{
    return oo::ToObjC(cxx::OOColor::brownColor());
}
+ (OOColor*)clearColor
{
    return oo::ToObjC(cxx::OOColor::clearColor());
}

- (OOColor*)blendedColorWithFraction:(float)fraction ofColor:(OOColor*)color
{
    return oo::ToObjC(_cxxColor->blendedColorWithFraction(fraction, oo::ToCxx(color)));
}

- (std::optional<std::string>)cxx_descriptionComponents
{
    return _cxxColor->descriptionComponents();
}

- (float)redComponent
{
    return _cxxColor->redComponent();
}
- (float)greenComponent
{
    return _cxxColor->greenComponent();
}
- (float)blueComponent
{
    return _cxxColor->blueComponent();
}

- (void)getRed:(float*)red green:(float*)green blue:(float*)blue alpha:(float*)alpha
{
    _cxxColor->getRed(red, green, blue, alpha);
}

- (OORGBAComponents)rgbaComponents
{
    return _cxxColor->rgbaComponents();
}
- (BOOL)isBlack
{
    return _cxxColor->isBlack();
}
- (BOOL)isWhite
{
    return _cxxColor->isWhite();
}
- (float)hueComponent
{
    return _cxxColor->hueComponent();
}
- (float)saturationComponent
{
    return _cxxColor->saturationComponent();
}
- (float)brightnessComponent
{
    return _cxxColor->brightnessComponent();
}

- (void)getHue:(float*)hue saturation:(float*)saturation brightness:(float*)brightness alpha:(float*)alpha
{
    _cxxColor->getHue(hue, saturation, brightness, alpha);
}

- (OOHSBAComponents)hsbaComponents
{
    return _cxxColor->hsbaComponents();
}
- (float)alphaComponent
{
    return _cxxColor->alphaComponent();
}

- (OOColor*)premultipliedColor
{
    return oo::ToObjC(_cxxColor->premultipliedColor());
}

- (OOColor*)colorWithBrightnessFactor:(float)factor
{
    return oo::ToObjC(_cxxColor->colorWithBrightnessFactor(factor));
}

- (std::vector<float>)cxx_normalizedArray
{
    return _cxxColor->normalizedArray();
}
- (std::optional<std::string>)cxx_rgbaDescription
{
    return _cxxColor->rgbaDescription();
}
- (std::optional<std::string>)cxx_hsbaDescription
{
    return _cxxColor->hsbaDescription();
}

@end
