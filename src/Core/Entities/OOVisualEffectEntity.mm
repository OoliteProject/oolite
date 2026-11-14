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

#import "OOVisualEffectEntity.h"

#import "OOMaths.h"
#import "OOOpenGLExtensionManager.h"
#import "OOShaderMaterial.h"
#import "Universe.h"

#import "OOConstToJSString.h"
#import "OOConstToString.h"
#import "OOStringExpander.h"
#import "OOStringParsing.h"
#import "ResourceManager.h"

#import "OOMesh.h"

#import "HeadUpDisplay.h"
#import "OOColor.h"
#import "OOPolygonSprite.h"

#import "OOFlasherEntity.h"

#import "OODebugFlags.h"
#import "OODebugGLDrawing.h"

#import "OOJSScript.h"

#import "MyOpenGLView.h"
#import "OOPListGameTypes.h"

#import "OOObjCPList.h"
#include "oofnd/PListGet.hpp"
#include "oofnd/String.hpp"

namespace {

// -objectForKey: as plist data (a null PList when absent), for +cxx_colorWithDescription:.
oo::PList ValueForKey(const oo::PList& dict, std::string_view key)
{
    const oo::PList* value = dict.find(key);
    return value != nullptr ? *value : oo::PList();
}

// get<std::string> where the Foundation code read nil: std::nullopt when the key is absent or its
// value is neither a string nor a number.
std::optional<std::string> OptionalStringForKey(const oo::PList& dict, std::string_view key)
{
    const oo::PList* value = dict.find(key);
    if (value == nullptr || !(value->isString() || value->isNumber()))
        return std::nullopt;
    return dict.get<std::string>(key);
}

// get<PList::Dict>: the dictionary, or null (nil).
oo::PList DictionaryForKey(const oo::PList& dict, std::string_view key)
{
    const oo::PList* value = dict.get<oo::PList::Dict>(key);
    return value != nullptr ? *value : oo::PList();
}

// A copy of the subentity list to walk (the Foundation code walked a copy of the array).
OOVisualEffectSubEntities SubEntitiesOf(const std::optional<OOVisualEffectSubEntities>& subEntities)
{
    return subEntities.value_or(OOVisualEffectSubEntities { });
}

// The subentities that answer YES to -isVisualEffect.
std::vector<oo::ObjCRef<OOVisualEffectEntity*>> VisualEffectsIn(const OOVisualEffectSubEntities& subEntities)
{
    std::vector<oo::ObjCRef<OOVisualEffectEntity*>> result;
    for (const auto& sub : subEntities) {
        if (!oo::ToCxx((::Entity*)sub.get())->getIsVisualEffect())
            continue; // -isVisualEffect, through the converted root
        result.emplace_back((OOVisualEffectEntity*)sub.get());
    }
    return result;
}

} // namespace

