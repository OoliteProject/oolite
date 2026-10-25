/*	oofnd/Log.hpp
	oo::log: Oolite's logging (OOLogging) without Foundation (bead oo-qpb, proposed ADR-0035):
	message-class switches with inheritance and $metaclasses, per-thread indentation, the exact
	Latest.log line layout, and a std::format front end.

	    OOLogging (Objective-C)                          oo::log
	    -----------------------------------------------  -------------------------------------------
	    OOLog(@"cls", @"n = %d, s = %@", n, s)           OO_LOG("cls", "n = {}, s = {}", n, s)
	    OOLogERR / OOLogWARN(@"cls", fmt, ...)           OO_LOG_ERR / OO_LOG_WARN("cls", fmt, ...)
	    OOLogWillDisplayMessagesInClass(@"cls")          oo::log::willDisplay("cls")
	    OOLogSetDisplayMessagesInClass(@"cls", YES)      oo::log::logger().setDisplay("cls", true)
	    OOLogIndent / Outdent / PushIndent / PopIndent   oo::log::indent / outdent / pushIndent / popIndent
	    OOLogIndentIf(@"cls") / OOLogOutdentIf           oo::log::indentIf("cls") / outdentIf
	    OOLogGetParentMessageClass(@"a.b")               oo::log::parentClass("a.b")
	    OOLogAbbreviatedFileName(__FILE__)               oo::log::abbreviatedFileName(__FILE__)
	    OOLogInsertMarker()                              oo::log::logger().insertMarker()

	The game's OOLogging.mm is a thin Objective-C shell over this: it loads logcontrol.plist and the
	logging-show-* defaults, formats %@ messages for the calls not yet converted, and installs the
	sink that feeds OOLogOutputHandler (Latest.log). Both kinds of call site share one Logger, so
	settings, indentation and line layout are identical whichever API wrote the line.

	Behaviour is OOLogging.mm's, captured by driving the original file against gnustep-base 1.31.1
	(tests/unit/oofnd/test_log.cpp): settings resolution, the internal diagnostics it prints (same
	function names and text), prefix order and spelling, indentation (two spaces a level, at most
	64, placed before the time), and the time stamp (local "HH:MM:SS.mmm", milliseconds truncated).

	Header-only, C++20. std::format itself may report a malformed format string at compile time;
	nothing here throws.
*/

#ifndef OOFND_LOG_HPP
#define OOFND_LOG_HPP

// Objective-C++ callers see OOCocoa.h's `#define true 1` / `#define false 0`; suspend them for
// this header (proposed ADR-0028).
#pragma push_macro("true")
#pragma push_macro("false")
#undef true
#undef false

#include <atomic>
#include <chrono>
#include <cstddef>
#include <cstdio>
#include <ctime>
#include <format>
#include <functional>
#include <mutex>
#include <optional>
#include <string>
#include <string_view>
#include <unordered_map>
#include <unordered_set>
#include <utility>
#include <vector>

namespace oo::log {

// A logcontrol.plist value before interpretation: a string, anything with a -boolValue (numbers),
// or anything else (described for the diagnostic, as %@ would).
struct RawSetting
{
	enum class Kind
	{
		string,
		boolean,
		other,
	};
	Kind kind = Kind::other;
	std::string text;	// the string, or the description of an `other`
	bool flag = false;	// the -boolValue of a `boolean`

