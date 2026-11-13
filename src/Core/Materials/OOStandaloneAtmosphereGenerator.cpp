/*
        OOStandaloneAtmosphereGenerator.cpp

        Generator for atmosphere textures when the planet is using a
        non-generated diffuse map.

        Oolite
        Copyright (C) 2004-2013 Giles C Williams and contributors

        This program is free software; you can redistribute it and/or
        modify it under the terms of the GNU General Public License
        as published by the Free Software Foundation; either version 2
        of the License, or (at your option) any later version.

        This program is distributed in the hope that it will be useful,
        but WITHOUT ANY WARRANTY; without even the implied warranty of
        MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
        GNU General Public License for more details.

        You should have received a copy of the GNU General Public License
        along with this program; if not, write to the Free Software
        Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
        MA 02110-1301, USA.
*/

#include "OOFoundation.h"
#include "OOStellarBody.h"

#define DEBUG_DUMP (0 && OOLITE_DEBUG)
#define DEBUG_DUMP_RAW (1 && DEBUG_DUMP)

#define ALBEDO_FACTOR \
  0.7f  // Overall darkening of everything, allowing better contrast for snow
        // and specular highlights.

#include <array>
#include <bit>
#include <cstddef>
#include <cstdint>
#include <format>
#include <optional>
#include <string>
#include <string_view>

#include "OOColor.h"
#include "OODescription.h"
#include "OOStandaloneAtmosphereGenerator.h"
#include "oofnd/PList.hpp"
#include "oofnd/String.hpp"
#include "oofnd/objc/OOAssert.h"

#ifndef TEXGEN_TEST_RIG
#include "OOTexture.h"
#include "Universe.h"
#endif

#if DEBUG_DUMP
#include "MyOpenGLView.h"
#endif

#define PLANET_TEXTURE_OPTIONS                                           \
  (OOTextureFlags::kMinFilterLinear | OOTextureFlags::kMagFilterLinear | \
   OOTextureFlags::kRepeatS | OOTextureFlags::kNoShrink)

constexpr int kRandomBufferSize = 128;

namespace {

FloatRGB FloatRGBFromDictColor(
    const oo::PList& dictionary,
    const std::string&
        key);  // dictionary: the planet info (colours are Object nodes)

}  // namespace

static bool FillFBMBuffer(OOStandaloneAtmosphereGeneratorInfo* info);
static float QFactor(float* accbuffer, int x, int y, unsigned width,
                     float polar_y_value, float bias, float polar_y);
static float BlendAlpha(float fraction, float a, float b);
static FloatRGBA CloudMix(OOStandaloneAtmosphereGeneratorInfo* info, float q,
                          float nearPole);

constexpr int kPlanetScale256x256 = 1;
constexpr int kPlanetScale512x512 = kPlanetScale256x256 + 1;
constexpr int kPlanetScale1024x1024 = kPlanetScale512x512 + 1;
#ifdef TEXGEN_TEST_RIG  // the test rig's scale only
constexpr int kPlanetScale2048x2048 = kPlanetScale1024x1024 + 1;
constexpr int kPlanetScale4096x4096 = kPlanetScale2048x2048 + 1;
#endif

constexpr int kPlanetScaleReducedDetail = kPlanetScale512x512;
constexpr int kPlanetScaleFullDetail = kPlanetScale1024x1024;

std::shared_ptr<OOStandaloneAtmosphereGenerator>
OOStandaloneAtmosphereGenerator::generatorWithPlanetInfo(
    const oo::PList& planetInfo, RANROTSeed seed) {
  std::shared_ptr<OOStandaloneAtmosphereGenerator> result =
      oo::makeShared<OOStandaloneAtmosphereGenerator>();
  if (!result->initWithPlanetInfo(planetInfo, seed)) return {};
  return result;
}

