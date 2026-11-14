#pragma once

#include <cstddef>
#include <cstdint>
#include <string_view>
#include <type_traits>

#include "OOEnumFlags.h"

// The debug console's flags. Their names and values are console.DEBUG_* in
// JavaScript.
enum class OODebugFlags : std::uint32_t {
  kNone = 0,
  kLinkedLists = 0x00000001,
  //	UNUSED						= 0x00000002,
  kCollisions = 0x00000004,
  kDocking = 0x00000008,
  kOctreeLogging = 0x00000010,
  //	UNUSED						= 0x00000020,
  kBoundingBoxes = 0x00000040,
  kOctreeDraw = 0x00000080,
  kDrawNormals = 0x00000100,
  kNoDust = 0x00000200,
  kNoShaderFallback = 0x00000400,
  kShaderValidation = 0x00000800,

  // Flag for temporary use, always last in list.
  kMisc = 0x10000000,

  kAll = 0xffffffff,
};
constexpr std::true_type OOEnableFlagOperators(OODebugFlags);

// The JavaScript name of each flag, written out: never derived from the
// identifier.
constexpr std::string_view OOEnumName(OODebugFlags f) noexcept {
  switch (f) {
    case OODebugFlags::kLinkedLists:
      return "DEBUG_LINKED_LISTS";
    case OODebugFlags::kCollisions:
      return "DEBUG_COLLISIONS";
    case OODebugFlags::kDocking:
      return "DEBUG_DOCKING";
    case OODebugFlags::kOctreeLogging:
      return "DEBUG_OCTREE_LOGGING";
    case OODebugFlags::kBoundingBoxes:
      return "DEBUG_BOUNDING_BOXES";
    case OODebugFlags::kOctreeDraw:
      return "DEBUG_OCTREE_DRAW";
    case OODebugFlags::kDrawNormals:
      return "DEBUG_DRAW_NORMALS";
    case OODebugFlags::kNoDust:
      return "DEBUG_NO_DUST";
    case OODebugFlags::kNoShaderFallback:
      return "DEBUG_NO_SHADER_FALLBACK";
    case OODebugFlags::kShaderValidation:
      return "DEBUG_SHADER_VALIDATION";
    case OODebugFlags::kMisc:
      return "DEBUG_MISC";
    case OODebugFlags::kNone:
    case OODebugFlags::kAll:
      return {};
  }
  return {};
}

// Every value scripts see, pinned.
static_assert(oo::ToUnderlying(OODebugFlags::kLinkedLists) == 0x00000001);
static_assert(oo::ToUnderlying(OODebugFlags::kCollisions) == 0x00000004);
static_assert(oo::ToUnderlying(OODebugFlags::kDocking) == 0x00000008);
static_assert(oo::ToUnderlying(OODebugFlags::kOctreeLogging) == 0x00000010);
static_assert(oo::ToUnderlying(OODebugFlags::kBoundingBoxes) == 0x00000040);
static_assert(oo::ToUnderlying(OODebugFlags::kOctreeDraw) == 0x00000080);
static_assert(oo::ToUnderlying(OODebugFlags::kDrawNormals) == 0x00000100);
static_assert(oo::ToUnderlying(OODebugFlags::kNoDust) == 0x00000200);
static_assert(oo::ToUnderlying(OODebugFlags::kNoShaderFallback) == 0x00000400);
static_assert(oo::ToUnderlying(OODebugFlags::kShaderValidation) == 0x00000800);
static_assert(oo::ToUnderlying(OODebugFlags::kMisc) == 0x10000000);
static_assert(oo::ToUnderlying(OODebugFlags::kAll) == 0xffffffff);

#ifdef OO_DEBUG_MONITOR_ENABLED

extern std::uint32_t gDebugFlags;
extern std::uint32_t gLiveEntityCount;
extern std::size_t gTotalEntityMemory;

#else

#define gDebugFlags (0)

#endif

// True if the debug console has turned flag on. Always false without the debug
// monitor.
inline bool OODebugFlagIsOn(OODebugFlags flag) noexcept {
  return (gDebugFlags & oo::ToUnderlying(flag)) != 0;
}
