/*

OOALSoundChannel.h

A channel for audio playback.

This class is an implementation detail. Do not use it directly; use an
OOSoundSource to play an OOSound.

The mixer makes and keeps the channels (oo::Ref), the sound sources hold one
borrowed, and the delegate is the C++ interface OOSoundChannelDelegate below.

OOALSound - OpenAL sound implementation for Oolite.
Copyright (C) 2006-2013 Jens Ayton

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

#include "OOALSound.h"
#include "OOFoundation.h"
#include "OOMaths.h"
#include "OOOpenALController.h"
#include "oofnd/Ref.hpp"
#include "oofnd/objc/OOObject.h"
struct OOSoundChannelTestAccess;
class OOSoundChannel;

/*	The channel's delegate: was the informal OOObject
   (OOSoundChannelDelegate) category, any object answering
   -channel:didFinishPlayingSound:. The channel holds it
   unretained, as before; a playing sound source and the stopped-source handler
   implement it.
*/
class OOSoundChannelDelegate {
 public:
  virtual void channel(OOSoundChannel* channel, OOSound* sound) = 0;

 protected:
  ~OOSoundChannelDelegate() = default;
};

class OOSoundChannel : public oo::RefCounted {
 public:
  /*	Was -init, which answered nil when OpenAL would not make a source: false
     then. Its maker runs it right after making the
     channel and drops a channel for which it fails.
  */
  bool init();

  ~OOSoundChannel() override;

  void update();

  void setDelegate(OOSoundChannelDelegate* delegate);

  // Unretained pointer used to maintain simple stack
  OOSoundChannel* next();
  void setNext(OOSoundChannel* next);

  // set sound position relative to listener
  void setPosition(Vector vector);
  void setGain(float gain);
  bool playSound(OOSound* sound, bool loop);
  void stop();

  OOSound* sound();

 private:
  // Was the private -hasStopped, which told the delegate that self had
  // finished; -dealloc sent it too, so the destructor does.
  void hasStopped();

  bool enqueueBuffer(OOSound* sound);
  void getNextSoundBuffer();

  OOSoundChannel* _next = {};
  OOSoundChannelDelegate* _delegate = {};
  std::shared_ptr<OOSound> _sound;  // retained
  ALuint _buffer = {};
  ALuint _lastBuffer = {};
  bool _bigSound = {};
  ALuint _source = {};
  bool _loop = {};

  friend struct ::OOSoundChannelTestAccess;  // tests only
};
