/*

OOVisualEffectEntity.m


Oolite
Copyright (C) 2004-2013 Giles C Williams and contributors

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the impllied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
MA 02110-1301, USA.

*/

#include "OOVisualEffectEntity.h"

#include "OOMaths.h"
#include "Universe.h"
#include "OOShaderMaterial.h"
#include "OOOpenGLExtensionManager.h"

#include "ResourceManager.h"
#include "OOStringParsing.h"
#include "OOStringExpander.h"
#include "OOConstToString.h"
#include "OOConstToJSString.h"

#include "OOMesh.h"

#include "OOColor.h"
#include "OOPolygonSprite.h"
#include "HeadUpDisplay.h"

#include "OOFlasherEntity.h"

#include "OODebugGLDrawing.h"
#include "OODebugFlags.h"

#include "OOJSScript.h"
#include "OOJSVisualEffect.h"


#include "MyOpenGLView.h"
#include "OOPListGameTypes.h"

#include "oofnd/PListGet.hpp"
#include "OOObjCPList.h"
#include "oofnd/String.hpp"


namespace {

// -objectForKey: as plist data (a null PList when absent), for +cxx_colorWithDescription:.
oo::PList ValueForKey(const oo::PList &dict, std::string_view key)
{
	const oo::PList *value = dict.find(key);
	return value != nullptr ? *value : oo::PList();
}


// get<std::string> where the Foundation code read nil: std::nullopt when the key is absent or its
// value is neither a string nor a number.
std::optional<std::string> OptionalStringForKey(const oo::PList &dict, std::string_view key)
{
	const oo::PList *value = dict.find(key);
	if (value == nullptr || !(value->isString() || value->isNumber()))  return std::nullopt;
	return dict.get<std::string>(key);
}


// get<PList::Dict>: the dictionary, or null (nil).
oo::PList DictionaryForKey(const oo::PList &dict, std::string_view key)
{
	const oo::PList *value = dict.get<oo::PList::Dict>(key);
	return value != nullptr ? *value : oo::PList();
}


// A copy of the subentity list to walk (the Foundation code walked a copy of the array).
OOVisualEffectSubEntities SubEntitiesOf(const std::optional<OOVisualEffectSubEntities> &subEntities)
{
	return subEntities.value_or(OOVisualEffectSubEntities{});
}


// The subentities that answer YES to -isVisualEffect.
std::vector<oo::EntityHold> VisualEffectsIn(const OOVisualEffectSubEntities &subEntities)
{
	std::vector<oo::EntityHold> result;
	for (const auto &sub : subEntities)
	{
		if (!sub.get()->getIsVisualEffect())  continue;	// -isVisualEffect, through the converted root
		result.push_back(sub);
	}
	return result;
}

}	// namespace


// [[OOVisualEffectEntity alloc] cxx_initWithKey:definition:] until bead oo-9ht.165 deleted the
// effect's facade: the root's facade (OOEntityWithDrawable's until bead oo-9ht.40) holding a new effect (+1, as +alloc gave), then
// the initialiser's body, which may fail, as the Objective-C one did.
Entity *oo::NewVisualEffect(const std::string &key, const oo::PList &dict)
{
	const Ref<OOVisualEffectEntity> effect = makeRef<OOVisualEffectEntity>();
	MadeEntityRetained(effect);	// +1, as +alloc gave (its object's, until bead oo-dpyk8)
	if (!effect->initWithKey(key, dict))
	{
		ReleaseEntity(effect.get());
		return nullptr;
	}
	return effect.get();
}


/*	-cxx_initWithKey:definition:'s body after [super init] (the constructor ran Entity's).
	oo::NewVisualEffect() runs it once the effect is made (amendment oo-0mxi item 2);
	false where the initialiser released itself and answered nil.
*/
bool OOVisualEffectEntity::initWithKey(const std::string &key, const oo::PList &dict)
{
	OOJS_PROFILE_ENTER

	_effectKey = key;

	if (!setUpVisualEffectFromDictionary(dict))
	{
		return false;
	}

	_haveExecutedSpawnAction = false;

	return true;

	OOJS_PROFILE_EXIT
}


