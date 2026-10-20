/*

OORendererSDLGPU.c

The SDL_GPU backend for the renderer layer (issue #579), first slice.

It implements OORendererBackend.h on SDL_GPU, reading pipeline state from
the state mirror (OORenderStateMachine.h) and fixed-function values from
OOFixedFunction.h, and drawing with the fixed-function emulation shaders
from OOGLSLTranslator, the same translator OXP shaders go through. It lives
with the spike for now, because the translator does; only the backend
harness (oogpu-backend-test) builds it.

How a frame is recorded. SDL_GPU can't start a copy pass while a render
pass is open, but Oolite creates vertex data and uploads textures in the
middle of drawing. So during a pass every draw is recorded: its vertices
go into a CPU arena (de-indexed into point, line or triangle lists, which
also makes GL's flat-shading provoking vertex easy to reproduce), with a
snapshot of the uniforms and the pipeline key. At the end of the pass one
copy pass uploads the arena and any pending texture uploads, and the draws
are replayed into the real render pass.

Conventions handled here:
- clip-space depth: the translator remaps GL's [-w, w] to SDL_GPU's [0, w],
  and pipelines clip at the near and far planes as GL does (SDL_GPU clamps
  depth by default);
- window origin: GL's viewport and scissor are bottom-left, SDL_GPU's top
  left; readback is flipped back to GL's bottom-up rows;
- flat shading: GL uses the last vertex of each primitive.

Not in this slice: render targets other than the window, fog, colour
material, separate specular, multitexturing, custom shader programs, wide
lines and large points (the CPU expansion exists for them), and alpha-only
or luminance textures are expanded to RGBA on upload.


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

#include "OORendererSDLGPU.h"

#include "OOGLSLTranslator.h"
#include "OORenderStateMachine.h"
#include "OORendererBackend.h"

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#pragma mark - Device and window target

static SDL_GPUDevice* sDevice = NULL;
static SDL_GPUTexture* sWindowColor = NULL;
static SDL_GPUTexture* sWindowDepth = NULL;
static unsigned sWindowWidth = 0, sWindowHeight = 0;
static const SDL_GPUTextureFormat kColorFormat = SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM;
static const SDL_GPUTextureFormat kDepthFormat = SDL_GPU_TEXTUREFORMAT_D32_FLOAT;

static OOGLSLProgram sFixedFunction;
static SDL_GPUShader* sFixedVertex = NULL;
static SDL_GPUShader* sFixedFragment = NULL;
static uint32_t sTextureSamplerSlot = 0;

// Deliberate faults for the harness's negative controls (OO_BACKEND_FAULT).
static const char* sFault = "";

typedef struct {
    float position[4];
    float color[4];
    float texCoord[4];
    float normal[3];
} GPUVertex;

typedef enum {
    kInputPosition,
    kInputColor,
    kInputTexCoord,
    kInputNormal,
    kInputNone,
} InputKind;

static SDL_GPUVertexAttribute sAttributes[8];
static uint32_t sAttributeCount = 0;

static SDL_GPUShader* CreateShader(const OOGLSLStageResult* stage, SDL_GPUShaderStage gpuStage)
{
    SDL_GPUShaderCreateInfo info = {
        .stage = gpuStage,
        .num_uniform_buffers = 2,
    };
    for (size_t i = 0; i < stage->samplerCount; i++) {
        if (stage->samplers[i].slot + 1 > info.num_samplers)
            info.num_samplers = stage->samplers[i].slot + 1;
    }
    if (stage->msl != NULL) {
        info.format = SDL_GPU_SHADERFORMAT_MSL;
        info.code = (const Uint8*)stage->msl;
        info.code_size = strlen(stage->msl);
        info.entrypoint = "main0";
    } else {
        info.format = SDL_GPU_SHADERFORMAT_SPIRV;
        info.code = (const Uint8*)stage->spirv;
        info.code_size = stage->spirvWordCount * sizeof(uint32_t);
        info.entrypoint = "main";
    }
    return SDL_CreateGPUShader(sDevice, &info);
}

static InputKind InputForName(const char* name)
{
    if (strcmp(name, "oo_Vertex") == 0)
        return kInputPosition;
    if (strcmp(name, "oo_Color") == 0)
        return kInputColor;
    if (strcmp(name, "oo_MultiTexCoord0") == 0)
        return kInputTexCoord;
    if (strcmp(name, "oo_Normal") == 0)
        return kInputNormal;
    return kInputNone;
}

static SDL_GPUTexture* CreateTarget(SDL_GPUTextureFormat format, SDL_GPUTextureUsageFlags usage, unsigned width, unsigned height)
{
    SDL_GPUTextureCreateInfo info = {
        .type = SDL_GPU_TEXTURETYPE_2D,
        .format = format,
        .usage = usage,
        .width = width,
        .height = height,
        .layer_count_or_depth = 1,
        .num_levels = 1,
    };
    return SDL_CreateGPUTexture(sDevice, &info);
}

static void CreateWhiteTexture(void);

bool OORendererSDLGPUInit(SDL_GPUDevice* device, unsigned width, unsigned height)
{
    sDevice = device;
    sWindowWidth = width;
    sWindowHeight = height;
    const char* fault = getenv("OO_BACKEND_FAULT");
    sFault = fault != NULL ? fault : "";

    sWindowColor = CreateTarget(kColorFormat, SDL_GPU_TEXTUREUSAGE_COLOR_TARGET | SDL_GPU_TEXTUREUSAGE_SAMPLER, width, height);
    sWindowDepth = CreateTarget(kDepthFormat, SDL_GPU_TEXTUREUSAGE_DEPTH_STENCIL_TARGET, width, height);
    if (sWindowColor == NULL || sWindowDepth == NULL)
        return false;

    if (!OOGLSLTranslatorInit())
        return false;
    OOGLSLOutputFormats formats = (SDL_GetGPUShaderFormats(device) & SDL_GPU_SHADERFORMAT_MSL) ? kOOGLSLOutputMSL : kOOGLSLOutputSPIRV;
    if (!OOGLSLTranslateProgram(NULL, NULL, NULL, formats, &sFixedFunction)) {
        fprintf(stderr, "fixed-function emulation: %s\n", sFixedFunction.log);
        return false;
    }
    sFixedVertex = CreateShader(&sFixedFunction.stages[kOOGLSLStageVertex], SDL_GPU_SHADERSTAGE_VERTEX);
    sFixedFragment = CreateShader(&sFixedFunction.stages[kOOGLSLStageFragment], SDL_GPU_SHADERSTAGE_FRAGMENT);
    if (sFixedVertex == NULL || sFixedFragment == NULL)
        return false;
    const OOGLSLStageResult* fragment = &sFixedFunction.stages[kOOGLSLStageFragment];
    for (size_t i = 0; i < fragment->samplerCount; i++) {
        if (strcmp(fragment->samplers[i].name, "oo_FixedFunctionTexture0") == 0)
            sTextureSamplerSlot = fragment->samplers[i].slot;
    }

    // Every emulation input reads from the one interleaved vertex.
    const OOGLSLStageResult* vertex = &sFixedFunction.stages[kOOGLSLStageVertex];
    for (size_t i = 0; i < vertex->vertexInputCount && sAttributeCount < 8; i++) {
        size_t offset;
        SDL_GPUVertexElementFormat format = SDL_GPU_VERTEXELEMENTFORMAT_FLOAT4;
        switch (InputForName(vertex->vertexInputs[i].name)) {
        case kInputPosition:
            offset = offsetof(GPUVertex, position);
            break;
        case kInputColor:
            offset = offsetof(GPUVertex, color);
            break;
        case kInputTexCoord:
            offset = offsetof(GPUVertex, texCoord);
            break;
        case kInputNormal:
            offset = offsetof(GPUVertex, normal);
            format = SDL_GPU_VERTEXELEMENTFORMAT_FLOAT3;
            break;
        default:
            continue;
        }
        sAttributes[sAttributeCount++] = (SDL_GPUVertexAttribute) {
            .location = vertex->vertexInputs[i].location,
            .buffer_slot = 0,
            .format = format,
            .offset = (Uint32)offset,
        };
    }
    CreateWhiteTexture();
    return true;
}

#pragma mark - Pipelines

typedef struct {
    SDL_GPUPrimitiveType topology;
    bool blend;
    OOBlendFactor blendSrc, blendDst;
    bool depthTest, depthWrite;
    OOCompareOp depthFunc;
    SDL_GPUCullMode cull;
    bool frontFaceCCW;
    bool wireframe;
} PipelineKey;

typedef struct {
    PipelineKey key;
    SDL_GPUGraphicsPipeline* pipeline;
} PipelineEntry;

static PipelineEntry* sPipelines = NULL;
static size_t sPipelineCount = 0, sPipelineCapacity = 0;

static SDL_GPUBlendFactor GPUBlendFactor(OOBlendFactor factor)
{
    switch (factor) {
    case kOOBlendFactorZero:
        return SDL_GPU_BLENDFACTOR_ZERO;
    case kOOBlendFactorOne:
        return SDL_GPU_BLENDFACTOR_ONE;
    case kOOBlendFactorSrcAlpha:
        return SDL_GPU_BLENDFACTOR_SRC_ALPHA;
    case kOOBlendFactorOneMinusSrcAlpha:
        return SDL_GPU_BLENDFACTOR_ONE_MINUS_SRC_ALPHA;
    case kOOBlendFactorDstColor:
        return SDL_GPU_BLENDFACTOR_DST_COLOR;
    case kOOBlendFactorOneMinusSrcColor:
        return SDL_GPU_BLENDFACTOR_ONE_MINUS_SRC_COLOR;
    case kOOBlendFactorSrcColor:
        return SDL_GPU_BLENDFACTOR_SRC_COLOR;
    case kOOBlendFactorOther:
        break;
    }
    OORendererBackendWarn("SDL_GPU backend: unsupported blend factor");
    return SDL_GPU_BLENDFACTOR_ONE;
}

static SDL_GPUCompareOp GPUCompareOp(OOCompareOp op)
{
    switch (op) {
    case kOOCompareNever:
        return SDL_GPU_COMPAREOP_NEVER;
    case kOOCompareLess:
        return SDL_GPU_COMPAREOP_LESS;
    case kOOCompareEqual:
        return SDL_GPU_COMPAREOP_EQUAL;
    case kOOCompareLessOrEqual:
        return SDL_GPU_COMPAREOP_LESS_OR_EQUAL;
    case kOOCompareGreater:
        return SDL_GPU_COMPAREOP_GREATER;
    case kOOCompareNotEqual:
        return SDL_GPU_COMPAREOP_NOT_EQUAL;
    case kOOCompareGreaterOrEqual:
        return SDL_GPU_COMPAREOP_GREATER_OR_EQUAL;
    case kOOCompareAlways:
        break;
    }
    return SDL_GPU_COMPAREOP_ALWAYS;
}

static PipelineKey CurrentKey(SDL_GPUPrimitiveType topology)
{
    const OORenderStateMachine* s = OORendererState();
    PipelineKey key = {
        .topology = topology,
        .blend = s->caps[kOOCapBlend],
        .blendSrc = s->blendSrc,
        .blendDst = s->blendDst,
        .depthTest = s->caps[kOOCapDepthTest],
        .depthWrite = s->depthMask,
        .depthFunc = s->depthFunc,
        .cull = SDL_GPU_CULLMODE_NONE,
        .frontFaceCCW = s->frontFaceCCW,
        .wireframe = s->wireframe,
    };
    if (s->caps[kOOCapCullFace]) {
        // GL_FRONT_AND_BACK draws nothing; SDL_GPU has no such mode.
        key.cull = s->cullFace == kOOCullFront ? SDL_GPU_CULLMODE_FRONT : SDL_GPU_CULLMODE_BACK;
    }
    if (!key.blend) {
        key.blendSrc = kOOBlendFactorOne;
        key.blendDst = kOOBlendFactorZero;
    }
    if (strcmp(sFault, "blend") == 0 && key.blend)
        key.blendDst = kOOBlendFactorOne;
    if (strcmp(sFault, "cull") == 0)
        key.frontFaceCCW = !key.frontFaceCCW;
    if (strcmp(sFault, "depth") == 0)
        key.depthTest = false;
    return key;
}

static SDL_GPUGraphicsPipeline* PipelineFor(const PipelineKey* key)
{
    for (size_t i = 0; i < sPipelineCount; i++) {
        if (memcmp(&sPipelines[i].key, key, sizeof *key) == 0)
            return sPipelines[i].pipeline;
    }

    SDL_GPUColorTargetDescription color = {
        .format = kColorFormat,
        .blend_state = {
            .enable_blend = key->blend,
            .src_color_blendfactor = GPUBlendFactor(key->blendSrc),
            .dst_color_blendfactor = GPUBlendFactor(key->blendDst),
            .color_blend_op = SDL_GPU_BLENDOP_ADD,
            // glBlendFunc applies the same factors to alpha.
            .src_alpha_blendfactor = GPUBlendFactor(key->blendSrc),
            .dst_alpha_blendfactor = GPUBlendFactor(key->blendDst),
            .alpha_blend_op = SDL_GPU_BLENDOP_ADD,
        },
    };
    SDL_GPUVertexBufferDescription buffer = {
        .slot = 0,
        .pitch = sizeof(GPUVertex),
        .input_rate = SDL_GPU_VERTEXINPUTRATE_VERTEX,
    };
    SDL_GPUGraphicsPipelineCreateInfo info = {
        .vertex_shader = sFixedVertex,
        .fragment_shader = sFixedFragment,
        .vertex_input_state = {
            .vertex_buffer_descriptions = &buffer,
            .num_vertex_buffers = 1,
            .vertex_attributes = sAttributes,
            .num_vertex_attributes = sAttributeCount,
        },
        .primitive_type = key->topology,
        .rasterizer_state = {
            .fill_mode = key->wireframe ? SDL_GPU_FILLMODE_LINE : SDL_GPU_FILLMODE_FILL,
            .cull_mode = key->cull,
            // Geometry and matrices stay in GL's convention, and SDL_GPU's
            // clip space has +y up as GL's does, so winding is unchanged.
            .front_face = key->frontFaceCCW ? SDL_GPU_FRONTFACE_COUNTER_CLOCKWISE : SDL_GPU_FRONTFACE_CLOCKWISE,
            // GL clips at the near and far planes; SDL_GPU clamps unless asked.
            .enable_depth_clip = strcmp(sFault, "depthclamp") != 0,
        },
        .depth_stencil_state = {
            .compare_op = GPUCompareOp(key->depthFunc),
            .enable_depth_test = key->depthTest,
            .enable_depth_write = key->depthTest && key->depthWrite,
        },
        .target_info = {
            .color_target_descriptions = &color,
            .num_color_targets = 1,
            .depth_stencil_format = kDepthFormat,
            .has_depth_stencil_target = true,
        },
    };
    SDL_GPUGraphicsPipeline* pipeline = SDL_CreateGPUGraphicsPipeline(sDevice, &info);
    if (pipeline == NULL) {
        fprintf(stderr, "SDL_CreateGPUGraphicsPipeline: %s\n", SDL_GetError());
        return NULL;
    }
    if (sPipelineCount == sPipelineCapacity) {
        sPipelineCapacity = sPipelineCapacity ? sPipelineCapacity * 2 : 16;
        sPipelines = realloc(sPipelines, sPipelineCapacity * sizeof *sPipelines);
    }
    sPipelines[sPipelineCount++] = (PipelineEntry) { *key, pipeline };
    return pipeline;
}

#pragma mark - Matrices and the legacy uniform block

static void Multiply(const float* a, const float* b, float* out)
{
    float r[16];
    for (int c = 0; c < 4; c++) {
        for (int row = 0; row < 4; row++) {
            float sum = 0;
            for (int k = 0; k < 4; k++)
                sum += a[k * 4 + row] * b[c * 4 + k];
            r[c * 4 + row] = sum;
        }
    }
    memcpy(out, r, sizeof r);
}

static void Transpose(const float* a, float* out)
{
    float r[16];
    for (int c = 0; c < 4; c++) {
        for (int row = 0; row < 4; row++)
            r[c * 4 + row] = a[row * 4 + c];
    }
    memcpy(out, r, sizeof r);
}

static void Inverse(const float* m, float* out)
{
    float inv[16];
    inv[0] = m[5] * m[10] * m[15] - m[5] * m[11] * m[14] - m[9] * m[6] * m[15] + m[9] * m[7] * m[14] + m[13] * m[6] * m[11] - m[13] * m[7] * m[10];
    inv[4] = -m[4] * m[10] * m[15] + m[4] * m[11] * m[14] + m[8] * m[6] * m[15] - m[8] * m[7] * m[14] - m[12] * m[6] * m[11] + m[12] * m[7] * m[10];
    inv[8] = m[4] * m[9] * m[15] - m[4] * m[11] * m[13] - m[8] * m[5] * m[15] + m[8] * m[7] * m[13] + m[12] * m[5] * m[11] - m[12] * m[7] * m[9];
    inv[12] = -m[4] * m[9] * m[14] + m[4] * m[10] * m[13] + m[8] * m[5] * m[14] - m[8] * m[6] * m[13] - m[12] * m[5] * m[10] + m[12] * m[6] * m[9];
    inv[1] = -m[1] * m[10] * m[15] + m[1] * m[11] * m[14] + m[9] * m[2] * m[15] - m[9] * m[3] * m[14] - m[13] * m[2] * m[11] + m[13] * m[3] * m[10];
    inv[5] = m[0] * m[10] * m[15] - m[0] * m[11] * m[14] - m[8] * m[2] * m[15] + m[8] * m[3] * m[14] + m[12] * m[2] * m[11] - m[12] * m[3] * m[10];
    inv[9] = -m[0] * m[9] * m[15] + m[0] * m[11] * m[13] + m[8] * m[1] * m[15] - m[8] * m[3] * m[13] - m[12] * m[1] * m[11] + m[12] * m[3] * m[9];
    inv[13] = m[0] * m[9] * m[14] - m[0] * m[10] * m[13] - m[8] * m[1] * m[14] + m[8] * m[2] * m[13] + m[12] * m[1] * m[10] - m[12] * m[2] * m[9];
    inv[2] = m[1] * m[6] * m[15] - m[1] * m[7] * m[14] - m[5] * m[2] * m[15] + m[5] * m[3] * m[14] + m[13] * m[2] * m[7] - m[13] * m[3] * m[6];
    inv[6] = -m[0] * m[6] * m[15] + m[0] * m[7] * m[14] + m[4] * m[2] * m[15] - m[4] * m[3] * m[14] - m[12] * m[2] * m[7] + m[12] * m[3] * m[6];
    inv[10] = m[0] * m[5] * m[15] - m[0] * m[7] * m[13] - m[4] * m[1] * m[15] + m[4] * m[3] * m[13] + m[12] * m[1] * m[7] - m[12] * m[3] * m[5];
    inv[14] = -m[0] * m[5] * m[14] + m[0] * m[6] * m[13] + m[4] * m[1] * m[14] - m[4] * m[2] * m[13] - m[12] * m[1] * m[6] + m[12] * m[2] * m[5];
    inv[3] = -m[1] * m[6] * m[11] + m[1] * m[7] * m[10] + m[5] * m[2] * m[11] - m[5] * m[3] * m[10] - m[9] * m[2] * m[7] + m[9] * m[3] * m[6];
    inv[7] = m[0] * m[6] * m[11] - m[0] * m[7] * m[10] - m[4] * m[2] * m[11] + m[4] * m[3] * m[10] + m[8] * m[2] * m[7] - m[8] * m[3] * m[6];
    inv[11] = -m[0] * m[5] * m[11] + m[0] * m[7] * m[9] + m[4] * m[1] * m[11] - m[4] * m[3] * m[9] - m[8] * m[1] * m[7] + m[8] * m[3] * m[5];
    inv[15] = m[0] * m[5] * m[10] - m[0] * m[6] * m[9] - m[4] * m[1] * m[10] + m[4] * m[2] * m[9] + m[8] * m[1] * m[6] - m[8] * m[2] * m[5];
    float det = m[0] * inv[0] + m[1] * inv[4] + m[2] * inv[8] + m[3] * inv[12];
    if (det == 0.0f) {
        memset(out, 0, 16 * sizeof(float));
        return;
    }
    for (int i = 0; i < 16; i++)
        out[i] = inv[i] / det;
}

static void Copy4(float* out, const float* in)
{
    memcpy(out, in, 4 * sizeof(float));
}

static void BuildLegacyState(OOGLSLLegacyStateBlock* L)
{
    const OORenderStateMachine* s = OORendererState();
    const OOFixedFunctionValues* ff = OORendererGetFixedFunctionValues();
    memset(L, 0, sizeof *L);

    float mv[16], p[16], mvp[16], inverse[16];
    memcpy(mv, s->modelView, sizeof mv);
    memcpy(p, s->projection, sizeof p);
    Multiply(p, mv, mvp);
    memcpy(L->modelViewMatrix, mv, sizeof mv);
    memcpy(L->projectionMatrix, p, sizeof p);
    memcpy(L->modelViewProjectionMatrix, mvp, sizeof mvp);
    Inverse(mv, L->modelViewMatrixInverse);
    Inverse(p, L->projectionMatrixInverse);
    Inverse(mvp, L->modelViewProjectionMatrixInverse);
    Transpose(mv, L->modelViewMatrixTranspose);
    Inverse(mv, inverse);
    Transpose(inverse, L->modelViewMatrixInverseTranspose);
    // gl_NormalMatrix: the upper 3x3 of the inverse transpose, std140 columns.
    for (int c = 0; c < 3; c++)
        memcpy(&L->normalMatrix[c * 4], &L->modelViewMatrixInverseTranspose[c * 4], 3 * sizeof(float));
    for (int t = 0; t < kOOGLSLMaxTextureCoords; t++) {
        for (int i = 0; i < 4; i++)
            L->textureMatrix[t][i * 5] = 1.0f;
    }

    const OOMaterialValues* material = &ff->frontMaterial;
    Copy4(L->frontMaterial.emission, material->emission);
    Copy4(L->frontMaterial.ambient, material->ambient);
    Copy4(L->frontMaterial.diffuse, material->diffuse);
    Copy4(L->frontMaterial.specular, material->specular);
    L->frontMaterial.shininess = material->shininess;
    Copy4(L->lightModelAmbient, ff->lightModelAmbient);
    for (int i = 0; i < kOOGLSLMaxLights && i < kOOFixedFunctionMaxLights; i++) {
        OOGLSLLightSource* light = &L->lightSource[i];
        const OOLightValues* values = &ff->lights[i];
        // A disabled light contributes nothing; the emulation reads zeroed colours.
        if (s->lights[i]) {
            Copy4(light->ambient, values->ambient);
            Copy4(light->diffuse, values->diffuse);
            Copy4(light->specular, values->specular);
        }
        Copy4(light->position, values->position);
        light->spotCutoff = 180;
        light->spotCosCutoff = -1;
        light->constantAttenuation = 1;
        for (int k = 0; k < 4; k++) {
            L->frontLightProduct[i].ambient[k] = material->ambient[k] * light->ambient[k];
            L->frontLightProduct[i].diffuse[k] = material->diffuse[k] * light->diffuse[k];
            L->frontLightProduct[i].specular[k] = material->specular[k] * light->specular[k];
        }
    }
    for (int k = 0; k < 4; k++)
        L->frontLightModelProductSceneColor[k] = material->emission[k] + material->ambient[k] * ff->lightModelAmbient[k];
    L->frontLightModelProductSceneColor[3] = material->diffuse[3];
    L->fogDensity = 1;
    L->fogEnd = 1;
    L->fogScale = 1;
    L->viewportHeight = (float)sWindowHeight;
    L->pointSize = 1;
    L->lightingEnabled = s->caps[kOOCapLighting] ? 1.0f : 0.0f;
}

#pragma mark - Textures

typedef struct {
    SDL_GPUTexture* texture;
    SDL_GPUSampler* sampler;
    OOTextureDescriptor descriptor;
} TextureRecord;

static TextureRecord* sTextures = NULL; // index = handle - 1
static size_t sTextureCount = 0;
static uint32_t sWhiteTexture = 0;

typedef struct {
    uint32_t texture;
    unsigned face, level, width, height;
    uint8_t* rgba;
} PendingUpload;

static PendingUpload* sUploads = NULL;
static size_t sUploadCount = 0, sUploadCapacity = 0;

static TextureRecord* TextureFor(uint32_t handle)
{
    if (handle == 0 || handle > sTextureCount || sTextures[handle - 1].texture == NULL)
        return NULL;
    return &sTextures[handle - 1];
}

uint32_t OORendererBackendCreateTexture(const OOTextureDescriptor* descriptor)
{
    SDL_GPUTextureCreateInfo info = {
        .type = descriptor->cube ? SDL_GPU_TEXTURETYPE_CUBE : SDL_GPU_TEXTURETYPE_2D,
        .format = descriptor->srgb ? SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM_SRGB : SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM,
        .usage = SDL_GPU_TEXTUREUSAGE_SAMPLER,
        .width = descriptor->width,
        .height = descriptor->height,
        .layer_count_or_depth = descriptor->cube ? 6 : 1,
        .num_levels = descriptor->levels,
    };
    SDL_GPUTexture* texture = SDL_CreateGPUTexture(sDevice, &info);
    if (texture == NULL) {
        OORendererBackendWarn("SDL_GPU backend: texture creation failed");
        return 0;
    }
    SDL_GPUSamplerAddressMode clamp = SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE;
    SDL_GPUSamplerCreateInfo samplerInfo = {
        .min_filter = descriptor->minFilter == kOOFilterNearest ? SDL_GPU_FILTER_NEAREST : SDL_GPU_FILTER_LINEAR,
        .mag_filter = descriptor->magFilter == kOOFilterNearest ? SDL_GPU_FILTER_NEAREST : SDL_GPU_FILTER_LINEAR,
        .mipmap_mode = SDL_GPU_SAMPLERMIPMAPMODE_LINEAR,
        .address_mode_u = descriptor->repeatS && !descriptor->cube ? SDL_GPU_SAMPLERADDRESSMODE_REPEAT : clamp,
        .address_mode_v = descriptor->repeatT && !descriptor->cube ? SDL_GPU_SAMPLERADDRESSMODE_REPEAT : clamp,
        .address_mode_w = clamp,
        .max_lod = descriptor->minFilter == kOOFilterLinearMipmapLinear ? (float)(descriptor->levels - 1) : 0.0f,
        .max_anisotropy = descriptor->anisotropy,
        .enable_anisotropy = descriptor->anisotropy > 1.0f,
    };
    TextureRecord record = { texture, SDL_CreateGPUSampler(sDevice, &samplerInfo), *descriptor };
    sTextures = realloc(sTextures, (sTextureCount + 1) * sizeof *sTextures);
    sTextures[sTextureCount++] = record;
    return (uint32_t)sTextureCount;
}

// SDL_GPU has no luminance or alpha formats, and no swizzle: expand to RGBA.
static uint8_t* ExpandToRGBA(OOTexelFormat format, const uint8_t* in, size_t texels)
{
    uint8_t* out = malloc(texels * 4);
    for (size_t i = 0; i < texels; i++) {
        uint8_t* o = &out[i * 4];
        switch (format) {
        case kOOTexelRGBA8:
            memcpy(o, &in[i * 4], 4);
            break;
        case kOOTexelGray8:
            o[0] = o[1] = o[2] = in[i];
            o[3] = 255;
            break;
        case kOOTexelAlpha8:
            o[0] = o[1] = o[2] = 0;
            o[3] = in[i];
            break;
        case kOOTexelGrayAlpha8:
            o[0] = o[1] = o[2] = in[i * 2];
            o[3] = in[i * 2 + 1];
            break;
        }
    }
    return out;
}

void OORendererBackendUploadTexture(uint32_t texture, unsigned face, unsigned level, unsigned width, unsigned height, const void* texels)
{
    TextureRecord* record = TextureFor(texture);
    if (record == NULL || texels == NULL)
        return;
    if (sUploadCount == sUploadCapacity) {
        sUploadCapacity = sUploadCapacity ? sUploadCapacity * 2 : 16;
        sUploads = realloc(sUploads, sUploadCapacity * sizeof *sUploads);
    }
    sUploads[sUploadCount++] = (PendingUpload) { texture, face, level, width, height,
        ExpandToRGBA(record->descriptor.format, texels, (size_t)width * height) };
}

static void CreateWhiteTexture(void)
{
    OOTextureDescriptor descriptor = { .width = 1, .height = 1, .levels = 1, .format = kOOTexelRGBA8 };
    sWhiteTexture = OORendererBackendCreateTexture(&descriptor);
    static const uint8_t white[4] = { 255, 255, 255, 255 };
    OORendererBackendUploadTexture(sWhiteTexture, 0, 0, 1, 1, white);
}

static void FlushUploads(SDL_GPUCopyPass* copy)
{
    for (size_t i = 0; i < sUploadCount; i++) {
        PendingUpload* upload = &sUploads[i];
        TextureRecord* record = TextureFor(upload->texture);
        Uint32 size = upload->width * upload->height * 4;
        if (record != NULL && size > 0) {
            SDL_GPUTransferBufferCreateInfo transferInfo = { .usage = SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD, .size = size };
            SDL_GPUTransferBuffer* transfer = SDL_CreateGPUTransferBuffer(sDevice, &transferInfo);
            memcpy(SDL_MapGPUTransferBuffer(sDevice, transfer, false), upload->rgba, size);
            SDL_UnmapGPUTransferBuffer(sDevice, transfer);
            SDL_GPUTextureTransferInfo source = { .transfer_buffer = transfer };
            SDL_GPUTextureRegion region = {
                .texture = record->texture,
                .mip_level = upload->level,
                .layer = upload->face,
                .w = upload->width,
                .h = upload->height,
                .d = 1,
            };
            SDL_UploadToGPUTexture(copy, &source, &region, false);
            SDL_ReleaseGPUTransferBuffer(sDevice, transfer);
        }
        free(upload->rgba);
    }
    sUploadCount = 0;
}

void OORendererBackendReadTexture(uint32_t texture, unsigned face, unsigned level, unsigned width, unsigned height, void* texels)
{
    (void)texture;
    (void)face;
    (void)level;
    (void)width;
    (void)height;
    (void)texels;
    OORendererBackendWarn("SDL_GPU backend: texture readback isn't implemented yet");
}

void OORendererBackendDeleteTexture(uint32_t texture)
{
    TextureRecord* record = TextureFor(texture);
    if (record == NULL)
        return;
    SDL_ReleaseGPUTexture(sDevice, record->texture);
    SDL_ReleaseGPUSampler(sDevice, record->sampler);
    memset(record, 0, sizeof *record);
}

#pragma mark - Recording draws

typedef struct {
    PipelineKey key;
    size_t firstVertex, vertexCount;
    size_t uniformIndex;
    uint32_t texture;
    SDL_Rect viewport;
    bool scissor;
    SDL_Rect scissorRect;
} RecordedDraw;

static GPUVertex* sVertices = NULL;
static size_t sVertexCount = 0, sVertexCapacity = 0;
static OOGLSLLegacyStateBlock* sUniforms = NULL;
static size_t sUniformCount = 0, sUniformCapacity = 0;
static RecordedDraw* sDraws = NULL;
static size_t sDrawCount = 0, sDrawCapacity = 0;

static GPUVertex* ReserveVertices(size_t count)
{
    if (sVertexCount + count > sVertexCapacity) {
        while (sVertexCount + count > sVertexCapacity)
            sVertexCapacity = sVertexCapacity ? sVertexCapacity * 2 : 4096;
        sVertices = realloc(sVertices, sVertexCapacity * sizeof *sVertices);
    }
    GPUVertex* result = &sVertices[sVertexCount];
    sVertexCount += count;
    return result;
}

// GL's bottom-left rectangles in SDL_GPU's top-left window co-ordinates.
static SDL_Rect FlipRect(const int r[4])
{
    if (strcmp(sFault, "origin") == 0)
        return (SDL_Rect) { r[0], r[1], r[2], r[3] };
    return (SDL_Rect) { r[0], (int)sWindowHeight - (r[1] + r[3]), r[2], r[3] };
}

/*  Record count vertices, already expanded to a list topology. A flat-shaded
    primitive takes its colour from its last vertex, as in GL.
*/
static void RecordDraw(SDL_GPUPrimitiveType topology, size_t first, size_t count)
{
    const OORenderStateMachine* s = OORendererState();
    unsigned perPrimitive = topology == SDL_GPU_PRIMITIVETYPE_TRIANGLELIST ? 3 : topology == SDL_GPU_PRIMITIVETYPE_LINELIST ? 2
                                                                                                                            : 1;
    if (s->flatShading && strcmp(sFault, "flat") != 0) {
        for (size_t p = first; p + perPrimitive <= first + count; p += perPrimitive) {
            for (unsigned v = 0; v + 1 < perPrimitive; v++)
                memcpy(sVertices[p + v].color, sVertices[p + perPrimitive - 1].color, sizeof sVertices[p].color);
        }
    }

    if (sUniformCount == sUniformCapacity) {
        sUniformCapacity = sUniformCapacity ? sUniformCapacity * 2 : 64;
        sUniforms = realloc(sUniforms, sUniformCapacity * sizeof *sUniforms);
    }
    BuildLegacyState(&sUniforms[sUniformCount]);

    const OOTextureUnitState* unit = &s->units[0];
    uint32_t texture = unit->texture2D && unit->binding2D != 0 && strcmp(sFault, "texture") != 0 ? unit->binding2D : sWhiteTexture;
    int full[4] = { 0, 0, (int)sWindowWidth, (int)sWindowHeight };
    if (sDrawCount == sDrawCapacity) {
        sDrawCapacity = sDrawCapacity ? sDrawCapacity * 2 : 64;
        sDraws = realloc(sDraws, sDrawCapacity * sizeof *sDraws);
    }
    sDraws[sDrawCount++] = (RecordedDraw) {
        .key = CurrentKey(topology),
        .firstVertex = first,
        .vertexCount = count,
        .uniformIndex = sUniformCount++,
        .texture = texture,
        .viewport = FlipRect(s->viewportSet ? s->viewport : full),
        .scissor = s->caps[kOOCapScissorTest],
        .scissorRect = FlipRect(s->scissor),
    };
}

