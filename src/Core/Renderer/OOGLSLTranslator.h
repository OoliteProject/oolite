/*

OOGLSLTranslator.h

Translates Oolite/OXP legacy GLSL (GLSL 1.10/1.20 written against the OpenGL
compatibility profile) into shaders that SDL_GPU can consume: SPIR-V for
Vulkan and MSL for Metal.

The translation keeps OXP shaders source compatible:
- Legacy built-in state (gl_ModelViewMatrix, gl_LightSource[], gl_FrontMaterial,
  gl_Fog ...) is redirected to members of a std140 uniform block,
  OOLegacyState, that the renderer fills from its own state. Its layout is
  OOLegacyStateBlock below.
- Legacy vertex attributes (gl_Vertex, gl_Normal, gl_MultiTexCoord0 ...),
  varyings (gl_TexCoord[], gl_FrontColor ...) and gl_FragColor/gl_FragData
  become ordinary inputs and outputs.
- Loose "uniform" declarations are gathered into one uniform block per stage,
  OOUniforms. Each member's offset is reported so uniforms can still be set
  by name.
- Legacy texture functions (texture2D, textureCube ...) are mapped to their
  modern equivalents.
- A vertex or fragment shader that is missing is replaced by an emulation of
  the fixed-function stage, as OpenGL does.
- Clip-space depth is remapped from GL's [-w, w] to [0, w].

Resource layout follows SDL_GPU's conventions:
- uniform slot 0 = OOLegacyState, slot 1 = OOUniforms;
- sampler slots are numbered in order of declaration binding.


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

#ifndef OOGLSLTRANSLATOR_H
#define OOGLSLTRANSLATOR_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

enum {
    kOOGLSLMaxLights = 8,
    kOOGLSLMaxTextureCoords = 8,
    kOOGLSLLegacyStateSlot = 0,
    kOOGLSLUniformsSlot = 1,
};

// Layout of the OOLegacyState uniform block (std140). The renderer fills
// this from its matrix and light state; it must match kLegacyStateBlock in
// OOGLSLTranslator.c.
typedef struct {
    float ambient[4], diffuse[4], specular[4], position[4], halfVector[4];
    float spotDirection[3], spotExponent;
    float spotCutoff, spotCosCutoff, constantAttenuation, linearAttenuation;
    float quadraticAttenuation, pad[3];
} OOGLSLLightSource;

typedef struct {
    float emission[4], ambient[4], diffuse[4], specular[4];
    float shininess, pad[3];
} OOGLSLMaterial;

typedef struct {
    float ambient[4], diffuse[4], specular[4];
} OOGLSLLightProduct;

typedef struct {
    float modelViewMatrix[16];
    float projectionMatrix[16];
    float modelViewProjectionMatrix[16];
    float modelViewMatrixInverse[16];
    float projectionMatrixInverse[16];
    float modelViewProjectionMatrixInverse[16];
    float modelViewMatrixTranspose[16];
    float modelViewMatrixInverseTranspose[16];
    float normalMatrix[12]; // mat3: three std140 columns of vec4
    float textureMatrix[kOOGLSLMaxTextureCoords][16];
    OOGLSLLightSource lightSource[kOOGLSLMaxLights];
    float lightModelAmbient[4];
    OOGLSLMaterial frontMaterial;
    float frontLightModelProductSceneColor[4];
    OOGLSLLightProduct frontLightProduct[kOOGLSLMaxLights];
    float fogColor[4];
    float fogDensity, fogStart, fogEnd, fogScale;
    float viewportHeight, pointSize;
    // Used by the fixed-function emulation.
    float lightingEnabled;
    float fogEnabled;
    float separateSpecular; // GL_SEPARATE_SPECULAR_COLOR: specular added after texturing
    float fogMode; // 0 linear, 1 exp, 2 exp2
    /*  Texture units 0 and 1: the environment mode, as kOOGLSLTexEnv*, and
        whether the unit is enabled.
    */
    float textureMode[2];
    float textureEnabled[2];
    // An alpha-only texture leaves the colour alone under modulate, replace and add, as in GL.
    float textureAlphaOnly[2];
    // GL_CLAMP_VERTEX_COLOR: off once the game draws into float targets.
    float clampColor;
    float pad[3];
} OOGLSLLegacyStateBlock;

