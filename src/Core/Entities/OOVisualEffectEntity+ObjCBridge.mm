/*

OOVisualEffectEntity+ObjCBridge.mm

TRANSITIONAL (proposed ADR-0056, bead oo-ukxy8): the Objective-C OOVisualEffectEntity façade's own
methods: its initialisers, which make the C++ effect and run its body, and one-line forwarders to
cxx::OOVisualEffectEntity for its selectors (slices 1 and 2), the OOSubEntity and OOBeaconEntity
protocols and the subentity relationship. See OOVisualEffectEntity+ObjCBridge.h.

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

#import "OOColor.h"
#import "OOFlasherEntity.h"
#import "OOJSVisualEffect.h"
#import "OOMesh.h"
#import "OOVisualEffectEntity.h"
#import "ShipEntity.h"

@implementation OOVisualEffectEntity

- (id)init
{
    return [self cxx_initWithKey:std::string { } definition:oo::PList()];
}

// [[OOVisualEffectEntity alloc] cxx_initWithKey:definition:] (the universe): a C++ effect, then the
// initialiser's body (amendment oo-0mxi item 2), which may fail, as the Objective-C one did. Sent
// again, it keeps the C++ part and runs the body again.
- (id)cxx_initWithKey:(const std::string&)key definition:(const oo::PList&)dict
{
    if (_cxxEntity != nullptr)
        self = [super initWithCxxEntity:_cxxEntity.get()];
    else
        self = [super initWithCxxEntity:oo::makeRef<cxx::OOVisualEffectEntity>().get()];
    if (self == nil)
        return nil;

    if (!oo::ToCxx(self)->initWithKey(key, dict)) {
        [self release];
        return nil;
    }
    return self;
}

- (BOOL)setUpVisualEffectFromDictionary:(const oo::PList&)effectDict
{
    return oo::ToCxx(self)->setUpVisualEffectFromDictionary(effectDict);
}
- (OOMesh*)mesh
{
    return oo::ToCxx(self)->mesh();
}
- (void)setMesh:(OOMesh*)mesh
{
    oo::ToCxx(self)->setMesh(mesh);
}
- (std::optional<std::string>)effectKey
{
    return oo::ToCxx(self)->effectKey();
}
- (GLfloat)frustumRadius
{
    return oo::ToCxx(self)->frustumRadius();
}
- (void)clearSubEntities
{
    oo::ToCxx(self)->clearSubEntities();
}
- (BOOL)setUpSubEntities
{
    return oo::ToCxx(self)->setUpSubEntities();
}
- (void)removeSubEntity:(Entity<OOSubEntity>*)sub
{
    oo::ToCxx(self)->removeSubEntity(sub);
}
- (void)setNoDrawDistance
{
    oo::ToCxx(self)->setNoDrawDistance();
}
- (std::vector<oo::ObjCRef<Entity*>>)subEntities
{
    return oo::ToCxx(self)->subEntities();
}
- (NSUInteger)subEntityCount
{
    return oo::ToCxx(self)->subEntityCount();
}
- (std::optional<std::vector<oo::ObjCRef<OOVisualEffectEntity*>>>)visualEffectSubEntityEnumerator
{
    return oo::ToCxx(self)->visualEffectSubEntityEnumerator();
}
- (BOOL)hasSubEntity:(Entity<OOSubEntity>*)sub
{
    return oo::ToCxx(self)->hasSubEntity(sub);
}
- (std::vector<oo::ObjCRef<Entity*>>)subEntityEnumerator
{
    return oo::ToCxx(self)->subEntityEnumerator();
}
- (std::vector<oo::ObjCRef<OOVisualEffectEntity*>>)effectSubEntityEnumerator
{
    return oo::ToCxx(self)->effectSubEntityEnumerator();
}
- (std::vector<oo::ObjCRef<Entity*>>)flasherEnumerator
{
    return oo::ToCxx(self)->flasherEnumerator();
}
- (void)orientationChanged
{
    oo::ToCxx(self)->orientationChanged();
}
- (Vector)forwardVector
{
    return oo::ToCxx(self)->forwardVector();
}
- (Vector)rightVector
{
    return oo::ToCxx(self)->rightVector();
}
- (Vector)upVector
{
    return oo::ToCxx(self)->upVector();
}
- (GLfloat)scaleMax
{
    return oo::ToCxx(self)->scaleMax();
}
- (GLfloat)scaleX
{
    return oo::ToCxx(self)->scaleX();
}
- (void)setScaleX:(GLfloat)factor
{
    oo::ToCxx(self)->setScaleX(factor);
}
- (GLfloat)scaleY
{
    return oo::ToCxx(self)->scaleY();
}
- (void)setScaleY:(GLfloat)factor
{
    oo::ToCxx(self)->setScaleY(factor);
}
- (GLfloat)scaleZ
{
    return oo::ToCxx(self)->scaleZ();
}
- (void)setScaleZ:(GLfloat)factor
{
    oo::ToCxx(self)->setScaleZ(factor);
}
- (BOOL)isBreakPattern
{
    return oo::ToCxx(self)->isBreakPattern();
}
- (void)setIsBreakPattern:(BOOL)bp
{
    oo::ToCxx(self)->setIsBreakPattern(bp);
}
- (oo::PList)effectInfoDictionary
{
    return oo::ToCxx(self)->effectInfoDictionary();
}

- (OOColor*)scannerDisplayColor1
{
    return oo::ToObjC(oo::ToCxx(self)->scannerDisplayColor1());
}
- (OOColor*)scannerDisplayColor2
{
    return oo::ToObjC(oo::ToCxx(self)->scannerDisplayColor2());
}
- (void)setScannerDisplayColor1:(OOColor*)color
{
    oo::ToCxx(self)->setScannerDisplayColor1(oo::ToCxx(color));
}
- (void)setScannerDisplayColor2:(OOColor*)color
{
    oo::ToCxx(self)->setScannerDisplayColor2(oo::ToCxx(color));
}
- (GLfloat*)scannerDisplayColorForShip:(BOOL)flash scannerDisplayColor1:(OOColor*)scannerDisplayColor1 scannerDisplayColor2:(OOColor*)scannerDisplayColor2
{
    return oo::ToCxx(self)->scannerDisplayColorForShip(flash, oo::ToCxx(scannerDisplayColor1), oo::ToCxx(scannerDisplayColor2));
}

- (void)setScript:(const std::optional<std::string>&)script_name
{
    oo::ToCxx(self)->setScript(script_name);
}
- (OOJSScript*)script
{
    return oo::ToCxx(self)->script();
}
- (oo::PList)scriptInfo
{
    return oo::ToCxx(self)->scriptInfo();
}
- (void)doScriptEvent:(OOJSPropID)message
{
    oo::ToCxx(self)->doScriptEvent(message);
}
- (void)remove
{
    oo::ToCxx(self)->remove();
}

// OOBeaconEntity
- (OOComparisonResult)compareBeaconCodeWith:(Entity<OOBeaconEntity>*)other
{
    return oo::ToCxx(self)->compareBeaconCodeWith(other);
}
- (std::optional<std::string>)beaconCode
{
    return oo::ToCxx(self)->beaconCode();
}
- (void)setBeaconCode:(const std::optional<std::string>&)bcode
{
    oo::ToCxx(self)->setBeaconCode(bcode);
}
- (std::optional<std::string>)beaconLabel
{
    return oo::ToCxx(self)->beaconLabel();
}
- (void)setBeaconLabel:(const std::optional<std::string>&)blabel
{
    oo::ToCxx(self)->setBeaconLabel(blabel);
}
- (BOOL)isBeacon
{
    return oo::ToCxx(self)->isBeacon();
}
- (id<OOHUDBeaconIcon>)beaconDrawable
{
    return oo::ToCxx(self)->beaconDrawable();
}
- (Entity<OOBeaconEntity>*)prevBeacon
{
    return oo::ToCxx(self)->prevBeacon();
}
- (Entity<OOBeaconEntity>*)nextBeacon
{
    return oo::ToCxx(self)->nextBeacon();
}
- (void)setPrevBeacon:(Entity<OOBeaconEntity>*)beaconShip
{
    oo::ToCxx(self)->setPrevBeacon(beaconShip);
}
- (void)setNextBeacon:(Entity<OOBeaconEntity>*)beaconShip
{
    oo::ToCxx(self)->setNextBeacon(beaconShip);
}
- (BOOL)isJammingScanning
{
    return oo::ToCxx(self)->isJammingScanning();
}

// Shader bindable uniforms (the shader bindings send these by name to the façade).
- (GLfloat)hullHeatLevel
{
    return oo::ToCxx(self)->hullHeatLevel();
}
- (void)setHullHeatLevel:(GLfloat)value
{
    oo::ToCxx(self)->setHullHeatLevel(value);
}
- (GLfloat)shaderFloat1
{
    return oo::ToCxx(self)->shaderFloat1();
}
- (void)setShaderFloat1:(GLfloat)value
{
    oo::ToCxx(self)->setShaderFloat1(value);
}
- (GLfloat)shaderFloat2
{
    return oo::ToCxx(self)->shaderFloat2();
}
- (void)setShaderFloat2:(GLfloat)value
{
    oo::ToCxx(self)->setShaderFloat2(value);
}
- (int)shaderInt1
{
    return oo::ToCxx(self)->shaderInt1();
}
- (void)setShaderInt1:(int)value
{
    oo::ToCxx(self)->setShaderInt1(value);
}
- (int)shaderInt2
{
    return oo::ToCxx(self)->shaderInt2();
}
- (void)setShaderInt2:(int)value
{
    oo::ToCxx(self)->setShaderInt2(value);
}
- (Vector)shaderVector1
{
    return oo::ToCxx(self)->shaderVector1();
}
- (void)setShaderVector1:(Vector)value
{
    oo::ToCxx(self)->setShaderVector1(value);
}
- (Vector)shaderVector2
{
    return oo::ToCxx(self)->shaderVector2();
}
- (void)setShaderVector2:(Vector)value
{
    oo::ToCxx(self)->setShaderVector2(value);
}

// OOSubEntity
- (void)rescaleBy:(GLfloat)factor
{
    oo::ToCxx(self)->rescaleBy(factor);
}
- (void)rescaleBy:(GLfloat)factor writeToCache:(BOOL)writeToCache
{
    oo::ToCxx(self)->rescaleBy(factor, writeToCache);
}
- (void)drawSubEntityImmediate:(bool)immediate translucent:(bool)translucent
{
    oo::ToCxx(self)->drawSubEntityImmediate(immediate, translucent);
}

// The JS side, which the engine asks for by selector (Entity (OOJavaScriptExtensions)): the
// binding's category, moved here from the binding's bridge file, which it deletes. Each forwards to
// the OOJSVisualEffect.mm function that holds its old body; they become members of the C++ class
// with this facade's deletion.
- (JSClassID)oo_jsClassID
{
    return ::JSVisualEffectClassID();
}
- (std::optional<std::string>)cxx_oo_jsClassName
{
    return ::OOJSVisualEffectJSClassName();
}
- (BOOL)isVisibleToScripts
{
    return ::OOJSVisualEffectIsVisibleToScripts();
}
- (std::vector<oo::ObjCRef<Entity*>>)subEntitiesForScript
{
    return ::OOJSVisualEffectSubEntitiesForScript(self);
} // empty before the first subentity

@end

@implementation OOVisualEffectEntity (SubEntityRelationship)

- (BOOL)isShipWithSubEntityShip:(Entity*)other
{
    return oo::ToCxx(self)->isShipWithSubEntityShip(other);
}

@end
