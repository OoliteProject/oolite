// clang-format off
/*	oofnd/Http.hpp
        oo::http::Download: one GET on its own thread, its callbacks queued for
        the main thread to take in order. The OXZ manager's NSURLConnection
        without Foundation.

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

        Captured from gnustep-base 1.31.1 against a loopback server (throwaway
        probe; tests/unit/oofnd/test_http.cpp replays the same exchanges against its
        own loopback server):
          * Every status is a response: a 404 or 500 delivers its body and
            finishes; it is not a failure. Only a transport error (refused, unresolved,
            reset before the response) fails.
          * expectedContentLength is the Content-Length header, or -1 without
            one (chunked, a connection-close body, a 204).
          * The body is delivered as sent: no Accept-Encoding is sent and a gzip
            body is not decoded.
          * The request carries User-Agent and Host and nothing else: no
            cookies, no Accept, no credentials (user:password@ in the URL is ignored).
            The fragment is not sent; the query is.
          * An absolute redirect is followed and only the final response is
            delivered.
          * A body cut short by the server closing the connection finishes with
            what arrived.
          * file: URLs are read from disk and delivered the same way.

        Deliberate differences, all in paths no well-formed http(s) URL reaches:
        a URL NSURL rejected (spaces, non-ASCII, empty) or a
        scheme other than http, https or file fails at once, where NSURLConnection
        never called back; an upper-case scheme and a relative redirect work, where
        it also never called back; an empty or unresolvable host fails, where it
        connected somewhere else. A failure's text is libcurl's, not NSError's
        description.

        http(s) goes through libcurl on every platform (pkg-config libcurl; macOS
        ships it with the SDK). On Windows the OpenSSL build trusts the Windows
        certificate store, not a bundle path under the MSYS2 prefix. file: URLs are
        read from disk and need no libcurl.

        Header-only, C++23.
*/
// clang-format on

#pragma once

#include <curl/curl.h>

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <deque>
#include <mutex>
#include <optional>
#include <string>
#include <string_view>
#include <thread>
#include <utility>

#include "oofnd/FileSystem.hpp"

