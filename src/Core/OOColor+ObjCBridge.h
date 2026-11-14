/*

OOColor+ObjCBridge.h

TRANSITIONAL (proposed ADR-0056, bead oo-11m): the Objective-C OOColor, a facade over the C++
cxx::OOColor (OOColor.h), for callers that are not converted yet. Its interface is the one
OOColor.h declared before the conversion, copied exactly (same selectors, same types), so those
callers compile and behave unchanged; each method forwards to its C++ member. Imported as the
last line of OOColor.h; do not import it directly.

        a caller that is                       holds / passes                  crosses with
        -------------------------------------  ------------------------------  ----------------------------
        still Objective-C                      OOColor * (this facade)         nothing: messages as before
        converted (C++)                        oo::Ref<cxx::OOColor>, cxx::OOColor *
          handing a colour to Objective-C                                       oo::ToObjC(color)
          taking one from Objective-C                                           oo::ToCxx(objcColor)

oo::ToObjC gives the colour's one live facade (oo::ObjCPeers), so identity survives a round trip:
oo::ToObjC(oo::ToCxx(c)) == c. Never add to this file; converted code does not message the facade.
Deleted by its deletion bead once no file outside OOColor.* names the Objective-C OOColor.

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

#ifndef OOCOLOR_OBJCBRIDGE_H
#define OOCOLOR_OBJCBRIDGE_H

#import "OOFoundation.h"
#import "OOOpenGL.h"
#import "oofnd/objc/OOObject.h"

@interface OOColor : OOObject <OOCopying> {
@private
    oo::Ref<cxx::OOColor> _cxxColor;
}

+ (OOColor*)colorWithHue:(float)hue saturation:(float)saturation brightness:(float)brightness alpha:(float)alpha; // Note: hue in 0..1
+ (OOColor*)colorWithRed:(float)red green:(float)green blue:(float)blue alpha:(float)alpha;
+ (OOColor*)colorWithWhite:(float)white alpha:(float)alpha;
+ (OOColor*)colorWithRGBAComponents:(OORGBAComponents)components;
+ (OOColor*)colorWithHSBAComponents:(OOHSBAComponents)components; // Note: hue in 0..360

+ (OOColor*)cxx_colorWithDescription:(const oo::PList&)description;
+ (OOColor*)cxx_brightColorWithDescription:(const oo::PList&)description;
+ (OOColor*)cxx_colorWithDescription:(const oo::PList&)description saturationFactor:(float)factor;

+ (OOColor*)cxx_colorFromString:(const std::string&)colorFloatString;

+ (OOColor*)blackColor; // 0.0 white
+ (OOColor*)darkGrayColor; // 0.333 white
+ (OOColor*)lightGrayColor; // 0.667 white
+ (OOColor*)whiteColor; // 1.0 white
+ (OOColor*)grayColor; // 0.5 white
+ (OOColor*)redColor; // 1.0, 0.0, 0.0 RGB
+ (OOColor*)greenColor; // 0.0, 1.0, 0.0 RGB
+ (OOColor*)blueColor; // 0.0, 0.0, 1.0 RGB
+ (OOColor*)cyanColor; // 0.0, 1.0, 1.0 RGB
+ (OOColor*)yellowColor; // 1.0, 1.0, 0.0 RGB
+ (OOColor*)magentaColor; // 1.0, 0.0, 1.0 RGB
+ (OOColor*)orangeColor; // 1.0, 0.5, 0.0 RGB
+ (OOColor*)purpleColor; // 0.5, 0.0, 0.5 RGB
+ (OOColor*)brownColor; // 0.6, 0.4, 0.2 RGB
+ (OOColor*)clearColor; // 0.0 white, 0.0 alpha

- (OOColor*)blendedColorWithFraction:(float)fraction ofColor:(OOColor*)color;

- (float)redComponent;
- (float)greenComponent;
- (float)blueComponent;
- (void)getRed:(float*)red green:(float*)green blue:(float*)blue alpha:(float*)alpha;

- (OORGBAComponents)rgbaComponents;

- (BOOL)isBlack;
- (BOOL)isWhite;

- (float)hueComponent;
- (float)saturationComponent;
- (float)brightnessComponent;
- (void)getHue:(float*)hue saturation:(float*)saturation brightness:(float*)brightness alpha:(float*)alpha;

- (OOHSBAComponents)hsbaComponents;

- (float)alphaComponent;

- (OOColor*)premultipliedColor;

- (OOColor*)colorWithBrightnessFactor:(float)factor;

- (std::vector<float>)cxx_normalizedArray;

- (std::optional<std::string>)cxx_rgbaDescription;
- (std::optional<std::string>)cxx_hsbaDescription;

@end

namespace oo {

// The colour's Objective-C facade: its live one, else a new one; autoreleased. nil for null.
OOColor* ToObjC(cxx::OOColor* color);
inline OOColor* ToObjC(const Ref<cxx::OOColor>& color) { return ToObjC(color.get()); }

// The C++ colour behind a facade, borrowed (the facade retains it); null for nil.
cxx::OOColor* ToCxx(OOColor* color);

} // namespace oo

#endif // OOCOLOR_OBJCBRIDGE_H
