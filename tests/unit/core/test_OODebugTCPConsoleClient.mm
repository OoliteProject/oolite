/*	test_OODebugTCPConsoleClient.mm
	Unit tests for the TCP debug console client (src/Core/Debug/OODebugTCPConsoleClient.h): bead
	oo-4nhg, converted after the Debug module's pattern seam oo-kq7 (proposed ADR-0056, amendment
	oo-kq7). The client is the debugger the golden harness drives the game through.

	The client opens a non-blocking socket to the console, sends "Request Connection", and then
	speaks the console protocol (OODebugTCPConsoleProtocol.h): property-list packets, each behind
	a four-byte big-endian length. These tests play the console on a loopback socket of their own
	and pin what the client sends and what it does with what it is sent: approval, refusal, the
	console output and configuration packets, ping, commands and configuration changes passed to
	the monitor, closing from either end, and a connection nobody answers. The frame loop's side
	(OODebugTCPConsoleIsWaitingForInput / OODebugTCPConsoleServiceInput) delivers the console's
	packets, as it does in the game. These expectations were written against the Objective-C class
	and run on it first.

	The debug monitor would bring the JavaScript engine and the game into the link, so it is this
	file's stand-in (proposed ADR-0056, amendment oo-z1s4 item 4): it records the commands and
	configuration values it is given and answers configuration values from a table. Since the
	conversion (commit 3dc0fde89 ran these tests on the Objective-C class, against an Objective-C
	monitor) the stand-in is the C++ monitor's members that the client calls, and the tests drive
	the client through its facade, which is its forwarding test; cxxClientAndItsFacade adds the C++
	API and the facade's contract (one facade per client, nil for null).
	Run: bash tools/check-core-tests.sh test_OODebugTCPConsoleClient
*/

#import "OODebugTCPConsoleClient.h"
#import "OODebugMonitor.h"
// The protocol's names as UTF-8 literals, as the client reads them.
#define OOALSTR(x) "" x
#import "OODebugTCPConsoleProtocol.h"

#include "oofnd/PListParsing.hpp"
#include "oofnd/PListWriting.hpp"
#include "oo_test.hpp"

#include <winsock2.h>
#include <ws2tcpip.h>

#include <map>
#include <string>
#include <utility>
#include <vector>


// MARK: The debug monitor's stand-in --------------------------------------------------------------

namespace {

struct MonitorRecord
{
	std::vector<std::string>						commands;
	std::vector<std::pair<std::string, oo::PList>>	configurationSets;
	std::map<std::string, oo::PList>				configuration;
};

MonitorRecord sMonitor;

}	// namespace


// The C++ monitor's members that the client calls, and the facade crossing its forwarders make.
cxx::OODebugMonitor *cxx::OODebugMonitor::sharedDebugMonitor()
{
	static cxx::OODebugMonitor *monitor = nullptr;
	if (monitor == nullptr)  monitor = oo::makeRef<cxx::OODebugMonitor>().leakRef();
	return monitor;
}


bool cxx::OODebugMonitor::TCPIgnoresDroppedPackets()
{
	return false;
}


void cxx::OODebugMonitor::performJSConsoleCommand(const std::string &command)
{
	sMonitor.commands.push_back(command);
}


oo::PList cxx::OODebugMonitor::configurationValueForKey(const std::string &key)
{
	auto found = sMonitor.configuration.find(key);
	return (found != sMonitor.configuration.end()) ? found->second : oo::PList();
}


void cxx::OODebugMonitor::setConfigurationValue(const oo::PList &value, const std::string &key)
{
	sMonitor.configurationSets.emplace_back(key, value);
}


namespace {

// What the debug monitor hands its debugger: here, an object that stands for its facade.
OODebugMonitor *Monitor()
{
	static OOObject *facade = nil;
	if (facade == nil)  facade = [[OOObject alloc] init];
	return (OODebugMonitor *)facade;
}

}	// namespace


cxx::OODebugMonitor *oo::ToCxx(OODebugMonitor *monitor)
{
	return (monitor == Monitor()) ? cxx::OODebugMonitor::sharedDebugMonitor() : nullptr;
}


// MARK: The console's end ------------------------------------------------------------------------

