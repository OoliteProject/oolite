/*

DustEntity.m

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

#import "DustEntity.h"
#include "oofnd/Process.hpp"

#import "MyOpenGLView.h"
#import "OODebugFlags.h"
#import "OOGraphicsResetManager.h"
#import "OOMacroOpenGL.h"
#import "OOMaths.h"
#import "Universe.h"

#if OO_SHADERS
#import "OOMaterial.h" // For kTangentAttributeIndex
#import "OOShaderProgram.h"
#import "OOShaderUniform.h"
#endif

#import "PlayerEntity.h"

#include "oofnd/String.hpp"
#include "oofnd/objc/OORuntime.h"

#define FAR_PLANE (DUST_SCALE * 0.50f)
#define NEAR_PLANE (DUST_SCALE * 0.25f)

#if OO_SHADERS
enum {
    kShaderModeOff,
    kShaderModeOn,
    kShaderModeUnknown
};
#endif

namespace cxx {

void DustEntity::init()
{
    int vi;

    // this should be unnecessary
    //	ranrot_srand((uint32_t)oo::date::timeIntervalSince1970());	// seed randomiser by time

    // self = [super init]: the constructor ran Entity's -init body.

    for (vi = 0; vi < DUST_N_PARTICLES; vi++) {
        vertices[vi].x = (ranrot_rand() % DUST_SCALE) - DUST_SCALE / 2;
        vertices[vi].y = (ranrot_rand() % DUST_SCALE) - DUST_SCALE / 2;
        vertices[vi].z = (ranrot_rand() % DUST_SCALE) - DUST_SCALE / 2;

        // Set up element index array for warp mode.
        indices[vi * 2] = vi;
        indices[vi * 2 + 1] = vi + DUST_N_PARTICLES;

#if OO_SHADERS
        vertices[vi + DUST_N_PARTICLES] = vertices[vi];
        warpinessAttr[vi] = 0.0f;
        warpinessAttr[vi + DUST_N_PARTICLES] = 1.0f;
#endif
    }

#if OO_SHADERS
    shaderMode = kShaderModeUnknown;
#endif

    drawDust = !oo::process::hasArgument("-nodust");

    dust_color = OOColor::colorWithRed(0.5, 1.0, 1.0, 1.0);
    setStatus(STATUS_ACTIVE);

    hasPointSprites = OOOpenGLExtensionManager::sharedManager()->haveExtension("GL_ARB_point_sprite");

    if (hasPointSprites) {
        texture = oo::ObjCRef<::OOTexture*>([::OOTexture cxx_textureWithName:"oolite-particle-dust.png"
                                                                    inFolder:"Textures"
                                                                     options:kOOTextureMinFilterMipMap | kOOTextureMagFilterLinear | kOOTextureAlphaMask
                                                                  anisotropy:kOOTextureDefaultAnisotropy / 2.0
                                                                     lodBias:0.0]);
    }

    collision_radius = DUST_SCALE; // for draw pass calculations

    OOGraphicsResetManager::sharedManager()->registerClient(oo::ToObjC(this)); // the facade answers -resetGraphicsState
}

// -dealloc is the facade's: it unregisters the facade from the graphics reset manager. The members
// release the colour, texture, shader and uniforms when the facade releases its C++ part.

void DustEntity::setDustColor(OOColor* color)
{
    dust_color = oo::Ref<OOColor>(color);
    // A message to a nil colour did nothing.
    if (dust_color != nullptr)
        dust_color->getRed(&color_fv[0], &color_fv[1], &color_fv[2], &color_fv[3]);
}

OOColor* DustEntity::dustColor()
{
    return dust_color.get();
}

bool DustEntity::canCollide()
{
    return NO;
}

void DustEntity::updateCameraRelativePosition()
{
    HPVector c_pos = [PLAYER viewpointPosition];
    cameraRelativePosition = make_vector((OOScalar)-fmod(c_pos.x, DUST_SCALE), (OOScalar)-fmod(c_pos.y, DUST_SCALE), (OOScalar)-fmod(c_pos.z, DUST_SCALE));
}

void DustEntity::update(OOTimeDelta /*delta_t*/)
{
    // [self setPosition:position];
    zero_distance = 0.0;

#if OO_SHADERS
    if (EXPECT_NOT(shaderMode == kShaderModeUnknown))
        checkShaderMode();

    // Shader takes care of repositioning.
    if (shaderMode == kShaderModeOn)
        return;
#endif

    Vector offset = vector_flip(cameraRelativePosition);
    GLfloat half_scale = DUST_SCALE * 0.50;
    int vi;
    for (vi = 0; vi < DUST_N_PARTICLES; vi++) {
        while (vertices[vi].x - offset.x < -half_scale)
            vertices[vi].x += DUST_SCALE;
        while (vertices[vi].x - offset.x > half_scale)
            vertices[vi].x -= DUST_SCALE;

        while (vertices[vi].y - offset.y < -half_scale)
            vertices[vi].y += DUST_SCALE;
        while (vertices[vi].y - offset.y > half_scale)
            vertices[vi].y -= DUST_SCALE;

        while (vertices[vi].z - offset.z < -half_scale)
            vertices[vi].z += DUST_SCALE;
        while (vertices[vi].z - offset.z > half_scale)
            vertices[vi].z -= DUST_SCALE;
    }
}

