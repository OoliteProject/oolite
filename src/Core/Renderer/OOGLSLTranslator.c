/*

OOGLSLTranslator.c


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

#include "OOGLSLTranslator.h"

#include <ctype.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <glslang/Include/glslang_c_interface.h>
#include <glslang/Public/resource_limits_c.h>
#include <spirv_cross/spirv_cross_c.h>

// SDL_GPU descriptor sets for SPIR-V graphics shaders.
enum {
    kVertexSamplerSet = 0,
    kVertexUniformSet = 1,
    kFragmentSamplerSet = 2,
    kFragmentUniformSet = 3,
};

enum {
    kSpvOpName = 5,
    kSpvOpVariable = 59,
    kSpvOpDecorate = 71,
    kSpvDecorationLocation = 30,
    kSpvDecorationBinding = 33,
    kSpvDecorationDescriptorSet = 34,
};

#pragma mark - Strings

typedef struct {
    char* s;
    size_t len, cap;
} Str;

static void StrAppendN(Str* str, const char* s, size_t n)
{
    if (str->len + n + 1 > str->cap) {
        size_t cap = str->cap ? str->cap : 256;
        while (str->len + n + 1 > cap)
            cap *= 2;
        str->s = realloc(str->s, cap);
        str->cap = cap;
    }
    memcpy(str->s + str->len, s, n);
    str->len += n;
    str->s[str->len] = '\0';
}

static void StrAppend(Str* str, const char* s)
{
    StrAppendN(str, s, strlen(s));
}

static void StrAppendf(Str* str, const char* format, ...)
{
    char buffer[1024];
    va_list args;
    va_start(args, format);
    int n = vsnprintf(buffer, sizeof buffer, format, args);
    va_end(args);
    if (n >= (int)sizeof buffer) {
        char* big = malloc((size_t)n + 1);
        va_start(args, format);
        vsnprintf(big, (size_t)n + 1, format, args);
        va_end(args);
        StrAppend(str, big);
        free(big);
    } else if (n > 0) {
        StrAppendN(str, buffer, (size_t)n);
    }
}

static char* StrDup(const char* s)
{
    if (s == NULL)
        return NULL;
    size_t n = strlen(s) + 1;
    return memcpy(malloc(n), s, n);
}

static bool IsIdentChar(char c)
{
    return isalnum((unsigned char)c) || c == '_';
}

// True if the identifier tok appears in src as a whole word.
static bool UsesToken(const char* src, const char* tok)
{
    size_t n = strlen(tok);
    for (const char* p = strstr(src, tok); p != NULL; p = strstr(p + 1, tok)) {
        if ((p == src || !IsIdentChar(p[-1])) && !IsIdentChar(p[n]))
            return true;
    }
    return false;
}

/*  GLSL 1.20 lets a uniform have an initializer, as the post chain's blur
    weights do; a uniform block member can't. Oolite never sets those, so
    an initialised uniform becomes a constant ("uniform" turns into
    "const  ", the same length, so error positions still match).
*/
static char* ConstifyInitialisedUniforms(const char* src)
{
    char* copy = StrDup(src);
    for (char* p = strstr(copy, "uniform"); p != NULL; p = strstr(p + 1, "uniform")) {
        if ((p > copy && IsIdentChar(p[-1])) || IsIdentChar(p[7]))
            continue;
        char* end = strchr(p, ';');
        char* equals = strchr(p, '=');
        if (end != NULL && equals != NULL && equals < end)
            memcpy(p, "const  ", 7);
    }
    return copy;
}

// Copy source, blanking out #version lines (they are replaced by our own)
// while keeping line numbers intact.
static void AppendUserSource(Str* out, const char* originalSrc)
{
    char* constified = ConstifyInitialisedUniforms(originalSrc);
    const char* src = constified;
    const char* line = src;
    while (*line != '\0') {
        const char* end = strchr(line, '\n');
        size_t n = end ? (size_t)(end - line + 1) : strlen(line);
        const char* p = line;
        while (*p == ' ' || *p == '\t')
            p++;
        if (*p == '#') {
            p++;
            while (*p == ' ' || *p == '\t')
                p++;
        }
        if (p != line && strncmp(p, "version", 7) == 0 && !IsIdentChar(p[7]))
            StrAppend(out, end ? "\n" : "");
        else
            StrAppendN(out, line, n);
        line += n;
    }
    if (out->len > 0 && out->s[out->len - 1] != '\n')
        StrAppend(out, "\n");
    free(constified);
}

#pragma mark - Prelude

