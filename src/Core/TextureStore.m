/*

TextureStore.m

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

*/

#import "OOCocoa.h"
#import "OOOpenGL.h"

#import "ResourceManager.h"
#import "legacy_random.h"

#import "TextureStore.h"
#import "OOColor.h"
#import "OOMaths.h"
#import "OOTextureScaling.h"


static NSString * const kOOLogPlanetTextureGen = @"texture.planet.generate";


#ifdef M_PI
	#define PI M_PI	// C99, apparently
#else
	#define PI	3.1415926536
#endif

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
	// NSLog(@"TESTING: GL_MAX_TEXTURE_SIZE =  %d", max_texture_dimension);
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

+ (GLuint) getTextureNameFor:(NSString *)filename inFolder:(NSString*) foldername
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

	int					max_d = [TextureStore maxTextureDimension];

	int					texture_h = 4;
	int					texture_w = 4;
	int					image_h, image_w;
	int					n_planes, im_bytes, tex_bytes;

	int					im_bytesPerRow;

	int					texi = 0;

	NSMutableDictionary*	texProps = [NSMutableDictionary dictionaryWithCapacity:3];  // autoreleased
#ifndef GNUSTEP
	texImage = [ResourceManager imageNamed:filename inFolder: foldername];
#else
	texImage = [ResourceManager surfaceNamed:filename inFolder: foldername];
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
	
	texture_w = OORoundUpToPowerOf2(image_w);
	texture_h = OORoundUpToPowerOf2(image_h);

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
		ranrot_srand( 12345);
		fillRanNoiseBuffer();
		fillSquareImageWithPlanetTex( imageBuffer, texture_w, n_planes, 1.0f, -0.5f,
			[OOColor blueColor],
			[OOColor cyanColor],
			[OOColor greenColor],
			[OOColor yellowColor]);
	}

	if (([filename hasPrefix:@"normalgen"])&&(texture_w == image_w)&&(texture_h == image_h))
	{
		NSLog(@"DEBUG filling image data for %@ (%d x %d) with extra-special sauce!", filename, texture_w, texture_h);
		ranrot_srand( 12345);
		fillRanNoiseBuffer();
		fillSquareImageWithPlanetNMap( imageBuffer, texture_w, n_planes, 1.0f, -0.5f, 64.0f);
	}

	if ((texture_w > image_w)||(texture_h > image_h))	// we need to scale the image up to the texture dimensions
	{
		texBytes = ScaleUpPixMap(imageBuffer, image_w, image_h, im_bytesPerRow, n_planes, texture_w, texture_h);
		freeTexBytes = YES;
	}
	else
	{
		// no scaling required - we will use the image data directly
		texBytes = imageBuffer;
		freeTexBytes = NO;
	}

	if ((texture_w > max_d)||(texture_h > max_d))	// we need to scale the texture down to the maximum texture dimensions
	{
		NSLog(@"INFORMATION: texture '%@' is %d x %d - too large for this version of OpenGL, it will be scaled down.",
			filename, image_w, image_h);
		
		int tex_w = (texture_w > max_d)? max_d : texture_w;
		int tex_h = (texture_h > max_d)? max_d : texture_h;
		//
		unsigned char *texBytes2 = malloc( tex_w * tex_h * n_planes);
		//
		int x, y, n, ix, iy;
		//
		int sx = texture_w / tex_w;	// samples per x
		int sy = texture_h / tex_h;	// samples per x
		//
		float ds = 1.0f / (sx * sy);
		//
		texi = 0;
		//
		// do sample based scaling
		for ( y = 0; y < tex_h; y++)
		{
			for ( x = 0; x < tex_w; x++)
			{
				for (n = 0; n < n_planes; n++)
				{
					float acc = 0;
					for (iy = 0; iy < sy; iy++)	for (ix = 0; ix < sx; ix++)
						acc += ds * texBytes[ ((y * sy + iy) * texture_w + (x * sx + ix)) * n_planes + n ];
					//
					texBytes2[ texi++] = (char)acc;
				}
			}
		}
		//
		if (freeTexBytes)
			free((void*)texBytes);
		texBytes = texBytes2;
		texture_w = tex_w;
		texture_h = tex_h;
		//
	}

	glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
	glGenTextures(1, &texName);			// get a new unique texture name
	glBindTexture(GL_TEXTURE_2D, texName);

	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);	// adjust this
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);	// adjust this

	switch (n_planes)	// from the number of planes work out how to treat the image as a texture
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

	if (freeTexBytes) free(texBytes);

	// add to dictionary
	//
	[texProps setObject:[NSNumber numberWithInt:texName] forKey:@"texName"];
	[texProps setObject:[NSNumber numberWithInt:texture_w] forKey:@"width"];
	[texProps setObject:[NSNumber numberWithInt:texture_h] forKey:@"height"];

	if (!textureUniversalDictionary)
		textureUniversalDictionary = [[NSMutableDictionary dictionary] retain];

	[textureUniversalDictionary setObject:texProps forKey:filename];
	[textureUniversalDictionary setObject:filename forKey:[NSNumber numberWithInt:texName]];
	
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