bool OOStandaloneAtmosphereGenerator::initWithPlanetInfo(
    const oo::PList& planetInfo, RANROTSeed seed) {
  OO_LOG("texture.planet.generate", "{}",
         "Initialising standalone atmosphere generator");

  // AllowCubeMap not used yet but might be in future
  if (initWithPath(std::format("OOStandaloneAtmosphereTexture@{}",
                               oo::str::pointerDescription(this)),
                   OOTextureFlags::kAllowCubeMap)) {
    OO_LOG("texture.planet.generate", "Extracting parameters for generator {}",
           description());
    _info.seed = seed;  // was a value box under "noise_map_seed" in planetInfo
    OO_LOG("texture.planet.generate", "{}", "Extracting atmosphere parameters");
    // we are an atmosphere:
    _info.cloudAlpha = planetInfo.get<float>("cloud_alpha", 1.0f);
    _info.cloudFraction =
        OOClamp_0_1_f(planetInfo.get<float>("cloud_fraction", 0.3));
    _info.cloudColor = FloatRGBFromDictColor(planetInfo, "cloud_color");
    _info.paleCloudColor =
        FloatRGBFromDictColor(planetInfo, "polar_cloud_color");

    OOGraphicsDetail detailLevel =
        (UNIVERSE != nullptr ? UNIVERSE->getDetailLevel() : OOGraphicsDetail{});

#ifndef TEXGEN_TEST_RIG
    if (detailLevel < OOGraphicsDetail::kShaders) {
      _planetScale = kPlanetScaleReducedDetail;
    } else {
      _planetScale = kPlanetScaleFullDetail;
    }
#else
    _planetScale = kPlanetScale4096x4096;
#endif
    _info.perlin3d = planetInfo.get<bool>(
        "perlin_3d", detailLevel > OOGraphicsDetail::kShaders);
    _info.planetAspectRatio = _info.perlin3d ? 2 : 1;
    _info.planetScaleOffset = 8 - _info.planetAspectRatio;
    return true;
  }

  return false;
}

std::shared_ptr<OOTexture>
OOStandaloneAtmosphereGenerator::planetTextureWithInfo(
    const oo::PList& planetInfo, RANROTSeed seed) {
  std::shared_ptr<OOTexture> result;
  const std::shared_ptr<OOStandaloneAtmosphereGenerator> generator =
      generatorWithPlanetInfo(planetInfo, seed);
  if (generator) {
    result = OOTexture::textureWithGenerator(generator.get());
  }

  return result;
}

bool OOStandaloneAtmosphereGenerator::generateAtmosphereTexture(
    std::shared_ptr<OOTexture>* texture, const oo::PList& planetInfo,
    RANROTSeed seed) {
  OOCParameterAssert(texture != nullptr);

  const std::shared_ptr<OOStandaloneAtmosphereGenerator> atmoGen =
      generatorWithPlanetInfo(planetInfo, seed);
  if (!atmoGen) return false;

  *texture = OOTexture::textureWithGenerator(atmoGen.get());

  return texture->get() != nullptr;
}

std::optional<std::string>
OOStandaloneAtmosphereGenerator::descriptionComponents() const {
  return std::format("seed: {},{}", _info.seed.high, _info.seed.low);
}

OOTextureFlags OOStandaloneAtmosphereGenerator::textureOptions() {
  return PLANET_TEXTURE_OPTIONS;
}

std::optional<std::string> OOStandaloneAtmosphereGenerator::cacheKey() {
  return std::format(
      "OOStandaloneAtmosphereGenerator-@{}\n{},{}/{},{}/{:f}/{:f}/"
      "{:f},{:f},{:f}/{:f},{:f},{:f}/{:f},{:f},{:f}",
      _planetScale, _info.width, _info.height, _info.seed.high, _info.seed.low,
      _info.cloudAlpha, _info.cloudFraction, _info.airColor.r, _info.airColor.g,
      _info.airColor.b, _info.cloudColor.r, _info.cloudColor.g,
      _info.cloudColor.b, _info.paleCloudColor.r, _info.paleCloudColor.g,
      _info.paleCloudColor.b);
}

bool OOStandaloneAtmosphereGenerator::getResultFormatWidthHeight(
    OOPixMap* outData, OOTextureDataFormat* outFormat, uint32_t* outWidth,
    uint32_t* outHeight) {
  bool waiting = false;
  if (!isReady()) {
    waiting = true;
    OO_LOG("texture.planet.generate.wait", "{} generator {}", "Waiting for",
           description());
  }

  bool result =
      OOTextureGenerator::getResult(outData, outFormat, outWidth, outHeight);

  if (waiting) {
    OO_LOG("texture.planet.generate.dequeue", "{} generator {}",
           result ? "Dequeued" : "Failed to dequeue", description());
  } else {
    OO_LOG("texture.planet.generate.dequeue",
           "{} generator {} without waiting.",
           result ? "Dequeued" : "Failed to dequeue", description());
  }

  return result;
}

