//
//  TextureStore.m
/*
 *
 *  Oolite
 *
 *  Created by Giles Williams on Sat Apr 03 2004.
 *  Copyright (c) 2004 for aegidian.org. All rights reserved.
 *

Copyright (c) 2004, Giles C Williams
All rights reserved.

This work is licensed under the Creative Commons Attribution-NonCommercial-ShareAlike License.
To view a copy of this license, visit http://creativecommons.org/licenses/by-nc-sa/2.0/
or send a letter to Creative Commons, 559 Nathan Abbott Way, Stanford, California 94305, USA.

You are free:

•	to copy, distribute, display, and perform the work
•	to make derivative works

Under the following conditions:

•	Attribution. You must give the original author credit.

•	Noncommercial. You may not use this work for commercial purposes.

•	Share Alike. If you alter, transform, or build upon this work,
you may distribute the resulting work only under a license identical to this one.

For any reuse or distribution, you must make clear to others the license terms of this work.

Any of these conditions can be waived if you get permission from the copyright holder.

Your fair use and other rights are in no way affected by the above.

*/

#import "OOCocoa.h"
#import "OOOpenGL.h"

#import "ResourceManager.h"
#import "legacy_random.h"

#import "TextureStore.h"
#import "OOColor.h"

#define PI	3.1415926536

@implementation TextureStore

- (id) init
{
	self = [super init];
	//
	textureDictionary = [[NSMutableDictionary dictionaryWithCapacity:5] retain];
	//
	return self;
}

- (void) dealloc
{
	if (textureDictionary) [textureDictionary release];
	//
	[super dealloc];
}

