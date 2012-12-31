/*

NSDictionaryOOExtensions.m


Copyright (C) 2008-2013 Jens Ayton and contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

*/

#import "NSDictionaryOOExtensions.h"


@implementation NSDictionary (OOExtensions)

- (NSDictionary *) dictionaryByAddingObject:(id)object forKey:(id)key
{
	// Note: object lifetime issues aside, we need to copy and autorelease so that the right thing happens for mutable dictionaries.
	if (object == nil || key == nil)  return [[self copy] autorelease];
	
	NSMutableDictionary *temp = [self mutableCopy];
	[temp setObject:object forKey:key];
	NSDictionary *result = [[temp copy] autorelease];
	[temp release];
	
	return result;
}


- (NSDictionary *) dictionaryByRemovingObjectForKey:(id)key
{
	// Note: object lifetime issues aside, we need to copy and autorelease so that the right thing happens for mutable dictionaries.
	if (key == nil)  return [[self copy] autorelease];
	
	NSMutableDictionary *temp = [self mutableCopy];
	[temp removeObjectForKey:key];
	NSDictionary *result = [[temp copy] autorelease];
	[temp release];
	
	return result;
}


- (NSDictionary *) dictionaryByAddingEntriesFromDictionary:(NSDictionary *)dictionary
{
	// Note: object lifetime issues aside, we need to copy and autorelease so that the right thing happens for mutable dictionaries.
	if (dictionary == nil)  return [[self copy] autorelease];
	
	NSMutableDictionary *temp = [self mutableCopy];
	[temp addEntriesFromDictionary:dictionary];
	NSDictionary *result = [[temp copy] autorelease];
	[temp release];
	
	return result;
}

@end
