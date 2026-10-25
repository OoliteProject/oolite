/*	oofnd/Http.hpp
	oo::http::Download: one GET on its own thread, its callbacks queued for the main thread to
	take in order (bead oo-3rb.13, proposed ADR-0044). The OXZ manager's NSURLConnection without
	Foundation.

	    OOOXZManager (Objective-C, gnustep-base 1.31)            oo::http
	    -------------------------------------------------------  -------------------------------------
	    [NSURL URLWithString:] + NSMutableURLRequest             parseUrl(url)
	    User-Agent header, -setHTTPShouldHandleCookies:NO        Download(url, userAgent)
	    NSURLConnection -initWithRequest:delegate:               Download(url, userAgent)
	    delegate callbacks, delivered by the run loop            Download::nextEvent() (main thread)
	    -connection:didReceiveResponse: (expectedContentLength)  Event::Kind::response (expectedLength)
	    -connection:didReceiveData:                              Event::Kind::data (bytes)
	    -connectionDidFinishLoading:                             Event::Kind::finished
	    -connection:didFailWithError:                            Event::Kind::failed (error)
	    -[NSURLConnection cancel]                                Download::cancel()

	Captured from gnustep-base 1.31.1 against a loopback server (throwaway probe;
	tests/unit/oofnd/test_http.cpp replays the same exchanges against its own loopback server):
	  * Every status is a response: a 404 or 500 delivers its body and finishes; it is not a
	    failure. Only a transport error (refused, unresolved, reset before the response) fails.
	  * expectedContentLength is the Content-Length header, or -1 without one (chunked, a
	    connection-close body, a 204).
	  * The body is delivered as sent: no Accept-Encoding is sent and a gzip body is not decoded.
	  * The request carries User-Agent and Host and nothing else: no cookies, no Accept, no
	    credentials (user:password@ in the URL is ignored). The fragment is not sent; the query is.
	  * An absolute redirect is followed and only the final response is delivered.
	  * A body cut short by the server closing the connection finishes with what arrived.
	  * file: URLs are read from disk and delivered the same way.

	Deliberate differences, all in paths no well-formed http(s) URL reaches (proposed ADR-0044):
	a URL NSURL rejected (spaces, non-ASCII, empty) or a scheme other than http, https or file
	fails at once, where NSURLConnection never called back; an upper-case scheme and a relative
	redirect work, where it also never called back; an empty or unresolvable host fails, where
	it connected somewhere else. A failure's text is WinHTTP's, not NSError's description.

	Windows: WinHTTP (an OS component; link -lwinhttp). Elsewhere every http(s) download fails
	with a clear error until the Phase 5 backend (libcurl) lands; file: URLs work everywhere.

	Header-only, C++20, compiles with -fno-exceptions.
*/

#ifndef OOFND_HTTP_HPP
#define OOFND_HTTP_HPP

// Objective-C++ callers see OOCocoa.h's `#define true 1` / `#define false 0`; suspend them for
// this header (proposed ADR-0028).
#pragma push_macro("true")
#pragma push_macro("false")
#undef true
#undef false

#include "oofnd/FileSystem.hpp"

#include <cstddef>
#include <cstdint>
#include <deque>
#include <limits>
#include <mutex>
#include <optional>
#include <string>
#include <string_view>
#include <thread>
#include <utility>

#if defined(_WIN32)
// Declared exactly as <winhttp.h> and <windows.h> declare them (HINTERNET = void *, DWORD =
// unsigned long, BOOL = int, INTERNET_PORT = unsigned short, DWORD_PTR = unsigned long long), so
// this header does not pull <windows.h> into Objective-C++ game code.
extern "C" {
__declspec(dllimport) void * __stdcall WinHttpOpen(const wchar_t *agent, unsigned long accessType, const wchar_t *proxy, const wchar_t *proxyBypass, unsigned long flags);
__declspec(dllimport) void * __stdcall WinHttpConnect(void *session, const wchar_t *serverName, unsigned short serverPort, unsigned long reserved);
__declspec(dllimport) void * __stdcall WinHttpOpenRequest(void *connect, const wchar_t *verb, const wchar_t *objectName, const wchar_t *version, const wchar_t *referrer, const wchar_t **acceptTypes, unsigned long flags);
__declspec(dllimport) int __stdcall WinHttpSetOption(void *handle, unsigned long option, void *buffer, unsigned long bufferLength);
__declspec(dllimport) int __stdcall WinHttpSetTimeouts(void *handle, int resolveTimeout, int connectTimeout, int sendTimeout, int receiveTimeout);
__declspec(dllimport) int __stdcall WinHttpSendRequest(void *request, const wchar_t *headers, unsigned long headersLength, void *optional, unsigned long optionalLength, unsigned long totalLength, unsigned long long context);
__declspec(dllimport) int __stdcall WinHttpReceiveResponse(void *request, void *reserved);
__declspec(dllimport) int __stdcall WinHttpQueryHeaders(void *request, unsigned long infoLevel, const wchar_t *name, void *buffer, unsigned long *bufferLength, unsigned long *index);
__declspec(dllimport) int __stdcall WinHttpQueryDataAvailable(void *request, unsigned long *bytesAvailable);
__declspec(dllimport) int __stdcall WinHttpReadData(void *request, void *buffer, unsigned long bytesToRead, unsigned long *bytesRead);
__declspec(dllimport) int __stdcall WinHttpCloseHandle(void *handle);
__declspec(dllimport) unsigned long __stdcall GetLastError(void);
}
#endif

