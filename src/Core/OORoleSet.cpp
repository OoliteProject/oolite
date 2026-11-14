/*

OORoleSet.mm

C++20 since bead oo-bhb9 (proposed ADR-0056, the OOColor house style). Method bodies are the
Objective-C ones with message sends turned into calls. Still Objective-C++ until Phase 4: the
log line describes the set through its Objective-C facade.


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

#include "OORoleSet.h"

#include "OOLogging.h"
#include "OOMaths.h" // randf()

#include "oofnd/String.hpp"

oo::Ref<OORoleSet> OORoleSet::roleSetWithString(const std::string& roleString)
{
    oo::Ref<OORoleSet> result = oo::makeRef<OORoleSet>();
    if (!result->initWithRoleString(roleString))
        return nullptr;
    return result;
}

oo::Ref<OORoleSet> OORoleSet::roleSetWithRole(const std::string& role, float probability)
{
    oo::Ref<OORoleSet> result = oo::makeRef<OORoleSet>();
    if (!result->initWithRole(role, probability))
        return nullptr;
    return result;
}

oo::Ref<OORoleSet> OORoleSet::roleSetWithRolesAndProbabilities(const std::map<std::string, float>* dict)
{
    oo::Ref<OORoleSet> result = oo::makeRef<OORoleSet>();
    if (!result->initWithRolesAndProbabilities(dict))
        return nullptr;
    return result;
}

bool OORoleSet::initWithRoleString(const std::string& roleString)
{
    const std::map<std::string, float> dict = OOParseRolesFromString(roleString);
    return initWithRolesAndProbabilities(dict.empty() ? nullptr : &dict);
}

bool OORoleSet::initWithRole(const std::string& role, float probability)
{
    std::map<std::string, float> dict;

    if (!role.empty() && 0 <= probability) {
        dict.emplace(role, probability);
    }
    return initWithRolesAndProbabilities(dict.empty() ? nullptr : &dict);
}

// oo::DescriptionOf (OODescription.h) wraps this as "<OORoleSet 0x...>{roleString}", which is what
// this class's own -description printed.
std::optional<std::string> OORoleSet::descriptionComponents() const
{
    // roleString() builds its cache on first use, which the const signature cannot (ADR-0055 item
    // 1 fixes it); a set is immutable, so the cache is only ever filled with this same text.
    return const_cast<OORoleSet*>(this)->roleString();
}

bool OORoleSet::isEqual(OORoleSet* other)
{
    if (other != nullptr) {
        return _rolesAndProbabilities == other->_rolesAndProbabilities;
    } else
        return false;
}

NSUInteger OORoleSet::hash()
{
    return _rolesAndProbabilities.size(); // as before: a Foundation dictionary hashes to its count
}

std::optional<std::string> OORoleSet::roleString()
{
    if (!_roleString.has_value()) {
        // Construct role string. We always do this so that it's in a normalized form.
        std::string result;
        bool first = true;
        for (const std::string& role : sortedRoles()) {
            if (!first)
                result += " ";
            else
                first = false;

            result += role;

            const float probability = probabilityForRole(role);
            if (probability != 1.0f) {
                result += oo::str::format("(%g)", probability);
            }
        }

        _roleString = std::move(result);
    }

    return _roleString;
}

bool OORoleSet::hasRole(const std::string& role)
{
    return !role.empty() && _rolesAndProbabilities.contains(role);
}

float OORoleSet::probabilityForRole(const std::string& role)
{
    const auto it = _rolesAndProbabilities.find(role);
    return it != _rolesAndProbabilities.end() ? it->second : 0.0f;
}

std::vector<std::string> OORoleSet::roles()
{
    std::vector<std::string> result;
    result.reserve(_rolesAndProbabilities.size());
    for (const auto& entry : _rolesAndProbabilities)
        result.push_back(entry.first);
    return result;
}

std::vector<std::string> OORoleSet::sortedRoles()
{
    std::vector<std::string> result = roles();
    std::stable_sort(result.begin(), result.end(), [](const std::string& a, const std::string& b) {
        return oo::str::caseInsensitiveCompare(a, b) < 0;
    });
    return result;
}

std::optional<std::map<std::string, float>> OORoleSet::rolesAndProbabilities()
{
    return _rolesAndProbabilities;
}

std::optional<std::string> OORoleSet::anyRole()
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
        OO_LOG("roleSet.anyRole.failed", "Could not get a weighted-random role from role set {}, returning unweighted selection {}. TotalProb: {:g}, selected: {:g}, prob at end: {:f}", oo::str::format("<OORoleSet %s>{%s}", oo::str::pointerDescription(this).c_str(), descriptionComponents().value_or("").c_str()), role.value_or("(null)"), _totalProb, selected, prob);
    }
    return role;
}

oo::Ref<OORoleSet> OORoleSet::roleSetWithAddedRoleIfNotSet(const std::string& role, float probability)
{
    if (role.empty() || probability < 0 || (_rolesAndProbabilities.contains(role) && probabilityForRole(role) == probability)) {
        return oo::Ref<OORoleSet>(this); // copy is retain: a role set is immutable
    }

    std::map<std::string, float> dict = _rolesAndProbabilities;
    dict[role] = probability;
    return roleSetWithRolesAndProbabilities(&dict);
}

oo::Ref<OORoleSet> OORoleSet::roleSetWithAddedRole(const std::string& role, float probability)
{
    if (role.empty() || probability < 0 || _rolesAndProbabilities.contains(role)) {
        return oo::Ref<OORoleSet>(this); // copy is retain: a role set is immutable
    }

    std::map<std::string, float> dict = _rolesAndProbabilities;
    dict[role] = probability;
    return roleSetWithRolesAndProbabilities(&dict);
}

oo::Ref<OORoleSet> OORoleSet::roleSetWithRemovedRole(const std::string& role)
{
    if (!_rolesAndProbabilities.contains(role))
        return oo::Ref<OORoleSet>(this); // copy is retain

    std::map<std::string, float> dict = _rolesAndProbabilities;
    dict.erase(role);
    return roleSetWithRolesAndProbabilities(&dict);
}

bool OORoleSet::initWithRolesAndProbabilities(const std::map<std::string, float>* dict)
{
    if (dict == nullptr) {
        return false;
    }

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
            OO_LOG("roleSet.badValue", "Attempt to create a role set with negative or non-numerical probability for role {}.", role);
            return false;
        }

        _totalProb += prob;
    }

    return true;
}

std::map<std::string, float> OOParseRolesFromString(std::string_view string)
{
    std::map<std::string, float> result;

    // Split string at spaces; scan tokens, looking for probabilities.
    for (const std::string& token : oo::str::tokens(string)) {
        std::string role = token;
        float probability = 1.0f;
        const std::size_t open = token.find('(');
        if (open != std::string::npos) {
            // The old scanner's -scanUpToString:@"(" (which leaves role alone when "(" comes first),
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
