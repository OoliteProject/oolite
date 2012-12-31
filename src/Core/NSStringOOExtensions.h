/*

NSStringOOExtensions.h

Convenience extensions to NSString.

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


@interface NSString (OOExtensions)

/*	+stringWithContentsOfUnicodeFile:
	
	Like +stringWithContentsOfFile:, but biased towards Unicode encodings and
	cross-system consistency. Specifically:
	* If the file starts with a UTF-16 BOM, assume UTF-16.
	* Otherwise, if the file can be interpreted as UTF-8, assume UTF-8.
	* Otherwise, assume ISO-Latin-1.
*/
+ (instancetype) stringWithContentsOfUnicodeFile:(NSString *)path;


/*	+stringWithUTF16String:
	
	Takes a NUL-terminated native-endian UTF-16 string.
*/
+ (instancetype) stringWithUTF16String:(const unichar *)chars;


/*	-utf16DataWithBOM:
	Convert to native-endian UTF-16 data.
*/
- (NSData *) utf16DataWithBOM:(BOOL)includeByteOrderMark;

/*	- oo_hash
	Hash function for when we want consistency across platforms and versions.
	It implements modified djb2 (with xor rather than addition) in terms of
	UTF-16 code elements.
*/
- (uint32_t) oo_hash;

@end


@interface NSMutableString (OOExtensions)

- (void) appendLine:(NSString *)line;
- (void) appendFormatLine:(NSString *)fmt, ...;
- (void) appendFormatLine:(NSString *)fmt arguments:(va_list)args;

- (void) deleteCharacterAtIndex:(unsigned long)index;

@end


/*	OOTabString(count)
	
	Return a string of <count> tabs.
*/
NSString *OOTabString(NSUInteger count);
