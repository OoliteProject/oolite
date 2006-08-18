/*

	Oolite

	OOColor.h

	Created by Giles Williams on 31/03/2006.


Copyright (c) 2005, Giles C Williams
All rights reserved.

This work is licensed under the Creative Commons Attribution-NonCommercial-ShareAlike License.
To view a copy of this license, visit http://creativecommons.org/licenses/by-nc-sa/2.0/
or send a letter to Creative Commons, 559 Nathan Abbott Way, Stanford, California 94305, USA.

You are free:

‚Ä¢	to copy, distribute, display, and perform the work
‚Ä¢	to make derivative works

Under the following conditions:

‚Ä¢	Attribution. You must give the original author credit.

‚Ä¢	Noncommercial. You may not use this work for commercial purposes.

‚Ä¢	Share Alike. If you alter, transform, or build upon this work,
you may distribute the resulting work only under a license identical to this one.

For any reuse or distribution, you must make clear to others the license terms of this work.

Any of these conditions can be waived if you get permission from the copyright holder.

Your fair use and other rights are in no way affected by the above.

*/

#import "OOCocoa.h"
#import "OOOpenGL.h"


@interface OOColor : NSObject
{
	GLfloat	rgba[4];
}

/* Create NSCalibratedRGBColorSpace colors.
*/
+ (OOColor *)colorWithCalibratedHue:(float)hue saturation:(float)saturation brightness:(float)brightness alpha:(float)alpha;
+ (OOColor *)colorWithCalibratedRed:(float)red green:(float)green blue:(float)blue alpha:(float)alpha;

/* Some convenience methods to create colors in the calibrated color spaces...
*/
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


/* Get the alpha component. For colors which do not have alpha components, this will return 1.0 (opaque).
*/
- (float)alphaComponent;

@end
