/*	icosmesh

        Generates src/Core/OOPlanetData.cpp and src/Core/OOPlanetData.h: the
   vertex, texture coordinate and index arrays of a subdivided icosahedron, at
   kLevels levels of detail, all levels sharing one vertex array.

        Usage: icosmesh [output-directory]   (default: the current directory)

        Based on Jens Ayton's 2009 Objective-C tool of the same name (main.m,
   JAIcosTriangle, JAVertexSet, JAIcosMesh). The arithmetic, the vertex order
   and the output text are the same, so it regenerates the checked-in files
   exactly.
*/

#include <climits>
#include <clocale>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <map>
#include <numbers>
#include <string>
#include <vector>

namespace {

constexpr const char* kFileName = "OOPlanetData";
constexpr unsigned kLevels = 6;
constexpr double kPi = std::numbers::pi;

struct Vector {
  double x, y, z;
};

struct Vertex {
  Vector v;
  double s, t;  // Lat/long texture coordinates
};

Vector VectorAdd(Vector u, Vector v) {
  return {u.x + v.x, u.y + v.y, u.z + v.z};
}

Vector VectorSubtract(Vector u, Vector v) {
  return {u.x - v.x, u.y - v.y, u.z - v.z};
}

double VectorDot(Vector u, Vector v) {
  return u.x * v.x + u.y * v.y + u.z * v.z;
}

Vector VectorCross(Vector u, Vector v) {
  return {u.y * v.z - v.y * u.z, u.z * v.x - v.z * u.x, u.x * v.y - v.x * u.y};
}

double VectorMagnitude(Vector v) { return std::sqrt(VectorDot(v, v)); }

Vector VectorScaleReciprocal(Vector v, double s) {
  return {v.x / s, v.y / s, v.z / s};
}

Vector VectorNormal(Vector v) {
  return VectorScaleReciprocal(v, VectorMagnitude(v));
}

bool IsPolarVector(Vector v) { return v.x == 0.0 && v.z == 0.0; }

// Convert vector to latitude and longitude (or θ and φ).
void VectorToCoordsRad(Vector v, double* latitude, double* longitude) {
  v = VectorNormal(v);

  double las = v.y;
  if (las != 1.0f) {
    double lat = std::asin(las);
    double rlac =
        1.0 / std::sqrt(1.0 - las * las);  // Equivalent to abs(1/cos(lat))

    if (latitude != nullptr) *latitude = lat;
    if (longitude != nullptr) {
      double los = v.x * rlac;
      double lon = std::asin(std::fmin(1.0, std::fmax(-1.0, los)));

      // Quadrant rectification.
      if (v.z < 0.0f) {
        // We're beyond 90 degrees of longitude in some direction.
        if (v.x < 0.0f) {
          // ...specifically, west.
          lon = -kPi - lon;
        } else {
          // ...specifically, east.
          lon = kPi - lon;
        }
      }

      *longitude = lon;
    }
  } else {
    // Straight up, avoid divide-by-zero
    if (latitude != nullptr) *latitude = kPi / 2.0f;
    if (longitude != nullptr) *longitude = 0.0f;  // arbitrary
  }
}

void VectorToCoords0_1(Vector v, double* latitude, double* longitude) {
  VectorToCoordsRad(v, latitude, longitude);
  if (latitude != nullptr) *latitude = 1.0 - (*latitude / kPi + 0.5);
  if (longitude != nullptr) *longitude = 1.0 - (*longitude / (kPi * 2.0) + 0.5);
}

class Triangle {
 public:
  // Note: order is not guaranteed to be maintained.
  Triangle(Vector a, Vector b, Vector c) {
    vertices_[0].v = VectorNormal(a);
    vertices_[1].v = VectorNormal(b);
    vertices_[2].v = VectorNormal(c);

    // If one of our vertices is a pole, make it the first.
    if (IsPolarVector(vertices_[2].v)) rotate();
    if (IsPolarVector(vertices_[1].v)) rotate();

    // Ensure winding is consistent.
    fixUpWinding();

    generateTextureCoordinates();
  }

  const Vertex& vertex(unsigned i) const { return vertices_[i]; }

  // Four triangles. Vertex orders preserve winding. Triangle order is intended
  // to be somewhat cache-friendly, but not as good as actually optimizing the
  // data.
  void subdivideInto(std::vector<Triangle>& out) const {
    Vector a = vertices_[0].v;
    Vector b = vertices_[1].v;
    Vector c = vertices_[2].v;

    Vector ab = VectorNormal(VectorAdd(a, b));
    Vector bc = VectorNormal(VectorAdd(b, c));
    Vector ca = VectorNormal(VectorAdd(c, a));

    out.emplace_back(a, ab, ca);
    out.emplace_back(ab, b, bc);
    out.emplace_back(ca, bc, c);
    out.emplace_back(ab, bc, ca);
  }

