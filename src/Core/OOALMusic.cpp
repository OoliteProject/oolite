/*

OOALMusic.m


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

#include "OOALMusic.h"

namespace {

OOMusic* sPlayingMusic = nullptr;

// The music's one source, made on first play and never released. A message to
// it while there was none did nothing, so each use checks.
OOSoundSource* sMusicSource = nullptr;

}  // namespace

OOMusic::~OOMusic() {
  if (sPlayingMusic == this) stop();
}

oo::Ref<OOMusic> OOMusic::initWithContentsOfFile(
    const std::optional<std::string>&
        inPath)  // OOSound's designated initializer, overridden
{
  oo::Ref<OOMusic> self = oo::adopt(new OOMusic);
  {
    self->sound = OOSound::initWithContentsOfFile(inPath);
    if (!self->sound) {
      self = nullptr;
    }
  }

  return self;
}

std::optional<std::string> OOMusic::name() {
  return sound != nullptr ? sound->name() : std::nullopt;
}

void OOMusic::setMusicGain(float newValue) {
  if (nullptr != sMusicSource) {
    sMusicSource->setGain(newValue);
  }
}

float OOMusic::musicGain() {
  if (nullptr == sMusicSource) return 0.0f;
  return sMusicSource->gain();
}

void OOMusic::playLooped(bool inLoop) {
  if (sPlayingMusic != this) {
    if (nullptr == sMusicSource) {
      sMusicSource = oo::makeRef<OOSoundSource>().leakRef();
    }
    sMusicSource->stop();
    sMusicSource->setLoop(inLoop);
    sMusicSource->setSound(sound.get());
    sMusicSource->play();

    sPlayingMusic = this;
  }
}

OOSoundSource* OOMusic::musicSoundSource() { return sMusicSource; }

bool OOMusic::isPlaying() {
  return sPlayingMusic == this && sMusicSource != nullptr &&
         sMusicSource->isPlaying();
}

void OOMusic::stop() {
  if (sPlayingMusic == this) {
    sPlayingMusic = nullptr;
    if (sMusicSource != nullptr) {
      sMusicSource->stop();
      sMusicSource->setSound(nullptr);
    }
  }
}