static void SetVertex(GPUVertex* out, const float* position, unsigned positionComponents, const float* color,
    unsigned colorComponents, const float* texCoord, unsigned texCoordComponents, const float* normal)
{
    static const float kDefaultPosition[4] = { 0, 0, 0, 1 }, kDefaultTexCoord[4] = { 0, 0, 0, 1 };
    const OOImmediateAttributes current = OOImmediateGetAttributes();
    memcpy(out->position, kDefaultPosition, sizeof out->position);
    memcpy(out->texCoord, kDefaultTexCoord, sizeof out->texCoord);
    for (unsigned i = 0; i < positionComponents; i++)
        out->position[i] = position[i];
    // Arrays without colours, texture co-ordinates or normals use the current ones, as GL does.
    memcpy(out->color, current.color, sizeof out->color);
    if (color != NULL) {
        out->color[3] = 1.0f;
        for (unsigned i = 0; i < colorComponents; i++)
            out->color[i] = color[i];
    }
    if (texCoord != NULL) {
        for (unsigned i = 0; i < texCoordComponents; i++)
            out->texCoord[i] = texCoord[i];
    } else {
        out->texCoord[0] = current.texCoord[0];
        out->texCoord[1] = current.texCoord[1];
    }
    memcpy(out->normal, normal != NULL ? normal : current.normal, sizeof out->normal);
}