namespace oo::http {

// A URL as the download needs it. `target` is the path and query sent in the
// request line
// ("/" when the URL has no path); the fragment and any user:password@ are
// dropped, as NSURLConnection dropped them. For a file: URL, `path` is the
// file.
struct Url {
  enum class Scheme { http, https, file };
  Scheme scheme = Scheme::http;
  std::string host;
  std::uint16_t port = 0;
  std::string target;
  std::string path;
};

namespace detail {

inline bool isUrlByte(unsigned char c) {
  // What NSURL accepted: printable ASCII other than space and the RFC 2396
  // "unwise" and delimiter characters it rejected.
  if (c <= 0x20 || c >= 0x7F) return false;
  switch (c) {
    case '"':
    case '<':
    case '>':
    case '\\':
    case '^':
    case '`':
    case '{':
    case '|':
    case '}':
      return false;
    default:
      return true;
  }
}

inline int hexValue(char c) {
  if (c >= '0' && c <= '9') return c - '0';
  if (c >= 'a' && c <= 'f') return c - 'a' + 10;
  if (c >= 'A' && c <= 'F') return c - 'A' + 10;
  return -1;
}

inline std::string percentDecoded(std::string_view s) {
  std::string out;
  out.reserve(s.size());
  for (std::size_t i = 0; i < s.size(); i++) {
    if (s[i] == '%' && i + 2 < s.size()) {
      const int hi = hexValue(s[i + 1]), lo = hexValue(s[i + 2]);
      if (hi >= 0 && lo >= 0) {
        out += static_cast<char>(hi * 16 + lo);
        i += 2;
        continue;
      }
    }
    out += s[i];
  }
  return out;
}

inline bool equalsIgnoringCase(std::string_view a, std::string_view b) {
  if (a.size() != b.size()) return false;
  for (std::size_t i = 0; i < a.size(); i++) {
    char x = a[i], y = b[i];
    if (x >= 'A' && x <= 'Z') x = static_cast<char>(x - 'A' + 'a');
    if (y >= 'A' && y <= 'Z') y = static_cast<char>(y - 'A' + 'a');
    if (x != y) return false;
  }
  return true;
}

#if defined(_WIN32)
inline std::wstring wideFromAscii(std::string_view s) {
  return std::wstring(s.begin(), s.end());
}
#endif

}  // namespace detail

// The URL, or nullopt when the download cannot start: not a URL NSURL accepted,
// a scheme other than http/https/file, no host, or a bad port.
inline std::optional<Url> parseUrl(std::string_view text) {
  if (text.empty()) return std::nullopt;
  for (const char c : text) {
    if (!detail::isUrlByte(static_cast<unsigned char>(c))) return std::nullopt;
  }
  const std::size_t colon = text.find(':');
  if (colon == std::string_view::npos || colon == 0) return std::nullopt;
  const std::string_view scheme = text.substr(0, colon);
  Url url;
  if (detail::equalsIgnoringCase(scheme, "http"))
    url.scheme = Url::Scheme::http;
  else if (detail::equalsIgnoringCase(scheme, "https"))
    url.scheme = Url::Scheme::https;
  else if (detail::equalsIgnoringCase(scheme, "file"))
    url.scheme = Url::Scheme::file;
  else
    return std::nullopt;

  std::string_view rest = text.substr(colon + 1);
  const std::size_t hash = rest.find('#');
  if (hash != std::string_view::npos) rest = rest.substr(0, hash);
  if (rest.substr(0, 2) != "//") return std::nullopt;
  rest.remove_prefix(2);

  const std::size_t slash = rest.find_first_of("/?");
  std::string_view authority = rest.substr(0, slash);
  std::string_view target =
      slash == std::string_view::npos ? std::string_view() : rest.substr(slash);

  if (url.scheme == Url::Scheme::file) {
    if (!authority.empty() &&
        !detail::equalsIgnoringCase(authority, "localhost"))
      return std::nullopt;
    const std::size_t query = target.find('?');
    std::string path = detail::percentDecoded(target.substr(0, query));
#if defined(_WIN32)
    // file:///C:/dir/file names C:/dir/file.
    if (path.size() >= 3 && path[0] == '/' && path[2] == ':') path.erase(0, 1);
#endif
    if (path.empty()) return std::nullopt;
    url.path = std::move(path);
    return url;
  }

  const std::size_t at = authority.rfind('@');
  if (at != std::string_view::npos) authority.remove_prefix(at + 1);
  std::string_view host = authority, port;
  if (!authority.empty() && authority.front() == '[') {
    const std::size_t close = authority.find(']');
    if (close == std::string_view::npos) return std::nullopt;
    host = authority.substr(1, close - 1);
    const std::string_view after = authority.substr(close + 1);
    if (!after.empty()) {
      if (after.front() != ':') return std::nullopt;
      port = after.substr(1);
    }
  } else {
    const std::size_t portColon = authority.rfind(':');
    if (portColon != std::string_view::npos) {
      host = authority.substr(0, portColon);
      port = authority.substr(portColon + 1);
    }
  }
  if (host.empty()) return std::nullopt;
  url.host = std::string(host);
  url.port = url.scheme == Url::Scheme::https ? 443 : 80;
  if (!port.empty()) {
    unsigned value = 0;
    for (const char c : port) {
      if (c < '0' || c > '9') return std::nullopt;
      value = value * 10 + static_cast<unsigned>(c - '0');
      if (value > 65535) return std::nullopt;
    }
    if (value == 0) return std::nullopt;
    url.port = static_cast<std::uint16_t>(value);
  }
  url.target = target.empty()
                   ? std::string("/")
                   : (target.front() == '?' ? "/" + std::string(target)
                                            : std::string(target));
  return url;
}

// One delegate callback.
struct Event {
  enum class Kind { response, data, finished, failed };
  Kind kind = Kind::failed;
  int status = 0;  // response: the HTTP status (0 for file:)
  std::int64_t expectedLength =
      -1;             // response: Content-Length, or -1 without one
  std::string bytes;  // data
  std::string error;  // failed: a description for the log
};

// One GET. The constructor starts it on its own thread; the owner takes its
// events, in order, with nextEvent() on its own thread. cancel() (and the
// destructor) stop it: nextEvent() answers nothing afterwards, even for events
// already queued. The destructor waits for the thread, which a cancel
// interrupts.
class Download {
 public:
  Download(std::string url, std::string userAgent) {
    worker_ = std::thread(
        [this, url = std::move(url), userAgent = std::move(userAgent)]() {
          run(url, userAgent);
        });
  }

  Download(const Download&) = delete;
  Download& operator=(const Download&) = delete;

  ~Download() {
    cancel();
    if (worker_.joinable()) worker_.join();
  }

  std::optional<Event> nextEvent() {
    std::lock_guard<std::mutex> lock(mutex_);
    if (cancelled_ || events_.empty()) return std::nullopt;
    Event event = std::move(events_.front());
    events_.pop_front();
    return event;
  }

  void cancel() {
    std::lock_guard<std::mutex> lock(mutex_);
    if (cancelled_) return;
    cancelled_ = true;
    events_.clear();
  }

  bool cancelled() const {
    std::lock_guard<std::mutex> lock(mutex_);
    return cancelled_;
  }

  // The read size: one data event carries at most this many bytes.
  static constexpr std::size_t kChunkSize = 64 * 1024;

