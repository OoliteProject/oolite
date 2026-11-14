/*

OOSkyDrawable.m


Copyright (C) 2007-2013 Jens Ayton

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

*/

#include "OOSkyDrawable.h"
#include "GameController.h"
#include "OOColor.h"
#include "OOGraphicsResetManager.h"
#include "OOMacroOpenGL.h"
#include "OOProbabilisticTextureManager.h"
#include "OOTexture.h"
#include "ResourceManager.h"
#include "Universe.h"

#include "oofnd/Defaults.hpp"
#include "oofnd/String.hpp"
#include "oofnd/objc/OOException.h"

#define SKY_ELEMENT_SCALE_FACTOR (BILLBOARD_DEPTH / 500.0f)
#define NEBULA_SHUFFLE_FACTOR 0.005f
#define DEBUG_COLORS 0 // If set, rgb = xyz (offset to range from 0.1 to 1.0).

/*	Min and max coords are 0 and 1 normally, but the default
        sky-render-inset-coords can be used to modify them slightly as an attempted
        work-around for artefacts on buggy S3/Via renderers.
*/
namespace {

float sMinTexCoord = 0.0f, sMaxTexCoord = 1.0f;
BOOL sInited = NO;

} // namespace

/*	Struct used to describe quads initially. This form is optimized for
        reasoning about.
        The colour is owned (it was autoreleased into the initialiser's pool), so the quads are a
        std::vector, not malloc()ed (bead oo-4jjl).
*/
struct OOSkyQuadDesc {
    Vector corners[4];
    oo::Ref<OOColor> color;
    OOTexture* texture;
};

enum : uint8_t {
    kSkyQuadSetPositionEntriesPerVertex = 3,
    kSkyQuadSetTexCoordEntriesPerVertex = 2,
    kSkyQuadSetColorEntriesPerVertex = 4
};

/*	Class containing a set of quads with the same texture. This form is
        optimized for rendering.
        A second class in the file with no caller outside it: global, no facade (amendment oo-vt0o
        item 2).
*/
class OOSkyQuadSet : public oo::RefCounted {
public:
    static void addQuads(OOSkyQuadDesc* quads, unsigned count, std::vector<oo::Ref<OOSkyQuadSet>>& ioArray);

    // Null where -initWithQuadsWithTexture:inArray:count: answered nil (amendment oo-novu).
    static oo::Ref<OOSkyQuadSet> initWithQuadsWithTexture(OOTexture* texture, OOSkyQuadDesc* array, unsigned totalCount);

    ~OOSkyQuadSet();

    // What "%@" printed between the braces of <OOSkyQuadSet 0x...>{...}.
    std::optional<std::string> descriptionComponents() const;

    void render();

#ifdef OO_DEBUG_MONITOR_ENABLED
    size_t totalSize();
    OOTexture* texture();
#endif

private:
    oo::Ref<OOTexture> _texture;
    unsigned _count = { };
    GLfloat* _positions = nullptr; // 3 entries per vertex, 12 per quad
    GLfloat* _texCoords = nullptr; // 2 entries per vertex, 8 per quad
    GLfloat* _colors = nullptr; // 4 entries per vertex, 16 per quad
};

/*	Textures are global because there is always a sky, but the sky isn't
        replaced very often, so the textures are likely to fall out of the cache.
*/
namespace {

OOProbabilisticTextureManager* sStarTextures;
OOProbabilisticTextureManager* sNebulaTextures;

oo::Ref<OOColor> SaturatedColorInRange(OOColor* color1, OOColor* color2, BOOL hueFix);

} // namespace

void (*OOSkyDrawable::sSetUpStarsStandIn)(OOSkyDrawable* sky, OOColor* color1, OOColor* color2) = nullptr;