static SDL_GPUPrimitiveType ListTopology(OONativePrimitive primitive)
{
    switch (primitive) {
    case kOONativePrimitivePoints:
        return SDL_GPU_PRIMITIVETYPE_POINTLIST;
    case kOONativePrimitiveLines:
    case kOONativePrimitiveLineStrip:
        return SDL_GPU_PRIMITIVETYPE_LINELIST;
    case kOONativePrimitiveTriangles:
    case kOONativePrimitiveTriangleStrip:
        break;
    }
    return SDL_GPU_PRIMITIVETYPE_TRIANGLELIST;
}

/*  The list of source vertex indices for a native primitive: strips become
    lists. Triangle strips keep GL's order (odd triangles i+1, i, i+2), so the
    winding and the provoking last vertex are unchanged.
*/
static size_t ListIndices(OONativePrimitive primitive, size_t count, size_t* out)
{
    size_t n = 0;
    switch (primitive) {
    case kOONativePrimitiveLineStrip:
        for (size_t i = 0; i + 1 < count; i++) {
            out[n++] = i;
            out[n++] = i + 1;
        }
        return n;
    case kOONativePrimitiveTriangleStrip:
        for (size_t i = 0; i + 2 < count; i++) {
            out[n++] = i % 2 ? i + 1 : i;
            out[n++] = i % 2 ? i : i + 1;
            out[n++] = i + 2;
        }
        return n;
    case kOONativePrimitiveLines:
        count -= count % 2;
        break;
    case kOONativePrimitiveTriangles:
        count -= count % 3;
        break;
    case kOONativePrimitivePoints:
        break;
    }
    for (size_t i = 0; i < count; i++)
        out[n++] = i;
    return n;
}

