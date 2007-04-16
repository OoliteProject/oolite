/*

OOSingleTextureMaterial.h

A material with a single texture (and no shaders).

Oolite
Copyright (C) 2004-2007 Giles C Williams and contributors

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

#import "OOBasicMaterial.h"

@class OOTexture;


@interface OOSingleTextureMaterial: OOBasicMaterial
{
	OOTexture				*texture;
}

/*	In addition to OOBasicMateral configuration keys, an OOTexture
	configuration dictionary may be used. If there is a "texture" entry, it
	will be used; otherwise, if there is a "textures" array, its first member
	will be used.
	
	If the found OOTexture config dictionary contains a "name" key, it will be
	used in preference to the name parameter.
*/
- (id)initWithName:(NSString *)name configuration:(NSDictionary *)configuration;

@end