static const char* const kCommonPrelude = "#version 410\n"
                                          // Line continuations and scalar swizzles, which GL drivers
                                          // accepted in older GLSL versions.
                                          "#extension GL_ARB_shading_language_420pack : enable\n"
                                          // C-style casts, accepted by NVIDIA's GL compiler.
                                          "#extension GL_NV_explicit_typecast : enable\n"
                                          "#define OO_SDL_GPU 1\n"
                                          "struct oo_LightSourceParameters {\n"
                                          "    vec4 ambient; vec4 diffuse; vec4 specular; vec4 position; vec4 halfVector;\n"
                                          "    vec3 spotDirection; float spotExponent; float spotCutoff; float spotCosCutoff;\n"
                                          "    float constantAttenuation; float linearAttenuation; float quadraticAttenuation;\n"
                                          "};\n"
                                          "struct oo_MaterialParameters { vec4 emission; vec4 ambient; vec4 diffuse; vec4 specular; float shininess; };\n"
                                          "struct oo_LightModelParameters { vec4 ambient; };\n"
                                          "struct oo_LightModelProducts { vec4 sceneColor; };\n"
                                          "struct oo_LightProducts { vec4 ambient; vec4 diffuse; vec4 specular; };\n"
                                          "struct oo_FogParameters { vec4 color; float density; float start; float end; float scale; };\n"
                                          "layout(std140) uniform OOLegacyState {\n"
                                          "    mat4 oo_ModelViewMatrix;\n"
                                          "    mat4 oo_ProjectionMatrix;\n"
                                          "    mat4 oo_ModelViewProjectionMatrix;\n"
                                          "    mat4 oo_ModelViewMatrixInverse;\n"
                                          "    mat4 oo_ProjectionMatrixInverse;\n"
                                          "    mat4 oo_ModelViewProjectionMatrixInverse;\n"
                                          "    mat4 oo_ModelViewMatrixTranspose;\n"
                                          "    mat4 oo_ModelViewMatrixInverseTranspose;\n"
                                          "    mat3 oo_NormalMatrix;\n"
                                          "    mat4 oo_TextureMatrix[8];\n"
                                          "    oo_LightSourceParameters oo_LightSource[8];\n"
                                          "    oo_LightModelParameters oo_LightModel;\n"
                                          "    oo_MaterialParameters oo_FrontMaterial;\n"
                                          "    oo_LightModelProducts oo_FrontLightModelProduct;\n"
                                          "    oo_LightProducts oo_FrontLightProduct[8];\n"
                                          "    oo_FogParameters oo_Fog;\n"
                                          "    float oo_ViewportHeight;\n"
                                          "    float oo_PointSize;\n"
                                          "    float oo_LightingEnabled;\n"
                                          "    float oo_FogEnabled;\n"
                                          "    float oo_SeparateSpecular;\n"
                                          "    float oo_FogMode;\n"
                                          "    vec2 oo_TextureMode;\n"
                                          "    vec2 oo_TextureEnabled;\n"
                                          "    vec2 oo_TextureAlphaOnly;\n"
                                          "    float oo_ClampColor;\n"
                                          "};\n"
                                          "#define gl_ModelViewMatrix oo_ModelViewMatrix\n"
                                          "#define gl_ProjectionMatrix oo_ProjectionMatrix\n"
                                          "#define gl_ModelViewProjectionMatrix oo_ModelViewProjectionMatrix\n"
                                          "#define gl_ModelViewMatrixInverse oo_ModelViewMatrixInverse\n"
                                          "#define gl_ProjectionMatrixInverse oo_ProjectionMatrixInverse\n"
                                          "#define gl_ModelViewProjectionMatrixInverse oo_ModelViewProjectionMatrixInverse\n"
                                          "#define gl_ModelViewMatrixTranspose oo_ModelViewMatrixTranspose\n"
                                          "#define gl_ModelViewMatrixInverseTranspose oo_ModelViewMatrixInverseTranspose\n"
                                          "#define gl_ProjectionMatrixTranspose transpose(oo_ProjectionMatrix)\n"
                                          "#define gl_ProjectionMatrixInverseTranspose transpose(oo_ProjectionMatrixInverse)\n"
                                          "#define gl_ModelViewProjectionMatrixTranspose transpose(oo_ModelViewProjectionMatrix)\n"
                                          "#define gl_ModelViewProjectionMatrixInverseTranspose transpose(oo_ModelViewProjectionMatrixInverse)\n"
                                          "#define gl_NormalMatrix oo_NormalMatrix\n"
                                          "#define gl_TextureMatrix oo_TextureMatrix\n"
                                          "#define gl_LightSource oo_LightSource\n"
                                          "#define gl_LightSourceParameters oo_LightSourceParameters\n"
                                          "#define gl_LightModel oo_LightModel\n"
                                          "#define gl_LightModelParameters oo_LightModelParameters\n"
                                          "#define gl_FrontMaterial oo_FrontMaterial\n"
                                          "#define gl_BackMaterial oo_FrontMaterial\n"
                                          "#define gl_MaterialParameters oo_MaterialParameters\n"
                                          "#define gl_FrontLightModelProduct oo_FrontLightModelProduct\n"
                                          "#define gl_BackLightModelProduct oo_FrontLightModelProduct\n"
                                          "#define gl_FrontLightProduct oo_FrontLightProduct\n"
                                          "#define gl_BackLightProduct oo_FrontLightProduct\n"
                                          "#define gl_Fog oo_Fog\n"
                                          // SDL_GPU always uses the full depth range.
                                          "struct oo_DepthRangeParameters { float near; float far; float diff; };\n"
                                          "const oo_DepthRangeParameters oo_DepthRange = oo_DepthRangeParameters(0.0, 1.0, 1.0);\n"
                                          "#define gl_DepthRange oo_DepthRange\n"
                                          "const int oo_MaxLights = 8;\n"
                                          "const int oo_MaxTextureCoords = 8;\n"
                                          "const int oo_MaxTextureUnits = 8;\n"
                                          "#define gl_MaxLights oo_MaxLights\n"
                                          "#define gl_MaxTextureCoords oo_MaxTextureCoords\n"
                                          "#define gl_MaxTextureUnits oo_MaxTextureUnits\n"
                                          // Legacy texture functions. These are wrappers rather than plain
                                          // macros so that a user variable named "texture" still works.
                                          "vec4 oo_texture2D(sampler2D s, vec2 c) { return texture(s, c); }\n"
                                          "vec4 oo_texture2DProj(sampler2D s, vec3 c) { return textureProj(s, c); }\n"
                                          "vec4 oo_texture2DProj(sampler2D s, vec4 c) { return textureProj(s, c); }\n"
                                          "vec4 oo_texture2DLod(sampler2D s, vec2 c, float l) { return textureLod(s, c, l); }\n"
                                          "vec4 oo_texture2DProjLod(sampler2D s, vec3 c, float l) { return textureProjLod(s, c, l); }\n"
                                          "vec4 oo_texture2DProjLod(sampler2D s, vec4 c, float l) { return textureProjLod(s, c, l); }\n"
                                          "vec4 oo_texture2DGrad(sampler2D s, vec2 c, vec2 dx, vec2 dy) { return textureGrad(s, c, dx, dy); }\n"
                                          "vec4 oo_texture3D(sampler3D s, vec3 c) { return texture(s, c); }\n"
                                          "vec4 oo_texture3DLod(sampler3D s, vec3 c, float l) { return textureLod(s, c, l); }\n"
                                          "vec4 oo_textureCube(samplerCube s, vec3 c) { return texture(s, c); }\n"
                                          "vec4 oo_textureCubeLod(samplerCube s, vec3 c, float l) { return textureLod(s, c, l); }\n"
                                          "vec4 oo_textureCubeGrad(samplerCube s, vec3 c, vec3 dx, vec3 dy) { return textureGrad(s, c, dx, dy); }\n"
                                          "vec4 oo_shadow2D(sampler2DShadow s, vec3 c) { return vec4(texture(s, c)); }\n"
                                          "vec4 oo_shadow2DProj(sampler2DShadow s, vec4 c) { return vec4(textureProj(s, c)); }\n"
                                          "vec4 oo_shadow2DLod(sampler2DShadow s, vec3 c, float l) { return vec4(textureLod(s, c, l)); }\n"
                                          "#define texture2D oo_texture2D\n"
                                          // GL_EXT_gpu_shader4, which the game's GLSL 3.30 rewrite uses.
                                          "#define textureSize2D textureSize\n"
                                          "#define texture2DProj oo_texture2DProj\n"
                                          "#define texture2DLod oo_texture2DLod\n"
                                          "#define texture2DLodEXT oo_texture2DLod\n"
                                          "#define texture2DLodARB oo_texture2DLod\n"
                                          "#define texture2DProjLod oo_texture2DProjLod\n"
                                          "#define texture2DProjLodEXT oo_texture2DProjLod\n"
                                          "#define texture2DGrad oo_texture2DGrad\n"
                                          "#define texture2DGradEXT oo_texture2DGrad\n"
                                          "#define texture2DGradARB oo_texture2DGrad\n"
                                          "#define texture3D oo_texture3D\n"
                                          "#define texture3DLod oo_texture3DLod\n"
                                          "#define textureCube oo_textureCube\n"
                                          "#define textureCubeLod oo_textureCubeLod\n"
                                          "#define textureCubeLodEXT oo_textureCubeLod\n"
                                          "#define textureCubeGrad oo_textureCubeGrad\n"
                                          "#define textureCubeGradEXT oo_textureCubeGrad\n"
                                          "#define shadow2D oo_shadow2D\n"
                                          "#define shadow2DProj oo_shadow2DProj\n"
                                          "#define shadow2DLod oo_shadow2DLod\n";

