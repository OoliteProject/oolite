/*

PlayerEntitySound.m

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

#include "PlayerEntitySound.h"

#include "GameController.h"
#include "OOCallByName.h"  // oo::ScheduleEntityCall
#include "OOEquipmentType.h"
#include "OOMaths.h"
#include "OOSound.h"
#include "OOSoundSourcePool.h"
#include "ResourceManager.h"
#include "Universe.h"
#include "oofnd/String.hpp"

// Sizes of sound source pools

constexpr int kBuySellSourcePoolSize = 4;
constexpr int kWarningPoolSize = 6;
constexpr int kWeaponPoolSize = 3;
constexpr int kDamagePoolSize = 4;
constexpr int kMiscPoolSize = 2;

namespace {
// The player's sound sources and pools, each shared until destroySound(). The
// holder is never deleted, so exit(0) runs none of their destructors (the
// mixer and the logger are gone by then), as the statics' references before
// were never given up at exit either.
struct PlayerSounds {
  std::shared_ptr<OOSoundSourcePool> warningPool, weaponPool, damagePool,
      miscPool, buySellPool;
  std::shared_ptr<::OOSoundSource> hyperspace, interfaceBeep, ecm, breakPattern;
  std::shared_ptr<::OOSoundSource> afterburner[2];
};

PlayerSounds& Sounds() {
  static PlayerSounds& sounds = *new PlayerSounds();
  return sounds;
}
}  // namespace

// Each pool static shares its pool until ReleasePool. A message to a nil pool
// did nothing, so each play checks for none.
namespace {
void ReleasePool(std::shared_ptr<OOSoundSourcePool>& pool) { pool.reset(); }

// Each source static owns its source until ReleaseSource. A message to a nil
// source did nothing and -isPlaying answered NO, so each use checks for none.
std::shared_ptr<::OOSoundSource> NewSource(::OOSound* sound = nullptr) {
  return oo::makeShared<::OOSoundSource>(sound);
}

void ReleaseSource(std::shared_ptr<::OOSoundSource>& source) { source.reset(); }

bool IsPlaying(const std::shared_ptr<::OOSoundSource>& source) {
  return source != nullptr && source->isPlaying();
}
}  // namespace

// Weapon identifier -> sound key (empty: no sound key, as @"" was).
using OOWeaponSoundMap = std::map<std::string, std::string, std::less<>>;
namespace {
OOWeaponSoundMap weaponShotMiss;
OOWeaponSoundMap weaponShotHit;
OOWeaponSoundMap weaponShieldHit;
OOWeaponSoundMap weaponUnshieldedHit;
OOWeaponSoundMap weaponLaunched;
}  // namespace

static const Vector kInterfaceBeepPosition = {0.0f, -0.2f, 0.5f};
static const Vector kInterfaceWarningPosition = {0.0f, -0.2f, 0.4f};
static const Vector kBreakPatternPosition = {0.0f, 0.0f, 1.0f};
static const Vector kEcmPosition = {0.2f, 0.6f, -0.1f};
static const Vector kWitchspacePosition = {0.0f, -0.3f, -0.3f};
// maybe these should actually track engine positions
static const Vector kAfterburner1Position = {-0.1f, 0.0f, -1.0f};
static const Vector kAfterburner2Position = {0.1f, 0.0f, -1.0f};

namespace {

// The sound key for a weapon, or fallback when the weapon has none (the
// dictionary lookup gave nil).
std::string WeaponSoundKey(const OOWeaponSoundMap& sounds,
                           const std::string& weaponIdentifier,
                           const std::string& fallback) {
  const auto found = sounds.find(weaponIdentifier);
  return found != sounds.end() ? found->second : fallback;
}

}  // namespace

void PlayerEntity::setUpSound() {
  destroySound();

  Sounds().interfaceBeep = NewSource();
  Sounds().interfaceBeep->setPosition(kInterfaceBeepPosition);

  Sounds().breakPattern = NewSource();
  Sounds().breakPattern->setPosition(kBreakPatternPosition);

  Sounds().ecm = NewSource();
  Sounds().ecm->setPosition(kEcmPosition);

  Sounds().hyperspace = NewSource();
  Sounds().hyperspace->setPosition(kWitchspacePosition);

  Sounds().buySellPool =
      OOSoundSourcePool::poolWithCount(kBuySellSourcePoolSize, 0.0);
  Sounds().warningPool =
      OOSoundSourcePool::poolWithCount(kWarningPoolSize, 0.0);
  Sounds().weaponPool = OOSoundSourcePool::poolWithCount(kWeaponPoolSize, 0.0);
  Sounds().damagePool = OOSoundSourcePool::poolWithCount(
      kDamagePoolSize, 0.1);  // Repeat time limit is to avoid playing a scrape
                              // sound every frame on glancing scrapes. This
                              // does limit the number of laser hits that can
                              // be played in a furrball, though; maybe lasers
                              // and scrapes should use different pools.
  Sounds().miscPool = OOSoundSourcePool::poolWithCount(kMiscPoolSize, 0.0);

  // Two sources with the same sound are used to simulate looping.
  ::OOSound* afterburnerSound =
      ResourceManager::ooSoundNamed("afterburner1.ogg", std::string("Sounds"));
  Sounds().afterburner[0] = NewSource(afterburnerSound);
  Sounds().afterburner[0]->setPosition(kAfterburner1Position);
  Sounds().afterburner[1] = NewSource(afterburnerSound);
  Sounds().afterburner[1]->setPosition(kAfterburner2Position);
}

// sets up the sound key dictionaries for all the available
// weapons/missiles/mines defined.

void PlayerEntity::setUpWeaponSounds() {
  OOWeaponSoundMap shotMissSounds;
  OOWeaponSoundMap shotHitSounds;
  OOWeaponSoundMap shieldHitSounds;
  OOWeaponSoundMap unshieldedHitSounds;
  OOWeaponSoundMap weaponLaunchedSounds;

  // special case: turrets aren't defined with a "EQ_WEAPON" prefix, and plasma
  // shots don't have a matching equipment item, so add a unique entry here.
  // this could be overridden if an OXP creates an equipment item with this key.
  // plasma shots don't make a sound when fired, so we only need to provide for
  // the hit player sound keys.
  shieldHitSounds["EQ_WEAPON_PLASMA_SHOT"] = "[player-hit-by-weapon]";
  unshieldedHitSounds["EQ_WEAPON_PLASMA_SHOT"] = "[player-direct-hit]";
  // grab a local copy of the sound identifiers for weapons to make the process
  // of looking up a sound ref as fast as possible a missing sound identifier is
  // stored as an empty key
  auto assignSound = [](OOWeaponSoundMap& sounds, ::OOEquipmentType* eqType,
                        std::string soundName) {
    sounds[(eqType != nullptr ? eqType->identifier()
                              : std::optional<std::string>())
               .value_or("")] = std::move(soundName);
  };

  for (const std::shared_ptr<::OOEquipmentType>& eqTypeRef :
       OOEquipmentType::allEquipmentTypes()) {
    ::OOEquipmentType* eqType = eqTypeRef.get();
    if (oo::str::hasPrefix((eqType != nullptr ? eqType->identifier()
                                              : std::optional<std::string>())
                               .value_or(""),
                           "EQ_WEAPON")) {
      assignSound(shotMissSounds, eqType,
                  (eqType != nullptr ? eqType->fxShotMissName()
                                     : std::optional<std::string>())
                      .value_or(""));
      assignSound(shotHitSounds, eqType,
                  (eqType != nullptr ? eqType->fxShotHitName()
                                     : std::optional<std::string>())
                      .value_or(""));
      assignSound(shieldHitSounds, eqType,
                  (eqType != nullptr ? eqType->fxShieldHitName()
                                     : std::optional<std::string>())
                      .value_or(""));
      assignSound(unshieldedHitSounds, eqType,
                  (eqType != nullptr ? eqType->fxUnshieldedHitName()
                                     : std::optional<std::string>())
                      .value_or(""));
    }
    if ((eqType != nullptr ? eqType->isMissileOrMine() : false)) {
      assignSound(weaponLaunchedSounds, eqType,
                  (eqType != nullptr ? eqType->fxWeaponLaunchedName()
                                     : std::optional<std::string>())
                      .value_or(""));
      assignSound(shieldHitSounds, eqType,
                  (eqType != nullptr ? eqType->fxShieldHitName()
                                     : std::optional<std::string>())
                      .value_or(""));
      assignSound(unshieldedHitSounds, eqType,
                  (eqType != nullptr ? eqType->fxUnshieldedHitName()
                                     : std::optional<std::string>())
                      .value_or(""));
    }
  }

  weaponShotMiss = std::move(shotMissSounds);
  weaponShotHit = std::move(shotHitSounds);
  weaponShieldHit = std::move(shieldHitSounds);
  weaponUnshieldedHit = std::move(unshieldedHitSounds);
  weaponLaunched = std::move(weaponLaunchedSounds);
}

void PlayerEntity::destroySound() {
  ReleaseSource(Sounds().interfaceBeep);
  ReleaseSource(Sounds().breakPattern);
  ReleaseSource(Sounds().ecm);
  ReleaseSource(Sounds().hyperspace);

  ReleaseSource(Sounds().afterburner[0]);
  ReleaseSource(Sounds().afterburner[1]);

  ReleasePool(Sounds().buySellPool);
  ReleasePool(Sounds().warningPool);
  ReleasePool(Sounds().weaponPool);
  ReleasePool(Sounds().damagePool);
  ReleasePool(Sounds().miscPool);

  weaponShotMiss.clear();
  weaponShotHit.clear();
  weaponShieldHit.clear();
  weaponUnshieldedHit.clear();
  weaponLaunched.clear();
}

void PlayerEntity::playInterfaceBeep(const std::string& beepKey) {
#if OOLITE_WINDOWS
  if (status() == OOEntityStatus::kStartGame) {
    return;
  }
#endif
  if (Sounds().interfaceBeep != nullptr)
    Sounds().interfaceBeep->playOOSound(OOSoundWithCustomSoundKey(beepKey));
}

bool PlayerEntity::isBeeping() { return IsPlaying(Sounds().interfaceBeep); }

void PlayerEntity::boop() { playInterfaceBeep("[general-boop]"); }

void PlayerEntity::playIdentOn() { playInterfaceBeep("[ident-on]"); }

void PlayerEntity::playIdentOff() { playInterfaceBeep("[ident-off]"); }

void PlayerEntity::playIdentLockedOn() {
  playInterfaceBeep("[ident-locked-on]");
}

void PlayerEntity::playMissileArmed() { playInterfaceBeep("[missile-armed]"); }

void PlayerEntity::playMineArmed() { playInterfaceBeep("[mine-armed]"); }

void PlayerEntity::playMissileSafe() { playInterfaceBeep("[missile-safe]"); }

void PlayerEntity::playMissileLockedOn() {
  playInterfaceBeep("[missile-locked-on]");
}

void PlayerEntity::playNextEquipmentSelected() {
  playInterfaceBeep("[next-equipment-selected]");
}

void PlayerEntity::playNextMissileSelected() {
  playInterfaceBeep("[next-missile-selected]");
}

void PlayerEntity::playWeaponsOnline() {
  playInterfaceBeep("[weapons-online]");
}

void PlayerEntity::playWeaponsOffline() {
  playInterfaceBeep("[weapons-offline]");
}

void PlayerEntity::playCargoJettisioned() {
  playInterfaceBeep("[cargo-jettisoned]");
}

void PlayerEntity::playAutopilotOn() { playInterfaceBeep("[autopilot-on]"); }

void PlayerEntity::playAutopilotOff() {
  // only if still alive
  if (energy > 0.0) {
    playInterfaceBeep("[autopilot-off]");
  }
}

void PlayerEntity::playAutopilotOutOfRange() {
  playInterfaceBeep("[autopilot-out-of-range]");
}

void PlayerEntity::playAutopilotCannotDockWithTarget() {
  playInterfaceBeep("[autopilot-cannot-dock-with-target]");
}

void PlayerEntity::playSaveOverwriteYes() {
  playInterfaceBeep("[save-overwrite-yes]");
}

void PlayerEntity::playSaveOverwriteNo() {
  playInterfaceBeep("[save-overwrite-no]");
}

void PlayerEntity::playHoldFull() { playInterfaceBeep("[hold-full]"); }

void PlayerEntity::playJumpMassLocked() {
  playInterfaceBeep("[jump-mass-locked]");
}

void PlayerEntity::playTargetLost() { playInterfaceBeep("[target-lost]"); }

void PlayerEntity::playNoTargetInMemory() {
  playInterfaceBeep("[no-target-in-memory]");
}

void PlayerEntity::playTargetSwitched() {
  playInterfaceBeep("[target-switched]");
}

void PlayerEntity::playHyperspaceNoTarget() {
  playInterfaceBeep("[witch-no-target]");
}

void PlayerEntity::playHyperspaceNoFuel() {
  playInterfaceBeep("[witch-no-fuel]");
}

void PlayerEntity::playHyperspaceBlocked() {
  playInterfaceBeep("[hyperspace-blocked]");
}

void PlayerEntity::playHyperspaceDistanceTooGreat() {
  playInterfaceBeep("[witch-too-far]");
}

void PlayerEntity::playCloakingDeviceOn() {
  playInterfaceBeep("[cloaking-device-on]");
}

void PlayerEntity::playCloakingDeviceOff() {
  playInterfaceBeep("[cloaking-device-off]");
}

void PlayerEntity::playMenuNavigationUp() {
  playInterfaceBeep("[menu-navigation-up]");
}

void PlayerEntity::playMenuNavigationDown() {
  playInterfaceBeep("[menu-navigation-down]");
}

void PlayerEntity::playMenuNavigationNot() {
  playInterfaceBeep("[menu-navigation-not]");
}

void PlayerEntity::playMenuPagePrevious() {
  playInterfaceBeep("[menu-next-page]");
}

void PlayerEntity::playMenuPageNext() {
  playInterfaceBeep("[menu-previous-page]");
}

void PlayerEntity::playDismissedReportScreen() {
  playInterfaceBeep("[dismissed-report-screen]");
}

void PlayerEntity::playDismissedMissionScreen() {
  playInterfaceBeep("[dismissed-mission-screen]");
}

void PlayerEntity::playChangedOption() {
  playInterfaceBeep("[changed-option]");
}

void PlayerEntity::updateFuelScoopSoundWithInterval(OOTimeDelta delta_t) {
  static double scoopSoundPlayTime = 0.0;
  scoopSoundPlayTime -= delta_t;
  if (scoopSoundPlayTime < 0.0) {
    if (!IsPlaying(Sounds().interfaceBeep)) {
      /* TODO: this should use the scoop position, not the standard
       * interface beep position */
      playInterfaceBeep("[scoop]");
      scoopSoundPlayTime = 0.5;
    } else
      scoopSoundPlayTime = 0.0;
  }
  if (!scoopOverride) {
    scoopSoundPlayTime = 0.0;
  }
}

