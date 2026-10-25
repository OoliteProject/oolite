/*	oofnd/LogFile.hpp
	oo::log::FileWriter: the Latest.log writer (OOLogOutputHandler's OOAsyncLogger) without
	Foundation (bead oo-3rb.64, proposed ADR-0042), and the byte conversions it and the console
	echo applied to a finished line.

	    OOLogOutputHandler (Objective-C, gnustep-base 1.31)      oo::log
	    -------------------------------------------------------  -------------------------------------
	    -[OOAsyncLogger init]: Latest.log -> Previous.log        rotateToPrevious(latest, previous)
	    -startLogging (create the file, start loggerThread)      FileWriter::start(path)
	    -asyncLogMessage: (line + "\n", CRLF, UTF-8 data)        FileWriter::write(line)
	      the bytes it enqueued                                  logFileBytes(line, crlf)
	    -flushLog ([logFile synchronizeFile] on the thread)      FileWriter::flush()
	    -endLogging ("\nClosing log at %@.", die, close)         FileWriter::end(postamble)
	    the 1 GiB "LOG TRUNCATED" saturation                     FileWriter (limit, shared flag)
	    [[line stringByAppendingString:@"\n"] UTF8String]         consoleBytes(line)

	Captured from gnustep-base 1.31.1 (throwaway probe; tests/unit/oofnd/test_logfile.cpp):
	  * A line is taken as GNUstep took the NSString the sink made of it (oo::utf8ToUtf16: an
	    invalid UTF-8 byte is one Latin-1 unit), "\n" is appended, and on Windows the string is
	    split with -componentsSeparatedByString:@"\n" and joined with "\r\n": every "\n" becomes
	    "\r\n" (an existing "\r\n" becomes "\r\r\n") EXCEPT one that a sequence-extending unit
	    follows, which that non-literal search does not see as a separator.
	  * -dataUsingEncoding:NSUTF8StringEncoding answers nil for a string holding a lone
	    surrogate, and OOAsyncQueue drops a nil message: such a line never reaches the file.
	  * -UTF8String (the stderr/stdout echo) writes a lone surrogate as U+FFFD, and fputs stops
	    at the first U+0000.
	  * Saturation: the writer thread counts the bytes it writes; the write that takes the total
	    past the limit (1 GiB) is replaced by the truncation notice, after which nothing more is
	    written or accepted, by this writer or any later one (the flag is process-wide).
	  * The file is created empty, written unbuffered (NSFileHandle -writeData: is one write per
	    message) and synchronised on flush. A write error ends writing (the exception left the
	    thread's loop); the writer still stops cleanly.

	Header-only, C++20, compiles with -fno-exceptions.
*/

#ifndef OOFND_LOGFILE_HPP
#define OOFND_LOGFILE_HPP

// Objective-C++ callers see OOCocoa.h's `#define true 1` / `#define false 0`; suspend them for
// this header (proposed ADR-0028).
#pragma push_macro("true")
#pragma push_macro("false")
#undef true
#undef false

#include "oofnd/FileSystem.hpp"
#include "oofnd/String.hpp"
#include "oofnd/Thread.hpp"

#include <atomic>
#include <condition_variable>
#include <cstdint>
#include <cstdio>
#include <deque>
#include <mutex>
#include <optional>
#include <string>
#include <string_view>
#include <thread>
#include <utility>

#if defined(_WIN32)
#include <io.h>
#else
#include <unistd.h>
#endif

namespace oo::log {

#if defined(_WIN32)
inline constexpr bool kLogFileCRLF = true;
#else
inline constexpr bool kLogFileCRLF = false;
#endif

// OOAsyncLogger's saturation point.
inline constexpr std::uint64_t kLogFileSaturationLimit = std::uint64_t(1) << 30;

// The bytes -asyncLogMessage: enqueued for <line>, or nullopt when it enqueued nothing (a lone
// surrogate made -dataUsingEncoding: answer nil).
inline std::optional<std::string> logFileBytes(std::string_view line, bool crlf)
{
	std::u16string units = oo::utf8ToUtf16(line);
	units += u'\n';
	for (std::size_t i = 0; i < units.size(); ++i)
	{
		const char16_t c = units[i];
		if (c >= 0xD800 && c <= 0xDBFF && i + 1 < units.size() && units[i + 1] >= 0xDC00 && units[i + 1] <= 0xDFFF)
		{
			++i;
			continue;
		}
		if (c >= 0xD800 && c <= 0xDFFF)  return std::nullopt;
	}
	if (!crlf)  return oo::utf16ToUtf8(units);

	std::u16string joined;
	joined.reserve(units.size() + 8);
	for (std::size_t i = 0; i < units.size(); ++i)
	{
		if (units[i] == u'\n' && !(i + 1 < units.size() && oo::str::detail::extendsSequence(units[i + 1])))
		{
			joined += u"\r\n";
		}
		else
		{
			joined += units[i];
		}
	}
	return oo::utf16ToUtf8(joined);
}

// The echo's bytes: UTF-8 with a lone surrogate as U+FFFD, then "\n", up to the first U+0000.
inline std::string consoleBytes(std::string_view line)
{
	std::u16string units = oo::utf8ToUtf16(line);
	for (std::size_t i = 0; i < units.size(); ++i)
	{
		const char16_t c = units[i];
		if (c >= 0xD800 && c <= 0xDBFF && i + 1 < units.size() && units[i + 1] >= 0xDC00 && units[i + 1] <= 0xDFFF)
		{
			++i;
			continue;
		}
		if (c >= 0xD800 && c <= 0xDFFF)  units[i] = 0xFFFD;
	}
	units += u'\n';
	std::string bytes = oo::utf16ToUtf8(units);
	const std::size_t nul = bytes.find('\0');
	if (nul != std::string::npos)  bytes.resize(nul);
	return bytes;
}

// -[OOAsyncLogger init]'s rotation: an existing <latest> replaces <previous> or, if it cannot be
// moved, is deleted. False only when it exists and can be neither moved nor deleted.
inline bool rotateToPrevious(const fs::Path& latest, const fs::Path& previous)
{
	if (!fs::fileExists(latest))  return true;
	(void)fs::removeItem(previous);
	if (fs::moveItem(latest, previous))  return true;
	return static_cast<bool>(fs::removeItem(latest));
}

class FileWriter
{
public:
	// <saturated> is shared by every writer of the process, as OOLogOutputHandler's sSaturated was.
	explicit FileWriter(std::atomic<bool>& saturated, bool crlf = kLogFileCRLF,
		std::uint64_t saturationLimit = kLogFileSaturationLimit) noexcept
		: saturated_(saturated), crlf_(crlf), limit_(saturationLimit)
	{
	}

