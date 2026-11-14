/*

OORoleSet+ObjCBridge.h

TRANSITIONAL (proposed ADR-0056, bead oo-bhb9): the Objective-C OORoleSet, a facade over the C++
cxx::OORoleSet (OORoleSet.h), for callers that are not converted yet. Its interface is the one
OORoleSet.h declared before the conversion, copied exactly (same selectors, same types), so those
callers compile and behave unchanged; each method forwards to its C++ member. Imported as the
last line of OORoleSet.h; do not import it directly.

        a caller that is                       holds / passes                  crosses with
        -------------------------------------  ------------------------------  ----------------------------
        still Objective-C                      OORoleSet * (this facade)       nothing: messages as before
        converted (C++)                        oo::Ref<cxx::OORoleSet>, cxx::OORoleSet *
          handing a role set to Objective-C                                     oo::ToObjC(roleSet)
          taking one from Objective-C                                           oo::ToCxx(objcRoleSet)

oo::ToObjC gives the set's one live facade (oo::ObjCPeers), so identity survives a round trip:
oo::ToObjC(oo::ToCxx(s)) == s. -initWithRoleString: and -initWithRole:probability: (ShipEntity
sends alloc/init) make the C++ set and record the new facade as its peer. Never add to this file;
converted code does not message the facade. Deleted by its deletion bead once no file outside
OORoleSet.* names the Objective-C OORoleSet.


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

#ifndef OOROLESET_OBJCBRIDGE_H
#define OOROLESET_OBJCBRIDGE_H

#import "OOFoundation.h"
#import "oofnd/objc/OOObject.h"

@interface OORoleSet : OOObject <OOCopying> {
@private
    oo::Ref<cxx::OORoleSet> _cxxRoleSet;
}

+ (instancetype)roleSetWithString:(const std::string&)roleString;
+ (instancetype)roleSetWithRole:(const std::string&)role probability:(float)probability;

- (id)initWithRoleString:(const std::string&)roleString;
- (id)initWithRole:(const std::string&)role probability:(float)probability;

- (std::optional<std::string>)roleString;

- (BOOL)hasRole:(const std::string&)role; // flipped with its family (bead oo-3rb.280)
- (float)probabilityForRole:(const std::string&)role;

- (std::vector<std::string>)roles; // in byte order of the role
- (std::vector<std::string>)sortedRoles; // case-insensitive order, as roleString lists them
- (std::optional<std::map<std::string, float>>)rolesAndProbabilities;

// Returns a random role, taking probabilities into account.
- (std::optional<std::string>)anyRole;

// Creating modified copies of role sets:
- (id)roleSetWithAddedRole:(const std::string&)role probability:(float)probability;
- (id)roleSetWithAddedRoleIfNotSet:(const std::string&)role probability:(float)probability; // Unlike the above, does not change probability if role exists.
- (id)roleSetWithRemovedRole:(const std::string&)role;

@end

namespace oo {

// The role set's Objective-C facade: its live one, else a new one; autoreleased. nil for null.
OORoleSet* ToObjC(cxx::OORoleSet* roleSet);
inline OORoleSet* ToObjC(const Ref<cxx::OORoleSet>& roleSet) { return ToObjC(roleSet.get()); }

// The C++ role set behind a facade, borrowed (the facade retains it); null for nil.
cxx::OORoleSet* ToCxx(OORoleSet* roleSet);

} // namespace oo

#endif // OOROLESET_OBJCBRIDGE_H
