/*

OOColor.m

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
#import "OOFoundationBridge.h"
#import "OOMaths.h"
#import "OOObjCPList.h"
#include "oofnd/objc/OORuntime.h"

#include "oofnd/Scanner.hpp"
#include "oofnd/String.hpp"
#include "oofnd/objc/OOAssert.h"

@implementation OOColor

// Set methods are internal, because OOColor is immutable (as seen from outside).
- (void)setRed:(float)r green:(float)g blue:(float)b alpha:(float)a
{
    rgba[0] = r;
    rgba[1] = g;
    rgba[2] = b;
    rgba[3] = a;
}

- (void)setHue:(float)h saturation:(float)s brightness:(float)b alpha:(float)a
{
    rgba[3] = a;
    if (s == 0.0f) {
        rgba[0] = rgba[1] = rgba[2] = b;
        return;
    }
    float f, p, q, t;
    int i;
    h = fmod(h, 360.0f);
    if (h < 0.0)
        h += 360.0f;
    h /= 60.0f;

    i = floor(h);
    f = h - i;
    p = b * (1.0f - s);
    q = b * (1.0f - (s * f));
    t = b * (1.0f - (s * (1.0f - f)));

    switch (i) {
    case 0:
        rgba[0] = b;
        rgba[1] = t;
        rgba[2] = p;
        break;
    case 1:
        rgba[0] = q;
        rgba[1] = b;
        rgba[2] = p;
        break;
    case 2:
        rgba[0] = p;
        rgba[1] = b;
        rgba[2] = t;
        break;
    case 3:
        rgba[0] = p;
        rgba[1] = q;
        rgba[2] = b;
        break;
    case 4:
        rgba[0] = t;
        rgba[1] = p;
        rgba[2] = b;
        break;
    case 5:
        rgba[0] = b;
        rgba[1] = p;
        rgba[2] = q;
        break;
    }
}

- (id)copyWithZone:(OOZone*)zone
{
    // Copy is implemented as retain since OOColor is immutable.
    return [self retain];
}

+ (OOColor*)colorWithHue:(float)hue saturation:(float)saturation brightness:(float)brightness alpha:(float)alpha
{
    OOColor* result = [[OOColor alloc] init];
    [result setHue:360.0f * hue saturation:saturation brightness:brightness alpha:alpha];
    return [result autorelease];
}

+ (OOColor*)colorWithRed:(float)red green:(float)green blue:(float)blue alpha:(float)alpha
{
    OOColor* result = [[OOColor alloc] init];
    [result setRed:red green:green blue:blue alpha:alpha];
    return [result autorelease];
}

+ (OOColor*)colorWithWhite:(float)white alpha:(float)alpha
{
    return [OOColor colorWithRed:white green:white blue:white alpha:alpha];
}

+ (OOColor*)colorWithRGBAComponents:(OORGBAComponents)components
{
    return [self colorWithRed:components.r
                        green:components.g
                         blue:components.b
                        alpha:components.a];
}

+ (OOColor*)colorWithHSBAComponents:(OOHSBAComponents)components
{
    return [self colorWithHue:components.h / 360.0f
                   saturation:components.s
                   brightness:components.b
                        alpha:components.a];
}

+ (OOColor*)cxx_colorWithDescription:(const oo::PList&)description
{
    return [self cxx_colorWithDescription:description saturationFactor:1.0f];
}

+ (OOColor*)cxx_colorWithDescription:(const oo::PList&)description saturationFactor:(float)factor
{
    OOColor* result = nil;

    if (description.isNull())
        return nil;

    if (description.type() == oo::PList::Type::Object) {
        id object = oo::ObjectIn(description);
        if ([object isKindOfClass:[OOColor class]])
            result = [[object copy] autorelease];
    } else if (const std::string* string = description.getIf<std::string>()) {
        if (string->ends_with("Color")) {
            // +fooColor selector
            SEL selector = OOSelectorFromName(string->c_str());
            if ([self respondsToSelector:selector])
                result = [self performSelector:selector];
        } else {
            // Some other string
            result = [self cxx_colorFromString:*string];
        }
    } else if (const oo::PList::Array* array = description.getIf<oo::PList::Array>()) {
        // The components' descriptions joined with spaces (-componentsJoinedByString:@" ").
        std::string components;
        bool first = true;
        for (const oo::PList& element : *array) {
            if (element.isNull())
                continue; // not an element of the Foundation array
            if (!first)
                components += ' ';
            components += oo::DescriptionOf(element);
            first = false;
        }
        result = [self cxx_colorFromString:components];
    } else if (description.isDict()) {
        const oo::PList* hue = description.find("hue");
        if (hue != nullptr && !hue->isNull()) {
            // Treat as HSB(A) dictionary
            float h = description.get<float>("hue");
            float s = description.get<float>("saturation", 1.0f);
            float b = description.get<float>("brightness", -1.0f);
            if (b < 0.0f)
                b = description.get<float>("value", 1.0f);
            float a = description.get<float>("alpha", -1.0f);
            if (a < 0.0f)
                a = description.get<float>("opacity", 1.0f);

            // Not "result =", because we handle the saturation scaling here to allow oversaturation.
            return [OOColor colorWithHue:h / 360.0f saturation:s * factor brightness:b alpha:a];
        } else {
            // Treat as RGB(A) dictionary
            float r = description.get<float>("red");
            float g = description.get<float>("green");
            float b = description.get<float>("blue");
            float a = description.get<float>("alpha", -1.0f);
            if (a < 0.0f)
                a = description.get<float>("opacity", 1.0f);

            result = [OOColor colorWithRed:r green:g blue:b alpha:a];
        }
    }

    if (factor != 1.0f && result != nil) {
        float h, s, b, a;
        [result getHue:&h saturation:&s brightness:&b alpha:&a];
        h *= 1.0 / 360.0f; // See note in header.
        s *= factor;
        result = [self colorWithHue:h saturation:s brightness:b alpha:a];
    }

    return result;
}

+ (OOColor*)cxx_brightColorWithDescription:(const oo::PList&)description
{
    OOColor* color = [OOColor cxx_colorWithDescription:description];
    if (color == nil || 0.5f <= [color brightnessComponent])
        return color;

    return [OOColor colorWithHue:[color hueComponent] / 360.0f saturation:[color saturationComponent] brightness:0.5f alpha:1.0f];
}

+ (OOColor*)colorWithDescription:(id)description
{
    return [self cxx_colorWithDescription:oo::PListFrom(description)];
}

+ (OOColor*)colorWithDescription:(id)description saturationFactor:(float)factor
{
    return [self cxx_colorWithDescription:oo::PListFrom(description) saturationFactor:factor];
}

+ (OOColor*)brightColorWithDescription:(id)description
{
    return [self cxx_brightColorWithDescription:oo::PListFrom(description)];
}

+ (OOColor*)cxx_colorFromString:(const std::string&)colorFloatString
{
    float rgbaValue[4] = { 0.0f, 0.0f, 0.0f, 1.0f };
    oo::str::Scanner scanner(colorFloatString);
    float factor = 1.0f;
    int i;

    for (i = 0; i != 4; ++i) {
        if (!scanner.scanFloat(&rgbaValue[i])) {
            // Less than three floats or non-float, can't parse -> quit
            if (i < 3)
                return nil;

            // If we get here, we only got three components. Make sure alpha is at correct scale:
            rgbaValue[3] /= factor;
        }
        if (1.0f < rgbaValue[i])
            factor = 1.0f / 255.0f;
    }

    return [OOColor colorWithRed:rgbaValue[0] * factor green:rgbaValue[1] * factor blue:rgbaValue[2] * factor alpha:rgbaValue[3] * factor];
}

+ (OOColor*)blackColor // 0.0 white
{
    return [OOColor colorWithWhite:0.0f alpha:1.0f];
}

+ (OOColor*)darkGrayColor // 0.333 white
{
    return [OOColor colorWithWhite:1.0f / 3.0f alpha:1.0f];
}

+ (OOColor*)lightGrayColor // 0.667 white
{
    return [OOColor colorWithWhite:2.0f / 3.0f alpha:1.0f];
}

+ (OOColor*)whiteColor // 1.0 white
{
    return [OOColor colorWithWhite:1.0f alpha:1.0f];
}

+ (OOColor*)grayColor // 0.5 white
{
    return [OOColor colorWithWhite:0.5f alpha:1.0f];
}

+ (OOColor*)redColor // 1.0, 0.0, 0.0 RGB
{
    return [OOColor colorWithRed:1.0f green:0.0f blue:0.0f alpha:1.0f];
}

+ (OOColor*)greenColor // 0.0, 1.0, 0.0 RGB
{
    return [OOColor colorWithRed:0.0f green:1.0f blue:0.0f alpha:1.0f];
}

+ (OOColor*)blueColor // 0.0, 0.0, 1.0 RGB
{
    return [OOColor colorWithRed:0.0f green:0.0f blue:1.0f alpha:1.0f];
}

+ (OOColor*)cyanColor // 0.0, 1.0, 1.0 RGB
{
    return [OOColor colorWithRed:0.0f green:1.0f blue:1.0f alpha:1.0f];
}

+ (OOColor*)yellowColor // 1.0, 1.0, 0.0 RGB
{
    return [OOColor colorWithRed:1.0f green:1.0f blue:0.0f alpha:1.0f];
}

+ (OOColor*)magentaColor // 1.0, 0.0, 1.0 RGB
{
    return [OOColor colorWithRed:1.0f green:0.0f blue:1.0f alpha:1.0f];
}

+ (OOColor*)orangeColor // 1.0, 0.5, 0.0 RGB
{
    return [OOColor colorWithRed:1.0f green:0.5f blue:0.0f alpha:1.0f];
}

+ (OOColor*)purpleColor // 0.5, 0.0, 0.5 RGB
{
    return [OOColor colorWithRed:0.5f green:0.0f blue:0.5f alpha:1.0f];
}

+ (OOColor*)brownColor // 0.6, 0.4, 0.2 RGB
{
    return [OOColor colorWithRed:0.6f green:0.4f blue:0.2f alpha:1.0f];
}

+ (OOColor*)clearColor // 0.0 white, 0.0 alpha
{
    return [OOColor colorWithWhite:0.0f alpha:0.0f];
}

- (OOColor*)blendedColorWithFraction:(float)fraction ofColor:(OOColor*)color
{
    float rgba1[4];
    [color getRed:&rgba1[0] green:&rgba1[1] blue:&rgba1[2] alpha:&rgba1[3]];

    OOColor* result = [[OOColor alloc] init];
    [result setRed:OOLerp(rgba[0], rgba1[0], fraction)
             green:OOLerp(rgba[1], rgba1[1], fraction)
              blue:OOLerp(rgba[2], rgba1[2], fraction)
             alpha:OOLerp(rgba[3], rgba1[3], fraction)];

    return [result autorelease];
}

- (std::optional<std::string>)cxx_descriptionComponents
{
    return oo::str::format("%g, %g, %g, %g", rgba[0], rgba[1], rgba[2], rgba[3]);
}

// Get the red, green, or blue components.
- (float)redComponent
{
    return rgba[0];
}

- (float)greenComponent
{
    return rgba[1];
}

- (float)blueComponent
{
    return rgba[2];
}

- (void)getRed:(float*)red green:(float*)green blue:(float*)blue alpha:(float*)alpha
{
    OOParameterAssert(red != NULL && green != NULL && blue != NULL && alpha != NULL);

    *red = rgba[0];
    *green = rgba[1];
    *blue = rgba[2];
    *alpha = rgba[3];
}

- (OORGBAComponents)rgbaComponents
{
    OORGBAComponents c = { rgba[0], rgba[1], rgba[2], rgba[3] };
    return c;
}

- (BOOL)isBlack
{
    return rgba[0] == 0.0f && rgba[1] == 0.0f && rgba[2] == 0.0f;
}

- (BOOL)isWhite
{
    return rgba[0] == 1.0f && rgba[1] == 1.0f && rgba[2] == 1.0f && rgba[3] == 1.0f;
}

// Get the components as hue, saturation, or brightness.
- (float)hueComponent
{
    float maxrgb = (rgba[0] > rgba[1]) ? ((rgba[0] > rgba[2]) ? rgba[0] : rgba[2]) : ((rgba[1] > rgba[2]) ? rgba[1] : rgba[2]);
    float minrgb = (rgba[0] < rgba[1]) ? ((rgba[0] < rgba[2]) ? rgba[0] : rgba[2]) : ((rgba[1] < rgba[2]) ? rgba[1] : rgba[2]);
    float delta = maxrgb - minrgb + 0.0001f;
    float fRed = rgba[0], fGreen = rgba[1], fBlue = rgba[2];
    float hue = 0.0f;
    if (maxrgb == fRed && fGreen >= fBlue) {
        hue = 60.0f * (fGreen - fBlue) / delta;
    } else if (maxrgb == fRed && fGreen < fBlue) {
        hue = 60.0f * (fGreen - fBlue) / delta + 360.0f;
    } else if (maxrgb == fGreen) {
        hue = 60.0f * (fBlue - fRed) / delta + 120.0f;
    } else if (maxrgb == fBlue) {
        hue = 60.0f * (fRed - fGreen) / delta + 240.0f;
    }
    return hue;
}

- (float)saturationComponent
{
    float maxrgb = (rgba[0] > rgba[1]) ? ((rgba[0] > rgba[2]) ? rgba[0] : rgba[2]) : ((rgba[1] > rgba[2]) ? rgba[1] : rgba[2]);
    float minrgb = (rgba[0] < rgba[1]) ? ((rgba[0] < rgba[2]) ? rgba[0] : rgba[2]) : ((rgba[1] < rgba[2]) ? rgba[1] : rgba[2]);
    return maxrgb == 0.0f ? 0.0f : (1.0f - (minrgb / maxrgb));
}

- (float)brightnessComponent
{
    float maxrgb = (rgba[0] > rgba[1]) ? ((rgba[0] > rgba[2]) ? rgba[0] : rgba[2]) : ((rgba[1] > rgba[2]) ? rgba[1] : rgba[2]);
    return maxrgb;
}

- (void)getHue:(float*)hue saturation:(float*)saturation brightness:(float*)brightness alpha:(float*)alpha
{
    OOParameterAssert(hue != NULL && saturation != NULL && brightness != NULL && alpha != NULL);

    *alpha = rgba[3];

    float fRed = rgba[0], fGreen = rgba[1], fBlue = rgba[2];
    float maxrgb = fmax(fRed, fmax(fGreen, fBlue));
    float minrgb = fmin(fRed, fmin(fGreen, fBlue));
    float delta = maxrgb - minrgb + 0.0001f;
    float h = 0.0f;
    if (maxrgb == fRed && fGreen >= fBlue) {
        h = 60.0f * (fGreen - fBlue) / delta;
    } else if (maxrgb == fRed && fGreen < fBlue) {
        h = 60.0f * (fGreen - fBlue) / delta + 360.0f;
    } else if (maxrgb == fGreen) {
        h = 60.0f * (fBlue - fRed) / delta + 120.0f;
    } else if (maxrgb == fBlue) {
        h = 60.0f * (fRed - fGreen) / delta + 240.0f;
    }

    float s = (maxrgb == 0.0f) ? 0.0f : (1.0f - (minrgb / maxrgb));

    *hue = h;
    *saturation = s;
    *brightness = maxrgb;
}

- (OOHSBAComponents)hsbaComponents
{
    OOHSBAComponents c;
    [self getHue:&c.h
        saturation:&c.s
        brightness:&c.b
             alpha:&c.a];
    return c;
}

// Get the alpha component.
- (float)alphaComponent
{
    return rgba[3];
}

- (OOColor*)premultipliedColor
{
    if (rgba[3] == 1.0f)
        return [[self retain] autorelease];
    return [OOColor colorWithRed:rgba[0] * rgba[3]
                           green:rgba[1] * rgba[3]
                            blue:rgba[2] * rgba[3]
                           alpha:1.0f];
}

- (OOColor*)colorWithBrightnessFactor:(float)factor
{
    return [OOColor colorWithRed:OOClamp_0_1_f(rgba[0] * factor)
                           green:OOClamp_0_1_f(rgba[1] * factor)
                            blue:OOClamp_0_1_f(rgba[2] * factor)
                           alpha:rgba[3]];
}

- (std::vector<float>)cxx_normalizedArray
{
    float r, g, b, a;
    [self getRed:&r green:&g blue:&b alpha:&a];
    return { r, g, b, a };
}

- (std::optional<std::string>)cxx_rgbaDescription
{
    return cxx_OORGBAComponentsDescription([self rgbaComponents]);
}

- (std::optional<std::string>)cxx_hsbaDescription
{
    return cxx_OOHSBAComponentsDescription([self hsbaComponents]);
}

@end

std::string cxx_OORGBAComponentsDescription(OORGBAComponents components)
{
    return oo::str::format("{%.3g, %.3g, %.3g, %.3g}", components.r, components.g, components.b, components.a);
}

std::string cxx_OOHSBAComponentsDescription(OOHSBAComponents components)
{
    return oo::str::format("{%i, %.3g, %.3g, %.3g}", (int)components.h, components.s, components.b, components.a);
}