 private:
  Vertex vertices_[3] = {};

  void rotate() {  // a = b, b = c, c = a
    Vertex temp = vertices_[0];
    vertices_[0] = vertices_[1];
    vertices_[1] = vertices_[2];
    vertices_[2] = temp;
  }

  // Requires that any polar coordinate is in [0].
  void generateTextureCoordinates() {
    VectorToCoords0_1(vertices_[1].v, &vertices_[1].t, &vertices_[1].s);
    VectorToCoords0_1(vertices_[2].v, &vertices_[2].t, &vertices_[2].s);
    if (!IsPolarVector(vertices_[0].v)) {
      VectorToCoords0_1(vertices_[0].v, &vertices_[0].t, &vertices_[0].s);
    } else {
      // Use longitude of average of v1 and v2.
      VectorToCoords0_1(VectorAdd(vertices_[1].v, vertices_[2].v), nullptr,
                        &vertices_[0].s);
      vertices_[0].t = (vertices_[0].v.y < 0) ? 1.0 : 0.0;
    }

    /*	Texture seam handling
            At the back of the mesh, at the longitude = 180°/-180° meridian, the
       texture wraps around. However, there isn't a convenient matching seam in
       the geometry - there are no great circles touching "poles" (source
       vertices) on a subdivided icosahedron - so we need to adjust texture
       coordinates and use the GL_REPEAT texture wrapping mode to cover it over.

            The technique is to establish whether we have at least one vertex in
       each of the (x, -z) and (-x, -z) quadrants, and if so, add 1 to the
       texture coordinates for the vertices in (-x, -z) -- corresponding to the
       east Pacific.

            NOTE: this technique is suboptimal because the selection of wrapped
       vertices changes at each subdivision level. Interpolating texture
       coordinates during subidivision, then finding the "nearest" option for
       "correct" calculated s for interpolated vertices could fix this.
    */
    bool haveNXNZ = false;
    bool havePXNZ = false;
    for (const Vertex& vertex : vertices_) {
      if (vertex.v.z < 0) {
        if (vertex.v.x < 0) {
          haveNXNZ = true;
        } else {
          havePXNZ = true;
        }
      }
    }

    if (haveNXNZ && havePXNZ) {
      for (Vertex& vertex : vertices_) {
        if (vertex.v.z < 0 && vertex.v.x >= 0) vertex.s += 1.0;
      }
      if (vertices_[0].v.y == -1.0) {
        // Special case: also need to wrap the polar coordinate of the
        // southernmost seam triangle.
        vertices_[0].s += 1.0;
      }
    }
  }

  void fixUpWinding() {
    // Construct vectors from v0 to v1 and v0 to v2.
    Vector ab = VectorSubtract(vertices_[1].v, vertices_[0].v);
    Vector ac = VectorSubtract(vertices_[2].v, vertices_[0].v);

    // Take their cross product.
    Vector cross = VectorCross(ab, ac);

    // For a correctly-wound triangle, this should point inwards. Since our
    // corner vectors point generally outwards, the dot product of any of these
    // with cross should be negative.
    if (VectorDot(cross, vertices_[0].v) > 0) {
      // If not, we swap v1 and v2.
      Vertex temp = vertices_[1];
      vertices_[1] = vertices_[2];
      vertices_[2] = temp;
    }
  }
};

// The vertices shared by every level. Two vertices are the same when their
// bytes are, as with the original's NSValue keys, so -0.0 and +0.0 stay
// distinct and indices follow first use.
class VertexSet {
 public:
  unsigned indexForVertex(const Vertex& vertex) {
    std::string key(reinterpret_cast<const char*>(&vertex), sizeof vertex);
    auto [it, inserted] =
        indices_.try_emplace(key, static_cast<unsigned>(vertices_.size()));
    if (inserted) vertices_.push_back(vertex);
    return it->second;
  }

  const std::vector<Vertex>& vertices() const { return vertices_; }

 private:
  std::map<std::string, unsigned> indices_;
  std::vector<Vertex> vertices_;
};

static_assert(sizeof(Vertex) == 5 * sizeof(double),
              "Vertex must have no padding bytes");

struct Mesh {
  std::vector<unsigned> indices;
  unsigned maxIndex = 0;