/* TODO: fix duplication between here and OOPlanetTextureGenerator of
 * various noise, interpolation, etc. functions */
void OOStandaloneAtmosphereGenerator::loadTexture() {
  OO_LOG("texture.planet.generate.begin", "Started generator {}",
         description());

  bool success = false;

  OOPixelBuffer aBuffer;
  uint8_t* apx = nullptr;

  _height = _info.height = 1 << (_planetScale + _info.planetScaleOffset);
  _width = _info.width = _height * _info.planetAspectRatio;

#define FAIL_IF(cond)               \
  do {                              \
    if (EXPECT_NOT(cond)) goto END; \
  } while (0)

  aBuffer = OOMakePixelBuffer(4 * static_cast<size_t>(_width) * _height);
  apx = aBuffer->data();

  FAIL_IF(!FillFBMBuffer(&_info));
#if DEBUG_DUMP_RAW
  dumpNoiseBuffer(_info.fbmBuffer.data());
#endif
  {
    float paleClouds =
        (_info.cloudFraction * _info.fbmBuffer[0] < 1.0f - _info.cloudFraction)
            ? 0.0f
            : 1.0f;

    int x, y;
    FloatRGBA color;
    float q, nearPole;
    float rHeight = 1.0f / _height;
    float fy, fHeight = _height;

    float cloudFraction = _info.cloudFraction;

    for (y = static_cast<int>(_height) - 1, fy = static_cast<float>(y); y >= 0;
         y--, fy--) {
      nearPole = (2.0f * fy - fHeight) * rHeight;
      nearPole *= nearPole;

      for (x = static_cast<int>(_width) - 1; x >= 0; x--) {
        q = QFactor(_info.fbmBuffer.data(), x, y, _width, paleClouds,
                    cloudFraction, nearPole);
        color = CloudMix(&_info, q, nearPole);
        *apx++ = 255.0f * color.r;
        *apx++ = 255.0f * color.g;
        *apx++ = 255.0f * color.b;
        *apx++ = 255.0f * color.a * _info.cloudAlpha;
      }
    }

    success = true;
    _format = kOOTextureDataRGBA;
  }

END:
  _info.fbmBuffer = std::vector<float>();
  if (success) _data = aBuffer;  // (otherwise the buffer goes with aBuffer)

  OO_LOG("texture.planet.generate.complete",
         "Completed generator {} {}successfully", description(),
         success ? "" : "un");

#if DEBUG_DUMP
  if (success) {
    const std::string diffuseName = std::format(
        "atmosphere-{}-{}-diffuse-new", _info.seed.high, _info.seed.low);
    const std::string lightsName = std::format("atmosphere-{}-{}-alpha-new",
                                               _info.seed.high, _info.seed.low);

    if (MyOpenGLView* gameView =
            (UNIVERSE != nullptr ? UNIVERSE->getGameView() : nullptr))
      gameView->dumpRGBAToRGBFileNamed(diffuseName, lightsName, aBuffer->data(),
                                       _width, _height, _width * 4);
  }
#endif
}

#if DEBUG_DUMP_RAW

void OOStandaloneAtmosphereGenerator::dumpNoiseBuffer(float* noise) {
  const std::string noiseName = std::format("atmosphere-{}-{}-noise-new",
                                            _info.seed.high, _info.seed.low);

  std::vector<uint8_t> noisePx(static_cast<size_t>(_width) * _height);
  unsigned x, y;
  for (y = 0; y < _height; y++) {
    for (x = 0; x < _width; x++) {
      noisePx[y * _width + x] = 255.0f * noise[y * _width + x];
    }
  }

  if (MyOpenGLView* gameView =
          (UNIVERSE != nullptr ? UNIVERSE->getGameView() : nullptr))
    gameView->dumpGrayToFileNamed(noiseName, noisePx.data(), _width, _height,
                                  _width);
}

