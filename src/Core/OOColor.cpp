/*

OOColor.mm

C++20 since bead oo-11m, the Phase 3 house-style exemplar (proposed ADR-0056). Method bodies
are the Objective-C ones with message sends turned into calls; the arithmetic is verbatim
(ADR-0012). An Object node's colour is the node's foreign object (bead oo-9ht.1).

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

#include "OOColor.h"
#include "OOMaths.h"

#include "oofnd/Scanner.hpp"
#include "oofnd/String.hpp"
#include "oofnd/objc/OOAssert.h"

namespace {

/*	The named colours colorWithDescription() accepts: the class methods whose names end in "Color",
        which the Objective-C class looked up by selector name and -respondsToSelector:
        (the Phase 3 recipe's "explicit table" for a selector called by name).
*/
struct NamedColor {
    std::string_view name;
    oo::Ref<OOColor> (*make)();
};

const NamedColor kNamedColors[] = {
    { "blackColor", &OOColor::blackColor },
    { "darkGrayColor", &OOColor::darkGrayColor },
    { "lightGrayColor", &OOColor::lightGrayColor },
    { "whiteColor", &OOColor::whiteColor },
    { "grayColor", &OOColor::grayColor },
    { "redColor", &OOColor::redColor },
    { "greenColor", &OOColor::greenColor },
    { "blueColor", &OOColor::blueColor },
    { "cyanColor", &OOColor::cyanColor },
    { "yellowColor", &OOColor::yellowColor },
    { "magentaColor", &OOColor::magentaColor },
    { "orangeColor", &OOColor::orangeColor },
    { "purpleColor", &OOColor::purpleColor },
    { "brownColor", &OOColor::brownColor },
    { "clearColor", &OOColor::clearColor },
};

} // namespace

// Set methods are internal, because OOColor is immutable (as seen from outside).
void OOColor::setRed(float r, float g, float b, float a)
{
    rgba[0] = r;
    rgba[1] = g;
    rgba[2] = b;
    rgba[3] = a;
}

void OOColor::setHue(float h, float s, float b, float a)
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

oo::Ref<OOColor> OOColor::colorWithHue(float hue, float saturation, float brightness, float alpha)
{
    oo::Ref<OOColor> result = oo::makeRef<OOColor>();
    result->setHue(360.0f * hue, saturation, brightness, alpha);
    return result;
}

oo::Ref<OOColor> OOColor::colorWithRed(float red, float green, float blue, float alpha)
{
    oo::Ref<OOColor> result = oo::makeRef<OOColor>();
    result->setRed(red, green, blue, alpha);
    return result;
}

oo::Ref<OOColor> OOColor::colorWithWhite(float white, float alpha)
{
    return colorWithRed(white, white, white, alpha);
}

oo::Ref<OOColor> OOColor::colorWithRGBAComponents(OORGBAComponents components)
{
    return colorWithRed(components.r,
        components.g,
        components.b,
        components.a);
}

oo::Ref<OOColor> OOColor::colorWithHSBAComponents(OOHSBAComponents components)
{
    return colorWithHue(components.h / 360.0f,
        components.s,
        components.b,
        components.a);
}

oo::Ref<OOColor> OOColor::colorWithDescription(const oo::PList& description)
{
    return colorWithDescription(description, 1.0f);
}

oo::Ref<OOColor> OOColor::colorWithDescription(const oo::PList& description, float factor)
{
    oo::Ref<OOColor> result;

    if (description.isNull())
        return nullptr;

    if (description.type() == oo::PList::Type::Object) {
        // The colour in an Object node is the node's foreign object (bead oo-9ht.1).
        if (OOColor* color = OOColorInObjectNode(description))
            result = oo::Ref<OOColor>(color);
    } else if (const std::string* string = description.getIf<std::string>()) {
        if (string->ends_with("Color")) {
            // A named colour (kNamedColors)
            for (const NamedColor& named : kNamedColors) {
                if (named.name == *string) {
                    result = named.make();
                    break;
                }
            }
        } else {
            // Some other string
            result = colorFromString(*string);
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
        result = colorFromString(components);
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
            return colorWithHue(h / 360.0f, s * factor, b, a);
        } else {
            // Treat as RGB(A) dictionary
            float r = description.get<float>("red");
            float g = description.get<float>("green");
            float b = description.get<float>("blue");
            float a = description.get<float>("alpha", -1.0f);
            if (a < 0.0f)
                a = description.get<float>("opacity", 1.0f);

            result = colorWithRed(r, g, b, a);
        }
    }

    if (factor != 1.0f && result != nullptr) {
        float h, s, b, a;
        result->getHue(&h, &s, &b, &a);
        h *= 1.0 / 360.0f; // See note in header.
        s *= factor;
        result = colorWithHue(h, s, b, a);
    }

    return result;
}

