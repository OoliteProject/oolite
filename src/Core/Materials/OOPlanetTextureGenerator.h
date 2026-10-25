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

#ifndef OOPLANETTEXTUREGENERATOR_H
#define OOPLANETTEXTUREGENERATOR_H

#include "OOTextureGenerator.h"
#include "OOMaths.h"
#include "oofnd/PList.hpp"


class OOPlanetNormalMapGenerator;		// private to OOPlanetTextureGenerator.mm
class OOPlanetAtmosphereGenerator;


typedef struct OOPlanetTextureGeneratorInfo
{
	RANROTSeed						seed;
	
	unsigned						width;
	unsigned						height;
	
	// Planet parameters.
	float							landFraction;
	float							polarFraction;
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
	
	uint16_t						*permutations;
	
	unsigned						planetAspectRatio;
	unsigned						planetScaleOffset;
	BOOL							perlin3d;
} OOPlanetTextureGeneratorInfo;



/*	Phase 3 (bead oo-kyje, proposed ADR-0056 amendments oo-bj8 item 12, oo-fn2f, oo-novu, oo-rr2x
	item 3, oo-kvqq and oo-y3dd): a converted leaf of the texture generators, global, over
	OOTextureGenerator, with no facade of its own; so are the two helper generators private to
	its file. Its one caller (OOPlanetEntity) calls the static members; a texture takes the C++
	generator (it took the generators' facade until bead oo-9ht.118 deleted it).
*/
class OOPlanetTextureGenerator : public OOTextureGenerator
{
public:
	~OOPlanetTextureGenerator() override;	// was -dealloc

	/*	planetInfo is the planet's material parameters, a mixed configuration: plist values with the
		colours as PList::Object nodes holding OOColors (proposed ADR-0043 Amendment 2; the
		selector-family flip oo-3rb.269.2, which ended the id boundary of beads oo-lzk6 / oo-2pmp).
		Was [[OOPlanetTextureGenerator alloc] initWithPlanetInfo:seed:]; null where that answered
		nil (amendment oo-novu).
	*/
	static oo::Ref<OOPlanetTextureGenerator> generatorWithPlanetInfo(const oo::PList &planetInfo, RANROTSeed seed);
	bool initWithPlanetInfo(const oo::PList &planetInfo, RANROTSeed seed);	// false where it answered nil

	/*	Were +planetTextureWithInfo:seed: and the three +generatePlanetTexture:...; the textures are
		answered retained (amendment oo-2en item 2). The one that took a texture and an atmosphere
		(+generatePlanetTexture:andAtmosphere:withInfo:seed:) has its own name: its arguments have
		the types of the one that took a texture and a secondary texture.
	*/
	static oo::Ref<OOTexture> planetTextureWithInfo(const oo::PList &planetInfo, RANROTSeed seed);
	static bool generatePlanetTextureAndAtmosphere(oo::Ref<OOTexture> *texture, oo::Ref<OOTexture> *atmosphere, const oo::PList &planetInfo, RANROTSeed seed);
	static bool generatePlanetTexture(oo::Ref<OOTexture> *texture, oo::Ref<OOTexture> *secondaryTexture, const oo::PList &planetInfo, RANROTSeed seed);
	static bool generatePlanetTexture(oo::Ref<OOTexture> *texture, oo::Ref<OOTexture> *secondaryTexture, oo::Ref<OOTexture> *atmosphere, const oo::PList &planetInfo, RANROTSeed seed);

	std::optional<std::string> descriptionComponents() const override;
	uint32_t textureOptions() override;
	std::optional<std::string> cacheKey() override;

	/*	Was -getResult:format:width:height:, whose keywords are not the root's
		-getResult:format:originalWidth:originalHeight:, so it never overrode it and nothing sends it;
		kept, under a name that does not override getResult() either (amendment oo-y3dd).
	*/
	bool getResultFormatWidthHeight(OOPixMap *outData, OOTextureDataFormat *outFormat, uint32_t *outWidth, uint32_t *outHeight);

	void loadTexture() override;

private:
	std::optional<std::string> cacheKeyForType(const std::string &type);
	OOPlanetNormalMapGenerator *normalMapGenerator();	// Must be called before generator is enqueued for rendering.
	OOPlanetAtmosphereGenerator *atmosphereGenerator();	// Must be called before generator is enqueued for rendering.
	void dumpNoiseBuffer(float *noise);	// defined where the .mm's DEBUG_DUMP_RAW is set

	OOPlanetTextureGeneratorInfo	_info = {};
	unsigned						_planetScale = {};
	
	oo::Ref<OOPlanetNormalMapGenerator>		_nMapGenerator;
	oo::Ref<OOPlanetAtmosphereGenerator>	_atmoGenerator;
};

#endif	// OOPLANETTEXTUREGENERATOR_H
