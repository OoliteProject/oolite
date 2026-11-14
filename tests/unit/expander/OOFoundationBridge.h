// Stub for tests/unit/expander (bead oo-3rb.335; Jon approved in chat 2026-09-30): the harness's own
// copy of the five NSString <-> std::string / oo::PList conversions it and its stubs use, taken
// unchanged from src/Core/OOStringBridge.h + OOFoundationBridge.h as oo-qps.16 deleted them
// (69f5a7108^), so every recorded line and digest is produced exactly as before. Test
// infrastructure only (the harness links gnustep-base; OOHarnessFoundation.h); never in the game.
#ifndef OO_HARNESS_FOUNDATION_BRIDGE_H
#define OO_HARNESS_FOUNDATION_BRIDGE_H

#import "OOFoundation.h"
#import "OOObjCPList.h"

#include "oofnd/String.hpp"
#include "oofnd/StdLib.hpp"
#include "oofnd/PList.hpp"

#include <optional>
#include <string>
#include <string_view>

namespace oo {

// NSString -> UTF-8 std::string, losslessly. nil -> "".
inline std::string StdString(NSString *string)
{
	const NSUInteger length = [string length];
	if (length == 0)  return std::string();
	std::u16string units(length, u'\0');
	[string getCharacters:reinterpret_cast<unichar *>(units.data()) range:NSMakeRange(0, length)];
	return oo::utf16ToUtf8(units);
}

// UTF-8 std::string -> NSString, unit for unit.
inline NSString *NSStringFrom(std::string_view string)
{
	const std::u16string units = oo::utf8ToUtf16(string);
	return [[[NSString alloc] initWithBytes:units.data()
									 length:units.size() * sizeof(char16_t)
								   encoding:NSUTF16LittleEndianStringEncoding] autorelease];
}

inline std::optional<std::string> OptionalString(NSString *string)
{
	if (string == nil)  return std::nullopt;
	return StdString(string);
}

inline PList PListFrom(id object)
{
	if (object == nil)  return PList();
	if ([object isKindOfClass:[NSString class]])  return PList(StdString(object));
	if ([object isKindOfClass:[NSNumber class]])
	{
		NSNumber *number = object;
		// Former NSNumber (OOExtensions) boolean identity test: constant true/false objects only.
#if __COREFOUNDATION_CFNUMBER__
		if (number == (NSNumber *)kCFBooleanTrue || number == (NSNumber *)kCFBooleanFalse)
			return PList(static_cast<bool>([number boolValue]));
#else
		{
			static NSNumber *sTrue = nil, *sFalse = nil;
			if (sTrue == nil)
			{
				sTrue = [[NSNumber numberWithBool:YES] retain];
				sFalse = [[NSNumber numberWithBool:NO] retain];
			}
			if (number == sTrue || number == sFalse)
				return PList(static_cast<bool>([number boolValue]));
		}
#endif
		// gnustep-base reports 'd' for a float too; its class tells (NSSmallFloat, NSFloatNumber: probed).
		if (std::string_view(class_getName(object_getClass(number))).find("Float") != std::string_view::npos)  return PList::singleReal([number floatValue]);
		switch (*[number objCType])
		{
			case 'f':
			case 'd':
				return PList([number doubleValue]);
			case 'C':
			case 'S':
			case 'I':
			case 'L':
			case 'Q':
				return PList::unsignedInteger([number unsignedLongLongValue]);
			default:
				return PList::signedInteger([number longLongValue]);
		}
	}
	if ([object isKindOfClass:[NSData class]])
	{
		NSData *data = object;
		return PList(Data([data bytes], [data length]));
	}
	if ([object isKindOfClass:[NSDate class]])
	{
		return PList(PList::Date{[(NSDate *)object timeIntervalSinceReferenceDate]});
	}
	if ([object isKindOfClass:[NSArray class]])
	{
		PList::Array array;
		array.reserve([(NSArray *)object count]);
		for (id element in (NSArray *)object)  array.push_back(PListFrom(element));
		return PList(std::move(array));
	}
	if ([object isKindOfClass:[NSDictionary class]])
	{
		NSDictionary *dictionary = object;
		PList::Dict dict;
		for (id key in dictionary)
		{
			if (![key isKindOfClass:[NSString class]])  return PList();
			dict.emplace(StdString(key), PListFrom([dictionary objectForKey:key]));
		}
		return PList(std::move(dict));
	}
	return PListObject(object);
}

inline id ObjectFromPList(const PList& plist)
{
	switch (plist.type())
	{
		case PList::Type::Null:
			return nil;
		case PList::Type::Bool:
			return [NSNumber numberWithBool:*plist.getIf<bool>() ? YES : NO];
		case PList::Type::Integer:
		{
			const PList::Integer& integer = *plist.getIf<PList::Integer>();
			if (integer.isUnsigned)  return [NSNumber numberWithUnsignedLongLong:integer.unsignedValue()];
			return [NSNumber numberWithLongLong:integer.value];
		}
		case PList::Type::Real:
			if (plist.isSinglePrecision())  return [NSNumber numberWithFloat:static_cast<float>(*plist.getIf<double>())];
			return [NSNumber numberWithDouble:*plist.getIf<double>()];
		case PList::Type::String:
			return NSStringFrom(*plist.getIf<std::string>());
		case PList::Type::Data:
		{
			const Data& data = *plist.getIf<PList::Data>();
			return [NSData dataWithBytes:data.bytes() length:data.length()];
		}
		case PList::Type::Date:
			return [NSDate dateWithTimeIntervalSinceReferenceDate:plist.getIf<PList::Date>()->sinceReferenceDate];
		case PList::Type::Array:
		{
			const PList::Array& array = *plist.getIf<PList::Array>();
			NSMutableArray *result = [NSMutableArray arrayWithCapacity:array.size()];
			for (const PList& element : array)
			{
				id object = ObjectFromPList(element);
				if (object != nil)  [result addObject:object];
			}
			return [[result copy] autorelease];
		}
		case PList::Type::Dict:
		{
			const PList::Dict& dict = *plist.getIf<PList::Dict>();
			NSMutableDictionary *result = [NSMutableDictionary dictionaryWithCapacity:dict.size()];
			for (const auto& [key, value] : dict)
			{
				id object = ObjectFromPList(value);
				if (object != nil)  [result setObject:object forKey:NSStringFrom(key)];
			}
			return [[result copy] autorelease];
		}
		case PList::Type::Object:
			return ObjectIn(plist);
	}
	return nil;
}

}	// namespace oo

#endif	// OO_HARNESS_FOUNDATION_BRIDGE_H
