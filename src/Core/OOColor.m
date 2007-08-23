/*

OOColor.m

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

#import "OOColor.h"
#import "OOCollectionExtractors.h"
#import "OOMaths.h"


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
	if (s == 0.0f)
	{
		rgba[0] = rgba[1] = rgba[2] = b;
		rgba[3] = a;
		return;
	}
	GLfloat f, p, q, t;
	int i;
	h = fmodf(h, 360.0f);
	if (h < 0.0) h += 360.0f;
	h /= 60.0f;
	
	i = floor(h);
	f = h - i;
	p = b * (1.0f - s);
	q = b * (1.0f - (s * f));
	t = b * (1.0f - (s * (1.0f - f)));
	
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


+ (OOColor *)colorWithCalibratedWhite:(float)white alpha:(float)alpha
{
	return [OOColor colorWithCalibratedRed:white green:white blue:white alpha:alpha];
}


+ (OOColor *)colorWithDescription:(id)description
{
	if (description == nil) return nil;
	
	if ([description isKindOfClass:[NSString class]])
	{
		if ([description hasSuffix:@"Color"])
		{
			// +fooColor selector
			SEL selector = NSSelectorFromString(description);
			if ([self respondsToSelector:selector])  return [self performSelector:selector];
		}
		else
		{
			// Some other string
			return [self colorFromString:description];
		}
	}
	else if ([description isKindOfClass:[NSArray class]])
	{
		return [self colorFromString:[description componentsJoinedByString:@" "]];
	}
	else if ([description isKindOfClass:[NSDictionary class]])
	{
		if ([description objectForKey:@"hue"] != nil)
		{
			// Treat as HSB(A) dictionary
			float h = [description floatForKey:@"hue"];
			float s = [description floatForKey:@"saturation" defaultValue:1.0f];
			float b = [description floatForKey:@"brightness" defaultValue:-1.0f];
			if (b < 0.0f)  b = [description floatForKey:@"value" defaultValue:1.0f];
			float a = [description floatForKey:@"alpha" defaultValue:-1.0f];
			if (a < 0.0f)  a = [description floatForKey:@"opacity" defaultValue:1.0f];
			
			return [OOColor colorWithCalibratedHue:h / 360.0f saturation:s brightness:b alpha:a];
		}
		else
		{
			// Treat as RGB(A) dictionary
			float r = [description floatForKey:@"red"];
			float g = [description floatForKey:@"green"];
			float b = [description floatForKey:@"blue"];
			float a = [description floatForKey:@"alpha" defaultValue:-1.0f];
			if (a < 0.0f)  a = [description floatForKey:@"opacity" defaultValue:1.0f];
			
			return [OOColor colorWithCalibratedRed:r green:g blue:b alpha:a];
		}
	}
	
	return nil;
}


+ (OOColor *)brightColorWithDescription:(id)description
{
	OOColor *color = [OOColor colorWithDescription:description];
	if (color == nil || 0.5f <= [color brightnessComponent])  return color;
	
	return [OOColor colorWithCalibratedHue:[color hueComponent] saturation:[color saturationComponent] brightness:0.5f alpha:1.0f];
}


+ (OOColor *)colorFromString:(NSString*) colorFloatString
{
	float			rgba[4] = { 0.0f, 0.0f, 0.0f, 1.0f };
	NSScanner		*scanner = [NSScanner scannerWithString:colorFloatString];
	float			factor = 1.0f;
	int				i;
	
	for (i = 0; i != 4; ++i)
	{
		if (![scanner scanFloat:&rgba[i]])
		{
			// Less than three floats or non-float, can't parse -> quit
			if (i < 3) return nil;
			
			// If we get here, we only got three components. Make sure alpha is at correct scale:
			rgba[3] /= factor;
		}
		if (1.0f < rgba[i]) factor = 1.0f / 255.0f;
	}
	
	return [OOColor colorWithCalibratedRed:rgba[0] * factor green:rgba[1] * factor blue:rgba[2] * factor alpha:rgba[3] * factor];
}


+ (OOColor *)blackColor			// 0.0 white
{
	return [OOColor colorWithCalibratedWhite:0.0f alpha:1.0f];
}


+ (OOColor *)darkGrayColor		// 0.333 white
{
	return [OOColor colorWithCalibratedWhite:1.0f/3.0f alpha:1.0f];
}


+ (OOColor *)lightGrayColor		// 0.667 white
{
	return [OOColor colorWithCalibratedWhite:2.0f/3.0f alpha:1.0f];
}


+ (OOColor *)whiteColor			// 1.0 white
{
	return [OOColor colorWithCalibratedWhite:1.0f alpha:1.0f];
}


+ (OOColor *)grayColor			// 0.5 white
{
	return [OOColor colorWithCalibratedWhite:0.5f alpha:1.0f];
}


+ (OOColor *)redColor			// 1.0, 0.0, 0.0 RGB
{
	return [OOColor colorWithCalibratedRed:1.0f green:0.0f blue:0.0f alpha:1.0f];
}


+ (OOColor *)greenColor			// 0.0, 1.0, 0.0 RGB
{
	return [OOColor colorWithCalibratedRed:0.0f green:1.0f blue:0.0f alpha:1.0f];
}


+ (OOColor *)blueColor			// 0.0, 0.0, 1.0 RGB
{
	return [OOColor colorWithCalibratedRed:0.0f green:0.0f blue:1.0f alpha:1.0f];
}


+ (OOColor *)cyanColor			// 0.0, 1.0, 1.0 RGB
{
	return [OOColor colorWithCalibratedRed:0.0f green:1.0f blue:1.0f alpha:1.0f];
}


+ (OOColor *)yellowColor		// 1.0, 1.0, 0.0 RGB
{
	return [OOColor colorWithCalibratedRed:1.0f green:1.0f blue:0.0f alpha:1.0f];
}


+ (OOColor *)magentaColor		// 1.0, 0.0, 1.0 RGB
{
	return [OOColor colorWithCalibratedRed:1.0f green:0.0f blue:1.0f alpha:1.0f];
}


+ (OOColor *)orangeColor		// 1.0, 0.5, 0.0 RGB
{
	return [OOColor colorWithCalibratedRed:1.0f green:0.5f blue:0.0f alpha:1.0f];
}


+ (OOColor *)purpleColor		// 0.5, 0.0, 0.5 RGB
{
	return [OOColor colorWithCalibratedRed:0.5f green:0.0f blue:0.5f alpha:1.0f];
}


+ (OOColor *)brownColor			// 0.6, 0.4, 0.2 RGB
{
	return [OOColor colorWithCalibratedRed:0.6f green:0.4f blue:0.2f alpha:1.0f];
}


+ (OOColor *)clearColor		// 0.0 white, 0.0 alpha
{
	return [OOColor colorWithCalibratedWhite:0.0f alpha:0.0f];
}


- (OOColor *)blendedColorWithFraction:(float)fraction ofColor:(OOColor *)color
{
	GLfloat	rgba1[4];
	[color getRed:&rgba1[0] green:&rgba1[1] blue:&rgba1[2] alpha:&rgba1[3]];
	OOColor* result = [[OOColor alloc] init];
	float prime = 1.0f - fraction;
	[result setRGBA: prime * rgba[0] + fraction * rgba1[0] : prime * rgba[1] + fraction * rgba1[1] : prime * rgba[2] + fraction * rgba1[2] : prime * rgba[3] + fraction * rgba1[3]];
	return [result autorelease];
}


// find a point on the sea->land scale
+ (OOColor *) planetTextureColor:(float) q:(OOColor *) seaColor:(OOColor *) paleSeaColor:(OOColor *) landColor:(OOColor *) paleLandColor
{
	float hi = 0.33;
	float oh = 1.0 / hi;
	float ih = 1.0 / (1.0 - hi);
	if (q <= 0.0)
		return seaColor;
	if (q > 1.0)
		return [OOColor whiteColor];
	if (q < 0.01)
		return [paleSeaColor blendedColorWithFraction: q * 100.0 ofColor: landColor];
	if (q > hi)
		return [paleLandColor blendedColorWithFraction: (q - hi) * ih ofColor: [OOColor whiteColor]];	// snow capped peaks
	return [paleLandColor blendedColorWithFraction: (hi - q) * oh ofColor: landColor];
}


// find a point on the sea->land scale given impress and bias
+ (OOColor *) planetTextureColor:(float) q:(float) impress:(float) bias :(OOColor *) seaColor:(OOColor *) paleSeaColor:(OOColor *) landColor:(OOColor *) paleLandColor
{
	float maxq = impress + bias;
	
	float hi = 0.66667 * maxq;
	float oh = 1.0 / hi;
	float ih = 1.0 / (1.0 - hi);
	
	if (q <= 0.0)
		return seaColor;
	if (q > 1.0)
		return [OOColor whiteColor];
	if (q < 0.01)
		return [paleSeaColor blendedColorWithFraction: q * 100.0 ofColor: landColor];
	if (q > hi)
		return [paleLandColor blendedColorWithFraction: (q - hi) * ih ofColor: [OOColor whiteColor]];	// snow capped peaks
	return [paleLandColor blendedColorWithFraction: (hi - q) * oh ofColor: landColor];
}


// Get the red, green, or blue components.
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


// Get the components as hue, saturation, or brightness.
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


// Get the alpha component.
- (float)alphaComponent
{
	return rgba[3];
}


- (OOColor *)premultipliedColor
{
	if (rgba[3] == 1.0f)  return [[self retain] autorelease];
	return [OOColor colorWithCalibratedRed:rgba[0] * rgba[3]
									 green:rgba[1] * rgba[3]
									  blue:rgba[2] * rgba[3]
									 alpha:1.0f];
}


- (OOColor *)colorWithBrightnessFactor:(float)factor
{
	return [OOColor colorWithCalibratedRed:OOClamp_0_1_f(rgba[0] * factor)
									 green:OOClamp_0_1_f(rgba[1] * factor)
									  blue:OOClamp_0_1_f(rgba[2] * factor)
									 alpha:rgba[3]];
}

@end
