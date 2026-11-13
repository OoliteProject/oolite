/*

OOTCPStreamDecoder.c


Copyright (C) 2007 Jens Ayton and contributors

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

// A plain C++ unit: the protocol header spells OOALSTR as a handle.
#define OO_PLAIN_CPP_UNIT 1
#include "OOTCPStreamDecoder.h"

#include <stdarg.h>
#include <stdint.h>
#include <stdlib.h>

#include <memory>
#include <new>

#include "OODebugTCPConsoleProtocol.h"

#ifdef OO_LOG_DEBUG_PROTOCOL_PACKETS
extern void LogOOTCPStreamDecoderPacket(OOALDictionaryRef packet);
#else
#define LogOOTCPStreamDecoderPacket(packet) \
  do {                                      \
  } while (0)
#endif

struct OOTCPStreamDecoder {
  uint8_t header[4];
  uint32_t headerSpaceUsed;
  OOALMutableDataRef nextPacketData;
  uint32_t nextSize;

  OOTCPStreamDecoderPacketCallback Packet;
  OOTCPStreamDecoderErrorCallback Error;
  OOTCPStreamDecoderFinalizeCallback Finalize;

  void* cbInfo;
};

static void Error(OOTCPStreamDecoderRef decoder, OOALStringRef format, ...);
static void PacketReady(OOTCPStreamDecoderRef decoder);

OOTCPStreamDecoderRef OOTCPStreamDecoderCreate(
    OOTCPStreamDecoderPacketCallback packetCB,
    OOTCPStreamDecoderErrorCallback errorCB,
    OOTCPStreamDecoderFinalizeCallback finalizeCB, void* cbInfo) {
  if (packetCB == nullptr) return nullptr;

  // The caller owns the handle until OOTCPStreamDecoderDestroy().
  OOTCPStreamDecoderRef decoder = new (std::nothrow) OOTCPStreamDecoder{};
  if (decoder == nullptr) return nullptr;

  decoder->headerSpaceUsed = 0;
  decoder->nextPacketData = nullptr;
  decoder->nextSize = 0;
  decoder->Packet = packetCB;
  decoder->Error = errorCB;
  decoder->Finalize = finalizeCB;
  decoder->cbInfo = cbInfo;

  return decoder;
}

void OOTCPStreamDecoderDestroy(OOTCPStreamDecoderRef decoder) {
  if (decoder == nullptr) return;
  const std::unique_ptr<OOTCPStreamDecoder> owned(
      decoder);  // deleted on return

  if (decoder->Finalize != nullptr) {
    decoder->Finalize(decoder->cbInfo);
  }

  if (decoder->nextPacketData != nullptr) {
    OOALRelease(decoder->nextPacketData);
    decoder->nextPacketData = nullptr;
  }
}

void OOTCPStreamDecoderReceiveData(OOTCPStreamDecoderRef decoder,
                                   OOALDataRef data) {
  if (decoder == nullptr || data == nullptr) return;

  OOTCPStreamDecoderReceiveBytes(decoder, OOALDataGetBytePtr(data),
                                 OOALDataGetLength(data));
}

void OOTCPStreamDecoderReceiveBytes(OOTCPStreamDecoderRef decoder,
                                    const void* inBytes, size_t length) {
  const unsigned char* bytes = nullptr;
  size_t remaining;
  size_t bytesToAdd;
  OOALAutoreleasePoolRef pool = nullptr;

  if (decoder == nullptr) return;

  bytes = static_cast<const unsigned char*>(inBytes);
  remaining = length;

  if (bytes == nullptr && remaining != 0) {
    Error(decoder, OOALSTR("Invalid data -- NULL bytes but %u byte count."),
          remaining);
    return;
  }

  while (remaining != 0) {
    if (decoder->nextPacketData != nullptr) {
      // More data expected
      bytesToAdd = remaining;
      if (decoder->nextSize < bytesToAdd) bytesToAdd = decoder->nextSize;

      OOALMutableDataAppendBytes(decoder->nextPacketData, bytes, bytesToAdd);

      remaining -= bytesToAdd;
      decoder->nextSize -= bytesToAdd;
      bytes += bytesToAdd;

      if (decoder->nextSize == 0) {
        // Packet is ready.
        pool = OOALCreateAutoreleasePool();
        PacketReady(decoder);
        OOALDestroyAutoreleasePool(pool);
        pool = nullptr;

        OOALRelease(decoder->nextPacketData);
        decoder->nextPacketData = nullptr;
      }
    } else if (decoder->headerSpaceUsed < 4) {
      // Read bytes for packet header
      remaining--;
      decoder->header[decoder->headerSpaceUsed++] = *bytes++;
    } else if (decoder->headerSpaceUsed == 4) {
      // We've read a header, start on a packet.
      decoder->nextSize = (decoder->header[0] << 24) |
                          (decoder->header[1] << 16) |
                          (decoder->header[2] << 8) | (decoder->header[3] << 0);

      decoder->headerSpaceUsed = 0;
      if (decoder->nextSize != 0) {
        decoder->nextPacketData = OOALDataCreateMutable(decoder->nextSize);
      }
    } else {
      Error(decoder,
            OOALSTR(
                "OOTCPStreamDecoder internal error: reached unreachable state. "
                "nextSize = %zu, bufferUsed = %zu, nextPacketData = %@."),
            static_cast<unsigned long>(decoder->nextSize),
            static_cast<unsigned long>(decoder->headerSpaceUsed),
            decoder->nextPacketData);
    }
  }
}

static void PacketReady(OOTCPStreamDecoderRef decoder) {
  OOALDictionaryRef packet = nullptr;
  OOALStringRef errorString = nullptr;
  OOALStringRef packetType = nullptr;

  packet = OOALPropertyListFromData(decoder->nextPacketData, &errorString);

  // Ensure that it's a property list.
  if (packet == nullptr) {
    Error(decoder,
          OOALSTR("Protocol error: packet is not property list (property list "
                  "error: %@)."),
          errorString);
    OOALRelease(errorString);
    return;
  }

  // Ensure that it's a dictionary.
  if (!OOALIsDictionary(packet)) {
    Error(decoder, OOALSTR("Protocol error: packet is a %@, not a dictionary."),
          OOTypeDescription(packet));
    return;
  }

  LogOOTCPStreamDecoderPacket(packet);

  // Get packet type (and ensure that there is one).
  packetType = OOALDictionaryGetValue(packet, kOOTCPPacketType);
  if (packetType == nullptr) {
    Error(decoder, OOALSTR("Protocol error: packet contains no packet type."));
    return;
  }

  if (!OOALIsString(packetType)) {
    Error(decoder,
          OOALSTR("Protocol error: packet type is a %@, not a string."),
          OOTypeDescription(packetType));
    return;
  }

  decoder->Packet(decoder->cbInfo, packetType, packet);
}

static void Error(OOTCPStreamDecoderRef decoder, OOALStringRef format, ...) {
  va_list args;
  OOALStringRef string = nullptr;

  if (decoder == nullptr || decoder->Error == nullptr || format == nullptr)
    return;

  va_start(args, format);
  string = OOALStringCreateWithFormatAndArguments(format, args);
  va_end(args);

  if (string != nullptr) {
    decoder->Error(decoder->cbInfo, string);
    OOALRelease(string);
  }
}

#endif /* OO_DEBUG_MONITOR_ENABLED */