#endif

OOINLINE float Lerp(float v0, float v1, float fraction) {
  // Linear interpolation - equivalent to v0 * (1.0f - fraction) + v1 *
  // fraction.
  return v0 + fraction * (v1 - v0);
}

static FloatRGB Blend(float fraction, FloatRGB a, FloatRGB b) {
  return (FloatRGB){Lerp(b.r, a.r, fraction), Lerp(b.g, a.g, fraction),
                    Lerp(b.b, a.b, fraction)};
}

static float BlendAlpha(float fraction, float a, float b) {
  return Lerp(b, a, fraction);
}

static FloatRGBA CloudMix(OOStandaloneAtmosphereGeneratorInfo* info, float q,
                          float nearPole) {
// #define AIR_ALPHA				(0.15f)
// #define CLOUD_ALPHA				(1.0f)
//  CIM: make distinction between cloud and not-cloud bigger
#define AIR_ALPHA (0.05f)
#define CLOUD_ALPHA (2.0f)

#define POLAR_BOUNDARY (0.33f)
#define CLOUD_BOUNDARY (0.5f)
#define RECIP_CLOUD_BOUNDARY (1.0f / CLOUD_BOUNDARY)

  FloatRGB cloudColor = info->cloudColor;
  float alpha = info->cloudAlpha, portion = 0.0f;

  q -= CLOUD_BOUNDARY * 0.5f;

  if (nearPole > POLAR_BOUNDARY) {
    portion = nearPole > POLAR_BOUNDARY + 0.2f
                  ? 1.0f
                  : (nearPole - POLAR_BOUNDARY) * 5.0f;
    cloudColor = Blend(portion, info->paleCloudColor, cloudColor);

    portion = nearPole > POLAR_BOUNDARY + 0.625f
                  ? 1.0f
                  : (nearPole - POLAR_BOUNDARY) * 1.6f;
  }

  if (q <= 0.0f) {
    if (q >= -CLOUD_BOUNDARY) {
      alpha *= BlendAlpha(-q * 0.5f * RECIP_CLOUD_BOUNDARY + 0.5f, CLOUD_ALPHA,
                          AIR_ALPHA);
    } else {
      alpha *= CLOUD_ALPHA;
    }
  } else {
    if (q < CLOUD_BOUNDARY) {
      alpha *= BlendAlpha(q * 0.5f * RECIP_CLOUD_BOUNDARY + 0.5f, AIR_ALPHA,
                          CLOUD_ALPHA);
    } else {
      alpha *= AIR_ALPHA;
    }
  }
  // magic numbers! at the poles we have fairly thin air.
  alpha *= BlendAlpha(portion, 0.6f, 1.0f);
  if (alpha > 1.0) {
    alpha = 1.0;
  }

  return (FloatRGBA){cloudColor.r, cloudColor.g, cloudColor.b, alpha};
}

namespace {

FloatRGB FloatRGBFromDictColor(const oo::PList& dictionary,
                               const std::string& key) {
  const oo::PList* value = dictionary.find(key);
  OOColor* color = (value != nullptr) ? OOColorInObjectNode(*value)
                                      : nullptr;  // an Object node
  OOCAssert(color != nullptr, "Expected OOColor, got %s",
            (value != nullptr) ? oo::DescriptionOf(*value).c_str() : "(null)");

  if (color == nullptr)
    return (FloatRGB){0.0f, 0.0f,
                      0.0f};  // a nil colour answered zeros (release builds)
  return (FloatRGB){color->redComponent() * ALBEDO_FACTOR,
                    color->greenComponent() * ALBEDO_FACTOR,
                    color->blueComponent() * ALBEDO_FACTOR};
}

}  // namespace

OOINLINE float Hermite(float q) { return 3.0f * q * q - 2.0f * q * q * q; }

#if __BIG_ENDIAN__
#define iman_ 1
#else
#define iman_ 0
#endif

