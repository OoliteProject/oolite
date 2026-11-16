/*

OOVisualEffectEntity+ObjCBridge.h

TRANSITIONAL (proposed ADR-0056, bead oo-ukxy8; amendments oo-dnbf, oo-0mxi and oo-ubjo): the
Objective-C OOVisualEffectEntity, a façade over the C++ cxx::OOVisualEffectEntity
(OOVisualEffectEntity.h), for the code that still messages effects by selector (the universe, the
HUD, the scripting bindings, the shader bindings). Its interface is the one OOVisualEffectEntity.h declared before the conversion,
copied exactly (same selectors, same types); each forwards to its C++ member in one line
(OOVisualEffectEntity+ObjCBridge.mm). Slice 2 (bead oo-xkf6c) returned its selectors and the
OOBeaconEntity protocol to this interface. The façade is the entity's Objective-C object and owns its
C++ part (amendment oo-bj8). Imported as the last line of OOVisualEffectEntity.h; do not import it
directly. Deleted by its deletion bead once no file outside OOVisualEffectEntity.* names the
Objective-C class.

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

#ifndef OOVISUALEFFECTENTITY_OBJCBRIDGE_H
#define OOVISUALEFFECTENTITY_OBJCBRIDGE_H

@interface OOVisualEffectEntity : OOEntityWithDrawable <OOSubEntity, OOBeaconEntity>

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
- (std::vector<oo::ObjCRef<Entity*>>)flasherEnumerator; // flasher subentities, a snapshot (the C++ OOFlasherEntity's objects)

- (void)orientationChanged;
- (Vector)forwardVector;
- (Vector)rightVector;
- (Vector)upVector;

- (GLfloat)scaleMax; // used for calculating frustum cull size
- (GLfloat)scaleX;
- (void)setScaleX:(GLfloat)factor;
- (GLfloat)scaleY;
- (void)setScaleY:(GLfloat)factor;
- (GLfloat)scaleZ;
- (void)setScaleZ:(GLfloat)factor;

- (BOOL)isBreakPattern;
- (void)setIsBreakPattern:(BOOL)bp;

- (oo::PList)effectInfoDictionary;

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

@end

namespace oo {

// The root's crossings, typed (amendment oo-up4b item 3).
inline cxx::OOVisualEffectEntity* ToCxx(::OOVisualEffectEntity* entity)
{
    return static_cast<cxx::OOVisualEffectEntity*>(ToCxx(static_cast<::Entity*>(entity)));
}

inline ::OOVisualEffectEntity* ToObjC(cxx::OOVisualEffectEntity* entity)
{
    return (::OOVisualEffectEntity*)ToObjC(static_cast<cxx::Entity*>(entity));
}

} // namespace oo

#endif // OOVISUALEFFECTENTITY_OBJCBRIDGE_H
