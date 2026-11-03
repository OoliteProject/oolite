/*

OOMesh.m

A note on memory management:
The dynamically-sized buffers used by OOMesh (_vertex etc) are the byte arrays
of refcounted OOMeshBuffers (one oo::Data each), which are tracked using the
_retainedObjects map. This simplifies the implementation of -dealloc, but more
importantly, it means bytes are refcounted and shared by a mesh and its mutable
copies. (Bytes read from the cache are copied into a buffer of their own.)

Since _retainedObjects is a map its members can be replaced,
potentially allowing mutable meshes, although we have no use for this at
present.


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

#include "OOMesh.h"
#include "Entity.h" // for NO_DRAW_DISTANCE_FACTOR.
#include "OOBasicMaterial.h"
#include "OOCacheManager.h"
#include "OODebugFlags.h"
#include "OODebugGLDrawing.h"
#include "OOGraphicsResetManager.h"
#include "OOMacroOpenGL.h"
#include "OOMaterialConvenienceCreators.h"
#include "OOMeshToOctreeConverter.h"
#include "OOOpenGLExtensionManager.h"
#include "OOProfilingStopwatch.h"
#include "OOShaderMaterial.h"
#include "Octree.h"
#include "ResourceManager.h"
#include "Universe.h"

#include "OODebugStandards.h"
#include "OOJavaScriptEngine.h"
#include "oofnd/Log.hpp"
#include "oofnd/Scanner.hpp"
#include "oofnd/String.hpp"
#include "oofnd/objc/OOAssert.h"
#include "oofnd/objc/OOException.h"
#include <cstring>

// If set, collision octree depth varies depending on the size of the mesh.
#define ADAPTIVE_OCTREE_DEPTH 1

// If set, cachable memory is scribbled with FEEDFACE to identify junk in cache.
#define SCRIBBLE 0

enum {
    kBaseOctreeDepth = 5, // 32x32x32
    //	kMaxOctreeDepth declared in Octree.h.
    kSmallOctreeDepth = 4, // 16x16x16
    kOctreeSizeThreshold = 900, // Size at which we start increasing octree depth
    kOctreeSmallSizeThreshold = 20
};

typedef enum {
    kNormalModePerFace,
    kNormalModeSmooth,
    kNormalModeExplicit
} OOMeshNormalMode;

static const char* const kOOLogMeshDataNotFound = "mesh.load.failed.fileNotFound"; // an OO_LOG message class
static const char* const kOOLogMeshTooManyMaterials = "mesh.load.failed.tooManyMaterials";

#if OOMESH_PROFILE
#define PROFILE(tag)                                                             \
    do {                                                                         \
        _stopwatchLastTime = Profile(tag, _stopwatch.get(), _stopwatchLastTime); \
    } while (0)
static OOTimeDelta Profile(const char* tag, OOProfilingStopwatch* stopwatch, OOTimeDelta lastTime)
{
    OOTimeDelta now = stopwatch->currentTime();
    OO_LOG("mesh.profile", "Mesh profile: stage {}, {:g} seconds (delta {:g})", tag, now, now - lastTime);
    return now;
}
#else
#define PROFILE(tag) \
    do {             \
    } while (0)
#endif

/*	VertexFaceRef
        List of indices of faces used by a given vertex.
        Always access using the provided functions.

        The overflow list is a std::vector owned by the VertexFaceRef, which lives in
        a std::vector for the duration of -loadData:scaleFactor:.
*/
enum {
#if OOLITE_64_BIT
    kVertexFaceDefInternalCount = 11 // sizeof (VertexFaceRef) = 32
#else
    kVertexFaceDefInternalCount = 5 // sizeof (VertexFaceRef) = 16
#endif
};

typedef struct VertexFaceRef {
    uint16_t internCount;
    uint16_t internFaces[kVertexFaceDefInternalCount];
    std::vector<NSUInteger> extra;
} VertexFaceRef;

static void VFRAddFace(VertexFaceRef* vfr, NSUInteger index);
static NSUInteger VFRGetCount(VertexFaceRef* vfr);
static NSUInteger VFRGetFaceAtIndex(VertexFaceRef* vfr, NSUInteger index);

// The OOCacheManager (OOMesh) category, as free functions next to the cache (defined below).
namespace {
oo::PList OOCacheManagerMeshDataForName(const std::string& inShipName);
void OOCacheManagerSetMeshData(const oo::PList& inData, const std::string& inShipName);
}

// One mesh buffer: the bytes _vertices & co. point into, shared (refcounted) by a mesh and its
// mutable copies as the retained data object was.
class OOMeshBuffer : public oo::RefCounted {
public:
    explicit OOMeshBuffer(oo::Data bytes)
        : data_(std::move(bytes))
    {
    }
    oo::Data& data() noexcept { return data_; }

private:
    oo::Data data_;
};

static BOOL IsLegacyNormalMode(OOMeshNormalMode mode)
{
    /*	True for modes that predate the "normal mode" concept, i.e. per-face
            and smooth. These modes require automatic winding correction.
    */
    switch (mode) {
    case kNormalModePerFace:
    case kNormalModeSmooth:
        return YES;

    case kNormalModeExplicit:
        return NO;
    }

#ifndef NDEBUG
    OORaiseException(OOInvalidArgumentException, "Unexpected normal mode in %s", __PRETTY_FUNCTION__);
#endif
    return NO;
}

static BOOL IsPerVertexNormalMode(OOMeshNormalMode mode)
{
    /*	True for modes that have per-vertex normals, i.e. not per-face mode.
     */
    switch (mode) {
    case kNormalModePerFace:
        return NO;

    case kNormalModeSmooth:
    case kNormalModeExplicit:
        return YES;
    }

#ifndef NDEBUG
    OORaiseException(OOInvalidArgumentException, "Unexpected normal mode in %s", __PRETTY_FUNCTION__);
#endif
    return NO;
}

oo::Ref<OOMesh> OOMesh::meshWithName(const std::string& name,
    const std::optional<std::string>& cacheKey,
    const oo::PList& materialDict,
    const oo::PList& shadersDict,
    bool smooth,
    const oo::PList& macros,
    Entity* object)
{
    // [[self alloc] initWithName:...] autoreleased: a new mesh, loaded, or null when it did not load.
    oo::Ref<OOMesh> mesh = oo::makeRef<OOMesh>();
    if (!mesh->initWithName(name, cacheKey, materialDict, shadersDict, smooth, macros, object, 1.0f, true))
        return nullptr;
    return mesh;
}

oo::Ref<OOMesh> OOMesh::meshWithName(const std::string& name,
    const std::optional<std::string>& cacheKey,
    const oo::PList& materialDict,
    const oo::PList& shadersDict,
    bool smooth,
    const oo::PList& macros,
    Entity* object,
    float scale,
    bool cacheWriteable)
{
    oo::Ref<OOMesh> mesh = oo::makeRef<OOMesh>();
    if (!mesh->initWithName(name, cacheKey, materialDict, shadersDict, smooth, macros, object, scale, cacheWriteable))
        return nullptr;
    return mesh;
}

oo::Ref<OOMaterial> OOMesh::placeholderMaterial()
{
    static OOBasicMaterial* placeholderMaterial = nullptr; // never released, as before

    if (placeholderMaterial == nullptr) {
        // +cxx_materialDefaults answers a copy: keep it alive while noTextures points into it (bead oo-f4241).
        const oo::PList materialDefaults = ResourceManager::materialDefaults();
        const oo::PList* noTextures = materialDefaults.find("no-textures-material");
        placeholderMaterial = OOBasicMaterial::materialWithName(std::string("/placeholder/"), (noTextures != nullptr ? *noTextures : oo::PList())).leakRef();
    }

    return oo::Ref<OOMaterial>(placeholderMaterial);
}

OOMesh::OOMesh()
{
    baseFile = "No Model";
    baseFileOctreeCacheRef = "No Model-0.000";
    _cacheWriteable = YES;
#if OO_MULTITEXTURE
    _textureUnitCount = NSNotFound;
#endif

    _lastPosition = kZeroVector;
    _lastRotMatrix = kZeroMatrix; // not identity
    _lastBoundingBox = kZeroBoundingBox;
}

OOMesh::~OOMesh()
{
    unsigned i;

    deleteDisplayLists();

    for (i = 0; i != kOOMeshMaxMaterials; ++i) {
        OOMaterial* material = materials[i]; // DESTROY(): cleared before the release
        materials[i] = nullptr;
        oo::release(material);
    }

    OOGraphicsResetManager::sharedManager()->unregisterCxxClient(this);

#if OOMESH_PROFILE
    _stopwatch = nullptr;
#endif
}

namespace {

const char* NormalModeDescription(OOMeshNormalMode mode)
{
    switch (mode) {
    case kNormalModePerFace:
        return "per-face";
    case kNormalModeSmooth:
        return "smooth";
    case kNormalModeExplicit:
        return "explicit";
    }

    return "unknown";
}

} // namespace

