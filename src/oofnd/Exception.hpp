/*	oofnd/Exception.hpp
        oo::Exception: the game's exception as a C++ type (bead oo-rskgl.1, ADR-0056 amendments
        oo-rskgl and oo-rskgl.1). It replaced the Objective-C OOException as the thing
        OORaiseException() throws; the Objective-C class was deleted by bead oo-4aq6a.1, which moved
        the rest of oofnd/objc/OOException.h here (that header now only includes this one).

            OOException                                   oofnd
            --------------------------------------------  ----------------------------------------------
            [OOException raise:N format:F, ...]            OORaiseException(N, F, ...)  (unchanged)
            [OOException exceptionWithName:N reason:R]     oo::Exception(N, R)
            @catch (OOException *e)                        catch (const oo::Exception &e)
            [e name], [e reason]                           e.name(), e.reason()  (const char *, UTF-8)
            Foundation's exception names                  OOInvalidArgumentException & co.: const char *
                                                           with the SAME text, so logged names do not change

        The name and reason are copied; a null one becomes "", as -initWithName:reason: did. It is
        deliberately NOT a std::exception: a handler for std::exception never caught an OOException,
        so it must not catch this one either. %@ has no meaning in OORaiseException's format: callers
        pass UTF-8 strings (%s).

        The game's @try/@catch/@finally as C++ try/catch (ADR-0056 amendment oo-rskgl):

            @catch (OOException *e) { ... [e name] ... }   catch (...)
                                                            {
                                                                const auto e = oo::CurrentOOException();
                                                                if (!e)  throw;	// not an OOException: on up
                                                                ... e->name() ...
                                                            }
            @throw e;  (inside that handler)                throw;  (the same object, rethrown)
            @catch (id e) { ... }                           catch (const oo::Exception &e) { ... }  (what
                                                            src throws; no Objective-C object is thrown)
            @catch (id e) {}                                catch (...)
                                                            {
                                                                if (!oo::CurrentOOException())  throw;
                                                            }  (the same, without an empty handler)
            @try { A } @finally { B }                       { oo::Finally f([&] { B }); A }

        CurrentOOException() tells the game's exception from anything else, as @catch (OOException *)
        did. The functions are defined in oofnd/Exception.cpp.

        C++20.
*/

#ifndef OOFND_EXCEPTION_HPP
#define OOFND_EXCEPTION_HPP

// Objective-C++ callers see OOFoundation.h's `#define true 1` / `#define false 0`; suspend them for the
// standard headers (as oofnd/Data.hpp does, proposed ADR-0028).
#pragma push_macro("true")
#pragma push_macro("false")
#undef true
#undef false

#include "oofnd/PrintfFormat.h"
#include <optional>
#include <string>
#include <utility>

extern "C" {

// Exception names. The text is Foundation's, so a name that reaches a log reads as it did.
extern const char* const OOGenericException;
extern const char* const OOInvalidArgumentException;
extern const char* const OORangeException;
extern const char* const OOInternalInconsistencyException;
extern const char* const OOMallocException;

/*	+[OOException raise:name format:...] as a function (Phase 3, proposed ADR-0056 amendment
        oo-dqxj): throws oo::Exception with the name and the printf-formatted reason. Never returns.
*/
void OORaiseException(const char* name, const char* format, ...) OO_PRINTF_FORMAT(2, 3) __attribute__((noreturn));
}

namespace oo {

class Exception {
public:
    Exception(const char* name, const char* reason)
        : _name(name != nullptr ? name : "")
        , _reason(reason != nullptr ? reason : "")
    {
    }

    // UTF-8, owned by the exception: valid while it is alive.
    const char* name() const noexcept { return _name.c_str(); }
    const char* reason() const noexcept { return _reason.c_str(); }

private:
    std::string _name;
    std::string _reason;
};

class CaughtOOException {
public:
    explicit CaughtOOException(const Exception* exception)
        : _exception(exception)
    {
    }

    // [exception name], [exception reason]: UTF-8, valid while the handler runs.
    const char* name() const { return _exception->name(); }
    const char* reason() const { return _exception->reason(); }

    // The exception itself, for an interface that still takes one.
    const Exception* object() const { return _exception; }

private:
    const Exception* _exception;
};

// Inside a catch handler only: the exception being handled when it is the game's oo::Exception,
// else std::nullopt (the handler then rethrows with `throw;`, as @catch (OOException *) let it pass).
std::optional<CaughtOOException> CurrentOOException();

// @finally: runs the body when the scope is left, normally or by an exception, after the handlers.
template <typename Body>
class Finally {
public:
    explicit Finally(Body body)
        : _body(std::move(body))
    {
    }
    ~Finally() noexcept(false) { _body(); }

    Finally(const Finally&) = delete;
    Finally& operator=(const Finally&) = delete;

private:
    Body _body;
};

} // namespace oo

#pragma pop_macro("false")
#pragma pop_macro("true")

#endif // OOFND_EXCEPTION_HPP