	FileWriter(const FileWriter&) = delete;
	FileWriter& operator=(const FileWriter&) = delete;

	~FileWriter() { stop(); }

	// -startLogging: create <path> empty and start the writer thread. False if the file cannot be
	// created (the caller then logs to the console only).
	bool start(const fs::Path& path)
	{
		if (thread_.joinable())  return false;
		file_ = fs::detail::openFile(path, true);
		if (file_ == nullptr)  return false;
		std::setvbuf(file_, nullptr, _IONBF, 0);
		failed_ = false;
		written_ = 0;
		accepting_ = true;
		thread_ = std::thread([this] { run(); });
		return true;
	}

	bool running() const noexcept { return thread_.joinable(); }

	// -asyncLogMessage: (the part that queues): nothing once saturated; a line holding a lone
	// surrogate is dropped.
	void write(std::string_view line)
	{
		if (saturated_.load())  return;
		std::optional<std::string> bytes = logFileBytes(line, crlf_);
		if (!bytes.has_value())  return;
		post(Kind::data, std::move(*bytes));
	}

	// -flushLog: have the thread synchronise the file.
	void flush() { post(Kind::flush, std::string()); }

	// -endLogging: queue <postamble> as a line, stop the thread after everything queued, close.
	void end(std::string_view postamble)
	{
		if (!thread_.joinable())  return;
		write(postamble);
		stop();
	}

	// The thread's name, as -loggerThread set it.
	static constexpr const char* kThreadName = "loggerThread";

private:
	enum class Kind
	{
		data,
		flush,
		die,
	};

	void post(Kind kind, std::string bytes)
	{
		{
			std::lock_guard<std::mutex> lock(mutex_);
			if (!accepting_)  return;
			queue_.emplace_back(kind, std::move(bytes));
		}
		ready_.notify_one();
	}

	void stop()
	{
		if (!thread_.joinable())  return;
		{
			std::lock_guard<std::mutex> lock(mutex_);
			accepting_ = false;
			queue_.emplace_back(Kind::die, std::string());
		}
		ready_.notify_one();
		thread_.join();
		queue_.clear();
		if (file_ != nullptr)  std::fclose(file_);
		file_ = nullptr;
	}

	void run()
	{
		oo::thread::setCurrentName(kThreadName);
		for (;;)
		{
			std::pair<Kind, std::string> message;
			{
				std::unique_lock<std::mutex> lock(mutex_);
				ready_.wait(lock, [this] { return !queue_.empty(); });
				message = std::move(queue_.front());
				queue_.pop_front();
			}
			if (message.first == Kind::die)  return;
			if (failed_)  continue;
			if (message.first == Kind::data)
			{
				if (saturated_.load())  continue;
				std::string& bytes = message.second;
				written_ += bytes.size();
				if (written_ > limit_)
				{
					saturated_.store(true);
					bytes = crlf_ ? "\r\n\r\n\r\n***** LOG TRUNCATED DUE TO EXCESSIVE LENGTH *****\r\n"
								  : "\n\n\n***** LOG TRUNCATED DUE TO EXCESSIVE LENGTH *****\n";
				}
				if (!bytes.empty() && std::fwrite(bytes.data(), 1, bytes.size(), file_) != bytes.size())  failed_ = true;
			}
			else
			{
				std::fflush(file_);
#if defined(_WIN32)
				(void)::_commit(::_fileno(file_));
#else
				(void)::fsync(::fileno(file_));
#endif
			}
		}
	}

	std::atomic<bool>& saturated_;
	const bool crlf_;
	const std::uint64_t limit_;
	std::FILE* file_ = nullptr;
	bool failed_ = false;
	std::uint64_t written_ = 0;
	std::thread thread_;
	std::mutex mutex_;
	bool accepting_ = false;	// guarded by mutex_
	std::condition_variable ready_;
	std::deque<std::pair<Kind, std::string>> queue_;
};

} // namespace oo::log

#pragma pop_macro("false")
#pragma pop_macro("true")

#endif // OOFND_LOGFILE_HPP
