/*

MyOpenGLView+FoundationBridge.mm

TRANSITIONAL: see MyOpenGLView+FoundationBridge.h. Each method forwards to its cxx_ counterpart
and treats nil as the old method did (a nil string was not copied to the clipboard, a nil snapshot
name was auto-numbered, a nil dump name wrote nothing).

Oolite
Copyright (C) 2004-2013 Giles C Williams and contributors

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

#import "MyOpenGLView.h" // declares the bridge category at its end
#import "OOFoundationBridge.h"

@implementation MyOpenGLView (OOFoundationBridge)

- (void)stringToClipboard:(NSString*)stringToCopy
{
    if (stringToCopy == nil)
        return;
    [self cxx_stringToClipboard:oo::StdString(stringToCopy)];
}

- (BOOL)snapShot:(NSString*)filename
{
    return [self cxx_snapShot:oo::OptionalString(filename)];
}

- (NSString*)typedString
{
    return oo::NSStringOrNil([self cxx_typedString]);
}

- (void)setTypedString:(NSString*)value
{
    [self cxx_setTypedString:oo::StdString(value)];
}

#ifndef NDEBUG
- (void)dumpRGBAToFileNamed:(NSString*)name
                      bytes:(uint8_t*)bytes
                      width:(NSUInteger)width
                     height:(NSUInteger)height
                   rowBytes:(NSUInteger)rowBytes
{
    if (name == nil)
        return;
    [self cxx_dumpRGBAToFileNamed:oo::StdString(name) bytes:bytes width:width height:height rowBytes:rowBytes];
}

- (void)dumpRGBToFileNamed:(NSString*)name
                     bytes:(uint8_t*)bytes
                     width:(NSUInteger)width
                    height:(NSUInteger)height
                  rowBytes:(NSUInteger)rowBytes
{
    if (name == nil)
        return;
    [self cxx_dumpRGBToFileNamed:oo::StdString(name) bytes:bytes width:width height:height rowBytes:rowBytes];
}

- (void)dumpGrayToFileNamed:(NSString*)name
                      bytes:(uint8_t*)bytes
                      width:(NSUInteger)width
                     height:(NSUInteger)height
                   rowBytes:(NSUInteger)rowBytes
{
    if (name == nil)
        return;
    [self cxx_dumpGrayToFileNamed:oo::StdString(name) bytes:bytes width:width height:height rowBytes:rowBytes];
}

- (void)dumpGrayAlphaToFileNamed:(NSString*)name
                           bytes:(uint8_t*)bytes
                           width:(NSUInteger)width
                          height:(NSUInteger)height
                        rowBytes:(NSUInteger)rowBytes
{
    if (name == nil)
        return;
    [self cxx_dumpGrayAlphaToFileNamed:oo::StdString(name) bytes:bytes width:width height:height rowBytes:rowBytes];
}

- (void)dumpRGBAToRGBFileNamed:(NSString*)rgbName
              andGrayFileNamed:(NSString*)grayName
                         bytes:(uint8_t*)bytes
                         width:(NSUInteger)width
                        height:(NSUInteger)height
                      rowBytes:(NSUInteger)rowBytes
{
    [self cxx_dumpRGBAToRGBFileNamed:oo::OptionalString(rgbName)
                    andGrayFileNamed:oo::OptionalString(grayName)
                               bytes:bytes
                               width:width
                              height:height
                            rowBytes:rowBytes];
}
#endif

@end
