/*

OODebugTCPConsoleClient.m


Oolite Debug Support

Copyright (C) 2009-2013 Jens Ayton and contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

*/

#ifdef OO_DEBUG_MONITOR_ENABLED

#include "OODebugTCPConsoleClient.h"
// The protocol's names as UTF-8 literals (the header would make them Objective-C string objects).
#define OOALSTR(x) "" x
#include "OODebugMonitor.h"
#include "OODebugTCPConsoleProtocol.h"
#include "OOFunctionAttributes.h"
#include "oofnd/FileSystem.hpp"
#include "oofnd/Log.hpp"
#include "oofnd/PListParsing.hpp"
#include "oofnd/ResourcePaths.hpp"
#include "oofnd/StdLib.hpp"
#include <stdint.h>

#if OOLITE_WINDOWS
#include <winsock2.h>
#include <ws2tcpip.h>
#else
#include <arpa/inet.h> // For htonl
#include <errno.h>
#include <fcntl.h>
#include <netdb.h>
#include <string.h>
#include <sys/select.h>
#include <sys/socket.h>
#include <unistd.h>
#endif
#include <math.h>
#include <thread>

#include "OOTCPStreamDecoder.h"
#include "oofnd/PListWriting.hpp"
#include "oofnd/String.hpp"

#ifdef OO_LOG_DEBUG_PROTOCOL_PACKETS
static void LogSendPacket(const oo::PList& packet);
#else
#define LogSendPacket(packet) \
    do {                      \
    } while (0)
#endif

namespace {

OOINLINE bool StatusIsSendable(OOTCPClientConnectionStatus status)
{
    return status == kOOTCPClientStartedConnectionStage1 || status == kOOTCPClientStartedConnectionStage2 || status == kOOTCPClientConnected;
}

} // namespace

/*	The socket (bead oo-3rb.14, proposed ADR-0041). What the Foundation streams did, measured
        against gnustep-base 1.31 on Windows, and kept here:

        * The host is looked up by name, IPv4 only; an unknown name logs GNUstep's own
          "Host '...' not found" line and gives no connection.
        * The socket is non-blocking. Opening starts the connect; both streams are then
          "opening" (1), "open" (2) once it completes, and on failure the input stream reports the
          error first ("error", 7), with the system's text for the error code as its description.
        * A read that would block leaves the input stream "reading" (3). A read of the peer's close
          puts the input stream "at end" (5) and returns 0; a connection reset or aborted puts both
          at end. Writes after the peer's close go on (the first usually succeeds); a send the
          system aborts puts both streams at end and returns 0, and later writes return 0; a
          connection reset on send puts the output stream in "error" (7), returns -1 and raises no
          event. Any other read error is "error" (7) on the input stream and an error event.
        * Events reach the handlers only through a wait (the frame loop's, the connect wait or the
          send-retry waits), as stream events reached the delegate only from the run loop.
*/
namespace {

enum : uint8_t {
    kStreamStatusNotOpen = 0,
    kStreamStatusOpening = 1,
    kStreamStatusOpen = 2,
    kStreamStatusReading = 3,
    kStreamStatusAtEnd = 5,
    kStreamStatusError = 7
};

const uintptr_t kNoSocket = ~(uintptr_t)0;

#if OOLITE_WINDOWS
typedef SOCKET OOSocket;
typedef int OOSocketLength;
int LastSocketError(void) { return WSAGetLastError(); }
bool ErrorIsWouldBlock(int error) { return error == WSAEWOULDBLOCK; }
bool ErrorIsConnectInProgress(int error) { return error == WSAEWOULDBLOCK; }
bool ErrorIsAbortOnSend(int error) { return error == WSAECONNABORTED; }
bool ErrorIsConnectionGone(int error) { return error == WSAECONNRESET || error == WSAECONNABORTED; }
void CloseSocket(OOSocket s) { closesocket(s); }
bool SetNonBlocking(OOSocket s)
{
    u_long on = 1;
    return ioctlsocket(s, FIONBIO, &on) == 0;
}
constexpr int kSendFlags = 0;

// The error's system text, as GNUstep's error object gave it (FormatMessage, trailing line break
// kept), as UTF-8; nullopt (was nil) when the system has none.
std::optional<std::string> SocketErrorDescription(int error)
{
    wchar_t* buffer = NULL;
    DWORD length = FormatMessageW(FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS,
        NULL, (DWORD)error, MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT), (LPWSTR)&buffer, 0, NULL);
    std::optional<std::string> result;
    if (length != 0 && buffer != NULL) {
        result = oo::utf16ToUtf8(std::u16string(reinterpret_cast<const char16_t*>(buffer), length));
    }
    if (buffer != NULL)
        LocalFree(buffer);
    return result;
}
#else
typedef int OOSocket;
typedef socklen_t OOSocketLength;
int LastSocketError(void) { return errno; }
bool ErrorIsWouldBlock(int error) { return error == EWOULDBLOCK || error == EAGAIN; }
bool ErrorIsConnectInProgress(int error) { return error == EINPROGRESS; }
bool ErrorIsAbortOnSend(int error) { return error == EPIPE || error == ECONNABORTED; }
bool ErrorIsConnectionGone(int error) { return error == ECONNRESET || error == ECONNABORTED; }
void CloseSocket(OOSocket s) { close(s); }
bool SetNonBlocking(OOSocket s)
{
    int flags = fcntl(s, F_GETFL, 0);
    return flags != -1 && fcntl(s, F_SETFL, flags | O_NONBLOCK) != -1;
}
#ifdef MSG_NOSIGNAL
constexpr int kSendFlags = MSG_NOSIGNAL;
#else
constexpr int kSendFlags = 0;
#endif

