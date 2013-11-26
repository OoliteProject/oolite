/*

OOVisualEffectEntity.m


Oolite
Copyright (C) 2004-2013 Giles C Williams and contributors

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
#import "OOStringExpander.h"
#import "OOCollectionExtractors.h"
#import "OOConstToString.h"
#import "OOConstToJSString.h"

#import "OOMesh.h"

#import "OOColor.h"
#import "OOPolygonSprite.h"

#import "OOFlasherEntity.h"

#import "OODebugGLDrawing.h"
#import "OODebugFlags.h"

#import "OOJSScript.h"

#import "OOFilteringEnumerator.h"

@interface OOVisualEffectEntity (Private)

- (void) drawSubEntityImmediate:(bool)immediate translucent:(bool)translucent;

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

	_haveExecutedSpawnAction = NO;

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

	collision_radius = 0.0;

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
	scaleX = 1.0;
	scaleY = 1.0;
	scaleZ = 1.0;

	[self clearSubEntities];
	[self setUpSubEntities];

	[self setScannerDisplayColor1:nil];
	[self setScannerDisplayColor2:nil];

	scanClass = CLASS_VISUAL_EFFECT;

	[self setStatus:STATUS_EFFECT];

	_hullHeatLevel = 60.0 / 256.0;
	_shaderFloat1 = 0.0;
	_shaderFloat2 = 0.0;
	_shaderInt1 = 0;
	_shaderInt2 = 0;
	_shaderVector1 = kZeroVector;
	_shaderVector2 = kZeroVector;

	[self setBeaconCode:[effectDict oo_stringForKey:@"beacon"]];
	[self setBeaconLabel:[effectDict oo_stringForKey:@"beacon_label" defaultValue:[self beaconCode]]];

	scriptInfo = [[effectDict oo_dictionaryForKey:@"script_info" defaultValue:nil] retain];
	[self setScript:[effectDict oo_stringForKey:@"script"]];

	return YES;

	OOJS_PROFILE_EXIT
}


- (void) dealloc
{
	[self clearSubEntities];
	DESTROY(_effectKey);
	DESTROY(effectinfoDictionary);
	DESTROY(scanner_display_color1);
	DESTROY(scanner_display_color2);
	DESTROY(scriptInfo);
	DESTROY(script);
	DESTROY(_beaconCode);
	DESTROY(_beaconLabel);
	DESTROY(_beaconDrawable);

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


- (NSString *)effectKey
{
	return _effectKey;
}


- (GLfloat)frustumRadius 
{
	return [self scaleMax] * _profileRadius;
}


- (void) clearSubEntities 
{
	[subEntities makeObjectsPerformSelector:@selector(setOwner:) withObject:nil];	// Ensure backlinks are broken
	[subEntities release];
	subEntities = nil;
	
	// reset size & mass!
	if ([self mesh])
	{
		collision_radius = [self findCollisionRadius];
	}
	else
	{
		collision_radius = 0.0;
	}
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

	[self setNoDrawDistance];

	return YES;
}


- (void) removeSubEntity:(Entity<OOSubEntity> *)sub
{
	[sub setOwner:nil];
	[subEntities removeObject:sub];
}


- (void) setNoDrawDistance
{
	GLfloat r = _profileRadius * [self scaleMax];
	no_draw_distance = r * r * NO_DRAW_DISTANCE_FACTOR * NO_DRAW_DISTANCE_FACTOR * 2.0;

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
	[flasher setPosition:[subentDict oo_hpvectorForKey:@"position"]];
	[self addSubEntity:flasher];
	return YES;
}


- (BOOL) setUpOneStandardSubentity:(NSDictionary *)subentDict 
{
	OOVisualEffectEntity			*subentity = nil;
	NSString			*subentKey = nil;
	HPVector				subPosition;
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
	
	subPosition = [subentDict oo_hpvectorForKey:@"position"];
	subOrientation = [subentDict oo_quaternionForKey:@"orientation"];
	
	[subentity setPosition:subPosition];
	[subentity setOrientation:subOrientation];
	
	[self addSubEntity:subentity];

	[subentity release];
	
	return YES;
}


- (void) addSubEntity:(Entity<OOSubEntity> *)sub
{
	if (sub == nil)  return;
	
	if (subEntities == nil)  subEntities = [[NSMutableArray alloc] init];
	sub->isSubEntity = YES;
	// Order matters - need consistent state in setOwner:. -- Ahruman 2008-04-20
	[subEntities addObject:sub];
	[sub setOwner:self];

	double distance = HPmagnitude([sub position]) + [sub findCollisionRadius];
	if (distance > _profileRadius)
	{
		_profileRadius = distance;
	}
}


- (NSArray *)subEntities 
{
	return [[subEntities copy] autorelease];
}


- (NSUInteger) subEntityCount
{
	return [subEntities count];
}


- (NSEnumerator *) visualEffectSubEntityEnumerator
{
	return [[self subEntities] objectEnumeratorFilteredWithSelector:@selector(isVisualEffect)];
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


- (void) drawSubEntityImmediate:(bool)immediate translucent:(bool)translucent
{
	if (cam_zero_distance > no_draw_distance) // this test provides an opportunity to do simple LoD culling
	{
		return; // TOO FAR AWAY
	}
	OOGL(glPushMatrix());
	// HPVect: camera position
	GLTranslateOOVector(HPVectorToVector(position));
	GLMultOOMatrix(rotMatrix);
	[self drawImmediate:immediate translucent:translucent];

	OOGL(glPopMatrix());
}


- (void) rescaleBy:(GLfloat)factor 
{
	if ([self mesh] != nil) {
		[self setMesh:[[self mesh] meshRescaledBy:factor]];
	}
	
	// rescale subentities
	Entity<OOSubEntity>	*se = nil;
	foreach (se, [self subEntities])
	{
		[se setPosition:HPvector_multiply_scalar([se position], factor)];
		[se rescaleBy:factor];
	}

	collision_radius *= factor;
	_profileRadius *= factor;
}


- (GLfloat) scaleMax
{
	GLfloat scale = 1.0;
	if (scaleX > scaleY)
	{
		if (scaleX > scaleZ)
		{
			scale *= scaleX;
		}
		else
		{
			scale *= scaleZ;
		}
	}
	else if (scaleY > scaleZ)
	{
		scale *= scaleY;
	}
	else
	{
		scale *= scaleZ;
	}
	return scale;
}

- (GLfloat) scaleX
{
	return scaleX;
}


- (void) setScaleX:(GLfloat)factor
{
	// rescale subentities
	Entity<OOSubEntity>	*se = nil;
	GLfloat flasher_factor = pow(factor/scaleX,1.0/3.0);
	foreach (se, [self subEntities])
	{
		HPVector move = [se position];
		move.x *= factor/scaleX;
		[se setPosition:move];
		if ([se isVisualEffect])
		{
			[(OOVisualEffectEntity*)se setScaleX:factor];
		}
		else
		{
			[se rescaleBy:flasher_factor];
		}
	}

	scaleX = factor;
	[self setNoDrawDistance];
}


- (GLfloat) scaleY
{
	return scaleY;
}


- (void) setScaleY:(GLfloat)factor
{
	// rescale subentities
	Entity<OOSubEntity>	*se = nil;
	GLfloat flasher_factor = pow(factor/scaleY,1.0/3.0);
	foreach (se, [self subEntities])
	{
		HPVector move = [se position];
		move.y *= factor/scaleY;
		[se setPosition:move];
		if ([se isVisualEffect])
		{
			[(OOVisualEffectEntity*)se setScaleY:factor];
		}
		else
		{
			[se rescaleBy:flasher_factor];
		}
	}

	scaleY = factor;
	[self setNoDrawDistance];
}


- (GLfloat) scaleZ
{
	return scaleZ;
}


- (void) setScaleZ:(GLfloat)factor
{
	// rescale subentities
	Entity<OOSubEntity>	*se = nil;
	GLfloat flasher_factor = pow(factor/scaleZ,1.0/3.0);
	foreach (se, [self subEntities])
	{
		HPVector move = [se position];
		move.z *= factor/scaleZ;
		[se setPosition:move];
		if ([se isVisualEffect])
		{
			[(OOVisualEffectEntity*)se setScaleZ:factor];
		}
		else
		{
			[se rescaleBy:flasher_factor];
		}
	}

	scaleZ = factor;
	[self setNoDrawDistance];
}


- (GLfloat) collisionRadius
{
	return [self scaleMax] * collision_radius;
}


- (void) orientationChanged
{
	[super orientationChanged];
	
	_v_forward   = vector_forward_from_quaternion(orientation);
	_v_up		= vector_up_from_quaternion(orientation);
	_v_right		= vector_right_from_quaternion(orientation);
}


// exposed to shaders
- (Vector) forwardVector
{
	return _v_forward;
}


// exposed to shaders
- (Vector) upVector
{
	return _v_up;
}


// exposed to shaders
- (Vector) rightVector
{
	return _v_right;
}


- (OOColor *)scannerDisplayColor1
{
	return [[scanner_display_color1 retain] autorelease];
}


- (OOColor *)scannerDisplayColor2
{
	return [[scanner_display_color2 retain] autorelease];
}


- (void)setScannerDisplayColor1:(OOColor *)color
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
}

static GLfloat default_color[4] =	{ 0.0, 0.0, 0.0, 0.0};
static GLfloat scripted_color[4] = 	{ 0.0, 0.0, 0.0, 0.0};

- (GLfloat *) scannerDisplayColorForShip:(BOOL)flash :(OOColor *)scannerDisplayColor1 :(OOColor *)scannerDisplayColor2
{
	
	if (scannerDisplayColor1 || scannerDisplayColor2)
	{
		if (scannerDisplayColor1 && !scannerDisplayColor2)
		{
			[scannerDisplayColor1 getRed:&scripted_color[0] green:&scripted_color[1] blue:&scripted_color[2] alpha:&scripted_color[3]];
		}
		
		if (!scannerDisplayColor1 && scannerDisplayColor2)
		{
			[scannerDisplayColor2 getRed:&scripted_color[0] green:&scripted_color[1] blue:&scripted_color[2] alpha:&scripted_color[3]];
		}
		
		if (scannerDisplayColor1 && scannerDisplayColor2)
		{
			if (flash)
				[scannerDisplayColor1 getRed:&scripted_color[0] green:&scripted_color[1] blue:&scripted_color[2] alpha:&scripted_color[3]];
			else
				[scannerDisplayColor2 getRed:&scripted_color[0] green:&scripted_color[1] blue:&scripted_color[2] alpha:&scripted_color[3]];
		}
		
		return scripted_color;
	}

	return default_color; // transparent black if not specified
}

- (void) drawImmediate:(bool)immediate translucent:(bool)translucent 
{
	if (no_draw_distance < cam_zero_distance)
	{
		return; // too far away to draw
	}
	OOGL(glPushMatrix());
	OOGL(glScalef(scaleX,scaleY,scaleZ));

	if ([self mesh] != nil)
	{
		[super drawImmediate:immediate translucent:translucent];
	}
	OOGL(glPopMatrix());

	// Draw subentities.
	if (!immediate)	// TODO: is this relevant any longer?
	{
		Entity<OOSubEntity> *subEntity = nil;
		foreach (subEntity, [self subEntities])
		{
			[subEntity drawSubEntityImmediate:immediate translucent:translucent];
		}
	}
}


- (void) update:(OOTimeDelta)delta_t
{
	[super update:delta_t];

	if (!_haveExecutedSpawnAction) {
		[self doScriptEvent:OOJSID("effectSpawned")];
		_haveExecutedSpawnAction = YES;
	}

	Entity *se = nil;
	foreach (se, [self subEntities])
	{
		[se update:delta_t];
	}
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


/* scripting */

