/*

oogpu-hlsl-check.c

Runs shader programs through the Direct3D 12 half of the SDL_GPU backend:
legacy GLSL -> translator -> HLSL (shader model 5.1) -> D3DCompile -> DXBC.
Needs no GPU, so it runs on CI's Windows runners, which have
d3dcompiler_47.dll but no Direct3D 12 device. Built by the game's meson
build in sdl_gpu builds (meson compile oogpu-hlsl-check).

Usage: oogpu-hlsl-check <manifest>
Each manifest line is "label <tab> vertex <tab> fragment <tab> prefix", with
"-" for a missing file; lines starting with # are comments. Paths are
relative to the working directory. Exits 0 if every program compiles, 1 if
any fails, 2 if D3DCompile can't be loaded (always, off Windows).


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
#include "OOHLSLCompiler.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static char* ReadFile(const char* path)
{
    FILE* file = fopen(path, "rb");
    if (file == NULL)
        return NULL;
    fseek(file, 0, SEEK_END);
    long size = ftell(file);
    fseek(file, 0, SEEK_SET);
    char* text = size >= 0 ? malloc((size_t)size + 1) : NULL;
    if (text != NULL) {
        size_t read = fread(text, 1, (size_t)size, file);
        text[read] = '\0';
    }
    fclose(file);
    return text;
}

// The next tab-separated field of *cursor, or "" at the end of the line.
static char* Field(char** cursor)
{
    char* start = *cursor;
    char* end = strchr(start, '\t');
    if (end != NULL) {
        *end = '\0';
        *cursor = end + 1;
    } else {
        *cursor = start + strlen(start);
    }
    return start;
}

static double Seconds(void)
{
    return (double)clock() / CLOCKS_PER_SEC;
}

int main(int argc, char* argv[])
{
    if (argc < 2) {
        fprintf(stderr, "usage: %s <manifest>\n", argv[0]);
        return 2;
    }
    if (!OOHLSLCompilerAvailable()) {
        fprintf(stderr, "D3DCompile (d3dcompiler_47.dll) is not available\n");
        return 2;
    }
    char* manifest = ReadFile(argv[1]);
    if (manifest == NULL || !OOGLSLTranslatorInit()) {
        fprintf(stderr, "cannot read %s, or cannot start glslang\n", argv[1]);
        return 2;
    }

    unsigned total = 0, passed = 0;
    char* cursor = manifest;
    while (*cursor != '\0') {
        char* lineEnd = strchr(cursor, '\n');
        char* next = lineEnd ? lineEnd + 1 : cursor + strlen(cursor);
        if (lineEnd != NULL) {
            *lineEnd = '\0';
            if (lineEnd > cursor && lineEnd[-1] == '\r')
                lineEnd[-1] = '\0';
        }
        char* fields = cursor;
        cursor = next;
        if (*fields == '\0' || *fields == '#')
            continue;

        const char* label = Field(&fields);
        const char* paths[3] = { Field(&fields), Field(&fields), Field(&fields) };
        char* texts[3] = { NULL };
        bool ok = true;
        for (int i = 0; i < 3; i++) {
            if (*paths[i] != '\0' && strcmp(paths[i], "-") != 0) {
                texts[i] = ReadFile(paths[i]);
                if (texts[i] == NULL) {
                    printf("FAIL\t%s\tcannot read %s\n", label, paths[i]);
                    ok = false;
                }
            }
        }
        total++;

        double start = Seconds();
        OOGLSLProgram program = { 0 };
        if (ok && !OOGLSLTranslateProgram(texts[0], texts[1], texts[2], kOOGLSLOutputHLSL | kOOGLSLOutputGLOrientation, &program)) {
            printf("FAIL\t%s\ttranslation:\n%s\n", label, program.log ? program.log : "");
            ok = false;
        }
        double translated = Seconds();
        for (int stage = 0; stage < kOOGLSLStageCount && ok; stage++) {
            void* code = NULL;
            size_t size = 0;
            char* log = NULL;
            if (!OOHLSLCompileToDXBC(program.stages[stage].hlsl, stage == kOOGLSLStageVertex, &code, &size, &log)) {
                printf("FAIL\t%s\t%s stage D3DCompile:\n%s\n", label, stage == kOOGLSLStageVertex ? "vertex" : "fragment", log ? log : "");
                ok = false;
            }
            free(code);
            free(log);
        }
        if (ok) {
            passed++;
            printf("PASS\t%s\ttranslate %.1f ms, D3DCompile %.1f ms\n", label, (translated - start) * 1000, (Seconds() - translated) * 1000);
        }
        fflush(stdout);
        OOGLSLProgramFree(&program);
        for (int i = 0; i < 3; i++)
            free(texts[i]);
    }

    printf("%u/%u programs compiled to DXBC\n", passed, total);
    OOGLSLTranslatorShutdown();
    free(manifest);
    return passed == total ? 0 : 1;
}