// Bias overloads are only legal in fragment shaders.
static const char* const kFragmentTexturePrelude = "vec4 oo_texture2D(sampler2D s, vec2 c, float b) { return texture(s, c, b); }\n"
                                                   "vec4 oo_texture2DProj(sampler2D s, vec3 c, float b) { return textureProj(s, c, b); }\n"
                                                   "vec4 oo_texture2DProj(sampler2D s, vec4 c, float b) { return textureProj(s, c, b); }\n"
                                                   "vec4 oo_texture3D(sampler3D s, vec3 c, float b) { return texture(s, c, b); }\n"
                                                   "vec4 oo_textureCube(samplerCube s, vec3 c, float b) { return texture(s, c, b); }\n"
                                                   "vec4 oo_shadow2D(sampler2DShadow s, vec3 c, float b) { return vec4(texture(s, c, b)); }\n";

typedef struct {
    const char* legacyName;
    const char* declaration;
} BuiltinMapping;

static const BuiltinMapping kVertexInputs[] = {
    { "gl_Vertex", "in vec4 oo_Vertex;\n#define gl_Vertex oo_Vertex\n" },
    { "gl_Normal", "in vec3 oo_Normal;\n#define gl_Normal oo_Normal\n" },
    { "gl_Color", "in vec4 oo_Color;\n#define gl_Color oo_Color\n" },
    { "gl_SecondaryColor", "in vec4 oo_SecondaryColor;\n#define gl_SecondaryColor oo_SecondaryColor\n" },
    { "gl_FogCoord", "in float oo_FogCoord;\n#define gl_FogCoord oo_FogCoord\n" },
    { "gl_MultiTexCoord0", "in vec4 oo_MultiTexCoord0;\n#define gl_MultiTexCoord0 oo_MultiTexCoord0\n" },
    { "gl_MultiTexCoord1", "in vec4 oo_MultiTexCoord1;\n#define gl_MultiTexCoord1 oo_MultiTexCoord1\n" },
    { "gl_MultiTexCoord2", "in vec4 oo_MultiTexCoord2;\n#define gl_MultiTexCoord2 oo_MultiTexCoord2\n" },
    { "gl_MultiTexCoord3", "in vec4 oo_MultiTexCoord3;\n#define gl_MultiTexCoord3 oo_MultiTexCoord3\n" },
    { "gl_MultiTexCoord4", "in vec4 oo_MultiTexCoord4;\n#define gl_MultiTexCoord4 oo_MultiTexCoord4\n" },
    { "gl_MultiTexCoord5", "in vec4 oo_MultiTexCoord5;\n#define gl_MultiTexCoord5 oo_MultiTexCoord5\n" },
    { "gl_MultiTexCoord6", "in vec4 oo_MultiTexCoord6;\n#define gl_MultiTexCoord6 oo_MultiTexCoord6\n" },
    { "gl_MultiTexCoord7", "in vec4 oo_MultiTexCoord7;\n#define gl_MultiTexCoord7 oo_MultiTexCoord7\n" },
    { "gl_FrontColor", "out vec4 oo_FrontColor;\n#define gl_FrontColor oo_FrontColor\n" },
    { "gl_BackColor", "vec4 oo_BackColor;\n#define gl_BackColor oo_BackColor\n" },
    { "gl_FrontSecondaryColor", "out vec4 oo_FrontSecondaryColor;\n#define gl_FrontSecondaryColor oo_FrontSecondaryColor\n" },
    { "gl_BackSecondaryColor", "vec4 oo_BackSecondaryColor;\n#define gl_BackSecondaryColor oo_BackSecondaryColor\n" },
    { "gl_TexCoord", "out vec4 oo_TexCoord[8];\n#define gl_TexCoord oo_TexCoord\n" },
    { "gl_FogFragCoord", "out float oo_FogFragCoord;\n#define gl_FogFragCoord oo_FogFragCoord\n" },
    { "gl_ClipVertex", "vec4 oo_ClipVertex;\n#define gl_ClipVertex oo_ClipVertex\n" },
};

static const BuiltinMapping kFragmentInputs[] = {
    { "gl_Color", "in vec4 oo_FrontColor;\n#define gl_Color oo_FrontColor\n" },
    { "gl_SecondaryColor", "in vec4 oo_FrontSecondaryColor;\n#define gl_SecondaryColor oo_FrontSecondaryColor\n" },
    { "gl_TexCoord", "in vec4 oo_TexCoord[8];\n#define gl_TexCoord oo_TexCoord\n" },
    { "gl_FogFragCoord", "in float oo_FogFragCoord;\n#define gl_FogFragCoord oo_FogFragCoord\n" },
    // GL's window origin is bottom left; SDL_GPU's is top left.
    { "gl_FragCoord", "vec4 oo_GLFragCoord() { return vec4(gl_FragCoord.x, oo_ViewportHeight - gl_FragCoord.y, gl_FragCoord.zw); }\n"
                      "#define gl_FragCoord oo_GLFragCoord()\n" },
};

// Fixed-function emulation, written in legacy GLSL and translated like OXP code.
static const char* const kFixedFunctionVertexSource = "void main(void)\n"
                                                      "{\n"
                                                      "    vec4 eyePos = gl_ModelViewMatrix * gl_Vertex;\n"
                                                      "    gl_Position = gl_ModelViewProjectionMatrix * gl_Vertex;\n"
                                                      "    gl_TexCoord[0] = gl_TextureMatrix[0] * gl_MultiTexCoord0;\n"
                                                      "    gl_TexCoord[1] = gl_TextureMatrix[1] * gl_MultiTexCoord1;\n"
                                                      "    gl_FogFragCoord = -eyePos.z;\n"
                                                      "    vec4 color = gl_Color;\n"
                                                      "    vec4 specular = vec4(0.0);\n"
                                                      "    if (oo_LightingEnabled > 0.5)\n"
                                                      "    {\n"
                                                      "        vec3 n = normalize(gl_NormalMatrix * gl_Normal);\n"
                                                      "        color = gl_FrontLightModelProduct.sceneColor;\n"
                                                      // Oolite only uses GL_LIGHT0 and GL_LIGHT1. A disabled light is
                                                      // represented by zeroed colours.
                                                      "        for (int i = 0; i < 2; i++)\n"
                                                      "        {\n"
                                                      "            vec4 lp = gl_LightSource[i].position;\n"
                                                      "            vec3 l = normalize(lp.w == 0.0 ? lp.xyz : lp.xyz - eyePos.xyz);\n"
                                                      "            float nDotL = max(dot(n, l), 0.0);\n"
                                                      "            color += gl_FrontLightProduct[i].ambient + gl_FrontLightProduct[i].diffuse * nDotL;\n"
                                                      "            if (nDotL > 0.0)\n"
                                                      "            {\n"
                                                      "                float nDotH = max(dot(n, normalize(l + vec3(0.0, 0.0, 1.0))), 0.0);\n"
                                                      "                specular += gl_FrontLightProduct[i].specular * pow(nDotH, gl_FrontMaterial.shininess);\n"
                                                      "            }\n"
                                                      "        }\n"
                                                      "        color.a = gl_FrontMaterial.diffuse.a;\n"
                                                      "    }\n"
                                                      // GL_SEPARATE_SPECULAR_COLOR adds the specular after texturing.
                                                      "    if (oo_SeparateSpecular > 0.5)\n"
                                                      "        gl_FrontSecondaryColor = oo_ClampColor > 0.5 ? clamp(vec4(specular.rgb, 0.0), 0.0, 1.0) : vec4(specular.rgb, 0.0);\n"
                                                      "    else\n"
                                                      "    {\n"
                                                      "        color.rgb += specular.rgb;\n"
                                                      "        gl_FrontSecondaryColor = vec4(0.0);\n"
                                                      "    }\n"
                                                      "    gl_FrontColor = oo_ClampColor > 0.5 ? clamp(color, 0.0, 1.0) : color;\n"
                                                      "}\n";

