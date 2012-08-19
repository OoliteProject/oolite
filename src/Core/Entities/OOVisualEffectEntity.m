/*

OOVisualEffectEntity.m


Oolite
Copyright (C) 2004-2012 Giles C Williams and contributors

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the impllied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
MA 02110-1301, USA.

*/

#import "OOVisualEffectEntity.h"

#import "OOMaths.h"
#import "Universe.h"
#import "OOShaderMaterial.h"
#import "OOOpenGLExtensionManager.h"

#import "ResourceManager.h"
#import "OOStringParsing.h"
#import "OOCollectionExtractors.h"
#import "OOConstToString.h"
#import "OOConstToJSString.h"

#import "OOMesh.h"

#import "Geometry.h"
#import "Octree.h"
#import "OOColor.h"
#import "OOPolygonSprite.h"

#import "OOFlasherEntity.h"

#import "OODebugGLDrawing.h"
#import "OODebugFlags.h"

#import "OOJSScript.h"

#import "OOFilteringEnumerator.h"


@interface OOVisualEffectEntity (Private)

- (void) drawSubEntity:(BOOL) immediate :(BOOL) translucent;

- (void) addSubEntity:(Entity<OOSubEntity> *) subent;
- (BOOL) setUpOneSubentity:(NSDictionary *) subentDict;
- (BOOL) setUpOneFlasher:(NSDictionary *) subentDict;
- (BOOL) setUpOneStandardSubentity:(NSDictionary *)subentDict;

@end


@implementation OOVisualEffectEntity

- (id) init
{
	return [self initWithKey:@"" definition:nil];
}

- (id)initWithKey:(NSString *)key definition:(NSDictionary *)dict
{
	OOJS_PROFILE_ENTER
	
	NSParameterAssert(dict != nil);
	
	self = [super init];
	if (self == nil)  return nil;

	_effectKey = [key retain];

	if (![self setUpVisualEffectFromDictionary:dict])
	{
		[self release];
		self = nil;
	}

	collisionTestFilter = NO;

	return self;
	
	OOJS_PROFILE_EXIT
}


- (BOOL) setUpVisualEffectFromDictionary:(NSDictionary *) effectDict
{
	OOJS_PROFILE_ENTER

	effectinfoDictionary = [effectDict copy];
	if (effectinfoDictionary == nil)  effectinfoDictionary = [[NSDictionary alloc] init];

	orientation = kIdentityQuaternion;
	rotMatrix	= kIdentityMatrix;

	NSString *modelName = [effectDict oo_stringForKey:@"model"];
	if (modelName != nil)
	{
		OOMesh *mesh = [OOMesh meshWithName:modelName
								   cacheKey:_effectKey
						 materialDictionary:[effectDict oo_dictionaryForKey:@"materials"]
						  shadersDictionary:[effectDict oo_dictionaryForKey:@"shaders"]
									 smooth:[effectDict oo_boolForKey:@"smooth" defaultValue:NO]
							   shaderMacros:OODefaultShipShaderMacros()
						shaderBindingTarget:self];
		if (mesh == nil)  return NO;
		[self setMesh:mesh];
	}

	isImmuneToBreakPatternHide = [effectDict oo_boolForKey:@"is_break_pattern"];

	[self clearSubEntities];
	[self setUpSubEntities];

//	[self setScannerDisplayColor1:nil];
//	[self setScannerDisplayColor2:nil];

	scanClass = CLASS_NO_DRAW; // TODO: allow appearance on scanner?

	[self setStatus:STATUS_EFFECT];

	return YES;

	OOJS_PROFILE_EXIT
}


- (void) dealloc
{
	[self clearSubEntities];
	DESTROY(_effectKey);
	DESTROY(effectinfoDictionary);
//	DESTROY(scanner_display_color1);
//	DESTROY(scanner_display_color2);

	[super dealloc];
}


- (BOOL) isEffect
{
	return YES;
}


- (BOOL) isVisualEffect
{
	return YES;
}


- (BOOL) canCollide
{
	return NO;
}


- (OOMesh *)mesh 
{
	return (OOMesh *)[self drawable];
}


- (void)setMesh:(OOMesh *)mesh 
{
	if (mesh != [self mesh])
	{
		[self setDrawable:mesh];
	}
}


- (GLfloat)frustumRadius 
{
	return _profileRadius;
}


- (void) clearSubEntities 
{
	[subEntities makeObjectsPerformSelector:@selector(setOwner:) withObject:nil];	// Ensure backlinks are broken
	[subEntities release];
	subEntities = nil;
	
	// reset size & mass!
	collision_radius = [self findCollisionRadius];
	_profileRadius = collision_radius;
}


- (BOOL)setUpSubEntities 
{
	unsigned int	i;
	_profileRadius = collision_radius;
	NSArray *subs = [effectinfoDictionary oo_arrayForKey:@"subentities"];
	
	for (i = 0; i < [subs count]; i++)
	{
		[self setUpOneSubentity:[subs oo_dictionaryAtIndex:i]];
	}

	no_draw_distance = _profileRadius * _profileRadius * NO_DRAW_DISTANCE_FACTOR * NO_DRAW_DISTANCE_FACTOR * 2.0;

	return YES;
}

- (BOOL) setUpOneSubentity:(NSDictionary *) subentDict 
{
	NSString *type = [subentDict oo_stringForKey:@"type"];
	if ([type isEqualToString:@"flasher"])
	{
		return [self setUpOneFlasher:subentDict];
	}
	else
	{
		return [self setUpOneStandardSubentity:subentDict];
	}


}


