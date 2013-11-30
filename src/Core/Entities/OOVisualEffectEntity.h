/*
 
 OOVisualEffectEntity.h
 
 Entity subclass representing a visual effect with a custom mesh
 
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

#import "OOEntityWithDrawable.h"
#import "OOPlanetEntity.h"
#import "OOJSPropID.h"
#import "HeadUpDisplay.h"
#import "OOWeakReference.h"

@class	OOColor, OOMesh, OOScript, OOJSScript;


@interface OOVisualEffectEntity: OOEntityWithDrawable <OOSubEntity,OOBeaconEntity>
{
@private
	NSMutableArray			*subEntities;

	NSDictionary			*effectinfoDictionary;

	GLfloat					_profileRadius; // for frustum culling

	OOColor					*scanner_display_color1;
	OOColor					*scanner_display_color2;

	GLfloat         _hullHeatLevel;
	GLfloat         _shaderFloat1;
	GLfloat         _shaderFloat2;
	int             _shaderInt1;
	int             _shaderInt2;
	Vector          _shaderVector1;
	Vector          _shaderVector2;

	Vector _v_forward;
	Vector _v_up;
	Vector _v_right;

	OOJSScript				*script;
	NSDictionary			*scriptInfo;

	NSString				*_effectKey;

	BOOL            _haveExecutedSpawnAction;

	// beacons
	NSString				*_beaconCode;
	NSString				*_beaconLabel;
	OOWeakReference			*_prevBeacon;
	OOWeakReference			*_nextBeacon;
	id <OOHUDBeaconIcon>	_beaconDrawable;

	// scaling
	GLfloat scaleX;
	GLfloat scaleY;
	GLfloat scaleZ;

}

- (id)initWithKey:(NSString *)key definition:(NSDictionary *) dict;
- (BOOL) setUpVisualEffectFromDictionary:(NSDictionary *) effectDict;

- (OOMesh *)mesh;
- (void)setMesh:(OOMesh *)mesh;

- (NSString *)effectKey;

- (GLfloat)frustumRadius;

- (void) clearSubEntities;
- (BOOL) setUpSubEntities;
- (void) removeSubEntity:(Entity<OOSubEntity> *)sub;
- (void) setNoDrawDistance;
- (NSArray *)subEntities;
- (NSUInteger) subEntityCount;
- (NSEnumerator *) visualEffectSubEntityEnumerator;
- (BOOL) hasSubEntity:(Entity<OOSubEntity> *)sub;

- (NSEnumerator *)subEntityEnumerator;
- (NSEnumerator *)effectSubEntityEnumerator;
- (NSEnumerator *)flasherEnumerator;

- (void) orientationChanged;
- (Vector) forwardVector;
- (Vector) rightVector;
- (Vector) upVector;

- (OOColor *)scannerDisplayColor1;
- (OOColor *)scannerDisplayColor2;
- (void)setScannerDisplayColor1:(OOColor *)color;
- (void)setScannerDisplayColor2:(OOColor *)color; 
- (GLfloat *) scannerDisplayColorForShip:(BOOL)flash :(OOColor *)scannerDisplayColor1 :(OOColor *)scannerDisplayColor2;

- (void) setScript:(NSString *)script_name;
- (OOJSScript *)script;
- (NSDictionary *)scriptInfo;
- (void) doScriptEvent:(jsid)message;
- (void) remove;

- (GLfloat) scaleMax; // used for calculating frustum cull size
- (GLfloat) scaleX;
- (void) setScaleX:(GLfloat)factor;
- (GLfloat) scaleY;
- (void) setScaleY:(GLfloat)factor;
- (GLfloat) scaleZ;
- (void) setScaleZ:(GLfloat)factor;

// convenience for shaders
- (GLfloat)hullHeatLevel;
- (void)setHullHeatLevel:(GLfloat)value;
// shader properties
- (GLfloat) shaderFloat1;
- (void)setShaderFloat1:(GLfloat)value;
- (GLfloat) shaderFloat2; 
- (void)setShaderFloat2:(GLfloat)value;
- (int) shaderInt1; 
- (void)setShaderInt1:(int)value;
- (int) shaderInt2;
- (void)setShaderInt2:(int)value;
- (Vector) shaderVector1; 
- (void)setShaderVector1:(Vector)value;
- (Vector) shaderVector2; 
- (void)setShaderVector2:(Vector)value;


- (BOOL) isBreakPattern;
- (void) setIsBreakPattern:(BOOL)bp;

- (NSDictionary *)effectInfoDictionary;


@end
