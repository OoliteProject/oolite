/*

Entity+ObjCBridge.h

TRANSITIONAL (proposed ADR-0056, amendment oo-bj8): the Objective-C Entity, a facade over the C++
cxx::Entity (Entity.h), for the code that messages entities, the entity subclasses not converted
yet (ShipEntity, PlanetEntity, the effects, ...), and everything that holds an entity as an
Objective-C object: the universe's lists, weak references, the JavaScript wrappers. Its interface
is the one Entity.h declared before the conversion, copied exactly (same selectors, same types),
so they compile and behave unchanged. Imported as the last line of Entity.h; do not import it
directly.

It is a hierarchy root's facade, as OODrawable+ObjCBridge.h is, with two differences.

1.	The Objective-C object is the entity's identity, and it owns the C++ part in both cases. Its
        superclass, OOWeakRefObject, keeps state (the weak reference), and callers keep and compare
        the object. So oo::ToObjC answers the entity's Objective-C object and never makes one, and
        C++ code that keeps an entity keeps that object (oo::ObjCRef<Entity *>, amendment oo-smy
        item 4).

        the entity is                        its Objective-C object is            virtual calls on
                                                                                  the C++ side reach
        -----------------------------------  -----------------------------------  ------------------
        an Objective-C subclass              the subclass instance; an adapter,   the subclass's
          (unconverted, [[X alloc] init])    oo::ObjCEntity<Base>, is its C++     methods
                                             part
        a C++ subclass (converted)           the facade oo::NewEntityFacade made  the C++ overrides
                                             when the entity was made

2.	The state is the C++ part's. _cxxEntity is @public, and unconverted code that read an ivar
        directly reads the C++ member through it, by the same name: ent->_cxxEntity->position, and
        _cxxEntity->position in an Objective-C subclass's method. When that code converts, deleting
        "_cxxEntity->" gives its body back verbatim.

The protocol the header declared (OOBeaconEntity) is here, unchanged. Never add to this file;
converted code does not message the facade. Deleted by its deletion bead once every caller and
every entity class is C++.

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

#ifndef ENTITY_OBJCBRIDGE_H
#define ENTITY_OBJCBRIDGE_H

@interface Entity : OOWeakRefObject {
@public
    oo::Ref<cxx::Entity> _cxxEntity; // the entity's state and behaviour; set by the initialiser
}

// The session in which the entity was created.
- (NSUInteger)sessionID;

- (BOOL)isShip;
- (BOOL)isDock;
- (BOOL)isStation;
- (BOOL)isSubEntity;
- (BOOL)isPlayer;
- (BOOL)isPlanet;
- (BOOL)isSun;
- (BOOL)isSunlit;
- (BOOL)isStellarObject;
- (BOOL)isSky;
- (BOOL)isWormhole;
- (BOOL)isEffect;
- (BOOL)isVisualEffect;
- (BOOL)isWaypoint;

- (BOOL)validForAddToUniverse;
- (void)addToLinkedLists;
- (void)removeFromLinkedLists;

- (void)updateLinkedLists;

- (void)wasAddedToUniverse;
- (void)wasRemovedFromUniverse;

- (void)warnAboutHostiles;

- (CollisionRegion*)collisionRegion;
- (void)setCollisionRegion:(CollisionRegion*)region;

- (void)setUniversalID:(OOUniversalID)uid;
- (OOUniversalID)universalID;

- (BOOL)throwingSparks;
- (void)setThrowSparks:(BOOL)value;
- (void)throwSparks;

- (void)setOwner:(Entity*)ent;
- (id)owner;
- (ShipEntity*)parentEntity; // owner if self is subentity of owner, otherwise nil.
- (ShipEntity*)rootShipEntity; // like parentEntity, but recursive.

- (void)setPosition:(HPVector)posn;
- (void)setPositionX:(OOHPScalar)x y:(OOHPScalar)y z:(OOHPScalar)z;
- (HPVector)position;
- (Vector)cameraRelativePosition;
- (GLfloat)cameraRangeFront;
- (GLfloat)cameraRangeBack;

- (void)updateCameraRelativePosition;
// gets a low-position relative vector
- (Vector)vectorTo:(Entity*)entity;

- (HPVector)absolutePositionForSubentity;
- (HPVector)absolutePositionForSubentityOffset:(HPVector)offset;

- (double)zeroDistance;
- (double)camZeroDistance;
- (OOComparisonResult)compareZeroDistance:(Entity*)otherEntity;

- (BoundingBox)boundingBox;

- (GLfloat)mass;

- (Quaternion)orientation;
- (void)setOrientation:(Quaternion)quat;
- (Quaternion)normalOrientation; // Historical wart: orientation.w is reversed for player; -normalOrientation corrects this.
- (void)setNormalOrientation:(Quaternion)quat;
- (void)orientationChanged;

- (void)setVelocity:(Vector)vel;
- (Vector)velocity;
- (double)speed;

- (GLfloat)distanceTravelled;
- (void)setDistanceTravelled:(GLfloat)value;

- (void)setStatus:(OOEntityStatus)stat;
- (OOEntityStatus)status;

- (void)setScanClass:(OOScanClass)sClass;
- (OOScanClass)scanClass;

- (void)setEnergy:(GLfloat)amount;
- (GLfloat)energy;

- (void)setMaxEnergy:(GLfloat)amount;
- (GLfloat)maxEnergy;

- (void)applyRoll:(GLfloat)roll andClimb:(GLfloat)climb;
- (void)applyRoll:(GLfloat)roll climb:(GLfloat)climb andYaw:(GLfloat)yaw;
- (void)moveForward:(double)amount;

- (OOMatrix)rotationMatrix;
- (OOMatrix)drawRotationMatrix;
- (OOMatrix)transformationMatrix;
- (OOMatrix)drawTransformationMatrix;

- (BOOL)canCollide;
- (GLfloat)collisionRadius;
- (GLfloat)frustumRadius;
- (void)setCollisionRadius:(GLfloat)amount;
- (std::vector<oo::ObjCRef<Entity*>>*)cxx_collidingEntities; // the live list (ADR-0043 item 22); nullptr on nil

- (void)update:(OOTimeDelta)delta_t;

- (void)applyVelocity:(OOTimeDelta)delta_t;
- (BOOL)checkCloseCollisionWith:(Entity*)other;

- (void)takeEnergyDamage:(double)amount from:(Entity*)ent becauseOf:(Entity*)other weaponIdentifier:(const std::string&)weaponIdentifier;

- (void)dumpState; // General "describe situtation verbosely in log" command.
- (void)dumpSelfState; // Subclasses should override this, not -dumpState, and call throught to super first.

- (NSUInteger)lastDrawCounter;
- (void)setLastDrawCounter:(NSUInteger)drawCounter;

// Subclass repsonsibilities
- (double)findCollisionRadius;
- (void)drawImmediate:(bool)immediate translucent:(bool)translucent;
- (BOOL)isVisible;
- (BOOL)isInSpace;
- (BOOL)isImmuneToBreakPatternHide;

// For shader bindings.
- (GLfloat)universalTime;
- (GLfloat)spawnTime;
- (GLfloat)timeElapsedSinceSpawn;
- (void)setAtmosphereFogging:(OOColor*)fogging;
- (OOColor*)fogUniform;

#ifdef OO_DEBUG_MONITOR_ENABLED
- (std::optional<std::string>)descriptionForObjDumpBasic;
- (std::optional<std::string>)descriptionForObjDump; // flipped with its family (bead oo-3rb.278)

- (std::vector<oo::ObjCRef<OOTexture*>>)cxx_allTextures;
#endif

@end

@protocol OOHUDBeaconIcon;

// Methods that must be supported by entities with beacons, regardless of type.
@protocol OOBeaconEntity

- (OOComparisonResult)compareBeaconCodeWith:(Entity<OOBeaconEntity>*)other;
- (std::optional<std::string>)beaconCode; // flipped with its family (bead oo-3rb.260)
- (void)setBeaconCode:(const std::optional<std::string>&)bcode; // flipped with its family (bead oo-3rb.260)
- (std::optional<std::string>)beaconLabel; // flipped with its family (bead oo-3rb.260)
- (void)setBeaconLabel:(const std::optional<std::string>&)blabel; // flipped with its family (bead oo-3rb.260)
- (BOOL)isBeacon;
- (id<OOHUDBeaconIcon>)beaconDrawable;
- (Entity<OOBeaconEntity>*)prevBeacon;
- (Entity<OOBeaconEntity>*)nextBeacon;
- (void)setPrevBeacon:(Entity<OOBeaconEntity>*)beaconShip;
- (void)setNextBeacon:(Entity<OOBeaconEntity>*)beaconShip;
- (BOOL)isJammingScanning;

@end

@interface Entity (OOObjCBridge)

/*	The designated initialiser: stores the entity's C++ part (retained) and counts the entity.
        -init passes a new adapter over cxx::Entity (an Objective-C entity); the facade of a converted
        intermediate class passes an adapter over its own C++ class (OOEntityWithDrawable's -init);
        oo::NewEntityFacade passes a C++ entity. Answers self.
*/
- (id)initWithCxxEntity:(cxx::Entity*)entity;

