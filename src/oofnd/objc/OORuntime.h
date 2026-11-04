/*	oofnd/objc/OORuntime.h
        Class and selector names without Foundation (bead oo-3rb.19, proposed ADR-0029 Decision 5).

        Foundation's NSClassFromString & co. are thin wrappers over libobjc2 that take and return
        NSString. These take and return UTF-8 C strings and call the same runtime functions GNUstep
        calls, so the result for any name is the one Foundation gave.

            Foundation                              oofnd/objc
            --------------------------------------  -------------------------------------------------
            NSClassFromString(s)                    OOClassFromName(utf8)       objc_lookUpClass
            NSStringFromClass(c)                    OOClassName(c)              class_getName
            NSSelectorFromString(s)                 OOSelectorFromName(utf8)    sel_registerName
            NSStringFromSelector(sel)               OOSelectorName(sel)         sel_getName
            sel1 == sel2                            OOSelectorsEqual(sel1, sel2) (sel_isEqual)

            In a format string, "%@", NSStringFromSelector(sel) becomes "%s", OOSelectorName(sel).

        NULL IN, NULL OUT: a NULL name gives Nil / a NULL SEL (Foundation: nil string -> 0), and a Nil
        class or NULL selector gives a NULL name (Foundation: nil). A NULL name must not reach "%s";
        the call sites converted so far only name selectors and classes that cannot be NULL there.

        libobjc2 selectors are TYPED (ADR-0029 measurement 9): @selector(foo:) carries a type encoding,
        OOSelectorFromName("foo:") does not, so compare selectors with OOSelectorsEqual (sel_isEqual),
        never with ==. Dispatch (respondsToSelector:, performSelector:, objc_msgSend) is by name and
        is unaffected.

        Header-only; Objective-C++ (the string_view overloads).
*/

#ifndef OOFND_OBJC_OORUNTIME_H
#define OOFND_OBJC_OORUNTIME_H

#include <objc/runtime.h>

// Objective-C++ game code sees OOFoundation.h's `#define true 1` / `#define false 0`; suspend them for
// the standard headers (as oofnd/Data.hpp does, proposed ADR-0028).
#pragma push_macro("true")
#pragma push_macro("false")
#undef true
#undef false
#include <string>
#include <string_view>
#pragma pop_macro("false")
#pragma pop_macro("true")

// The class named `name`, or Nil if no such class is registered.
inline Class OOClassFromName(const char* name)
{
    return name != nullptr ? objc_lookUpClass(name) : Nil;
}

inline Class OOClassFromName(std::string_view name)
{
    const std::string terminated(name);
    return objc_lookUpClass(terminated.c_str());
}

// The class's name (UTF-8, owned by the runtime), or NULL for Nil.
inline const char* OOClassName(Class cls)
{
    return cls != Nil ? class_getName(cls) : nullptr;
}

// The (untyped) selector named `name`, registering it if it is new; NULL for a NULL name.
inline SEL OOSelectorFromName(const char* name)
{
    return name != nullptr ? sel_registerName(name) : nullptr;
}

inline SEL OOSelectorFromName(std::string_view name)
{
    const std::string terminated(name);
    return sel_registerName(terminated.c_str());
}

// The selector's name (UTF-8, owned by the runtime), or NULL for a NULL selector.
inline const char* OOSelectorName(SEL selector)
{
    return selector != nullptr ? sel_getName(selector) : nullptr;
}

// Selector identity by name, whatever the type encodings (see the banner).
inline bool OOSelectorsEqual(SEL a, SEL b)
{
    if (a == nullptr || b == nullptr)
        return a == b;
    return sel_isEqual(a, b);
}

#endif // OOFND_OBJC_OORUNTIME_H
