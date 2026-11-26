/*	oofnd/objc/OOConstantString.mm
        @"..." literals without Foundation (see OOConstantString.h and proposed ADR-0029).
*/

#include "oofnd/objc/OOConstantString.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <string>
#include <string_view>
#include <unordered_map>

namespace {

uintptr_t bitsOf(id object)
{
    const void* address = object;
    return reinterpret_cast<uintptr_t>(address);
}

bool isTiny(id object)
{
    return (bitsOf(object) & OBJC_SMALL_OBJECT_MASK) == OO_TINY_STRING_TAG;
}

// Literals are immortal, so their UTF-8 forms are too: one interned std::string per literal that
// needs one (a UTF-16 literal, or a tiny literal, which has no bytes of its own). Keyed by the
// object pointer (a tiny literal's pointer IS its value). Map nodes never move, so c_str() stays
// valid for the life of the process.
std::mutex gInternLock;
std::unordered_map<uintptr_t, std::string>* gInterned = nullptr;

void appendUTF8(std::string& out, uint32_t codePoint)
{
    if (codePoint < 0x80) {
        out += static_cast<char>(codePoint);
    } else if (codePoint < 0x800) {
        out += static_cast<char>(0xC0 | (codePoint >> 6));
        out += static_cast<char>(0x80 | (codePoint & 0x3F));
    } else if (codePoint < 0x10000) {
        out += static_cast<char>(0xE0 | (codePoint >> 12));
        out += static_cast<char>(0x80 | ((codePoint >> 6) & 0x3F));
        out += static_cast<char>(0x80 | (codePoint & 0x3F));
    } else {
        out += static_cast<char>(0xF0 | (codePoint >> 18));
        out += static_cast<char>(0x80 | ((codePoint >> 12) & 0x3F));
        out += static_cast<char>(0x80 | ((codePoint >> 6) & 0x3F));
        out += static_cast<char>(0x80 | (codePoint & 0x3F));
    }
}

std::string decodeTiny(uintptr_t bits)
{
    std::string result;
    const unsigned count = static_cast<unsigned>((bits >> 3) & 0x1F);
    for (unsigned i = 0; i < count; ++i) {
        result += static_cast<char>((bits >> (57 - 7 * i)) & 0x7F);
    }
    return result;
}

std::string decodeUTF16(const OOConstantString* string)
{
    std::string result;
    uint32_t count = string->length;
    const unsigned char* bytes = reinterpret_cast<const unsigned char*>(string->data);
    for (uint32_t i = 0; i < count; ++i) {
        uint16_t u16;
        std::memcpy(&u16, bytes + 2 * i, sizeof u16); // data is not guaranteed 2-byte aligned
        uint32_t unit = u16;
        if (unit >= 0xD800 && unit < 0xDC00 && i + 1 < count) {
            uint16_t low;
            std::memcpy(&low, bytes + 2 * (i + 1), sizeof low);
            if (low >= 0xDC00 && low < 0xE000) {
                unit = 0x10000 + ((unit - 0xD800) << 10) + (low - 0xDC00);
                ++i;
            }
        }
        appendUTF8(result, unit);
    }
    return result;
}

// The UTF-8 bytes of a literal, tiny or not.
std::string_view utf8View(OOConstantString* string)
{
    if (!isTiny(string) && string->flags == 0)
        return std::string_view(string->data, string->size);

    const uintptr_t key = bitsOf(string);
    std::lock_guard<std::mutex> lock(gInternLock);
    if (gInterned == nullptr)
        gInterned = new std::unordered_map<uintptr_t, std::string>(); // never freed: immortal
    auto found = gInterned->find(key);
    if (found == gInterned->end()) {
        found = gInterned->emplace(key, isTiny(string) ? decodeTiny(key) : decodeUTF16(string)).first;
    }
    return found->second;
}

bool isConstantString(id object)
{
    if (object == nil)
        return false;
    const Class target = [OOConstantString class];
    for (Class c = object_getClass(object); c != Nil; c = class_getSuperclass(c)) {
        if (c == target)
            return true;
    }
    return false;
}

} // namespace

void OOConstantStringInstall(void)
{
    Class tiny = [OOTinyString class];
    if (!objc_registerSmallObjectClass_np(tiny, OO_TINY_STRING_TAG)) {
        // Already registered: fine if it is ours (a second call), fatal if it is another
        // library's (gnustep-base's GSTinyString): the two string floors must not be mixed.
        id probe = reinterpret_cast<id>(static_cast<uintptr_t>(OO_TINY_STRING_TAG)); // an empty tiny string
        Class owner = object_getClass(probe);
        if (owner != tiny) {
            std::fprintf(stderr, "oofnd: small-object tag %d already belongs to %s; OOConstantString cannot coexist with it\n",
                OO_TINY_STRING_TAG, owner != Nil ? class_getName(owner) : "Nil");
            std::abort();
        }
    }
}

@implementation OOConstantString

- (id)retain
{
    return self;
}

- (oneway void)release
{
}

- (id)autorelease
{
    return self;
}

- (uintptr_t)retainCount
{
    return UINTPTR_MAX;
}

- (id)copyWithZone:(OOZone*)zone
{
    (void)zone;
    return self;
}

- (const char*)UTF8String
{
    std::string_view view = utf8View(self);
    return view.data();
}

- (uintptr_t)length
{
    return length;
}

- (BOOL)isEqualToString:(OOConstantString*)other
{
    if (other == self)
        return YES;
    if (!isConstantString(other))
        return NO;
    return utf8View(self) == utf8View(other);
}

- (BOOL)isEqual:(id)other
{
    return [self isEqualToString:other];
}

- (uintptr_t)hash
{
    // FNV-1a over the UTF-8 bytes, so equal literals hash equally whichever form clang chose.
    uint64_t h = 14695981039346656037ull;
    for (char c : utf8View(self)) {
        h ^= static_cast<unsigned char>(c);
        h *= 1099511628211ull;
    }
    return static_cast<uintptr_t>(h);
}

@end

@implementation OOTinyString

- (uintptr_t)length
{
    return (bitsOf(self) >> 3) & 0x1F; // ASCII only, so UTF-16 units == characters
}

@end
