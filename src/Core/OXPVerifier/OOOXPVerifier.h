/*

OOOXPVerifier.h

Oolite expansion pack verification manager.

NOTE: the overall design is discussed in OXP verifier design.txt.

The stages keep and call it, and GameController calls its static
runVerificationIfRequested(). The stages are C++ (OOOXPVerifierStage), kept and
driven as they are.


Copyright (C) 2007-2013 Jens Ayton and contributors

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

#ifndef OO_OXP_VERIFIER_ENABLED
#ifdef NDEBUG
#define OO_OXP_VERIFIER_ENABLED 0
#else
#define OO_OXP_VERIFIER_ENABLED 1
#endif
#endif

#if OO_OXP_VERIFIER_ENABLED

#include "OOFoundation.h"
#include "oofnd/PList.hpp"
#include "oofnd/Ref.hpp"
#include "oofnd/StdLib.hpp"
#include "oofnd/objc/OOObject.h"

class OOOXPVerifierStage;  // OOOXPVerifierStage.h, which imports this header

struct OOOXPVerifierTestAccess;  // tests only

/*	verifyOXP.plist is
   an oo::PList, paths and names are UTF-8 std::strings, stages are retained
   through oo::Ref. The stages waiting to be examined or run are a vector in
   registration order (they were a set). A stage is kept as the C++ stage itself
   (oo::Ref<::OOOXPVerifierStage>).
*/
class OOOXPVerifier : public oo::RefCounted {
 public:
  /*	Look for command-line arguments requesting OXP verification. If any are
          found, run the verification and return true. Otherwise, return false.

          At the moment, only one OXP may be verified per run; additional
     requests are ignored.
  */
  static bool runVerificationIfRequested();

  /*	Stage registration. Currently, stages are registered by OOOXPVerifier
          itself. Stages may also register other stages - substages, as it were
     - in their -initWithVerifier: methods, or when -dependencies or -dependents
     are called. Registration at later points is not permitted.
  */
  void registerStage(::OOOXPVerifierStage* stage);

  //	All other methods are for use by verifier stages.
  std::optional<std::string> oxpPath();
  std::optional<std::string> oxpDisplayName();

  ::OOOXPVerifierStage* stageWithName(
      const std::string& name);  // null: none (borrowed: the verifier keeps it)

  // Read from verifyOXP.plist
  oo::PList configurationValueForKey(const std::string& key);
  oo::PList configurationArrayForKey(
      const std::string&
          key);  // an Array, or null (was nil) if absent or not an array
  oo::PList configurationDictionaryForKey(
      const std::string&
          key);  // a Dict, or null (was nil) if absent or not a dictionary
  std::optional<std::string> configurationStringForKey(
      const std::string&
          key);  // a string, or a number's text; nullopt (was nil) otherwise
  std::optional<std::vector<std::string>> configurationSetForKey(
      const std::string& key);  // the array's distinct strings in byte order;
                                // nullopt (was nil) if not an array

 private:
  OOOXPVerifier() = default;

  // -initWithPath:, which could fail (verifyOXP.plist unreadable):
  // createWithPath() runs it on a new object and answers null then.
  static oo::Ref<OOOXPVerifier> createWithPath(
      const std::optional<std::string>& path);
  bool initWithPath(const std::optional<std::string>& path);  // nullopt: nil
  void run();

  void setUpLogOverrides();

  void registerBaseStages();
  void buildDependencyGraph();
  void runStages();

  bool setUpDependencies(const std::vector<std::string>& dependencies,
                         ::OOOXPVerifierStage* stage);
  void setUpDependents(const std::vector<std::string>& dependents,
                       ::OOOXPVerifierStage* stage);

  void dumpDebugGraphviz();

  /*	Test stand-in hook: makes the stage a test names in its verifyOXP.plist,
     asked after the stage table and before the class-name lookup. Null in the
     game; set only through
     OOOXPVerifierTestAccess.
  */
  friend struct ::OOOXPVerifierTestAccess;
  static oo::Ref<::OOOXPVerifierStage> (*sTestStageMaker)(
      const std::string& name);

  oo::PList _verifierPList = {};

  std::string _basePath = {};
  std::string _displayName = {};

  std::map<std::string, oo::Ref<::OOOXPVerifierStage>, std::less<>>
      _stagesByName;  // no `= {}`: GCC instantiates ~Ref<T> at a default member
                      // initializer, and T is incomplete here
  std::vector<oo::Ref<::OOOXPVerifierStage>>
      _waitingStages;  // no `= {}`: GCC instantiates ~Ref<T> at a default
                       // member initializer, and T is incomplete here

  bool _openForRegistration = {};
};

#endif
