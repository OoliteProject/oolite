/*

OOCacheManager.h
By Jens Ayton

Singleton class responsible for handling Oolite's data cache.
The cache manager stores arbitrary property lists in separate namespaces
(referred to simply as caches). The cache is emptied if it was created with a
different verison of Oolite, or if it was created on a system with a different
byte sex.

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

#import "OOCocoa.h"


@interface OOCacheManager: NSObject
{
@private
	NSMutableDictionary		*_caches;
	id						_scheduledWrite;
	BOOL					_permitWrites;
	BOOL					_dirty;
}

+ (OOCacheManager *) sharedCache;

- (id)objectForKey:(NSString *)inKey inCache:(NSString *)inCacheKey;
- (void)setObject:(id)inElement forKey:(NSString *)inKey inCache:(NSString *)inCacheKey;
- (void)removeObjectForKey:(NSString *)inKey inCache:(NSString *)inCacheKey;
- (void)clearCache:(NSString *)inCacheKey;
- (void)clearAllCaches;
- (void) reloadAllCaches;

- (void)setAllowCacheWrites:(BOOL)flag;

- (void)flush;
- (void)finishOngoingFlush;	// Wait for flush to complete. Does nothing if async flushing is disabled.

@end