 private:
  void push(Event event) {
    std::lock_guard<std::mutex> lock(mutex_);
    if (!cancelled_) events_.push_back(std::move(event));
  }

  static Event failure(std::string text) {
    Event event;
    event.kind = Event::Kind::failed;
    event.error = std::move(text);
    return event;
  }

  void run(const std::string& text, const std::string& userAgent) {
    const std::optional<Url> url = parseUrl(text);
    if (!url.has_value()) {
      push(failure("unsupported URL \"" + text + "\""));
      return;
    }
    if (url->scheme == Url::Scheme::file) {
      runFile(url->path);
      return;
    }
    runCurl(*url, userAgent);
  }

  void runFile(const std::string& path) {
    auto data = fs::readFile(fs::pathFromUTF8(path));
    if (!data.has_value()) {
      push(failure("cannot read file " + path));
      return;
    }
    Event response;
    response.kind = Event::Kind::response;
    response.expectedLength = static_cast<std::int64_t>(data->length());
    push(std::move(response));
    const std::string_view bytes = data->stringView();
    for (std::size_t offset = 0; offset < bytes.size(); offset += kChunkSize) {
      Event chunk;
      chunk.kind = Event::Kind::data;
      chunk.bytes = std::string(bytes.substr(offset, kChunkSize));
      push(std::move(chunk));
    }
    Event done;
    done.kind = Event::Kind::finished;
    push(std::move(done));
  }

  // What the header callback has seen of the response being read.
  struct Transfer {
    Download* download = nullptr;
    int status = 0;
    std::int64_t length = -1;
    bool redirect = false;   // this block has a Location header
    bool responded = false;  // the response event is queued
  };

  // The request URL as the contract sends it: no fragment, no user:password@.
  static std::string curlUrl(const Url& url) {
    std::string text =
        url.scheme == Url::Scheme::https ? "https://" : "http://";
    text += url.host.find(':') != std::string::npos ? "[" + url.host + "]"
                                                    : url.host;
    return text + ":" + std::to_string(url.port) + url.target;
  }

  static std::string curlErrorText(CURLcode code, const char* detail) {
    std::string text = std::string("request failed: libcurl error ") +
                       std::to_string(static_cast<int>(code)) + " (" +
                       curl_easy_strerror(code) + ")";
    if (detail != nullptr && detail[0] != '\0')
      text += std::string(": ") + detail;
    return text;
  }

  void respond(Transfer& transfer) {
    Event response;
    response.kind = Event::Kind::response;
    response.status = transfer.status;
    response.expectedLength = transfer.length;
    push(std::move(response));
    transfer.responded = true;
  }

  // One header line. A block ends at its blank line; the blocks of an
  // informational status or of a redirect that is followed are not the
  // response.
  static std::size_t onHeader(char* data, std::size_t size, std::size_t count,
                              void* user) {
    Transfer& transfer = *static_cast<Transfer*>(user);
    const std::size_t total = size * count;
    const std::string_view line(data, total);
    if (transfer.responded) return total;  // trailers
    if (line.rfind("HTTP/", 0) == 0) {
      const std::size_t space = line.find(' ');
      transfer.status = 0;
      for (std::size_t i = space == std::string_view::npos ? line.size()
                                                           : space + 1;
           i < line.size() && line[i] >= '0' && line[i] <= '9'; i++) {
        transfer.status = transfer.status * 10 + (line[i] - '0');
      }
      transfer.length = -1;
      transfer.redirect = false;
    } else if (line == "\r\n" || line == "\n") {
      const bool followed = transfer.status / 100 == 1 ||
                            (transfer.status / 100 == 3 && transfer.redirect);
      if (!followed) transfer.download->respond(transfer);
    } else {
      const std::size_t colon = line.find(':');
      if (colon != std::string_view::npos) {
        const std::string_view name = line.substr(0, colon);
        if (detail::equalsIgnoringCase(name, "Location")) {
          transfer.redirect = true;
        } else if (detail::equalsIgnoringCase(name, "Content-Length")) {
          std::string_view value = line.substr(colon + 1);
          while (!value.empty() &&
                 (value.front() == ' ' || value.front() == '\t'))
            value.remove_prefix(1);
          while (!value.empty() &&
                 (value.back() == '\r' || value.back() == '\n' ||
                  value.back() == ' ' || value.back() == '\t'))
            value.remove_suffix(1);
          std::int64_t length = 0;
          bool digits = !value.empty();
          for (const char c : value) {
            if (c < '0' || c > '9' || length > (INT64_MAX - 9) / 10) {
              digits = false;
              break;
            }
            length = length * 10 + (c - '0');
          }
          if (digits) transfer.length = length;
        }
      }
    }
    return total;
  }