// Not declared by the header before: ShipEntity overrides it, and the adapter sends it.
- (void)subEntityReallyDied:(ShipEntity*)sub;

@end

/*	The informal protocols a shader binding target implements, categories of the Objective-C root
        that the entities implement (Entity's facade, ShipEntity). They are not the material's: they
        stay Objective-C until the entities convert (ADR-0056 amendment of bead oo-3kqi, item 5), moved
        here unchanged from the shader material's facade header when bead oo-9ht.46 deleted it.
*/
@interface OOObject (ShaderBindingHierarchy)

/*	Informal protocol for objects to "forward" their shader bindings up a
        hierarchy (for instance, subentities to parent entities).
*/
- (id<OOWeakReferenceSupport>)superShaderBindingTarget;

@end

@interface OOObject (OOShaderMaterialTargetOptional)

- (uint32_t)randomSeedForShaders;

@end

namespace oo {

// The entity's Objective-C object: an Objective-C entity itself, else a C++ entity's facade.
// Borrowed (the Objective-C object owns the C++ part, so it lives while the entity does); nil for
// null, and for an adapter whose object has been deallocated.
::Entity* ToObjC(cxx::Entity* entity);
inline ::Entity* ToObjC(const Ref<cxx::Entity>& entity) { return ToObjC(entity.get()); }

// The C++ entity behind an Objective-C one, borrowed; null for nil.
inline cxx::Entity* ToCxx(::Entity* entity) { return entity != nil ? entity->_cxxEntity.get() : nullptr; }

// The Objective-C object of an entity made in C++ (a converted subclass): a new facade that owns
// it and is its identity from then on, autoreleased. Call it once, where the entity is made. Its
// class is the facade of the entity's nearest converted class that has one (OOEntityWithDrawable,
// OOLightParticleEntity, and the leaves with a facade; else Entity).
::Entity* NewEntityFacade(const Ref<cxx::Entity>& entity);

// The class name "%@" and the debug dumps print: the Objective-C class of an Objective-C entity,
// the C++ class's name ("cxx::" dropped) of a C++ one.
std::string EntityClassName(cxx::Entity* entity);

/*	The C++ part of an Objective-C entity, in two halves. ObjCEntity<Base> derives from Base, the
        C++ class of the Objective-C class's nearest converted superclass (cxx::Entity, or
        cxx::OOEntityWithDrawable: amendment oo-up4b item 1), and each of its virtual members messages
        the Objective-C object, so the subclass's override runs, as it did when the base class was
        Objective-C. ObjCEntityLink is its non-template half: the object, and a super...() member per
        virtual member that is Base's own, which is what [super ...] (or a subclass that does not
        override) reached. The facade's methods call those on an Objective-C entity. The Objective-C
        object owns the adapter (its _cxxEntity) and is not retained by it; its -dealloc clears the
        pointer, after which the members answer as a message to nil did. The template is not final: a
        converted intermediate class that adds virtual members derives its own adapter from it
        (OOLightParticleEntity+ObjCBridge.mm, amendment oo-0otc).
*/
class ObjCEntityLink {
public:
    explicit ObjCEntityLink(::Entity* objcOwner)
        : _objcOwner(objcOwner)
    {
    }
    virtual ~ObjCEntityLink() = default;
    ObjCEntityLink(const ObjCEntityLink&) = delete;
    ObjCEntityLink& operator=(const ObjCEntityLink&) = delete;

