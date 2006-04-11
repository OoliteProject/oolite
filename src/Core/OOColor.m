/*

	Oolite

	OOColor.m

	Created by Giles Williams on 31/03/2006.


Copyright (c) 2005, Giles C Williams
All rights reserved.

This work is licensed under the Creative Commons Attribution-NonCommercial-ShareAlike License.
To view a copy of this license, visit http://creativecommons.org/licenses/by-nc-sa/2.0/
or send a letter to Creative Commons, 559 Nathan Abbott Way, Stanford, California 94305, USA.

You are free:

•	to copy, distribute, display, and perform the work
•	to make derivative works

Under the following conditions:

•	Attribution. You must give the original author credit.

•	Noncommercial. You may not use this work for commercial purposes.

•	Share Alike. If you alter, transform, or build upon this work,
you may distribute the resulting work only under a license identical to this one.

For any reuse or distribution, you must make clear to others the license terms of this work.

Any of these conditions can be waived if you get permission from the copyright holder.

Your fair use and other rights are in no way affected by the above.

*/

#import "OOColor.h"

@implementation OOColor

- (void) setRGBA:(GLfloat)r:(GLfloat)g:(GLfloat)b:(GLfloat)a
{
	rgba[0] = r;
	rgba[1] = g;
	rgba[2] = b;
	rgba[3] = a;
}

- (void) setHSBA:(GLfloat)h:(GLfloat)s:(GLfloat)b:(GLfloat)a
{
	if (s == 0.0)
	{
		rgba[0] = rgba[1] = rgba[2] = b;
		rgba[3] = a;
		return;
	}
	GLfloat f, p, q, t;
	int i;
	while (h >= 360.0) h -= 360.0;
	while (h < 0.0) h += 360.0;
	h /= 60.0;
	i = floor(h);
	f = h - i;
	p = b * (1.0 - s);
	q = b * (1.0 - (s * f));
	t = b * (1.0 - (s * (1.0 - f)));
	switch (i)
	{
		case 0:
			rgba[0] = b;	rgba[1] = t;	rgba[2] = p;	break;
		case 1:
			rgba[0] = q;	rgba[1] = b;	rgba[2] = p;	break;
		case 2:
			rgba[0] = p;	rgba[1] = b;	rgba[2] = t;	break;
		case 3:
			rgba[0] = p;	rgba[1] = q;	rgba[2] = b;	break;
		case 4:
			rgba[0] = t;	rgba[1] = p;	rgba[2] = b;	break;
		case 5:
			rgba[0] = b;	rgba[1] = p;	rgba[2] = q;	break;
	}
	rgba[3] = a;
}

/* Create NSCalibratedRGBColorSpace colors.
*/
+ (OOColor *)colorWithCalibratedHue:(float)hue saturation:(float)saturation brightness:(float)brightness alpha:(float)alpha
{
	OOColor* result = [[OOColor alloc] init];
	[result setHSBA: 360.0 * hue : saturation : brightness : alpha];
	return [result autorelease];
}

+ (OOColor *)colorWithCalibratedRed:(float)red green:(float)green blue:(float)blue alpha:(float)alpha
{
	OOColor* result = [[OOColor alloc] init];
	[result setRGBA:red:green:blue:alpha];
	return [result autorelease];
}

/* Some convenience methods to create colors in the calibrated color spaces...
*/
+ (OOColor *)blackColor;	/* 0.0 white */
{
	OOColor* result = [[OOColor alloc] init];
	[result setRGBA: 0.0 : 0.0 : 0.0 : 1.0];
	return [result autorelease];
}
+ (OOColor *)darkGrayColor;	/* 0.333 white */
{
	OOColor* result = [[OOColor alloc] init];
	[result setRGBA: 0.333 : 0.333 : 0.333 : 1.0];
	return [result autorelease];
}
+ (OOColor *)lightGrayColor;	/* 0.667 white */
{
	OOColor* result = [[OOColor alloc] init];
	[result setRGBA: 0.667 : 0.667 : 0.667 : 1.0];
	return [result autorelease];
}
+ (OOColor *)whiteColor;	/* 1.0 white */
{
	OOColor* result = [[OOColor alloc] init];
	[result setRGBA: 1.0 : 1.0 : 1.0 : 1.0];
	return [result autorelease];
}
+ (OOColor *)grayColor;		/* 0.5 white */
{
	OOColor* result = [[OOColor alloc] init];
	[result setRGBA: 0.5 : 0.5 : 0.5 : 1.0];
	return [result autorelease];
}
+ (OOColor *)redColor;		/* 1.0, 0.0, 0.0 RGB */
{
	OOColor* result = [[OOColor alloc] init];
	[result setRGBA: 1.0 : 0.0 : 0.0 : 1.0];
	return [result autorelease];
}

