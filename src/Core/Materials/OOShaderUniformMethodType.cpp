/*

OOShaderUniformMethodType.m


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

/*
        For shader uniform binding to work, it is necessary to be able to tell
   the return type of a method. This is done by comparing the return type
   encoding of the method to those of methods in a template class, one method
   for each supported return type. The encodings compared are the member
   tables' rows', @encode() of the member's type.

        The encoding is platform-defined, so to stay implementation-agnostic the
   template encodings are the compiler's own, @encode() of each type: what the
   runtime records for a method returning that type; its measured literals,
   kOOTypeEncoding<> (OOTypeEncodings.h).
*/

#include "OOShaderUniformMethodType.h"

#if OO_SHADERS || defined(OO_DEBUG_MONITOR_ENABLED)

#include <cstring>

#include "OOColor.h"
#include "OOMaths.h"
#include "OOTypeEncodings.h"  // @encode()'s measured literals; OOColor * the complete class's, as the bindings' own
#include "oofnd/String.hpp"

static bool sInited = false;
static const char* sTemplates[kOOShaderUniformTypeCount];

static void InitTemplates(void);

OOShaderUniformType OOShaderUniformTypeFromEncoding(const char* typeCode) {
  unsigned i;

  if (EXPECT_NOT(sInited == false)) InitTemplates();
  if (EXPECT_NOT(typeCode == NULL)) return kOOShaderUniformTypeInvalid;

  for (i = kOOShaderUniformTypeInvalid + 1; i != kOOShaderUniformTypeCount;
       ++i) {
    if (sTemplates[i] != NULL && strcmp(sTemplates[i], typeCode) == 0)
      return (OOShaderUniformType)i;
  }
  return kOOShaderUniformTypeInvalid;
}

// The entities' hooks: none until the entities register theirs.
namespace {
OOShaderEntityHooks sEntityHooks = {};
bool sEntityHooksSet = false;
}  // namespace

void OOSetShaderEntityHooks(const OOShaderEntityHooks& hooks) noexcept {
  sEntityHooks = hooks;
  sEntityHooksSet = true;
}

const OOShaderEntityHooks* OOShaderEntityHooksIfSet() noexcept {
  return sEntityHooksSet ? &sEntityHooks : nullptr;
}

static void InitTemplates(void) {
// Each was the return type of a template method (-signedCharMethod and so on).
#define GET_TEMPLATE(enumValue, type)              \
  do {                                             \
    sTemplates[enumValue] = kOOTypeEncoding<type>; \
  } while (0)

  GET_TEMPLATE(kOOShaderUniformTypeChar, signed char);
  GET_TEMPLATE(kOOShaderUniformTypeUnsignedChar, unsigned char);
  GET_TEMPLATE(kOOShaderUniformTypeShort, signed short);
  GET_TEMPLATE(kOOShaderUniformTypeUnsignedShort, unsigned short);
  GET_TEMPLATE(kOOShaderUniformTypeInt, signed int);
  GET_TEMPLATE(kOOShaderUniformTypeUnsignedInt, unsigned int);
  GET_TEMPLATE(kOOShaderUniformTypeLong, signed long);
  GET_TEMPLATE(kOOShaderUniformTypeUnsignedLong, unsigned long);
  GET_TEMPLATE(kOOShaderUniformTypeFloat, float);
  GET_TEMPLATE(kOOShaderUniformTypeDouble, double);
  GET_TEMPLATE(kOOShaderUniformTypeVector, Vector);
  GET_TEMPLATE(kOOShaderUniformTypeHPVector, HPVector);
  GET_TEMPLATE(kOOShaderUniformTypeQuaternion, Quaternion);
  GET_TEMPLATE(kOOShaderUniformTypeMatrix, OOMatrix);
  GET_TEMPLATE(kOOShaderUniformTypePoint, NSPoint);
  // The colour bindings (laserColor, fogUniform) answer the C++ colour
  // (OOShaderUniform.mm).
  GET_TEMPLATE(kOOShaderUniformTypeColor, OOColor*);
  GET_TEMPLATE(kOOShaderUniformTypeObject, OOObjCId);  // id's

  sInited = true;
}

#endif  // OO_SHADERS