#if OO_SHADERS
OOShaderProgram* DustEntity::getShader()
{
    if (shader == nullptr) {
        ::DustEntity* self = oo::ToObjC(this); // what the uniforms are bound to
        std::string prefix = oo::str::format(
            "#define OODUST_SCALE_MAX    (float(%g))\n"
            "#define OODUST_SCALE_FACTOR (float(%g))\n"
            "#define OODUST_SIZE         (float(%g))\n",
            FAR_PLANE / NEAR_PLANE,
            1.0f / (FAR_PLANE - NEAR_PLANE),
            (float)DUST_SCALE);

        // Reuse tangent attribute ID for "warpiness", as we don't need a tangent.
        oo::PList::Dict attributes;
        attributes["aWarpiness"] = oo::PList::signedInteger(kTangentAttributeIndex); // +numberWithInt:

        shader = OOShaderProgram::shaderProgramWithVertexShaderName("oolite-dust.vertex",
            "oolite-dust.fragment",
            std::optional<std::string>(std::move(prefix)),
            oo::PList(std::move(attributes)));

        uniforms.clear();
        oo::Ref<OOShaderUniform> uWarp = OOShaderUniform::initWithName("uWarp",
            oo::ToObjC(shader),
            self,
            OOSelectorFromName("warpVector"),
            0);
        oo::Ref<OOShaderUniform> uOffsetPlayerPosition = OOShaderUniform::initWithName("uOffsetPlayerPosition",
            oo::ToObjC(shader),
            self,
            OOSelectorFromName("offsetPlayerPosition"),
            0);

        uniforms.push_back(uWarp);
        uniforms.push_back(uOffsetPlayerPosition);
    }

    return shader.get();
}

Vector DustEntity::offsetPlayerPosition()
{
    // used as shader uniform, so needs to be low precision
    HPVector c_pos = [PLAYER viewpointPosition];
    Vector offset = make_vector((OOScalar)fmod(c_pos.x, DUST_SCALE), (OOScalar)fmod(c_pos.y, DUST_SCALE), (OOScalar)fmod(c_pos.z, DUST_SCALE));
    return vector_subtract(offset, make_vector(DUST_SCALE * 0.5f, DUST_SCALE * 0.5f, DUST_SCALE * 0.5f));
}

void DustEntity::checkShaderMode()
{
    shaderMode = kShaderModeOff;
    if ([UNIVERSE detailLevel] >= DETAIL_LEVEL_SHADERS) {
        if (OOOpenGLExtensionManager::sharedManager()->useDustShader()) {
            shaderMode = kShaderModeOn;
        }
    }
}
#endif

Vector DustEntity::warpVector()
{
    return vector_multiply_scalar([PLAYER velocity], 1.0f / HYPERSPEED_FACTOR);
}

