/*

OOOXPVerifier.h

Oolite expansion pack verification manager.

NOTE: the overall design is discussed in OXP verifier design.txt.


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

#ifndef OO_OXP_VERIFIER_ENABLED
#ifdef NDEBUG
#define OO_OXP_VERIFIER_ENABLED 0
#else
#define OO_OXP_VERIFIER_ENABLED 1
#endif
#endif

#if OO_OXP_VERIFIER_ENABLED

#import "OOFoundation.h"
#import "oofnd/objc/OOObject.h"

#include "oofnd/PList.hpp"
#include "oofnd/StdLib.hpp"
#include "oofnd/objc/OOObjCRef.h"

@class OOOXPVerifierStage;

/*	Foundation sweep (proposed ADR-0043, bead oo-hkvv): verifyOXP.plist is an oo::PList, paths
        and names are UTF-8 std::strings, stages are retained through oo::ObjCRef. The stages waiting
        to be examined or run are a vector in registration order (they were a set). The configuration
        accessors are cxx_ methods. -configurationValueForKey: is a shared selector (OODebugMonitor)
        and keeps Objective-C objects.
*/
@interface OOOXPVerifier : OOObject {
@private
    oo::PList _verifierPList;

    std::string _basePath;
    std::string _displayName;

    std::map<std::string, oo::ObjCRef<OOOXPVerifierStage*>, std::less<>> _stagesByName;
    std::vector<oo::ObjCRef<OOOXPVerifierStage*>> _waitingStages;

    BOOL _openForRegistration;
}

/*	Look for command-line arguments requesting OXP verification. If any are
        found, run the verification and return YES. Otherwise, return NO.

        At the moment, only one OXP may be verified per run; additional requests
        are ignored.
*/
+ (BOOL)runVerificationIfRequested;

/*	Stage registration. Currently, stages are registered by OOOXPVerifier
        itself. Stages may also register other stages - substages, as it were -
        in their -initWithVerifier: methods, or when -dependencies or
        -dependents are called. Registration at later points is not permitted.
*/
- (void)registerStage:(OOOXPVerifierStage*)stage;

//	All other methods are for use by verifier stages.
- (std::optional<std::string>)cxx_oxpPath;
- (std::optional<std::string>)cxx_oxpDisplayName;

- (id)cxx_stageWithName:(const std::string&)name;

// Read from verifyOXP.plist
- (id)configurationValueForKey:(id)key; // key: an Objective-C string. Shared selector (proposed ADR-0043).
- (oo::PList)cxx_configurationArrayForKey:(const std::string&)key; // an Array, or null (was nil) if absent or not an array
- (oo::PList)cxx_configurationDictionaryForKey:(const std::string&)key; // a Dict, or null (was nil) if absent or not a dictionary
- (std::optional<std::string>)cxx_configurationStringForKey:(const std::string&)key; // a string, or a number's text; nullopt (was nil) otherwise
- (std::optional<std::vector<std::string>>)cxx_configurationSetForKey:(const std::string&)key; // the array's distinct strings in byte order; nullopt (was nil) if not an array

@end

#endif
