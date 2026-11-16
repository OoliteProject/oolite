/*

OOXMLExtensions.m

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

#include "OOXMLExtensions.h"

#include "oofnd/FileSystem.hpp"
#include "oofnd/PListWriting.hpp"

bool OOWriteXMLPListToFile(const oo::PList& plist, const std::string& path,
                           std::string* outError) {
  const oo::Expected<oo::Data, oo::PListError> data = oo::writeXMLPList(plist);
  if (!data) {
    if (outError != nullptr) {
      *outError = "could not convert property list to XML: " +
                  data.error().description();
    }
    return false;
  }

  if (!oo::fs::writeFile(oo::fs::pathFromUTF8(path), *data,
                         oo::fs::WriteMode::atomic)) {
    if (outError != nullptr) {
      *outError = "could not write data to " + path + ".";
    }
    return false;
  }

  return true;
}
