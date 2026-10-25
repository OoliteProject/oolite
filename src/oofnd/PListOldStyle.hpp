/*	oofnd/PListOldStyle.hpp
	The old-style (OpenStep / GNUstep text) property-list scanner: a port of GNUstep base
	1.31.1's parsePlItem() and helpers (Source/NSPropertyList.m), which is what
	+[NSPropertyListSerialization propertyListFromData:...] runs - and so what
	OOPropertyListFromData runs - on any data that does not start with "<?" (XML) or look binary.

	    oo::Expected<oo::PList, oo::PListError> r = oo::parseOldStylePList(bytes);
	    if (!r) OOLog(..., "%s", r.error().description().c_str());

	It reproduces GNUstep quirk-for-quirk (ADR-0027), including the odd parts:

	  * Whitespace is the bytes 0x08-0x0D and space (GNUstep's fixed table: backspace counts).
	    "//" and "/" "*" comments are whitespace; an unterminated one is an error, except after the
	    top-level item, where running off the end is how a plist is supposed to end.
	  * An unquoted string is a run of bytes outside GNUstep's `quotables` table (letters, digits
	    and !#$%&*+-./:?@^_|~); bytes >= 0x80 end it. It may be EMPTY: "=" parses as "" and then
	    fails with "extra data after parsed string".
	  * A quoted string is UTF-8 (strictly: overlong forms and encoded surrogates are errors).
	    Escapes: \a \b \t \r \n \v \f; \ followed by 1-3 octal digits; \U or \u followed by 0-4
	    hex digits (so "\u4x" is U+0004 then 'x', and "\u" alone is U+0000); any other escaped
	    character is itself. An octal or hex escape still open at the closing quote is DROPPED
	    ("a\u12" is "a"). Lone surrogates survive (as WTF-8, see PList.hpp). As in any NSString
	    GNUstep builds from UTF-16 units, a leading U+FEFF is dropped and a leading U+FFFE drops
	    itself and byte-swaps the rest ("\UFFFEx" is U+7800).
	  * Line numbers in error messages count newlines, and a newline that terminates an octal or
	    hex escape is counted twice (GNUstep rescans it); "char" is the byte offset + 1.
	  * After the top-level item only whitespace and comments may follow.
  * Arrays "( a, b, )" may end in a comma; ",," is an empty string. Dictionaries
    "{ k = v; }" may omit the last ';' and keep the last of repeated keys; keys must be strings
    (ADR-0027 item 2). Data "<0a0b 0c>" allows whitespace and comments between octets.
  * GNUstep's extensions "<*I12>", "<*R1.5>", "<*BY>", "<*D2001-01-01 00:00:00 +0000>" and
    "<[base64]>" are read, and make the reported format GNUstep. A <*D> or <[...]> GNUstep cannot
    decode is nil WITHOUT an error, which makes the whole plist nil: oofnd returns a null PList.

	Error messages are GNUstep's, formatted as its propertyListWithData formats them:
	"Parse failed at line L (char C) - <reason>".
*/

#ifndef OOFND_PLISTOLDSTYLE_HPP
#define OOFND_PLISTOLDSTYLE_HPP

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
#include <optional>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace oo {

