/*	oofnd/objc/OOException.mm
        The Foundation-free Objective-C exception (see OOException.h and proposed ADR-0029).
*/

#include "oofnd/objc/OOException.h"

#include <cstdarg>
#include <cstdio>
#include <string>

const char* const OOGenericException = "NSGenericException";
const char* const OOInvalidArgumentException = "NSInvalidArgumentException";
const char* const OORangeException = "NSRangeException";
const char* const OOInternalInconsistencyException = "NSInternalInconsistencyException";
const char* const OOMallocException = "NSMallocException";

@implementation OOException {
    std::string _name;
    std::string _reason;
}

+ (id)exceptionWithName:(const char*)name reason:(const char*)reason
{
    return [[[self alloc] initWithName:name reason:reason] autorelease];
}

+ (void)raise:(const char*)name format:(const char*)format, ...
{
    std::string reason;
    if (format != nullptr) {
        va_list args;
        va_start(args, format);
        va_list measure;
        va_copy(measure, args);
        int length = std::vsnprintf(nullptr, 0, format, measure);
        va_end(measure);
        if (length > 0) {
            reason.resize(static_cast<size_t>(length) + 1);
            std::vsnprintf(reason.data(), reason.size(), format, args);
            reason.resize(static_cast<size_t>(length));
        }
        va_end(args);
    }
    @throw [self exceptionWithName:name reason:reason.c_str()];
}

- (id)initWithName:(const char*)name reason:(const char*)reason
{
    if ((self = [super init])) {
        _name = name != nullptr ? name : "";
        _reason = reason != nullptr ? reason : "";
    }
    return self;
}

- (const char*)name
{
    return _name.c_str();
}

- (const char*)reason
{
    return _reason.c_str();
}

- (void)raise
{
    @throw self;
}

@end
