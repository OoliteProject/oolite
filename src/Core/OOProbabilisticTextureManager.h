/*

OOProbabilisticTextureManager.h

Manages a set of textures, specified in a property list, with associated
probabilities. To avoid interfering with other PRNG-based code, it uses its
own ranrot state.


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

#import <Foundation/Foundation.h>
#import "OOTexture.h"
#import "OOMaths.h"


@interface OOProbabilisticTextureManager: NSObject
{
@private
	unsigned				_count;
	OOTexture				**_textures;
	float					*_prob;
	float					_probMax;
	RANROTSeed				_seed;
}

/*	plistName is the name of the property list specifying the actual textures
	to use. The plist will be loaded from Config directories and merged. It
	should contain an array of dictionaries; each dictionary must have a
	"texture" entry specifying the texture file name (in Textures directories)
	and an optional "probability" entry (default: 1.0). As a convenience, an
	entry may also be a string, in which case probability will be 1.0.
	
	If no seed is specified, the current seed will be copied.
*/
- (id)initWithPListName:(NSString *)plistName 
				options:(uint32_t)options
			 anisotropy:(GLfloat)anisotropy
				lodBias:(GLfloat)lodBias;

- (id)initWithPListName:(NSString *)plistName 
				options:(uint32_t)options
			 anisotropy:(GLfloat)anisotropy
				lodBias:(GLfloat)lodBias
				   seed:(RANROTSeed)seed;

/*	Select a texture, weighted-randomly.
*/
- (OOTexture *)selectTexture;

- (unsigned)textureCount;

- (void)ensureTexturesLoaded;

- (RANROTSeed)seed;
- (void)setSeed:(RANROTSeed)seed;

@end
