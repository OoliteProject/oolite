/*

OOHLSLCompiler.c


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

#include "OOHLSLCompiler.h"

#include <stdlib.h>
#include <string.h>

#ifdef _WIN32

#define COBJMACROS
#include <windows.h>
// After windows.h, which it needs.
#include <d3dcommon.h>

// D3DCompile, as d3dcompiler.h declares it.
typedef HRESULT(WINAPI* D3DCompileFunction)(LPCVOID source, SIZE_T sourceSize, LPCSTR sourceName,
    const D3D_SHADER_MACRO* defines, ID3DInclude* include, LPCSTR entryPoint, LPCSTR target,
    UINT flags1, UINT flags2, ID3DBlob** code, ID3DBlob** errors);

enum {
    kD3DCompileOptimizationLevel3 = 1 << 15, // D3DCOMPILE_OPTIMIZATION_LEVEL3
};

static D3DCompileFunction LoadD3DCompile(void)
{
    static bool tried = false;
    static D3DCompileFunction compile = NULL;
    if (!tried) {
        tried = true;
        HMODULE library = LoadLibraryA("d3dcompiler_47.dll");
        if (library != NULL)
            compile = (D3DCompileFunction)(void*)GetProcAddress(library, "D3DCompile");
    }
    return compile;
}

bool OOHLSLCompilerAvailable(void)
{
    return LoadD3DCompile() != NULL;
}

bool OOHLSLCompileToDXBC(const char* hlsl, bool vertexStage, void** outCode, size_t* outSize, char** outLog)
{
    *outCode = NULL;
    *outSize = 0;
    if (outLog != NULL)
        *outLog = NULL;
    D3DCompileFunction compile = LoadD3DCompile();
    if (compile == NULL)
        return false;

    ID3DBlob *code = NULL, *errors = NULL;
    HRESULT result = compile(hlsl, strlen(hlsl), NULL, NULL, NULL, "main", vertexStage ? "vs_5_1" : "ps_5_1",
        kD3DCompileOptimizationLevel3, 0, &code, &errors);
    if (errors != NULL) {
        if (outLog != NULL) {
            size_t length = ID3D10Blob_GetBufferSize(errors);
            *outLog = malloc(length + 1);
            if (*outLog != NULL) {
                memcpy(*outLog, ID3D10Blob_GetBufferPointer(errors), length);
                (*outLog)[length] = '\0';
            }
        }
        ID3D10Blob_Release(errors);
    }
    if (FAILED(result) || code == NULL) {
        if (code != NULL)
            ID3D10Blob_Release(code);
        return false;
    }
    *outSize = ID3D10Blob_GetBufferSize(code);
    *outCode = malloc(*outSize);
    if (*outCode != NULL)
        memcpy(*outCode, ID3D10Blob_GetBufferPointer(code), *outSize);
    ID3D10Blob_Release(code);
    return *outCode != NULL;
}

#else

bool OOHLSLCompilerAvailable(void)
{
    return false;
}

bool OOHLSLCompileToDXBC(const char* hlsl, bool vertexStage, void** outCode, size_t* outSize, char** outLog)
{
    (void)hlsl;
    (void)vertexStage;
    *outCode = NULL;
    *outSize = 0;
    if (outLog != NULL)
        *outLog = NULL;
    return false;
}

#endif