OOSkyDrawable::OOSkyDrawable(OOColor* color1,
    OOColor* color2,
    OOColor* color3,
    OOColor* color4,
    unsigned starCount,
    unsigned nebulaCount,
    bool nebulaHueFix,
    float nebulaClusterFactor,
    float nebulaAlpha,
    float nebulaScale)
{
    if (!sInited) {
        sInited = YES;
        if (oo::Defaults::standard().boolForKey("sky-render-inset-coords")) {
            sMinTexCoord += 1.0f / 128.0f;
            sMaxTexCoord -= 1.0f / 128.0f;
        }
    }

    // self = [super init]: could not fail (amendment oo-lh0x item 3).

    _starCount = starCount;
    _nebulaCount = nebulaCount;

    {
        setUpStars(color1, color2);

        if (!(UNIVERSE != nullptr ? UNIVERSE->reducedDetail() : false)) {
            setUpNebulae(color3,
                color4,
                nebulaClusterFactor,
                nebulaHueFix,
                nebulaAlpha,
                nebulaScale);
        }
    }

    OOGraphicsResetManager::sharedManager()->registerCxxClient(this);
}

OOSkyDrawable::~OOSkyDrawable()
{
    OO_ENTER_OPENGL();

    OOGraphicsResetManager::sharedManager()->unregisterCxxClient(this);
    if (_displayListName != 0)
        glDeleteLists(_displayListName, 1);
}

void OOSkyDrawable::renderOpaqueParts()
{
    // While technically translucent, the sky doesn't need to be depth-sorted
    // since it'll be behind everything else anyway.

    OO_ENTER_OPENGL();
    OOSetOpenGLState(OPENGL_STATE_ADDITIVE_BLENDING);

    OOGL(glDisable(GL_DEPTH_TEST)); // don't read the depth buffer
    OOGL(glEnable(GL_TEXTURE_2D));

    // Make stars dim in atmosphere. Note: works OK on night side because sky is dark blue, not black.
    GLfloat fogColor[4] = { 0.02, 0.02, 0.02, 1.0 };
    OOGL(glFogfv(GL_FOG_COLOR, fogColor));

    if (_displayListName != 0) {
        OOGL(glCallList(_displayListName));
    } else {
        // Set up display list
        ensureTexturesLoaded();
        _displayListName = glGenLists(1);

        OOGL(glNewList(_displayListName, GL_COMPILE));

        OOGL(glEnableClientState(GL_TEXTURE_COORD_ARRAY));
        OOGL(glEnableClientState(GL_COLOR_ARRAY));

        for (const oo::Ref<OOSkyQuadSet>& quadSet : _quadSets)
            quadSet->render();

        OOGL(glDisableClientState(GL_TEXTURE_COORD_ARRAY));
        OOGL(glDisableClientState(GL_COLOR_ARRAY));

        OOGL(glEndList());
    }

    // Restore state
    OOGL(glEnable(GL_DEPTH_TEST));
    OOGL(glDisable(GL_TEXTURE_2D));

    // Resetting fog is draw loop's responsibility.

    OOVerifyOpenGLState();
    cxx_OOCheckOpenGLErrors("OOSkyDrawable after rendering");
}

bool OOSkyDrawable::hasOpaqueParts()
{
    return YES;
}

GLfloat OOSkyDrawable::maxDrawDistance()
{
    return INFINITY;
}

#ifdef OO_DEBUG_MONITOR_ENABLED
std::vector<oo::Ref<OOTexture>> OOSkyDrawable::allTextures()
{
    std::vector<oo::Ref<OOTexture>> result;
    result.reserve(_quadSets.size());

    for (const oo::Ref<OOSkyQuadSet>& quadSet : _quadSets) {
        result.emplace_back(quadSet->texture());
    }

    return result;
}

size_t OOSkyDrawable::totalSize()
{
    size_t result = OODrawable::totalSize();

    for (const oo::Ref<OOSkyQuadSet>& quadSet : _quadSets) {
        result += quadSet->totalSize();
    }

    return result;
}
#endif

#if DEBUG_COLORS
namespace {

oo::Ref<OOColor> DebugColor(Vector orientation)
{
    Vector color = vector_add(make_vector(0.55, 0.55, 0.55), vector_multiply_scalar(vector_normal(orientation), 0.45));
    return OOColor::colorWithRed(color.x, color.y, color.z, 1.0);
}

} // namespace
#endif

