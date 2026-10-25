/*	oofnd/PListDescription.hpp
	oo::describe(plist): the text gnustep-base's -description gave for the Foundation form of a
	property list (what "%@" printed for oo::ObjectFromPList(plist)), without Foundation (proposed
	ADR-0055 item 1, bead oo-qps.32). Game code reaches it as oo::DescriptionOf(const oo::PList &)
	(src/Core/OODescription.h).

	    value (top level)        text
	    -----------------------  ----------------------------------------------------------------
	    null (nil)               (null)
	    string                   itself
	    bool / integer           1 / 0; %lld, or %llu when unsigned
	    real                     %0.16g; a single-precision real (PList::singleReal) %0.7g
	    data                     <0a0b0c0d 0e>: lower-case hex, a space after every four bytes
	    date                     2001-01-01 00:00:00 +0000: oo::date::description, local time zone
	    Object node              its PListForeign::description()
	    array                    (a, b, c)                    () when empty
	    dictionary               {key = value; other = 2; }   {} when empty; keys by -compare:
	                                                          (UTF-16 units of each key's NFD)

	Inside an array or dictionary every element and key except data, arrays and dictionaries is
	written as a string: bare when it is non-empty ASCII letters and digits, else quoted, with
	" and \ escaped, \a \b \v \f as those escapes, TAB LF CR raw, any other control character as
	\ooo (three octal digits) and every UTF-16 unit above U+007F as \UXXXX (upper-case hex). So
	a number or a date in a collection is quoted when its text needs it ("-2", "0.5", 1).
	Null elements are left out (ObjectFromPList dropped them).

	Pinned byte for byte by tests/unit/oofnd/test_plist_description.cpp against rows captured from
	GNUstep base 1.31.1 (tools/captures/plist-description/capture.sh, with TZ=UTC: the test
	describes dates at offset 0).

	Header-only, C++20, compiles with -fno-exceptions.
*/

#ifndef OOFND_PLISTDESCRIPTION_HPP
#define OOFND_PLISTDESCRIPTION_HPP

// Suspend OOCocoa.h's `#define true 1` / `#define false 0` for this header (see oofnd/Data.hpp,
// proposed ADR-0028); restored at the end.
#pragma push_macro("true")
#pragma push_macro("false")
#undef true
#undef false

#include "oofnd/PList.hpp"
#include "oofnd/Date.hpp"

#include <unicode/unorm2.h>

#include <algorithm>
#include <cstdio>
#include <optional>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace oo {

