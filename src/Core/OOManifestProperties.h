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


static NSString * const kOOManifestIdentifier			= @"identifier";
static NSString * const kOOManifestVersion				= @"version";
static NSString * const kOOManifestRequiredOoliteVersion= @"required_oolite_version";
static NSString * const kOOManifestMaximumOoliteVersion = @"maximum_oolite_version";
static NSString * const kOOManifestTitle				= @"title";
static NSString * const kOOManifestRequiresOXPs			= @"requires_oxps";
static NSString * const kOOManifestConflictOXPs			= @"conflict_oxps";
static NSString * const kOOManifestDescription			= @"description";
static NSString * const kOOManifestCategory				= @"category";
static NSString * const kOOManifestDownloadURL			= @"download_url";
static NSString * const kOOManifestFileSize				= @"file_size";
static NSString * const kOOManifestInformationURL		= @"information_url";
static NSString * const kOOManifestAuthor				= @"author";
static NSString * const kOOManifestLicense				= @"license";
static NSString * const kOOManifestTags					= @"tags";
/* these properties are not contained in the manifest.plist (and would be
   overwritten if they were...) but are calculated by Oolite */
static NSString * const kOOManifestFilePath				= @"file_path";
static NSString * const kOOManifestRequiredBy			= @"required_by";
static NSString * const kOOManifestAvailableVersion		= @"available_version";
/* these properties are not contained in the manifest.plist but are
 * provided by in the manifest*s* list by the API */
static NSString * const kOOManifestUploadDate			= @"upload_date";
// following manifest.plist properties not (yet?) used by Oolite
// but may be used by other manifest reading applications
#if 0
static NSString * const kOOManifestOptionalOXPs			= @"optional_oxps";
#endif

// properties for within requires/optional/conflicts entries
static NSString * const kOOManifestRelationIdentifier	= @"identifier";
static NSString * const kOOManifestRelationVersion		= @"version";
static NSString * const kOOManifestRelationMaxVersion	= @"maximum_version";
static NSString * const kOOManifestRelationDescription	= @"description";

// 'magic' value for a tag to exclude an OXP from loading except when
// required by a scenario
static NSString * const kOOManifestTagScenarioOnly		= @"oolite-scenario-only";