std::optional<std::string> OOMesh::descriptionComponents() const
{
    OOMesh* mesh = const_cast<OOMesh*>(this); // the getters are not const (ADR-0056 item 3)
    const std::optional<std::string> modelName = mesh->modelName();
    return oo::str::format("\"%s\", %zu vertices, %zu faces, radius: %g m normals: %s", modelName ? modelName->c_str() : "(null)", mesh->getVertexCount(), mesh->getFaceCount(), mesh->collisionRadius(), NormalModeDescription((OOMeshNormalMode)_normalMode));
}

oo::Ref<OOMesh> OOMesh::copyWithZone(OOZone* zone)
{
    // -zone is always nil (OOObject.h), so this is [self zone].
    if (zone == nullptr)
        return oo::Ref<OOMesh>(this); // OK because we're immutable seen from the outside
    else
        return mutableCopyWithZone(zone);
}

std::optional<std::string> OOMesh::modelName()
{
    return baseFile;
}

size_t OOMesh::getVertexCount()
{
    return vertexCount;
}

size_t OOMesh::getFaceCount()
{
    return faceCount;
}

void OOMesh::renderOpaqueParts()
{
    OO_ENTER_OPENGL();

    Entity* bindingEntity = _shaderBindingTarget.get(); // a message to a gone target's weak reference answered NO
    BOOL meshBelongsToVisualEffect = bindingEntity != nullptr && bindingEntity->getIsVisualEffect();

    OOSetOpenGLState(OPENGL_STATE_OPAQUE);

    OOGL(glVertexPointer(3, GL_FLOAT, 0, _displayLists.vertexArray));
    OOGL(glNormalPointer(GL_FLOAT, 0, _displayLists.normalArray));

    // for visual effects enable blending. This will allow use of alpha
    // channel in shaders - note, this is a bit of cheating the system,
    // which expects blending to be disabled at this point
    if (meshBelongsToVisualEffect) {
        OOGL(glEnable(GL_BLEND));
        OOGL(glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA));
    }

#if OO_SHADERS
    if (OOOpenGLExtensionManager::sharedManager()->shadersSupported()) {
        OOGL(glEnableVertexAttribArrayARB(kTangentAttributeIndex));
        OOGL(glVertexAttribPointerARB(kTangentAttributeIndex, 3, GL_FLOAT, GL_FALSE, 0, _displayLists.tangentArray));
    }
#endif

    BOOL usingNormalsAsTexCoords = NO;
    OOMeshMaterialIndex ti;

    /*	FIXME: really, really horrible hack to set up texture coordinates for
            each texture unit. Very messy and still fails to handle some possibly-
            basic stuff, like switching usingNormalsAsTexCoords per texture unit.
            The right way to do this is probably to move attribute setup into the
            material model.
            -- Ahruman 2010-04-12
    */
#if OO_MULTITEXTURE
    if (_textureUnitCount == NSNotFound) {
        _textureUnitCount = 0;
        for (ti = 0; ti < materialCount; ti++) {
            NSUInteger count = materials[ti] != nullptr ? materials[ti]->countOfTextureUnitsWithBaseCoordinates() : 0;
            if (_textureUnitCount < count)
                _textureUnitCount = count;
        }
    }

    NSUInteger unit;
    if (_textureUnitCount <= 1) {
        OOGL(glEnableClientState(GL_TEXTURE_COORD_ARRAY));
    } else {
        /*	It should not be possible to have multiple texture units if
                texture combiners are not available.
        */
        OOCAssert(OOOpenGLExtensionManager::sharedManager()->textureCombinersSupported(), "Mesh %s uses %zu texture units, but multitexturing is not available.", oo::str::format("<OOMesh %s>", oo::str::pointerDescription(this).c_str()).c_str(), _textureUnitCount);

        for (unit = 0; unit < _textureUnitCount; unit++) {
            OOGL(glClientActiveTextureARB(GL_TEXTURE0_ARB + unit));
            OOGL(glEnableClientState(GL_TEXTURE_COORD_ARRAY));
        }
    }
#else
    OOGL(glEnableClientState(GL_TEXTURE_COORD_ARRAY));
#endif

    try {
        if (!listsReady) {
            OOGL(displayList0 = glGenLists(materialCount));

            // Ensure all textures are loaded
            for (ti = 0; ti < materialCount; ti++) {
                if (materials[ti] != nullptr)
                    materials[ti]->ensureFinishedLoading();
            }
        }

        for (ti = 0; ti < materialCount; ti++) {
            BOOL wantsNormalsAsTextureCoordinates = materials[ti] != nullptr && materials[ti]->wantsNormalsAsTextureCoordinates();
            if (ti == 0 || wantsNormalsAsTextureCoordinates != usingNormalsAsTexCoords) {
                // FIXME: enabling/disabling texturing should be handled by the material.
#if OO_MULTITEXTURE
                for (unit = 0; unit < _textureUnitCount; unit++) {
                    if (_textureUnitCount > 1) {
                        OOGL(glClientActiveTextureARB(GL_TEXTURE0_ARB + unit));
                        OOGL(glActiveTextureARB(GL_TEXTURE0_ARB + unit));
                    }
#endif
                    if (!wantsNormalsAsTextureCoordinates) {
                        OOGL(glDisable(GL_TEXTURE_CUBE_MAP));
                        OOGL(glTexCoordPointer(2, GL_FLOAT, 0, _displayLists.textureUVArray));
                        /*	FIXME: Not including the line below breaks multitexturing in no-shaders mode.
                                However, the OpenGL state manager should probably be handling this;
                                TEXTURE_2D is part of OPENGL_STATE_OPAQUE, which has already been set.
                                - Nikos 20130103
                        */
                        OOGL(glEnable(GL_TEXTURE_2D));
                    } else {
                        OOGL(glDisable(GL_TEXTURE_2D));
                        OOGL(glTexCoordPointer(3, GL_FLOAT, 0, _displayLists.vertexArray));
                        OOGL(glEnable(GL_TEXTURE_CUBE_MAP));
                    }
#if OO_MULTITEXTURE
                }
#endif
                usingNormalsAsTexCoords = wantsNormalsAsTextureCoordinates;
            }

            if (materials[ti] != nullptr)
                materials[ti]->apply();
            OOGL(glDrawArrays(GL_TRIANGLES, triangle_range[ti].location, triangle_range[ti].length));
        }

        listsReady = YES;
        brokenInRender = NO;
    } catch (...) {
        const auto exception = oo::CurrentOOException();
        if (!exception)
            throw; // not an OOException: it goes on up, as before
        if (!brokenInRender) {
            OO_LOG(cxx_kOOLogException, "***** {} for {} encountered exception: {} : {} *****", __PRETTY_FUNCTION__, description(), exception->name(), exception->reason());
            brokenInRender = YES;
        }
        if (strncmp(exception->name(), "Oolite", 6) == 0) {
            if (UNIVERSE != nullptr)
                UNIVERSE->handleOoliteException(exception->object());
        } // handle these ourself
        else
            throw; // pass these on
    }

#if OO_SHADERS
    if (OOOpenGLExtensionManager::sharedManager()->shadersSupported()) {
        OOGL(glDisableVertexAttribArrayARB(kTangentAttributeIndex));
    }
#endif

    OOMaterial::applyNone();
    cxx_OOCheckOpenGLErrors([&]() -> std::string { return "OOMesh after drawing " + description(); });

#if OO_MULTITEXTURE
    if (_textureUnitCount <= 1) {
        OOGL(glDisableClientState(GL_TEXTURE_COORD_ARRAY));
    } else {
        for (unit = 0; unit < _textureUnitCount; unit++) {
            OOGL(glClientActiveTextureARB(GL_TEXTURE0_ARB + unit));
            OOGL(glDisableClientState(GL_TEXTURE_COORD_ARRAY));
        }

        OOGL(glClientActiveTextureARB(GL_TEXTURE0_ARB));
        OOGL(glActiveTextureARB(GL_TEXTURE0_ARB));
    }
#else
    OOGL(glDisableClientState(GL_TEXTURE_COORD_ARRAY));
#endif

#ifdef OO_DEBUG_MONITOR_ENABLED
    if (gDebugFlags & DEBUG_DRAW_NORMALS)
        debugDrawNormals();
    if (gDebugFlags & DEBUG_OCTREE_DRAW) {
        if (Octree* cxxOctree = getOctree().get())
            cxxOctree->drawOctree();
    } // a nil octree did nothing
#endif

    // visual effect - disable previously enabled blending
    if (meshBelongsToVisualEffect)
        OOGL(glDisable(GL_BLEND));

    OOVerifyOpenGLState();
}

void OOMesh::rebindMaterials()
{
    OOMeshMaterialCount i;
    oo::Ref<OOMaterial> material;

    if (materialCount != 0) {
        for (i = 0; i != materialCount; ++i) {
            OOMaterial* oldMaterial = materials[i];

            if (materialKeys[i] != "_oo_placeholder_material") {
                material = OOMaterial::materialWithName(materialKeys[i],
                    _cacheKey,
                    _materialDict,
                    _shadersDict,
                    _shaderMacros,
                    _shaderBindingTarget.get(), // Windows DEP fix.
                    IsPerVertexNormalMode((OOMeshNormalMode)_normalMode));
            } else {
                material = nullptr;
            }

            // The member holds the material, retained, as before.
            if (material != nullptr) {
                materials[i] = oo::retain(material.get());
            } else {
                materials[i] = placeholderMaterial().leakRef();
            }

            /*	Release is deferred to here to ensure we don't end up releasing
                    a texture that's not in the recent-cache and then reloading it.
            */
            oo::release(oldMaterial);
        }
    }
}

