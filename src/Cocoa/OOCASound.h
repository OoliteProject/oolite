/*

OOCASound.h

Abstract base class for sounds, and primary sound loading interface.

OOCASound - Core Audio sound implementation for Oolite.
Copyright (C) 2005-2006 Jens Ayton

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

#import <Cocoa/Cocoa.h>


@interface OOSound: NSObject
{
	uint32_t			_playingCount;
}

+ (void) setUp;
+ (void) tearDown;
+ (void) update;

+ (void) setMasterVolume:(float) fraction;
+ (float) masterVolume;

- (id) initWithContentsOfFile:(NSString *)path;

- (BOOL) play;
- (BOOL) stop;	// Deprecated; does nothing. If needed, use OOCASoundSource.

- (BOOL) isPlaying;
- (uint32_t)playingCount;

- (NSString *)name;

@end