std::optional<std::string> SocketErrorDescription(int error)
{
    return std::string(strerror(error));
}
#endif

// Every client with an open socket, for the frame loop (not retained: a client removes itself when it closes).
std::vector<OODebugTCPConsoleClient*> sLiveClients;

}

namespace {

// One of OODebugTCPConsoleProtocol.h's name constants (UTF-8 literals here, see OOALSTR above).
std::string ProtocolName(const char* name)
{
    return std::string(name);
}

// PListView get<> of a string: the packet's value for <key> if it is a string, or a number's
// -stringValue; nullopt (was nil) for anything else, a missing key or a packet that is no
// dictionary. <key> is one of OODebugTCPConsoleProtocol.h's constants.
std::optional<std::string> PacketString(const oo::PList& packet, const char* key)
{
    const std::string name = ProtocolName(key);
    const oo::PList* value = packet.find(name);
    if (value == nullptr || !(value->isString() || value->isNumber()))
        return std::nullopt;
    return packet.get<std::string>(name);
}

}

namespace {

// Info-gnustep.plist string (CFBundleVersion / CFBundleName as the Override category used to expose).
std::optional<std::string> OoliteInfoString(std::string_view key)
{
    const oo::fs::Path plistPath = oo::ResourcePaths::current().builtInResourcesDirectory() / "Info-gnustep.plist";
    oo::PList info;
    if (const oo::fs::Result<oo::Data> bytes = oo::fs::readFile(plistPath); bytes && !bytes->empty()) {
        if (oo::Expected<oo::PList, oo::PListError> parsed = oo::parsePropertyList(bytes->stringView());
            parsed && parsed->isDict())
            info = std::move(*parsed);
    }
    if (const oo::PList* v = info.find(key); v != nullptr && v->isString())
        return *v->getIf<std::string>();
    return std::nullopt;
}

} // namespace

// -init (initWithAddress:nullopt port:0) stays in the facade.
oo::Ref<OODebugTCPConsoleClient> OODebugTCPConsoleClient::clientWithAddress(const std::optional<std::string>& address, uint16_t port)
{
    oo::Ref<OODebugTCPConsoleClient> client = oo::adopt(new OODebugTCPConsoleClient);
    if (!client->initWithAddress(address, port))
        return oo::Ref<OODebugTCPConsoleClient>();
    return client;
}

bool OODebugTCPConsoleClient::initWithAddress(const std::optional<std::string>& hostAddress, uint16_t port)
{
    bool OK = false;

    const std::string address = hostAddress.value_or("127.0.0.1");
    if (port == 0)
        port = kOOTCPConsolePort;

    // (The object is constructed: [super init] cannot fail.)
    {
        _socket = kNoSocket;

        if (openSocketToHost(address, port)) {
            // Need to wait for the streams to reach open status before we can send packets
            // TODO: Might be neater to use the handleEvent callback to flag this.. - Micha 20090425
            // This was a three-second run-loop wait, but a run-loop pass whose limit has passed
            // still returns YES, so it waited until the connection opened or failed (measured:
            // 21 s for an address that never answers). Waiting on the socket does the same.
            while (_hostName.has_value() && (_inStatus < kStreamStatusOpen || _outStatus < kStreamStatusOpen)) {
                OODebugTCPConsoleServiceInput(-1.0);
            }

            _decoder = OOTCPStreamDecoderCreate(DecoderPacket, DecoderError, NULL, this);
        }

        if (_decoder != NULL) {
            OK = true;
            _status = kOOTCPClientStartedConnectionStage1;

            // Attempt to connect: the protocol version, and the game's version (omitted when there is
            // none: +dictionaryWithObjectsAndKeys: stopped at the nil).
            oo::PList::Dict parameters;
            parameters[ProtocolName(kOOTCPProtocolVersion)] = oo::PList(static_cast<std::int64_t>(kOOTCPProtocolVersion_1_1_0));
            const std::optional<std::string> versionStr = OoliteInfoString("CFBundleVersion");
            const oo::PList version = versionStr ? oo::PList(*versionStr) : oo::PList();
            if (!version.isNull())
                parameters[ProtocolName(kOOTCPOoliteVersion)] = version;
            sendPacket(ProtocolName(kOOTCPPacket_RequestConnection),
                oo::PList(std::move(parameters)));

            if (_status == kOOTCPClientStartedConnectionStage1)
                _status = kOOTCPClientStartedConnectionStage2;
            else
                OK = false; // Connection failed.
        }

        if (!OK) {
            OO_LOG("debugTCP.connect.failed", "Failed to connect to debug console at address {}:{}.", address, port);
            return OK; // self was released and nil answered: the factory drops the object
        }
    }

    return OK;
}