oo::PList OOMesh::getMaterials()
{
    return _materialDict;
}

oo::PList OOMesh::shaders()
{
    return _shadersDict;
}

bool OOMesh::hasOpaqueParts()
{
    return YES;
}

GLfloat OOMesh::collisionRadius()
{
    return _collisionRadius;
}

GLfloat OOMesh::maxDrawDistance()
{
    return _maxDrawDistance;
}

#if ADAPTIVE_OCTREE_DEPTH
unsigned OOMesh::octreeDepth()
{
    float threshold = kOctreeSizeThreshold;
    unsigned result = kBaseOctreeDepth;
    GLfloat xs, ys, zs, t, size;

    bounding_box_get_dimensions(_boundingBox, &xs, &ys, &zs);
    // Shuffle dimensions around so zs is smallest
    if (xs < zs) {
        t = zs;
        zs = xs;
        xs = t;
    }
    if (ys < zs) {
        t = zs;
        zs = ys;
        ys = t;
    }
    size = (xs + ys) / 2.0f; // Use average of two largest

    if (size < static_cast<GLfloat>(kOctreeSmallSizeThreshold))
        result = kSmallOctreeDepth;
    else
        while (result < kMaxOctreeDepth) {
            if (size < threshold)
                break;
            threshold *= 2.0f;
            result++;
        }

    OO_LOG("mesh.load.octree.size", "Selected octree depth {} for size {:g} for {}", result, size, baseFile.value_or("(null)"));
    return result;
}
#else
unsigned OOMesh::octreeDepth()
{
    return kBaseOctreeDepth;
}
#endif

oo::Ref<Octree> OOMesh::getOctree()
{
    if (octree == nullptr) {
        octree = baseFileOctreeCacheRef ? OOCacheManagerOctreeForModel(*baseFileOctreeCacheRef) : oo::Ref<Octree>();
        if (octree == nullptr) {
            {
                oo::Ref<OOMeshToOctreeConverter> converter = OOMeshToOctreeConverter::converterWithCapacity(faceCount);
                OOMeshFaceCount i;
                for (i = 0; i < faceCount; i++) {
                    // Somewhat surprisingly, this method doesn't even show up in profiles. -- Ahruman 2012-09-22
                    Triangle tri;
                    tri.v[0] = _vertices[_faces[i].vertex[0]];
                    tri.v[1] = _vertices[_faces[i].vertex[1]];
                    tri.v[2] = _vertices[_faces[i].vertex[2]];
                    converter->addTriangle(tri);
                }

                octree = converter->findOctreeToDepth(octreeDepth());
                if (EXPECT(_cacheWriteable) && baseFileOctreeCacheRef) {
                    OOCacheManagerSetOctree(octree.get(), *baseFileOctreeCacheRef);
                }
            }
        } else {
            OO_LOG("mesh.load.octreeCached", "Retrieved octree \"{}\" from cache.", baseFileOctreeCacheRef.value_or("(null)"));
        }
    }

    return octree;
}

BoundingBox OOMesh::findBoundingBoxRelativeToPosition(Vector opv, Vector ri, Vector rj, Vector rk, Vector position, Vector si, Vector sj, Vector sk)
{
    BoundingBox result;
    Vector pv, rv;

    // FIXME: rewrite with matrices
    Vector rpos = vector_subtract(position, opv); // model origin relative to opv

    rv.x = dot_product(ri, rpos);
    rv.y = dot_product(rj, rpos);
    rv.z = dot_product(rk, rpos); // model origin rel to opv in ijk

    if (EXPECT_NOT(vertexCount < 1)) {
        bounding_box_reset_to_vector(&result, rv);
    } else {
        pv.x = rpos.x + si.x * _vertices[0].x + sj.x * _vertices[0].y + sk.x * _vertices[0].z;
        pv.y = rpos.y + si.y * _vertices[0].x + sj.y * _vertices[0].y + sk.y * _vertices[0].z;
        pv.z = rpos.z + si.z * _vertices[0].x + sj.z * _vertices[0].y + sk.z * _vertices[0].z; // _vertices[0] position rel to opv
        rv.x = dot_product(ri, pv);
        rv.y = dot_product(rj, pv);
        rv.z = dot_product(rk, pv); // _vertices[0] position rel to opv in ijk
        bounding_box_reset_to_vector(&result, rv);
    }

    OOMeshVertexCount i;
    for (i = 1; i < vertexCount; i++) {
        pv.x = rpos.x + si.x * _vertices[i].x + sj.x * _vertices[i].y + sk.x * _vertices[i].z;
        pv.y = rpos.y + si.y * _vertices[i].x + sj.y * _vertices[i].y + sk.y * _vertices[i].z;
        pv.z = rpos.z + si.z * _vertices[i].x + sj.z * _vertices[i].y + sk.z * _vertices[i].z;
        rv.x = dot_product(ri, pv);
        rv.y = dot_product(rj, pv);
        rv.z = dot_product(rk, pv);
        bounding_box_add_vector(&result, rv);
    }

    return result;
}

BoundingBox OOMesh::findSubentityBoundingBoxWithPosition(Vector position, OOMatrix rotMatrix)
{
    // HACK! Should work out what the various bounding box things do and make it neat and consistent.
    // FIXME: this is a bottleneck.
    // Try to fix bottleneck by caching for common case where subentity
    // pos+rot is constant from frame to frame. - CIM

    if (vector_equal(position, _lastPosition) && OOMatrixEqual(rotMatrix, _lastRotMatrix)) {
        return _lastBoundingBox;
    }

    BoundingBox result;
    Vector v;

    v = vector_add(position, OOVectorMultiplyMatrix(_vertices[0], rotMatrix));
    bounding_box_reset_to_vector(&result, v);

    OOMeshVertexCount i;
    for (i = 1; i < vertexCount; i++) {
        v = vector_add(position, OOVectorMultiplyMatrix(_vertices[i], rotMatrix));
        bounding_box_add_vector(&result, v);
    }

    _lastBoundingBox = result;
    _lastPosition = position;
    _lastRotMatrix = rotMatrix;

    return result;
}

oo::Ref<OOMesh> OOMesh::meshRescaledBy(GLfloat scaleFactor)
{
    oo::Ref<OOMesh> result = mutableCopyWithZone(nullptr); // [self mutableCopy]
    result->rescaleByFactor(scaleFactor);
    return result;
}

void OOMesh::setBindingTarget(Entity* target)
{
    unsigned i;

    for (i = 0; i != kOOMeshMaxMaterials; ++i) {
        // A nil material did nothing.
        if (OOMaterial* material = materials[i])
            material->setBindingTarget(target);
    }
}

#ifdef OO_DEBUG_MONITOR_ENABLED
void OOMesh::dumpSelfState()
{
    OODrawable::dumpSelfState();

    if (baseFile)
        OO_LOG("dumpState.mesh", "Model file: {}", *baseFile);
    OO_LOG("dumpState.mesh", "Vertex count: {}, face count: {}", static_cast<unsigned>(vertexCount), static_cast<unsigned>(faceCount));
    OO_LOG("dumpState.mesh", "Normals: {}", NormalModeDescription((OOMeshNormalMode)_normalMode));
}
#endif

#ifdef OO_DEBUG_MONITOR_ENABLED
std::vector<oo::Ref<OOTexture>> OOMesh::allTextures()
{
    // Every material's textures; id forwarder NSSetFromObjects drops duplicates as -unionSet: did.
    std::vector<oo::Ref<OOTexture>> result;
    OOMeshMaterialCount i;
    for (i = 0; i != materialCount; i++) {
        // A nil material answered no textures.
        OOMaterial* material = materials[i];
        if (material == nullptr)
            continue;
        for (const oo::Ref<OOTexture>& texture : material->allTextures())
            result.push_back(texture);
    }

    return result;
}

size_t OOMesh::totalSize()
{
    size_t result = OODrawable::totalSize();
    if (_vertices != NULL)
        result += sizeof *_vertices * vertexCount;
    if (_normals != NULL)
        result += sizeof *_normals * vertexCount;
    if (_tangents != NULL)
        result += sizeof *_tangents * vertexCount;
    if (_faces != NULL)
        result += sizeof *_faces * faceCount;

    result += _displayLists.count * (sizeof(GLint) + sizeof(GLfloat) + sizeof(Vector) * 3);

    OOMeshMaterialCount i;
    for (i = 0; i != materialCount; i++) {
        // The object's own size (was its facade class's instance size), 0 for nil.
        if (materials[i] != nullptr)
            result += materials[i]->objectSize();
    }

    // A nil octree answered 0.
    if (octree != nullptr)
        result += octree->totalSize();
    return result;
}
#endif

/*	This method exists purely to suppress Clang static analyzer warnings that
        these ivars are unused (but may be used by categories, which they are).
        FIXME: there must be a feature macro we can use to avoid actually building
        this into the app, but I can't find it in docs.
*/
bool OOMesh::suppressClangStuff()
{
    return _normals && _tangents && _faces && _boundingBox.min.x;
}