bool OOVisualEffectEntity::setUpVisualEffectFromDictionary(const oo::PList &effectDict)
{
	OOJS_PROFILE_ENTER

	effectinfoDictionary = effectDict;
	if (effectinfoDictionary.isNull())  effectinfoDictionary = oo::PList(oo::PList::Dict{});

	orientation = kIdentityQuaternion;
	rotMatrix	= kIdentityMatrix;

	collision_radius = 0.0;

	const std::optional<std::string> modelName = OptionalStringForKey(effectDict, "model");
	if (modelName.has_value())
	{
		const oo::Ref<::OOMesh> mesh = ::OOMesh::meshWithName(*modelName,
								   _effectKey,
								   DictionaryForKey(effectDict, "materials"),
								   DictionaryForKey(effectDict, "shaders"),
								   effectDict.get<bool>("smooth", false),
								   OODefaultShipShaderMacros(),
								   this);	// the C++ effect (bead oo-9ht.39.6)
		if (mesh == nullptr)  return false;
		setMesh(mesh.get());
	}

	isImmuneToBreakPatternHide = effectDict.get<bool>("is_break_pattern");
	_scaleX = 1.0;
	_scaleY = 1.0;
	_scaleZ = 1.0;

	clearSubEntities();
	setUpSubEntities();

	setScannerDisplayColor1(nullptr);
	setScannerDisplayColor2(nullptr);

	scanClass = CLASS_VISUAL_EFFECT;

	setStatus(STATUS_EFFECT);

	_hullHeatLevel = 60.0 / 256.0;
	_shaderFloat1 = 0.0;
	_shaderFloat2 = 0.0;
	_shaderInt1 = 0;
	_shaderInt2 = 0;
	_shaderVector1 = kZeroVector;
	_shaderVector2 = kZeroVector;

	setBeaconCode(OptionalStringForKey(effectDict, "beacon"));
	const std::optional<std::string> beaconLabel = OptionalStringForKey(effectDict, "beacon_label");
	setBeaconLabel(beaconLabel.has_value() ? beaconLabel : this->beaconCode());

	const oo::PList *scriptInfoValue = effectDict.get<oo::PList::Dict>("script_info");
	_scriptInfo = scriptInfoValue != nullptr ? *scriptInfoValue : oo::PList();
	setScript(OptionalStringForKey(effectDict, "script"));

	return true;

	OOJS_PROFILE_EXIT
}


OOVisualEffectEntity::~OOVisualEffectEntity()
{
	clearSubEntities();
	scanner_display_color1 = nullptr;
	scanner_display_color2 = nullptr;
	_script = nullptr;
	_beaconDrawable = nullptr;
}


bool OOVisualEffectEntity::isEffect()
{
	return true;
}


bool OOVisualEffectEntity::getIsVisualEffect()
{
	return true;
}


bool OOVisualEffectEntity::canCollide()
{
	return false;
}


::OOMesh *OOVisualEffectEntity::mesh()
{
	return static_cast<::OOMesh *>(getDrawable());	// an effect's drawable is its mesh
}


void OOVisualEffectEntity::setMesh(::OOMesh *mesh)
{
	if (mesh != this->mesh())
	{
		setDrawable(mesh);
	}
}


std::optional<std::string> OOVisualEffectEntity::effectKey()
{
	return _effectKey;
}


GLfloat OOVisualEffectEntity::frustumRadius()
{
	return scaleMax() * _profileRadius;
}


void OOVisualEffectEntity::clearSubEntities()
{
	for (const auto &sub : SubEntitiesOf(_subEntities))  { if (sub.get() != nullptr)  sub.get()->setOwner(nullptr); }	// Ensure backlinks are broken
	_subEntities.reset();

	// reset size & mass!
	if (mesh())
	{
		collision_radius = findCollisionRadius();
	}
	else
	{
		collision_radius = 0.0;
	}
	_profileRadius = collision_radius;
}


