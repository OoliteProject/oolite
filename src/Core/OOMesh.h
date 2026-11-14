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

#import "OODrawable.h"
#import "OOOpenGL.h"
#import "OOOpenGLExtensionManager.h"
#import "OOWeakReference.h"

#include "oofnd/PList.hpp"
#include "oofnd/Ref.hpp"
#include "oofnd/StdLib.hpp"

@class OOMaterial, Octree;
class OOMeshBuffer; // OOMesh.mm: one refcounted buffer (an oo::Data), shared by a mesh and its mutable copies

#define OOMESH_PROFILE 0
#if OOMESH_PROFILE
#import "OOProfilingStopwatch.h"
#endif

enum {
    kOOMeshMaxMaterials = 8
};

typedef uint16_t OOMeshSmoothGroup;
typedef uint8_t OOMeshMaterialIndex, OOMeshMaterialCount;
typedef uint32_t OOMeshVertexCount;
typedef uint32_t OOMeshFaceCount;
typedef uint8_t OOMeshFaceVertexCount;

typedef struct
{
    OOMeshSmoothGroup smoothGroup;
    OOMeshMaterialIndex materialIndex;
    GLuint vertex[3];

    Vector normal;
    Vector tangent;
    GLfloat s[3];
    GLfloat t[3];
} OOMeshFace;

typedef struct
{
    GLint* indexArray;
    GLfloat* textureUVArray;
    Vector* vertexArray;
    Vector* normalArray;
    Vector* tangentArray;

    GLuint count;
} OOMeshDisplayLists;

@interface OOMesh : OODrawable <OOCopying> {
@private
    uint8_t _normalMode : 2,
        brokenInRender : 1,
        listsReady : 1;

    OOMeshMaterialCount materialCount;
    OOMeshVertexCount vertexCount;
    OOMeshFaceCount faceCount;

    std::optional<std::string> baseFile; // "No Model" until loaded; nullopt after -rescaleByFactor: (no octree cache)
    std::optional<std::string> baseFileOctreeCacheRef;
    BOOL _cacheWriteable;

    Vector* _vertices;
    Vector* _normals;
    Vector* _tangents;
    OOMeshFace* _faces;

    // Redundancy! Needs fixing.
    OOMeshDisplayLists _displayLists;

    NSRange triangle_range[kOOMeshMaxMaterials];
    std::string materialKeys[kOOMeshMaxMaterials];
    OOMaterial* materials[kOOMeshMaxMaterials];
    GLuint displayList0;

    GLfloat collisionRadius;
    GLfloat maxDrawDistance;
    BoundingBox boundingBox;

    Octree* octree;

    std::map<std::string, oo::Ref<OOMeshBuffer>, std::less<>> _retainedObjects; // the buffers _vertices & co. point into, by key

    oo::PList _materialDict; // mixed configurations (proposed ADR-0043 Amendment 2); null = nil
    oo::PList _shadersDict;
    std::optional<std::string> _cacheKey; // nil and @"" differ for OOMaterial
    oo::PList _shaderMacros;
    id _shaderBindingTarget;

    Vector _lastPosition;
    OOMatrix _lastRotMatrix;
    BoundingBox _lastBoundingBox;

#if OO_MULTITEXTURE
    NSUInteger _textureUnitCount;
#endif

#if OOMESH_PROFILE
    oo::Ref<OOProfilingStopwatch> _stopwatch;
    double _stopwatchLastTime;
#endif
}

+ (instancetype)meshWithName:(const std::string&)name
                    cacheKey:(const std::optional<std::string>&)cacheKey
          materialDictionary:(const oo::PList&)materialDict
           shadersDictionary:(const oo::PList&)shadersDict
                      smooth:(BOOL)smooth
                shaderMacros:(const oo::PList&)macros
         shaderBindingTarget:(id<OOWeakReferenceSupport>)object;

+ (instancetype)meshWithName:(const std::string&)name
                    cacheKey:(const std::optional<std::string>&)cacheKey
          materialDictionary:(const oo::PList&)materialDict
           shadersDictionary:(const oo::PList&)shadersDict
                      smooth:(BOOL)smooth
                shaderMacros:(const oo::PList&)macros
         shaderBindingTarget:(id<OOWeakReferenceSupport>)object
                 scaleFactor:(float)factor
              cacheWriteable:(BOOL)cacheWriteable;

+ (OOMaterial*)placeholderMaterial;

- (std::optional<std::string>)modelName;

- (void)rebindMaterials;

- (oo::PList)materials; // null: none
- (oo::PList)shaders;

- (size_t)vertexCount;
- (size_t)faceCount;

- (Octree*)octree;

// This needs a better name.
- (BoundingBox)findBoundingBoxRelativeToPosition:(Vector)opv
                                              ri:(Vector)ri
                                              rj:(Vector)rj
                                              rk:(Vector)rk
                                    selfPosition:(Vector)position
                                              si:(Vector)si
                                              sj:(Vector)sj
                                              sk:(Vector)sk;
- (BoundingBox)findSubentityBoundingBoxWithPosition:(Vector)position rotMatrix:(OOMatrix)rotMatrix;

- (OOMesh*)meshRescaledBy:(GLfloat)scaleFactor;

@end

#import "OOCacheManager.h"
@interface OOCacheManager (Octree)

+ (Octree*)octreeForModel:(const std::string&)inKey;
+ (void)setOctree:(Octree*)inOctree forModel:(const std::string&)inKey;

@end
