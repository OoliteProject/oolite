//	
//	OOCASoundDecoder.h
//	CoreAudio sound implementation for Oolite
//	
/*

Copyright © 2005-2006 Jens Ayton
All rights reserved.

This work is licensed under the Creative Commons Attribution-ShareAlike License.
To view a copy of this license, visit http://creativecommons.org/licenses/by-sa/2.0/
or send a letter to Creative Commons, 559 Nathan Abbott Way, Stanford, California 94305, USA.

You are free:

•	to copy, distribute, display, and perform the work
•	to make derivative works

Under the following conditions:

•	Attribution. You must give the original author credit.
•	Share Alike. If you alter, transform, or build upon this work,
	you may distribute the resulting work only under a license identical to this one.

For any reuse or distribution, you must make clear to others the license terms of this work.

Any of these conditions can be waived if you get permission from the copyright holder.

Your fair use and other rights are in no way affected by the above.

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
