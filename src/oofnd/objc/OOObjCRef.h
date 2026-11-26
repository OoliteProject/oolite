/*	oofnd/objc/OOObjCRef.h
        oo::ObjCRef<T *>: a strong reference to an Objective-C object that a C++ container can own
        (the Foundation sweep, proposed ADR-0043). It is what an NSArray / NSSet / NSDictionary did
        for the objects it held: retain on the way in, release on the way out.

            Objective-C (manual retain/release)            oofnd
            ---------------------------------------------  --------------------------------------------
            NSMutableArray *a (of OOTexture *)             std::vector<oo::ObjCRef<OOTexture *>> a
            NSMutableDictionary *d (NSString -> OOFoo *)   std::map<std::string, oo::ObjCRef<OOFoo *>> d
            NSMutableSet *s (of objects, identity)         std::vector<oo::ObjCRef<id>> s  (+ std::find)
            [a addObject:x]                                a.emplace_back(x)          (retains)
            [a addObject:[[OOFoo alloc] init...]]          a.push_back(oo::adoptObjC([[OOFoo alloc] init...]))
            [d setObject:x forKey:k]                       d[k] = oo::ObjCRef<OOFoo *>(x)
            [a objectAtIndex:i]  /  [d objectForKey:k]     a[i].get()  /  (it != d.end() ? it->second.get() : nil)
            [a removeObject...] / [d removeObjectForKey:]  erase (releases)
            [a count]                                      a.size()

            T is the object POINTER type, as in std::vector<NSString *>: oo::ObjCRef<OOTexture *>,
            oo::ObjCRef<id>. Messaging goes through get(): [ref.get() apply].

        SEMANTICS (the same shape as oo::Ref<T>, ADR-0026, so Phase 3 turns ObjCRef<X *> into
        oo::Ref<X> when X becomes a C++ class):

          * ObjCRef(x) RETAINS, like adding x to a collection or assigning through a retaining setter.
            For a +1 object (+alloc/-init..., -copy, +new, an OO_RETURNS_RETAINED result) use
            oo::adoptObjC(x) / ObjCRef::adopt(x), which takes over that +1 instead; ref.leakRef() hands
            a +1 back out. Mixing them up leaks or over-releases, as it did in Objective-C.
          * retain/release are libobjc2's objc_retain() / objc_release(): the count that OOObject and
            gnustep-base's NSObject both use (ADR-0029 measurement 2). An object that overrides
            -retain / -release (Oolite's immortal singletons) is sent the messages, as before.
          * Identity, not -isEqual:. ==, <=> and std::hash compare the pointers. An NSSet / NSDictionary
            key that relied on -isEqual: / -hash (strings, OORoleSet...) is not a job for this type:
            key those by value (std::string, ...) instead.
          * nil is a valid value (a null ObjCRef); get() returns nil and messaging it is a no-op, as
            before. Foundation collections could not hold nil; a C++ container can, so do not add one
            where the old code would have raised.
          * Thread safety is objc_retain's: copying and destroying a ref is safe on any thread, the
            container holding it is not (as NSMutableArray was not).
          * Zero bytes are a null ObjCRef, so a message to nil whose method returns an ObjCRef (or a
            std::vector of them) by value yields an empty one: clang zero-fills the result of a nil
            message (tests/unit/oofnd/test_objc_ref.mm pins this).

        Header-only, Objective-C++. It includes no Foundation and links against libobjc2 alone.
*/

#ifndef OOFND_OBJC_OOOBJCREF_H
#define OOFND_OBJC_OOOBJCREF_H

#include <objc/runtime.h>

#include <objc/objc-arc.h>

// Objective-C++ game code sees OOFoundation.h's `#define true 1` / `#define false 0`; suspend them for
// the standard headers (as oofnd/Data.hpp does, proposed ADR-0028).
#pragma push_macro("true")
#pragma push_macro("false")
#undef true
#undef false

#include <compare>
#include <cstddef>
#include <functional>
#include <type_traits>
#include <utility>

namespace oo {

template <class T>
class ObjCRef {
    static_assert(std::is_pointer_v<T> && std::is_convertible_v<T, id>,
        "oo::ObjCRef<T>: T is an Objective-C object pointer type (OOTexture *, id)");

public:
    ObjCRef() noexcept = default;
    ObjCRef(std::nullptr_t) noexcept { }

    // Retains. For a +1 object (+alloc/-init..., -copy, +new) use oo::adoptObjC().
    explicit ObjCRef(T object) noexcept
        : object_(object)
    {
        objc_retain(object_);
    }

    ObjCRef(const ObjCRef& other) noexcept
        : object_(other.object_)
    {
        objc_retain(object_);
    }
    ObjCRef(ObjCRef&& other) noexcept
        : object_(other.leakRef())
    {
    }

    // ObjCRef<OOTexture *> -> ObjCRef<id> (or to any superclass pointer), as the pointers convert.
    template <class U>
        requires std::is_convertible_v<U, T>
    ObjCRef(const ObjCRef<U>& other) noexcept
        : object_(other.get())
    {
        objc_retain(object_);
    }
    template <class U>
        requires std::is_convertible_v<U, T>
    ObjCRef(ObjCRef<U>&& other) noexcept
        : object_(other.leakRef())
    {
    }

    ~ObjCRef() { objc_release(object_); }

    ObjCRef& operator=(const ObjCRef& other) noexcept
    {
        ObjCRef(other).swap(*this); // retain before release: safe for self-assignment
        return *this;
    }
    ObjCRef& operator=(ObjCRef&& other) noexcept
    {
        ObjCRef(std::move(other)).swap(*this);
        return *this;
    }
    ObjCRef& operator=(std::nullptr_t) noexcept
    {
        ObjCRef().swap(*this);
        return *this;
    }

    void swap(ObjCRef& other) noexcept { std::swap(object_, other.object_); }

    T get() const noexcept { return object_; }
    explicit operator bool() const noexcept { return object_ != nil; }

    // Hands the +1 to the caller and empties this ref (an OO_RETURNS_RETAINED return).
    [[nodiscard]] T leakRef() noexcept { return std::exchange(object_, nil); }

    // Takes over a +1 object without retaining it again.
    [[nodiscard]] static ObjCRef adopt(T object) noexcept
    {
        ObjCRef ref;
        ref.object_ = object;
        return ref;
    }

private:
    T object_ = nil;
};

template <class T>
[[nodiscard]] ObjCRef<T> adoptObjC(T object) noexcept { return ObjCRef<T>::adopt(object); }

template <class T, class U>
bool operator==(const ObjCRef<T>& a, const ObjCRef<U>& b) noexcept
{
    return static_cast<id>(a.get()) == static_cast<id>(b.get());
}
template <class T>
bool operator==(const ObjCRef<T>& a, std::nullptr_t) noexcept { return a.get() == nil; }
template <class T>
bool operator==(const ObjCRef<T>& a, id b) noexcept { return static_cast<id>(a.get()) == b; }

template <class T, class U>
std::strong_ordering operator<=>(const ObjCRef<T>& a, const ObjCRef<U>& b) noexcept
{
    return std::compare_three_way { }(static_cast<const void*>(a.get()), static_cast<const void*>(b.get()));
}

} // namespace oo

template <class T>
struct std::hash<oo::ObjCRef<T>> {
    std::size_t operator()(const oo::ObjCRef<T>& ref) const noexcept
    {
        return std::hash<const void*> { }(static_cast<const void*>(ref.get()));
    }
};

#pragma pop_macro("false")
#pragma pop_macro("true")

#endif // OOFND_OBJC_OOOBJCREF_H