bool OOMesh::initWithName(const std::string& name,
    const std::optional<std::string>& cacheKey,
    const oo::PList& materialDict,
    const oo::PList& shadersDict,
    bool smooth,
    const oo::PList& macros,
    Entity* target,
    float scale,
    bool cacheWriteable)
{
    OOJS_PROFILE_ENTER

    // The mesh is new (the factory made it; -init's defaults, which loading overwrites). It answers
    // whether it loaded: the factory drops it when not, as [self release] did.
    bool loaded = false;
    {
        _normalMode = smooth ? kNormalModeSmooth : kNormalModePerFace;
        _cacheWriteable = cacheWriteable;

#if OOMESH_PROFILE
        _stopwatch = oo::makeRef<OOProfilingStopwatch>();
#endif

        if (loadData(name, scale)) {
            calculateBoundingVolumes();
            PROFILE("finished calculateBoundingVolumes (again\?\?)");

            baseFile = name;
            baseFileOctreeCacheRef = oo::str::format("%s-%.3f", name.c_str(), scale);

            /*	New in r3033: save the material-defining parameters here so we
                    can rebind the materials at any time.
                    -- Ahruman 2010-02-17
            */
            _materialDict = materialDict;
            _shadersDict = shadersDict;
            _cacheKey = cacheKey;
            _shaderMacros = macros;
            _shaderBindingTarget = target;

            rebindMaterials();
            PROFILE("finished material setup");

            OOGraphicsResetManager::sharedManager()->registerCxxClient(this);
            loaded = true;
        }
#if OOMESH_PROFILE
        _stopwatch = nullptr;
#endif
#if OO_MULTITEXTURE
        if (EXPECT(loaded)) {
            _textureUnitCount = NSNotFound;
        }
#endif
    }
    return loaded;

    OOJS_PROFILE_EXIT
}

oo::Ref<OOMesh> OOMesh::mutableCopyWithZone(OOZone* /*zone*/)
{
    OOMeshMaterialCount i;

    // NSCopyObject(self, 0, zone) without Foundation (ADR-0029 reroot): a new mesh whose members
    // are copied one by one (the copy constructor), as NSCopyObject copied the ivars bitwise and
    // the C++ ones were then constructed afresh over the copy, so the buffers are shared. Zones are
    // unused, as on GNUstep.
    oo::Ref<OOMesh> result = oo::makeRef<OOMesh>(*this);

    // (The binding target is a weak reference since bead oo-9ht.39.6, copied; the octree is a C++ reference, copied.)

    for (i = 0; i != kOOMeshMaxMaterials; ++i) {
        oo::retain(result->materials[i]);
    }

    // Reset unsharable GL state
    result->listsReady = NO;

    OOGraphicsResetManager::sharedManager()->registerCxxClient(result.get());

    return result;
}

oo::PList OOMesh::modelData()
{
    OOJS_PROFILE_ENTER

    BOOL includeNormals = IsPerVertexNormalMode((OOMeshNormalMode)_normalMode);

    // Prepare cache data elements.
    const auto vertData = _retainedObjects.find("vertices");
    const auto faceData = _retainedObjects.find("faces");
    const auto normData = _retainedObjects.find("normals");
    const auto tanData = _retainedObjects.find("tangents");

    // Ensure we have all the required data elements.
    if (vertData == _retainedObjects.end() || faceData == _retainedObjects.end()) {
        return oo::PList();
    }

    if (includeNormals) {
        if (normData == _retainedObjects.end() || tanData == _retainedObjects.end())
            return oo::PList();
    }

    // All OK; stick 'em in a dictionary. The counts are unsigned (+numberWithUnsignedInt:, and
    // +numberWithUnsignedChar: for the normal mode); the normals are only included when used.
    oo::PList::Array mtlKeys;
    for (OOMeshMaterialCount i = 0; i != materialCount; ++i)
        mtlKeys.emplace_back(materialKeys[i]);

    oo::PList::Dict result;
    result["vertex count"] = oo::PList(vertexCount);
    result["vertex data"] = oo::PList(vertData->second->data());
    result["face count"] = oo::PList(faceCount);
    result["face data"] = oo::PList(faceData->second->data());
    result["material keys"] = oo::PList(std::move(mtlKeys));
    result["normal mode"] = oo::PList::unsignedInteger(_normalMode);
    if (includeNormals) {
        result["normal data"] = oo::PList(normData->second->data());
        result["tangent data"] = oo::PList(tanData->second->data());
    }
    return oo::PList(std::move(result));

    OOJS_PROFILE_EXIT
}

bool OOMesh::setModelFromModelData(const oo::PList& dict, const std::string& fileName)
{
    OOJS_PROFILE_ENTER

    unsigned i;

    if (!dict.isDict())
        return NO;

    vertexCount = dict.get<unsigned int>("vertex count");
    faceCount = dict.get<unsigned int>("face count");

    if (vertexCount == 0 || faceCount == 0)
        return NO;

    // Read data elements from dictionary.
    const oo::PList* vertData = dict.get<oo::PList::Data>("vertex data");
    const oo::PList* faceData = dict.get<oo::PList::Data>("face data");
    const oo::PList* normData = nullptr;
    const oo::PList* tanData = nullptr;

    const oo::PList* mtlKeys = dict.get<oo::PList::Array>("material keys");
    _normalMode = dict.get<unsigned char>("normal mode");
    BOOL includeNormals = IsPerVertexNormalMode((OOMeshNormalMode)_normalMode);

    // Ensure we have all the required data elements.
    if (vertData == nullptr || faceData == nullptr || mtlKeys == nullptr) {
        OO_LOG("mesh.load.error.badCacheData", "Ignoring bad cache data for mesh \"{}\".", fileName);
        return NO;
    }

    if (includeNormals) {
        normData = dict.get<oo::PList::Data>("normal data");
        tanData = dict.get<oo::PList::Data>("tangent data");
        if (normData == nullptr || tanData == nullptr) {
            OO_LOG("mesh.load.error.badCacheData", "Ignoring bad normal/tangent cache data for mesh \"{}\".", fileName);
            return NO;
        }
    }

    // Ensure data objects are of correct size.
    if (vertData->getIf<oo::PList::Data>()->length() != sizeof *_vertices * vertexCount)
        return NO;
    if (faceData->getIf<oo::PList::Data>()->length() != sizeof *_faces * faceCount)
        return NO;
    if (includeNormals) {
        if (normData->getIf<oo::PList::Data>()->length() != sizeof *_normals * vertexCount)
            return NO;
        if (tanData->getIf<oo::PList::Data>()->length() != sizeof *_tangents * vertexCount)
            return NO;
    }

    // Retain data: each is copied into a buffer of this mesh's, and the pointers taken from it.
    setRetainedObject(*vertData->getIf<oo::PList::Data>(), "vertices");
    _vertices = (Vector*)_retainedObjects.find("vertices")->second->data().mutableBytes();
    setRetainedObject(*faceData->getIf<oo::PList::Data>(), "faces");
    _faces = (OOMeshFace*)_retainedObjects.find("faces")->second->data().mutableBytes();
    if (includeNormals) {
        setRetainedObject(*normData->getIf<oo::PList::Data>(), "normals");
        _normals = (Vector*)_retainedObjects.find("normals")->second->data().mutableBytes();
        setRetainedObject(*tanData->getIf<oo::PList::Data>(), "tangents");
        _tangents = (Vector*)_retainedObjects.find("tangents")->second->data().mutableBytes();
    } else {
        _normals = NULL;
        _tangents = NULL;
    }

    // Copy material keys (oo_stringAtIndex: a string, or a number's -stringValue).
    const oo::PList::Array& keys = *mtlKeys->getIf<oo::PList::Array>();
    materialCount = keys.size();
    for (i = 0; i != materialCount; ++i) {
        const oo::PList& key = keys[i];
        if (key.isString() || key.isNumber())
            materialKeys[i] = oo::PListGet<std::string>::from(&key, std::string());
        else {
            OO_LOG("mesh.load.error.badCacheData", "Ignoring bad cache data for mesh \"{}\".", fileName);
            return NO;
        }
    }

    return YES;

    OOJS_PROFILE_EXIT
}