	static RawSetting string(std::string s) { return {Kind::string, std::move(s), false}; }
	static RawSetting boolean(bool b) { return {Kind::boolean, std::string(), b}; }
	static RawSetting other(std::string description) { return {Kind::other, std::move(description), false}; }
};

// The show-* switches (logging-show-function, -file-and-line, -class, -time).
struct Options
{
	bool showFunction = false;
	bool showFileAndLine = false;
	bool showClass = false;
	bool showTime = false;
};

namespace detail {

// -caseInsensitiveCompare: == NSOrderedSame against a lowercase ASCII word (see oo::str).
inline bool isWord(std::string_view s, std::string_view lowerWord) noexcept
{
	if (s.size() != lowerWord.size()) return false;
	for (std::size_t i = 0; i < s.size(); ++i)
	{
		const char c = (s[i] >= 'A' && s[i] <= 'Z') ? static_cast<char>(s[i] + 32) : s[i];
		if (c != lowerWord[i]) return false;
	}
	return true;
}

// Hashing for heterogeneous lookup: a willDisplay() that hits the cache allocates nothing.
struct StringHash
{
	using is_transparent = void;
	std::size_t operator()(std::string_view s) const noexcept { return std::hash<std::string_view>{}(s); }
};

template <class V>
using StringMap = std::unordered_map<std::string, V, StringHash, std::equal_to<>>;

// OOLogging's per-thread indentation (thread_local since bead oo-3rb.6).
struct IndentState
{
	unsigned level = 0;
	std::vector<unsigned> stack;
};

inline IndentState& indentState()
{
	static thread_local IndentState state;
	return state;
}

} // namespace detail

// OOLogGetParentMessageClass(): up to the last '.'; none for a class without one.
inline std::optional<std::string> parentClass(std::string_view messageClass)
{
	const std::size_t dot = messageClass.rfind('.');
	if (dot == std::string_view::npos) return std::nullopt;
	return std::string(messageClass.substr(0, dot));
}

// OOLogAbbreviatedFileName(): the last path component of __FILE__ ('/' or '\'), trailing
// separators ignored; "unspecified file" for NULL.
inline std::string abbreviatedFileName(const char* file)
{
	if (file == nullptr) return "unspecified file";
	std::string_view f(file);
	while (f.size() > 1 && (f.back() == '/' || f.back() == '\\')) f.remove_suffix(1);
	const std::size_t sep = f.find_last_of("/\\");
	return std::string(sep == std::string_view::npos || f.size() == 1 ? f : f.substr(sep + 1));
}

// [[NSDate date] descriptionWithCalendarFormat:@"%H:%M:%S.%F" ...]: local time, milliseconds
// truncated.
inline std::string timeStamp(std::chrono::system_clock::time_point when)
{
	const auto ms = std::chrono::floor<std::chrono::milliseconds>(when.time_since_epoch()).count();
	const std::time_t seconds = static_cast<std::time_t>(ms >= 0 ? ms / 1000 : (ms - 999) / 1000);
	const int milli = static_cast<int>(ms - static_cast<long long>(seconds) * 1000);
	std::tm tm{};
#ifdef _WIN32
	localtime_s(&tm, &seconds);
#else
	localtime_r(&seconds, &tm);
#endif
	char buf[16];
	std::snprintf(buf, sizeof buf, "%02d:%02d:%02d.%03d", tm.tm_hour, tm.tm_min, tm.tm_sec, milli);
	return buf;
}

// The line OOLogWithFunctionFileAndLineAndArguments() hands to the output handler.
inline std::string composeLine(const Options& options, std::string_view messageClass, const char* function, const char* file,
	unsigned long line, std::string_view message, unsigned indentLevel, std::string_view time)
{
	const std::string fn = function != nullptr ? function : "(null)";
	std::string text;
	if (options.showFileAndLine && file != nullptr)
	{
		if (options.showFunction) text = std::format("{} ({}:{}): {}", fn, abbreviatedFileName(file), line, message);
		else text = std::format("{}:{}: {}", abbreviatedFileName(file), line, message);
	}
	else if (options.showFunction)
	{
		text = std::format("{}: {}", fn, message);
	}
	else
	{
		text = message;
	}
	if (options.showClass)
	{
		text = (options.showFunction || options.showFileAndLine) ? std::format("[{}] {}", messageClass, text)
																: std::format("[{}]: {}", messageClass, text);
	}
	if (options.showTime) text = std::format("{} {}", time, text);
	if (indentLevel != 0)
	{
		const unsigned spaces = indentLevel >= 32 ? 64u : indentLevel * 2;
		text.insert(0, spaces, ' ');
	}
	return text;
}

// --- per-thread indentation ------------------------------------------------------------------

inline unsigned indentLevel() { return detail::indentState().level; }
inline void indent() { ++detail::indentState().level; }
inline void outdent()
{
	unsigned& level = detail::indentState().level;
	if (level != 0) --level;
}
inline void pushIndent()
{
	detail::IndentState& s = detail::indentState();
	s.stack.push_back(s.level);
}
inline bool popIndent();	// below: underflow is reported through the logger

// --- the logger ------------------------------------------------------------------------------

class Logger
{
public:
	using Sink = void (*)(std::string_view line);

