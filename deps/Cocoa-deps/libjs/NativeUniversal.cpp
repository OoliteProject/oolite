#if __i386__
#include "../../mozilla/js/src/nanojit/Nativei386.cpp"
#elif __x86_64__
#include "../../mozilla/js/src/nanojit/NativeX64.cpp"
#endif