static const char* const kFixedFunctionFragmentSource = "uniform sampler2D oo_FixedFunctionTexture0;\n"
                                                        "uniform sampler2D oo_FixedFunctionTexture1;\n"
                                                        // GL's texture environments, applied unit by unit.
                                                        "vec4 oo_TexEnv(float mode, vec4 previous, vec4 texel, float alphaOnly)\n"
                                                        "{\n"
                                                        // GL's alpha textures: modulate, replace and add keep the colour.
                                                        "    if (alphaOnly > 0.5 && mode < 2.5) return vec4(previous.rgb, mode < 1.5 && mode > 0.5 ? texel.a : previous.a * texel.a);\n"
                                                        "    if (mode < 0.5) return previous * texel;\n"
                                                        "    if (mode < 1.5) return texel;\n"
                                                        "    if (mode < 2.5) return vec4(previous.rgb + texel.rgb, previous.a * texel.a);\n"
                                                        "    if (mode < 3.5) return previous * texel;\n"
                                                        "    if (mode < 4.5) return vec4(previous.rgb + texel.rgb, previous.a * texel.a);\n"
                                                        "    return vec4(texel.rgb, previous.a * texel.a);\n"
                                                        "}\n"
                                                        "void main(void)\n"
                                                        "{\n"
                                                        "    vec4 color = gl_Color;\n"
                                                        "    if (oo_TextureEnabled.x > 0.5)\n"
                                                        "        color = oo_TexEnv(oo_TextureMode.x, color, texture2D(oo_FixedFunctionTexture0, gl_TexCoord[0].st), oo_TextureAlphaOnly.x);\n"
                                                        "    if (oo_TextureEnabled.y > 0.5)\n"
                                                        "        color = oo_TexEnv(oo_TextureMode.y, color, texture2D(oo_FixedFunctionTexture1, gl_TexCoord[1].st), oo_TextureAlphaOnly.y);\n"
                                                        "    color.rgb += gl_SecondaryColor.rgb;\n"
                                                        "    if (oo_FogEnabled > 0.5)\n"
                                                        "    {\n"
                                                        "        float z = gl_FogFragCoord, f;\n"
                                                        "        if (oo_FogMode < 0.5)\n"
                                                        "            f = (gl_Fog.end - z) * gl_Fog.scale;\n"
                                                        "        else if (oo_FogMode < 1.5)\n"
                                                        "            f = exp(-gl_Fog.density * z);\n"
                                                        "        else\n"
                                                        "            f = exp(-(gl_Fog.density * z) * (gl_Fog.density * z));\n"
                                                        "        color.rgb = mix(gl_Fog.color.rgb, color.rgb, clamp(f, 0.0, 1.0));\n"
                                                        "    }\n"
                                                        "    gl_FragColor = color;\n"
                                                        "}\n";

// Build the complete GLSL 4.10 source for one stage. extraOutputs is
// appended to the vertex prelude (declarations) and extraInit to the vertex
// epilogue; both are used to supply varyings the fragment shader reads but
// the vertex shader never writes.
/*  The number of gl_FragData outputs a shader writes: one more than its
    highest constant index, or one if it only uses computed indices.
*/
static unsigned FragDataCount(const char* source)
{
    unsigned count = 1;
    for (const char* p = strstr(source, "gl_FragData"); p != NULL; p = strstr(p + 1, "gl_FragData")) {
        const char* q = p + strlen("gl_FragData");
        while (*q == ' ' || *q == '\t')
            q++;
        if (*q != '[')
            continue;
        q++;
        while (*q == ' ' || *q == '\t')
            q++;
        if (*q >= '0' && *q <= '9') {
            unsigned index = (unsigned)strtoul(q, NULL, 10);
            if (index + 1 > count && index < 8)
                count = index + 1;
        }
    }
    return count;
}

static char* BuildStageSource(OOGLSLStage stage, const char* prefix, const char* source,
    const char* extraOutputs, const char* extraInit, bool glOrientation)
{
    Str combined = { 0 };
    if (prefix != NULL)
        StrAppend(&combined, prefix);
    StrAppend(&combined, source);
    if (stage == kOOGLSLStageVertex && UsesToken(combined.s, "ftransform"))
        StrAppend(&combined, " gl_Vertex ");

    Str out = { 0 };
    StrAppend(&out, kCommonPrelude);

    if (stage == kOOGLSLStageVertex) {
        for (size_t i = 0; i < sizeof kVertexInputs / sizeof *kVertexInputs; i++) {
            if (UsesToken(combined.s, kVertexInputs[i].legacyName))
                StrAppend(&out, kVertexInputs[i].declaration);
        }
        StrAppend(&out, "#define ftransform() (oo_ModelViewProjectionMatrix * oo_Vertex)\n");
        if (extraOutputs != NULL)
            StrAppend(&out, extraOutputs);
        StrAppend(&out, "#define main oo_user_main\n");
    } else {
        StrAppend(&out, kFragmentTexturePrelude);
        for (size_t i = 0; i < sizeof kFragmentInputs / sizeof *kFragmentInputs; i++) {
            if (!UsesToken(combined.s, kFragmentInputs[i].legacyName))
                continue;
            // Rendering in GL's orientation, gl_FragCoord already matches GL.
            if (glOrientation && strcmp(kFragmentInputs[i].legacyName, "gl_FragCoord") == 0)
                continue;
            StrAppend(&out, kFragmentInputs[i].declaration);
        }
        if (UsesToken(combined.s, "gl_FragColor"))
            StrAppend(&out, "layout(location = 0) out vec4 oo_FragColor;\n#define gl_FragColor oo_FragColor\n");
        else if (UsesToken(combined.s, "gl_FragData")) {
            // As many outputs as the highest constant index written, as the post chain's bloom pass writes two.
            char declaration[128];
            snprintf(declaration, sizeof declaration, "layout(location = 0) out vec4 oo_FragData[%u];\n#define gl_FragData oo_FragData\n",
                FragDataCount(combined.s));
            StrAppend(&out, declaration);
        }
    }
    free(combined.s);

    // The prefix may bring its own #version (the game's post-processing shaders do); ours stands.
    if (prefix != NULL)
        AppendUserSource(&out, prefix);
    StrAppend(&out, "\n#line 1\n");
    AppendUserSource(&out, source);

    if (stage == kOOGLSLStageVertex) {
        StrAppend(&out, "#undef main\n"
                        "void main()\n"
                        "{\n");
        if (extraInit != NULL)
            StrAppend(&out, extraInit);
        StrAppend(&out, "    oo_user_main();\n");
        // GL clip-space depth is [-w, w]; SDL_GPU's is [0, w]. OO_TRANSLATOR_FAULT=depthremap
        // leaves it out, as a negative control for the backend harness.
#ifndef NDEBUG
        const char* fault = getenv("OO_TRANSLATOR_FAULT");
#else
        const char* fault = NULL; // the harness's negative controls are debug-only
#endif
        if (fault == NULL || strcmp(fault, "depthremap") != 0)
            StrAppend(&out, "    gl_Position.z = (gl_Position.z + gl_Position.w) * 0.5;\n");
        if (glOrientation && (fault == NULL || strcmp(fault, "orientation") != 0))
            StrAppend(&out, "    gl_Position.y = -gl_Position.y;\n");
        StrAppend(&out, "}\n");
    }
    return out.s;
}