    ::Entity* objcOwner() { return _objcOwner; }
    void objcOwnerDeallocated() { _objcOwner = nil; }

    virtual NSUInteger superSessionID() = 0;
    virtual bool superIsDock() = 0;
    virtual bool superIsPlanet() = 0;
    virtual bool superIsSun() = 0;
    virtual bool superIsSky() = 0;
    virtual bool superIsEffect() = 0;
    virtual bool superGetIsVisualEffect() = 0;
    virtual bool superIsWaypoint() = 0;
    virtual bool superValidForAddToUniverse() = 0;
    virtual void superWasAddedToUniverse() = 0;
    virtual void superWasRemovedFromUniverse() = 0;
    virtual void superWarnAboutHostiles() = 0;
    virtual void superThrowSparks() = 0;
    virtual void superSetOwner(cxx::Entity* ent) = 0;
    virtual void superSetPosition(HPVector posn) = 0;
    virtual GLfloat superCameraRangeFront() = 0;
    virtual GLfloat superCameraRangeBack() = 0;
    virtual void superUpdateCameraRelativePosition() = 0;
    virtual OOComparisonResult superCompareZeroDistance(cxx::Entity* otherEntity) = 0;
    virtual void superSetOrientation(Quaternion quat) = 0;
    virtual Quaternion superNormalOrientation() = 0;
    virtual void superSetNormalOrientation(Quaternion quat) = 0;
    virtual void superOrientationChanged() = 0;
    virtual Vector superGetVelocity() = 0;
    virtual void superSetStatus(OOEntityStatus stat) = 0;
    virtual OOScanClass superGetScanClass() = 0;
    virtual void superApplyRoll(GLfloat roll, GLfloat climb) = 0;
    virtual void superApplyRoll(GLfloat roll, GLfloat climb, GLfloat yaw) = 0;
    virtual void superMoveForward(double amount) = 0;
    virtual OOMatrix superDrawRotationMatrix() = 0;
    virtual OOMatrix superDrawTransformationMatrix() = 0;
    virtual bool superCanCollide() = 0;
    virtual GLfloat superCollisionRadius() = 0;
    virtual GLfloat superFrustumRadius() = 0;
    virtual void superUpdate(OOTimeDelta delta_t) = 0;
    virtual bool superCheckCloseCollisionWith(cxx::Entity* other) = 0;
    virtual void superTakeEnergyDamage(double amount, cxx::Entity* ent, cxx::Entity* other, const std::string& weaponIdentifier) = 0;
    virtual void superDumpSelfState() = 0;
    virtual void superSubEntityReallyDied(ShipEntity* sub) = 0;
    virtual double superFindCollisionRadius() = 0;
    virtual void superDrawImmediate(bool immediate, bool translucent) = 0;
    virtual bool superIsVisible() = 0;
    virtual std::optional<std::string> superDescriptionComponents() const = 0;
#ifdef OO_DEBUG_MONITOR_ENABLED
    virtual std::optional<std::string> superDescriptionForObjDump() = 0;
    virtual std::vector<ObjCRef<OOTexture*>> superAllTextures() = 0;
#endif

protected:
    ::Entity* _objcOwner = { }; // Not retained.
};

template <class Base>
class ObjCEntity : public Base, public ObjCEntityLink {
public:
    explicit ObjCEntity(::Entity* objcOwner)
        : ObjCEntityLink(objcOwner)
    {
    }

