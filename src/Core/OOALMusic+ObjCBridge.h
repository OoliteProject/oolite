/*

OOALMusic+ObjCBridge.h

TRANSITIONAL (proposed ADR-0056, the Audio module: amendment oo-2en): the Objective-C OOMusic, a
facade over the C++ cxx::OOMusic (OOALMusic.h), for the resource manager, which makes musics by
[[OOMusic alloc] cxx_initWithContentsOfFile:], and the music controller, which messages them. Its
interface is the one OOALMusic.h declared before the conversion, copied exactly; like a converted
class's facade in a hierarchy (amendment oo-up4b item 3) it has no ivars, because the root's facade
holds its C++ part, and oo::ToObjC answers it for a cxx::OOMusic by the C++ class's name. Imported
as the last line of OOALMusic.h; do not import it directly. Never add to this file; converted code
does not message the facade.


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

#ifndef OOALMUSIC_OBJCBRIDGE_H
#define OOALMUSIC_OBJCBRIDGE_H

@interface OOMusic : OOSound

- (void)playLooped:(BOOL)looped;
- (void)stop;
- (BOOL)isPlaying;
- (void)setMusicGain:(float)newValue;
- (float)musicGain;
- (OOSoundSource*)musicSoundSource;

@end

namespace oo {

// The music's Objective-C facade, an OOMusic; autoreleased. nil for null.
OOMusic* ToObjC(cxx::OOMusic* music);

// The C++ music behind a facade, borrowed (the facade retains it); null for nil.
cxx::OOMusic* ToCxx(OOMusic* music);

} // namespace oo

#endif // OOALMUSIC_OBJCBRIDGE_H
