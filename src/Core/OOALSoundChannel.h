/*

OOALSoundChannel.h

A channel for audio playback.

This class is an implementation detail. Do not use it directly; use an
OOSoundSource to play an OOSound.

C++20 since bead oo-5vp8 (proposed ADR-0056, the Audio module: amendment oo-2en). Its Objective-C
facade was deleted by bead oo-9ht.86: the mixer makes and keeps the channels (oo::Ref), the sound
sources hold one borrowed, and the delegate is the C++ interface OOSoundChannelDelegate below.

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

#ifndef OOALSOUNDCHANNEL_H
#define OOALSOUNDCHANNEL_H

#include "OOCocoa.h"
#include "oofnd/objc/OOObject.h"
#include "OOOpenALController.h"
#include "OOMaths.h"

#include "oofnd/Ref.hpp"

#include "OOALSound.h"
struct OOSoundChannelTestAccess;
class OOSoundChannel;


/*	The channel's delegate: was the informal OOObject (OOSoundChannelDelegate) category, any object
	answering -channel:didFinishPlayingSound: (bead oo-9ht.86). The channel holds it unretained, as
	before; a playing sound source and the stopped-source handler implement it.
*/
class OOSoundChannelDelegate
{
public:
	virtual void channel(OOSoundChannel *channel, OOSound *sound) = 0;

protected:
	~OOSoundChannelDelegate() = default;
};


class OOSoundChannel : public oo::RefCounted
{
public:
	/*	Was -init, which answered nil when OpenAL would not make a source: false then (amendment
		oo-r7m0 item 2). Its maker runs it right after making the channel and drops a channel for
		which it fails.
	*/
	bool init();

	~OOSoundChannel() override;

	void update();

	void setDelegate(OOSoundChannelDelegate *delegate);

	// Unretained pointer used to maintain simple stack
	OOSoundChannel *next();
	void setNext(OOSoundChannel *next);

	// set sound position relative to listener
	void setPosition(Vector vector);
	void setGain(float gain);
	bool playSound(OOSound *sound, bool loop);
	void stop();

	OOSound *sound();

private:
	// Was the private -hasStopped, which told the delegate that self had finished; -dealloc sent it
	// too, so the destructor does.
	void hasStopped();

	bool enqueueBuffer(OOSound *sound);
	void getNextSoundBuffer();

	OOSoundChannel				*_next = {};
	OOSoundChannelDelegate		*_delegate = {};
	oo::Ref<OOSound>			_sound;	// retained, as the Objective-C sound was
	ALuint						_buffer = {};
	ALuint						_lastBuffer = {};
	bool						_bigSound = {};
	ALuint						_source = {};
	// (The Objective-C class's _playing, which nothing read or wrote, is not kept: -Wunused-private-field.)
	bool						_loop = {};

	friend struct ::OOSoundChannelTestAccess;	// tests only (amendment oo-862e item 2)
};

#endif	// OOALSOUNDCHANNEL_H