namespace oo::http {

// A URL as the download needs it. `target` is the path and query sent in the request line
// ("/" when the URL has no path); the fragment and any user:password@ are dropped, as
// NSURLConnection dropped them. For a file: URL, `path` is the file.
struct Url
{
	enum class Scheme { http, https, file };
	Scheme scheme = Scheme::http;
	std::string host;
	std::uint16_t port = 0;
	std::string target;
	std::string path;
};

namespace detail {

inline bool isUrlByte(unsigned char c)
{
	// What NSURL accepted: printable ASCII other than space and the RFC 2396 "unwise" and
	// delimiter characters it rejected.
	if (c <= 0x20 || c >= 0x7F)  return false;
	switch (c)
	{
		case '"': case '<': case '>': case '\\': case '^': case '`': case '{': case '|': case '}':
			return false;
		default:
			return true;
	}
}

inline int hexValue(char c)
{
	if (c >= '0' && c <= '9')  return c - '0';
	if (c >= 'a' && c <= 'f')  return c - 'a' + 10;
	if (c >= 'A' && c <= 'F')  return c - 'A' + 10;
	return -1;
}

inline std::string percentDecoded(std::string_view s)
{
	std::string out;
	out.reserve(s.size());
	for (std::size_t i = 0; i < s.size(); i++)
	{
		if (s[i] == '%' && i + 2 < s.size())
		{
			const int hi = hexValue(s[i + 1]), lo = hexValue(s[i + 2]);
			if (hi >= 0 && lo >= 0)
			{
				out += static_cast<char>(hi * 16 + lo);
				i += 2;
				continue;
			}
		}
		out += s[i];
	}
	return out;
}

inline bool equalsIgnoringCase(std::string_view a, std::string_view b)
{
	if (a.size() != b.size())  return false;
	for (std::size_t i = 0; i < a.size(); i++)
	{
		char x = a[i], y = b[i];
		if (x >= 'A' && x <= 'Z')  x = static_cast<char>(x - 'A' + 'a');
		if (y >= 'A' && y <= 'Z')  y = static_cast<char>(y - 'A' + 'a');
		if (x != y)  return false;
	}
	return true;
}

#if defined(_WIN32)
inline std::wstring wideFromAscii(std::string_view s)
{
	return std::wstring(s.begin(), s.end());
}
#endif

} // namespace detail

// The URL, or nullopt when the download cannot start: not a URL NSURL accepted, a scheme other
// than http/https/file, no host, or a bad port.
inline std::optional<Url> parseUrl(std::string_view text)
{
	if (text.empty())  return std::nullopt;
	for (const char c : text)
	{
		if (!detail::isUrlByte(static_cast<unsigned char>(c)))  return std::nullopt;
	}
	const std::size_t colon = text.find(':');
	if (colon == std::string_view::npos || colon == 0)  return std::nullopt;
	const std::string_view scheme = text.substr(0, colon);
	Url url;
	if (detail::equalsIgnoringCase(scheme, "http"))  url.scheme = Url::Scheme::http;
	else if (detail::equalsIgnoringCase(scheme, "https"))  url.scheme = Url::Scheme::https;
	else if (detail::equalsIgnoringCase(scheme, "file"))  url.scheme = Url::Scheme::file;
	else  return std::nullopt;

	std::string_view rest = text.substr(colon + 1);
	const std::size_t hash = rest.find('#');
	if (hash != std::string_view::npos)  rest = rest.substr(0, hash);
	if (rest.substr(0, 2) != "//")  return std::nullopt;
	rest.remove_prefix(2);

	const std::size_t slash = rest.find_first_of("/?");
	std::string_view authority = rest.substr(0, slash);
	std::string_view target = slash == std::string_view::npos ? std::string_view() : rest.substr(slash);

	if (url.scheme == Url::Scheme::file)
	{
		if (!authority.empty() && !detail::equalsIgnoringCase(authority, "localhost"))  return std::nullopt;
		const std::size_t query = target.find('?');
		std::string path = detail::percentDecoded(target.substr(0, query));
#if defined(_WIN32)
		// file:///C:/dir/file names C:/dir/file.
		if (path.size() >= 3 && path[0] == '/' && path[2] == ':')  path.erase(0, 1);
#endif
		if (path.empty())  return std::nullopt;
		url.path = std::move(path);
		return url;
	}

	const std::size_t at = authority.rfind('@');
	if (at != std::string_view::npos)  authority.remove_prefix(at + 1);
	std::string_view host = authority, port;
	if (!authority.empty() && authority.front() == '[')
	{
		const std::size_t close = authority.find(']');
		if (close == std::string_view::npos)  return std::nullopt;
		host = authority.substr(1, close - 1);
		const std::string_view after = authority.substr(close + 1);
		if (!after.empty())
		{
			if (after.front() != ':')  return std::nullopt;
			port = after.substr(1);
		}
	}
	else
	{
		const std::size_t portColon = authority.rfind(':');
		if (portColon != std::string_view::npos)
		{
			host = authority.substr(0, portColon);
			port = authority.substr(portColon + 1);
		}
	}
	if (host.empty())  return std::nullopt;
	url.host = std::string(host);
	url.port = url.scheme == Url::Scheme::https ? 443 : 80;
	if (!port.empty())
	{
		unsigned value = 0;
		for (const char c : port)
		{
			if (c < '0' || c > '9')  return std::nullopt;
			value = value * 10 + static_cast<unsigned>(c - '0');
			if (value > 65535)  return std::nullopt;
		}
		if (value == 0)  return std::nullopt;
		url.port = static_cast<std::uint16_t>(value);
	}
	url.target = target.empty() ? std::string("/") : (target.front() == '?' ? "/" + std::string(target) : std::string(target));
	return url;
}

// One delegate callback.
struct Event
{
	enum class Kind { response, data, finished, failed };
	Kind kind = Kind::failed;
	int status = 0;						// response: the HTTP status (0 for file:)
	std::int64_t expectedLength = -1;	// response: Content-Length, or -1 without one
	std::string bytes;					// data
	std::string error;					// failed: a description for the log
};

// One GET. The constructor starts it on its own thread; the owner takes its events, in order,
// with nextEvent() on its own thread. cancel() (and the destructor) stop it: nextEvent() answers
// nothing afterwards, even for events already queued. The destructor waits for the thread,
// which a cancel interrupts.
class Download
{
public:
	Download(std::string url, std::string userAgent)
	{
		worker_ = std::thread([this, url = std::move(url), userAgent = std::move(userAgent)]() {
			run(url, userAgent);
		});
	}

