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

#import <Foundation/Foundation.h>

#define OOAL_STREAM_CHUNK_SIZE (sizeof(char) * 409600)

@interface OOALSoundDecoder: NSObject

- (id)initWithPath:(NSString *)inPath;
+ (OOALSoundDecoder *)codecWithPath:(NSString *)inPath;

// Full-buffer reading.
- (BOOL)readCreatingBuffer:(char **)outBuffer withFrameCount:(size_t *)outSize;

// Stream reading.
- (size_t)streamToBuffer:(char *)buffer;

// Returns the size of the data -readMonoCreatingBuffer:withFrameCount: will create.
- (size_t)sizeAsBuffer;

- (BOOL)isStereo;

- (long)sampleRate;

// For streaming
- (void) reset;

- (NSString *)name;

@end