#pragma mark - glslang

static bool sInitialized = false;

bool OOGLSLTranslatorInit(void)
{
    if (!sInitialized)
        sInitialized = glslang_initialize_process() != 0;
    return sInitialized;
}

void OOGLSLTranslatorShutdown(void)
{
    if (sInitialized) {
        glslang_finalize_process();
        sInitialized = false;
    }
}

static const glslang_stage_t kGlslangStages[kOOGLSLStageCount] = { GLSLANG_STAGE_VERTEX, GLSLANG_STAGE_FRAGMENT };
static const char* const kStageNames[kOOGLSLStageCount] = { "vertex", "fragment" };

typedef struct {
    uint32_t* words;
    size_t count;
} SPIRVModule;

static bool CompileWithGlslang(char* sources[kOOGLSLStageCount], SPIRVModule outModules[kOOGLSLStageCount], Str* log)
{
    glslang_shader_t* shaders[kOOGLSLStageCount] = { NULL };
    glslang_program_t* program = glslang_program_create();
    bool OK = true;
    // Legacy shaders produce a deprecation warning for every attribute and
    // varying, which would drown out anything useful.
    const glslang_messages_t messages = GLSLANG_MSG_SPV_RULES_BIT | GLSLANG_MSG_VULKAN_RULES_BIT | GLSLANG_MSG_SUPPRESS_WARNINGS_BIT;

    for (int stage = 0; stage < kOOGLSLStageCount && OK; stage++) {
        glslang_input_t input = {
            .language = GLSLANG_SOURCE_GLSL,
            .stage = kGlslangStages[stage],
            .client = GLSLANG_CLIENT_VULKAN,
            .client_version = GLSLANG_TARGET_VULKAN_1_0,
            .target_language = GLSLANG_TARGET_SPV,
            .target_language_version = GLSLANG_TARGET_SPV_1_0,
            .code = sources[stage],
            .default_version = 410,
            .default_profile = GLSLANG_NO_PROFILE,
            .messages = messages,
            .resource = glslang_default_resource(),
        };
        shaders[stage] = glslang_shader_create(&input);
        glslang_shader_set_options(shaders[stage], GLSLANG_SHADER_AUTO_MAP_BINDINGS | GLSLANG_SHADER_AUTO_MAP_LOCATIONS | GLSLANG_SHADER_VULKAN_RULES_RELAXED);
        // Blocks with the same name must match across stages, so each stage
        // gets its own.
        glslang_shader_set_default_uniform_block_name(shaders[stage], stage == kOOGLSLStageVertex ? "OOVertexUniforms" : "OOFragmentUniforms");
        glslang_shader_set_default_uniform_block_set_and_binding(shaders[stage],
            stage == kOOGLSLStageVertex ? kVertexUniformSet : kFragmentUniformSet, kOOGLSLUniformsSlot);

        if (!glslang_shader_preprocess(shaders[stage], &input) || !glslang_shader_parse(shaders[stage], &input)) {
            StrAppendf(log, "%s shader:\n%s", kStageNames[stage], glslang_shader_get_info_log(shaders[stage]));
            OK = false;
        } else {
            const char* info = glslang_shader_get_info_log(shaders[stage]);
            if (info != NULL && *info != '\0')
                StrAppendf(log, "%s shader:\n%s", kStageNames[stage], info);
            glslang_program_add_shader(program, shaders[stage]);
        }
    }

    if (OK && (!glslang_program_link(program, messages) || !glslang_program_map_io(program))) {
        StrAppendf(log, "link:\n%s", glslang_program_get_info_log(program));
        OK = false;
    }

    for (int stage = 0; stage < kOOGLSLStageCount && OK; stage++) {
        glslang_program_SPIRV_generate(program, kGlslangStages[stage]);
        outModules[stage].count = glslang_program_SPIRV_get_size(program);
        outModules[stage].words = malloc(outModules[stage].count * sizeof(uint32_t));
        glslang_program_SPIRV_get(program, outModules[stage].words);
        const char* spvMessages = glslang_program_SPIRV_get_messages(program);
        if (spvMessages != NULL && *spvMessages != '\0')
            StrAppendf(log, "%s SPIR-V:\n%s", kStageNames[stage], spvMessages);
    }

    glslang_program_delete(program);
    for (int stage = 0; stage < kOOGLSLStageCount; stage++) {
        if (shaders[stage] != NULL)
            glslang_shader_delete(shaders[stage]);
    }
    return OK;
}

#pragma mark - SPIR-V patching

static bool SetDecoration(SPIRVModule* module, uint32_t target, uint32_t decoration, uint32_t value)
{
    bool found = false;
    for (size_t i = 5; i < module->count;) {
        uint32_t op = module->words[i] & 0xFFFF;
        uint32_t length = module->words[i] >> 16;
        if (length == 0)
            break;
        if (op == kSpvOpDecorate && length >= 4 && module->words[i + 1] == target && module->words[i + 2] == decoration) {
            module->words[i + 3] = value;
            found = true;
        }
        i += length;
    }
    return found;
}

#pragma mark - SPIRV-Cross

typedef struct {
    spvc_context context;
    spvc_compiler compiler;
    spvc_resources resources;
} Reflector;

static void ReportSpvcError(void* userData, const char* error)
{
    StrAppendf((Str*)userData, "SPIRV-Cross: %s\n", error);
}

static bool ReflectorCreate(Reflector* r, const SPIRVModule* module, spvc_backend backend, Str* log)
{
    spvc_parsed_ir ir = NULL;
    memset(r, 0, sizeof *r);
    if (spvc_context_create(&r->context) != SPVC_SUCCESS)
        return false;
    spvc_context_set_error_callback(r->context, ReportSpvcError, log);
    return spvc_context_parse_spirv(r->context, module->words, module->count, &ir) == SPVC_SUCCESS
        && spvc_context_create_compiler(r->context, backend, ir, SPVC_CAPTURE_MODE_COPY, &r->compiler) == SPVC_SUCCESS
        && spvc_compiler_create_shader_resources(r->compiler, &r->resources) == SPVC_SUCCESS;
}

static void ReflectorDestroy(Reflector* r)
{
    if (r->context != NULL)
        spvc_context_destroy(r->context);
    memset(r, 0, sizeof *r);
}

static void GetResources(Reflector* r, spvc_resource_type type, const spvc_reflected_resource** list, size_t* count)
{
    *list = NULL;
    *count = 0;
    spvc_resources_get_resource_list_for_type(r->resources, type, list, count);
}