bool OOMesh::loadData(const std::string& filename, float scale)
{
    OOJS_PROFILE_ENTER

    std::optional<oo::str::Scanner> scanner; // made from the preprocessed text below
    BOOL failFlag = NO;
    std::string failString = "***** ";
    unsigned i, j;
    std::map<std::string, unsigned, std::less<>> texFileName2Idx;
    BOOL using_preloaded = NO;

    const std::string cacheKey = oo::str::format("%s:%u:%.3f", filename.c_str(), _normalMode, scale);
    const oo::PList cacheData = OOCacheManagerMeshDataForName(cacheKey);
    if (cacheData) {
        if (setModelFromModelData(cacheData, filename)) {
            using_preloaded = YES;
            PROFILE("loaded from cache");
            OO_LOG("mesh.load.cached", "Retrieved mesh \"{}\" from cache.", filename);
        }
    }

    if (!using_preloaded) {
        OO_LOG("mesh.load.uncached", "Mesh \"{}\" is not in cache, loading.", cacheKey);

        const oo::str::CharacterSet whitespaceCharSet = oo::str::CharacterSet::whitespace();
        const oo::str::CharacterSet whitespaceAndNewlineCharSet = oo::str::CharacterSet::whitespaceAndNewline();
        // The newline set. The non-Mac build made it as whitespace-and-newline minus whitespace,
        // which is the same set (U+000A-U+000D and U+0085: Scanner.hpp's tables).
        const oo::str::CharacterSet newlineCharSet = oo::str::CharacterSet::newline();

        {
            const std::optional<std::string> dataOpt = ResourceManager::stringFromFilesNamed(filename, "Models", NO);
            if (!dataOpt) {
                // Model not found
                OO_LOG(kOOLogMeshDataNotFound, "***** ERROR: could not find {}", filename);
                cxx_OOStandardsError("Model file not found");
                return NO;
            }

            // strip out comments and commas between values
            std::vector<std::string> lines = oo::str::split(*dataOpt, "\n");
            for (i = 0; i < lines.size(); i++) {
                std::string line = lines[i];
                std::vector<std::string> parts;
                //
                // comments
                //
                parts = oo::str::split(line, "#");
                line = parts.empty() ? std::string() : parts[0];
                parts = oo::str::split(line, "//");
                line = parts.empty() ? std::string() : parts[0];
                //
                // commas
                //
                parts = oo::str::split(line, ",");
                line.clear();
                for (std::size_t p = 0; p < parts.size(); ++p) {
                    if (p)
                        line += ' ';
                    line += parts[p];
                }
                //
                lines[i] = std::move(line);
            }

            std::string data;
            for (std::size_t li = 0; li < lines.size(); ++li) {
                if (li)
                    data += '\n';
                data += lines[li];
            }
            scanner.emplace(data);
        }

        PROFILE("finished preprocessing");

        // get number of vertices
        //
        scanner->setScanLocation(0); // reset
        if (scanner->scanString("NVERTS")) {
            int n_v;
            if (scanner->scanInt(&n_v))
                vertexCount = n_v;
            else {
                failFlag = YES;
                failString += "Failed to read value of NVERTS\n";
            }
        } else {
            failFlag = YES;
            failString += "Failed to read NVERTS\n";
        }

        if (!allocateVertexBuffersWithCount(vertexCount)) {
            OO_LOG(cxx_kOOLogAllocationFailure, "***** ERROR: failed to allocate memory for model {} ({} vertices).", filename, static_cast<unsigned>(vertexCount));
            return NO;
        }

        // get number of faces
        if (scanner->scanString("NFACES")) {
            int n_f;
            if (scanner->scanInt(&n_f)) {
                faceCount = n_f;
            } else {
                failFlag = YES;
                failString += "Failed to read value of NFACES\n";
            }
        } else {
            failFlag = YES;
            failString += "Failed to read NFACES\n";
        }

        // Allocate face->vertex table.
        std::vector<VertexFaceRef> faceRefTable(vertexCount); // zeroed, freed when loading ends
        VertexFaceRef* faceRefs = faceRefTable.data();

        if (!allocateFaceBuffersWithCount(faceCount)) {
            OO_LOG(cxx_kOOLogAllocationFailure, "***** ERROR: failed to allocate memory for model {} ({} vertices, {} faces).", filename, static_cast<unsigned>(vertexCount), static_cast<unsigned>(faceCount));
            return NO;
        }

        // get vertex data
        if (scanner->scanString("VERTEX")) {
            for (j = 0; j < vertexCount; j++) {
                float x = 0, y = 0, z = 0; // read only after every scan succeeded (GCC -Wmaybe-uninitialized; bead oo-1q4)
                if (!failFlag) {
                    if (!scanner->scanFloat(&x))
                        failFlag = YES;
                    if (!scanner->scanFloat(&y))
                        failFlag = YES;
                    if (!scanner->scanFloat(&z))
                        failFlag = YES;
                    if (!failFlag) {
                        _vertices[j] = make_vector(x * scale, y * scale, z * scale);
                    } else {
                        failString += oo::str::format("Failed to read a value for vertex[%d] in %s\n", j, "VERTEX");
                    }
                }
            }
        } else {
            failFlag = YES;
            failString += "Failed to find VERTEX data\n";
        }

        // get face data
        if (scanner->scanString("FACES")) {
            for (j = 0; j < faceCount; j++) {
                int r, g, b;
                float nx = 0, ny = 0, nz = 0; // read only after every scan succeeded (GCC -Wmaybe-uninitialized; bead oo-1q4)
                int n_v;
                if (!failFlag) {
                    // colors
                    if (!scanner->scanInt(&r))
                        failFlag = YES;
                    if (!scanner->scanInt(&g))
                        failFlag = YES;
                    if (!scanner->scanInt(&b))
                        failFlag = YES;
                    if (!failFlag) {
                        _faces[j].smoothGroup = r;
                    } else {
                        failString += oo::str::format("Failed to read a color for face[%d] in FACES\n", j);
                    }

                    // normal
                    if (!scanner->scanFloat(&nx))
                        failFlag = YES;
                    if (!scanner->scanFloat(&ny))
                        failFlag = YES;
                    if (!scanner->scanFloat(&nz))
                        failFlag = YES;
                    if (!failFlag) {
                        _faces[j].normal = vector_normal(make_vector(nx, ny, nz));
                    } else {
                        failString += oo::str::format("Failed to read a normal for face[%d] in FACES\n", j);
                    }

                    // vertices
                    if (scanner->scanInt(&n_v)) {
                        if (n_v < 3) {
                            failFlag = YES;
                            failString += oo::str::format("Face[%u] has fewer than three vertices.\n", j);
                        } else if (n_v > 3) {
                            OO_LOG_WARN("mesh.load.warning.nonTriangular", "Face[{}] of {} has {} vertices specified. Only the first three will be used.", static_cast<unsigned>(j), baseFile.value_or("(null)"), static_cast<unsigned>(n_v));
                            n_v = 3;
                        }
                    } else {
                        failFlag = YES;
                        failString += oo::str::format("Failed to read number of vertices for face[%d] in FACES\n", j);
                    }

                    if (!failFlag) {
                        int vi;
                        for (i = 0; (int)i < n_v; i++) {
                            if (scanner->scanInt(&vi)) {
                                _faces[j].vertex[i] = vi;
                                if (faceRefs != NULL)
                                    VFRAddFace(&faceRefs[vi], j);
                            } else {
                                failFlag = YES;
                                failString += oo::str::format("Failed to read vertex[%d] for face[%d] in FACES\n", i, j);
                            }
                        }
                    }
                }
            }
        } else {
            failFlag = YES;
            failString += "Failed to find FACES data\n";
        }

        // Get textures data.
        if (scanner->scanString("TEXTURES")) {
            for (j = 0; j < faceCount; j++) {
                std::string materialKey;
                float max_x, max_y;
                float s, t;
                if (!failFlag) {
                    // materialKey
                    //
                    scanner->scanCharactersFromSet(whitespaceAndNewlineCharSet);
                    std::string scannedKey;
                    if (!scanner->scanUpToCharactersFromSet(whitespaceCharSet, &scannedKey)) {
                        failFlag = YES;
                        failString += oo::str::format("Failed to read texture filename for face[%d] in TEXTURES\n", j);
                    } else {
                        materialKey = std::move(scannedKey);
                        const auto indexIt = texFileName2Idx.find(materialKey);
                        if (indexIt != texFileName2Idx.end()) {
                            _faces[j].materialIndex = indexIt->second;
                        } else {
                            if (materialCount == kOOMeshMaxMaterials) {
                                OO_LOG(kOOLogMeshTooManyMaterials, "***** ERROR: model {} has too many materials (maximum is {})", filename, static_cast<int>(kOOMeshMaxMaterials));
                                return NO;
                            }
                            _faces[j].materialIndex = materialCount;
                            materialKeys[materialCount] = materialKey;
                            texFileName2Idx.emplace(materialKey, materialCount);
                            ++materialCount;
                        }
                    }

                    // texture size
                    //
                    if (!failFlag) {
                        if (!scanner->scanFloat(&max_x))
                            failFlag = YES;
                        if (!scanner->scanFloat(&max_y))
                            failFlag = YES;
                        if (failFlag)
                            failString += oo::str::format("Failed to read texture size for max_x and max_y in face[%d] in TEXTURES\n", j);
                    }

                    // vertices
                    //
                    if (!failFlag) {
                        for (i = 0; i < 3; i++) {
                            if (!scanner->scanFloat(&s))
                                failFlag = YES;
                            if (!scanner->scanFloat(&t))
                                failFlag = YES;
                            if (!failFlag) {
                                _faces[j].s[i] = s / max_x;
                                _faces[j].t[i] = t / max_y;
                            } else
                                failString += oo::str::format("Failed to read s t coordinates for vertex[%d] in face[%d] in TEXTURES\n", i, j);
                        }
                    }
                }
            }
        } else {
            failFlag = YES;
            failString += "Failed to find TEXTURES data (will use placeholder material)\n";
            materialKeys[0] = "_oo_placeholder_material";
            materialCount = 1;

            for (j = 0; j < faceCount; j++) {
                _faces[j].materialIndex = 0;
            }
        }

        if (scanner->scanString("NAMES")) {
            unsigned int count;
            if (!scanner->scanInt((int*)&count)) {
                failFlag = YES;
                failString += "Expected count after NAMES\n";
            } else {
                for (j = 0; j < count; j++) {
                    scanner->scanCharactersFromSet(whitespaceAndNewlineCharSet);
                    std::string scannedName;
                    if (!scanner->scanUpToCharactersFromSet(newlineCharSet, &scannedName)) {
                        failFlag = YES;
                        failString += "Expected file name\n";
                    } else {
                        renameTexturesFrom(oo::str::format("%u", j), scannedName);
                    }
                }
            }
        }

        BOOL explicitTangents = NO;

        // Get explicit normals.
        if (scanner->scanString("NORMALS")) {
            _normalMode = kNormalModeExplicit;
            if (!allocateNormalBuffersWithCount(vertexCount)) {
                OO_LOG(cxx_kOOLogAllocationFailure, "***** ERROR: failed to allocate memory for model {} ({} vertices).", filename, static_cast<unsigned>(vertexCount));
                return NO;
            }

            for (j = 0; j < vertexCount; j++) {
                float x = 0, y = 0, z = 0; // read only after every scan succeeded (GCC -Wmaybe-uninitialized; bead oo-1q4)
                if (!failFlag) {
                    if (!scanner->scanFloat(&x))
                        failFlag = YES;
                    if (!scanner->scanFloat(&y))
                        failFlag = YES;
                    if (!scanner->scanFloat(&z))
                        failFlag = YES;
                    if (!failFlag) {
                        _normals[j] = vector_normal(make_vector(x, y, z));
                    } else {
                        failString += oo::str::format("Failed to read a value for vertex[%d] in %s\n", j, "NORMALS");
                    }
                }
            }

            // Get explicit tangents (only together with vertices).
            if (scanner->scanString("TANGENTS")) {
                for (j = 0; j < vertexCount; j++) {
                    float x, y, z;
                    if (!failFlag) {
                        if (!scanner->scanFloat(&x))
                            failFlag = YES;
                        if (!scanner->scanFloat(&y))
                            failFlag = YES;
                        if (!scanner->scanFloat(&z))
                            failFlag = YES;
                        if (!failFlag) {
                            _tangents[j] = vector_normal(make_vector(x, y, z));
                        } else {
                            failString += oo::str::format("Failed to read a value for vertex[%d] in %s\n", j, "TANGENTS");
                        }
                    }
                }
            }
        }

        PROFILE("finished parsing");

        if (IsLegacyNormalMode((OOMeshNormalMode)_normalMode)) {
            checkNormalsAndAdjustWinding();
            PROFILE("finished checkNormalsAndAdjustWinding");
        }
        if (!explicitTangents) {
            generateFaceTangents();
            PROFILE("finished generateFaceTangents");
        }

        // check for smooth shading and recalculate normals
        if (_normalMode == kNormalModeSmooth) {
            if (!allocateNormalBuffersWithCount(vertexCount)) {
                OO_LOG(cxx_kOOLogAllocationFailure, "***** ERROR: failed to allocate memory for model {} ({} vertices).", filename, static_cast<unsigned>(vertexCount));
                return NO;
            }
            calculateVertexNormalsAndTangentsWithFaceRefs(faceRefs);
            PROFILE("finished calculateVertexNormalsAndTangents");

        } else if (IsPerVertexNormalMode((OOMeshNormalMode)_normalMode) && !explicitTangents) {
            calculateVertexTangentsWithFaceRefs(faceRefs);
            PROFILE("finished calculateVertexTangents");
        }

        // save the resulting data for possible reuse
        if (EXPECT(_cacheWriteable)) {
            OOCacheManagerSetMeshData(modelData(), cacheKey);
            PROFILE("saved to cache");
        }

        if (failFlag) {
            OO_LOG("mesh.error", "{} ..... from {} {}", failString, filename, (using_preloaded) ? "(from preloaded data)" : "(from file)");
        }
    }

    calculateBoundingVolumes();
    PROFILE("finished calculateBoundingVolumes");

    // set up vertex arrays for drawing
    if (!setUpVertexArrays())
        return NO;
    PROFILE("finished setUpVertexArrays");

    return YES;

    OOJS_PROFILE_EXIT
}

