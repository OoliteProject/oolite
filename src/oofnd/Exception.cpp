/*	oofnd/Exception.cpp
        OORaiseException(), the exception names and oo::CurrentOOException() (see oofnd/Exception.hpp).
        Moved from oofnd/objc/OOException.mm when bead oo-4aq6a.1 deleted the Objective-C OOException
        class; the code is unchanged.
*/

#include "oofnd/Exception.hpp"

#include <cstdarg>
#include <cstdio>
#include <string>

const char* const OOGenericException = "NSGenericException";
const char* const OOInvalidArgumentException = "NSInvalidArgumentException";
const char* const OORangeException = "NSRangeException";
const char* const OOInternalInconsistencyException = "NSInternalInconsistencyException";
const char* const OOMallocException = "NSMallocException";

namespace {

// printf into a std::string; args is consumed.
std::string FormatReason(const char* format, va_list args)
{
    std::string reason;
    va_list measure;
    va_copy(measure, args);
    int length = std::vsnprintf(nullptr, 0, format, measure);
    va_end(measure);
    if (length > 0) {
        reason.resize(static_cast<size_t>(length) + 1);
        std::vsnprintf(reason.data(), reason.size(), format, args);
        reason.resize(static_cast<size_t>(length));
    }
    return reason;
}

} // namespace

void OORaiseException(const char* name, const char* format, ...)
{
    std::string reason;
    if (format != nullptr) {
        va_list args;
        va_start(args, format);
        reason = FormatReason(format, args);
        va_end(args);
    }
    throw oo::Exception(name, reason.c_str()); // the C++ exception since bead oo-rskgl.1
}

namespace oo {

std::optional<CaughtOOException> CurrentOOException()
{
    try {
        throw;
    } catch (const Exception& exception) {
        return CaughtOOException(&exception);
    } catch (...) {
        return std::nullopt; // not the game's exception: not what @catch (OOException *) caught
    }
}

} // namespace oo
