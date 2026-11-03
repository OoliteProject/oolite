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

#ifndef OOSTANDALONEATMOSPHEREGENERATOR_H
#define OOSTANDALONEATMOSPHEREGENERATOR_H

#include "OOMaths.h"
#include "OOTextureGenerator.h"
#include "oofnd/PList.hpp"

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

/*	Phase 3 (bead oo-y3dd, proposed ADR-0056 amendments oo-bj8 item 12, oo-2c6g item 2, oo-novu,
        oo-rr2x item 3 and oo-kvqq): a converted leaf of the texture generators, global, over
        OOTextureGenerator, with no facade of its own. Its one caller (OOPlanetEntity) calls the
        static members; the texture takes the C++ generator (the generators' facade until bead oo-9ht.118).
*/
class OOStandaloneAtmosphereGenerator : public OOTextureGenerator {
public:
    /*	planetInfo is the planet's material parameters, a mixed configuration: plist values with the
            colours as PList::Object nodes holding OOColors (proposed ADR-0043 Amendment 2; the
            selector-family flip oo-3rb.269.2, which ended the id boundary of beads oo-lzk6 / oo-2pmp).
            Was [[OOStandaloneAtmosphereGenerator alloc] initWithPlanetInfo:seed:]; null where that
            answered nil (amendment oo-novu).
    */
    static oo::Ref<OOStandaloneAtmosphereGenerator> generatorWithPlanetInfo(const oo::PList& planetInfo, RANROTSeed seed);
    bool initWithPlanetInfo(const oo::PList& planetInfo, RANROTSeed seed); // false where it answered nil

    // Were +planetTextureWithInfo:seed: and +generateAtmosphereTexture:withInfo:seed:; the texture
    // is answered retained (amendment oo-2en item 2).
    static oo::Ref<OOTexture> planetTextureWithInfo(const oo::PList& planetInfo, RANROTSeed seed);
    static bool generateAtmosphereTexture(oo::Ref<OOTexture>* texture, const oo::PList& planetInfo, RANROTSeed seed);

    std::optional<std::string> descriptionComponents() const override;
    uint32_t textureOptions() override;
    std::optional<std::string> cacheKey() override;

    /*	Was -getResult:format:width:height:, whose keywords are not the root's
            -getResult:format:originalWidth:originalHeight:, so it never overrode it and nothing sends it;
            kept, under a name that does not override getResult() either.
    */
    bool getResultFormatWidthHeight(OOPixMap* outData, OOTextureDataFormat* outFormat, uint32_t* outWidth, uint32_t* outHeight);

    void loadTexture() override;

private:
    void dumpNoiseBuffer(float* noise); // defined where the .mm's DEBUG_DUMP_RAW is set

    OOStandaloneAtmosphereGeneratorInfo _info = { };
    unsigned _planetScale = { };
};

#endif // OOSTANDALONEATMOSPHEREGENERATOR_H
