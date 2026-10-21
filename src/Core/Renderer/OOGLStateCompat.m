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
#import "OOTextureInternal.h"

/*  On SDL_GPU the wrappers only record: the state mirror is what the
    backend draws from, and there is no GL context to keep in step.
*/
#if OO_RENDERER_SDL_GPU
#define GLCALL(call) ((void)0)
#else
#define GLCALL(call) OOGL(call)
#endif

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
    GLCALL(glEnable(cap));
}

void OOGLDisable(GLenum cap)
{
    OO_ENTER_OPENGL();
    RecordCapability(cap, false);
    GLCALL(glDisable(cap));
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
    GLCALL(glBlendFunc(src, dst));
}

void OOGLDepthMask(GLboolean flag)
{
    OO_ENTER_OPENGL();
    OORendererSetDepthMask(flag != GL_FALSE);
    GLCALL(glDepthMask(flag));
}

static OOCompareOp CompareOpForGL(GLenum func)
{
    switch (func) {
    case GL_NEVER:
        return kOOCompareNever;
    case GL_EQUAL:
        return kOOCompareEqual;
    case GL_LEQUAL:
        return kOOCompareLessOrEqual;
    case GL_GREATER:
        return kOOCompareGreater;
    case GL_NOTEQUAL:
        return kOOCompareNotEqual;
    case GL_GEQUAL:
        return kOOCompareGreaterOrEqual;
    case GL_ALWAYS:
        return kOOCompareAlways;
    default:
        return kOOCompareLess;
    }
}

void OOGLDepthFunc(GLenum func)
{
    OO_ENTER_OPENGL();
    OORendererSetDepthFunc(CompareOpForGL(func));
    GLCALL(glDepthFunc(func));
}

static OOCullFace CullFaceForGL(GLenum mode)
{
    return mode == GL_FRONT ? kOOCullFront : mode == GL_FRONT_AND_BACK ? kOOCullFrontAndBack
                                                                       : kOOCullBack;
}

void OOGLCullFace(GLenum mode)
{
    OO_ENTER_OPENGL();
    OORendererSetCullFace(CullFaceForGL(mode));
    GLCALL(glCullFace(mode));
}

void OOGLFrontFace(GLenum mode)
{
    OO_ENTER_OPENGL();
    OORendererSetFrontFaceCCW(mode != GL_CW);
    GLCALL(glFrontFace(mode));
}

void OOGLShadeModel(GLenum mode)
{
    OO_ENTER_OPENGL();
    OORendererSetFlatShading(mode == GL_FLAT);
    GLCALL(glShadeModel(mode));
}

void OOGLPolygonMode(GLenum face, GLenum mode)
{
    OO_ENTER_OPENGL();
    // Oolite only switches both faces at once.
    OORendererSetWireframe(mode == GL_LINE);
    GLCALL(glPolygonMode(face, mode));
}

void OOGLScissor(GLint x, GLint y, GLsizei width, GLsizei height)
{
    OO_ENTER_OPENGL();
    OORendererSetScissorRect(x, y, width, height);
    GLCALL(glScissor(x, y, width, height));
}

void OOGLViewport(GLint x, GLint y, GLsizei width, GLsizei height)
{
    OO_ENTER_OPENGL();
    OORendererSetViewport(x, y, width, height);
    GLCALL(glViewport(x, y, width, height));
}

void OOGLLoadModelViewMatrix(const GLfloat matrix[16])
{
    OO_ENTER_OPENGL();
    OORendererSetModelViewMatrix(matrix);
    GLCALL(glMatrixMode(GL_MODELVIEW));
    GLCALL(glLoadMatrixf(matrix));
}

void OOGLLoadProjectionMatrix(const GLfloat matrix[16])
{
    OO_ENTER_OPENGL();
    OORendererSetProjectionMatrix(matrix);
    GLCALL(glMatrixMode(GL_PROJECTION));
    GLCALL(glLoadMatrixf(matrix));
}

void OOGLActiveTexture(GLenum unit)
{
    OO_ENTER_OPENGL();
    OORendererSetActiveTexture(unit - GL_TEXTURE0);
    GLCALL(glActiveTextureARB(unit));
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
    GLCALL(glBindTexture(target, texture));
}

void OOGLDeleteTextures(GLsizei count, const GLuint* textures)
{
    OO_ENTER_OPENGL();
    for (GLsizei i = 0; i < count; i++)
        OORendererForgetTexture(textures[i]);
    GLCALL(glDeleteTextures(count, textures));
}

