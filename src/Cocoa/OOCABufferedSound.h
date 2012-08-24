/*

OOCABufferedSound.h

Subclass of OOSound playing from an in-memory buffer.

This class is an implementation detail. Do not use it directly; use OOSound.


OOCASound - Core Audio sound implementation for Oolite.
Copyright (C) 2005-2012 Jens Ayton

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

#import <Cocoa/Cocoa.h>
#import "OOCASound.h"

@class OOCASoundDecoder;


@interface OOCABufferedSound: OOSound
{
@private
	float				*_bufferL,
						*_bufferR;
	size_t				_size;
	Float64				_sampleRate;
	NSString			*_name;
	BOOL				_stereo;
}

- (id)initWithDecoder:(OOCASoundDecoder *)inDecoder;

@end