+ (OOColor *)greenColor;	/* 0.0, 1.0, 0.0 RGB */
{
	OOColor* result = [[OOColor alloc] init];
	[result setRGBA: 0.0 : 1.0 : 0.00 : 1.0];
	return [result autorelease];
}
+ (OOColor *)blueColor;		/* 0.0, 0.0, 1.0 RGB */
{
	OOColor* result = [[OOColor alloc] init];
	[result setRGBA: 0.0 : 0.0 : 1.0 : 1.0];
	return [result autorelease];
}
+ (OOColor *)cyanColor;		/* 0.0, 1.0, 1.0 RGB */
{
	OOColor* result = [[OOColor alloc] init];
	[result setRGBA: 0.0 : 1.0 : 1.0 : 1.0];
	return [result autorelease];
}
+ (OOColor *)yellowColor;	/* 1.0, 1.0, 0.0 RGB */
{
	OOColor* result = [[OOColor alloc] init];
	[result setRGBA: 1.0 : 1.0 : 0.0 : 1.0];
	return [result autorelease];
}
+ (OOColor *)magentaColor;	/* 1.0, 0.0, 1.0 RGB */
{
	OOColor* result = [[OOColor alloc] init];
	[result setRGBA: 1.0 : 0.0 : 1.0 : 1.0];
	return [result autorelease];
}
+ (OOColor *)orangeColor;	/* 1.0, 0.5, 0.0 RGB */
{
	OOColor* result = [[OOColor alloc] init];
	[result setRGBA: 1.0 : 0.5 : 0.0 : 1.0];
	return [result autorelease];
}
+ (OOColor *)purpleColor;	/* 0.5, 0.0, 0.5 RGB */
{
	OOColor* result = [[OOColor alloc] init];
	[result setRGBA: 0.5 : 0.0 : 0.5 : 1.0];
	return [result autorelease];
}
+ (OOColor *)brownColor;	/* 0.6, 0.4, 0.2 RGB */
{
	OOColor* result = [[OOColor alloc] init];
	[result setRGBA: 0.6 : 0.4 : 0.2 : 1.0];
	return [result autorelease];
}
+ (OOColor *)clearColor;	/* 0.0 white, 0.0 alpha */
{
	OOColor* result = [[OOColor alloc] init];
	[result setRGBA: 0.0 : 0.0 : 0.0 : 0.0];
	return [result autorelease];
}

/* Blend using the NSCalibratedRGB color space. Both colors are converted into the calibrated RGB color space, and they are blended by taking fraction of color and 1 - fraction of the receiver. The result is in the calibrated RGB color space. If the colors cannot be converted into the calibrated RGB color space the blending fails and nil is returned.
*/
- (OOColor *)blendedColorWithFraction:(float)fraction ofColor:(OOColor *)color
{
	GLfloat	rgba1[4];
	[color getRed:&rgba1[0] green:&rgba1[1] blue:&rgba1[2] alpha:&rgba1[3]];
	OOColor* result = [[OOColor alloc] init];
	float prime = 1.0f - fraction;
	[result setRGBA: prime * rgba[0] + fraction * rgba1[0] : prime * rgba[1] + fraction * rgba1[1] : prime * rgba[2] + fraction * rgba1[2] : prime * rgba[3] + fraction * rgba1[3]];
	return [result autorelease];
}

/* Get the red, green, or blue components of NSCalibratedRGB or NSDeviceRGB colors.
*/
- (GLfloat)redComponent
{
	return rgba[0];
}

- (GLfloat)greenComponent
{
	return rgba[1];
}

- (GLfloat)blueComponent
{
	return rgba[2];
}

- (void)getRed:(GLfloat *)red green:(GLfloat *)green blue:(GLfloat *)blue alpha:(GLfloat *)alpha
{
	*red = rgba[0];
	*green = rgba[1];
	*blue = rgba[2];
	*alpha = rgba[3];
}

