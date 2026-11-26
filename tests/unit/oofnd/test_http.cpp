/*	test_http.cpp
	oo::http::parseUrl and oo::http::Download (oofnd/Http.hpp, bead oo-3rb.13, proposed ADR-0044).

	The exchanges below are the ones a throwaway probe ran through gnustep-base 1.31.1's
	NSURLConnection against a loopback server; the expected callbacks are what it delivered
	(status, expectedContentLength, body, finish or fail), except where the header comment of
	Http.hpp lists a deliberate difference (the relative redirect, an unparseable URL).

	On Windows the test runs its own HTTP server on 127.0.0.1 (winsock): no network is used.
	Link: -lwinhttp -lws2_32 (tests/unit/oofnd/meson.build; tools/check-oofnd.sh reads this line:)
*/
// oofnd-link-windows: -lwinhttp -lws2_32

// The header must survive OOCocoa.h's true/false macros and hand them back (proposed ADR-0028).
#define true						1
#define false						0
#include "oofnd/Http.hpp"
#include <type_traits>
static_assert(std::is_same_v<decltype(true), int>, "Http.hpp must restore OOCocoa.h's true macro");
#undef true
#undef false

#include "oo_test.hpp"

#include <atomic>
#include <chrono>
#include <cstdint>
#include <filesystem>
#include <mutex>
#include <optional>
#include <string>
#include <thread>
#include <vector>

#if defined(_WIN32)
#include <winsock2.h>
#include <ws2tcpip.h>
#endif