static OOCombineOp CombineOpForGL(GLint value)
{
    switch (value) {
    case GL_MODULATE:
        return kOOCombineModulate;
    case GL_ADD:
        return kOOCombineAdd;
    case GL_REPLACE:
        return kOOCombineReplace;
    default:
        return kOOCombineOther;
    }
}

static OOTexEnvMode TexEnvModeForGL(GLint value)
{
    switch (value) {
    case GL_REPLACE:
        return kOOTexEnvReplace;
    case GL_DECAL:
        return kOOTexEnvDecal;
    case GL_BLEND:
        return kOOTexEnvBlend;
    case GL_ADD:
        return kOOTexEnvAdd;
#ifdef GL_COMBINE_ARB
    case GL_COMBINE_ARB:
        return kOOTexEnvCombine;
#endif
    default:
        return kOOTexEnvModulate;
    }
}

static void RecordTexEnvMode(GLenum target, GLenum name, GLint value)
{
    if (target != GL_TEXTURE_ENV)
        return;
#ifdef GL_COMBINE_RGB_ARB
    if (name == GL_COMBINE_RGB_ARB)
        OORendererSetTexEnvCombineRGB(CombineOpForGL(value));
#endif
    if (name == GL_TEXTURE_ENV_MODE)
        OORendererSetTexEnvMode(TexEnvModeForGL(value));
}

void OOGLTexEnvi(GLenum target, GLenum name, GLint value)
{
    OO_ENTER_OPENGL();
    RecordTexEnvMode(target, name, value);
    GLCALL(glTexEnvi(target, name, value));
}

void OOGLTexEnvf(GLenum target, GLenum name, GLfloat value)
{
    OO_ENTER_OPENGL();
    RecordTexEnvMode(target, name, (GLint)value);
#if GL_EXT_texture_lod_bias
    if (target == GL_TEXTURE_FILTER_CONTROL_EXT && name == GL_TEXTURE_LOD_BIAS_EXT)
        OORendererSetTextureLODBias(value);
#endif
    GLCALL(glTexEnvf(target, name, value));
}

void OOGLTexEnvfv(GLenum target, GLenum name, const GLfloat* values)
{
    OO_ENTER_OPENGL();
    if (target == GL_TEXTURE_ENV && name == GL_TEXTURE_ENV_COLOR)
        OORendererSetTexEnvColor(values);
    GLCALL(glTexEnvfv(target, name, values));
}

void OOGLUseProgramObject(GLhandleARB program)
{
    OO_ENTER_OPENGL();
    OORendererSetProgram((uint32_t)OOGLProgramName(program));
    GLCALL(glUseProgramObjectARB(program));
}

void OOGLUseProgram(GLuint program)
{
    OO_ENTER_OPENGL();
    OORendererSetProgram(program);
    GLCALL(glUseProgram(program));
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
    GLCALL(glPushAttrib(mask));
}

void OOGLPopAttrib(void)
{
    OO_ENTER_OPENGL();
    GLCALL(glPopAttrib());
    OORendererPopAttributes();
    if (sAttribDepth > 0) {
        sAttribDepth--;
        if (sSavedMasks[sAttribDepth] & GL_CURRENT_BIT)
            OOImmediateSetAttributes(sSavedCurrent[sAttribDepth]);
    }
}

#ifndef NDEBUG

#if !OO_RENDERER_SDL_GPU
void OORendererBackendVerifyStateMachine(void)
{
    OOGLVerifyStateMachine();
}
#endif

void OORendererBackendNoteDrawOutsidePass(void)
{
    // Once per calling function: the first frames outside the renderer.
    static NSMutableSet* sReported = nil;
    if (sReported == nil)
        sReported = [[NSMutableSet alloc] init];
    NSArray* stack = [NSThread callStackSymbols];
    NSString* caller = @"?";
    for (NSString* frame in stack) {
        if ([frame rangeOfString:@"OORenderer"].location == NSNotFound && [frame rangeOfString:@"OOImmediate"].location == NSNotFound
            && [frame rangeOfString:@"NoteDrawOutsidePass"].location == NSNotFound && [frame rangeOfString:@"VerifyState"].location == NSNotFound
            && [frame rangeOfString:@"callStackSymbols"].location == NSNotFound) {
            caller = frame;
            break;
        }
    }
    NSRange space = [caller rangeOfString:@"0x"];
    NSString* key = space.location != NSNotFound ? [caller substringFromIndex:space.location] : caller;
    // Drop the address so each function is reported once.
    NSRange name = [key rangeOfString:@" "];
    if (name.location != NSNotFound)
        key = [key substringFromIndex:name.location + 1];
    if (![sReported containsObject:key]) {
        [sReported addObject:key];
        OOLogWARN(@"rendering.renderer.outsidePass", @"A draw outside any render pass, from %@. SDL_GPU will drop it.", key);
    }
}