namespace plist_description_detail {

inline bool isBare(std::u16string_view u) noexcept
{
	if (u.empty()) return false;
	return std::all_of(u.begin(), u.end(), [](char16_t c) {
		return (c >= u'0' && c <= u'9') || (c >= u'A' && c <= u'Z') || (c >= u'a' && c <= u'z');
	});
}

// A dictionary key as -compare: (no options) orders it: GNUstep compares strings with every
// composed character decomposed, so the UTF-16 units of the canonical decomposition (NFD) decide
// ("e" < "ea" < U+00E9 < U+00EA < "f"; captured). ASCII is its own decomposition.
inline std::u16string compareKey(std::string_view s)
{
	std::u16string u = utf8ToUtf16(s);
	if (std::all_of(u.begin(), u.end(), [](char16_t c) { return c < 0x80; })) return u;
	UErrorCode status = U_ZERO_ERROR;
	const UNormalizer2* nfd = unorm2_getNFDInstance(&status);
	if (U_FAILURE(status)) return u;
	std::u16string out(u.size() * 4 + 4, char16_t());
	const int32_t n = unorm2_normalize(nfd, reinterpret_cast<const UChar*>(u.data()), static_cast<int32_t>(u.size()),
		reinterpret_cast<UChar*>(out.data()), static_cast<int32_t>(out.size()), &status);
	if (U_FAILURE(status)) return u;
	out.resize(static_cast<std::size_t>(n));
	return out;
}

// A string as an element or key of a described collection (GNUstep's quoting, see the header).
inline void appendElementString(std::string& out, std::string_view s)
{
	const std::u16string u = utf8ToUtf16(s);
	if (isBare(u))
	{
		out += s;
		return;
	}
	out += '"';
	char buffer[8];
	for (char16_t c : u)
	{
		switch (c)
		{
			case u'"': out += "\\\""; break;
			case u'\\': out += "\\\\"; break;
			case u'\a': out += "\\a"; break;
			case u'\b': out += "\\b"; break;
			case u'\v': out += "\\v"; break;
			case u'\f': out += "\\f"; break;
			case u'\t':
			case u'\n':
			case u'\r': out += static_cast<char>(c); break;
			default:
				if (c < 0x20 || c == 0x7F)
				{
					std::snprintf(buffer, sizeof buffer, "\\%03o", static_cast<unsigned>(c));
					out += buffer;
				}
				else if (c > 0x7F)
				{
					std::snprintf(buffer, sizeof buffer, "\\U%04X", static_cast<unsigned>(c));
					out += buffer;
				}
				else
				{
					out += static_cast<char>(c);
				}
		}
	}
	out += '"';
}

inline std::string numberText(const PList& v)
{
	char buffer[40];
	if (const bool* b = v.getIf<bool>()) return *b ? "1" : "0";
	if (const PList::Integer* i = v.getIf<PList::Integer>())
	{
		if (i->isUnsigned) std::snprintf(buffer, sizeof buffer, "%llu", static_cast<unsigned long long>(i->unsignedValue()));
		else std::snprintf(buffer, sizeof buffer, "%lld", static_cast<long long>(i->value));
		return buffer;
	}
	std::snprintf(buffer, sizeof buffer, v.isSinglePrecision() ? "%0.7g" : "%0.16g", v.doubleValue());
	return buffer;
}

inline std::string dataText(const Data& data)
{
	static const char kHex[] = "0123456789abcdef";
	std::string out = "<";
	for (std::size_t i = 0; i < data.length(); ++i)
	{
		if (i != 0 && i % 4 == 0) out += ' ';
		const unsigned byte = data.bytes()[i];
		out += kHex[byte >> 4];
		out += kHex[byte & 0x0F];
	}
	out += '>';
	return out;
}

// The Foundation date's -description (oo::date::description): in the local time zone, or at <utcOffsetMinutes>.
inline std::string dateText(const PList::Date& when, std::optional<int> utcOffsetMinutes)
{
	const auto t = date::dateWithTimeIntervalSinceReferenceDate(when.sinceReferenceDate);
	return utcOffsetMinutes.has_value() ? date::description(t, *utcOffsetMinutes) : date::description(t);
}

inline void appendValue(std::string& out, const PList& v, std::optional<int> utcOffsetMinutes);

inline void appendElement(std::string& out, const PList& v, std::optional<int> utcOffsetMinutes)
{
	switch (v.type())
	{
		case PList::Type::Data:
		case PList::Type::Array:
		case PList::Type::Dict:
			appendValue(out, v, utcOffsetMinutes);
			break;
		default:
		{
			std::string text;
			appendValue(text, v, utcOffsetMinutes);
			appendElementString(out, text);
		}
	}
}

inline void appendValue(std::string& out, const PList& v, std::optional<int> utcOffsetMinutes)
{
	switch (v.type())
	{
		case PList::Type::Null: out += "(null)"; return;
		case PList::Type::Bool:
		case PList::Type::Integer:
		case PList::Type::Real: out += numberText(v); return;
		case PList::Type::String: out += *v.getIf<std::string>(); return;
		case PList::Type::Data: out += dataText(*v.getIf<PList::Data>()); return;
		case PList::Type::Date: out += dateText(*v.getIf<PList::Date>(), utcOffsetMinutes); return;
		case PList::Type::Object:
		{
			const PList::Object& object = *v.getIf<PList::Object>();
			out += object ? object->description() : std::string("(null)");
			return;
		}
		case PList::Type::Array:
		{
			out += '(';
			bool first = true;
			for (const PList& element : *v.getIf<PList::Array>())
			{
				if (element.isNull()) continue;
				if (!first) out += ", ";
				first = false;
				appendElement(out, element, utcOffsetMinutes);
			}
			out += ')';
			return;
		}
		case PList::Type::Dict:
		{
			std::vector<std::pair<std::u16string, const PList::Dict::value_type*>> keys;
			for (const auto& kv : *v.getIf<PList::Dict>())
			{
				if (!kv.second.isNull()) keys.emplace_back(compareKey(kv.first), &kv);
			}
			std::sort(keys.begin(), keys.end(), [](const auto& a, const auto& b) { return a.first < b.first; });
			out += '{';
			for (const auto& key : keys)
			{
				appendElementString(out, key.second->first);
				out += " = ";
				appendElement(out, key.second->second, utcOffsetMinutes);
				out += "; ";
			}
			out += '}';
			return;
		}
	}
}

}	// namespace plist_description_detail

// What -description gave for oo::ObjectFromPList(plist) (see the table above).
inline std::string describe(const PList& plist)
{
	std::string out;
	plist_description_detail::appendValue(out, plist, std::nullopt);
	return out;
}

// The same with dates at a fixed UTC offset instead of the local time zone (the tests: 0).
inline std::string describe(const PList& plist, int utcOffsetMinutes)
{
	std::string out;
	plist_description_detail::appendValue(out, plist, utcOffsetMinutes);
	return out;
}

}	// namespace oo

#pragma pop_macro("false")
#pragma pop_macro("true")

#endif	// OOFND_PLISTDESCRIPTION_HPP
