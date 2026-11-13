/*

OOPolygonSprite.m
Oolite


Copyright (C) 2009-2013 Jens Ayton

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

/*	Implementation note:

        The polygon data is tesselated (on object creation) using a GLU
   tesselator. Although GLU produces a mix of triangles, triangle fans and
   triangle strips, we convert those to a single triangle soup since the
   polygons are unlikely to be large enough that using multiple primitives would
   be a win.

        Uniquing vertices and using indices, and using the same vertex array for
        outline and filled mode, would in principle be more efficient, but not
        worth the added complexity in the preprocessing given the simplicity of
        the icons we're likely to encounter.
*/

#include "OOPolygonSprite.h"

#include <format>
#include <string_view>

#include "OOGraphicsResetManager.h"
#include "OOMacroOpenGL.h"
#include "OOMaths.h"
#include "OOPointMaths.h"
#include "oofnd/Defaults.hpp"
#include "oofnd/String.hpp"
#include "oofnd/objc/OOAssert.h"
#include "oofnd/objc/OOException.h"

#ifndef APIENTRY
#define APIENTRY
#endif

#define kCosMitreLimit 0.866f  // Approximately cos(30 deg)

/*	Contours are std::vector<NSPoint> (arrays of point boxes before).
   The tesselator is handed a pointer to each vertex, so a
   contour must not change, or be destroyed, until its polygon has ended (the
   boxes used to live in the autorelease pool until -loadPolygons: returned).
*/
using OOPolygonContour = std::vector<NSPoint>;

using TessPolygonData = struct {
  std::vector<GLfloat> data;   // the vertices, as x, y pairs
  GLenum mode;                 // Current primitive mode.
  size_t vCount;               // Number of vertices so far in primitive.
  NSPoint pending0, pending1;  // Used for splitting
                               // GL_TRIANGLE_STRIP/GL_TRIANGLE_FAN primitives.
  bool OK;                     // Set to false to indicate error.
  std::vector<std::unique_ptr<NSPoint>>
      combinedVertices;  // made by the combine callback; live until the data
                         // goes
#ifndef NDEBUG
  bool generatingOutline;
  unsigned svgID;
  std::string name;
  std::optional<std::string> debugSVG;  // nullopt: not dumping
#endif
};

namespace {
std::vector<OOPolygonContour> DataArrayToPoints(TessPolygonData* data,
                                                const oo::PList& dataArray);
OOPolygonContour BuildOutlineContour(const OOPolygonContour& dataArray,
                                     GLfloat width, bool inner);

void SubmitVertices(GLUtesselator* tesselator, TessPolygonData* polygonData,
                    const OOPolygonContour& contour);
}  // namespace

static bool AppendVertex(TessPolygonData* data, NSPoint vertex);

#ifndef NDEBUG
static void SVGDumpBegin(TessPolygonData* data);
static void SVGDumpEnd(TessPolygonData* data);
namespace {
void SVGDumpBeginGroup(TessPolygonData* data, std::string_view name);
}
static void SVGDumpEndGroup(TessPolygonData* data);
namespace {
void SVGDumpAppendBaseContour(TessPolygonData* data,
                              const OOPolygonContour& points);
}
static void SVGDumpBeginPrimitive(TessPolygonData* data);
static void SVGDumpEndPrimitive(TessPolygonData* data);
static void SVGDumpAppendTriangle(TessPolygonData* data, NSPoint v0, NSPoint v1,
                                  NSPoint v2);
#else
#define SVGDumpEnd(data) \
  do {                   \
  } while (0)
#define SVGDumpBeginGroup(data, name) \
  do {                                \
  } while (0)
#define SVGDumpEndGroup(data) \
  do {                        \
  } while (0)
#define SVGDumpAppendBaseContour(data, points) \
  do {                                         \
  } while (0)
#define SVGDumpBeginPrimitive(data) \
  do {                              \
  } while (0)
#define SVGDumpEndPrimitive(data) \
  do {                            \
  } while (0)
#define SVGDumpAppendTriangle(data, v0, v1, v2) \
  do {                                          \
  } while (0)
#endif