static void Report(NSMutableArray* bad, NSString* format, ...)
{
    va_list args;
    va_start(args, format);
    [bad addObject:[[[NSString alloc] initWithFormat:format arguments:args] autorelease]];
    va_end(args);
}

void OOGLVerifyStateMachine(void)
{
#if OO_RENDERER_SDL_GPU
    return; // no GL context to compare
#endif
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

    // Every field of the mirror, so the SDL_GPU backend can rely on all of it.
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
#ifdef GL_POINT_SPRITE_ARB
        { GL_POINT_SPRITE_ARB, kOOCapPointSprite, "GL_POINT_SPRITE" },
#endif
        { GL_LINE_SMOOTH, kOOCapLineSmooth, "GL_LINE_SMOOTH" },
        { GL_POINT_SMOOTH, kOOCapPointSmooth, "GL_POINT_SMOOTH" },
        { GL_NORMALIZE, kOOCapNormalize, "GL_NORMALIZE" },
#ifdef GL_RESCALE_NORMAL
        { GL_RESCALE_NORMAL, kOOCapRescaleNormal, "GL_RESCALE_NORMAL" },
#endif
    };
    for (size_t i = 0; i < sizeof kCaps / sizeof *kCaps; i++) {
        if ((glIsEnabled(kCaps[i].gl) != GL_FALSE) != state->caps[kCaps[i].cap])
            Report(bad, @"%s", kCaps[i].name);
    }
    for (unsigned i = 0; i < kOOMaxStateLights; i++) {
        if ((glIsEnabled(GL_LIGHT0 + i) != GL_FALSE) != state->lights[i])
            Report(bad, @"GL_LIGHT%u", i);
    }

    GLboolean depthMask;
    glGetBooleanv(GL_DEPTH_WRITEMASK, &depthMask);
    if ((depthMask != GL_FALSE) != state->depthMask)
        Report(bad, @"depth mask");
    GLint value, values[4];
    glGetIntegerv(GL_BLEND_SRC, &value);
    if (BlendFactorForGL((GLenum)value) != state->blendSrc)
        Report(bad, @"blend source factor");
    glGetIntegerv(GL_BLEND_DST, &value);
    if (BlendFactorForGL((GLenum)value) != state->blendDst)
        Report(bad, @"blend destination factor");
    glGetIntegerv(GL_DEPTH_FUNC, &value);
    if (CompareOpForGL((GLenum)value) != state->depthFunc)
        Report(bad, @"depth function");
    glGetIntegerv(GL_CULL_FACE_MODE, &value);
    if (CullFaceForGL((GLenum)value) != state->cullFace)
        Report(bad, @"cull face");
    glGetIntegerv(GL_FRONT_FACE, &value);
    if ((value != GL_CW) != state->frontFaceCCW)
        Report(bad, @"front face");
    glGetIntegerv(GL_SHADE_MODEL, &value);
    if ((value == GL_FLAT) != state->flatShading)
        Report(bad, @"shade model");
    glGetIntegerv(GL_POLYGON_MODE, values);
    if ((values[0] == GL_LINE) != state->wireframe || (values[1] == GL_LINE) != state->wireframe)
        Report(bad, @"polygon mode");
    // GL's initial box is the window; it only matters once the test is on.
    if (state->caps[kOOCapScissorTest]) {
        glGetIntegerv(GL_SCISSOR_BOX, values);
        if (memcmp(values, state->scissor, sizeof state->scissor) != 0)
            Report(bad, @"scissor box (GL %d %d %d %d, recorded %d %d %d %d)", values[0], values[1], values[2], values[3],
                state->scissor[0], state->scissor[1], state->scissor[2], state->scissor[3]);
    }
    if (state->viewportSet) {
        glGetIntegerv(GL_VIEWPORT, values);
        if (memcmp(values, state->viewport, sizeof state->viewport) != 0)
            Report(bad, @"viewport (GL %d %d %d %d, recorded %d %d %d %d)", values[0], values[1], values[2], values[3],
                state->viewport[0], state->viewport[1], state->viewport[2], state->viewport[3]);
    }
    GLfloat matrix[16];
    glGetFloatv(GL_MODELVIEW_MATRIX, matrix);
    if (memcmp(matrix, state->modelView, sizeof matrix) != 0)
        Report(bad, @"modelview matrix");
    glGetFloatv(GL_PROJECTION_MATRIX, matrix);
    if (memcmp(matrix, state->projection, sizeof matrix) != 0)
        Report(bad, @"projection matrix");

    glGetIntegerv(GL_CURRENT_PROGRAM, &value);
    if ((uint32_t)value != state->program)
        Report(bad, @"program (GL %d, recorded %u)", value, state->program);

    GLint activeTexture;
    glGetIntegerv(GL_ACTIVE_TEXTURE, &activeTexture);
    if ((unsigned)(activeTexture - GL_TEXTURE0) != state->activeTexture)
        Report(bad, @"active texture unit");
    GLint unitCount = 1;
    glGetIntegerv(GL_MAX_TEXTURE_UNITS, &unitCount);
    if (unitCount > kOOMaxTextureUnits)
        unitCount = kOOMaxTextureUnits;
    for (GLint u = 0; u < unitCount; u++) {
        const OOTextureUnitState* unit = &state->units[u];
        glActiveTextureARB(GL_TEXTURE0 + u);
        if ((glIsEnabled(GL_TEXTURE_2D) != GL_FALSE) != unit->texture2D)
            Report(bad, @"GL_TEXTURE_2D on unit %d", u);
        glGetIntegerv(GL_TEXTURE_BINDING_2D, &value);
        if ((uint32_t)value != unit->binding2D)
            Report(bad, @"2D texture binding on unit %d (GL %d, recorded %u)", u, value, unit->binding2D);
#if OO_TEXTURE_CUBE_MAP
        if ((glIsEnabled(GL_TEXTURE_CUBE_MAP) != GL_FALSE) != unit->textureCube)
            Report(bad, @"GL_TEXTURE_CUBE_MAP on unit %d", u);
        glGetIntegerv(GL_TEXTURE_BINDING_CUBE_MAP, &value);
        if ((uint32_t)value != unit->bindingCube)
            Report(bad, @"cube map binding on unit %d (GL %d, recorded %u)", u, value, unit->bindingCube);
#endif
        glGetTexEnviv(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, &value);
        if (TexEnvModeForGL(value) != unit->envMode)
            Report(bad, @"texture environment mode on unit %d", u);
#ifdef GL_COMBINE_RGB_ARB
        glGetTexEnviv(GL_TEXTURE_ENV, GL_COMBINE_RGB_ARB, &value);
        if (CombineOpForGL(value) != unit->combineRGB)
            Report(bad, @"RGB combine op on unit %d", u);
#endif
        GLfloat color[4];
        glGetTexEnvfv(GL_TEXTURE_ENV, GL_TEXTURE_ENV_COLOR, color);
        if (memcmp(color, unit->envColor, sizeof color) != 0)
            Report(bad, @"texture environment colour on unit %d", u);
#if GL_EXT_texture_lod_bias
        if (gOOTextureInfo.textureLODBiasAvailable) {
            GLfloat bias;
            glGetTexEnvfv(GL_TEXTURE_FILTER_CONTROL_EXT, GL_TEXTURE_LOD_BIAS_EXT, &bias);
            if (bias != unit->lodBias)
                Report(bad, @"LOD bias on unit %d (GL %g, recorded %g)", u, bias, unit->lodBias);
        }
#endif
    }
    glActiveTextureARB((GLenum)activeTexture);

    for (NSString* field in bad) {
        // Report each kind of mismatch once, keyed without the values.
        NSString* key = [[field componentsSeparatedByString:@" ("] objectAtIndex:0];
        if (![sReported containsObject:key]) {
            [sReported addObject:key];
            OOLogWARN(@"rendering.renderer.stateMachine", @"GL %@ changed without the OOGL* wrappers; first seen at a draw from %@.", field, [NSThread callStackSymbols].count > 3 ? [[NSThread callStackSymbols] objectAtIndex:3] : @"?");
        }
    }
}

#endif
