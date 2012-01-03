/*

OODebugTCPConsoleProtocol.h

Definitions used in Oolite remote debug console protocol.


Oolite Debug OXP

Copyright (C) 2007-2012 Jens Ayton

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


#ifndef OOALSTR
#ifdef __OBJC__
#import <Foundation/Foundation.h>
#define OOALSTR(x) @""x
#else	// C
#include <CoreFoundation/CoreFoundation.h>
#define OOALSTR(x) CFSTR(x)
#endif
#endif


enum
{
	kOOTCPConsolePort			= 0x002173	/* = 8563 */
};


/*	PROTOCOL OVERVIEW
	
	The basic unit of the protocol is property lists. Property lists originate
	with OpenStep and are thus defined in Cocoa and GNUstep, but they're also
	implemented in CoreFoundation (Mac OS X) and CFLite (cross-platform), with
	a C interface.
	
	The protocol uses a TCP stream in each direction. Each stream consists of
	a series of property lists in the Apple XML encoding. Each property list
	is framed in the simplest possible way: it is preceeded by an unsigned
	32-bit length, in network-endian order. Each length + property list
	combination is referred to as a packet.
	
	Every packet's property list must have a dictionary as its root element.
	The dictionary must contain a kOOTCPConsolePacketType key, whose value
	determines the meaning of the rest of the dictionary.
*/




/* *** Packet types *** */
/*	kOOTCPPacket_RequestConnection
	client --> server
	Message sent from client (Oolite) to server (console) to request a cosole
	connection.
	
	Required values:
		kOOTCPProtocolVersion
		kOOTCPOoliteVersion
	Expected responses:
		kOOTCPPacket_ApproveConnection
			OR
		kOOTCPPacket_RejectConnection
*/
#define kOOTCPPacket_RequestConnection		OOALSTR("Request Connection")

/*	kOOTCPPacket_ApproveConnection
	client <-- server
	Message sent in response to kOOTCPPacket_RequestConnection if connection is
	established successfully.
	
	Optional values:
		kOOTCPConsoleIdentity
*/
#define kOOTCPPacket_ApproveConnection		OOALSTR("Approve Connection")

/*	kOOTCPPacket_RejectConnection
	client <-- server
	Message sent in response to kOOTCPPacket_RequestConnection if connection is
	not established successfully. After this message is sent, the connection
	is closed with no further traffic.
	
	Optional values:
		kOOTCPMessage
	Expected responses:
		None permitted.
*/
#define kOOTCPPacket_RejectConnection		OOALSTR("Reject Connection")

/*	kOOTCPPacket_CloseConnection
	client <-> server
	Message sent by either party to cleanly close connection.
	
	Optional values:
		kOOTCPMessage
	Expected responses:
		None permitted.
*/
#define kOOTCPPacket_CloseConnection		OOALSTR("Close Connection")

/*	kOOTCPPacket_ConsoleOutput
	client --> server
	Message sent by Oolite to print text to console.
	
	Required values:
		kOOTCPMessage
		kOOTCPColorKey
	Optional values:
		kOOTCPEmphasisRanges
*/
#define kOOTCPPacket_ConsoleOutput			OOALSTR("Console Output")

/*	kOOTCPPacket_ClearConsole
	client --> server
	Message sent by Oolite to clear console output.
*/
#define kOOTCPPacket_ClearConsole			OOALSTR("Clear Console")

/*	kOOTCPPacket_ShowConsole
	client --> server
	Message sent by Oolite to request that the cosole makes itself visible and
	active.
*/
#define kOOTCPPacket_ShowConsole			OOALSTR("Show Console")

/*	kOOTCPPacket_NoteConfiguration
	client --> server
	Message sent by Oolite to appraise the console of the contents of the
	configuration dictionary. Sent once after the initial handshake.
	
	Required values:
		kOOTCPConfiguration
*/
#define kOOTCPPacket_NoteConfiguration		OOALSTR("Note Configuration")

/*	kOOTCPPacket_NoteConfigurationChange
	client <-> server
	Message sent by Oolite when the contents of the configuration dictionary
	change, or by console to change the configuration dictionary (in which
	case a confirmation will be returned in form of one or more
	kOOTCPPacket_NoteConfigurationChange messages). For this message,
	kOOTCPConfiguration is a delta -- keys not contained in it are not to be
	removed, they are simply unchanged. Deletions are handled with
	kOOTCPRemovedConfigurationKeys.
	
	This key is also sent in response to a kOOTCPPacket_RequestConfigurationValue
	message, even if no configuration value has changed.
	
	Required values (at least one of):
		kOOTCPConfiguration
		kOOTCPRemovedConfigurationKeys
*/
#define kOOTCPPacket_NoteConfigurationChange OOALSTR("Note Configuration Change")

/*	kOOTCPPacket_PerformCommand
	client <-- server
	Message sent by console to issue a command.
	
	Required values:
		kOOTCPMessage
*/
#define kOOTCPPacket_PerformCommand			OOALSTR("Perform Command")

/*	kOOTCPPacket_RequestConfigurationValue
	client <-- server
	Message sent by console to request a configuration value. This will result
	in a kOOTCPPacket_NoteConfigurationChange message being sent. If the value
	is nil, the response will contain a kOOTCPRemovedConfigurationKeys value.
	
	Required values:
		kOOTCPConfigurationKey
	Expected response:
		kOOTCPPacket_NoteConfigurationChange
*/
#define kOOTCPPacket_RequestConfigurationValue OOALSTR("Request Configuration Value")

