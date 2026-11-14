/*

OOCallByName.mm

See OOCallByName.h (proposed ADR-0055 item 5, bead oo-qps.34). Foundation-free: oo-qps.72
deleted the transitional id branch that bridged an argument to an Objective-C object (a method
with an object parameter is logged and not called). tests/unit/oofnd/test_objc_call_by_name.mm
compiles this file and links it against libobjc2 alone.

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

#import "OOCallByName.h"

#include "oofnd/Log.hpp"
#include "oofnd/objc/OORuntime.h"

#include <objc/runtime.h>

#include <cstdint>
#include <cstdlib>
#include <cstring>

/*	One method per accepted C++ signature: their type encodings are what a called method's must be
        (the encoding of a C++ class or reference is compiler- and ABI-specific, so it is read, not
        spelled; tests/unit/oofnd/test_objc_call_by_name.mm pins it on this toolchain). Looked up by
        name rather than @selector: they are read, never called by name.
*/
@interface OOCallByNameSignatures : OOObject
- (oo::PList)resultPList;
- (void)stringArgument:(const std::string&)argument;
- (void)plistArgument:(const oo::PList&)argument;
@end

@implementation OOCallByNameSignatures

- (oo::PList)resultPList
{
    return oo::PList();
}

- (void)stringArgument:(const std::string&)argument
{
    (void)argument;
}

- (void)plistArgument:(const oo::PList&)argument
{
    (void)argument;
}

@end