#if SCRIBBLE
static void Scribble(void* bytes, size_t size)
{
#if OOLITE_BIG_ENDIAN
    enum { kScribble = 0xFEEDFACE };
#else
    enum { kScribble = 0xCEFAEDFE };
#endif

    size /= sizeof(uint32_t);
    uint32_t* mem = bytes;
    while (size--)
        *mem++ = kScribble;
}
#else
#define Scribble(bytes, size) \
    do {                      \
    } while (0)
#endif

void OOMesh::deleteDisplayLists()
{
    if (listsReady) {
        OO_ENTER_OPENGL();

        OOGL(glDeleteLists(displayList0, materialCount));
        listsReady = NO;
    }
}

void OOMesh::resetGraphicsState()
{
    deleteDisplayLists();
    rebindMaterials();
    _textureUnitCount = NSNotFound;
}

bool OOMesh::setUpVertexArrays()
{
    OOJS_PROFILE_ENTER

    NSUInteger fi, vi, mi;

    if (!allocateVertexArrayBuffersWithCount(faceCount))
        return NO;

    // if smoothed, find any vertices that are between faces of different
    // smoothing groups and mark them as being on an edge and therefore NOT
    // smooth shaded
    std::vector<BOOL> is_edge_vertex(vertexCount);
    std::vector<GLfloat> smoothGroup(vertexCount);
    for (vi = 0; vi < vertexCount; vi++) {
        is_edge_vertex[vi] = NO;
        smoothGroup[vi] = -1;
    }
    if (_normalMode == kNormalModeSmooth) {
        for (fi = 0; fi < faceCount; fi++) {
            GLfloat rv = _faces[fi].smoothGroup;
            int i;
            for (i = 0; i < 3; i++) {
                vi = _faces[fi].vertex[i];
                if (smoothGroup[vi] < 0.0) // unassigned
                    smoothGroup[vi] = rv;
                else if (smoothGroup[vi] != rv) // a different colour
                    is_edge_vertex[vi] = YES;
            }
        }
    }

    // base model, flat or smooth shaded, all triangles
    int tri_index = 0;
    int uv_index = 0;
    int vertex_index = 0;

    // Iterate over material names
    for (mi = 0; mi != materialCount; ++mi) {
        triangle_range[mi].location = tri_index;

        for (fi = 0; fi < faceCount; fi++) {
            Vector normal, tangent;

            if (_faces[fi].materialIndex == mi) {
                for (vi = 0; vi < 3; vi++) {
                    int v = _faces[fi].vertex[vi];
                    if (IsPerVertexNormalMode((OOMeshNormalMode)_normalMode)) {
                        if (is_edge_vertex[v]) {
                            getNormal(&normal, &tangent, v, _faces[fi].smoothGroup);
                        } else {
                            OOCAssert(_normals != NULL && _tangents != NULL, "Normal/tangent buffers not allocated in %s", __PRETTY_FUNCTION__);

                            normal = _normals[v];
                            tangent = _tangents[v];
                        }
                    } else {
                        normal = _faces[fi].normal;
                        tangent = _faces[fi].tangent;
                    }

                    // FIXME: avoid redundant vertices so index array is actually useful.
                    _displayLists.indexArray[tri_index++] = vertex_index;
                    _displayLists.normalArray[vertex_index] = normal;
                    _displayLists.tangentArray[vertex_index] = tangent;
                    _displayLists.vertexArray[vertex_index++] = _vertices[v];
                    _displayLists.textureUVArray[uv_index++] = _faces[fi].s[vi];
                    _displayLists.textureUVArray[uv_index++] = _faces[fi].t[vi];
                }
            }
        }
        triangle_range[mi].length = tri_index - triangle_range[mi].location;
    }

    _displayLists.count = tri_index; // total number of triangle vertices
    return YES;

    OOJS_PROFILE_EXIT
}

#ifdef OO_DEBUG_MONITOR_ENABLED
void OOMesh::debugDrawNormals()
{
    GLuint i;
    Vector v, n, t, b;
    float length, blend;
    GLfloat color[3];
    OODebugWFState state;

    OO_ENTER_OPENGL();

    state = OODebugBeginWireframe(NO);

    // Draw
    OOGLBEGIN(GL_LINES);
    for (i = 0; i < _displayLists.count; ++i) {
        v = _displayLists.vertexArray[i];
        n = _displayLists.normalArray[i];
        t = _displayLists.tangentArray[i];
        b = true_cross_product(n, t);

        // Draw normal
        length = magnitude2(n);
        blend = fabs(length - 1) * 5.0;
        color[0] = MIN(blend, 1.0f);
        color[1] = 1.0f - color[0];
        color[2] = color[1];
        glColor3fv(color);

        glVertex3f(v.x, v.y, v.z);
        scale_vector(&n, 5.0f);
        n = vector_add(n, v);
        glVertex3f(n.x, n.y, n.z);

        // Draw tangent
        glColor3f(1.0f, 1.0f, 0.0f);
        t = vector_add(v, vector_multiply_scalar(t, 3.0f));
        glVertex3f(v.x, v.y, v.z);
        glVertex3f(t.x, t.y, t.z);

        // Draw bitangent
        glColor3f(0.0f, 1.0f, 0.0f);
        b = vector_add(v, vector_multiply_scalar(b, 3.0f));
        glVertex3f(v.x, v.y, v.z);
        glVertex3f(b.x, b.y, b.z);
    }
    OOGLEND();

    OODebugEndWireframe(state);
}
#endif