static size_t ListCapacity(size_t count)
{
    return count * 3 + 3;
}

void OORendererBackendDrawImmediate(OONativePrimitive primitive, const OOImmediateVertex* vertices, size_t count)
{
    size_t* order = malloc(ListCapacity(count) * sizeof *order);
    size_t n = ListIndices(primitive, count, order);
    size_t first = sVertexCount;
    GPUVertex* out = ReserveVertices(n);
    for (size_t i = 0; i < n; i++) {
        const OOImmediateVertex* v = &vertices[order[i]];
        SetVertex(&out[i], v->position, 3, v->color, 4, v->texCoord, 2, v->normal);
    }
    free(order);
    if (n > 0)
        RecordDraw(ListTopology(primitive), first, n);
}

static const float* StreamElement(const OOVertexStream* stream, size_t index, unsigned defaultComponents)
{
    size_t stride = stream->stride ? stream->stride : (stream->components ? stream->components : defaultComponents) * sizeof(float);
    return (const float*)((const char*)stream->buffer->data + stream->offset + index * stride);
}

static void DrawLayout(OONativePrimitive primitive, const OOVertexLayout* layout, size_t first, size_t count,
    const void* indices, OOIndexType indexType)
{
    const OOVertexStream *position = NULL, *color = NULL, *texCoord = NULL, *normal = NULL;
    for (unsigned i = 0; i < layout->count; i++) {
        const OOVertexStream* stream = &layout->streams[i];
        switch (stream->semantic) {
        case kOOVertexPosition:
            position = stream;
            break;
        case kOOVertexColor:
            color = stream;
            break;
        case kOOVertexTexCoord:
            if (stream->index == 0)
                texCoord = stream;
            break;
        case kOOVertexNormal:
            normal = stream;
            break;
        case kOOVertexAttribute:
            // Generic attribute 0 stands in for gl_Vertex, as in GL.
            if (stream->index == 0 && position == NULL)
                position = stream;
            break;
        }
    }
    if (position == NULL) {
        OORendererBackendWarn("SDL_GPU backend: a vertex layout without positions");
        return;
    }

    size_t* order = malloc(ListCapacity(count) * sizeof *order);
    size_t n = ListIndices(primitive, count, order);
    size_t firstOut = sVertexCount;
    GPUVertex* out = ReserveVertices(n);
    for (size_t i = 0; i < n; i++) {
        size_t index = first + order[i];
        if (indices != NULL)
            index = indexType == kOOIndex16 ? ((const uint16_t*)indices)[order[i]] : ((const uint32_t*)indices)[order[i]];
        SetVertex(&out[i], StreamElement(position, index, 3), position->components,
            color ? StreamElement(color, index, 4) : NULL, color ? color->components : 0,
            texCoord ? StreamElement(texCoord, index, 2) : NULL, texCoord ? texCoord->components : 0,
            normal ? StreamElement(normal, index, 3) : NULL);
    }
    free(order);
    if (n > 0)
        RecordDraw(ListTopology(primitive), firstOut, n);
}

