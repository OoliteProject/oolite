/*

OOManifestProperties.h

The property keys used in manifest.plist entries

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

#include <string_view>

inline constexpr std::string_view kOOManifestIdentifier = "identifier";
inline constexpr std::string_view kOOManifestVersion = "version";
inline constexpr std::string_view kOOManifestRequiredOoliteVersion = "required_oolite_version";
inline constexpr std::string_view kOOManifestMaximumOoliteVersion = "maximum_oolite_version";
inline constexpr std::string_view kOOManifestTitle = "title";
inline constexpr std::string_view kOOManifestRequiresOXPs = "requires_oxps";
inline constexpr std::string_view kOOManifestConflictOXPs = "conflict_oxps";
inline constexpr std::string_view kOOManifestDescription = "description";
inline constexpr std::string_view kOOManifestCategory = "category";
inline constexpr std::string_view kOOManifestDownloadURL = "download_url";
inline constexpr std::string_view kOOManifestFileSize = "file_size";
inline constexpr std::string_view kOOManifestInformationURL = "information_url";
inline constexpr std::string_view kOOManifestAuthor = "author";
inline constexpr std::string_view kOOManifestLicense = "license";
inline constexpr std::string_view kOOManifestTags = "tags";
/* these properties are not contained in the manifest.plist (and would be
   overwritten if they were...) but are calculated by Oolite */
inline constexpr std::string_view kOOManifestFilePath = "file_path";
inline constexpr std::string_view kOOManifestRequiredBy = "required_by";
inline constexpr std::string_view kOOManifestAvailableVersion = "available_version";
/* these properties are not contained in the manifest.plist but are
 * provided by in the manifest*s* list by the API */
inline constexpr std::string_view kOOManifestUploadDate = "upload_date";
// following manifest.plist properties not (yet?) used by Oolite
// but may be used by other manifest reading applications
#if 0
inline constexpr std::string_view kOOManifestOptionalOXPs			= "optional_oxps";
#endif

// properties for within requires/optional/conflicts entries
inline constexpr std::string_view kOOManifestRelationIdentifier = "identifier";
inline constexpr std::string_view kOOManifestRelationVersion = "version";
inline constexpr std::string_view kOOManifestRelationMaxVersion = "maximum_version";
inline constexpr std::string_view kOOManifestRelationDescription = "description";

// 'magic' value for a tag to exclude an OXP from loading except when
// required by a scenario
inline constexpr std::string_view kOOManifestTagScenarioOnly = "oolite-scenario-only";
