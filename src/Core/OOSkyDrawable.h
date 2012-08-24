/*

OOSkyDrawable.h

Drawable for the sky (i.e., the surrounding space, not planetary atmosphere).


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

#import "OODrawable.h"
#import "OOOpenGL.h"

@class OOColor, OOTexture;


@interface OOSkyDrawable: OODrawable
{
@private
	unsigned				_starCount;
	unsigned				_nebulaCount;
	
	NSMutableArray			*_quadSets;
	
	GLint					_displayListName;
}

- (id)initWithColor1:(OOColor *)color1
			  Color2:(OOColor *)color2
		   starCount:(unsigned)starCount
		 nebulaCount:(unsigned)nebulaCount
	   clusterFactor:(float)nebulaClusterFactor
			   alpha:(float)nebulaAlpha
			   scale:(float)nebulaScale;

@end
