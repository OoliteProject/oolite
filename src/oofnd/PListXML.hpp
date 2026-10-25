/*	oofnd/PListXML.hpp
	The XML property-list reader Oolite runs today, reproduced quirk-for-quirk (ADR-0027):

	  * oo::changeDTDIfApplicable() - OOPListParsing.m's ChangeDTDIfApplicable(): when the data
	    starts with exactly <?xml version="1.0" encoding="UTF-8"?> followed (after whitespace) by
	    one of Apple's two plist DOCTYPE lines, that DOCTYPE is replaced by GNUstep's and the
	    whitespace between by a single newline. Anything else is returned unchanged.
	  * oo::parseXMLPList() - the NSPropertyListXMLFormat_v1_0 branch of GNUstep base 1.31.1's
	    +[NSPropertyListSerialization propertyListWithData:...]: the GSXMLPListParser delegate
	    (NSPropertyList.m) driven by GSSloppyXMLParser, GNUstep's own non-validating XML scanner
	    (NSXMLParser.m), ported as written. What that means in practice:

	      - The <?xml ...?> declaration must be the very first byte: leading whitespace or a BOM
	        fails the parse. DOCTYPE, comments, processing instructions and attributes are
	        skipped; CDATA sections are DROPPED (GSXMLPListParser has no CDATA callback).
	      - Tags must nest exactly; an unknown element (anything but plist, dict, array, key,
	        string, data, date, integer, real, true, false) fails when it closes.
	      - Text inside key/string/... is kept verbatim (leading and trailing whitespace too).
	        Text between container tags is trimmed and GLUED onto the next key or value:
	        <dict>x<key>k</key>... has the key "xk".
	      - Entities: the five predefined ones and &#ddd; / &#xhh; (6 digits at most); any other
	        entity becomes "". A '&' without a ';' before the next '<' fails the parse.
	      - In <key> and <string>, \Uxxxx (capital U, exactly four hex digits) is a UTF-16 unit.
	      - <integer> is strtoll of the text (so " 12 " is 12, "1.9" is 1, overflow saturates),
	        stored unsigned unless the text starts with '-'; <real> is strtod; <data> is
	        GSMimeDocument's lenient base64; <date> see PList.hpp's parseCalendarDate().
	      - The result is the LAST completed top-level value; an empty <plist/> is nil without an
	        error (a null PList here). A value in a dict without a preceding <key> fails.
	      - Byte-order marks follow NSString (see PList.hpp): an entity or \U escape for U+FEFF
	        or U+FFFE is "", and a text chunk starting with U+FEFF loses it.
	      - The bytes are UTF-8, or ISO-8859-1 when they are not valid UTF-8 or the declaration
	        says so (GNUstep scans the whole document for encoding="..."). UTF-16/32 fail.

	Every failure has GNUstep's single message, "failed to parse as XML property list".
*/

#ifndef OOFND_PLISTXML_HPP
#define OOFND_PLISTXML_HPP

// Suspend OOCocoa.h's `#define true 1` / `#define false 0` for this header (see oofnd/Data.hpp,
// proposed ADR-0028); restored at the end.
#pragma push_macro("true")
#pragma push_macro("false")
#undef true
#undef false

#include "oofnd/Expected.hpp"
#include "oofnd/PList.hpp"

#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <optional>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace oo {

// OOPListParsing.m's ChangeDTDIfApplicable(), byte for byte.
inline std::string changeDTDIfApplicable(std::string_view data)
{
	static constexpr std::string_view kXmlDecl = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>";
	static constexpr std::string_view kAppleDTDs[] = {
		"<!DOCTYPE plist PUBLIC \"-//Apple Computer//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">",
		"<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">",
	};
	static constexpr std::string_view kGNUstepDTD =
		"<!DOCTYPE plist PUBLIC \"-//GNUstep//DTD plist 0.9//EN\" \"http://www.gnustep.org/plist-0_9.xml\">";

	// `length < sizeof xmlDeclLine`: sizeof counts the NUL, so the declaration alone passes.
	if (data.size() < kXmlDecl.size() + 1) return std::string(data);
	if (data.substr(0, kXmlDecl.size()) != kXmlDecl) return std::string(data);
	std::size_t offset = kXmlDecl.size();
	auto isSpace = [](unsigned char c) { return c == ' ' || (c >= '\t' && c <= '\r'); };
	while (offset < data.size() && isSpace(static_cast<unsigned char>(data[offset]))) ++offset;
	for (std::string_view dtd : kAppleDTDs)
	{
		if (dtd.size() <= data.size() - offset && data.substr(offset, dtd.size()) == dtd)
		{
			std::string out;
			out.reserve(data.size());
			out += kXmlDecl;
			out += '\n';
			out += kGNUstepDTD;
			out += data.substr(offset + dtd.size());
			return out;
		}
	}
	return std::string(data);
}

