/*

OOALStreamedSound+ObjCBridge.h

TRANSITIONAL (proposed ADR-0056, the Audio module: amendment oo-2en): the Objective-C OOALStreamedSound, a
facade over the C++ cxx::OOALStreamedSound (OOALStreamedSound.h), for the root's class cluster
(cxx::OOSound::initWithContentsOfFile in OOALSound.mm), which makes it by alloc/init and whose test
stubs this class by name (amendment oo-rmd7 item 3). Its interface is the one OOALStreamedSound.h declared
before the conversion, copied exactly; like a converted class's facade in a hierarchy (amendment
oo-up4b item 3) it has no ivars, because the root's facade holds its C++ part. oo::ToObjC answers it
for a cxx::OOALStreamedSound by the C++ class's name. Imported as the last line of OOALStreamedSound.h; do not import it
directly. Never add to this file; converted code does not message the facade.


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

#ifndef OOALSTREAMEDSOUND_OBJCBRIDGE_H
#define OOALSTREAMEDSOUND_OBJCBRIDGE_H

@interface OOALStreamedSound : OOSound

- (id)initWithDecoder:(OOALSoundDecoder*)inDecoder;

@end

namespace oo {

// The sound's Objective-C facade, a OOALStreamedSound; autoreleased. nil for null.
OOALStreamedSound* ToObjC(cxx::OOALStreamedSound* sound);

// The C++ sound behind a facade, borrowed (the facade retains it); null for nil.
cxx::OOALStreamedSound* ToCxx(OOALStreamedSound* sound);

} // namespace oo

#endif // OOALSTREAMEDSOUND_OBJCBRIDGE_H