// (same behaviour as, but faster than, FLOAT->INT)
// Works OK for -32728 to 32727.99999236688
OOINLINE int32_t fast_floor(double val) {
  val += 68719476736.0 * 1.5;
  // the double's two 32-bit halves
  const auto words = std::bit_cast<std::array<int32_t, 2>>(val);
  return (words[iman_] >> 16);
}

static bool GenerateFBMNoise(OOStandaloneAtmosphereGeneratorInfo* info);
static bool GenerateFBMNoise3D(OOStandaloneAtmosphereGeneratorInfo* info);

static bool FillFBMBuffer(OOStandaloneAtmosphereGeneratorInfo* info) {
  OOCParameterAssert(info != nullptr);

  // Allocate result buffer.
  info->fbmBuffer.assign(static_cast<size_t>(info->width) * info->height, 0.0f);
  if (!info->perlin3d) {
    GenerateFBMNoise(info);
  } else {
    GenerateFBMNoise3D(info);
  }

  return true;
}

//	Size of permutation buffer used to map integer coordinates to gradients.
// Must be power of two.
constexpr int kPermutationCount = 1 << 10;
constexpr int kPermutationMask = kPermutationCount - 1;

// Number of different gradient vectors used. The most important thing is that
// the gradients are evenly distributed and sum to 0.
constexpr int kGradientCount = 12;

#define LUT_DOT 1

#if !LUT_DOT
static const Vector kGradients[kGradientCount] = {
    {1, 1, 0},  {-1, 1, 0},  {1, -1, 0}, {-1, -1, 0}, {1, 0, 1},  {-1, 0, 1},
    {1, 0, -1}, {-1, 0, -1}, {0, 1, 1},  {0, -1, 1},  {0, 1, -1}, {0, -1, -1}};
#else
static const uint8_t kGradients[kGradientCount][3] = {
    {2, 2, 1}, {0, 2, 1}, {2, 0, 1}, {0, 0, 1}, {2, 1, 2}, {0, 1, 2},
    {2, 1, 0}, {0, 1, 0}, {1, 2, 2}, {1, 0, 2}, {1, 2, 0}, {1, 0, 0}};

/*	Attempted speedup that didn't pan out, but might inspire something
   better. Since our gradient vectors' components are all -1, 0 or 1, we should
   be able to calculate the dot product without any multiplication at all, by
        simply summing the right combination of (x, y, z), (0, 0, 0) and (-x,
   -y, -z).

        This turns out to be slightly slower than using multiplication, even if
        the negations are precalculated.
*/
OOINLINE float TDot3(const uint8_t grad[3], float x, float y, float z) {
  float xt[3] = {-x, 0.0f, x};
  float yt[3] = {-y, 0.0f, y};
  float zt[3] = {-z, 0.0f, z};

  return xt[grad[0]] + yt[grad[1]] + zt[grad[2]];
}
#endif

