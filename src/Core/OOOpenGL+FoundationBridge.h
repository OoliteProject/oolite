/*

OOOpenGL+FoundationBridge.h

TRANSITIONAL (proposed ADR-0043, "Transitional bridges"; bead oo-zpz4, made by chunk oo-3rb.143).
OOCheckOpenGLErrors() as it was declared before its sweep, with the same name, type and linkage,
forwarding to cxx_OOCheckOpenGLErrors in OOOpenGL.h. It exists so that its callers compile
unchanged; each caller moves to cxx_OOCheckOpenGLErrors in its own sweep bead (a literal context
-> the printf form; `%@, self` -> the function form with oo::DescriptionOf(self)). When `git grep`
finds no caller of it, the bridge bead deletes this file, OOOpenGL+FoundationBridge.mm, its line
in Core/meson.build and the #import at the end of OOOpenGL.h. Never add to it; never call it from
migrated code. oo-qps (the removal of gnustep-base) cannot compile while it exists.

Registry: src/oofnd/README.md, "Transitional bridges".

Oolite
Copyright (C) 2004-2013 Giles C Williams and contributors (OOOpenGL.h)

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

// Imported only from the end of OOOpenGL.h (which declares everything used here); never import it
// directly, and never import OOOpenGL.h from it (a cycle).
#ifndef OOOPENGL_FOUNDATIONBRIDGE_H
#define OOOPENGL_FOUNDATIONBRIDGE_H

#ifdef __cplusplus
extern "C" {
#endif

/*	OOCheckOpenGLErrors()
        Check for and log OpenGL errors, and returns YES if an error occurred.
        NOTE: this is controlled by the log message class rendering.opengl.error.
                  If logging is disabled, no error checking will occur. This is done
                  because glGetError() is quite expensive, requiring a full OpenGL
                  state sync.
*/
BOOL OOCheckOpenGLErrors(NSString* format, ...); // -> cxx_OOCheckOpenGLErrors

#ifdef __cplusplus
}
#endif

#endif // OOOPENGL_FOUNDATIONBRIDGE_H