namespace plist_detail {

inline bool isCSpace(int c) noexcept { return c == ' ' || (c >= '\t' && c <= '\r'); }

// NSString -initWithData:encoding:NSUTF8StringEncoding accepts exactly well-formed UTF-8.
inline bool isStrictUtf8(std::string_view s) noexcept
{
	const auto* p = reinterpret_cast<const unsigned char*>(s.data());
	const std::size_t n = s.size();
	std::size_t i = 0;
	while (i < n)
	{
		const unsigned char b = p[i];
		std::size_t len;
		std::uint32_t c;
		if (b < 0x80) { i++; continue; }
		if (b >= 0xC2 && b <= 0xDF) { len = 2; c = b & 0x1Fu; }
		else if (b >= 0xE0 && b <= 0xEF) { len = 3; c = b & 0x0Fu; }
		else if (b >= 0xF0 && b <= 0xF4) { len = 4; c = b & 0x07u; }
		else return false;
		if (i + len > n) return false;
		for (std::size_t k = 1; k < len; ++k)
		{
			if ((p[i + k] & 0xC0) != 0x80) return false;
			c = (c << 6) | (p[i + k] & 0x3Fu);
		}
		if ((len == 3 && c < 0x800) || (len == 4 && (c < 0x10000 || c > 0x10FFFF)) || (c >= 0xD800 && c <= 0xDFFF))
		{
			return false;
		}
		i += len;
	}
	return true;
}

// +[GSMimeDocument charsetForXml:] for single-byte data: the lower-cased value of the first
// quoted string after an `encoding` token anywhere in the document (which may be ""), else
// "utf-8"; "utf-16" or "ucs-4" (not supported by oofnd) when the byte pattern says so.
inline std::string charsetForXml(std::string_view xml)
{
	const auto* ptr = reinterpret_cast<const unsigned char*>(xml.data());
	const auto* end = ptr + xml.size();
	if (xml.size() < 4) return "utf-8";   // nil -> GSUndefinedEncoding -> UTF-8 guess
	if ((ptr[0] == 0xFE && ptr[1] == 0xFF) || (ptr[0] == 0xFF && ptr[1] == 0xFE)) return "utf-16";
	if (ptr[0] == 0xEF && ptr[1] == 0xBB && ptr[2] == 0xBF) return "utf-8";
	if (ptr[0] == 0 || ptr[1] == 0)   // GNUstep's two- and four-byte patterns all have one of these
	{
		const bool four = (ptr[0] == 0 && ptr[1] == 0) || (ptr[2] == 0 && ptr[3] == 0);
		return four ? "ucs-4" : "utf-16";
	}
	while (ptr + 1 <= end && isCSpace(*ptr)) ptr++;
	if (ptr + 20 >= end || ptr[0] != '<' || ptr[1] != '?') return "utf-8";
	ptr += 5;
	char buffer[31];
	std::size_t buflen = 0;
	unsigned char quote = 0;
	bool found = false;
	while (ptr + 1 <= end)
	{
		const unsigned char c = *ptr++;
		if (quote == 0)
		{
			if (c == '\'' || c == '"')
			{
				buflen = 0;
				quote = c;
			}
			else if (isCSpace(c) || c == '=')
			{
				if (buflen == 8)
				{
					buffer[8] = '\0';
					std::string token(buffer, 8);
					for (char& ch : token) ch = (ch >= 'A' && ch <= 'Z') ? static_cast<char>(ch - 'A' + 'a') : ch;
					if (token == "encoding") found = true;
				}
				buflen = 0;
			}
			else
			{
				if (buflen == 30) buflen = 0;
				buffer[buflen++] = static_cast<char>(c);
			}
		}
		else if (c == quote)
		{
			if (found)
			{
				std::string cs(buffer, buflen);
				for (char& ch : cs) ch = (ch >= 'A' && ch <= 'Z') ? static_cast<char>(ch - 'A' + 'a') : ch;
				return cs;
			}
			buflen = 0;
			quote = 0;
		}
		else
		{
			if (buflen == 30) buflen = 0;
			buffer[buflen++] = static_cast<char>(c);
		}
	}
	return "utf-8";
}

// -[NSXMLParser initWithData:]: decode by the declared charset, falling back to ISO-8859-1 when
// that fails, and re-encode as UTF-8. nullopt for encodings oofnd does not read (ADR-0027 item 6).
inline std::optional<std::string> xmlDataAsUtf8(std::string_view data)
{
	const std::string charset = charsetForXml(data);
	// An empty or unknown name is GSUndefinedEncoding, which GNUstep reads as it reads UTF-8.
	if (charset.rfind("utf-16", 0) == 0 || charset.rfind("utf-32", 0) == 0 || charset == "ucs-2" || charset == "ucs-4")
	{
		return std::nullopt;
	}
	const bool latin1 = charset == "iso-8859-1" || charset == "latin1" || charset == "iso_8859-1" || charset == "iso-latin-1";
	const bool ascii = charset == "us-ascii" || charset == "ascii";
	bool decodes = !latin1 && isStrictUtf8(data);
	if (decodes && ascii)
	{
		for (unsigned char b : data) decodes = decodes && b < 0x80;   // NSASCIIStringEncoding
	}
	if (decodes) return std::string(data);
	std::string out;
	out.reserve(data.size() + data.size() / 8);
	for (unsigned char b : data)
	{
		if (b < 0x80)
		{
			out += static_cast<char>(b);
		}
		else
		{
			out += static_cast<char>(0xC0 | (b >> 6));
			out += static_cast<char>(0x80 | (b & 0x3F));
		}
	}
	return out;
}

// +[GSMimeDocument decodeBase64:]: skips unknown characters (not counting them), stops at NUL,
// treats a missing tail as '=' padding.
inline Data decodeMimeBase64(std::string_view source)
{
	std::vector<std::uint8_t> out;
	if (source.empty()) return Data();
	long length = static_cast<long>(source.size());
	unsigned char buf[4] = {0, 0, 0, 0};
	unsigned char group[3];
	unsigned pos = 0;
	int pad = 0;
	auto decodeGroup = [](const unsigned char in[4], unsigned char o[3]) {
		o[0] = static_cast<unsigned char>((in[0] << 2) | ((in[1] & 0x30) >> 4));
		o[1] = static_cast<unsigned char>(((in[1] & 0x0F) << 4) | ((in[2] & 0x3C) >> 2));
		o[2] = static_cast<unsigned char>(((in[2] & 0x03) << 6) | (in[3] & 0x3F));
	};
	for (unsigned char uc : source)
	{
		if (uc == '\0') break;
		int c = uc;
		if (c >= 'A' && c <= 'Z') c -= 'A';
		else if (c >= 'a' && c <= 'z') c = c - 'a' + 26;
		else if (c >= '0' && c <= '9') c = c - '0' + 52;
		else if (c == '/' || c == '_') c = 63;
		else if (c == '+' || c == '-') c = 62;
		else if (c == '=')
		{
			c = -1;
			pad++;
		}
		else
		{
			c = -1;
			length--;
		}
		if (c >= 0)
		{
			buf[pos++] = static_cast<unsigned char>(c);
			if (pos == 4)
			{
				pos = 0;
				decodeGroup(buf, group);
				out.insert(out.end(), group, group + 3);
			}
		}
	}
	if (length % 4 > 0) pad += static_cast<int>(4 - length % 4);
	if (pos > 0)
	{
		for (unsigned i = pos; i < 4; i++) buf[i] = 0;
		decodeGroup(buf, group);
		if (pad > 3) pad = 3;
		out.insert(out.end(), group, group + (3 - pad));
	}
	return Data(std::move(out));
}

// GSXMLPListParser's -unescape: \Uxxxx (exactly four hex digits) becomes that UTF-16 unit.
inline std::string unescapeXMLPListString(const std::string& utf8)
{
	if (utf8.find("\\U") == std::string::npos) return utf8;
	std::u16string value = utf8ToUtf16(utf8);
	auto isHex = [](char16_t c) { return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F'); };
	auto hexVal = [](char16_t c) { return c <= '9' ? c - '0' : (c >= 'a' ? c - 'a' + 10 : c - 'A' + 10); };
	std::size_t loc = 0, len = value.size();   // NSRange r = {loc, len}
	while (len >= 6)
	{
		const std::size_t found = value.find(u"\\U", loc);
		if (found == std::u16string::npos || found + 2 > loc + len) break;   // r.length == 0
		loc = found;
		len = 2;
		if (value.size() < loc + 6) break;   // r stays {loc, 2}: the loop ends
		if (isHex(value[loc + 2]) && isHex(value[loc + 3]) && isHex(value[loc + 4]) && isHex(value[loc + 5]))
		{
			const char16_t v = static_cast<char16_t>((hexVal(value[loc + 2]) << 12) | (hexVal(value[loc + 3]) << 8)
													 | (hexVal(value[loc + 4]) << 4) | hexVal(value[loc + 5]));
			// The replacement is [NSString initWithCharacters:&v length:1], so U+FEFF and U+FFFE
			// become "" (and the location still steps on by one).
			value.replace(loc, 6, (v == 0xFEFF || v == 0xFFFE) ? 0 : 1, v);
			loc += 1;
			len = 0;
		}
		const std::size_t next = loc + len;
		loc = next;
		len = value.size() - next;
	}
	return utf16ToUtf8(value);
}

// GSSloppyXMLParser (NSXMLParser.m) with GSXMLPListParser (NSPropertyList.m) as its delegate.
class XMLPListReader
{
public:
	explicit XMLPListReader(std::string data) : data_(std::move(data))
	{
		bytes_ = reinterpret_cast<const unsigned char*>(data_.data());
		cend_ = data_.size();
		if (cend_ - cp_ > 2 && bytes_[0] == 0xEF && bytes_[1] == 0xBB && bytes_[2] == 0xBF) cp_ += 3;   // BOM
	}

	// -parse. True on success; result() is then the plist (null for nil).
	bool parse()
	{
		std::size_t vp = cp_;
		int c;
		ignorable_ = true;
		whitespace_ = true;
		c = cget();
		while (!abort_)
		{
			if (c == '<' || c == kEOF || c == '&')
			{
				if (c == '<') ignorable_ = true;
				if (cp_ - vp > 1)   // push out any characters collected so far
				{
					std::size_t p = cp_ - 1;
					if (ignorable_)
					{
						if (whitespace_) p = vp;
						else while (p > vp && isCSpace(bytes_[p - 1])) p--;
					}
					if (hasElement_)
					{
						if (p > vp) foundCharacters(vp, p - vp);
						if (p < cp_ - 1) foundCharacters(p, cp_ - 1 - p);
					}
					vp = cp_;
					if (abort_) return false;   // "invalid character data"
				}
			}

			if (c == kEOF)
			{
				return tagPath_.empty() ? true : fail();   // "unexpected end of file"
			}
			if (c == '&')
			{
				ignorable_ = false;
				whitespace_ = true;
				std::string entity;
				if (!parseEntity(entity)) return fail();   // "'&' not followed by entity name or number"
				appendCharacters(entity);
				vp = cp_;
				c = cget();
				continue;
			}
			if (c != '<')
			{
				if (whitespace_ && !isCSpace(c))
				{
					if (ignorable_ && cp_ - vp > 1)
					{
						foundCharacters(vp, cp_ - vp - 1);   // accumulated whitespace
						vp = cp_ - 1;
					}
					ignorable_ = false;
					whitespace_ = false;
				}
				c = cget();
				continue;
			}

			// '<'
			std::size_t tp = cp_;
			const std::size_t sp = tp - 1;
			ignorable_ = true;
			whitespace_ = true;
			if (cp_ + 3 < cend_ && std::memcmp(bytes_ + cp_, "!--", 3) == 0)
			{
				cp_ += 3;
				while (cp_ + 3 < cend_ && std::memcmp(bytes_ + cp_, "-->", 3) != 0) cp_++;
				cp_ += 3;   // may go beyond cend_; cget() then reports kEOF
				vp = cp_;
				c = cget();
				continue;
			}
			if (cp_ + 8 < cend_ && std::memcmp(bytes_ + cp_, "![CDATA[", 8) == 0)
			{
				cp_ += 8;
				while (cp_ + 3 < cend_ && std::memcmp(bytes_ + cp_, "]]>", 3) != 0) cp_++;
				cp_ += 3;   // the CDATA text is not delivered: GSXMLPListParser has no foundCDATA
				vp = cp_;
				c = cget();
				continue;
			}
			c = cget();
			if (c == '/' || c == '?')
			{
				c = cget();
			}
			else if (c == '!')
			{
				processDeclaration();
				if (abort_) return false;   // "invalid character in declaration ..."
				vp = cp_;
				c = cget();
				continue;
			}
			while (c != kEOF && !isCSpace(c) && c != '>' && c != '/' && c != '?') c = cget();
			const bool closing = byteAt(tp) == '/';
			const long tagStart = static_cast<long>(closing ? tp + 1 : tp);
			const long tagLen = static_cast<long>(cp_) - tagStart - 1;
			if (tagLen < 0) return fail();   // "invalid character in tag"
			const std::string_view rawTag(reinterpret_cast<const char*>(bytes_) + tagStart, static_cast<std::size_t>(tagLen));
			if (!isStrictUtf8(rawTag)) return fail();   // cut at the end of the data: "invalid character in tag"
			const std::string tag(utf8WithoutLeadingBOM(rawTag));   // NewUTF8STR() drops a leading BOM

			while (isCSpace(c)) c = cget();
			while (c != kEOF)
			{
				if (c == '/' && byteAt(tp) != '/')
				{
					c = cget();
					if (c != '>') return fail();   // "<tag/ is missing the >"
					processTag(tag, false);
					if (!abort_) processTag(tag, true);
					break;
				}
				if (c == '?' && byteAt(tp) == '?')
				{
					c = cget();
					if (c != '>') return fail();                   // "<?tag ...? is missing the >"
					if (tag == "?xml" && sp != 0) return fail();   // "bad <?xml > preamble"
					processTag(tag, false);
					break;
				}
				while (isCSpace(c)) c = cget();
				if (c == '>')
				{
					if (!abort_) processTag(tag, closing);
					break;
				}
				std::optional<std::string> arg = newQarg();
				if (!arg || arg->empty()) return fail();   // "empty attribute name"
				c = cget();
				while (isCSpace(c)) c = cget();
				if (c == '=')
				{
					c = cget();
					while (isCSpace(c)) c = cget();
					if (!newQarg()) return fail();   // -setObject:nil forKey: raises
					c = cget();
					while (isCSpace(c)) c = cget();
				}
			}
			vp = cp_;
			c = cget();
		}
		return false;   // "aborted"
	}

	PList result() { return std::move(plist_); }

private:
	static constexpr int kEOF = -1;

	int cget() { return cp_ < cend_ ? bytes_[cp_++] : kEOF; }
	int byteAt(std::size_t i) const { return i < cend_ ? bytes_[i] : kEOF; }
	bool fail()
	{
		abort_ = true;
		return false;
	}

	void foundCharacters(std::size_t start, std::size_t length)
	{
		// Each chunk is its own NSString from UTF-8 bytes: a leading U+FEFF is dropped. The data
		// is valid UTF-8 by now, but a chunk that runs to the end of it is one byte short (cget()
		// does not advance at the end), so it can end inside a character: NewUTF8STR() is then
		// nil and GNUstep fails the parse with "invalid character data".
		const std::string_view chunk(reinterpret_cast<const char*>(bytes_) + start, length);
		if (!isStrictUtf8(chunk))
		{
			abort_ = true;
			return;
		}
		appendCharacters(utf8WithoutLeadingBOM(chunk));
	}

	// -_parseEntity: after '&', up to ';'. False if a '<' or the end comes first.
	bool parseEntity(std::string& out)
	{
		const std::size_t ep = cp_;
		int c;
		do
		{
			c = cget();
		} while (c != kEOF && c != '<' && c != ';');
		if (c != ';') return false;
		out = newEntity(ep, cp_ - ep - 1);
		return true;
	}

	// -_newEntity:length: (shouldResolveExternalEntities is NO: unknown entities are "").
	std::string newEntity(std::size_t ep, std::size_t len)
	{
		const char* e = reinterpret_cast<const char*>(bytes_) + ep;
		if (len > 0 && e[0] == '#')
		{
			if (len < 8)
			{
				char buf[8];
				std::memcpy(buf, e + 1, len - 1);
				buf[len - 1] = '\0';
				unsigned int val = 0;
				int n = std::sscanf(buf, "x%x;", &val);
				if (n == 0)
				{
					int d = 0;
					n = std::sscanf(buf, "%d;", &d);
					val = static_cast<unsigned int>(d);
				}
				// (sscanf returning kEOF left GNUstep reading an uninitialised value: treated
				// here as not a number, ADR-0027 item 4.)
				if (n == 1)
				{
					if (val > 0x10FFFF)
					{
						abort_ = true;   // "invalid numeric entity codepoint"
						return std::string();
					}
					std::u16string u;
					if (val > 0xFFFF)
					{
						val -= 0x10000;
						u += static_cast<char16_t>(val / 0x400 + 0xD800);
						u += static_cast<char16_t>(val % 0x400 + 0xDC00);
					}
					else
					{
						u += static_cast<char16_t>(val);
					}
					applyInitWithCharactersBOM(u);   // -initWithCharacters:length:
					return utf16ToUtf8(u);
				}
			}
			return std::string();
		}
		const std::string_view name(e, len);
		if (name == "amp") return "&";
		if (name == "lt") return "<";
		if (name == "gt") return ">";
		if (name == "quot") return "\"";
		if (name == "apos") return "'";
		return std::string();
	}

	// -_newQarg: an attribute name or value, quoted or not. Only its extent (and entity errors)
	// matter here: GSXMLPListParser ignores attributes. nullopt for an unterminated quote, and
	// for text that is not UTF-8 (an unquoted one cut at the end of the data), which GNUstep also
	// reports as "invalid character in quoted string" (so the parse fails).
	std::optional<std::string> newQarg()
	{
		std::size_t ap = --cp_;
		int c = cget();
		std::size_t len;
		bool containsEntity = false;
		if (c == '"' || c == '\'')
		{
			const int quote = c;
			do
			{
				c = cget();
				if (c == kEOF) return std::nullopt;
				if (c == '&') containsEntity = true;
			} while (c != quote);
			len = cp_ - ap - 2;
			ap++;
		}
		else
		{
			while (!isCSpace(c) && c != '>' && c != '/' && c != '?' && c != '=' && c != kEOF)
			{
				if (c == '&') containsEntity = true;
				c = cget();
			}
			cp_--;   // back to the terminating character (one further at kEOF, as GNUstep does)
			len = cp_ - ap;
		}
		if (!isStrictUtf8(std::string_view(reinterpret_cast<const char*>(bytes_) + ap, len)))
		{
			abort_ = true;
			return std::nullopt;
		}
		std::string out;
		if (containsEntity)
		{
			std::size_t start = ap;
			std::size_t ptr = ap;
			const std::size_t end = ap + len;
			while (ptr < end)
			{
				while (ptr < end && bytes_[ptr] != '&') ptr++;
				if (ptr > start)
				{
					out.append(utf8WithoutLeadingBOM(std::string_view(reinterpret_cast<const char*>(bytes_) + start, ptr - start)));
					start = ptr;
				}
				else
				{
					while (ptr < end && bytes_[ptr] != ';') ptr++;
					out += newEntity(start + 1, ptr - start - 1);
					if (ptr < end) ptr++;
					start = ptr;
				}
			}
			return out;
		}
		return std::string(utf8WithoutLeadingBOM(std::string_view(reinterpret_cast<const char*>(bytes_) + ap, len)));
	}

	// -_processDeclaration: <!DOCTYPE ...>, <!ELEMENT ...>, <!ENTITY ...>, <!ATTLIST ...>.
	void processDeclaration()
	{
		int c = cget();
		while (isCSpace(c)) c = cget();
		std::size_t tp = cp_ - 1;
		while (c != kEOF && !isCSpace(c) && c != '>') c = cget();
		const std::string_view rawDecl(reinterpret_cast<const char*>(bytes_) + tp, cp_ - tp - 1);
		const std::string decl(utf8WithoutLeadingBOM(rawDecl));   // NewUTF8STR() drops a leading BOM
		// Each word is a NewUTF8STR(): one cut at the end of the data can end inside a character,
		// and GNUstep then fails with "invalid character in declaration[ name/attr/type]".
		const auto wordIsValid = [this](std::size_t from) {
			return isStrictUtf8(std::string_view(reinterpret_cast<const char*>(bytes_) + from, cp_ - from - 1));
		};
		if (!isStrictUtf8(rawDecl))
		{
			abort_ = true;
			return;
		}
		while (isCSpace(c)) c = cget();
		tp = cp_ - 1;
		while (c != kEOF && !isCSpace(c) && c != '>') c = cget();   // the name
		if (!wordIsValid(tp))
		{
			abort_ = true;
			return;
		}
		if (decl == "ATTLIST")
		{
			while (c != kEOF && c != '>')
			{
				while (isCSpace(c)) c = cget();
				tp = cp_ - 1;
				while (c != kEOF && !isCSpace(c) && c != '>') c = cget();   // attribute
				if (!wordIsValid(tp))
				{
					abort_ = true;
					return;
				}
				while (isCSpace(c)) c = cget();
				tp = cp_ - 1;
				while (c != kEOF && !isCSpace(c) && c != '>') c = cget();   // type
				if (!wordIsValid(tp))
				{
					abort_ = true;
					return;
				}
				while (isCSpace(c)) c = cget();
				if (c == '#')
				{
					while (c != kEOF && !isCSpace(c) && c != '>') c = cget();
				}
				else
				{
					// At the end of the data, -_newQarg steps back onto the last byte; unless that
					// byte opens a quote, this loop then re-reads it forever and GNUstep never
					// returns. oofnd fails the parse instead (ADR-0027 item 4).
					if (c == kEOF && bytes_[cend_ - 1] != '"' && bytes_[cend_ - 1] != '\'')
					{
						abort_ = true;
						return;
					}
					(void)newQarg();
					c = cget();
				}
				while (isCSpace(c)) c = cget();
			}
		}
		else if (decl == "DOCTYPE")
		{
			while (isCSpace(c)) c = cget();
			while (c != kEOF && c != '[' && c != '>') c = cget();
			if (c == '[')
			{
				while (c != kEOF && c != ']')
				{
					if (c == '<')
					{
						c = cget();
						if (c == '!')
						{
							processDeclaration();
							c = cget();
						}
					}
					else
					{
						c = cget();
					}
				}
				if (c == ']')
				{
					while (c != kEOF && c != '>') c = cget();
				}
			}
		}
		else if (decl == "ELEMENT" || decl == "ENTITY")
		{
			while (c != kEOF && c != '>') c = cget();
		}
	}

	// -_processTag:isEnd:withAttributes:
	void processTag(const std::string& tag, bool isEnd)
	{
		if (!isEnd)
		{
			if (!tag.empty() && tag[0] == '?') return;   // <?xml ...?> and processing instructions
			hasElement_ = true;
			tagPath_.push_back(tag);
			didStartElement(tag);
		}
		else
		{
			if (tagPath_.empty() || tagPath_.back() != tag)
			{
				abort_ = true;   // "tag nesting error"
				return;
			}
			didEndElement(tag);
			tagPath_.pop_back();
		}
	}

	// --- GSXMLPListParser ----------------------------------------------------------------------

	struct Frame
	{
		std::optional<std::string> keyInParent;   // NSNull when there was no pending key
		PList container;
	};

	void appendCharacters(std::string_view s)
	{
		if (inPCData_)
		{
			value_ += s;
			return;
		}
		// -stringByTrimmingSpaces (ASCII isspace only)
		std::size_t b = 0, e = s.size();
		while (b < e && isCSpace(static_cast<unsigned char>(s[b]))) b++;
		while (e > b && isCSpace(static_cast<unsigned char>(s[e - 1]))) e--;
		value_ += s.substr(b, e - b);
	}

	void didStartElement(const std::string& name)
	{
		if (name == "dict" || name == "array")
		{
			stack_.push_back(Frame{std::move(key_), name == "dict" ? PList(PList::Dict{}) : PList(PList::Array{})});
			key_.reset();
			inDictionary_ = name == "dict";
			inArray_ = !inDictionary_;
		}
		else if (name != "plist")
		{
			inPCData_ = true;
		}
	}

	void didEndElement(const std::string& name)
	{
		inPCData_ = false;
		std::optional<PList> item;   // plist; nullopt is nil
		if (name == "dict" || name == "array")
		{
			item = std::move(stack_.back().container);
			key_ = std::move(stack_.back().keyInParent);
			stack_.pop_back();
			inArray_ = inDictionary_ = false;
			if (!stack_.empty())
			{
				inArray_ = stack_.back().container.isArray();
				inDictionary_ = stack_.back().container.isDict();
			}
		}
		else if (name == "key")
		{
			key_ = unescapeXMLPListString(value_);
			value_.clear();
			return;
		}
		else if (name == "data")
		{
			for (unsigned char ch : value_)
			{
				if (ch >= 0x80)   // -dataUsingEncoding:NSASCIIStringEncoding is nil
				{
					abort_ = true;
					return;
				}
			}
			item = PList(decodeMimeBase64(value_));
		}
		else if (name == "date")
		{
			// NSCalendarDate reads [description cString]: GNUstep's default C-string encoding,
			// ISO-8859-1 in the game's build, up to the first NUL. A character beyond U+00FF
			// raises NSCharacterConversionException out of the parser; oofnd fails the parse
			// (ADR-0027 item 7). Found by the GNUstep differential fuzzer (bead oo-g2k).
			const std::u16string units = utf8ToUtf16(value_);
			std::string latin1;
			for (char16_t u : units)
			{
				if (u > 0xFF)
				{
					abort_ = true;
					return;
				}
				latin1 += static_cast<char>(u);
			}
			const bool zulu = !value_.empty() && value_.back() == 'Z' && units.size() == 20;
			if (const std::size_t nul = latin1.find('\0'); nul != std::string::npos) latin1.resize(nul);
			if (std::optional<double> d = parseCalendarDate(latin1, zulu)) item = PList(PList::Date{*d});
		}
		else if (name == "string")
		{
			item = PList(unescapeXMLPListString(value_));
		}
		else if (name == "integer")
		{
			const long long v = std::strtoll(value_.c_str(), nullptr, 10);   // -longLongValue
			if (!value_.empty() && value_[0] == '-') item = PList::signedInteger(v);
			else item = PList::unsignedInteger(static_cast<unsigned long long>(v));
		}
		else if (name == "real")
		{
			item = PList(std::strtod(value_.c_str(), nullptr));
		}
		else if (name == "true")
		{
			item = PList(true);
		}
		else if (name == "false")
		{
			item = PList(false);
		}
		else if (name == "plist")
		{
			value_.clear();
			return;
		}
		else
		{
			abort_ = true;   // invalid tag
			return;
		}

		if (inArray_ || inDictionary_)
		{
			if (inDictionary_ && !key_)
			{
				abort_ = true;
				return;
			}
			if (!item)
			{
				// -addObject:nil / -setObject:nil forKey: raise NSInvalidArgumentException out of
				// GNUstep's parser; oofnd fails the parse instead (ADR-0027 item 7).
				abort_ = true;
				return;
			}
			// GNUstep also keeps this value as `plist`, but the enclosing container always
			// replaces it before a successful end, so it is moved, not copied.
			if (inArray_)
			{
				stack_.back().container.getIf<PList::Array>()->push_back(std::move(*item));
			}
			else
			{
				stack_.back().container.getIf<PList::Dict>()->insert_or_assign(std::move(*key_), std::move(*item));
				key_.reset();
			}
		}
		else
		{
			plist_ = item ? std::move(*item) : PList();
		}
		value_.clear();
	}

	std::string data_;
	const unsigned char* bytes_ = nullptr;
	std::size_t cp_ = 0;
	std::size_t cend_ = 0;
	bool abort_ = false;
	bool ignorable_ = true;
	bool whitespace_ = true;
	bool hasElement_ = false;
	std::vector<std::string> tagPath_;

	std::string value_;
	std::vector<Frame> stack_;
	std::optional<std::string> key_;
	bool inArray_ = false;
	bool inDictionary_ = false;
	bool inPCData_ = false;
	PList plist_;
};

} // namespace plist_detail

// The XML branch of -[NSPropertyListSerialization propertyListWithData:...] (no DTD change: that
// is OOPListParsing's step, changeDTDIfApplicable() above). A parse GNUstep completes with nil
// yields a null PList.
inline Expected<PList, PListError> parseXMLPList(std::string_view bytes)
{
	std::optional<std::string> utf8 = plist_detail::xmlDataAsUtf8(bytes);
	if (utf8)
	{
		plist_detail::XMLPListReader reader(std::move(*utf8));
		if (reader.parse()) return reader.result();
	}
	return Unexpected(PListError{"failed to parse as XML property list"});
}

} // namespace oo

#pragma pop_macro("false")
#pragma pop_macro("true")

#endif // OOFND_PLISTXML_HPP
