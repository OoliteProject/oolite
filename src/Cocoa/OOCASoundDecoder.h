/*

OOCASoundDecoder.h

Class responsible for converting a sound to a PCM buffer for playback. This
class is an implementation detail. Do not use it directly; use OOSound to
load sounds.

OOCASound - Core Audio sound implementation for Oolite.
Copyright (C) 2005-2006  Jens Ayton

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
MA 02110-1301, USA.

*/

#import <Cocoa/Cocoa.h>


@interface OOCASoundDecoder: NSObject

- (id)initWithPath:(NSString *)inPath;
+ (OOCASoundDecoder *)codecWithPath:(NSString *)inPath;

// Full-buffer reading.
- (BOOL)readMonoCreatingBuffer:(float **)outBuffer withFrameCount:(size_t *)outSize;
- (BOOL)readStereoCreatingLeftBuffer:(float **)outLeftBuffer rightBuffer:(float **)outRightBuffer withFrameCount:(size_t *)outSize;

// Stream reading. This will always provide two channels (as non-interleaved PCM), discarding extra channels or doubling mono as necessary.
- (size_t)streamStereoToBufferL:(float *)ioBufferL bufferR:(float *)ioBufferR maxFrames:(size_t)inMax;

// Returns the size of the data -readMonoCreatingBuffer:withFrameCount: will create.
- (size_t)sizeAsBuffer;

- (BOOL)isStereo;

- (Float64)sampleRate;

// For streaming
- (BOOL)atEnd;
- (BOOL)scanToOffset:(uint64_t)inOffset;
- (void)rewindToBeginning;

- (NSString *)name;

@end