/* Get the components of NSCalibratedRGB or NSDeviceRGB colors as hue, saturation, or brightness.
*/
- (float)hueComponent
{
	GLfloat maxrgb = (rgba[0] > rgba[1])? ((rgba[0] > rgba[2])? rgba[0]:rgba[2]):((rgba[1] > rgba[2])? rgba[1]:rgba[2]);
	GLfloat minrgb = (rgba[0] < rgba[1])? ((rgba[0] < rgba[2])? rgba[0]:rgba[2]):((rgba[1] < rgba[2])? rgba[1]:rgba[2]);
	if (maxrgb == minrgb)
		return 0.0;
	GLfloat delta = maxrgb - minrgb;
	GLfloat hue = 0.0;
	if (rgba[0] == maxrgb)
		hue = (rgba[1] - rgba[2]) / delta;
	else if (rgba[1] == maxrgb)
		hue = 2.0 + (rgba[2] - rgba[0]) / delta;
	else if (rgba[2] == maxrgb)
		hue = 4.0 + (rgba[0] - rgba[1]) / delta;
	hue *= 60.0;
	while (hue < 0.0) hue += 360.0;
	return hue;
}

- (float)saturationComponent
{
	GLfloat maxrgb = (rgba[0] > rgba[1])? ((rgba[0] > rgba[2])? rgba[0]:rgba[2]):((rgba[1] > rgba[2])? rgba[1]:rgba[2]);
	GLfloat minrgb = (rgba[0] < rgba[1])? ((rgba[0] < rgba[2])? rgba[0]:rgba[2]):((rgba[1] < rgba[2])? rgba[1]:rgba[2]);
	GLfloat brightness = 0.5 * (maxrgb + minrgb);
	if (maxrgb == minrgb)
		return 0.0;
	GLfloat delta = maxrgb - minrgb;
	return (brightness <= 0.5)? (delta / (maxrgb + minrgb)) : (delta / (2.0 - (maxrgb + minrgb)));
}

- (float)brightnessComponent
{
	GLfloat maxrgb = (rgba[0] > rgba[1])? ((rgba[0] > rgba[2])? rgba[0]:rgba[2]):((rgba[1] > rgba[2])? rgba[1]:rgba[2]);
	GLfloat minrgb = (rgba[0] < rgba[1])? ((rgba[0] < rgba[2])? rgba[0]:rgba[2]):((rgba[1] < rgba[2])? rgba[1]:rgba[2]);
	return 0.5 * (maxrgb + minrgb);
}

- (void)getHue:(float *)hue saturation:(float *)saturation brightness:(float *)brightness alpha:(float *)alpha
{
	*alpha = rgba[3];
	GLfloat maxrgb = (rgba[0] > rgba[1])? ((rgba[0] > rgba[2])? rgba[0]:rgba[2]):((rgba[1] > rgba[2])? rgba[1]:rgba[2]);
	GLfloat minrgb = (rgba[0] < rgba[1])? ((rgba[0] < rgba[2])? rgba[0]:rgba[2]):((rgba[1] < rgba[2])? rgba[1]:rgba[2]);
	*brightness = 0.5 * (maxrgb + minrgb);
	if (maxrgb == minrgb)
	{
		*saturation = 0.0;
		*hue = 0.0;
		return;
	}
	GLfloat delta = maxrgb - minrgb;
	*saturation = (*brightness <= 0.5)? (delta / (maxrgb + minrgb)) : (delta / (2.0 - (maxrgb + minrgb)));
	if (rgba[0] == maxrgb)
		*hue = (rgba[1] - rgba[2]) / delta;
	else if (rgba[1] == maxrgb)
		*hue = 2.0 + (rgba[2] - rgba[0]) / delta;
	else if (rgba[2] == maxrgb)
		*hue = 4.0 + (rgba[0] - rgba[1]) / delta;
	*hue *= 60.0;
	while (*hue < 0.0) *hue += 360.0;
}


/* Get the alpha component. For colors which do not have alpha components, this will return 1.0 (opaque).
*/
- (float)alphaComponent
{
	return rgba[3];
}


#ifndef GNUSTEP

- (NSColor *)asNSColor
{
	return [NSColor colorWithCalibratedRed:rgba[0] green:rgba[1] blue:rgba[2] alpha:rgba[3]];
}


- (void)set
{
	[[self asNSColor] set];
}


- (void)setFill
{
	[[self asNSColor] setFill];
}


- (void)setStroke
{
	[[self asNSColor] setStroke];
}

#endif

@end
