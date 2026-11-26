/*

OOPListParsing.h

Property list parser. Tries to use native Foundation property list parsing,
then falls back on Oolite ad-hoc parser for backwards-compatibility (Oolite's
XML plist parser is more lenient than Foundation on OS X).

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

#import "OOFoundation.h"

#include "oofnd/Data.hpp"
#include "oofnd/PList.hpp"
#include "oofnd/StdLib.hpp"

// whereFrom is an optional description of the data source, for error reporting (nullopt reads as
// "<data in memory>"). No data (nullopt) parses nothing. The result is null where there was no
// property list.
oo::PList cxx_OOPropertyListFromData(const std::optional<oo::Data>& data, const std::optional<std::string>& whereFrom);
oo::PList cxx_OOPropertyListFromFile(const std::string& path);

// The typed wrappers have no twins: test the result's kind (getIf<oo::PList::Dict> /
// getIf<oo::PList::Array>).

/*	TRANSITIONAL (proposed ADR-0043, "Transitional bridges"): the Foundation-typed functions as they
        were declared before their sweep (bead oo-crpp, chunk oo-3rb.132), forwarding to the cxx_
        functions above, so unmigrated callers compile unchanged. Callers move to the cxx_ API in their
        own sweep beads; the bridge goes in its own bead.
*/
#import "OOPListParsing+FoundationBridge.h"