void OOMesh::setRetainedObject(oo::Data object, const std::string& key)
{
    _retainedObjects.insert_or_assign(key, oo::adopt(new OOMeshBuffer(std::move(object))));
}

/* valgrind complains that the memory allocated here isn't initialised
         at the time OOCacheManager::writeDict is pushing it to the
         cache. Not sure if that's a problem or not. - CIM */
void* OOMesh::allocateBytesWithSize(size_t size, NSUInteger count, const std::string& key)
{
    if (count == 0) {
        count = 1;
    }
    size *= count;
    oo::Data holder;
    holder.setLength(size); // zero-filled (malloc left it uninitialised)
    setRetainedObject(std::move(holder), key);
    void* bytes = _retainedObjects.find(key)->second->data().mutableBytes();
    if (bytes != NULL) {
        Scribble(bytes, size);
    }
    return bytes;
}

bool OOMesh::allocateVertexBuffersWithCount(NSUInteger /*count*/)
{
    _vertices = (Vector*)allocateBytesWithSize(sizeof *_vertices, vertexCount, "vertices");
    return _vertices != NULL;
}

bool OOMesh::allocateNormalBuffersWithCount(NSUInteger /*count*/)
{
    _normals = (Vector*)allocateBytesWithSize(sizeof *_normals, vertexCount, "normals");
    _tangents = (Vector*)allocateBytesWithSize(sizeof *_tangents, vertexCount, "tangents");
    return _normals != NULL && _tangents != NULL;
}

bool OOMesh::allocateFaceBuffersWithCount(NSUInteger /*count*/)
{
    _faces = (OOMeshFace*)allocateBytesWithSize(sizeof *_faces, faceCount, "faces");
    return _faces != NULL;
}

bool OOMesh::allocateVertexArrayBuffersWithCount(NSUInteger count)
{
    _displayLists.indexArray = (GLint*)allocateBytesWithSize(sizeof *_displayLists.indexArray, count * 3, "indexArray");
    _displayLists.textureUVArray = (GLfloat*)allocateBytesWithSize(sizeof *_displayLists.textureUVArray, count * 6, "textureUVArray");
    _displayLists.vertexArray = (Vector*)allocateBytesWithSize(sizeof *_displayLists.vertexArray, count * 3, "vertexArray");
    _displayLists.normalArray = (Vector*)allocateBytesWithSize(sizeof *_displayLists.normalArray, count * 3, "normalArray");
    _displayLists.tangentArray = (Vector*)allocateBytesWithSize(sizeof *_displayLists.tangentArray, count * 3, "tangentArray");

    return _faces != NULL && _displayLists.indexArray != NULL && _displayLists.textureUVArray != NULL && _displayLists.vertexArray != NULL && _displayLists.normalArray != NULL && _displayLists.tangentArray != NULL;
}

void OOMesh::renameTexturesFrom(const std::string& from, const std::string& to)
{
    /*	IMPORTANT: this has to be called before setUpMaterials..., so it can
            only be used during loading.
    */
    OOMeshMaterialCount i;
    for (i = 0; i != materialCount; i++) {
        if (materialKeys[i] == from) {
            materialKeys[i] = to;
        }
    }
}

static float FaceArea(GLuint* vertIndices, Vector* vertices)
{
    /*	Calculate areas using Heron's formula.	*/
    float a2 = distance2(vertices[vertIndices[0]], vertices[vertIndices[1]]);
    float b2 = distance2(vertices[vertIndices[1]], vertices[vertIndices[2]]);
    float c2 = distance2(vertices[vertIndices[2]], vertices[vertIndices[0]]);
    return sqrt((2.0f * (a2 * b2 + b2 * c2 + c2 * a2) - (a2 * a2 + b2 * b2 + c2 * c2)) * 0.0625f);
}

static float FaceAreaCorrect(GLuint* vertIndices, Vector* vertices)
{
    /*	Calculate area of triangle.
            The magnitude of the cross product of two vectors is the area of
            the parallelogram they span. The area of a triangle is half the
            area of a parallelogram sharing two of its sides.
            Since we only use the area of the triangle as a weight factor,
            constant terms are irrelevant, so we don't bother halving the
            value.
    */
    Vector AB = vector_subtract(vertices[vertIndices[1]], vertices[vertIndices[0]]);
    Vector AC = vector_subtract(vertices[vertIndices[2]], vertices[vertIndices[0]]);
    return magnitude(true_cross_product(AB, AC));
}

void OOMesh::checkNormalsAndAdjustWinding()
{
    OOJS_PROFILE_ENTER

    Vector calculatedNormal;
    OOMeshFaceCount i;

    OOCParameterAssert(_normalMode != kNormalModeExplicit);

    for (i = 0; i < faceCount; i++) {
        Vector v0, v1, v2, norm;
        v0 = _vertices[_faces[i].vertex[0]];
        v1 = _vertices[_faces[i].vertex[1]];
        v2 = _vertices[_faces[i].vertex[2]];
        norm = _faces[i].normal;

        calculatedNormal = normal_to_surface(v2, v1, v0);
        if (vector_equal(norm, kZeroVector)) {
            norm = vector_flip(calculatedNormal);
            _faces[i].normal = norm;
        }

        /*	FIXME: for 2.0, either require explicit normals for every model
                or change to: if (dot_product(norm, calculatedNormal) < 0.0f)
                -- Ahruman 2010-01-23
        */
        if (norm.x * calculatedNormal.x < 0 || norm.y * calculatedNormal.y < 0 || norm.z * calculatedNormal.z < 0) {
            // normal lies in the WRONG direction!
            // reverse the winding
            int v0 = _faces[i].vertex[0];
            _faces[i].vertex[0] = _faces[i].vertex[2];
            _faces[i].vertex[2] = v0;

            GLfloat f0 = _faces[i].s[0];
            _faces[i].s[0] = _faces[i].s[2];
            _faces[i].s[2] = f0;

            f0 = _faces[i].t[0];
            _faces[i].t[0] = _faces[i].t[2];
            _faces[i].t[2] = f0;
        }
    }

    OOJS_PROFILE_EXIT_VOID
}

void OOMesh::generateFaceTangents()
{
    OOJS_PROFILE_ENTER

    OOMeshFaceCount i;
    for (i = 0; i < faceCount; i++) {
        OOMeshFace* face = _faces + i;

        /*	Generate tangents, i.e. vectors that run in the direction of the s
                texture coordinate. Based on code I found in a forum somewhere and
                then lost track of. Sorry to whomever I should be crediting.
                -- Ahruman 2008-11-23
        */
        Vector vAB = vector_subtract(_vertices[face->vertex[1]], _vertices[face->vertex[0]]);
        Vector vAC = vector_subtract(_vertices[face->vertex[2]], _vertices[face->vertex[0]]);
        Vector nA = face->normal;

        // projAB = aB - (nA . vAB) * nA
        Vector vProjAB = vector_subtract(vAB, vector_multiply_scalar(nA, dot_product(nA, vAB)));
        Vector vProjAC = vector_subtract(vAC, vector_multiply_scalar(nA, dot_product(nA, vAC)));

        // delta s/t
        GLfloat dsAB = face->s[1] - face->s[0];
        GLfloat dsAC = face->s[2] - face->s[0];
        GLfloat dtAB = face->t[1] - face->t[0];
        GLfloat dtAC = face->t[2] - face->t[0];

        if (dsAC * dtAB > dsAB * dtAC) {
            face->tangent = vector_normal(vector_subtract(vector_multiply_scalar(vProjAC, dtAB), vector_multiply_scalar(vProjAB, dtAC)));
        } else {
            face->tangent = vector_normal(vector_subtract(vector_multiply_scalar(vProjAB, dtAC), vector_multiply_scalar(vProjAC, dtAB)));
        }
    }

    OOJS_PROFILE_EXIT_VOID
}

