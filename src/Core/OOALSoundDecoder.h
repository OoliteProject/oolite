/*

OOALSoundDecoder.h

Class responsible for converting a sound to a PCM buffer for playback. This
class is an implementation detail. Do not use it directly; use OOSound to
load sounds.


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

#import "OOFoundation.h"
#import "OOFunctionAttributes.h"
#import "oofnd/objc/OOObject.h"

#include "oofnd/StdLib.hpp"

#define OOAL_STREAM_CHUNK_SIZE (sizeof(char) * 409600)

@interface OOALSoundDecoder : OOObject

- (id)initWithPath:(id)inPath; // inPath: an Objective-C string. Shared selector (Foundation declares -initWithPath: too): -cxx_initWithPath:.
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

- (id)name; // shared selector (Foundation declares -name too): -cxx_name as an Objective-C string, or nil
- (std::optional<std::string>)cxx_name; // (bead oo-3rb.289.2)

@end