- (GLuint) getTextureNameFor:(NSString *)filename
{
#ifndef GNUSTEP
	NSBitmapImageRep	*bitmapImageRep = nil;
	NSImage				*texImage;
#else
	SDLImage			*texImage;
#endif
	NSSize				imageSize;
	GLuint				texName;

	unsigned char		*texBytes;
	BOOL				freeTexBytes;

	int					texture_h = 4;
	int					texture_w = 4;
	int					image_h, image_w;
	int					n_planes, im_bytes, tex_bytes;

	int					im_bytesPerRow;

	int					texi = 0;

	if (![textureDictionary objectForKey:filename])
	{
		NSMutableDictionary*	texProps = [NSMutableDictionary dictionaryWithCapacity:3];  // autoreleased
#ifndef GNUSTEP
		texImage = [ResourceManager imageNamed:filename inFolder:@"Textures"];
#else
		texImage = [ResourceManager surfaceNamed:filename inFolder:@"Textures"];
#endif
		if (!texImage)
		{
			NSLog(@"***** Couldn't find texture : %@", filename);
			NSException* myException = [NSException
				exceptionWithName: OOLITE_EXCEPTION_TEXTURE_NOT_FOUND
				reason: [NSString stringWithFormat:@"Oolite couldn't find texture : %@ on any search-path.", filename]
				userInfo: [NSDictionary dictionaryWithObjectsAndKeys: filename, @"texture", nil]];
			[myException raise];
			return 0;
		}

#ifndef GNUSTEP
		NSArray* reps = [texImage representations];

//		NSLog(@"DEBUG texture %@ representations:\n%@", filename, reps);

		int i;
		for (i = 0; ((i < [reps count]) && !bitmapImageRep); i++)
		{
			NSObject* imageRep = [reps objectAtIndex:i];
			if ([imageRep isKindOfClass:[NSBitmapImageRep class]])
				bitmapImageRep = (NSBitmapImageRep*)imageRep;
		}
		if (!bitmapImageRep)
		{
			NSLog(@"***** Couldn't find a representation for texture : %@ %@", filename, texImage);
			NSException* myException = [NSException
				exceptionWithName: OOLITE_EXCEPTION_TEXTURE_NOT_FOUND
				reason: [NSString stringWithFormat:@"Oolite couldn't find a NSBitMapImageRep for texture : %@ : %@.", filename, texImage]
				userInfo: [NSDictionary dictionaryWithObjectsAndKeys: filename, @"texture", nil]];
			[myException raise];
			return 0;
		}

//		imageSize = [texImage size];			// Gives size in points, which is bad.
		imageSize = NSMakeSize( [bitmapImageRep pixelsWide], [bitmapImageRep pixelsHigh]);	// Gives size in pixels, which is good.
		image_w = imageSize.width;
		image_h = imageSize.height;

		while (texture_w < image_w)
			texture_w *= 2;
		while (texture_h < image_h)
			texture_h *= 2;

		n_planes = [bitmapImageRep samplesPerPixel];
		im_bytes = image_w * image_h * n_planes;
		tex_bytes = texture_w * texture_h * n_planes;
		im_bytesPerRow = [bitmapImageRep bytesPerRow];

		unsigned char* imageBuffer = [bitmapImageRep bitmapData];
#else
		imageSize = NSMakeSize([texImage surface]->w, [texImage surface]->h);
		image_w = imageSize.width;
		image_h = imageSize.height;

		while (texture_w < image_w)
			texture_w *= 2;
		while (texture_h < image_h)
			texture_h *= 2;

		n_planes = [texImage surface]->format->BytesPerPixel;
		im_bytesPerRow = [texImage surface]->pitch;
		unsigned char* imageBuffer = [texImage surface]->pixels;
		im_bytes = image_w * image_h * n_planes;
		tex_bytes = texture_w * texture_h * n_planes;
		im_bytesPerRow = [texImage surface]->pitch;

#endif

		if (([filename hasPrefix:@"blur"])&&(texture_w == image_w)&&(texture_h == image_h))
		{
//			NSLog(@"DEBUG filling image data for %@ (%d x %d) with special sauce!", filename, texture_w, texture_h);
			fillSquareImageDataWithBlur(imageBuffer, texture_w, n_planes);
		}

		if (([filename hasPrefix:@"noisegen"])&&(texture_w == image_w)&&(texture_h == image_h))
		{
			NSLog(@"DEBUG filling image data for %@ (%d x %d) with special sauce!", filename, texture_w, texture_h);
			fillSquareImageWithPlanetTex( imageBuffer, texture_w, n_planes, 1.0, 0.0,
				[OOColor blueColor], 0.55, 0.01,
				[OOColor whiteColor], 0.00, 0.005,
				[OOColor greenColor], 0.08, 0.08,
				[OOColor yellowColor]);
		}

		if ((texture_w > image_w)||(texture_h > image_h))	// we need to scale the image to the texture dimensions
		{
			texBytes = malloc(tex_bytes);
			freeTexBytes = YES;

			// do bilinear scaling
			int x, y, n;
			float texel_w = (float)image_w / (float)texture_w;
			float texel_h = (float)image_h / (float)texture_h;
//			NSLog(@"scaling image %@ : %@\n scale (%d  x %d) to (%d x %d) texels: (%.3f x %.3f)", filename, texImage, image_w, image_h, texture_w, texture_h, texel_w, texel_h);

			for ( y = 0; y < texture_h; y++)
			{
				float y_lo = texel_h * y;
				float y_hi = y_lo + texel_h - 0.001;
				int y0 = floor(y_lo);
				int y1 = floor(y_hi);

				float py0 = 1.0;
				float py1 = 0.0;
				if (y1 > y0)
				{
					py0 = (y1 - y_lo) / texel_h;
					py1 = 1.0 - py0;
				}

				for ( x = 0; x < texture_w; x++)
				{
					float x_lo = texel_w * x;
					float x_hi = x_lo + texel_w - 0.001;
					int x0 = floor(x_lo);
					int x1 = floor(x_hi);
					float acc = 0;

					float px0 = 1.0;
					float px1 = 0.0;
					if (x1 > x0)
					{
						px0 = (x1 - x_lo) / texel_w;
						px1 = 1.0 - px0;
					}

					int	xy00 = y0 * im_bytesPerRow + n_planes * x0;
					int	xy01 = y0 * im_bytesPerRow + n_planes * x1;
					int	xy10 = y1 * im_bytesPerRow + n_planes * x0;
					int	xy11 = y1 * im_bytesPerRow + n_planes * x1;

					for (n = 0; n < n_planes; n++)
					{
						acc = py0 * (px0 * imageBuffer[ xy00 + n] + px1 * imageBuffer[ xy10 + n])
							+ py1 * (px0 * imageBuffer[ xy01 + n] + px1 * imageBuffer[ xy11 + n]);
						texBytes[ texi++] = (char)acc;	// float -> char
					}
				}
			}
		}
		else
		{
			// no scaling required - we will use the image data directly
			texBytes = imageBuffer;
			freeTexBytes = NO;
		}

		glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
		glGenTextures(1, &texName);			// get a new unique texture name
		glBindTexture(GL_TEXTURE_2D, texName);

		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);	// adjust this
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);	// adjust this

		switch (n_planes)	// fromt he number of planes work out how to treat the image as a texture
		{
			case 4:
				glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, texture_w, texture_h, 0, GL_RGBA, GL_UNSIGNED_BYTE, texBytes);
				break;
			case 3:
				glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, texture_w, texture_h, 0, GL_RGB, GL_UNSIGNED_BYTE, texBytes);
				break;
			case 1:
				glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, texture_w, texture_h, 0, GL_LUMINANCE, GL_UNSIGNED_BYTE, texBytes);
				break;
			default:
				// throw an error - we don't know how to deal with this texture format...
				NSLog(@"***** Couldn't deal with format of texture : %@ (%d image planes)", filename, n_planes);
				NSException* myException = [NSException
					exceptionWithName: OOLITE_EXCEPTION_TEXTURE_NOT_UNDERSTOOD
					reason: [NSString stringWithFormat:@"Oolite couldn't understand the format of texture : %@ (%d image planes)", filename, n_planes]
					userInfo: [NSDictionary dictionaryWithObjectsAndKeys: filename, @"texture", nil]];
				[myException raise];
				return 0;
		}