- (void) setScript:(NSString *)script_name
{
	NSMutableDictionary		*properties = nil;
	
	properties = [NSMutableDictionary dictionary];
	[properties setObject:self forKey:@"visualEffect"];
	
	[script autorelease];
	script = [OOScript jsScriptFromFileNamed:script_name properties:properties];
	// does not support legacy scripting
	if (script == nil) {
		script = [OOScript jsScriptFromFileNamed:@"oolite-default-effect-script.js" properties:properties];
	}
	[script retain];
}


- (OOJSScript *)script
{
	return script;
}


- (NSDictionary *)scriptInfo
{
	return (scriptInfo != nil) ? scriptInfo : (NSDictionary *)[NSDictionary dictionary];
}

// unlikely to need events with arguments
- (void) doScriptEvent:(jsid)message
{
	JSContext *context = OOJSAcquireContext();
	[script callMethod:message inContext:context withArguments:NULL count:0 result:NULL];
	OOJSRelinquishContext(context);
}


- (void) remove
{
	[self doScriptEvent:OOJSID("effectRemoved")];
	[UNIVERSE removeEntity:(Entity*)self];
}


/* beacons */

- (NSComparisonResult) compareBeaconCodeWith:(Entity<OOBeaconEntity> *) other
{
	return [[self beaconCode] compare:[other beaconCode] options: NSCaseInsensitiveSearch];
}


