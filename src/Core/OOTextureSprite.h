/*

OOTextureSprite.h

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

#import "OOCocoa.h"
#import "OOOpenGL.h"

@class OOTexture;


#define	OPEN_GL_SPRITE_MIN_WIDTH	64.0
#define	OPEN_GL_SPRITE_MIN_HEIGHT	64.0


@interface OOTextureSprite: NSObject
{
@private
	OOTexture	*texture;
	NSSize		size;
}


- (id) initWithTexture:(OOTexture *)texture;
- (id) initWithTexture:(OOTexture *)texture size:(NSSize)spriteSize;

- (NSSize) size;

- (void) blitToX:(float)x Y:(float)y Z:(float)z alpha:(float)a;
- (void) blitCentredToX:(float)x Y:(float)y Z:(float)z alpha:(float)a;
- (void) blitBackgroundCentredToX:(float)x Y:(float)y Z:(float)z alpha:(float)a;

@end