  static std::size_t onData(char* data, std::size_t size, std::size_t count,
                            void* user) {
    Transfer& transfer = *static_cast<Transfer*>(user);
    Download& download = *transfer.download;
    const std::size_t total = size * count;
    if (download.cancelled()) {
#if defined(CURL_WRITEFUNC_ERROR)
      return CURL_WRITEFUNC_ERROR;
#else
      return 0;
#endif
    }
    if (!transfer.responded) download.respond(transfer);  // no headers seen
    for (std::size_t offset = 0; offset < total; offset += kChunkSize) {
      Event chunk;
      chunk.kind = Event::Kind::data;
      chunk.bytes.assign(data + offset, std::min(kChunkSize, total - offset));
      download.push(std::move(chunk));
    }
    return total;
  }

  // Called about once a second even when nothing arrives, which is what ends a
  // stalled transfer after cancel().
  static int onProgress(void* user, curl_off_t, curl_off_t, curl_off_t,
                        curl_off_t) {
    return static_cast<Transfer*>(user)->download->cancelled() ? 1 : 0;
  }

  void runCurl(const Url& url, const std::string& userAgent) {
    static const CURLcode initialised = curl_global_init(CURL_GLOBAL_DEFAULT);
    if (initialised != CURLE_OK) {
      push(failure(curlErrorText(initialised, "curl_global_init")));
      return;
    }
    CURL* curl = curl_easy_init();
    if (curl == nullptr) {
      push(failure("curl_easy_init failed"));
      return;
    }
    // Accept: is removed; curl sends no cookies, no Accept-Encoding and no
    // credentials unless asked.
    curl_slist* headers = curl_slist_append(nullptr, "Accept:");
    char errorBuffer[CURL_ERROR_SIZE] = {};
    Transfer transfer;
    transfer.download = this;
    const std::string target = curlUrl(url);

    curl_easy_setopt(curl, CURLOPT_URL, target.c_str());
    curl_easy_setopt(curl, CURLOPT_USERAGENT, userAgent.c_str());
    curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);
    curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION, 1L);
    curl_easy_setopt(curl, CURLOPT_MAXREDIRS, 20L);
#if LIBCURL_VERSION_NUM >= 0x075500  // 7.85.0
    curl_easy_setopt(curl, CURLOPT_PROTOCOLS_STR, "http,https");
    curl_easy_setopt(curl, CURLOPT_REDIR_PROTOCOLS_STR, "http,https");
#endif
    curl_easy_setopt(curl, CURLOPT_NOSIGNAL, 1L);
    // NSURLRequest's 60 s: to connect, and without a byte for that long.
    curl_easy_setopt(curl, CURLOPT_CONNECTTIMEOUT, 60L);
    curl_easy_setopt(curl, CURLOPT_LOW_SPEED_LIMIT, 1L);
    curl_easy_setopt(curl, CURLOPT_LOW_SPEED_TIME, 60L);
    curl_easy_setopt(curl, CURLOPT_BUFFERSIZE, static_cast<long>(kChunkSize));
#if defined(_WIN32) && LIBCURL_VERSION_NUM >= 0x074700  // 7.71.0
    curl_easy_setopt(curl, CURLOPT_SSL_OPTIONS,
                     static_cast<long>(CURLSSLOPT_NATIVE_CA));
#endif
    curl_easy_setopt(curl, CURLOPT_ERRORBUFFER, errorBuffer);
    curl_easy_setopt(curl, CURLOPT_HEADERFUNCTION, &Download::onHeader);
    curl_easy_setopt(curl, CURLOPT_HEADERDATA, &transfer);
    curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, &Download::onData);
    curl_easy_setopt(curl, CURLOPT_WRITEDATA, &transfer);
    curl_easy_setopt(curl, CURLOPT_NOPROGRESS, 0L);
    curl_easy_setopt(curl, CURLOPT_XFERINFOFUNCTION, &Download::onProgress);
    curl_easy_setopt(curl, CURLOPT_XFERINFODATA, &transfer);

    const CURLcode code = curl_easy_perform(curl);
    curl_slist_free_all(headers);
    curl_easy_cleanup(curl);

    if (cancelled()) return;
    // A body the server cut short finished with what had arrived.
    if (code != CURLE_OK &&
        !(code == CURLE_PARTIAL_FILE && transfer.responded)) {
      push(failure(curlErrorText(code, errorBuffer)));
      return;
    }
    Event done;
    done.kind = Event::Kind::finished;
    push(std::move(done));
  }

  mutable std::mutex mutex_;
  bool cancelled_ = false;    // guarded by mutex_
  std::deque<Event> events_;  // guarded by mutex_
  std::thread worker_;
};

}  // namespace oo::http