	// Where finished lines go (the game: OOLogOutputHandlerPrint, installed by OOLoggingInit).
	// Until then they go to stderr, as OOLogOutputHandlerPrint sent them before its own init.
	void setSink(Sink sink) noexcept { sink_.store(sink != nullptr ? sink : &stderrSink); }

	// OOLoggingInit(): before it, willDisplay() reports the error and answers false.
	void setInitialized(bool initialized) noexcept { initialized_.store(initialized); }
	bool initialized() const noexcept { return initialized_.load(); }

	Options options() const
	{
		std::lock_guard<std::mutex> lock(mutex_);
		return options_;
	}
	void setOptions(const Options& options)
	{
		std::lock_guard<std::mutex> lock(mutex_);
		options_ = options;
	}
	void setShowClassTemporarily(bool show)
	{
		std::lock_guard<std::mutex> lock(mutex_);
		options_.showClass = show;
	}

	/*	LoadExplicitSettingsFromDictionary() over <entries>, in the order given (the
		NSDictionary's enumeration order, which is the order of the diagnostics), into a fresh
		table. With <final>, LoadExplicitSettings()'s last step too: take _default and _override
		out of the table (each keeps its previous value unless present) and drop the cache.
		OOLoggingReloadSettings loads the built-in logcontrol.plist first without <final>, then
		the full settings with it.
	*/
	void replaceSettings(const std::vector<std::pair<std::string, RawSetting>>& entries, bool final)
	{
		std::vector<std::pair<const char*, std::string>> diagnostics;	// (function, message)
		{
			std::lock_guard<std::mutex> lock(mutex_);
			explicit_.clear();
			for (const auto& [key, raw] : entries)
			{
				std::optional<Value> value;
				if (raw.kind == RawSetting::Kind::string)
				{
					const std::string& s = raw.text;
					if (detail::isWord(s, "yes") || detail::isWord(s, "true") || detail::isWord(s, "on")) value = Value::on();
					else if (detail::isWord(s, "no") || detail::isWord(s, "false") || detail::isWord(s, "off")) value = Value::off();
					else if (detail::isWord(s, "inherit") || detail::isWord(s, "inherited")) explicit_.erase(key);
					else if (s.starts_with('$')) value = Value::meta(s);
					else diagnostics.emplace_back("LoadExplicitSettingsFromDictionary", badValue(s));
				}
				else if (raw.kind == RawSetting::Kind::boolean)
				{
					value = raw.flag ? Value::on() : Value::off();
				}
				else
				{
					diagnostics.emplace_back("LoadExplicitSettingsFromDictionary", badValue(raw.text));
				}
				if (value) explicit_[key] = *value;
			}
			if (final)
			{
				takeSwitch("_default", "_default may not be set to a metaclass, ignoring.", diagnostics, [&](bool v) {
					defaultDisplay_ = v;
				});
				takeSwitch("_override", "_override may not be set to a metaclass, ignoring.", diagnostics, [&](bool v) {
					overrideInEffect_ = true;
					overrideValue_ = v;
				});
				cache_.clear();
			}
		}
		for (const auto& [function, text] : diagnostics) internal(function, text);
	}

	// OOLogging's Inited(): false, with its error, before OOLoggingInit().
	bool checkInitialized()
	{
		if (initialized()) return true;
		internal("Inited", "***** ERROR: OOLoggingInit() has not been called.");
		return false;
	}