//
//		if (n_planes == 4)
//			glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, texture_w, texture_h, 0, GL_RGBA, GL_UNSIGNED_BYTE, texBytes);
//		else
//			glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, texture_w, texture_h, 0, GL_RGB, GL_UNSIGNED_BYTE, texBytes);

		if (freeTexBytes) free(texBytes);

		// add to dictionary
		//
		[texProps setObject:[NSNumber numberWithInt:texName] forKey:@"texName"];
		[texProps setObject:[NSNumber numberWithInt:texture_w] forKey:@"width"];
		[texProps setObject:[NSNumber numberWithInt:texture_h] forKey:@"height"];

		[textureDictionary setObject:texProps forKey:filename];
	}
	else
	{
		texName = (GLuint)[(NSNumber *)[[textureDictionary objectForKey:filename] objectForKey:@"texName"] intValue];
	}
	return texName;
}

- (NSSize) getSizeOfTexture:(NSString *)filename
{
	NSSize size = NSMakeSize(0.0, 0.0);	// zero size
	if ([textureDictionary objectForKey:filename])
	{
		size.width = [(NSNumber *)[[textureDictionary objectForKey:filename] objectForKey:@"width"] intValue];
		size.height = [(NSNumber *)[[textureDictionary objectForKey:filename] objectForKey:@"height"] intValue];
	}
	return size;
}

- (void) reloadTextures
{
#ifdef WIN32
	int i;

	// Free up the texture image data from video memory. I assume this is a reasonable thing
	// to do for any platform, but just in case... stick it in a WIN32 only condition.
	NSArray *keys = [textureDictionary allKeys];
	for (i = 0; i < [keys count]; i++)
	{
		GLuint texName = (GLuint)[(NSNumber *)[[textureDictionary objectForKey:[keys objectAtIndex:i]] objectForKey:@"texName"] intValue];
		NSLog(@"deleting texture #%d (%@)", texName, (NSString *)[keys objectAtIndex:i]);
		glDeleteTextures(1, &texName);
	}
#endif

	[textureDictionary removeAllObjects];
	return;
}

