/*

OOTextureLoader.h

Abstract base class for asynchronous texture loaders, which are dispatched by
OOTextureLoadDispatcher. In general, this should be used through OOTexture.

Note: interface is likely to change in future to support other buffer types
(like S3TC/DXT#).


Copyright (C) 2007-2009 Jens Ayton

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

#import "OOTexture.h"
#import "OOPixMap.h"
#import "OOAsyncWorkManager.h"


@interface OOTextureLoader: NSObject <OOAsyncWorkTask>
{
	NSString					*path;
	
	uint8_t						generateMipMaps: 1,
								scaleAsNormalMap: 1,
								avoidShrinking: 1,
								noScalingWhatsoever: 1,
								extractChannel: 1,
								allowCubeMap: 1,
								isCubeMap: 1,
								ready: 1;
	uint8_t						extractChannelIndex;
	OOTextureDataFormat			format;
	
	void						*data;
	uint32_t					width,
								height,
								rowBytes;
}

+ (id)loaderWithPath:(NSString *)path options:(uint32_t)options;

/*	Convenience method to load images not destined for normal texture use.
	Specifier is a string or a dictionary as with textures. ExtraOptions is
	ored into the option flags interpreted from the specifier. Folder is the
	directory to look in, typically Textures or Images. Options in the
	specifier which are applied at the OOTexture level will be ignored.
*/
+ (id)loaderWithTextureSpecifier:(id)specifier extraOptions:(uint32_t)extraOptions folder:(NSString *)folder;

- (BOOL)isReady;

/*	Return value indicates success. This may only be called once (subsequent
	attempts will return failure), and only on the main thread.
*/
- (BOOL) getResult:(OOPixMap *)result
			format:(OOTextureDataFormat *)outFormat;



/*** Subclass interface; do not use on pain of pain. Unless you're subclassing. ***/

// Subclasses shouldn't do much on init, because of the whole asynchronous thing.
- (id)initWithPath:(NSString *)path options:(uint32_t)options;

- (NSString *)path;

/*	Load data, setting up data, format, width, and height, and rowBytes if it's
	not width * 4.
	
	Thread-safety concerns: this will be called in a worker thread, and there
	may be several worker threads. The caller takes responsibility for
	autorelease pools and exception safety.
	
	Superclass will handle scaling and mip-map generation. Data must be
	allocated with malloc() family.
*/
- (void)loadTexture;

@end