// Sample 3D noise function defined by kGradients and permutation table at point
// p.
static float SampleNoise3D(OOStandaloneAtmosphereGeneratorInfo* info,
                           Vector p) {
  uint16_t* permutations = info->permutations.data();

  // Split coordinates into integer and fractional parts.
  float fx = floor(p.x);
  float fy = floor(p.y);
  float fz = floor(p.z);
  int X = fx;
  int Y = fy;
  int Z = fz;
  float x = p.x - fx;
  float y = p.y - fy;
  float z = p.z - fz;

  // Select gradient for each corner.
#define PERM(v) permutations[(v) & kPermutationMask]

  unsigned PZ0 = PERM(Z);
  unsigned PZ1 = PERM(Z + 1);

  unsigned PY0Z0 = PERM(Y + PZ0);
  unsigned PY1Z0 = PERM(Y + 1 + PZ0);
  unsigned PY0Z1 = PERM(Y + PZ1);
  unsigned PY1Z1 = PERM(Y + 1 + PZ1);

  unsigned gi000 = PERM(X + PY0Z0);
  unsigned gi010 = PERM(X + PY1Z0);
  unsigned gi100 = PERM(X + 1 + PY0Z0);
  unsigned gi110 = PERM(X + 1 + PY1Z0);
  unsigned gi001 = PERM(X + PY0Z1);
  unsigned gi011 = PERM(X + PY1Z1);
  unsigned gi101 = PERM(X + 1 + PY0Z1);
  unsigned gi111 = PERM(X + 1 + PY1Z1);

#undef PERM

  //	Calculate noise contributions from each of the eight corners.
#if !LUT_DOT
#define DOT3(idx, x_, y_, z_) \
  dot_product(kGradients[(idx) % kGradientCount], (Vector){(x_), (y_), (z_)})
#else
#define DOT3(idx, x_, y_, z_) \
  TDot3(kGradients[(idx) % kGradientCount], (x_), (y_), (z_))
#endif

  float x1 = x - 1.0f;
  float y1 = y - 1.0f;
  float z1 = z - 1.0f;
  float n000 = DOT3(gi000, x, y, z);
  float n010 = DOT3(gi010, x, y1, z);
  float n100 = DOT3(gi100, x1, y, z);
  float n110 = DOT3(gi110, x1, y1, z);
  float n001 = DOT3(gi001, x, y, z1);
  float n011 = DOT3(gi011, x, y1, z1);
  float n101 = DOT3(gi101, x1, y, z1);
  float n111 = DOT3(gi111, x1, y1, z1);

#undef DOT3

  // Compute the fade curve value for each of x, y, z
  float u = Hermite(x);
  float v = Hermite(y);
  float w = Hermite(z);

  // Interpolate along the contributions from each of the corners.
  float nx00 = Lerp(n000, n100, u);
  float nx01 = Lerp(n001, n101, u);
  float nx10 = Lerp(n010, n110, u);
  float nx11 = Lerp(n011, n111, u);

  float nxy0 = Lerp(nx00, nx10, v);
  float nxy1 = Lerp(nx01, nx11, v);

  float nxyz = Lerp(nxy0, nxy1, w);

  return nxyz;
}

/*	Generate shuffled permutation order - each value from 0 to
        kPermutationCount - 1 occurs exactly once. This shuffling provides all
   the randomness in the resulting noise. Don't worry, though - for
        kPermutationCount = 1024 this allows for 4e2567 different noise maps,
        which is a lot more than RanRot will actually give us.
*/
static bool MakePermutationTable(OOStandaloneAtmosphereGeneratorInfo* info) {
  info->permutations.resize(kPermutationCount);
  uint16_t* perms = info->permutations.data();

  /*	Fisher-Yates/Durstenfeld/Knuth shuffle, "inside-out" variant.
          Based on pseudocode from
     http://en.wikipedia.org/wiki/Fisher-Yates_shuffle

          When comparing to the pseudocode, note that it generates a one-based
          series, but this version generates a zero-based series.
  */
  perms[0] = 0;
  uint16_t* curr = perms;
  uint16_t n;
  for (n = 1; n < kPermutationCount; n++) {
    uint16_t j = RanrotWithSeed(&info->seed) & kPermutationMask;
    *++curr = perms[j];
    perms[j] = n - 1;
  }

  return true;
}

static bool GenerateFBMNoise3D(OOStandaloneAtmosphereGeneratorInfo* info) {
  bool OK = false;

  FAIL_IF(!MakePermutationTable(info));

  {
    unsigned x, y, width = info->width, height = info->height;
    float lon, lat;  // Longitude and latitude in radians.
    float dlon = 2.0f * M_PI / width;
    float dlat = M_PI / height;
    float* px = info->fbmBuffer.data();

    for (y = 0, lat = -M_PI_2; y < height; y++, lat += dlat) {
      float las = sin(lat);
      float lac = cos(lat);

      for (x = 0, lon = -M_PI; x < width; x++, lon += dlon) {
        // FIXME: in real life, we really don't want sin and cos per pixel.
        // Convert spherical coordinates to vector.
        float los = sin(lon);
        float loc = cos(lon);

        Vector p = {los * lac, las, loc * lac};

#if 1
        // fBM
        unsigned octaveMask = 4;
        float octave = octaveMask;
        octaveMask -= 1;
        float scale = 0.4f;
        float sum = 0;

        while ((octaveMask + 1) < height) {
          Vector ps = vector_multiply_scalar(p, octave);
          sum += scale * SampleNoise3D(info, ps);

          octave *= 2.0f;
          octaveMask = (octaveMask << 1) | 1;
          scale *= 0.5f;
        }
#else
        // Single octave
        p = vector_multiply_scalar(p, 4.0f);
        float sum = 0.5f * SampleNoise3D(info, p);
#endif

        *px++ = sum + 0.5f;
      }
    }
  }

END:
  info->permutations = std::vector<uint16_t>();
  return OK;
}

