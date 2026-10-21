/*

oogpu-check.c

Runs shader programs through the whole SDL_GPU chain: legacy GLSL ->
SPIR-V (validated for Vulkan 1.0 with SPIRV-Tools) -> MSL -> SDL_GPU shader
and graphics pipeline objects on the local GPU.

Usage: oogpu-check <manifest> [<log file>]

Each manifest line is: label<TAB>vertex path<TAB>fragment path<TAB>prefix path
with "-" for a missing stage (fixed-function emulation) or no prefix.
One result line is printed per program:
    PASS | TRANSLATE | SPIRV_VAL | GPU_SHADER | GPU_PIPELINE  <label>
Details of failures go to the log file.


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

#include <spirv-tools/libspirv.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static bool ValidateSPIRV(spv_context context, const OOGLSLStageResult* stage, FILE* log)
{
    spv_diagnostic diagnostic = NULL;
    spv_result_t result = spvValidateBinary(context, stage->spirv, stage->spirvWordCount, &diagnostic);
    if (result != SPV_SUCCESS && diagnostic != NULL)
        fprintf(log, "spirv-val: %s\n", diagnostic->error);
    spvDiagnosticDestroy(diagnostic);
    return result == SPV_SUCCESS;
}

static char* Field(char** cursor)
{
    char* start = *cursor;
    char* end = strpbrk(start, "\t\n\r");
    if (end != NULL) {
        *end = '\0';
        *cursor = end + 1;
    } else {
        *cursor = start + strlen(start);
    }
    return start;
}

static char* ReadOptional(const char* path, FILE* log, bool* ok)
{
    if (strcmp(path, "-") == 0)
        return NULL;
    char* text = OOReadTextFile(path);
    if (text == NULL) {
        fprintf(log, "cannot read %s\n", path);
        *ok = false;
    }
    return text;
}

int main(int argc, char* argv[])
{
    if (argc < 2) {
        fprintf(stderr, "usage: %s <manifest> [<log file>]\n", argv[0]);
        return 2;
    }
    char* manifest = OOReadTextFile(argv[1]);
    FILE* log = argc > 2 ? fopen(argv[2], "w") : stderr;
    if (manifest == NULL || log == NULL) {
        fprintf(stderr, "cannot open input or log\n");
        return 2;
    }

    if (!SDL_Init(SDL_INIT_VIDEO)) {
        fprintf(stderr, "SDL_Init: %s\n", SDL_GetError());
        return 1;
    }
    SDL_GPUDevice* device = SDL_CreateGPUDevice(SDL_GPU_SHADERFORMAT_MSL | SDL_GPU_SHADERFORMAT_SPIRV, true, NULL);
    if (device == NULL) {
        fprintf(stderr, "SDL_CreateGPUDevice: %s\n", SDL_GetError());
        return 1;
    }
    fprintf(stderr, "GPU driver: %s\n", SDL_GetGPUDeviceDriver(device));
    spv_context spvContext = spvContextCreate(SPV_ENV_VULKAN_1_0);
    OOGLSLOutputFormats formats = OOGPUFormatsForDevice(device) | kOOGLSLOutputSPIRV;
    // OO_CHECK_HLSL_DIR: also translate to HLSL, writing <n>.vs.hlsl and <n>.ps.hlsl there for an HLSL compiler.
    const char* hlslDir = getenv("OO_CHECK_HLSL_DIR");
    if (hlslDir != NULL)
        formats |= kOOGLSLOutputHLSL;

    unsigned total = 0, passed = 0;
    char* cursor = manifest;
    while (*cursor != '\0') {
        char* lineEnd = strchr(cursor, '\n');
        char* next = lineEnd ? lineEnd + 1 : cursor + strlen(cursor);
        if (lineEnd != NULL)
            *lineEnd = '\0';
        char* fields = cursor;
        cursor = next;
        if (*fields == '\0' || *fields == '#')
            continue;

        const char* label = Field(&fields);
        const char* vsPath = Field(&fields);
        const char* fsPath = Field(&fields);
        const char* prefixPath = Field(&fields);
        bool ok = true;
        char* vs = ReadOptional(vsPath, log, &ok);
        char* fs = ReadOptional(fsPath, log, &ok);
        char* prefix = ReadOptional(*prefixPath ? prefixPath : "-", log, &ok);
        const char* status = "PASS";
        total++;

        OOGLSLProgram program = { 0 };
        fprintf(log, "==== %s\n", label);
        Uint64 start = SDL_GetTicksNS();
        bool translated = ok && OOGLSLTranslateProgram(vs, fs, prefix, formats, &program);
        double translateMs = (SDL_GetTicksNS() - start) / 1e6;
        if (!translated) {
            status = "TRANSLATE";
            if (ok)
                fprintf(log, "%s", program.log);
        } else {
            for (int stage = 0; stage < kOOGLSLStageCount; stage++) {
                if (!ValidateSPIRV(spvContext, &program.stages[stage], log))
                    status = "SPIRV_VAL";
                if (hlslDir != NULL) {
                    char path[1024];
                    snprintf(path, sizeof path, "%s/%u.%s.hlsl", hlslDir, total, stage == kOOGLSLStageVertex ? "vs" : "ps");
                    FILE* file = fopen(path, "w");
                    if (file != NULL && program.stages[stage].hlsl != NULL) {
                        fprintf(file, "// %s\n%s", label, program.stages[stage].hlsl);
                    } else {
                        status = "HLSL";
                    }
                    if (file != NULL)
                        fclose(file);
                }
            }
            if (strcmp(status, "PASS") == 0) {
                OOGPUProgram gpu;
                if (!OOGPUProgramCreate(device, &program, SDL_GPU_TEXTUREFORMAT_B8G8R8A8_UNORM, SDL_GPU_TEXTUREFORMAT_D32_FLOAT, &gpu)) {
                    status = strstr(SDL_GetError(), "ipeline") ? "GPU_PIPELINE" : "GPU_SHADER";
                    fprintf(log, "SDL: %s\n", SDL_GetError());
                    for (int stage = 0; stage < kOOGLSLStageCount; stage++) {
                        if (program.stages[stage].msl != NULL)
                            fprintf(log, "---- %s MSL\n%s\n", stage == 0 ? "vertex" : "fragment", program.stages[stage].msl);
                    }
                } else {
                    OOGPUProgramRelease(device, &gpu);
                }
            }
        }
        if (strcmp(status, "PASS") == 0)
            passed++;
        printf("%s\t%s\t%.2f\n", status, label, translateMs);
        fflush(stdout);
        OOGLSLProgramFree(&program);
        free(vs);
        free(fs);
        free(prefix);
    }

    fprintf(stderr, "%u/%u programs passed\n", passed, total);
    spvContextDestroy(spvContext);
    SDL_DestroyGPUDevice(device);
    SDL_Quit();
    OOGLSLTranslatorShutdown();
    free(manifest);
    return passed == total ? 0 : 1;
}