static void APIENTRY TessBeginCallback(GLenum type, void* polygonData);
static void APIENTRY TessVertexCallback(void* vertexData, void* polygonData);
static void APIENTRY TessCombineCallback(GLdouble coords[3],
                                         void* vertexData[4], GLfloat weight[4],
                                         void** outData, void* polygonData);
static void APIENTRY TessEndCallback(void* polygonData);

static void APIENTRY ErrorCallback(GLenum error, void* polygonData);

// this is needed to maintain compatibility with GCC 14+
using TessFuncPtr = GLvoid (*)();

// Null where -initWithDataArray:outlineWidth:name: released itself and answered
// nil.
std::shared_ptr<OOPolygonSprite> OOPolygonSprite::initWithDataArray(
    const oo::PList& dataArray, GLfloat outlineWidth, const std::string& name) {
  std::shared_ptr<OOPolygonSprite> sprite =
      std::shared_ptr<OOPolygonSprite>(new OOPolygonSprite(), oo::Dispose{});
  {
#ifndef NDEBUG
    sprite->_name = name;
#endif

    if (dataArray.count() == 0) {
      return nullptr;
    }

    // Normalize data to array-of-arrays form.
    const oo::PList* first = dataArray.at(0);
    const bool arrayOfArrays = first != nullptr && first->isArray();
    if (!sprite->loadPolygons(
            (arrayOfArrays ? dataArray
                           : oo::PList(oo::PList::Array{dataArray})),
            outlineWidth)) {
      return nullptr;
    }

    // -initWithDataArray:... registered the sprite.
    OOGraphicsResetManager::sharedManager()->registerCxxClient(sprite.get());
  }

  return sprite;
}

OOPolygonSprite::~OOPolygonSprite() {
  OOGraphicsResetManager::sharedManager()->unregisterCxxClient(this);
}

#ifndef NDEBUG
std::optional<std::string> OOPolygonSprite::descriptionComponents() const {
  return _name;
}
#endif

std::string OOPolygonSprite::description() const {
  std::string result =
      std::format("<OOPolygonSprite {}>", oo::str::pointerDescription(this));
#ifndef NDEBUG
  const std::optional<std::string> components = descriptionComponents();
  if (components.has_value()) result += "{" + *components + "}";
#endif
  return result;
}

void OOPolygonSprite::drawWithData(GLfloat* data, size_t count, GLuint* vbo) {
  if (count == 0) return;
  OOCParameterAssert(vbo != nullptr && data != nullptr);

  OO_ENTER_OPENGL();
  OOSetOpenGLState(OOOpenGLStateID::kOverlay);

#if OO_USE_VBO
  bool useVBO = OOOpenGLExtensionManager::sharedManager()->vboSupported();

  if (useVBO) {
    if (*vbo == 0) {
      OOGL(glGenBuffersARB(1, vbo));
      if (*vbo != 0) {
        OOGL(glBindBufferARB(GL_ARRAY_BUFFER, *vbo));
        OOGL(glBufferDataARB(GL_ARRAY_BUFFER, sizeof(GLfloat) * count * 2, data,
                             GL_STATIC_DRAW));
      }
    } else {
      OOGL(glBindBufferARB(GL_ARRAY_BUFFER, *vbo));
    }
    if (*vbo != 0)
      data = NULL;  // Must pass NULL pointer to glVertexPointer to use VBO.
  }
#endif

  OOGL(glEnableClientState(GL_VERTEX_ARRAY));
  OOGL(glVertexPointer(2, GL_FLOAT, 0, data));
  OOGL(glDrawArrays(GL_TRIANGLES, 0, count));
  OOGL(glDisableClientState(GL_VERTEX_ARRAY));

#if OO_USE_VBO
  if (useVBO) OOGL(glBindBufferARB(GL_ARRAY_BUFFER, 0));
#endif

  OOVerifyOpenGLState();
  cxx_OOCheckOpenGLErrors([&]() -> std::string {
    return "OOPolygonSprite after rendering " + description();
  });
}

void OOPolygonSprite::drawFilled() {
#if !OO_USE_VBO
  GLuint _solidVBO;  // Unusued
#endif

  drawWithData(_solidData.data(), _solidData.size() / 2, &_solidVBO);
}

void OOPolygonSprite::drawOutline() {
#if !OO_USE_VBO
  GLuint _outlineVBO;  // Unusued
#endif

  drawWithData(_outlineData.data(), _outlineData.size() / 2, &_outlineVBO);
}

