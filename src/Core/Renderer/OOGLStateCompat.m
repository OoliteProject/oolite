/*

OOGLStateCompat.m


Copyright (C) 2026 Oolite contributors

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

#import "OOGLStateCompat.h"

#import "OOImmediateMode.h"
#import "OOLogging.h"
#import "OOMacroOpenGL.h"
#import "OOOpenGLExtensionManager.h"
#import "OORendererBackend.h"

static bool CapabilityForGL(GLenum cap, OOCapability* outCap)
{
    switch (cap) {
    case GL_BLEND:
        *outCap = kOOCapBlend;
        return true;
    case GL_DEPTH_TEST:
        *outCap = kOOCapDepthTest;
        return true;
    case GL_CULL_FACE:
        *outCap = kOOCapCullFace;
        return true;
    case GL_LIGHTING:
        *outCap = kOOCapLighting;
        return true;
    case GL_FOG:
        *outCap = kOOCapFog;
        return true;
    case GL_COLOR_MATERIAL:
        *outCap = kOOCapColorMaterial;
        return true;
    case GL_SCISSOR_TEST:
        *outCap = kOOCapScissorTest;
        return true;
#ifdef GL_POINT_SPRITE_ARB
    case GL_POINT_SPRITE_ARB:
        *outCap = kOOCapPointSprite;
        return true;
#endif
    case GL_LINE_SMOOTH:
        *outCap = kOOCapLineSmooth;
        return true;
    case GL_POINT_SMOOTH:
        *outCap = kOOCapPointSmooth;
        return true;
    case GL_NORMALIZE:
        *outCap = kOOCapNormalize;
        return true;
#ifdef GL_RESCALE_NORMAL
    case GL_RESCALE_NORMAL:
        *outCap = kOOCapRescaleNormal;
        return true;
#endif
    default:
        return false;
    }
}

static void RecordCapability(GLenum cap, bool enabled)
{
    OOCapability ooCap;
    if (CapabilityForGL(cap, &ooCap))
        OORendererSetCapability(ooCap, enabled);
    else if (cap >= GL_LIGHT0 && cap < GL_LIGHT0 + kOOMaxStateLights)
        OORendererSetLightEnabled(cap - GL_LIGHT0, enabled);
    else if (cap == GL_TEXTURE_2D)
        OORendererSetTextureEnabled(false, enabled);
#if OO_TEXTURE_CUBE_MAP
    else if (cap == GL_TEXTURE_CUBE_MAP)
        OORendererSetTextureEnabled(true, enabled);
#endif
}

void OOGLEnable(GLenum cap)
{
    OO_ENTER_OPENGL();
    RecordCapability(cap, true);
    OOGL(glEnable(cap));
}

void OOGLDisable(GLenum cap)
{
    OO_ENTER_OPENGL();
    RecordCapability(cap, false);
    OOGL(glDisable(cap));
}

static OOBlendFactor BlendFactorForGL(GLenum factor)
{
    switch (factor) {
    case GL_ZERO:
        return kOOBlendFactorZero;
    case GL_ONE:
        return kOOBlendFactorOne;
    case GL_SRC_ALPHA:
        return kOOBlendFactorSrcAlpha;
    case GL_ONE_MINUS_SRC_ALPHA:
        return kOOBlendFactorOneMinusSrcAlpha;
    case GL_DST_COLOR:
        return kOOBlendFactorDstColor;
    case GL_ONE_MINUS_SRC_COLOR:
        return kOOBlendFactorOneMinusSrcColor;
    case GL_SRC_COLOR:
        return kOOBlendFactorSrcColor;
    default:
        return kOOBlendFactorOther;
    }
}

void OOGLBlendFunc(GLenum src, GLenum dst)
{
    OO_ENTER_OPENGL();
    OORendererSetBlendFunc(BlendFactorForGL(src), BlendFactorForGL(dst));
    OOGL(glBlendFunc(src, dst));
}

void OOGLDepthMask(GLboolean flag)
{
    OO_ENTER_OPENGL();
    OORendererSetDepthMask(flag != GL_FALSE);
    OOGL(glDepthMask(flag));
}

void OOGLDepthFunc(GLenum func)
{
    OO_ENTER_OPENGL();
    OOCompareOp op = kOOCompareLess;
    switch (func) {
    case GL_NEVER:
        op = kOOCompareNever;
        break;
    case GL_EQUAL:
        op = kOOCompareEqual;
        break;
    case GL_LEQUAL:
        op = kOOCompareLessOrEqual;
        break;
    case GL_GREATER:
        op = kOOCompareGreater;
        break;
    case GL_NOTEQUAL:
        op = kOOCompareNotEqual;
        break;
    case GL_GEQUAL:
        op = kOOCompareGreaterOrEqual;
        break;
    case GL_ALWAYS:
        op = kOOCompareAlways;
        break;
    default:
        break;
    }
    OORendererSetDepthFunc(op);
    OOGL(glDepthFunc(func));
}

void OOGLCullFace(GLenum mode)
{
    OO_ENTER_OPENGL();
    OORendererSetCullFace(mode == GL_FRONT ? kOOCullFront : mode == GL_FRONT_AND_BACK ? kOOCullFrontAndBack
                                                                                      : kOOCullBack);
    OOGL(glCullFace(mode));
}

void OOGLFrontFace(GLenum mode)
{
    OO_ENTER_OPENGL();
    OORendererSetFrontFaceCCW(mode != GL_CW);
    OOGL(glFrontFace(mode));
}

void OOGLShadeModel(GLenum mode)
{
    OO_ENTER_OPENGL();
    OORendererSetFlatShading(mode == GL_FLAT);
    OOGL(glShadeModel(mode));
}

void OOGLPolygonMode(GLenum face, GLenum mode)
{
    OO_ENTER_OPENGL();
    // Oolite only switches both faces at once.
    OORendererSetWireframe(mode == GL_LINE);
    OOGL(glPolygonMode(face, mode));
}

void OOGLScissor(GLint x, GLint y, GLsizei width, GLsizei height)
{
    OO_ENTER_OPENGL();
    OORendererSetScissorRect(x, y, width, height);
    OOGL(glScissor(x, y, width, height));
}

void OOGLActiveTexture(GLenum unit)
{
    OO_ENTER_OPENGL();
    OORendererSetActiveTexture(unit - GL_TEXTURE0);
    OOGL(glActiveTextureARB(unit));
}

void OOGLBindTexture(GLenum target, GLuint texture)
{
    OO_ENTER_OPENGL();
    if (target == GL_TEXTURE_2D)
        OORendererSetTextureBinding(false, texture);
#if OO_TEXTURE_CUBE_MAP
    else if (target == GL_TEXTURE_CUBE_MAP)
        OORendererSetTextureBinding(true, texture);
#endif
    OOGL(glBindTexture(target, texture));
}

void OOGLDeleteTextures(GLsizei count, const GLuint* textures)
{
    OO_ENTER_OPENGL();
    for (GLsizei i = 0; i < count; i++)
        OORendererForgetTexture(textures[i]);
    OOGL(glDeleteTextures(count, textures));
}

static void RecordTexEnvMode(GLenum target, GLenum name, GLint value)
{
    if (target != GL_TEXTURE_ENV || name != GL_TEXTURE_ENV_MODE)
        return;
    OOTexEnvMode mode = kOOTexEnvModulate;
    switch (value) {
    case GL_REPLACE:
        mode = kOOTexEnvReplace;
        break;
    case GL_DECAL:
        mode = kOOTexEnvDecal;
        break;
    case GL_BLEND:
        mode = kOOTexEnvBlend;
        break;
    case GL_ADD:
        mode = kOOTexEnvAdd;
        break;
#ifdef GL_COMBINE_ARB
    case GL_COMBINE_ARB:
        mode = kOOTexEnvCombine;
        break;
#endif
    default:
        break;
    }
    OORendererSetTexEnvMode(mode);
}

void OOGLTexEnvi(GLenum target, GLenum name, GLint value)
{
    OO_ENTER_OPENGL();
    RecordTexEnvMode(target, name, value);
    OOGL(glTexEnvi(target, name, value));
}

void OOGLTexEnvf(GLenum target, GLenum name, GLfloat value)
{
    OO_ENTER_OPENGL();
    RecordTexEnvMode(target, name, (GLint)value);
    OOGL(glTexEnvf(target, name, value));
}

void OOGLTexEnvfv(GLenum target, GLenum name, const GLfloat* values)
{
    OO_ENTER_OPENGL();
    if (target == GL_TEXTURE_ENV && name == GL_TEXTURE_ENV_COLOR)
        OORendererSetTexEnvColor(values);
    OOGL(glTexEnvfv(target, name, values));
}

void OOGLUseProgramObject(GLhandleARB program)
{
    OO_ENTER_OPENGL();
    OORendererSetProgram((uint32_t)OOGLProgramName(program));
    OOGL(glUseProgramObjectARB(program));
}

void OOGLUseProgram(GLuint program)
{
    OO_ENTER_OPENGL();
    OORendererSetProgram(program);
    OOGL(glUseProgram(program));
}

enum {
    kMaxAttribDepth = 16
};
static OOImmediateAttributes sSavedCurrent[kMaxAttribDepth];
static GLbitfield sSavedMasks[kMaxAttribDepth];
static int sAttribDepth = 0;

void OOGLPushAttrib(GLbitfield mask)
{
    OO_ENTER_OPENGL();
    if (sAttribDepth < kMaxAttribDepth) {
        if (mask & GL_CURRENT_BIT)
            sSavedCurrent[sAttribDepth] = OOImmediateGetAttributes();
        sSavedMasks[sAttribDepth] = mask;
        sAttribDepth++;
    }
    OORendererPushAttributes(mask);
    OOGL(glPushAttrib(mask));
}

void OOGLPopAttrib(void)
{
    OO_ENTER_OPENGL();
    OOGL(glPopAttrib());
    OORendererPopAttributes();
    if (sAttribDepth > 0) {
        sAttribDepth--;
        if (sSavedMasks[sAttribDepth] & GL_CURRENT_BIT)
            OOImmediateSetAttributes(sSavedCurrent[sAttribDepth]);
    }
}

#ifndef NDEBUG

void OORendererBackendVerifyStateMachine(void)
{
    OOGLVerifyStateMachine();
}

void OOGLVerifyStateMachine(void)
{
    static int sEnabled = -1;
    if (sEnabled < 0)
        sEnabled = getenv("OO_VERIFY_RENDER_STATE") != NULL;
    if (!sEnabled)
        return;

    OO_ENTER_OPENGL();
    static NSMutableSet* sReported = nil;
    if (sReported == nil)
        sReported = [[NSMutableSet alloc] init];
    const OORenderStateMachine* state = OORendererState();
    NSMutableArray* bad = [NSMutableArray array];

    static const struct {
        GLenum gl;
        OOCapability cap;
        const char* name;
    } kCaps[] = {
        { GL_BLEND, kOOCapBlend, "GL_BLEND" },
        { GL_DEPTH_TEST, kOOCapDepthTest, "GL_DEPTH_TEST" },
        { GL_CULL_FACE, kOOCapCullFace, "GL_CULL_FACE" },
        { GL_LIGHTING, kOOCapLighting, "GL_LIGHTING" },
        { GL_FOG, kOOCapFog, "GL_FOG" },
        { GL_COLOR_MATERIAL, kOOCapColorMaterial, "GL_COLOR_MATERIAL" },
        { GL_SCISSOR_TEST, kOOCapScissorTest, "GL_SCISSOR_TEST" },
        { GL_LINE_SMOOTH, kOOCapLineSmooth, "GL_LINE_SMOOTH" },
        { GL_POINT_SMOOTH, kOOCapPointSmooth, "GL_POINT_SMOOTH" },
    };
    for (size_t i = 0; i < sizeof kCaps / sizeof *kCaps; i++) {
        if ((glIsEnabled(kCaps[i].gl) != GL_FALSE) != state->caps[kCaps[i].cap])
            [bad addObject:[NSString stringWithUTF8String:kCaps[i].name]];
    }
    for (unsigned i = 0; i < 2; i++) {
        if ((glIsEnabled(GL_LIGHT0 + i) != GL_FALSE) != state->lights[i])
            [bad addObject:[NSString stringWithFormat:@"GL_LIGHT%u", i]];
    }
    GLboolean depthMask;
    glGetBooleanv(GL_DEPTH_WRITEMASK, &depthMask);
    if ((depthMask != GL_FALSE) != state->depthMask)
        [bad addObject:@"depth mask"];
    GLint value;
    glGetIntegerv(GL_BLEND_DST, &value);
    if (BlendFactorForGL((GLenum)value) != state->blendDst)
        [bad addObject:@"blend function"];
    glGetIntegerv(GL_ACTIVE_TEXTURE, &value);
    if ((unsigned)(value - GL_TEXTURE0) != state->activeTexture)
        [bad addObject:@"active texture unit"];
    else {
        const OOTextureUnitState* unit = &state->units[state->activeTexture];
        if ((glIsEnabled(GL_TEXTURE_2D) != GL_FALSE) != unit->texture2D)
            [bad addObject:@"GL_TEXTURE_2D"];
        glGetIntegerv(GL_TEXTURE_BINDING_2D, &value);
        if ((uint32_t)value != unit->binding2D)
            [bad addObject:[NSString stringWithFormat:@"2D texture binding (GL %d, recorded %u)", value, unit->binding2D]];
    }

    for (NSString* field in bad) {
        if (![sReported containsObject:field]) {
            [sReported addObject:field];
            OOLogWARN(@"rendering.renderer.stateMachine", @"GL %@ changed without the OOGL* wrappers; first seen at a draw from %@.", field, [NSThread callStackSymbols].count > 3 ? [[NSThread callStackSymbols] objectAtIndex:3] : @"?");
        }
    }
}

#endif
