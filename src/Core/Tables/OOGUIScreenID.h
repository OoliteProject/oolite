/*	OOGUIScreenID.h

The values of a GUI screen: JS and callObjC (encoded "i", OOTypeEncodings.h) see
it. The numbers are the program's ordinals (kMain is 0, which OOJSGlobal reads
as no screen too), not the -1 that OOGUIScreenID.tbl wrote for every screen and
its macro discarded; and the names the game reads and writes for them. It was
OOGUIScreenID.tbl, an X-macro table.
*/

#pragma once

#include <cstdint>
#include <string_view>

#include "OOEnumFlags.h"
#include "OOEnumTable.h"

enum class OOGUIScreenID : std::int32_t {
  kMain = 0,
  kIntro1 = 1,
  kShipLibrary = 2,
  kKeyboard = 3,
  kNewGame = 4,
  kOXZManager = 5,
  kStatus = 6,
  kManifest = 7,
  kEquipShip = 8,
  kShipyard = 9,
  kLongRangeChart = 10,
  kShortRangeChart = 11,
  kSystemData = 12,
  kMarket = 13,
  kMarketInfo = 14,
  // kContracts,
  kOptions = 15,
  kGameOptions = 16,
  kLoad = 17,
  kSave = 18,
  kSaveOverwrite = 19,
  kStickMapper = 20,
  kStickProfile = 21,
  kMission = 22,
  kReport = 23,
  kInterfaces = 24,
  kKeyboardConfirmClear = 25,
  kKeyboardConfig = 26,
  kKeyboardEntry = 27,
  kKeyboardLayout = 28,
};

// What an unknown name reads as.
inline constexpr OOGUIScreenID kOOGUIScreenIDDefault = OOGUIScreenID::kMain;

// The name of each value. No default: -Wswitch reports a value added without
// one.
constexpr std::string_view OOEnumName(OOGUIScreenID value) noexcept {
  switch (value) {
    case OOGUIScreenID::kMain:
      return "GUI_SCREEN_MAIN";
    case OOGUIScreenID::kIntro1:
      return "GUI_SCREEN_INTRO1";
    case OOGUIScreenID::kShipLibrary:
      return "GUI_SCREEN_SHIPLIBRARY";
    case OOGUIScreenID::kKeyboard:
      return "GUI_SCREEN_KEYBOARD";
    case OOGUIScreenID::kNewGame:
      return "GUI_SCREEN_NEWGAME";
    case OOGUIScreenID::kOXZManager:
      return "GUI_SCREEN_OXZMANAGER";
    case OOGUIScreenID::kStatus:
      return "GUI_SCREEN_STATUS";
    case OOGUIScreenID::kManifest:
      return "GUI_SCREEN_MANIFEST";
    case OOGUIScreenID::kEquipShip:
      return "GUI_SCREEN_EQUIP_SHIP";
    case OOGUIScreenID::kShipyard:
      return "GUI_SCREEN_SHIPYARD";
    case OOGUIScreenID::kLongRangeChart:
      return "GUI_SCREEN_LONG_RANGE_CHART";
    case OOGUIScreenID::kShortRangeChart:
      return "GUI_SCREEN_SHORT_RANGE_CHART";
    case OOGUIScreenID::kSystemData:
      return "GUI_SCREEN_SYSTEM_DATA";
    case OOGUIScreenID::kMarket:
      return "GUI_SCREEN_MARKET";
    case OOGUIScreenID::kMarketInfo:
      return "GUI_SCREEN_MARKETINFO";
    // case OOGUIScreenID::kContracts:
    //   return "GUI_SCREEN_CONTRACTS";
    case OOGUIScreenID::kOptions:
      return "GUI_SCREEN_OPTIONS";
    case OOGUIScreenID::kGameOptions:
      return "GUI_SCREEN_GAMEOPTIONS";
    case OOGUIScreenID::kLoad:
      return "GUI_SCREEN_LOAD";
    case OOGUIScreenID::kSave:
      return "GUI_SCREEN_SAVE";
    case OOGUIScreenID::kSaveOverwrite:
      return "GUI_SCREEN_SAVE_OVERWRITE";
    case OOGUIScreenID::kStickMapper:
      return "GUI_SCREEN_STICKMAPPER";
    case OOGUIScreenID::kStickProfile:
      return "GUI_SCREEN_STICKPROFILE";
    case OOGUIScreenID::kMission:
      return "GUI_SCREEN_MISSION";
    case OOGUIScreenID::kReport:
      return "GUI_SCREEN_REPORT";
    case OOGUIScreenID::kInterfaces:
      return "GUI_SCREEN_INTERFACES";
    case OOGUIScreenID::kKeyboardConfirmClear:
      return "GUI_SCREEN_KEYBOARD_CONFIRMCLEAR";
    case OOGUIScreenID::kKeyboardConfig:
      return "GUI_SCREEN_KEYBOARD_CONFIG";
    case OOGUIScreenID::kKeyboardEntry:
      return "GUI_SCREEN_KEYBOARD_ENTRY";
    case OOGUIScreenID::kKeyboardLayout:
      return "GUI_SCREEN_KEYBOARD_LAYOUT";
  }
  return {};
}

