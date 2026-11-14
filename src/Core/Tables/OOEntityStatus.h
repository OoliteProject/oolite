

/*	OOEntityStatus.h

The values of an entity's status: saves, JS and callObjC (encoded "i",
OOTypeEncodings.h), and the names the game reads and writes for them. It was
OOEntityStatus.tbl, an X-macro table.
*/

#pragma once

#include <cstdint>
#include <string_view>

#include "OOEnumFlags.h"
#include "OOEnumTable.h"

enum class OOEntityStatus : std::int32_t {
  kStartGame = -10,
  kRestartGame = -2,
  kDead = -1,
  kInactive = 0,
  kTest = 1,
  kCockpitDisplay = 2,
  kActive = 5,
  kEffect = 10,
  kInFlight = 100,
  kDocked = 200,
  kAutopilotEngaged = 300,
  kDocking = 401,
  kLaunching = 402,
  kWitchspaceCountdown = 410,
  kEnteringWitchspace = 411,
  kExitingWitchspace = 412,
  kEscapeSequence = 500,
  kInHold = 600,
  kBeingScooped = 700,
  kHandlingError = 999,
};

// What an unknown name reads as.
inline constexpr OOEntityStatus kOOEntityStatusDefault =
    OOEntityStatus::kInactive;

// The name of each value. No default: -Wswitch reports a value added without
// one.
constexpr std::string_view OOEnumName(OOEntityStatus value) noexcept {
  switch (value) {
    case OOEntityStatus::kStartGame:
      return "STATUS_START_GAME";
    case OOEntityStatus::kRestartGame:
      return "STATUS_RESTART_GAME";
    case OOEntityStatus::kDead:
      return "STATUS_DEAD";
    case OOEntityStatus::kInactive:
      return "STATUS_INACTIVE";
    case OOEntityStatus::kTest:
      return "STATUS_TEST";
    case OOEntityStatus::kCockpitDisplay:
      return "STATUS_COCKPIT_DISPLAY";
    case OOEntityStatus::kActive:
      return "STATUS_ACTIVE";
    case OOEntityStatus::kEffect:
      return "STATUS_EFFECT";
    case OOEntityStatus::kInFlight:
      return "STATUS_IN_FLIGHT";
    case OOEntityStatus::kDocked:
      return "STATUS_DOCKED";
    case OOEntityStatus::kAutopilotEngaged:
      return "STATUS_AUTOPILOT_ENGAGED";
    case OOEntityStatus::kDocking:
      return "STATUS_DOCKING";
    case OOEntityStatus::kLaunching:
      return "STATUS_LAUNCHING";
    case OOEntityStatus::kWitchspaceCountdown:
      return "STATUS_WITCHSPACE_COUNTDOWN";
    case OOEntityStatus::kEnteringWitchspace:
      return "STATUS_ENTERING_WITCHSPACE";
    case OOEntityStatus::kExitingWitchspace:
      return "STATUS_EXITING_WITCHSPACE";
    case OOEntityStatus::kEscapeSequence:
      return "STATUS_ESCAPE_SEQUENCE";
    case OOEntityStatus::kInHold:
      return "STATUS_IN_HOLD";
    case OOEntityStatus::kBeingScooped:
      return "STATUS_BEING_SCOOPED";
    case OOEntityStatus::kHandlingError:
      return "STATUS_HANDLING_ERROR";
  }
  return {};
}

inline constexpr auto kOOEntityStatusTable = oo::MakeEnumTable<
    OOEntityStatus, OOEntityStatus::kStartGame, OOEntityStatus::kRestartGame,
    OOEntityStatus::kDead, OOEntityStatus::kInactive, OOEntityStatus::kTest,
    OOEntityStatus::kCockpitDisplay, OOEntityStatus::kActive,
    OOEntityStatus::kEffect, OOEntityStatus::kInFlight, OOEntityStatus::kDocked,
    OOEntityStatus::kAutopilotEngaged, OOEntityStatus::kDocking,
    OOEntityStatus::kLaunching, OOEntityStatus::kWitchspaceCountdown,
    OOEntityStatus::kEnteringWitchspace, OOEntityStatus::kExitingWitchspace,
    OOEntityStatus::kEscapeSequence, OOEntityStatus::kInHold,
    OOEntityStatus::kBeingScooped, OOEntityStatus::kHandlingError>();

// Every number that leaves the program, pinned.
static_assert(oo::ToUnderlying(OOEntityStatus::kStartGame) == -10);
static_assert(oo::ToUnderlying(OOEntityStatus::kRestartGame) == -2);
static_assert(oo::ToUnderlying(OOEntityStatus::kDead) == -1);
static_assert(oo::ToUnderlying(OOEntityStatus::kInactive) == 0);
static_assert(oo::ToUnderlying(OOEntityStatus::kTest) == 1);
static_assert(oo::ToUnderlying(OOEntityStatus::kCockpitDisplay) == 2);
static_assert(oo::ToUnderlying(OOEntityStatus::kActive) == 5);
static_assert(oo::ToUnderlying(OOEntityStatus::kEffect) == 10);
static_assert(oo::ToUnderlying(OOEntityStatus::kInFlight) == 100);
static_assert(oo::ToUnderlying(OOEntityStatus::kDocked) == 200);
static_assert(oo::ToUnderlying(OOEntityStatus::kAutopilotEngaged) == 300);
static_assert(oo::ToUnderlying(OOEntityStatus::kDocking) == 401);
static_assert(oo::ToUnderlying(OOEntityStatus::kLaunching) == 402);
static_assert(oo::ToUnderlying(OOEntityStatus::kWitchspaceCountdown) == 410);
static_assert(oo::ToUnderlying(OOEntityStatus::kEnteringWitchspace) == 411);
static_assert(oo::ToUnderlying(OOEntityStatus::kExitingWitchspace) == 412);
static_assert(oo::ToUnderlying(OOEntityStatus::kEscapeSequence) == 500);
static_assert(oo::ToUnderlying(OOEntityStatus::kInHold) == 600);
static_assert(oo::ToUnderlying(OOEntityStatus::kBeingScooped) == 700);
static_assert(oo::ToUnderlying(OOEntityStatus::kHandlingError) == 999);