// time delay method for playing afterburner sounds
// this overlaps two sounds each 2 seconds long, but with a 0.75s
// crossfade

void PlayerEntity::updateAfterburnerSound() {
  static uint8_t which = 0;

  if (!afterburner_engaged)  // end the loop cycle
  {
    afterburnerSoundLooping = false;
  }

  if (afterburnerSoundLooping) {
    if (Sounds().afterburner[which] != nullptr)
      Sounds().afterburner[which]->play();
    which = !which;

    // and swap sounds in 1.25s time (a deferred call on the player)
    oo::ScheduleEntityCall(
        this,
        [](Entity* entity) {
          if (PlayerEntity* player = dynamic_cast<PlayerEntity*>(entity))
            player->updateAfterburnerSound();
        },
        1.25);
  }
}

void PlayerEntity::startAfterburnerSound() {
  if (!afterburnerSoundLooping) {
    afterburnerSoundLooping = true;
    updateAfterburnerSound();
  }
}

void PlayerEntity::stopAfterburnerSound() {
  // Do nothing, stop is detected in updateAfterburnerSound
}

void PlayerEntity::playCloakingDeviceInsufficientEnergy() {
  playInterfaceBeep("[cloaking-device-insufficent-energy]");
}

void PlayerEntity::playBuyCommodity() {
  if (Sounds().buySellPool != nullptr)
    Sounds().buySellPool->playSoundWithKey("[buy-commodity]");
}

