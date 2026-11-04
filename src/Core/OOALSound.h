/*

OOALSound.h

OOALSound - OpenAL sound implementation for Oolite.

The sound sources, the channels, the resource manager, the player and the JS
Sound class hold and call the C++ sound (oo::Ref).

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

#include "OOFoundation.h"
#include "OOOpenALController.h"
#include "oofnd/Ref.hpp"
#include "oofnd/StdLib.hpp"
#include "oofnd/objc/OOObject.h"

class OOSound : public oo::RefCounted {
 public:
  OOSound();

  static bool setUp();
  static void update();

  static void setMasterVolume(float fraction);
  static float masterVolume();

  /*	Was -cxx_initWithContentsOfFile:, a class cluster's initialiser: it
     answered, in place of the receiver, an OOALBufferedSound for up to 1 MB of
     decoded data, else an OOALStreamedSound. Null
     where it answered nil: sound not OK, no decoder for the path, or the
     concrete sound refused.
  */
  static oo::Ref<OOSound> initWithContentsOfFile(
      const std::optional<std::string>& path);  // nullopt: null

  virtual std::optional<std::string> name();  // nullopt: none

  static bool isSoundOK();

  virtual ALuint soundBuffer();
  virtual bool soundIncomplete();
  virtual void rewind();

  // What "%@" prints between the braces of <Class 0x...>{...}
  // (OODescription.h). None here, as OOObject answered.
  virtual std::optional<std::string> descriptionComponents() const;

  // What "%@" printed for the sound: <ClassName 0x...>{components}, the C++
  // class's name.
  std::string description() const;
};
