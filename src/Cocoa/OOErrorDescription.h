/*

OOErrorDescription.h

A set of functions for mapping various types of Mac OS error codes to names,
primarily for debugging purposes.

For OOCASound - Core Audio sound implementation for Oolite.
By Jens Ayton, 2005

This file is hereby placed in the public domain.

*/

#import <Foundation/Foundation.h>


// Provide descriptions of various Mac-specific error codes
NSString *OSStatusErrorNSString(OSStatus inCode);
NSString *AudioErrorNSString(ComponentResult inCode);
NSString *KernelResultNSString(kern_return_t inCode);
NSString *FourCharCodeToNSString(FourCharCode inCode);
NSString *AudioErrorShortNSString(OSStatus inCode);
