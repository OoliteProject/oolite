/*

OOTrumble.h

Implements cute, fuzzy trumbles.

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

#include "OOEnumFlags.h"
#include "OOFoundation.h"
#include "OOOpenGL.h"
#include "oofnd/PList.hpp"
#include "oofnd/Ref.hpp"

class AI;  // AI.h
class OOTexture;
class PlayerEntity;
class OOSound;

#define TRUMBLE_MAX_ROTATION 15.0
#define TRUMBLE_MAX_ROTATIONAL_VELOCITY 5.0

#define TRUMBLE_GROWTH_RATE 0.01

enum class trumble_animation : int {
  kNone = 0,
  kIdle,
  kBlink,
  kSnarl,
  kProot,
  kShudder,
  kStoned,
  kSpawn,
  kSleep,
  kDie,
};
static_assert(static_cast<int>(trumble_animation::kNone) == 0);
static_assert(static_cast<int>(trumble_animation::kIdle) == 1);
static_assert(static_cast<int>(trumble_animation::kBlink) == 2);
static_assert(static_cast<int>(trumble_animation::kSnarl) == 3);
static_assert(static_cast<int>(trumble_animation::kProot) == 4);
static_assert(static_cast<int>(trumble_animation::kShudder) == 5);
static_assert(static_cast<int>(trumble_animation::kStoned) == 6);
static_assert(static_cast<int>(trumble_animation::kSpawn) == 7);
static_assert(static_cast<int>(trumble_animation::kSleep) == 8);
static_assert(static_cast<int>(trumble_animation::kDie) == 9);

enum class trumble_eyes : int {
  kNone = 0,
  kOpen,
  kShut,
  kWide,
};
static_assert(static_cast<int>(trumble_eyes::kNone) == 0);
static_assert(static_cast<int>(trumble_eyes::kOpen) == 1);
static_assert(static_cast<int>(trumble_eyes::kShut) == 2);
static_assert(static_cast<int>(trumble_eyes::kWide) == 3);

enum class trumble_mouth : int {
  kNone = 0,
  kPout,
  kGrowl,
  kSnarl,
  kNormal,
};
static_assert(static_cast<int>(trumble_mouth::kNone) == 0);
static_assert(static_cast<int>(trumble_mouth::kPout) == 1);
static_assert(static_cast<int>(trumble_mouth::kGrowl) == 2);
static_assert(static_cast<int>(trumble_mouth::kSnarl) == 3);
static_assert(static_cast<int>(trumble_mouth::kNormal) == 4);

struct OOTrumbleTestAccess;  // tests/unit/core/test_OOTrumble.cpp

class OOTrumble : public oo::RefCounted {
 public:
  OOTrumble();  // -init
  explicit OOTrumble(::PlayerEntity* p1);
  OOTrumble(::PlayerEntity* p1, const std::string& digramString);

  void setupForPlayer(::PlayerEntity* p1, const std::string& digramString);

  void spawnFrom(OOTrumble* parentTrumble);

  void calcGrowthRate();

  // The getters of the ivars of the same name (a data member and a member
  // function cannot share a name).
  uint16_t* getDigram();
  NSPoint getPosition();
  NSPoint getMovement();
  GLfloat getRotation();
  GLfloat getSize();
  GLfloat getHunger();
  GLfloat getDiscomfort();

  // AI methods here
  void actionIdle();
  void actionBlink();
  void actionSnarl();
  void actionProot();
  void actionShudder();
  void actionStoned();
  void actionPop();
  void actionSleep();
  void actionSpawn();

  void randomizeMotionX();
  void randomizeMotionY();

  void drawTrumble(double z);
  void updateTrumble(double delta_t);

  void updateIdle(double delta_t);
  void updateBlink(double delta_t);
  void updateSnarl(double delta_t);
  void updateProot(double delta_t);
  void updateShudder(double delta_t);
  void updateStoned(double delta_t);
  void updatePop(double delta_t);
  void updateSleep(double delta_t);
  void updateSpawn(double delta_t);

  oo::PList dictionary();  // the savegame record: a dictionary
  void setFromDictionary(const oo::PList& dict);

 private:
  friend struct ::OOTrumbleTestAccess;  // the test reads the private state

  ::PlayerEntity* player = {};  // owning entity (not retained)
  //
  uint16_t digram[2] =
      {};  // seed for pseudo-randomly setting up Trumble (pair of characters)
  //
  GLfloat colorBase[4] = {};    // color of Trumble
  GLfloat colorPoint1[4] = {};  // color of Trumble (variation 1)
  GLfloat colorPoint2[4] = {};  // color of Trumble	(variation 2)
  GLfloat colorEyes[4] = {};    // color of Trumble (eye color)
  GLfloat* pointColor[6] = {};  // pointscheme
  //
  GLfloat hunger = {};  // behaviour modifier 0.0 (satiated) to 1.0 (starving)
  GLfloat discomfort = {};  // behaviour modifier 0.0 (very happy) to 1.0
                            // (extremely uncomfortable)
  //
  GLfloat size = {};         // 0.0 -> max_size
  GLfloat max_size = {};     // 0.90 -> 1.25
  GLfloat growth_rate = {};  // diff to size per sec.
  //
  GLfloat rotation = {};             // CW rotation in radians (starts at 0.0)
  GLfloat rotational_velocity = {};  // +r (radians/sec)
  //
  NSPoint position = {};  // x, y onscreen relative to center of screen
  NSPoint movement = {};  // +x, +y (screen units / sec)
  //
  NSPoint eye_position =
      {};  // current position of eyes relative to their starting position
  NSPoint mouth_position =
      {};  // current position of eyes relative to their starting position
  //
  double animationTime = {};      // set to 0.0 at start of current animation
  double animationDuration = {};  // set to 0.0 at start of current animation
  //
  trumble_animation animation = {};      // current animation sequence
  trumble_animation nextAnimation = {};  // next animation sequence
  //
  int animationStage = {};  // sub-sequence within animation
  //
  trumble_mouth mouthFrame = {};  // which mouth position - determines what
                                  // part of the texture to display
  trumble_eyes eyeFrame = {};     // which eye position - determines what part
                                  // of the texture to display
  //
  std::shared_ptr<OOTexture> texture;
  //
  GLfloat saved_float1 = {}, saved_float2 = {};
  //
  bool readyToSpawn = {};
};
