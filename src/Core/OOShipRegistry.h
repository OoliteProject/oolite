/*

OOShipRegistry.h

Manage the set of installed ships.


Copyright (C) 2008-2013 Jens Ayton and contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

*/

#pragma once

#include "OOFoundation.h"
#include "oofnd/PList.hpp"
#include "oofnd/Ref.hpp"
#include "oofnd/StdLib.hpp"
#include "oofnd/objc/OOObject.h"

class OOProbabilitySet;
class OOMutableProbabilitySet;

class OOShipRegistry : public oo::RefCounted {
 public:
  static OOShipRegistry* sharedRegistry();  // the one instance, made on first
                                            // use and never released; borrowed

  static void reload();

  // A null PList where there is no such entry (was nil).
  oo::PList shipInfoForKey(const std::string& key);
  void setShipInfoForKey(const std::string& key, const oo::PList& newShipData);
  oo::PList effectInfoForKey(const std::string& key);
  oo::PList shipyardInfoForKey(const std::string& key);
  OOProbabilitySet* probabilitySetForRole(const std::string& role);

  oo::PList demoShipKeys();  // arrays (one per class) of demo ship dictionaries
  std::vector<std::string> playerShipKeys();

  // (OOConveniences)
  std::vector<std::string> shipKeys();   // in key order
  std::vector<std::string> shipRoles();  // in role order
  std::vector<std::string> shipKeysWithRole(const std::string& role);
  std::optional<std::string> randomShipKeyForRole(
      const std::string& role);  // nullopt: no ship has the role

 private:
  oo::PList _shipData;    // ship key -> ship dictionary (null until loaded)
  oo::PList _effectData;  // effect key -> effect dictionary (null until loaded)
  oo::PList _demoShips;   // demo ship entries (dictionaries) grouped in arrays
                          // by class
  std::vector<std::string>
      _playerShips;  // shipyard keys, in shipyard.plist key order
  std::optional<std::map<std::string, oo::Ref<OOProbabilitySet>, std::less<>>>
      _probabilitySets;  // role -> ship keys; nullopt: none cached yet

  void init();  // -init's body: run by sharedRegistry() once sSingleton is set,
                // so that a re-entrant sharedRegistry() answers the registry
                // being loaded

  // (OODataLoader) The load stages. The ship dictionary each stage mutates is
  // one property list, passed through every stage.
  void loadShipData();
  void loadDemoShipConditions();
  void loadDemoShips();
  void loadCachedRoleProbabilitySets();
  void buildRoleProbabilitySets();

  bool applyLikeShips(oo::PList& ioData, const std::string& likeKey);
  bool loadAndMergeShipyard(oo::PList& ioData);
  bool stripPrivateKeys(oo::PList& ioData);
  bool makeShipEntriesMutable(oo::PList& ioData);
  bool loadAndApplyShipDataOverrides(oo::PList& ioData);
  bool removeUnusableEntries(oo::PList& ioData, bool shipMode);
  bool sanitizeConditions(oo::PList& ioData);

  bool canonicalizeAndTagSubentities(oo::PList& ioData);
  bool preloadShipMeshes(
      oo::PList& ioData);  // defined only when OOShipRegistry.mm's PRELOAD is
                           // set (it is 0)

  oo::PList mergeShip(
      const oo::PList& child,
      const oo::PList& parent);  // a null PList where the parent was nil
  void mergeShipRoles(const std::string& roles, const std::string& shipKey,
                      std::map<std::string, oo::Ref<OOMutableProbabilitySet>,
                               std::less<>>& probabilitySets);

  // Declarations and ship data are property lists; a result is a declaration
  // dictionary, or a null PList where it was nil.
  oo::PList canonicalizeSubentityDeclaration(const oo::PList& declaration,
                                             const std::string& shipKey,
                                             const oo::PList& shipData,
                                             bool* outFatalError);
  oo::PList translateOldStyleSubentityDeclaration(
      const std::string& declaration, const std::string& shipKey,
      const oo::PList& shipData, bool* outFatalError);
  oo::PList translateOldStyleFlasherDeclaration(const oo::PList& tokens,
                                                const std::string& shipKey,
                                                bool* outFatalError);
  oo::PList translateOldStandardBasicSubentityDeclaration(
      const oo::PList& tokens, const std::string& shipKey,
      const oo::PList& shipData, bool* outFatalError);
  oo::PList validateNewStyleSubentityDeclaration(const oo::PList& declaration,
                                                 const std::string& shipKey,
                                                 bool* outFatalError);
  oo::PList validateNewStyleFlasherDeclaration(const oo::PList& declaration,
                                               const std::string& shipKey,
                                               bool* outFatalError);
  oo::PList validateNewStyleStandardSubentityDeclaration(
      const oo::PList& declaration, const std::string& shipKey,
      bool* outFatalError);

  bool shipIsBallTurretForKey(const std::string& shipKey,
                              const oo::PList& shipData);
};