bool OOVisualEffectEntity::setUpSubEntities()
{
	unsigned int	i;
	_profileRadius = collision_radius;
	const oo::PList *subs = effectinfoDictionary.get<oo::PList::Array>("subentities");

	for (i = 0; subs != nullptr && i < subs->count(); i++)
	{
		const oo::PList *subentDict = subs->at<oo::PList::Dict>(i);	// nil for anything but a dictionary
		setUpOneSubentity(subentDict != nullptr ? *subentDict : oo::PList());
	}

	setNoDrawDistance();

	return true;
}


// The list holds the sub-entities (bead oo-xn1j1); [sub setOwner:nil] first, as before.
void OOVisualEffectEntity::removeSubEntity(Entity *sub)
{
	if (sub != nullptr)  sub->setOwner(nullptr);
	if (_subEntities.has_value())  std::erase_if(*_subEntities, [sub](const auto &entry) { return entry.get() == sub; });
}


void OOVisualEffectEntity::setNoDrawDistance()
{
	GLfloat r = _profileRadius * scaleMax();
	no_draw_distance = r * r * NO_DRAW_DISTANCE_FACTOR * NO_DRAW_DISTANCE_FACTOR * 2.0;

}


bool OOVisualEffectEntity::setUpOneSubentity(const oo::PList &subentDict)
{
	const std::optional<std::string> type = OptionalStringForKey(subentDict, "type");
	if (type == "flasher")
	{
		return setUpOneFlasher(subentDict);
	}
	else
	{
		return setUpOneStandardSubentity(subentDict);
	}


}


bool OOVisualEffectEntity::setUpOneFlasher(const oo::PList &subentDict)
{
	// C++ since bead oo-9ht.107: the flasher's object is the nearest façade left.
	Entity *flasher = oo::MadeEntity(OOFlasherEntity::flasherWithDictionary(subentDict));
	if (flasher != nullptr)  flasher->setPosition(subentDict ? OOHPVectorFromPList(subentDict.find("position"), kZeroHPVector) : kZeroHPVector);
	addSubEntity(flasher);
	return true;
}


bool OOVisualEffectEntity::setUpOneStandardSubentity(const oo::PList &subentDict)
{
	Entity		*subentity = nullptr;	// the effect, its object +1 (beads oo-9ht.165, oo-9ht.39.26)
	std::optional<std::string>	subentKey;
	HPVector				subPosition;
	Quaternion			subOrientation;

	subentKey = OptionalStringForKey(subentDict, "subentity_key");
	if (!subentKey.has_value()) {
		OO_LOG("setup.visualeffect.badEntry.subentities", "Failed to set up entity - no subentKey in {}", oo::DescriptionOf(subentDict));
		return false;
	}

	subentity = (UNIVERSE != nullptr ? UNIVERSE->newVisualEffectWithName(*subentKey) : nullptr);
	if (subentity == nullptr) {
		OO_LOG("setup.visualeffect.badEntry.subentities", "Failed to set up entity {}", *subentKey);
		return false;
	}

	subPosition = OOHPVectorFromPList(subentDict.find("position"), kZeroHPVector);
	subOrientation = OOQuaternionFromPList(subentDict.find("orientation"), kIdentityQuaternion);

	subentity->setPosition(subPosition);
	subentity->setOrientation(subOrientation);

	addSubEntity(subentity);

	oo::ReleaseEntity(subentity);

	return true;
}


void OOVisualEffectEntity::addSubEntity(Entity *sub)
{
	if (sub == nullptr)  return;

	if (!_subEntities.has_value())  _subEntities.emplace();
	sub->isSubEntity = true;
	// Order matters - need consistent state in setOwner:. -- Ahruman 2008-04-20
	_subEntities->emplace_back(sub);
	sub->setOwner(this);

	double distance = HPmagnitude(sub->getPosition()) + sub->findCollisionRadius();
	if (distance > _profileRadius)
	{
		_profileRadius = distance;
	}
}


std::vector<oo::EntityHold> OOVisualEffectEntity::subEntities()
{
	if (!_subEntities.has_value())  return {};
	std::vector<oo::EntityHold> result;
	result.reserve(_subEntities->size());
	for (const auto &sub : *_subEntities)
	{
		result.push_back(sub);
	}
	return result;
}