namespace {

using oo::http::Download;
using oo::http::Event;
using oo::http::Url;
using oo::http::parseUrl;

const char* const kUserAgent = "Oolite/1.93";

// Everything one download delivered, in order.
struct Transcript
{
	int responses = 0;
	int status = -1;
	std::int64_t expected = -2;
	std::string body;
	bool finished = false;
	bool failed = false;
	bool dataBeforeResponse = false;
	bool eventAfterEnd = false;
	std::string error;
};

// Takes events until the download ends (or 30 s pass), as the frame loop would.
Transcript run(Download& download)
{
	Transcript t;
	const auto limit = std::chrono::steady_clock::now() + std::chrono::seconds(30);
	while (std::chrono::steady_clock::now() < limit)
	{
		std::optional<Event> event = download.nextEvent();
		if (!event.has_value())
		{
			if (t.finished || t.failed)  break;
			std::this_thread::sleep_for(std::chrono::milliseconds(2));
			continue;
		}
		if (t.finished || t.failed)  t.eventAfterEnd = true;
		switch (event->kind)
		{
			case Event::Kind::response:
				t.responses++;
				t.status = event->status;
				t.expected = event->expectedLength;
				t.body.clear();
				break;
			case Event::Kind::data:
				if (t.responses == 0)  t.dataBeforeResponse = true;
				t.body += event->bytes;
				break;
			case Event::Kind::finished:
				t.finished = true;
				break;
			case Event::Kind::failed:
				t.failed = true;
				t.error = event->error;
				break;
		}
	}
	// Nothing trails the end.
	std::this_thread::sleep_for(std::chrono::milliseconds(20));
	if (download.nextEvent().has_value())  t.eventAfterEnd = true;
	return t;
}

Transcript get(const std::string& url)
{
	Download download(url, kUserAgent);
	return run(download);
}

std::string bigBody()
{
	std::string body;
	body.reserve(300000);
	for (int i = 0; i < 300000; i++)  body += static_cast<char>(i % 251);
	return body;
}

// --- parseUrl -------------------------------------------------------------------------------------

OO_TEST(parse_http_urls)
{
	auto u = parseUrl("https://addons.oolite.space/api/1.0/overview");
	OO_CHECK(u.has_value());
	OO_CHECK(u->scheme == Url::Scheme::https);
	OO_CHECK_EQ(u->host, std::string("addons.oolite.space"));
	OO_CHECK_EQ(u->port, 443);
	OO_CHECK_EQ(u->target, std::string("/api/1.0/overview"));

	u = parseUrl("http://127.0.0.1:18432");
	OO_CHECK(u.has_value());
	OO_CHECK(u->scheme == Url::Scheme::http);
	OO_CHECK_EQ(u->port, 18432);
	OO_CHECK_EQ(u->target, std::string("/"));

	u = parseUrl("http://127.0.0.1:18432/ok?x=1#frag");
	OO_CHECK(u.has_value());
	OO_CHECK_EQ(u->target, std::string("/ok?x=1"));

	u = parseUrl("http://example.com?q");
	OO_CHECK(u.has_value());
	OO_CHECK_EQ(u->target, std::string("/?q"));

	u = parseUrl("http://user:pw@127.0.0.1:18432/headers");
	OO_CHECK(u.has_value());
	OO_CHECK_EQ(u->host, std::string("127.0.0.1"));
	OO_CHECK_EQ(u->target, std::string("/headers"));

	u = parseUrl("HTTP://127.0.0.1/a%20b");
	OO_CHECK(u.has_value());
	OO_CHECK(u->scheme == Url::Scheme::http);
	OO_CHECK_EQ(u->port, 80);
	OO_CHECK_EQ(u->target, std::string("/a%20b"));

	u = parseUrl("http://[::1]:8080/x");
	OO_CHECK(u.has_value());
	OO_CHECK_EQ(u->host, std::string("::1"));
	OO_CHECK_EQ(u->port, 8080);
}

OO_TEST(parse_file_urls)
{
	auto u = parseUrl("file:///C:/Windows/win.ini");
	OO_CHECK(u.has_value());
	OO_CHECK(u->scheme == Url::Scheme::file);
#if defined(_WIN32)
	OO_CHECK_EQ(u->path, std::string("C:/Windows/win.ini"));
#else
	OO_CHECK_EQ(u->path, std::string("/C:/Windows/win.ini"));
#endif
	u = parseUrl("file://localhost/tmp/a%20b.txt");
	OO_CHECK(u.has_value());
	OO_CHECK_EQ(u->path, std::string("/tmp/a b.txt"));
	OO_CHECK(!parseUrl("file://otherhost/x").has_value());
	OO_CHECK(!parseUrl("file://").has_value());
}

OO_TEST(parse_rejects_what_cannot_start)
{
	// NSURL answered nil for these (spaces, non-ASCII, empty).
	OO_CHECK(!parseUrl("").has_value());
	OO_CHECK(!parseUrl("not a url").has_value());
	OO_CHECK(!parseUrl("http://exa mple.com/").has_value());
	OO_CHECK(!parseUrl("http://127.0.0.1/a b").has_value());
	OO_CHECK(!parseUrl("http://example.com/\xC3\xA9").has_value());
	OO_CHECK(!parseUrl("http://example.com/{x}").has_value());
	// Schemes and shapes NSURLConnection could not fetch over HTTP.
	OO_CHECK(!parseUrl("ftp://127.0.0.1/ok").has_value());
	OO_CHECK(!parseUrl("mailto:someone@example.com").has_value());
	OO_CHECK(!parseUrl("http:///nohost").has_value());
	OO_CHECK(!parseUrl("http:example.com").has_value());
	OO_CHECK(!parseUrl("://x").has_value());
	OO_CHECK(!parseUrl("http://example.com:0/").has_value());
	OO_CHECK(!parseUrl("http://example.com:65536/").has_value());
	OO_CHECK(!parseUrl("http://example.com:8a/").has_value());
	OO_CHECK(!parseUrl("http://[::1/").has_value());
}

// --- downloads that need no server ------------------------------------------------------------------

OO_TEST(unparseable_url_fails_at_once)
{
	for (const char* url : {"", "not a url", "http://exa mple.com/", "ftp://127.0.0.1/ok", "http:///nohost"})
	{
		const Transcript t = get(url);
		OO_CHECK(t.failed);
		OO_CHECK(!t.finished);
		OO_CHECK_EQ(t.responses, 0);
		OO_CHECK(!t.error.empty());
		OO_CHECK(!t.eventAfterEnd);
	}
}

OO_TEST(file_url_delivers_the_file)
{
	std::error_code ec;
	const auto stamp = std::chrono::steady_clock::now().time_since_epoch().count();
	const oo::fs::Path dir = std::filesystem::temp_directory_path(ec) / ("oofnd-http-" + std::to_string(stamp));
	std::filesystem::create_directories(dir, ec);
	const oo::fs::Path file = dir / "manifest data.txt";
	const std::string body = bigBody();
	OO_CHECK(oo::fs::writeFile(file, oo::Data(body.data(), body.size())).has_value());

	std::string url = "file://";
	std::string path = oo::fs::utf8String(file);
	for (char& c : path)  if (c == '\\')  c = '/';
	if (!path.empty() && path.front() != '/')  url += "/";
	for (const char c : path)  url += (c == ' ') ? std::string("%20") : std::string(1, c);

	const Transcript t = get(url);
	OO_CHECK(t.finished);
	OO_CHECK(!t.failed);
	OO_CHECK_EQ(t.responses, 1);
	OO_CHECK_EQ(t.expected, static_cast<std::int64_t>(body.size()));
	OO_CHECK(t.body == body);
	OO_CHECK(!t.dataBeforeResponse);
	OO_CHECK(!t.eventAfterEnd);

	const Transcript missing = get(url + ".missing");
	OO_CHECK(missing.failed);
	OO_CHECK_EQ(missing.responses, 0);
	std::filesystem::remove_all(dir, ec);
}

// The OXZ manager writes what a download delivers through these (oofnd/FileSystem.hpp).
OO_TEST(download_file_sink)
{
	std::error_code ec;
	const auto stamp = std::chrono::steady_clock::now().time_since_epoch().count();
	const oo::fs::Path dir = std::filesystem::temp_directory_path(ec) / ("oofnd-http-sink-" + std::to_string(stamp));
	std::filesystem::create_directories(dir, ec);
	const oo::fs::Path file = dir / "download.tmp";
	OO_CHECK(oo::fs::writeFile(file, oo::Data::fromString("previous contents")).has_value());

	std::FILE* f = oo::fs::createFileForWriting(file);
	OO_CHECK(f != nullptr);
	OO_CHECK_EQ(oo::fs::fileSize(file).value_or(99), 0u);	// created empty over the old file
	OO_CHECK_EQ(std::fwrite("hello ", 1, 6, f), 6u);
	OO_CHECK_EQ(std::fwrite("world", 1, 5, f), 5u);
	OO_CHECK(oo::fs::synchronizeFile(f));
	OO_CHECK_EQ(oo::fs::fileSize(file).value_or(0), 11u);
	OO_CHECK_EQ(std::fclose(f), 0);
	OO_CHECK_EQ(oo::fs::readFile(file).value_or(oo::Data()).toString(), std::string("hello world"));

	OO_CHECK(!oo::fs::synchronizeFile(nullptr));
	OO_CHECK(oo::fs::createFileForWriting(dir / "missing-dir" / "x") == nullptr);
	std::filesystem::remove_all(dir, ec);
}

OO_TEST(cancel_before_taking_drops_everything)
{
	Download download("file:///nonexistent-oofnd-http-test/x", kUserAgent);
	download.cancel();
	OO_CHECK(download.cancelled());
	std::this_thread::sleep_for(std::chrono::milliseconds(50));
	OO_CHECK(!download.nextEvent().has_value());
	download.cancel();	// twice is harmless
}

#if defined(_WIN32)

// --- a loopback HTTP/1.1 server replaying the probe's exchanges ---------------------------------------

class Server
{
public:
	Server()
	{
		WSADATA wsa;
		WSAStartup(MAKEWORD(2, 2), &wsa);
		listener_ = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
		sockaddr_in addr = {};
		addr.sin_family = AF_INET;
		addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
		addr.sin_port = 0;
		bind(listener_, reinterpret_cast<sockaddr*>(&addr), sizeof addr);
		int length = sizeof addr;
		getsockname(listener_, reinterpret_cast<sockaddr*>(&addr), &length);
		port_ = ntohs(addr.sin_port);
		listen(listener_, 16);
		acceptor_ = std::thread([this]() { acceptLoop(); });
	}