void OOPolygonSprite::resetGraphicsState() {
#if OO_USE_VBO
  OO_ENTER_OPENGL();

  if (_solidVBO != 0) glDeleteBuffersARB(1, &_solidVBO);
  if (_outlineVBO != 0) glDeleteBuffersARB(1, &_outlineVBO);

  _solidVBO = 0;
  _outlineVBO = 0;
#endif
}

// FIXME: this method is absolutely horrible.
bool OOPolygonSprite::loadPolygons(const oo::PList& dataArray,
                                   float outlineWidth) {
  OOCParameterAssert(dataArray);

  GLUtesselator* tesselator = nullptr;
  std::vector<OOPolygonContour>
      contours;  // the tesselator points into these until the end
  std::vector<OOPolygonContour>
      outlineContours;  // (vectors move their buffers, so the points stay put)

  TessPolygonData polygonData{};
  polygonData.OK = true;
#ifndef NDEBUG
  polygonData.name = _name;
  if (oo::Defaults::standard().boolForKey("polygon-sprite-dump-svg"))
    SVGDumpBegin(&polygonData);
#endif

  // For efficiency, grow to more than big enough for most cases to avoid
  // regrowing.
  polygonData.data.reserve(100 * 2);

  tesselator = gluNewTess();
  if (tesselator == nullptr) {
    polygonData.OK = false;
    goto END;
  }

  contours = DataArrayToPoints(&polygonData, dataArray);

  /*** Tesselate polygon fill ***/
  gluTessCallback(tesselator, GLU_TESS_BEGIN_DATA,
                  reinterpret_cast<TessFuncPtr>(TessBeginCallback));
  gluTessCallback(tesselator, GLU_TESS_VERTEX_DATA,
                  reinterpret_cast<TessFuncPtr>(TessVertexCallback));
  gluTessCallback(tesselator, GLU_TESS_END_DATA,
                  reinterpret_cast<TessFuncPtr>(TessEndCallback));
  gluTessCallback(tesselator, GLU_TESS_ERROR_DATA,
                  reinterpret_cast<TessFuncPtr>(ErrorCallback));
  gluTessCallback(tesselator, GLU_TESS_COMBINE_DATA,
                  reinterpret_cast<TessFuncPtr>(TessCombineCallback));

  gluTessBeginPolygon(tesselator, &polygonData);
  SVGDumpBeginGroup(&polygonData, "Fill");

  std::size_t contourCount, contourIndex;
  contourCount = contours.size();
  for (contourIndex = 0; contourIndex < contourCount && polygonData.OK;
       contourIndex++) {
    SubmitVertices(tesselator, &polygonData, contours[contourIndex]);
  }

  gluTessEndPolygon(tesselator);
  SVGDumpEndGroup(&polygonData);

  if (polygonData.OK) {
    _solidData = std::move(polygonData.data);
    _solidData.shrink_to_fit();
  }
  if (!polygonData.OK) goto END;

  /*** Tesselate polygon outline ***/
  gluDeleteTess(tesselator);
  tesselator = gluNewTess();
  if (tesselator == nullptr) {
    polygonData.OK = false;
    goto END;
  }

  polygonData.data = {};
  polygonData.data.reserve(100 * 2);
#ifndef NDEBUG
  polygonData.generatingOutline = true;
#endif

  gluTessCallback(tesselator, GLU_TESS_BEGIN_DATA,
                  reinterpret_cast<TessFuncPtr>(TessBeginCallback));
  gluTessCallback(tesselator, GLU_TESS_VERTEX_DATA,
                  reinterpret_cast<TessFuncPtr>(TessVertexCallback));
  gluTessCallback(tesselator, GLU_TESS_END_DATA,
                  reinterpret_cast<TessFuncPtr>(TessEndCallback));
  gluTessCallback(tesselator, GLU_TESS_ERROR_DATA,
                  reinterpret_cast<TessFuncPtr>(ErrorCallback));
  gluTessCallback(tesselator, GLU_TESS_COMBINE_DATA,
                  reinterpret_cast<TessFuncPtr>(TessCombineCallback));
  gluTessProperty(tesselator, GLU_TESS_WINDING_RULE, GLU_TESS_WINDING_POSITIVE);

  gluTessBeginPolygon(tesselator, &polygonData);
  SVGDumpBeginGroup(&polygonData, "Outline");

  outlineWidth *= 0.5f;  // Half the width in, half the width out.
  contourCount = contours.size();
  outlineContours.reserve(contourCount * 2);
  for (contourIndex = 0; contourIndex < contourCount && polygonData.OK;
       contourIndex++) {
    const OOPolygonContour& contour = contours[contourIndex];

    outlineContours.push_back(
        BuildOutlineContour(contour, outlineWidth, false));
    SubmitVertices(tesselator, &polygonData, outlineContours.back());
    outlineContours.push_back(BuildOutlineContour(contour, outlineWidth, true));
    SubmitVertices(tesselator, &polygonData, outlineContours.back());
  }

  gluTessEndPolygon(tesselator);
  SVGDumpEndGroup(&polygonData);

  if (polygonData.OK) {
    _outlineData = std::move(polygonData.data);
    _outlineData.shrink_to_fit();
  }

END:
  SVGDumpEnd(&polygonData);
  gluDeleteTess(tesselator);
  return polygonData.OK;
}