// GLSL spelling of a type, for declaring a missing varying.
static void AppendGLSLTypeName(Str* out, spvc_type type)
{
    unsigned vecSize = spvc_type_get_vector_size(type);
    unsigned columns = spvc_type_get_columns(type);
    const char* prefix = "";
    switch (spvc_type_get_basetype(type)) {
    case SPVC_BASETYPE_INT32:
        prefix = "i";
        break;
    case SPVC_BASETYPE_UINT32:
        prefix = "u";
        break;
    case SPVC_BASETYPE_BOOLEAN:
        prefix = "b";
        break;
    default:
        break;
    }
    if (columns > 1)
        StrAppendf(out, vecSize == columns ? "mat%u" : "mat%ux%u", columns, vecSize);
    else if (vecSize > 1)
        StrAppendf(out, "%svec%u", prefix, vecSize);
    else
        StrAppend(out, *prefix == 'i' ? "int" : *prefix == 'u' ? "uint"
                : *prefix == 'b'                               ? "bool"
                                                               : "float");
}

/*  Find fragment inputs that the vertex shader doesn't write, and generate
    vertex declarations and initialisers for them. In GL their values were
    undefined; Metal and Vulkan refuse to link such pipelines.
    Returns true if anything was missing.
*/
static bool FindMissingVaryings(SPIRVModule modules[kOOGLSLStageCount], Str* outDecls, Str* outInit, Str* log)
{
    Reflector vertex, fragment;
    bool missing = false;
    if (ReflectorCreate(&vertex, &modules[kOOGLSLStageVertex], SPVC_BACKEND_NONE, log)
        && ReflectorCreate(&fragment, &modules[kOOGLSLStageFragment], SPVC_BACKEND_NONE, log)) {
        const spvc_reflected_resource *inputs, *outputs;
        size_t inputCount, outputCount;
        GetResources(&fragment, SPVC_RESOURCE_TYPE_STAGE_INPUT, &inputs, &inputCount);
        GetResources(&vertex, SPVC_RESOURCE_TYPE_STAGE_OUTPUT, &outputs, &outputCount);
        for (size_t i = 0; i < inputCount; i++) {
            bool found = false;
            for (size_t j = 0; j < outputCount && !found; j++)
                found = strcmp(inputs[i].name, outputs[j].name) == 0;
            if (found)
                continue;

            missing = true;
            spvc_type type = spvc_compiler_get_type_handle(fragment.compiler, inputs[i].type_id);
            StrAppend(outDecls, "out ");
            AppendGLSLTypeName(outDecls, type);
            StrAppendf(outDecls, " %s", inputs[i].name);
            unsigned arraySize = spvc_type_get_num_array_dimensions(type) > 0 ? spvc_type_get_array_dimension(type, 0) : 0;
            if (arraySize > 0)
                StrAppendf(outDecls, "[%u]", arraySize);
            StrAppend(outDecls, ";\n");

            // GL drivers commonly default an unwritten colour to white.
            const char* value = strcmp(inputs[i].name, "oo_FrontColor") == 0 ? "1.0" : "0.0";
            Str typeName = { 0 };
            AppendGLSLTypeName(&typeName, type);
            if (arraySize > 0) {
                StrAppendf(outInit, "    for (int i = 0; i < %u; i++) %s[i] = %s(%s);\n", arraySize, inputs[i].name, typeName.s, value);
            } else {
                StrAppendf(outInit, "    %s = %s(%s);\n", inputs[i].name, typeName.s, value);
            }
            free(typeName.s);
        }
    }
    ReflectorDestroy(&vertex);
    ReflectorDestroy(&fragment);
    return missing;
}

static int CompareBindings(const void* a, const void* b)
{
    const uint32_t* x = a;
    const uint32_t* y = b;
    return (x[0] > y[0]) - (x[0] < y[0]);
}

/*  Rewrite descriptor sets and bindings to SDL_GPU's layout, and make
    fragment input locations match the vertex outputs of the same name.
*/
static bool AssignResourceLocations(SPIRVModule modules[kOOGLSLStageCount], Str* log)
{
    bool OK = true;
    for (int stage = 0; stage < kOOGLSLStageCount && OK; stage++) {
        Reflector r;
        if (!ReflectorCreate(&r, &modules[stage], SPVC_BACKEND_NONE, log)) {
            OK = false;
            ReflectorDestroy(&r);
            break;
        }

        const spvc_reflected_resource* list;
        size_t count;

        // Samplers: slots 0..n-1 in declaration binding order.
        GetResources(&r, SPVC_RESOURCE_TYPE_SAMPLED_IMAGE, &list, &count);
        uint32_t (*order)[2] = calloc(count + 1, sizeof *order);
        for (size_t i = 0; i < count; i++) {
            order[i][0] = spvc_compiler_get_decoration(r.compiler, list[i].id, SpvDecorationBinding);
            order[i][1] = list[i].id;
        }
        qsort(order, count, sizeof *order, CompareBindings);
        for (size_t i = 0; i < count; i++) {
            SetDecoration(&modules[stage], order[i][1], kSpvDecorationDescriptorSet,
                stage == kOOGLSLStageVertex ? kVertexSamplerSet : kFragmentSamplerSet);
            SetDecoration(&modules[stage], order[i][1], kSpvDecorationBinding, (uint32_t)i);
        }
        free(order);

        GetResources(&r, SPVC_RESOURCE_TYPE_SEPARATE_IMAGE, &list, &count);
        if (count > 0) {
            StrAppendf(log, "%s shader: separate images are not supported.\n", kStageNames[stage]);
            OK = false;
        }

        GetResources(&r, SPVC_RESOURCE_TYPE_UNIFORM_BUFFER, &list, &count);
        for (size_t i = 0; i < count; i++) {
            const char* blockName = spvc_compiler_get_name(r.compiler, list[i].base_type_id);
            uint32_t slot = strcmp(blockName, "OOLegacyState") == 0 ? kOOGLSLLegacyStateSlot : kOOGLSLUniformsSlot;
            SetDecoration(&modules[stage], list[i].id, kSpvDecorationDescriptorSet,
                stage == kOOGLSLStageVertex ? kVertexUniformSet : kFragmentUniformSet);
            SetDecoration(&modules[stage], list[i].id, kSpvDecorationBinding, slot);
        }
        ReflectorDestroy(&r);
    }

    if (OK) {
        Reflector vertex, fragment;
        if (ReflectorCreate(&vertex, &modules[kOOGLSLStageVertex], SPVC_BACKEND_NONE, log)
            && ReflectorCreate(&fragment, &modules[kOOGLSLStageFragment], SPVC_BACKEND_NONE, log)) {
            const spvc_reflected_resource *inputs, *outputs;
            size_t inputCount, outputCount;
            GetResources(&fragment, SPVC_RESOURCE_TYPE_STAGE_INPUT, &inputs, &inputCount);
            GetResources(&vertex, SPVC_RESOURCE_TYPE_STAGE_OUTPUT, &outputs, &outputCount);
            for (size_t i = 0; i < inputCount; i++) {
                for (size_t j = 0; j < outputCount; j++) {
                    if (strcmp(inputs[i].name, outputs[j].name) == 0) {
                        uint32_t location = spvc_compiler_get_decoration(vertex.compiler, outputs[j].id, SpvDecorationLocation);
                        SetDecoration(&modules[kOOGLSLStageFragment], inputs[i].id, kSpvDecorationLocation, location);
                        break;
                    }
                }
            }
        } else {
            OK = false;
        }
        ReflectorDestroy(&vertex);
        ReflectorDestroy(&fragment);
    }
    return OK;
}

