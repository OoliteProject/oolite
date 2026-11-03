/*

OOPListParsing.m

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

#include "OOPListParsing.h"
#include "OOLogging.h"
#include "OOStringParsing.h"
#include "Universe.h"
#include "oofnd/FileSystem.hpp"
#include "oofnd/Log.hpp"

#include "oofnd/PListParsing.hpp"

oo::PList cxx_OOPropertyListFromData(const std::optional<oo::Data>& data, const std::optional<std::string>& whereFrom)
{
    oo::PList result;

    const std::string source = whereFrom.value_or("<data in memory>");
    if (UNIVERSE != nil) {
        OO_LOG("plist.information", "Parsing {} as a property list.", source);
    }

    if (data.has_value()) {
        // oo::parsePropertyList changes an Apple DTD line first, as ChangeDTDIfApplicable did.
        const std::string_view bytes(reinterpret_cast<const char*>(data->bytes()), data->length());
        const oo::Expected<oo::PList, oo::PListError> parsed = oo::parsePropertyList(bytes);
        if (parsed)
            result = *parsed;
        if (result.isNull()) // parser failed
        {
            // Ensure we can say something sensible...
            const std::string error = parsed ? std::string("<no error message>") : parsed.error().description();

            OO_LOG("plist.parse.failed", "Failed to parse {} as a property list.\n{}", source, error);
        }
    }

    return result;
}

oo::PList cxx_OOPropertyListFromFile(const std::string& path)
{
    oo::PList result;

    // Load file, if it exists...
    const std::optional<oo::Data> data = OODataFromOXZFile(path);
    if (data.has_value()) {
        // ...and parse it
        result = cxx_OOPropertyListFromData(data, path);
    }
    // Non-existent file is not an error.

    return result;
}
