/*

OOHLSLCompiler.h

HLSL to DXBC, for SDL_GPU's Direct3D 12 driver (issue #579). Uses the
D3DCompile in d3dcompiler_47.dll, which Windows 10 and later include; it is
loaded on first use, so nothing links against it.


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

#ifndef OOHLSLCOMPILER_H
#define OOHLSLCOMPILER_H

#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

// Whether the compiler can be loaded; always false off Windows.
bool OOHLSLCompilerAvailable(void);

/*  Compile shader model 5.1 HLSL (entry point "main") to DXBC. On success,
    *outCode holds outSize bytes; free() it. On failure, *outLog (if not
    NULL) gets the compiler's messages, also to free().
*/
bool OOHLSLCompileToDXBC(const char* hlsl, bool vertexStage, void** outCode, size_t* outSize, char** outLog);

#ifdef __cplusplus
}
#endif

#endif