OODebugTCPConsoleClient::~OODebugTCPConsoleClient()
{
    if (StatusIsSendable(_status)) {
        disconnectFromServerWithMessage(std::string("TCP console bridge unexpectedly released while active."));
    }
    /*	-dealloc then told a connected monitor (_monitor set) to disconnect it. That never did
            anything: the monitor retains its debugger (this client's facade) while _monitor is set, so
            the client could not be released then, and the monitor ignores a debugger that is not its
            own. Not translated (proposed ADR-0056, amendment oo-kq7 item 3).
    */

    closeConnection();

    OOTCPStreamDecoderDestroy(_decoder);
    _decoder = NULL;
}

bool OODebugTCPConsoleClient::connectDebugMonitor(OODebugMonitor* debugMonitor,
    std::optional<std::string>* message)
{
    if (_status == kOOTCPClientConnectionRefused) {
        if (message != NULL)
            *message = "Connection refused.";
        return false;
    }
    if (_status == kOOTCPClientDisconnected) {
        if (message != NULL)
            *message = "Cannot reconnect after disconnecting.";
        return false;
    }

    _monitor = debugMonitor;

    return true;
}

void OODebugTCPConsoleClient::disconnectDebugMonitor(OODebugMonitor* /*debugMonitor*/,
    const std::optional<std::string>& message)
{
    disconnectFromServerWithMessage(message);
    _monitor = nullptr;
}

void OODebugTCPConsoleClient::debugMonitor(OODebugMonitor* /*debugMonitor*/,
    const std::string& output,
    const std::optional<std::string>& colorKey,
    NSRange emphasisRange)
{
    oo::PList::Dict parameters;
    parameters[ProtocolName(kOOTCPMessage)] = oo::PList(output);
    parameters[ProtocolName(kOOTCPColorKey)] = colorKey.has_value() ? oo::PList(*colorKey) : oo::PList(std::string("general"));
    if (emphasisRange.length != 0) {
        parameters[ProtocolName(kOOTCPEmphasisRanges)] = oo::PList(oo::PList::Array {
            oo::PList(static_cast<std::int64_t>(emphasisRange.location)),
            oo::PList(static_cast<std::int64_t>(emphasisRange.length)) });
    }

    sendPacket(ProtocolName(kOOTCPPacket_ConsoleOutput),
        oo::PList(std::move(parameters)));
}

std::string OODebugTCPConsoleClient::description() const
{
    // What "%@" printed for the facade (no description components).
    return oo::str::format("<OODebugTCPConsoleClient %s>", oo::str::pointerDescription(this).c_str());
}

void OODebugTCPConsoleClient::debugMonitorClearConsole(OODebugMonitor* /*debugMonitor*/)
{
    sendPacket(ProtocolName(kOOTCPPacket_ClearConsole),
        oo::PList());
}

void OODebugTCPConsoleClient::debugMonitorShowConsole(OODebugMonitor* /*debugMonitor*/)
{
    sendPacket(ProtocolName(kOOTCPPacket_ShowConsole),
        oo::PList());
}

void OODebugTCPConsoleClient::debugMonitor(OODebugMonitor* /*debugMonitor*/,
    const oo::PList& configuration)
{
    sendPacket(ProtocolName(kOOTCPPacket_NoteConfiguration),
        configuration,
        ProtocolName(kOOTCPConfiguration));
}

void OODebugTCPConsoleClient::debugMonitor(OODebugMonitor* /*debugMonitor*/,
    const oo::PList& newValue,
    const std::string& key)
{
    if (newValue) {
        oo::PList::Dict change;
        change[key] = newValue;
        sendPacket(ProtocolName(kOOTCPPacket_NoteConfiguration),
            oo::PList(std::move(change)),
            ProtocolName(kOOTCPConfiguration));
    } else {
        sendPacket(ProtocolName(kOOTCPPacket_NoteConfiguration),
            oo::PList(oo::PList::Array { oo::PList(key) }),
            ProtocolName(kOOTCPRemovedConfigurationKeys));
    }
}