namespace {

void SubmitVertices(GLUtesselator* tesselator, TessPolygonData* polygonData,
                    const OOPolygonContour& contour) {
  std::size_t vertexCount = contour.size(), vertexIndex;
  if (vertexCount > 2) {
    gluTessBeginContour(tesselator);

    for (vertexIndex = 0; vertexIndex < vertexCount && polygonData->OK;
         vertexIndex++) {
      const NSPoint* point = &contour[vertexIndex];
      NSPoint p = *point;
      GLdouble vert[3] = {p.x, p.y, 0.0};

      gluTessVertex(tesselator, vert, const_cast<NSPoint*>(point));
    }

    gluTessEndContour(tesselator);
  }
}

std::vector<OOPolygonContour> DataArrayToPoints(TessPolygonData* data,
                                                const oo::PList& dataArray) {
  /*	This converts an icon definition in the form of an array of array of
          numbers to internal data in the form of a list of contours (lists of
          NSPoints). In addition to repacking the data, it performs
          the following data processing:
            * Sequences of duplicate vertices are removed (including across the
              beginning and end, in case of manually closed contours).
            * Vertices containing nans or infinities are skipped, Just In Case.
            * The signed area of each contour is calculated; if it is negative,
              the contour is clockwise, and we need to flip it.
  */

  SVGDumpBeginGroup(data, "Base contours");

  std::size_t polyIter, polyCount = dataArray.count();
  std::vector<OOPolygonContour> subArrays(polyCount);

  for (polyIter = 0; polyIter < polyCount; polyIter++) {
    const oo::PList& polyDef = *dataArray.at(polyIter);
    std::size_t vertIter, vertCount = polyDef.count() / 2;
    OOPolygonContour newPolyDef;
    newPolyDef.reserve(vertCount);
    double area = 0;

    double oldX = polyDef.at<double>((vertCount - 1) * 2);
    double oldY = polyDef.at<double>((vertCount - 1) * 2 + 1);

    for (vertIter = 0; vertIter < vertCount; vertIter++) {
      double x = polyDef.at<double>(vertIter * 2);
      double y = polyDef.at<double>(vertIter * 2 + 1);

      // Skip bad or duplicate vertices.
      if (x == oldX && y == oldY) continue;
      if (isnan(x) || isnan(y)) continue;
      if (!isfinite(x) || !isfinite(y)) continue;

      area += x * oldY - oldX * y;

      oldX = x;
      oldY = y;

      newPolyDef.push_back(NSMakePoint(x, y));
    }

    // Eliminate duplicates at ends - the initialization of oldX and oldY will
    // catch one pair, but not extra-silly cases.
    while (newPolyDef.size() > 1 &&
           NSEqualPoints(newPolyDef.front(), newPolyDef.back())) {
      newPolyDef.pop_back();
    }

    if (area >= 0) {
      subArrays[polyIter] = std::move(newPolyDef);
    } else {
      subArrays[polyIter] =
          OOPolygonContour(newPolyDef.rbegin(), newPolyDef.rend());
    }

    SVGDumpAppendBaseContour(data, subArrays[polyIter]);
  }

  SVGDumpEndGroup(data);
  return subArrays;
}

OOPolygonContour BuildOutlineContour(const OOPolygonContour& dataArray,
                                     GLfloat width, bool inner) {
  std::size_t i, count = dataArray.size();
  if (count < 2) return dataArray;

  /*
          Generate inner or outer boundary for a contour, offset by the
     specified width inwards/outwards from the line. At anticlockwise (convex)
     corners sharper than acos(kCosMitreLimit), the corner is mitred, i.e. an
          additional line segment is generated so the outline doesn't protrude
          arbitratrily far.

          Overview of the maths:
          For each vertex, we consider a normalized vector A from the previous
          vertex and a normalized vector B to the next vertex. (These are always
          defined since the polygons are closed.)

          The dot product of A and B is the cosine of the angle, which we
     compare to kCosMitreLimit to determine mitreing. If the dot product is
     exactly 1, the vectors are antiparallel and we have a cap; the mitreing
     case handles this implicitly. (The non-mitreing case would result in a
          divide-by-zero.)

          Non-mitreing case:
                  To position the vertex, we need a vector N normal to the
     corner. We observe that A + B is tangent to the corner, and a 90 degree
                  rotation in 2D is trivial. The offset along this line is
                  proportional to the secant of the angle between N and the 90
     degree rotation of A (or B; the angle is by definition the same), or width
     / (N dot rA). Since both N and rA are rotated by ninety degrees in the same
                  direction, we can cut out both rotations (i.e., using the
     tangent and A) and get the same result.

          Mitreing case:
                  The two new vertices are the original vertex offset by scale
     along the ninety-degree rotation of A and B respectively.
  */

  NSPoint prev, current, next;
  if (inner) {
    prev = dataArray[0];
    current = dataArray[count - 1];
    next = dataArray[count - 2];
  } else {
    prev = dataArray[count - 1];
    current = dataArray[0];
    next = dataArray[1];
  }

  OOPolygonContour result;
  result.reserve(count);

  for (i = 0; i < count; i++) {
    NSPoint a = PtNormal(PtSub(current, prev));
    NSPoint b = PtNormal(PtSub(next, current));

    double dot = PtDot(a, b);
    bool clockwise = PtCross(a, b) < 0.0f;

    if (-dot < kCosMitreLimit || !clockwise) {
      // Non-mitreing case.
      NSPoint t = PtNormal(PtAdd(a, b));
      NSPoint v = PtScale(PtRotACW(t), width / PtDot(t, a));

      if (!isnan(v.x) && !isnan(v.y)) {
        result.push_back(PtAdd(v, current));
      }
    } else {
      // Mitreing case.
      NSPoint v1 = PtScale(PtAdd(PtRotACW(a), a), width);
      NSPoint v2 = PtScale(PtSub(PtRotACW(b), b), width);

      if (!isnan(v1.x) && !isnan(v1.y)) {
        result.push_back(PtAdd(v1, current));
      }
      if (!isnan(v2.x) && !isnan(v2.y)) {
        result.push_back(PtAdd(v2, current));
      }
    }

    prev = current;
    current = next;

    if (inner) {
      next = dataArray[(count * 2 - 3 - i) % count];
    } else {
      next = dataArray[(i + 2) % count];
    }
  }

  return result;
}

}  // namespace

