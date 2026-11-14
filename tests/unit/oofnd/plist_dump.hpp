/*	tests/unit/oofnd/plist_dump.hpp
	A canonical one-line text form of an oo::PList, shared by the oofnd PList tests. It is the
	same format the (uncommitted) GNUstep oracle harness printed for the NSPropertyListSerialization
	results the tests pin, so an expected string in a test is exactly what GNUstep produced:

	    nil                 no value (Foundation nil)
	    S"text"             string; printable ASCII verbatim except \" and \\, every other UTF-16
	                        code unit as \uXXXX (so lone surrogates and U+0000 are visible)
	    B1 / B0             boolean
	    I-5 / U1844...      integer (U only for unsigned values above INT64_MAX)
	    R1.5                real, %.17g
	    D<0a0b>             data, lower-case hex
	    T12.500             date, seconds since 2001-01-01T00:00:00Z, %.3f
	    [a,b]               array
	    {"k"=v;"l"=w;}      dictionary, keys in UTF-16 code-unit order (-[NSString compare:])
*/

#ifndef OOFND_TESTS_PLIST_DUMP_HPP
#define OOFND_TESTS_PLIST_DUMP_HPP

#include "oofnd/PList.hpp"

#include <algorithm>
#include <cinttypes>
#include <cstdio>
#include <string>
#include <utility>
#include <vector>

namespace oo_test {

inline void dumpString(const std::string& s, std::string& out)
{
	out += '"';
	for (char16_t c : oo::utf8ToUtf16(s))
	{
		if (c == u'"' || c == u'\\')
		{
			out += '\\';
			out += static_cast<char>(c);
		}
		else if (c >= 0x20 && c < 0x7F)
		{
			out += static_cast<char>(c);
		}
		else
		{
			char buf[8];
			std::snprintf(buf, sizeof buf, "\\u%04X", static_cast<unsigned>(c));
			out += buf;
		}
	}
	out += '"';
}

inline void dump(const oo::PList& p, std::string& out)
{
	char buf[64];
	switch (p.type())
	{
		case oo::PList::Type::Null:
			out += "nil";
			break;
		case oo::PList::Type::Object:   // no parser produces one (ADR-0043 Amendment 2)
			out += "object";
			break;
		case oo::PList::Type::Bool:
			out += *p.getIf<bool>() ? "B1" : "B0";
			break;
		case oo::PList::Type::Integer:
		{
			const oo::PList::Integer& i = *p.getIf<oo::PList::Integer>();
			if (i.isUnsigned && i.value < 0) std::snprintf(buf, sizeof buf, "U%" PRIu64, i.unsignedValue());
			else std::snprintf(buf, sizeof buf, "I%" PRId64, i.value);
			out += buf;
			break;
		}
		case oo::PList::Type::Real:
			std::snprintf(buf, sizeof buf, "R%.17g", *p.getIf<double>());
			out += buf;
			break;
		case oo::PList::Type::String:
			out += 'S';
			dumpString(*p.getIf<std::string>(), out);
			break;
		case oo::PList::Type::Data:
			out += "D<";
			for (std::uint8_t b : p.getIf<oo::PList::Data>()->span())
			{
				std::snprintf(buf, sizeof buf, "%02x", b);
				out += buf;
			}
			out += '>';
			break;
		case oo::PList::Type::Date:
			std::snprintf(buf, sizeof buf, "T%.3f", p.getIf<oo::PList::Date>()->sinceReferenceDate);
			out += buf;
			break;
		case oo::PList::Type::Array:
		{
			out += '[';
			bool first = true;
			for (const oo::PList& e : *p.getIf<oo::PList::Array>())
			{
				if (!first) out += ',';
				first = false;
				dump(e, out);
			}
			out += ']';
			break;
		}
		case oo::PList::Type::Dict:
		{
			std::vector<std::pair<std::u16string, const std::pair<const std::string, oo::PList>*>> keys;
			for (const auto& kv : *p.getIf<oo::PList::Dict>()) keys.emplace_back(oo::utf8ToUtf16(kv.first), &kv);
			std::sort(keys.begin(), keys.end(), [](const auto& a, const auto& b) { return a.first < b.first; });
			out += '{';
			for (const auto& k : keys)
			{
				dumpString(k.second->first, out);
				out += '=';
				dump(k.second->second, out);
				out += ';';
			}
			out += '}';
			break;
		}
	}
}

inline std::string dump(const oo::PList& p)
{
	std::string out;
	dump(p, out);
	return out;
}

} // namespace oo_test

#endif // OOFND_TESTS_PLIST_DUMP_HPP