	// OOLogSetDisplayMessagesInClass().
	void setDisplay(std::string_view messageClass, bool display)
	{
		if (!checkInitialized()) return;
		std::lock_guard<std::mutex> lock(mutex_);
		const std::string key(messageClass);
		auto it = explicit_.find(key);
		if (it == explicit_.end() || !(it->second.kind == (display ? Value::Kind::on : Value::Kind::off)))
		{
			explicit_[key] = display ? Value::on() : Value::off();
			cache_.clear();
		}
	}

	// OOLogWillDisplayMessagesInClass().
	bool willDisplay(std::string_view messageClass)
	{
		if (!checkInitialized()) return false;
		std::vector<std::string> diagnostics;
		bool result;
		{
			std::lock_guard<std::mutex> lock(mutex_);
			if (overrideInEffect_) return overrideValue_;
			auto it = cache_.find(messageClass);
			if (it != cache_.end()) return it->second;
			const std::string key(messageClass);
			result = resolve(key, diagnostics);
			cache_.emplace(key, result);
		}
		for (const std::string& d : diagnostics) internal("ResolveMetaClassReference", d);
		return result;
	}

	// OOLogWithFunctionFileAndLineAndArguments() after the message is formatted: prefixes, time,
	// indentation, then the sink. Does not test the class (the macros do, as OOLog's do).
	void write(std::string_view messageClass, const char* function, const char* file, unsigned long line, std::string_view message)
	{
		const Options o = options();
		const std::string time = o.showTime ? timeStamp(std::chrono::system_clock::now()) : std::string();
		emit(composeLine(o, messageClass, function, file, line, message, indentLevel(), time));
	}

	// OOLogInsertMarker().
	void insertMarker()
	{
		const unsigned id = ++lastMarker_;
		emit(std::format("\n\n========== [Marker {}] ==========", id));
	}

	// OOLogInternal_(): OOLogging's own diagnostics, unprefixed.
	void internal(std::string_view function, std::string_view message)
	{
		emit(std::format("OOLogging internal - {}: {}", function, message));
	}

	void emit(std::string_view line) const
	{
		if (Sink sink = sink_.load()) sink(line);
	}

private:
	struct Value
	{
		enum class Kind
		{
			on,
			off,
			meta,
		};
		Kind kind = Kind::off;
		std::string metaclass;
		static Value on() { return {Kind::on, {}}; }
		static Value off() { return {Kind::off, {}}; }
		static Value meta(std::string m) { return {Kind::meta, std::move(m)}; }
	};

	static void stderrSink(std::string_view line)
	{
		std::fwrite(line.data(), 1, line.size(), stderr);
		std::fputc('\n', stderr);
	}

	static std::string badValue(std::string_view v)
	{
		return std::format("Bad setting value \"{}\" (expected yes, no, inherit or $metaclass).", v);
	}

	template <class F>
	void takeSwitch(const char* key, const char* metaMessage, std::vector<std::pair<const char*, std::string>>& diagnostics, F apply)
	{
		auto it = explicit_.find(key);
		if (it == explicit_.end()) return;
		if (it->second.kind == Value::Kind::meta) diagnostics.emplace_back("LoadExplicitSettings", metaMessage);
		else apply(it->second.kind == Value::Kind::on);
		explicit_.erase(it);
	}

	// ResolveDisplaySetting(): explicit on/off, else the parent's, else _default; a $metaclass
	// resolves through ResolveMetaClassReference().
	bool resolve(const std::string& messageClass, std::vector<std::string>& diagnostics) const
	{
		std::string cls = messageClass;
		for (;;)
		{
			auto it = explicit_.find(cls);
			if (it == explicit_.end())
			{
				std::optional<std::string> parent = parentClass(cls);
				if (!parent) return defaultDisplay_;
				cls = std::move(*parent);
				continue;
			}
			if (it->second.kind != Value::Kind::meta) return it->second.kind == Value::Kind::on;
			return resolveMeta(it->second.metaclass, diagnostics);
		}
	}

