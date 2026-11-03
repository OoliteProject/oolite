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

@interface OOVisualEffectEntity (Private)

- (void)drawSubEntityImmediate:(bool)immediate translucent:(bool)translucent;

- (void)addSubEntity:(Entity<OOSubEntity>*)subent;
- (BOOL)setUpOneSubentity:(const oo::PList&)subentDict;
- (BOOL)setUpOneFlasher:(const oo::PList&)subentDict;
- (BOOL)setUpOneStandardSubentity:(const oo::PList&)subentDict;

@end

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
        if (![sub.get() isVisualEffect])
            continue;
        result.emplace_back((OOVisualEffectEntity*)sub.get());
    }
    return result;
}

} // namespace

@implementation OOVisualEffectEntity

- (id)init
{
    return [self cxx_initWithKey:std::string { } definition:oo::PList()];
}

- (id)cxx_initWithKey:(const std::string&)key definition:(const oo::PList&)dict
{
    OOJS_PROFILE_ENTER

    self = [super init];
    if (self == nil)
        return nil;

    _effectKey = key;

    if (![self setUpVisualEffectFromDictionary:dict]) {
        [self release];
        self = nil;
    }

    _haveExecutedSpawnAction = NO;

    return self;

    OOJS_PROFILE_EXIT
}

- (BOOL)setUpVisualEffectFromDictionary:(const oo::PList&)effectDict
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
        OOMesh* mesh = [OOMesh meshWithName:*modelName
                                   cacheKey:_effectKey
                         materialDictionary:DictionaryForKey(effectDict, "materials")
                          shadersDictionary:DictionaryForKey(effectDict, "shaders")
                                     smooth:effectDict.get<bool>("smooth", NO)
                               shaderMacros:OODefaultShipShaderMacros()
                        shaderBindingTarget:self];
        if (mesh == nil)
            return NO;
        [self setMesh:mesh];
    }

    isImmuneToBreakPatternHide = effectDict.get<bool>("is_break_pattern");
    scaleX = 1.0;
    scaleY = 1.0;
    scaleZ = 1.0;

    [self clearSubEntities];
    [self setUpSubEntities];

    [self setScannerDisplayColor1:nil];
    [self setScannerDisplayColor2:nil];

    scanClass = CLASS_VISUAL_EFFECT;

    [self setStatus:STATUS_EFFECT];

    _hullHeatLevel = 60.0 / 256.0;
    _shaderFloat1 = 0.0;
    _shaderFloat2 = 0.0;
    _shaderInt1 = 0;
    _shaderInt2 = 0;
    _shaderVector1 = kZeroVector;
    _shaderVector2 = kZeroVector;

    [self setBeaconCode:OptionalStringForKey(effectDict, "beacon")];
    const std::optional<std::string> beaconLabel = OptionalStringForKey(effectDict, "beacon_label");
    [self setBeaconLabel:beaconLabel.has_value() ? beaconLabel : [self beaconCode]];

    const oo::PList* scriptInfoValue = effectDict.get<oo::PList::Dict>("script_info");
    scriptInfo = scriptInfoValue != nullptr ? *scriptInfoValue : oo::PList();
    [self setScript:OptionalStringForKey(effectDict, "script")];

    return YES;

    OOJS_PROFILE_EXIT
}

- (void)dealloc
{
    [self clearSubEntities];
    DESTROY(scanner_display_color1);
    DESTROY(scanner_display_color2);
    DESTROY(script);
    DESTROY(_beaconDrawable);

    [super dealloc];
}

- (BOOL)isEffect
{
    return YES;
}

- (BOOL)isVisualEffect
{
    return YES;
}

- (BOOL)canCollide
{
    return NO;
}

- (OOMesh*)mesh
{
    return (OOMesh*)[self drawable];
}

- (void)setMesh:(OOMesh*)mesh
{
    if (mesh != [self mesh]) {
        [self setDrawable:mesh];
    }
}

- (std::optional<std::string>)effectKey
{
    return _effectKey;
}

- (GLfloat)frustumRadius
{
    return [self scaleMax] * _profileRadius;
}

