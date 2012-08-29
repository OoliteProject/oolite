/*

OOMaterialSpecifier.m

 
Copyright (C) 2010-2012 Jens Ayton

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

*/

#import "OOMaterialSpecifier.h"
#import "OOColor.h"
#import "OOCollectionExtractors.h"
#import "OOTexture.h"
#import "Universe.h"
#import "NSDictionaryOOExtensions.h"


NSString * const kOOMaterialDiffuseColorName				= @"diffuse_color";
NSString * const kOOMaterialDiffuseColorLegacyName			= @"diffuse";
NSString * const kOOMaterialAmbientColorName				= @"ambient_color";
NSString * const kOOMaterialAmbientColorLegacyName			= @"ambient";
NSString * const kOOMaterialSpecularColorName				= @"specular_color";
NSString * const kOOMaterialSpecularColorLegacyName			= @"specular";
NSString * const kOOMaterialSpecularModulateColorName		= @"specular_modulate_color";
NSString * const kOOMaterialEmissionColorName				= @"emission_color";
NSString * const kOOMaterialEmissionColorLegacyName			= @"emission";
NSString * const kOOMaterialEmissionModulateColorName		= @"emission_modulate_color";
NSString * const kOOMaterialIlluminationModulateColorName	= @"illumination_modulate_color";

NSString * const kOOMaterialDiffuseMapName					= @"diffuse_map";
NSString * const kOOMaterialSpecularColorMapName			= @"specular_color_map";
NSString * const kOOMaterialSpecularExponentMapName			= @"specular_exponent_map";
NSString * const kOOMaterialCombinedSpecularMapName			= @"specular_map";	// Combined specular_color_map and specular_exponent_map (unfortunate name required for backwards-compatibility).
NSString * const kOOMaterialNormalMapName					= @"normal_map";
NSString * const kOOMaterialParallaxMapName					= @"parallax_map";
NSString * const kOOMaterialNormalAndParallaxMapName		= @"normal_and_parallax_map";
NSString * const kOOMaterialEmissionMapName					= @"emission_map";
NSString * const kOOMaterialIlluminationMapName				= @"illumination_map";
NSString * const kOOMaterialEmissionAndIlluminationMapName	= @"emission_and_illumination_map";

NSString * const kOOMaterialParallaxScaleName				= @"parallax_scale";
NSString * const kOOMaterialParallaxBiasName				= @"parallax_bias";

NSString * const kOOMaterialSpecularExponentName			= @"specular_exponent";
NSString * const kOOMaterialSpecularExponentLegacyName		= @"shininess";

NSString * const kOOMaterialLightMapsName					= @"light_map";


@implementation NSDictionary (OOMateralProperties)

// Internal. Used to avoid mutual recusion between -oo_specularExponentMapSpecifier and -oo_specularExponent.
- (int) oo_rawSpecularExponentValue
{
	NSObject *value = [self objectForKey:kOOMaterialSpecularExponentName];
	if (value == nil)  value = [self objectForKey:kOOMaterialSpecularExponentLegacyName];
	return OOIntFromObject(value, -1);
}


- (OOColor *) oo_diffuseColor
{
	OOColor *result = [OOColor colorWithDescription:[self objectForKey:kOOMaterialDiffuseColorName]];
	if (result == nil)  result = [OOColor colorWithDescription:[self objectForKey:kOOMaterialDiffuseColorLegacyName]];
	
	if ([result isWhite])  result = nil;
	return result;
}


- (OOColor *) oo_ambientColor
{
	OOColor *result = [OOColor colorWithDescription:[self objectForKey:kOOMaterialAmbientColorName]];
	if (result == nil)  result = [OOColor colorWithDescription:[self objectForKey:kOOMaterialAmbientColorLegacyName]];
	return result;
}


- (OOColor *) oo_specularColor
{
	OOColor *result = [OOColor colorWithDescription:[self objectForKey:kOOMaterialSpecularColorName]];
	if (result == nil)  result = [OOColor colorWithDescription:[self objectForKey:kOOMaterialSpecularColorLegacyName]];
	if (result == nil)
	{
		result = [OOColor colorWithWhite:0.2f alpha:1.0f];
	}
	return result;
}


- (OOColor *) oo_specularModulateColor
{
	OOColor *result = [OOColor colorWithDescription:[self objectForKey:kOOMaterialSpecularModulateColorName]];
	if (result == nil)  result = [OOColor whiteColor];
	
	return result;
}