- (GLuint) getPlanetTextureNameFor:(NSDictionary*)planetinfo
{
	NSSize				imageSize;
	GLuint				texName;

	unsigned char		*texBytes;

	int					texture_h = 4;
	int					texture_w = 4;
	int					image_h, image_w;
	int					n_planes, im_bytes, tex_bytes;

	int					im_bytesPerRow;

	imageSize = NSMakeSize( 512, 512);	// Gives size in pixels, which is good.
	image_w = imageSize.width;
	image_h = imageSize.height;
	texture_w = imageSize.width;
	texture_h = imageSize.height;
	n_planes = 4;
	im_bytes = image_w * image_h * n_planes;
	tex_bytes = texture_w * texture_h * n_planes;
	im_bytesPerRow = 512 * 4;

	unsigned char* imageBuffer = malloc( tex_bytes);

	float land_fraction = [[planetinfo objectForKey:@"land_fraction"] floatValue];
	float sea_bias = land_fraction - 1.0;
	
	NSLog(@"genning texture for land_fraction %.5f", land_fraction);
	
	OOColor* land_color = (OOColor*)[planetinfo objectForKey:@"land_color"];
	OOColor* sea_color = (OOColor*)[planetinfo objectForKey:@"sea_color"];
	OOColor* polar_land_color = (OOColor*)[planetinfo objectForKey:@"polar_land_color"];
	OOColor* polar_sea_color = (OOColor*)[planetinfo objectForKey:@"polar_sea_color"];

	fillSquareImageWithPlanetTex( imageBuffer, texture_w, n_planes, 1.0, sea_bias,
		sea_color, 0.22, 0.05,
		polar_sea_color, 0.23, 0.05,
		land_color, 0.22, 0.05,
		polar_land_color);

	texBytes = imageBuffer;

	glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
	glGenTextures(1, &texName);			// get a new unique texture name
	glBindTexture(GL_TEXTURE_2D, texName);

	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);	// adjust this
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);	// adjust this

	glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, texture_w, texture_h, 0, GL_RGBA, GL_UNSIGNED_BYTE, texBytes);

	return texName;
}

void fillSquareImageDataWithBlur(unsigned char * imageBuffer, int width, int nplanes)
{
	int x, y;
	int r = width / 2;
	float r1 = 1.0 / r;
	float i_error = 0;
	for (y = 0; y < r; y++) for (x = 0; x < r; x++)
	{
		int x1 = r - x - 1;
		int x2 = r + x;
		int y1 = r - y - 1;
		int y2 = r + y;
		float d = sqrt(x*x + y*y);
		if (d > r)
			d = r;
		float fi = 255.0 - 255.0 * d * r1;
		unsigned char i = (unsigned char)fi;

		i_error += fi - i;	// accumulate the error between i and fi

		if ((i_error > 1.0)&&(i < 255))
		{
//			NSLog(@"DEBUG err correct");
			i_error -= 1.0;
			i++;
		}

		int p;
		for (p = 0; p < nplanes - 1; p++)
		{
			imageBuffer[ p + nplanes * (y1 * width + x1) ] = 128 | (ranrot_rand() & 127);
			imageBuffer[ p + nplanes * (y1 * width + x2) ] = 128 | (ranrot_rand() & 127);
			imageBuffer[ p + nplanes * (y2 * width + x1) ] = 128 | (ranrot_rand() & 127);
			imageBuffer[ p + nplanes * (y2 * width + x2) ] = 128 | (ranrot_rand() & 127);
		}
		imageBuffer[ p + nplanes * (y1 * width + x1) ] = i;	// hoping RGBA last plane is alpha
		imageBuffer[ p + nplanes * (y1 * width + x2) ] = i;
		imageBuffer[ p + nplanes * (y2 * width + x1) ] = i;
		imageBuffer[ p + nplanes * (y2 * width + x2) ] = i;
	}
}

float ranNoiseBuffer[ 128 * 128];
void fillRanNoiseBuffer()
{
	int i;
	for (i = 0; i < 16384; i++)
		ranNoiseBuffer[i] = randf();
}

float lerp_r( float v0, float r0s, float r0i, float v1, float r1s, float r1i, float v2, float r2s, float r2i, float v3, float q)
{
	if (q < r0s)
		return v0;
	q -= r0s;
	if (q < r0i)
		return v0 * (r0i - q)/r0i + v1 * q / r0i;
	q -= r0i;
	//
	if (q < r1s)
		return v1;
	q -= r1s;
	if (q < r1i)
		return v1 * (r1i - q)/r1i + v2 * q / r1i;
	q -= r1i;
	//
	if (q < r2s)
		return v2;
	q -= r2s;
	if (q < r2i)
		return v2 * (r2i - q)/r2i + v3 * q / r2i;
	q -= r2i;
	//
	return v3;	// values of q over r0+r1+r2+r3
}

float my_lerp( float v0, float v1, float q)
{
	float q1 = 0.5 * (1.0 + cosf((q + 1.0) * PI));
	return v0 * (1.0 - q1) + v1 * q1;
}

