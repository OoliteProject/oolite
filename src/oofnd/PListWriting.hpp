/*	oofnd/PListWriting.hpp
	The two plist writers Oolite uses, reproduced byte for byte (ADR-0027):

	    Objective-C                                                   oofnd
	    ------------------------------------------------------------  ------------------------------
	    [plist oldSchoolPListFormatWithErrorDescription:&err]          oo::writeOldStylePList(plist)
	        (src/Core/OldSchoolPropertyListWriting.m)
	    [NSPropertyListSerialization dataFromPropertyList:plist       oo::writeXMLPList(plist)
	        format:NSPropertyListXMLFormat_v1_0 errorDescription:&err]

	Both return the bytes as oo::Data (UTF-8), or a PListError.

	OLD-STYLE (OldSchoolPropertyListWriting.m): tab indentation; dictionary keys sorted with
	-caseInsensitiveCompare:; `key = value;` with arrays and dictionaries starting on the next
	line; a string is bare when it is non-empty ASCII letters and digits not starting with a
	digit, otherwise quoted with only " \ newline and CR escaped (a newline is written as a
	backslash followed by a real newline) - and, reproducing the original's bug, the text
	BETWEEN two such characters is left out ("a\"b\\c" is written "a\"\\c"); booleans are true/false, reals %.8g, integers in
	decimal; data is <0A0B0C0D 0E0F> in groups of four bytes, a new line every 32; the whole
	thing ends in a newline. Dates cannot be written ("non-plist object in dictionary" inside a
	container, "Class NSCalendarDate does not support OldSchoolPropertyListWriting" at the top).
	Differences (ADR-0027): a string with non-ASCII characters is always quoted (item 5); data of
	a length where the original overflows its buffer or loops (5-7, 9+ bytes) is written in the
	intended form, not truncated or crashed (item 4); keys equal but for case are ordered by
	their UTF-16 units (GNUstep: hash order).

	XML (GNUstep's OAppend with step 2): Apple's DOCTYPE header; indentation "", 4 spaces, tab,
	tab + 4 spaces, ... capped at six tabs; keys sorted by -compare: (UTF-16 units); reals
	%.16g; <data> base64 on the line after the tag; dates %Y-%m-%dT%H:%M:%SZ in UTC; no newline
	after </plist>. Text escaping is XString's: & < > ' " as entities, other controls (not tab,
	LF, CR) and U+FFFE/U+FFFF as \Uxxxx - but only when the string contains one of & < > ' " \,
	a control, a surrogate or U+FFFE/FFFF; otherwise it is written raw (a NUL byte included).

	Both writers treat a string holding a lone surrogate as GNUstep does: its UTF-8 conversion
	fails, so the old-style writer fails as a whole and the XML writer writes nothing for it.
*/

#ifndef OOFND_PLISTWRITING_HPP
#define OOFND_PLISTWRITING_HPP

// Suspend OOCocoa.h's `#define true 1` / `#define false 0` for this header (see oofnd/Data.hpp,
// proposed ADR-0028); restored at the end.
#pragma push_macro("true")
#pragma push_macro("false")
#undef true
#undef false

#include "oofnd/Expected.hpp"
#include "oofnd/PList.hpp"

#include <algorithm>
#include <cinttypes>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace oo {