NSUInteger OOVisualEffectEntity::subEntityCount()
{
	return _subEntities.has_value() ? _subEntities->size() : 0;
}


std::optional<std::vector<oo::EntityHold>> OOVisualEffectEntity::visualEffectSubEntityEnumerator()
{
	if (!_subEntities.has_value())  return std::nullopt;
	return VisualEffectsIn(*_subEntities);
}


bool OOVisualEffectEntity::hasSubEntity(Entity *subPart)
{
	if (!_subEntities.has_value())  return false;
	return std::find_if(_subEntities->begin(), _subEntities->end(), [subPart](const auto &entry) { return entry.get() == subPart; }) != _subEntities->end();
}


std::vector<oo::EntityHold> OOVisualEffectEntity::subEntityEnumerator()
{
	return subEntities();
}


std::vector<oo::EntityHold> OOVisualEffectEntity::effectSubEntityEnumerator()
{
	return VisualEffectsIn(SubEntitiesOf(_subEntities));
}


std::vector<oo::EntityHold> OOVisualEffectEntity::flasherEnumerator()
{
	std::vector<oo::EntityHold> flashers;
	if (!_subEntities.has_value())  return flashers;
	for (const auto &sub : *_subEntities)
	{
		if (dynamic_cast<OOFlasherEntity *>(sub.get()) == nullptr)  continue;
		flashers.push_back(sub);
	}
	return flashers;
}


void OOVisualEffectEntity::drawSubEntityImmediate(bool immediate, bool translucent)
{
	if (cam_zero_distance > no_draw_distance) // this test provides an opportunity to do simple LoD culling
	{
		return; // TOO FAR AWAY
	}
	OOGLPushModelView();
	// HPVect: camera position
	OOGLTranslateModelView(HPVectorToVector(position));
	OOGLMultModelView(rotMatrix);
	drawImmediate(immediate, translucent);

	OOGLPopModelView();
}


void OOVisualEffectEntity::rescaleBy(GLfloat factor)
{
	if (mesh() != nullptr) {
		setMesh(mesh()->meshRescaledBy(factor).get());
	}

	// rescale subentities
	Entity	*se = nullptr;
	for (const auto &seRef : SubEntitiesOf(_subEntities))
	{
		se = seRef.get();
		if (se == nullptr)  continue;	// every message went to nil
		se->setPosition(HPvector_multiply_scalar(se->getPosition(), factor));
		if (OOSubEntityInterface *cxxSub = dynamic_cast<OOSubEntityInterface *>(se))  cxxSub->rescaleBy(factor);
		// (else: none - every effect sub-entity adopts the interface; bead oo-dpyk8)
	}

	collision_radius *= factor;
	_profileRadius *= factor;
}


void OOVisualEffectEntity::rescaleBy(GLfloat /*factor*/, bool /*writeToCache*/)
{
	/* Do nothing; this is only needed because of OOEntityWithDrawable
	   implementation requirements */
}


GLfloat OOVisualEffectEntity::scaleMax()
{
	GLfloat scale = 1.0;
	if (_scaleX > _scaleY)
	{
		if (_scaleX > _scaleZ)
		{
			scale *= _scaleX;
		}
		else
		{
			scale *= _scaleZ;
		}
	}
	else if (_scaleY > _scaleZ)
	{
		scale *= _scaleY;
	}
	else
	{
		scale *= _scaleZ;
	}
	return scale;
}

GLfloat OOVisualEffectEntity::scaleX()
{
	return _scaleX;
}