- (void)clearSubEntities
{
    for (const auto& sub : SubEntitiesOf(subEntities))
        [sub.get() setOwner:nil]; // Ensure backlinks are broken
    subEntities.reset();

    // reset size & mass!
    if ([self mesh]) {
        collision_radius = [self findCollisionRadius];
    } else {
        collision_radius = 0.0;
    }
    _profileRadius = collision_radius;
}

- (BOOL)setUpSubEntities
{
    unsigned int i;
    _profileRadius = collision_radius;
    const oo::PList* subs = effectinfoDictionary.get<oo::PList::Array>("subentities");

    for (i = 0; subs != nullptr && i < subs->count(); i++) {
        const oo::PList* subentDict = subs->at<oo::PList::Dict>(i); // nil for anything but a dictionary
        [self setUpOneSubentity:subentDict != nullptr ? *subentDict : oo::PList()];
    }

    [self setNoDrawDistance];

    return YES;
}

- (void)removeSubEntity:(Entity<OOSubEntity>*)sub
{
    [sub setOwner:nil];
    if (subEntities.has_value())
        std::erase_if(*subEntities, [sub](const auto& entry) { return entry.get() == sub; });
}

- (void)setNoDrawDistance
{
    GLfloat r = _profileRadius * [self scaleMax];
    no_draw_distance = r * r * NO_DRAW_DISTANCE_FACTOR * NO_DRAW_DISTANCE_FACTOR * 2.0;
}

- (BOOL)setUpOneSubentity:(const oo::PList&)subentDict
{
    const std::optional<std::string> type = OptionalStringForKey(subentDict, "type");
    if (type == "flasher") {
        return [self setUpOneFlasher:subentDict];
    } else {
        return [self setUpOneStandardSubentity:subentDict];
    }
}

- (BOOL)setUpOneFlasher:(const oo::PList&)subentDict
{
    OOFlasherEntity* flasher = [OOFlasherEntity flasherWithDictionary:subentDict];
    [flasher setPosition:subentDict ? OOHPVectorFromPList(subentDict.find("position"), kZeroHPVector) : kZeroHPVector];
    [self addSubEntity:flasher];
    return YES;
}

- (BOOL)setUpOneStandardSubentity:(const oo::PList&)subentDict
{
    OOVisualEffectEntity* subentity = nil;
    std::optional<std::string> subentKey;
    HPVector subPosition;
    Quaternion subOrientation;

    subentKey = OptionalStringForKey(subentDict, "subentity_key");
    if (!subentKey.has_value()) {
        OO_LOG("setup.visualeffect.badEntry.subentities", "Failed to set up entity - no subentKey in {}", oo::DescriptionOf(subentDict));
        return NO;
    }

    subentity = [UNIVERSE cxx_newVisualEffectWithName:*subentKey];
    if (subentity == nil) {
        OO_LOG("setup.visualeffect.badEntry.subentities", "Failed to set up entity {}", *subentKey);
        return NO;
    }

    subPosition = OOHPVectorFromPList(subentDict.find("position"), kZeroHPVector);
    subOrientation = OOQuaternionFromPList(subentDict.find("orientation"), kIdentityQuaternion);

    [subentity setPosition:subPosition];
    [subentity setOrientation:subOrientation];

    [self addSubEntity:subentity];

    [subentity release];

    return YES;
}

- (void)addSubEntity:(Entity<OOSubEntity>*)sub
{
    if (sub == nil)
        return;

    if (!subEntities.has_value())
        subEntities.emplace();
    sub->isSubEntity = YES;
    // Order matters - need consistent state in setOwner:. -- Ahruman 2008-04-20
    subEntities->emplace_back(sub);
    [sub setOwner:self];

    double distance = HPmagnitude([sub position]) + [sub findCollisionRadius];
    if (distance > _profileRadius) {
        _profileRadius = distance;
    }
}

- (std::vector<oo::ObjCRef<Entity*>>)subEntities
{
    if (!subEntities.has_value())
        return { };
    std::vector<oo::ObjCRef<Entity*>> result;
    result.reserve(subEntities->size());
    for (const auto& sub : *subEntities) {
        result.emplace_back(sub.get());
    }
    return result;
}

