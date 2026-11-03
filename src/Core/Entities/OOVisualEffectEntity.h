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

#pragma once

#import "HeadUpDisplay.h"
#import "OOEntityWithDrawable.h"
#import "OOJSPropID.h"
#import "OOPlanetEntity.h"
#import "OOWeakReference.h"

#include "oofnd/PList.hpp"
#include "oofnd/StdLib.hpp"
#include "oofnd/objc/OOObjCRef.h"

@class OOColor, OOMesh, OOScript, OOJSScript, OOFlasherEntity;

/*	Foundation sweep (proposed ADR-0043, bead oo-ensq). The effect definition and script_info are
        oo::PLists (script_info null where it was nil); the effect key and beacon strings are
        std::optional (nullopt where they were nil). The subentity list is nullopt until the first
        subentity is added and again after -clearSubEntities, as the array was nil. -subEntities /
        -subEntityEnumerator / -flasherEnumerator return std::vector snapshots (empty where the
        array was nil).
*/
using OOVisualEffectSubEntities = std::vector<oo::ObjCRef<Entity<OOSubEntity>*>>;

@interface OOVisualEffectEntity : OOEntityWithDrawable <OOSubEntity, OOBeaconEntity> {
@private
    std::optional<OOVisualEffectSubEntities> subEntities;

    oo::PList effectinfoDictionary;

    GLfloat _profileRadius; // for frustum culling

    OOColor* scanner_display_color1;
    OOColor* scanner_display_color2;

    GLfloat _hullHeatLevel;
    GLfloat _shaderFloat1;
    GLfloat _shaderFloat2;
    int _shaderInt1;
    int _shaderInt2;
    Vector _shaderVector1;
    Vector _shaderVector2;

    Vector _v_forward;
    Vector _v_up;
    Vector _v_right;

    OOJSScript* script;
    oo::PList scriptInfo;

    std::optional<std::string> _effectKey;

    BOOL _haveExecutedSpawnAction;

    // beacons
    std::optional<std::string> _beaconCode;
    std::optional<std::string> _beaconLabel;
    OOWeakReference* _prevBeacon;
    OOWeakReference* _nextBeacon;
    id<OOHUDBeaconIcon> _beaconDrawable;

    // scaling
    GLfloat scaleX;
    GLfloat scaleY;
    GLfloat scaleZ;
}

- (id)cxx_initWithKey:(const std::string&)key definition:(const oo::PList&)dict;
- (BOOL)setUpVisualEffectFromDictionary:(const oo::PList&)effectDict;

- (OOMesh*)mesh;
- (void)setMesh:(OOMesh*)mesh;

- (std::optional<std::string>)effectKey;

- (GLfloat)frustumRadius;

- (void)clearSubEntities;
- (BOOL)setUpSubEntities;
- (void)removeSubEntity:(Entity<OOSubEntity>*)sub;
- (void)setNoDrawDistance;
- (std::vector<oo::ObjCRef<Entity*>>)subEntities; // a snapshot; empty before the first subentity (was nil)
- (NSUInteger)subEntityCount;
- (std::optional<std::vector<oo::ObjCRef<OOVisualEffectEntity*>>>)visualEffectSubEntityEnumerator; // the visual-effect subentities; nullopt where the array was nil
- (BOOL)hasSubEntity:(Entity<OOSubEntity>*)sub;

- (std::vector<oo::ObjCRef<Entity*>>)subEntityEnumerator; // snapshot, same as -subEntities
- (std::vector<oo::ObjCRef<OOVisualEffectEntity*>>)effectSubEntityEnumerator;
- (std::vector<oo::ObjCRef<OOFlasherEntity*>>)flasherEnumerator; // flasher subentities, a snapshot

- (void)orientationChanged;
- (Vector)forwardVector;
- (Vector)rightVector;
- (Vector)upVector;

- (OOColor*)scannerDisplayColor1;
- (OOColor*)scannerDisplayColor2;
- (void)setScannerDisplayColor1:(OOColor*)color;
- (void)setScannerDisplayColor2:(OOColor*)color;
- (GLfloat*)scannerDisplayColorForShip:(BOOL)flash scannerDisplayColor1:(OOColor*)scannerDisplayColor1 scannerDisplayColor2:(OOColor*)scannerDisplayColor2;

- (void)setScript:(const std::optional<std::string>&)script_name;
- (OOJSScript*)script;
- (oo::PList)scriptInfo; // flipped with its family (bead oo-3rb.284)
- (void)doScriptEvent:(OOJSPropID)message;
- (void)remove;

- (GLfloat)scaleMax; // used for calculating frustum cull size
- (GLfloat)scaleX;
- (void)setScaleX:(GLfloat)factor;
- (GLfloat)scaleY;
- (void)setScaleY:(GLfloat)factor;
- (GLfloat)scaleZ;
- (void)setScaleZ:(GLfloat)factor;

// convenience for shaders
- (GLfloat)hullHeatLevel;
- (void)setHullHeatLevel:(GLfloat)value;
// shader properties
- (GLfloat)shaderFloat1;
- (void)setShaderFloat1:(GLfloat)value;
- (GLfloat)shaderFloat2;
- (void)setShaderFloat2:(GLfloat)value;
- (int)shaderInt1;
- (void)setShaderInt1:(int)value;
- (int)shaderInt2;
- (void)setShaderInt2:(int)value;
- (Vector)shaderVector1;
- (void)setShaderVector1:(Vector)value;
- (Vector)shaderVector2;
- (void)setShaderVector2:(Vector)value;

- (BOOL)isBreakPattern;
- (void)setIsBreakPattern:(BOOL)bp;

- (oo::PList)effectInfoDictionary;

@end
