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

#include "Entity.h"
#include "OOColor.h"
#include "OOPlanetEntity.h"
#include "legacy_random.h"
#include "oofnd/PList.hpp"
#include "oofnd/StdLib.hpp"

/*	The sun's system dictionary is an oo::PList and its name std::optional
   (nil stays nil).
*/

#define SUN_CORONA_SAMPLES \
  729  // Samples at half-degree intervals, with a bit of overlap.
#define MAX_CORONAFLARE 600000.0  // nova flare

#ifndef SUN_DIRECT_VISION_GLARE
#define SUN_DIRECT_VISION_GLARE 1
#endif

#if SUN_DIRECT_VISION_GLARE
#define SUN_GLARE_MULT_FACTOR 3.0
#define SUN_GLARE_ADD_FACTOR (M_PI / 16.0)
#define SUN_GLARE_CORONA_FACTOR 0.5f
#else
#define SUN_GLARE_CORONA_FACTOR 1.5
#endif

/*	The universe makes it with
   oo::makeRef<OOSunEntity>() and holds it as the C++ class; its
   OOStellarBody answers are members (OOStellarBodyRadius()).
*/
class OOSunEntity : public Entity {
 public:
  /*	-initSunWithColor:andDictionary:'s body after [super init] (the
     constructor ran Entity's), run on a new sun.
  */
  void initSunWithColor(OOColor* sun_color, const oo::PList& dict);
  bool setSunColor(OOColor* sun_color);
  bool changeSunProperty(const std::string& key, const oo::PList& dict);

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

  // OOStellarBody's name.
  std::optional<std::string> name();
  void setName(const std::optional<std::string>& name);

  std::optional<std::string> descriptionComponents() const override;
  bool canCollide() override;
#ifdef OO_DEBUG_MONITOR_ENABLED
  bool checkCloseCollisionWith(Entity* other) override;
#endif
  void update(OOTimeDelta delta_t) override;
  void drawImmediate(bool immediate, bool translucent) override;
  void updateCameraRelativePosition() override;
  void setPosition(HPVector posn) override;
  bool isSun() override;
  bool isVisible() override;

  // The binding's bodies (OOJSSun.mm).
  JSClassID jsClassID() override;
  std::optional<std::string> jsClassName() override;
  bool isVisibleToScripts() override;

 private:
  void calculateGLArrays(GLfloat inner_radius, GLfloat width,
                         GLfloat z_distance);
  void drawOpaqueParts();
  void drawTranslucentParts();

  GLfloat sun_diffuse[4] = {};
  GLfloat sun_specular[4] = {};

  GLfloat discColor[4] = {};
  GLfloat outerCoronaColor[4] = {};

  GLfloat cor16k = {}, lim16k = {};

  double corona_speed_factor =
      {};  // multiply delta_t by this before adding it to corona_stage
  double corona_stage = {};  // 0.0 -> 1.0
  GLfloat rvalue[SUN_CORONA_SAMPLES] =
      {};  // stores random values for adjusting colors in the corona
  float corona_blending = {};

  GLuint sunTriangles[3240 * 3] = {};
  GLfloat sunVertices[1801 * 3] = {};
  GLfloat sunColors[1801 * 4] = {};

  OOTimeDelta _novaCountdown = {};
  OOTimeDelta _novaExpansionTimer = {};
  float _novaExpansionRate = {};

  float _sunBrightnessFactor = {};
  float _sunCoronaAlphaFactor = {};

  std::optional<std::string> _name;  // nullopt: nil
};
