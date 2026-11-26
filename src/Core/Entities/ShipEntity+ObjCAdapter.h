/*

ShipEntity+ObjCAdapter.h

TRANSITIONAL (proposed ADR-0056, amendments oo-mvzmb and oo-64ako): the C++ part of an
Objective-C ship, oo::ObjCShipEntity<Base>, and the facade's private initialiser that makes it,
shared by ShipEntity+ObjCBridge.mm (Base cxx::ShipEntity) and StationEntity+ObjCBridge.mm (Base
cxx::StationEntity, whose facade overrides -initShipPart). Private to those two files; deleted with
ShipEntity+ObjCBridge.h.

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

#ifndef SHIPENTITY_OBJCADAPTER_H
#define SHIPENTITY_OBJCADAPTER_H

#import "ShipEntity.h"

namespace oo {

/*	The C++ part of an Objective-C ship (ShipEntity, StationEntity, DockEntity, PlayerEntity, ...):
        the root's adapter over Base (cxx::ShipEntity, or a converted subclass of it: cxx::StationEntity),
        plus the members cxx::ShipEntity added that the Objective-C subclasses override, which message
        the Objective-C object (ADR-0056 amendments oo-vl43 item 1, oo-mvzmb and oo-64ako). Each slice
        that makes such a member virtual adds its line (docs/phases/3-slices/ShipEntity.md); the
        facade's forwarder calls cxx::ShipEntity's own member, which is what [super ...] (or not
        overriding) reached.
*/
template <class Base>
class ObjCShipEntity final : public ObjCEntity<Base> {
public:
    explicit ObjCShipEntity(::Entity* objcOwner)
        : ObjCEntity<Base>(objcOwner)
    {
    }

    // Slice 3 (bead oo-mvzmb).
    bool setUpShipFromDictionary(const oo::PList& shipDict) override { return [(::ShipEntity*)this->_objcOwner setUpShipFromDictionary:shipDict]; }
    bool setUpSubEntities() override { return [(::ShipEntity*)this->_objcOwner setUpSubEntities]; }

    // Slice 5 (bead oo-ddnn8).
    GLfloat doesHitLine(HPVector v0, HPVector v1, ::ShipEntity** hitEntity) override { return [(::ShipEntity*)this->_objcOwner doesHitLine:v0 v1:v1 hitEntity:hitEntity]; }

    // Slice 8 (bead oo-vxdsc).
    bool hasPrimaryWeapon(OOWeaponType weaponType) override { return [(::ShipEntity*)this->_objcOwner hasPrimaryWeapon:weaponType]; }

    // Slice 9 (bead oo-ke13m).
    bool canAddEquipment(const std::string& equipmentKeyIn, const std::string& context) override { return [(::ShipEntity*)this->_objcOwner canAddEquipment:equipmentKeyIn inContext:context]; }
    ::OOEquipmentType* weaponTypeForFacing(OOWeaponFacing facing, bool strict) override { return [(::ShipEntity*)this->_objcOwner weaponTypeForFacing:facing strict:strict]; }
    std::vector<oo::ObjCRef<::OOEquipmentType*>> missilesList() override { return [(::ShipEntity*)this->_objcOwner missilesList]; }
    oo::PList passengerListForScripting() override { return [(::ShipEntity*)this->_objcOwner passengerListForScripting]; }
    oo::PList parcelListForScripting() override { return [(::ShipEntity*)this->_objcOwner parcelListForScripting]; }
    oo::PList contractListForScripting() override { return [(::ShipEntity*)this->_objcOwner contractListForScripting]; }
    bool setWeaponMount(OOWeaponFacing facing, const std::string& eqKey) override { return [(::ShipEntity*)this->_objcOwner setWeaponMount:facing toWeapon:eqKey]; }
    bool addEquipmentItem(const std::string& equipmentKey, const std::string& context) override { return [(::ShipEntity*)this->_objcOwner addEquipmentItem:equipmentKey inContext:context]; }
    bool addEquipmentItem(const std::string& equipmentKeyIn, bool validateAddition, const std::string& context) override { return [(::ShipEntity*)this->_objcOwner addEquipmentItem:equipmentKeyIn withValidation:validateAddition inContext:context]; }

    // Slice 10 (bead oo-wvcs2).
    void removeEquipmentItem(const std::string& equipmentKey) override { [(::ShipEntity*)this->_objcOwner removeEquipmentItem:equipmentKey]; }
    bool removeExternalStore(::OOEquipmentType* eqType) override { return [(::ShipEntity*)this->_objcOwner removeExternalStore:eqType]; }
    OOCreditsQuantity removeMissiles() override { return [(::ShipEntity*)this->_objcOwner removeMissiles]; }
    NSUInteger parcelCount() override { return [(::ShipEntity*)this->_objcOwner parcelCount]; }
    NSUInteger passengerCount() override { return [(::ShipEntity*)this->_objcOwner passengerCount]; }
    NSUInteger passengerCapacity() override { return [(::ShipEntity*)this->_objcOwner passengerCapacity]; }
    float maxForwardShieldLevel() override { return [(::ShipEntity*)this->_objcOwner maxForwardShieldLevel]; }
    float maxAftShieldLevel() override { return [(::ShipEntity*)this->_objcOwner maxAftShieldLevel]; }