void OOVisualEffectEntity::setScaleX(GLfloat factor)
{
	// rescale subentities
	Entity	*se = nullptr;
	GLfloat flasher_factor = pow(factor/_scaleX,1.0/3.0);
	for (const auto &seRef : SubEntitiesOf(_subEntities))
	{
		se = seRef.get();
		if (se == nullptr)  continue;	// every message went to nil
		HPVector move = se->getPosition();
		move.x *= factor/_scaleX;
		se->setPosition(move);
		if (se->getIsVisualEffect())
		{
			oo::ToEffect(se)->setScaleX(factor);
		}
		else if (OOSubEntityInterface *cxxSub = dynamic_cast<OOSubEntityInterface *>(se))
		{
			cxxSub->rescaleBy(flasher_factor);
		}
		else
		{
			if (OOSubEntityInterface *cxxSub = dynamic_cast<OOSubEntityInterface *>(se))  cxxSub->rescaleBy(flasher_factor);	// every effect sub-entity adopts it (bead oo-dpyk8)
		}
	}

	_scaleX = factor;
	setNoDrawDistance();
}


GLfloat OOVisualEffectEntity::scaleY()
{
	return _scaleY;
}


void OOVisualEffectEntity::setScaleY(GLfloat factor)
{
	// rescale subentities
	Entity	*se = nullptr;
	GLfloat flasher_factor = pow(factor/_scaleY,1.0/3.0);
	for (const auto &seRef : SubEntitiesOf(_subEntities))
	{
		se = seRef.get();
		if (se == nullptr)  continue;	// every message went to nil
		HPVector move = se->getPosition();
		move.y *= factor/_scaleY;
		se->setPosition(move);
		if (se->getIsVisualEffect())
		{
			oo::ToEffect(se)->setScaleY(factor);
		}
		else if (OOSubEntityInterface *cxxSub = dynamic_cast<OOSubEntityInterface *>(se))
		{
			cxxSub->rescaleBy(flasher_factor);
		}
		else
		{
			if (OOSubEntityInterface *cxxSub = dynamic_cast<OOSubEntityInterface *>(se))  cxxSub->rescaleBy(flasher_factor);	// every effect sub-entity adopts it (bead oo-dpyk8)
		}
	}

	_scaleY = factor;
	setNoDrawDistance();
}


GLfloat OOVisualEffectEntity::scaleZ()
{
	return _scaleZ;
}


void OOVisualEffectEntity::setScaleZ(GLfloat factor)
{
	// rescale subentities
	Entity	*se = nullptr;
	GLfloat flasher_factor = pow(factor/_scaleZ,1.0/3.0);
	for (const auto &seRef : SubEntitiesOf(_subEntities))
	{
		se = seRef.get();
		if (se == nullptr)  continue;	// every message went to nil
		HPVector move = se->getPosition();
		move.z *= factor/_scaleZ;
		se->setPosition(move);
		if (se->getIsVisualEffect())
		{
			oo::ToEffect(se)->setScaleZ(factor);
		}
		else if (OOSubEntityInterface *cxxSub = dynamic_cast<OOSubEntityInterface *>(se))
		{
			cxxSub->rescaleBy(flasher_factor);
		}
		else
		{
			if (OOSubEntityInterface *cxxSub = dynamic_cast<OOSubEntityInterface *>(se))  cxxSub->rescaleBy(flasher_factor);	// every effect sub-entity adopts it (bead oo-dpyk8)
		}
	}

	_scaleZ = factor;
	setNoDrawDistance();
}


GLfloat OOVisualEffectEntity::collisionRadius()
{
	return scaleMax() * collision_radius;
}


void OOVisualEffectEntity::orientationChanged()
{
	OOEntityWithDrawable::orientationChanged();

	_v_forward   = vector_forward_from_quaternion(orientation);
	_v_up		= vector_up_from_quaternion(orientation);
	_v_right		= vector_right_from_quaternion(orientation);
}


// exposed to shaders
Vector OOVisualEffectEntity::forwardVector()
{
	return _v_forward;
}


// exposed to shaders
Vector OOVisualEffectEntity::upVector()
{
	return _v_up;
}


// exposed to shaders
Vector OOVisualEffectEntity::rightVector()
{
	return _v_right;
}


