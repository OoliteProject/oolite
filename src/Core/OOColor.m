/*

OOColor.m

Oolite
Copyright (C) 2004-2012 Giles C Williams and contributors

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

// Set methods are internal, because OOColor is immutable (as seen from outside).
- (void) setRGBA:(OOCGFloat)r:(OOCGFloat)g:(OOCGFloat)b:(OOCGFloat)a
{
	rgba[0] = r;
	rgba[1] = g;
	rgba[2] = b;
	rgba[3] = a;
}


- (void) setHSBA:(OOCGFloat)h:(OOCGFloat)s:(OOCGFloat)b:(OOCGFloat)a
{
	rgba[3] = a;
	if (s == 0.0f)
	{
		rgba[0] = rgba[1] = rgba[2] = b;
		return;
	}
	OOCGFloat f, p, q, t;
	int i;
	h = fmod(h, 360.0f);
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
}


- (id)copyWithZone:(NSZone *)zone
{
	// Copy is implemented as retain since OOColor is immutable.
	return [self retain];
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


+ (OOColor *)colorWithRGBAComponents:(OORGBAComponents)components
{
	return [self colorWithCalibratedRed:components.r
								  green:components.g
								   blue:components.b
								  alpha:components.a];
}


+ (OOColor *)colorWithHSBAComponents:(OOHSBAComponents)components
{
	return [self colorWithCalibratedHue:components.h / 360.0f
							 saturation:components.s
							 brightness:components.b
								  alpha:components.a];
}


+ (OOColor *)colorWithDescription:(id)description
{
	return [self colorWithDescription:description saturationFactor:1.0f];
}


+ (OOColor *)colorWithDescription:(id)description saturationFactor:(float)factor
{
	NSDictionary			*dict = nil;
	OOColor					*result = nil;
	
	if (description == nil) return nil;
	
	if ([description isKindOfClass:[OOColor class]])
	{
		result = [[description copy] autorelease];
	}
	else if ([description isKindOfClass:[NSString class]])
	{
		if ([description hasSuffix:@"Color"])
		{
			// +fooColor selector
			SEL selector = NSSelectorFromString(description);
			if ([self respondsToSelector:selector])  result = [self performSelector:selector];
		}
		else
		{
			// Some other string
			result = [self colorFromString:description];
		}
	}
	else if ([description isKindOfClass:[NSArray class]])
	{
		result = [self colorFromString:[description componentsJoinedByString:@" "]];
	}
	else if ([description isKindOfClass:[NSDictionary class]])
	{
		dict = description;	// Workaround for gnu-gcc's more agressive "multiple methods named..." warnings.
		
		if ([dict objectForKey:@"hue"] != nil)
		{
			// Treat as HSB(A) dictionary
			float h = [dict oo_floatForKey:@"hue"];
			float s = [dict oo_floatForKey:@"saturation" defaultValue:1.0f];
			float b = [dict oo_floatForKey:@"brightness" defaultValue:-1.0f];
			if (b < 0.0f)  b = [dict oo_floatForKey:@"value" defaultValue:1.0f];
			float a = [dict oo_floatForKey:@"alpha" defaultValue:-1.0f];
			if (a < 0.0f)  a = [dict oo_floatForKey:@"opacity" defaultValue:1.0f];
			
			// Not "result =", because we handle the saturation scaling here to allow oversaturation.
			return [OOColor colorWithCalibratedHue:h / 360.0f saturation:s * factor brightness:b alpha:a];
		}
		else
		{
			// Treat as RGB(A) dictionary
			float r = [dict oo_floatForKey:@"red"];
			float g = [dict oo_floatForKey:@"green"];
			float b = [dict oo_floatForKey:@"blue"];
			float a = [dict oo_floatForKey:@"alpha" defaultValue:-1.0f];
			if (a < 0.0f)  a = [dict oo_floatForKey:@"opacity" defaultValue:1.0f];
			
			result = [OOColor colorWithCalibratedRed:r green:g blue:b alpha:a];
		}
	}
	
	if (factor != 1.0f && result != nil)
	{
		OOCGFloat h, s, b, a;
		[result getHue:&h saturation:&s brightness:&b alpha:&a];
		h *= 1.0 / 360.0f;	// See note in header.
		s *= factor;
		result = [self colorWithCalibratedHue:h saturation:s brightness:b alpha:a];
	}
	
	return result;
}


+ (OOColor *)brightColorWithDescription:(id)description
{
	OOColor *color = [OOColor colorWithDescription:description];
	if (color == nil || 0.5f <= [color brightnessComponent])  return color;
	
	return [OOColor colorWithCalibratedHue:[color hueComponent] / 360.0f saturation:[color saturationComponent] brightness:0.5f alpha:1.0f];
}


+ (OOColor *)colorFromString:(NSString*) colorFloatString
{
	float			rgbaValue[4] = { 0.0f, 0.0f, 0.0f, 1.0f };
	NSScanner		*scanner = [NSScanner scannerWithString:colorFloatString];
	float			factor = 1.0f;
	int				i;
	
	for (i = 0; i != 4; ++i)
	{
		if (![scanner scanFloat:&rgbaValue[i]])
		{
			// Less than three floats or non-float, can't parse -> quit
			if (i < 3) return nil;
			
			// If we get here, we only got three components. Make sure alpha is at correct scale:
			rgbaValue[3] /= factor;
		}
		if (1.0f < rgbaValue[i]) factor = 1.0f / 255.0f;
	}
	
	return [OOColor colorWithCalibratedRed:rgbaValue[0] * factor green:rgbaValue[1] * factor blue:rgbaValue[2] * factor alpha:rgbaValue[3] * factor];
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
	[color getGLRed:&rgba1[0] green:&rgba1[1] blue:&rgba1[2] alpha:&rgba1[3]];
	OOColor* result = [[OOColor alloc] init];
	float prime = 1.0f - fraction;
	[result setRGBA: prime * rgba[0] + fraction * rgba1[0] : prime * rgba[1] + fraction * rgba1[1] : prime * rgba[2] + fraction * rgba1[2] : prime * rgba[3] + fraction * rgba1[3]];
	return [result autorelease];
}


- (NSString *) descriptionComponents
{
	return [NSString stringWithFormat:@"%g, %g, %g, %g", rgba[0], rgba[1], rgba[2], rgba[3]];
}


// Get the red, green, or blue components.
- (OOCGFloat)redComponent
{
	return rgba[0];
}


- (OOCGFloat)greenComponent
{
	return rgba[1];
}


- (OOCGFloat)blueComponent
{
	return rgba[2];
}


- (void)getRed:(OOCGFloat *)red green:(OOCGFloat *)green blue:(OOCGFloat *)blue alpha:(OOCGFloat *)alpha
{
	NSParameterAssert(red != NULL && green != NULL && blue != NULL && alpha != NULL);
	
	*red = rgba[0];
	*green = rgba[1];
	*blue = rgba[2];
	*alpha = rgba[3];
}


- (void)getGLRed:(GLfloat *)red green:(GLfloat *)green blue:(GLfloat *)blue alpha:(GLfloat *)alpha
{
	NSParameterAssert(red != NULL && green != NULL && blue != NULL && alpha != NULL);
	
	*red = rgba[0];
	*green = rgba[1];
	*blue = rgba[2];
	*alpha = rgba[3];
}


- (OORGBAComponents)rgbaComponents
{
	OORGBAComponents c = { rgba[0], rgba[1], rgba[2], rgba[3] };
	return c;
}


- (BOOL)isBlack
{
	return rgba[0] == 0.0f && rgba[1] == 0.0f && rgba[2] == 0.0f;
}


- (BOOL)isWhite
{
	return rgba[0] == 1.0f && rgba[1] == 1.0f && rgba[2] == 1.0f && rgba[3] == 1.0f;
}


// Get the components as hue, saturation, or brightness.
- (OOCGFloat)hueComponent
{
	OOCGFloat maxrgb = (rgba[0] > rgba[1])? ((rgba[0] > rgba[2])? rgba[0]:rgba[2]):((rgba[1] > rgba[2])? rgba[1]:rgba[2]);
	OOCGFloat minrgb = (rgba[0] < rgba[1])? ((rgba[0] < rgba[2])? rgba[0]:rgba[2]):((rgba[1] < rgba[2])? rgba[1]:rgba[2]);
	if (maxrgb == minrgb)
		return 0.0;
	OOCGFloat delta = maxrgb - minrgb;
	OOCGFloat hue = 0.0;
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

- (OOCGFloat)saturationComponent
{
	OOCGFloat maxrgb = (rgba[0] > rgba[1])? ((rgba[0] > rgba[2])? rgba[0]:rgba[2]):((rgba[1] > rgba[2])? rgba[1]:rgba[2]);
	OOCGFloat minrgb = (rgba[0] < rgba[1])? ((rgba[0] < rgba[2])? rgba[0]:rgba[2]):((rgba[1] < rgba[2])? rgba[1]:rgba[2]);
	OOCGFloat brightness = 0.5 * (maxrgb + minrgb);
	if (maxrgb == minrgb)
		return 0.0;
	OOCGFloat delta = maxrgb - minrgb;
	return (brightness <= 0.5)? (delta / (maxrgb + minrgb)) : (delta / (2.0 - (maxrgb + minrgb)));
}

- (OOCGFloat)brightnessComponent
{
	OOCGFloat maxrgb = (rgba[0] > rgba[1])? ((rgba[0] > rgba[2])? rgba[0]:rgba[2]):((rgba[1] > rgba[2])? rgba[1]:rgba[2]);
	OOCGFloat minrgb = (rgba[0] < rgba[1])? ((rgba[0] < rgba[2])? rgba[0]:rgba[2]):((rgba[1] < rgba[2])? rgba[1]:rgba[2]);
	return 0.5 * (maxrgb + minrgb);
}

- (void)getHue:(OOCGFloat *)hue saturation:(OOCGFloat *)saturation brightness:(OOCGFloat *)brightness alpha:(OOCGFloat *)alpha
{
	NSParameterAssert(hue != NULL && saturation != NULL && brightness != NULL && alpha != NULL);
	
	*alpha = rgba[3];
	
	int maxrgb = (rgba[0] > rgba[1])? ((rgba[0] > rgba[2])? 0:2):((rgba[1] > rgba[2])? 1:2);
	int minrgb = (rgba[0] < rgba[1])? ((rgba[0] < rgba[2])? 0:2):((rgba[1] < rgba[2])? 1:2);
	*brightness = 0.5 * (rgba[maxrgb] + rgba[minrgb]);
	if (rgba[maxrgb] == rgba[minrgb])
	{
		*saturation = 0.0;
		*hue = 0.0;
		return;
	}
	OOCGFloat delta = rgba[maxrgb] - rgba[minrgb];
	*saturation = (*brightness <= 0.5)? (delta / (rgba[maxrgb] + rgba[minrgb])) : (delta / (2.0 - (rgba[maxrgb] + rgba[minrgb])));

	if (maxrgb==0)
		*hue = (rgba[1] - rgba[2]) / delta;
	else if (maxrgb==1)
		*hue = 2.0 + (rgba[2] - rgba[0]) / delta;
	else if (maxrgb==2)
		*hue = 4.0 + (rgba[0] - rgba[1]) / delta;
	*hue *= 60.0;
	while (*hue < 0.0) *hue += 360.0;
}


- (OOHSBAComponents)hsbaComponents
{
	OOHSBAComponents c;
	[self getHue:&c.h
	  saturation:&c.s
	  brightness:&c.b
		   alpha:&c.a];
	return c;
}


// Get the alpha component.
- (OOCGFloat)alphaComponent
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


- (NSArray *)normalizedArray
{
	OOCGFloat r, g, b, a;
	[self getRed:&r green:&g blue:&b alpha:&a];
	return [NSArray arrayWithObjects:
		[NSNumber numberWithDouble:r],
		[NSNumber numberWithDouble:g],
		[NSNumber numberWithDouble:b],
		[NSNumber numberWithDouble:a],
		nil];
}


- (NSString *)rgbaDescription
{
	return OORGBAComponentsDescription([self rgbaComponents]);
}


- (NSString *)hsbaDescription
{
	return OOHSBAComponentsDescription([self hsbaComponents]);
}

@end


NSString *OORGBAComponentsDescription(OORGBAComponents components)
{
	return [NSString stringWithFormat:@"{%.3g, %.3g, %.3g, %.3g}", components.r, components.g, components.b, components.a];
}


NSString *OOHSBAComponentsDescription(OOHSBAComponents components)
{
	return [NSString stringWithFormat:@"{%i, %.3g, %.3g, %.3g}", (int)components.h, components.s, components.b, components.a];
}