namespace cxx {

/*	-cxx_initWithKey:definition:'s body after [super init] (the constructor ran Entity's). The
        façade runs it once it holds this object (amendment oo-0mxi item 2); false where the
        initialiser released itself and answered nil.
*/
bool OOVisualEffectEntity::initWithKey(const std::string& key, const oo::PList& dict)
{
    OOJS_PROFILE_ENTER

    _effectKey = key;

    if (!setUpVisualEffectFromDictionary(dict)) {
        return false;
    }

    _haveExecutedSpawnAction = false;

    return true;

    OOJS_PROFILE_EXIT
}

bool OOVisualEffectEntity::setUpVisualEffectFromDictionary(const oo::PList& effectDict)
{
    OOJS_PROFILE_ENTER

    effectinfoDictionary = effectDict;
    if (effectinfoDictionary.isNull())
        effectinfoDictionary = oo::PList(oo::PList::Dict { });

    orientation = kIdentityQuaternion;
    rotMatrix = kIdentityMatrix;

    collision_radius = 0.0;

    const std::optional<std::string> modelName = OptionalStringForKey(effectDict, "model");
    if (modelName.has_value()) {
        ::OOMesh* mesh = [::OOMesh meshWithName:*modelName
                                       cacheKey:_effectKey
                             materialDictionary:DictionaryForKey(effectDict, "materials")
                              shadersDictionary:DictionaryForKey(effectDict, "shaders")
                                         smooth:effectDict.get<bool>("smooth", false)
                                   shaderMacros:OODefaultShipShaderMacros()
                            shaderBindingTarget:oo::ToObjC(this)];
        if (mesh == nil)
            return false;
        setMesh(mesh);
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

    const oo::PList* scriptInfoValue = effectDict.get<oo::PList::Dict>("script_info");
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
    DESTROY(_script);
    DESTROY(_beaconDrawable);
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

::OOMesh* OOVisualEffectEntity::mesh()
{
    return (::OOMesh*)getDrawable();
}

void OOVisualEffectEntity::setMesh(::OOMesh* mesh)
{
    if (mesh != this->mesh()) {
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
    for (const auto& sub : SubEntitiesOf(_subEntities))
        [sub.get() setOwner:nil]; // Ensure backlinks are broken
    _subEntities.reset();

    // reset size & mass!
    if (mesh()) {
        collision_radius = findCollisionRadius();
    } else {
        collision_radius = 0.0;
    }
    _profileRadius = collision_radius;
}

bool OOVisualEffectEntity::setUpSubEntities()
{
    unsigned int i;
    _profileRadius = collision_radius;
    const oo::PList* subs = effectinfoDictionary.get<oo::PList::Array>("subentities");

    for (i = 0; subs != nullptr && i < subs->count(); i++) {
        const oo::PList* subentDict = subs->at<oo::PList::Dict>(i); // nil for anything but a dictionary
        setUpOneSubentity(subentDict != nullptr ? *subentDict : oo::PList());
    }

    setNoDrawDistance();

    return true;
}

void OOVisualEffectEntity::removeSubEntity(OOVisualEffectSubEntity* sub)
{
    [sub setOwner:nil];
    if (_subEntities.has_value())
        std::erase_if(*_subEntities, [sub](const auto& entry) { return entry.get() == sub; });
}

void OOVisualEffectEntity::setNoDrawDistance()
{
    GLfloat r = _profileRadius * scaleMax();
    no_draw_distance = r * r * NO_DRAW_DISTANCE_FACTOR * NO_DRAW_DISTANCE_FACTOR * 2.0;
}

bool OOVisualEffectEntity::setUpOneSubentity(const oo::PList& subentDict)
{
    const std::optional<std::string> type = OptionalStringForKey(subentDict, "type");
    if (type == "flasher") {
        return setUpOneFlasher(subentDict);
    } else {
        return setUpOneStandardSubentity(subentDict);
    }
}

bool OOVisualEffectEntity::setUpOneFlasher(const oo::PList& subentDict)
{
    // C++ now: the flasher's object is the nearest facade left.
    ::Entity* flasher = oo::NewEntityFacade(OOFlasherEntity::flasherWithDictionary(subentDict));
    [flasher setPosition:subentDict ? OOHPVectorFromPList(subentDict.find("position"), kZeroHPVector) : kZeroHPVector];
    addSubEntity((OOVisualEffectSubEntity*)flasher);
    return true;
}

bool OOVisualEffectEntity::setUpOneStandardSubentity(const oo::PList& subentDict)
{
    ::OOVisualEffectEntity* subentity = nil;
    std::optional<std::string> subentKey;
    HPVector subPosition;
    Quaternion subOrientation;

    subentKey = OptionalStringForKey(subentDict, "subentity_key");
    if (!subentKey.has_value()) {
        OO_LOG("setup.visualeffect.badEntry.subentities", "Failed to set up entity - no subentKey in {}", oo::DescriptionOf(subentDict));
        return false;
    }

    subentity = [UNIVERSE cxx_newVisualEffectWithName:*subentKey];
    if (subentity == nil) {
        OO_LOG("setup.visualeffect.badEntry.subentities", "Failed to set up entity {}", *subentKey);
        return false;
    }

    subPosition = OOHPVectorFromPList(subentDict.find("position"), kZeroHPVector);
    subOrientation = OOQuaternionFromPList(subentDict.find("orientation"), kIdentityQuaternion);

    [subentity setPosition:subPosition];
    [subentity setOrientation:subOrientation];

    addSubEntity(subentity);

    [subentity release];

    return true;
}

void OOVisualEffectEntity::addSubEntity(OOVisualEffectSubEntity* sub)
{
    if (sub == nil)
        return;

    if (!_subEntities.has_value())
        _subEntities.emplace();
    sub->_cxxEntity->isSubEntity = true;
    // Order matters - need consistent state in setOwner:. -- Ahruman 2008-04-20
    _subEntities->emplace_back(sub);
    [sub setOwner:oo::ToObjC(this)];

    double distance = HPmagnitude([sub position]) + [sub findCollisionRadius];
    if (distance > _profileRadius) {
        _profileRadius = distance;
    }
}

std::vector<oo::ObjCRef<::Entity*>> OOVisualEffectEntity::subEntities()
{
    if (!_subEntities.has_value())
        return { };
    std::vector<oo::ObjCRef<::Entity*>> result;
    result.reserve(_subEntities->size());
    for (const auto& sub : *_subEntities) {
        result.emplace_back(sub.get());
    }
    return result;
}

NSUInteger OOVisualEffectEntity::subEntityCount()
{
    return _subEntities.has_value() ? _subEntities->size() : 0;
}

std::optional<std::vector<oo::ObjCRef<::OOVisualEffectEntity*>>> OOVisualEffectEntity::visualEffectSubEntityEnumerator()
{
    if (!_subEntities.has_value())
        return std::nullopt;
    return VisualEffectsIn(*_subEntities);
}

bool OOVisualEffectEntity::hasSubEntity(OOVisualEffectSubEntity* sub)
{
    if (!_subEntities.has_value())
        return false;
    return std::find_if(_subEntities->begin(), _subEntities->end(), [sub](const auto& entry) { return entry.get() == sub; }) != _subEntities->end();
}

std::vector<oo::ObjCRef<::Entity*>> OOVisualEffectEntity::subEntityEnumerator()
{
    return subEntities();
}

std::vector<oo::ObjCRef<::OOVisualEffectEntity*>> OOVisualEffectEntity::effectSubEntityEnumerator()
{
    return VisualEffectsIn(SubEntitiesOf(_subEntities));
}

std::vector<oo::ObjCRef<::Entity*>> OOVisualEffectEntity::flasherEnumerator()
{
    std::vector<oo::ObjCRef<::Entity*>> flashers;
    if (!_subEntities.has_value())
        return flashers;
    for (const auto& sub : *_subEntities) {
        if (dynamic_cast<OOFlasherEntity*>(oo::ToCxx((::Entity*)sub.get())) == nullptr)
            continue;
        flashers.emplace_back(sub.get());
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
    if (mesh() != nil) {
        setMesh([mesh() meshRescaledBy:factor]);
    }

    // rescale subentities
    OOVisualEffectSubEntity* se = nil;
    for (const auto& seRef : SubEntitiesOf(_subEntities)) {
        se = seRef.get();
        [se setPosition:HPvector_multiply_scalar([se position], factor)];
        if (OOSubEntityInterface* cxxSub = dynamic_cast<OOSubEntityInterface*>(oo::ToCxx((::Entity*)se)))
            cxxSub->rescaleBy(factor);
        else
            [se rescaleBy:factor];
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
    if (_scaleX > _scaleY) {
        if (_scaleX > _scaleZ) {
            scale *= _scaleX;
        } else {
            scale *= _scaleZ;
        }
    } else if (_scaleY > _scaleZ) {
        scale *= _scaleY;
    } else {
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
    OOVisualEffectSubEntity* se = nil;
    GLfloat flasher_factor = pow(factor / _scaleX, 1.0 / 3.0);
    for (const auto& seRef : SubEntitiesOf(_subEntities)) {
        se = seRef.get();
        HPVector move = [se position];
        move.x *= factor / _scaleX;
        [se setPosition:move];
        if ([se isVisualEffect]) {
            [(::OOVisualEffectEntity*)se setScaleX:factor];
        } else if (OOSubEntityInterface* cxxSub = dynamic_cast<OOSubEntityInterface*>(oo::ToCxx((::Entity*)se))) {
            cxxSub->rescaleBy(flasher_factor);
        } else {
            [se rescaleBy:flasher_factor];
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
    OOVisualEffectSubEntity* se = nil;
    GLfloat flasher_factor = pow(factor / _scaleY, 1.0 / 3.0);
    for (const auto& seRef : SubEntitiesOf(_subEntities)) {
        se = seRef.get();
        HPVector move = [se position];
        move.y *= factor / _scaleY;
        [se setPosition:move];
        if ([se isVisualEffect]) {
            [(::OOVisualEffectEntity*)se setScaleY:factor];
        } else if (OOSubEntityInterface* cxxSub = dynamic_cast<OOSubEntityInterface*>(oo::ToCxx((::Entity*)se))) {
            cxxSub->rescaleBy(flasher_factor);
        } else {
            [se rescaleBy:flasher_factor];
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
    OOVisualEffectSubEntity* se = nil;
    GLfloat flasher_factor = pow(factor / _scaleZ, 1.0 / 3.0);
    for (const auto& seRef : SubEntitiesOf(_subEntities)) {
        se = seRef.get();
        HPVector move = [se position];
        move.z *= factor / _scaleZ;
        [se setPosition:move];
        if ([se isVisualEffect]) {
            [(::OOVisualEffectEntity*)se setScaleZ:factor];
        } else if (OOSubEntityInterface* cxxSub = dynamic_cast<OOSubEntityInterface*>(oo::ToCxx((::Entity*)se))) {
            cxxSub->rescaleBy(flasher_factor);
        } else {
            [se rescaleBy:flasher_factor];
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

    _v_forward = vector_forward_from_quaternion(orientation);
    _v_up = vector_up_from_quaternion(orientation);
    _v_right = vector_right_from_quaternion(orientation);
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
    if (no_draw_distance < cam_zero_distance) {
        return; // too far away to draw
    }
    OOGLPushModelView();
    OOGLScaleModelView(make_vector(_scaleX, _scaleY, _scaleZ));

    if (mesh() != nil) {
        OOEntityWithDrawable::drawImmediate(immediate, translucent);
    }
    OOGLPopModelView();

    // Draw subentities.
    if (!immediate) // TODO: is this relevant any longer?
    {
        OOVisualEffectSubEntity* subEntity = nil;
        for (const auto& subEntityRef : SubEntitiesOf(_subEntities)) {
            subEntity = subEntityRef.get();
            if (OOSubEntityInterface* cxxSub = dynamic_cast<OOSubEntityInterface*>(oo::ToCxx((::Entity*)subEntity)))
                cxxSub->drawSubEntityImmediate(immediate, translucent);
            else
                [subEntity drawSubEntityImmediate:immediate translucent:translucent];
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

    ::Entity* se = nil;
    for (const auto& seRef : SubEntitiesOf(_subEntities)) {
        se = seRef.get();
        [se update:delta_t];
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
bool OOVisualEffectEntity::isShipWithSubEntityShip(::Entity* other)
{
    assert(getIsVisualEffect());

    if (![other isVisualEffect])
        return false;
    if (![other isSubEntity])
        return false;
    if ([other owner] != oo::ToObjC(this))
        return false;

#ifndef NDEBUG
    // Sanity check; this should always be true.
    if (!hasSubEntity((::OOVisualEffectEntity*)other)) {
        OO_LOG_ERR("visualeffect.subentity.sanityCheck.failed", "{} thinks it's a subentity of {}, but the supposed parent does not agree. {}", oo::ShortDescriptionOf(other), oo::ShortDescriptionOf(oo::ToObjC(this)), "This is an internal error, please report it.");
        [other setOwner:nil];
        return false;
    }
#endif

    return true;
}

cxx::OOColor* OOVisualEffectEntity::scannerDisplayColor1()
{
    return scanner_display_color1.get();
}

cxx::OOColor* OOVisualEffectEntity::scannerDisplayColor2()
{
    return scanner_display_color2.get();
}

void OOVisualEffectEntity::setScannerDisplayColor1(cxx::OOColor* color)
{
    scanner_display_color1 = nullptr;

    if (color == nullptr)
        scanner_display_color1 = cxx::OOColor::colorWithDescription(ValueForKey(effectinfoDictionary, "scanner_display_color1"));
    else
        scanner_display_color1 = oo::Ref<cxx::OOColor>(color);
}

void OOVisualEffectEntity::setScannerDisplayColor2(cxx::OOColor* color)
{
    scanner_display_color2 = nullptr;

    if (color == nullptr)
        scanner_display_color2 = cxx::OOColor::colorWithDescription(ValueForKey(effectinfoDictionary, "scanner_display_color2"));
    else
        scanner_display_color2 = oo::Ref<cxx::OOColor>(color);
}

static GLfloat default_color[4] = { 0.0, 0.0, 0.0, 0.0 };
static GLfloat scripted_color[4] = { 0.0, 0.0, 0.0, 0.0 };

GLfloat* OOVisualEffectEntity::scannerDisplayColorForShip(bool flash, cxx::OOColor* scannerDisplayColor1, cxx::OOColor* scannerDisplayColor2)
{

    if (scannerDisplayColor1 || scannerDisplayColor2) {
        if (scannerDisplayColor1 && !scannerDisplayColor2) {
            scannerDisplayColor1->getRed(&scripted_color[0], &scripted_color[1], &scripted_color[2], &scripted_color[3]);
        }

        if (!scannerDisplayColor1 && scannerDisplayColor2) {
            scannerDisplayColor2->getRed(&scripted_color[0], &scripted_color[1], &scripted_color[2], &scripted_color[3]);
        }

        if (scannerDisplayColor1 && scannerDisplayColor2) {
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

void OOVisualEffectEntity::setScript(const std::optional<std::string>& script_name)
{
    oo::PList::Dict propertyList;
    propertyList["visualEffect"] = oo::PListObject(oo::ToObjC(this));
    const oo::PList properties(std::move(propertyList));

    [_script autorelease];
    _script = cxx::OOScript::jsScriptFromFileNamed(script_name.value_or(std::string()), properties);
    // does not support legacy scripting
    if (_script == nil) {
        _script = cxx::OOScript::jsScriptFromFileNamed("oolite-default-effect-script.js", properties);
    }
    [_script retain];
}

::OOJSScript* OOVisualEffectEntity::script()
{
    return _script;
}

oo::PList OOVisualEffectEntity::scriptInfo()
{
    return _scriptInfo ? _scriptInfo : oo::PList(oo::PList::Dict { });
}

// unlikely to need events with arguments
void OOVisualEffectEntity::doScriptEvent(OOJSPropID message)
{
    JSContext* context = OOJSAcquireContext();
    [_script callMethod:message inContext:context withArguments:NULL count:0 result:NULL];
    OOJSRelinquishContext(context);
}

void OOVisualEffectEntity::remove()
{
    doScriptEvent(OOJSID("effectRemoved"));
    [UNIVERSE removeEntity:(::Entity*)oo::ToObjC(this)];
}

/* beacons */

OOComparisonResult OOVisualEffectEntity::compareBeaconCodeWith(OOVisualEffectBeaconEntity* other)
{
    return (OOComparisonResult)oo::str::caseInsensitiveCompare(beaconCode().value_or(""), [other beaconCode].value_or(""));
}

std::optional<std::string> OOVisualEffectEntity::beaconCode()
{
    return _beaconCode;
}

// bcode: optional string; empty is treated as none. The Foundation version compared the new string with the
// old by pointer, so any new string (every string this class hands out is new) replaced it.
void OOVisualEffectEntity::setBeaconCode(const std::optional<std::string>& bcode)
{
    std::optional<std::string> code = bcode;
    if (code.has_value() && code->empty())
        code.reset();

    if (code.has_value() || _beaconCode.has_value()) {
        _beaconCode = code;

        DESTROY(_beaconDrawable);
    }
    // if not blanking code and label is currently blank, default label to code
    if (code.has_value() && (!_beaconLabel.has_value() || _beaconLabel->empty())) {
        setBeaconLabel(code);
    }
}

std::optional<std::string> OOVisualEffectEntity::beaconLabel()
{
    return _beaconLabel;
}

void OOVisualEffectEntity::setBeaconLabel(const std::optional<std::string>& blabel)
{
    std::optional<std::string> label = blabel;
    if (label.has_value() && label->empty())
        label.reset();

    if (label.has_value() || _beaconLabel.has_value()) {
        _beaconLabel = label.has_value() ? cxx_OOExpand(*label) : std::nullopt;
    }
}

bool OOVisualEffectEntity::isBeacon()
{
    return beaconCode().has_value();
}

id<OOHUDBeaconIcon> OOVisualEffectEntity::beaconDrawable()
{
    if (_beaconDrawable == nil) {
        const std::u16string beaconCode = oo::utf8ToUtf16(_beaconCode.value_or(std::string()));
        NSUInteger length = beaconCode.size(); // -length: UTF-16 units

        if (length > 1) {
            const oo::PList* iconEntry = [UNIVERSE cxx_descriptions]->find(*_beaconCode);
            const oo::PList iconData = (iconEntry != nullptr) ? *iconEntry : oo::PList();
            if (iconData.isArray())
                _beaconDrawable = [[::OOPolygonSprite alloc] initWithDataArray:iconData outlineWidth:0.5 name:*_beaconCode];
        }

        if (_beaconDrawable == nil) {
            if (length > 0)
                _beaconDrawable = [[::OOHUDBeaconCodeIcon alloc] initWithText:oo::utf16ToUtf8(beaconCode.substr(0, 1))]; // -substringToIndex:1
            else
                _beaconDrawable = [[::OOHUDBeaconCodeIcon alloc] initWithText:std::string()];
        }
    }

    return _beaconDrawable;
}

OOVisualEffectBeaconEntity* OOVisualEffectEntity::prevBeacon()
{
    return [_prevBeacon weakRefUnderlyingObject];
}

OOVisualEffectBeaconEntity* OOVisualEffectEntity::nextBeacon()
{
    return [_nextBeacon weakRefUnderlyingObject];
}

void OOVisualEffectEntity::setPrevBeacon(OOVisualEffectBeaconEntity* beaconShip)
{
    if (beaconShip != prevBeacon()) {
        [_prevBeacon release];
        _prevBeacon = [beaconShip weakRetain];
    }
}

void OOVisualEffectEntity::setNextBeacon(OOVisualEffectBeaconEntity* beaconShip)
{
    if (beaconShip != nextBeacon()) {
        [_nextBeacon release];
        _nextBeacon = [beaconShip weakRetain];
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

} // namespace cxx