- (NSUInteger)subEntityCount
{
    return subEntities.has_value() ? subEntities->size() : 0;
}

- (std::optional<std::vector<oo::ObjCRef<OOVisualEffectEntity*>>>)visualEffectSubEntityEnumerator
{
    if (!subEntities.has_value())
        return std::nullopt;
    return VisualEffectsIn(*subEntities);
}

- (BOOL)hasSubEntity:(Entity<OOSubEntity>*)sub
{
    if (!subEntities.has_value())
        return NO;
    return std::find_if(subEntities->begin(), subEntities->end(), [sub](const auto& entry) { return entry.get() == sub; }) != subEntities->end();
}

- (std::vector<oo::ObjCRef<Entity*>>)subEntityEnumerator
{
    return [self subEntities];
}

- (std::vector<oo::ObjCRef<OOVisualEffectEntity*>>)effectSubEntityEnumerator
{
    return VisualEffectsIn(SubEntitiesOf(subEntities));
}

- (std::vector<oo::ObjCRef<OOFlasherEntity*>>)flasherEnumerator
{
    std::vector<oo::ObjCRef<OOFlasherEntity*>> flashers;
    if (!subEntities.has_value())
        return flashers;
    for (const auto& sub : *subEntities) {
        if (![sub.get() isFlasher])
            continue;
        flashers.emplace_back((OOFlasherEntity*)sub.get());
    }
    return flashers;
}

- (void)drawSubEntityImmediate:(bool)immediate translucent:(bool)translucent
{
    if (cam_zero_distance > no_draw_distance) // this test provides an opportunity to do simple LoD culling
    {
        return; // TOO FAR AWAY
    }
    OOGLPushModelView();
    // HPVect: camera position
    OOGLTranslateModelView(HPVectorToVector(position));
    OOGLMultModelView(rotMatrix);
    [self drawImmediate:immediate translucent:translucent];

    OOGLPopModelView();
}

- (void)rescaleBy:(GLfloat)factor
{
    if ([self mesh] != nil) {
        [self setMesh:[[self mesh] meshRescaledBy:factor]];
    }

    // rescale subentities
    Entity<OOSubEntity>* se = nil;
    for (const auto& seRef : SubEntitiesOf(subEntities)) {
        se = seRef.get();
        [se setPosition:HPvector_multiply_scalar([se position], factor)];
        [se rescaleBy:factor];
    }

    collision_radius *= factor;
    _profileRadius *= factor;
}

- (void)rescaleBy:(GLfloat)factor writeToCache:(BOOL)writeToCache
{
    /* Do nothing; this is only needed because of OOEntityWithDrawable
       implementation requirements */
}

- (GLfloat)scaleMax
{
    GLfloat scale = 1.0;
    if (scaleX > scaleY) {
        if (scaleX > scaleZ) {
            scale *= scaleX;
        } else {
            scale *= scaleZ;
        }
    } else if (scaleY > scaleZ) {
        scale *= scaleY;
    } else {
        scale *= scaleZ;
    }
    return scale;
}

- (GLfloat)scaleX
{
    return scaleX;
}

- (void)setScaleX:(GLfloat)factor
{
    // rescale subentities
    Entity<OOSubEntity>* se = nil;
    GLfloat flasher_factor = pow(factor / scaleX, 1.0 / 3.0);
    for (const auto& seRef : SubEntitiesOf(subEntities)) {
        se = seRef.get();
        HPVector move = [se position];
        move.x *= factor / scaleX;
        [se setPosition:move];
        if ([se isVisualEffect]) {
            [(OOVisualEffectEntity*)se setScaleX:factor];
        } else {
            [se rescaleBy:flasher_factor];
        }
    }

    scaleX = factor;
    [self setNoDrawDistance];
}

- (GLfloat)scaleY
{
    return scaleY;
}