- (OOColor *) oo_emissionColor
{
	OOColor *result = [OOColor colorWithDescription:[self objectForKey:kOOMaterialEmissionColorName]];
	if (result == nil)  result = [OOColor colorWithDescription:[self objectForKey:kOOMaterialEmissionColorLegacyName]];
	
	if ([result isBlack])  result = nil;
	return result;
}


- (OOColor *) oo_emissionModulateColor
{
	OOColor *result = [OOColor colorWithDescription:[self objectForKey:kOOMaterialEmissionModulateColorName]];
	
	if ([result isWhite])  result = nil;
	return result;
}


- (OOColor *) oo_illuminationModulateColor
{
	OOColor *result = [OOColor colorWithDescription:[self objectForKey:kOOMaterialIlluminationModulateColorName]];
	
	if ([result isWhite])  result = nil;
	return result;
}


- (NSDictionary *) oo_diffuseMapSpecifierWithDefaultName:(NSString *)name
{
	return [self oo_textureSpecifierForKey:kOOMaterialDiffuseMapName defaultName:name];
}


- (NSDictionary *) oo_combinedSpecularMapSpecifier
{
	if ([self oo_rawSpecularExponentValue] == 0)  return nil;
	return [self oo_textureSpecifierForKey:kOOMaterialCombinedSpecularMapName defaultName:nil];
}


- (NSDictionary *) oo_specularColorMapSpecifier
{
	if ([self oo_rawSpecularExponentValue] == 0)  return nil;
	NSDictionary *result = [self oo_textureSpecifierForKey:kOOMaterialSpecularColorMapName defaultName:nil];
	if (result == nil)  result = [self oo_combinedSpecularMapSpecifier];
	return result;
}


- (NSDictionary *) oo_specularExponentMapSpecifier
{
	if ([self oo_rawSpecularExponentValue] == 0)  return nil;
	NSDictionary *result = [self oo_textureSpecifierForKey:kOOMaterialSpecularExponentMapName defaultName:nil];
	if (result == nil)  result = [[self oo_combinedSpecularMapSpecifier] dictionaryByAddingObject:@"a" forKey:@"extract_channel"];
	return result;
}


- (NSDictionary *) oo_normalMapSpecifier
{
	if ([self oo_normalAndParallaxMapSpecifier] != nil)  return nil;
	return [self oo_textureSpecifierForKey:kOOMaterialNormalMapName defaultName:nil];
}


- (NSDictionary *) oo_parallaxMapSpecifier
{
	id spec = [self oo_textureSpecifierForKey:kOOMaterialParallaxMapName defaultName:nil];
	if (spec == nil)
	{
		// Default is alpha channel of normal_and_parallax_map.
		spec = [[self oo_normalAndParallaxMapSpecifier] dictionaryByAddingObject:@"a"
																		  forKey:@"extract_channel"];
	}
	
	return spec;
}


- (NSDictionary *) oo_normalAndParallaxMapSpecifier
{
	return [self oo_textureSpecifierForKey:kOOMaterialNormalAndParallaxMapName defaultName:nil];
}


- (NSDictionary *) oo_emissionMapSpecifier
{
	return [self oo_textureSpecifierForKey:kOOMaterialEmissionMapName defaultName:nil];
}


- (NSDictionary *) oo_illuminationMapSpecifier
{
	return [self oo_textureSpecifierForKey:kOOMaterialIlluminationMapName defaultName:nil];
}


- (NSDictionary *) oo_emissionAndIlluminationMapSpecifier
{
	if ([self oo_emissionMapSpecifier] != nil || [self oo_illuminationMapSpecifier] != nil)  return nil;
	return [self oo_textureSpecifierForKey:kOOMaterialEmissionAndIlluminationMapName defaultName:nil];
}


- (float) oo_parallaxScale
{
	return [self oo_floatForKey:kOOMaterialParallaxScaleName defaultValue:kOOMaterialDefaultParallaxScale];
}


- (float) oo_parallaxBias
{
	return [self oo_floatForKey:kOOMaterialParallaxBiasName];
}


- (int) oo_specularExponent
{
	int result = [self oo_rawSpecularExponentValue];
	if (result < 0)
	{
		if ([UNIVERSE useShaders] && [self oo_specularExponentMapSpecifier] != nil)
		{
			result = 128;
		}
		else
		{
			result = 10;
		}
	}
	
	return result;
}

@end
