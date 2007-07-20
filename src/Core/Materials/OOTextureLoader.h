/*

OOTextureLoader.h

Manage asynchronous (threaded) loading of textures. In general, this should be
used through OOTexture.

Note: interface is likely to change in future to support other buffer (like
S3TC/DXT#).

Oolite
Copyright (C) 2004-2007 Giles C Williams and contributors

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


This file may also be distributed under the MIT/X11 license:

Copyright (C) 2007 Jens Ayton

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

#import "OOTexture.h"


@interface OOTextureLoader: NSObject
{
	NSString					*path;
	
	uint8_t						generateMipMaps: 1,
								scaleAsNormalMap: 1,
								avoidShrinking: 1,
								noScalingWhatsoever: 1,
								ready: 1;
	OOTextureDataFormat			format;
	
	void						*data;
	uint32_t					width,
								height,
								rowBytes;
}

+ (id)loaderWithPath:(NSString *)path options:(uint32_t)options;

- (BOOL)isReady;

/*	Return value indicates success. This may only be called once (subsequent
	attempts will return failure), and only on the main thread.
*/
- (BOOL)getResult:(void **)outData
		   format:(OOTextureDataFormat *)outFormat
			width:(uint32_t *)outWidth
		   height:(uint32_t *)outHeight;


/*** Subclass interface; do not use on pain of pain. Unless you're subclassing. ***/

// Subclasses shouldn't do much on init, because of the whole asynchronous thing.
- (id)initWithPath:(NSString *)path options:(uint32_t)options;

- (NSString *)path;

/*	Load data, setting up data, width, and height, and rowBytes if it's not
	width * 4.
	
	Thread-safety concerns: this will be called in a worker thread, and there
	may be several worker threads. The caller takes responsibility for
	autorelease pools and exception safety.
	
	Data must be little-endian ARGB (FIXME: is this correct?)
	
	Superclass will handle scaling and mip-map generation. Data must be
	allocated with malloc() family.
*/
- (void)loadTexture;

@end


static inline uint8_t OOTexturePlanesForFormat(OOTextureDataFormat format)
{
	switch (format)
	{
		case kOOTextureDataRGBA:
			return 4;
		
		case kOOTextureDataGrayscale:
			return 1;
		
		case kOOTextureDataInvalid:
			break;
	}
	
	return 0;
}