static bool AppendVertex(TessPolygonData* data, NSPoint vertex) {
  OOCParameterAssert(data != nullptr);

  data->data.push_back(vertex.x);
  data->data.push_back(vertex.y);
  return true;
}

static void APIENTRY TessBeginCallback(GLenum type, void* polygonData) {
  TessPolygonData* data = static_cast<TessPolygonData*>(polygonData);
  OOCParameterAssert(data != nullptr);

  data->mode = type;
  data->vCount = 0;

  SVGDumpBeginPrimitive(data);
}

static void APIENTRY TessVertexCallback(void* vertexData, void* polygonData) {
  TessPolygonData* data = static_cast<TessPolygonData*>(polygonData);
  const NSPoint* vertPoint = static_cast<const NSPoint*>(vertexData);
  OOCParameterAssert(vertPoint != nullptr && data != nullptr);
  if (!data->OK) return;

  NSPoint p = *vertPoint;
  NSPoint vertex = {p.x, p.y};
  size_t vCount = data->vCount++;

  switch (data->mode) {
    case GL_TRIANGLES:
      data->OK = AppendVertex(data, vertex);
#ifndef NDEBUG
      switch (vCount % 3) {
        case 0:
          data->pending0 = vertex;
          break;

        case 1:
          data->pending1 = vertex;
          break;

        case 2:
          SVGDumpAppendTriangle(data, data->pending0, data->pending1, vertex);
      }
#endif
      break;

    case GL_TRIANGLE_FAN:
      if (vCount == 0)
        data->pending0 = vertex;
      else if (vCount == 1)
        data->pending1 = vertex;
      else {
        data->OK = AppendVertex(data, data->pending0) &&
                   AppendVertex(data, data->pending1) &&
                   AppendVertex(data, vertex);
        SVGDumpAppendTriangle(data, data->pending0, data->pending1, vertex);
        data->pending1 = vertex;
      }
      break;

    case GL_TRIANGLE_STRIP:
      if (vCount == 0)
        data->pending0 = vertex;
      else if (vCount == 1)
        data->pending1 = vertex;
      else {
        /*	In order to produce consistent winding, the vertex->triangle
                order for GL_TRIANGLE_STRIP is:
                0, 1, 2
                2, 1, 3
                2, 3, 4
                4, 3, 5
                4, 5, 6
                6, 5, 7
                6, 7, 8

                Vertices 0 and 1 are special-cased above, and the first
                time we get here it's time for the first triangle, which
                is pending0, pending1, v. v (i.e., vertex 2) then goes into
                pending0.
                For the second triangle, the triangle is again pending0,
                pending1, v, and we then put v (i.e., vertex 3) into
                pending1.
                The third triangle follows the same pattern as the first,
                and the fourthe the same as the second.
                In other words, after storing each triangle, v goes into
                pending0 for even vertex indicies, and pending1 for odd
                vertex indices.
         */
        data->OK = AppendVertex(data, data->pending0) &&
                   AppendVertex(data, data->pending1) &&
                   AppendVertex(data, vertex);
        SVGDumpAppendTriangle(data, data->pending0, data->pending1, vertex);
        if ((vCount % 2) == 0)
          data->pending0 = vertex;
        else
          data->pending1 = vertex;
      }
      break;

    default:
      OO_LOG("polygonSprite.tesselate.error",
             "Unexpected tesselator primitive mode {}.",
             static_cast<unsigned>(data->mode));
      data->OK = false;
  }
}

