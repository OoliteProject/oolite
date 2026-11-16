/*

OOShaderUniformMethodType.h

Type code declarations and OpenStep implementation agnostic method type
matching for uniform bindings.


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

#pragma once

#include "OOOpenGLExtensionManager.h"

#if OO_SHADERS || defined(OO_DEBUG_MONITOR_ENABLED)

#include "OOMaths.h"
#include <string>

typedef enum {
    kOOShaderUniformTypeInvalid, // Not valid for bindings or constants

    kOOShaderUniformTypeChar, // Binding only
    kOOShaderUniformTypeUnsignedChar, // Binding only
    kOOShaderUniformTypeShort, // Binding only
    kOOShaderUniformTypeUnsignedShort, // Binding only
    kOOShaderUniformTypeInt, // Binding or constant
    kOOShaderUniformTypeUnsignedInt, // Binding only
    kOOShaderUniformTypeLong, // Binding only
    kOOShaderUniformTypeUnsignedLong, // Binding only
    kOOShaderUniformTypeLongLong, // Binding only
    kOOShaderUniformTypeUnsignedLongLong, // Binding only
    kOOShaderUniformTypeFloat, // Binding or constant
    kOOShaderUniformTypeDouble, // Binding only
    kOOShaderUniformTypeVector, // Binding or constant
    kOOShaderUniformTypeHPVector, // Binding only
    kOOShaderUniformTypeQuaternion, // Binding or constant
    kOOShaderUniformTypeMatrix, // Binding or constant
    kOOShaderUniformTypePoint, // Binding only
    kOOShaderUniformTypeColor, // Binding only: the C++ colour (OOColor *), since bead oo-9ht.1 deleted its facade
    kOOShaderUniformTypeObject, // Binding only

    kOOShaderUniformTypeCount // Not valid for bindings or constants
} OOShaderUniformType;

/*	The uniform type of a return type's encoding (@encode() of the type; NULL gives invalid): the
        member tables below give their rows' types this way, so a row's type is the method's it
        replaced. (OOShaderUniformTypeFromMethod(), which read a method's encoding from the runtime for
        the Objective-C binding target, went with that target in bead oo-4aq6a.7.)
*/
OOShaderUniformType OOShaderUniformTypeFromEncoding(const char* typeCode);

/*	Binding to a target's C++ members (bead oo-9ht.158, ADR-0056 amendment oo-9ht.158): a uniform
        bound to a property name the target's class lists in its member table reads the member through
        the table's getter, not a method found by selector. The value is passed in the field its type
        uses: integers (and booleans and enums) in i, floats in f, the structures in theirs, a colour
        in color (borrowed).
*/
class OOColor;
struct OOShaderBindingValue {
    long long i;
    double f;
    Vector v;
    HPVector hpv;
    Quaternion q;
    OOMatrix m;
    NSPoint p;
    OOColor* color;
};

/*	A row's getter reads the member of the target's C++ object (bead oo-9ht.39.6.1: the rows receive
        the C++ entity; the getter had the Objective-C object since bead oo-9ht.158). The same type as
        OOShaderCxxBindingGetter (OOShaderUniform.h), so the uniform reads a member binding as it reads
        a C++ target's.
*/
namespace oo {
class RefCounted;
}
typedef void (*OOShaderMemberGetter)(oo::RefCounted* target, OOShaderBindingValue& outValue);

struct OOShaderMemberBinding {
    OOShaderUniformType type;
    OOShaderMemberGetter get;
    oo::RefCounted* target; // the C++ object get reads (the entity's part), borrowed: the uniform holds it weakly
};

/*	A material's binding target is the C++ entity (bead oo-9ht.39.6, ADR-0056 amendment
        oo-9ht.39.6). What the uniform and the material asked of the entity's Objective-C object they
        ask through these, which the entities register (EntityShaderBindings.mm), so the materials
        still link without them; with none registered an entity target binds nothing.
*/
class Entity;
struct OOShaderEntityHooks {
    // -superShaderBindingTarget: the entity a "bind to super" uniform binds to next, or null.
    Entity* (*superTarget)(Entity* entity);
    // What the log lines printed for the entity's Objective-C object (bead oo-dpyk8, which deleted it):
    // its class's name ("Entity"), and its description; "(null)" for an entity without one.
    std::string (*className)(Entity* entity);
    std::string (*description)(Entity* entity);
    // The row of the entities' member table for the name, where it binds this entity (only for the
    // root facade's own class, as the member lookup above).
    bool (*memberBinding)(Entity* entity, const char* property, OOShaderMemberBinding* outBinding);
    // -randomSeedForShaders, where the entity's object answers it.
    bool (*randomSeed)(Entity* entity, uint32_t* outSeed);
};
void OOSetShaderEntityHooks(const OOShaderEntityHooks& hooks) noexcept;
const OOShaderEntityHooks* OOShaderEntityHooksIfSet() noexcept; // null where none is registered

/*	(The selector path for an Objective-C target - OOShaderUniformBindMethod(), OOCallIntegerMethod(),
        OOCallFloatMethod() and the return-type casts of the method's IMP - went with that target in bead
        oo-4aq6a.7: no game code bound an Objective-C object, and callObjC() calls only C++ tables.)
*/

#endif // OO_SHADERS