static OOGLSLBaseType BaseType(spvc_type type)
{
    switch (spvc_type_get_basetype(type)) {
    case SPVC_BASETYPE_FP32:
        return kOOGLSLTypeFloat;
    case SPVC_BASETYPE_INT32:
        return kOOGLSLTypeInt;
    case SPVC_BASETYPE_UINT32:
        return kOOGLSLTypeUInt;
    case SPVC_BASETYPE_BOOLEAN:
        return kOOGLSLTypeBool;
    default:
        return kOOGLSLTypeOther;
    }
}

static bool ReflectStage(OOGLSLStage stage, SPIRVModule* module, OOGLSLOutputFormats formats, OOGLSLStageResult* result, Str* log)
{
    Reflector r;
    bool OK = ReflectorCreate(&r, module, (formats & kOOGLSLOutputMSL) ? SPVC_BACKEND_MSL : SPVC_BACKEND_NONE, log);
    const spvc_reflected_resource* list;
    size_t count;

    if (OK) {
        // Which uniform blocks does the stage actually use?
        spvc_set active = NULL;
        spvc_resources activeResources = NULL;
        if (spvc_compiler_get_active_interface_variables(r.compiler, &active) == SPVC_SUCCESS
            && spvc_compiler_create_shader_resources_for_active_variables(r.compiler, &activeResources, active) == SPVC_SUCCESS) {
            spvc_resources_get_resource_list_for_type(activeResources, SPVC_RESOURCE_TYPE_UNIFORM_BUFFER, &list, &count);
            for (size_t i = 0; i < count; i++) {
                if (spvc_compiler_get_decoration(r.compiler, list[i].id, SpvDecorationBinding) == kOOGLSLLegacyStateSlot)
                    result->usesLegacyState = true;
            }
        }

        GetResources(&r, SPVC_RESOURCE_TYPE_UNIFORM_BUFFER, &list, &count);
        for (size_t i = 0; i < count; i++) {
            if (spvc_compiler_get_decoration(r.compiler, list[i].id, SpvDecorationBinding) != kOOGLSLUniformsSlot)
                continue;
            spvc_type block = spvc_compiler_get_type_handle(r.compiler, list[i].base_type_id);
            size_t blockSize = 0;
            spvc_compiler_get_declared_struct_size(r.compiler, block, &blockSize);
            result->uniformBlockSize = (uint32_t)blockSize;
            unsigned memberCount = spvc_type_get_num_member_types(block);
            result->uniforms = calloc(memberCount, sizeof *result->uniforms);
            result->uniformCount = memberCount;
            for (unsigned m = 0; m < memberCount; m++) {
                OOGLSLUniform* u = &result->uniforms[m];
                spvc_type memberType = spvc_compiler_get_type_handle(r.compiler, spvc_type_get_member_type(block, m));
                unsigned offset = 0, stride = 0;
                size_t size = 0;
                u->name = StrDup(spvc_compiler_get_member_name(r.compiler, list[i].base_type_id, m));
                spvc_compiler_type_struct_member_offset(r.compiler, block, m, &offset);
                spvc_compiler_get_declared_struct_member_size(r.compiler, block, m, &size);
                u->offset = offset;
                u->size = (uint32_t)size;
                u->baseType = BaseType(memberType);
                u->vectorSize = spvc_type_get_vector_size(memberType);
                u->columns = spvc_type_get_columns(memberType);
                if (spvc_type_get_num_array_dimensions(memberType) > 0) {
                    u->arraySize = spvc_type_get_array_dimension(memberType, 0);
                    if (spvc_compiler_type_struct_member_array_stride(r.compiler, block, m, &stride) == SPVC_SUCCESS)
                        u->arrayStride = stride;
                }
                if (u->columns > 1 && spvc_compiler_type_struct_member_matrix_stride(r.compiler, block, m, &stride) == SPVC_SUCCESS)
                    u->matrixStride = stride;
            }
        }

        GetResources(&r, SPVC_RESOURCE_TYPE_SAMPLED_IMAGE, &list, &count);
        result->samplers = calloc(count + 1, sizeof *result->samplers);
        result->samplerCount = count;
        for (size_t i = 0; i < count; i++) {
            spvc_type type = spvc_compiler_get_type_handle(r.compiler, list[i].type_id);
            OOGLSLSampler* s = &result->samplers[i];
            s->name = StrDup(list[i].name);
            s->slot = spvc_compiler_get_decoration(r.compiler, list[i].id, SpvDecorationBinding);
            s->isCube = spvc_type_get_image_dimension(type) == SpvDimCube;
            s->isShadow = spvc_type_get_image_is_depth(type);
            if (spvc_type_get_image_dimension(type) != SpvDim2D && !s->isCube) {
                StrAppendf(log, "%s shader: sampler %s has an unsupported dimension.\n", kStageNames[stage], s->name);
                OK = false;
            }
        }

        if (stage == kOOGLSLStageVertex) {
            GetResources(&r, SPVC_RESOURCE_TYPE_STAGE_INPUT, &list, &count);
            result->vertexInputs = calloc(count + 1, sizeof *result->vertexInputs);
            result->vertexInputCount = count;
            for (size_t i = 0; i < count; i++) {
                spvc_type type = spvc_compiler_get_type_handle(r.compiler, list[i].type_id);
                result->vertexInputs[i].name = StrDup(list[i].name);
                result->vertexInputs[i].location = spvc_compiler_get_decoration(r.compiler, list[i].id, SpvDecorationLocation);
                result->vertexInputs[i].vectorSize = spvc_type_get_vector_size(type);
            }
        }
    }

    if (OK && (formats & kOOGLSLOutputMSL)) {
        SpvExecutionModel model = stage == kOOGLSLStageVertex ? SpvExecutionModelVertex : SpvExecutionModelFragment;
        spvc_compiler_options options = NULL;
        spvc_compiler_create_compiler_options(r.compiler, &options);
        spvc_compiler_options_set_uint(options, SPVC_COMPILER_OPTION_MSL_VERSION, SPVC_MAKE_MSL_VERSION(2, 1, 0));
        spvc_compiler_install_compiler_options(r.compiler, options);

        // SDL_GPU binds uniform slot n at [[buffer(n)]] and sampler slot n
        // at [[texture(n)]]/[[sampler(n)]].
        unsigned samplerSet = stage == kOOGLSLStageVertex ? kVertexSamplerSet : kFragmentSamplerSet;
        unsigned uniformSet = stage == kOOGLSLStageVertex ? kVertexUniformSet : kFragmentUniformSet;
        for (unsigned slot = 0; slot < 2; slot++) {
            spvc_msl_resource_binding binding;
            spvc_msl_resource_binding_init(&binding);
            binding.stage = model;
            binding.desc_set = uniformSet;
            binding.binding = slot;
            binding.msl_buffer = slot;
            spvc_compiler_msl_add_resource_binding(r.compiler, &binding);
        }
        for (size_t i = 0; i < result->samplerCount; i++) {
            spvc_msl_resource_binding binding;
            spvc_msl_resource_binding_init(&binding);
            binding.stage = model;
            binding.desc_set = samplerSet;
            binding.binding = result->samplers[i].slot;
            binding.msl_texture = result->samplers[i].slot;
            binding.msl_sampler = result->samplers[i].slot;
            spvc_compiler_msl_add_resource_binding(r.compiler, &binding);
        }

        const char* msl = NULL;
        if (spvc_compiler_compile(r.compiler, &msl) == SPVC_SUCCESS)
            result->msl = StrDup(msl);
        else
            OK = false;
    }

    ReflectorDestroy(&r);
    return OK;
}