namespace plist_detail {

inline bool hasLoneSurrogate(std::u16string_view u) noexcept
{
	for (std::size_t i = 0; i < u.size(); ++i)
	{
		if (u[i] >= 0xD800 && u[i] <= 0xDBFF && i + 1 < u.size() && u[i + 1] >= 0xDC00 && u[i + 1] <= 0xDFFF)
		{
			++i;
		}
		else if (u[i] >= 0xD800 && u[i] <= 0xDFFF)
		{
			return true;
		}
	}
	return false;
}

// Seconds since 2001-01-01Z -> "%Y-%m-%d?%H:%M:%S" fields in UTC (proleptic Gregorian).
inline void breakDate(double sinceReferenceDate, long& y, int& mo, int& d, int& h, int& mi, int& s)
{
	const double t = std::floor(sinceReferenceDate);
	const long long days = static_cast<long long>(std::floor(t / 86400.0));
	const long long secs = static_cast<long long>(t) - days * 86400;
	// civil_from_days (H. Hinnant) on days since 1970-01-01; 2001-01-01 is day 11323.
	const long long z = days + 11323 + 719468;
	const long long era = (z >= 0 ? z : z - 146096) / 146097;
	const long long doe = z - era * 146097;
	const long long yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
	long long year = yoe + era * 400;
	const long long doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
	const long long mp = (5 * doy + 2) / 153;
	d = static_cast<int>(doy - (153 * mp + 2) / 5 + 1);
	mo = static_cast<int>(mp < 10 ? mp + 3 : mp - 9);
	if (mo <= 2) ++year;
	y = static_cast<long>(year);
	h = static_cast<int>(secs / 3600);
	mi = static_cast<int>((secs % 3600) / 60);
	s = static_cast<int>(secs % 60);
}

inline void appendBase64(std::string& out, const Data& data)
{
	static constexpr char kB64[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
	const std::uint8_t* src = data.bytes();
	const std::size_t n = data.length();
	for (std::size_t i = 0; i < n; i += 3)
	{
		const int c0 = src[i];
		const int c1 = i + 1 < n ? src[i + 1] : 0;
		const int c2 = i + 2 < n ? src[i + 2] : 0;
		out += kB64[(c0 >> 2) & 077];
		out += kB64[((c0 << 4) & 060) | ((c1 >> 4) & 017)];
		out += i + 1 < n ? kB64[((c1 << 2) & 074) | ((c2 >> 6) & 03)] : '=';
		out += i + 2 < n ? kB64[c2 & 077] : '=';
	}
}

// --- old-style (OldSchoolPropertyListWriting.m) -------------------------------------------------

class OldStyleWriter
{
public:
	std::string error;
	bool nilResult = false;   // GNUstep returned nil without an error description

	// -oldSchoolPListFormatWithIndentation:errorDescription:. False on failure.
	bool format(const PList& v, unsigned indent, std::string& out)
	{
		switch (v.type())
		{
			case PList::Type::String: return formatString(*v.getIf<std::string>(), out);
			case PList::Type::Bool: out += *v.getIf<bool>() ? "true" : "false"; return true;
			case PList::Type::Integer:
			{
				const PList::Integer& i = *v.getIf<PList::Integer>();
				char buf[32];
				if (i.isUnsigned) std::snprintf(buf, sizeof buf, "%" PRIu64, i.unsignedValue());
				else std::snprintf(buf, sizeof buf, "%" PRId64, i.value);
				out += buf;
				return true;
			}
			case PList::Type::Real:
			{
				char buf[40];
				std::snprintf(buf, sizeof buf, "%.8g", *v.getIf<double>());
				out += buf;
				return true;
			}
			case PList::Type::Data: formatData(*v.getIf<Data>(), indent, out); return true;
			case PList::Type::Array: return formatArray(*v.getIf<PList::Array>(), indent, out);
			case PList::Type::Dict: return formatDict(*v.getIf<PList::Dict>(), indent, out);
			case PList::Type::Date:
				error = "Class NSCalendarDate does not support OldSchoolPropertyListWriting";
				return false;
			case PList::Type::Object:
				// NSObject's -oldSchoolPListFormatWithIndentation:errorDescription: (Amendment 2 carrier).
				error = "Class " + v.getIf<PList::Object>()->get()->className() + " does not support OldSchoolPropertyListWriting";
				return false;
			case PList::Type::Null: break;
		}
		nilResult = true;   // [nil oldSchoolPList...] is nil
		error = "nil property list";
		return false;
	}

private:
	static void newLineAndIndent(std::string& out, unsigned depth)
	{
		out += '\n';
		out.append(depth, '\t');
	}

	static bool conforms(const PList& v) { return !v.isDate() && !v.isNull(); }

	bool formatString(const std::string& s, std::string& out)
	{
		const std::u16string u = utf8ToUtf16(s);
		if (hasLoneSurrogate(u))
		{
			// -dataUsingEncoding:NSUTF8StringEncoding of the result is nil.
			nilResult = true;
			error = "a string with a lone UTF-16 surrogate cannot be written as UTF-8";
			return false;
		}
		auto isAlnum = [](char16_t c) { return (c >= '0' && c <= '9') || (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z'); };
		// +alphanumericCharacterSet is Unicode-wide in GNUstep; oofnd quotes all non-ASCII
		// (ADR-0027 item 5), so only ASCII letters and digits leave a string bare.
		if (!u.empty() && std::all_of(u.begin(), u.end(), isAlnum) && !(u[0] >= '0' && u[0] <= '9'))
		{
			out += s;
			return true;
		}
		// The original's escaping loop appends the text before the first character that needs an
		// escape and the text after the last one, but never the text BETWEEN two of them:
		// "quote\"back\\slash" is written "quote\"\\slash". Reproduced (the writer must be
		// byte-identical); a string with at most one run of such characters is unaffected.
		auto needsEscape = [](char c) { return c == '"' || c == '\n' || c == '\r' || c == '\\'; };
		out += '"';
		std::size_t found = 0;
		while (found < s.size() && !needsEscape(s[found])) ++found;
		out.append(s, 0, found);
		while (found < s.size())
		{
			switch (s[found])
			{
				case '"': out += "\\\""; break;
				case '\n': out += "\\\n"; break;
				case '\r': out += "\\\r"; break;
				default: out += "\\\\"; break;
			}
			std::size_t next = found + 1;
			while (next < s.size() && !needsEscape(s[next])) ++next;
			if (next == s.size())
			{
				out.append(s, found + 1, std::string::npos);
				break;
			}
			found = next;   // (the text in between is dropped)
		}
		out += '"';
		return true;
	}

	// NSData's writer, as intended: GNUstep's buffer is too small for 5-7 and 9+ bytes (it
	// truncates, pads with uninitialised bytes or crashes) and loops forever for more than 32
	// bytes at indentation 0. Byte-identical for 0-4 and 8 bytes (ADR-0027 item 4).
	static void formatData(const Data& d, unsigned indent, std::string& out)
	{
		static constexpr char kHex[] = "0123456789ABCDEF";
		const std::uint8_t* b = d.bytes();
		out += '<';
		for (std::size_t i = 0; i != d.length(); ++i)
		{
			if (i != 0 && (i & 3) == 0)
			{
				if ((i & 31) == 0)
				{
					out += '\n';
					if (indent > 1) out.append(indent - 1, '\t');
				}
				out += ' ';
			}
			out += kHex[b[i] >> 4];
			out += kHex[b[i] & 0xF];
		}
		out += '>';
	}

	bool formatArray(const PList::Array& a, unsigned indent, std::string& out)
	{
		out += '(';
		newLineAndIndent(out, indent + 1);
		for (std::size_t i = 0; i != a.size(); ++i)
		{
			if (i != 0)
			{
				out += ',';
				newLineAndIndent(out, indent + 1);
			}
			if (!conforms(a[i]))
			{
				error = "non-plist object in dictionary";   // (sic: GNUstep's text, for arrays too)
				return false;
			}
			if (!format(a[i], indent + 1, out)) return false;
		}
		newLineAndIndent(out, indent);
		out += ')';
		return true;
	}

	// -caseInsensitiveCompare: (ASCII case folding to lower case, then UTF-16 units), with keys
	// equal but for case ordered by their units.
	static bool caseInsensitiveLess(const std::u16string& a, const std::u16string& b)
	{
		auto fold = [](char16_t c) { return (c >= 'A' && c <= 'Z') ? static_cast<char16_t>(c - 'A' + 'a') : c; };
		const std::size_t n = std::min(a.size(), b.size());
		for (std::size_t i = 0; i < n; ++i)
		{
			const char16_t x = fold(a[i]), y = fold(b[i]);
			if (x != y) return x < y;
		}
		if (a.size() != b.size()) return a.size() < b.size();
		return a < b;
	}

	bool formatDict(const PList::Dict& dict, unsigned indent, std::string& out)
	{
		std::vector<std::pair<std::u16string, const PList::Dict::value_type*>> keys;
		keys.reserve(dict.size());
		for (const auto& kv : dict) keys.emplace_back(utf8ToUtf16(kv.first), &kv);
		std::sort(keys.begin(), keys.end(), [](const auto& a, const auto& b) { return caseInsensitiveLess(a.first, b.first); });

		out += '{';
		newLineAndIndent(out, indent + 1);
		for (std::size_t i = 0; i != keys.size(); ++i)
		{
			if (i != 0) newLineAndIndent(out, indent + 1);
			const PList& value = keys[i].second->second;
			if (!conforms(value))
			{
				error = "non-plist object in dictionary";
				return false;
			}
			if (!formatString(keys[i].second->first, out)) return false;
			std::string valueDesc;
			if (!format(value, indent + 1, valueDesc)) return false;
			out += " =";
			if (value.isArray() || value.isDict()) newLineAndIndent(out, indent + 1);
			else out += ' ';
			out += valueDesc;
			out += ';';
		}
		newLineAndIndent(out, indent);
		out += '}';
		return true;
	}
};

// --- XML (NSPropertyList.m's OAppend / XString) --------------------------------------------------

inline void appendXMLString(std::string& out, const std::string& s)
{
	if (s.empty()) return;
	const std::u16string u = utf8ToUtf16(s);
	auto quotable = [](char16_t c) {
		return c == '&' || c == '<' || c == '>' || c == '\'' || c == '\\' || c == '"'
			   || (c >= 0x01 && c <= 0x1F && c != 0x09 && c != 0x0A && c != 0x0D) || (c >= 0xD800 && c <= 0xDFFE)
			   || c == 0xFFFE || c == 0xFFFF;
	};
	if (hasLoneSurrogate(u)) return;   // -dataUsingEncoding:NSUTF8StringEncoding is nil
	if (std::none_of(u.begin(), u.end(), quotable))
	{
		out += s;
		return;
	}
	static constexpr char kHex[] = "0123456789ABCDEF";
	std::u16string map;
	map.reserve(u.size() + 16);
	for (std::size_t i = 0; i < u.size(); ++i)
	{
		const char16_t c = u[i];
		switch (c)
		{
			case '&': map += u"&amp;"; break;
			case '<': map += u"&lt;"; break;
			case '>': map += u"&gt;"; break;
			case '\'': map += u"&apos;"; break;
			case '"': map += u"&quot;"; break;
			default:
				if (c >= 0xD800 && c <= 0xDBFF && i + 1 < u.size() && u[i + 1] >= 0xDC00 && u[i + 1] <= 0xDFFF)
				{
					map += c;
					map += u[++i];
				}
				else if ((c < 0x20 && c != 0x09 && c != 0x0A && c != 0x0D) || c > 0xFFFD)
				{
					map += u'\\';
					map += u'U';
					map += static_cast<char16_t>(kHex[(c >> 12) & 0xF]);
					map += static_cast<char16_t>(kHex[(c >> 8) & 0xF]);
					map += static_cast<char16_t>(kHex[(c >> 4) & 0xF]);
					map += static_cast<char16_t>(kHex[c & 0xF]);
				}
				else
				{
					map += c;
				}
				break;
		}
	}
	applyInitWithCharactersBOM(map);   // the escaped text becomes an NSString from units
	out += utf16ToUtf8(map);
}

inline const char* xmlIndent(unsigned index) noexcept
{
	static constexpr const char* kIndents[] = {
		"", "  ", "    ", "      ", "\t", "\t  ", "\t    ", "\t      ", "\t\t", "\t\t  ", "\t\t    ", "\t\t      ",
		"\t\t\t", "\t\t\t  ", "\t\t\t    ", "\t\t\t      ", "\t\t\t\t", "\t\t\t\t  ", "\t\t\t\t    ", "\t\t\t\t      ",
		"\t\t\t\t\t", "\t\t\t\t\t  ", "\t\t\t\t\t    ", "\t\t\t\t\t      ", "\t\t\t\t\t\t",
	};
	constexpr unsigned count = sizeof kIndents / sizeof kIndents[0];
	return kIndents[index < count ? index : count - 1];
}

inline void appendXML(std::string& out, const PList& v, unsigned level)
{
	constexpr unsigned step = 2;
	char buf[48];
	switch (v.type())
	{
		case PList::Type::String:
			out += "<string>";
			appendXMLString(out, *v.getIf<std::string>());
			out += "</string>\n";
			return;
		case PList::Type::Bool:
			out += *v.getIf<bool>() ? "<true/>\n" : "<false/>\n";
			return;
		case PList::Type::Integer:
		{
			const PList::Integer& i = *v.getIf<PList::Integer>();
			if (i.isUnsigned) std::snprintf(buf, sizeof buf, "%" PRIu64, i.unsignedValue());
			else std::snprintf(buf, sizeof buf, "%" PRId64, i.value);
			out += "<integer>";
			out += buf;
			out += "</integer>\n";
			return;
		}
		case PList::Type::Real:
			if (v.isSinglePrecision())  std::snprintf(buf, sizeof buf, "%0.7g", static_cast<double>(static_cast<float>(*v.getIf<double>())));   // +numberWithFloat: (captured)
			else  std::snprintf(buf, sizeof buf, "%0.16g", *v.getIf<double>());
			out += "<real>";
			out += buf;
			out += "</real>\n";
			return;
		case PList::Type::Data:
			out += "<data>\n";
			appendBase64(out, *v.getIf<Data>());
			out += "</data>\n";
			return;
		case PList::Type::Date:
		{
			long y;
			int mo, d, h, mi, s;
			breakDate(v.getIf<PList::Date>()->sinceReferenceDate, y, mo, d, h, mi, s);
			std::snprintf(buf, sizeof buf, "%04ld-%02d-%02dT%02d:%02d:%02dZ", y, mo, d, h, mi, s);
			out += "<date>";
			out += buf;
			out += "</date>\n";
			return;
		}
		case PList::Type::Array:
		{
			const char* base = xmlIndent(level * step);
			const char* size = xmlIndent((level + 1) * step);
			out += "<array>\n";
			for (const PList& e : *v.getIf<PList::Array>())
			{
				out += size;
				appendXML(out, e, level + 1);
			}
			out += base;
			out += "</array>\n";
			return;
		}
		case PList::Type::Dict:
		{
			const char* base = xmlIndent(level * step);
			const char* size = xmlIndent((level + 1) * step);
			std::vector<std::pair<std::u16string, const PList::Dict::value_type*>> keys;
			for (const auto& kv : *v.getIf<PList::Dict>()) keys.emplace_back(utf8ToUtf16(kv.first), &kv);
			std::sort(keys.begin(), keys.end(), [](const auto& a, const auto& b) { return a.first < b.first; });
			out += "<dict>\n";
			for (const auto& k : keys)
			{
				out += size;
				out += "<key>";
				appendXMLString(out, k.second->first);
				out += "</key>\n";
				out += size;
				appendXML(out, k.second->second, level + 1);
			}
			out += base;
			out += "</dict>\n";
			return;
		}
		case PList::Type::Null:
			out += "<string>(nil)</string>";   // OAppend's nil branch (no newline)
			return;
		case PList::Type::Object:
			// Not property-list data (Amendment 2 carrier): its -description in a <string>, with NO
			// line break after it (captured from gnustep-base 1.31.1, bead oo-3rb.149: GNUstep's
			// XML writer falls through to the description without the string branch's newline).
			out += "<string>";
			appendXMLString(out, v.getIf<PList::Object>()->get()->description());
			out += "</string>";
			return;
	}
}

} // namespace plist_detail

// -[NSObject(OldSchoolPropertyListWriting) oldSchoolPListFormatWithErrorDescription:]
inline Expected<Data, PListError> writeOldStylePList(const PList& plist)
{
	plist_detail::OldStyleWriter writer;
	std::string out;
	if (!writer.format(plist, 0, out)) return Unexpected(PListError{writer.error});
	out += '\n';
	return Data(out.data(), out.size());
}

// +[NSPropertyListSerialization dataFromPropertyList:format:NSPropertyListXMLFormat_v1_0 ...]
inline Expected<Data, PListError> writeXMLPList(const PList& plist)
{
	if (plist.isNull()) return Unexpected(PListError{"nil property list"});   // GNUstep raises
	std::string out =
		"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
		"<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n"
		"<plist version=\"1.0\">\n";
	plist_detail::appendXML(out, plist, 0);
	out += "</plist>";
	return Data(out.data(), out.size());
}

} // namespace oo

#pragma pop_macro("false")
#pragma pop_macro("true")

#endif // OOFND_PLISTWRITING_HPP
