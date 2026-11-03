/*

OOWaypointEntity.m

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

#import "OOWaypointEntity.h"
#import "Entity.h"
#import "HeadUpDisplay.h"
#import "OOFoundationBridge.h"
#import "OOMacroOpenGL.h"
#import "OOOpenGL.h"
#import "OOPListGameTypes.h"
#import "OOPolygonSprite.h"
#import "OOStringExpander.h"
#import "PlayerEntity.h"
#import "Universe.h"

#include "oofnd/PListGet.hpp"

#define OOWAYPOINT_KEY_POSITION "position"
#define OOWAYPOINT_KEY_ORIENTATION "orientation"
#define OOWAYPOINT_KEY_SIZE "size"
#define OOWAYPOINT_KEY_CODE "beaconCode"
#define OOWAYPOINT_KEY_LABEL "beaconLabel"

@implementation OOWaypointEntity

+ (instancetype)waypointWithDictionary:(const oo::PList&)info
{
    return [[[OOWaypointEntity alloc] cxx_initWithDictionary:info] autorelease];
}

- (id)initWithDictionary:(id)info // shared selector (Foundation declares it too)
{
    return [self cxx_initWithDictionary:oo::PListFrom(info)];
}

- (id)cxx_initWithDictionary:(const oo::PList&)info
{
    self = [super init];
    if (EXPECT_NOT(self == nil))
        return nil;

    // A nil dictionary read zero-filled values and nil strings (messaging nil), not the defaults.
    oriented = YES;
    position = info ? OOHPVectorFromPList(info.find(OOWAYPOINT_KEY_POSITION), kZeroHPVector) : kZeroHPVector;
    Quaternion q = info ? OOQuaternionFromPList(info.find(OOWAYPOINT_KEY_ORIENTATION), kIdentityQuaternion) : (Quaternion) { 0, 0, 0, 0 };
    [self setOrientation:q];
    [self setSize:info.get<oo::NonNegative<float>>(OOWAYPOINT_KEY_SIZE, 1000.0)];
    [self setBeaconCode:info ? std::optional<std::string>(info.get<std::string>(OOWAYPOINT_KEY_CODE, "W")) : std::nullopt];
    [self setBeaconLabel:info ? std::optional<std::string>(info.get<std::string>(OOWAYPOINT_KEY_LABEL, "Waypoint")) : std::nullopt];

    [self setStatus:STATUS_EFFECT];
    [self setScanClass:CLASS_NO_DRAW];

    return self;
}

- (void)dealloc
{
    DESTROY(_prevBeacon);
    DESTROY(_nextBeacon);
    DESTROY(_beaconDrawable);

    [super dealloc];
}

// override
- (void)setOrientation:(Quaternion)q
{
    if (quaternion_equal(q, kZeroQuaternion)) {
        q = kIdentityQuaternion;
        oriented = NO;
    } else {
        oriented = YES;
    }
    [super setOrientation:q];
}

- (BOOL)oriented
{
    return oriented;
}

- (OOScalar)size
{
    return _size;
}

- (void)setSize:(OOScalar)newSize
{
    if (newSize > 0) {
        _size = newSize;
        no_draw_distance = newSize * newSize * NO_DRAW_DISTANCE_FACTOR * NO_DRAW_DISTANCE_FACTOR * 2;
    }
}

- (BOOL)isEffect
{
    return YES;
}

- (BOOL)isWaypoint
{
    return YES;
}

- (void)drawImmediate:(bool)immediate translucent:(bool)translucent
{
    if (!translucent || no_draw_distance < cam_zero_distance) {
        return;
    }

    if (![PLAYER cxx_hasEquipmentItemProviding:"EQ_ADVANCED_COMPASS"]) {
        return;
    }

    int8_t i, j, k;

    GLfloat a = 0.75;
    if ([PLAYER compassTarget] != self) {
        a *= 0.25;
    }
    if (cam_zero_distance > _size * _size) {
        // dim out as gets further away; 2-D HUD display more
        // important at long range
        a -= 0.004f * (sqrtf(cam_zero_distance) / _size);
    }
    if (a < 0.01f) {
        return;
    }

    GLfloat s0 = _size;
    GLfloat s1 = _size * 0.75f;

    OO_ENTER_OPENGL();
    OOSetOpenGLState(OPENGL_STATE_TRANSLUCENT_PASS);
    OOGL(glEnable(GL_BLEND));
    GLScaledLineWidth(1.0);

    OOGL(glColor4f(0.0, 0.0, 1.0, a));
    OOGLBEGIN(GL_LINES);
    for (i = -1; i <= 1; i += 2) {
        for (j = -1; j <= 1; j += 2) {
            for (k = -1; k <= 1; k += 2) {
                glVertex3f(i * s0, j * s0, k * s1);
                glVertex3f(i * s0, j * s1, k * s0);
                glVertex3f(i * s0, j * s1, k * s0);
                glVertex3f(i * s1, j * s0, k * s0);
                glVertex3f(i * s1, j * s0, k * s0);
                glVertex3f(i * s0, j * s0, k * s1);
            }
        }
    }
    if (oriented) {
        while (s1 > 20.0f) {
            glVertex3f(-20.0, 0, -s1 - 20.0f);
            glVertex3f(0, 0, -s1);
            glVertex3f(20.0, 0, -s1 - 20.0f);
            glVertex3f(0, 0, -s1);
            glVertex3f(-20.0, 0, s1 - 20.0f);
            glVertex3f(0, 0, s1);
            glVertex3f(20.0, 0, s1 - 20.0f);
            glVertex3f(0, 0, s1);
            s1 *= 0.5;
        }
    }
    OOGLEND();

    OOGL(glDisable(GL_BLEND));
    OOVerifyOpenGLState();
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

@end
