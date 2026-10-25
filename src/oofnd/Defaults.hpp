/*	oofnd/Defaults.hpp
	oo::Defaults: the game's preferences, replacing NSUserDefaults and the two categories that bend
	GNUstep's to Oolite (Core/NSUserDefaults+Override.m, Core/NSBundle+Override.m); bead oo-32f.

	    today (Objective-C, gnustep-base 1.31)                   oofnd
	    -------------------------------------------------------  ---------------------------------
	    [NSUserDefaults standardUserDefaults]                    oo::Defaults::standard()
	    -objectForKey: / -stringForKey: / -arrayForKey: /        object() / stringForKey() /
	      -dictionaryForKey:                                       arrayForKey() / dictionaryForKey()
	    -boolForKey: / -integerForKey: / -floatForKey: /         boolForKey() / integerForKey() /
	      -doubleForKey:                                           floatForKey() / doubleForKey()
	    -setObject:forKey: -setBool: -setInteger: -setFloat:     setObject() setBool() setInteger()
	      -setDouble: -removeObjectForKey:                         setFloat() setDouble() removeObject()
	    -registerDefaults: / -synchronize                        registerDefaults() / synchronize()
	    NSUserDefaults+Override -writeDictionary:toFile:         writeOpenStepPList() + synchronize()
	    NSBundle+Override -infoDictionary (for the domain name)  applicationDomainName()

	Everything below was probed against gnustep-base 1.31 on this toolchain (proposed ADR-0032):

	  * FILE. <home>/GNUstep/Defaults/<domain>.plist, home as ResourcePaths::homeDirectory()
	    (next to oolite.exe; GNUstep.conf's GNUSTEP_USER_DEFAULTS_DIR, not the environment).
	    <domain> is CFBundleIdentifier from <builtInResources>/Info-gnustep.plist ("oolite"), which
	    is what NSBundle+Override makes -infoDictionary read, else the process name. NSGlobalDomain
	    is read from NSGlobalDomain.plist beside it. On POSIX, OO_GNUSTEPDEFAULTSDIR (what
	    run_oolite.sh writes into GNUstep.conf) overrides the directory.
	  * SEARCH LIST. arguments, application domain, NSGlobalDomain, registration. (GNUstep's
	    GSPrimaryDomain, GSConfigDomain and language domains hold nothing the game reads.)
	  * ARGUMENTS. argv[0] skipped; "-key value" sets key (last wins); the value is parsed as a
	    property list and kept as the raw string if that fails; a "-key" followed by another
	    "-arg" or by nothing sets nothing; a lone "-" and non-dash words are skipped.
	  * WRITING. Only synchronize() writes, never at exit. It re-reads the file, applies this
	    process's changes since the last synchronize on top (another writer's keys survive), and
	    writes only if the result differs from what is on disk; an empty domain deletes the
	    file. The format is NSUserDefaults+Override's: GNUstep's NSPropertyListOpenStepFormat
	    (writeOpenStepPList below), written atomically. An unreadable file reads as empty.
	  * GETTERS. NSUserDefaults' own coercions: strings through GNUstep's -boolValue /
	    -integerValue / -doubleValue (defaults_detail), numbers through NSNumber's, anything
	    else 0/NO; stringForKey only strings. Numbers written come back as strings next run.

	Header-only, C++20, no exceptions. Thread-safe as NSUserDefaults is (one mutex).
*/

#ifndef OOFND_DEFAULTS_HPP
#define OOFND_DEFAULTS_HPP

// Suspend OOCocoa.h's `#define true 1` / `#define false 0` for this header (see oofnd/Data.hpp,
// proposed ADR-0028); restored at the end.
#pragma push_macro("true")
#pragma push_macro("false")
#undef true
#undef false

#include "oofnd/FileSystem.hpp"
#include "oofnd/PList.hpp"
#include "oofnd/PListParsing.hpp"
#include "oofnd/PListWriting.hpp"
#include "oofnd/ResourcePaths.hpp"

#include <algorithm>
#include <charconv>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <ctime>
#include <functional>
#include <limits>
#include <map>
#include <mutex>
#include <optional>
#include <set>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

