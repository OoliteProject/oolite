/*

OODebugTCPConsoleClient.h


Oolite Debug OXP

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

#import "OOCocoa.h"
#import "OODebuggerInterface.h"

@class OODebugMonitor;


typedef enum
{
	kOOTCPClientNotConnected,
	kOOTCPClientStartedConnectionStage1,
	kOOTCPClientStartedConnectionStage2,
	kOOTCPClientConnected,
	kOOTCPClientConnectionRefused,
	kOOTCPClientDisconnected
} OOTCPClientConnectionStatus;


@interface OODebugTCPConsoleClient: NSObject <OODebuggerInterface>
{
@private
	NSHost						*_host;
	NSOutputStream				*_outStream;
	NSInputStream				*_inStream;
	OOTCPClientConnectionStatus	_status;
	OODebugMonitor				*_monitor;
	struct OOTCPStreamDecoder	*_decoder;
}

- (id) initWithAddress:(NSString *)address	// Pass nil for localhost
				  port:(uint16_t)port;		// Pass 0 for default port

@end


#if OOLITE_MAC_OS_X

/*
	Declare conformance to NSStreamDelegate, which is a formal protocol starting
	in the Mac OS X 10.6 SDK. At the time of writing, it's still an informal
	protocol in GNUstep trunk. -- Ahruman 2012-01-07
*/
@interface OODebugTCPConsoleClient (NSStreamDelegate) <NSStreamDelegate>
@end

#endif
