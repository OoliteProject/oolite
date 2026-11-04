// Stub for tests/unit/expander: only what
// src/Core/OOStringExpander.mm uses. The game's PLAYER is the C++ player, whose
// members the expander calls; the harness's player is C++ too, with the same
// answers, defined below.
#pragma once

#include <format>
#include <optional>
#include <string>

#include "OOFoundation.h"
#include "OOTypes.h"
#include "oofnd/PList.hpp"
#include "oofnd/String.hpp"

struct OOHarnessPlayer {
  OOSystemID systemID();
  std::optional<std::string> keyBindingDescription2(const std::string& binding);
  oo::PList missionVariableForKey(const std::string& key);
  // The by-name methods (the special keys and whitelist.plist's query methods).
  bool respondsToName(const std::string& name);
  oo::PList callByName(const std::string& name);
};

// Records "query <name>" (test_string_expander.cpp).
void OOHarnessRecordQuery(const std::string& name);

// The player's answers: every whitelisted legacy query name the stub did not
// declare answers with its own name and is logged (so a call the engine makes
// or skips shows); the declared special keys answer fixed text.
namespace oo_harness {

struct NamedAnswer {
  const char* name;
  const char* answer;
};

inline const NamedAnswer kDeclaredAnswers[] = {
    {"commanderName_string", "Jameson"},
    {"commanderShip_string", "Cobra Mark III"},
    {"commanderShipDisplayName_string", "Cobra É"},
    {"commanderRank_string", "Harmless"},
    {"commanderKillsAsString", "12"},
    {"commanderLegalStatus_string", "Clean"},
    {"commanderBountyAsString", "0"},
    {"creditsFormattedForSubstitution", "1,234.5"},
    {"creditsFormattedForLegacySubstitution", "1234.5"},
};

// A text through a Foundation string and back, as the stub's Objective-C forms
// took and gave it.
inline std::string RoundTrip(const std::string& text) {
  return oo::utf16ToUtf8(oo::utf8ToUtf16(text));
}

}  // namespace oo_harness

inline OOSystemID OOHarnessPlayer::systemID() { return 7; }

inline std::optional<std::string> OOHarnessPlayer::keyBindingDescription2(
    const std::string& binding) {
  return oo::utf16ToUtf8(u"kb:" + oo::utf8ToUtf16(binding));
}

inline oo::PList OOHarnessPlayer::missionVariableForKey(
    const std::string& key) {
  const std::u16string units = oo::utf8ToUtf16(key);
  if (units.ends_with(u"_nil")) return oo::PList();
  return oo::PList(oo::utf16ToUtf8(u"mv:" + units));
}

inline bool OOHarnessPlayer::respondsToName(const std::string& name) {
  // The stub resolved every name without arguments; the expander's names (the
  // special keys and whitelist.plist's query methods) all are.
  return !name.empty() && name.back() != ':';
}

inline oo::PList OOHarnessPlayer::callByName(const std::string& name) {
  for (const oo_harness::NamedAnswer& declared : oo_harness::kDeclaredAnswers) {
    if (name == declared.name)
      return oo::PList(oo_harness::RoundTrip(declared.answer));
  }
  if (name == "systemID")
    return oo::PList();  // a scalar result, ignored by a by-name call
  if (!respondsToName(name)) return oo::PList();
  OOHarnessRecordQuery(name);
  return oo::PList(std::format("q({})", name));
}

// The expander asks and calls the player's by-name methods on its C++ part
// (OOCallByName.h); the harness's player answers them
// itself.
#include "OOCallByName.h"
namespace oo {
inline bool EntityRespondsToName(OOHarnessPlayer* player,
                                 const std::string& name) {
  return player != nullptr && player->respondsToName(name);
}
inline PList CallEntityByName(OOHarnessPlayer* player,
                              const std::string& name) {
  return player != nullptr ? player->callByName(name) : PList();
}
}  // namespace oo

OOHarnessPlayer* OOHarnessGetPlayer(void);
#define PLAYER OOHarnessGetPlayer()