namespace {

void StartWinsock()
{
	static bool started = false;
	if (!started)
	{
		WSADATA data;
		started = (WSAStartup(MAKEWORD(2, 2), &data) == 0);
	}
}


// A listening loopback socket on a free port.
SOCKET Listen(uint16_t *outPort)
{
	StartWinsock();
	SOCKET s = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
	sockaddr_in address = {};
	address.sin_family = AF_INET;
	address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
	address.sin_port = 0;
	bind(s, reinterpret_cast<sockaddr *>(&address), sizeof address);
	listen(s, 4);
	int size = sizeof address;
	getsockname(s, reinterpret_cast<sockaddr *>(&address), &size);
	*outPort = ntohs(address.sin_port);
	return s;
}


SOCKET Accept(SOCKET listener)
{
	SOCKET s = accept(listener, nullptr, nullptr);
	DWORD timeout = 5000;	// a missing packet fails the check instead of hanging the test
	setsockopt(s, SOL_SOCKET, SO_RCVTIMEO, reinterpret_cast<const char *>(&timeout), sizeof timeout);
	return s;
}


bool ReceiveAll(SOCKET s, uint8_t *buffer, size_t length)
{
	while (length > 0)
	{
		int received = recv(s, reinterpret_cast<char *>(buffer), static_cast<int>(length), 0);
		if (received <= 0)  return false;
		buffer += received;
		length -= static_cast<size_t>(received);
	}
	return true;
}


// The next packet from the client, parsed; null if none arrives.
oo::PList ReadPacket(SOCKET s)
{
	uint8_t header[4];
	if (!ReceiveAll(s, header, sizeof header))  return oo::PList();
	const size_t length = (size_t(header[0]) << 24) | (size_t(header[1]) << 16) | (size_t(header[2]) << 8) | size_t(header[3]);
	std::string body(length, '\0');
	if (!ReceiveAll(s, reinterpret_cast<uint8_t *>(body.data()), length))  return oo::PList();
	oo::Expected<oo::PList, oo::PListError> parsed = oo::parsePropertyList(body);
	return parsed ? std::move(*parsed) : oo::PList();
}


// Sends a packet of the given type (and parameters) to the client, and lets the client's frame
// loop handle it.
void SendPacket(SOCKET s, const std::string &type, oo::PList::Dict parameters = {})
{
	parameters["packet type"] = oo::PList(type);
	const oo::Expected<oo::Data, oo::PListError> data = oo::writeXMLPList(oo::PList(std::move(parameters)));
	const uint32_t length = htonl(static_cast<uint32_t>(data->length()));
	send(s, reinterpret_cast<const char *>(&length), sizeof length, 0);
	send(s, reinterpret_cast<const char *>(data->bytes()), static_cast<int>(data->length()), 0);
	OODebugTCPConsoleServiceInput(2.0);
}


std::string TypeOf(const oo::PList &packet)
{
	const oo::PList *value = packet.find("packet type");
	const std::string *type = (value != nullptr) ? value->getIf<std::string>() : nullptr;
	return (type != nullptr) ? *type : std::string();
}


const oo::PList *Value(const oo::PList &packet, const std::string &key)
{
	return packet.find(key);
}


// The same property list, compared as XML: integers read back from XML are unsigned when
// non-negative, which oo::PList's == tells apart.
bool Same(const oo::PList *value, const oo::PList &expected)
{
	if (value == nullptr)  return false;
	const oo::Expected<oo::Data, oo::PListError> a = oo::writeXMLPList(*value), b = oo::writeXMLPList(expected);
	return a && b && a->stringView() == b->stringView();
}


// A client connected to a console socket of this test's: its request read.
struct Session
{
	SOCKET listener = INVALID_SOCKET;
	SOCKET console = INVALID_SOCKET;
	OODebugTCPConsoleClient *client = nil;
	oo::PList request;

	Session()
	{
		uint16_t port = 0;
		listener = Listen(&port);
		client = [[OODebugTCPConsoleClient alloc] initWithAddress:std::string("127.0.0.1") port:port];
		if (client != nil)
		{
			console = Accept(listener);
			request = ReadPacket(console);
		}
	}

	~Session()
	{
		[client release];
		if (console != INVALID_SOCKET)  closesocket(console);
		closesocket(listener);
	}
};

}	// namespace


// MARK: Tests -------------------------------------------------------------------------------------

// Connecting sends "Request Connection" with the protocol version; the monitor can then connect,
// and the console's approval is read.
OO_TEST(connectsAndRequestsTheConnection)
{
	@autoreleasepool
	{
		Session session;
		OO_CHECK(session.client != nil);
		OO_CHECK(TypeOf(session.request) == "Request Connection");
		const oo::PList *version = Value(session.request, "protocol version");
		OO_CHECK(Same(version, oo::PList(static_cast<std::int64_t>(kOOTCPProtocolVersion_1_1_0))));

		std::optional<std::string> message;
		OO_CHECK([session.client connectDebugMonitor:Monitor() errorMessage:&message]);
		OO_CHECK(!message.has_value());
		OO_CHECK(OODebugTCPConsoleIsWaitingForInput());

		SendPacket(session.console, "Approve Connection", { { "console identity", oo::PList(std::string("Test Console")) } });
		OO_CHECK(OODebugTCPConsoleIsWaitingForInput());
	}
}