void OODebugTCPConsoleClient::closeConnection()
{
    if (_socket != kNoSocket) {
        CloseSocket((OOSocket)_socket);
        _socket = kNoSocket;
        sLiveClients.erase(std::remove(sLiveClients.begin(), sLiveClients.end(), this), sLiveClients.end());
    }
    _inStatus = _outStatus = kStreamStatusNotOpen;
    _inError = _outError = 0;
    _errorEventPending = false;

    _hostName = std::nullopt;
}

bool OODebugTCPConsoleClient::openSocketToHost(const std::string& address, uint16_t port)
{
    struct addrinfo hints, *found = NULL;
    struct sockaddr_in host;
    OOSocket s;

#if OOLITE_WINDOWS
    // gnustep-base started Winsock for its own sockets; nothing else in the game does.
    static bool winsockStarted = false;
    if (!winsockStarted) {
        WSADATA data;
        winsockStarted = (WSAStartup(MAKEWORD(2, 2), &data) == 0);
    }
#endif

    memset(&hints, 0, sizeof hints);
    hints.ai_family = AF_INET;
    hints.ai_socktype = SOCK_STREAM;
    if (getaddrinfo(address.c_str(), NULL, &hints, &found) != 0 || found == NULL) {
        // Same text as gnustep-base's unknown-host message, via OO_LOG.
        OO_LOG("unclassified", "Host '{}' not found - perhaps the hostname is wrong or networking is not set up on your machine", address);
        return false;
    }
    memcpy(&host, found->ai_addr, sizeof host);
    freeaddrinfo(found);
    host.sin_port = htons(port);

    s = ::socket(AF_INET, SOCK_STREAM, IPPROTO_TCP); // the C function, not socket() below
    if ((uintptr_t)s == kNoSocket)
        return false;
    if (!SetNonBlocking(s)) {
        CloseSocket(s);
        return false;
    }

    _hostName = address;
    _socket = (uintptr_t)s;
    sLiveClients.push_back(this);
    _inStatus = _outStatus = kStreamStatusOpening;

    if (connect(s, (struct sockaddr*)&host, sizeof host) == 0) {
        _inStatus = _outStatus = kStreamStatusOpen;
    } else {
        int error = LastSocketError();
        if (!ErrorIsConnectInProgress(error)) {
            _inStatus = kStreamStatusError;
            _inError = _outError = error;
            _pendingErrorCode = error;
            _errorEventPending = true;
        }
    }

    return true;
}

NSInteger OODebugTCPConsoleClient::receive(uint8_t* buffer, size_t length)
{
    if (_socket == kNoSocket)
        return 0;
    if (_inStatus == kStreamStatusAtEnd)
        return 0;
    if (_inStatus != kStreamStatusOpen && _inStatus != kStreamStatusReading)
        return -1;

    int received = (int)recv((OOSocket)_socket, (char*)buffer, (int)length, 0);
    if (received > 0) {
        _inStatus = kStreamStatusOpen;
        return received;
    }
    if (received == 0) {
        _inStatus = kStreamStatusAtEnd;
        return 0;
    }

    int error = LastSocketError();
    if (ErrorIsWouldBlock(error)) {
        _inStatus = kStreamStatusReading;
    } else if (ErrorIsConnectionGone(error)) {
        _inStatus = _outStatus = kStreamStatusAtEnd;
        return 0;
    } else {
        _inStatus = kStreamStatusError;
        _inError = error;
        _pendingErrorCode = error;
        _errorEventPending = true;
    }
    return -1;
}

bool OODebugTCPConsoleClient::isWaitingForInput()
{
    if (_errorEventPending)
        return true;
    if (_socket == kNoSocket)
        return false;
    return _inStatus == kStreamStatusOpening || _outStatus == kStreamStatusOpening || _inStatus == kStreamStatusOpen || _inStatus == kStreamStatusReading;
}

bool OODebugTCPConsoleClient::hasPendingErrorEvent()
{
    return _errorEventPending;
}

uintptr_t OODebugTCPConsoleClient::socket()
{
    return _socket;
}

void OODebugTCPConsoleClient::addToWaitSets(fd_set* readSet, fd_set* writeSet, fd_set* exceptSet)
{
    if (_socket == kNoSocket)
        return;
    OOSocket s = (OOSocket)_socket;
    if (_inStatus == kStreamStatusOpening || _outStatus == kStreamStatusOpening) {
        // Connecting: done when writable; failed when exceptional (Windows) or writable with an error.
        FD_SET(s, writeSet);
        FD_SET(s, exceptSet);
    } else if (_inStatus == kStreamStatusOpen || _inStatus == kStreamStatusReading) {
        FD_SET(s, readSet);
    }
}