void PlayerEntity::playBuyShip() {
  if (Sounds().buySellPool != nullptr)
    Sounds().buySellPool->playSoundWithKey("[buy-ship]");
}

void PlayerEntity::playSellCommodity() {
  if (Sounds().buySellPool != nullptr)
    Sounds().buySellPool->playSoundWithKey("[sell-commodity]");
}

void PlayerEntity::playCantBuyCommodity() {
  if (Sounds().buySellPool != nullptr)
    Sounds().buySellPool->playSoundWithKey("[could-not-buy-commodity]");
}

void PlayerEntity::playCantSellCommodity() {
  if (Sounds().buySellPool != nullptr)
    Sounds().buySellPool->playSoundWithKey("[could-not-sell-commodity]");
}

void PlayerEntity::playCantBuyShip() {
  if (Sounds().buySellPool != nullptr)
    Sounds().buySellPool->playSoundWithKey("[could-not-buy-ship]");
}

void PlayerEntity::playStandardHyperspace() {
  OOSoundSourcePlayCustomSoundWithKey(Sounds().hyperspace.get(),
                                      "[hyperspace-countdown-begun]");
}

void PlayerEntity::playGalacticHyperspace() {
  OOSoundSourcePlayCustomSoundWithKey(Sounds().hyperspace.get(),
                                      "[galactic-hyperspace-countdown-begun]");
}