void OORendererBackendDrawArrays(OONativePrimitive primitive, const OOVertexLayout* layout, size_t first, size_t count)
{
    DrawLayout(primitive, layout, first, count, NULL, kOOIndex32);
}

void OORendererBackendDrawElements(OONativePrimitive primitive, const OOVertexLayout* layout,
    const void* indices, OOIndexType indexType, size_t count)
{
    DrawLayout(primitive, layout, 0, count, indices, indexType);
}

#pragma mark - Passes

static float sClearColor[4] = { 0, 0, 0, 0 };
static float sClearDepth = 1.0f;
static OORenderPassDescriptor sPass;

void OORendererBackendSetClearValues(const float clearColor[4], float clearDepth)
{
    memcpy(sClearColor, clearColor, sizeof sClearColor);
    sClearDepth = clearDepth;
}

void OORendererBackendBeginPass(const OORenderPassDescriptor* pass, const float clearColor[4], float clearDepth)
{
    if (pass->target != kOORenderTargetCurrent && pass->target != OORendererWindowTarget())
        OORendererBackendWarn("SDL_GPU backend: only the window target is implemented; drawing there instead");
    sPass = *pass;
    memcpy(sClearColor, clearColor, sizeof sClearColor);
    sClearDepth = clearDepth;
    sVertexCount = sUniformCount = sDrawCount = 0;
}

