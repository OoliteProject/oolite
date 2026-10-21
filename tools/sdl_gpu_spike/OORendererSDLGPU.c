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
- orientation: everything is rendered upside down (the translator negates
  clip-space y), so every target holds GL's bottom-up rows. Uploaded
  textures and render targets then agree, as in GL, and viewports, scissor
  rectangles and readback use GL's co-ordinates unchanged. The front face
  is inverted to match. Only presenting to a window will need a flip;
- flat shading: GL uses the last vertex of each primitive;
- frames in flight: passes are submitted without waiting; only readback
  waits for the GPU;
- SDL_GPU has no luminance or alpha-only formats; they are expanded to
  RGBA on upload.

Not yet: colour material (Oolite never enables it), multitexture combine,
and texture environment modes other than modulate.


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
#include "OORendererProgram.h"

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
static const SDL_GPUTextureFormat kTargetColorFormat = SDL_GPU_TEXTUREFORMAT_R16G16B16A16_FLOAT;

// Render targets (below); the open pass's target is NULL for the window.
typedef struct TargetRecord TargetRecord;
static TargetRecord* sPassTarget = NULL;
static unsigned TargetWidth(void);
static unsigned TargetHeight(void);
static unsigned TargetColorCount(void);
static bool TargetHasDepth(void);
static bool TargetMultisampled(void);

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
    float generic[4]; // one generic attribute, such as a program's "tangent"
} GPUVertex;

typedef enum {
    kInputPosition,
    kInputColor,
    kInputTexCoord,
    kInputNormal,
    kInputGeneric,
    kInputNone,
} InputKind;

static SDL_GPUVertexAttribute sAttributes[16];
static uint32_t sAttributeCount = 0;
static OOGLSLOutputFormats sFormats = 0;

enum {
    kMaxSamplers = 16
};

// A uniform as both stages see it; -1 where a stage doesn't have it.
typedef struct {
    char* name;
    const OOGLSLUniform* uniform[kOOGLSLStageCount];
    int samplerSlot[kOOGLSLStageCount];
} ProgramUniform;

struct OORendererProgram {
    OOGLSLProgram translated;
    SDL_GPUShader* shaders[kOOGLSLStageCount];
    SDL_GPUVertexAttribute attributes[16];
    uint32_t attributeCount;
    int genericLocation; // the generic attribute bound to GPUVertex.generic, or -1
    ProgramUniform* uniforms;
    size_t uniformCount;
    // Current values, which persist as GL program state does.
    uint8_t* blocks[kOOGLSLStageCount];
    uint32_t blockSize[kOOGLSLStageCount];
    int samplerUnits[kOOGLSLStageCount][kMaxSamplers];
    bool samplerIsCube[kOOGLSLStageCount][kMaxSamplers];
    uint32_t samplerCount[kOOGLSLStageCount];
};

static OORendererProgram* sCurrentProgram = NULL;

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

static InputKind InputForName(const char* name, const char* genericName)
{
    if (genericName != NULL && strcmp(name, genericName) == 0)
        return kInputGeneric;
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

// Every shader input reads from the one interleaved vertex; unknown inputs are left unfed.
static uint32_t BuildAttributes(const OOGLSLStageResult* vertex, const char* genericName, SDL_GPUVertexAttribute out[16])
{
    uint32_t count = 0;
    for (size_t i = 0; i < vertex->vertexInputCount && count < 16; i++) {
        size_t offset;
        SDL_GPUVertexElementFormat format = SDL_GPU_VERTEXELEMENTFORMAT_FLOAT4;
        switch (InputForName(vertex->vertexInputs[i].name, genericName)) {
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
        case kInputGeneric:
            offset = offsetof(GPUVertex, generic);
            break;
        default:
            continue;
        }
        static const SDL_GPUVertexElementFormat kFormats[5] = { SDL_GPU_VERTEXELEMENTFORMAT_FLOAT4, SDL_GPU_VERTEXELEMENTFORMAT_FLOAT,
            SDL_GPU_VERTEXELEMENTFORMAT_FLOAT2, SDL_GPU_VERTEXELEMENTFORMAT_FLOAT3, SDL_GPU_VERTEXELEMENTFORMAT_FLOAT4 };
        // Feed the components the shader declares; the vertex supplies four.
        if (format == SDL_GPU_VERTEXELEMENTFORMAT_FLOAT4 && vertex->vertexInputs[i].vectorSize < 4)
            format = kFormats[vertex->vertexInputs[i].vectorSize];
        out[count++] = (SDL_GPUVertexAttribute) {
            .location = vertex->vertexInputs[i].location,
            .buffer_slot = 0,
            .format = format,
            .offset = (Uint32)offset,
        };
    }
    return count;
}

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
    formats |= kOOGLSLOutputGLOrientation;
    sFormats = formats;
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

    sAttributeCount = BuildAttributes(&sFixedFunction.stages[kOOGLSLStageVertex], NULL, sAttributes);
    CreateWhiteTexture();
    return true;
}

#pragma mark - Pipelines