void OOVisualEffectEntity::drawImmediate(bool immediate, bool translucent)
{
	if (no_draw_distance < cam_zero_distance)
	{
		return; // too far away to draw
	}
	OOGLPushModelView();
	OOGLScaleModelView(make_vector(_scaleX,_scaleY,_scaleZ));

	if (mesh() != nullptr)
	{
		OOEntityWithDrawable::drawImmediate(immediate, translucent);
	}
	OOGLPopModelView();

	// Draw subentities.
	if (!immediate)	// TODO: is this relevant any longer?
	{
		Entity *subEntity = nullptr;
		for (const auto &subEntityRef : SubEntitiesOf(_subEntities))
		{
			subEntity = subEntityRef.get();
			if (OOSubEntityInterface *cxxSub = dynamic_cast<OOSubEntityInterface *>(subEntity))  cxxSub->drawSubEntityImmediate(immediate, translucent);
			else if (::ShipEntity *ship = oo::ToShip(subEntity))  ship->drawSubEntityImmediate(immediate, translucent);	// the category's (bead oo-dpyk8)
		}
	}
}


void OOVisualEffectEntity::update(OOTimeDelta delta_t)
{
	OOEntityWithDrawable::update(delta_t);

	if (!_haveExecutedSpawnAction) {
		doScriptEvent(OOJSID("effectSpawned"));
		_haveExecutedSpawnAction = true;
	}

	Entity *se = nullptr;
	for (const auto &seRef : SubEntitiesOf(_subEntities))
	{
		se = seRef.get();
		if (se != nullptr)  se->update(delta_t);
	}
}


bool OOVisualEffectEntity::isBreakPattern()
{
	return isImmuneToBreakPatternHide;
}


void OOVisualEffectEntity::setIsBreakPattern(bool bp)
{
	isImmuneToBreakPatternHide = bp;
}


oo::PList OOVisualEffectEntity::effectInfoDictionary()
{
	return effectinfoDictionary;
}


// (SubEntityRelationship) a slightly misnamed test now things other than ships can have subents
// The C++ entity (bead oo-w9pi2): the members its object's messages forwarded to (the virtual
// getIsVisualEffect() and setOwner(), which an Objective-C entity's adapter sends on; nil's NO for none).
bool OOVisualEffectEntity::isShipWithSubEntityShip(Entity *other)
{
	assert (getIsVisualEffect());

	if (other == nullptr || !other->getIsVisualEffect())  return false;
	if (!oo::EntityIsSubEntity(other))  return false;
	if (oo::LiveOwner(other) != this)  return false;	// its owner's object is this effect's

#ifndef NDEBUG
	// Sanity check; this should always be true.
	if (!hasSubEntity(other))
	{
		OO_LOG_ERR("visualeffect.subentity.sanityCheck.failed", "{} thinks it's a subentity of {}, but the supposed parent does not agree. {}", oo::EntityShortDescription(other), oo::EntityShortDescription(this), "This is an internal error, please report it.");
		other->setOwner(nullptr);
		return false;
	}
#endif

	return true;
}


OOColor *OOVisualEffectEntity::scannerDisplayColor1()
{
	return scanner_display_color1.get();
}


OOColor *OOVisualEffectEntity::scannerDisplayColor2()
{
	return scanner_display_color2.get();
}


void OOVisualEffectEntity::setScannerDisplayColor1(OOColor *color)
{
	scanner_display_color1 = nullptr;

	if (color == nullptr)  scanner_display_color1 = OOColor::colorWithDescription(ValueForKey(effectinfoDictionary, "scanner_display_color1"));
	else  scanner_display_color1 = oo::Ref<OOColor>(color);
}


void OOVisualEffectEntity::setScannerDisplayColor2(OOColor *color)
{
	scanner_display_color2 = nullptr;

	if (color == nullptr)  scanner_display_color2 = OOColor::colorWithDescription(ValueForKey(effectinfoDictionary, "scanner_display_color2"));
	else  scanner_display_color2 = oo::Ref<OOColor>(color);
}

static GLfloat default_color[4] =	{ 0.0, 0.0, 0.0, 0.0};
static GLfloat scripted_color[4] = 	{ 0.0, 0.0, 0.0, 0.0};

