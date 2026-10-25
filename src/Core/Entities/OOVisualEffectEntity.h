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

#include "OOEntityWithDrawable.h"
#include "ooscript/JSEngine.hpp"
#include "OOPlanetEntity.h"
#include "OOJSPropID.h"
#include "HeadUpDisplay.h"
#include "OOColor.h"
#include "OOPolygonSprite.h"	// OOHUDBeaconIcon (bead oo-7ae4p): the beacon drawable is oo::Ref

#include "oofnd/StdLib.hpp"
#include "oofnd/PList.hpp"

class OOMesh;	// C++ since bead oo-9ht.132
#include "OOScript.h"	// oo::Ref<OOScript> members and results (bead oo-9ht.133)
class OOColor;
class OOFlasherEntity;	// C++ only since bead oo-9ht.107


/*	Foundation sweep (proposed ADR-0043, bead oo-ensq). The effect definition and script_info are
	oo::PLists (script_info null where it was nil); the effect key and beacon strings are
	std::optional (nullopt where they were nil). The subentity list is nullopt until the first
	subentity is added and again after -clearSubEntities, as the array was nil. -subEntities /
	-subEntityEnumerator / -flasherEnumerator return std::vector snapshots (empty where the
	array was nil).
*/
// A subentity, as the class names it from inside namespace cxx (where Entity is the C++ root).
using OOVisualEffectSubEntities = std::vector<oo::EntityHold>;





/*	A visual effect (bead oo-ukxy8, slice 1 of docs/phases/3-slices/OOVisualEffectEntity.md): the
	class shell, its state and the entity side (construction from the effect definition, the mesh,
	subentities and flashers, scaling, orientation vectors, drawing, update, the break pattern flag,
	the subentity relationship), and its scripted surface (bead oo-xkf6c, slice 2: scanner colours,
	the script and its events, the beacons and the shader uniforms).
*/
/*	Since bead oo-9ht.165 the global C++ class, with no Objective-C class of its own: an effect's
	Objective-C object is the root's facade (OOEntityWithDrawable's until bead oo-9ht.40), made by oo::NewVisualEffectObject(), and
	the selectors found on it by name are the root's facade's (Entity
	(OOVisualEffectSelectorsCalledByName), ADR-0056 amendment oo-9ht.165).
*/
class OOVisualEffectEntity : public OOEntityWithDrawable, public cxx::OOSubEntityInterface	// <OOSubEntity, OOBeaconEntity>
{
public:
	~OOVisualEffectEntity();

	/*	-cxx_initWithKey:definition:'s body after [super init] (the constructor ran Entity's): false
		where the initialiser released itself and answered nil. oo::NewVisualEffectObject() runs it
		once the object holds this effect (amendment oo-0mxi item 2; bead oo-9ht.165).
	*/
	bool initWithKey(const std::string &key, const oo::PList &dict);
	bool setUpVisualEffectFromDictionary(const oo::PList &effectDict);

	::OOMesh *mesh();
	void setMesh(::OOMesh *mesh);

	std::optional<std::string> effectKey();

	GLfloat frustumRadius() override;

	void clearSubEntities();
	bool setUpSubEntities();
	void removeSubEntity(Entity *sub);	// the C++ sub-entity (bead oo-9ht.39.8.13; the list holds it since bead oo-xn1j1)
	void setNoDrawDistance();
	std::vector<oo::EntityHold> subEntities();	// a snapshot; empty before the first subentity (was nil)
	NSUInteger subEntityCount();
	std::optional<std::vector<oo::EntityHold>> visualEffectSubEntityEnumerator();	// the visual-effect subentities' objects; nullopt where the array was nil
	bool hasSubEntity(Entity *sub);	// the C++ entity's (bead oo-w9pi2)

	std::vector<oo::EntityHold> subEntityEnumerator();	// snapshot, same as subEntities()
	std::vector<oo::EntityHold> effectSubEntityEnumerator();	// the visual-effect subentities' objects
	std::vector<oo::EntityHold> flasherEnumerator();	// flasher subentities' objects (the nearest façade left), a snapshot

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

	// OOSubEntity: owners call these through cxx::OOSubEntityInterface (bead oo-9ht.165).
	void rescaleBy(GLfloat factor) override;
	void rescaleBy(GLfloat factor, bool writeToCache) override;
	void drawSubEntityImmediate(bool immediate, bool translucent) override;

	// Entity (SubEntityRelationship): the root's facade answers it for an effect's part.
	bool isShipWithSubEntityShip(Entity *other);	// the C++ entity (bead oo-w9pi2; was its object)

