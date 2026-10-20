/*

OOGPUSpikeCommon.h

Helpers shared by the SDL_GPU phase 0 spike tools: turning a translated
OOGLSLProgram into SDL_GPU shaders and a graphics pipeline.


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

#ifndef OOGPUSPIKECOMMON_H
#define OOGPUSPIKECOMMON_H

#include "OOGLSLTranslator.h"
#include <SDL3/SDL.h>

// Vertex streams the spike meshes provide. Every vertex input a shader
// declares is fed from one of these; unknown inputs read zeros.
typedef enum {
    kOOVertexStreamPosition, // float3
    kOOVertexStreamNormal, // float3
    kOOVertexStreamTexCoord, // float2
    kOOVertexStreamTangent, // float3
    kOOVertexStreamColor, // float4
    kOOVertexStreamZero, // float4, all zero
    kOOVertexStreamCount
} OOVertexStream;

OOVertexStream OOVertexStreamForInput(const char* name);
uint32_t OOVertexStreamComponents(OOVertexStream stream);

typedef struct {
    SDL_GPUShader* vertexShader;
    SDL_GPUShader* fragmentShader;
    SDL_GPUGraphicsPipeline* pipeline;
    // Vertex buffer slot i is fed from stream streamForSlot[i].
    OOVertexStream streamForSlot[16];
    uint32_t slotCount;
} OOGPUProgram;

// Translation formats the device can consume.
OOGLSLOutputFormats OOGPUFormatsForDevice(SDL_GPUDevice* device);

// Returns false and sets SDL_GetError() on failure.
bool OOGPUProgramCreate(SDL_GPUDevice* device, const OOGLSLProgram* program,
    SDL_GPUTextureFormat colorFormat, SDL_GPUTextureFormat depthFormat, OOGPUProgram* outProgram);
void OOGPUProgramRelease(SDL_GPUDevice* device, OOGPUProgram* program);

char* OOReadTextFile(const char* path);

#endif
