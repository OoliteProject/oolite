/*

OOSunEntity.h

Entity subclass representing a sun.

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


#pragma once

#include "OOPlanetEntity.h"

#include "Entity.h"
#include "legacy_random.h"
#include "OOColor.h"

#include "oofnd/StdLib.hpp"
#include "oofnd/PList.hpp"

/*	Foundation sweep (proposed ADR-0043, bead oo-hach): the sun's system dictionary is an oo::PList
	and its name std::optional (nil stays nil): -cxx_name / -cxx_setName: (the id -name / -setName:
	retired with oo-qps.44).
*/


#define SUN_CORONA_SAMPLES		729			// Samples at half-degree intervals, with a bit of overlap.
#define MAX_CORONAFLARE			600000.0	// nova flare

#ifndef	SUN_DIRECT_VISION_GLARE
#define	SUN_DIRECT_VISION_GLARE	1
#endif

#if SUN_DIRECT_VISION_GLARE
#define SUN_GLARE_MULT_FACTOR 3.0
#define SUN_GLARE_ADD_FACTOR (M_PI/16.0)
#define SUN_GLARE_CORONA_FACTOR 0.5f
#else
#define SUN_GLARE_CORONA_FACTOR 1.5
#endif


/*	C++ only since bead oo-9ht.111 deleted its Objective-C facade (ADR-0056 amendments oo-9ht.12,
	oo-9ht.107): the universe makes it with oo::makeRef<OOSunEntity>(), hands it to Objective-C
	with oo::NewEntityFacade (its object is the root Entity's facade) and holds it as the C++ class;
	its OOStellarBody answers are members (OOStellarBodyRadius() asks them for an Objective-C object).
*/
class OOSunEntity : public Entity
{
public:
	/*	-initSunWithColor:andDictionary:'s body after [super init] (the constructor ran Entity's),
		run on a new sun (the facade ran it once it held this object until bead oo-9ht.111).
	*/
	void initSunWithColor(OOColor *sun_color, const oo::PList &dict);
	bool setSunColor(OOColor *sun_color);
	bool changeSunProperty(const std::string &key, const oo::PList &dict);

	OOStellarBodyType planetType();

	void getDiffuseComponents(GLfloat components[4]);
	void getSpecularComponents(GLfloat components[4]);

	double radius();
	void setRadius(GLfloat rad, GLfloat corona);

	bool willGoNova();
	bool goneNova();
	void setGoingNova(bool yesno, double interval);

	void drawStarGlare();
	void drawDirectVisionSunGlare();
	void resetNova();

	// OOStellarBody's name (-cxx_name / -cxx_setName:), which the facade answered until bead oo-9ht.111.
	std::optional<std::string> name();
	void setName(const std::optional<std::string> &name);

	std::optional<std::string> descriptionComponents() const override;
	bool canCollide() override;
#ifndef NDEBUG
	bool checkCloseCollisionWith(Entity *other) override;
#endif
	void update(OOTimeDelta delta_t) override;
	void drawImmediate(bool immediate, bool translucent) override;
	void updateCameraRelativePosition() override;
	void setPosition(HPVector posn) override;
	bool isSun() override;
	bool isVisible() override;

	// The binding's bodies (OOJSSun.mm), which the facade forwarded to until bead oo-9ht.111.
	void getJSClass(ooscript::ClassDef **outClass, ooscript::Object *outPrototype) override;
	std::optional<std::string> jsClassName() override;
	bool isVisibleToScripts() override;

private:
	void calculateGLArrays(GLfloat inner_radius, GLfloat width, GLfloat z_distance);
	void drawOpaqueParts();
	void drawTranslucentParts();

	GLfloat					sun_diffuse[4] = {};
	GLfloat					sun_specular[4] = {};

	GLfloat					discColor[4] = {};
	GLfloat					outerCoronaColor[4] = {};

	GLfloat					cor16k = {}, lim16k = {};

	double					corona_speed_factor = {};		// multiply delta_t by this before adding it to corona_stage
	double					corona_stage = {};				// 0.0 -> 1.0
	GLfloat					rvalue[SUN_CORONA_SAMPLES] = {};	// stores random values for adjusting colors in the corona
	float					corona_blending = {};

	GLuint         sunTriangles[3240*3] = {};
	GLfloat sunVertices[1801*3] = {};
	GLfloat sunColors[1801*4] = {};

	OOTimeDelta				_novaCountdown = {};
	OOTimeDelta				_novaExpansionTimer = {};
	float					_novaExpansionRate = {};

	float					_sunBrightnessFactor = {};
	float					_sunCoronaAlphaFactor = {};

	std::optional<std::string>	_name;	// nullopt: nil
};