  unsigned faceCount() const {
    return static_cast<unsigned>(indices.size() / 3);
  }
};

Mesh MeshForTriangles(const std::vector<Triangle>& triangles,
                      VertexSet& vertices) {
  Mesh mesh;
  for (const Triangle& triangle : triangles) {
    for (unsigned i = 0; i < 3; i++) {
      unsigned index = vertices.indexForVertex(triangle.vertex(i));
      mesh.indices.push_back(index);
      if (mesh.maxIndex < index) mesh.maxIndex = index;
    }
  }
  return mesh;
}

const char* SizeEnumeratorForMaximum(unsigned maxValue) {
  if (maxValue <= UCHAR_MAX) return "GL_UNSIGNED_BYTE";
  if (maxValue <= USHRT_MAX) return "GL_UNSIGNED_SHORT";
  return "GL_UNSIGNED_INT";
}

const char* SizeTypeForMaximum(unsigned maxValue) {
  if (maxValue <= UCHAR_MAX) return "GLubyte";
  if (maxValue <= USHRT_MAX) return "GLushort";
  return "GLuint";
}

/*	Coordinates of icosahedron with the y axis through the centre of the top
   face. Based on
   http://www.csee.umbc.edu/~squire/reference/polyhedra.shtml#icosahedron
*/
constexpr Vector kBaseVertices[12] = {
    {+0.607061998207, +0.794654472292, +0.000000000000},
    {+0.982246946377, -0.187592474085, +0.000000000000},
    {+0.491123473188, +0.187592474085, +0.850650808352},
    {-0.303530999103, +0.794654472292, +0.525731112119},
    {-0.303530999103, +0.794654472292, -0.525731112119},
    {+0.491123473188, +0.187592474085, -0.850650808352},
    {+0.303530999103, -0.794654472292, +0.525731112119},
    {-0.491123473188, -0.187592474085, +0.850650808352},
    {-0.982246946377, +0.187592474085, +0.000000000000},
    {-0.491123473188, -0.187592474085, -0.850650808352},
    {+0.303530999103, -0.794654472292, -0.525731112119},
    {-0.607061998207, -0.794654472292, +0.000000000000}};

// Faces with consistent winding.
constexpr struct {
  unsigned a, b, c;
} kBaseTriangles[20] = {{1, 0, 2},  {2, 0, 3},  {3, 0, 4},  {4, 0, 5},
                        {5, 0, 1},  {1, 2, 6},  {2, 3, 7},  {3, 4, 8},
                        {4, 5, 9},  {5, 1, 10}, {6, 10, 1}, {7, 6, 2},
                        {8, 7, 3},  {9, 8, 4},  {10, 9, 5}, {6, 11, 10},
                        {7, 11, 6}, {8, 11, 7}, {9, 11, 8}, {10, 11, 9}};

void WritePrelude(FILE* header, FILE* source) {
  std::fprintf(
      header,
      "/*\n"
      "\t%s.h\n"
      "\tFor Oolite\n"
      "\t\n"
      "\tThis file was automatically generated by tools/icosmesh. Do not "
      "modify.\n"
      "\t\n"
      "\tThis data may be used freely.\n"
      "*/\n"
      "\n"
      "#pragma once\n"
      "\n"
      "#include \"OOOpenGLOnly.h\"\n"
      "\n"
      "\n"
      "#define kOOPlanetDataLevels %u\n"
      "\n"
      "\n"
      "typedef struct\n"
      "{\n"
      "\tunsigned        vertexCount;\n"
      "\tunsigned        faceCount;\n"
      "\tGLenum          type;\n"
      "\tconst void      *indices;   // faceCount * 3\n"
      "} OOPlanetDataLevel;\n"
      "\n"
      "\n"
      "extern const OOPlanetDataLevel kPlanetData[kOOPlanetDataLevels];\n",
      kFileName, kLevels);

  std::fprintf(source,
               "/*\n"
               "\t%s.cpp\n"
               "\tFor Oolite\n"
               "\t\n"
               "\tThis file was automatically generated by tools/icosmesh. Do "
               "not modify.\n"
               "\t\n"
               "\tThis data may be used freely.\n"
               "*/\n"
               "\n"
               "#include \"OOPlanetData.h\"\n",
               kFileName);
}

void WriteMesh(FILE* source, unsigned level, const Mesh& mesh) {
  unsigned count = mesh.faceCount();
  std::fprintf(
      source,
      "\n\n/*  Level %u index array\n    %u faces\n*/\nstatic const %s "
      "kFaceIndicesLevel%u[%u] =\n{\n",
      level, count, SizeTypeForMaximum(mesh.maxIndex), level, count * 3);
  for (unsigned i = 0; i < count; i++) {
    if (i != 0) std::fprintf(source, ",\n");
    std::fprintf(source, "\t%5u, %5u, %5u", mesh.indices[i * 3],
                 mesh.indices[i * 3 + 1], mesh.indices[i * 3 + 2]);
  }
  std::fprintf(source, "\n};\n");
}

void WriteVertices(FILE* header, FILE* source, const VertexSet& vertexSet) {
  const std::vector<Vertex>& vertices = vertexSet.vertices();
  auto count = static_cast<unsigned>(vertices.size());

  std::fprintf(header, "\n\n#define kOOPlanetDataVertexCount %u\n\n", count);
  std::fprintf(header,
               "extern const GLfloat "
               "kOOPlanetVertices[kOOPlanetDataVertexCount * 3];\n");
  std::fprintf(header,
               "extern const GLfloat "
               "kOOPlanetTexCoords[kOOPlanetDataVertexCount * 2];\n");

  std::fprintf(
      source,
      "\n\n/*  Shared vertex array\n    %u vertices\n*/\nconst GLfloat "
      "kOOPlanetVertices[kOOPlanetDataVertexCount * 3] =\n{\n",
      count);
  for (unsigned i = 0; i < count; i++) {
    if (i != 0) std::fprintf(source, ",\n");
    std::fprintf(source, "\t%+.8ff, %+.8ff, %+.8ff", vertices[i].v.x,
                 vertices[i].v.y, vertices[i].v.z);
  }

  std::fprintf(source,
               "\n};\n\n/*  Shared texture coordinate array\n    %u "
               "pairs\n*/\nconst GLfloat "
               "kOOPlanetTexCoords[kOOPlanetDataVertexCount * 2] =\n{\n",
               count);
  for (unsigned i = 0; i < count; i++) {
    if (i != 0) std::fprintf(source, ",\n");
    std::fprintf(source, "\t%+.8ff, %+.8ff", vertices[i].s, vertices[i].t);
  }

  std::fprintf(source, "\n};\n");
}

}  // namespace