	~Server()
	{
		stopping_ = true;
		closesocket(listener_);
		acceptor_.join();
		std::lock_guard<std::mutex> lock(mutex_);
		for (std::thread& t : connections_)  t.join();
		WSACleanup();
	}

	std::string url(const std::string& path) const
	{
		return "http://127.0.0.1:" + std::to_string(port_) + path;
	}

	// Released by the stalled response (see cancel_interrupts_a_stalled_body).
	std::atomic<bool> stopping_{false};

private:
	void acceptLoop()
	{
		for (;;)
		{
			SOCKET c = accept(listener_, nullptr, nullptr);
			if (c == INVALID_SOCKET)  return;
			std::lock_guard<std::mutex> lock(mutex_);
			connections_.emplace_back([this, c]() { serve(c); });
		}
	}

	static void sendAll(SOCKET c, const std::string& bytes)
	{
		size_t sent = 0;
		while (sent < bytes.size())
		{
			const int n = send(c, bytes.data() + sent, static_cast<int>(bytes.size() - sent), 0);
			if (n <= 0)  return;
			sent += static_cast<size_t>(n);
		}
	}

	static std::string reply(const std::string& status, const std::vector<std::string>& headers, const std::string& body)
	{
		std::string out = "HTTP/1.1 " + status + "\r\n";
		for (const std::string& h : headers)  out += h + "\r\n";
		return out + "\r\n" + body;
	}

	static std::string length(const std::string& body)
	{
		return "Content-Length: " + std::to_string(body.size());
	}