GLfloat *OOVisualEffectEntity::scannerDisplayColorForShip(bool flash, OOColor *scannerDisplayColor1, OOColor *scannerDisplayColor2)
{

	if (scannerDisplayColor1 || scannerDisplayColor2)
	{
		if (scannerDisplayColor1 && !scannerDisplayColor2)
		{
			scannerDisplayColor1->getRed(&scripted_color[0], &scripted_color[1], &scripted_color[2], &scripted_color[3]);
		}

		if (!scannerDisplayColor1 && scannerDisplayColor2)
		{
			scannerDisplayColor2->getRed(&scripted_color[0], &scripted_color[1], &scripted_color[2], &scripted_color[3]);
		}

		if (scannerDisplayColor1 && scannerDisplayColor2)
		{
			if (flash)
				scannerDisplayColor1->getRed(&scripted_color[0], &scripted_color[1], &scripted_color[2], &scripted_color[3]);
			else
				scannerDisplayColor2->getRed(&scripted_color[0], &scripted_color[1], &scripted_color[2], &scripted_color[3]);
		}

		return scripted_color;
	}

	return default_color; // transparent black if not specified
}


/* scripting */

void OOVisualEffectEntity::setScript(const std::optional<std::string> &script_name)
{
	oo::PList::Dict propertyList;
	propertyList["visualEffect"] = oo::EntityObjectNode(this);
	const oo::PList properties(std::move(propertyList));

	OOScriptAutorelease(std::move(_script));	// [_script autorelease]
	_script = OOScript::jsScriptFromFileNamed(script_name.value_or(std::string()), properties);
	// does not support legacy scripting
	if (_script == nullptr) {
		_script = OOScript::jsScriptFromFileNamed("oolite-default-effect-script.js", properties);
	}
}


::OOScript *OOVisualEffectEntity::script()
{
	return _script.get();
}


oo::PList OOVisualEffectEntity::scriptInfo()
{
	return _scriptInfo ? _scriptInfo : oo::PList(oo::PList::Dict{});
}

// unlikely to need events with arguments
void OOVisualEffectEntity::doScriptEvent(ooscript::PropertyId message)
{
	ooscript::Context context = OOJSAcquireContext();
	if (_script != nullptr)  _script->callMethod(message, context, NULL, 0, NULL);
	OOJSRelinquishContext(context);
}


void OOVisualEffectEntity::remove()
{
	doScriptEvent(OOJSID("effectRemoved"));
	if (UNIVERSE != nullptr)  UNIVERSE->removeEntity(this);
}


/* beacons */

OOComparisonResult OOVisualEffectEntity::compareBeaconCodeWith(Entity *other)
{
	return (OOComparisonResult)oo::str::caseInsensitiveCompare(beaconCode().value_or(""), oo::BeaconCode(other).value_or(""));
}


std::optional<std::string> OOVisualEffectEntity::beaconCode()
{
	return _beaconCode;
}


// bcode: optional string; empty is treated as none. The Foundation version compared the new string with the
// old by pointer, so any new string (every string this class hands out is new) replaced it.
void OOVisualEffectEntity::setBeaconCode(const std::optional<std::string> &bcode)
{
	std::optional<std::string> code = bcode;
	if (code.has_value() && code->empty())  code.reset();

	if (code.has_value() || _beaconCode.has_value())
	{
		_beaconCode = code;

		_beaconDrawable = nullptr;
	}
	// if not blanking code and label is currently blank, default label to code
	if (code.has_value() && (!_beaconLabel.has_value() || _beaconLabel->empty()))
	{
		setBeaconLabel(code);
	}

}


std::optional<std::string> OOVisualEffectEntity::beaconLabel()
{
	return _beaconLabel;
}


void OOVisualEffectEntity::setBeaconLabel(const std::optional<std::string> &blabel)
{
	std::optional<std::string> label = blabel;
	if (label.has_value() && label->empty())  label.reset();

	if (label.has_value() || _beaconLabel.has_value())
	{
		_beaconLabel = label.has_value() ? cxx_OOExpand(*label) : std::nullopt;
	}
}


bool OOVisualEffectEntity::isBeacon()
{
	return beaconCode().has_value();
}