oo::Ref<OOColor> OOColor::brightColorWithDescription(const oo::PList& description)
{
    oo::Ref<OOColor> color = colorWithDescription(description);
    if (color == nullptr || 0.5f <= color->brightnessComponent())
        return color;

    return colorWithHue(color->hueComponent() / 360.0f, color->saturationComponent(), 0.5f, 1.0f);
}

oo::Ref<OOColor> OOColor::colorFromString(const std::string& colorFloatString)
{
    float rgbaValue[4] = { 0.0f, 0.0f, 0.0f, 1.0f };
    oo::str::Scanner scanner(colorFloatString);
    float factor = 1.0f;
    int i;

    for (i = 0; i != 4; ++i) {
        if (!scanner.scanFloat(&rgbaValue[i])) {
            // Less than three floats or non-float, can't parse -> quit
            if (i < 3)
                return nullptr;

            // If we get here, we only got three components. Make sure alpha is at correct scale:
            rgbaValue[3] /= factor;
        }
        if (1.0f < rgbaValue[i])
            factor = 1.0f / 255.0f;
    }

    return colorWithRed(rgbaValue[0] * factor, rgbaValue[1] * factor, rgbaValue[2] * factor, rgbaValue[3] * factor);
}

oo::Ref<OOColor> OOColor::blackColor() // 0.0 white
{
    return colorWithWhite(0.0f, 1.0f);
}

oo::Ref<OOColor> OOColor::darkGrayColor() // 0.333 white
{
    return colorWithWhite(1.0f / 3.0f, 1.0f);
}

oo::Ref<OOColor> OOColor::lightGrayColor() // 0.667 white
{
    return colorWithWhite(2.0f / 3.0f, 1.0f);
}

oo::Ref<OOColor> OOColor::whiteColor() // 1.0 white
{
    return colorWithWhite(1.0f, 1.0f);
}

oo::Ref<OOColor> OOColor::grayColor() // 0.5 white
{
    return colorWithWhite(0.5f, 1.0f);
}

oo::Ref<OOColor> OOColor::redColor() // 1.0, 0.0, 0.0 RGB
{
    return colorWithRed(1.0f, 0.0f, 0.0f, 1.0f);
}

oo::Ref<OOColor> OOColor::greenColor() // 0.0, 1.0, 0.0 RGB
{
    return colorWithRed(0.0f, 1.0f, 0.0f, 1.0f);
}

oo::Ref<OOColor> OOColor::blueColor() // 0.0, 0.0, 1.0 RGB
{
    return colorWithRed(0.0f, 0.0f, 1.0f, 1.0f);
}

oo::Ref<OOColor> OOColor::cyanColor() // 0.0, 1.0, 1.0 RGB
{
    return colorWithRed(0.0f, 1.0f, 1.0f, 1.0f);
}

oo::Ref<OOColor> OOColor::yellowColor() // 1.0, 1.0, 0.0 RGB
{
    return colorWithRed(1.0f, 1.0f, 0.0f, 1.0f);
}

oo::Ref<OOColor> OOColor::magentaColor() // 1.0, 0.0, 1.0 RGB
{
    return colorWithRed(1.0f, 0.0f, 1.0f, 1.0f);
}

oo::Ref<OOColor> OOColor::orangeColor() // 1.0, 0.5, 0.0 RGB
{
    return colorWithRed(1.0f, 0.5f, 0.0f, 1.0f);
}

oo::Ref<OOColor> OOColor::purpleColor() // 0.5, 0.0, 0.5 RGB
{
    return colorWithRed(0.5f, 0.0f, 0.5f, 1.0f);
}

oo::Ref<OOColor> OOColor::brownColor() // 0.6, 0.4, 0.2 RGB
{
    return colorWithRed(0.6f, 0.4f, 0.2f, 1.0f);
}

oo::Ref<OOColor> OOColor::clearColor() // 0.0 white, 0.0 alpha
{
    return colorWithWhite(0.0f, 0.0f);
}

oo::Ref<OOColor> OOColor::blendedColorWithFraction(float fraction, OOColor* color)
{
    // A message to nil left rgba1 unwritten (indeterminate); a null colour now blends with zeros.
    float rgba1[4] = { 0.0f, 0.0f, 0.0f, 0.0f };
    if (color != nullptr)
        color->getRed(&rgba1[0], &rgba1[1], &rgba1[2], &rgba1[3]);

    oo::Ref<OOColor> result = oo::makeRef<OOColor>();
    result->setRed(OOLerp(rgba[0], rgba1[0], fraction),
        OOLerp(rgba[1], rgba1[1], fraction),
        OOLerp(rgba[2], rgba1[2], fraction),
        OOLerp(rgba[3], rgba1[3], fraction));

    return result;
}

