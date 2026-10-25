/*

OODebugTCPConsoleClient.h


Oolite Debug Support

Copyright (C) 2007-2013 Jens Ayton

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

#pragma once

#include "OOCocoa.h"
#include "oofnd/objc/OOObject.h"
#include "OODebuggerInterface.h"
#include "OOTCPStreamDecoderAbstractionLayer.h"

#include "oofnd/StdLib.hpp"
#include "oofnd/PList.hpp"
#include "oofnd/Ref.hpp"

#if OOLITE_WINDOWS
struct fd_set;		// winsock2.h's, which the .mm includes
#else
#include <sys/select.h>
#endif

struct OOTCPStreamDecoder;


typedef enum
{
	kOOTCPClientNotConnected,
	kOOTCPClientStartedConnectionStage1,
	kOOTCPClientStartedConnectionStage2,
	kOOTCPClientConnected,
	kOOTCPClientConnectionRefused,
	kOOTCPClientDisconnected
} OOTCPClientConnectionStatus;


/*	The frame loop's side of the console socket: what the run loop did for the console's
	streams. OODebugTCPConsoleIsWaitingForInput() is true while a console socket can deliver
	something (input, end of stream or an error); OODebugTCPConsoleServiceInput() waits up to
	timeout seconds (< 0: no limit) for that, then handles what arrived, as one run-loop wait
	did.
*/
bool OODebugTCPConsoleIsWaitingForInput(void);
void OODebugTCPConsoleServiceInput(double timeout);


class OODebugMonitor;


/*	The connection is one non-blocking TCP socket (bead oo-3rb.14, proposed ADR-0041), where it was a
	Foundation host lookup and an input/output stream pair on the run loop. _inStatus/_outStatus
	keep the two streams' status numbers (Foundation's stream-status values), which the
	connection-failure messages print; _pendingErrorCode is an error event the run loop would
	still have delivered to the stream delegate.

	The debug monitor reaches the client through the C++ OODebuggerInterface, which the client
	implements (bead oo-9ht.81 deleted its Objective-C facade and moved it out of namespace cxx).
*/
class OODebugTCPConsoleClient : public OODebuggerInterface
{
public:
	// [[OODebugTCPConsoleClient alloc] initWithAddress:port:]; null when the connection fails.
	static oo::Ref<OODebugTCPConsoleClient> clientWithAddress(const std::optional<std::string> &address,	// Pass nullopt for localhost
															  uint16_t port);		// Pass 0 for default port

	~OODebugTCPConsoleClient();

	// The debugger interface (OODebuggerInterface).
	bool connectDebugMonitor(OODebugMonitor *debugMonitor,
							 std::optional<std::string> *message) override;
	void disconnectDebugMonitor(OODebugMonitor *debugMonitor,
								const std::optional<std::string> &message) override;
	void debugMonitor(OODebugMonitor *debugMonitor,
					  const std::string &output,
					  const std::optional<std::string> &colorKey,
					  NSRange emphasisRange) override;
	void debugMonitorClearConsole(OODebugMonitor *debugMonitor) override;
	void debugMonitorShowConsole(OODebugMonitor *debugMonitor) override;
	void debugMonitor(OODebugMonitor *debugMonitor,
					  const oo::PList &configuration) override;
	void debugMonitor(OODebugMonitor *debugMonitor,
					  const oo::PList &newValue,
					  const std::string &key) override;
	std::string description() const override;	// <OODebugTCPConsoleClient 0x...>, as the facade's %@ printed

private:
	// The frame loop's functions below read the clients' sockets.
	friend bool ::OODebugTCPConsoleIsWaitingForInput(void);
	friend void ::OODebugTCPConsoleServiceInput(double timeout);

	OODebugTCPConsoleClient() = default;
	bool initWithAddress(const std::optional<std::string> &address, uint16_t port);

	// The decoder's callbacks; its string and dictionary handles are OOALObjectRef.
	static void DecoderPacket(void *cbInfo, OOALObjectRef packetType, OOALObjectRef packet);
	static void DecoderError(void *cbInfo, OOALObjectRef errorDesc);

	void closeConnection();

	bool sendBytes(const void *bytes, size_t count);
	void sendDictionary(const oo::PList &dictionary);

	// Packet type and parameter names are OODebugTCPConsoleProtocol.h's constants (ProtocolName()).
	void sendPacket(const std::string &packetType,
					const oo::PList &parameters);	// a dictionary; null: the type alone

	void sendPacket(const std::string &packetType,
					const oo::PList &value,
					const std::string &paramKey);	// a null value or empty key: the type alone

	bool openSocketToHost(const std::string &address, uint16_t port);
	NSInteger receive(uint8_t *buffer, size_t length);
	bool isWaitingForInput();
	bool hasPendingErrorEvent();
	uintptr_t socket();
	void addToWaitSets(fd_set *readSet, fd_set *writeSet, fd_set *exceptSet);
	void handleWaitResultRead(bool readable, bool writable, bool exceptional);
	void handleErrorEvent();
	void serviceSocketFor(double seconds);

	void readData();
	void dispatchPacket(const oo::PList &packet, const std::string &packetType);

	// Packets are property-list dictionaries (anything else answers no values).
	void handleApproveConnectionPacket(const oo::PList &packet);
	void handleRejectConnectionPacket(const oo::PList &packet);
	void handleCloseConnectionPacket(const oo::PList &packet);
	void handleNoteConfigurationChangePacket(const oo::PList &packet);
	void handlePerformCommandPacket(const oo::PList &packet);
	void handleRequestConfigurationValuePacket(const oo::PList &packet);
	void handlePingPacket(const oo::PList &packet);
	void handlePongPacket(const oo::PList &packet);

	void disconnectFromServerWithMessage(const std::optional<std::string> &message);	// nullopt: a close packet without a message
	void breakConnectionWithMessage(const std::string &message);
	void breakConnectionWithStreamError(int error);

	std::optional<std::string>	_hostName;			// was the host object; nullopt when closed
	uintptr_t					_socket = {};		// SOCKET / file descriptor; all ones when closed
	int							_inStatus = {},
								_outStatus = {};
	int							_inError = {},
								_outError = {};
	int							_pendingErrorCode = {};
	bool						_errorEventPending = {};
	OOTCPClientConnectionStatus	_status = {};
	OODebugMonitor			*_monitor = {};
	::OOTCPStreamDecoder		*_decoder = {};
};
