/*

OOALSoundChannel+ObjCBridge.h

TRANSITIONAL (proposed ADR-0056, the Audio module: amendment oo-2en): the Objective-C
OOSoundChannel, a facade over the C++ cxx::OOSoundChannel (OOALSoundChannel.h), for the mixer,
which makes the channels by alloc/init, and the sound sources, which message them; both stub this
class in their tests (amendment oo-rmd7 item 3). Its interface is the one OOALSoundChannel.h
declared before the conversion, copied exactly, and so is the delegate category, which moves here
with it (as a protocol does: amendment oo-jpd8 item 1). Imported as the last line of
OOALSoundChannel.h; do not import it directly.

oo::ToObjC(oo::ToCxx(c)) == c. Never add to this file; converted code does not message the
facade. Deleted by its deletion bead once the mixer and the sources are C++.


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

#ifndef OOALSOUNDCHANNEL_OBJCBRIDGE_H
#define OOALSOUNDCHANNEL_OBJCBRIDGE_H

@interface OOSoundChannel : OOObject {
@private
    oo::Ref<cxx::OOSoundChannel> _cxxChannel;
}

- (void)update;

- (void)setDelegate:(id)delegate;

// Unretained pointer used to maintain simple stack
- (OOSoundChannel*)next;
- (void)setNext:(OOSoundChannel*)next;

// set sound position relative to listener
- (void)setPosition:(Vector)vector;
- (void)setGain:(float)gain;
- (BOOL)playSound:(OOSound*)sound looped:(BOOL)loop;
- (void)stop;

- (OOSound*)sound;

@end

@interface OOObject (OOSoundChannelDelegate)

- (void)channel:(OOSoundChannel*)inChannel didFinishPlayingSound:(OOSound*)inSound;

@end

namespace oo {

// The channel's Objective-C facade: its live one, else a new one; autoreleased. nil for null.
OOSoundChannel* ToObjC(cxx::OOSoundChannel* channel);
inline OOSoundChannel* ToObjC(const Ref<cxx::OOSoundChannel>& channel) { return ToObjC(channel.get()); }

// The C++ channel behind a facade, borrowed (the facade retains it); null for nil.
cxx::OOSoundChannel* ToCxx(OOSoundChannel* channel);

} // namespace oo

#endif // OOALSOUNDCHANNEL_OBJCBRIDGE_H
