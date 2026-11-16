/*

OOPListSchemaVerifier+ObjCBridge.h

TRANSITIONAL (proposed ADR-0056, bead oo-pni4): the Objective-C OOPListSchemaVerifier, a facade over
the C++ cxx::OOPListSchemaVerifier (OOPListSchemaVerifier.h), for the code that is not converted yet:
its one caller, OOCheckShipDataPListVerifierStage, which makes it, sets itself as the delegate and
verifies with it. (The type verifiers of slice 2 of OOPListSchemaVerifier.mm call the C++ core
directly since bead oo-pgh9, so the OOPrivate category is gone.) Its interface is the one OOPListSchemaVerifier.h declared before the
conversion, copied exactly (same selectors, same types), and so is the delegate's informal
protocol; each method forwards to its C++ member. Imported as the last line of
OOPListSchemaVerifier.h; do not import it directly.

        a caller that is                       holds / passes                       crosses with
        -------------------------------------  -----------------------------------  ------------------------
        still Objective-C                      OOPListSchemaVerifier * (this facade)  nothing: messages as before
        converted (C++)                        oo::Ref<cxx::OOPListSchemaVerifier>
          handing a verifier to Objective-C                                         oo::ToObjC(verifier)
          taking one from Objective-C                                               oo::ToCxx(objcVerifier)

The delegate stays Objective-C: the C++ verifier messages it and hands it oo::ToObjC(this), the
verifier's one live facade (oo::ObjCPeers), so a delegate sees the object it registered with.
Never add to this file; converted code does not message the facade. Deleted by its deletion bead
once no file outside OOPListSchemaVerifier.* names the Objective-C class.

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

#ifndef OOPLISTSCHEMAVERIFIER_OBJCBRIDGE_H
#define OOPLISTSCHEMAVERIFIER_OBJCBRIDGE_H

#import "OOFoundation.h"
#import "oofnd/objc/OOObject.h"

@interface OOPListSchemaVerifier : OOObject {
@private
    oo::Ref<cxx::OOPListSchemaVerifier> _cxxVerifier;
}

+ (instancetype)verifierWithSchema:(const oo::PList&)schema; // nil for a null schema
- (id)initWithSchema:(const oo::PList&)schema;

- (void)setDelegate:(id)delegate;
- (id)delegate;

- (BOOL)verifyPropertyList:(const oo::PList&)plist named:(const std::string&)name;

/*	Convert a key path (such as provided to the delegate method
        -verifier:withPropertyList:failedForProperty:atPath:expectedType:) to a
        human-readable string. Strings are separated by dots and numbers are give
        brackets. For instance, the key path ( "adder-player", "custom_views", 0,
        "view_description" ) is transfomed to
        "adder-player.custom_views[0].view_description".
*/
+ (std::optional<std::string>)descriptionForKeyPath:(const oo::PList&)keyPath; // a null or empty path is "root"; nullopt for a component that is neither string nor number

@end

@interface OOObject (OOPListSchemaVerifierDelegate)

// Handle "delegated types". Return YES for valid, NO for invalid.
// name: a string; keyPath: an array of strings and numbers; typeKey: a string.
- (BOOL)verifier:(OOPListSchemaVerifier*)verifier
    withPropertyList:(const oo::PList&)rootPList
               named:(const std::string&)name
        testProperty:(const oo::PList&)subPList
              atPath:(const oo::PList&)keyPath
         againstType:(const oo::PList&)typeKey
               error:(std::optional<OOPListSchemaVerifierError>*)outError; // flipped with its family (bead oo-3rb.275)

/*	Method notifying of verification failure.
        Return YES to continue verifying, NO to stop.
*/
// name: a string; localSchema: the schema type specifier (a string or a dictionary).
- (BOOL)verifier:(OOPListSchemaVerifier*)verifier
     withPropertyList:(const oo::PList&)rootPList
                named:(const std::string&)name
    failedForProperty:(const oo::PList&)subPList
            withError:(const OOPListSchemaVerifierError&)error
         expectedType:(const oo::PList&)localSchema; // flipped with its family (bead oo-3rb.275)

@end

namespace oo {

// The verifier's Objective-C facade: its live one, else a new one; autoreleased. nil for null.
OOPListSchemaVerifier* ToObjC(cxx::OOPListSchemaVerifier* verifier);
inline OOPListSchemaVerifier* ToObjC(const Ref<cxx::OOPListSchemaVerifier>& verifier) { return ToObjC(verifier.get()); }
// The C++ verifier behind a facade, borrowed (the facade retains it); null for nil.
cxx::OOPListSchemaVerifier* ToCxx(OOPListSchemaVerifier* verifier);

} // namespace oo

#endif // OOPLISTSCHEMAVERIFIER_OBJCBRIDGE_H
