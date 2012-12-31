/*
	OldSchoolPropertyListWriting.h
	Copyright 2006-2013 Jens Ayton
	
	A protocol for writing property lists in the OpenStep/simple text format. Why? Because as of
	Tiger, the system functions to write plists reject the format. I, however, like it, because
	it’s clear and legible. Fight the power!

	Permission is hereby granted, free of charge, to any person obtaining a copy of this software
	and associated documentation files (the "Software"), to deal in the Software without
	restriction, including without limitation the rights to use, copy, modify, merge, publish,
	distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the
	Software is furnished to do so, subject to the following conditions:
	
	The above copyright notice and this permission notice shall be included in all copies or
	substantial portions of the Software.

	THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING
	BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
	NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
	DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
	OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
*/

#import <Foundation/Foundation.h>


@protocol OldSchoolPropertyListWriting

- (NSString *)oldSchoolPListFormatWithIndentation:(unsigned)inIndentation errorDescription:(NSString **)outErrorDescription;

@end


@interface NSObject (OldSchoolPropertyListWriting)

- (NSData *)oldSchoolPListFormatWithErrorDescription:(NSString **)outErrorDescription;

@end



@interface NSString (OldSchoolPropertyListWriting) <OldSchoolPropertyListWriting>
@end

@interface NSNumber (OldSchoolPropertyListWriting) <OldSchoolPropertyListWriting>
@end

@interface NSData (OldSchoolPropertyListWriting) <OldSchoolPropertyListWriting>
@end

@interface NSArray (OldSchoolPropertyListWriting) <OldSchoolPropertyListWriting>
@end

@interface NSDictionary (OldSchoolPropertyListWriting) <OldSchoolPropertyListWriting>
@end
