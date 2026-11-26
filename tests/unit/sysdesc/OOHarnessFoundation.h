// Harness prefix for tests/unit/sysdesc, force-included (-include) by tools/check-sysdesc-tools.sh
// into its two translation units: the copied OOConvertSystemDescriptions.mm and
// test_sysdesc_tools.mm (bead oo-3rb.335; Jon approved in
// chat 2026-09-30).
//
// The game left Foundation (oo-qps.16 .. oo-qps.18): OOCocoa.h now takes Foundation's C types from
// oofnd/objc/OOFoundationTypes.h, which refuses to compile beside Foundation by design. This harness
// still links gnustep-base, as test infrastructure (like tools/plist-fuzz/gnustep_oracle.mm): its
// NSString oracle IS the thing the digests were captured from. So here Foundation is imported first
// and the floor header's guard is pre-defined: the C types (NSInteger, NSRange, NSPoint ...) come
// from Foundation, which is what the floor header reproduces, and every other line of the real
// OOCocoa.h still applies.
#import <Foundation/Foundation.h>
#define OOFND_OBJC_OOFOUNDATIONTYPES_H 1