	void serve(SOCKET c)
	{
		std::string buffer;
		char chunk[4096];
		for (;;)
		{
			size_t end;
			while ((end = buffer.find("\r\n\r\n")) == std::string::npos)
			{
				const int n = recv(c, chunk, sizeof chunk, 0);
				if (n <= 0)
				{
					closesocket(c);
					return;
				}
				buffer.append(chunk, static_cast<size_t>(n));
			}
			const std::string head = buffer.substr(0, end + 4);
			buffer.erase(0, end + 4);
			const size_t sp = head.find(' ');
			const std::string path = head.substr(sp + 1, head.find(' ', sp + 1) - sp - 1);
			if (!respond(c, path, head))
			{
				closesocket(c);
				return;
			}
		}
	}

	// false: close the connection after this response.
	bool respond(SOCKET c, const std::string& path, const std::string& head)
	{
		if (path == "/ok")
		{
			sendAll(c, reply("200 OK", {"Content-Length: 5", "Set-Cookie: a=b"}, "hello"));
		}
		else if (path == "/headers")
		{
			sendAll(c, reply("200 OK", {length(head)}, head));
		}
		else if (path == "/404")
		{
			sendAll(c, reply("404 Not Found", {"Content-Length: 9"}, "not found"));
		}
		else if (path == "/500")
		{
			sendAll(c, reply("500 Internal", {"Content-Length: 3"}, "bad"));
		}
		else if (path == "/redir")
		{
			sendAll(c, reply("302 Found", {"Location: /ok", "Content-Length: 0"}, ""));
		}
		else if (path == "/redirabs")
		{
			sendAll(c, reply("301 Moved", {"Location: " + url("/headers"), "Set-Cookie: session=1", "Content-Length: 0"}, ""));
		}
		else if (path == "/chunked")
		{
			sendAll(c, reply("200 OK", {"Transfer-Encoding: chunked"}, "5\r\nhello\r\n6\r\n world\r\n0\r\n\r\n"));
		}
		else if (path == "/nolen")
		{
			sendAll(c, reply("200 OK", {"Connection: close"}, "no length body"));
			return false;
		}
		else if (path == "/gzip")
		{
			const std::string z("\x1f\x8b\x08\x00\x00\x00\x00\x00\x02\xff\xab\x02\x00\x00\xff\xff", 16);
			sendAll(c, reply("200 OK", {length(z), "Content-Encoding: gzip"}, z));
		}
		else if (path == "/big")
		{
			const std::string body = bigBody();
			sendAll(c, reply("200 OK", {length(body)}, body));
		}
		else if (path == "/empty")
		{
			sendAll(c, reply("200 OK", {"Content-Length: 0"}, ""));
		}
		else if (path == "/204")
		{
			sendAll(c, reply("204 No Content", {}, ""));
		}
		else if (path == "/drop")
		{
			sendAll(c, reply("200 OK", {"Content-Length: 100"}, "partial"));
			return false;
		}
		else if (path == "/stall")
		{
			sendAll(c, reply("200 OK", {"Content-Length: 100"}, "part"));
			const auto limit = std::chrono::steady_clock::now() + std::chrono::seconds(20);
			while (!stopping_ && std::chrono::steady_clock::now() < limit)
			{
				std::this_thread::sleep_for(std::chrono::milliseconds(5));
			}
			return false;
		}
		else
		{
			sendAll(c, reply("404 Not Found", {"Content-Length: 0"}, ""));
		}
		return true;
	}

