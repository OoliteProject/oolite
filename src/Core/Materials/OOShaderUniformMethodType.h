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

#import "OOOpenGLExtensionManager.h"

#if OO_SHADERS || defined(OO_DEBUG_MONITOR_ENABLED)

#import "OOMaths.h"
#include <objc/runtime.h>
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

/*	The uniform type of a method's return value, from the runtime's type encoding (its
        arguments are not considered, as the method signature object's -methodReturnType did not
        consider them; bead oo-3rb.15). NULL gives kOOShaderUniformTypeInvalid.
*/
OOShaderUniformType OOShaderUniformTypeFromMethod(Method method);

// The same for a type encoding (@encode() of the return type; NULL gives invalid): the member
// tables below give their rows' types this way, so a row's type is the method's it replaced.
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

typedef void (*OOShaderBindingGetter)(id object, OOShaderBindingValue& outValue);

struct OOShaderMemberBinding {
    OOShaderUniformType type;
    OOShaderBindingGetter get;
};

/*	The member tables are registered by their classes (the entities': Entity+ObjCBridge.mm), so the
        uniform links without them. A lookup answers false where the target's class has no row for the
        name, the row does not apply to this target, or its type is not bindable: the uniform then binds
        by selector as before.
*/
typedef bool (*OOShaderMemberBindingLookup)(id target, SEL selector, OOShaderMemberBinding* outBinding);
void OOSetShaderMemberBindingLookup(OOShaderMemberBindingLookup lookup) noexcept;
bool OOShaderMemberBindingFor(id target, SEL selector, OOShaderMemberBinding* outBinding);

/*	The selector path, for a name no member table answers (a material may bind any method without
        arguments; bead oo-9ht.158 keeps that until a decision restricts the set): what the uniform did
        before, moved here from OOShaderUniform.mm. False with *outProblem set where it cannot bind.
*/
bool OOShaderUniformBindMethod(id target, SEL selector, IMP* outMethod, OOShaderUniformType* outType, std::string* outProblem);

long long OOCallIntegerMethod(id object, SEL selector, IMP method, OOShaderUniformType type);
double OOCallFloatMethod(id object, SEL selector, IMP method, OOShaderUniformType type);

typedef char (*CharReturnMsgSend)(id, SEL);
typedef unsigned char (*UnsignedCharReturnMsgSend)(id, SEL);
typedef short (*ShortReturnMsgSend)(id, SEL);
typedef unsigned short (*UnsignedShortReturnMsgSend)(id, SEL);
typedef int (*IntReturnMsgSend)(id, SEL);
typedef unsigned int (*UnsignedIntReturnMsgSend)(id, SEL);
typedef long (*LongReturnMsgSend)(id, SEL);
typedef unsigned long (*UnsignedLongReturnMsgSend)(id, SEL);
typedef long long (*LongLongReturnMsgSend)(id, SEL);
typedef unsigned long long (*UnsignedLongLongReturnMsgSend)(id, SEL);
typedef float (*FloatReturnMsgSend)(id, SEL);
typedef double (*DoubleReturnMsgSend)(id, SEL);
typedef Vector (*VectorReturnMsgSend)(id, SEL);
typedef HPVector (*HPVectorReturnMsgSend)(id, SEL);
typedef Quaternion (*QuaternionReturnMsgSend)(id, SEL);
typedef OOMatrix (*MatrixReturnMsgSend)(id, SEL);
typedef NSPoint (*PointReturnMsgSend)(id, SEL);
typedef id (*ObjectReturnMsgSend)(id, SEL);
// kOOShaderUniformTypeColor: a colour binding answers the C++ colour, borrowed (bead oo-9ht.1).
class OOColor;
typedef OOColor* (*ColorReturnMsgSend)(id, SEL);

#endif // OO_SHADERS
