/*

OOColor.h

Replacement for NSColor (to avoid AppKit dependencies). Only handles RGBA
colours without colour space correction.

Oolite
Copyright (C) 2004-2007 Giles C Williams and contributors

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
MA 02110-1301, USA.

*/

#import "OOCocoa.h"
#import "OOOpenGL.h"


@interface OOColor : NSObject
{
	GLfloat	rgba[4];
}

+ (OOColor *)colorWithCalibratedHue:(float)hue saturation:(float)saturation brightness:(float)brightness alpha:(float)alpha;
+ (OOColor *)colorWithCalibratedRed:(float)red green:(float)green blue:(float)blue alpha:(float)alpha;
+ (OOColor *)colorWithCalibratedWhite:(float)white alpha:(float)alpha;

// Flexible color creator; takes a selector name, a string with components, or an array.
+ (OOColor *)colorWithDescription:(id)description;

// Like +colorWithDescription:, but forces brightness of at least 0.5.
+ (OOColor *)brightColorWithDescription:(id)description;

// Creates a colour given a string with components.
+ (OOColor *)colorFromString:(NSString*) colorFloatString;

+ (OOColor *)blackColor;	/* 0.0 white */
+ (OOColor *)darkGrayColor;	/* 0.333 white */
+ (OOColor *)lightGrayColor;	/* 0.667 white */
+ (OOColor *)whiteColor;	/* 1.0 white */
+ (OOColor *)grayColor;		/* 0.5 white */
+ (OOColor *)redColor;		/* 1.0, 0.0, 0.0 RGB */
+ (OOColor *)greenColor;	/* 0.0, 1.0, 0.0 RGB */
+ (OOColor *)blueColor;		/* 0.0, 0.0, 1.0 RGB */
+ (OOColor *)cyanColor;		/* 0.0, 1.0, 1.0 RGB */
+ (OOColor *)yellowColor;	/* 1.0, 1.0, 0.0 RGB */
+ (OOColor *)magentaColor;	/* 1.0, 0.0, 1.0 RGB */
+ (OOColor *)orangeColor;	/* 1.0, 0.5, 0.0 RGB */
+ (OOColor *)purpleColor;	/* 0.5, 0.0, 0.5 RGB */
+ (OOColor *)brownColor;	/* 0.6, 0.4, 0.2 RGB */
+ (OOColor *)clearColor;	/* 0.0 white, 0.0 alpha */

/* Blend using the NSCalibratedRGB color space. Both colors are converted into the calibrated RGB color space, and they are blended by taking fraction of color and 1 - fraction of the receiver. The result is in the calibrated RGB color space. If the colors cannot be converted into the calibrated RGB color space the blending fails and nil is returned.
*/
- (OOColor *)blendedColorWithFraction:(float)fraction ofColor:(OOColor *)color;

+ (OOColor *) planetTextureColor:(float) q:(OOColor *) seaColor:(OOColor *) paleSeaColor:(OOColor *) landColor:(OOColor *) paleLandColor;
+ (OOColor *) planetTextureColor:(float) q:(float) impress:(float) bias :(OOColor *) seaColor:(OOColor *) paleSeaColor:(OOColor *) landColor:(OOColor *) paleLandColor;

/* Get the red, green, or blue components of NSCalibratedRGB or NSDeviceRGB colors.
*/
- (float)redComponent;
- (float)greenComponent;
- (float)blueComponent;
- (void)getRed:(float *)red green:(float *)green blue:(float *)blue alpha:(float *)alpha;

/* Get the components of NSCalibratedRGB or NSDeviceRGB colors as hue, saturation, or brightness.
*/
- (float)hueComponent;
- (float)saturationComponent;
- (float)brightnessComponent;
- (void)getHue:(float *)hue saturation:(float *)saturation brightness:(float *)brightness alpha:(float *)alpha;


// Get the alpha component.
- (float)alphaComponent;

// Returns the colour, premultiplied by its alpha channel, and with an alpha of 1.0. If the reciever's alpha is 1.0, it will return itself.
- (OOColor *)premultipliedColor;

// Multiply r, g and b components of a colour by specified factor, clamped to [0..1].
- (OOColor *)colorWithBrightnessFactor:(float)factor;

- (GLfloat *) RGBA;

@end