int main(int argc, char* argv[]) {
  // Let printf ignore local number formatting conventions; for example, use a
  // dot as the decimal separator.
  if (std::setlocale(LC_NUMERIC, "C") == nullptr) {
    std::fprintf(stderr, "Failed to set locale.\n");
    return EXIT_FAILURE;
  }

  std::string directory =
      (argc > 1) ? std::string(argv[1]) + "/" : std::string();
  std::string headerPath = directory + kFileName + ".h";
  std::string sourcePath = directory + kFileName + ".cpp";
  FILE* header = std::fopen(headerPath.c_str(), "w");
  FILE* source = std::fopen(sourcePath.c_str(), "w");
  if (header == nullptr || source == nullptr) {
    std::fprintf(stderr, "Failed to open output files.\n");
    return EXIT_FAILURE;
  }

  WritePrelude(header, source);

  std::vector<Triangle> triangles;
  for (const auto& face : kBaseTriangles) {
    triangles.emplace_back(kBaseVertices[face.a], kBaseVertices[face.b],
                           kBaseVertices[face.c]);
  }

  unsigned faceCount[kLevels];
  unsigned maxIndex[kLevels];
  VertexSet vertices;
  for (unsigned level = 0; level < kLevels; level++) {
    if (level != 0) {
      std::vector<Triangle> subdivided;
      subdivided.reserve(triangles.size() * 4);
      for (const Triangle& triangle : triangles)
        triangle.subdivideInto(subdivided);
      triangles = std::move(subdivided);
    }
    Mesh mesh = MeshForTriangles(triangles, vertices);
    WriteMesh(source, level, mesh);
    faceCount[level] = mesh.faceCount();
    maxIndex[level] = mesh.maxIndex + 1;
  }

  WriteVertices(header, source, vertices);

  std::fprintf(
      source,
      "\n\nconst OOPlanetDataLevel kPlanetData[kOOPlanetDataLevels] =\n{\n");
  for (unsigned i = 0; i < kLevels; i++) {
    if (i != 0) std::fprintf(source, ",\n");
    std::fprintf(source, "\t{ %u, %u, %s, kFaceIndicesLevel%u }", maxIndex[i],
                 faceCount[i], SizeEnumeratorForMaximum(maxIndex[i]), i);
  }
  std::fprintf(source, "\n};\n");

  bool failed = std::ferror(header) || std::ferror(source);
  failed |= std::fclose(header) != 0;
  failed |= std::fclose(source) != 0;
  if (failed) {
    std::fprintf(stderr, "Failed to write output files.\n");
    return EXIT_FAILURE;
  }
  return EXIT_SUCCESS;
}
