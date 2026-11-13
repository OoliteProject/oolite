/*	oofnd/PListParsing.hpp
        oo::parsePropertyList(): what OOPropertyListFromData
   (src/Core/OOPListParsing.m) does with a buffer, minus the logging -
   ChangeDTDIfApplicable, then GNUstep's
        +[NSPropertyListSerialization
   propertyListFromData:mutabilityOption:format:errorDescription:] format
   detection and dispatch:

          * empty data                      -> error "empty data argument passed
   to method"
          * "bplist00..." / first byte 0 or 1 -> binary formats: an error in
   oofnd
          * "<?" after plist whitespace       -> oo::parseXMLPList
   (oofnd/PListXML.hpp)
          * anything else                     -> oo::parseOldStylePList
   (oofnd/PListOldStyle.hpp)

            std::expected<oo::PList, oo::PListError> r =
   oo::parsePropertyList(bytes); if (!r) OOLog(kOOLogPListFoundationParseError,
   "Failed to parse %s as a property list.\n%s", whereFrom,
   r.error().description().c_str()); else if (r->isNull()) ...   // GNUstep's
   "nil without an error" (logged as "<no error message>")

        A PList that is not the kind the caller wanted (OODictionaryFromData's
   ValueIfClass) is the caller's check: r->getIf<oo::PList::Dict>().
*/

#pragma once

#include <cstddef>
#include <expected>
#include <string>
#include <string_view>

#include "oofnd/PList.hpp"
#include "oofnd/PListOldStyle.hpp"
#include "oofnd/PListXML.hpp"

namespace oo {

// -[NSPropertyListSerialization propertyListWithData:options:format:error:] (no
// DTD change).
inline std::expected<PList, PListError> parsePropertyListData(
    std::string_view bytes, PListFormat* format = nullptr) {
  if (bytes.empty())
    return std::unexpected(PListError{"empty data argument passed to method"});
  const auto* b = reinterpret_cast<const unsigned char*>(bytes.data());
  if (bytes.size() >= 8 && bytes.substr(0, 8) == "bplist00") {
    if (format != nullptr) *format = PListFormat::kBinary;
    return std::unexpected(
        PListError{"binary property lists are not supported by oofnd"});
  }
  if (b[0] == 0 || b[0] == 1) {
    if (format != nullptr) *format = PListFormat::kGNUstepBinary;
    return std::unexpected(
        PListError{"binary property lists are not supported by oofnd"});
  }
  std::size_t index = 0;
  while (index < bytes.size() && plist_detail::isPListSpace(b[index])) index++;
  if (bytes.size() - index > 2 && b[index] == '<' && b[index + 1] == '?') {
    if (format != nullptr) *format = PListFormat::kXML;
    return parseXMLPList(bytes);
  }
  return parseOldStylePList(bytes, format);
}

// OOPropertyListFromData(data, whereFrom) without the log lines.
inline std::expected<PList, PListError> parsePropertyList(
    std::string_view bytes, PListFormat* format = nullptr) {
  const std::string data = changeDTDIfApplicable(bytes);
  return parsePropertyListData(data, format);
}

}  // namespace oo