// The category OOSkyDrawable (OOPrivate): private members.

void OOSkyDrawable::setUpStars(OOColor* color1, OOColor* color2)
{
    if (sSetUpStarsStandIn != nullptr) {
        sSetUpStarsStandIn(this, color1, color2);
        return;
    }

    std::vector<OOSkyQuadDesc> quads;
    OOSkyQuadDesc* currQuad = NULL;
    unsigned i;
    Quaternion q;
    Vector vi, vj, vk;
    float size;
    Vector middle, offset;

    loadStarTextures();

    quads.resize(_starCount);

    currQuad = quads.data();
    for (i = 0; i != _starCount; ++i) {
        // Select a direction and rotation.
        q = OORandomQuaternion();
        basis_vectors_from_quaternion(q, &vi, &vj, &vk);

        // Select colour and texture.
#if DEBUG_COLORS
        currQuad->color = DebugColor(vk);
#else
        // The fraction is drawn even for no colour, as the message's argument was.
        const float fraction = randf();
        currQuad->color = (color1 != nullptr) ? color1->blendedColorWithFraction(fraction, color2) : nullptr;
#endif
        currQuad->texture = (sStarTextures != nullptr) ? sStarTextures->selectTexture() : nil; // Not retained, since sStarTextures is never released.

        // Select scale; calculate centre position and offset to first corner.
        size = (1 + (ranrot_rand() % 6)) * SKY_ELEMENT_SCALE_FACTOR;
        middle = vector_multiply_scalar(vk, BILLBOARD_DEPTH);
        offset = vector_multiply_scalar(vector_add(vi, vj), 0.5f * size);

        // Scale the "side" vectors.
        Vector vj2 = vector_multiply_scalar(vj, size);
        Vector vi2 = vector_multiply_scalar(vi, size);

        // Set up corners.
        currQuad->corners[0] = vector_subtract(middle, offset);
        currQuad->corners[1] = vector_add(currQuad->corners[0], vj2);
        currQuad->corners[2] = vector_add(currQuad->corners[1], vi2);
        currQuad->corners[3] = vector_add(currQuad->corners[0], vi2);

        ++currQuad;
    }

    addQuads(quads.data(), _starCount);
}

