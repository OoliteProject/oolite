/*

OOOXPVerifierStage+ObjCBridge.h

TRANSITIONAL (proposed ADR-0056 Amendment 1, bead oo-cwz): the Objective-C OOOXPVerifierStage, a
facade over the C++ cxx::OOOXPVerifierStage (OOOXPVerifierStage.h), for the Objective-C verifier
and for the stages not converted yet. Its interface is the one OOOXPVerifierStage.h declared
before the conversion, copied exactly (same selectors, same types), so they compile and behave
unchanged; OOOXPVerifierStageInternal.h still declares its OOInternal category. Imported as the
last line of OOOXPVerifierStage.h; do not import it directly.

A class with subclasses has two kinds of facade, one class:

        the stage is                         its facade is                      virtual calls on the
                                                                                  C++ side reach
        -----------------------------------  ---------------------------------  ---------------------
        an Objective-C subclass              the subclass instance itself; its  the subclass's
          (unconverted, [[X alloc] init])    -init made its C++ part, an        methods (-cxx_name,
                                             adapter that forwards the virtual  -run, ...), as
                                             members to it                      overriding did
        a C++ subclass (converted)           made by oo::ToObjC, one live one   the C++ overrides
                                             per stage (oo::ObjCPeers)

An Objective-C subclass's [super cxx_name] (and -cxx_dependencies, -dependents, -shouldRun,
-run) reaches the C++ base class's own member, not the virtual one, so it does what the base did.
An Objective-C subclass of a converted intermediate class (OOFileHandlingVerifierStage, bead
oo-up4b) is the same kind, with an adapter over that class, oo::ObjCStage<cxx::Mid>, and reaches
cxx::Mid's own members. A converted class with a facade of its own (cxx::X, facade X) is the
second kind; oo::ToObjC makes an X for it.

        a caller that is                       holds / passes                      crosses with
        -------------------------------------  ----------------------------------  -----------------
        still Objective-C (the verifier,       OOOXPVerifierStage * (this facade)  nothing
          unconverted stages)
        converted (C++)                        oo::Ref<cxx::OOOXPVerifierStage>
          handing a stage to Objective-C                                           oo::ToObjC(stage)
          taking one from Objective-C                                              oo::ToCxx(objcStage)

oo::ToObjC(oo::ToCxx(s)) == s for both kinds. Never add to this file; converted code does not
message the facade. Deleted by its deletion bead once the verifier and every stage are C++.


Copyright (C) 2007-2013 Jens Ayton

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

*/

#ifndef OOOXPVERIFIERSTAGE_OBJCBRIDGE_H
#define OOOXPVERIFIERSTAGE_OBJCBRIDGE_H

#if OO_OXP_VERIFIER_ENABLED

#include "oofnd/objc/OOObjCRef.h"

@interface OOOXPVerifierStage : OOObject {
@private
    oo::Ref<cxx::OOOXPVerifierStage> _cxxStage;
}

- (OOOXPVerifier*)verifier;
- (BOOL)completed;

// Subclass responsibilities:

- (std::optional<std::string>)cxx_name; // nullopt: none (bead oo-3rb.289.1)
- (std::optional<std::vector<std::string>>)cxx_dependencies; // nullopt: none (nil); override this (bead oo-3rb.291.3)
- (std::optional<std::vector<std::string>>)dependents; // stage names; nullopt: none (nil)
- (BOOL)shouldRun;
- (void)run;

@end

@interface OOOXPVerifierStage (OOObjCBridge)

/*	The facade of a C++ stage (oo::ToObjC makes it); or, from the -init of a converted intermediate
        class's facade (ADR-0056 Amendment 1 item 7, bead oo-up4b), an Objective-C stage whose C++ part
        is stage, an oo::ObjCStage of that class. Retains stage.
*/
- (id)initWithCxxStage:(cxx::OOOXPVerifierStage*)stage;

@end

namespace oo {

// The stage's Objective-C object: an Objective-C stage itself, else a C++ stage's live facade (or
// a new one); autoreleased. nil for null.
OOOXPVerifierStage* ToObjC(cxx::OOOXPVerifierStage* stage);
inline OOOXPVerifierStage* ToObjC(const Ref<cxx::OOOXPVerifierStage>& stage) { return ToObjC(stage.get()); }

// The C++ stage behind an Objective-C one, borrowed (the Objective-C object retains it); null for nil.
cxx::OOOXPVerifierStage* ToCxx(OOOXPVerifierStage* stage);

/*	The C++ part of an Objective-C stage (an unconverted subclass), the adapter: each virtual
        member messages the Objective-C object, so the subclass's override runs, as it did when the
        base class was Objective-C. Base is the C++ class of its nearest converted superclass:
        cxx::OOOXPVerifierStage when the root facade's -init makes it, cxx::Mid when an intermediate
        facade's -init does (ADR-0056 amendment of bead oo-up4b). The super...() members are Base's
        own, what [super ...] reached; the root facade answers with them when the subclass does not
        override a method, or calls super. The Objective-C object owns the adapter (its _cxxStage) and
        is not retained by it; its -dealloc clears the pointer, after which the members answer as a
        message to nil did.
*/
class ObjCStageLink {
public:
    ::OOOXPVerifierStage* owner() { return _owner; }
    void ownerDeallocated() { _owner = nil; }

    virtual std::optional<std::string> superName() = 0;
    virtual std::optional<std::vector<std::string>> superDependencies() = 0;
    virtual std::optional<std::vector<std::string>> superDependents() = 0;
    virtual bool superShouldRun() = 0;
    virtual void superRun() = 0;

protected:
    explicit ObjCStageLink(::OOOXPVerifierStage* owner)
        : _owner(owner)
    {
    }
    ~ObjCStageLink() = default;

    ::OOOXPVerifierStage* _owner = { }; // Not retained.
};

template <class Base>
class ObjCStage final : public Base, public ObjCStageLink {
public:
    explicit ObjCStage(::OOOXPVerifierStage* owner)
        : ObjCStageLink(owner)
    {
    }

    std::optional<std::string> name() override { return [_owner cxx_name]; }
    std::optional<std::vector<std::string>> dependencies() override { return [_owner cxx_dependencies]; }
    std::optional<std::vector<std::string>> dependents() override { return [_owner dependents]; }
    bool shouldRun() override { return [_owner shouldRun]; }
    void run() override { [_owner run]; }

    std::optional<std::string> superName() override { return Base::name(); }
    std::optional<std::vector<std::string>> superDependencies() override { return Base::dependencies(); }
    std::optional<std::vector<std::string>> superDependents() override { return Base::dependents(); }
    bool superShouldRun() override { return Base::shouldRun(); }
    void superRun() override { Base::run(); }
};

// The adapter, if stage is an Objective-C stage's C++ part; else null (a C++ stage, or null).
ObjCStageLink* AsObjCStage(cxx::OOOXPVerifierStage* stage);

} // namespace oo

#endif // OO_OXP_VERIFIER_ENABLED

#endif // OOOXPVERIFIERSTAGE_OBJCBRIDGE_H