void APIENTRY TessCombineCallback(GLdouble coords[3], void* /*vertexData*/[4],
                                  GLfloat /*weight*/[4], void** outData,
                                  void* polygonData) {
  TessPolygonData* data = static_cast<TessPolygonData*>(polygonData);
  NSPoint point = {coords[0], coords[1]};
  data->combinedVertices.push_back(std::make_unique<NSPoint>(point));
  *outData = data->combinedVertices.back().get();
}

static void APIENTRY TessEndCallback(void* polygonData) {
  TessPolygonData* data = static_cast<TessPolygonData*>(polygonData);
  OOCParameterAssert(data != nullptr);

  data->mode = 0;
  data->vCount = 0;

  SVGDumpEndPrimitive(data);
}

static void APIENTRY ErrorCallback(GLenum error, void* polygonData) {
  TessPolygonData* data = static_cast<TessPolygonData*>(polygonData);
  OOCParameterAssert(data != nullptr);

  std::string name;
#ifndef NDEBUG
  name = std::format(" \"{}\"", data->name);
#endif

  const char* errStr = reinterpret_cast<const char*>(gluErrorString(error));

  OO_LOG("polygonSprite.tesselate.error",
         "Error {} ({}) while tesselating polygon{}.", errStr,
         static_cast<unsigned>(error), name);
  data->OK = false;
}

#ifndef NDEBUG
#include "ResourceManager.h"
#include "legacy_random.h"

static void SVGDumpBegin(TessPolygonData* data) {
  data->debugSVG = std::string(
      "<?xml version=\"1.0\" standalone=\"no\"?>\n"
      "<!DOCTYPE svg PUBLIC \"-//W3C//DTD SVG 1.1//EN\" "
      "\"http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd\">\n"
      "<svg viewBox=\"-5 -5 10 10\" version=\"1.1\" "
      "xmlns=\"http://www.w3.org/2000/svg\">\n"
      "\t<desc>Oolite polygon sprite debug dump.</desc>\n"
      "\t\n");
}

