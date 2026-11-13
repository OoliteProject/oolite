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

#include <cstddef>
#include <string>

#include "OOMaths.h"

// A uniform's (and a by-name method's) type tag: stored as uint8_t, an index
// into the template table, and the start of OOJSCall's method-type numbers, so
// typed constants rather than an enumeration.
using OOShaderUniformType = int;
inline constexpr OOShaderUniformType kOOShaderUniformTypeInvalid =
    0;  // Not valid for bindings or constants
inline constexpr OOShaderUniformType kOOShaderUniformTypeChar =
    1;  // Binding only
inline constexpr OOShaderUniformType kOOShaderUniformTypeUnsignedChar =
    2;  // Binding only
inline constexpr OOShaderUniformType kOOShaderUniformTypeShort =
    3;  // Binding only
inline constexpr OOShaderUniformType kOOShaderUniformTypeUnsignedShort =
    4;  // Binding only
inline constexpr OOShaderUniformType kOOShaderUniformTypeInt =
    5;  // Binding or constant
inline constexpr OOShaderUniformType kOOShaderUniformTypeUnsignedInt =
    6;  // Binding only
inline constexpr OOShaderUniformType kOOShaderUniformTypeLong =
    7;  // Binding only
inline constexpr OOShaderUniformType kOOShaderUniformTypeUnsignedLong =
    8;  // Binding only
inline constexpr OOShaderUniformType kOOShaderUniformTypeLongLong =
    9;  // Binding only
inline constexpr OOShaderUniformType kOOShaderUniformTypeUnsignedLongLong =
    10;  // Binding only
inline constexpr OOShaderUniformType kOOShaderUniformTypeFloat =
    11;  // Binding or constant
inline constexpr OOShaderUniformType kOOShaderUniformTypeDouble =
    12;  // Binding only
inline constexpr OOShaderUniformType kOOShaderUniformTypeVector =
    13;  // Binding or constant
inline constexpr OOShaderUniformType kOOShaderUniformTypeHPVector =
    14;  // Binding only
inline constexpr OOShaderUniformType kOOShaderUniformTypeQuaternion =
    15;  // Binding or constant
inline constexpr OOShaderUniformType kOOShaderUniformTypeMatrix =
    16;  // Binding or constant
inline constexpr OOShaderUniformType kOOShaderUniformTypePoint =
    17;  // Binding only
inline constexpr OOShaderUniformType kOOShaderUniformTypeColor =
    18;  // Binding only: the C++ colour (OOColor *)
inline constexpr OOShaderUniformType kOOShaderUniformTypeObject =
    19;  // Binding only
inline constexpr OOShaderUniformType kOOShaderUniformTypeCount =
    20;  // Not valid for bindings or constants
static_assert(static_cast<int>(kOOShaderUniformTypeInvalid) == 0);
static_assert(static_cast<int>(kOOShaderUniformTypeChar) == 1);
static_assert(static_cast<int>(kOOShaderUniformTypeUnsignedChar) == 2);
static_assert(static_cast<int>(kOOShaderUniformTypeShort) == 3);
static_assert(static_cast<int>(kOOShaderUniformTypeUnsignedShort) == 4);
static_assert(static_cast<int>(kOOShaderUniformTypeInt) == 5);
static_assert(static_cast<int>(kOOShaderUniformTypeUnsignedInt) == 6);
static_assert(static_cast<int>(kOOShaderUniformTypeLong) == 7);
static_assert(static_cast<int>(kOOShaderUniformTypeUnsignedLong) == 8);
static_assert(static_cast<int>(kOOShaderUniformTypeLongLong) == 9);
static_assert(static_cast<int>(kOOShaderUniformTypeUnsignedLongLong) == 10);
static_assert(static_cast<int>(kOOShaderUniformTypeFloat) == 11);
static_assert(static_cast<int>(kOOShaderUniformTypeDouble) == 12);
static_assert(static_cast<int>(kOOShaderUniformTypeVector) == 13);
static_assert(static_cast<int>(kOOShaderUniformTypeHPVector) == 14);
static_assert(static_cast<int>(kOOShaderUniformTypeQuaternion) == 15);
static_assert(static_cast<int>(kOOShaderUniformTypeMatrix) == 16);
static_assert(static_cast<int>(kOOShaderUniformTypePoint) == 17);
static_assert(static_cast<int>(kOOShaderUniformTypeColor) == 18);
static_assert(static_cast<int>(kOOShaderUniformTypeObject) == 19);

/*	The uniform type of a return type's encoding (@encode() of the type;
   NULL gives invalid): the member tables below give their rows' types this way,
   so a row's type is the method's it replaced.
*/
OOShaderUniformType OOShaderUniformTypeFromEncoding(const char* typeCode);

/*	Binding to a target's C++ members: a uniform
        bound to a property name the target's class lists in its member table
   reads the member through the table's getter, not a method found by selector.
   The value is passed in the field its type uses: integers (and booleans and
   enums) in i, floats in f, the structures in theirs, a colour in color
   (borrowed).
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

/*	A row's getter reads the member of the target's C++ object (the rows
   receive the C++ entity). The same type as OOShaderCxxBindingGetter
   (OOShaderUniform.h), so the uniform reads a member binding as it reads a C++
   target's.
*/
namespace oo {
class Object;
}
typedef void (*OOShaderMemberGetter)(oo::Object* target,
                                     OOShaderBindingValue& outValue);

struct OOShaderMemberBinding {
  OOShaderUniformType type;
  OOShaderMemberGetter get;
  oo::Object* target;  // the C++ object get reads (the entity's part),
                       // borrowed: the uniform holds it weakly
};

/*	A material's binding target is the C++ entity. What the uniform and the
   material ask of the entity they ask through these,
   which the entities register (EntityShaderBindings.cpp), so the materials
   still link without them; with none registered an entity target binds nothing.
*/
class Entity;
struct OOShaderEntityHooks {
  // -superShaderBindingTarget: the entity a "bind to super" uniform binds to
  // next, or null.
  Entity* (*superTarget)(Entity* entity);
  // What the log lines print for the entity: its class's
  // name ("Entity"), and its description; "(null)" for an entity without one.
  std::string (*className)(Entity* entity);
  std::string (*description)(Entity* entity);
  // The row of the entities' member table for the name, where it binds this
  // entity (as the member lookup above).
  bool (*memberBinding)(Entity* entity, const char* property,
                        OOShaderMemberBinding* outBinding);
  // -randomSeedForShaders, where the entity's object answers it.
  bool (*randomSeed)(Entity* entity, uint32_t* outSeed);
};
void OOSetShaderEntityHooks(const OOShaderEntityHooks& hooks) noexcept;
const OOShaderEntityHooks*
OOShaderEntityHooksIfSet() noexcept;  // null where none is registered

#endif  // OO_SHADERS