- (void)setScaleY:(GLfloat)factor
{
    // rescale subentities
    Entity<OOSubEntity>* se = nil;
    GLfloat flasher_factor = pow(factor / scaleY, 1.0 / 3.0);
    for (const auto& seRef : SubEntitiesOf(subEntities)) {
        se = seRef.get();
        HPVector move = [se position];
        move.y *= factor / scaleY;
        [se setPosition:move];
        if ([se isVisualEffect]) {
            [(OOVisualEffectEntity*)se setScaleY:factor];
        } else {
            [se rescaleBy:flasher_factor];
        }
    }

    scaleY = factor;
    [self setNoDrawDistance];
}

- (GLfloat)scaleZ
{
    return scaleZ;
}

- (void)setScaleZ:(GLfloat)factor
{
    // rescale subentities
    Entity<OOSubEntity>* se = nil;
    GLfloat flasher_factor = pow(factor / scaleZ, 1.0 / 3.0);
    for (const auto& seRef : SubEntitiesOf(subEntities)) {
        se = seRef.get();
        HPVector move = [se position];
        move.z *= factor / scaleZ;
        [se setPosition:move];
        if ([se isVisualEffect]) {
            [(OOVisualEffectEntity*)se setScaleZ:factor];
        } else {
            [se rescaleBy:flasher_factor];
        }
    }

    scaleZ = factor;
    [self setNoDrawDistance];
}

- (GLfloat)collisionRadius
{
    return [self scaleMax] * collision_radius;
}

- (void)orientationChanged
{
    [super orientationChanged];

    _v_forward = vector_forward_from_quaternion(orientation);
    _v_up = vector_up_from_quaternion(orientation);
    _v_right = vector_right_from_quaternion(orientation);
}

// exposed to shaders
- (Vector)forwardVector
{
    return _v_forward;
}

// exposed to shaders
- (Vector)upVector
{
    return _v_up;
}

// exposed to shaders
- (Vector)rightVector
{
    return _v_right;
}

- (OOColor*)scannerDisplayColor1
{
    return [[scanner_display_color1 retain] autorelease];
}

- (OOColor*)scannerDisplayColor2
{
    return [[scanner_display_color2 retain] autorelease];
}

- (void)setScannerDisplayColor1:(OOColor*)color
{
    DESTROY(scanner_display_color1);

    if (color == nil)
        color = [OOColor cxx_colorWithDescription:ValueForKey(effectinfoDictionary, "scanner_display_color1")];
    scanner_display_color1 = [color retain];
}

- (void)setScannerDisplayColor2:(OOColor*)color
{
    DESTROY(scanner_display_color2);

    if (color == nil)
        color = [OOColor cxx_colorWithDescription:ValueForKey(effectinfoDictionary, "scanner_display_color2")];
    scanner_display_color2 = [color retain];
}

static GLfloat default_color[4] = { 0.0, 0.0, 0.0, 0.0 };
static GLfloat scripted_color[4] = { 0.0, 0.0, 0.0, 0.0 };

- (GLfloat*)scannerDisplayColorForShip:(BOOL)flash scannerDisplayColor1:(OOColor*)scannerDisplayColor1 scannerDisplayColor2:(OOColor*)scannerDisplayColor2
{

    if (scannerDisplayColor1 || scannerDisplayColor2) {
        if (scannerDisplayColor1 && !scannerDisplayColor2) {
            [scannerDisplayColor1 getRed:&scripted_color[0] green:&scripted_color[1] blue:&scripted_color[2] alpha:&scripted_color[3]];
        }

        if (!scannerDisplayColor1 && scannerDisplayColor2) {
            [scannerDisplayColor2 getRed:&scripted_color[0] green:&scripted_color[1] blue:&scripted_color[2] alpha:&scripted_color[3]];
        }

        if (scannerDisplayColor1 && scannerDisplayColor2) {
            if (flash)
                [scannerDisplayColor1 getRed:&scripted_color[0] green:&scripted_color[1] blue:&scripted_color[2] alpha:&scripted_color[3]];
            else
                [scannerDisplayColor2 getRed:&scripted_color[0] green:&scripted_color[1] blue:&scripted_color[2] alpha:&scripted_color[3]];
        }

        return scripted_color;
    }

    return default_color; // transparent black if not specified
}