/*  HLSL for D3D12, with SDL_GPU's registers: a vertex shader's textures and
    samplers in space0 and its uniform buffers in space1, a fragment shader's
    in space2 and space3, matching the SPIR-V descriptor sets.
*/
static bool EmitHLSL(OOGLSLStage stage, const SPIRVModule* module, OOGLSLStageResult* result, Str* log)
{
    Reflector r;
    bool OK = ReflectorCreate(&r, module, SPVC_BACKEND_HLSL, log);
    if (OK) {
        spvc_compiler_options options = NULL;
        spvc_compiler_create_compiler_options(r.compiler, &options);
        spvc_compiler_options_set_uint(options, SPVC_COMPILER_OPTION_HLSL_SHADER_MODEL, 51);
        // D3D has no point size; SPIRV-Cross drops writes to gl_PointSize with this.
        spvc_compiler_options_set_bool(options, SPVC_COMPILER_OPTION_HLSL_POINT_SIZE_COMPAT, SPVC_TRUE);
        spvc_compiler_install_compiler_options(r.compiler, options);

        SpvExecutionModel model = stage == kOOGLSLStageVertex ? SpvExecutionModelVertex : SpvExecutionModelFragment;
        unsigned samplerSet = stage == kOOGLSLStageVertex ? kVertexSamplerSet : kFragmentSamplerSet;
        unsigned uniformSet = stage == kOOGLSLStageVertex ? kVertexUniformSet : kFragmentUniformSet;
        for (unsigned slot = 0; slot < 2; slot++) {
            spvc_hlsl_resource_binding binding;
            spvc_hlsl_resource_binding_init(&binding);
            binding.stage = model;
            binding.desc_set = uniformSet;
            binding.binding = slot;
            binding.cbv.register_space = uniformSet;
            binding.cbv.register_binding = slot;
            spvc_compiler_hlsl_add_resource_binding(r.compiler, &binding);
        }
        for (size_t i = 0; i < result->samplerCount; i++) {
            spvc_hlsl_resource_binding binding;
            spvc_hlsl_resource_binding_init(&binding);
            binding.stage = model;
            binding.desc_set = samplerSet;
            binding.binding = result->samplers[i].slot;
            binding.srv.register_space = samplerSet;
            binding.srv.register_binding = result->samplers[i].slot;
            binding.sampler.register_space = samplerSet;
            binding.sampler.register_binding = result->samplers[i].slot;
            spvc_compiler_hlsl_add_resource_binding(r.compiler, &binding);
        }

        const char* hlsl = NULL;
        if (spvc_compiler_compile(r.compiler, &hlsl) == SPVC_SUCCESS)
            result->hlsl = StrDup(hlsl);
        else
            OK = false;
    }
    ReflectorDestroy(&r);
    return OK;
}

#pragma mark - Public interface

bool OOGLSLTranslateProgram(const char* vertexSource, const char* fragmentSource,
    const char* prefix, OOGLSLOutputFormats formats, OOGLSLProgram* outProgram)
{
    memset(outProgram, 0, sizeof *outProgram);
    Str log = { 0 };
    SPIRVModule modules[kOOGLSLStageCount] = { { 0 } };
    char* sources[kOOGLSLStageCount] = { NULL };
    Str extraOutputs = { 0 }, extraInit = { 0 };
    bool OK = OOGLSLTranslatorInit();
    if (!OK)
        StrAppend(&log, "Could not initialise glslang.\n");

    const char* userSources[kOOGLSLStageCount] = {
        vertexSource ? vertexSource : kFixedFunctionVertexSource,
        fragmentSource ? fragmentSource : kFixedFunctionFragmentSource,
    };

    for (int pass = 0; pass < 2 && OK; pass++) {
        for (int stage = 0; stage < kOOGLSLStageCount; stage++) {
            free(sources[stage]);
            free(modules[stage].words);
            modules[stage].words = NULL;
            sources[stage] = BuildStageSource(stage, prefix, userSources[stage], extraOutputs.s, extraInit.s,
                (formats & kOOGLSLOutputGLOrientation) != 0);
        }
        OK = CompileWithGlslang(sources, modules, &log);
        if (OK && pass == 0 && !FindMissingVaryings(modules, &extraOutputs, &extraInit, &log))
            break;
    }

    if (OK)
        OK = AssignResourceLocations(modules, &log);

    for (int stage = 0; stage < kOOGLSLStageCount && OK; stage++) {
        OOGLSLStageResult* result = &outProgram->stages[stage];
        OK = ReflectStage(stage, &modules[stage], formats, result, &log);
        if (OK && (formats & kOOGLSLOutputHLSL))
            OK = EmitHLSL(stage, &modules[stage], result, &log);
        if (OK && (formats & kOOGLSLOutputSPIRV)) {
            result->spirv = modules[stage].words;
            result->spirvWordCount = modules[stage].count;
            modules[stage].words = NULL;
        }
    }

    for (int stage = 0; stage < kOOGLSLStageCount; stage++) {
        free(sources[stage]);
        free(modules[stage].words);
    }
    free(extraOutputs.s);
    free(extraInit.s);
    outProgram->log = log.s ? log.s : StrDup("");
    return OK;
}

static void FreeStage(OOGLSLStageResult* stage)
{
    free(stage->spirv);
    free(stage->msl);
    free(stage->hlsl);
    for (size_t i = 0; i < stage->uniformCount; i++)
        free(stage->uniforms[i].name);
    free(stage->uniforms);
    for (size_t i = 0; i < stage->samplerCount; i++)
        free(stage->samplers[i].name);
    free(stage->samplers);
    for (size_t i = 0; i < stage->vertexInputCount; i++)
        free(stage->vertexInputs[i].name);
    free(stage->vertexInputs);
}

void OOGLSLProgramFree(OOGLSLProgram* program)
{
    if (program == NULL)
        return;
    for (int stage = 0; stage < kOOGLSLStageCount; stage++)
        FreeStage(&program->stages[stage]);
    free(program->log);
    memset(program, 0, sizeof *program);
}

const OOGLSLUniform* OOGLSLFindUniform(const OOGLSLStageResult* stage, const char* name)
{
    for (size_t i = 0; i < stage->uniformCount; i++) {
        if (strcmp(stage->uniforms[i].name, name) == 0)
            return &stage->uniforms[i];
    }
    return NULL;
}