	Download(const Download&) = delete;
	Download& operator=(const Download&) = delete;

	~Download()
	{
		cancel();
		if (worker_.joinable())  worker_.join();
	}

	std::optional<Event> nextEvent()
	{
		std::lock_guard<std::mutex> lock(mutex_);
		if (cancelled_ || events_.empty())  return std::nullopt;
		Event event = std::move(events_.front());
		events_.pop_front();
		return event;
	}

	void cancel()
	{
		std::lock_guard<std::mutex> lock(mutex_);
		if (cancelled_)  return;
		cancelled_ = true;
		events_.clear();
#if defined(_WIN32)
		// Closing the request handle ends a blocking WinHTTP call on the worker.
		if (request_ != nullptr)
		{
			WinHttpCloseHandle(request_);
			request_ = nullptr;
		}
#endif
	}

	bool cancelled() const
	{
		std::lock_guard<std::mutex> lock(mutex_);
		return cancelled_;
	}

	// The read size: one data event carries at most this many bytes.
	static constexpr std::size_t kChunkSize = 64 * 1024;

private:
	void push(Event event)
	{
		std::lock_guard<std::mutex> lock(mutex_);
		if (!cancelled_)  events_.push_back(std::move(event));
	}

	static Event failure(std::string text)
	{
		Event event;
		event.kind = Event::Kind::failed;
		event.error = std::move(text);
		return event;
	}

