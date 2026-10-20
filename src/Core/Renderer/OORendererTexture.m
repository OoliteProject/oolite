/*

OORendererTexture.m

Objective-C glue between the renderer layer and OOTexture for the OpenGL
backend.


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

#import "OOMacroOpenGL.h"
#import "OORendererBackend.h"
#import "OOTextureInternal.h"

static GLint sSavedBinding[kOORendererMaxDrawStateDepth];
static GLfloat sSavedLODBias[kOORendererMaxDrawStateDepth];

void OORendererBackendApplyTexture(const void* texture)
{
    OO_ENTER_OPENGL();
    if (texture != NULL)
        [(OOTexture*)texture apply];
    else
        OOGL(glBindTexture(GL_TEXTURE_2D, 0));
}

unsigned OORendererBackendTextureName(const void* texture)
{
    return texture != NULL ? (unsigned)[(OOTexture*)texture glTextureName] : 0;
}

void OORendererBackendSaveTexture(int depth)
{
    OO_ENTER_OPENGL();
    OOGL(glGetIntegerv(GL_TEXTURE_BINDING_2D, &sSavedBinding[depth]));
#if GL_EXT_texture_lod_bias
    if (gOOTextureInfo.textureLODBiasAvailable)
        OOGL(glGetTexEnvfv(GL_TEXTURE_FILTER_CONTROL_EXT, GL_TEXTURE_LOD_BIAS_EXT, &sSavedLODBias[depth]));
#endif
}

void OORendererBackendRestoreTexture(int depth)
{
    OO_ENTER_OPENGL();
    OOGL(glBindTexture(GL_TEXTURE_2D, (GLuint)sSavedBinding[depth]));
#if GL_EXT_texture_lod_bias
    if (gOOTextureInfo.textureLODBiasAvailable)
        OOGL(glTexEnvf(GL_TEXTURE_FILTER_CONTROL_EXT, GL_TEXTURE_LOD_BIAS_EXT, sSavedLODBias[depth]));
#endif
}
