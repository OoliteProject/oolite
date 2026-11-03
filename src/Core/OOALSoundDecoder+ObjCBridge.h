/*

OOALSoundDecoder+ObjCBridge.h

TRANSITIONAL (proposed ADR-0056, the Audio module: amendment oo-2en): the Objective-C
OOALSoundDecoder, a facade over the C++ cxx::OOALSoundDecoder (OOALSoundDecoder.h), for the code
that still messages decoders: the sounds (OOALBufferedSound, OOALStreamedSound) and the root's class
cluster in OOALSound.mm, whose test stubs this class by name (amendment oo-rmd7 item 3). Its
interface is the one OOALSoundDecoder.h declared before the conversion, copied exactly (same
selectors, same types), so they compile and behave unchanged. Imported as the last line of
OOALSoundDecoder.h; do not import it directly.

oo::ToObjC(oo::ToCxx(d)) == d. Never add to this file; converted code does not message the
facade. Deleted by its deletion bead once every caller is C++.


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

#ifndef OOALSOUNDDECODER_OBJCBRIDGE_H
#define OOALSOUNDDECODER_OBJCBRIDGE_H

@interface OOALSoundDecoder : OOObject {
@private
    oo::Ref<cxx::OOALSoundDecoder> _cxxDecoder;
}

- (id)cxx_initWithPath:(const std::optional<std::string>&)inPath OO_RETURNS_RETAINED; // nullopt: nil (bead oo-3rb.292.2)
+ (OOALSoundDecoder*)codecWithPath:(const std::string&)inPath;

// Full-buffer reading.
- (BOOL)readCreatingBuffer:(char**)outBuffer withFrameCount:(size_t*)outSize;

// Stream reading.
- (size_t)streamToBuffer:(char*)buffer;

// Returns the size of the data -readMonoCreatingBuffer:withFrameCount: will create.
- (size_t)sizeAsBuffer;

- (BOOL)isStereo;

- (long)sampleRate;

// For streaming
- (void)reset;

- (std::optional<std::string>)cxx_name; // (bead oo-3rb.289.2)

@end

namespace oo {

// The decoder's Objective-C facade: its live one, else a new one; autoreleased. nil for null.
OOALSoundDecoder* ToObjC(cxx::OOALSoundDecoder* decoder);
inline OOALSoundDecoder* ToObjC(const Ref<cxx::OOALSoundDecoder>& decoder) { return ToObjC(decoder.get()); }

// The C++ decoder behind a facade, borrowed (the facade retains it); null for nil.
cxx::OOALSoundDecoder* ToCxx(OOALSoundDecoder* decoder);

} // namespace oo

#endif // OOALSOUNDDECODER_OBJCBRIDGE_H