void DustEntity::drawImmediate(bool /*immediate*/, bool translucent)
{
    if (!drawDust || [UNIVERSE breakPatternHide] || !translucent)
        return; // DON'T DRAW

    ::PlayerEntity* player = PLAYER;
    assert(player != nil);

#ifdef OO_DEBUG_MONITOR_ENABLED
    if (gDebugFlags & DEBUG_NO_DUST)
        return;
#endif

#if OO_SHADERS
    if (EXPECT_NOT(shaderMode == kShaderModeUnknown))
        checkShaderMode();
    BOOL useShader = (shaderMode == kShaderModeOn);
#endif

    GLfloat* fogcolor = [UNIVERSE skyClearColor];
    float idealDustSize = [[UNIVERSE gameView] viewSize].width / 800.0f;

    BOOL warp_stars = [player atHyperspeed];
    float dustIntensity;

    OO_ENTER_OPENGL();
    OOSetOpenGLState(OPENGL_STATE_OPAQUE);
    OOGL(glDisableClientState(GL_NORMAL_ARRAY));

    if (!warp_stars) {
        // Draw points.
        float dustPointSize = ceil(idealDustSize);
        if (dustPointSize < 1.0f)
            dustPointSize = 1.0f;
        OOGL(GLScaledPointSize(dustPointSize));
        dustIntensity = OOClamp_0_1_f(idealDustSize / dustPointSize);
    } else {
        // Draw lines.
        float idealLineSize = idealDustSize * 0.5f;
        float dustLineSize = ceil(idealLineSize);
        if (dustLineSize < 1.0f)
            dustLineSize = 1.0f;
        GLScaledLineWidth(dustLineSize);
        dustIntensity = OOClamp_0_1_f(idealLineSize / dustLineSize);
    }
    if (fogcolor[3] > 0.0) {
        // fade out dust when entering atmosphere (issue #100)
        dustIntensity = OOClamp_0_1_f(dustIntensity - (fogcolor[3] * 3.0));
    }

    if (dustIntensity > 0.0) {

        float* color = NULL;
        if (player->_cxxEntity->isSunlit)
            color = color_fv;
        else
            color = UNIVERSE->_cxxUniverse->stars_ambient;
        OOGL(glColor4f(color[0], color[1], color[2], dustIntensity));

#if OO_SHADERS
        if (useShader) {
            // A message to a nil program did nothing.
            OOShaderProgram* program = getShader();
            if (program != nullptr)
                program->apply();
            // A message to a nil uniform (the initialiser answered nil) did nothing.
            for (const oo::Ref<OOShaderUniform>& uniform : uniforms)
                if (uniform != nullptr)
                    uniform->apply();
        } else
#endif
        {
            OOGL(glEnable(GL_FOG));
            OOGL(glFogi(GL_FOG_MODE, GL_LINEAR));
            OOGL(glFogfv(GL_FOG_COLOR, fogcolor));
            OOGL(glHint(GL_FOG_HINT, GL_NICEST));
            OOGL(glFogf(GL_FOG_START, NEAR_PLANE));
            OOGL(glFogf(GL_FOG_END, FAR_PLANE));
        }

        OOGL(glEnable(GL_BLEND));
        OOGL(glDepthMask(GL_FALSE));

        if (warp_stars) {
            OOGL(glDisable(GL_TEXTURE_2D));
#if OO_SHADERS
            if (useShader) {
                OOGL(glEnableVertexAttribArrayARB(kTangentAttributeIndex));
                OOGL(glVertexAttribPointerARB(kTangentAttributeIndex, 1, GL_FLOAT, GL_FALSE, 0, warpinessAttr));
            } else
#endif
            {
                Vector warpVector = this->warpVector();
                unsigned vi;
                for (vi = 0; vi < DUST_N_PARTICLES; vi++) {
                    vertices[vi + DUST_N_PARTICLES] = vector_subtract(vertices[vi], warpVector);
                }
            }

            OOGL(glVertexPointer(3, GL_FLOAT, 0, vertices));
            OOGL(glDrawElements(GL_LINES, DUST_N_PARTICLES * 2, GL_UNSIGNED_SHORT, indices));

#if OO_SHADERS
            if (useShader) {
                OOGL(glDisableVertexAttribArrayARB(kTangentAttributeIndex));
            }
#endif
            OOGL(glEnable(GL_TEXTURE_2D));

        } else {
            if (hasPointSprites) {
#if OO_SHADERS
                if (!useShader)
#endif
                {
                    OOGL(glBlendFunc(GL_SRC_ALPHA, GL_ONE));
                }
                OOGL(glEnable(GL_POINT_SPRITE_ARB));
                [texture.get() apply];
                OOGL(glVertexPointer(3, GL_FLOAT, 0, vertices));
                OOGL(glDrawArrays(GL_POINTS, 0, DUST_N_PARTICLES));
                OOGL(glDisable(GL_POINT_SPRITE_ARB));
            } else {
                OOGL(glDisable(GL_TEXTURE_2D));
                OOGL(glVertexPointer(3, GL_FLOAT, 0, vertices));
                OOGL(glDrawArrays(GL_POINTS, 0, DUST_N_PARTICLES));
                OOGL(glEnable(GL_TEXTURE_2D));
            }
        }

        // reapply normal conditions
#if OO_SHADERS
        if (useShader) {
            OOShaderProgram::applyNone();
        } else
#endif
        {
            OOGL(glDisable(GL_FOG));
            OOGL(glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA));
        }

        OOGL(glDisable(GL_BLEND));
        OOGL(glDepthMask(GL_TRUE));
    }
    OOGL(glEnableClientState(GL_NORMAL_ARRAY));

    OOVerifyOpenGLState();
    cxx_OOCheckOpenGLErrors([&]() -> std::string { return "DustEntity after drawing " + oo::DescriptionOf(oo::ToObjC(this)); });
}

void DustEntity::resetGraphicsState()
{
#if OO_SHADERS
    shader = nullptr; // DESTROY(shader)
    uniforms.clear();

    shaderMode = kShaderModeUnknown;

    /*	Duplicate vertex data. This is only required if we're switching from
            non-shader mode to a shader mode, but let's KISS.
    */
    memcpy(vertices + DUST_N_PARTICLES, vertices, sizeof *vertices * DUST_N_PARTICLES);
#endif
}

#ifdef OO_DEBUG_MONITOR_ENABLED
std::optional<std::string> DustEntity::descriptionForObjDump()
{
    // Don't include range and visibility flag as they're irrelevant.
    return descriptionForObjDumpBasic();
}
#endif

} // namespace cxx
