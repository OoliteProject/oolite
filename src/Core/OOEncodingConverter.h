/*

OOEncodingConverter.h

Convert a string to an 8-bit encoding, with some Oolite-specific remappings
specified at init time (currently always from oolite-font.plist).


Copyright (C) 2008-2013 Jens Ayton and contributors

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

#pragma once

#ifndef OOENCODINGCONVERTER_EXCLUDE // For the convenience of fonttexgen

#include "OOFoundation.h"

#include "oofnd/Encoding.hpp"
#include "oofnd/PList.hpp"
#include "oofnd/Ref.hpp"
#include "oofnd/StdLib.hpp"

class OOCache; // C++ since bead oo-rdfh

/*	C++20 since bead oo-demz (proposed ADR-0056, the OOColor house style). Its one caller
        (HeadUpDisplay's text engine) was adapted in the same bead, so there is no Objective-C facade
        and the class is global.
*/
class OOEncodingConverter : public oo::RefCounted {
public:
    // [[OOEncodingConverter alloc] initWithEncoding:substitutions:] and -initWithFontPList:.
    OOEncodingConverter(std::optional<oo::str::Encoding> encoding, const oo::PList& substitutions); // a dictionary of strings
    explicit OOEncodingConverter(const oo::PList& fontPList);

    ~OOEncodingConverter() override;

    oo::Data convertString(const std::string& string); // empty if the string cannot be converted

    std::optional<oo::str::Encoding> encoding();

    // What "%@" printed between the braces of <OOEncodingConverter 0x...>{...} (OODescription.h).
    std::optional<std::string> descriptionComponents() const;

private:
    std::optional<oo::Data> performConversionForString(const std::string& string);
    void profileFire(void* junk); // defined only when the .mm's PROFILE_ENCODING_CONVERTER is on

    std::optional<oo::str::Encoding> _encoding = { }; // nullopt: an unknown encoding name (was NSNotFound)
    oo::Ref<OOCache> _cache; // no `= {}`: GCC instantiates ~Ref<T> at a default member initializer, and T is incomplete here (bead oo-1q4)
    std::vector<std::pair<std::string, std::string>> _substitutions = { }; // in the order they are applied
};

#endif // OOENCODINGCONVERTER_EXCLUDE

/*
        There are a variety of overlapping naming schemes for text encoding.
        We ignore them and use a fixed list (oo::str::Encoding in oofnd/Encoding.hpp):
                "windows-latin-1"		windowsCP1252 (code page 1252)
                "windows-latin-2"		windowsCP1250 (code page 1250)
                "windows-cyrillic"		windowsCP1251 (code page 1251)
                "windows-greek"			windowsCP1253 (code page 1253)
                "windows-turkish"		windowsCP1254 (code page 1254)
*/
const char* StringFromEncoding(unsigned encoding); // oo::str::Encoding numeric value; NULL for unknown
// (EncodingFromString() retired with the Foundation sweep, bead oo-gosz: oo::str::encodingFromName() in oofnd/Encoding.hpp)
