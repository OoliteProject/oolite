/*

OOGPUSpikeCommon.c


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

#include "OOGPUSpikeCommon.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

OOVertexStream OOVertexStreamForInput(const char* name)
{
    if (strcmp(name, "oo_Vertex") == 0)
        return kOOVertexStreamPosition;
    if (strcmp(name, "oo_Normal") == 0)
        return kOOVertexStreamNormal;
    if (strcmp(name, "oo_MultiTexCoord0") == 0)
        return kOOVertexStreamTexCoord;
    if (strcmp(name, "tangent") == 0)
        return kOOVertexStreamTangent;
    if (strcmp(name, "oo_Color") == 0)
        return kOOVertexStreamColor;
    return kOOVertexStreamZero;
}

uint32_t OOVertexStreamComponents(OOVertexStream stream)
{
    switch (stream) {
    case kOOVertexStreamTexCoord:
        return 2;
    case kOOVertexStreamColor:
    case kOOVertexStreamZero:
        return 4;
    default:
        return 3;
    }
}

static const SDL_GPUVertexElementFormat kFormats[5] = {
    SDL_GPU_VERTEXELEMENTFORMAT_INVALID,
    SDL_GPU_VERTEXELEMENTFORMAT_FLOAT,
    SDL_GPU_VERTEXELEMENTFORMAT_FLOAT2,
    SDL_GPU_VERTEXELEMENTFORMAT_FLOAT3,
    SDL_GPU_VERTEXELEMENTFORMAT_FLOAT4,
};

OOGLSLOutputFormats OOGPUFormatsForDevice(SDL_GPUDevice* device)
{
    SDL_GPUShaderFormat formats = SDL_GetGPUShaderFormats(device);
    if (formats & SDL_GPU_SHADERFORMAT_MSL)
        return kOOGLSLOutputMSL;
    return kOOGLSLOutputSPIRV;
}

static SDL_GPUShader* CreateShader(SDL_GPUDevice* device, const OOGLSLStageResult* stage, SDL_GPUShaderStage gpuStage)
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
    return SDL_CreateGPUShader(device, &info);
}

bool OOGPUProgramCreate(SDL_GPUDevice* device, const OOGLSLProgram* program,
    SDL_GPUTextureFormat colorFormat, SDL_GPUTextureFormat depthFormat, OOGPUProgram* outProgram)
{
    memset(outProgram, 0, sizeof *outProgram);
    const OOGLSLStageResult* vertex = &program->stages[kOOGLSLStageVertex];

    outProgram->vertexShader = CreateShader(device, vertex, SDL_GPU_SHADERSTAGE_VERTEX);
    if (outProgram->vertexShader == NULL)
        return false;
    outProgram->fragmentShader = CreateShader(device, &program->stages[kOOGLSLStageFragment], SDL_GPU_SHADERSTAGE_FRAGMENT);
    if (outProgram->fragmentShader == NULL) {
        OOGPUProgramRelease(device, outProgram);
        return false;
    }

    // One buffer slot per input keeps the spike simple; the real renderer
    // will interleave.
    SDL_GPUVertexBufferDescription buffers[16];
    SDL_GPUVertexAttribute attributes[16];
    uint32_t count = 0;
    for (size_t i = 0; i < vertex->vertexInputCount && count < 16; i++) {
        OOVertexStream stream = OOVertexStreamForInput(vertex->vertexInputs[i].name);
        uint32_t components = OOVertexStreamComponents(stream);
        buffers[count] = (SDL_GPUVertexBufferDescription) {
            .slot = count,
            .pitch = components * sizeof(float),
            .input_rate = SDL_GPU_VERTEXINPUTRATE_VERTEX,
        };
        attributes[count] = (SDL_GPUVertexAttribute) {
            .location = vertex->vertexInputs[i].location,
            .buffer_slot = count,
            .format = kFormats[components],
        };
        outProgram->streamForSlot[count] = stream;
        count++;
    }
    outProgram->slotCount = count;

    SDL_GPUColorTargetDescription colorTarget = {
        .format = colorFormat,
        .blend_state = {
            .enable_blend = true,
            .src_color_blendfactor = SDL_GPU_BLENDFACTOR_SRC_ALPHA,
            .dst_color_blendfactor = SDL_GPU_BLENDFACTOR_ONE_MINUS_SRC_ALPHA,
            .color_blend_op = SDL_GPU_BLENDOP_ADD,
            .src_alpha_blendfactor = SDL_GPU_BLENDFACTOR_ONE,
            .dst_alpha_blendfactor = SDL_GPU_BLENDFACTOR_ONE_MINUS_SRC_ALPHA,
            .alpha_blend_op = SDL_GPU_BLENDOP_ADD,
        },
    };
    SDL_GPUGraphicsPipelineCreateInfo info = {
        .vertex_shader = outProgram->vertexShader,
        .fragment_shader = outProgram->fragmentShader,
        .vertex_input_state = {
            .vertex_buffer_descriptions = buffers,
            .num_vertex_buffers = count,
            .vertex_attributes = attributes,
            .num_vertex_attributes = count,
        },
        .primitive_type = SDL_GPU_PRIMITIVETYPE_TRIANGLELIST,
        .rasterizer_state = {
            .fill_mode = SDL_GPU_FILLMODE_FILL,
            .cull_mode = SDL_GPU_CULLMODE_BACK,
            // GL's default; matrices stay in GL convention.
            .front_face = SDL_GPU_FRONTFACE_COUNTER_CLOCKWISE,
        },
        .depth_stencil_state = {
            .compare_op = SDL_GPU_COMPAREOP_LESS_OR_EQUAL,
            .enable_depth_test = depthFormat != SDL_GPU_TEXTUREFORMAT_INVALID,
            .enable_depth_write = depthFormat != SDL_GPU_TEXTUREFORMAT_INVALID,
        },
        .target_info = {
            .color_target_descriptions = &colorTarget,
            .num_color_targets = 1,
            .depth_stencil_format = depthFormat,
            .has_depth_stencil_target = depthFormat != SDL_GPU_TEXTUREFORMAT_INVALID,
        },
    };
    outProgram->pipeline = SDL_CreateGPUGraphicsPipeline(device, &info);
    if (outProgram->pipeline == NULL) {
        OOGPUProgramRelease(device, outProgram);
        return false;
    }
    return true;
}

void OOGPUProgramRelease(SDL_GPUDevice* device, OOGPUProgram* program)
{
    if (program->pipeline != NULL)
        SDL_ReleaseGPUGraphicsPipeline(device, program->pipeline);
    if (program->vertexShader != NULL)
        SDL_ReleaseGPUShader(device, program->vertexShader);
    if (program->fragmentShader != NULL)
        SDL_ReleaseGPUShader(device, program->fragmentShader);
    memset(program, 0, sizeof *program);
}

char* OOReadTextFile(const char* path)
{
    size_t size = 0;
    void* data = SDL_LoadFile(path, &size);
    if (data == NULL)
        return NULL;
    char* result = malloc(size + 1);
    memcpy(result, data, size);
    result[size] = '\0';
    SDL_free(data);
    return result;
}