- (NSString *) beaconCode
{
	return _beaconCode;
}


- (void) setBeaconCode:(NSString *)bcode
{
	if ([bcode length] == 0)  bcode = nil;
	
	if (_beaconCode != bcode)
	{
		[_beaconCode release];
		_beaconCode = [bcode copy];
		
		DESTROY(_beaconDrawable);
	}
	// if not blanking code and label is currently blank, default label to code
	if (bcode != nil && (_beaconLabel == nil || [_beaconLabel length] == 0))
	{
		[self setBeaconLabel:bcode];
	}

}


- (NSString *) beaconLabel
{
	return _beaconLabel;
}


- (void) setBeaconLabel:(NSString *)blabel
{
	if ([blabel length] == 0)  blabel = nil;
	
	if (_beaconLabel != blabel)
	{
		[_beaconLabel release];
		_beaconLabel = [OOExpand(blabel) retain];
	}
}


- (BOOL) isBeacon
{
	return [self beaconCode] != nil;
}


- (id <OOHUDBeaconIcon>) beaconDrawable
{
	if (_beaconDrawable == nil)
	{
		NSString	*beaconCode = [self beaconCode];
		NSUInteger	length = [beaconCode length];
		
		if (length > 1)
		{
			NSArray *iconData = [[UNIVERSE descriptions] oo_arrayForKey:beaconCode];
			if (iconData != nil)  _beaconDrawable = [[OOPolygonSprite alloc] initWithDataArray:iconData outlineWidth:0.5 name:beaconCode];
		}
		
		if (_beaconDrawable == nil)
		{
			if (length > 0)  _beaconDrawable = [[beaconCode substringToIndex:1] retain];
			else  _beaconDrawable = @"";
		}
	}
	
	return _beaconDrawable;
}


