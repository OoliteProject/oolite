/*

MyOpenGLView+FoundationBridge.h

TRANSITIONAL (proposed ADR-0043, "Transitional bridges"; bead oo-3rb.110). MyOpenGLView's
Foundation-typed API as it was before its sweep, with the same selector names and types,
forwarding to the cxx_ API in MyOpenGLView.h. It exists so that MyOpenGLView's callers compile
unchanged; each caller moves to the cxx_ API in its own sweep bead. When `git grep` finds no caller
of anything declared here, the bridge bead deletes this file, MyOpenGLView+FoundationBridge.mm, its
line in SDL/meson.build and the #import at the end of MyOpenGLView.h. Never add to it (except the
later MyOpenGLView chunks of the same split, which move their own selectors here); never call it
from migrated code. oo-qps (the removal of gnustep-base) cannot compile while it exists.

Registry: src/oofnd/README.md, "Transitional bridges".

Oolite
Copyright (C) 2004-2013 Giles C Williams and contributors (MyOpenGLView.h)

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

// Imported only from the end of MyOpenGLView.h (which declares everything used here); never import
// it directly, and never import MyOpenGLView.h from it (a cycle).
#ifndef MYOPENGLVIEW_FOUNDATIONBRIDGE_H
#define MYOPENGLVIEW_FOUNDATIONBRIDGE_H

@interface MyOpenGLView (OOFoundationBridge)

- (void)stringToClipboard:(NSString*)stringToCopy; // -> -cxx_stringToClipboard:

- (BOOL)snapShot:(NSString*)filename; // -> -cxx_snapShot:

// From MyOpenGLView+Input.h (bead oo-3rb.113):
- (NSString*)typedString; // -> -cxx_typedString (an autoreleased copy, no longer the live buffer)
- (void)setTypedString:(NSString*)value; // -> -cxx_setTypedString:

// -> -cxx_dump...
#ifndef NDEBUG
// General image-dumping method.
- (void)dumpRGBAToFileNamed:(NSString*)name
                      bytes:(uint8_t*)bytes
                      width:(NSUInteger)width
                     height:(NSUInteger)height
                   rowBytes:(NSUInteger)rowBytes;
- (void)dumpRGBToFileNamed:(NSString*)name
                     bytes:(uint8_t*)bytes
                     width:(NSUInteger)width
                    height:(NSUInteger)height
                  rowBytes:(NSUInteger)rowBytes;
- (void)dumpGrayToFileNamed:(NSString*)name
                      bytes:(uint8_t*)bytes
                      width:(NSUInteger)width
                     height:(NSUInteger)height
                   rowBytes:(NSUInteger)rowBytes;
- (void)dumpGrayAlphaToFileNamed:(NSString*)name
                           bytes:(uint8_t*)bytes
                           width:(NSUInteger)width
                          height:(NSUInteger)height
                        rowBytes:(NSUInteger)rowBytes;
- (void)dumpRGBAToRGBFileNamed:(NSString*)rgbName
              andGrayFileNamed:(NSString*)grayName
                         bytes:(uint8_t*)bytes
                         width:(NSUInteger)width
                        height:(NSUInteger)height
                      rowBytes:(NSUInteger)rowBytes;
#endif

@end

#endif // MYOPENGLVIEW_FOUNDATIONBRIDGE_H
