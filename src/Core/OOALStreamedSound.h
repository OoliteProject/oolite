/*

OOALStreamedSound.h

OOALStreamedSound - OpenAL sound implementation for Oolite.

A subclass of OOSound; the root's class cluster makes it from the C++
decoder.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

*/

#pragma once

#include <vector>

#include "OOALSound.h"
#include "OOALSoundDecoder.h"
#include "oofnd/StdLib.hpp"

class OOALStreamedSound : public OOSound {
 public:
  /*	Was -initWithDecoder:, which kept the decoder to stream from: null where
     it answered nil (sound not OK, or no decoder).
  */
  static oo::Ref<OOALStreamedSound> initWithDecoder(
      OOALSoundDecoder* inDecoder);

  ~OOALStreamedSound() override;

  std::optional<std::string> name() override;
  void rewind() override;
  bool soundIncomplete() override;
  ALuint soundBuffer() override;

 private:
  friend struct OOALStreamedSoundTestAccess;  // the stand-ins of tests that
                                              // stub the sound

  OOALStreamedSound() = default;

  std::vector<char> _buffer;  // one OOAL_STREAM_CHUNK_SIZE chunk
  double _sampleRate = {};
  std::optional<std::string> _name;  // nil-able, as the name was
  bool _stereo = {};
  oo::Ref<OOALSoundDecoder> decoder;  // retained
  bool _reachedEnd = {};
};