- (void)drawImmediate:(bool)immediate translucent:(bool)translucent
{
    if (no_draw_distance < cam_zero_distance) {
        return; // too far away to draw
    }
    OOGLPushModelView();
    OOGLScaleModelView(make_vector(scaleX, scaleY, scaleZ));

    if ([self mesh] != nil) {
        [super drawImmediate:immediate translucent:translucent];
    }
    OOGLPopModelView();

    // Draw subentities.
    if (!immediate) // TODO: is this relevant any longer?
    {
        Entity<OOSubEntity>* subEntity = nil;
        for (const auto& subEntityRef : SubEntitiesOf(subEntities)) {
            subEntity = subEntityRef.get();
            [subEntity drawSubEntityImmediate:immediate translucent:translucent];
        }
    }
}

- (void)update:(OOTimeDelta)delta_t
{
    [super update:delta_t];

    if (!_haveExecutedSpawnAction) {
        [self doScriptEvent:OOJSID("effectSpawned")];
        _haveExecutedSpawnAction = YES;
    }

    Entity* se = nil;
    for (const auto& seRef : SubEntitiesOf(subEntities)) {
        se = seRef.get();
        [se update:delta_t];
    }
}

- (BOOL)isBreakPattern
{
    return isImmuneToBreakPatternHide;
}

- (void)setIsBreakPattern:(BOOL)bp
{
    isImmuneToBreakPatternHide = bp;
}

- (oo::PList)effectInfoDictionary
{
    return effectinfoDictionary;
}

/* scripting */

- (void)setScript:(const std::optional<std::string>&)script_name
{
    oo::PList::Dict propertyList;
    propertyList["visualEffect"] = oo::PListObject(self);
    const oo::PList properties(std::move(propertyList));

    [script autorelease];
    script = [OOScript cxx_jsScriptFromFileNamed:script_name.value_or(std::string()) properties:properties];
    // does not support legacy scripting
    if (script == nil) {
        script = [OOScript cxx_jsScriptFromFileNamed:"oolite-default-effect-script.js" properties:properties];
    }
    [script retain];
}

- (OOJSScript*)script
{
    return script;
}

- (oo::PList)scriptInfo
{
    return scriptInfo ? scriptInfo : oo::PList(oo::PList::Dict { });
}

// unlikely to need events with arguments
- (void)doScriptEvent:(OOJSPropID)message
{
    JSContext* context = OOJSAcquireContext();
    [script callMethod:message inContext:context withArguments:NULL count:0 result:NULL];
    OOJSRelinquishContext(context);
}

- (void)remove
{
    [self doScriptEvent:OOJSID("effectRemoved")];
    [UNIVERSE removeEntity:(Entity*)self];
}

/* beacons */

- (OOComparisonResult)compareBeaconCodeWith:(Entity<OOBeaconEntity>*)other
{
    return (OOComparisonResult)oo::str::caseInsensitiveCompare([self beaconCode].value_or(""), [other beaconCode].value_or(""));
}

- (std::optional<std::string>)beaconCode
{
    return _beaconCode;
}

// bcode: optional string; empty is treated as none. The Foundation version compared the new string with the
// old by pointer, so any new string (every string this class hands out is new) replaced it.
- (void)setBeaconCode:(const std::optional<std::string>&)bcode
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
        [self setBeaconLabel:code];
    }
}

- (std::optional<std::string>)beaconLabel
{
    return _beaconLabel;
}

- (void)setBeaconLabel:(const std::optional<std::string>&)blabel
{
    std::optional<std::string> label = blabel;
    if (label.has_value() && label->empty())
        label.reset();

    if (label.has_value() || _beaconLabel.has_value()) {
        _beaconLabel = label.has_value() ? cxx_OOExpand(*label) : std::nullopt;
    }
}

- (BOOL)isBeacon
{
    return [self beaconCode].has_value();
}

