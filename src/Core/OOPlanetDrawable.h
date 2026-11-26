/*

OOPlanetDrawable.h

Draw a ball, such as might be used to represent a planet.

A class derived from the drawable root OODrawable. It keeps its material
retained, as an oo::Ref<OOMaterial>.

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

#include "OODrawable.h"
#include "OOMaterial.h"
#include "OOMaths.h"
#include "oofnd/Ref.hpp"
#include "oofnd/StdLib.hpp"

class OOPlanetDrawable : public OODrawable {
 public:
  static oo::Ref<OOPlanetDrawable> planetWithTextureName(
      const std::string& textureName, float radius);
  static oo::Ref<OOPlanetDrawable> atmosphereWithRadius(float radius);

  // -init's body.
  OOPlanetDrawable();

  // -initAsAtmosphere: a new drawable that draws an atmosphere.
  static oo::Ref<OOPlanetDrawable> initAsAtmosphere();

  // -copy (OOCopying's -copyWithZone:): a new drawable with this one's
  // material, kind, radius, transform and level of detail.
  oo::Ref<OOPlanetDrawable> copy();

  OOMaterial* material();
  void setMaterial(OOMaterial* material);

  // The material's name (nullopt when it has none, as nil was).
  std::optional<std::string> textureName();
  void setTextureName(const std::string& textureName);

  // Radius, in game metres.
  float radius();
  void setRadius(float radius);

  // Level of detail, [0..1]. Granularity is implementation-defined.
  float levelOfDetail();
  void setLevelOfDetail(float lod);
  void calculateLevelOfDetailForViewDistance(float distance);

  // depth-buffer hack
  void renderTranslucentPartsOnOpaquePass();

  void renderOpaqueParts() override;
  void renderTranslucentParts() override;
  bool hasOpaqueParts() override;
  bool hasTranslucentParts() override;
#ifdef OO_DEBUG_MONITOR_ENABLED
  size_t objectSize() const override { return sizeof *this; }
#endif
  GLfloat collisionRadius() override;
  GLfloat maxDrawDistance() override;
  BoundingBox boundingBox() override;
  void setBindingTarget(Entity* target) override;
  void dumpSelfState() override;
#ifdef OO_DEBUG_MONITOR_ENABLED
  std::vector<oo::Ref<OOTexture>> allTextures() override;
#endif

 private:
  void recalculateTransform();
#ifdef OO_DEBUG_MONITOR_ENABLED
  void debugDrawNormals();
#endif
  void renderCommonParts();

  oo::Ref<OOMaterial> _material;
  bool _isAtmosphere = false;
  float _radius = {};
  OOMatrix _transform = {};
  unsigned _lod = {};
};
