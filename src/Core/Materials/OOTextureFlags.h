/*

OOTextureFlags.h

The texture option flags. OOTexture.h and OOTextureLoader.h both include it: the
loaders do not include OOTexture.h, so a test can stand in for OOTexture.

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

#pragma once

#include <cstdint>
#include <type_traits>

#include "OOEnumFlags.h"

// Texture options: single bits, and the multi-bit min-filter, mag-filter and
// channel-extraction fields (read them through their k...Mask).
enum class OOTextureFlags : std::uint32_t {
  kNone = 0,

  kMinFilterDefault = 0x000000U,
  kMinFilterNearest = 0x000001U,
  kMinFilterLinear = 0x000002U,
  kMinFilterMipMap = 0x000003U,

  kMagFilterNearest = 0x000000U,
  kMagFilterLinear = 0x000004U,

  kNoShrink = 0x000010U,
  kExtraShrink = 0x000020U,
  kRepeatS = 0x000040U,
  kRepeatT = 0x000080U,
  kAllowRectTexture =
      0x000100U,  // Indicates that GL_TEXTURE_RECTANGLE_EXT may be used
                  // instead of GL_TEXTURE_2D. See -texCoordsScale for a
                  // discussion of rectangle textures.
  kNoFNFMessage = 0x000200U,  // Don't log file not found error
  kNeverScale =
      0x000400U,  // Don't rescale texture, even if rect textures are not
                  // available. This *must not* be used for regular textures,
                  // but may be passed to OOTextureLoader when being used for
                  // other purposes.
  kAlphaMask =
      0x000800U,  // Single-channel texture should be GL_ALPHA, not
                  // GL_LUMINANCE. No effect for multi-channel textures.
  kAllowCubeMap = 0x001000U,

  kSRGBA = 0x002000U,

  kExtractChannelMask = 0x700000U,
  kExtractChannelNone = 0x000000U,
  kExtractChannelR = 0x100000U,  // 001
  kExtractChannelG = 0x300000U,  // 011
  kExtractChannelB = 0x500000U,  // 101
  kExtractChannelA = 0x700000U,  // 111

  kMinFilterMask = 0x000003U,
  kMagFilterMask = 0x000004U,
  kFlagsMask = ~(kMinFilterMask | kMagFilterMask),

  kDefaultOptions = kMinFilterDefault | kMagFilterLinear,

  kDefinedFlags = kMinFilterMask | kMagFilterMask | kNoShrink | kExtraShrink |
                  kAllowRectTexture | kAllowCubeMap | kRepeatS | kRepeatT |
                  kNoFNFMessage | kNeverScale | kAlphaMask | kSRGBA |
                  kExtractChannelMask,

  kFlagsAllowedForRectangleTexture = kDefinedFlags & ~(kRepeatS | kRepeatT),
  kFlagsAllowedForCubeMap = kDefinedFlags & ~(kRepeatS | kRepeatT)
};
constexpr std::true_type OOEnableFlagOperators(OOTextureFlags);
