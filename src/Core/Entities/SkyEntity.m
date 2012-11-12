/*

SkyEntity.m

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


#import "SkyEntity.h"
#import "OOSkyDrawable.h"
#import "PlayerEntity.h"

#import "OOMaths.h"
#import "Universe.h"
#import "MyOpenGLView.h"
#import "OOColor.h"
#import "OOStringParsing.h"
#import "OOCollectionExtractors.h"
#import "OOMaterial.h"


#define SKY_BASIS_STARS			4800
#define SKY_BASIS_BLOBS			1280
#define SKY_clusterChance		0.80
#define SKY_alpha				0.10
#define SKY_scale				10.0


@interface SkyEntity (OOPrivate)

- (void)readColor1:(OOColor **)ioColor1 andColor2:(OOColor **)ioColor2 fromDictionary:(NSDictionary *)dictionary;

@end


@implementation SkyEntity

- (id) initWithColors:(OOColor *) col1:(OOColor *) col2 andSystemInfo:(NSDictionary *) systemInfo
{
	OOSkyDrawable			*skyDrawable;
	float					clusterChance,
							alpha,
							scale;
	signed					starCount,	// Need to be able to hold -1...
							nebulaCount;
	unsigned				starCountMultiplier, 
							nebulaCountMultiplier;
	
	self = [super init];
	if (self == nil)  return nil;
	
	// Load colours
	[self readColor1:&col1 andColor2:&col2 fromDictionary:systemInfo];
	
	skyColor = [[OOColor colorWithDescription:[systemInfo objectForKey:@"sun_color"]] retain];
	if (skyColor == nil)
	{
		skyColor = [[col2 blendedColorWithFraction:0.5 ofColor:col1] retain];
	}
	
	// Load distribution values
	clusterChance = [systemInfo oo_floatForKey:@"sky_blur_cluster_chance" defaultValue:SKY_clusterChance];
	alpha = [systemInfo oo_floatForKey:@"sky_blur_alpha" defaultValue:SKY_alpha];
	scale = [systemInfo oo_floatForKey:@"sky_blur_scale" defaultValue:SKY_scale];
	
	// Load star count
	starCount = [systemInfo oo_floatForKey:@"sky_n_stars" defaultValue:-1];
	starCountMultiplier = [systemInfo oo_unsignedIntForKey:@"star_count_multiplier" defaultValue:1];
	nebulaCountMultiplier = [systemInfo oo_unsignedIntForKey:@"nebula_count_multiplier" defaultValue:1];
	if (0 <= starCount)
	{
		// nothing
	}
	else
	{
		starCount = starCountMultiplier * SKY_BASIS_STARS * 0.5 * randf() * randf();
	}
	
	// ...and nebula count. (Note: simplifying this would change the appearance of stars/blobs.)
	nebulaCount = [systemInfo oo_floatForKey:@"sky_n_blurs" defaultValue:-1];
	if (0 <= nebulaCount)
	{
		// nothing
	}
	else
	{
		nebulaCount = nebulaCountMultiplier * SKY_BASIS_BLOBS * 0.5 * randf() * randf();
	}
	
	if ([UNIVERSE reducedDetail]) 
	{
		// limit stars and blobs to basis levels, and halve stars again
		if (starCount > SKY_BASIS_STARS)
		{
			starCount = SKY_BASIS_STARS;
		}
		starCount /= 2; 
		if (nebulaCount > SKY_BASIS_BLOBS)
		{
			nebulaCount = SKY_BASIS_BLOBS;
		}
	}
	
	skyDrawable = [[OOSkyDrawable alloc]
				   initWithColor1:col1
				   Color2:col2
				   starCount:starCount
				   nebulaCount:nebulaCount
				   clusterFactor:clusterChance
				   alpha:alpha
				   scale:scale];
	[self setDrawable:skyDrawable];
	[skyDrawable release];
	
	[self setStatus:STATUS_EFFECT];
	
	return self;
}


- (void) dealloc
{
	[skyColor release];
	
	[super dealloc];
}


- (OOColor *) skyColor
{
	return skyColor;
}


- (BOOL) changeProperty:(NSString *)key withDictionary:(NSDictionary*)dict
{
	id	object = [dict objectForKey:key];
	
	// TODO: properties requiring reInit?
	if ([key isEqualToString:@"sun_color"])
	{
		OOColor 	*col=[[OOColor colorWithDescription:object] retain];
		if (col != nil)
		{
			[skyColor release];
			skyColor = [col copy];
			[col release];
			[UNIVERSE setLighting];
		}
	}
	else
	{
		OOLogWARN(@"script.warning", @"Change to property '%@' not applied, will apply only on leaving and re-entering this system.",key);
		return NO;
	}
	return YES;
}


- (void) update:(OOTimeDelta) delta_t
{
	PlayerEntity *player = PLAYER;
	zero_distance = MAX_CLEAR_DEPTH * MAX_CLEAR_DEPTH;
	cam_zero_distance = zero_distance;
	if (player != nil) 
	{
		position = [player viewpointPosition];
	}
	else
	{
		OOLog(@"sky.warning",@"PLAYER is nil");
	}
}


- (BOOL) isSky
{
	return YES;
}


- (BOOL) isVisible
{
	return YES;
}


- (BOOL) canCollide
{
	return NO;
}


- (void) drawImmediate:(bool)immediate translucent:(bool)translucent
{
	if ([UNIVERSE breakPatternHide])  return;
	
	[super drawImmediate:immediate translucent:translucent];
	
	OOCheckOpenGLErrors(@"SkyEntity after drawing %@", self);
}


#ifndef NDEBUG
- (NSString *) descriptionForObjDump
{
	// Don't include range and visibility flag as they're irrelevant.
	return [self descriptionForObjDumpBasic];
}
#endif

@end


@implementation SkyEntity (OOPrivate)

- (void)readColor1:(OOColor **)ioColor1 andColor2:(OOColor **)ioColor2 fromDictionary:(NSDictionary *)dictionary
{
	NSString			*string = nil;
	NSArray				*tokens = nil;
	id					colorDesc = nil;
	OOColor				*color = nil;
	
	assert(ioColor1 != NULL && ioColor2 != NULL);
	
	string = [dictionary oo_stringForKey:@"sky_rgb_colors"];
	if (string != nil)
	{
		tokens = ScanTokensFromString(string);
		
		if ([tokens count] == 6)
		{
			float r1 = OOClamp_0_1_f([tokens oo_floatAtIndex:0]);
			float g1 = OOClamp_0_1_f([tokens oo_floatAtIndex:1]);
			float b1 = OOClamp_0_1_f([tokens oo_floatAtIndex:2]);
			float r2 = OOClamp_0_1_f([tokens oo_floatAtIndex:3]);
			float g2 = OOClamp_0_1_f([tokens oo_floatAtIndex:4]);
			float b2 = OOClamp_0_1_f([tokens oo_floatAtIndex:5]);
			*ioColor1 = [OOColor colorWithRed:r1 green:g1 blue:b1 alpha:1.0];
			*ioColor2 = [OOColor colorWithRed:r2 green:g2 blue:b2 alpha:1.0];
		}
		else
		{
			OOLogWARN(@"sky.fromDict", @"could not interpret \"%@\" as two RGB colours (must be six numbers).", string);
		}
	}
	colorDesc = [dictionary objectForKey:@"sky_color_1"];
	if (colorDesc != nil)
	{
		color = [[OOColor colorWithDescription:colorDesc] premultipliedColor];
		if (color != nil)  *ioColor1 = color;
		else  OOLogWARN(@"sky.fromDict", @"could not interpret \"%@\" as a colour.", colorDesc);
	}
	colorDesc = [dictionary objectForKey:@"sky_color_2"];
	if (colorDesc != nil)
	{
		color = [[OOColor colorWithDescription:colorDesc] premultipliedColor];
		if (color != nil)  *ioColor2 = color;
		else  OOLogWARN(@"sky.fromDict", @"could not interpret \"%@\" as a colour.", colorDesc);
	}
}

@end