// What the monitor sends becomes the console's packets.
OO_TEST(sendsTheMonitorsOutput)
{
	@autoreleasepool
	{
		Session session;
		OO_CHECK([session.client connectDebugMonitor:Monitor() errorMessage:NULL]);
		SendPacket(session.console, "Approve Connection");

		[session.client debugMonitor:Monitor() jsConsoleOutput:"hello" colorKey:std::nullopt emphasisRange:NSMakeRange(1, 2)];
		oo::PList packet = ReadPacket(session.console);
		OO_CHECK(TypeOf(packet) == "Console Output");
		OO_CHECK(Same(Value(packet, "message"), oo::PList(std::string("hello"))));
		OO_CHECK(Same(Value(packet, "color key"), oo::PList(std::string("general"))));
		OO_CHECK(Same(Value(packet, "emphasis ranges"), oo::PList(oo::PList::Array{ oo::PList(1), oo::PList(2) })));

		[session.client debugMonitor:Monitor() jsConsoleOutput:"oops" colorKey:std::string("error") emphasisRange:NSMakeRange(0, 0)];
		packet = ReadPacket(session.console);
		OO_CHECK(Same(Value(packet, "color key"), oo::PList(std::string("error"))));
		OO_CHECK(Value(packet, "emphasis ranges") == nullptr);

		[session.client debugMonitorClearConsole:Monitor()];
		packet = ReadPacket(session.console);
		OO_CHECK(TypeOf(packet) == "Clear Console" && packet.getIf<oo::PList::Dict>()->size() == 1);

		[session.client debugMonitorShowConsole:Monitor()];
		OO_CHECK(TypeOf(ReadPacket(session.console)) == "Show Console");

		oo::PList::Dict configuration;
		configuration["font-size"] = oo::PList(12);
		[session.client debugMonitor:Monitor() noteConfiguration:oo::PList(configuration)];
		packet = ReadPacket(session.console);
		OO_CHECK(TypeOf(packet) == "Note Configuration");
		OO_CHECK(Same(Value(packet, "configuration"), oo::PList(configuration)));

		[session.client debugMonitor:Monitor() noteChangedConfigrationValue:oo::PList(14) forKey:"font-size"];
		packet = ReadPacket(session.console);
		OO_CHECK(TypeOf(packet) == "Note Configuration");
		configuration["font-size"] = oo::PList(14);
		OO_CHECK(Same(Value(packet, "configuration"), oo::PList(configuration)));

		[session.client debugMonitor:Monitor() noteChangedConfigrationValue:oo::PList() forKey:"font-size"];
		packet = ReadPacket(session.console);
		OO_CHECK(TypeOf(packet) == "Note Configuration");
		OO_CHECK(Value(packet, "configuration") == nullptr);
		OO_CHECK(Same(Value(packet, "removed configuration keys"), oo::PList(oo::PList::Array{ oo::PList(std::string("font-size")) })));
	}
}