// Old 2D value noise.

static void FillRandomBuffer(float* randomBuffer, RANROTSeed seed) {
  unsigned i, len = kRandomBufferSize * kRandomBufferSize;
  for (i = 0; i < len; i++) {
    randomBuffer[i] = randfWithSeed(&seed);
  }
}

static void AddNoise(OOStandaloneAtmosphereGeneratorInfo* info,
                     float* randomBuffer, float octave, unsigned octaveMask,
                     float scale, float* qxBuffer, int* ixBuffer) {
  unsigned x, y;
  unsigned width = info->width, height = info->height;
  int ix, jx, iy, jy;
  float rr = octave / width;
  float fx, fy, qx, qy, rix, rjx, rfinal;
  float* dst = info->fbmBuffer.data();

  for (fy = 0, y = 0; y < height; fy++, y++) {
    qy = fy * rr;
    iy = fast_floor(qy);
    jy = (iy + 1) & octaveMask;
    qy = Hermite(qy - iy);
    iy &= (kRandomBufferSize - 1);
    jy &= (kRandomBufferSize - 1);

    for (fx = 0, x = 0; x < width; fx++, x++) {
      if (y == 0) {
        // first pass: initialise buffers.
        qx = fx * rr;
        ix = fast_floor(qx);
        qx -= ix;
        ix &= (kRandomBufferSize - 1);
        ixBuffer[x] = ix;
        qxBuffer[x] = Hermite(qx);
      } else {
        // later passes: grab the stored values.
        ix = ixBuffer[x];
        qx = qxBuffer[x];
      }

      jx = (ix + 1) & octaveMask;
      jx &= (kRandomBufferSize - 1);

      rix = Lerp(randomBuffer[iy * kRandomBufferSize + ix],
                 randomBuffer[iy * kRandomBufferSize + jx], qx);
      rjx = Lerp(randomBuffer[jy * kRandomBufferSize + ix],
                 randomBuffer[jy * kRandomBufferSize + jx], qx);
      rfinal = Lerp(rix, rjx, qy);

      *dst++ += scale * rfinal;
    }
  }
}

static bool GenerateFBMNoise(OOStandaloneAtmosphereGeneratorInfo* info) {
  // Allocate the temporary buffers we need in one fell swoop, to avoid
  // administrative overhead.
  size_t randomBufferSize =
      kRandomBufferSize * kRandomBufferSize * sizeof(float);
  size_t qxBufferSize = info->width * sizeof(float);
  size_t ixBufferSize = info->width * sizeof(int);
  std::vector<float> randomStorage(randomBufferSize / sizeof(float));
  std::vector<float> qxStorage(qxBufferSize / sizeof(float));
  std::vector<int> ixStorage(ixBufferSize / sizeof(int));

  float* randomBuffer = randomStorage.data();
  float* qxBuffer = qxStorage.data();
  int* ixBuffer = ixStorage.data();

  // Get us some value noise.
  FillRandomBuffer(randomBuffer, info->seed);

  // Generate basic fBM noise.
  unsigned height = info->height;
  unsigned octaveMask = 8 * info->planetAspectRatio;
  float octave = octaveMask;
  octaveMask -= 1;
  float scale = 0.5f;

  while ((octaveMask + 1) < height) {
    AddNoise(info, randomBuffer, octave, octaveMask, scale, qxBuffer, ixBuffer);
    octave *= 2.0f;
    octaveMask = (octaveMask << 1) | 1;
    scale *= 0.5f;
  }

  return true;
}

static float QFactor(float* accbuffer, int x, int y, unsigned width,
                     float polar_y_value, float bias, float polar_y) {
  float q = accbuffer[y * width + x];  // 0.0 -> 1.0
  q += bias;

  // Polar Y smooth.
  q = q * (1.0f - polar_y) + polar_y * polar_y_value;

  return q;
}