	void run(const std::string& text, const std::string& userAgent)
	{
		const std::optional<Url> url = parseUrl(text);
		if (!url.has_value())
		{
			push(failure("unsupported URL \"" + text + "\""));
			return;
		}
		if (url->scheme == Url::Scheme::file)
		{
			runFile(url->path);
			return;
		}
#if defined(_WIN32)
		runWinHttp(*url, userAgent);
#else
		(void)userAgent;
		push(failure("no HTTP client in this build (proposed ADR-0044: libcurl at Phase 5)"));
#endif
	}

	void runFile(const std::string& path)
	{
		auto data = fs::readFile(fs::pathFromUTF8(path));
		if (!data.has_value())
		{
			push(failure("cannot read file " + path));
			return;
		}
		Event response;
		response.kind = Event::Kind::response;
		response.expectedLength = static_cast<std::int64_t>(data->length());
		push(std::move(response));
		const std::string_view bytes = data->stringView();
		for (std::size_t offset = 0; offset < bytes.size(); offset += kChunkSize)
		{
			Event chunk;
			chunk.kind = Event::Kind::data;
			chunk.bytes = std::string(bytes.substr(offset, kChunkSize));
			push(std::move(chunk));
		}
		Event done;
		done.kind = Event::Kind::finished;
		push(std::move(done));
	}

#if defined(_WIN32)
	static constexpr unsigned long kAccessTypeNoProxy = 1;					// WINHTTP_ACCESS_TYPE_NO_PROXY
	static constexpr unsigned long kFlagSecure = 0x00800000;				// WINHTTP_FLAG_SECURE
	static constexpr unsigned long kOptionDisableFeature = 63;				// WINHTTP_OPTION_DISABLE_FEATURE
	static constexpr unsigned long kDisableCookies = 0x1;					// WINHTTP_DISABLE_COOKIES
	static constexpr unsigned long kOptionRedirectPolicy = 88;				// WINHTTP_OPTION_REDIRECT_POLICY
	static constexpr unsigned long kRedirectPolicyAlways = 2;				// ..._REDIRECT_POLICY_ALWAYS
	static constexpr unsigned long kQueryContentLength = 5;					// WINHTTP_QUERY_CONTENT_LENGTH
	static constexpr unsigned long kQueryStatusCode = 19;					// WINHTTP_QUERY_STATUS_CODE
	static constexpr unsigned long kQueryFlagNumber = 0x20000000;			// WINHTTP_QUERY_FLAG_NUMBER
	static constexpr unsigned long kErrorConnectionError = 12030;			// ERROR_WINHTTP_CONNECTION_ERROR
	static constexpr int kTimeoutMilliseconds = 60000;						// NSURLRequest's 60 s

	static std::string errorText(const char *step, unsigned long code)
	{
		const char *what = nullptr;
		switch (code)
		{
			case 12002: what = "the operation timed out"; break;
			case 12005: what = "the URL is invalid"; break;
			case 12007: what = "the server name could not be resolved"; break;
			case 12017: what = "the operation was cancelled"; break;
			case 12029: what = "could not connect to the server"; break;
			case 12030: what = "the connection with the server was terminated"; break;
			case 12152: what = "the server returned an invalid response"; break;
			case 12156: what = "the redirect failed"; break;
			case 12175: what = "a secure connection could not be established"; break;
			default: break;
		}
		std::string text = std::string(step) + " failed: WinHTTP error " + std::to_string(code);
		if (what != nullptr)  text += std::string(" (") + what + ")";
		return text;
	}

	// The request handle, or nullptr once cancel() has closed it.
	void *request()
	{
		std::lock_guard<std::mutex> lock(mutex_);
		return request_;
	}

