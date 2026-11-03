/*

OOStringBridge.h

The NSString <-> std::string bridge that lets a file call oo::str (oofnd/String.hpp) while it
still holds NSStrings (bead oo-dps, proposed ADR-0034). Objective-C++ only; deleted with
gnustep-base, when no NSString is left to bridge.

        [s stringByTrimmingLeadingWhitespaceAndNewlineCharacters]
            ->  oo::StringMap(s, oo::str::trimLeadingWhitespaceAndNewlines)
        [s pathHasExtension:@"oxp"]
            ->  oo::str::pathHasExtension(oo::StdString(s), "oxp")
        [s oo_hash]
            ->  (s != nil ? oo::str::ooHash(oo::StdString(s)) : 0)

Both directions are exact, unit for unit: StdString reads the UTF-16 units and writes UTF-8
(WTF-8 for a lone surrogate, as oo::PList strings are), and NSStringFrom builds the NSString from
those units with an explicit byte order, which keeps a leading U+FEFF or U+FFFE
(-stringWithCharacters:length: would drop the first and byte-swap after the second; probed on
gnustep-base 1.31.1). -UTF8String is not used: it turns a lone surrogate into U+FFFD.

nil is where the bridge needs care. Messaging nil returns nil / 0 / NO, and an oo::str function
cannot see a nil: StdString(nil) is "". StringMap keeps nil as nil for NSString -> NSString
methods; for any other result type, test the receiver as the oo_hash line above does.

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

#ifndef OOSTRINGBRIDGE_H
#define OOSTRINGBRIDGE_H

#import "OOFoundation.h"

#include "oofnd/String.hpp"

#include <string>
#include <string_view>

namespace oo {

// NSString -> UTF-8 std::string, losslessly. nil -> "".
inline std::string StdString(NSString* string)
{
    const NSUInteger length = [string length];
    if (length == 0)
        return std::string();
    std::u16string units(length, u'\0');
    [string getCharacters:reinterpret_cast<unichar*>(units.data()) range:NSMakeRange(0, length)];
    return oo::utf16ToUtf8(units);
}

// UTF-8 std::string -> NSString, unit for unit.
inline NSString* NSStringFrom(std::string_view string)
{
    const std::u16string units = oo::utf8ToUtf16(string);
    return [[[NSString alloc] initWithBytes:units.data()
                                     length:units.size() * sizeof(char16_t)
                                   encoding:NSUTF16LittleEndianStringEncoding] autorelease];
}

// An oo::str function applied to an NSString the way the category method it replaces was
// messaged: nil in, nil out.
template <class F>
NSString* StringMap(NSString* string, F function)
{
    if (string == nil)
        return nil;
    return NSStringFrom(function(StdString(string)));
}

} // namespace oo

#endif // OOSTRINGBRIDGE_H