void OOSkyDrawable::setUpNebulae(OOColor* color1,
    OOColor* color2,
    float nebulaClusterFactor,
    bool nebulaHueFix,
    float nebulaAlpha,
    float nebulaScale)
{
    std::vector<OOSkyQuadDesc> quads;
    OOSkyQuadDesc* currQuad = NULL;
    unsigned i, actualCount = 0;
    oo::Ref<OOColor> color;
    Quaternion q;
    Vector vi, vj, vk;
    double size, r2;
    Vector middle, offset;
    int r1;

    loadNebulaTextures();

    quads.resize(_nebulaCount);

    currQuad = quads.data();
    for (i = 0; i < _nebulaCount; ++i) {
        color = SaturatedColorInRange(color1, color2, nebulaHueFix);

        // Select a direction and rotation.
        q = OORandomQuaternion();

        // Create a cluster of nebula quads.
        while ((i < _nebulaCount) && (randf() < nebulaClusterFactor)) {
            // Select size.
            r1 = 1 + (ranrot_rand() & 15);
            size = nebulaScale * r1 * SKY_ELEMENT_SCALE_FACTOR;

            // Calculate centre position and offset to first corner.
            basis_vectors_from_quaternion(q, &vi, &vj, &vk);

            // Select colour and texture. Smaller nebula quads are dimmer.
#if DEBUG_COLORS
            currQuad->color = DebugColor(vk);
#else
            currQuad->color = (color != nullptr) ? color->colorWithBrightnessFactor(nebulaAlpha * (0.5f + (float)r1 / 32.0f)) : nullptr;
#endif
            currQuad->texture = (sNebulaTextures != nullptr) ? sNebulaTextures->selectTexture() : nil; // Not retained, since sStarTextures is never released.

            middle = vector_multiply_scalar(vk, BILLBOARD_DEPTH);
            offset = vector_multiply_scalar(vector_add(vi, vj), 0.5f * size);

            // Rotate vi and vj by a random angle
            r2 = randf() * M_PI * 2.0;
            quaternion_rotate_about_axis(&q, vk, r2);
            vi = vector_right_from_quaternion(q);
            vj = vector_up_from_quaternion(q);

            // Scale the "side" vectors.
            vj = vector_multiply_scalar(vj, size);
            vi = vector_multiply_scalar(vi, size);

            // Set up corners.
            currQuad->corners[0] = vector_subtract(middle, offset);
            currQuad->corners[1] = vector_add(currQuad->corners[0], vj);
            currQuad->corners[2] = vector_add(currQuad->corners[1], vi);
            currQuad->corners[3] = vector_add(currQuad->corners[0], vi);

            // Shuffle direction quat around a bit to spread the cluster out.
            size = NEBULA_SHUFFLE_FACTOR / (nebulaScale * SKY_ELEMENT_SCALE_FACTOR);
            q.x += size * (randf() - 0.5);
            q.y += size * (randf() - 0.5);
            q.z += size * (randf() - 0.5);
            q.w += size * (randf() - 0.5);
            quaternion_normalize(&q);

            ++i;
            ++currQuad;
            ++actualCount;
        }
    }

    /*	The above code generates less than _nebulaCount quads, because i is
            incremented once in the outer loop as well as in the inner loop. To
            keep skies looking the same, we leave the bug in and fill in the
            actual generated count here.
    */
    _nebulaCount = actualCount;

    addQuads(quads.data(), _nebulaCount);
}

void OOSkyDrawable::addQuads(OOSkyQuadDesc* quads, unsigned count)
{
    OOSkyQuadSet::addQuads(quads, count, _quadSets);
}

void OOSkyDrawable::loadStarTextures()
{
    if (sStarTextures == nullptr) {
        sStarTextures = OOProbabilisticTextureManager::createWithPListName("startextures.plist",
            kOOTextureMinFilterMipMap | kOOTextureMagFilterLinear | kOOTextureAlphaMask,
            0.0f,
            -0.0f)
                            .leakRef();
        if (sStarTextures == nullptr) {
            OORaiseException(OOLITE_EXCEPTION_DATA_NOT_FOUND, "No star textures could be loaded.");
        }
    }

    sStarTextures->setSeed(RANROTGetFullSeed());
}

void OOSkyDrawable::loadNebulaTextures()
{
    if (sNebulaTextures == nullptr) {
        sNebulaTextures = OOProbabilisticTextureManager::createWithPListName("nebulatextures.plist",
            kOOTextureDefaultOptions | kOOTextureAlphaMask,
            0.0f,
            0.0f)
                              .leakRef();
        if (sNebulaTextures == nullptr) {
            OORaiseException(OOLITE_EXCEPTION_DATA_NOT_FOUND, "No nebula textures could be loaded.");
        }
    }

    sNebulaTextures->setSeed(RANROTGetFullSeed());
}

void OOSkyDrawable::ensureTexturesLoaded()
{
    if (sStarTextures != nullptr)
        sStarTextures->ensureTexturesLoaded();
    if (sNebulaTextures != nullptr)
        sNebulaTextures->ensureTexturesLoaded();
}

void OOSkyDrawable::resetGraphicsState()
{
    OO_ENTER_OPENGL();

    if (_displayListName != 0) {
        glDeleteLists(_displayListName, 1);
        _displayListName = 0;
    }
}

// OOSkyQuadSet