void OOMesh::calculateVertexNormalsAndTangentsWithFaceRefs(VertexFaceRef* faceRefs)
{
    OOJS_PROFILE_ENTER

    OOCParameterAssert(faceRefs != NULL);

    NSUInteger i, j;
    std::vector<float> triangle_area(faceCount);

    OOCAssert(_normals != NULL && _tangents != NULL, "Normal/tangent buffers not allocated in %s", __PRETTY_FUNCTION__);

    for (i = 0; i < faceCount; i++) {
        triangle_area[i] = FaceArea(_faces[i].vertex, _vertices);
    }
    for (i = 0; i < vertexCount; i++) {
        Vector normal_sum = kZeroVector;
        Vector tangent_sum = kZeroVector;

        VertexFaceRef* vfr = &faceRefs[i];
        NSUInteger fIter, fCount = VFRGetCount(vfr);
        for (fIter = 0; fIter < fCount; fIter++) {
            j = VFRGetFaceAtIndex(vfr, fIter);

            float t = triangle_area[j]; // weight sum by area
            normal_sum = vector_add(normal_sum, vector_multiply_scalar(_faces[j].normal, t));
            tangent_sum = vector_add(tangent_sum, vector_multiply_scalar(_faces[j].tangent, t));
        }

        normal_sum = vector_normal_or_fallback(normal_sum, kBasisZVector);
        tangent_sum = vector_subtract(tangent_sum, vector_multiply_scalar(normal_sum, dot_product(tangent_sum, normal_sum)));
        tangent_sum = vector_normal_or_fallback(tangent_sum, kBasisXVector);

        _normals[i] = normal_sum;
        _tangents[i] = tangent_sum;
    }

    OOJS_PROFILE_EXIT_VOID
}

void OOMesh::calculateVertexTangentsWithFaceRefs(VertexFaceRef* faceRefs)
{
    OOJS_PROFILE_ENTER

    OOCParameterAssert(faceRefs != NULL);

    /*	This is conceptually broken.
            At the moment, it's calculating one tangent per "input" vertex. It should
            be calculating one tangent per "real" vertex, where a "real" vertex is
            defined as a combination of position, normal, material and texture
            coordinates.
            Currently, we don't have a format with unique "real" vertices.
            This basically means explicit-normal models without explicit tangents
            can't usefully be normal mapped.
            I don't intend to do anything about this pre-MSNR, although it might be
            possible to fix it by moving tangent generation to the same stage as
            smooth-grouped normal generation.
            -- Ahruman 2010-05-22
    */
    NSUInteger i, j;
    std::vector<float> triangle_area(faceCount);
    for (i = 0; i < faceCount; i++) {
        triangle_area[i] = FaceAreaCorrect(_faces[i].vertex, _vertices);
    }
    for (i = 0; i < vertexCount; i++) {
        Vector tangent_sum = kZeroVector;

        VertexFaceRef* vfr = &faceRefs[i];
        NSUInteger fIter, fCount = VFRGetCount(vfr);
        for (fIter = 0; fIter < fCount; fIter++) {
            j = VFRGetFaceAtIndex(vfr, fIter);

            float t = triangle_area[j]; // weight sum by area
            tangent_sum = vector_add(tangent_sum, vector_multiply_scalar(_faces[j].tangent, t));
        }

        tangent_sum = vector_subtract(tangent_sum, vector_multiply_scalar(_normals[i], dot_product(_normals[i], tangent_sum)));
        tangent_sum = vector_normal_or_fallback(tangent_sum, kBasisXVector);

        _tangents[i] = tangent_sum;
    }

    OOJS_PROFILE_EXIT_VOID
}

/* profiling suggests this function takes a lot of time - almost all
 * the overhead of setting up a new ship is here. - CIM */
void OOMesh::getNormal(Vector* outNormal, Vector* outTangent, OOMeshVertexCount v_index, OOMeshSmoothGroup smoothGroup)
{
    OOJS_PROFILE_ENTER

    assert(outNormal != NULL && outTangent != NULL);

    NSUInteger j;
    Vector normal_sum = kZeroVector;
    Vector tangent_sum = kZeroVector;
    for (j = 0; j < faceCount; j++) {
        if (_faces[j].smoothGroup == smoothGroup) {
            if ((_faces[j].vertex[0] == v_index) || (_faces[j].vertex[1] == v_index) || (_faces[j].vertex[2] == v_index)) {
                float area = FaceArea(_faces[j].vertex, _vertices);
                normal_sum = vector_add(normal_sum, vector_multiply_scalar(_faces[j].normal, area));
                tangent_sum = vector_add(tangent_sum, vector_multiply_scalar(_faces[j].tangent, area));
            }
        }
    }

    *outNormal = vector_normal_or_fallback(normal_sum, kBasisZVector);
    *outTangent = vector_normal_or_fallback(tangent_sum, kBasisXVector);

    OOJS_PROFILE_EXIT_VOID
}

void OOMesh::calculateBoundingVolumes()
{
    OOJS_PROFILE_ENTER

    OOMeshVertexCount i;
    float d_squared, length_longest_axis, length_shortest_axis;
    GLfloat result;

    result = 0.0f;
    if (vertexCount)
        bounding_box_reset_to_vector(&_boundingBox, _vertices[0]);
    else
        bounding_box_reset(&_boundingBox);

    for (i = 0; i < vertexCount; i++) {
        d_squared = magnitude2(_vertices[i]);
        if (d_squared > result)
            result = d_squared;
        bounding_box_add_vector(&_boundingBox, _vertices[i]);
    }

    length_longest_axis = _boundingBox.max.x - _boundingBox.min.x;
    if (_boundingBox.max.y - _boundingBox.min.y > length_longest_axis)
        length_longest_axis = _boundingBox.max.y - _boundingBox.min.y;
    if (_boundingBox.max.z - _boundingBox.min.z > length_longest_axis)
        length_longest_axis = _boundingBox.max.z - _boundingBox.min.z;

    length_shortest_axis = _boundingBox.max.x - _boundingBox.min.x;
    if (_boundingBox.max.y - _boundingBox.min.y < length_shortest_axis)
        length_shortest_axis = _boundingBox.max.y - _boundingBox.min.y;
    if (_boundingBox.max.z - _boundingBox.min.z < length_shortest_axis)
        length_shortest_axis = _boundingBox.max.z - _boundingBox.min.z;

    d_squared = (length_longest_axis + length_shortest_axis) * (length_longest_axis + length_shortest_axis) * 0.25; // square of average length
    _maxDrawDistance = d_squared * NO_DRAW_DISTANCE_FACTOR * NO_DRAW_DISTANCE_FACTOR; // no longer based on the collision radius

    _collisionRadius = sqrtf(result);

    OOJS_PROFILE_EXIT_VOID
}

void OOMesh::rescaleByFactor(GLfloat factor)
{
    // Rescale base vertices used for geometry calculations.
    OOMeshVertexCount i;
    Vector* vertex = NULL;

    for (i = 0; i < vertexCount; i++) {
        vertex = &_vertices[i];
        *vertex = vector_multiply_scalar(*vertex, factor);
    }

    // Rescale actual display vertices.
    for (i = 0; i < _displayLists.count; i++) {
        vertex = &_displayLists.vertexArray[i];
        *vertex = vector_multiply_scalar(*vertex, factor);
    }

    calculateBoundingVolumes();
    octree = nullptr;
    baseFile.reset(); // Avoid octree cache.
    baseFileOctreeCacheRef.reset();
}

BoundingBox OOMesh::boundingBox()
{
    return _boundingBox;
}

static const char* const kOOCacheMeshes = "OOMesh";

// The OOCacheManager (OOMesh) category, as free functions next to the cache (the slice plan).

namespace {

oo::PList OOCacheManagerMeshDataForName(const std::string& inShipName)
{
    return OOCacheManager::sharedCache()->pListForKey(inShipName, kOOCacheMeshes);
}

void OOCacheManagerSetMeshData(const oo::PList& inData, const std::string& inShipName)
{
    if (inData) {
        OOCacheManager::sharedCache()->setPList(inData, inShipName, kOOCacheMeshes);
    }
}

} // namespace

static const char* const kOOCacheOctrees = "octrees";

// The OOCacheManager (Octree) category, as free functions next to the cache (OOMesh.h).

oo::Ref<Octree> OOCacheManagerOctreeForModel(const std::string& inKey)
{
    oo::Ref<Octree> result;
    OOCacheManager* cache = OOCacheManager::sharedCache();

    const oo::PList data = cache->pListForKey(inKey, kOOCacheOctrees); // null: absent
    if (data) {
        result = Octree::initWithDictionary(data);
    }

    return result;
}

void OOCacheManagerSetOctree(Octree* inOctree, const std::string& inKey)
{
    if (inOctree != nullptr) {
        OOCacheManager::sharedCache()->setPList(inOctree->dictionaryRepresentation(), inKey, kOOCacheOctrees);
    }
}

static void VFRAddFace(VertexFaceRef* vfr, NSUInteger index)
{
    OOCParameterAssert(vfr != NULL);

    if (index < UINT16_MAX && vfr->internCount < kVertexFaceDefInternalCount) {
        vfr->internFaces[vfr->internCount++] = index;
    } else {
        vfr->extra.push_back(index);
    }
}

static NSUInteger VFRGetCount(VertexFaceRef* vfr)
{
    OOCParameterAssert(vfr != NULL);

    return vfr->internCount + vfr->extra.size();
}

static NSUInteger VFRGetFaceAtIndex(VertexFaceRef* vfr, NSUInteger index)
{
    OOCParameterAssert(vfr != NULL && index < VFRGetCount(vfr));

    if (index < vfr->internCount)
        return vfr->internFaces[index];
    else
        return vfr->extra[index - vfr->internCount];
}
