/*

TextureStore.m

Oolite
Copyright (C) 2004-2013 Giles C Williams and contributors

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

#import "TextureStore.h"
#if !NEW_PLANETS

#import "OOMaths.h"

#ifndef NDEBUG
#import "Universe.h"
#import "MyOpenGLView.h"
#else
#import "OOColor.h"
#endif

#import "OOCollectionExtractors.h"

#define DEBUG_DUMP			(	0	&& !defined(NDEBUG))


static NSString * const kOOLogPlanetTextureGen			= @"texture.planet.generate";


#import "OOTextureGenerator.h"	// For FloatRGB


static FloatRGB FloatRGBFromDictColor(NSDictionary *dictionary, NSString *key)
{
	OOColor *color = [dictionary objectForKey:key];
	if (color == nil)
	{
		// could not get a color from the dicitionary, return white color instead of hitting the assert below
		color = [OOColor colorWithDescription:@"whiteColor"];
		OOLog(@"textureStore.FloatRGBFromDictColor.nilColor", @"Expected color for key \"%@\" in dictionary %@, got nil. Setting color to %@", key, dictionary, [color rgbaDescription]);
	}
	NSCAssert1([color isKindOfClass:[OOColor class]], @"Expected OOColor, got %@", [color class]);
	
	return (FloatRGB){ [color redComponent], [color greenComponent], [color blueComponent] };
}


static FloatRGB Blend(float fraction, FloatRGB a, FloatRGB b)
{
	return (FloatRGB)
	{
		OOLerp(a.r, b.r, fraction),
		OOLerp(a.g, b.g, fraction),
		OOLerp(a.b, b.b, fraction)
	};
}


static FloatRGB PlanetTextureColor(float q, float impress, float bias, FloatRGB seaColor, FloatRGB paleSeaColor, FloatRGB landColor, FloatRGB paleLandColor)
{
	const FloatRGB kWhite = { 1.0, 1.0, 1.0 };
	float maxq = impress + bias;
	
	float hi = 0.66667 * maxq;
	float oh = 1.0 / hi;
	float ih = 1.0 / (1.0 - hi);
	
	if (q <= 0.0)
	{
		return seaColor;
	}
	if (q > 1.0)
	{
		return (FloatRGB){ 1.0f, 1.0f, 1.0f };
	}
	if (q < 0.01)
	{
		return Blend(q * 100.0f, paleSeaColor, landColor);
	}
	if (q > hi)
	{
		return Blend((q - hi) * ih, paleLandColor, kWhite);	// snow capped peaks
	}
	
	return Blend((hi - q) * oh, paleLandColor, landColor);
}


static void fillSquareImageDataWithCloudTexture(unsigned char * imageBuffer, int width, OOColor* cloudcolor, float impress, float bias);
static void fillSquareImageWithPlanetTex(unsigned char * imageBuffer, int width, float impress, float bias, FloatRGB seaColor, FloatRGB paleSeaColor, FloatRGB landColor, FloatRGB paleLandColor);


@implementation TextureStore


#define PROC_TEXTURE_SIZE	512

+ (BOOL) getPlanetTextureNameFor:(NSDictionary *)planetInfo intoData:(unsigned char **)textureData width:(GLuint *)textureWidth height:(GLuint *)textureHeight
{
	int					texture_h = PROC_TEXTURE_SIZE;
	int					texture_w = PROC_TEXTURE_SIZE;

	int					tex_bytes = texture_w * texture_h * 4;
	
	NSParameterAssert(textureData != NULL && textureWidth != NULL && textureHeight != NULL);
	
	unsigned char *imageBuffer = malloc(tex_bytes);
	if (imageBuffer == NULL)  return NO;
	
	*textureData = imageBuffer;
	*textureWidth = texture_w;
	*textureHeight = texture_h;
	
	float land_fraction = [[planetInfo objectForKey:@"land_fraction"] floatValue];
	float sea_bias = land_fraction - 1.0;
	
	OOLog(kOOLogPlanetTextureGen, @"genning texture for land_fraction %.5f", land_fraction);
	
	FloatRGB land_color = FloatRGBFromDictColor(planetInfo, @"land_color");
	FloatRGB sea_color = FloatRGBFromDictColor(planetInfo, @"sea_color");
	FloatRGB polar_land_color = FloatRGBFromDictColor(planetInfo, @"polar_land_color");
	FloatRGB polar_sea_color = FloatRGBFromDictColor(planetInfo, @"polar_sea_color");
	
	// Pale sea colour gives a better transition between land and sea., Backported from the new planets code.
	FloatRGB pale_sea_color = Blend(0.45, polar_sea_color, Blend(0.7, sea_color, land_color));
	
	fillSquareImageWithPlanetTex(imageBuffer, texture_w, 1.0, sea_bias,
		sea_color,
		pale_sea_color,
		land_color,
		polar_land_color);
	
	return YES;
}


+ (BOOL) getCloudTextureNameFor:(OOColor*)color :(GLfloat)impress :(GLfloat)bias intoData:(unsigned char **)textureData width:(GLuint *)textureWidth height:(GLuint *)textureHeight
{
	int					texture_h = PROC_TEXTURE_SIZE;
	int					texture_w = PROC_TEXTURE_SIZE;
	int					tex_bytes;
	
	tex_bytes = texture_w * texture_h * 4;
	
	NSParameterAssert(textureData != NULL && textureWidth != NULL && textureHeight != NULL);
	
	unsigned char *imageBuffer = malloc(tex_bytes);
	if (imageBuffer == NULL)  return NO;
	
	*textureData = imageBuffer;
	*textureWidth = texture_w;
	*textureHeight = texture_h;
	
	fillSquareImageDataWithCloudTexture( imageBuffer, texture_w, color, impress, bias);
	
	return YES;
}

@end


static RANROTSeed sNoiseSeed;
static float ranNoiseBuffer[128 * 128];

void fillRanNoiseBuffer()
{
	sNoiseSeed = RANROTGetFullSeed();
	
	int i;
	for (i = 0; i < 16384; i++)
		ranNoiseBuffer[i] = randf();
}


static void addNoise(float * buffer, int p, int n, float scale)
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
		float rix = OOLerp(ranNoiseBuffer[iy * 128 + ix], ranNoiseBuffer[iy * 128 + jx], qx);
		float rjx = OOLerp(ranNoiseBuffer[jy * 128 + ix], ranNoiseBuffer[jy * 128 + jx], qx);
		float rfinal = scale * OOLerp(rix, rjx, qy);
		
		buffer[y * p + x] += rfinal;
	}
}


static float q_factor(float* accbuffer, int x, int y, int width, BOOL polar_y_smooth, float polar_y_value, BOOL polar_x_smooth, float polar_x_value, float impress, float bias)
{
	while ( x < 0 ) x+= width;
	while ( y < 0 ) y+= width;
	while ( x >= width ) x-= width;
	while ( y >= width ) y-= width;

	float q = accbuffer[ y * width + x];	// 0.0 -> 1.0

	q *= impress;	// impress
	q += bias;		// + bias

	float polar_y = (2.0f * y - width) / (float) width;
	float polar_x = (2.0f * x - width) / (float) width;
	
	polar_x *= polar_x;
	polar_y *= polar_y;
	
	if (polar_x_smooth)
		q = q * (1.0 - polar_x) + polar_x * polar_x_value;
	if (polar_y_smooth)
		q = q * (1.0 - polar_y) + polar_y * polar_y_value;

	if (q > 1.0)	q = 1.0;
	if (q < 0.0)	q = 0.0;
	
	return q;
}


static void fillSquareImageDataWithCloudTexture(unsigned char * imageBuffer, int width, OOColor* cloudcolor, float impress, float bias)
{
	NSCParameterAssert(width > 0);
	
	float accbuffer[width * width];
	memset(accbuffer, 0, sizeof accbuffer);
	int x, y;

	GLfloat rgba[4];
	rgba[0] = [cloudcolor redComponent];
	rgba[1] = [cloudcolor greenComponent];
	rgba[2] = [cloudcolor blueComponent];
	rgba[3] = [cloudcolor alphaComponent];

	int octave = 8;
	float scale = 0.5;
	while (octave < width)
	{
		addNoise(accbuffer, width, octave, scale);
		octave *= 2;
		scale *= 0.5;
	}
	
	float pole_value = (impress * accbuffer[0] - bias < 0.0)? 0.0: 1.0;
	
	for (y = 0; y < width; y++) for (x = 0; x < width; x++)
	{
		float q = q_factor(accbuffer, x, y, width, YES, pole_value, NO, 0.0, impress, bias);
		
		imageBuffer[0 + 4 * (y * width + x) ] = 255 * rgba[0];
		imageBuffer[1 + 4 * (y * width + x) ] = 255 * rgba[1];
		imageBuffer[2 + 4 * (y * width + x) ] = 255 * rgba[2];
		imageBuffer[3 + 4 * (y * width + x) ] = 255 * rgba[3] * q;
	}
#if DEBUG_DUMP
	NSString *name = [NSString stringWithFormat:@"atmosphere-%u-%u-old", sNoiseSeed.high, sNoiseSeed.low];
	OOLog(@"planetTex.dump", [NSString stringWithFormat:@"Saving generated texture to file %@.", name]);
	
	[[UNIVERSE gameView] dumpRGBAToFileNamed:name
									   bytes:imageBuffer
									   width:width
									  height:width
									rowBytes:width * 4];
#endif
}

static void fillSquareImageWithPlanetTex(unsigned char * imageBuffer, int width, float impress, float bias,
	FloatRGB seaColor,
	FloatRGB paleSeaColor,
	FloatRGB landColor,
	FloatRGB paleLandColor)
{
	float accbuffer[width * width];
	memset(accbuffer, 0, sizeof accbuffer);
	
	int octave = 8;
	float scale = 0.5;
	while (octave < width)
	{
		addNoise(accbuffer, width, octave, scale);
		octave *= 2;
		scale *= 0.5;
	}
	
	float pole_value = (impress + bias > 0.5)? 0.5 * (impress + bias) : 0.0;
	
	int x, y;
	for (y = 0; y < width; y++) for (x = 0; x < width; x++)
	{
		float q = q_factor(accbuffer, x, y, width, YES, pole_value, NO, 0.0, impress, bias);

		float yN = q_factor(accbuffer, x, y - 1, width, YES, pole_value, NO, 0.0, impress, bias);
		float yS = q_factor(accbuffer, x, y + 1, width, YES, pole_value, NO, 0.0, impress, bias);
		float yW = q_factor(accbuffer, x - 1, y, width, YES, pole_value, NO, 0.0, impress, bias);
		float yE = q_factor(accbuffer, x + 1, y, width, YES, pole_value, NO, 0.0, impress, bias);

		Vector norm = make_vector( 24.0 * (yW - yE), 24.0 * (yS - yN), 2.0);
		
		norm = vector_normal(norm);
		
		GLfloat shade = pow(norm.z, 3.2);
		
		FloatRGB color = PlanetTextureColor(q, impress, bias, seaColor, paleSeaColor, landColor, paleLandColor);
		
		color.r *= shade;
		color.g *= shade;
		color.b *= shade;
		
		imageBuffer[0 + 4 * (y * width + x)] = 255 * color.r;
		imageBuffer[1 + 4 * (y * width + x)] = 255 * color.g;
		imageBuffer[2 + 4 * (y * width + x)] = 255 * color.b;
		imageBuffer[3 + 4 * (y * width + x)] = 255;
	}
#if DEBUG_DUMP
	OOLog(@"planetTex.dump", [NSString stringWithFormat:@"Saving generated texture to file planet-%u-%u-old.", sNoiseSeed.high, sNoiseSeed.low]);
	
	[[UNIVERSE gameView] dumpRGBAToFileNamed:[NSString stringWithFormat:@"planet-%u-%u-old", sNoiseSeed.high, sNoiseSeed.low]
									   bytes:imageBuffer
									   width:width
									  height:width
									rowBytes:width * 4];
#endif
}

#endif	// !NEW_PLANETS