// What the console sends: ping is answered, commands and configuration go to the monitor, a
// configuration request is answered from the monitor, and an unknown packet is ignored.
OO_TEST(handlesTheConsolesPackets)
{
	@autoreleasepool
	{
		Session session;
		OO_CHECK([session.client connectDebugMonitor:Monitor() errorMessage:NULL]);
		SendPacket(session.console, "Approve Connection");

		SendPacket(session.console, "Ping", { { "message", oo::PList(std::string("p1")) } });
		oo::PList packet = ReadPacket(session.console);
		OO_CHECK(TypeOf(packet) == "Pong");
		OO_CHECK(Same(Value(packet, "message"), oo::PList(std::string("p1"))));

		SendPacket(session.console, "Ping");
		packet = ReadPacket(session.console);
		OO_CHECK(TypeOf(packet) == "Pong" && packet.getIf<oo::PList::Dict>()->size() == 1);

		sMonitor = MonitorRecord();
		SendPacket(session.console, "Perform Command", { { "message", oo::PList(std::string("1 + 1")) } });
		OO_CHECK(sMonitor.commands == std::vector<std::string>{ "1 + 1" });
		SendPacket(session.console, "Perform Command", { { "message", oo::PList(42) } });	// a number's string value
		OO_CHECK(sMonitor.commands.size() == 2 && sMonitor.commands[1] == "42");
		SendPacket(session.console, "Perform Command");
		OO_CHECK(sMonitor.commands.size() == 2);

		// Every entry of the configuration is set, the removed-keys entry included; the removed
		// keys are then cleared.
		oo::PList::Dict change;
		change["a"] = oo::PList(1);
		change["removed configuration keys"] = oo::PList(oo::PList::Array{ oo::PList(std::string("b")), oo::PList(3) });
		SendPacket(session.console, "Note Configuration Change", { { "configuration", oo::PList(change) } });
		OO_CHECK(sMonitor.configurationSets.size() == 3);
		if (sMonitor.configurationSets.size() == 3)
		{
			OO_CHECK(sMonitor.configurationSets[0].first == "a" && Same(&sMonitor.configurationSets[0].second, oo::PList(1)));
			OO_CHECK(sMonitor.configurationSets[1].first == "removed configuration keys");
			OO_CHECK(sMonitor.configurationSets[2].first == "b" && sMonitor.configurationSets[2].second.isNull());
		}
		SendPacket(session.console, "Note Configuration Change", { { "configuration", oo::PList(std::string("not a dictionary")) } });
		OO_CHECK(sMonitor.configurationSets.size() == 3);

		sMonitor.configuration["font-size"] = oo::PList(12);
		SendPacket(session.console, "Request Configuration Value", { { "configuration key", oo::PList(std::string("font-size")) } });
		packet = ReadPacket(session.console);
		OO_CHECK(TypeOf(packet) == "Note Configuration");
		oo::PList::Dict expected;
		expected["font-size"] = oo::PList(12);
		OO_CHECK(Same(Value(packet, "configuration"), oo::PList(expected)));

		SendPacket(session.console, "Request Configuration Value", { { "configuration key", oo::PList(std::string("missing")) } });
		packet = ReadPacket(session.console);
		OO_CHECK(Same(Value(packet, "removed configuration keys"), oo::PList(oo::PList::Array{ oo::PList(std::string("missing")) })));

		SendPacket(session.console, "No Such Packet");
		SendPacket(session.console, "Ping", { { "message", oo::PList(std::string("p2")) } });
		packet = ReadPacket(session.console);
		OO_CHECK(TypeOf(packet) == "Pong" && Same(Value(packet, "message"), oo::PList(std::string("p2"))));
	}
}


// The monitor disconnects: a close packet with the message, then the socket closes; the client
// cannot be connected again.
OO_TEST(disconnectsFromTheConsole)
{
	@autoreleasepool
	{
		Session session;
		OO_CHECK([session.client connectDebugMonitor:Monitor() errorMessage:NULL]);
		SendPacket(session.console, "Approve Connection");

		[session.client disconnectDebugMonitor:Monitor() message:std::string("bye")];
		oo::PList packet = ReadPacket(session.console);
		OO_CHECK(TypeOf(packet) == "Close Connection");
		OO_CHECK(Same(Value(packet, "message"), oo::PList(std::string("bye"))));
		char byte = 0;
		OO_CHECK(recv(session.console, &byte, 1, 0) == 0);
		OO_CHECK(!OODebugTCPConsoleIsWaitingForInput());

		std::optional<std::string> message;
		OO_CHECK(![session.client connectDebugMonitor:Monitor() errorMessage:&message]);
		OO_CHECK(message == std::optional<std::string>("Cannot reconnect after disconnecting."));

		// Disconnecting again sends nothing: the socket is already closed.
		[session.client disconnectDebugMonitor:Monitor() message:std::nullopt];
	}
}


// No message: the close packet has no message key.
OO_TEST(disconnectsWithoutAMessage)
{
	@autoreleasepool
	{
		Session session;
		[session.client disconnectDebugMonitor:Monitor() message:std::nullopt];
		oo::PList packet = ReadPacket(session.console);
		OO_CHECK(TypeOf(packet) == "Close Connection" && packet.getIf<oo::PList::Dict>()->size() == 1);
	}
}


// The console refuses the connection: the monitor cannot connect.
OO_TEST(theConsoleRefuses)
{
	@autoreleasepool
	{
		Session session;
		SendPacket(session.console, "Reject Connection", { { "message", oo::PList(std::string("no thanks")) } });
		OO_CHECK(!OODebugTCPConsoleIsWaitingForInput());
		char byte = 0;
		OO_CHECK(recv(session.console, &byte, 1, 0) == 0);

		std::optional<std::string> message;
		OO_CHECK(![session.client connectDebugMonitor:Monitor() errorMessage:&message]);
		OO_CHECK(message == std::optional<std::string>("Connection refused."));
	}
}