    // Slice 17 (bead oo-6hofy).
    void applyAttitudeChanges(double delta_t) override { [(::ShipEntity*)this->_objcOwner applyAttitudeChanges:delta_t]; }
    void setName(const std::optional<std::string>& inName) override { [(::ShipEntity*)this->_objcOwner cxx_setName:inName]; }

    // Slice 18 (bead oo-vho1o).
    bool isUnpiloted() override { return [(::ShipEntity*)this->_objcOwner isUnpiloted]; }
    bool hasHostileTarget() override { return [(::ShipEntity*)this->_objcOwner hasHostileTarget]; }

    // Slice 19 (bead oo-umyg2).
    GLfloat fuelChargeRate() override { return [(::ShipEntity*)this->_objcOwner fuelChargeRate]; }

    // Slice 20 (bead oo-66inv).
    void setBounty(OOCreditsQuantity amount) override { [(::ShipEntity*)this->_objcOwner setBounty:amount]; }
    void setBounty(OOCreditsQuantity amount, OOLegalStatusReason reason) override { [(::ShipEntity*)this->_objcOwner setBounty:amount withReason:reason]; }
    void setBounty(OOCreditsQuantity amount, const std::string& reason) override { [(::ShipEntity*)this->_objcOwner setBounty:amount withReasonAsString:reason]; }
    OOCreditsQuantity getBounty() override { return [(::ShipEntity*)this->_objcOwner bounty]; }
    int legalStatus() override { return [(::ShipEntity*)this->_objcOwner legalStatus]; }
    OOCargoQuantity cargoQuantityOnBoard() override { return [(::ShipEntity*)this->_objcOwner cargoQuantityOnBoard]; }
    oo::PList cargoListForScripting() override { return [(::ShipEntity*)this->_objcOwner cargoListForScripting]; }

    // Slice 21 (bead oo-cicod).
    void setMaxFlightPitch(GLfloat newValue) override { [(::ShipEntity*)this->_objcOwner setMaxFlightPitch:newValue]; }
    void setMaxFlightRoll(GLfloat newValue) override { [(::ShipEntity*)this->_objcOwner setMaxFlightRoll:newValue]; }
    void setMaxFlightYaw(GLfloat newValue) override { [(::ShipEntity*)this->_objcOwner setMaxFlightYaw:newValue]; }
    void noteTakingDamage(double amount, ::Entity* entity, OOShipDamageType type) override { [(::ShipEntity*)this->_objcOwner noteTakingDamage:amount from:entity type:type]; }

    // Slice 22 (bead oo-z1utw).
    void getDestroyedBy(::Entity* whom, OOShipDamageType type) override { [(::ShipEntity*)this->_objcOwner getDestroyedBy:whom damageType:type]; }
    void becomeExplosion() override { [(::ShipEntity*)this->_objcOwner becomeExplosion]; }
    void becomeEnergyBlast() override { [(::ShipEntity*)this->_objcOwner becomeEnergyBlast]; }

    // Slice 23 (bead oo-xmrgd).
    void becomeLargeExplosion(double factor) override { [(::ShipEntity*)this->_objcOwner becomeLargeExplosion:factor]; }
    void collectBountyFor(::ShipEntity* other) override { [(::ShipEntity*)this->_objcOwner collectBountyFor:other]; }
    GLfloat laserHeatLevel() override { return [(::ShipEntity*)this->_objcOwner laserHeatLevel]; }
    GLfloat laserHeatLevelAft() override { return [(::ShipEntity*)this->_objcOwner laserHeatLevelAft]; }
    GLfloat laserHeatLevelForward() override { return [(::ShipEntity*)this->_objcOwner laserHeatLevelForward]; }
    GLfloat laserHeatLevelPort() override { return [(::ShipEntity*)this->_objcOwner laserHeatLevelPort]; }
    GLfloat laserHeatLevelStarboard() override { return [(::ShipEntity*)this->_objcOwner laserHeatLevelStarboard]; }
    void setFoundTarget(::Entity* targetEntity) override { [(::ShipEntity*)this->_objcOwner setFoundTarget:targetEntity]; }

    // Slice 24 (bead oo-zd80m).
    bool isValidTarget(::Entity* target) override { return [(::ShipEntity*)this->_objcOwner isValidTarget:target]; }
    void addTarget(::Entity* targetEntity) override { [(::ShipEntity*)this->_objcOwner addTarget:targetEntity]; }

