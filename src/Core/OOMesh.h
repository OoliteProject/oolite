/*

OOMesh.h

Standard OODrawable for static meshes from DAT files. OOMeshes are immutable
(and can therefore be shared). Avoid the temptation to add externally-visible
mutator methods as it will break such sharing. (Sharing will be implemented
when ship types are turned into objects instead of dictionaries; this is
currently slated for post-1.70. -- Ahruman)

Hmm. On further consideration, sharing will be problematic because of material
bindings. Two possible solutions: separate mesh data into shared object with
each mesh instance having its own set of materials but shared data, or
retarget bindings each frame. -- Ahruman


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
#include "OOGraphicsResetManager.h"
#include "OOOpenGL.h"
#include "OOOpenGLExtensionManager.h"
class Entity;  // Entity.h: the shader binding target

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

#include "oofnd/PList.hpp"
#include "oofnd/Ref.hpp"

class OOMaterial;
struct VertexFaceRef;  // OOMesh.cpp: the faces that use one vertex, while
                       // loading
class OOMeshBuffer;  // OOMesh.cpp: one refcounted buffer (an oo::Data), shared
                     // by a mesh and its mutable copies

#define OOMESH_PROFILE 0
#if OOMESH_PROFILE
#include "OOProfilingStopwatch.h"
#endif

inline constexpr int kOOMeshMaxMaterials = 8;

typedef uint16_t OOMeshSmoothGroup;
typedef uint8_t OOMeshMaterialIndex, OOMeshMaterialCount;
typedef uint32_t OOMeshVertexCount;
typedef uint32_t OOMeshFaceCount;
typedef uint8_t OOMeshFaceVertexCount;

typedef struct {
  OOMeshSmoothGroup smoothGroup;
  OOMeshMaterialIndex materialIndex;
  GLuint vertex[3];

  Vector normal;
  Vector tangent;
  GLfloat s[3];
  GLfloat t[3];
} OOMeshFace;

typedef struct {
  GLint* indexArray;
  GLfloat* textureUVArray;
  Vector* vertexArray;
  Vector* normalArray;
  Vector* tangentArray;

  GLuint count;
} OOMeshDisplayLists;

class Octree;

/*	A mesh: the class shell, its factories, lifecycle and accessors,
   loading, geometry and rendering. Its callers hold std::shared_ptr<OOMesh>.
*/
class OOMesh : public OODrawable, public OOGraphicsResetClient {
 public:
  static std::shared_ptr<OOMesh> meshWithName(
      const std::string& name, const std::optional<std::string>& cacheKey,
      const oo::PList& materialDict, const oo::PList& shadersDict, bool smooth,
      const oo::PList& macros, Entity* object);

  static std::shared_ptr<OOMesh> meshWithName(
      const std::string& name, const std::optional<std::string>& cacheKey,
      const oo::PList& materialDict, const oo::PList& shadersDict, bool smooth,
      const oo::PList& macros, Entity* object, float factor,
      bool cacheWriteable);

  static std::shared_ptr<OOMaterial> placeholderMaterial();

  OOMesh();
  OOMesh(const OOMesh&) = default;  // -mutableCopyWithZone:'s copy: every
                                    // member, the buffers shared
  ~OOMesh() override;

  std::shared_ptr<OOMesh> copyWithZone(OOZone* zone);
  std::shared_ptr<OOMesh> mutableCopyWithZone(OOZone* zone);

  std::optional<std::string> modelName();

  oo::PList getMaterials();  // null: none (-materials; the member materials is
                             // the materials)
  oo::PList shaders();

  size_t getVertexCount();  // -vertexCount
  size_t getFaceCount();    // -faceCount

  // OODrawable
  bool hasOpaqueParts() override;
  GLfloat collisionRadius() override;
  GLfloat maxDrawDistance() override;
  void setBindingTarget(Entity* target) override;
  std::optional<std::string> descriptionComponents() const override;
#ifdef OO_DEBUG_MONITOR_ENABLED
  void dumpSelfState() override;
  std::vector<std::shared_ptr<OOTexture>> allTextures() override;
  size_t totalSize() override;
  size_t objectSize() const override { return sizeof *this; }
#endif

  std::shared_ptr<Octree>
  getOctree();  // -octree (the member octree is the octree)

  // This needs a better name.
  BoundingBox findBoundingBoxRelativeToPosition(Vector opv, Vector ri,
                                                Vector rj, Vector rk,
                                                Vector position, Vector si,
                                                Vector sj, Vector sk);
  BoundingBox findSubentityBoundingBoxWithPosition(Vector position,
                                                   OOMatrix rotMatrix);

  std::shared_ptr<OOMesh> meshRescaledBy(GLfloat scaleFactor);

  BoundingBox boundingBox() override;

  void renderOpaqueParts() override;