	void runWinHttp(const Url& url, const std::string& userAgent)
	{
		void *session = WinHttpOpen(detail::wideFromAscii(userAgent).c_str(), kAccessTypeNoProxy, nullptr, nullptr, 0);
		if (session == nullptr)
		{
			push(failure(errorText("WinHttpOpen", GetLastError())));
			return;
		}
		WinHttpSetTimeouts(session, kTimeoutMilliseconds, kTimeoutMilliseconds, kTimeoutMilliseconds, kTimeoutMilliseconds);
		void *connect = WinHttpConnect(session, detail::wideFromAscii(url.host).c_str(), url.port, 0);
		if (connect == nullptr)
		{
			push(failure(errorText("WinHttpConnect", GetLastError())));
			WinHttpCloseHandle(session);
			return;
		}
		void *handle = WinHttpOpenRequest(connect, L"GET", detail::wideFromAscii(url.target).c_str(), nullptr, nullptr, nullptr,
										  url.scheme == Url::Scheme::https ? kFlagSecure : 0);
		if (handle == nullptr)
		{
			push(failure(errorText("WinHttpOpenRequest", GetLastError())));
			WinHttpCloseHandle(connect);
			WinHttpCloseHandle(session);
			return;
		}
		{
			std::lock_guard<std::mutex> lock(mutex_);
			if (cancelled_)  WinHttpCloseHandle(handle);
			else  request_ = handle;
		}
		transfer();
		{
			std::lock_guard<std::mutex> lock(mutex_);
			if (request_ != nullptr)
			{
				WinHttpCloseHandle(request_);
				request_ = nullptr;
			}
		}
		WinHttpCloseHandle(connect);
		WinHttpCloseHandle(session);
	}

	void transfer()
	{
		void *handle = request();
		if (handle == nullptr)  return;
		unsigned long option = kDisableCookies;
		WinHttpSetOption(handle, kOptionDisableFeature, &option, sizeof option);
		option = kRedirectPolicyAlways;
		WinHttpSetOption(handle, kOptionRedirectPolicy, &option, sizeof option);

		if (!WinHttpSendRequest(handle, nullptr, 0, nullptr, 0, 0, 0))
		{
			push(failure(errorText("sending the request", GetLastError())));
			return;
		}
		if (!WinHttpReceiveResponse(handle, nullptr))
		{
			push(failure(errorText("receiving the response", GetLastError())));
			return;
		}

		Event response;
		response.kind = Event::Kind::response;
		unsigned long status = 0, size = sizeof status;
		if (WinHttpQueryHeaders(handle, kQueryStatusCode | kQueryFlagNumber, nullptr, &status, &size, nullptr))
		{
			response.status = static_cast<int>(status);
		}
		wchar_t lengthText[32] = {};
		size = sizeof lengthText - sizeof(wchar_t);
		if (WinHttpQueryHeaders(handle, kQueryContentLength, nullptr, lengthText, &size, nullptr))
		{
			std::int64_t length = 0;
			bool digits = lengthText[0] != L'\0';
			for (const wchar_t *p = lengthText; *p != L'\0'; p++)
			{
				if (*p < L'0' || *p > L'9' || length > (std::numeric_limits<std::int64_t>::max() - 9) / 10)
				{
					digits = false;
					break;
				}
				length = length * 10 + (*p - L'0');
			}
			if (digits)  response.expectedLength = length;
		}
		push(std::move(response));

		std::string buffer(kChunkSize, '\0');
		for (;;)
		{
			handle = request();
			if (handle == nullptr)  return;
			// Ask what has arrived first: a synchronous read of a full buffer would wait for it.
			unsigned long available = 0, got = 0;
			bool ok = WinHttpQueryDataAvailable(handle, &available) != 0;
			if (ok && available > 0)
			{
				const unsigned long want = available < buffer.size() ? available : static_cast<unsigned long>(buffer.size());
				ok = WinHttpReadData(handle, buffer.data(), want, &got) != 0;
			}
			if (!ok)
			{
				const unsigned long code = GetLastError();
				// A body the server cut short finished with what had arrived.
				if (code != kErrorConnectionError)
				{
					push(failure(errorText("reading the response", code)));
					return;
				}
				got = 0;
			}
			if (got == 0)  break;
			Event chunk;
			chunk.kind = Event::Kind::data;
			chunk.bytes.assign(buffer.data(), got);
			push(std::move(chunk));
		}
		Event done;
		done.kind = Event::Kind::finished;
		push(std::move(done));
	}
#endif

	mutable std::mutex mutex_;
	bool cancelled_ = false;			// guarded by mutex_
	std::deque<Event> events_;			// guarded by mutex_
#if defined(_WIN32)
	void *request_ = nullptr;			// guarded by mutex_
#endif
	std::thread worker_;
};

} // namespace oo::http

#pragma pop_macro("false")
#pragma pop_macro("true")

#endif // OOFND_HTTP_HPP