	// A cycle of metaclasses recursed until the stack overflowed in OOLogging.mm; here it falls
	// back to _default (the one deliberate difference).
	bool resolveMeta(std::string meta, std::vector<std::string>& diagnostics) const
	{
		std::unordered_set<std::string> seen;
		for (;;)
		{
			if (!seen.insert(meta).second) return defaultDisplay_;
			if (!meta.starts_with('$'))
			{
				diagnostics.push_back(std::format("Bad setting value \"{}\" (expected yes, no, inherit or $metaclass). Falling back to _default.", meta));
				return defaultDisplay_;
			}
			auto it = explicit_.find(meta);
			if (it == explicit_.end())
			{
				diagnostics.push_back(std::format("Reference to undefined metaclass {}, falling back to _default.", meta));
				return defaultDisplay_;
			}
			if (it->second.kind != Value::Kind::meta) return it->second.kind == Value::Kind::on;
			meta = it->second.metaclass;
		}
	}

	mutable std::mutex mutex_;
	detail::StringMap<Value> explicit_;
	detail::StringMap<bool> cache_;
	Options options_;
	bool defaultDisplay_ = true;
	bool overrideInEffect_ = false;
	bool overrideValue_ = false;
	std::atomic<bool> initialized_{false};
	std::atomic<unsigned> lastMarker_{0};
	std::atomic<Sink> sink_{&stderrSink};
};

// The process's one logger.
inline Logger& logger()
{
	static Logger instance;
	return instance;
}

inline bool willDisplay(std::string_view messageClass) { return logger().willDisplay(messageClass); }

inline bool popIndent()
{
	detail::IndentState& s = detail::indentState();
	if (s.stack.empty())
	{
		logger().internal("OOLogPopIndent", "OOLogPopIndent(): state stack underflow.");
		return false;
	}
	s.level = s.stack.back();
	s.stack.pop_back();
	return true;
}

inline void indentIf(std::string_view messageClass)
{
	if (willDisplay(messageClass)) indent();
}

inline void outdentIf(std::string_view messageClass)
{
	if (willDisplay(messageClass)) outdent();
}

// The std::format front end. <function>/<file>/<line> are what OOLog passes: __FUNCTION__,
// __FILE__, __LINE__ (the macros below supply them).
template <class... Args>
void message(std::string_view messageClass, const char* function, const char* file, unsigned long line,
	std::format_string<Args...> format, Args&&... args)
{
	logger().write(messageClass, function, file, line, std::format(format, std::forward<Args>(args)...));
}

template <class... Args>
void messageWithPrefix(std::string_view messageClass, const char* function, const char* file, unsigned long line,
	std::string_view prefix, std::format_string<Args...> format, Args&&... args)
{
	if (!willDisplay(messageClass)) return;
	std::string text(prefix);
	text += std::format(format, std::forward<Args>(args)...);
	logger().write(messageClass, function, file, line, text);
}

inline constexpr std::string_view kErrorPrefix = "***** ERROR: ";
inline constexpr std::string_view kWarningPrefix = "----- WARNING: ";

} // namespace oo::log

// OOLog / OOLogERR / OOLogWARN with std::format formats. The class is a string (a literal, or
// oo::StdString of an NSString constant); the arguments are only evaluated if the class shows.
#define OO_LOG(messageClass, ...) \
	do { if (::oo::log::willDisplay(messageClass)) ::oo::log::message((messageClass), __FUNCTION__, __FILE__, __LINE__, __VA_ARGS__); } while (0)
#define OO_LOG_ERR(messageClass, ...) \
	::oo::log::messageWithPrefix((messageClass), __FUNCTION__, __FILE__, __LINE__, ::oo::log::kErrorPrefix, __VA_ARGS__)
#define OO_LOG_WARN(messageClass, ...) \
	::oo::log::messageWithPrefix((messageClass), __FUNCTION__, __FILE__, __LINE__, ::oo::log::kWarningPrefix, __VA_ARGS__)

#pragma pop_macro("false")
#pragma pop_macro("true")

#endif // OOFND_LOG_HPP
