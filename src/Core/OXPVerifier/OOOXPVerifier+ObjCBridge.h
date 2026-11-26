/*

OOOXPVerifier+ObjCBridge.h

TRANSITIONAL (proposed ADR-0056, bead oo-tsa4): the Objective-C OOOXPVerifier, a facade over the
C++ cxx::OOOXPVerifier (OOOXPVerifier.h), for GameController (+runVerificationIfRequested) and the
stages, which keep it as their verifier and message it. Its interface is the one OOOXPVerifier.h
declared before the conversion, copied exactly (same selectors, same types), so they compile and
behave unchanged; the categories that other files add to it (-fileScannerStage,
-textureVerifierStage) are unchanged too (the model stage's went with bead oo-9ht.56). Since bead
oo-9ht.4 deleted the stage facade, the stages it registers and answers by name are the C++
stages (OOOXPVerifierStage *, borrowed). Imported as the last line of OOOXPVerifier.h; do not
import it directly.

Never add to this file; converted code does not message the facade. Deleted by its deletion bead.


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

#ifndef OOOXPVERIFIER_OBJCBRIDGE_H
#define OOOXPVERIFIER_OBJCBRIDGE_H

#if OO_OXP_VERIFIER_ENABLED

@interface OOOXPVerifier : OOObject {
@private
    oo::Ref<cxx::OOOXPVerifier> _cxxVerifier;
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
- (void)registerStage:(OOOXPVerifierStage*)stage; // the C++ stage (its facade until bead oo-9ht.4)

//	All other methods are for use by verifier stages.
- (std::optional<std::string>)cxx_oxpPath;
- (std::optional<std::string>)cxx_oxpDisplayName;

- (OOOXPVerifierStage*)cxx_stageWithName:(const std::string&)name; // borrowed; null: none (was an id, the stage's facade, until bead oo-9ht.4)

// Read from verifyOXP.plist
- (oo::PList)configurationValueForKey:(const std::string&)key;
- (oo::PList)cxx_configurationArrayForKey:(const std::string&)key; // an Array, or null (was nil) if absent or not an array
- (oo::PList)cxx_configurationDictionaryForKey:(const std::string&)key; // a Dict, or null (was nil) if absent or not a dictionary
- (std::optional<std::string>)cxx_configurationStringForKey:(const std::string&)key; // a string, or a number's text; nullopt (was nil) otherwise
- (std::optional<std::vector<std::string>>)cxx_configurationSetForKey:(const std::string&)key; // the array's distinct strings in byte order; nullopt (was nil) if not an array

@end

@interface OOOXPVerifier (OOObjCBridge)

// The facade of verifier (oo::ToObjC makes it). Retains verifier.
- (id)initWithCxxVerifier:(cxx::OOOXPVerifier*)verifier;

@end

namespace oo {

// The verifier's facade: its live one, else a new one; autoreleased. nil for null.
OOOXPVerifier* ToObjC(cxx::OOOXPVerifier* verifier);
inline OOOXPVerifier* ToObjC(const Ref<cxx::OOOXPVerifier>& verifier) { return ToObjC(verifier.get()); }

// The C++ verifier behind a facade, borrowed (the facade retains it); null for nil.
cxx::OOOXPVerifier* ToCxx(OOOXPVerifier* verifier);

} // namespace oo

#endif // OO_OXP_VERIFIER_ENABLED

#endif // OOOXPVERIFIER_OBJCBRIDGE_H
