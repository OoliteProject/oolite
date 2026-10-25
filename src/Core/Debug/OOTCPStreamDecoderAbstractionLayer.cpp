/*	OOTCPStreamDecoderAbstractionLayer.h

	Abstraction layer to allow OOTCPStreamDecoder to work with CoreFoundation/
	CF-Lite, Cocoa Foundation or GNUstep Foundation.

	oofnd implementation (proposed ADR-0043 Amendment 2 item 14): each handle is a struct
	OOALObject holding its value as an oo::PList (a string, a data buffer or the parsed packet).
*/

#ifndef NDEBUG

#include "OOTCPStreamDecoderAbstractionLayer.h"
#include "OOCocoa.h"
#include "oofnd/Ref.hpp"	// oo::AutoreleaseScope (was objc-arc.h's pool functions, oo-31u.8)

#include "oofnd/PListParsing.hpp"
#include "oofnd/String.hpp"

#include "oofnd/StdLib.hpp"
#include "OOTCPStreamDecoderFormat.hpp"


struct OOALObject
{
	oo::PList value;
	// Borrowed handles given out for this object: its dictionary values and its type description.
	std::map<std::string, std::unique_ptr<OOALObject>, std::less<>> children;
	std::unique_ptr<OOALObject> typeDescription;
};


struct OOALAutoreleasePool
{
	std::vector<std::unique_ptr<OOALObject>> objects;
	// Was an Objective-C autorelease pool pushed with this one (oo-31u.8). Declared last so it
	// drains first, before the objects are freed, as the pool was popped before they were.
	oo::AutoreleaseScope deferred;
};


namespace {

// The innermost pools, innermost last (per thread, as autorelease pools are).
thread_local std::vector<OOALAutoreleasePool *> sPools;


OOALObject *NewObject(oo::PList value)
{
	auto *object = new OOALObject;
	object->value = std::move(value);
	return object;
}


// "%@" of a handle: what GNUstep printed for the object it stood for.
std::string DescriptionOf(OOALObjectRef object)
{
	if (object == nullptr)  return "(null)";
	if (const std::string *string = object->value.getIf<std::string>())  return *string;
	return oo::DescriptionOf(object->value);
}


}	// namespace


// Simulate literal CF/NS strings. Each literal string that is used becomes a single object. Since it uses pointers as keys, it should only be used with literals.
// Called from OOTCPStreamDecoder.c through OOALSTR(), so it keeps C linkage now that this file is Objective-C++ (bead oo-x7o).
extern "C" OOALStringRef OOALGetConstantString(const char *string);
OOALStringRef OOALGetConstantString(const char *string)
{
	static std::map<const char *, std::unique_ptr<OOALObject>> *sStrings = nullptr;

	if (sStrings == nullptr)
	{
		sStrings = new std::map<const char *, std::unique_ptr<OOALObject>>;
	}

	std::unique_ptr<OOALObject> &value = (*sStrings)[string];
	if (value == nullptr)
	{
		// Note: non-ASCII strings are not permitted, but we don't bother to detect them.
		value.reset(NewObject(oo::PList(std::string(string))));
	}

	return value.get();
}


void OOALRelease(OOALObjectRef object)
{
	delete object;
}


OOALStringRef OOTypeDescription(OOALObjectRef object)
{
	// What the handle holds: "(null)" for nothing, else the property-list type's name ("string",
	// "array", ...). It was the class name of the Foundation object built for the value
	// ([[object class] description], GNUstep's private classes such as GSCInlineString).
	auto *mutableObject = const_cast<OOALObject *>(object);
	if (mutableObject->typeDescription == nullptr)
	{
		const std::string name = object->value.isNull() ? std::string("(null)") : std::string(oo::typeName(object->value.type()));
		mutableObject->typeDescription.reset(NewObject(oo::PList(name)));
	}
	return mutableObject->typeDescription.get();
}


bool OOALIsString(OOALObjectRef object)
{
	return object->value.isString();
}


OOALStringRef OOALStringCreateWithFormatAndArguments(OOALStringRef format, va_list args)
{
	return NewObject(oo::PList(OOTCPStreamDecoderFormat::FormatWithArguments<OOALObjectRef>(DescriptionOf(format), args, DescriptionOf)));
}


bool OOALIsDictionary(OOALObjectRef object)
{
	return object->value.isDict();
}


OOALObjectRef OOALDictionaryGetValue(OOALDictionaryRef dictionary, OOALObjectRef key)
{
	const std::string *keyString = key->value.getIf<std::string>();
	if (keyString == nullptr)  return nullptr;
	const oo::PList *value = dictionary->value.find(*keyString);
	if (value == nullptr)  return nullptr;

	auto *parent = const_cast<OOALObject *>(dictionary);
	std::unique_ptr<OOALObject> &child = parent->children[*keyString];
	if (child == nullptr)  child.reset(NewObject(*value));
	return child.get();
}


bool OOALIsData(OOALObjectRef object)
{
	return object->value.isData();
}


OOALMutableDataRef OOALDataCreateMutable(size_t capacity)
{
	(void)capacity;
	return NewObject(oo::PList(oo::Data()));
}


void OOALMutableDataAppendBytes(OOALMutableDataRef data, const void *bytes, size_t length)
{
	data->value.getIf<oo::PList::Data>()->append(bytes, length);
}


const void *OOALDataGetBytePtr(OOALDataRef data)
{
	return data->value.getIf<oo::PList::Data>()->bytes();
}


size_t OOALDataGetLength(OOALDataRef data)
{
	return data->value.getIf<oo::PList::Data>()->length();
}


OOALAutoreleasePoolRef OOALCreateAutoreleasePool(void)
{
	auto *pool = new OOALAutoreleasePool;
	sPools.push_back(pool);
	return pool;
}


void OOALDestroyAutoreleasePool(OOALAutoreleasePoolRef pool)
{
	if (!sPools.empty() && sPools.back() == pool)  sPools.pop_back();
	delete pool;
}


OOALObjectRef OOALPropertyListFromData(OOALMutableDataRef data, OOALStringRef *errStr)
{
	const oo::Data &bytes = *data->value.getIf<oo::PList::Data>();
	oo::Expected<oo::PList, oo::PListError> parsed = oo::parsePropertyList(std::string_view(reinterpret_cast<const char *>(bytes.bytes()), bytes.length()));
	if (!parsed || parsed->isNull())
	{
		// The error string is owned by the caller (+1); no error text reads as nil did.
		if (errStr != nullptr)  *errStr = parsed ? nullptr : NewObject(oo::PList(parsed.error().description()));
		return nullptr;
	}

	OOALObject *result = NewObject(std::move(*parsed));
	// Belongs to the innermost pool (the decoder never releases a packet).
	if (!sPools.empty())  sPools.back()->objects.emplace_back(result);
	return result;
}


const oo::PList &OOALObjectPList(OOALObjectRef object)
{
	return object->value;
}

#endif /* NDEBUG */
