/*

TextureStore.h

Singleton responsible for loading, binding and caching textures.

Legacy class, used only by PlanetEntity. Use OOTexture or OOMaterial for any
new development.


Oolite
Copyright (C) 2004-2012 Giles C Williams and contributors

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

// TextureStore is only used for old planets.
#import "OOStellarBody.h"
#if !NEW_PLANETS

#import "OOCocoa.h"
#import "OOOpenGL.h"


@class OOColor;


@interface TextureStore: NSObject

// routines to create textures...
+ (BOOL) getPlanetTextureNameFor:(NSDictionary *)planetInfo
						intoData:(unsigned char **)textureData
						   width:(GLuint *)textureWidth
						  height:(GLuint *)textureHeight;
+ (BOOL) getCloudTextureNameFor:(OOColor *)color :(GLfloat)impress :(GLfloat)bias
					   intoData:(unsigned char **)textureData
						  width:(GLuint *)textureWidth
						 height:(GLuint *)textureHeight;

@end


void fillRanNoiseBuffer();


#endif	// !NEW_PLANETS