void OOSkyQuadSet::addQuads(OOSkyQuadDesc* quads, unsigned count, std::vector<oo::Ref<OOSkyQuadSet>>& ioArray)
{
    std::vector<oo::Ref<OOTexture>> seenTextures; // by identity (textures do not override -isEqual:)
    OOTexture* texture = nil;
    oo::Ref<OOSkyQuadSet> quadSet;
    unsigned i;

    // Iterate over all quads.
    for (i = 0; i != count; ++i) {
        texture = quads[i].texture;

        // If we haven't seen this quad's texture before...
        if (std::find(seenTextures.begin(), seenTextures.end(), texture) == seenTextures.end()) {
            seenTextures.emplace_back(texture);

            // ...create a quad set for this texture.
            quadSet = initWithQuadsWithTexture(texture, quads, count);
            if (quadSet != nullptr) {
                ioArray.push_back(quadSet);
            }
        }
    }
}

oo::Ref<OOSkyQuadSet> OOSkyQuadSet::initWithQuadsWithTexture(OOTexture* texture, OOSkyQuadDesc* array, unsigned totalCount)
{
    BOOL OK = YES;
    unsigned i, j, vertexCount;
    GLfloat* pos;
    GLfloat* tc;
    GLfloat* col;
    GLfloat r, g, b, x;
    size_t posSize, tcSize, colSize;
    unsigned count = 0;
    // -integerForKey: gives 0 wherever get<NSInteger>(key, 0) fell back to the default.
    int skyColorCorrection = (int)oo::Defaults::standard().integerForKey("sky-color-correction");

// Hejl / Burgess-Dawson filmic tone mapping
// this algorithm has gamma correction already embedded
#define SKYCOLOR_TONEMAP_COMPONENT(skyColorComponent)                  \
    do {                                                               \
        x = MAX(0.0, (skyColorComponent) - 0.004);                     \
        *col++ = (x * (6.2 * x + 0.5)) / (x * (6.2 * x + 1.7) + 0.06); \
    } while (0)

    oo::Ref<OOSkyQuadSet> self = oo::makeRef<OOSkyQuadSet>(); // [super init] could not fail

    if (OK) {
        // Count the quads in the array using this texture.
        for (i = 0; i != totalCount; ++i) {
            if (array[i].texture == texture)
                ++self->_count;
        }
        if (self->_count == 0)
            OK = NO;
    }

    if (OK) {
        // Allocate arrays.
        vertexCount = self->_count * 4;
        posSize = sizeof *self->_positions * vertexCount * kSkyQuadSetPositionEntriesPerVertex;
        tcSize = sizeof *self->_texCoords * vertexCount * kSkyQuadSetTexCoordEntriesPerVertex;
        colSize = sizeof *self->_colors * vertexCount * kSkyQuadSetColorEntriesPerVertex;

        self->_positions = (GLfloat*)malloc(posSize);
        self->_texCoords = (GLfloat*)malloc(tcSize);
        self->_colors = (GLfloat*)malloc(colSize);

        if (self->_positions == NULL || self->_texCoords == NULL || self->_colors == NULL)
            OK = NO;

        pos = self->_positions;
        tc = self->_texCoords;
        col = self->_colors;
    }

    if (OK) {
        // Find the matching quads again, and convert them to renderable representation.
        for (i = 0; i != totalCount; ++i) {
            if (array[i].texture == texture) {
                // A message to a nil colour answered 0.
                OOColor* color = array[i].color.get();
                r = (color != nullptr) ? color->redComponent() : 0.0f;
                g = (color != nullptr) ? color->greenComponent() : 0.0f;
                b = (color != nullptr) ? color->blueComponent() : 0.0f;

                // Loop over vertices
                for (j = 0; j != 4; ++j) {
                    *pos++ = array[i].corners[j].x;
                    *pos++ = array[i].corners[j].y;
                    *pos++ = array[i].corners[j].z;

                    // Colour is the same for each vertex
                    if (skyColorCorrection == 0) // no color correction
                    {
                        *col++ = r;
                        *col++ = g;
                        *col++ = b;
                    } else if (skyColorCorrection == 1) // gamma correction only
                    {
                        *col++ = pow(r, 1.0 / 2.2);
                        *col++ = pow(g, 1.0 / 2.2);
                        *col++ = pow(b, 1.0 / 2.2);
                    } else // gamma correctioin + filmic tone mapping
                    {
                        SKYCOLOR_TONEMAP_COMPONENT(r);
                        SKYCOLOR_TONEMAP_COMPONENT(g);
                        SKYCOLOR_TONEMAP_COMPONENT(b);
                    }
                    *col++ = 1.0f; // Alpha is unused but needs to be there
                }

                // Texture co-ordinates are the same for each quad.
                *tc++ = sMinTexCoord;
                *tc++ = sMinTexCoord;

                *tc++ = sMaxTexCoord;
                *tc++ = sMinTexCoord;

                *tc++ = sMaxTexCoord;
                *tc++ = sMaxTexCoord;

                *tc++ = sMinTexCoord;
                *tc++ = sMaxTexCoord;

                count++;
            }
        }

        self->_texture = oo::Ref<OOTexture>(texture);
        OO_LOG("sky.setup", "Generated quadset with {} quads for texture {}", static_cast<unsigned>(count), (self->_texture != nullptr) ? self->_texture->description() : std::string("(null)"));
    }

    if (!OK) {
        return nullptr; // [self release]; self = nil
    }

    return self;
}