namespace {

enum class Kind : std::uint8_t {
    None, // no such slot (no argument)
    Void, // a void result, or a scalar result the dispatcher ignores
    PList, // oo::PList result, or a const oo::PList & argument
    String, // a const std::string & argument
    Object, // an object (id or ClassName *): a result, ignored (ADR-0055 Amendment 2)
    Unsupported
};

std::string OwnedEncoding(char* encoding)
{
    std::string result = encoding != nullptr ? encoding : "";
    std::free(encoding);
    return result;
}

struct Encodings {
    std::string plistResult;
    std::string stringArgument;
    std::string plistArgument;
};

const Encodings& ReferenceEncodings()
{
    static const Encodings encodings = [] {
        Class reference = [OOCallByNameSignatures class];
        Encodings result;
        result.plistResult = OwnedEncoding(method_copyReturnType(class_getInstanceMethod(reference, OOSelectorFromName("resultPList"))));
        result.stringArgument = OwnedEncoding(method_copyArgumentType(class_getInstanceMethod(reference, OOSelectorFromName("stringArgument:")), 2));
        result.plistArgument = OwnedEncoding(method_copyArgumentType(class_getInstanceMethod(reference, OOSelectorFromName("plistArgument:")), 2));
        return result;
    }();
    return encodings;
}

// Type qualifiers (const, in, out...) lead an encoding; they do not change the calling convention.
std::string_view Unqualified(std::string_view encoding)
{
    while (!encoding.empty() && std::strchr("rnNoORV", encoding.front()) != nullptr)
        encoding.remove_prefix(1);
    return encoding;
}

Kind ResultKind(Method method)
{
    const std::string encoding = OwnedEncoding(method_copyReturnType(method));
    const std::string_view type = Unqualified(encoding);
    if (type == "v")
        return Kind::Void;
    if (type == "@")
        return Kind::Object;
    if (encoding == ReferenceEncodings().plistResult)
        return Kind::PList;
    if (type.size() == 1 && std::strchr("cCsSiIlLqQfdB", type.front()) != nullptr)
        return Kind::Void;
    return Kind::Unsupported;
}

Kind ArgumentKind(Method method)
{
    const unsigned count = method_getNumberOfArguments(method);
    if (count == 2)
        return Kind::None;
    if (count != 3)
        return Kind::Unsupported;
    const std::string encoding = OwnedEncoding(method_copyArgumentType(method, 2));
    if (Unqualified(encoding) == "@")
        return Kind::Object;
    if (encoding == ReferenceEncodings().stringArgument)
        return Kind::String;
    if (encoding == ReferenceEncodings().plistArgument)
        return Kind::PList;
    return Kind::Unsupported;
}

// The method <target> runs for <selector>, following a forwarding proxy; nullptr if none.
Method MethodFor(id& target, SEL selector)
{
    for (int hops = 0; hops < 8 && target != nil; hops++) {
        Method method = class_getInstanceMethod(object_getClass(target), selector);
        if (method != nullptr)
            return method;
        if (![target respondsToSelector:@selector(forwardingTargetForSelector:)])
            return nullptr;
        id next = [target forwardingTargetForSelector:selector];
        if (next == target)
            return nullptr;
        target = next;
    }
    return nullptr;
}

void LogUnknown(id target, SEL selector)
{
    OO_LOG_ERR("callByName.unknownSelector", "{} does not respond to {}.", class_getName(object_getClass(target)), sel_getName(selector));
}

void LogBadSignature(id target, SEL selector, Method method)
{
    const char* encoding = method_getTypeEncoding(method);
    OO_LOG_ERR("callByName.badSignature", "-[{} {}] has no signature a by-name call can use (type encoding {}).", class_getName(object_getClass(target)), sel_getName(selector), encoding != nullptr ? encoding : "?");
}

// <imp> as a function of the method's own C++ signature. The cast goes through void (*)(void), the
// generic function pointer type, as a cast between two unrelated function types must.
template <class Function>
Function As(IMP imp)
{
    return reinterpret_cast<Function>(reinterpret_cast<void (*)(void)>(imp));
}

// What an argument is when the method takes it in one of the forms below.
struct Argument {
    Kind kind = Kind::None;
    const std::string* string = nullptr;
    const oo::PList* plist = nullptr;
};

oo::PList Call(id target, SEL selector, const Argument& argument)
{
    if (target == nil)
        return oo::PList();
    id receiver = target;
    Method method = MethodFor(receiver, selector);
    // A facade's category may hold a method that only some objects answer (the player's selectors
    // on the root's facade, ADR-0056 amendments oo-9ht.177, oo-9ht.144): it asks -respondsToSelector:.
    if (method == nullptr || ![receiver respondsToSelector:selector]) {
        LogUnknown(target, selector);
        return oo::PList();
    }
    target = receiver;

    const Kind result = ResultKind(method);
    Kind parameter = ArgumentKind(method);
    IMP imp = method_getImplementation(method);

    // A string reaches a PList parameter as a string PList; a PList reaches a string parameter
    // only when it is a string.
    oo::PList stringAsPList;
    if (argument.kind == Kind::String && parameter == Kind::PList) {
        stringAsPList = oo::PList(*argument.string);
    }
    const std::string* plistAsString = (argument.kind == Kind::PList) ? argument.plist->getIf<std::string>() : nullptr;

    const bool arityMatches = (argument.kind == Kind::None) == (parameter == Kind::None);
    const bool usable = arityMatches && result != Kind::Unsupported && parameter != Kind::Unsupported
        && parameter != Kind::Object
        && !(argument.kind == Kind::PList && parameter == Kind::String && plistAsString == nullptr)
        && !(parameter == Kind::PList && result != Kind::Void && result != Kind::Object);
    if (!usable) {
        LogBadSignature(target, selector, method);
        return oo::PList();
    }

    if (result == Kind::Object) {
        // An object result (the ship a launch action returns) is ignored, as a scalar is: no
        // dispatcher reads one (ADR-0055 Amendment 2). OOJSCall calls such a method itself.
        switch (parameter) {
        case Kind::None:
            (void)As<id (*)(id, SEL)>(imp)(target, selector);
            break;
        case Kind::String:
            (void)As<id (*)(id, SEL, const std::string&)>(imp)(target, selector, (argument.kind == Kind::String) ? *argument.string : *plistAsString);
            break;
        case Kind::PList:
            (void)As<id (*)(id, SEL, const oo::PList&)>(imp)(target, selector, (argument.kind == Kind::PList) ? *argument.plist : stringAsPList);
            break;
        default:
            break;
        }
        return oo::PList();
    }

    switch (parameter) {
    case Kind::None:
        if (result == Kind::PList)
            return As<oo::PList (*)(id, SEL)>(imp)(target, selector);
        As<void (*)(id, SEL)>(imp)(target, selector);
        return oo::PList();

    case Kind::String: {
        const std::string& string = (argument.kind == Kind::String) ? *argument.string : *plistAsString;
        if (result == Kind::PList)
            return As<oo::PList (*)(id, SEL, const std::string&)>(imp)(target, selector, string);
        As<void (*)(id, SEL, const std::string&)>(imp)(target, selector, string);
        return oo::PList();
    }

    case Kind::PList: {
        const oo::PList& plist = (argument.kind == Kind::PList) ? *argument.plist : stringAsPList;
        As<void (*)(id, SEL, const oo::PList&)>(imp)(target, selector, plist);
        return oo::PList();
    }

    default:
        return oo::PList();
    }
}

} // namespace

oo::PList OOCallByName(id target, SEL selector)
{
    return Call(target, selector, Argument { });
}

oo::PList OOCallByName(id target, SEL selector, const std::string& argument)
{
    return Call(target, selector, Argument { Kind::String, &argument, nullptr });
}

oo::PList OOCallByName(id target, SEL selector, const oo::PList& argument)
{
    return Call(target, selector, Argument { Kind::PList, nullptr, &argument });
}