- (Entity <OOBeaconEntity> *) prevBeacon
{
	return [_prevBeacon weakRefUnderlyingObject];
}


- (Entity <OOBeaconEntity> *) nextBeacon
{
	return [_nextBeacon weakRefUnderlyingObject];
}


- (void) setPrevBeacon:(Entity <OOBeaconEntity> *)beaconShip
{
	if (beaconShip != [self prevBeacon])
	{
		[_prevBeacon release];
		_prevBeacon = [beaconShip weakRetain];
	}
}


- (void) setNextBeacon:(Entity <OOBeaconEntity> *)beaconShip
{
	if (beaconShip != [self nextBeacon])
	{
		[_nextBeacon release];
		_nextBeacon = [beaconShip weakRetain];
	}
}


- (BOOL) isJammingScanning 
{
	return NO;
}


/* Shader bindable uniforms */

// no automatic change of this, but simplifies use of default shader
- (GLfloat)hullHeatLevel
{
	return _hullHeatLevel;
}


- (void)setHullHeatLevel:(GLfloat)value
{
	_hullHeatLevel = OOClamp_0_1_f(value);
}


- (GLfloat) shaderFloat1 
{
	return _shaderFloat1;
}


- (void)setShaderFloat1:(GLfloat)value
{
	_shaderFloat1 = value;
}


- (GLfloat) shaderFloat2 
{
	return _shaderFloat2;
}


- (void)setShaderFloat2:(GLfloat)value
{
	_shaderFloat2 = value;
}


- (int) shaderInt1 
{
	return _shaderInt1;
}


- (void)setShaderInt1:(int)value
{
	_shaderInt1 = value;
}


- (int) shaderInt2 
{
	return _shaderInt2;
}


- (void)setShaderInt2:(int)value
{
	_shaderInt2 = value;
}


- (Vector) shaderVector1 
{
	return _shaderVector1;
}


- (void)setShaderVector1:(Vector)value
{
	_shaderVector1 = value;
}


- (Vector) shaderVector2 
{
	return _shaderVector2;
}


- (void)setShaderVector2:(Vector)value
{
	_shaderVector2 = value;
}


@end

@implementation OOVisualEffectEntity (SubEntityRelationship)

// a slightly misnamed test now things other than ships can have subents
- (BOOL) isShipWithSubEntityShip:(Entity *)other
{
	assert ([self isVisualEffect]);
	
	if (![other isVisualEffect])  return NO;
	if (![other isSubEntity])  return NO;
	if ([other owner] != self)  return NO;
	
#ifndef NDEBUG
	// Sanity check; this should always be true.
	if (![self hasSubEntity:(OOVisualEffectEntity *)other])
	{
		OOLogERR(@"visualeffect.subentity.sanityCheck.failed", @"%@ thinks it's a subentity of %@, but the supposed parent does not agree. %@", [other shortDescription], [self shortDescription], @"This is an internal error, please report it.");
		[other setOwner:nil];
		return NO;
	}
#endif
	
	return YES;
}

@end