  void rebindMaterials();

  // OOGraphicsResetClient: the mesh registers itself once loaded, and
  // unregisters when destroyed.
  void resetGraphicsState() override;

  // Internal: the state, public while the test reads it.
  // Zero, as class_createInstance left the ivars.
  uint8_t _normalMode : 2 = 0, brokenInRender : 1 = 0, listsReady : 1 = 0;

  OOMeshMaterialCount materialCount = {};
  OOMeshVertexCount vertexCount = {};
  OOMeshFaceCount faceCount = {};

  std::optional<std::string>
      baseFile;  // "No Model" until loaded; nullopt after -rescaleByFactor: (no
                 // octree cache)
  std::optional<std::string> baseFileOctreeCacheRef;
  bool _cacheWriteable = {};

  Vector* _vertices = {};
  Vector* _normals = {};
  Vector* _tangents = {};
  OOMeshFace* _faces = {};

  // Redundancy! Needs fixing.
  OOMeshDisplayLists _displayLists = {};

  NSRange triangle_range[kOOMeshMaxMaterials] = {};
  std::string materialKeys[kOOMeshMaxMaterials];
  std::shared_ptr<OOMaterial> materials[kOOMeshMaxMaterials];  // shared
  GLuint displayList0 = {};

  // (named like the overridden getters, which a C++ member cannot be)
  GLfloat _collisionRadius = {};
  GLfloat _maxDrawDistance = {};
  BoundingBox _boundingBox = {};

  std::shared_ptr<Octree> octree;

  std::map<std::string, std::shared_ptr<OOMeshBuffer>, std::less<>>
      _retainedObjects;  // the buffers _vertices & co. point into, by key

  oo::PList _materialDict;  // mixed configurations; null = nil
  oo::PList _shadersDict;
  std::optional<std::string> _cacheKey;  // nil and @"" differ for OOMaterial
  oo::PList _shaderMacros;
  std::weak_ptr<Entity> _shaderBindingTarget =
      {};  // the entity, held weakly as its object's weak reference was

  Vector _lastPosition = {};
  OOMatrix _lastRotMatrix = {};
  BoundingBox _lastBoundingBox = {};

#if OO_MULTITEXTURE
  std::size_t _textureUnitCount = {};
#endif

#if OOMESH_PROFILE
  std::shared_ptr<OOProfilingStopwatch> _stopwatch;
  double _stopwatchLastTime = {};
#endif

  // Internal: geometry, which the loading calls.
  void checkNormalsAndAdjustWinding();
  void generateFaceTangents();
  void calculateVertexNormalsAndTangentsWithFaceRefs(VertexFaceRef* faceRefs);
  void calculateVertexTangentsWithFaceRefs(VertexFaceRef* faceRefs);
  void getNormal(Vector* outNormal, Vector* outTangent,
                 OOMeshVertexCount v_index, OOMeshSmoothGroup smoothGroup);
  void calculateBoundingVolumes();
  void rescaleByFactor(GLfloat factor);

  // Internal: buffers and display lists, which the loading and the destructor
  // call.
  void deleteDisplayLists();
  bool setUpVertexArrays();

  // Manage the set of refcounted buffers we need to hang on to.
  void setRetainedObject(oo::Data object, const std::string& key);
  void* allocateBytesWithSize(size_t size, std::size_t count,
                              const std::string& key);

  // Allocate all per-vertex/per-face buffers.
  bool allocateVertexBuffersWithCount(std::size_t count);
  bool allocateNormalBuffersWithCount(std::size_t count);
  bool allocateFaceBuffersWithCount(std::size_t count);
  bool allocateVertexArrayBuffersWithCount(std::size_t count);

  void renameTexturesFrom(const std::string& from, const std::string& to);

 private:
  // Loading.
  bool initWithName(const std::string& name,
                    const std::optional<std::string>& cacheKey,
                    const oo::PList& materialDict, const oo::PList& shadersDict,
                    bool smooth, const oo::PList& macros, Entity* target,
                    float scale, bool cacheWriteable);
  bool loadData(const std::string& filename, float scale);
  oo::PList modelData();  // null: incomplete
  bool setModelFromModelData(const oo::PList& dict,
                             const std::string& fileName);

#ifdef OO_DEBUG_MONITOR_ENABLED
  void debugDrawNormals();
#endif
  unsigned octreeDepth();
  bool suppressClangStuff();
};

// The OOCacheManager (Octree) category, as free functions next to the cache.
// The octree cached for a model key, made afresh from its representation; null
// when none.
std::shared_ptr<Octree> OOCacheManagerOctreeForModel(const std::string& inKey);
// Caches the octree's representation under the key; a null octree does nothing.
void OOCacheManagerSetOctree(Octree* inOctree, const std::string& inKey);