OOHUDBeaconIcon *OOVisualEffectEntity::beaconDrawable()
{
	if (_beaconDrawable == nullptr)
	{
		const std::u16string	beaconCode = oo::utf8ToUtf16(_beaconCode.value_or(std::string()));
		NSUInteger	length = beaconCode.size();	// -length: UTF-16 units

		if (length > 1)
		{
			const oo::PList *iconEntry = UNIVERSE->descriptions()->find(*_beaconCode);
			const oo::PList iconData = (iconEntry != nullptr) ? *iconEntry : oo::PList();
			if (iconData.isArray())  _beaconDrawable = OOPolygonSprite::initWithDataArray(iconData, 0.5, *_beaconCode);	// null where it answered nil
		}

		if (_beaconDrawable == nullptr)
		{
			if (length > 0)  _beaconDrawable = oo::makeRef<OOHUDBeaconCodeIcon>(oo::utf16ToUtf8(beaconCode.substr(0, 1)));	// -substringToIndex:1
			else  _beaconDrawable = oo::makeRef<OOHUDBeaconCodeIcon>(std::string());
		}
	}

	return _beaconDrawable.get();
}


Entity *OOVisualEffectEntity::prevBeacon()
{
	return oo::LiveEntity(_prevBeacon);
}


Entity *OOVisualEffectEntity::nextBeacon()
{
	return oo::LiveEntity(_nextBeacon);
}


void OOVisualEffectEntity::setPrevBeacon(Entity *beaconShip)
{
	if (beaconShip != prevBeacon())
	{
		_prevBeacon = oo::WeakRef<Entity>(beaconShip);
	}
}


void OOVisualEffectEntity::setNextBeacon(Entity *beaconShip)
{
	if (beaconShip != nextBeacon())
	{
		_nextBeacon = oo::WeakRef<Entity>(beaconShip);
	}
}


bool OOVisualEffectEntity::isJammingScanning()
{
	return false;
}


/* Shader bindable uniforms */

// no automatic change of this, but simplifies use of default shader
GLfloat OOVisualEffectEntity::hullHeatLevel()
{
	return _hullHeatLevel;
}


void OOVisualEffectEntity::setHullHeatLevel(GLfloat value)
{
	_hullHeatLevel = OOClamp_0_1_f(value);
}


GLfloat OOVisualEffectEntity::shaderFloat1()
{
	return _shaderFloat1;
}


void OOVisualEffectEntity::setShaderFloat1(GLfloat value)
{
	_shaderFloat1 = value;
}


GLfloat OOVisualEffectEntity::shaderFloat2()
{
	return _shaderFloat2;
}


void OOVisualEffectEntity::setShaderFloat2(GLfloat value)
{
	_shaderFloat2 = value;
}


int OOVisualEffectEntity::shaderInt1()
{
	return _shaderInt1;
}


void OOVisualEffectEntity::setShaderInt1(int value)
{
	_shaderInt1 = value;
}


int OOVisualEffectEntity::shaderInt2()
{
	return _shaderInt2;
}


void OOVisualEffectEntity::setShaderInt2(int value)
{
	_shaderInt2 = value;
}


Vector OOVisualEffectEntity::shaderVector1()
{
	return _shaderVector1;
}


void OOVisualEffectEntity::setShaderVector1(Vector value)
{
	_shaderVector1 = value;
}


Vector OOVisualEffectEntity::shaderVector2()
{
	return _shaderVector2;
}


void OOVisualEffectEntity::setShaderVector2(Vector value)
{
	_shaderVector2 = value;
}


// The JS questions, which the effect's facade answered with the binding's functions until bead
// oo-9ht.165 (the root's facade asks these now).
void OOVisualEffectEntity::getJSClass(ooscript::ClassDef **outClass, ooscript::Object *outPrototype)
{
	::OOJSVisualEffectGetJSClass(outClass, outPrototype);
}


std::optional<std::string> OOVisualEffectEntity::jsClassName()
{
	return ::OOJSVisualEffectJSClassName();
}


bool OOVisualEffectEntity::isVisibleToScripts()
{
	return ::OOJSVisualEffectIsVisibleToScripts();
}
