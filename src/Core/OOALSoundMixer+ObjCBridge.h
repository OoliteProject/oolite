/*

OOALSoundMixer+ObjCBridge.h

TRANSITIONAL (proposed ADR-0056, the Audio module: amendment oo-2en): the Objective-C OOSoundMixer,
a facade over the C++ cxx::OOSoundMixer (OOALSoundMixer.h), for the code that messages the mixer:
the sound sources, the root sound's +update (OOALSound.mm) and OOOpenALController::shutdown(), whose
tests stub this class (amendment oo-rmd7 item 3). Its interface is the one OOALSoundMixer.h declared
before the conversion, copied exactly. +sharedMixer answers one facade for the life of the process
(amendment oo-r7m0 item 5). Imported as the last line of OOALSoundMixer.h; do not import it
directly. Never add to this file; converted code does not message the facade.


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

#ifndef OOALSOUNDMIXER_OBJCBRIDGE_H
#define OOALSOUNDMIXER_OBJCBRIDGE_H

@interface OOSoundMixer : OOObject {
@private
    oo::Ref<cxx::OOSoundMixer> _cxxMixer;
}

// Singleton accessor
+ (id)sharedMixer;

- (void)update;

// Only to be called at app shutdown, by OOOpenALController::shutdown(). (Declared here since
// bead oo-r7m0: the declaration it resolved to was OOOpenALController's own -shutdown.)
- (void)shutdown;

- (OOSoundChannel*)popChannel;
- (void)pushChannel:(OOSoundChannel*)channel;

@end

namespace oo {

// The mixer's Objective-C facade: its live one, else a new one; autoreleased. nil for null.
OOSoundMixer* ToObjC(cxx::OOSoundMixer* mixer);

// The C++ mixer behind a facade, borrowed (the facade retains it); null for nil.
cxx::OOSoundMixer* ToCxx(OOSoundMixer* mixer);

} // namespace oo

#endif // OOALSOUNDMIXER_OBJCBRIDGE_H