typedef struct {
    const OORendererProgram* program; // NULL for the fixed-function emulation
    SDL_GPUPrimitiveType topology;
    // The pass's target.
    SDL_GPUTextureFormat colorFormat;
    unsigned colorCount;
    bool hasDepth;
    SDL_GPUSampleCount samples;
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
    // Zeroed first: the cache compares keys with memcmp, padding included.
    PipelineKey key;
    memset(&key, 0, sizeof key);
    key.program = sCurrentProgram;
    key.topology = topology;
    key.colorFormat = sPassTarget ? kTargetColorFormat : kColorFormat;
    key.colorCount = TargetColorCount();
    key.hasDepth = TargetHasDepth();
    key.samples = TargetMultisampled() ? SDL_GPU_SAMPLECOUNT_4 : SDL_GPU_SAMPLECOUNT_1;
    key.blend = s->caps[kOOCapBlend];
    key.blendSrc = s->blendSrc;
    key.blendDst = s->blendDst;
    key.depthTest = s->caps[kOOCapDepthTest];
    key.depthWrite = s->depthMask;
    key.depthFunc = s->depthFunc;
    key.cull = SDL_GPU_CULLMODE_NONE;
    key.frontFaceCCW = s->frontFaceCCW;
    key.wireframe = s->wireframe;
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

    SDL_GPUColorTargetDescription colors[kOOMaxColorAttachments];
    SDL_GPUColorTargetDescription color = {
        .format = key->colorFormat,
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
        .vertex_shader = key->program ? key->program->shaders[kOOGLSLStageVertex] : sFixedVertex,
        .fragment_shader = key->program ? key->program->shaders[kOOGLSLStageFragment] : sFixedFragment,
        .vertex_input_state = {
            .vertex_buffer_descriptions = &buffer,
            .num_vertex_buffers = 1,
            .vertex_attributes = key->program ? key->program->attributes : sAttributes,
            .num_vertex_attributes = key->program ? key->program->attributeCount : sAttributeCount,
        },
        .primitive_type = key->topology,
        .rasterizer_state = {
            .fill_mode = key->wireframe ? SDL_GPU_FILLMODE_LINE : SDL_GPU_FILLMODE_FILL,
            .cull_mode = key->cull,
            // Rendering upside down reverses the winding on screen.
            .front_face = key->frontFaceCCW ? SDL_GPU_FRONTFACE_CLOCKWISE : SDL_GPU_FRONTFACE_COUNTER_CLOCKWISE,
            // GL clips at the near and far planes; SDL_GPU clamps unless asked.
            .enable_depth_clip = strcmp(sFault, "depthclamp") != 0,
        },
        .depth_stencil_state = {
            .compare_op = GPUCompareOp(key->depthFunc),
            .enable_depth_test = key->depthTest,
            .enable_depth_write = key->depthTest && key->depthWrite,
        },
        .multisample_state = { .sample_count = key->samples },
        .target_info = {
            .color_target_descriptions = colors,
            .num_color_targets = key->colorCount,
            .depth_stencil_format = kDepthFormat,
            .has_depth_stencil_target = key->hasDepth,
        },
    };
    for (unsigned i = 0; i < key->colorCount; i++)
        colors[i] = color;
    if (!key->hasDepth) {
        info.depth_stencil_state.enable_depth_test = false;
        info.depth_stencil_state.enable_depth_write = false;
    }
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

/*  GL's built-in uniform state. Shaders see every light's values whether it
    is enabled or not, as in GL; the fixed-function emulation instead reads
    zeroed products for a disabled light.
*/
static void BuildLegacyState(OOGLSLLegacyStateBlock* L, bool fixedFunction)
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
        Copy4(light->ambient, values->ambient);
        Copy4(light->diffuse, values->diffuse);
        Copy4(light->specular, values->specular);
        Copy4(light->position, values->position);
        light->spotCutoff = 180;
        light->spotCosCutoff = -1;
        light->constantAttenuation = 1;
        if (fixedFunction && !s->lights[i])
            continue;
        for (int k = 0; k < 4; k++) {
            L->frontLightProduct[i].ambient[k] = material->ambient[k] * light->ambient[k];
            L->frontLightProduct[i].diffuse[k] = material->diffuse[k] * light->diffuse[k];
            L->frontLightProduct[i].specular[k] = material->specular[k] * light->specular[k];
        }
    }
    for (int k = 0; k < 4; k++)
        L->frontLightModelProductSceneColor[k] = material->emission[k] + material->ambient[k] * ff->lightModelAmbient[k];
    L->frontLightModelProductSceneColor[3] = material->diffuse[3];
    const OOFogValues* fog = &ff->fog;
    Copy4(L->fogColor, fog->color);
    L->fogDensity = fog->density;
    L->fogStart = fog->start;
    L->fogEnd = fog->end;
    L->fogScale = fog->end != fog->start ? 1.0f / (fog->end - fog->start) : 1.0f;
    L->fogMode = fog->mode == kOOFogExp ? 1.0f : fog->mode == kOOFogExp2 ? 2.0f
                                                                         : 0.0f;
    L->fogEnabled = s->caps[kOOCapFog] && strcmp(sFault, "fog") != 0 ? 1.0f : 0.0f;
    // The colour sum only applies with lighting.
    L->separateSpecular = ff->separateSpecular && s->caps[kOOCapLighting] && strcmp(sFault, "specular") != 0 ? 1.0f : 0.0f;
    L->viewportHeight = (float)TargetHeight();
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

static uint32_t sBlackTexture = 0, sBlackCube = 0;

