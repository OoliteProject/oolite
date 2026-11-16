/*

HeadUpDisplay+FoundationBridge.h

TRANSITIONAL (proposed ADR-0043, "Transitional bridges"; made by bead oo-3rb.209, chunk 1 of the
HeadUpDisplay sweep oo-3rb.81, and extended only by its later chunks oo-3rb.210-.213).
HeadUpDisplay's Foundation-typed API as it was before its sweep, with the same selector and function
names and types, forwarding to the cxx_ API in HeadUpDisplay.h. It exists so that HeadUpDisplay's
callers (GuiDisplayGen, Universe, PlayerEntity, OOJSPlayerShip, PlayerEntityStickProfile,
PlayerEntityStickMapper, OOStringParsing, OOJSFont) compile unchanged; each caller moves to the cxx_
API in its own sweep bead. It also carries the NSString (OOHUDBeaconIcon) category, which the entity
files' beacon-letter strings use until they have a Foundation-free drawable. When `git grep` finds
no caller of anything declared here, the bridge bead deletes this file,
HeadUpDisplay+FoundationBridge.mm, its line in Core/meson.build and the #import at the end of
HeadUpDisplay.h. Never add to it outside the HeadUpDisplay chunks; never call it from migrated
code. oo-qps (the removal of gnustep-base) cannot compile while it exists.

Registry: src/oofnd/README.md, "Transitional bridges".

Copyright (C) 2004-2013 Giles C Williams and contributors (HeadUpDisplay.h)

*/

// Imported only from the end of HeadUpDisplay.h (which declares everything used here); never
// import it directly, and never import HeadUpDisplay.h from it (a cycle).
#ifndef HEADUPDISPLAY_FOUNDATIONBRIDGE_H
#define HEADUPDISPLAY_FOUNDATIONBRIDGE_H

@interface HeadUpDisplay (OOFoundationBridge)

// Chunk 2 (oo-3rb.210): hidden selectors.
- (void)setHiddenSelector:(NSString*)selectorName hidden:(BOOL)hide; // -> -cxx_setHiddenSelector:hidden:

// Chunk 3 (oo-3rb.211): initialiser, GUI reset, names, crosshair definition.
- (id)initWithDictionary:(NSDictionary*)hudinfo inFile:(NSString*)hudFileName; // -> -cxx_initWithDictionary:inFile:

- (void)resetGuis:(NSDictionary*)info; // -> -cxx_resetGuis:

- (NSString*)hudName; // -> -cxx_hudName

- (void)setDeferredHudName:(NSString*)newDeferredHudName; // -> -cxx_setDeferredHudName:
- (NSString*)deferredHudName; // -> -cxx_deferredHudName
- (NSString*)crosshairDefinition; // -> -cxx_crosshairDefinition
- (BOOL)setCrosshairDefinition:(NSString*)newDefinition; // -> -cxx_setCrosshairDefinition:

@end

// Chunk 1 (oo-3rb.209): the beacon-letter category and the text engine.
@interface NSString (OOHUDBeaconIcon) <OOHUDBeaconIcon>
@end

void OODrawString(NSString* text, GLfloat x, GLfloat y, GLfloat z, NSSize siz); // -> cxx_OODrawString
void OODrawStringAligned(NSString* text, GLfloat x, GLfloat y, GLfloat z, NSSize siz, BOOL rightAlign); // -> cxx_OODrawStringAligned
void OODrawStringQuadsAligned(NSString* text, GLfloat x, GLfloat y, GLfloat z, NSSize siz, BOOL rightAlign); // -> cxx_OODrawStringQuadsAligned
void OODrawHilightedString(NSString* text, GLfloat x, GLfloat y, GLfloat z, NSSize siz); // -> cxx_OODrawHilightedString
NSRect OORectFromString(NSString* text, GLfloat x, GLfloat y, NSSize siz); // -> cxx_OORectFromString

#ifdef __cplusplus
extern "C" {
#endif

CGFloat OOStringWidthInEm(NSString* text); // -> cxx_OOStringWidthInEm

#ifdef __cplusplus
}
#endif

#endif // HEADUPDISPLAY_FOUNDATIONBRIDGE_H