	bool isEffect() override;
	bool getIsVisualEffect() override;
	bool canCollide() override;
	GLfloat collisionRadius() override;
	void drawImmediate(bool immediate, bool translucent) override;
	void update(OOTimeDelta delta_t) override;

	// The JS questions the engine asks the object (Entity (OOJavaScriptExtensions)), which the
	// effect's facade answered until bead oo-9ht.165: the binding's functions (OOJSVisualEffect.h).
	void getJSClass(ooscript::ClassDef **outClass, ooscript::Object *outPrototype) override;
	std::optional<std::string> jsClassName() override;
	bool isVisibleToScripts() override;

	OOColor *scannerDisplayColor1();
	OOColor *scannerDisplayColor2();
	void setScannerDisplayColor1(OOColor *color);
	void setScannerDisplayColor2(OOColor *color);
	GLfloat *scannerDisplayColorForShip(bool flash, OOColor *scannerDisplayColor1, OOColor *scannerDisplayColor2);

	void setScript(const std::optional<std::string> &script_name);
	::OOScript *script();
	oo::PList scriptInfo();
	void doScriptEvent(ooscript::PropertyId message);
	void remove();

	// OOBeaconEntity: the root's facade (Entity (OOWaypointBeacon)) answers it for an effect's part.
	OOComparisonResult compareBeaconCodeWith(Entity *other);
	std::optional<std::string> beaconCode();
	void setBeaconCode(const std::optional<std::string> &bcode);
	std::optional<std::string> beaconLabel();
	void setBeaconLabel(const std::optional<std::string> &blabel);
	bool isBeacon();
	OOHUDBeaconIcon *beaconDrawable();	// borrowed (the protocol type until bead oo-7ae4p)
	Entity *prevBeacon();	// the C++ entity since bead oo-9ht.39.24 (null once its object has gone, as before)
	Entity *nextBeacon();
	void setPrevBeacon(Entity *beaconShip);
	void setNextBeacon(Entity *beaconShip);
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
	std::optional<OOVisualEffectSubEntities>	_subEntities;	// was subEntities, named like its getter

	oo::PList				effectinfoDictionary;

	GLfloat					_profileRadius = {}; // for frustum culling

	oo::Ref<OOColor>	scanner_display_color1;
	oo::Ref<OOColor>	scanner_display_color2;

	GLfloat         _hullHeatLevel = {};
	GLfloat         _shaderFloat1 = {};
	GLfloat         _shaderFloat2 = {};
	int             _shaderInt1 = {};
	int             _shaderInt2 = {};
	Vector          _shaderVector1 = {};
	Vector          _shaderVector2 = {};

	Vector _v_forward = {};
	Vector _v_up = {};
	Vector _v_right = {};

	oo::Ref<OOScript> _script;	// was script, named like its getter
	oo::PList				_scriptInfo;	// was scriptInfo, named like its getter

	std::optional<std::string>	_effectKey;

	bool            _haveExecutedSpawnAction = {};

	// beacons
	std::optional<std::string>	_beaconCode;
	std::optional<std::string>	_beaconLabel;
	oo::WeakRef<Entity>	_prevBeacon;	// the beacons' C++ parts (bead oo-9ht.39.5.2; were their objects' weak references)
	oo::WeakRef<Entity>	_nextBeacon;
	oo::Ref<OOHUDBeaconIcon>	_beaconDrawable;

	// scaling (were scaleX, scaleY, scaleZ, named like their getters)
	GLfloat _scaleX = {};
	GLfloat _scaleY = {};
	GLfloat _scaleZ = {};

private:
	void addSubEntity(Entity *sub);
	bool setUpOneSubentity(const oo::PList &subentDict);
	bool setUpOneFlasher(const oo::PList &subentDict);
	bool setUpOneStandardSubentity(const oo::PList &subentDict);
};



namespace oo {

// A new effect (bead oo-9ht.165) after the effect's initialiser body (OOVisualEffectEntity::initWithKey()),
// made as its object was (oo::MadeEntityRetained(); bead oo-dpyk8); null where the body failed, as
// [[OOVisualEffectEntity alloc] cxx_initWithKey:definition:] answered nil. +1, as +alloc gave.
Entity *NewVisualEffect(const std::string &key, const oo::PList &dict);

// The effect an entity is: nullptr for null or another entity (what -isKindOfClass:
// [OOVisualEffectEntity class] and the cast after it found; bead oo-9ht.39.3).
inline OOVisualEffectEntity *ToEffect(Entity *entity)
{
	return dynamic_cast<OOVisualEffectEntity *>(entity);
}

}	// namespace oo
