/*	oofnd/PListParsing.hpp
	oo::parsePropertyList(): what OOPropertyListFromData (src/Core/OOPListParsing.m) does with a
	buffer, minus the logging - ChangeDTDIfApplicable, then GNUstep's
	+[NSPropertyListSerialization propertyListFromData:mutabilityOption:format:errorDescription:]
	format detection and dispatch:

	  * empty data                      -> error "empty data argument passed to method"
	  * "bplist00..." / first byte 0 or 1 -> binary formats: an error in oofnd (ADR-0027 item 3)
	  * "<?" after plist whitespace       -> oo::parseXMLPList      (oofnd/PListXML.hpp)
	  * anything else                     -> oo::parseOldStylePList (oofnd/PListOldStyle.hpp)

	    oo::Expected<oo::PList, oo::PListError> r = oo::parsePropertyList(bytes);
	    if (!r)            OOLog(kOOLogPListFoundationParseError, "Failed to parse %s as a property list.\n%s",
	                             whereFrom, r.error().description().c_str());
	    else if (r->isNull()) ...   // GNUstep's "nil without an error" (logged as "<no error message>")

	A PList that is not the kind the caller wanted (OODictionaryFromData's ValueIfClass) is the
	caller's check: r->getIf<oo::PList::Dict>().
*/

#ifndef OOFND_PLISTPARSING_HPP
#define OOFND_PLISTPARSING_HPP

// Suspend OOCocoa.h's `#define true 1` / `#define false 0` for this header (see oofnd/Data.hpp,
// proposed ADR-0028); restored at the end.
#pragma push_macro("true")
#pragma push_macro("false")
#undef true
#undef false

#include "oofnd/Expected.hpp"
#include "oofnd/PList.hpp"
#include "oofnd/PListOldStyle.hpp"
#include "oofnd/PListXML.hpp"

#include <cstddef>
#include <string>
#include <string_view>

namespace oo {

// -[NSPropertyListSerialization propertyListWithData:options:format:error:] (no DTD change).
inline Expected<PList, PListError> parsePropertyListData(std::string_view bytes, PListFormat* format = nullptr)
{
	if (bytes.empty()) return Unexpected(PListError{"empty data argument passed to method"});
	const auto* b = reinterpret_cast<const unsigned char*>(bytes.data());
	if (bytes.size() >= 8 && bytes.substr(0, 8) == "bplist00")
	{
		if (format != nullptr) *format = PListFormat::Binary;
		return Unexpected(PListError{"binary property lists are not supported by oofnd"});
	}
	if (b[0] == 0 || b[0] == 1)
	{
		if (format != nullptr) *format = PListFormat::GNUstepBinary;
		return Unexpected(PListError{"binary property lists are not supported by oofnd"});
	}
	std::size_t index = 0;
	while (index < bytes.size() && plist_detail::isPListSpace(b[index])) index++;
	if (bytes.size() - index > 2 && b[index] == '<' && b[index + 1] == '?')
	{
		if (format != nullptr) *format = PListFormat::XML;
		return parseXMLPList(bytes);
	}
	return parseOldStylePList(bytes, format);
}

// OOPropertyListFromData(data, whereFrom) without the log lines.
inline Expected<PList, PListError> parsePropertyList(std::string_view bytes, PListFormat* format = nullptr)
{
	const std::string data = changeDTDIfApplicable(bytes);
	return parsePropertyListData(data, format);
}

} // namespace oo

#pragma pop_macro("false")
#pragma pop_macro("true")

#endif // OOFND_PLISTPARSING_HPP
