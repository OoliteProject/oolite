#if __ppc__ || __ppc664__
#include "../../Cross-platform-deps/mozilla/nsprpub/pr/src/md/unix/os_Darwin_ppc.s"
#elif __i386__
#include "../../Cross-platform-deps/mozilla/nsprpub/pr/src/md/unix/os_Darwin_x86.s"
#elif __x86_64__
#include "../../Cross-platform-deps/mozilla/nsprpub/pr/src/md/unix/os_Darwin_x86_64.s"
#endif