    NSUInteger sessionID() override { return [_objcOwner sessionID]; }
    bool isDock() override { return [_objcOwner isDock]; }
    bool isPlanet() override { return [_objcOwner isPlanet]; }
    bool isSun() override { return [_objcOwner isSun]; }
    bool isSky() override { return [_objcOwner isSky]; }
    bool isEffect() override { return [_objcOwner isEffect]; }
    bool getIsVisualEffect() override { return [_objcOwner isVisualEffect]; }
    bool isWaypoint() override { return [_objcOwner isWaypoint]; }
    bool validForAddToUniverse() override { return [_objcOwner validForAddToUniverse]; }
    void wasAddedToUniverse() override { [_objcOwner wasAddedToUniverse]; }
    void wasRemovedFromUniverse() override { [_objcOwner wasRemovedFromUniverse]; }
    void warnAboutHostiles() override { [_objcOwner warnAboutHostiles]; }
    void throwSparks() override { [_objcOwner throwSparks]; }
    void setOwner(cxx::Entity* ent) override { [_objcOwner setOwner:ToObjC(ent)]; }
    void setPosition(HPVector posn) override { [_objcOwner setPosition:posn]; }
    GLfloat cameraRangeFront() override { return [_objcOwner cameraRangeFront]; }
    GLfloat cameraRangeBack() override { return [_objcOwner cameraRangeBack]; }
    void updateCameraRelativePosition() override { [_objcOwner updateCameraRelativePosition]; }
    OOComparisonResult compareZeroDistance(cxx::Entity* otherEntity) override { return [_objcOwner compareZeroDistance:ToObjC(otherEntity)]; }
    void setOrientation(Quaternion quat) override { [_objcOwner setOrientation:quat]; }
    Quaternion normalOrientation() override { return [_objcOwner normalOrientation]; }
    void setNormalOrientation(Quaternion quat) override { [_objcOwner setNormalOrientation:quat]; }
    void orientationChanged() override { [_objcOwner orientationChanged]; }
    Vector getVelocity() override { return [_objcOwner velocity]; }
    void setStatus(OOEntityStatus stat) override { [_objcOwner setStatus:stat]; }
    OOScanClass getScanClass() override { return [_objcOwner scanClass]; }
    void applyRoll(GLfloat roll, GLfloat climb) override { [_objcOwner applyRoll:roll andClimb:climb]; }
    void applyRoll(GLfloat roll, GLfloat climb, GLfloat yaw) override { [_objcOwner applyRoll:roll climb:climb andYaw:yaw]; }
    void moveForward(double amount) override { [_objcOwner moveForward:amount]; }
    OOMatrix drawRotationMatrix() override { return [_objcOwner drawRotationMatrix]; }
    OOMatrix drawTransformationMatrix() override { return [_objcOwner drawTransformationMatrix]; }
    bool canCollide() override { return [_objcOwner canCollide]; }
    GLfloat collisionRadius() override { return [_objcOwner collisionRadius]; }
    GLfloat frustumRadius() override { return [_objcOwner frustumRadius]; }
    void update(OOTimeDelta delta_t) override { [_objcOwner update:delta_t]; }
    bool checkCloseCollisionWith(cxx::Entity* other) override { return [_objcOwner checkCloseCollisionWith:ToObjC(other)]; }
    void takeEnergyDamage(double amount, cxx::Entity* ent, cxx::Entity* other, const std::string& weaponIdentifier) override { [_objcOwner takeEnergyDamage:amount from:ToObjC(ent) becauseOf:ToObjC(other) weaponIdentifier:weaponIdentifier]; }
    void dumpSelfState() override { [_objcOwner dumpSelfState]; }
    void subEntityReallyDied(ShipEntity* sub) override { [_objcOwner subEntityReallyDied:sub]; }
    double findCollisionRadius() override { return [_objcOwner findCollisionRadius]; }
    void drawImmediate(bool immediate, bool translucent) override { [_objcOwner drawImmediate:immediate translucent:translucent]; }
    bool isVisible() override { return [_objcOwner isVisible]; }
    std::optional<std::string> descriptionComponents() const override { return [_objcOwner cxx_descriptionComponents]; }
#ifdef OO_DEBUG_MONITOR_ENABLED
    std::optional<std::string> descriptionForObjDump() override { return [_objcOwner descriptionForObjDump]; }
    std::vector<ObjCRef<OOTexture*>> allTextures() override { return [_objcOwner cxx_allTextures]; }
#endif

