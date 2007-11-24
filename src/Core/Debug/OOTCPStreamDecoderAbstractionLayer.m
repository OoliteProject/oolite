/*	OOTCPStreamDecoderAbstractionLayer.h
	
	Abstraction layer to allow OOTCPStreamDecoder to work with CoreFoundation/
	CF-Lite, Cocoa Foundation or GNUstep Foundation.
	
	Foundation implementation.
*/

#ifndef OO_EXCLUDE_DEBUG_SUPPORT

#import "OOTCPStreamDecoderAbstractionLayer.h"
#import "OOCocoa.h"


// Simulate literal CF/NS strings. Each literal string that is used becomes a single object. Since it uses pointers as keys, it should only be used with literals.
OOALStringRef OOALGetConstantString(const char *string)
{
	static NSMutableDictionary		*sStrings = nil;
	NSValue							*key = nil;
	NSString						*value = nil;
	
	if (sStrings == nil)
	{
		sStrings = [[NSMutableDictionary alloc] init];
	}
	
	key = [NSValue valueWithPointer:string];
	value = [sStrings objectForKey:key];
	if (value == nil)
	{
		// Note: non-ASCII strings are not permitted, but we don't bother to detect them.
		value = [NSString stringWithUTF8String:string];
		if (value != nil)  [sStrings setObject:value forKey:key];
	}
	
	return value;
}


void OOALRelease(OOALObjectRef object)
{
	[object release];
}


OOALStringRef OOTypeDescription(OOALObjectRef object)
{
	return [[object class] description];
}


bool OOALIsString(OOALObjectRef object)
{
	return [object isKindOfClass:[NSString class]];
}


OOALStringRef OOALStringCreateWithFormatAndArguments(OOALStringRef format, va_list args)
{
	return [[NSString alloc] initWithFormat:format arguments:args];
}


bool OOALIsDictionary(OOALObjectRef object)
{
	return [object isKindOfClass:[NSDictionary class]];
}


OOALObjectRef OOALDictionaryGetValue(OOALDictionaryRef dictionary, OOALObjectRef key)
{
	return [dictionary objectForKey:key];
}


bool OOALIsData(OOALObjectRef object)
{
	return [object isKindOfClass:[NSData class]];
}


OOALMutableDataRef OOALDataCreateMutable(size_t capacity)
{
	return [[NSMutableData alloc] initWithCapacity:capacity];
}


void OOALMutableDataAppendBytes(OOALMutableDataRef data, const void *bytes, size_t length)
{
	[data appendBytes:bytes length:length];
}


const void *OOALDataGetBytePtr(OOALDataRef data)
{
	return [data bytes];
}


size_t OOALDataGetLength(OOALDataRef data)
{
	return [data length];
}


OOALAutoreleasePoolRef OOALCreateAutoreleasePool(void)
{
	return [[NSAutoreleasePool alloc] init];
}


OOALObjectRef OOALPropertyListFromData(OOALMutableDataRef data, OOALStringRef *errStr)
{
	id result = [NSPropertyListSerialization propertyListFromData:data
												 mutabilityOption:NSPropertyListImmutable
														   format:NULL
												 errorDescription:errStr];
	[result retain];
	
#if !OOLITE_RELEASE_PLIST_ERROR_STRINGS
	[*errStr retain];
#endif
	
	return result;
}

#endif /* OO_EXCLUDE_DEBUG_SUPPORT */