#if defined(_WIN32)
// As in ResourcePaths.hpp: identical to the SDK's declarations, without <windows.h>.
extern "C" __declspec(dllimport) wchar_t* __stdcall GetCommandLineW(void);
extern "C" __declspec(dllimport) wchar_t** __stdcall CommandLineToArgvW(const wchar_t* cmdLine, int* argc);
extern "C" __declspec(dllimport) void* __stdcall LocalFree(void* mem);
#endif

namespace oo {

namespace defaults_detail {

inline bool isAsciiSpace(unsigned char c) noexcept { return c == ' ' || (c >= '\t' && c <= '\r'); }

// -[NSString boolValue]: the first character that is not a space, '0', '+' or '-' decides.
inline bool stringBoolValue(std::string_view s) noexcept
{
	for (unsigned char c : s)
	{
		if (c > 'y')  break;
		if ((c >= '1' && c <= '9') || c == 'y' || c == 'Y' || c == 't' || c == 'T')  return true;
		if (!isAsciiSpace(c) && c != '0' && c != '-' && c != '+')  break;
	}
	return false;
}

// -[NSString integerValue] / -longLongValue: ASCII spaces, a sign, decimal digits. Overflow
// saturates the magnitude, then a positive value is reinterpreted (-1) and a negative one
// clamps to the minimum, as probed.
inline std::int64_t stringIntegerValue(std::string_view s) noexcept
{
	std::size_t i = 0;
	while (i < s.size() && isAsciiSpace(static_cast<unsigned char>(s[i])))  ++i;
	bool negative = false;
	if (i < s.size() && (s[i] == '+' || s[i] == '-'))  negative = s[i++] == '-';
	std::uint64_t magnitude = 0;
	for (; i < s.size() && s[i] >= '0' && s[i] <= '9'; ++i)
	{
		const unsigned digit = static_cast<unsigned>(s[i] - '0');
		magnitude = magnitude > (UINT64_MAX - digit) / 10 ? UINT64_MAX : magnitude * 10 + digit;
	}
	if (!negative)  return static_cast<std::int64_t>(magnitude);
	if (magnitude > (std::uint64_t{1} << 63))  return INT64_MIN;
	return static_cast<std::int64_t>(0 - magnitude);
}

// Leading white space for -doubleValue: ASCII plus the Unicode spaces (U+00A0 counts here).
inline std::size_t skipUnicodeSpace(std::string_view s) noexcept
{
	std::size_t i = 0;
	while (i < s.size())
	{
		const auto b = [&](std::size_t k) { return i + k < s.size() ? static_cast<unsigned char>(s[i + k]) : 0u; };
		if (isAsciiSpace(b(0)))  { i += 1; continue; }
		if ((b(0) == 0xC2 && (b(1) == 0x85 || b(1) == 0xA0)))  { i += 2; continue; }
		if (b(0) == 0xE1 && b(1) == 0x9A && b(2) == 0x80)  { i += 3; continue; }                   // U+1680
		if (b(0) == 0xE2 && b(1) == 0x80 && ((b(2) >= 0x80 && b(2) <= 0x8A) || b(2) == 0xA8 || b(2) == 0xA9 || b(2) == 0xAF))  { i += 3; continue; }
		if (b(0) == 0xE2 && b(1) == 0x81 && b(2) == 0x9F)  { i += 3; continue; }                   // U+205F
		if (b(0) == 0xE3 && b(1) == 0x80 && b(2) == 0x80)  { i += 3; continue; }                   // U+3000
		break;
	}
	return i;
}

// -[NSString doubleValue]: spaces, sign, digits[.digits], and an exponent only if it has digits;
// no hex, inf or nan (those read as 0). -floatValue is (float) of this.
inline double stringDoubleValue(std::string_view s) noexcept
{
	std::size_t i = skipUnicodeSpace(s);
	bool negative = false;
	if (i < s.size() && (s[i] == '+' || s[i] == '-'))  negative = s[i++] == '-';
	const std::size_t start = i;
	auto digits = [&] { std::size_t n = 0; while (i < s.size() && s[i] >= '0' && s[i] <= '9') { ++i; ++n; } return n; };
	std::size_t mantissa = digits();
	if (i < s.size() && s[i] == '.')  { ++i; mantissa += digits(); }
	if (mantissa == 0)  return 0.0;
	std::size_t end = i;
	bool negativeExponent = false;
	if (i < s.size() && (s[i] == 'e' || s[i] == 'E'))
	{
		++i;
		if (i < s.size() && (s[i] == '+' || s[i] == '-'))  negativeExponent = s[i++] == '-';
		if (digits() > 0)  end = i;
	}
	double value = 0.0;
	const std::from_chars_result r = std::from_chars(s.data() + start, s.data() + end, value);
	if (r.ec == std::errc::result_out_of_range)  value = negativeExponent ? 0.0 : std::numeric_limits<double>::infinity();
	return negative ? -value : value;
}

// NSNumber -longLongValue of a double: truncation; NaN and out of range give the minimum (x86-64).
inline std::int64_t realIntegerValue(double d) noexcept
{
	if (!(d >= -9223372036854775808.0 && d < 9223372036854775808.0))  return INT64_MIN;
	return static_cast<std::int64_t>(d);
}

// --- GNUstep's NSPropertyListOpenStepFormat writer (NSPropertyList.m, OAppend) ----------------

inline void appendOpenStepString(std::string& out, std::string_view utf8)
{
	bool bare = !utf8.empty();
	for (unsigned char c : utf8)
	{
		if (!((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9')))  bare = false;
	}
	if (bare)  { out += utf8; return; }
	out += '"';
	char buf[8];
	for (char16_t u : utf8ToUtf16(utf8))
	{
		switch (u)
		{
			case '"':  out += "\\\""; continue;
			case '\\': out += "\\\\"; continue;
			case '\a': out += "\\a"; continue;
			case '\b': out += "\\b"; continue;
			case '\v': out += "\\v"; continue;
			case '\f': out += "\\f"; continue;
			case '\t': case '\n': case '\r': out += static_cast<char>(u); continue;
			default: break;
		}
		if (u < 0x20 || u == 0x7F)  std::snprintf(buf, sizeof buf, "\\%03o", static_cast<unsigned>(u));
		else if (u >= 0x80)  std::snprintf(buf, sizeof buf, "\\U%04X", static_cast<unsigned>(u));
		else  { out += static_cast<char>(u); continue; }
		out += buf;
	}
	out += '"';
}

using SinglePrecision = std::function<bool(const PList& real)>;

inline void appendOpenStep(std::string& out, const PList& v, unsigned level, const SinglePrecision& single)
{
	char buf[48];
	switch (v.type())
	{
		case PList::Type::Null: out += "\"<null>\""; return;
		case PList::Type::Object: appendOpenStepString(out, v.getIf<PList::Object>()->get()->description()); return;   // not captured; never written by the game
		case PList::Type::Bool: out += *v.getIf<bool>() ? "1" : "0"; return;
		case PList::Type::Integer:
		{
			const PList::Integer& i = *v.getIf<PList::Integer>();
			if (i.isUnsigned)  std::snprintf(buf, sizeof buf, "%llu", static_cast<unsigned long long>(i.unsignedValue()));
			else  std::snprintf(buf, sizeof buf, "%lld", static_cast<long long>(i.value));
			appendOpenStepString(out, buf);
			return;
		}
		case PList::Type::Real:
		{
			const double d = *v.getIf<double>();
			if (std::isnan(d))  std::snprintf(buf, sizeof buf, "nan");
			else if (std::isinf(d))  std::snprintf(buf, sizeof buf, d < 0 ? "-inf" : "inf");
			else if (v.isSinglePrecision() || (single && single(v)))  std::snprintf(buf, sizeof buf, "%.7g", static_cast<double>(static_cast<float>(d)));
			else  std::snprintf(buf, sizeof buf, "%.16g", d);
			appendOpenStepString(out, buf);
			return;
		}
		case PList::Type::String: appendOpenStepString(out, *v.getIf<std::string>()); return;
		case PList::Type::Data:
		{
			const Data& data = *v.getIf<Data>();
			out += '<';
			for (std::size_t i = 0; i < data.length(); ++i)
			{
				if (i > 0 && i % 4 == 0)  out += ' ';
				std::snprintf(buf, sizeof buf, "%02x", static_cast<unsigned>(data.bytes()[i]));
				out += buf;
			}
			out += '>';
			return;
		}
		case PList::Type::Date:
		{
			// -[NSDate description]: local time, whole seconds.
			const std::time_t t = static_cast<std::time_t>(std::floor(v.getIf<PList::Date>()->sinceReferenceDate + 978307200.0));
			std::tm local{};
#if defined(_WIN32)
			localtime_s(&local, &t);
#else
			localtime_r(&t, &local);
#endif
			std::strftime(buf, sizeof buf, "%Y-%m-%d %H:%M:%S %z", &local);
			appendOpenStepString(out, buf);
			return;
		}
		case PList::Type::Array:
		{
			const PList::Array& a = *v.getIf<PList::Array>();
			out += "(\n";
			for (std::size_t i = 0; i < a.size(); ++i)
			{
				out += plist_detail::xmlIndent((level + 1) * 2);
				appendOpenStep(out, a[i], level + 1, single);
				out += i + 1 < a.size() ? ",\n" : "\n";
			}
			out += plist_detail::xmlIndent(level * 2);
			out += ')';
			return;
		}
		case PList::Type::Dict:
		{
			// Keys in UTF-16 order (GNUstep: -compare:, which also folds canonical decompositions).
			std::vector<std::pair<std::u16string, const PList::Dict::value_type*>> keys;
			for (const auto& e : *v.getIf<PList::Dict>())  keys.emplace_back(utf8ToUtf16(e.first), &e);
			std::sort(keys.begin(), keys.end(), [](const auto& x, const auto& y) { return x.first < y.first; });
			out += "{\n";
			for (const auto& k : keys)
			{
				out += plist_detail::xmlIndent((level + 1) * 2);
				appendOpenStepString(out, k.second->first);
				out += " = ";
				appendOpenStep(out, k.second->second, level + 1, single);
				out += ";\n";
			}
			out += plist_detail::xmlIndent(level * 2);
			out += '}';
			return;
		}
	}
}

} // namespace defaults_detail

// +[NSPropertyListSerialization dataFromPropertyList:format:NSPropertyListOpenStepFormat ...]:
// 4-space/tab indentation, no newline at the end, numbers as their -description. `single` says
// which reals were NSNumber floats (written %.7g, not %.16g).
inline Data writeOpenStepPList(const PList& plist, const defaults_detail::SinglePrecision& single = {})
{
	std::string out;
	defaults_detail::appendOpenStep(out, plist, 0, single);
	return Data::fromString(out);
}

// NSUserDefaults' argument domain from the process arguments (argv[0] included, and skipped).
inline PList::Dict parseDefaultsArguments(const std::vector<std::string>& argv)
{
	PList::Dict result;
	auto isKey = [](const std::string& a) { return a.size() > 1 && a[0] == '-'; };
	std::size_t i = 1;
	while (i < argv.size())
	{
		if (!isKey(argv[i]))  { ++i; continue; }
		const std::string key = argv[i].substr(1);
		if (i + 1 >= argv.size())  break;
		if (isKey(argv[i + 1]))  { ++i; continue; }
		const std::string& raw = argv[i + 1];
		Expected<PList, PListError> parsed = parsePropertyListData(raw);
		result[key] = parsed && !parsed->isNull() ? std::move(*parsed) : PList(raw);
		i += 2;
	}
	return result;
}

// The application domain's name: [[NSBundle mainBundle] bundleIdentifier] (from the Info
// dictionary NSBundle+Override loads), else -[NSProcessInfo processName].
inline std::string applicationDomainName(const PList& infoDictionary, std::string_view processName)
{
	const PList* identifier = infoDictionary.find("CFBundleIdentifier");
	if (identifier != nullptr && identifier->isString() && !identifier->getIf<std::string>()->empty())
	{
		return *identifier->getIf<std::string>();
	}
	return std::string(processName);
}

inline fs::Path userDefaultsDirectory(const ResourcePaths& paths)
{
	if (paths.environment().platform == PathEnvironment::Platform::posix && paths.environment().getenv)
	{
		if (std::optional<std::string> dir = paths.environment().getenv("OO_GNUSTEPDEFAULTSDIR"))  return fs::pathFromUTF8(*dir);
	}
	return paths.homeDirectory() / "GNUstep" / "Defaults";
}

class Defaults
{
public:
	Defaults(fs::Path directory, std::string applicationDomain, PList::Dict arguments = {})
		: directory_(std::move(directory)), domainName_(std::move(applicationDomain)), arguments_(std::move(arguments))
	{
		application_ = load(domainPath(domainName_));
		global_ = load(domainPath("NSGlobalDomain"));
	}

	// The process's defaults, built on first use from the real environment and command line.
	static Defaults& standard()
	{
		static Defaults* instance = new Defaults(forProcess());   // never destroyed, as the ObjC singleton
		return *instance;
	}

	static Defaults forProcess()
	{
		const ResourcePaths paths = ResourcePaths::current();
		const std::vector<std::string> argv = processArguments();
		std::string processName = argv.empty() ? std::string() : fs::utf8String(fs::pathFromUTF8(argv[0]).stem());
		const PList info = load(paths.builtInResourcesDirectory() / "Info-gnustep.plist");
		return Defaults(userDefaultsDirectory(paths), applicationDomainName(info, processName), parseDefaultsArguments(argv));
	}

	const std::string& domainName() const noexcept { return domainName_; }
	fs::Path domainPath(std::string_view domain) const { return directory_ / fs::pathFromUTF8(std::string(domain) + ".plist"); }

	// --- reading (the search list) --------------------------------------------------------

	PList object(std::string_view key) const
	{
		std::lock_guard<std::mutex> lock(mutex_);
		for (const PList::Dict* domain : {&arguments_, &application_, &global_, &registration_})
		{
			if (auto it = domain->find(key); it != domain->end())  return it->second;
		}
		return PList();
	}

	std::optional<std::string> stringForKey(std::string_view key) const
	{
		PList v = object(key);
		if (!v.isString())  return std::nullopt;
		return std::move(*v.getIf<std::string>());
	}
	PList arrayForKey(std::string_view key) const { PList v = object(key); return v.isArray() ? v : PList(); }
	PList dictionaryForKey(std::string_view key) const { PList v = object(key); return v.isDict() ? v : PList(); }

	bool boolForKey(std::string_view key) const
	{
		const PList v = object(key);
		if (const std::string* s = v.getIf<std::string>())  return defaults_detail::stringBoolValue(*s);
		return v.isNumber() && v.boolValue();   // NaN is true, -0 false
	}
	std::int64_t integerForKey(std::string_view key) const
	{
		const PList v = object(key);
		if (const std::string* s = v.getIf<std::string>())  return defaults_detail::stringIntegerValue(*s);
		if (const double* d = v.getIf<double>())  return defaults_detail::realIntegerValue(*d);
		return v.isNumber() ? v.int64Value() : 0;
	}
	double doubleForKey(std::string_view key) const
	{
		const PList v = object(key);
		if (const std::string* s = v.getIf<std::string>())  return defaults_detail::stringDoubleValue(*s);
		return v.isNumber() ? v.doubleValue() : 0.0;
	}
	float floatForKey(std::string_view key) const { return static_cast<float>(doubleForKey(key)); }

	// --- writing (the application domain; persisted by synchronize()) ---------------------

	void setObject(std::string_view key, PList value)
	{
		if (value.isNull())  { removeObject(key); return; }
		std::lock_guard<std::mutex> lock(mutex_);
		const std::string k(key);
		floatKeys_.erase(k);
		application_[k] = value;
		changes_[k] = std::move(value);
	}
	void setBool(std::string_view key, bool value) { setObject(key, PList(value)); }
	void setInteger(std::string_view key, std::int64_t value) { setObject(key, PList(value)); }
	void setDouble(std::string_view key, double value) { setObject(key, PList(value)); }
	void setFloat(std::string_view key, float value)
	{
		setObject(key, PList(value));
		std::lock_guard<std::mutex> lock(mutex_);
		floatKeys_.insert(std::string(key));
	}
	void removeObject(std::string_view key)
	{
		std::lock_guard<std::mutex> lock(mutex_);
		const std::string k(key);
		floatKeys_.erase(k);
		application_.erase(k);
		changes_[k] = std::nullopt;
	}

	void registerDefaults(const PList::Dict& values)
	{
		std::lock_guard<std::mutex> lock(mutex_);
		for (const auto& e : values)  registration_[e.first] = e.second;
	}

	// Merge this process's changes onto the file as it is now, write it if that changed it.
	bool synchronize()
	{
		std::lock_guard<std::mutex> lock(mutex_);
		const fs::Path path = domainPath(domainName_);
		const PList::Dict onDisk = load(path);
		PList::Dict merged = onDisk;
		for (auto& c : changes_)
		{
			if (c.second)  merged[c.first] = *c.second;
			else  merged.erase(c.first);
		}
		bool ok = true;
		if (merged.empty() && !onDisk.empty())
		{
			ok = static_cast<bool>(fs::removeItem(path));
		}
		else if (merged != onDisk)
		{
			const PList root(merged);
			const PList::Dict& written = *root.getIf<PList::Dict>();
			auto single = [&](const PList& real) {
				for (const std::string& k : floatKeys_)
				{
					auto it = written.find(k);
					if (it != written.end() && &it->second == &real)  return true;
				}
				return false;
			};
			ok = fs::createDirectories(directory_) && fs::writeFile(path, writeOpenStepPList(root, single));
		}
		for (auto it = floatKeys_.begin(); it != floatKeys_.end();)  it = changes_.count(*it) ? std::next(it) : floatKeys_.erase(it);
		application_ = std::move(merged);
		changes_.clear();
		global_ = load(domainPath("NSGlobalDomain"));
		return ok;
	}

private:
	// A persistent domain file: any plist format; missing, unreadable or not a dictionary is empty.
	static PList::Dict load(const fs::Path& path)
	{
		fs::Result<Data> bytes = fs::readFile(path);
		if (!bytes || bytes->empty())  return {};
		Expected<PList, PListError> plist = parsePropertyList(bytes->stringView());
		if (!plist || !plist->isDict())  return {};
		return std::move(*plist->getIf<PList::Dict>());
	}

	// -[NSProcessInfo arguments] as UTF-8.
	static std::vector<std::string> processArguments()
	{
		std::vector<std::string> argv;
#if defined(_WIN32)
		int argc = 0;
		wchar_t** wargv = CommandLineToArgvW(GetCommandLineW(), &argc);
		if (wargv == nullptr)  return argv;
		for (int i = 0; i < argc; ++i)  argv.push_back(fs::nativeUTF8String(fs::Path(wargv[i])));
		LocalFree(wargv);
#else
		if (std::FILE* f = std::fopen("/proc/self/cmdline", "rb"))
		{
			std::string arg;
			for (int c; (c = std::fgetc(f)) != EOF;)
			{
				if (c == 0)  { argv.push_back(std::move(arg)); arg.clear(); }
				else  arg += static_cast<char>(c);
			}
			std::fclose(f);
		}
#endif
		return argv;
	}

	fs::Path directory_;
	std::string domainName_;
	mutable std::mutex mutex_;
	PList::Dict arguments_;
	PList::Dict application_;
	PList::Dict global_;
	PList::Dict registration_;
	std::map<std::string, std::optional<PList>, std::less<>> changes_;   // since the last synchronize
	std::set<std::string, std::less<>> floatKeys_;                       // set with setFloat
};

} // namespace oo

#pragma pop_macro("false")
#pragma pop_macro("true")

#endif // OOFND_DEFAULTS_HPP
