/*

OOColor+FoundationBridge.h

TRANSITIONAL (proposed ADR-0043, "Transitional bridges"; bead oo-tms0). OOColor's Foundation-typed
API as it was before its sweep, with the same selector names and types, forwarding to the cxx_
API in OOColor.h. It exists so that OOColor's callers compile unchanged; each caller moves to the
cxx_ API in its own sweep bead. When `git grep` finds no caller of anything declared here, the
bridge bead deletes this file, OOColor+FoundationBridge.mm, its line in Core/meson.build and the
#import at the end of OOColor.h. Never add to it; never call it from migrated code. oo-qps (the
removal of gnustep-base) cannot compile while it exists.

Registry: src/oofnd/README.md, "Transitional bridges".

Copyright (C) 2007-2013 Jens Ayton and contributors (OOColor.h)

*/

// Imported only from the end of OOColor.h (which declares everything used here); never import it
// directly, and never import OOColor.h from it (a cycle).
#ifndef OOCOLOR_FOUNDATIONBRIDGE_H
#define OOCOLOR_FOUNDATIONBRIDGE_H

@interface OOColor (OOFoundationBridge)

+ (OOColor*)colorFromString:(NSString*)colorFloatString; // -> +cxx_colorFromString:
- (NSArray*)normalizedArray; // -> -cxx_normalizedArray
- (NSString*)rgbaDescription; // -> -cxx_rgbaDescription
- (NSString*)hsbaDescription; // -> -cxx_hsbaDescription

@end

NSString* OORGBAComponentsDescription(OORGBAComponents components); // -> cxx_OORGBAComponentsDescription
NSString* OOHSBAComponentsDescription(OOHSBAComponents components); // -> cxx_OOHSBAComponentsDescription

#endif // OOCOLOR_FOUNDATIONBRIDGE_H
