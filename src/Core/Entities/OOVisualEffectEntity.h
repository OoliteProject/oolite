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
#import "OOColor.h"
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
// A subentity, as the class names it from inside namespace cxx (where Entity is the C++ root).
typedef Entity<OOSubEntity> OOVisualEffectSubEntity;
typedef Entity<OOBeaconEntity> OOVisualEffectBeaconEntity;
using OOVisualEffectSubEntities = std::vector<oo::ObjCRef<Entity<OOSubEntity>*>>;

@class OOVisualEffectEntity; // the façade (OOVisualEffectEntity+ObjCBridge.h)

namespace cxx {

/*	A visual effect (bead oo-ukxy8, slice 1 of docs/phases/3-slices/OOVisualEffectEntity.md): the
        class shell, its state and the entity side (construction from the effect definition, the mesh,
        subentities and flashers, scaling, orientation vectors, drawing, update, the break pattern flag,
        the subentity relationship), and its scripted surface (bead oo-xkf6c, slice 2: scanner colours,
        the script and its events, the beacons and the shader uniforms).
*/
class OOVisualEffectEntity : public OOEntityWithDrawable {
public:
    ~OOVisualEffectEntity();

    /*	-cxx_initWithKey:definition:'s body after [super init] (the constructor ran Entity's): false
            where the initialiser released itself and answered nil. The façade runs it once it holds this
            object (amendment oo-0mxi item 2), because the universe allocates effects.
    */
    bool initWithKey(const std::string& key, const oo::PList& dict);
    bool setUpVisualEffectFromDictionary(const oo::PList& effectDict);

    ::OOMesh* mesh();
    void setMesh(::OOMesh* mesh);

    std::optional<std::string> effectKey();

    GLfloat frustumRadius() override;

    void clearSubEntities();
    bool setUpSubEntities();
    void removeSubEntity(OOVisualEffectSubEntity* sub);
    void setNoDrawDistance();
    std::vector<oo::ObjCRef<::Entity*>> subEntities(); // a snapshot; empty before the first subentity (was nil)
    NSUInteger subEntityCount();
    std::optional<std::vector<oo::ObjCRef<::OOVisualEffectEntity*>>> visualEffectSubEntityEnumerator(); // the visual-effect subentities; nullopt where the array was nil
    bool hasSubEntity(OOVisualEffectSubEntity* sub);

    std::vector<oo::ObjCRef<::Entity*>> subEntityEnumerator(); // snapshot, same as subEntities()
    std::vector<oo::ObjCRef<::OOVisualEffectEntity*>> effectSubEntityEnumerator();
    std::vector<oo::ObjCRef<::OOFlasherEntity*>> flasherEnumerator(); // flasher subentities, a snapshot

    void orientationChanged() override;
    Vector forwardVector();
    Vector rightVector();
    Vector upVector();

    GLfloat scaleMax(); // used for calculating frustum cull size
    GLfloat scaleX();
    void setScaleX(GLfloat factor);
    GLfloat scaleY();
    void setScaleY(GLfloat factor);
    GLfloat scaleZ();
    void setScaleZ(GLfloat factor);

    bool isBreakPattern();
    void setIsBreakPattern(bool bp);

    oo::PList effectInfoDictionary();

    // OOSubEntity, answered by the façade.
    void rescaleBy(GLfloat factor);
    void rescaleBy(GLfloat factor, bool writeToCache);
    void drawSubEntityImmediate(bool immediate, bool translucent);

    // Entity (SubEntityRelationship), answered by the façade.
    bool isShipWithSubEntityShip(::Entity* other);

    bool isEffect() override;
    bool getIsVisualEffect() override;
    bool canCollide() override;
    GLfloat collisionRadius() override;
    void drawImmediate(bool immediate, bool translucent) override;
    void update(OOTimeDelta delta_t) override;

