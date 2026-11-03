/*

OORoleSet.h

Manage a set of roles for a ship (or ship type), including probabilities.

A role set is an immutable object.


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

#import "OOFoundation.h"
#import "oofnd/objc/OOObject.h"

#include "oofnd/StdLib.hpp"

/*	Foundation sweep (proposed ADR-0043, bead oo-hi38): roles are UTF-8 std::strings. An empty
        role means "no role", as nil did. Results that could be nil are std::optional (a message to a
        nil role set yields std::nullopt / an empty vector). -hasRole: and -intersectsSet: are shared
        selectors (ShipEntity; Foundation sets), so they keep Objective-C object parameters until their family
        bead.
*/
@interface OORoleSet : OOObject <OOCopying> {
@private
    std::map<std::string, float> _rolesAndProbabilities;
    std::optional<std::string> _roleString; // normalised form, built on first use
    float _totalProb;
}

+ (instancetype)roleSetWithString:(const std::string&)roleString;
+ (instancetype)roleSetWithRole:(const std::string&)role probability:(float)probability;

- (id)initWithRoleString:(const std::string&)roleString;
- (id)initWithRole:(const std::string&)role probability:(float)probability;

- (std::optional<std::string>)roleString;

- (BOOL)hasRole:(id)role; // role: an Objective-C string. Shared selector (proposed ADR-0043).
- (float)probabilityForRole:(const std::string&)role;
- (BOOL)intersectsSet:(id)set; // an OORoleSet or an Objective-C set of strings. Shared selector (proposed ADR-0043).

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

// Returns a map whose keys are roles and whose values are weights; empty for no roles.
std::map<std::string, float> OOParseRolesFromString(std::string_view string);