    // Slice 27 (bead oo-pnfyp).
    GLfloat lookingAtSunWithThresholdAngleCos(GLfloat thresholdAngleCos) override { return [(::ShipEntity*)this->_objcOwner lookingAtSunWithThresholdAngleCos:thresholdAngleCos]; }

    // Slice 28 (bead oo-40ocf).
    ::ShipEntity* fireMissile() override { return [(::ShipEntity*)this->_objcOwner fireMissile]; }

    // Slice 29 (bead oo-g900k).
    void noticeECM() override { [(::ShipEntity*)this->_objcOwner noticeECM]; }
    bool fireECM() override { return [(::ShipEntity*)this->_objcOwner fireECM]; }
    bool activateCloakingDevice() override { return [(::ShipEntity*)this->_objcOwner activateCloakingDevice]; }
    void deactivateCloakingDevice() override { [(::ShipEntity*)this->_objcOwner deactivateCloakingDevice]; }
    ::ShipEntity* launchEscapeCapsule() override { return [(::ShipEntity*)this->_objcOwner launchEscapeCapsule]; }
    void dumpCargo() override { [(::ShipEntity*)this->_objcOwner dumpCargo]; }

    // Slice 30 (bead oo-ogoct).
    bool collideWithShip(::ShipEntity* other) override { return [(::ShipEntity*)this->_objcOwner collideWithShip:other]; }
    void adjustVelocity(Vector xVel) override { [(::ShipEntity*)this->_objcOwner adjustVelocity:xVel]; }
    bool canScoop(::ShipEntity* other) override { return [(::ShipEntity*)this->_objcOwner canScoop:other]; }
    void suppressTargetLost() override { [(::ShipEntity*)this->_objcOwner suppressTargetLost]; }

    // Slice 31 (bead oo-gx86h).
    void takeScrapeDamage(double amount, ::Entity* ent) override { [(::ShipEntity*)this->_objcOwner takeScrapeDamage:amount from:ent]; }
    void takeHeatDamage(double amount) override { [(::ShipEntity*)this->_objcOwner takeHeatDamage:amount]; }
    void enterDock(::StationEntity* station) override { [(::ShipEntity*)this->_objcOwner enterDock:station]; }
    void leaveDock(::StationEntity* station) override { [(::ShipEntity*)this->_objcOwner leaveDock:station]; }
    void enterWormhole(::WormholeEntity* w_hole) override { [(::ShipEntity*)this->_objcOwner enterWormhole:w_hole]; }
    void enterWitchspace() override { [(::ShipEntity*)this->_objcOwner enterWitchspace]; }
    void leaveWitchspace() override { [(::ShipEntity*)this->_objcOwner leaveWitchspace]; }

    // Slice 32 (bead oo-5e0ny).
    void markAsOffender(int offence_value) override { [(::ShipEntity*)this->_objcOwner markAsOffender:offence_value]; }
    void markAsOffender(int offence_value, OOLegalStatusReason reason) override { [(::ShipEntity*)this->_objcOwner markAsOffender:offence_value withReason:reason]; }

    // Slice 33 (bead oo-tz2ra).
    void receiveCommsMessage(const std::string& message_text, ::ShipEntity* other) override { [(::ShipEntity*)this->_objcOwner receiveCommsMessage:message_text from:other]; }
    bool isMining() override { return [(::ShipEntity*)this->_objcOwner isMining]; }
    void interpretAIMessage(const std::string& ms) override { [(::ShipEntity*)this->_objcOwner interpretAIMessage:ms]; }

    // Slice 34 (bead oo-nkyn3).
    void doScriptEvent(OOJSPropID message, JSContext* context, JSValue* argv, int argc) override { [(::ShipEntity*)this->_objcOwner doScriptEvent:message inContext:context withArguments:argv count:argc]; }
    OOAlertCondition alertCondition() override { return [(::ShipEntity*)this->_objcOwner alertCondition]; }
    OOAlertCondition realAlertCondition() override { return [(::ShipEntity*)this->_objcOwner realAlertCondition]; }

    // ShipEntityAI.mm slice 1 (bead oo-iebuz).
    void acceptDistressMessageFrom(::ShipEntity* other) override { [(::ShipEntity*)this->_objcOwner acceptDistressMessageFrom:other]; }

    // ShipEntityAI.mm slice 3 (bead oo-wc9o3).
    void disengageAutopilot() override { [(::ShipEntity*)this->_objcOwner disengageAutopilot]; }
    void commsMessage(const std::string& valueString) override { [(::ShipEntity*)this->_objcOwner commsMessage:valueString]; }
    void commsMessageByUnpiloted(const std::string& valueString) override { [(::ShipEntity*)this->_objcOwner commsMessageByUnpiloted:valueString]; }
};

} // namespace oo

// What [super init] did in the ship's initialisers: makes the ship's C++ part (the .mm files).
@interface ShipEntity (OOObjCBridgePrivate)

- (id)initShipPart;

@end

#endif // SHIPENTITY_OBJCADAPTER_H
