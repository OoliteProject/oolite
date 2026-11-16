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

#import "OODebuggerInterface.h"
#import "OOFoundation.h"
#import "oofnd/objc/OOObject.h"

#include "oofnd/StdLib.hpp"

@class OODebugMonitor;

typedef enum {
    kOOTCPClientNotConnected,
    kOOTCPClientStartedConnectionStage1,
    kOOTCPClientStartedConnectionStage2,
    kOOTCPClientConnected,
    kOOTCPClientConnectionRefused,
    kOOTCPClientDisconnected
} OOTCPClientConnectionStatus;

/*	The connection is one non-blocking TCP socket (bead oo-3rb.14, proposed ADR-0041), where it was a
        Foundation host lookup and an input/output stream pair on the run loop. _inStatus/_outStatus
        keep the two streams' status numbers (Foundation's stream-status values), which the
        connection-failure messages print; _pendingErrorCode is an error event the run loop would
        still have delivered to the stream delegate.
*/
@interface OODebugTCPConsoleClient : OOObject <OODebuggerInterface> {
@private
    std::optional<std::string> _hostName; // was the host object; nullopt when closed
    uintptr_t _socket; // SOCKET / file descriptor; all ones when closed
    int _inStatus,
        _outStatus;
    int _inError,
        _outError;
    int _pendingErrorCode;
    BOOL _errorEventPending;
    OOTCPClientConnectionStatus _status;
    OODebugMonitor* _monitor;
    struct OOTCPStreamDecoder* _decoder;
}

- (id)initWithAddress:(const std::optional<std::string>&)address // Pass nullopt for localhost
                 port:(uint16_t)port; // Pass 0 for default port

@end

/*	The frame loop's side of the console socket: what the run loop did for the console's
        streams. OODebugTCPConsoleIsWaitingForInput() is YES while a console socket can deliver
        something (input, end of stream or an error); OODebugTCPConsoleServiceInput() waits up to
        timeout seconds (< 0: no limit) for that, then handles what arrived, as one run-loop wait
        did.
*/
BOOL OODebugTCPConsoleIsWaitingForInput(void);
void OODebugTCPConsoleServiceInput(double timeout);