    NSUInteger superSessionID() override { return Base::sessionID(); }
    bool superIsDock() override { return Base::isDock(); }
    bool superIsPlanet() override { return Base::isPlanet(); }
    bool superIsSun() override { return Base::isSun(); }
    bool superIsSky() override { return Base::isSky(); }
    bool superIsEffect() override { return Base::isEffect(); }
    bool superGetIsVisualEffect() override { return Base::getIsVisualEffect(); }
    bool superIsWaypoint() override { return Base::isWaypoint(); }
    bool superValidForAddToUniverse() override { return Base::validForAddToUniverse(); }
    void superWasAddedToUniverse() override { Base::wasAddedToUniverse(); }
    void superWasRemovedFromUniverse() override { Base::wasRemovedFromUniverse(); }
    void superWarnAboutHostiles() override { Base::warnAboutHostiles(); }
    void superThrowSparks() override { Base::throwSparks(); }
    void superSetOwner(cxx::Entity* ent) override { Base::setOwner(ent); }
    void superSetPosition(HPVector posn) override { Base::setPosition(posn); }
    GLfloat superCameraRangeFront() override { return Base::cameraRangeFront(); }
    GLfloat superCameraRangeBack() override { return Base::cameraRangeBack(); }
    void superUpdateCameraRelativePosition() override { Base::updateCameraRelativePosition(); }
    OOComparisonResult superCompareZeroDistance(cxx::Entity* otherEntity) override { return Base::compareZeroDistance(otherEntity); }
    void superSetOrientation(Quaternion quat) override { Base::setOrientation(quat); }
    Quaternion superNormalOrientation() override { return Base::normalOrientation(); }
    void superSetNormalOrientation(Quaternion quat) override { Base::setNormalOrientation(quat); }
    void superOrientationChanged() override { Base::orientationChanged(); }
    Vector superGetVelocity() override { return Base::getVelocity(); }
    void superSetStatus(OOEntityStatus stat) override { Base::setStatus(stat); }
    OOScanClass superGetScanClass() override { return Base::getScanClass(); }
    void superApplyRoll(GLfloat roll, GLfloat climb) override { Base::applyRoll(roll, climb); }
    void superApplyRoll(GLfloat roll, GLfloat climb, GLfloat yaw) override { Base::applyRoll(roll, climb, yaw); }
    void superMoveForward(double amount) override { Base::moveForward(amount); }
    OOMatrix superDrawRotationMatrix() override { return Base::drawRotationMatrix(); }
    OOMatrix superDrawTransformationMatrix() override { return Base::drawTransformationMatrix(); }
    bool superCanCollide() override { return Base::canCollide(); }
    GLfloat superCollisionRadius() override { return Base::collisionRadius(); }
    GLfloat superFrustumRadius() override { return Base::frustumRadius(); }
    void superUpdate(OOTimeDelta delta_t) override { Base::update(delta_t); }
    bool superCheckCloseCollisionWith(cxx::Entity* other) override { return Base::checkCloseCollisionWith(other); }
    void superTakeEnergyDamage(double amount, cxx::Entity* ent, cxx::Entity* other, const std::string& weaponIdentifier) override { Base::takeEnergyDamage(amount, ent, other, weaponIdentifier); }
    void superDumpSelfState() override { Base::dumpSelfState(); }
    void superSubEntityReallyDied(ShipEntity* sub) override { Base::subEntityReallyDied(sub); }
    double superFindCollisionRadius() override { return Base::findCollisionRadius(); }
    void superDrawImmediate(bool immediate, bool translucent) override { Base::drawImmediate(immediate, translucent); }
    bool superIsVisible() override { return Base::isVisible(); }
    std::optional<std::string> superDescriptionComponents() const override { return Base::descriptionComponents(); }
#ifdef OO_DEBUG_MONITOR_ENABLED
    std::optional<std::string> superDescriptionForObjDump() override { return Base::descriptionForObjDump(); }
    std::vector<ObjCRef<OOTexture*>> superAllTextures() override { return Base::allTextures(); }
#endif
};

// The adapter half of an Objective-C entity's C++ part; null for a C++ entity.
inline ObjCEntityLink* AsObjCEntity(cxx::Entity* entity) { return dynamic_cast<ObjCEntityLink*>(entity); }

} // namespace oo

#endif // ENTITY_OBJCBRIDGE_H