static SDL_GPULoadOp LoadOp(OOLoadOp op)
{
    switch (op) {
    case kOOLoadClear:
        return SDL_GPU_LOADOP_CLEAR;
    case kOOLoadDontCare:
        return SDL_GPU_LOADOP_DONT_CARE;
    case kOOLoadKeep:
        break;
    }
    return SDL_GPU_LOADOP_LOAD;
}

static SDL_GPUBuffer* sVertexBuffer = NULL;
static Uint32 sVertexBufferSize = 0;

static void WaitFor(SDL_GPUCommandBuffer* commands)
{
    SDL_GPUFence* fence = SDL_SubmitGPUCommandBufferAndAcquireFence(commands);
    if (fence != NULL) {
        SDL_WaitForGPUFences(sDevice, true, &fence, 1);
        SDL_ReleaseGPUFence(sDevice, fence);
    }
}

void OORendererBackendEndPass(void)
{
    SDL_GPUCommandBuffer* commands = SDL_AcquireGPUCommandBuffer(sDevice);
    Uint32 vertexBytes = (Uint32)(sVertexCount * sizeof(GPUVertex));

    SDL_GPUCopyPass* copy = SDL_BeginGPUCopyPass(commands);
    FlushUploads(copy);
    SDL_GPUTransferBuffer* transfer = NULL;
    if (vertexBytes > 0) {
        if (vertexBytes > sVertexBufferSize) {
            if (sVertexBuffer != NULL)
                SDL_ReleaseGPUBuffer(sDevice, sVertexBuffer);
            sVertexBufferSize = vertexBytes * 2;
            SDL_GPUBufferCreateInfo bufferInfo = { .usage = SDL_GPU_BUFFERUSAGE_VERTEX, .size = sVertexBufferSize };
            sVertexBuffer = SDL_CreateGPUBuffer(sDevice, &bufferInfo);
        }
        SDL_GPUTransferBufferCreateInfo transferInfo = { .usage = SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD, .size = vertexBytes };
        transfer = SDL_CreateGPUTransferBuffer(sDevice, &transferInfo);
        memcpy(SDL_MapGPUTransferBuffer(sDevice, transfer, false), sVertices, vertexBytes);
        SDL_UnmapGPUTransferBuffer(sDevice, transfer);
        SDL_GPUTransferBufferLocation source = { .transfer_buffer = transfer };
        SDL_GPUBufferRegion destination = { .buffer = sVertexBuffer, .size = vertexBytes };
        SDL_UploadToGPUBuffer(copy, &source, &destination, true);
    }
    SDL_EndGPUCopyPass(copy);

    SDL_GPUColorTargetInfo color = {
        .texture = sWindowColor,
        .clear_color = { sClearColor[0], sClearColor[1], sClearColor[2], sClearColor[3] },
        .load_op = LoadOp(sPass.colorLoad),
        .store_op = SDL_GPU_STOREOP_STORE,
    };
    SDL_GPUDepthStencilTargetInfo depth = {
        .texture = sWindowDepth,
        .clear_depth = sClearDepth,
        .load_op = LoadOp(sPass.depthLoad),
        .store_op = SDL_GPU_STOREOP_STORE,
        .stencil_load_op = SDL_GPU_LOADOP_DONT_CARE,
        .stencil_store_op = SDL_GPU_STOREOP_DONT_CARE,
    };
    SDL_GPURenderPass* pass = SDL_BeginGPURenderPass(commands, &color, 1, &depth);
    if (sDrawCount > 0) {
        SDL_GPUBufferBinding binding = { .buffer = sVertexBuffer };
        SDL_BindGPUVertexBuffers(pass, 0, &binding, 1);
    }
    for (size_t i = 0; i < sDrawCount; i++) {
        const RecordedDraw* draw = &sDraws[i];
        SDL_GPUGraphicsPipeline* pipeline = PipelineFor(&draw->key);
        TextureRecord* texture = TextureFor(draw->texture);
        if (pipeline == NULL || texture == NULL)
            continue;
        SDL_BindGPUGraphicsPipeline(pass, pipeline);
        SDL_GPUViewport viewport = { (float)draw->viewport.x, (float)draw->viewport.y, (float)draw->viewport.w, (float)draw->viewport.h, 0, 1 };
        SDL_SetGPUViewport(pass, &viewport);
        SDL_Rect scissor = draw->scissor ? draw->scissorRect : (SDL_Rect) { 0, 0, (int)sWindowWidth, (int)sWindowHeight };
        SDL_SetGPUScissor(pass, &scissor);
        SDL_GPUTextureSamplerBinding sampler = { .texture = texture->texture, .sampler = texture->sampler };
        SDL_BindGPUFragmentSamplers(pass, sTextureSamplerSlot, &sampler, 1);
        const OOGLSLLegacyStateBlock* uniforms = &sUniforms[draw->uniformIndex];
        SDL_PushGPUVertexUniformData(commands, kOOGLSLLegacyStateSlot, uniforms, sizeof *uniforms);
        SDL_PushGPUFragmentUniformData(commands, kOOGLSLLegacyStateSlot, uniforms, sizeof *uniforms);
        SDL_DrawGPUPrimitives(pass, (Uint32)draw->vertexCount, 1, (Uint32)draw->firstVertex, 0);
    }
    SDL_EndGPURenderPass(pass);
    // The harness reads back after each pass; the game will pipeline frames.
    WaitFor(commands);
    if (transfer != NULL)
        SDL_ReleaseGPUTransferBuffer(sDevice, transfer);
    sVertexCount = sUniformCount = sDrawCount = 0;
}