static void SVGDumpEnd(TessPolygonData* data) {
  if (!data->debugSVG.has_value()) return;

  *data->debugSVG += "</svg>\n";
  ResourceManager::writeDiagnosticString(
      *data->debugSVG, std::format("Polygon Sprites/{}.svg", data->name));
  data->debugSVG.reset();
}

namespace {
void SVGDumpBeginGroup(TessPolygonData* data, std::string_view name) {
  if (!data->debugSVG.has_value()) return;

  *data->debugSVG += std::format("\t<g id=\"{} {}\">\n", name, data->svgID++);
}
}  // namespace

static void SVGDumpEndGroup(TessPolygonData* data) {
  if (!data->debugSVG.has_value()) return;
  *data->debugSVG += "\t</g>\n";
}

namespace {
void SVGDumpAppendBaseContour(TessPolygonData* data,
                              const OOPolygonContour& points) {
  if (!data->debugSVG.has_value()) return;

  const std::string groupName = std::format("contour {}", data->svgID++);
  *data->debugSVG += std::format(
      "\t\t<g id=\"{}\" stroke=\"#BBB\" fill=\"none\">\n\t\t<path "
      "stroke-width=\"0.05\" d=\"",
      groupName);

  std::size_t i, count = points.size();
  for (i = 0; i < count; i++) {
    NSPoint p = points[i];
    *data->debugSVG +=
        std::format("{} {:f} {:f} ", (i == 0) ? 'M' : 'L', p.x, -p.y);
  }

  // Close and add a circle at the first vertex. (SVG has support for end
  // markers, but this isn’t reliable across implementations.)
  if (points.empty())
    OORaiseException(
        OORangeException,
        "SVGDumpAppendBaseContour: empty contour");  // -objectAtIndex:0
                                                     // raised here
  NSPoint p = points[0];
  *data->debugSVG += std::format(
      "z\"/>\n\t\t\t<circle cx=\"{:f}\" cy=\"{:f}\" r=\"0.1\" fill=\"#BBB\" "
      "stroke=\"none\"/>\n\t\t</g>\n",
      p.x, -p.y);
}
}  // namespace

static void SVGDumpBeginPrimitive(TessPolygonData* data) {
  if (!data->debugSVG.has_value()) return;

  std::string groupName = "Unknown primitive";
  switch (data->mode) {
    case GL_TRIANGLES:
      groupName = "Triangle soup";
      break;

    case GL_TRIANGLE_FAN:
      groupName = "Triangle fan";
      break;

    case GL_TRIANGLE_STRIP:
      groupName = "Triangle strip";
      break;
  }
  groupName += std::format(" {}", data->svgID++);

  // Pick random colour for the primitive.
  uint8_t red = (Ranrot() & 0x3F) + 0x20;
  uint8_t green = (Ranrot() & 0x3F) + 0x20;
  uint8_t blue = (Ranrot() & 0x3F) + 0x20;
  if (!data->generatingOutline) {
    red += 0x80;
    green += 0x80;
    blue += 0x80;
  }

  *data->debugSVG += std::format(
      "\t\t<g id=\"{}\" fill=\"#{:2X}{:2X}{:2X}\" fill-opacity=\"0.3\" "
      "stroke=\"{}\" stroke-width=\"0.01\">\n",
      groupName, red, green, blue, data->generatingOutline ? "#060" : "#008");
}

static void SVGDumpEndPrimitive(TessPolygonData* data) {
  if (!data->debugSVG.has_value()) return;
  *data->debugSVG += "\t\t</g>\n";
}

static void SVGDumpAppendTriangle(TessPolygonData* data, NSPoint v0, NSPoint v1,
                                  NSPoint v2) {
  if (!data->debugSVG.has_value()) return;
  *data->debugSVG +=
      std::format("\t\t\t<path d=\"M {:f} {:f} L {:f} {:f} L {:f} {:f} z\"/>\n",
                  v0.x, -v0.y, v1.x, -v1.y, v2.x, -v2.y);
}
#endif