namespace plist_detail {

// GNUstep's `quotables` and `whitespace` bitmaps (NSPropertyList.m), bit (c % 8) of byte c / 8.
inline constexpr unsigned char kQuotables[32] = {
	0xff, 0xff, 0xff, 0xff, 0x85, 0x13, 0x00, 0x78, 0x00, 0x00, 0x00, 0x38, 0x01, 0x00, 0x00, 0xa8,
	0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
};
inline constexpr unsigned char kWhitespace[32] = {
	0x00, 0x3f, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
	0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
};

constexpr bool isQuotable(unsigned char c) noexcept { return (kQuotables[c / 8] & (1u << (c % 8))) != 0; }
constexpr bool isPListSpace(unsigned char c) noexcept { return (kWhitespace[c / 8] & (1u << (c % 8))) != 0; }

// isxdigit()/char2num() in the C locale, total over all code units.
constexpr bool isHexDigit(std::uint32_t c) noexcept
{
	return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F');
}
constexpr unsigned hexValue(std::uint32_t c) noexcept
{
	return c <= '9' ? c - '0' : (c >= 'a' ? c - 'a' + 10 : c - 'A' + 10);
}

// Strict UTF-8 -> UTF-16 (GSToUnicode's NSUTF8StringEncoding): false on any malformed sequence,
// overlong form, encoded surrogate or code point above U+10FFFF.
inline bool decodeUtf8Strict(const unsigned char* p, std::size_t n, std::u16string& out)
{
	std::size_t i = 0;
	while (i < n)
	{
		const unsigned char b = p[i];
		std::uint32_t c;
		std::size_t len;
		if (b < 0x80) { c = b; len = 1; }
		else if (b >= 0xC2 && b <= 0xDF) { c = b & 0x1Fu; len = 2; }
		else if (b >= 0xE0 && b <= 0xEF) { c = b & 0x0Fu; len = 3; }
		else if (b >= 0xF0 && b <= 0xF4) { c = b & 0x07u; len = 4; }
		else return false;
		if (i + len > n) return false;
		for (std::size_t k = 1; k < len; ++k)
		{
			if ((p[i + k] & 0xC0) != 0x80) return false;
			c = (c << 6) | (p[i + k] & 0x3Fu);
		}
		if ((len == 3 && c < 0x800) || (len == 4 && (c < 0x10000 || c > 0x10FFFF))) return false;
		if (c >= 0xD800 && c <= 0xDFFF) return false;
		if (c >= 0x10000)
		{
			out += static_cast<char16_t>(0xD800 + ((c - 0x10000) >> 10));
			out += static_cast<char16_t>(0xDC00 + ((c - 0x10000) & 0x3FF));
		}
		else
		{
			out += static_cast<char16_t>(c);
		}
		i += len;
	}
	return true;
}

// -[NSData initWithBase64EncodedData:options:NSDataBase64DecodingIgnoreUnknownCharacters]
// (NSData.m): unknown characters are skipped; after '=' only '=' or unknown characters may
// follow (anything else is nil); a '=' with no pending sextets stands for a zero byte (OS X
// compatibility); a partial final group yields (sextets - 1) bytes.
inline std::optional<Data> decodeBase64IgnoringUnknown(const unsigned char* src, std::size_t length)
{
	auto isBase64 = [](int c) {
		return (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '/' || c == '+';
	};
	auto decodeGroup = [](const unsigned char in[4], unsigned char out[3]) {
		out[0] = static_cast<unsigned char>((in[0] << 2) | ((in[1] & 0x30) >> 4));
		out[1] = static_cast<unsigned char>(((in[1] & 0x0F) << 4) | ((in[2] & 0x3C) >> 2));
		out[2] = static_cast<unsigned char>(((in[2] & 0x03) << 6) | (in[3] & 0x3F));
	};
	std::vector<std::uint8_t> out;
	out.reserve(((length + 3) * 3) / 4);
	unsigned char buf[4] = {0, 0, 0, 0};
	unsigned char group[3];
	unsigned pos = 0;
	std::size_t i = 0;
	while (i < length)
	{
		int c = src[i++];
		if (c >= 'A' && c <= 'Z') c -= 'A';
		else if (c >= 'a' && c <= 'z') c = c - 'a' + 26;
		else if (c >= '0' && c <= '9') c = c - '0' + 52;
		else if (c == '/') c = 63;
		else if (c == '+') c = 62;
		else if (c == '=')
		{
			while (i < length)
			{
				c = src[i++];
				if (c != '=')
				{
					if (!isBase64(c)) continue;   // an unknown character
					return std::nullopt;
				}
			}
			if (pos == 0) out.push_back(0);
			c = -1;
		}
		else
		{
			c = -1;   // ignored
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
	if (pos > 0)
	{
		for (unsigned k = pos; k < 4; k++) buf[k] = 0;
		pos--;
		if (pos > 0)
		{
			decodeGroup(buf, group);
			out.insert(out.end(), group, group + pos);
		}
	}
	return Data(std::move(out));
}

// GNUstep's `pldata` plus the parse functions that take it.
class OldStyleScanner
{
public:
	explicit OldStyleScanner(std::string_view bytes) noexcept
		: ptr_(reinterpret_cast<const unsigned char*>(bytes.data())), end_(bytes.size())
	{
	}

	// parsePlItem(). nullopt is GNUstep's nil; err_ says whether that was an error.
	std::optional<PList> parseItem()
	{
		const bool start = (pos_ == 0);
		if (!skipSpace()) return std::nullopt;

		std::optional<PList> result;
		switch (ptr_[pos_])
		{
			case '{':
				result = parseDictionary();
				break;

			case '(':
				result = parseArray();
				break;

			case '<':
				pos_++;
				if (pos_ < end_ && ptr_[pos_] == '*') result = parseTypedValue();
				else if (pos_ < end_ && ptr_[pos_] == '[') result = parseBase64Data();
				else result = parseHexData();
				break;

			case '"':
				result = parseQuotedString();
				break;

			default:
				result = parseUnquotedString();
				break;
		}
		if (start && result && err_ == nullptr)
		{
			if (skipSpace())
			{
				err_ = "extra data after parsed string";
				result.reset();
			}
			else
			{
				err_ = nullptr;   // reaching the end is expected here
			}
		}
		return result;
	}

	const char* error() const noexcept { return err_; }
	bool usedGNUstepExtensions() const noexcept { return !old_; }

	std::string errorMessage() const
	{
		char buf[64];
		std::snprintf(buf, sizeof buf, "Parse failed at line %u (char %zu) - ", lin_ + 1, pos_ + 1);
		return std::string(buf) + err_;
	}

private:
	// skipSpace(): skips whitespace and comments, counting lines. True if anything is left.
	bool skipSpace()
	{
		unsigned char c;
		while (pos_ < end_)
		{
			c = ptr_[pos_];
			if (!isPListSpace(c))
			{
				if (c == '/' && pos_ < end_ - 1)
				{
					if (ptr_[pos_ + 1] == '/')
					{
						pos_ += 2;
						while (pos_ < end_)
						{
							c = ptr_[pos_];
							if (c == '\n') break;
							pos_++;
						}
						if (pos_ >= end_)
						{
							err_ = "reached end of string in comment";
							return false;
						}
					}
					else if (ptr_[pos_ + 1] == '*')
					{
						pos_ += 2;
						while (pos_ < end_)
						{
							c = ptr_[pos_];
							if (c == '\n')
							{
								lin_++;
							}
							else if (c == '*' && pos_ < end_ - 1 && ptr_[pos_ + 1] == '/')
							{
								pos_++;   // skip past '*'
								break;
							}
							pos_++;
						}
						if (pos_ >= end_)
						{
							err_ = "reached end of string in comment";
							return false;
						}
					}
					else
					{
						return true;
					}
				}
				else
				{
					return true;
				}
			}
			if (c == '\n') lin_++;
			pos_++;
		}
		err_ = "reached end of string";
		return false;
	}

	std::optional<PList> parseQuotedString()
	{
		const std::size_t start = ++pos_;
		unsigned escaped = 0;
		std::size_t shrink = 0;
		bool hex = false;

		// Pass 1, over the bytes: find the closing quote.
		while (pos_ < end_)
		{
			const unsigned char c = ptr_[pos_];
			if (escaped)
			{
				if (escaped == 1 && c >= '0' && c <= '7')
				{
					escaped = 2;
					hex = false;
				}
				else if (escaped == 1 && (c == 'u' || c == 'U'))
				{
					escaped = 2;
					hex = true;
				}
				else if (escaped > 1)
				{
					if (hex && isHexDigit(c))
					{
						shrink++;
						if (++escaped == 6) escaped = 0;
					}
					else if (c >= '0' && c <= '7')
					{
						shrink++;
						if (++escaped == 4) escaped = 0;
					}
					else
					{
						pos_--;   // rescan this character (its newline is counted twice)
						escaped = 0;
					}
				}
				else
				{
					escaped = 0;
				}
			}
			else
			{
				if (c == '\\')
				{
					escaped = 1;
					shrink++;
				}
				else if (c == '"')
				{
					break;
				}
			}
			if (c == '\n') lin_++;
			pos_++;
		}
		if (pos_ >= end_)
		{
			err_ = "reached end of string while parsing quoted string";
			return std::nullopt;
		}

		std::string text;
		if (pos_ - start - shrink != 0)
		{
			std::u16string temp;
			if (!decodeUtf8Strict(ptr_ + start, pos_ - start, temp))
			{
				err_ = "invalid utf8 data while parsing quoted string";
				return std::nullopt;
			}
			// Pass 2, over the UTF-16 units: apply the escapes.
			std::u16string chars;
			chars.reserve(temp.size());
			char16_t pending = 0;
			escaped = 0;
			hex = false;
			for (std::size_t j = 0; j < temp.size(); j++)
			{
				const char16_t c = temp[j];
				if (escaped)
				{
					if (escaped == 1 && c >= '0' && c <= '7')
					{
						pending = static_cast<char16_t>(c - '0');
						hex = false;
						escaped++;
					}
					else if (escaped == 1 && (c == 'u' || c == 'U'))
					{
						pending = 0;
						hex = true;
						escaped++;
					}
					else if (escaped > 1)
					{
						if (hex && isHexDigit(c))
						{
							pending = static_cast<char16_t>((pending << 4) | hexValue(c));
							if (++escaped == 6)
							{
								escaped = 0;
								chars += pending;
							}
						}
						else if (c >= '0' && c <= '7')
						{
							pending = static_cast<char16_t>((pending << 3) | (c - '0'));
							if (++escaped == 4)
							{
								escaped = 0;
								chars += pending;
							}
						}
						else
						{
							escaped = 0;
							j--;   // rescan
							chars += pending;
						}
					}
					else
					{
						escaped = 0;
						switch (c)
						{
							case 'a': chars += u'\a'; break;
							case 'b': chars += u'\b'; break;
							case 't': chars += u'\t'; break;
							case 'r': chars += u'\r'; break;
							case 'n': chars += u'\n'; break;
							case 'v': chars += u'\v'; break;
							case 'f': chars += u'\f'; break;
							default: chars += c; break;
						}
					}
				}
				else if (c == '\\')
				{
					escaped = 1;
				}
				else
				{
					chars += c;
				}
			}
			// An escape still open here is dropped, as GNUstep's length = k drops it. The units
			// then become an NSString through -initWithCharactersNoCopy:, BOM rules and all.
			applyInitWithCharactersBOM(chars);
			appendUtf16AsUtf8(text, chars.data(), chars.size());
		}
		pos_++;
		return PList(std::move(text));
	}

	std::optional<PList> parseUnquotedString()
	{
		const std::size_t start = pos_;
		while (pos_ < end_ && !isQuotable(ptr_[pos_])) pos_++;
		// Every byte here is < 0x80 (the rest are quotable), so this is ASCII.
		return PList(std::string(reinterpret_cast<const char*>(ptr_ + start), pos_ - start));
	}

	// '{' key = value; ... '}'. The last ';' may be missing (GSMacOSXCompatible is NO); a repeated
	// key keeps the last value (-setObject:forKey:). A nil key or value without an error (a
	// <*D...> or <[...]> GNUstep could not decode) makes the whole dictionary nil, silently.
	std::optional<PList> parseDictionary()
	{
		PList::Dict dict;
		pos_++;
		while (skipSpace() && ptr_[pos_] != '}')
		{
			std::optional<PList> key = parseItem();
			if (!key) return std::nullopt;
			if (!key->isString())
			{
				// GNUstep accepts any item as a key; oofnd keys are strings (ADR-0027 item 2).
				err_ = "non-string key in dictionary";
				return std::nullopt;
			}
			if (!skipSpace()) return std::nullopt;
			if (ptr_[pos_] != '=')
			{
				err_ = "unexpected character (wanted '=')";
				return std::nullopt;
			}
			pos_++;
			std::optional<PList> val = parseItem();
			if (!val) return std::nullopt;
			if (!skipSpace()) return std::nullopt;
			if (ptr_[pos_] == ';')
			{
				pos_++;
			}
			else if (ptr_[pos_] != '}')
			{
				err_ = "unexpected character (wanted ';' or '}')";
				return std::nullopt;
			}
			dict.insert_or_assign(std::move(*key->getIf<std::string>()), std::move(*val));
		}
		if (pos_ >= end_)
		{
			err_ = "unexpected end of string when parsing dictionary";
			return std::nullopt;
		}
		pos_++;
		return PList(std::move(dict));
	}

	// '(' item, item, ... ')'. A trailing ',' is allowed; ",," is an empty unquoted string.
	std::optional<PList> parseArray()
	{
		PList::Array array;
		pos_++;
		while (skipSpace() && ptr_[pos_] != ')')
		{
			std::optional<PList> val = parseItem();
			if (!val) return std::nullopt;
			if (!skipSpace()) return std::nullopt;
			if (ptr_[pos_] == ',')
			{
				pos_++;
			}
			else if (ptr_[pos_] != ')')
			{
				err_ = "unexpected character (wanted ',' or ')')";
				return std::nullopt;
			}
			array.push_back(std::move(*val));
		}
		if (pos_ >= end_)
		{
			err_ = "unexpected end of string when parsing array";
			return std::nullopt;
		}
		pos_++;
		return PList(std::move(array));
	}

	// '<' hex octets '>', pos_ just past '<'. Whitespace AND comments may separate octets (GNUstep
	// calls skipSpace between them), so a comment can even run past the first '>'.
	std::optional<PList> parseHexData()
	{
		std::size_t max = pos_;
		while (max < end_ && ptr_[max] != '>') max++;
		if (max >= end_)
		{
			err_ = "unexpected end of string when parsing data";
			return std::nullopt;
		}
		std::vector<std::uint8_t> buf;
		(void)skipSpace();
		while (pos_ < max && isHexDigit(ptr_[pos_]) && isHexDigit(ptr_[pos_ + 1]))
		{
			buf.push_back(static_cast<std::uint8_t>((hexValue(ptr_[pos_]) << 4) | hexValue(ptr_[pos_ + 1])));
			pos_ += 2;
			(void)skipSpace();
		}
		// GNUstep reads ptr[pos] even when a comment ran to the end of the input (undefined
		// behaviour there); oofnd treats the end as "not '>'" (ADR-0027 item 4).
		if (pos_ >= end_ || ptr_[pos_] != '>')
		{
			err_ = "unexpected character (wanted '>')";
			return std::nullopt;
		}
		pos_++;
		return PList(Data(std::move(buf)));
	}

	// GNUstep's extension "<*Tvalue>", pos_ at '*': I integer, R real, B bool (Y/N), D date.
	// The value may be in double quotes. An undecodable date is nil with no error.
	std::optional<PList> parseTypedValue()
	{
		old_ = false;
		pos_++;
		const std::size_t min = pos_;
		while (pos_ < end_ && ptr_[pos_] != '>') pos_++;
		std::size_t len = pos_ - min;
		std::optional<PList> result;
		if (len > 1)
		{
			const unsigned char* p = ptr_ + min;
			const unsigned char type = *p++;
			len--;
			if (len > 2 && p[0] == '"' && p[len - 1] == '"')
			{
				len -= 2;
				p++;
			}
			const std::string buf(reinterpret_cast<const char*>(p), len);
			if (type == 'I')
			{
				if (buf[0] == '-') result = PList::signedInteger(std::strtoll(buf.c_str(), nullptr, 10));
				else result = PList::unsignedInteger(std::strtoull(buf.c_str(), nullptr, 10));
			}
			else if (type == 'B')
			{
				if (buf[0] == 'Y') result = PList(true);
				else if (buf[0] == 'N') result = PList(false);
				else
				{
					err_ = "bad value for bool";
					return std::nullopt;
				}
			}
			else if (type == 'D')
			{
				if (std::optional<double> d = parseCalendarDate(buf, false)) result = PList(PList::Date{*d});
			}
			else if (type == 'R')
			{
				result = PList(std::strtod(buf.c_str(), nullptr));
			}
			else
			{
				err_ = "unrecognized type code after '<*'";
				return std::nullopt;
			}
		}
		else
		{
			err_ = "missing type code after '<*'";
			return std::nullopt;
		}
		if (pos_ >= end_)
		{
			err_ = "unexpected end of string when parsing data";
			return std::nullopt;
		}
		pos_++;   // the '>'
		return result;
	}

	// GNUstep's extension "<[base64]>", pos_ at '['. Undecodable base64 is nil with no error.
	std::optional<PList> parseBase64Data()
	{
		old_ = false;
		pos_++;
		const std::size_t min = pos_;
		while (pos_ < end_ && ptr_[pos_] != ']') pos_++;
		const std::size_t len = pos_ - min;
		if (pos_ >= end_)
		{
			err_ = "unexpected end of string when parsing data";
			return std::nullopt;
		}
		pos_++;
		if (pos_ >= end_)
		{
			err_ = "unexpected end of string when parsing ']>'";
			return std::nullopt;
		}
		if (ptr_[pos_] != '>')
		{
			err_ = "unexpected character (wanted '>')";
			return std::nullopt;
		}
		pos_++;
		if (len == 0) return PList(Data());
		std::optional<Data> d = decodeBase64IgnoringUnknown(ptr_ + min, len);
		if (!d) return std::nullopt;
		return PList(std::move(*d));
	}

	const unsigned char* ptr_;
	std::size_t end_;
	std::size_t pos_ = 0;
	unsigned lin_ = 0;
	const char* err_ = nullptr;
	bool old_ = true;    // no GNUstep <*...> / <[...]> extension seen
};

} // namespace plist_detail

// The OpenStep-format branch of -[NSPropertyListSerialization propertyListWithData:...].
// An error has GNUstep's message; a parse that GNUstep finishes with nil and no error yields a
// null PList. *format, if given, receives OpenStep, or GNUstep if an extension was used.
inline Expected<PList, PListError> parseOldStylePList(std::string_view bytes, PListFormat* format = nullptr)
{
	plist_detail::OldStyleScanner scanner(bytes);
	std::optional<PList> result = scanner.parseItem();
	if (format != nullptr) *format = scanner.usedGNUstepExtensions() ? PListFormat::GNUstep : PListFormat::OpenStep;
	if (scanner.error() != nullptr) return Unexpected(PListError{scanner.errorMessage()});
	return result ? std::move(*result) : PList();
}

} // namespace oo

#pragma pop_macro("false")
#pragma pop_macro("true")

#endif // OOFND_PLISTOLDSTYLE_HPP