void addNoise(float * buffer, int p, int n, float scale)
{
	int x, y;
	
	float r = (float)p / (float)n;
	for (y = 0; y < p; y++) for (x = 0; x < p; x++)
	{
		int ix = floor( (float)x / r);
		int jx = (ix + 1) % n;
		int iy = floor( (float)y / r);
		int jy = (iy + 1) % n;
		float qx = x / r - ix;
		float qy = y / r - iy;
		ix &= 127;
		iy &= 127;
		jx &= 127;
		jy &= 127;
		float rix = my_lerp( ranNoiseBuffer[iy * 128 + ix], ranNoiseBuffer[iy * 128 + jx], qx);
		float rjx = my_lerp( ranNoiseBuffer[jy * 128 + ix], ranNoiseBuffer[jy * 128 + jx], qx);
		float rfinal = scale * my_lerp( rix, rjx, qy);

		buffer[ y * p + x ] += rfinal;
	}
}

void fillSquareImageDataWithSmoothNoise(unsigned char * imageBuffer, int width, int nplanes)
{
	float accbuffer[width * width];
	int x, y;
	for (y = 0; y < width; y++) for (x = 0; x < width; x++) accbuffer[ y * width + x] = 0.0f;

	fillRanNoiseBuffer();
	int octave = 4;
	float scale = 0.5;
	while (octave < width)
	{
		addNoise( accbuffer, width, octave, scale);
		octave *= 2;
		scale *= 0.5;
	}
	
	for (y = 0; y < width; y++) for (x = 0; x < width; x++)
	{
		int p;
		float q = accbuffer[ y * width + x];
		q = 2.0f * ( q - 0.5f);
		if (q < 0.0f)
			q = 0.0f;
		for (p = 0; p < nplanes - 1; p++)
			imageBuffer[ p + nplanes * (y * width + x) ] = 255 * q;
		imageBuffer[ p + nplanes * (y * width + x) ] = 255;
	}
}

void fillSquareImageWithPlanetTex(unsigned char * imageBuffer, int width, int nplanes, float impress, float bias,
	OOColor* c0, float r0s, float r0i,
	OOColor* c1, float r1s, float r1i,
	OOColor* c2, float r2s, float r2i,
	OOColor* c3)
{
	float accbuffer[width * width];
	int x, y;
	for (y = 0; y < width; y++) for (x = 0; x < width; x++) accbuffer[ y * width + x] = 0.0f;

	fillRanNoiseBuffer();
	int octave = 4;
	float scale = 0.5;
	while (octave < width)
	{
		addNoise( accbuffer, width, octave, scale);
		octave *= 2;
		scale *= 0.5;
	}
	
	for (y = 0; y < width; y++) for (x = 0; x < width; x++)
	{
		float q =  impress * accbuffer[ y * width + x] + bias;
		if (q > 1.0)	q = 1.0;
		if (q < 0.0)	q = 0.0;
		
		float red = lerp_r( [c0 redComponent], r0s, r0i, [c1 redComponent], r1s, r1i, [c2 redComponent], r2s, r2i, [c3 redComponent], q);
		float green = lerp_r( [c0 greenComponent], r0s, r0i, [c1 greenComponent], r1s, r1i, [c2 greenComponent], r2s, r2i, [c3 greenComponent], q);
		float blue = lerp_r( [c0 blueComponent], r0s, r0i, [c1 blueComponent], r1s, r1i, [c2 blueComponent], r2s, r2i, [c3 blueComponent], q);
		
		if (nplanes == 1)
			imageBuffer[ y * width + x ] = 255 * q;
		if (nplanes == 3)
		{
			imageBuffer[ 0 + 3 * (y * width + x) ] = 255 * red;
			imageBuffer[ 1 + 3 * (y * width + x) ] = 255 * green;
			imageBuffer[ 2 + 3 * (y * width + x) ] = 255 * blue;
		}
		if (nplanes == 4)
		{
			imageBuffer[ 0 + 4 * (y * width + x) ] = 255 * red;
			imageBuffer[ 1 + 4 * (y * width + x) ] = 255 * green;
			imageBuffer[ 2 + 4 * (y * width + x) ] = 255 * blue;
			imageBuffer[ 3 + 4 * (y * width + x) ] = 255;
		}
	}
}

@end
