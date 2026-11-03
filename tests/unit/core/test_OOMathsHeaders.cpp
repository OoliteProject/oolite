/*	test_OOMathsHeaders.cpp
        Unit tests for the maths headers' layout since upstream #748: each one
   (OOVector.h, OOQuaternion.h, OOFastArithmetic.h, ...) may be included on its
   own, in any order, rather than only through OOMaths.h (the umbrella's
   INCLUDED_OOMATHS_h guard, OOMATHS_STANDALONE and OOMATHS_OPENGL_INTEGRATION
   are gone). What they share (OOScalar, the M_ constants, MIN/MAX/ABS) is
   OOMathsBase.h's, which each includes. The case includes three of them
   directly, without OOMaths.h, and uses their inline functions. Run: bash
   meson test -C build/meson_test test_OOMathsHeaders
*/

#include "OOFastArithmetic.h"
#include "OOQuaternion.h"  // directly, not through OOMaths.h
#include "OOVector.h"

#if defined(INCLUDED_OOMATHS_h) || defined(OOMATHS_STANDALONE) || \
    defined(OOMATHS_OPENGL_INTEGRATION)
constexpr bool kUmbrellaMacros = true;
#else
constexpr bool kUmbrellaMacros = false;
#endif

#include <type_traits>

#include "oo_test.hpp"

// The headers work on their own, and the umbrella's switches are gone.
OO_TEST(mathsHeadersStandAlone) {
  OO_CHECK(!kUmbrellaMacros);
  OO_CHECK((std::is_same_v<OOScalar, GLfloat>));  // always the GL type
  Vector v = vector_add(make_vector(1, 2, 3), make_vector(1, 1, 1));
  OO_CHECK(v.x == 2 && v.y == 3 && v.z == 4);
  OO_CHECK(dot_product(v, make_vector(1, 0, 0)) == 2);
  Quaternion q = make_quaternion(1, 0, 0, 0);
  OO_CHECK(quaternion_dot_product(q, q) == 1);
  OO_CHECK(OOClamp_0_1_f(2.0f) == 1.0f);
  OO_CHECK(MIN(3, 4) == 3 && MAX(3, 4) == 4 && M_PI > 3.14);
}

OO_TEST_MAIN()
