/*

OOPlanetEntity.h

Entity subclass representing a planet.

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

#include <algorithm>
#include <chrono>
#include <condition_variable>
#include <cstddef>
#include <cstdint>
#include <functional>
#include <map>
#include <memory>
#include <mutex>
#include <optional>
#include <set>
#include <string>
#include <string_view>
#include <unordered_map>
#include <unordered_set>
#include <utility>
#include <vector>

#include "Entity.h"
#include "OOColor.h"
#include "OOGraphicsResetManager.h"
#include "OOStellarBody.h"
#include "legacy_random.h"
#include "oofnd/Object.hpp"
#include "oofnd/PList.hpp"

/*	The planet configuration and material parameters are oo::PLists (mixed:
   colours are PList::Object nodes); texture and planet names are std::optional
   (nullopt where they were nil).
*/

class OOMaterial;
class OOTexture;
class ShipEntity;
class OOPlanetDrawable;  // this class is its one caller

/*	The universe and the legacy scripts make it with
   oo::makeShared<OOPlanetEntity>() and hold it as
   the C++ class. Its OOStellarBody answers are members (OOStellarBodyRadius()),
   and the shader binding names are answered for a planet only
   (OOEntityCalledByName.cpp).
*/
class OOPlanetEntity : public Entity, public ::OOGraphicsResetClient {
 public:
  ~OOPlanetEntity() override;  // unregisters the graphics reset client

  /*	The initialisers' bodies after [self init] (the constructor ran
     Entity's), run on a new planet once its object is made.
  */
  void initAsMainPlanetForSystem(OOSystemID s);
  void initFromDictionary(const oo::PList& dict, bool atmosphere,
                          Random_Seed seed, OOSystemID systemID);

  std::shared_ptr<OOPlanetEntity> miniatureVersion();

  double rotationalVelocity();
  void setRotationalVelocity(double v);

  bool planetHasStation();
  void launchShuttle();
  void welcomeShuttle(::ShipEntity* shuttle);

  bool hasAtmosphere();

  // FIXME: need material model.
  std::optional<std::string> textureFileName();  // nullopt: none
  void setTextureFileName(const std::optional<std::string>& textureName);

  bool setUpPlanetFromTexture(
      const std::optional<std::string>& fileName);  // nullopt: none

  // The drawables' materials, as the drawables keep them.
  OOMaterial* material();
  OOMaterial* atmosphereMaterial();
  OOMaterial* atmosphereShaderMaterial();

  bool isFinishedLoading();

  Vector airColorAsVector();  // visible to shader bindings
  OOColor* airColor();
  void setAirColor(OOColor* newColor);
  Vector illuminationColorAsVector();  // visible to shader bindings
  OOColor* illuminationColor();
  void setIlluminationColor(OOColor* newColor);
  float airColorMixRatio();  // visible to shader bindings
  void setAirColorMixRatio(float newRatio);
  float airDensity();  // visible to shafer bindings
  void setAirDensity(float newDensity);

  void setTerminatorThresholdVector(Vector newTerminatorThresholdVector);
  Vector terminatorThresholdVector();  // visible to shader bindings

  // OOStellarBody.
  double radius();
  OOStellarBodyType planetType();
  std::optional<std::string> name();
  void setName(const std::optional<std::string>& name);

  // OOGraphicsResetClient: the planet registers itself once set up.
  void resetGraphicsState() override;

  std::optional<std::string> descriptionComponents() const override;
  void setOrientation(Quaternion quat) override;
  void update(OOTimeDelta delta_t) override;
  void drawImmediate(bool immediate, bool translucent) override;
  bool checkCloseCollisionWith(Entity* other) override;
  bool isPlanet() override;
  bool isVisible() override;

  // The binding's bodies (OOJSPlanet.cpp).
  JSClassID jsClassID() override;
  std::optional<std::string> jsClassName() override;
  bool isVisibleToScripts() override;

 private:
  bool initAsMiniatureVersionOfPlanet(OOPlanetEntity* planet);

  void setUpTerrainParametersWithSourceInfo(const oo::PList& sourceInfo,
                                            oo::PList& targetInfo);
  void setUpLandParametersWithSourceInfo(const oo::PList& sourceInfo,
                                         oo::PList& targetInfo);
  void setUpAtmosphereParametersWithSourceInfo(const oo::PList& sourceInfo,
                                               oo::PList& targetInfo);
  void setUpColorParametersWithSourceInfo(const oo::PList& sourceInfo,
                                          oo::PList& targetInfo,
                                          bool isAtmosphere);
  void setUpTypeParametersWithSourceInfo(const oo::PList& sourceInfo,
                                         oo::PList& targetInfo);

  std::shared_ptr<OOPlanetDrawable> _planetDrawable;
  std::shared_ptr<OOPlanetDrawable> _atmosphereDrawable;
  std::shared_ptr<OOPlanetDrawable> _cloudsShaderDrawable;
  std::shared_ptr<OOPlanetDrawable> _atmosphereShaderDrawable;

  bool _miniature = false;
  std::shared_ptr<OOColor> _airColor;
  std::shared_ptr<OOColor> _illuminationColor;
  float _airColorMixRatio = {};
  float _airDensity = {};
  double _mesopause2 = {};

  Vector _rotationAxis = {};
  float _rotationalVelocity = {};
  Quaternion _atmosphereOrientation = {};
  float _atmosphereRotationalVelocity = {};

  Vector _terminatorThresholdVector = {};

  unsigned _shuttlesOnGround = {};
  OOTimeDelta _lastLaunchTime = {};
  OOTimeDelta _shuttleLaunchInterval = {};

  oo::PList _materialParameters;  // null where it was nil
  std::optional<std::string> _textureName;
  std::optional<std::string> _normSpecMapName;

  std::optional<std::string> _name;

  // The texture generators' noise seed, handed to them directly; was a value
  // box under "noise_map_seed" in planetInfo / _materialParameters.
  RANROTSeed _noiseMapSeed = {};
};