void PlayerEntity::playHyperspaceAborted() {
  OOSoundSourcePlayCustomSoundWithKey(Sounds().hyperspace.get(),
                                      "[hyperspace-countdown-aborted]");
}

void PlayerEntity::playHitByECMSound() {
  if (!IsPlaying(Sounds().ecm))
    OOSoundSourcePlayCustomSoundWithKey(Sounds().ecm.get(),
                                        "[player-hit-by-ecm]");
}

void PlayerEntity::playFiredECMSound() {
  if (!IsPlaying(Sounds().ecm))
    OOSoundSourcePlayCustomSoundWithKey(Sounds().ecm.get(),
                                        "[player-fired-ecm]");
}

void PlayerEntity::playLaunchFromStation() {
  OOSoundSourcePlayCustomSoundWithKey(Sounds().breakPattern.get(),
                                      "[player-launch-from-station]");
}

void PlayerEntity::playDockWithStation() {
  OOSoundSourcePlayCustomSoundWithKey(Sounds().breakPattern.get(),
                                      "[player-dock-with-station]");
}

void PlayerEntity::playExitWitchspace() {
  OOSoundSourcePlayCustomSoundWithKey(Sounds().breakPattern.get(),
                                      "[player-exit-witchspace]");
}

void PlayerEntity::playHostileWarning() {
  if (Sounds().warningPool != nullptr)
    Sounds().warningPool->playSoundWithKey("[hostile-warning]", 1.0f,
                                           kInterfaceWarningPosition);
}