inline constexpr auto kOOGUIScreenIDTable = oo::MakeEnumTable<
    OOGUIScreenID, OOGUIScreenID::kMain, OOGUIScreenID::kIntro1,
    OOGUIScreenID::kShipLibrary, OOGUIScreenID::kKeyboard,
    OOGUIScreenID::kNewGame, OOGUIScreenID::kOXZManager, OOGUIScreenID::kStatus,
    OOGUIScreenID::kManifest, OOGUIScreenID::kEquipShip,
    OOGUIScreenID::kShipyard, OOGUIScreenID::kLongRangeChart,
    OOGUIScreenID::kShortRangeChart, OOGUIScreenID::kSystemData,
    OOGUIScreenID::kMarket, OOGUIScreenID::kMarketInfo, OOGUIScreenID::kOptions,
    OOGUIScreenID::kGameOptions, OOGUIScreenID::kLoad, OOGUIScreenID::kSave,
    OOGUIScreenID::kSaveOverwrite, OOGUIScreenID::kStickMapper,
    OOGUIScreenID::kStickProfile, OOGUIScreenID::kMission,
    OOGUIScreenID::kReport, OOGUIScreenID::kInterfaces,
    OOGUIScreenID::kKeyboardConfirmClear, OOGUIScreenID::kKeyboardConfig,
    OOGUIScreenID::kKeyboardEntry, OOGUIScreenID::kKeyboardLayout>();

// Every number that leaves the program, pinned.
static_assert(oo::ToUnderlying(OOGUIScreenID::kMain) == 0);
static_assert(oo::ToUnderlying(OOGUIScreenID::kIntro1) == 1);
static_assert(oo::ToUnderlying(OOGUIScreenID::kShipLibrary) == 2);
static_assert(oo::ToUnderlying(OOGUIScreenID::kKeyboard) == 3);
static_assert(oo::ToUnderlying(OOGUIScreenID::kNewGame) == 4);
static_assert(oo::ToUnderlying(OOGUIScreenID::kOXZManager) == 5);
static_assert(oo::ToUnderlying(OOGUIScreenID::kStatus) == 6);
static_assert(oo::ToUnderlying(OOGUIScreenID::kManifest) == 7);
static_assert(oo::ToUnderlying(OOGUIScreenID::kEquipShip) == 8);
static_assert(oo::ToUnderlying(OOGUIScreenID::kShipyard) == 9);
static_assert(oo::ToUnderlying(OOGUIScreenID::kLongRangeChart) == 10);
static_assert(oo::ToUnderlying(OOGUIScreenID::kShortRangeChart) == 11);
static_assert(oo::ToUnderlying(OOGUIScreenID::kSystemData) == 12);
static_assert(oo::ToUnderlying(OOGUIScreenID::kMarket) == 13);
static_assert(oo::ToUnderlying(OOGUIScreenID::kMarketInfo) == 14);
static_assert(oo::ToUnderlying(OOGUIScreenID::kOptions) == 15);
static_assert(oo::ToUnderlying(OOGUIScreenID::kGameOptions) == 16);
static_assert(oo::ToUnderlying(OOGUIScreenID::kLoad) == 17);
static_assert(oo::ToUnderlying(OOGUIScreenID::kSave) == 18);
static_assert(oo::ToUnderlying(OOGUIScreenID::kSaveOverwrite) == 19);
static_assert(oo::ToUnderlying(OOGUIScreenID::kStickMapper) == 20);
static_assert(oo::ToUnderlying(OOGUIScreenID::kStickProfile) == 21);
static_assert(oo::ToUnderlying(OOGUIScreenID::kMission) == 22);
static_assert(oo::ToUnderlying(OOGUIScreenID::kReport) == 23);
static_assert(oo::ToUnderlying(OOGUIScreenID::kInterfaces) == 24);
static_assert(oo::ToUnderlying(OOGUIScreenID::kKeyboardConfirmClear) == 25);
static_assert(oo::ToUnderlying(OOGUIScreenID::kKeyboardConfig) == 26);
static_assert(oo::ToUnderlying(OOGUIScreenID::kKeyboardEntry) == 27);
static_assert(oo::ToUnderlying(OOGUIScreenID::kKeyboardLayout) == 28);
