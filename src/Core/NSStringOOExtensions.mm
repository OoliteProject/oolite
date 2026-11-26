/*

NSStringOOExtensions.m

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

#import "NSStringOOExtensions.h"
#import "NSDataOOExtensions.h"
#import "OOFoundation.h"
#import "OOStringBridge.h"

@implementation NSString (OOExtensions)

+ (instancetype)stringWithContentsOfUnicodeFile:(NSString*)path
{
    // The UTF-16 / UTF-8 / Latin-1 decision and GNUstep's decoding are oo::str's (bead
    // oo-3rb.62), including the corrected length after a UTF-8 BOM: this read six bytes past
    // the buffer (length + 3).
    NSData* data = [NSData oo_dataWithOXZFile:path];
    if (data == nil)
        return nil;
    return oo::NSStringFrom(oo::str::decodeUnicodeFile((const uint8_t*)[data bytes], [data length]));
}

+ (instancetype)stringWithUTF16String:(const unichar*)chars
{
    size_t length;
    const unichar* end;

    if (chars == NULL)
        return nil;

    // Find length of string.
    end = chars;
    while (*end++) { }
    length = end - chars - 1;

    return [NSString stringWithCharacters:chars length:length];
}

- (NSData*)utf16DataWithBOM:(BOOL)includeByteOrderMark
{
    size_t lengthInChars;
    size_t lengthInBytes;
    unichar* buffer = NULL;
    unichar* characters = NULL;

    // Calculate sizes
    lengthInChars = [self length];
    lengthInBytes = lengthInChars * sizeof(unichar);
    if (includeByteOrderMark)
        lengthInBytes += sizeof(unichar);

    // Allocate buffer
    buffer = (unichar*)malloc(lengthInBytes);
    if (buffer == NULL)
        return nil;

    // write BOM (native-endian) if desired
    characters = buffer;
    if (includeByteOrderMark) {
        *characters++ = 0xFEFF;
    }

    // Get the contents
    [self getCharacters:characters];

    // NSData takes ownership of the buffer.
    return [NSData dataWithBytesNoCopy:buffer length:lengthInBytes freeWhenDone:YES];
}

- (uint32_t)oo_hash
{
    NSUInteger i, length = [self length];
    uint32_t hash = 5381;
    for (i = 0; i < length; i++) {
        hash = ((hash << 5) + hash) /* 33 * hash */ ^ [self characterAtIndex:i];
    }
    return hash;
}

- (NSString*)stringByTrimmingLeadingCharactersInSet:(NSCharacterSet*)characterSet
{
    NSRange rangeOfFirstWantedCharacter = [self rangeOfCharacterFromSet:[characterSet invertedSet]];
    if (rangeOfFirstWantedCharacter.location == NSNotFound)
        return @"";

    return [self substringFromIndex:rangeOfFirstWantedCharacter.location];
}

- (NSString*)stringByTrimmingLeadingWhitespaceAndNewlineCharacters
{
    return [self stringByTrimmingLeadingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

- (NSString*)stringByTrimmingTrailingCharactersInSet:(NSCharacterSet*)characterSet
{
    NSRange rangeOfLastWantedCharacter = [self rangeOfCharacterFromSet:[characterSet invertedSet] options:NSBackwardsSearch];
    if (rangeOfLastWantedCharacter.location == NSNotFound)
        return @"";

    return [self substringToIndex:rangeOfLastWantedCharacter.location + 1]; // non-inclusive
}

- (NSString*)stringByTrimmingTrailingWhitespaceAndNewlineCharacters
{
    return [self stringByTrimmingTrailingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

@end

@implementation NSMutableString (OOExtensions)

- (void)appendLine:(NSString*)line
{
    [self appendString:line ? [line stringByAppendingString:@"\n"] : (NSString*)@"\n"];
}

- (void)appendFormatLine:(NSString*)fmt, ...
{
    va_list args;
    va_start(args, fmt);
    [self appendFormatLine:fmt arguments:args];
    va_end(args);
}

- (void)appendFormatLine:(NSString*)fmt arguments:(va_list)args
{
    NSString* formatted = [[NSString alloc] initWithFormat:fmt arguments:args];
    [self appendLine:formatted];
    [formatted release];
}

- (void)deleteCharacterAtIndex:(unsigned long)index
{
    [self deleteCharactersInRange:NSMakeRange(index, 1)];
}

@end

NSString* OOTabString(NSUInteger count)
{
    NSString* const staticTabs[] = {
        @"",
        @"\t",
        @"\t\t",
        @"\t\t\t",
        @"\t\t\t\t",
        @"\t\t\t\t\t", // 5
        @"\t\t\t\t\t\t",
        @"\t\t\t\t\t\t\t",
        @"\t\t\t\t\t\t\t\t",
        @"\t\t\t\t\t\t\t\t\t",
        @"\t\t\t\t\t\t\t\t\t\t" // 10
    };
    enum { kStaticTabCount = sizeof staticTabs / sizeof *staticTabs };

    if (count < kStaticTabCount) {
        return staticTabs[count];
    } else {
        return [staticTabs[kStaticTabCount - 1] stringByAppendingString:OOTabString(count - (kStaticTabCount - 1))];
    }
}
