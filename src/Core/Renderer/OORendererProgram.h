/*

OORendererProgram.h

Shader programs for the renderer layer (issue #579).

Programs are Oolite's legacy GLSL (and OXPs'), compiled by the backend: by
the driver on OpenGL, and by the GLSL translator under SDL_GPU, which also
reflects the uniforms. Uniforms are set by handle on the program in use, as
OOShaderProgram's are; a sampler uniform's integer value is the texture
unit it reads, whose binding comes from the state mirror at each draw.


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

#ifndef OORENDERERPROGRAM_H
#define OORENDERERPROGRAM_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct OORendererProgram OORendererProgram;

// A generic vertex attribute's location, as glBindAttribLocation.
typedef struct {
    const char* name;
    unsigned location;
} OOAttributeBinding;

typedef enum {
    kOOProgramStageVertex,
    kOOProgramStageFragment,
    kOOProgramStageLink,
} OOProgramStage;

typedef struct {
    OOProgramStage stage; // what failed
    char* log; // the compiler's or linker's log; free() it
} OOProgramError;

/*  Compile and link. Either source may be NULL for that stage's fixed
    function; prefix (may be NULL) is prepended to both, then "#line 0".
    Returns NULL on failure, filling outError (if not NULL).
*/
OORendererProgram* OORendererCreateProgram(const char* vertexSource, const char* fragmentSource, const char* prefix,
    const OOAttributeBinding* bindings, size_t bindingCount, OOProgramError* outError);
void OORendererReleaseProgram(OORendererProgram* program);

// Draw with program from now on, or with fixed function for NULL.
void OORendererUseProgram(OORendererProgram* program);
OORendererProgram* OORendererCurrentProgram(void);

// The OpenGL program name, for the state mirror; 0 on other backends.
uint32_t OORendererProgramGLName(const OORendererProgram* program);

typedef int OOProgramUniform; // -1 for none
OOProgramUniform OORendererProgramUniform(OORendererProgram* program, const char* name);

typedef enum {
    kOOUniformInt, // also bool, and the texture unit of a sampler
    kOOUniformFloat,
    kOOUniformVec2,
    kOOUniformVec4,
    kOOUniformMat3, // nine floats, column-major
    kOOUniformMat4, // sixteen floats, column-major
} OOUniformType;

// Set a uniform of the program in use. values are int32_t for kOOUniformInt, floats otherwise.
void OORendererSetUniform(OOProgramUniform uniform, OOUniformType type, const void* values);

#ifdef __cplusplus
}
#endif

#endif