std::optional<std::string> OOColor::descriptionComponents() const
{
    return oo::str::format("%g, %g, %g, %g", rgba[0], rgba[1], rgba[2], rgba[3]);
}

std::string OOColor::className() const
{
    return "OOColor";
}

std::string OOColor::description() const
{
    std::string result = oo::str::format("<OOColor %s>", oo::str::pointerDescription(this).c_str());
    const std::optional<std::string> components = descriptionComponents();
    if (components.has_value())
        result += "{" + *components + "}";
    return result;
}

// Get the red, green, or blue components.
float OOColor::redComponent()
{
    return rgba[0];
}

float OOColor::greenComponent()
{
    return rgba[1];
}

float OOColor::blueComponent()
{
    return rgba[2];
}

void OOColor::getRed(float* red, float* green, float* blue, float* alpha)
{
    OOCParameterAssert(red != NULL && green != NULL && blue != NULL && alpha != NULL);

    *red = rgba[0];
    *green = rgba[1];
    *blue = rgba[2];
    *alpha = rgba[3];
}

OORGBAComponents OOColor::rgbaComponents()
{
    OORGBAComponents c = { rgba[0], rgba[1], rgba[2], rgba[3] };
    return c;
}

bool OOColor::isBlack()
{
    return rgba[0] == 0.0f && rgba[1] == 0.0f && rgba[2] == 0.0f;
}

bool OOColor::isWhite()
{
    return rgba[0] == 1.0f && rgba[1] == 1.0f && rgba[2] == 1.0f && rgba[3] == 1.0f;
}

// Get the components as hue, saturation, or brightness.
float OOColor::hueComponent()
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

float OOColor::saturationComponent()
{
    float maxrgb = (rgba[0] > rgba[1]) ? ((rgba[0] > rgba[2]) ? rgba[0] : rgba[2]) : ((rgba[1] > rgba[2]) ? rgba[1] : rgba[2]);
    float minrgb = (rgba[0] < rgba[1]) ? ((rgba[0] < rgba[2]) ? rgba[0] : rgba[2]) : ((rgba[1] < rgba[2]) ? rgba[1] : rgba[2]);
    return maxrgb == 0.0f ? 0.0f : (1.0f - (minrgb / maxrgb));
}

float OOColor::brightnessComponent()
{
    float maxrgb = (rgba[0] > rgba[1]) ? ((rgba[0] > rgba[2]) ? rgba[0] : rgba[2]) : ((rgba[1] > rgba[2]) ? rgba[1] : rgba[2]);
    return maxrgb;
}

void OOColor::getHue(float* hue, float* saturation, float* brightness, float* alpha)
{
    OOCParameterAssert(hue != NULL && saturation != NULL && brightness != NULL && alpha != NULL);

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

OOHSBAComponents OOColor::hsbaComponents()
{
    OOHSBAComponents c;
    getHue(&c.h,
        &c.s,
        &c.b,
        &c.a);
    return c;
}

// Get the alpha component.
float OOColor::alphaComponent()
{
    return rgba[3];
}

oo::Ref<OOColor> OOColor::premultipliedColor()
{
    if (rgba[3] == 1.0f)
        return oo::Ref<OOColor>(this);
    return colorWithRed(rgba[0] * rgba[3],
        rgba[1] * rgba[3],
        rgba[2] * rgba[3],
        1.0f);
}

oo::Ref<OOColor> OOColor::colorWithBrightnessFactor(float factor)
{
    return colorWithRed(OOClamp_0_1_f(rgba[0] * factor),
        OOClamp_0_1_f(rgba[1] * factor),
        OOClamp_0_1_f(rgba[2] * factor),
        rgba[3]);
}

std::vector<float> OOColor::normalizedArray()
{
    float r, g, b, a;
    getRed(&r, &g, &b, &a);
    return { r, g, b, a };
}

std::optional<std::string> OOColor::rgbaDescription()
{
    return OORGBAComponentsDescription(rgbaComponents());
}

std::optional<std::string> OOColor::hsbaDescription()
{
    return OOHSBAComponentsDescription(hsbaComponents());
}

std::string OORGBAComponentsDescription(OORGBAComponents components)
{
    return oo::str::format("{%.3g, %.3g, %.3g, %.3g}", components.r, components.g, components.b, components.a);
}

std::string OOHSBAComponentsDescription(OOHSBAComponents components)
{
    return oo::str::format("{%i, %.3g, %.3g, %.3g}", (int)components.h, components.s, components.b, components.a);
}