void OORendererBackendReadPixels(int x, int y, int width, int height, OOPixelFormat format, void* pixels)
{
    if (format != kOOPixelsBGRA8) {
        OORendererBackendWarn("SDL_GPU backend: only BGRA8 readback is implemented");
        return;
    }
    Uint32 size = (Uint32)(width * height * 4);
    SDL_GPUTransferBufferCreateInfo transferInfo = { .usage = SDL_GPU_TRANSFERBUFFERUSAGE_DOWNLOAD, .size = size };
    SDL_GPUTransferBuffer* transfer = SDL_CreateGPUTransferBuffer(sDevice, &transferInfo);
    SDL_GPUCommandBuffer* commands = SDL_AcquireGPUCommandBuffer(sDevice);
    SDL_GPUCopyPass* copy = SDL_BeginGPUCopyPass(commands);
    int flipped[4] = { x, y, width, height };
    SDL_Rect rect = FlipRect(flipped);
    SDL_GPUTextureRegion region = { .texture = sWindowColor, .x = (Uint32)rect.x, .y = (Uint32)rect.y, .w = (Uint32)width, .h = (Uint32)height, .d = 1 };
    SDL_GPUTextureTransferInfo destination = { .transfer_buffer = transfer };
    SDL_DownloadFromGPUTexture(copy, &region, &destination);
    SDL_EndGPUCopyPass(copy);
    WaitFor(commands);

    // SDL_GPU's rows run top-down; GL's bottom-up. RGBA to BGRA.
    const uint8_t* source = SDL_MapGPUTransferBuffer(sDevice, transfer, false);
    uint8_t* out = pixels;
    for (int row = 0; row < height; row++) {
        const uint8_t* in = source + (size_t)(height - 1 - row) * width * 4;
        for (int i = 0; i < width; i++) {
            uint8_t* o = out + ((size_t)row * width + i) * 4;
            o[0] = in[i * 4 + 2];
            o[1] = in[i * 4 + 1];
            o[2] = in[i * 4 + 0];
            o[3] = in[i * 4 + 3];
        }
    }
    SDL_UnmapGPUTransferBuffer(sDevice, transfer);
    SDL_ReleaseGPUTransferBuffer(sDevice, transfer);
}

