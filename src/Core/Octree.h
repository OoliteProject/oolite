/*

Octree.h

Octtree class for collision detection.

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

#include "OOFoundation.h"
#include "OOMaths.h"
#include "OOOpenGL.h"
#include "oofnd/PList.hpp"
#include "oofnd/Ref.hpp"
#include "oofnd/objc/OOObject.h"

#define OCTREE_MIN_HALF_WIDTH 1.0

#if !defined(OODEBUGLDRAWING_DISABLE) && !defined(OO_DEBUG_MONITOR_ENABLED)
#define OODEBUGLDRAWING_DISABLE 1
#endif

class OOOctreeBuilder;
struct Octree_details;

class Octree : public oo::RefCounted {
 public:
  /*
          initWithDictionary()

          Deserialize an octree from cache representation; null if it is not a
     valid one. (To make a new octree, build it with OOOctreeBuilder.)
  */
  static oo::Ref<Octree> initWithDictionary(const oo::PList& dictionary);

  oo::Ref<Octree> octreeScaledBy(GLfloat factor);

#ifndef OODEBUGLDRAWING_DISABLE
  void drawOctree();
  void drawOctreeCollisions();
#endif

  GLfloat isHitByLine(Vector v0, Vector v1);

  bool isHitByOctree(Octree* other, Vector origin, Triangle ijk);
  bool isHitByOctree(Octree* other, Vector origin, Triangle ijk, GLfloat s1,
                     GLfloat s2);

  oo::PList
  dictionaryRepresentation();  // the cache representation: a dictionary

  GLfloat volume();

  Vector randomPoint();

#ifdef OO_DEBUG_MONITOR_ENABLED
  size_t totalSize();
#endif

  ~Octree() override;

 private:
  friend class ::OOOctreeBuilder;

  Octree(const oo::Data& data,
         GLfloat radius);  // -initWithData:radius:, less its failure
  static oo::Ref<Octree> initWithData(
      const oo::Data& data, GLfloat radius);  // Designated initializer.

#ifndef OODEBUGLDRAWING_DISABLE
  void drawOctreeFromLocation(uint32_t loc, GLfloat scale, Vector offset);
  void drawOctreeCollisionFromLocation(uint32_t loc, GLfloat scale,
                                       Vector offset);
#endif

  bool hasCollision();
  void setHasCollision(bool value);

  Octree_details octreeDetails();

  GLfloat _radius = {};
  uint32_t _nodeCount = {};
  const int* _octree = {};
  bool _hasCollision = {};

  unsigned char* _collisionOctree = {};

  oo::Data _data;
};

enum {
  kMaxOctreeDepth = 7  // 128x128x128
};

class OOOctreeBuilder : public oo::RefCounted {
 public:
  OOOctreeBuilder();  // -init; raises OOMallocException if it cannot allocate
  ~OOOctreeBuilder() override;

  /*
          buildOctreeWithRadius()

          Generate an octree with the current data in the builder and the
     specified radius, and clear the builder. If NDEBUG is undefined, throws an
     exception if the structure of the octree is invalid.
  */
  oo::Ref<Octree> buildOctreeWithRadius(GLfloat radius);

  /*
          Append nodes to the octree.

          There are three types of nodes: solid, empty, and inner nodes.
          An inner node must have exactly eight children, which may be any type
     of node. Exactly one node must be added at root level.

          The order of child nodes is defined as follows: the index of a child
     node is a three bit number. The highest bit represents x, the middle bit
          represents y and the low bit represents z. A set bit indicates the
     high- coordinate half of the parent node, and a clear bit indicates the
     low- coordinate half.

          For instance, if the parent node is a cube ranging from -1 to 1 on
     each axis, the child 101 (5) represents x 0..1, y -1..0, z 0..1.
  */
  void writeSolid();
  void writeEmpty();
  void beginInnerNode();
  void endInnerNode();

 private:
  struct OOOctreeBuildState {
    uint32_t insertionPoint;
    uint32_t remaining;
  };

  // The file-static helpers that read the builder's state.
  static OOOctreeBuildState* State(OOOctreeBuilder* self);
  static void SetNode_slow(OOOctreeBuilder* self, uint32_t index,
                           int value) NO_INLINE_FUNC;
  static void SetNode(OOOctreeBuilder* self, uint32_t index, int value);
  static void InsertNode(OOOctreeBuilder* self, int value);

  int* _octree = {};
  uint32_t _nodeCount = {}, _capacity = {};
  OOOctreeBuildState _stateStack[kMaxOctreeDepth + 1] = {};
  uint8_t _level = {};
};
