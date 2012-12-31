/*

OOPlanetTextureGenerator.h

Generator for planet diffuse maps.


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

#import "OOTextureGenerator.h"
#import "OOMaths.h"

#define PERLIN_3D			0

@class OOPlanetNormalMapGenerator, OOPlanetAtmosphereGenerator;


typedef struct OOPlanetTextureGeneratorInfo
{
	RANROTSeed						seed;
	
	unsigned						width;
	unsigned						height;
	
	// Planet parameters.
	float							landFraction;
	FloatRGB						landColor;
	FloatRGB						seaColor;
	FloatRGB						deepSeaColor;
	FloatRGB						paleLandColor;
	FloatRGB						polarSeaColor;
	FloatRGB						paleSeaColor;
	
	// Planet mixing coefficients.
	float							mix_hi;
	float							mix_oh;
	float							mix_ih;
	float							mix_polarCap;
	
	// Atmosphere parameters.
	float							cloudAlpha;
	float							cloudFraction;
	FloatRGB						airColor;
	FloatRGB						cloudColor;
	FloatRGB						paleCloudColor;
	
	// Noise generation stuff.
	float							*fbmBuffer;
	float							*qBuffer;
	
#if PERLIN_3D
	uint16_t						*permutations;
#endif
} OOPlanetTextureGeneratorInfo;



@interface OOPlanetTextureGenerator: OOTextureGenerator
{
@private
	OOPlanetTextureGeneratorInfo	_info;
	unsigned						_planetScale;
	
	OOPlanetNormalMapGenerator		*_nMapGenerator;
	OOPlanetAtmosphereGenerator		*_atmoGenerator;
}


- (id) initWithPlanetInfo:(NSDictionary *)planetInfo;

+ (OOTexture *) planetTextureWithInfo:(NSDictionary *)planetInfo;
+ (BOOL) generatePlanetTexture:(OOTexture **)texture andAtmosphere:(OOTexture **)atmosphere withInfo:(NSDictionary *)planetInfo;
+ (BOOL) generatePlanetTexture:(OOTexture **)texture secondaryTexture:(OOTexture **)secondaryTexture withInfo:(NSDictionary *)planetInfo;
+ (BOOL) generatePlanetTexture:(OOTexture **)texture secondaryTexture:(OOTexture **)secondaryTexture andAtmosphere:(OOTexture **)atmosphere withInfo:(NSDictionary *)planetInfo;

@end
