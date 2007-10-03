/*	OOTCPStreamDecoder.h
	
	Psuedo-object to take blobs of data, create Oolite TCP debug console
	protocol packets.
*/

#ifndef INCLUDED_OOTCPStreamDecoder_h
#define INCLUDED_OOTCPStreamDecoder_h

#include "OOTCPStreamDecoderAbstractionLayer.h"


typedef struct OOTCPStreamDecoder *OOTCPStreamDecoderRef;

typedef void (*OOTCPStreamDecoderPacketCallback)(void *cbInfo, OOALStringRef packetType, OOALDictionaryRef packet);
typedef void (*OOTCPStreamDecoderErrorCallback)(void *cbInfo, OOALStringRef errorDesc);
typedef void (*OOTCPStreamDecoderFinalizeCallback)(void *cbInfo);


OOTCPStreamDecoderRef OOTCPStreamDecoderCreate(OOTCPStreamDecoderPacketCallback packetCB, OOTCPStreamDecoderErrorCallback errorCB, OOTCPStreamDecoderFinalizeCallback finalizeCB, void *cbInfo);
void OOTCPStreamDecoderDestroy(OOTCPStreamDecoderRef decoder);

void OOTCPStreamDecoderReceiveData(OOTCPStreamDecoderRef decoder, OOALDataRef data);
void OOTCPStreamDecoderReceiveBytes(OOTCPStreamDecoderRef decoder, const void *bytes, size_t length);

#endif /* INCLUDED_OOTCPStreamDecoder_h */