    cxx::OOColor* scannerDisplayColor1();
    cxx::OOColor* scannerDisplayColor2();
    void setScannerDisplayColor1(cxx::OOColor* color);
    void setScannerDisplayColor2(cxx::OOColor* color);
    GLfloat* scannerDisplayColorForShip(bool flash, cxx::OOColor* scannerDisplayColor1, cxx::OOColor* scannerDisplayColor2);

    void setScript(const std::optional<std::string>& script_name);
    ::OOJSScript* script();
    oo::PList scriptInfo();
    void doScriptEvent(OOJSPropID message);
    void remove();

    // OOBeaconEntity, answered by the façade.
    OOComparisonResult compareBeaconCodeWith(OOVisualEffectBeaconEntity* other);
    std::optional<std::string> beaconCode();
    void setBeaconCode(const std::optional<std::string>& bcode);
    std::optional<std::string> beaconLabel();
    void setBeaconLabel(const std::optional<std::string>& blabel);
    bool isBeacon();
    id<OOHUDBeaconIcon> beaconDrawable();
    OOVisualEffectBeaconEntity* prevBeacon();
    OOVisualEffectBeaconEntity* nextBeacon();
    void setPrevBeacon(OOVisualEffectBeaconEntity* beaconShip);
    void setNextBeacon(OOVisualEffectBeaconEntity* beaconShip);
    bool isJammingScanning();

    // convenience for shaders
    GLfloat hullHeatLevel();
    void setHullHeatLevel(GLfloat value);
    // shader properties
    GLfloat shaderFloat1();
    void setShaderFloat1(GLfloat value);
    GLfloat shaderFloat2();
    void setShaderFloat2(GLfloat value);
    int shaderInt1();
    void setShaderInt1(int value);
    int shaderInt2();
    void setShaderInt2(int value);
    Vector shaderVector1();
    void setShaderVector1(Vector value);
    Vector shaderVector2();
    void setShaderVector2(Vector value);

    // The state, public as the class shell left it (the test reads some of it).
    std::optional<OOVisualEffectSubEntities> _subEntities; // was subEntities, named like its getter

    oo::PList effectinfoDictionary;

    GLfloat _profileRadius = { }; // for frustum culling

    oo::Ref<cxx::OOColor> scanner_display_color1;
    oo::Ref<cxx::OOColor> scanner_display_color2;

    GLfloat _hullHeatLevel = { };
    GLfloat _shaderFloat1 = { };
    GLfloat _shaderFloat2 = { };
    int _shaderInt1 = { };
    int _shaderInt2 = { };
    Vector _shaderVector1 = { };
    Vector _shaderVector2 = { };

    Vector _v_forward = { };
    Vector _v_up = { };
    Vector _v_right = { };

    ::OOJSScript* _script = { }; // retained; was script, named like its getter
    oo::PList _scriptInfo; // was scriptInfo, named like its getter

    std::optional<std::string> _effectKey;

    bool _haveExecutedSpawnAction = { };

    // beacons
    std::optional<std::string> _beaconCode;
    std::optional<std::string> _beaconLabel;
    ::OOWeakReference* _prevBeacon = { };
    ::OOWeakReference* _nextBeacon = { };
    id<OOHUDBeaconIcon> _beaconDrawable = { }; // retained

    // scaling (were scaleX, scaleY, scaleZ, named like their getters)
    GLfloat _scaleX = { };
    GLfloat _scaleY = { };
    GLfloat _scaleZ = { };

private:
    void addSubEntity(OOVisualEffectSubEntity* sub);
    bool setUpOneSubentity(const oo::PList& subentDict);
    bool setUpOneFlasher(const oo::PList& subentDict);
    bool setUpOneStandardSubentity(const oo::PList& subentDict);
};

} // namespace cxx

// Transitional: the Objective-C OOVisualEffectEntity, for code not yet converted. Deleted, with
// namespace cxx above, by the bridge's deletion bead.
#import "OOVisualEffectEntity+ObjCBridge.h"
