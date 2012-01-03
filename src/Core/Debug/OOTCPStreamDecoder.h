/*

OOTCPStreamDecoder.h

Psuedo-object to take blobs of data, create Oolite TCP debug console
protocol packets.


Copyright (C) 2007-2012 Jens Ayton and contributors

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