void OODebugTCPConsoleClient::handleWaitResultRead(bool readable, bool writable, bool exceptional)
{
    if (_inStatus == kStreamStatusOpening || _outStatus == kStreamStatusOpening) {
        if (!writable && !exceptional)
            return;

        int error = 0;
        OOSocketLength size = sizeof error;
        if (getsockopt((OOSocket)_socket, SOL_SOCKET, SO_ERROR, (char*)&error, &size) != 0)
            error = LastSocketError();
        if (error == 0 && !exceptional) {
            // The streams' open-completed and space-available events: the delegate ignored them.
            _inStatus = _outStatus = kStreamStatusOpen;
        } else {
            // The input stream's error event comes first; handling it closes both.
            _inStatus = kStreamStatusError;
            _inError = _outError = error;
            _pendingErrorCode = error;
            handleErrorEvent();
        }
        return;
    }

    if (readable) {
        // The bytes-available event (end of stream was an event the delegate ignored).
        if (_status <= kOOTCPClientConnected)
            readData();
        if (_errorEventPending)
            handleErrorEvent();
    }
}

// The delegate's error branch, for the event the failing stream raised.
void OODebugTCPConsoleClient::handleErrorEvent()
{
    _errorEventPending = false;
    if (_status > kOOTCPClientConnected)
        return;
    breakConnectionWithStreamError(_pendingErrorCode);
}

// A nested run of the run loop for the given time, as far as the console is concerned: its
// socket's events as they arrive.
void OODebugTCPConsoleClient::serviceSocketFor(double seconds)
{
    const std::chrono::steady_clock::time_point deadline = std::chrono::steady_clock::now() + std::chrono::duration_cast<std::chrono::steady_clock::duration>(std::chrono::duration<double>(seconds));
    for (;;) {
        const double remaining = std::chrono::duration<double>(deadline - std::chrono::steady_clock::now()).count();
        if (remaining <= 0.0)
            break;
        if (OODebugTCPConsoleIsWaitingForInput()) {
            OODebugTCPConsoleServiceInput(remaining);
        } else {
            // Nothing to wait on: a plain wait of the same whole milliseconds, rounded up.
            // (Not std::this_thread: on this toolchain it sleeps in 15.6 ms steps whatever the
            // timer resolution, measured.)
#if OOLITE_WINDOWS
            Sleep((DWORD)ceil(remaining * 1000.0));
#else
            std::this_thread::sleep_for(std::chrono::milliseconds((long long)ceil(remaining * 1000.0)));
#endif
        }
    }
}

bool OODebugTCPConsoleClient::sendBytes(const void* bytes, size_t count)
{
    if (bytes == NULL || count == 0)
        return true;
    if (!StatusIsSendable(_status) || _socket == kNoSocket)
        return false;

    do {
        NSInteger written;
        if (_outStatus == kStreamStatusAtEnd)
            written = 0;
        else if (_outStatus != kStreamStatusOpen)
            written = -1;
        else {
            written = send((OOSocket)_socket, (const char*)bytes, (int)count, kSendFlags);
            if (written < 0) {
                int error = LastSocketError();
                if (ErrorIsAbortOnSend(error)) {
                    _inStatus = _outStatus = kStreamStatusAtEnd;
                    written = 0;
                } else if (!ErrorIsWouldBlock(error)) {
                    _outStatus = kStreamStatusError;
                    _outError = error;
                }
            }
        }
        if (written < 1)
            return false;

        count -= written;
        bytes = (const uint8_t*)bytes + written;
    } while (count > 0);

    return true;
}