#ifndef NO_SHADERS
//+ (GLuint) shaderProgramFromDictionary:(NSDictionary *) shaderDict
+ (GLhandleARB) shaderProgramFromDictionary:(NSDictionary *) shaderDict
{
	if ([shaderUniversalDictionary objectForKey:shaderDict])
		return (GLhandleARB)[(NSNumber*)[shaderUniversalDictionary objectForKey:shaderDict] unsignedIntValue];

	if (!shaderDict)
	{
		NSLog(@"ERROR: null dictionary passed to [TextureStore prepareShaderFDromDictionary:]");
		return 0;	// failed!
	}
	
	GLhandleARB fragment_shader_object = nil;
	GLhandleARB vertex_shader_object = nil;

	// check if we need to make a fragment shader
	if ([shaderDict objectForKey:@"glsl"])
	{
		GLhandleARB shader_object = glCreateShaderObjectARB(GL_FRAGMENT_SHADER_ARB);	// a fragment shader
		if (!shader_object)
		{
			NSLog(@"GLSL ERROR: could not create a fragment shader with glCreateShaderObjectARB()");
			return 0;	// failed!
		}
	
		NSString* glslSourceString = (NSString*)[shaderDict objectForKey:@"glsl"];
		const GLcharARB *fragment_string;
		fragment_string = [glslSourceString cString];
		glShaderSourceARB( shader_object, 1, &fragment_string, NULL);
	
		// compile the shader!
		glCompileShaderARB( shader_object);
		GLint result;
		glGetObjectParameterivARB( shader_object, GL_OBJECT_COMPILE_STATUS_ARB, &result);
		if (result != GL_TRUE)
		{
			char log[1024];
			GLsizei log_length;
			glGetInfoLogARB( shader_object, 1024, &log_length, log);
			NSLog(@"GLSL ERROR: shader code would not compile:\n%s\n\n%@\n\n", log, [shaderDict objectForKey:@"glsl"]);
			return 0;	// failed!
		}
		
		fragment_shader_object = shader_object;
	
	}
	else if ([shaderDict objectForKey:@"glsl-fragment"])
	{
		GLhandleARB shader_object = glCreateShaderObjectARB(GL_FRAGMENT_SHADER_ARB);	// a fragment shader
		if (!shader_object)
		{
			NSLog(@"GLSL ERROR: could not create a fragment shader with glCreateShaderObjectARB()");
			return 0;	// failed!
		}
	
		NSString* glslSourceString = (NSString*)[shaderDict objectForKey:@"glsl-fragment"];
		const GLcharARB *fragment_string;
		fragment_string = [glslSourceString cString];
		glShaderSourceARB( shader_object, 1, &fragment_string, NULL);

		// compile the shader!
		glCompileShaderARB( shader_object);
		GLint result;
		glGetObjectParameterivARB( shader_object, GL_OBJECT_COMPILE_STATUS_ARB, &result);
		if (result != GL_TRUE)
		{
			char log[1024];
			GLsizei log_length;
			glGetInfoLogARB( shader_object, 1024, &log_length, log);
			NSLog(@"GLSL ERROR: shader code would not compile:\n%s\n\n%@\n\n", log, [shaderDict objectForKey:@"glsl-fragment"]);
			return 0;	// failed!
		}
	
		fragment_shader_object = shader_object;
	}
	
	// check if we need to make a vertex shader
	if ([shaderDict objectForKey:@"glsl-vertex"])
	{
		GLhandleARB shader_object = glCreateShaderObjectARB(GL_VERTEX_SHADER_ARB);	// a vertex shader
		if (!shader_object)
		{
			NSLog(@"GLSL ERROR: could not create a vertex shader with glCreateShaderObjectARB()");
			return 0;	// failed!
		}
	
		NSString* glslSourceString = (NSString*)[shaderDict objectForKey:@"glsl-vertex"];
		const GLcharARB *vertex_string;
		vertex_string = [glslSourceString cString];
		glShaderSourceARB( shader_object, 1, &vertex_string, NULL);

		// compile the shader!
		glCompileShaderARB( shader_object);
		GLint result;
		glGetObjectParameterivARB( shader_object, GL_OBJECT_COMPILE_STATUS_ARB, &result);
		if (result != GL_TRUE)
		{
			char log[1024];
			GLsizei log_length;
			glGetInfoLogARB( shader_object, 1024, &log_length, log);
			NSLog(@"GLSL ERROR: shader code would not compile:\n%s\n\n%@\n\n", log, [shaderDict objectForKey:@"glsl-vertex"]);
			return 0;	// failed!
		}
		vertex_shader_object = shader_object;
	}
	
	if ((!fragment_shader_object)&&(!vertex_shader_object))
	{
		NSLog(@"GLSL ERROR: could not create any shaders from %@", shaderDict);
		return 0;	// failed!
	}

	// create a shader program
	GLhandleARB shader_program = glCreateProgramObjectARB();
	if (!shader_program)
	{
		NSLog(@"GLSL ERROR: could not create a shader program with glCreateProgramObjectARB()");
		return 0;	// failed!
	}
	
	// attach the shader objects
	if (vertex_shader_object)
	{
		glAttachObjectARB( shader_program, vertex_shader_object);
		glDeleteObjectARB( vertex_shader_object); /* Release */
	}
	if (fragment_shader_object)
	{
		glAttachObjectARB( shader_program, fragment_shader_object);
		glDeleteObjectARB( fragment_shader_object); /* Release */
	}
	
	// link the program
	glLinkProgramARB( shader_program);
	GLint result;
	glGetObjectParameterivARB( shader_program, GL_OBJECT_LINK_STATUS_ARB, &result);
	if (result != GL_TRUE)
	{
		char log[1024];
		GLsizei log_length;
		glGetInfoLogARB( shader_program, 1024, &log_length, log);
		NSLog(@"GLSL ERROR: shader program would not link:\n%s\n\n%@\n\n", log, shaderDict);
		return 0;	// failed!
	}

	// store the resulting program for reuse
	if (!shaderUniversalDictionary)
		shaderUniversalDictionary = [[NSMutableDictionary dictionary] retain];
	[shaderUniversalDictionary setObject: [NSNumber numberWithUnsignedInt: (unsigned int) shader_program] forKey: shaderDict];	
		
	return shader_program;
}
#endif

