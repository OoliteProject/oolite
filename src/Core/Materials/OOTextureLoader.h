/*

OOTextureLoader.h

Abstract base class for asynchronous texture loaders, which are dispatched by
OOTextureLoadDispatcher. In general, this should be used through OOTexture.

Note: interface is likely to change in future to support other buffer types
(like S3TC/DXT#).


Copyright (C) 2007-2012 Jens Ayton

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
#import "OOAsyncWorkManager.h"


@interface OOTextureLoader: NSObject <OOAsyncWorkTask>
{
@protected
	NSString					*_path;
	
	OOTextureFlags				_options;
	uint8_t						_generateMipMaps: 1,
								_scaleAsNormalMap: 1,
								_avoidShrinking: 1,
								_noScalingWhatsoever: 1,
								_extractChannel: 1,
								_allowCubeMap: 1,
								_isCubeMap: 1,
								_ready: 1;
	uint8_t						_extractChannelIndex;
	OOTextureDataFormat			_format;
	
	void						*_data;
	uint32_t					_width,
								_height,
								_rowBytes,
								_originalWidth,
								_originalHeight;
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
			format:(OOTextureDataFormat *)outFormat
	 originalWidth:(uint32_t *)outWidth
	originalHeight:(uint32_t *)outHeight;

/*	Hopefully-unique string for texture loader; analagous, but not identical,
	to corresponding texture cacheKey.
*/
- (NSString *) cacheKey;



/*** Subclass interface; do not use on pain of pain. Unless you're subclassing. ***/

// Subclasses shouldn't do much on init, because of the whole asynchronous thing.
- (id)initWithPath:(NSString *)path options:(uint32_t)options;

- (NSString *)path;

/*	Load data, setting up _data, _format, _width, and _height; also _rowBytes
	if it's not _width * OOTextureComponentsForFormat(_format), and
	_originalWidth/_originalHeight if _width and _height for some reason aren't
	the original pixel dimensions.
	
	Thread-safety concerns: this will be called in a worker thread, and there
	may be several worker threads. The caller takes responsibility for
	autorelease pools and exception safety.
	
	Superclass will handle scaling and mip-map generation. Data must be
	allocated with malloc() family.
*/
- (void)loadTexture;

@end