/*  White stands in for texturing switched off in the fixed-function
    emulation. Black stands in for a program's sampler with nothing bound,
    which GL samples as (0, 0, 0, 1).
*/
static void CreateWhiteTexture(void)
{
    OOTextureDescriptor descriptor = { .width = 1, .height = 1, .levels = 1, .format = kOOTexelRGBA8 };
    sWhiteTexture = OORendererBackendCreateTexture(&descriptor);
    static const uint8_t white[4] = { 255, 255, 255, 255 }, black[4] = { 0, 0, 0, 255 };
    OORendererBackendUploadTexture(sWhiteTexture, 0, 0, 1, 1, white);
    sBlackTexture = OORendererBackendCreateTexture(&descriptor);
    OORendererBackendUploadTexture(sBlackTexture, 0, 0, 1, 1, black);
    descriptor.cube = true;
    sBlackCube = OORendererBackendCreateTexture(&descriptor);
    for (unsigned face = 0; face < 6; face++)
        OORendererBackendUploadTexture(sBlackCube, face, 0, 1, 1, black);
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

#pragma mark - Render targets

struct TargetRecord {
    bool used;
    OORenderTargetDescriptor descriptor;
    SDL_GPUTexture* color[kOOMaxColorAttachments];
    SDL_GPUTexture* depth;
    uint32_t colorTextures[kOOMaxColorAttachments]; // texture handles; single-sampled targets only
};

static TargetRecord* sTargets = NULL; // index = target - 1
static size_t sTargetCount = 0;

static TargetRecord* TargetFor(OORenderTarget target)
{
    if (target == 0 || target > sTargetCount || !sTargets[target - 1].used)
        return NULL;
    return &sTargets[target - 1];
}

static unsigned TargetWidth(void)
{
    return sPassTarget ? sPassTarget->descriptor.width : sWindowWidth;
}

static unsigned TargetHeight(void)
{
    return sPassTarget ? sPassTarget->descriptor.height : sWindowHeight;
}

static unsigned TargetColorCount(void)
{
    return sPassTarget ? sPassTarget->descriptor.colorAttachments : 1;
}

static bool TargetHasDepth(void)
{
    return sPassTarget ? sPassTarget->descriptor.depth : true;
}

static bool TargetMultisampled(void)
{
    return sPassTarget != NULL && sPassTarget->descriptor.samples > 1;
}

// Create (or, after a resize, recreate) a target's textures.
static void AllocateTarget(TargetRecord* record)
{
    const OORenderTargetDescriptor* d = &record->descriptor;
    bool multisample = d->samples > 1;
    SDL_GPUTextureCreateInfo info = {
        .type = SDL_GPU_TEXTURETYPE_2D,
        .format = kTargetColorFormat,
        .usage = SDL_GPU_TEXTUREUSAGE_COLOR_TARGET | (multisample ? 0 : SDL_GPU_TEXTUREUSAGE_SAMPLER),
        .width = d->width,
        .height = d->height,
        .layer_count_or_depth = 1,
        .num_levels = 1,
        .sample_count = multisample ? SDL_GPU_SAMPLECOUNT_4 : SDL_GPU_SAMPLECOUNT_1,
    };
    for (unsigned i = 0; i < d->colorAttachments; i++) {
        record->color[i] = SDL_CreateGPUTexture(sDevice, &info);
        if (multisample)
            continue;
        if (record->colorTextures[i] == 0) {
            // Attachments are sampled linearly and clamped, as on GL.
            SDL_GPUSamplerCreateInfo samplerInfo = {
                .min_filter = SDL_GPU_FILTER_LINEAR,
                .mag_filter = SDL_GPU_FILTER_LINEAR,
                .mipmap_mode = SDL_GPU_SAMPLERMIPMAPMODE_NEAREST,
                .address_mode_u = SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
                .address_mode_v = SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
                .address_mode_w = SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
            };
            TextureRecord texture = { NULL, SDL_CreateGPUSampler(sDevice, &samplerInfo), { .width = d->width, .height = d->height, .levels = 1 } };
            sTextures = realloc(sTextures, (sTextureCount + 1) * sizeof *sTextures);
            sTextures[sTextureCount++] = texture;
            record->colorTextures[i] = (uint32_t)sTextureCount;
        }
        sTextures[record->colorTextures[i] - 1].texture = record->color[i];
    }
    if (d->depth) {
        info.format = kDepthFormat;
        info.usage = SDL_GPU_TEXTUREUSAGE_DEPTH_STENCIL_TARGET;
        record->depth = SDL_CreateGPUTexture(sDevice, &info);
    }
}

static void ReleaseTargetTextures(TargetRecord* record)
{
    for (unsigned i = 0; i < record->descriptor.colorAttachments; i++) {
        if (record->color[i] != NULL)
            SDL_ReleaseGPUTexture(sDevice, record->color[i]);
        record->color[i] = NULL;
        if (record->colorTextures[i] != 0)
            sTextures[record->colorTextures[i] - 1].texture = NULL;
    }
    if (record->depth != NULL)
        SDL_ReleaseGPUTexture(sDevice, record->depth);
    record->depth = NULL;
}

OORenderTarget OORendererBackendCreateRenderTarget(const OORenderTargetDescriptor* descriptor)
{
    sTargets = realloc(sTargets, (sTargetCount + 1) * sizeof *sTargets);
    TargetRecord* record = &sTargets[sTargetCount++];
    memset(record, 0, sizeof *record);
    record->used = true;
    record->descriptor = *descriptor;
    AllocateTarget(record);
    return (OORenderTarget)sTargetCount;
}

void OORendererBackendResizeRenderTarget(OORenderTarget target, unsigned width, unsigned height)
{
    TargetRecord* record = TargetFor(target);
    if (record == NULL)
        return;
    // SDL_GPU textures can't be resized; the handles stay, the textures change.
    ReleaseTargetTextures(record);
    record->descriptor.width = width;
    record->descriptor.height = height;
    AllocateTarget(record);
}

uint32_t OORendererBackendRenderTargetTexture(OORenderTarget target, unsigned attachment)
{
    TargetRecord* record = TargetFor(target);
    if (record == NULL || record->descriptor.samples > 1 || attachment >= record->descriptor.colorAttachments)
        return 0;
    return record->colorTextures[attachment];
}

static void WaitFor(SDL_GPUCommandBuffer* commands);

void OORendererBackendResolveRenderTarget(OORenderTarget source, OORenderTarget destination)
{
    TargetRecord* from = TargetFor(source);
    TargetRecord* to = TargetFor(destination);
    if (from == NULL || to == NULL || from->descriptor.colorAttachments == 0 || to->descriptor.colorAttachments == 0)
        return;
    SDL_GPUCommandBuffer* commands = SDL_AcquireGPUCommandBuffer(sDevice);
    // An empty pass that resolves (SDL_GPU's form of GL's blit) colour 0.
    bool resolve = from->descriptor.samples > 1 && strcmp(sFault, "resolve") != 0;
    SDL_GPUColorTargetInfo color = {
        .texture = from->color[0],
        .load_op = SDL_GPU_LOADOP_LOAD,
        .store_op = resolve ? SDL_GPU_STOREOP_RESOLVE : SDL_GPU_STOREOP_STORE,
        .resolve_texture = resolve ? to->color[0] : NULL,
    };
    if (from->descriptor.samples == 1) {
        OORendererBackendWarn("SDL_GPU backend: resolving a single-sampled target isn't implemented");
        SDL_CancelGPUCommandBuffer(commands);
        return;
    }
    SDL_EndGPURenderPass(SDL_BeginGPURenderPass(commands, &color, 1, NULL));
    SDL_SubmitGPUCommandBuffer(commands);
}

void OORendererBackendDeleteRenderTarget(OORenderTarget target)
{
    TargetRecord* record = TargetFor(target);
    if (record == NULL)
        return;
    ReleaseTargetTextures(record);
    for (unsigned i = 0; i < record->descriptor.colorAttachments; i++) {
        if (record->colorTextures[i] != 0) {
            TextureRecord* texture = &sTextures[record->colorTextures[i] - 1];
            SDL_ReleaseGPUSampler(sDevice, texture->sampler);
            memset(texture, 0, sizeof *texture);
        }
    }
    record->used = false;
}

#pragma mark - Recording draws

typedef struct {
    PipelineKey key;
    size_t firstVertex, vertexCount;
    size_t uniformIndex;
    uint32_t texture;
    // Programs: the uniform blocks' offsets into sBlockBytes, and each sampler slot's texture.
    size_t blockOffset[kOOGLSLStageCount];
    uint32_t samplerTextures[kOOGLSLStageCount][kMaxSamplers];
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
static uint8_t* sBlockBytes = NULL;
static size_t sBlockUsed = 0, sBlockCapacity = 0;

static size_t CopyBlock(const uint8_t* block, uint32_t size)
{
    if (sBlockUsed + size > sBlockCapacity) {
        while (sBlockUsed + size > sBlockCapacity)
            sBlockCapacity = sBlockCapacity ? sBlockCapacity * 2 : 65536;
        sBlockBytes = realloc(sBlockBytes, sBlockCapacity);
    }
    size_t offset = sBlockUsed;
    memcpy(sBlockBytes + offset, block, size);
    sBlockUsed += size;
    return offset;
}

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

/*  A GL rectangle in the target's co-ordinates. Rendering in GL's
    orientation, they are the same; the "origin" fault flips them as if it
    weren't.
*/
static SDL_Rect TargetRect(const int r[4])
{
    if (strcmp(sFault, "origin") == 0)
        return (SDL_Rect) { r[0], (int)TargetHeight() - (r[1] + r[3]), r[2], r[3] };
    return (SDL_Rect) { r[0], r[1], r[2], r[3] };
}

/*  Record count vertices, already expanded to a list topology. A flat-shaded
    primitive takes its colour from its last vertex, as in GL.
*/
// Set while recording expanded lines and points, whose positions are already NDC.
static bool sDrawInNDC = false;

static void SetIdentityMatrices(OOGLSLLegacyStateBlock* L)
{
    float identity[16] = { 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1 };
    float* matrices[] = { L->modelViewMatrix, L->projectionMatrix, L->modelViewProjectionMatrix, L->modelViewMatrixInverse,
        L->projectionMatrixInverse, L->modelViewProjectionMatrixInverse, L->modelViewMatrixTranspose, L->modelViewMatrixInverseTranspose };
    for (size_t i = 0; i < sizeof matrices / sizeof *matrices; i++)
        memcpy(matrices[i], identity, sizeof identity);
    memset(L->normalMatrix, 0, sizeof L->normalMatrix);
    for (int c = 0; c < 3; c++)
        L->normalMatrix[c * 5] = 1.0f;
}

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
    BuildLegacyState(&sUniforms[sUniformCount], sCurrentProgram == NULL);
    if (sDrawInNDC)
        SetIdentityMatrices(&sUniforms[sUniformCount]);

    const OOTextureUnitState* unit = &s->units[0];
    uint32_t texture = unit->texture2D && unit->binding2D != 0 && strcmp(sFault, "texture") != 0 ? unit->binding2D : sWhiteTexture;
    int full[4] = { 0, 0, (int)TargetWidth(), (int)TargetHeight() };
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
        .viewport = TargetRect(s->viewportSet ? s->viewport : full),
        .scissor = s->caps[kOOCapScissorTest],
        .scissorRect = TargetRect(s->scissor),
    };
    RecordedDraw* draw = &sDraws[sDrawCount - 1];
    const OORendererProgram* program = sCurrentProgram;
    if (program != NULL) {
        for (int stage = 0; stage < kOOGLSLStageCount; stage++) {
            draw->blockOffset[stage] = CopyBlock(program->blocks[stage], program->blockSize[stage]);
            for (uint32_t slot = 0; slot < program->samplerCount[stage]; slot++) {
                int unit = program->samplerUnits[stage][slot];
                bool cube = program->samplerIsCube[stage][slot];
                uint32_t texture = 0;
                if (unit >= 0 && unit < kOOMaxTextureUnits)
                    texture = cube ? s->units[unit].bindingCube : s->units[unit].binding2D;
                if (TextureFor(texture) == NULL || strcmp(sFault, "sampler") == 0)
                    texture = cube ? sBlackCube : sBlackTexture;
                draw->samplerTextures[stage][slot] = texture;
            }
        }
    }
}

