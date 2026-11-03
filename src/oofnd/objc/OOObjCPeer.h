/*	oofnd/objc/OOObjCPeer.h
        oo::ObjCPeers: at most one live Objective-C peer per C++ object (proposed ADR-0056, bead
        oo-11m). Phase 3 converts a class to C++ while most of its callers are still Objective-C; they
        keep compiling against a thin Objective-C facade of the same name (X+ObjCBridge.h) that holds
        an oo::Ref to the C++ object. This table makes the facade faithful to identity: handing the
        same C++ object to Objective-C twice gives the same facade while that facade lives, so ==,
        -isEqual:, -hash and a PList::Object node behave as they did when there was one object.

            in X+ObjCBridge.mm                                    what it does
            ----------------------------------------------------  ----------------------------------------
            static oo::ObjCPeers &Peers()                         one table per facade class, made on first
            { static auto *p = new oo::ObjCPeers; return *p; }    use and never destroyed (a facade may be
                                                                  released while the process exits)
            Peers().peerFor(cxx, [&] { return [[X alloc] ...]; }) the live peer, else the one make() gives
                                                                  (+1, adopted); autoreleased; nil for null
            Peers().forget(cxx) in the facade's -dealloc          drops the entry once no peer is alive

        SEMANTICS
          * The table holds each peer WEAKLY (libobjc2's zeroing weak references, objc_initWeak and
            objc_loadWeakRetained), so it never keeps a facade alive; the facade keeps the C++ object
            alive through its oo::Ref ivar. A facade whose count has reached zero reads as dead here
            before its -dealloc runs, so a concurrent peerFor() never resurrects it: it makes a new peer.
          * forget() erases the entry only if its peer is dead: a peer made for the same object between
            the old one's final release and its -dealloc keeps its entry.
          * One mutex per table. make() runs under it, so it must not call back into the same table
            (a facade initialiser only stores its ivar); nothing is released or autoreleased under it.
          * Keys are C++ object addresses. An entry exists only while a peer that retains its object
            may exist, so an address is not reused while it has an entry.

        Header-only, Objective-C++. It includes no Foundation and links against libobjc2 alone.
        Deleted with the last facade (Phase 3 exit: zero @implementation).
*/

#ifndef OOFND_OBJC_OOOBJCPEER_H
#define OOFND_OBJC_OOOBJCPEER_H

#include <objc/runtime.h>

#include <objc/objc-arc.h>

// Objective-C++ game code sees OOCocoa.h's `#define true 1` / `#define false 0`; suspend them for
// the standard headers (as oofnd/Data.hpp does, proposed ADR-0028).
#pragma push_macro("true")
#pragma push_macro("false")
#undef true
#undef false

#include <mutex>
#include <unordered_map>

namespace oo {

class ObjCPeers {
public:
    ObjCPeers() = default;
    ObjCPeers(const ObjCPeers&) = delete;
    ObjCPeers& operator=(const ObjCPeers&) = delete;

    // The live peer of object if it has one, else make()'s new +1 peer, recorded. The result is
    // autoreleased (+0), as a factory method's was; nil for a null object or a nil make().
    template <class Make>
    id peerFor(const void* object, Make make)
    {
        if (object == nullptr)
            return nil;
        id peer = nil;
        {
            std::lock_guard<std::mutex> lock(mutex_);
            auto found = peers_.find(object);
            if (found != peers_.end())
                peer = objc_loadWeakRetained(&found->second);
            if (peer == nil) {
                peer = make();
                if (peer == nil)
                    return nil;
                if (found != peers_.end())
                    objc_storeWeak(&found->second, peer);
                else
                    objc_initWeak(&peers_[object], peer);
            }
        }
        return objc_autorelease(peer);
    }

    // Called from the peer's -dealloc: forgets object's entry unless a newer peer is alive.
    void forget(const void* object)
    {
        id live = nil;
        {
            std::lock_guard<std::mutex> lock(mutex_);
            auto found = peers_.find(object);
            if (found == peers_.end())
                return;
            live = objc_loadWeakRetained(&found->second);
            if (live == nil) {
                objc_destroyWeak(&found->second);
                peers_.erase(found);
            }
        }
        objc_release(live); // outside the lock: it may be the newer peer's last reference
    }

    // Entries (for tests).
    std::size_t count()
    {
        std::lock_guard<std::mutex> lock(mutex_);
        return peers_.size();
    }

private:
    std::mutex mutex_;
    std::unordered_map<const void*, id> peers_; // values are weak slots; nodes never move
};

} // namespace oo

#pragma pop_macro("false")
#pragma pop_macro("true")

#endif // OOFND_OBJC_OOOBJCPEER_H
