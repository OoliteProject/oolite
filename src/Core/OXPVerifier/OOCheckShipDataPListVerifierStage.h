/*

OOCheckShipDataPListVerifierStage.h

OOOXPVerifierStage which checks shipdata.plist.


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

#include "OOTextureVerifierStage.h"

#if OO_OXP_VERIFIER_ENABLED

#include "OOPListSchemaVerifier.h"  // the delegate interface
#include "oofnd/PList.hpp"
#include "oofnd/Ref.hpp"
#include "oofnd/StdLib.hpp"

class OOAIStateMachineVerifierStage;

/*	shipdata.plist and the entry being checked are oo::PList; the key and
   role sets are sorted std::vectors of strings.

   A subclass of OOTextureHandlingStage. Nothing outside this file names it,
   and the verifier makes it from its name (kCxxStages in OOOXPVerifier.mm) and
   holds it. It is the schema verifier's delegate, through the C++ interface
   OOPListSchemaVerifierDelegate.
*/
class OOCheckShipDataPListVerifierStage : public OOTextureHandlingStage,
                                          public OOPListSchemaVerifierDelegate {
 public:
  std::optional<std::string> name() override;
  std::optional<std::vector<std::string>> dependents() override;
  bool shouldRun() override;
  void run() override;

  /*	The schema verifier's delegate (OOPListSchemaVerifierDelegate; formerly
     an informal protocol's two selectors). Both selectors
     start with verifier:, which would hide verifier(), so each name adds its
     distinguishing keyword.
  */
  bool verifierTestProperty(
      OOPListSchemaVerifier* verifier, const oo::PList& rootPList,
      const std::string& name, const oo::PList& subPList,
      const oo::PList& keyPath, const oo::PList& typeKey,
      std::optional<OOPListSchemaVerifierError>* outError) override;
  bool verifierFailedForProperty(OOPListSchemaVerifier* verifier,
                                 const oo::PList& rootPList,
                                 const std::string& name,
                                 const oo::PList& subPList,
                                 const OOPListSchemaVerifierError& error,
                                 const oo::PList& localSchema) override;

 private:
  void verifyShipInfo(const oo::PList& info, const std::string& name);

  void reportMessage(
      const std::string&
          message);  // formatted by the caller, oo::str::formatRuntime (was
                     // -message:, renamed so AI's -message: could flip)
  void verboseMessage(const std::string& message);

  void getRoles();
  void checkKeys();
  void checkSchema();
  void checkModel();

  std::vector<std::string> rolesFromString(const std::string& string);

  oo::PList _shipdataPList = {};
  std::vector<std::string> _ooliteShipNames = {};
  std::vector<std::string> _basicKeys = {}, _stationKeys = {}, _playerKeys = {},
                           _allKeys = {};
  oo::Ref<OOPListSchemaVerifier> _schemaVerifier = {};  // Made by run().
  OOAIStateMachineVerifierStage* _aiVerifierStage =
      {};  // Not retained (the verifier holds it).

  // Info about ship currently being checked.
  std::string _name = {};
  oo::PList _info = {};
  std::vector<std::string> _roles = {};
  bool _isStation = {}, _isPlayer = {}, _isTemplate = {},
       _havePrintedMessage = {};
};

#endif