- (id<OOHUDBeaconIcon>)beaconDrawable
{
    if (_beaconDrawable == nil) {
        const std::u16string beaconCode = oo::utf8ToUtf16(_beaconCode.value_or(std::string()));
        NSUInteger length = beaconCode.size(); // -length: UTF-16 units

        if (length > 1) {
            const oo::PList* iconEntry = [UNIVERSE cxx_descriptions]->find(*_beaconCode);
            const oo::PList iconData = (iconEntry != nullptr) ? *iconEntry : oo::PList();
            if (iconData.isArray())
                _beaconDrawable = [[OOPolygonSprite alloc] initWithDataArray:iconData outlineWidth:0.5 name:*_beaconCode];
        }

        if (_beaconDrawable == nil) {
            if (length > 0)
                _beaconDrawable = [[OOHUDBeaconCodeIcon alloc] initWithText:oo::utf16ToUtf8(beaconCode.substr(0, 1))]; // -substringToIndex:1
            else
                _beaconDrawable = [[OOHUDBeaconCodeIcon alloc] initWithText:std::string()];
        }
    }

    return _beaconDrawable;
}

- (Entity<OOBeaconEntity>*)prevBeacon
{
    return [_prevBeacon weakRefUnderlyingObject];
}

- (Entity<OOBeaconEntity>*)nextBeacon
{
    return [_nextBeacon weakRefUnderlyingObject];
}

- (void)setPrevBeacon:(Entity<OOBeaconEntity>*)beaconShip
{
    if (beaconShip != [self prevBeacon]) {
        [_prevBeacon release];
        _prevBeacon = [beaconShip weakRetain];
    }
}

- (void)setNextBeacon:(Entity<OOBeaconEntity>*)beaconShip
{
    if (beaconShip != [self nextBeacon]) {
        [_nextBeacon release];
        _nextBeacon = [beaconShip weakRetain];
    }
}

- (BOOL)isJammingScanning
{
    return NO;
}

/* Shader bindable uniforms */

// no automatic change of this, but simplifies use of default shader
- (GLfloat)hullHeatLevel
{
    return _hullHeatLevel;
}

- (void)setHullHeatLevel:(GLfloat)value
{
    _hullHeatLevel = OOClamp_0_1_f(value);
}

- (GLfloat)shaderFloat1
{
    return _shaderFloat1;
}

- (void)setShaderFloat1:(GLfloat)value
{
    _shaderFloat1 = value;
}

- (GLfloat)shaderFloat2
{
    return _shaderFloat2;
}

- (void)setShaderFloat2:(GLfloat)value
{
    _shaderFloat2 = value;
}

- (int)shaderInt1
{
    return _shaderInt1;
}

- (void)setShaderInt1:(int)value
{
    _shaderInt1 = value;
}

- (int)shaderInt2
{
    return _shaderInt2;
}

- (void)setShaderInt2:(int)value
{
    _shaderInt2 = value;
}

- (Vector)shaderVector1
{
    return _shaderVector1;
}

- (void)setShaderVector1:(Vector)value
{
    _shaderVector1 = value;
}

- (Vector)shaderVector2
{
    return _shaderVector2;
}

- (void)setShaderVector2:(Vector)value
{
    _shaderVector2 = value;
}

@end

@implementation OOVisualEffectEntity (SubEntityRelationship)

// a slightly misnamed test now things other than ships can have subents
- (BOOL)isShipWithSubEntityShip:(Entity*)other
{
    assert([self isVisualEffect]);

    if (![other isVisualEffect])
        return NO;
    if (![other isSubEntity])
        return NO;
    if ([other owner] != self)
        return NO;

#ifndef NDEBUG
    // Sanity check; this should always be true.
    if (![self hasSubEntity:(OOVisualEffectEntity*)other]) {
        OO_LOG_ERR("visualeffect.subentity.sanityCheck.failed", "{} thinks it's a subentity of {}, but the supposed parent does not agree. {}", oo::ShortDescriptionOf(other), oo::ShortDescriptionOf(self), "This is an internal error, please report it.");
        [other setOwner:nil];
        return NO;
    }
#endif

    return YES;
}

@end
