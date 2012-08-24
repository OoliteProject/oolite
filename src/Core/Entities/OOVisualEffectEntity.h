/*
 
 OOVisualEffectEntity.h
 
 Entity subclass representing a visual effect with a custom mesh
 
 Oolite
 Copyright (C) 2004-2012 Giles C Williams and contributors
 
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

#import "OOEntityWithDrawable.h"
#import "OOPlanetEntity.h"
#import "OOJSPropID.h"

@class	OOColor, OOMesh, OOScript, OOJSScript;


@interface OOVisualEffectEntity: OOEntityWithDrawable <OOSubEntity>
{
@private
	NSMutableArray			*subEntities;

	NSDictionary			*effectinfoDictionary;

	GLfloat					_profileRadius; // for frustum culling

	OOColor					*scanner_display_color1;
	OOColor					*scanner_display_color2;
	
	NSString				*_effectKey;

}

- (id)initWithKey:(NSString *)key definition:(NSDictionary *) dict;
- (BOOL) setUpVisualEffectFromDictionary:(NSDictionary *) effectDict;

- (OOMesh *)mesh;
- (void)setMesh:(OOMesh *)mesh;

- (GLfloat)frustumRadius;

- (void) clearSubEntities;
- (BOOL)setUpSubEntities;
- (NSArray *)subEntities;
- (unsigned) subEntityCount;
- (BOOL) hasSubEntity:(Entity<OOSubEntity> *)sub;

- (NSEnumerator *)subEntityEnumerator;
- (NSEnumerator *)effectSubEntityEnumerator;
- (NSEnumerator *)flasherEnumerator;

- (OOColor *)scannerDisplayColor1;
- (OOColor *)scannerDisplayColor2;
- (void)setScannerDisplayColor1:(OOColor *)color;
- (void)setScannerDisplayColor2:(OOColor *)color; 
- (GLfloat *) scannerDisplayColorForShip:(BOOL)flash :(OOColor *)scannerDisplayColor1 :(OOColor *)scannerDisplayColor2;

// convenience for shaders
// FIXME: make this actually work
- (GLfloat)hullHeatLevel;

- (BOOL) isBreakPattern;
- (void) setIsBreakPattern:(BOOL)bp;

- (NSDictionary *)effectInfoDictionary;


@end
