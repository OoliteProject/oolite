/*	oofnd/objc/OOAssert.mm
        Foundation-free assertions: the failure path (see OOAssert.h).
*/

#include "oofnd/objc/OOAssert.h"
#include "oofnd/Log.hpp"

#include <cstdarg>
#include <cstdio>
#include <string>

namespace {

std::string FormatV(const char* format, va_list args)
{
    std::string text;
    if (format == nullptr)
        return text;
    va_list measure;
    va_copy(measure, args);
    const int length = std::vsnprintf(nullptr, 0, format, measure);
    va_end(measure);
    if (length > 0) {
        text.resize(static_cast<std::size_t>(length) + 1);
        std::vsnprintf(text.data(), text.size(), format, args);
        text.resize(static_cast<std::size_t>(length));
    }
    return text;
}

[[noreturn]] void Fail(const std::string& reason)
{
    // gnustep-base NSLogv()ed the same text first; its NSLog hook logged it in class "gnustep".
    if (oo::log::willDisplay("gnustep"))
        oo::log::message("gnustep", nullptr, nullptr, 0, "{}", reason);
    OORaiseException(OOInternalInconsistencyException, "%s", reason.c_str()); // oo::Exception since bead oo-rskgl.1
    __builtin_unreachable();
}

} // namespace

void OOAssertFailedInFunction(const char* function, const char* file, long line, const char* format, ...)
{
    va_list args;
    va_start(args, format);
    const std::string message = FormatV(format, args);
    va_end(args);

    std::string reason = std::string(file != nullptr ? file : "") + ":" + std::to_string(line)
        + "  Assertion failed in " + (function != nullptr ? function : "") + ".  " + message;
    Fail(reason);
}
