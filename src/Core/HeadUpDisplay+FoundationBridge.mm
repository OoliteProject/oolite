/*

HeadUpDisplay+FoundationBridge.mm

TRANSITIONAL: see HeadUpDisplay+FoundationBridge.h. Each method and function forwards to its cxx_
counterpart and converts the result exactly as the old one produced it (nil for nil).

*/

#import "HeadUpDisplay.h" // declares the bridge at its end
#import "OOFoundationBridge.h"

@implementation HeadUpDisplay (OOFoundationBridge)

// Chunk 2 (oo-3rb.210).

// A nil name (from JavaScript) arrives as "".
- (void)setHiddenSelector:(NSString*)selectorName hidden:(BOOL)hide
{
    [self cxx_setHiddenSelector:oo::StdString(selectorName) hidden:hide];
}

// Chunk 3 (oo-3rb.211).

- (id)initWithDictionary:(NSDictionary*)hudinfo inFile:(NSString*)hudFileName
{
    return [self cxx_initWithDictionary:oo::PListFrom(hudinfo) inFile:oo::OptionalString(hudFileName)];
}

- (void)resetGuis:(NSDictionary*)info
{
    [self cxx_resetGuis:oo::PListFrom(info)];
}

- (NSString*)hudName
{
    return oo::NSStringOrNil([self cxx_hudName]);
}

- (void)setDeferredHudName:(NSString*)newDeferredHudName
{
    [self cxx_setDeferredHudName:oo::OptionalString(newDeferredHudName)];
}

- (NSString*)deferredHudName
{
    return oo::NSStringOrNil([self cxx_deferredHudName]);
}

- (NSString*)crosshairDefinition
{
    return oo::NSStringOrNil([self cxx_crosshairDefinition]);
}

// A nil name found no file, as "" does: the default crosshairs, NO.
- (BOOL)setCrosshairDefinition:(NSString*)newDefinition
{
    return [self cxx_setCrosshairDefinition:oo::StdString(newDefinition)];
}

@end

// Chunk 1 (oo-3rb.209).

@implementation NSString (OOHUDBeaconIcon)

- (void)oo_drawHUDBeaconIconAt:(NSPoint)where size:(NSSize)size alpha:(GLfloat)alpha z:(GLfloat)z
{
    cxx_OODrawString(oo::StdString(self), where.x - 2.5 * size.width, where.y - 3.0 * size.height, z, NSMakeSize(size.width * 2, size.height * 2));
}

@end

// A nil text drew and measured nothing; "" does the same.
void OODrawString(NSString* text, GLfloat x, GLfloat y, GLfloat z, NSSize siz)
{
    cxx_OODrawString(oo::StdString(text), x, y, z, siz);
}

void OODrawStringAligned(NSString* text, GLfloat x, GLfloat y, GLfloat z, NSSize siz, BOOL rightAlign)
{
    cxx_OODrawStringAligned(oo::StdString(text), x, y, z, siz, rightAlign);
}

void OODrawStringQuadsAligned(NSString* text, GLfloat x, GLfloat y, GLfloat z, NSSize siz, BOOL rightAlign)
{
    cxx_OODrawStringQuadsAligned(oo::StdString(text), x, y, z, siz, rightAlign);
}

void OODrawHilightedString(NSString* text, GLfloat x, GLfloat y, GLfloat z, NSSize siz)
{
    cxx_OODrawHilightedString(oo::StdString(text), x, y, z, siz);
}

NSRect OORectFromString(NSString* text, GLfloat x, GLfloat y, NSSize siz)
{
    return cxx_OORectFromString(oo::StdString(text), x, y, siz);
}

CGFloat OOStringWidthInEm(NSString* text)
{
    return cxx_OOStringWidthInEm(oo::StdString(text));
}