/*	kOOTCPPacket_Ping
	client <-> server
	Must be responded to with a kOOTCPPacket_Pong message containing the same
	kOOTCPMessage, if any.
	
	Optional values:
		kOOTCPMessage
	Expected response:
		kOOTCPPacket_Pong
*/
#define kOOTCPPacket_Ping OOALSTR("Ping")

/*	kOOTCPPacket_Pong
	client <-> server
	Must be sent in response to kOOTCPPacket_Ping. If the kOOTCPPacket_Ping
	packet had a kOOTCPMessage, the same kOOTCPMessage value must be attached
	to the kOOTCPPacket_Pong.
	
	Optional values:
		kOOTCPMessage (required if included in ping)
*/
#define kOOTCPPacket_Pong OOALSTR("Pong")




/* *** Value keys *** */
/*	kOOTCPPacketType
	String indicating packet type. See above under 

	See constants below under *** Packet types ***.
*/
#define kOOTCPPacketType					OOALSTR("packet type")

/*	kOOTCPProtocolVersion
	Number indicating version of debug console TCP protocol. Sent with
	kOOTCPPacket_RequestConnection.
	
	See constants below under *** Version constants ***.
*/
#define kOOTCPProtocolVersion				OOALSTR("protocol version")

/*	kOOTCPOoliteVersion
	String indicating the version of Oolite, for example "1.70" or "1.71.1 b2".
	Consists of two or more integers separated by .s, optionally followed by
	a space and additional information in unspecified format. Sent with
	kOOTCPPacket_RequestConnection.
*/
#define kOOTCPOoliteVersion					OOALSTR("Oolite version")

/*	kOOTCPMessage
	Textual message sent with various packet types. No specified format.
*/
#define kOOTCPMessage						OOALSTR("message")

/*	kOOTCPConsoleIdentity
	String identifying console software. No specified format.
*/
#define kOOTCPConsoleIdentity				OOALSTR("console identity")

/*	kOOTCPColorKey
	String identifying colour/formatting to be used. The configuration
	dictionary contains keys of the form foo-foreground-color and
	foo-background-color to be used. If no colour is specified for the
	specified key, the key "general" should be tried. The colour values are
	specified as arrays of three numbers in the range 0-1, specifying RGB
	colours.
	
	For example, if the configuration key contains:
	{
		general-background-color = (1,1,1);
		general-foreground-color = (0,0,0);
		foo-background-color = (1,0,0);
	}
	the colour key "foo" maps to the background colour (1,0,0) and the
	foreground color (0,0,0). Sent with kOOTCPPacket_ConsoleOutput.
*/
#define kOOTCPColorKey						OOALSTR("color key")

/*	kOOTCPEmphasisRanges
	An array containing an even number of integers. Each pair of integers
	specifies a range (in the form offset, length) which should be emphasized.
	Sent with kOOTCPPacket_ConsoleOutput.
*/
#define kOOTCPEmphasisRanges				OOALSTR("emphasis ranges")

/*	kOOTCPConfiguration
	A dictionary of key/value pairs to add/set in the configuration
	dictionary. Sent with kOOTCPPacket_NoteConfiguration and
	kOOTCPPacket_NoteConfiguration.
*/
#define kOOTCPConfiguration					OOALSTR("configuration")

/*	kOOTCPConfiguration
	An array of keys to remove from the configuration dictionary. Sent with
	kOOTCPPacket_NoteConfiguration.
*/
#define kOOTCPRemovedConfigurationKeys		OOALSTR("removed configuration keys")

/*	kOOTCPConfigurationKey
	A string specifying the configuration key for which a value is requested.
	Sent with kOOTCPPacket_RequestConfigurationValue.
*/
#define kOOTCPConfigurationKey				OOALSTR("configuration key")



/* *** Version constants *** */
/*	Version constants have three components: format, major and minor. The
	format version will change if the framing mechanism is changed, that is,
	if we switch from the property-list basted protocol in use. The major
	version will be changed to indicate compatibility-breaking changes. The
	minor version will be changed when new non-critical packets are added.
*/

#define OOTCP_ENCODE_VERSION(f, mj, mi) \
		((((f) << 16) & kOOTCPProtocolVersionFormatMask) | \
		(((f) << 8) & kOOTCPProtocolVersionMajorMask) | \
		((mi) & kOOTCPProtocolVersionMinorMask))

#define OOTCP_VERSION_FORMAT(v)  (((v) & kOOTCPProtocolVersionFormatMask) >> 16)
#define OOTCP_VERSION_MAJOR(v)  (((v) & kOOTCPProtocolVersionMajorMask) >> 8)
#define OOTCP_VERSION_MINOR(v)  ((v) & kOOTCPProtocolVersionMinorMask)

enum
{
	kOOTCPProtocolVersionFormatMask		= 0x00FF0000,
	kOOTCPProtocolVersionMajorMask		= 0x0000FF00,
	kOOTCPProtocolVersionMinorMask		= 0x000000FF,
	
	kOOTCPProtocolVersionPListFormat	= 1,
	
	// 1:1.0, first version.
	kOOTCPProtocolVersion_1_1_0			= OOTCP_ENCODE_VERSION(kOOTCPProtocolVersionPListFormat, 1, 0)
};
