/*

OOPlanetTextureGenerator.h

Generator for planet diffuse maps.


Oolite
Copyright (C) 2004-2009 Giles C Williams and contributors

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

@class OOPlanetNormalMapGenerator, OOPlanetAtmosphereGenerator;


@interface OOPlanetTextureGenerator: OOTextureGenerator
{
@private
	float						_landFraction;
	FloatRGB					_landColor;
	FloatRGB					_seaColor;
	FloatRGB					_polarLandColor;
	FloatRGB					_polarSeaColor;
	
	float						_cloudAlpha;
	float						_cloudFraction;
	FloatRGB					_airColor;
	FloatRGB					_cloudColor;
	FloatRGB					_polarAirColor;
	FloatRGB					_polarCloudColor;
	
	RANROTSeed					_seed;
	OOPlanetNormalMapGenerator	*_nMapGenerator;
	OOPlanetAtmosphereGenerator	*_atmoGenerator;
	OOUInteger					_planetScale;
}

- (id) initWithPlanetInfo:(NSDictionary *)planetInfo;

+ (OOTexture *) planetTextureWithInfo:(NSDictionary *)planetInfo;
+ (BOOL) generatePlanetTexture:(OOTexture **)texture andAtmosphere:(OOTexture **)atmosphere withInfo:(NSDictionary *)planetInfo;
+ (BOOL) generatePlanetTexture:(OOTexture **)texture secondaryTexture:(OOTexture **)secondaryTexture withInfo:(NSDictionary *)planetInfo;
+ (BOOL) generatePlanetTexture:(OOTexture **)texture secondaryTexture:(OOTexture **)secondaryTexture andAtmosphere:(OOTexture **)atmosphere withInfo:(NSDictionary *)planetInfo;

@end