void OODebugTCPConsoleClient::sendDictionary(const oo::PList& dictionary)
{
    size_t count;
    const uint8_t* bytes = NULL;
    uint32_t header;
    bool sentOK = true;

    if (dictionary.isNull() || !StatusIsSendable(_status))
        return;

    /*	GNUstep's XML property-list serialisation, byte for byte (oo::writeXMLPList, ADR-0043 item
            15). GNUstep reported no error for anything the console is sent (an object that is not
            property-list data is written as its description, probed); writeXMLPList fails only on a
            null list, which is not sent. The log keeps GNUstep's fallback text.
    */
    const oo::Expected<oo::Data, oo::PListError> data = oo::writeXMLPList(dictionary);
    if (!data) {
        OO_LOG("debugTCP.conversionFailure", "Could not convert dictionary to data for transmission to debug console: {}", "unknown error.");
        return;
    }

    LogSendPacket(dictionary);

    count = data->length();
    if (count == 0)
        return;
    header = htonl(count);

    bytes = data->bytes();

    /*	In testing, all bad stream errors were caused by the python console
            rejecting headers. Made the protocol a bit more fault tolerant.
            -- Kaks 2012.03.24
    */
    if (!sendBytes(&header, sizeof header)) {
        OO_LOG("debugTCP.send.warning", "{}", "Error sending packet header, retrying.");
        // wait 8 milliseconds, resend the header
        serviceSocketFor(.008);
        if (!sendBytes(&header, sizeof header)) {
            // debugTCP.send.warning: Error sending packet header, retrying one more time.
            // wait 16 milliseconds, try to resend the header one last time!
            serviceSocketFor(.016);
            if (!sendBytes(&header, sizeof header)) {
                sentOK = false;
            }
        }
    }

    if (sentOK && !sendBytes(bytes, count)) {
        OO_LOG("debugTCP.send.warning", "{}", "Error sending packet body, retrying.");
        // wait 8 milliseconds, try again.
        serviceSocketFor(.008);
        if (!sendBytes(bytes, count)) {
            sentOK = false;
        }
    }

    if (!sentOK) {
        OO_LOG("debugTCP.send.error", "The following packet could not be sent: {}", oo::DescriptionOf(dictionary));
        if (!OODebugMonitor::sharedDebugMonitor()->TCPIgnoresDroppedPackets()) {
            breakConnectionWithStreamError(_socket != kNoSocket ? _outError : 0);
        }
    }
}

void OODebugTCPConsoleClient::sendPacket(const std::string& packetType,
    const oo::PList& parameters)
{
    // A copy of the parameters with the packet type set (was dictionary copy with one added entry);
    // no parameters: the type alone.
    oo::PList::Dict dict;
    if (const oo::PList::Dict* given = parameters.getIf<oo::PList::Dict>())
        dict = *given;
    dict[ProtocolName(kOOTCPPacketType)] = oo::PList(packetType);

    sendDictionary(oo::PList(std::move(dict)));
}

void OODebugTCPConsoleClient::sendPacket(const std::string& packetType,
    const oo::PList& value,
    const std::string& paramKey)
{
    // A null value or an empty key gives the type-only packet, as +dictionaryWithObjectsAndKeys:
    // did by stopping at the nil.
    oo::PList::Dict dict;
    dict[ProtocolName(kOOTCPPacketType)] = oo::PList(packetType);
    if (!value.isNull() && !paramKey.empty())
        dict[paramKey] = value;

    sendDictionary(oo::PList(std::move(dict)));
}

void OODebugTCPConsoleClient::readData()
{
    enum { kBufferSize = 16 << 10 };

    uint8_t buffer[kBufferSize];
    NSInteger length;

    length = receive(buffer, kBufferSize);
    while (length > 0) {
        // The bytes go to the decoder in a data handle (OOTCPStreamDecoderAbstractionLayer), which
        // is released once the decoder has taken them, as the no-copy data object was.
        auto data = OOALDataCreateMutable((size_t)length);
        OOALMutableDataAppendBytes(data, buffer, (size_t)length);
        OOTCPStreamDecoderReceiveData(_decoder, data);
        OOALRelease(data);
        length = receive(buffer, kBufferSize);
    }
}

