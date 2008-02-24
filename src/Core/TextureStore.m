/*

TextureStore.m

Oolite
Copyright (C) 2004-2008 Giles C Williams and contributors

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

#import "OOCocoa.h"
#import "OOOpenGL.h"

#import "ResourceManager.h"
#import "legacy_random.h"

#import "TextureStore.h"
#import "OOColor.h"
#import "OOMaths.h"
#import "OOTextureScaling.h"
#import "OOStringParsing.h"
#import "OOTexture.h"

#define kOOLogUnconvertedNSLog @"unclassified.TextureStore"


static NSString * const kOOLogPlanetTextureGen			= @"texture.planet.generate";


@implementation TextureStore

NSMutableDictionary	*textureUniversalDictionary = nil;
NSMutableDictionary	*shaderUniversalDictionary = nil;

BOOL	done_maxsize_test = NO;
GLuint	max_texture_dimension = 512;	// conservative start
+ (GLuint) maxTextureDimension
{
	if (done_maxsize_test)
		return max_texture_dimension;
	GLint result;
	glGetIntegerv( GL_MAX_TEXTURE_SIZE, &result);
	max_texture_dimension = result;
	done_maxsize_test = YES;
	return max_texture_dimension;
}


+ (GLuint) getTextureNameFor:(NSString *)filename
{
	if ([textureUniversalDictionary objectForKey:filename])
		return [[(NSDictionary *)[textureUniversalDictionary objectForKey:filename] objectForKey:@"texName"] intValue];
	return [TextureStore getTextureNameFor: filename inFolder: @"Textures"];
}

+ (GLuint) getImageNameFor:(NSString *)filename
{
	if ([textureUniversalDictionary objectForKey:filename])
		return [[(NSDictionary *)[textureUniversalDictionary objectForKey:filename] objectForKey:@"texName"] intValue];
	return [TextureStore getTextureNameFor: filename inFolder: @"Images"];
}


+ (GLuint) getTextureNameFor:(NSString *)fileName inFolder:(NSString*)folderName
{
	OOTexture				*texture = nil;
	NSDictionary			*texProps = nil;
	GLint					texName;
	NSSize					dimensions;
	NSNumber				*texNameObj = nil;
	
	texture = [OOTexture textureWithName:fileName inFolder:folderName];
	texName = [texture glTextureName];
	if (texName != 0)
	{
		dimensions = [texture dimensions];
		texNameObj = [NSNumber numberWithInt:texName];
		
		texProps = [NSDictionary dictionaryWithObjectsAndKeys:
						texNameObj, @"texName",
						[NSNumber numberWithInt:dimensions.width], @"width",
						[NSNumber numberWithInt:dimensions.height], @"height",
						texture, @"OOTexture",
						nil];
		
		if (textureUniversalDictionary == nil)  textureUniversalDictionary = [[NSMutableDictionary alloc] init];
		
		[textureUniversalDictionary setObject:texProps forKey:fileName];
		[textureUniversalDictionary setObject:fileName forKey:texNameObj];
	}
	return texName;
}


+ (NSString*) getNameOfTextureWithGLuint:(GLuint) value
{
	return (NSString*)[textureUniversalDictionary objectForKey:[NSNumber numberWithInt:value]];
}

+ (NSSize) getSizeOfTexture:(NSString *)filename
{
	NSSize size = NSMakeSize(0.0, 0.0);	// zero size
	if ([textureUniversalDictionary objectForKey:filename])
	{
		size.width = [[(NSDictionary *)[textureUniversalDictionary objectForKey:filename] objectForKey:@"width"] intValue];
		size.height = [[(NSDictionary *)[textureUniversalDictionary objectForKey:filename] objectForKey:@"height"] intValue];
	}
	return size;
}


+ (GLuint) getPlanetTextureNameFor:(NSDictionary*)planetinfo intoData:(unsigned char **)textureData
{
	GLuint				texName;

	int					texsize = 512;

	unsigned char		*texBytes;

	int					texture_h = texsize;
	int					texture_w = texsize;

	int					tex_bytes = texture_w * texture_h * 4;

	unsigned char* imageBuffer = malloc( tex_bytes);
	if (textureData)
		(*textureData) = imageBuffer;

	float land_fraction = [[planetinfo objectForKey:@"land_fraction"] floatValue];
	float sea_bias = land_fraction - 1.0;
	
	OOLog(kOOLogPlanetTextureGen, @"genning texture for land_fraction %.5f", land_fraction);
	
	OOColor* land_color = (OOColor*)[planetinfo objectForKey:@"land_color"];
	OOColor* sea_color = (OOColor*)[planetinfo objectForKey:@"sea_color"];
	OOColor* polar_land_color = (OOColor*)[planetinfo objectForKey:@"polar_land_color"];
	OOColor* polar_sea_color = (OOColor*)[planetinfo objectForKey:@"polar_sea_color"];

	fillSquareImageWithPlanetTex( imageBuffer, texture_w, 4, 1.0, sea_bias,
		sea_color,
		polar_sea_color,
		land_color,
		polar_land_color);

	texBytes = imageBuffer;

	glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
	texName = GLAllocateTextureName();
	glBindTexture(GL_TEXTURE_2D, texName);

	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);	// adjust this
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);	// adjust this

	glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, texture_w, texture_h, 0, GL_RGBA, GL_UNSIGNED_BYTE, texBytes);

	return texName;
}

+ (GLuint) getPlanetNormalMapNameFor:(NSDictionary*)planetinfo intoData:(unsigned char **)textureData
{
	GLuint				texName;

	int					texsize = 512;

	unsigned char		*texBytes;

	int					texture_h = texsize;
	int					texture_w = texsize;

	int					tex_bytes = texture_w * texture_h * 4;

	unsigned char* imageBuffer = malloc( tex_bytes);
	if (textureData)
		(*textureData) = imageBuffer;

	float land_fraction = [[planetinfo objectForKey:@"land_fraction"] floatValue];
	float sea_bias = land_fraction - 1.0;
	
	OOLog(@"textureStore.genNormalMap", @"genning normal map for land_fraction %.5f", land_fraction);
	
//	fillRanNoiseBuffer();
	fillSquareImageWithPlanetNMap( imageBuffer, texture_w, 4, 1.0, sea_bias, 24.0);

	texBytes = imageBuffer;

	glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
	texName = GLAllocateTextureName();
	glBindTexture(GL_TEXTURE_2D, texName);

	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);	// adjust this
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);	// adjust this

	glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, texture_w, texture_h, 0, GL_RGBA, GL_UNSIGNED_BYTE, texBytes);

	return texName;
}

+ (GLuint) getCloudTextureNameFor:(OOColor*) color: (GLfloat) impress: (GLfloat) bias intoData:(unsigned char **)textureData
{
	GLuint				texName;

	unsigned char		*texBytes;

	int					texture_h = 512;
	int					texture_w = 512;
	int					tex_bytes;

	tex_bytes = texture_w * texture_h * 4;

	unsigned char* imageBuffer = malloc( tex_bytes);
	if (textureData)
		(*textureData) = imageBuffer;

//	fillRanNoiseBuffer();
	fillSquareImageDataWithCloudTexture( imageBuffer, texture_w, 4, color, impress, bias);

	texBytes = imageBuffer;

	glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
	texName = GLAllocateTextureName();
	glBindTexture(GL_TEXTURE_2D, texName);

	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);	// adjust this
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);	// adjust this

	glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, texture_w, texture_h, 0, GL_RGBA, GL_UNSIGNED_BYTE, texBytes);

	return texName;
}

void fillSquareImageDataWithBlur(unsigned char * imageBuffer, int width, int nplanes)
{
	OOLog(@"texture.generatingBlur", @"Genrating blur - %u pixels wide, %u planes.", width, nplanes);
	
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

float my_lerp( float v0, float v1, float q)
{
	float q1 = 0.5 * (1.0 + cosf((q + 1.0) * M_PI));
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

float q_factor(float* accbuffer, int x, int y, int width, BOOL polar_y_smooth, float polar_y_value, BOOL polar_x_smooth, float polar_x_value, float impress, float bias)
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


void fillSquareImageDataWithCloudTexture(unsigned char * imageBuffer, int width, int nplanes, OOColor* cloudcolor, float impress, float bias)
{
	float accbuffer[width * width];
	int x, y;
	y = width * width;
	for (x = 0; x < y; x++) accbuffer[x] = 0.0f;

	GLfloat rgba[4];
	rgba[0] = [cloudcolor redComponent];
	rgba[1] = [cloudcolor greenComponent];
	rgba[2] = [cloudcolor blueComponent];
	rgba[3] = [cloudcolor alphaComponent];

	int octave = 8;
	float scale = 0.5;
	while (octave < width)
	{
		addNoise( accbuffer, width, octave, scale);
		octave *= 2;
		scale *= 0.5;
	}
	
	float pole_value = (impress * accbuffer[0] - bias < 0.0)? 0.0: 1.0;
	
	for (y = 0; y < width; y++) for (x = 0; x < width; x++)
	{
		float q = q_factor( accbuffer, x, y, width, YES, pole_value, NO, 0.0, impress, bias);
				
		if (nplanes == 1)
			imageBuffer[ y * width + x ] = 255 * q;
		if (nplanes == 3)
		{
			imageBuffer[ 0 + 3 * (y * width + x) ] = 255 * rgba[0] * q;
			imageBuffer[ 1 + 3 * (y * width + x) ] = 255 * rgba[1] * q;
			imageBuffer[ 2 + 3 * (y * width + x) ] = 255 * rgba[2] * q;
		}
		if (nplanes == 4)
		{
			imageBuffer[ 0 + 4 * (y * width + x) ] = 255 * rgba[0];
			imageBuffer[ 1 + 4 * (y * width + x) ] = 255 * rgba[1];
			imageBuffer[ 2 + 4 * (y * width + x) ] = 255 * rgba[2];
			imageBuffer[ 3 + 4 * (y * width + x) ] = 255 * rgba[3] * q;
		}
	}
}

void fillSquareImageWithPlanetTex(unsigned char * imageBuffer, int width, int nplanes, float impress, float bias,
	OOColor* seaColor,
	OOColor* paleSeaColor,
	OOColor* landColor,
	OOColor* paleLandColor)
{
	float accbuffer[width * width];
	int x, y;
	y = width * width;
	for (x = 0; x < y; x++) accbuffer[x] = 0.0f;

	int octave = 8;
	float scale = 0.5;
	while (octave < width)
	{
		addNoise( accbuffer, width, octave, scale);
		octave *= 2;
		scale *= 0.5;
	}
	
	float pole_value = (impress + bias > 0.5)? 0.5 * (impress + bias) : 0.0;
	
	for (y = 0; y < width; y++) for (x = 0; x < width; x++)
	{
		float q = q_factor( accbuffer, x, y, width, YES, pole_value, NO, 0.0, impress, bias);

		float yN = q_factor( accbuffer, x, y - 1, width, YES, pole_value, NO, 0.0, impress, bias);
		float yS = q_factor( accbuffer, x, y + 1, width, YES, pole_value, NO, 0.0, impress, bias);
		float yW = q_factor( accbuffer, x - 1, y, width, YES, pole_value, NO, 0.0, impress, bias);
		float yE = q_factor( accbuffer, x + 1, y, width, YES, pole_value, NO, 0.0, impress, bias);

		Vector norm = make_vector( 24.0 * (yW - yE), 24.0 * (yS - yN), 2.0);
		
		norm = unit_vector(&norm);
		
		GLfloat shade = powf( norm.z, 3.2);
		
		OOColor* color = [OOColor planetTextureColor:q:impress:bias :seaColor :paleSeaColor :landColor :paleLandColor];
		
		float red = [color redComponent];
		float green = [color greenComponent];
		float blue = [color blueComponent];
		
		red *= shade;
		green *= shade;
		blue *= shade;
		
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

void fillSquareImageWithPlanetNMap(unsigned char * imageBuffer, int width, int nplanes, float impress, float bias, float factor)
{
	if (nplanes != 4)
	{
		OOLog(@"textureStore.planetMap.failed", @"ERROR: fillSquareImageWithPlanetNMap() can only create textures with 4 planes.");
		return;
	}
	
	float accbuffer[width * width];
	int x, y;
	y = width * width;
	for (x = 0; x < y; x++) accbuffer[x] = 0.0f;

	int octave = 8;
	float scale = 0.5;
	while (octave < width)
	{
		addNoise( accbuffer, width, octave, scale);
		octave *= 2;
		scale *= 0.5;
	}
	
	float pole_value = (impress + bias > 0.5)? 0.5 * (impress + bias) : 0.0;
	
	for (y = 0; y < width; y++) for (x = 0; x < width; x++)
	{
		float yN = q_factor( accbuffer, x, y - 1, width, YES, pole_value, NO, 0.0, impress, bias);
		float yS = q_factor( accbuffer, x, y + 1, width, YES, pole_value, NO, 0.0, impress, bias);
		float yW = q_factor( accbuffer, x - 1, y, width, YES, pole_value, NO, 0.0, impress, bias);
		float yE = q_factor( accbuffer, x + 1, y, width, YES, pole_value, NO, 0.0, impress, bias);

		Vector norm = make_vector( factor * (yW - yE), factor * (yS - yN), 2.0);
		
		norm = unit_vector(&norm);
		
		norm.x = 0.5 * (norm.x + 1.0);
		norm.y = 0.5 * (norm.y + 1.0);
		norm.z = 0.5 * (norm.z + 1.0);
		
		imageBuffer[ 0 + 4 * (y * width + x) ] = 255 * norm.x;
		imageBuffer[ 1 + 4 * (y * width + x) ] = 255 * norm.y;
		imageBuffer[ 2 + 4 * (y * width + x) ] = 255 * norm.z;
		imageBuffer[ 3 + 4 * (y * width + x) ] = 255;// * q;				// alpha is heightmap
	}
}

@end
