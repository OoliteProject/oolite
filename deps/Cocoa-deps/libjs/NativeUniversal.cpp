#if __ppc__ || ___ppc64__
#include "../../Cross-platform-deps/mozilla/js/src/nanojit/NativePPC.cpp"
#elif __i386__
#include "../../Cross-platform-deps/mozilla/js/src/nanojit/Nativei386.cpp"
#elif __x86_64__
#include "../../Cross-platform-deps/mozilla/js/src/nanojit/NativeX64.cpp"
#endif