void OODebugTCPConsoleClient::dispatchPacket(const oo::PList& packet, const std::string& packetType)
{
    if (packet.isNull())
        return;

    // The packet type names are OODebugTCPConsoleProtocol.h's constants, read as C++ strings.
#define PACKET_CASE(x)                                     \
    else if (packetType == ProtocolName(kOOTCPPacket_##x)) \
    {                                                      \
        handle##x##Packet(packet);                         \
    }

    if (0) { }
    PACKET_CASE(ApproveConnection)
    PACKET_CASE(RejectConnection)
    PACKET_CASE(CloseConnection)
    PACKET_CASE(NoteConfigurationChange)
    PACKET_CASE(PerformCommand)
    PACKET_CASE(RequestConfigurationValue)
    PACKET_CASE(Ping)
    PACKET_CASE(Pong)
    else
    {
        OO_LOG("debugTCP.protocolError.unknownPacketType", "Unhandled packet type {}.", packetType);
    }
}

void OODebugTCPConsoleClient::handleApproveConnectionPacket(const oo::PList& packet)
{
    if (_status == kOOTCPClientStartedConnectionStage2) {
        _status = kOOTCPClientConnected;

        // Build "Connected..." message with two optional parts, console identity and host name.
        std::string connectedMessage = "Connected to debug console";

        const std::optional<std::string> consoleIdentity = PacketString(packet, kOOTCPConsoleIdentity);
        if (consoleIdentity.has_value())
            connectedMessage += " \"" + *consoleIdentity + "\"";

        const std::string hostName = _hostName.value_or(std::string());
        if (hostName.length() != 0 && hostName != "localhost" && hostName != "127.0.0.1" && hostName != "::1") {
            connectedMessage += " at " + hostName;
        }

        OO_LOG("debugTCP.connected", "{}.", connectedMessage);
    } else {
        OO_LOG("debugTCP.protocolError.outOfOrder", "Got {} packet from debug console in wrong context.", kOOTCPPacket_ApproveConnection);
    }
}

void OODebugTCPConsoleClient::handleRejectConnectionPacket(const oo::PList& packet)
{
    if (_status == kOOTCPClientStartedConnectionStage2) {
        _status = kOOTCPClientConnectionRefused;
    } else {
        OO_LOG("debugTCP.protocolError.outOfOrder", "Got {} packet from debug console in wrong context.", kOOTCPPacket_RejectConnection);
    }

    breakConnectionWithMessage(PacketString(packet, kOOTCPMessage).value_or("Console refused connection."));
}

void OODebugTCPConsoleClient::handleCloseConnectionPacket(const oo::PList& packet)
{
    if (!StatusIsSendable(_status)) {
        OO_LOG("debugTCP.protocolError.outOfOrder", "Got {} packet from debug console in wrong context.", kOOTCPPacket_CloseConnection);
    }
    breakConnectionWithMessage(PacketString(packet, kOOTCPMessage).value_or("Console closed connection."));
}

void OODebugTCPConsoleClient::handleNoteConfigurationChangePacket(const oo::PList& packet)
{
    if (_monitor == nullptr)
        return;

    const oo::PList* configuration = packet.find(ProtocolName(kOOTCPConfiguration));
    if (configuration != nullptr && !configuration->isDict())
        configuration = nullptr;
    if (configuration != nullptr) {
        for (const auto& entry : *configuration->getIf<oo::PList::Dict>()) {
            _monitor->setConfigurationValue(entry.second, entry.first);
        }
    }

    // The removed keys are read from the configuration, as the old code read them.
    const oo::PList* removed = (configuration != nullptr) ? configuration->find(ProtocolName(kOOTCPRemovedConfigurationKeys)) : nullptr;
    if (removed != nullptr && removed->isArray()) {
        for (const oo::PList& key : *removed->getIf<oo::PList::Array>()) {
            const std::string* keyStr = key.getIf<std::string>();
            if (keyStr != nullptr)
                _monitor->setConfigurationValue(oo::PList(), *keyStr);
        }
    }
}

void OODebugTCPConsoleClient::handlePerformCommandPacket(const oo::PList& packet)
{
    const std::optional<std::string> message = PacketString(packet, kOOTCPMessage);
    if (message.has_value() && _monitor != nullptr)
        _monitor->performJSConsoleCommand(*message); // no monitor: nothing, as nil did
}

void OODebugTCPConsoleClient::handleRequestConfigurationValuePacket(const oo::PList& packet)
{
    const std::optional<std::string> key = PacketString(packet, kOOTCPConfigurationKey);
    if (key.has_value()) {
        const oo::PList value = (_monitor != nullptr) ? _monitor->configurationValueForKey(*key) : oo::PList(); // no monitor: null, as nil gave
        debugMonitor(_monitor,
            value,
            *key);
    }
}

void OODebugTCPConsoleClient::handlePingPacket(const oo::PList& packet)
{
    const oo::PList* message = packet.find(ProtocolName(kOOTCPMessage));
    sendPacket(ProtocolName(kOOTCPPacket_Pong),
        (message != nullptr) ? *message : oo::PList(),
        ProtocolName(kOOTCPMessage));
}

void OODebugTCPConsoleClient::handlePongPacket(const oo::PList& /*packet*/)
{
    // Do nothing; we don't currently send pings.
}

void OODebugTCPConsoleClient::disconnectFromServerWithMessage(const std::optional<std::string>& message)
{
    if (StatusIsSendable(_status)) {
        // nullopt: a close packet without a message key, as nil gave.
        sendPacket(ProtocolName(kOOTCPPacket_CloseConnection),
            message.has_value() ? oo::PList(*message) : oo::PList(),
            ProtocolName(kOOTCPMessage));
    }
    closeConnection();

    _status = kOOTCPClientDisconnected;
}

void OODebugTCPConsoleClient::breakConnectionWithMessage(const std::string& message)
{
    closeConnection();

    if (_status != kOOTCPClientConnectionRefused)
        _status = kOOTCPClientDisconnected;

    if (message.length() > 0) {
        OO_LOG("debugTCP.disconnect", "No connection to debug console: \"{}\"", message);
    } else {
        OO_LOG("debugTCP.disconnect", "{}", "Debug console not connected.");
    }

#if 0
	// Disconnecting causes crashiness for reasons I don't understand, and isn't very important anyway.
	_monitor->disconnectDebugger(this, message);
	_monitor = nullptr;
#endif
}

// error: the failing stream's error code; 0 for none (a closed stream, or one at its end).
void OODebugTCPConsoleClient::breakConnectionWithStreamError(int error)
{
    std::optional<std::string> errorDesc;

    if (error != 0)
        errorDesc = SocketErrorDescription(error);
    if (!errorDesc.has_value())
        errorDesc = "bad stream.";
    breakConnectionWithMessage(oo::str::format(
        "Connection to debug console failed: '%s' (outStream status: %zu, inStream status: %zu).",
        errorDesc->c_str(), (size_t)_outStatus, (size_t)_inStatus));
}

bool OODebugTCPConsoleIsWaitingForInput(void)
{
    for (OODebugTCPConsoleClient* client : sLiveClients) {
        if (client->isWaitingForInput())
            return true;
    }
    return false;
}

void OODebugTCPConsoleServiceInput(double timeout)
{
    fd_set readSet, writeSet, exceptSet;
    struct timeval limit, *limitPtr = NULL;
    int highest = -1;

    // An error event already raised is delivered without waiting.
    for (OODebugTCPConsoleClient* client : std::vector<OODebugTCPConsoleClient*>(sLiveClients)) {
        if (client->hasPendingErrorEvent()) {
            client->handleErrorEvent();
            return;
        }
    }

    FD_ZERO(&readSet);
    FD_ZERO(&writeSet);
    FD_ZERO(&exceptSet);
    for (OODebugTCPConsoleClient* client : sLiveClients) {
        if (client->isWaitingForInput()) {
            client->addToWaitSets(&readSet, &writeSet, &exceptSet);
            if ((int)client->socket() > highest)
                highest = (int)client->socket();
        }
    }
    if (highest < 0)
        return;

    if (timeout >= 0.0) {
        // Whole milliseconds, rounded up, as the run loop waited (measured).
        const long long millis = (long long)ceil(timeout * 1000.0);
        limit.tv_sec = (long)(millis / 1000);
        limit.tv_usec = (long)(millis % 1000) * 1000;
        limitPtr = &limit;
    }
    if (select(highest + 1, &readSet, &writeSet, &exceptSet, limitPtr) <= 0)
        return;

    for (OODebugTCPConsoleClient* client : std::vector<OODebugTCPConsoleClient*>(sLiveClients)) {
        if (client->socket() == kNoSocket)
            continue;
        OOSocket s = (OOSocket)client->socket();
        bool readable = FD_ISSET(s, &readSet) != 0;
        bool writable = FD_ISSET(s, &writeSet) != 0;
        bool exceptional = FD_ISSET(s, &exceptSet) != 0;
        if (readable || writable || exceptional) {
            // One client's events per wait: handling them can close (and release) clients.
            client->handleWaitResultRead(readable, writable, exceptional);
            return;
        }
    }
}

void OODebugTCPConsoleClient::DecoderPacket(void* cbInfo, OOALObjectRef packetType, OOALObjectRef packet)
{
    // The decoder's handles hold property lists (OOTCPStreamDecoderAbstractionLayer, bead oo-x3xy).
    // A type that is not a string was nil, and no packet was dispatched.
    const std::string* type = OOALObjectPList(packetType).getIf<std::string>();
    if (type == nullptr)
        return;
    static_cast<OODebugTCPConsoleClient*>(cbInfo)->dispatchPacket(OOALObjectPList(packet), *type);
}

void OODebugTCPConsoleClient::DecoderError(void* cbInfo, OOALObjectRef errorDesc)
{
    // A description that is not a string was nil: no message ("Debug console not connected.").
    const std::string* description = OOALObjectPList(errorDesc).getIf<std::string>();
    static_cast<OODebugTCPConsoleClient*>(cbInfo)->breakConnectionWithMessage((description != nullptr) ? *description : std::string());
}

#ifdef OO_LOG_DEBUG_PROTOCOL_PACKETS
void LogOOTCPStreamDecoderPacket(OOALObjectRef packetHandle)
{
    // GNUstep's XML property-list serialisation, byte for byte (ADR-0043 item 15).
    const oo::Expected<oo::Data, oo::PListError> data = oo::writeXMLPList(OOALObjectPList(packetHandle));
    const std::string xml = data ? std::string(data->stringView()) : std::string();
    OO_LOG("debugTCP.receive", "Received packet:\n{}", xml);
}

static void LogSendPacket(const oo::PList& packet)
{
    const oo::Expected<oo::Data, oo::PListError> data = oo::writeXMLPList(packet);
    const std::string xml = data ? std::string(data->stringView()) : std::string();
    OO_LOG("debugTCP.send", "Sent packet:\n{}", xml);
}
#endif

#endif /* OO_DEBUG_MONITOR_ENABLED */
