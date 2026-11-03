// Stub for tests/unit/sysdesc (bead oo-3rb.335; Jon approved in chat 2026-09-30): the harness's own
// copy of the three conversions it uses (StdString, NSStringFrom, ObjectFromPList), taken unchanged
// from src/Core/OOStringBridge.h + OOFoundationBridge.h as oo-qps.16 deleted them (69f5a7108^), so
// every recorded line and digest is produced exactly as before. One difference: an Object node
// (an OOObject inside a PList, Core/OOObjCPList.h) converts to nil here, because the harness only
// converts plists parsed from files, which never hold one, and OOObjCPList.h would pull the game's
// Objective-C description family into this Foundation-linked test. Test infrastructure only (the
// harness links gnustep-base; OOHarnessFoundation.h); never in the game.
#ifndef OO_HARNESS_FOUNDATION_BRIDGE_H
#define OO_HARNESS_FOUNDATION_BRIDGE_H

#import "OOFoundation.h"

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
			return nil;	// never in a parsed plist (see the top of this file)
	}
	return nil;
}

}	// namespace oo

#endif	// OO_HARNESS_FOUNDATION_BRIDGE_H
