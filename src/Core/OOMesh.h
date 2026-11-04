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

#include "oofnd/PList.hpp"
#include "oofnd/Ref.hpp"
#include "oofnd/StdLib.hpp"

class OOMaterial;
struct VertexFaceRef;  // OOMesh.mm: the faces that use one vertex, while
                       // loading
class OOMeshBuffer;    // OOMesh.mm: one refcounted buffer (an oo::Data), shared
                       // by a mesh and its mutable copies

#define OOMESH_PROFILE 0
#if OOMESH_PROFILE
#include "OOProfilingStopwatch.h"
#endif

enum { kOOMeshMaxMaterials = 8 };

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
   loading, geometry and rendering. Its callers hold oo::Ref<OOMesh>.
*/
class OOMesh : public OODrawable, public OOGraphicsResetClient {
 public:
  static oo::Ref<OOMesh> meshWithName(
      const std::string& name, const std::optional<std::string>& cacheKey,
      const oo::PList& materialDict, const oo::PList& shadersDict, bool smooth,
      const oo::PList& macros, Entity* object);

  static oo::Ref<OOMesh> meshWithName(
      const std::string& name, const std::optional<std::string>& cacheKey,
      const oo::PList& materialDict, const oo::PList& shadersDict, bool smooth,
      const oo::PList& macros, Entity* object, float factor,
      bool cacheWriteable);

  static oo::Ref<OOMaterial> placeholderMaterial();

  OOMesh();
  OOMesh(const OOMesh&) = default;  // -mutableCopyWithZone:'s copy: every
                                    // member, the buffers shared
  ~OOMesh() override;

  oo::Ref<OOMesh> copyWithZone(OOZone* zone);
  oo::Ref<OOMesh> mutableCopyWithZone(OOZone* zone);

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
  std::vector<oo::Ref<OOTexture>> allTextures() override;
  size_t totalSize() override;
  size_t objectSize() const override { return sizeof *this; }
#endif

  oo::Ref<Octree> getOctree();  // -octree (the member octree is the octree)

  // This needs a better name.
  BoundingBox findBoundingBoxRelativeToPosition(Vector opv, Vector ri,
                                                Vector rj, Vector rk,
                                                Vector position, Vector si,
                                                Vector sj, Vector sk);
  BoundingBox findSubentityBoundingBoxWithPosition(Vector position,
                                                   OOMatrix rotMatrix);

  oo::Ref<OOMesh> meshRescaledBy(GLfloat scaleFactor);

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
  OOMaterial* materials[kOOMeshMaxMaterials] = {};  // retained
  GLuint displayList0 = {};

  // (named like the overridden getters, which a C++ member cannot be)
  GLfloat _collisionRadius = {};
  GLfloat _maxDrawDistance = {};
  BoundingBox _boundingBox = {};

  oo::Ref<Octree> octree;

  std::map<std::string, oo::Ref<OOMeshBuffer>, std::less<>>
      _retainedObjects;  // the buffers _vertices & co. point into, by key

  oo::PList _materialDict;  // mixed configurations; null = nil
  oo::PList _shadersDict;
  std::optional<std::string> _cacheKey;  // nil and @"" differ for OOMaterial
  oo::PList _shaderMacros;
  oo::WeakRef<Entity> _shaderBindingTarget =
      {};  // the entity, held weakly as its object's weak reference was

  Vector _lastPosition = {};
  OOMatrix _lastRotMatrix = {};
  BoundingBox _lastBoundingBox = {};

#if OO_MULTITEXTURE
  NSUInteger _textureUnitCount = {};
#endif

#if OOMESH_PROFILE
  oo::Ref<OOProfilingStopwatch> _stopwatch;
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
  void* allocateBytesWithSize(size_t size, NSUInteger count,
                              const std::string& key);

  // Allocate all per-vertex/per-face buffers.
  bool allocateVertexBuffersWithCount(NSUInteger count);
  bool allocateNormalBuffersWithCount(NSUInteger count);
  bool allocateFaceBuffersWithCount(NSUInteger count);
  bool allocateVertexArrayBuffersWithCount(NSUInteger count);

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
oo::Ref<Octree> OOCacheManagerOctreeForModel(const std::string& inKey);
// Caches the octree's representation under the key; a null octree does nothing.
void OOCacheManagerSetOctree(Octree* inOctree, const std::string& inKey);
