/*

OORoleSet.m


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

#import "OORoleSet.h"

#import "OOFoundationBridge.h"
#import "OOLogging.h"
#import "OOMaths.h" // randf()

#include "oofnd/String.hpp"

@interface OORoleSet (OOPrivate)

// nullptr is a nil dictionary: the initializer fails, as it did.
- (id)initWithRolesAndProbabilities:(const std::map<std::string, float>*)dict;

@end

@implementation OORoleSet

+ (instancetype)roleSetWithString:(const std::string&)roleString
{
    return [[[self alloc] initWithRoleString:roleString] autorelease];
}

+ (instancetype)roleSetWithRole:(const std::string&)role probability:(float)probability
{
    return [[[self alloc] initWithRole:role probability:probability] autorelease];
}

- (id)initWithRoleString:(const std::string&)roleString
{
    const std::map<std::string, float> dict = OOParseRolesFromString(roleString);
    return [self initWithRolesAndProbabilities:dict.empty() ? nullptr : &dict];
}

- (id)initWithRole:(const std::string&)role probability:(float)probability
{
    std::map<std::string, float> dict;

    if (!role.empty() && 0 <= probability) {
        dict.emplace(role, probability);
    }
    return [self initWithRolesAndProbabilities:dict.empty() ? nullptr : &dict];
}

// OOObject's -description wraps this as "<OORoleSet 0x...>{roleString}", which is what this
// class's own -description printed.
- (id)descriptionComponents
{
    return oo::NSStringOrNil([self roleString]);
}

- (BOOL)isEqual:(id)other
{
    if ([other isKindOfClass:[OORoleSet class]]) {
        return _rolesAndProbabilities == ((OORoleSet*)other)->_rolesAndProbabilities;
    } else
        return NO;
}

- (NSUInteger)hash
{
    return _rolesAndProbabilities.size(); // as before: a Foundation dictionary hashes to its count
}

- (id)copyWithZone:(OOZone*)zone
{
    // Note: since object is immutable, a copy is no different from the original.
    return [self retain];
}

- (std::optional<std::string>)roleString
{
    if (!_roleString.has_value()) {
        // Construct role string. We always do this so that it's in a normalized form.
        std::string result;
        bool first = true;
        for (const std::string& role : [self sortedRoles]) {
            if (!first)
                result += " ";
            else
                first = false;

            result += role;

            const float probability = [self probabilityForRole:role];
            if (probability != 1.0f) {
                result += oo::str::format("(%g)", probability);
            }
        }

        _roleString = std::move(result);
    }

    return _roleString;
}

- (BOOL)hasRole:(id)role
{
    return role != nil && _rolesAndProbabilities.contains(oo::StdString(role));
}

- (float)probabilityForRole:(const std::string&)role
{
    const auto it = _rolesAndProbabilities.find(role);
    return it != _rolesAndProbabilities.end() ? it->second : 0.0f;
}

- (BOOL)intersectsSet:(id)set
{
    std::vector<std::string> other;
    if ([set isKindOfClass:[OORoleSet class]])
        other = [(OORoleSet*)set roles];
    else if (oo::IsNSSet(set))
        other = oo::StringsFrom(set);
    else
        return NO;

    for (const std::string& role : other) {
        if (_rolesAndProbabilities.contains(role))
            return YES;
    }
    return NO;
}

- (std::vector<std::string>)roles
{
    std::vector<std::string> result;
    result.reserve(_rolesAndProbabilities.size());
    for (const auto& entry : _rolesAndProbabilities)
        result.push_back(entry.first);
    return result;
}

- (std::vector<std::string>)sortedRoles
{
    std::vector<std::string> result = [self roles];
    std::stable_sort(result.begin(), result.end(), [](const std::string& a, const std::string& b) {
        return oo::str::caseInsensitiveCompare(a, b) < 0;
    });
    return result;
}

- (std::optional<std::map<std::string, float>>)rolesAndProbabilities
{
    return _rolesAndProbabilities;
}

- (std::optional<std::string>)anyRole
{
    std::optional<std::string> role;
    float prob, selected;

    selected = randf() * _totalProb;
    prob = 0.0f;

    if (_rolesAndProbabilities.empty())
        return std::nullopt;

    for (const auto& [name, probability] : _rolesAndProbabilities) {
        prob += probability;
        if (selected <= prob) {
            role = name;
            break;
        }
    }
    if (!role.has_value()) {
        role = _rolesAndProbabilities.begin()->first;
        OOLog(@"roleSet.anyRole.failed", @"Could not get a weighted-random role from role set %@, returning unweighted selection %@. TotalProb: %g, selected: %g, prob at end: %f", self, oo::NSStringOrNil(role), _totalProb, selected, prob);
    }
    return role;
}

- (id)roleSetWithAddedRoleIfNotSet:(const std::string&)role probability:(float)probability
{
    if (role.empty() || probability < 0 || (_rolesAndProbabilities.contains(role) && [self probabilityForRole:role] == probability)) {
        return [[self copy] autorelease];
    }

    std::map<std::string, float> dict = _rolesAndProbabilities;
    dict[role] = probability;
    return [[[[self class] alloc] initWithRolesAndProbabilities:&dict] autorelease];
}

- (id)roleSetWithAddedRole:(const std::string&)role probability:(float)probability
{
    if (role.empty() || probability < 0 || _rolesAndProbabilities.contains(role)) {
        return [[self copy] autorelease];
    }

    std::map<std::string, float> dict = _rolesAndProbabilities;
    dict[role] = probability;
    return [[[[self class] alloc] initWithRolesAndProbabilities:&dict] autorelease];
}

- (id)roleSetWithRemovedRole:(const std::string&)role
{
    if (!_rolesAndProbabilities.contains(role))
        return [[self copy] autorelease];

    std::map<std::string, float> dict = _rolesAndProbabilities;
    dict.erase(role);
    return [[[[self class] alloc] initWithRolesAndProbabilities:&dict] autorelease];
}

@end

@implementation OORoleSet (OOPrivate)

- (id)initWithRolesAndProbabilities:(const std::map<std::string, float>*)dict
{
    if (dict == nullptr) {
        [self release];
        return nil;
    }

    self = [super init];
    if (self == nil)
        return nil;

    // Note: _roleString is derived on the fly as needed.
    // MKW 20090815 - if we are re-initialising this OORoleSet object, we need
    //                to ensure that _roles and _roleString are cleared.
    // Why would we be re-initing? That's never valid. -- Ahruman 2010-02-06
    assert(!_roleString.has_value());

    std::map<std::string, float> tDict = *dict;
    const auto thargon = dict->find("thargon");
    const float thargProb = thargon != dict->end() ? thargon->second : 0.0f;

    if (thargProb > 0.0f && !dict->contains("EQ_THARGON")) {
        tDict["EQ_THARGON"] = thargProb;
        tDict.erase("thargon");
    }

    _rolesAndProbabilities = std::move(tDict);

    for (const auto& [role, prob] : *dict) {
        if (prob < 0) {
            OOLog(@"roleSet.badValue", @"Attempt to create a role set with negative or non-numerical probability for role %@.", oo::NSStringFrom(role));
            [self release];
            return nil;
        }

        _totalProb += prob;
    }

    return self;
}

@end

std::map<std::string, float> OOParseRolesFromString(std::string_view string)
{
    std::map<std::string, float> result;

    // Split string at spaces; scan tokens, looking for probabilities.
    for (const std::string& token : oo::str::tokens(string)) {
        std::string role = token;
        float probability = 1.0f;
        const std::size_t open = token.find('(');
        if (open != std::string::npos) {
            // -[NSScanner scanUpToString:@"("] (which leaves role alone when "(" comes first),
            // scanString:@"(", then scanFloat: (-scanDouble:, narrowed). Ignore rest of string.
            if (open != 0)
                role = token.substr(0, open);
            double scanned = 0.0;
            if (oo::plist_get::scanDouble(oo::utf8ToUtf16(std::string_view(token).substr(open + 1)), &scanned)) {
                probability = static_cast<float>(scanned);
            }
        }

        // shipKey roles start with [ so other roles can't
        if (0 <= probability && !oo::str::hasPrefix(role, "[")) {
            result[role] = probability;
        }
    }

    return result;
}