#pragma mark - State the mirror already holds

/*  Pushed draw states are recorded in the state mirror by OORenderState.c,
    and fixed-function values by OOFixedFunction.c; draws read both. There
    is no GL context to apply them to, save or verify.
*/
void OORendererBackendPushDrawState(const OODrawState* state, int depth)
{
    (void)state;
    (void)depth;
}

void OORendererBackendPopDrawState(int depth)
{
    (void)depth;
}

void OORendererBackendVerifyDrawState(const OODrawState* state)
{
    (void)state;
}

void OORendererBackendVerifyStateMachine(void)
{
}

void OORendererBackendSetLightColor(unsigned light, OOLightColor which, const float rgba[4])
{
    (void)light;
    (void)which;
    (void)rgba;
}

void OORendererBackendSetLightPosition(unsigned light, const float eyePosition[4])
{
    (void)light;
    (void)eyePosition;
}

void OORendererBackendSetLightModelAmbient(const float rgba[4])
{
    (void)rgba;
}

void OORendererBackendSetLightModelSeparateSpecular(bool separate)
{
    (void)separate;
}

void OORendererBackendSetMaterialColor(OOMaterialFace face, OOMaterialColor which, const float rgba[4])
{
    (void)face;
    (void)which;
    (void)rgba;
}

void OORendererBackendSetMaterialShininess(OOMaterialFace face, float shininess)
{
    (void)face;
    (void)shininess;
}

void OORendererBackendSetFog(const OOFogValues* fog)
{
    (void)fog;
}

// No GL current values to keep in step with OOImmediate.
void OORendererBackendGetGLAttributes(OOImmediateAttributes* outAttributes)
{
    (void)outAttributes;
}

void OORendererBackendSetGLAttributes(const OOImmediateAttributes* attributes)
{
    (void)attributes;
}

void OORendererBackendCheckGLAttributes(const OOImmediateAttributes* expected)
{
    (void)expected;
}

#pragma mark - Not yet implemented

OORenderTarget OORendererBackendCreateRenderTarget(const OORenderTargetDescriptor* descriptor)
{
    (void)descriptor;
    OORendererBackendWarn("SDL_GPU backend: render targets aren't implemented yet");
    return 0;
}

void OORendererBackendResizeRenderTarget(OORenderTarget target, unsigned width, unsigned height)
{
    (void)target;
    (void)width;
    (void)height;
}

uint32_t OORendererBackendRenderTargetTexture(OORenderTarget target, unsigned attachment)
{
    (void)target;
    (void)attachment;
    return 0;
}

void OORendererBackendResolveRenderTarget(OORenderTarget source, OORenderTarget destination)
{
    (void)source;
    (void)destination;
}

void OORendererBackendDeleteRenderTarget(OORenderTarget target)
{
    (void)target;
}
