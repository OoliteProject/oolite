/*

OORoleSet.h

Manage a set of roles for a ship (or ship type), including probabilities.

A role set is an immutable object.

Ships hold an oo::Ref<OORoleSet>.


Copyright (C) 2007-2013 Jens Ayton

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
#include "oofnd/Ref.hpp"
#include "oofnd/StdLib.hpp"

/*	Roles are UTF-8 std::strings. An empty
        role means "no role", as nil did. Results that could be nil are
   std::optional (a message to a nil role set yields std::nullopt / an empty
   vector). -hasRole: takes a const std::string &. There is no -intersectsSet:;
   HasRoleInSetPredicate tests -hasRole: per role.
*/
class OORoleSet : public oo::RefCounted {
 public:
  // The factories: null where there are no roles.
  static oo::Ref<OORoleSet> roleSetWithString(const std::string& roleString);
  static oo::Ref<OORoleSet> roleSetWithRole(const std::string& role,
                                            float probability);

  std::optional<std::string> roleString();

  bool hasRole(const std::string& role);
  float probabilityForRole(const std::string& role);

  std::vector<std::string> roles();  // in byte order of the role
  std::vector<std::string>
  sortedRoles();  // case-insensitive order, as roleString lists them
  std::optional<std::map<std::string, float>> rolesAndProbabilities();

  // Returns a random role, taking probabilities into account.
  std::optional<std::string> anyRole();

  // Creating modified copies of role sets:
  oo::Ref<OORoleSet> roleSetWithAddedRole(const std::string& role,
                                          float probability);
  oo::Ref<OORoleSet> roleSetWithAddedRoleIfNotSet(
      const std::string& role,
      float probability);  // Unlike the above, does not change probability if
                           // role exists.
  oo::Ref<OORoleSet> roleSetWithRemovedRole(const std::string& role);

  // -isEqual: and -hash: equal role sets have the same roles with the same
  // probabilities.
  bool isEqual(OORoleSet* other);
  NSUInteger hash();

  // What "%@" prints between the braces of <OORoleSet 0x...>{...}
  // (OODescription.h).
  std::optional<std::string> descriptionComponents() const;

 private:
  // The initialisers: false where they returned nil.
  bool initWithRoleString(const std::string& roleString);
  bool initWithRole(const std::string& role, float probability);
  // nullptr is a nil dictionary: the initializer fails, as it did.
  bool initWithRolesAndProbabilities(const std::map<std::string, float>* dict);

  // [[[self class] alloc] initWithRolesAndProbabilities:dict]: null where that
  // returned nil.
  static oo::Ref<OORoleSet> roleSetWithRolesAndProbabilities(
      const std::map<std::string, float>* dict);

  std::map<std::string, float> _rolesAndProbabilities = {};
  std::optional<std::string> _roleString =
      {};  // normalised form, built on first use
  float _totalProb = {};
};

// Returns a map whose keys are roles and whose values are weights; empty for no
// roles.
std::map<std::string, float> OOParseRolesFromString(std::string_view string);