// The console closes the connection: the client closes its socket and cannot be connected again.
OO_TEST(theConsoleCloses)
{
	@autoreleasepool
	{
		Session session;
		OO_CHECK([session.client connectDebugMonitor:Monitor() errorMessage:NULL]);
		SendPacket(session.console, "Approve Connection");
		SendPacket(session.console, "Close Connection");
		OO_CHECK(!OODebugTCPConsoleIsWaitingForInput());

		std::optional<std::string> message;
		OO_CHECK(![session.client connectDebugMonitor:Monitor() errorMessage:&message]);
		OO_CHECK(message == std::optional<std::string>("Cannot reconnect after disconnecting."));

		// Nothing more is sent.
		[session.client debugMonitorShowConsole:Monitor()];
		OO_CHECK(!OODebugTCPConsoleIsWaitingForInput());
	}
}


// The console hangs up: the client's input is at its end and it waits for nothing more.
OO_TEST(theConsoleHangsUp)
{
	@autoreleasepool
	{
		Session session;
		OO_CHECK(OODebugTCPConsoleIsWaitingForInput());
		closesocket(session.console);
		session.console = INVALID_SOCKET;
		OODebugTCPConsoleServiceInput(2.0);
		OO_CHECK(!OODebugTCPConsoleIsWaitingForInput());
	}
}


// Nobody answers: the connection fails and the initialiser answers nil.
OO_TEST(nobodyAnswers)
{
	@autoreleasepool
	{
		uint16_t port = 0;
		SOCKET listener = Listen(&port);
		closesocket(listener);

		OODebugTCPConsoleClient *client = [[OODebugTCPConsoleClient alloc] initWithAddress:std::string("127.0.0.1") port:port];
		OO_CHECK(client == nil);
		OO_CHECK(!OODebugTCPConsoleIsWaitingForInput());
	}
}


// The C++ client and its facade: a client made by the facade's initialiser is that facade's, the
// crossing keeps one facade per client, and null and nil cross as each other.
OO_TEST(cxxClientAndItsFacade)
{
	@autoreleasepool
	{
		Session session;
		cxx::OODebugTCPConsoleClient *client = oo::ToCxx(session.client);
		OO_CHECK(client != nullptr);
		OO_CHECK(oo::ToObjC(client) == session.client);
		OO_CHECK(oo::ToCxx((OODebugTCPConsoleClient *)nil) == nullptr);
		OO_CHECK(oo::ToObjC((cxx::OODebugTCPConsoleClient *)nullptr) == nil);

		OO_CHECK(client->connectDebugMonitor(cxx::OODebugMonitor::sharedDebugMonitor(), nullptr));
		client->debugMonitorShowConsole(cxx::OODebugMonitor::sharedDebugMonitor());
		OO_CHECK(TypeOf(ReadPacket(session.console)) == "Show Console");
	}

	@autoreleasepool
	{
		uint16_t port = 0;
		SOCKET listener = Listen(&port);
		oo::Ref<cxx::OODebugTCPConsoleClient> client = cxx::OODebugTCPConsoleClient::clientWithAddress(std::string("127.0.0.1"), port);
		OO_CHECK(client.get() != nullptr);
		SOCKET console = Accept(listener);
		OO_CHECK(TypeOf(ReadPacket(console)) == "Request Connection");

		OODebugTCPConsoleClient *facade = oo::ToObjC(client.get());
		OO_CHECK(facade != nil && oo::ToObjC(client.get()) == facade && oo::ToCxx(facade) == client.get());
		[facade debugMonitorClearConsole:Monitor()];
		OO_CHECK(TypeOf(ReadPacket(console)) == "Clear Console");

		client = oo::Ref<cxx::OODebugTCPConsoleClient>();	// the facade still holds it
		[facade debugMonitorShowConsole:Monitor()];
		OO_CHECK(TypeOf(ReadPacket(console)) == "Show Console");
		closesocket(console);
		closesocket(listener);
	}

	uint16_t port = 0;
	SOCKET listener = Listen(&port);
	closesocket(listener);
	OO_CHECK(cxx::OODebugTCPConsoleClient::clientWithAddress(std::string("127.0.0.1"), port).get() == nullptr);
}


OO_TEST_MAIN()
