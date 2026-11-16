/*

OOALSoundDecoder.h

Class responsible for converting a sound to a PCM buffer for playback. This
class is an implementation detail. Do not use it directly; use OOSound to
load sounds.

The sounds call it directly. The Vorbis codec, the class cluster's one
concrete decoder, is private to OOALSoundDecoder.mm.


OOALSound - OpenAL sound implementation for Oolite.
Copyright (C) 2005-2013 Jens Ayton

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

#include "OOFoundation.h"
#include "OOFunctionAttributes.h"
#include "oofnd/Ref.hpp"
#include "oofnd/StdLib.hpp"
#include "oofnd/objc/OOObject.h"

#define OOAL_STREAM_CHUNK_SIZE (sizeof(char) * 409600)

class OOALSoundDecoder : public oo::RefCounted {
 public:
  /*	Was -cxx_initWithPath:, a class cluster's initialiser: it answered, in
     place of the receiver, the Vorbis codec for a path whose extension is
     "ogg", else nil. Null where it answered nil (also when the codec could not
     open the file).
  */
  static oo::Ref<OOALSoundDecoder> initWithPath(
      const std::optional<std::string>& inPath);  // nullopt: null
  static oo::Ref<OOALSoundDecoder> codecWithPath(const std::string& inPath);

  // Full-buffer reading.
  virtual bool readCreatingBuffer(char** outBuffer, size_t* outSize);

  // Stream reading.
  virtual size_t streamToBuffer(char* buffer);

  // Returns the size of the data readCreatingBuffer() will create.
  virtual size_t sizeAsBuffer();

  virtual bool isStereo();

  virtual long sampleRate();

  // For streaming
  virtual void reset();

  virtual std::optional<std::string> name();

  // What "%@" prints between the braces of <Class 0x...>{...}
  // (OODescription.h). None here, as OOObject answered; the codec prints its
  // name and comments.
  virtual std::optional<std::string> descriptionComponents() const;
};