void PlayerEntity::playAlertConditionRed() {
  if (Sounds().warningPool != nullptr)
    Sounds().warningPool->playSoundWithKey("[alert-condition-red]", 2.0f,
                                           kInterfaceWarningPosition);
}

void PlayerEntity::playIncomingMissile(Vector missileVector) {
  if (Sounds().warningPool != nullptr)
    Sounds().warningPool->playSoundWithKey("[incoming-missile]", 3.0f,
                                           missileVector);
}

void PlayerEntity::playEnergyLow() {
  if (Sounds().warningPool != nullptr)
    Sounds().warningPool->playSoundWithKey("[energy-low]", 0.5f,
                                           kInterfaceWarningPosition);
}

void PlayerEntity::playDockingDenied() {
  if (Sounds().warningPool != nullptr)
    Sounds().warningPool->playSoundWithKey("[autopilot-denied]", 1.0f,
                                           kInterfaceWarningPosition);
}

void PlayerEntity::playWitchjumpFailure() {
  if (Sounds().warningPool != nullptr)
    Sounds().warningPool->playSoundWithKey("[witchdrive-failure]", 1.5f,
                                           kWitchspacePosition);
}

void PlayerEntity::playWitchjumpMisjump() {
  if (Sounds().warningPool != nullptr)
    Sounds().warningPool->playSoundWithKey("[witchdrive-malfunction]", 1.5f,
                                           kWitchspacePosition);
}

void PlayerEntity::playWitchjumpBlocked() {
  if (Sounds().warningPool != nullptr)
    Sounds().warningPool->playSoundWithKey("[witch-blocked-by-@]", 1.3f,
                                           kWitchspacePosition);
}

void PlayerEntity::playWitchjumpDistanceTooGreat() {
  if (Sounds().warningPool != nullptr)
    Sounds().warningPool->playSoundWithKey("[witch-too-far]", 1.3f,
                                           kWitchspacePosition);
}