static void SetVertex(GPUVertex* out, const float* position, unsigned positionComponents, const float* color,
    unsigned colorComponents, const float* texCoord, unsigned texCoordComponents, const float* normal,
    const float* generic, unsigned genericComponents)
{
    // GL's default for a generic attribute without an array is (0, 0, 0, 1).
    static const float kDefaultGeneric[4] = { 0, 0, 0, 1 };
    memcpy(out->generic, kDefaultGeneric, sizeof out->generic);
    for (unsigned i = 0; generic != NULL && i < genericComponents; i++)
        out->generic[i] = generic[i];
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

/*  SDL_GPU has no wide lines, and point size isn't portable (Metal needs
    the shader to write it), so points and lines wider than a pixel are
    expanded into triangles, as GL would rasterise them, and drawn with
    identity matrices. Expanded geometry that is lit or fogged would use its
    NDC position as the eye position; Oolite's wide lines and points are
    neither.
*/
static bool NeedsExpansion(OONativePrimitive primitive, float lineWidth)
{
    if (primitive == kOONativePrimitivePoints)
        return true;
    return (primitive == kOONativePrimitiveLines || primitive == kOONativePrimitiveLineStrip) && lineWidth > 1.0f;
}

static void ExpandAndRecord(OONativePrimitive primitive, const OOImmediateVertex* in, size_t count, float lineWidth, float pointSize)
{
    const OORenderStateMachine* s = OORendererState();
    float mvp[16];
    Multiply(s->projection, s->modelView, mvp);
    float viewport[4] = { 0, 0, (float)TargetWidth(), (float)TargetHeight() };
    if (s->viewportSet) {
        for (int i = 0; i < 4; i++)
            viewport[i] = (float)s->viewport[i];
    }

    OOImmediateVertex* lines = NULL;
    OOImmediateVertex* out = NULL;
    size_t n = 0;
    if (primitive == kOONativePrimitivePoints) {
        bool smooth = s->caps[kOOCapPointSmooth];
        out = malloc(OOExpandPointsCapacity(count, smooth) * sizeof *out);
        n = OOExpandPointsToTriangles(in, count, pointSize, smooth, mvp, viewport, out);
    } else {
        // Separate segments, so a flat-shaded line can take its last vertex's colour throughout, as in GL.
        size_t segments = primitive == kOONativePrimitiveLineStrip ? (count > 1 ? count - 1 : 0) : count / 2;
        lines = malloc((segments * 2 + 1) * sizeof *lines);
        for (size_t i = 0; i < segments; i++) {
            size_t a = primitive == kOONativePrimitiveLineStrip ? i : i * 2;
            lines[i * 2] = in[a];
            lines[i * 2 + 1] = in[a + 1];
            if (s->flatShading)
                memcpy(lines[i * 2].color, lines[i * 2 + 1].color, sizeof lines[i * 2].color);
        }
        bool smooth = s->caps[kOOCapLineSmooth];
        out = malloc(OOExpandLinesCapacity(kOONativePrimitiveLines, segments * 2) * sizeof *out);
        n = OOExpandLinesToTriangles(kOONativePrimitiveLines, lines, segments * 2, lineWidth, smooth, mvp, viewport, out);
    }
    size_t first = sVertexCount;
    GPUVertex* gpu = ReserveVertices(n);
    for (size_t i = 0; i < n; i++)
        SetVertex(&gpu[i], out[i].position, 3, out[i].color, 4, out[i].texCoord, 2, out[i].normal, NULL, 0);
    free(out);
    free(lines);
    if (n > 0 && strcmp(sFault, "wide") != 0) {
        sDrawInNDC = true;
        RecordDraw(SDL_GPU_PRIMITIVETYPE_TRIANGLELIST, first, n);
        sDrawInNDC = false;
    }
}

void OORendererBackendDrawImmediate(OONativePrimitive primitive, const OOImmediateVertex* vertices, size_t count)
{
    if (NeedsExpansion(primitive, OOImmediateBatchLineWidth())) {
        ExpandAndRecord(primitive, vertices, count, OOImmediateBatchLineWidth(), OOImmediateBatchPointSize());
        return;
    }
    size_t* order = malloc(ListCapacity(count) * sizeof *order);
    size_t n = ListIndices(primitive, count, order);
    size_t first = sVertexCount;
    GPUVertex* out = ReserveVertices(n);
    for (size_t i = 0; i < n; i++) {
        const OOImmediateVertex* v = &vertices[order[i]];
        SetVertex(&out[i], v->position, 3, v->color, 4, v->texCoord, 2, v->normal, NULL, 0);
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
    const OOVertexStream *position = NULL, *color = NULL, *texCoord = NULL, *normal = NULL, *generic = NULL;
    int genericLocation = sCurrentProgram ? sCurrentProgram->genericLocation : -1;
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
            else if ((int)stream->index == genericLocation && strcmp(sFault, "generic") != 0)
                generic = stream;
            break;
        }
    }
    if (position == NULL) {
        OORendererBackendWarn("SDL_GPU backend: a vertex layout without positions");
        return;
    }

    if (NeedsExpansion(primitive, OOImmediateLineWidth())) {
        // Gather the vertices in order, then expand them as immediate mode does.
        OOImmediateVertex* gathered = malloc((count + 1) * sizeof *gathered);
        OOImmediateAttributes current = OOImmediateGetAttributes();
        for (size_t i = 0; i < count; i++) {
            size_t index = first + i;
            if (indices != NULL)
                index = indexType == kOOIndex16 ? ((const uint16_t*)indices)[i] : ((const uint32_t*)indices)[i];
            OOImmediateVertex* v = &gathered[i];
            memset(v, 0, sizeof *v);
            const float* p = StreamElement(position, index, 3);
            for (unsigned c = 0; c < position->components && c < 3; c++)
                v->position[c] = p[c];
            memcpy(v->color, current.color, sizeof v->color);
            if (color != NULL) {
                const float* c4 = StreamElement(color, index, 4);
                v->color[3] = 1.0f;
                for (unsigned c = 0; c < color->components && c < 4; c++)
                    v->color[c] = c4[c];
            }
            memcpy(v->texCoord, current.texCoord, sizeof v->texCoord);
            if (texCoord != NULL)
                memcpy(v->texCoord, StreamElement(texCoord, index, 2), sizeof v->texCoord);
        }
        ExpandAndRecord(primitive, gathered, count, OOImmediateLineWidth(), OOImmediatePointSize());
        free(gathered);
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
            normal ? StreamElement(normal, index, 3) : NULL,
            generic ? StreamElement(generic, index, 4) : NULL, generic ? generic->components : 0);
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
    sPassTarget = NULL;
    if (pass->target != kOORenderTargetCurrent && pass->target != OORendererWindowTarget()) {
        sPassTarget = TargetFor(pass->target);
        if (sPassTarget == NULL)
            OORendererBackendWarn("SDL_GPU backend: a pass into an unknown target; drawing into the window instead");
    }
    sPass = *pass;
    memcpy(sClearColor, clearColor, sizeof sClearColor);
    sClearDepth = clearDepth;
    sVertexCount = sUniformCount = sDrawCount = sBlockUsed = 0;
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

    SDL_GPUColorTargetInfo colors[kOOMaxColorAttachments];
    unsigned colorCount = sPassTarget ? sPassTarget->descriptor.colorAttachments : 1;
    for (unsigned i = 0; i < colorCount; i++) {
        colors[i] = (SDL_GPUColorTargetInfo) {
            .texture = sPassTarget ? sPassTarget->color[i] : sWindowColor,
            .clear_color = { sClearColor[0], sClearColor[1], sClearColor[2], sClearColor[3] },
            .load_op = LoadOp(sPass.colorLoad),
            .store_op = SDL_GPU_STOREOP_STORE,
        };
    }
    SDL_GPUTexture* depthTexture = sPassTarget ? sPassTarget->depth : sWindowDepth;
    SDL_GPUDepthStencilTargetInfo depth = {
        .texture = depthTexture,
        .clear_depth = sClearDepth,
        .load_op = LoadOp(sPass.depthLoad),
        .store_op = SDL_GPU_STOREOP_STORE,
        .stencil_load_op = SDL_GPU_LOADOP_DONT_CARE,
        .stencil_store_op = SDL_GPU_STOREOP_DONT_CARE,
    };
    SDL_GPURenderPass* pass = SDL_BeginGPURenderPass(commands, colors, colorCount, depthTexture ? &depth : NULL);
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
        SDL_Rect scissor = draw->scissor ? draw->scissorRect : (SDL_Rect) { 0, 0, (int)TargetWidth(), (int)TargetHeight() };
        SDL_SetGPUScissor(pass, &scissor);
        const OOGLSLLegacyStateBlock* uniforms = &sUniforms[draw->uniformIndex];
        SDL_PushGPUVertexUniformData(commands, kOOGLSLLegacyStateSlot, uniforms, sizeof *uniforms);
        SDL_PushGPUFragmentUniformData(commands, kOOGLSLLegacyStateSlot, uniforms, sizeof *uniforms);
        const OORendererProgram* program = draw->key.program;
        if (program == NULL) {
            SDL_GPUTextureSamplerBinding sampler = { .texture = texture->texture, .sampler = texture->sampler };
            SDL_BindGPUFragmentSamplers(pass, sTextureSamplerSlot, &sampler, 1);
        } else {
            for (int stage = 0; stage < kOOGLSLStageCount; stage++) {
                SDL_GPUTextureSamplerBinding samplers[kMaxSamplers];
                uint32_t count = program->samplerCount[stage];
                for (uint32_t slot = 0; slot < count; slot++) {
                    const TextureRecord* t = TextureFor(draw->samplerTextures[stage][slot]);
                    samplers[slot] = (SDL_GPUTextureSamplerBinding) { .texture = t->texture, .sampler = t->sampler };
                }
                const uint8_t* block = sBlockBytes + draw->blockOffset[stage];
                if (stage == kOOGLSLStageVertex) {
                    if (count > 0)
                        SDL_BindGPUVertexSamplers(pass, 0, samplers, count);
                    if (program->blockSize[stage] > 0)
                        SDL_PushGPUVertexUniformData(commands, kOOGLSLUniformsSlot, block, program->blockSize[stage]);
                } else {
                    if (count > 0)
                        SDL_BindGPUFragmentSamplers(pass, 0, samplers, count);
                    if (program->blockSize[stage] > 0)
                        SDL_PushGPUFragmentUniformData(commands, kOOGLSLUniformsSlot, block, program->blockSize[stage]);
                }
            }
        }
        SDL_DrawGPUPrimitives(pass, (Uint32)draw->vertexCount, 1, (Uint32)draw->firstVertex, 0);
    }
    SDL_EndGPURenderPass(pass);
    /*  No wait: command buffers run in submission order, SDL_GPU keeps
        released resources alive until the GPU is done with them, the vertex
        buffer upload cycles, and everything the CPU wrote has already been
        copied. Only readback waits.
    */
    SDL_SubmitGPUCommandBuffer(commands);
    if (transfer != NULL)
        SDL_ReleaseGPUTransferBuffer(sDevice, transfer);
    sVertexCount = sUniformCount = sDrawCount = sBlockUsed = 0;
    sPassTarget = NULL;
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
    SDL_Rect rect = TargetRect(flipped);
    SDL_GPUTextureRegion region = { .texture = sWindowColor, .x = (Uint32)rect.x, .y = (Uint32)rect.y, .w = (Uint32)width, .h = (Uint32)height, .d = 1 };
    SDL_GPUTextureTransferInfo destination = { .transfer_buffer = transfer };
    SDL_DownloadFromGPUTexture(copy, &region, &destination);
    SDL_EndGPUCopyPass(copy);
    WaitFor(commands);

    // Rendered in GL's orientation, the rows are already bottom-up. RGBA to BGRA.
    const uint8_t* source = SDL_MapGPUTransferBuffer(sDevice, transfer, false);
    uint8_t* out = pixels;
    for (int row = 0; row < height; row++) {
        const uint8_t* in = source + (size_t)row * width * 4;
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

void OORendererBackendNoteDrawOutsidePass(void)
{
    OORendererBackendWarn("SDL_GPU backend: a draw outside any pass is dropped");
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

#pragma mark - Programs

// OOProgramError's log is released with free(), so it can't come from SDL's allocator.
static char* CopyString(const char* string)
{
    size_t length = strlen(string);
    char* copy = malloc(length + 1);
    if (copy != NULL)
        memcpy(copy, string, length + 1);
    return copy;
}

static ProgramUniform* FindOrAddUniform(OORendererProgram* program, const char* name)
{
    for (size_t i = 0; i < program->uniformCount; i++) {
        if (strcmp(program->uniforms[i].name, name) == 0)
            return &program->uniforms[i];
    }
    program->uniforms = realloc(program->uniforms, (program->uniformCount + 1) * sizeof *program->uniforms);
    ProgramUniform* entry = &program->uniforms[program->uniformCount++];
    memset(entry, 0, sizeof *entry);
    entry->name = SDL_strdup(name);
    for (int stage = 0; stage < kOOGLSLStageCount; stage++)
        entry->samplerSlot[stage] = -1;
    return entry;
}

OORendererProgram* OORendererCreateProgram(const char* vertexSource, const char* fragmentSource, const char* prefix,
    const OOAttributeBinding* bindings, size_t bindingCount, OOProgramError* outError)
{
    if (outError != NULL)
        *outError = (OOProgramError) { kOOProgramStageLink, NULL };
    if (vertexSource == NULL && fragmentSource == NULL)
        return NULL;
    OORendererProgram* program = calloc(1, sizeof *program);
    program->genericLocation = -1;
    if (!OOGLSLTranslateProgram(vertexSource, fragmentSource, prefix, sFormats, &program->translated)) {
        /*  The translator compiles and links both stages together, so every
            failure is reported as a link failure; its log has the details.
        */
        if (outError != NULL)
            outError->log = CopyString(program->translated.log ? program->translated.log : "");
        OOGLSLProgramFree(&program->translated);
        free(program);
        return NULL;
    }
    const OOGLSLStageResult* vertex = &program->translated.stages[kOOGLSLStageVertex];
    program->shaders[kOOGLSLStageVertex] = CreateShader(vertex, SDL_GPU_SHADERSTAGE_VERTEX);
    program->shaders[kOOGLSLStageFragment] = CreateShader(&program->translated.stages[kOOGLSLStageFragment], SDL_GPU_SHADERSTAGE_FRAGMENT);

    // The first bound attribute the shader reads feeds GPUVertex.generic.
    const char* genericName = NULL;
    for (size_t b = 0; b < bindingCount && genericName == NULL; b++) {
        for (size_t i = 0; i < vertex->vertexInputCount; i++) {
            if (strcmp(vertex->vertexInputs[i].name, bindings[b].name) == 0) {
                genericName = bindings[b].name;
                program->genericLocation = (int)bindings[b].location;
                break;
            }
        }
    }
    program->attributeCount = BuildAttributes(vertex, genericName, program->attributes);

    for (int stage = 0; stage < kOOGLSLStageCount; stage++) {
        const OOGLSLStageResult* result = &program->translated.stages[stage];
        for (size_t i = 0; i < result->uniformCount; i++)
            FindOrAddUniform(program, result->uniforms[i].name)->uniform[stage] = &result->uniforms[i];
        for (size_t i = 0; i < result->samplerCount; i++) {
            const OOGLSLSampler* sampler = &result->samplers[i];
            if (sampler->slot >= kMaxSamplers)
                continue;
            FindOrAddUniform(program, sampler->name)->samplerSlot[stage] = (int)sampler->slot;
            program->samplerIsCube[stage][sampler->slot] = sampler->isCube;
            if (sampler->slot + 1 > program->samplerCount[stage])
                program->samplerCount[stage] = sampler->slot + 1;
        }
        program->blockSize[stage] = result->uniformBlockSize > 0 ? result->uniformBlockSize + 16 : 0;
        program->blocks[stage] = calloc(1, program->blockSize[stage] + 16);
    }
    if (program->shaders[kOOGLSLStageVertex] == NULL || program->shaders[kOOGLSLStageFragment] == NULL) {
        if (outError != NULL)
            outError->log = CopyString(SDL_GetError());
        OORendererReleaseProgram(program);
        return NULL;
    }
    return program;
}

void OORendererReleaseProgram(OORendererProgram* program)
{
    if (program == NULL)
        return;
    if (program == sCurrentProgram)
        OORendererUseProgram(NULL);
    // Pipelines built for it go too.
    for (size_t i = 0; i < sPipelineCount;) {
        if (sPipelines[i].key.program == program) {
            SDL_ReleaseGPUGraphicsPipeline(sDevice, sPipelines[i].pipeline);
            sPipelines[i] = sPipelines[--sPipelineCount];
        } else
            i++;
    }
    for (int stage = 0; stage < kOOGLSLStageCount; stage++) {
        if (program->shaders[stage] != NULL)
            SDL_ReleaseGPUShader(sDevice, program->shaders[stage]);
        free(program->blocks[stage]);
    }
    for (size_t i = 0; i < program->uniformCount; i++)
        SDL_free(program->uniforms[i].name);
    free(program->uniforms);
    OOGLSLProgramFree(&program->translated);
    free(program);
}

void OORendererUseProgram(OORendererProgram* program)
{
    sCurrentProgram = program;
    // The mirror holds a GL program name; any non-zero value says "a program".
    OORendererSetProgram(program != NULL ? (uint32_t)(uintptr_t)program : 0);
}

OORendererProgram* OORendererCurrentProgram(void)
{
    return sCurrentProgram;
}

uint32_t OORendererProgramGLName(const OORendererProgram* program)
{
    (void)program;
    return 0;
}

OOProgramUniform OORendererProgramUniform(OORendererProgram* program, const char* name)
{
    if (program == NULL)
        return -1;
    for (size_t i = 0; i < program->uniformCount; i++) {
        if (strcmp(program->uniforms[i].name, name) == 0)
            return (OOProgramUniform)i;
    }
    return -1;
}

static void WriteUniform(uint8_t* block, const OOGLSLUniform* u, OOUniformType type, const void* values)
{
    uint8_t* at = block + u->offset;
    const float* f = values;
    switch (type) {
    case kOOUniformInt: {
        int32_t value = *(const int32_t*)values;
        // As glUniform1i: ints and bools only.
        if (u->baseType == kOOGLSLTypeInt || u->baseType == kOOGLSLTypeUInt)
            memcpy(at, &value, 4);
        else if (u->baseType == kOOGLSLTypeBool) {
            uint32_t b = value != 0;
            memcpy(at, &b, 4);
        }
        return;
    }
    case kOOUniformFloat:
        if (u->baseType == kOOGLSLTypeFloat && u->columns == 1)
            memcpy(at, f, 4);
        else if (u->baseType == kOOGLSLTypeBool) {
            uint32_t b = *f != 0.0f;
            memcpy(at, &b, 4);
        }
        return;
    case kOOUniformVec2:
    case kOOUniformVec4: {
        uint32_t n = type == kOOUniformVec2 ? 2 : 4;
        if (u->baseType == kOOGLSLTypeFloat && u->columns == 1 && u->vectorSize == n)
            memcpy(at, f, n * 4);
        return;
    }
    case kOOUniformMat3:
    case kOOUniformMat4: {
        uint32_t n = type == kOOUniformMat3 ? 3 : 4;
        if (u->baseType != kOOGLSLTypeFloat || u->columns != n || u->vectorSize != n)
            return;
        for (uint32_t c = 0; c < n; c++)
            memcpy(at + c * u->matrixStride, f + c * n, n * 4);
        return;
    }
    }
}

void OORendererSetUniform(OOProgramUniform uniform, OOUniformType type, const void* values)
{
    OORendererProgram* program = sCurrentProgram;
    if (program == NULL || uniform < 0 || (size_t)uniform >= program->uniformCount || strcmp(sFault, "uniform") == 0)
        return;
    const ProgramUniform* entry = &program->uniforms[uniform];
    for (int stage = 0; stage < kOOGLSLStageCount; stage++) {
        if (entry->samplerSlot[stage] >= 0 && type == kOOUniformInt)
            program->samplerUnits[stage][entry->samplerSlot[stage]] = *(const int32_t*)values;
        if (entry->uniform[stage] != NULL)
            WriteUniform(program->blocks[stage], entry->uniform[stage], type, values);
    }
}