OOSkyQuadSet::~OOSkyQuadSet()
{
    // -dealloc's [_texture release] is the member's destructor.

    if (_positions != NULL)
        free(_positions);
    if (_texCoords != NULL)
        free(_texCoords);
    if (_colors != NULL)
        free(_colors);
}

std::optional<std::string> OOSkyQuadSet::descriptionComponents() const
{
    return oo::str::format("%u quads, texture: %s", _count, ((_texture != nullptr) ? _texture->description() : std::string("(null)")).c_str());
}

void OOSkyQuadSet::render()
{
    OO_ENTER_OPENGL();

    if (_texture != nullptr)
        _texture->apply(); // a message to nil did nothing

    OOGL(glVertexPointer(kSkyQuadSetPositionEntriesPerVertex, GL_FLOAT, 0, _positions));
    OOGL(glTexCoordPointer(kSkyQuadSetTexCoordEntriesPerVertex, GL_FLOAT, 0, _texCoords));
    OOGL(glColorPointer(kSkyQuadSetColorEntriesPerVertex, GL_FLOAT, 0, _colors));

    OOGL(glDrawArrays(GL_QUADS, 0, 4 * _count));
}

#ifdef OO_DEBUG_MONITOR_ENABLED
size_t OOSkyQuadSet::totalSize()
{
    // sizeof *this stands for the Objective-C instance size (the object's own size).
    return sizeof *this + static_cast<size_t>(_count) * 4 * (sizeof *_positions + sizeof *_texCoords + sizeof *_colors);
}

OOTexture* OOSkyQuadSet::texture()
{
    return _texture.get();
}
#endif

namespace {

oo::Ref<OOColor> SaturatedColorInRange(OOColor* color1, OOColor* color2, BOOL hueFix)
{
    oo::Ref<OOColor> color;
    float hue = 0, saturation = 0, brightness = 0, alpha = 0; // left 0 by a nil colour

    // The fraction is drawn even for no colour, as the message's argument was.
    const float fraction = randf();
    color = (color1 != nullptr) ? color1->blendedColorWithFraction(fraction, color2) : nullptr;
    if (color != nullptr)
        color->getHue(&hue, &saturation, &brightness, &alpha);

    saturation = 0.5 * saturation + 0.5; // move saturation up a notch!

    /*	NOTE: this changes the hue, because getHue:... produces hue values
            in [0, 360], but colorWithCalibratedHue:... takes hue values in
            [0, 1].
    */
    if (hueFix) {
        /* now nebula colours can be independently set, correct the
         * range so they behave expectedly if they have actually been
         * set in planetinfo */
        hue /= 360.0;
    }
    /* else keep it how it was before so the nebula hues are clearer */

    return OOColor::colorWithHue(hue, saturation, brightness, alpha);
}

} // namespace
