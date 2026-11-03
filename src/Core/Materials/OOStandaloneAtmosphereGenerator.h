/*

OOStandaloneAtmosphereGenerator.h

Generator for planet atmospheres when the planet is using a
non-generated diffuse map.


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

#import "OOMaths.h"
#import "OOTextureGenerator.h"

typedef struct OOStandaloneAtmosphereGeneratorInfo {
    RANROTSeed seed;

    unsigned width;
    unsigned height;

    // Atmosphere parameters.
    float cloudAlpha;
    float cloudFraction;
    FloatRGB airColor;
    FloatRGB cloudColor;
    FloatRGB paleCloudColor;

    // Noise generation stuff.
    float* fbmBuffer;

    uint16_t* permutations;

    unsigned planetAspectRatio;
    unsigned planetScaleOffset;
    BOOL perlin3d;
} OOStandaloneAtmosphereGeneratorInfo;

@interface OOStandaloneAtmosphereGenerator : OOTextureGenerator {
@private
    OOStandaloneAtmosphereGeneratorInfo _info;
    unsigned _planetScale;
}

/*	Foundation sweep (proposed ADR-0043, bead oo-2pmp): planetInfo is the planet's material
        parameters, an Objective-C dictionary that holds OOColor objects (not a property list), so it
        stays id at this boundary and is never round-tripped through oo::PList.
*/
- (id)initWithPlanetInfo:(id)planetInfo seed:(RANROTSeed)seed; // Shared selector (proposed ADR-0043).

+ (OOTexture*)planetTextureWithInfo:(id)planetInfo seed:(RANROTSeed)seed; // Shared selector (proposed ADR-0043).
+ (BOOL)generateAtmosphereTexture:(OOTexture**)texture withInfo:(id)planetInfo seed:(RANROTSeed)seed;

@end