- (BOOL) setUpOneFlasher:(NSDictionary *) subentDict
{
	OOFlasherEntity *flasher = [OOFlasherEntity flasherWithDictionary:subentDict];
	[flasher setPosition:[subentDict oo_vectorForKey:@"position"]];
	[self addSubEntity:flasher];
	return YES;
}


- (BOOL) setUpOneStandardSubentity:(NSDictionary *)subentDict 
{
	OOVisualEffectEntity			*subentity = nil;
	NSString			*subentKey = nil;
	Vector				subPosition;
	Quaternion			subOrientation;
	
	subentKey = [subentDict oo_stringForKey:@"subentity_key"];
	if (subentKey == nil) {
		OOLog(@"setup.visualeffect.badEntry.subentities",@"Failed to set up entity - no subentKey in %@",subentDict);
		return NO;
	}
	
	subentity = [UNIVERSE newVisualEffectWithName:subentKey];
	if (subentity == nil) {
		OOLog(@"setup.visualeffect.badEntry.subentities",@"Failed to set up entity %@",subentKey);
		return NO;
	}
	
	subPosition = [subentDict oo_vectorForKey:@"position"];
	subOrientation = [subentDict oo_quaternionForKey:@"orientation"];
	
	[subentity setPosition:subPosition];
	[subentity setOrientation:subOrientation];
	
	[self addSubEntity:subentity];

	[subentity release];
	
	return YES;
}


- (void) addSubEntity:(Entity<OOSubEntity> *) sub {
	if (sub == nil)  return;
	
	if (subEntities == nil)  subEntities = [[NSMutableArray alloc] init];
	sub->isSubEntity = YES;
	// Order matters - need consistent state in setOwner:. -- Ahruman 2008-04-20
	[subEntities addObject:sub];
	[sub setOwner:self];

	double distance = magnitude([sub position]) + [sub findCollisionRadius];
	if (distance > _profileRadius)
	{
		_profileRadius = distance;
	}
}


- (NSArray *)subEntities 
{
	return [[subEntities copy] autorelease];
}


- (unsigned) subEntityCount 
{
	return [subEntities count];
}


- (BOOL) hasSubEntity:(Entity<OOSubEntity> *)sub 
{
	return [subEntities containsObject:sub];
}


- (NSEnumerator *)subEntityEnumerator 
{
	return [[self subEntities] objectEnumerator];
}


- (NSEnumerator *)effectSubEntityEnumerator 
{
	return [[self subEntities] objectEnumeratorFilteredWithSelector:@selector(isVisualEffect)];
}


- (NSEnumerator *)flasherEnumerator 
{
	return [[self subEntities] objectEnumeratorFilteredWithSelector:@selector(isFlasher)];
}


- (void) drawSubEntity:(BOOL) immediate :(BOOL) translucent 
{
	if (cam_zero_distance > no_draw_distance) // this test provides an opportunity to do simple LoD culling
	{
		return; // TOO FAR AWAY
	}
	OOGL(glPushMatrix());
		
	GLTranslateOOVector(position);
	GLMultOOMatrix(rotMatrix);
	[self drawEntity:immediate :translucent];
	
	OOGL(glPopMatrix());
}


- (void) rescaleBy:(GLfloat)factor 
{
	[self setMesh:[[self mesh] meshRescaledBy:factor]];
	
	// rescale subentities
	Entity<OOSubEntity>	*se = nil;
	foreach (se, [self subEntities])
	{
		[se setPosition:vector_multiply_scalar([se position], factor)];
		[se rescaleBy:factor];
	}

}


/*- (void)setScannerDisplayColor1:(OOColor *)color
{
	DESTROY(scanner_display_color1);
	
	if (color == nil)  color = [OOColor colorWithDescription:[effectinfoDictionary objectForKey:@"scanner_display_color1"]];
	scanner_display_color1 = [color retain];
}


- (void)setScannerDisplayColor2:(OOColor *)color
{
	DESTROY(scanner_display_color2);
	
	if (color == nil)  color = [OOColor colorWithDescription:[effectinfoDictionary objectForKey:@"scanner_display_color2"]];
	scanner_display_color2 = [color retain];
	}*/


- (void)drawEntity:(BOOL)immediate :(BOOL)translucent
{
	if (no_draw_distance < cam_zero_distance)
	{
		return; // too far away to draw
	}
	[super drawEntity:immediate :translucent];

	// Draw subentities.
	if (!immediate)	// TODO: is this relevant any longer?
	{
		OOVisualEffectEntity *subEntity = nil;
		foreach (subEntity, [self subEntities])
		{
			[subEntity drawSubEntity:immediate :translucent];
		}
	}

}


- (void) update:(OOTimeDelta)delta_t
{
	[super update:delta_t];

	Entity *se = nil;
	foreach (se, [self subEntities])
	{
		[se update:delta_t];
	}
}


- (GLfloat)hullHeatLevel
{
	return 60.0 / 256.0;
}


- (BOOL) isBreakPattern
{
	return isImmuneToBreakPatternHide;
}


- (void) setIsBreakPattern:(BOOL)bp
{
	isImmuneToBreakPatternHide = bp;
}


- (NSDictionary *)effectInfoDictionary
{
	return effectinfoDictionary;
}


@end