void PlayerEntity::playWitchjumpInsufficientFuel() {
  if (Sounds().warningPool != nullptr)
    Sounds().warningPool->playSoundWithKey("[witch-no-fuel]", 1.3f,
                                           kWitchspacePosition);
}

void PlayerEntity::playFuelLeak() {
  if (Sounds().warningPool != nullptr)
    Sounds().warningPool->playSoundWithKey("[fuel-leak]", 0.5f,
                                           kWitchspacePosition);
}

void PlayerEntity::playShieldHit(Vector attackVector,
                                 const std::string& weaponIdentifier) {
  if (Sounds().damagePool != nullptr)
    Sounds().damagePool->playSoundWithKey(
        WeaponSoundKey(weaponShieldHit, weaponIdentifier,
                       "[player-hit-by-weapon]"),
        attackVector);
}

void PlayerEntity::playDirectHit(Vector attackVector,
                                 const std::string& weaponIdentifier) {
  if (Sounds().damagePool != nullptr)
    Sounds().damagePool->playSoundWithKey(
        WeaponSoundKey(weaponUnshieldedHit, weaponIdentifier,
                       "[player-direct-hit]"),
        attackVector);
}

void PlayerEntity::playScrapeDamage(Vector attackVector) {
  if (Sounds().damagePool != nullptr)
    Sounds().damagePool->playSoundWithKey("[player-scrape-damage]",
                                          attackVector);
}

void PlayerEntity::playLaserHit(bool hit, Vector weaponOffset,
                                const std::string& weaponIdentifier) {
  if (hit) {
    if (Sounds().weaponPool != nullptr)
      Sounds().weaponPool->playSoundWithKey(
          WeaponSoundKey(weaponShotHit, weaponIdentifier, "[player-laser-hit]"),
          1.0f, 0.05, static_cast<bool>(true), weaponOffset);
  } else {
    if (Sounds().weaponPool != nullptr)
      Sounds().weaponPool->playSoundWithKey(
          WeaponSoundKey(weaponShotMiss, weaponIdentifier,
                         "[player-laser-miss]"),
          1.0f, 0.05, static_cast<bool>(true), weaponOffset);
  }
}

void PlayerEntity::playWeaponOverheated(Vector weaponOffset) {
  if (Sounds().weaponPool != nullptr)
    Sounds().weaponPool->playSoundWithKey(
        "[weapon-overheat]", static_cast<bool>(false), weaponOffset);
}

void PlayerEntity::playMissileLaunched(Vector weaponOffset,
                                       const std::string& weaponIdentifier) {
  if (Sounds().weaponPool != nullptr)
    Sounds().weaponPool->playSoundWithKey(
        WeaponSoundKey(weaponLaunched, weaponIdentifier, "[missile_launched]"),
        weaponOffset);
}

void PlayerEntity::playMineLaunched(Vector weaponOffset,
                                    const std::string& weaponIdentifier) {
  if (Sounds().weaponPool != nullptr)
    Sounds().weaponPool->playSoundWithKey(
        WeaponSoundKey(weaponLaunched, weaponIdentifier, "[mine_launched]"),
        weaponOffset);
}

void PlayerEntity::playEscapePodScooped() {
  if (Sounds().miscPool != nullptr)
    Sounds().miscPool->playSoundWithKey("[escape-pod-scooped]",
                                        kInterfaceBeepPosition);
}

void PlayerEntity::playAegisCloseToPlanet() {
  if (Sounds().miscPool != nullptr)
    Sounds().miscPool->playSoundWithKey("[aegis-planet]",
                                        kInterfaceBeepPosition);
}

void PlayerEntity::playAegisCloseToStation() {
  if (Sounds().miscPool != nullptr)
    Sounds().miscPool->playSoundWithKey("[aegis-station]",
                                        kInterfaceBeepPosition);
}

void PlayerEntity::playGameOver() {
  if (Sounds().miscPool != nullptr)
    Sounds().miscPool->playSoundWithKey("[game-over]");
}

void PlayerEntity::playLegacyScriptSound(const std::string& key) {
  if (Sounds().miscPool != nullptr)
    Sounds().miscPool->playSoundWithKey(key, 1.1f);
}
