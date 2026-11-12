/*	oofnd/AutoreleaseScope.hpp
        oo::AutoreleaseScope, the game's autorelease pool over shared
   ownership (spec 009, contracts/ownership.md), with the rules of the
   libobjc2 pool it replaces:

          * per-thread and nested: the innermost scope on the thread receives
            what is autoreleased;
          * draining releases newest first, and an object released during a
            drain that autoreleases another puts it on top, so it is released
            next, in the same pass;
          * scopes end in LIFO order on the thread that opened them; anything
            else is a programming error and aborts;
          * with no scope open on the thread, an autoreleased object is kept
            forever and counted (GNUstep's "autorelease called without pool").
*/

#pragma once

#include <cstddef>
#include <cstdlib>
#include <memory>
#include <utility>
#include <vector>

namespace oo {

class AutoreleaseScope;

namespace detail {

inline thread_local AutoreleaseScope* tInnermostScope = nullptr;
inline thread_local std::size_t tLeakedWithoutScope = 0;

// Hands one owning reference to the innermost scope on this thread; with none
// open it is kept forever and counted.
inline void autoreleaseOwner(std::shared_ptr<const void> owner) noexcept;

}  // namespace detail

class AutoreleaseScope {
 public:
  AutoreleaseScope() noexcept : parent_(detail::tInnermostScope) {
    detail::tInnermostScope = this;
  }

  ~AutoreleaseScope() {  // drains, then pops itself
    if (detail::tInnermostScope != this)
      std::abort();  // not LIFO, or not this thread
    drain();
    detail::tInnermostScope = parent_;
  }

  AutoreleaseScope(const AutoreleaseScope&) = delete;
  AutoreleaseScope& operator=(const AutoreleaseScope&) = delete;
  static void* operator new(std::size_t) = delete;
  static void* operator new[](std::size_t) = delete;

  // Releases newest first, cascading: an object autoreleased by a release
  // lands on top and is released next. The scope stays open.
  void drain() noexcept {
    while (!pending_.empty()) {
      std::shared_ptr<const void> owner = std::move(pending_.back());
      pending_.pop_back();
      owner.reset();  // may autorelease more, onto pending_
    }
  }

  std::size_t pendingCount() const noexcept { return pending_.size(); }

  // The innermost open scope on this thread, or nullptr.
  static AutoreleaseScope* current() noexcept {
    return detail::tInnermostScope;
  }

  // How many objects this thread autoreleased with no scope open (and so kept
  // forever).
  static std::size_t leakedWithoutScope() noexcept {
    return detail::tLeakedWithoutScope;
  }

 private:
  friend void detail::autoreleaseOwner(
      std::shared_ptr<const void> owner) noexcept;

  AutoreleaseScope* parent_;
  std::vector<std::shared_ptr<const void>> pending_;
};

namespace detail {

inline void autoreleaseOwner(std::shared_ptr<const void> owner) noexcept {
  if (AutoreleaseScope* scope = tInnermostScope) {
    scope->pending_.push_back(std::move(owner));
  } else {
    ++tLeakedWithoutScope;
    // Kept forever, as the object was with no pool (never deleted).
    try {
      static_cast<void>(new std::shared_ptr<const void>(std::move(owner)));
    } catch (...) {
      std::abort();  // out of memory while keeping it: nothing else to do
    }
  }
}

}  // namespace detail

// Hands one owning reference to the innermost scope on this thread and returns
// the raw pointer. With no scope open the object is kept forever and counted,
// as today.
template <class T>
T* autorelease(std::shared_ptr<T> p) noexcept {
  T* raw = p.get();
  if (raw != nullptr) detail::autoreleaseOwner(std::move(p));
  return raw;
}

}  // namespace oo