+ (void) reloadTextures
{
#ifdef WIN32
	int i;

	// Free up the texture image data from video memory. I assume this is a reasonable thing
	// to do for any platform, but just in case... stick it in a WIN32 only condition.
	NSArray *keys = [textureUniversalDictionary allKeys];
	for (i = 0; i < [keys count]; i++)
	{
		GLuint texName = [[(NSDictionary *)[textureUniversalDictionary objectForKey:[keys objectAtIndex:i]] objectForKey:@"texName"] intValue];
		NSLog(@"deleting texture #%d (%@)", texName, (NSString *)[keys objectAtIndex:i]);
		glDeleteTextures(1, &texName);
	}
#endif

	[textureUniversalDictionary removeAllObjects];
	return;
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
	glGenTextures(1, &texName);			// get a new unique texture name
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
	
	NSLog(@"genning normal map for land_fraction %.5f", land_fraction);
	
//	fillRanNoiseBuffer();
	fillSquareImageWithPlanetNMap( imageBuffer, texture_w, 4, 1.0, sea_bias, 24.0);

	texBytes = imageBuffer;

	glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
	glGenTextures(1, &texName);			// get a new unique texture name
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
	glGenTextures(1, &texName);			// get a new unique texture name
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
		NSLog(@"ERROR: fillSquareImageWithPlanetNMap() can only create textures with 4 planes.");
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