enum {
    kOOGLSLTexEnvModulate,
    kOOGLSLTexEnvReplace,
    kOOGLSLTexEnvAdd,
    kOOGLSLTexEnvCombineModulate, // GL_COMBINE with the default sources: texture, previous
    kOOGLSLTexEnvCombineAdd,
    kOOGLSLTexEnvCombineReplace,
};

typedef enum {
    kOOGLSLStageVertex,
    kOOGLSLStageFragment,
    kOOGLSLStageCount
} OOGLSLStage;

typedef enum {
    kOOGLSLTypeOther,
    kOOGLSLTypeFloat,
    kOOGLSLTypeInt,
    kOOGLSLTypeUInt,
    kOOGLSLTypeBool,
} OOGLSLBaseType;

typedef struct {
    char* name;
    uint32_t offset;
    uint32_t size; // Total size in bytes, including any array elements.
    OOGLSLBaseType baseType;
    uint32_t vectorSize; // 1-4
    uint32_t columns; // 1 for non-matrices
    uint32_t arraySize; // 0 for non-arrays
    uint32_t arrayStride;
    uint32_t matrixStride;
} OOGLSLUniform;

typedef struct {
    char* name;
    uint32_t slot;
    bool isCube;
    bool isShadow;
} OOGLSLSampler;

typedef struct {
    char* name;
    uint32_t location;
    uint32_t vectorSize;
} OOGLSLVertexInput;

typedef struct {
    // SPIR-V for SDL_GPU_SHADERFORMAT_SPIRV.
    uint32_t* spirv;
    size_t spirvWordCount;
    // MSL source for SDL_GPU_SHADERFORMAT_MSL, entry point "main0".
    char* msl;
    // Reflection.
    bool usesLegacyState;
    uint32_t uniformBlockSize; // 0 if the stage has no loose uniforms.
    OOGLSLUniform* uniforms;
    size_t uniformCount;
    OOGLSLSampler* samplers;
    size_t samplerCount;
    // Only for the vertex stage.
    OOGLSLVertexInput* vertexInputs;
    size_t vertexInputCount;
} OOGLSLStageResult;

typedef struct {
    OOGLSLStageResult stages[kOOGLSLStageCount];
    // Compile/link log; on failure explains why. May be non-empty on success
    // (warnings). Line numbers refer to the original source of each stage.
    char* log;
} OOGLSLProgram;

typedef enum {
    kOOGLSLOutputSPIRV = 1 << 0,
    kOOGLSLOutputMSL = 1 << 1,
    /*  Render upside down (negated clip-space y, so the caller inverts the
        front face): every target then holds GL's bottom-up rows, matching
        uploaded textures, and gl_FragCoord needs no flipping. Without it,
        output has SDL_GPU's top-left orientation.
    */
    kOOGLSLOutputGLOrientation = 1 << 2,
} OOGLSLOutputFormats;

bool OOGLSLTranslatorInit(void);
void OOGLSLTranslatorShutdown(void);

/*  Translate a program. vertexSource or fragmentSource may be NULL, in which
    case a fixed-function emulation is used for that stage. prefix (may be
    NULL) is prepended to both stages, as OOShaderProgram does with macro
    definitions.
    Returns false on failure; outProgram->log then explains why. Always call
    OOGLSLProgramFree on outProgram.
*/
bool OOGLSLTranslateProgram(const char* vertexSource, const char* fragmentSource,
    const char* prefix, OOGLSLOutputFormats formats, OOGLSLProgram* outProgram);

void OOGLSLProgramFree(OOGLSLProgram* program);

const OOGLSLUniform* OOGLSLFindUniform(const OOGLSLStageResult* stage, const char* name);

#ifdef __cplusplus
}
#endif

#endif