	SOCKET listener_ = INVALID_SOCKET;
	unsigned short port_ = 0;
	std::thread acceptor_;
	std::mutex mutex_;
	std::vector<std::thread> connections_;
};

Server& server()
{
	static Server instance;
	return instance;
}

void expectComplete(const Transcript& t, int status, std::int64_t expected, const std::string& body)
{
	OO_CHECK(t.finished);
	OO_CHECK(!t.failed);
	OO_CHECK_EQ(t.responses, 1);
	OO_CHECK_EQ(t.status, status);
	OO_CHECK_EQ(t.expected, expected);
	OO_CHECK(t.body == body);
	OO_CHECK(!t.dataBeforeResponse);
	OO_CHECK(!t.eventAfterEnd);
}

OO_TEST(ok_delivers_response_data_finish)
{
	expectComplete(get(server().url("/ok")), 200, 5, "hello");
	expectComplete(get(server().url("/ok#frag")), 200, 5, "hello");
	expectComplete(get(server().url("/big")), 200, 300000, bigBody());
	expectComplete(get(server().url("/empty")), 200, 0, "");
}

OO_TEST(error_statuses_are_responses_with_a_body)
{
	expectComplete(get(server().url("/404")), 404, 9, "not found");
	expectComplete(get(server().url("/500")), 500, 3, "bad");
	expectComplete(get(server().url("/ok?x=1")), 404, 0, "");
	expectComplete(get(server().url("")), 404, 0, "");
}

OO_TEST(unknown_length_is_minus_one)
{
	expectComplete(get(server().url("/chunked")), 200, -1, "hello world");
	expectComplete(get(server().url("/nolen")), 200, -1, "no length body");
	expectComplete(get(server().url("/204")), 204, -1, "");
}

OO_TEST(body_is_delivered_as_sent)
{
	const std::string z("\x1f\x8b\x08\x00\x00\x00\x00\x00\x02\xff\xab\x02\x00\x00\xff\xff", 16);
	expectComplete(get(server().url("/gzip")), 200, 16, z);
}

OO_TEST(a_body_cut_short_finishes_with_what_arrived)
{
	expectComplete(get(server().url("/drop")), 200, 100, "partial");
}

OO_TEST(request_carries_user_agent_and_host_only)
{
	const Transcript t = get(server().url("/headers"));
	OO_CHECK(t.finished);
	OO_CHECK_EQ(t.status, 200);
	OO_CHECK(t.body.rfind("GET /headers HTTP/1.1\r\n", 0) == 0);
	OO_CHECK(t.body.find("\r\nUser-Agent: Oolite/1.93\r\n") != std::string::npos);
	OO_CHECK(t.body.find("\r\nHost: 127.0.0.1:") != std::string::npos);
	OO_CHECK(t.body.find("Accept-Encoding") == std::string::npos);
	OO_CHECK(t.body.find("Cookie") == std::string::npos);
	OO_CHECK(t.body.find("Authorization") == std::string::npos);

	const std::string withUser = "http://user:pw@" + server().url("/headers").substr(7);
	const Transcript u = get(withUser);
	OO_CHECK(u.finished);
	OO_CHECK(u.body.find("Authorization") == std::string::npos);
}

OO_TEST(redirects_deliver_only_the_final_response)
{
	// Absolute: as NSURLConnection. The redirect's Set-Cookie is not sent back.
	const Transcript a = get(server().url("/redirabs"));
	OO_CHECK(a.finished);
	OO_CHECK_EQ(a.responses, 1);
	OO_CHECK_EQ(a.status, 200);
	OO_CHECK(a.body.rfind("GET /headers HTTP/1.1\r\n", 0) == 0);
	OO_CHECK(a.body.find("Cookie") == std::string::npos);
	// Relative: NSURLConnection never called back (proposed ADR-0044); it is followed.
	expectComplete(get(server().url("/redir")), 200, 5, "hello");
}

OO_TEST(refused_connection_fails)
{
	// Port 1 on loopback: nothing listens there.
	const Transcript t = get("http://127.0.0.1:1/x");
	OO_CHECK(t.failed);
	OO_CHECK(!t.finished);
	OO_CHECK_EQ(t.responses, 0);
	OO_CHECK(t.error.find("12029") != std::string::npos);
	OO_CHECK(!t.eventAfterEnd);
}

OO_TEST(cancel_interrupts_a_stalled_body)
{
	server();
	server().stopping_ = false;
	const auto start = std::chrono::steady_clock::now();
	{
		Download download(server().url("/stall"), kUserAgent);
		// Wait for the response and the first bytes.
		std::string body;
		bool response = false;
		const auto limit = std::chrono::steady_clock::now() + std::chrono::seconds(10);
		while (body.size() < 4 && std::chrono::steady_clock::now() < limit)
		{
			std::optional<Event> event = download.nextEvent();
			if (!event.has_value())
			{
				std::this_thread::sleep_for(std::chrono::milliseconds(2));
				continue;
			}
			if (event->kind == Event::Kind::response)  response = true;
			if (event->kind == Event::Kind::data)  body += event->bytes;
		}
		OO_CHECK(response);
		OO_CHECK_EQ(body, std::string("part"));
		download.cancel();
		OO_CHECK(!download.nextEvent().has_value());
		std::this_thread::sleep_for(std::chrono::milliseconds(50));
		OO_CHECK(!download.nextEvent().has_value());
	}	// the destructor joins the worker the cancel interrupted
	OO_CHECK(std::chrono::steady_clock::now() - start < std::chrono::seconds(10));
	server().stopping_ = true;
}

#endif // _WIN32

} // namespace

OO_TEST_MAIN()
