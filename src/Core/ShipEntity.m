/*

ShipEntity.m

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

#import "ShipEntity.h"
#import "ShipEntityAI.h"

#import "OOMaths.h"
#import "Universe.h"
#import "TextureStore.h"
#import "OOStringParsing.h"
#import "OOCollectionExtractors.h"
#import "OOConstToString.h"

#import "OOCharacter.h"
#import "OOBrain.h"
#import "AI.h"

#import "Geometry.h"
#import "Octree.h"
#import "NSScannerOOExtensions.h"
#import "OOColor.h"

#import "ParticleEntity.h"
#import "StationEntity.h"
#import "PlanetEntity.h"
#import "PlayerEntity.h"
#import "PlayerEntityLegacyScriptEngine.h"
#import "WormholeEntity.h"
#import "GuiDisplayGen.h"

#define kOOLogUnconvertedNSLog @"unclassified.ShipEntity"


extern NSString * const kOOLogNoteAddShips;
extern NSString * const kOOLogSyntaxAddShips;
static NSString * const kOOLogEntityBehaviourChanged	= @"entity.behaviour.changed";
static NSString * const kOOLogOpenGLVersion				= @"rendering.opengl.version";
static NSString * const kOOLogOpenGLShaderSupport		= @"rendering.opengl.shader.support";
static NSString * const kOOLogShaderInit				= @"rendering.opengl.shader.init";
static NSString * const kOOLogShaderInitDumpShader		= @"rendering.opengl.shader.init.dump.shader";
static NSString * const kOOLogShaderInitDumpTexture		= @"rendering.opengl.shader.init.dump.texture";
static NSString * const kOOLogShaderInitDumpShaderInfo	= @"rendering.opengl.shader.init.dump.shaderInfo";
static NSString * const	kOOLogShaderTextureNameMissing	= @"rendering.opengl.shader.texNameMissing";

#ifdef GNUSTEP
void loadOpenGLFunctions()
{
	glGetObjectParameterivARB = (PFNGLGETOBJECTPARAMETERIVARBPROC)wglGetProcAddress("glGetObjectParameterivARB");
	glCreateShaderObjectARB = (PFNGLCREATESHADEROBJECTARBPROC)wglGetProcAddress("glCreateShaderObjectARB");
	glGetInfoLogARB = (PFNGLGETINFOLOGARBPROC)wglGetProcAddress("glGetInfoLogARB");
	glCreateProgramObjectARB = (PFNGLCREATEPROGRAMOBJECTARBPROC)wglGetProcAddress("glCreateProgramObjectARB");
	glAttachObjectARB = (PFNGLATTACHOBJECTARBPROC)wglGetProcAddress("glAttachObjectARB");
	glDeleteObjectARB = (PFNGLDELETEOBJECTARBPROC)wglGetProcAddress("glDeleteObjectARB");
	glLinkProgramARB = (PFNGLLINKPROGRAMARBPROC)wglGetProcAddress("glLinkProgramARB");
	glCompileShaderARB = (PFNGLCOMPILESHADERARBPROC)wglGetProcAddress("glCompileShaderARB");
	glShaderSourceARB = (PFNGLSHADERSOURCEARBPROC)wglGetProcAddress("glShaderSourceARB");
	glUseProgramObjectARB = (PFNGLUSEPROGRAMOBJECTARBPROC)wglGetProcAddress("glUseProgramObjectARB");
	glActiveTextureARB = (PFNGLACTIVETEXTUREARBPROC)wglGetProcAddress("glActiveTextureARB");
	glGetUniformLocationARB = (PFNGLGETUNIFORMLOCATIONARBPROC)wglGetProcAddress("glGetUniformLocationARB");
	glUniform1iARB = (PFNGLUNIFORM1IARBPROC)wglGetProcAddress("glUniform1iARB");
	glUniform1fARB = (PFNGLUNIFORM1FARBPROC)wglGetProcAddress("glUniform1fARB");
}
#endif


static void ApplyConstantUniforms(NSDictionary *uniforms, GLhandleARB shaderProgram);


@implementation ShipEntity

- (id) init
{
	/*	-init used to set up a bunch of defaults that were different from
		those in -reinit and -setUpShipFromDictionary:. However, it seems that
		no ships are ever used which are not -setUpShipFromDictionary: (which
		is as it should be), so these different defaults were meaningless.
	*/
	return [self initWithDictionary:nil];
}


// Designated initializer
- (id) initWithDictionary:(NSDictionary *) dict
{
	self = [super init];
	
	isShip = YES;
	entity_personality = ranrot_rand() & 0x7FFF;
	
	zero_distance = SCANNER_MAX_RANGE2 * 2.0;
	weapon_recharge_rate = 6.0;
	shot_time = 100000.0;
	ship_temperature = 60.0;
	
	[self setUpShipFromDictionary:dict];
	return self;
}


- (void) setUpShipFromDictionary:(NSDictionary *) dict
{
	NSDictionary		*shipdict = dict;
	int					i;
	
	// Does this positional stuff need setting up here?
	// Either way, having four representations of orientation is dumb. Needs fixing. --Ahruman
    q_rotation = kIdentityQuaternion;
    quaternion_into_gl_matrix(q_rotation, rotMatrix);
	v_forward	= vector_forward_from_quaternion(q_rotation);
	v_up		= vector_up_from_quaternion(q_rotation);
	v_right		= vector_right_from_quaternion(q_rotation);
	reference	= v_forward;  // reference vector for (* turrets *)
	
	isShip = YES;
	
	// check if this is based upon a different ship
	for (;;)
	{
		// TODO: avoid reference loops.
		NSString		*other_shipdesc = [shipdict stringForKey:@"like_ship" defaultValue:nil];
		NSDictionary	*other_shipdict = [UNIVERSE getDictionaryForShip:other_shipdesc];
		if (other_shipdict == nil)  break;
		
		other_shipdesc = [other_shipdict objectForKey:@"like_ship"];
		
		NSMutableDictionary* this_shipdict = [NSMutableDictionary dictionaryWithDictionary:other_shipdict]; // basics from that one
		[this_shipdict addEntriesFromDictionary:shipdict];	// overrides from this one
		[this_shipdict setObject:other_shipdesc forKey:@"like_ship"];
		shipdict = this_shipdict;
	}
	
	shipinfoDictionary = [shipdict copy];
	shipdict = shipinfoDictionary;	// TEMP: ensure no mutation
	
	// set things from dictionary from here out
	max_flight_speed = [shipdict doubleForKey:@"max_flight_speed" defaultValue:0.0f];
	max_flight_roll = [shipdict doubleForKey:@"max_flight_roll" defaultValue:0.0f];
	max_flight_pitch = [shipdict doubleForKey:@"max_flight_pitch" defaultValue:0.0f];
	max_flight_yaw = [shipdict doubleForKey:@"max_flight_yaw" defaultValue:max_flight_pitch];	// Note by default yaw == pitch
	
	thrust = [shipdict doubleForKey:@"thrust" defaultValue:thrust];
	
	// This was integer percentages, made it floating point... I don't see any reason to limit the value's precision. -- Ahruman
	float accuracy = [shipdict doubleForKey:@"accuracy" defaultValue:-100];	// Out-of-range default
	if (accuracy >= -5.0f && accuracy <= 10.0f)
	{
		pitch_tolerance = 0.01 * (85.0f + accuracy);
	}
	else
	{
		// TODO: reimplement with randf(), or maybe bellf(). -- Ahruman
		pitch_tolerance = 0.01 * (80 +(ranrot_rand() & 15));
	}
	
	maxEnergy = [shipdict floatForKey:@"max_energy" defaultValue:0.0];
	energy_recharge_rate = [shipdict floatForKey:@"energy_recharge_rate" defaultValue:0.0];
	
	aft_weapon_type = StringToWeaponType([shipdict objectForKey:@"aft_weapon_type"]);
	forward_weapon_type = StringToWeaponType([shipdict objectForKey:@"forward_weapon_type"]);
	
	weapon_energy = [shipdict doubleForKey:@"weapon_energy" defaultValue:0.0];
	scanner_range = [shipdict doubleForKey:@"weapon_energy" defaultValue:25600.0];
	missiles = [shipdict doubleForKey:@"missiles" defaultValue:0];

	// upgrades:
	has_ecm = [shipdict fuzzyBooleanForKey:@"has_ecm" defaultValue:0.0];
	has_scoop = [shipdict fuzzyBooleanForKey:@"has_scoop" defaultValue:0.0];
	has_escape_pod = [shipdict fuzzyBooleanForKey:@"has_escape_pod" defaultValue:0.0];
	has_energy_bomb = [shipdict fuzzyBooleanForKey:@"has_energy_bomb" defaultValue:0.0];
	has_fuel_injection = [shipdict fuzzyBooleanForKey:@"has_fuel_injection" defaultValue:0.0];
	has_cloaking_device = [shipdict fuzzyBooleanForKey:@"has_cloaking_device" defaultValue:0.0];
	has_military_jammer = [shipdict fuzzyBooleanForKey:@"has_military_jammer" defaultValue:0.0];
	has_military_scanner_filter = [shipdict fuzzyBooleanForKey:@"has_military_scanner_filter" defaultValue:0.0];
	canFragment = [shipdict fuzzyBooleanForKey:@"fragment_chance" defaultValue:0.9];
	
	cloaking_device_active = NO;
	military_jammer_active = NO;
	
	if ([shipdict fuzzyBooleanForKey:@"has_shield_booster" defaultValue:0.0])
	{
		maxEnergy += 256.0f;
	}
	if ([shipdict fuzzyBooleanForKey:@"has_shield_enhancer" defaultValue:0.0])
	{
		maxEnergy += 256.0f;
		energy_recharge_rate *= 1.5;
	}
	
	// Moved here from above upgrade loading so that ships start with full energy banks. -- Ahruman
	energy = maxEnergy;
	
	fuel = [shipdict intForKey:@"fuel" defaultValue:0];	// Does it make sense that this defaults to 0? Should it not be 70? -- Ahruman
	fuel_accumulator = 1.0;
	
	bounty = [shipdict intForKey:@"bounty" defaultValue:0];
	
	[shipAI autorelease];
	shipAI = [[AI alloc] init];
	[shipAI setStateMachine:[shipdict stringForKey:@"ai_type" defaultValue:@"nullAI.plist"]];
	
	max_cargo = [shipdict intForKey:@"max_cargo" defaultValue:0];
	likely_cargo = [shipdict intForKey:@"likely_cargo" defaultValue:0];
	extra_cargo = [shipdict intForKey:@"extra_cargo" defaultValue:15];
	
	if ([shipdict objectForKey:@"cargo_carried"])
	{
		cargo_flag = CARGO_FLAG_FULL_UNIFORM;

		[self setCommodity:NSNotFound andAmount:0];
		int c_commodity = NSNotFound;
		int c_amount = 1;
		NSScanner*	scanner = [NSScanner scannerWithString: [shipdict objectForKey:@"cargo_carried"]];
		if ([scanner scanInt: &c_amount])
		{
			[scanner ooliteScanCharactersFromSet:[NSCharacterSet whitespaceCharacterSet] intoString:NULL];	// skip whitespace
			c_commodity = [UNIVERSE commodityForName: [[scanner string] substringFromIndex:[scanner scanLocation]]];
		}
		else
		{
			c_amount = 1;
			c_commodity = [UNIVERSE commodityForName: (NSString*)[shipdict objectForKey:@"cargo_carried"]];
		}

		if (c_commodity != NSNotFound)  [self setCommodity:c_commodity andAmount:c_amount];
	}
	
	if ([shipdict objectForKey:@"cargo_type"])
	{
		cargo_type = StringToCargoType([shipdict objectForKey:@"cargo_type"]);
		
		[cargo autorelease];
		cargo = [[NSMutableArray alloc] initWithCapacity:max_cargo]; // alloc retains;
	}
	
	// A HACK!! - must do this before the model is set
	isSmoothShaded = [shipdict boolForKey:@"smooth" defaultValue:NO];
	
	// must do this next one before checking subentities
	NSString *modelName = [shipdict stringForKey:@"model" defaultValue:nil];
	if (modelName != nil)  [self setModelName:modelName];
	
	float density = [shipdict floatForKey:@"density" defaultValue:1.0];
	if (octree)  mass = density * 20.0 * [octree volume];
	
	[name release];
	name = [[shipdict stringForKey:@"name" defaultValue:nil] copy];
	
	[roles release];
	roles = [[shipdict stringForKey:@"roles" defaultValue:nil] copy];
	
	[self setOwner:self];
	
	NSArray *plumes = [shipdict arrayForKey:@"exhaust" defaultValue:nil];
	for (i = 0; i < [plumes count]; i++)
	{
		ParticleEntity *exhaust = [[ParticleEntity alloc] initExhaustFromShip:self details:[plumes objectAtIndex:i]];
		[self addExhaust:exhaust];
		[exhaust release];
	}
	
	is_hulk = [shipdict boolForKey:@"is_hulk" defaultValue:NO];
	
	NSArray *subs = [shipdict arrayForKey:@"subentities" defaultValue:nil];
	for (i = 0; i < [subs count]; i++)
	{
		NSArray *details = ScanTokensFromString([subs objectAtIndex:i]);

		if ([details count] == 8)
		{
			Vector sub_pos, ref;
			Quaternion sub_q;
			Entity* subent;
			NSString* subdesc = (NSString *)[details objectAtIndex:0];
			sub_pos.x = [(NSString *)[details objectAtIndex:1] floatValue];
			sub_pos.y = [(NSString *)[details objectAtIndex:2] floatValue];
			sub_pos.z = [(NSString *)[details objectAtIndex:3] floatValue];
			sub_q.w = [(NSString *)[details objectAtIndex:4] floatValue];
			sub_q.x = [(NSString *)[details objectAtIndex:5] floatValue];
			sub_q.y = [(NSString *)[details objectAtIndex:6] floatValue];
			sub_q.z = [(NSString *)[details objectAtIndex:7] floatValue];

			if ([subdesc isEqual:@"*FLASHER*"])
			{
				subent = [[ParticleEntity alloc] init];	// retained
				[(ParticleEntity*)subent setColor:[OOColor colorWithCalibratedHue: sub_q.w/360.0 saturation:1.0 brightness:1.0 alpha:1.0]];
				[(ParticleEntity*)subent setDuration: sub_q.x];
				[(ParticleEntity*)subent setEnergy: 2.0 * sub_q.y];
				[(ParticleEntity*)subent setSize:NSMakeSize( sub_q.z, sub_q.z)];
				[(ParticleEntity*)subent setParticleType:PARTICLE_FLASHER];
				[(ParticleEntity*)subent setStatus:STATUS_EFFECT];
				[(ParticleEntity*)subent setPosition:sub_pos];
			}
			else
			{
				quaternion_normalize(&sub_q);

				subent = [UNIVERSE newShipWithName:subdesc];	// retained

				if ((self->isStation)&&([subdesc rangeOfString:@"dock"].location != NSNotFound))
					[(StationEntity*)self setDockingPortModel:(ShipEntity*)subent :sub_pos :sub_q];

				if (subent)
				{
					[(ShipEntity*)subent setStatus:STATUS_INACTIVE];
					//
					ref = vector_forward_from_quaternion(sub_q);	// VECTOR FORWARD
					//
					[(ShipEntity*)subent setReference: ref];
					[(ShipEntity*)subent setPosition: sub_pos];
					[(ShipEntity*)subent setQRotation: sub_q];
					//
					[self addSolidSubentityToCollisionRadius:(ShipEntity*)subent];
					//
					subent->isSubentity = YES;
				}
				//
			}
			if (sub_entities == nil)
				sub_entities = [[NSArray arrayWithObject:subent] retain];
			else
			{
				NSMutableArray *temp = [NSMutableArray arrayWithArray:sub_entities];
				[temp addObject:subent];
				[sub_entities release];
				sub_entities = [[NSArray arrayWithArray:temp] retain];
			}

			[subent setOwner: self];

			[subent release];
		}
	}
	
	isFrangible = [shipdict boolForKey:@"frangible" defaultValue:YES];
	
	OOColor *color = [OOColor brightColorWithDescription:[shipdict objectForKey:@"laser_color"]];
	if (color == nil)  color = [OOColor redColor];
	[self setLaserColor:color];
	
	// scan class
	scanClass = StringToScanClass([shipdict objectForKey:@"scanClass"]);
	
	// scripting
	// TODO: use OOScript here. -- Ahruman
	launch_actions = [[shipdict arrayForKey:KEY_LAUNCH_ACTIONS defaultValue:nil] copy];
	script_actions = [[shipdict arrayForKey:KEY_LAUNCH_ACTIONS defaultValue:nil] copy];
	death_actions = [[shipdict arrayForKey:KEY_LAUNCH_ACTIONS defaultValue:nil] copy];
	NSArray *setUpActions = [shipdict arrayForKey:KEY_SETUP_ACTIONS defaultValue:nil];
	if (setUpActions != nil)
	{
		PlayerEntity* player = [PlayerEntity sharedPlayer];
		[player setScript_target:self];
		[player scriptActions:setUpActions forTarget:self];
	}
	
	//  escorts
	n_escorts = [shipdict intForKey:@"escorts" defaultValue:0];
	escortsAreSetUp = (n_escorts == 0);

	// beacons
	NSString *beaconCode = [shipdict stringForKey:@"beacon" defaultValue:nil];
	if (beaconCode == nil)  beaconChar = '\0';
	else  beaconChar = [beaconCode lossyCString][0];
	
	// rotating subentities
	subentityRotationalVelocity = kIdentityQuaternion;
	ScanQuaternionFromString([shipdict objectForKey:@"rotational_velocity"], &subentityRotationalVelocity);

	// contact tracking entities
	//
	if ([shipdict objectForKey:@"track_contacts"])
	{
		[self setTrackCloseContacts:[[shipdict objectForKey:@"track_contacts"] boolValue]];
		// DEBUG....
		[self setReportAImessages:YES];
	}
	else
	{
		[self setTrackCloseContacts:NO];
	}

	// set weapon offsets
	[self setDefaultWeaponOffsets];
	//
	ScanVectorFromString([shipdict objectForKey:@"weapon_position_forward"], &forwardWeaponOffset);
	ScanVectorFromString([shipdict objectForKey:@"weapon_position_aft"], &aftWeaponOffset);
	ScanVectorFromString([shipdict objectForKey:@"weapon_position_port"], &portWeaponOffset);
	ScanVectorFromString([shipdict objectForKey:@"weapon_position_starboard"], &starboardWeaponOffset);

	// fuel scoop destination position (where cargo gets sucked into)
	tractor_position = kZeroVector;
	ScanVectorFromString([shipdict objectForKey:@"scoop_position"], &tractor_position);

	// ship skin insulation factor (1.0 is normal)
	heat_insulation = [shipdict doubleForKey:@"heat_insulation"	defaultValue:1.0];
		
	// crew and passengers
	NSDictionary* cdict = [[UNIVERSE characters] objectForKey:[shipdict stringForKey:@"pilot" defaultValue:nil]];
	if (cdict != nil)
	{
		OOCharacter	*pilot = [OOCharacter characterWithDictionary:cdict];
		[self setCrew:[NSArray arrayWithObject:pilot]];
	}
	
	// unpiloted (like missiles asteroids etc.)
	if ([shipdict fuzzyBooleanForKey:@"unpiloted" defaultValue:0.0f])  [self setCrew:nil];
}


- (void) dealloc
{
	[self setTrackCloseContacts:NO];	// deallocs tracking dictionary

	[shipinfoDictionary release];
	[shipAI release];
	[cargo release];
	[name release];
	[roles release];
	[sub_entities release];
	[laser_color release];
	//scripting
	[launch_actions release];
	[script_actions release];
	[death_actions release];

	[previousCondition release];

	[dockingInstructions release];

	[crew release];

	[lastRadioMessage autorelease];

	[octree autorelease];
	
	[shader_info release];

	[super dealloc];
}


- (NSString*) description
{
	if (debug & DEBUG_ENTITIES)
	{
		NSMutableString* result = [NSMutableString stringWithFormat:@"\n<%@ %@ %d>", [self class], name, universalID];
		[result appendFormat:@"\n isPlayer: %@", (isPlayer)? @"YES":@"NO"];
		[result appendFormat:@"\n isShip: %@", (isShip)? @"YES":@"NO"];
		[result appendFormat:@"\n isStation: %@", (isStation)? @"YES":@"NO"];
		[result appendFormat:@"\n isSubentity: %@", (isSubentity)? @"YES":@"NO"];
		[result appendFormat:@"\n canCollide: %@", ([self canCollide])? @"YES":@"NO"];
		[result appendFormat:@"\n behaviour: %d %@", behaviour, BehaviourToString(behaviour)];
		[result appendFormat:@"\n status: %d %@", status, EntityStatusToString(status)];
		[result appendFormat:@"\n collisionRegion: %@", collisionRegion];
		return result;
	}
	else
		return [NSString stringWithFormat:@"<%@ %@ %d>", [self class], name, universalID];
}

- (void) setOctree:(Octree*) oct
{
	[octree release];
	octree = [oct retain];
}


- (void) setModelName:(NSString*) modelName
{
	NS_DURING
		[super setModelName:modelName];
	NS_HANDLER
		if ([[localException name] isEqual: OOLITE_EXCEPTION_DATA_NOT_FOUND])
		{
			OOLog(kOOLogException, @"***** Oolite Data Not Found Exception : '%@' in [ShipEntity setModelName:] *****", [localException reason]);
		}
		[localException raise];
	NS_ENDHANDLER
	
	Octree *newOctree;
	newOctree = [OOCacheManager octreeForModel:modelName];
	if (newOctree == nil)
	{
		newOctree = [[self geometry] findOctreeToDepth: OCTREE_MAX_DEPTH];
		[OOCacheManager setOctree:newOctree forModel:modelName];
	}
	
	[self setOctree:newOctree];
}

// ship's brains!
- (OOBrain*)	brain
{
	return brain;
}

- (void)		setBrain:(OOBrain*) aBrain
{
	brain = aBrain;
}


- (GLfloat) doesHitLine:(Vector) v0: (Vector) v1;
{
	Vector u0 = vector_between(position, v0);	// relative to origin of model / octree
	Vector u1 = vector_between(position, v1);
	Vector w0 = make_vector( dot_product( u0, v_right), dot_product( u0, v_up), dot_product( u0, v_forward));	// in ijk vectors
	Vector w1 = make_vector( dot_product( u1, v_right), dot_product( u1, v_up), dot_product( u1, v_forward));
	return [octree isHitByLine:w0 :w1];
}

- (GLfloat) doesHitLine:(Vector) v0: (Vector) v1 :(ShipEntity**) hitEntity;
{
	if (hitEntity)
		hitEntity[0] = (ShipEntity*)nil;
	Vector u0 = vector_between(position, v0);	// relative to origin of model / octree
	Vector u1 = vector_between(position, v1);
	Vector w0 = make_vector( dot_product( u0, v_right), dot_product( u0, v_up), dot_product( u0, v_forward));	// in ijk vectors
	Vector w1 = make_vector( dot_product( u1, v_right), dot_product( u1, v_up), dot_product( u1, v_forward));
	GLfloat hit_distance = [octree isHitByLine:w0 :w1];
	if (hit_distance)
	{
		if (hitEntity)
			hitEntity[0] = self;
	}
	if (sub_entities)
	{
		int n_subs = [sub_entities count];
		int i;
		for (i = 0; i < n_subs; i++)
		{
			ShipEntity* se = [sub_entities objectAtIndex:i];
			if (se->isShip)
			{
				Vector p0 = [se absolutePositionForSubentity];
				Triangle ijk = [se absoluteIJKForSubentity];
				u0 = vector_between( p0, v0);
				u1 = vector_between( p0, v1);
				w0 = resolveVectorInIJK( u0, ijk);
				w1 = resolveVectorInIJK( u1, ijk);
				GLfloat hitSub = [se->octree isHitByLine:w0 :w1];
				if ((hitSub)&&((!hit_distance)||(hit_distance > hitSub)))
				{	
					hit_distance = hitSub;
					if (hitEntity)
						hitEntity[0] = se;
				}
			}
		}
	}
	return hit_distance;
}

- (GLfloat) doesHitLine:(Vector) v0: (Vector) v1 withPosition:(Vector) o andIJK:(Vector) i :(Vector) j :(Vector) k;
{
	Vector u0 = vector_between( o, v0);	// relative to origin of model / octree
	Vector u1 = vector_between( o, v1);
	Vector w0 = make_vector( dot_product( u0, i), dot_product( u0, j), dot_product( u0, k));	// in ijk vectors
	Vector w1 = make_vector( dot_product( u1, j), dot_product( u1, j), dot_product( u1, k));
	return [octree isHitByLine:w0 :w1];
}


- (void) wasAddedToUniverse
{
	[super wasAddedToUniverse];
	
	// if we have a universal id then we can proceed to set up any
	// stuff that happens when we get added to the UNIVERSE
	if (universalID != NO_TARGET)
	{
		// set up escorts
		//
		if (status == STATUS_IN_FLIGHT)	// just popped into existence
		{
			if ((!escortsAreSetUp)&&(n_escorts > 0))
				[self setUpEscorts];
		}
		else
		{
			escortsAreSetUp = YES;	// we don't do this ourself!
		}
	}

	//	Tell subentities, too
	NSEnumerator	*subEntityEnum;
	Entity			*subEntity;
	
	for (subEntityEnum = [sub_entities objectEnumerator]; (subEntity = [subEntityEnum nextObject]); )
	{
		[subEntity wasAddedToUniverse];
	}
	
	[self resetTracking];	// resets stuff for tracking/exhausts
}


- (void) wasRemovedFromUniverse
{
	NSEnumerator	*subEntityEnum;
	Entity			*subEntity;
	
	for (subEntityEnum = [sub_entities objectEnumerator]; (subEntity = [subEntityEnum nextObject]); )
	{
		[subEntity wasRemovedFromUniverse];
	}
}


- (Vector)	absoluteTractorPosition
{
	Vector result = position;
	result.x += v_right.x * tractor_position.x + v_up.x * tractor_position.y + v_forward.x * tractor_position.z;
	result.y += v_right.y * tractor_position.x + v_up.y * tractor_position.y + v_forward.y * tractor_position.z;
	result.z += v_right.z * tractor_position.x + v_up.z * tractor_position.y + v_forward.z * tractor_position.z;
	return result;
}

- (NSString*)	beaconCode
{
	return (NSString*)[shipinfoDictionary objectForKey:@"beacon"];
}

- (BOOL)	isBeacon
{
	return (beaconChar != 0);
}

- (char)	beaconChar
{
	return beaconChar;
}

- (void)	setBeaconChar:(char) bchar
{
	beaconChar = bchar;
}

- (int)		nextBeaconID
{
	return nextBeaconID;
}

- (void)	setNextBeacon:(ShipEntity*) beaconShip
{
	if (beaconShip == nil)
		nextBeaconID = NO_TARGET;
	else
		nextBeaconID = [beaconShip universalID];
}

- (void) setUpEscorts
{
	NSString *escortRole = @"escort";
	NSString *escortShipKey = nil;

	if ([roles isEqual:@"trader"])
		escortRole = @"escort";

	if ([roles isEqual:@"police"])
		escortRole = @"wingman";

	if ([shipinfoDictionary objectForKey:@"escort-role"])
	{
		escortRole = (NSString*)[shipinfoDictionary objectForKey:@"escort-role"];
		if (![[UNIVERSE newShipWithRole:escortRole] autorelease])
			escortRole = @"escort";
	}

	if ([shipinfoDictionary objectForKey:@"escort-ship"])
	{
		escortShipKey = (NSString*)[shipinfoDictionary objectForKey:@"escort-ship"];
		if (![[UNIVERSE newShipWithName:escortShipKey] autorelease])
			escortShipKey = nil;
	}

//	NSLog(@"DEBUG Setting up escorts for %@", self);

	while (n_escorts > 0)
	{
		Vector ex_pos = [self getCoordinatesForEscortPosition:n_escorts - 1];

		ShipEntity *escorter;

		if (escortShipKey)
			escorter = [UNIVERSE newShipWithName:escortShipKey];	// retained
		else
			escorter = [UNIVERSE newShipWithRole:escortRole];	// retained

		if (!escorter)
			break;

		if (![escorter crew])
			[escorter setCrew:[NSArray arrayWithObject:
				[OOCharacter randomCharacterWithRole: @"hunter"
				andOriginalSystem: [UNIVERSE systemSeed]]]];
				
		// spread them around a little randomly
		double dd = escorter->collision_radius;
		ex_pos.x += dd * 6.0 * (randf() - 0.5);
		ex_pos.y += dd * 6.0 * (randf() - 0.5);
		ex_pos.z += dd * 6.0 * (randf() - 0.5);


		[escorter setScanClass: CLASS_NEUTRAL];
		[escorter setPosition:ex_pos];

		[escorter setStatus:STATUS_IN_FLIGHT];

		[escorter setRoles:escortRole];

		[escorter setScanClass:scanClass];		// you are the same as I

		//[escorter setReportAImessages: (i == 0) ? YES:NO ]; // debug

		[UNIVERSE addEntity:escorter];
		[[escorter getAI] setStateMachine:@"escortAI.plist"];	// must happen after adding to the UNIVERSE!

		[escorter setGroup_id:universalID];
		[self setGroup_id:universalID];		// make self part of same group

		[escorter setOwner: self];	// make self group leader

		[[escorter getAI] setState:@"FLYING_ESCORT"];	// begin immediately

		if (bounty)
		{
			int extra = 1 | (ranrot_rand() & 15);
			bounty += extra;	// obviously we're dodgier than we thought!
			[escorter setBounty: extra];
//			NSLog(@"DEBUG setting bounty for %@ escorting %@ to %d", escorter, self, extra);

//			[escorter setReportAImessages: YES ]; // debug
		}
		else
		{
			[escorter setBounty:0];
		}

//		NSLog(@"DEBUG set up escort ship %@ for %@", escorter, self);

		[escorter release];
		n_escorts--;
	}
}


- (void) rescaleBy:(GLfloat) factor
{
	// rescale vertices and rebuild vertex arrays
	//
	int i;
	for (i = 0; i < n_vertices; i++)
	{
		vertices[i].x *= factor;
		vertices[i].y *= factor;
		vertices[i].z *= factor;
	}
	[self setUpVertexArrays];
	usingVAR = [self OGL_InitVAR];
	if (usingVAR)
		[self OGL_AssignVARMemory:sizeof(EntityData) :(void *)&entityData :0];
	
	// rescale the collision radii & bounding box
	//
	collision_radius *= factor;
	actual_radius *= factor;
	boundingBox.min.x *= factor;
	boundingBox.min.y *= factor;
	boundingBox.min.z *= factor;
	boundingBox.max.x *= factor;
	boundingBox.max.y *= factor;
	boundingBox.max.z *= factor;

	// rescale octree
	//
	[self setOctree:[octree octreeScaledBy: factor]];
	
	// rescale positions of subentities
	//
	int n_subs = [sub_entities count];
	for (i = 0; i < n_subs; i++)
	{
		Entity* se = (Entity*)[sub_entities objectAtIndex:i];
		se->position.x *= factor;
		se->position.y *= factor;
		se->position.z *= factor;
		
		// rescale ship subentities
		if (se->isShip)
			[(ShipEntity*)se rescaleBy: factor];
		
		// rescale particle subentities
		if (se->isParticle)
		{
			ParticleEntity* pe = (ParticleEntity*)se;
			NSSize sz = [pe size];
			sz.width *= factor;
			sz.height *= factor;
			[pe setSize: sz];
		}
	}
	
	// rescale mass
	//
	mass *= factor * factor * factor;
	
}


- (NSDictionary*)	 shipInfoDictionary
{
	return shipinfoDictionary;
}


- (void) setDefaultWeaponOffsets
{
	forwardWeaponOffset = kZeroVector;
	aftWeaponOffset = kZeroVector;
	portWeaponOffset = kZeroVector;
	starboardWeaponOffset = kZeroVector;
}


- (BOOL)isFrangible
{
	return isFrangible;
}


- (BOOL)isCloaked
{
	return cloaking_device_active;
}


- (OOScanClass) scanClass
{
	if (cloaking_device_active)
		return CLASS_NO_DRAW;
	else
		return scanClass;
}

//////////////////////////////////////////////

BOOL ship_canCollide (ShipEntity* ship)
{
	int		s_status =		ship->status;
	int		s_scan_class =	ship->scanClass;
	if ((s_status == STATUS_COCKPIT_DISPLAY)||(s_status == STATUS_DEAD)||(s_status == STATUS_BEING_SCOOPED))
		return NO;
	if ((s_scan_class == CLASS_MISSILE) && (ship->shot_time < 0.25)) // not yet fused
		return NO;
	return YES;
}

- (BOOL) canCollide
{
	return ship_canCollide(self);
}

ShipEntity* doOctreesCollide(ShipEntity* prime, ShipEntity* other)
{
	// octree check
	Octree* prime_octree = prime->octree;
	Octree* other_octree = other->octree;
	
	Vector prime_position = prime->position;

	Triangle prime_ijk;
	prime_ijk.v[0] = prime->v_right;
	prime_ijk.v[1] = prime->v_up;
	prime_ijk.v[2] = prime->v_forward;
	
	if (prime->isSubentity)
	{
		prime_position = [prime absolutePositionForSubentity];
		prime_ijk = [prime absoluteIJKForSubentity];
	}
	
	Vector other_position = other->position;
	
	Triangle other_ijk;
	other_ijk.v[0] = other->v_right;
	other_ijk.v[1] = other->v_up;
	other_ijk.v[2] = other->v_forward;
	
	if (other->isSubentity)
	{
		other_position = [other absolutePositionForSubentity];
		other_ijk = [other absoluteIJKForSubentity];
	}

	Vector		relative_position_of_other = resolveVectorInIJK( vector_between(prime_position, other_position), prime_ijk);
	Triangle	relative_ijk_of_other;
	relative_ijk_of_other.v[0] = resolveVectorInIJK( other_ijk.v[0], prime_ijk);
	relative_ijk_of_other.v[1] = resolveVectorInIJK( other_ijk.v[1], prime_ijk);
	relative_ijk_of_other.v[2] = resolveVectorInIJK( other_ijk.v[2], prime_ijk);
	
	// check hull octree against other hull octree
	//
	if ([prime_octree isHitByOctree: other_octree withOrigin: relative_position_of_other andIJK: relative_ijk_of_other])
		return other;
		
	// check prime subentities against the other's hull
	//
	NSArray* prime_subs = prime->sub_entities;
	if (prime_subs)
	{
		int i;
		int n_subs = [prime_subs count];
		for (i = 0; i < n_subs; i++)
		{
			Entity* se = (Entity*)[prime_subs objectAtIndex:i];
			if ((se->isShip) && [se canCollide] && doOctreesCollide( (ShipEntity*)se, other))
				return other;
		}
	}

	// check prime hull against the other's subentities
	//
	NSArray* other_subs = other->sub_entities;
	if (other_subs)
	{
		int i;
		int n_subs = [other_subs count];
		for (i = 0; i < n_subs; i++)
		{
			Entity* se = (Entity*)[other_subs objectAtIndex:i];
			if ((se->isShip) && [se canCollide] && doOctreesCollide( prime, (ShipEntity*)se))
				return (ShipEntity*)se;
		}
	}

	// check prime subenties against the other's subentities
	//
	if ((prime_subs)&&(other_subs))
	{
		int i;
		int n_osubs = [other_subs count];
		for (i = 0; i < n_osubs; i++)
		{
			Entity* oe = (Entity*)[other_subs objectAtIndex:i];
			if ((oe->isShip) && [oe canCollide])
			{
				int j;
				int n_psubs = [prime_subs count];
				for (j = 0; j <  n_psubs; j++)
				{
					Entity* pe = (Entity*)[prime_subs objectAtIndex:j];
					if ((pe->isShip) && [pe canCollide] && doOctreesCollide( (ShipEntity*)pe, (ShipEntity*)oe))
						return (ShipEntity*)oe;
				}
			}
		}
	}

	// fall through => no collision
	//
	return (ShipEntity*)nil;
}

- (BOOL) checkCloseCollisionWith:(Entity *)other
{
	if (!other)
		return NO;
	if ([collidingEntities containsObject:other])	// we know about this already!
		return NO;

	if ((other->isShip)&&[self canScoop: (ShipEntity*)other])	// quick test - could this improve scooping for small ships? I think so!
		return YES;

	if (trackCloseContacts)
	{
		// in update we check if close contacts have gone out of touch range (origin within our collision_radius)
		// here we check if something has come within that range
		NSString* other_key = [NSString stringWithFormat:@"%d", other->universalID];
		if ((![closeContactsInfo objectForKey: other_key]) && (distance2( position, other->position) < collision_radius * collision_radius))
		{
			// calculate position with respect to our own position and orientation
			Vector	dpos = vector_between( position, other->position);
			Vector  rpos = make_vector( dot_product(dpos, v_right), dot_product(dpos, v_up), dot_product(dpos, v_forward));
			[closeContactsInfo setObject:[NSString stringWithFormat:@"%f %f %f", rpos.x, rpos.y, rpos.z] forKey: other_key];
			// send AI a message about the touch
			int	temp_id = primaryTarget;
			primaryTarget = other->universalID;
			[shipAI reactToMessage:@"CLOSE CONTACT"];
			primaryTarget = temp_id;
		}
	}

	if (zero_distance > CLOSE_COLLISION_CHECK_MAX_RANGE2)	// don't work too hard on entities that are far from the player
		return YES;

	if (other->isShip)
	{
		// check hull octree versus other hull octree
		//
		collider = doOctreesCollide( self, (ShipEntity*)other);
		return (collider != nil);
	}
	
	// default at this stage is to say YES they've collided!
	//
	collider = other;
	return YES;
}

- (BOOL) checkBoundingBoxCollisionWith:(Entity *)other
{
	if (other->isShip)
	{
		// check bounding boxes ...
		//
		// get bounding box relative to this ship's orientation
		BoundingBox arbb = [other findBoundingBoxRelativeTo:self InVectors: v_right: v_up: v_forward];

		// construct 6 rectangles based on the sides of the possibly overlapping bounding boxes
		NSRect  other_x_rect = NSMakeRect(arbb.min.z, arbb.min.y, arbb.max.z - arbb.min.z, arbb.max.y - arbb.min.y);
		NSRect  other_y_rect = NSMakeRect(arbb.min.x, arbb.min.z, arbb.max.x - arbb.min.x, arbb.max.z - arbb.min.z);
		NSRect  other_z_rect = NSMakeRect(arbb.min.x, arbb.min.y, arbb.max.x - arbb.min.x, arbb.max.y - arbb.min.y);

		NSRect  ship_x_rect = NSMakeRect(boundingBox.min.z, boundingBox.min.y, boundingBox.max.z - boundingBox.min.z, boundingBox.max.y - boundingBox.min.y);
		NSRect  ship_y_rect = NSMakeRect(boundingBox.min.x, boundingBox.min.z, boundingBox.max.x - boundingBox.min.x, boundingBox.max.z - boundingBox.min.z);
		NSRect  ship_z_rect = NSMakeRect(boundingBox.min.x, boundingBox.min.y, boundingBox.max.x - boundingBox.min.x, boundingBox.max.y - boundingBox.min.y);

		if (NSIntersectsRect(ship_x_rect,other_x_rect) && NSIntersectsRect(ship_y_rect,other_y_rect) && NSIntersectsRect(ship_z_rect,other_z_rect))
			return YES;
		else
			return NO;
	}
	if (other->isParticle)
	{
		// check bounding boxes ...
		//
		// get position relative to this ship's orientation
		Vector	r_pos = other->position;
		double	cr = other->collision_radius;
		r_pos.x -= position.x;	r_pos.y -= position.y;	r_pos.z -= position.z;
		if	((r_pos.x + cr > boundingBox.min.x)&&
				(r_pos.x - cr < boundingBox.max.x)&&
				(r_pos.y + cr > boundingBox.min.y)&&
				(r_pos.y - cr < boundingBox.max.y)&&
				(r_pos.z + cr > boundingBox.min.z)&&
				(r_pos.z - cr < boundingBox.max.z))
			return YES;
		else
			return NO;
	}
	return YES;
}

- (BOOL) subentityCheckBoundingBoxCollisionWith:(Entity *)other
{
//	NSLog(@"DEBUG [%@ subentityCheckBoundingBoxCollisionWith:%@]", self, other);

	BoundingBox sebb = [self findSubentityBoundingBox];

//	NSLog(@"DEBUG bounding box for subentity: %@ [%.1fm %.1fm]x [%.1fm %.1fm]y [%.1fm %.1fm]z", self,
//		sebb.min.x, sebb.max.x, sebb.min.y, sebb.max.y, sebb.min.z, sebb.max.z);

	if (other->isShip)
	{
		// check bounding boxes ...
		Entity* parent = [self owner];
		if (!parent)
			return NO;
		Vector i = vector_right_from_quaternion(parent->q_rotation);
		Vector j = vector_up_from_quaternion(parent->q_rotation);
		Vector k = vector_forward_from_quaternion(parent->q_rotation);

		//
		// get bounding box relative to this ship's orientation
		BoundingBox arbb = [other findBoundingBoxRelativeTo:parent InVectors: i: j: k];

//		NSLog(@"DEBUG bounding box for other: %@ [%.1fm %.1fm]x [%.1fm %.1fm]y [%.1fm %.1fm]z", other,
//			arbb.min.x, arbb.max.x, arbb.min.y, arbb.max.y, arbb.min.z, arbb.max.z);

		// construct 6 rectangles based on the sides of the possibly overlapping bounding boxes
		NSRect  x_rect = NSMakeRect(sebb.min.z, sebb.min.y, sebb.max.z - sebb.min.z, sebb.max.y - sebb.min.y);
		NSRect  y_rect = NSMakeRect(sebb.min.x, sebb.min.z, sebb.max.x - sebb.min.x, sebb.max.z - sebb.min.z);
		NSRect  z_rect = NSMakeRect(sebb.min.x, sebb.min.y, sebb.max.x - sebb.min.x, sebb.max.y - sebb.min.y);
		NSRect  other_x_rect = NSMakeRect(arbb.min.z, arbb.min.y, arbb.max.z - arbb.min.z, arbb.max.y - arbb.min.y);
		NSRect  other_y_rect = NSMakeRect(arbb.min.x, arbb.min.z, arbb.max.x - arbb.min.x, arbb.max.z - arbb.min.z);
		NSRect  other_z_rect = NSMakeRect(arbb.min.x, arbb.min.y, arbb.max.x - arbb.min.x, arbb.max.y - arbb.min.y);

//		NSLog(@"DEBUG intersects in x:%@: y:%@: z:%@",
//			NSIntersectsRect(x_rect,other_x_rect)? @"YES": @"NO ",
//			NSIntersectsRect(y_rect,other_y_rect)? @"YES": @"NO ",
//			NSIntersectsRect(z_rect,other_z_rect)? @"YES": @"NO ");

		if (NSIntersectsRect(x_rect,other_x_rect) && NSIntersectsRect(y_rect,other_y_rect) && NSIntersectsRect(z_rect,other_z_rect))
			return YES;
		else
			return NO;
	}
	if (other->isParticle)
	{
		// check bounding boxes ...
		//
		// get position relative to this ship's orientation
		Vector	r_pos = other->position;
		double	cr = other->collision_radius;
		r_pos.x -= position.x;	r_pos.y -= position.y;	r_pos.z -= position.z;
		if	((r_pos.x + cr > sebb.min.x)&&
				(r_pos.x - cr < sebb.max.x)&&
				(r_pos.y + cr > sebb.min.y)&&
				(r_pos.y - cr < sebb.max.y)&&
				(r_pos.z + cr > sebb.min.z)&&
				(r_pos.z - cr < sebb.max.z))
			return YES;
		else
			return NO;
	}
	return YES;
}

- (BoundingBox) findSubentityBoundingBox
{
	BoundingBox result;
	Vector  v = vertices[0];
	mult_vector_gl_matrix(&v, rotMatrix);
	v.x += position.x;	v.y += position.y;	v.z += position.z;
	bounding_box_reset_to_vector(&result,v);
	int i;
    for (i = 1; i < n_vertices; i++)
    {
		v = vertices[i];
		mult_vector_gl_matrix(&v, rotMatrix);
		v.x += position.x;	v.y += position.y;	v.z += position.z;
		bounding_box_add_vector(&result,v);
    }

//	NSLog(@"DEBUG subentity bounding box for %@ of %@ is [%.1fm %.1fm]x [%.1fm %.1fm]y [%.1fm %.1fm]z", self, [self owner],
//		result.min.x, result.max.x, result.min.y, result.max.y, result.min.z, result.max.z);

	return result;
}

- (BoundingBox) findSubentityBoundingBoxRelativeTo: (Entity*)other inVectors: (Vector)vi: (Vector)vj: (Vector)vk
{
	Entity* parent = [self owner];
	Vector	othpos = other->position;
	Vector	parent_pos = parent->position;
	Vector	relpos = make_vector( parent_pos.x - othpos.x, parent_pos.y - othpos.y, parent_pos.z - othpos.z);
	GLfloat*	parent_rotmatrix = [parent drawRotationMatrix];
	BoundingBox result;
	Vector	v,	w;
	v = vertices[0];
	mult_vector_gl_matrix(&v, rotMatrix);
	v.x += position.x;	v.y += position.y;	v.z += position.z;
	mult_vector_gl_matrix(&v, parent_rotmatrix);
	v.x += relpos.x;	v.y += relpos.y;	v.z += relpos.z;
	w = make_vector( dot_product( v, vi), dot_product( v, vj), dot_product( v, vk));
	bounding_box_reset_to_vector(&result,w);
	int i;
    for (i = 1; i < n_vertices; i++)
    {
		v = vertices[i];
		mult_vector_gl_matrix(&v, rotMatrix);
		v.x += position.x;	v.y += position.y;	v.z += position.z;
		mult_vector_gl_matrix(&v, parent_rotmatrix);
		v.x += relpos.x;	v.y += relpos.y;	v.z += relpos.z;
		w = make_vector( dot_product( v, vi), dot_product( v, vj), dot_product( v, vk));
		bounding_box_add_vector(&result,w);
    }

	return result;
}

- (BoundingBox) findSubentityBoundingBoxRelativeToPosition: (Vector)othpos inVectors: (Vector)vi: (Vector)vj: (Vector)vk
{
	Entity* parent = [self owner];
	Vector	parent_pos = parent->position;
	Vector	relpos = make_vector( parent_pos.x - othpos.x, parent_pos.y - othpos.y, parent_pos.z - othpos.z);
	GLfloat*	parent_rotmatrix = [parent drawRotationMatrix];
	BoundingBox result;
	Vector	v,	w;
	v = vertices[0];
	mult_vector_gl_matrix(&v, rotMatrix);
	v.x += position.x;	v.y += position.y;	v.z += position.z;
	mult_vector_gl_matrix(&v, parent_rotmatrix);
	v.x += relpos.x;	v.y += relpos.y;	v.z += relpos.z;
	w = make_vector( dot_product( v, vi), dot_product( v, vj), dot_product( v, vk));
	bounding_box_reset_to_vector(&result,w);
	int i;
    for (i = 1; i < n_vertices; i++)
    {
		v = vertices[i];
		mult_vector_gl_matrix(&v, rotMatrix);
		v.x += position.x;	v.y += position.y;	v.z += position.z;
		mult_vector_gl_matrix(&v, parent_rotmatrix);
		v.x += relpos.x;	v.y += relpos.y;	v.z += relpos.z;
		w = make_vector( dot_product( v, vi), dot_product( v, vj), dot_product( v, vk));
		bounding_box_add_vector(&result,w);
    }
	return result;
}


- (Vector) absolutePositionForSubentity
{
	Vector		abspos = position;
	Entity*		last = nil;
	Entity*		father = [self owner];
	while ((father)&&(father != last))
	{
		GLfloat* r_mat = [father drawRotationMatrix];
		mult_vector_gl_matrix(&abspos, r_mat);
		Vector pos = father->position;
		abspos.x += pos.x;	abspos.y += pos.y;	abspos.z += pos.z;
		last = father;
		father = [father owner];
	}
	return abspos;
}

- (Vector) absolutePositionForSubentityOffset:(Vector) offset
{

	Vector		off = offset;
	mult_vector_gl_matrix(&off, rotMatrix);
	Vector		abspos = make_vector( position.x + off.x, position.y + off.y, position.z + off.z);
	Entity*		last = nil;
	Entity*		father = [self owner];
	while ((father)&&(father != last))
	{
		GLfloat* r_mat = [father drawRotationMatrix];
		mult_vector_gl_matrix(&abspos, r_mat);
		Vector pos = father->position;
		abspos.x += pos.x;	abspos.y += pos.y;	abspos.z += pos.z;
		last = father;
		father = [father owner];
	}
	return abspos;
}

- (Triangle) absoluteIJKForSubentity;
{
	Triangle	result;
	result.v[0] = make_vector( 1.0, 0.0, 0.0);
	result.v[1] = make_vector( 0.0, 1.0, 0.0);
	result.v[2] = make_vector( 0.0, 0.0, 1.0);
	Entity*		last = nil;
	Entity*		father = self;
	while ((father)&&(father != last))
	{
		GLfloat* r_mat = [father drawRotationMatrix];
		mult_vector_gl_matrix(&result.v[0], r_mat);
		mult_vector_gl_matrix(&result.v[1], r_mat);
		mult_vector_gl_matrix(&result.v[2], r_mat);
		last = father;
		father = [father owner];
	}
	return result;
}

- (void) addSolidSubentityToCollisionRadius:(ShipEntity*) subent
{
	if (!subent)
		return;

	double distance = sqrt(magnitude2(subent->position)) + [subent findCollisionRadius];
	if (distance > collision_radius)
		collision_radius = distance;
	
	mass += 20.0 * [subent->octree volume];
}


- (void) update:(double) delta_t
{
	if (shipinfoDictionary == nil)
	{
		OOLog(@"shipEntity.notDict", @"Ship %@ was not set up from dictionary.", self);
	}
	
	//
	// deal with collisions
	//
	[self manageCollisions];
	[self saveToLastFrame];
	
	//
	// reset any inadvertant legal mishaps
	//
	if (scanClass == CLASS_POLICE)
	{
		if (bounty > 0)
			bounty = 0;
		ShipEntity* targEnt = (ShipEntity*)[UNIVERSE entityForUniversalID:primaryTarget];
		if ((targEnt)&&(targEnt->scanClass == CLASS_POLICE))
		{
			primaryTarget = NO_TARGET;
			[shipAI reactToMessage:@"TARGET_LOST"];
		}
	}
	//

	if (trackCloseContacts)
	{
		// in checkCloseCollisionWith: we check if some thing has come within touch range (origin within our collision_radius)
		// here we check if it has gone outside that range
		NSArray* shipIDs = [closeContactsInfo allKeys];
		int i = 0;
		int n_ships = [shipIDs count];
		for (i = 0; i < n_ships; i++)
		{
			NSString*	other_key = (NSString*)[shipIDs objectAtIndex:i];
			ShipEntity* other = (ShipEntity*)[UNIVERSE entityForUniversalID:[other_key intValue]];
			if ((other != nil) && (other->isShip))
			{
				if (distance2( position, other->position) > collision_radius * collision_radius)	// moved beyond our sphere!
				{
					// calculate position with respect to our own position and orientation
					Vector	dpos = vector_between( position, other->position);
					Vector  pos1 = make_vector( dot_product(dpos, v_right), dot_product(dpos, v_up), dot_product(dpos, v_forward));
					Vector	pos0 = {0, 0, 0};
					ScanVectorFromString([closeContactsInfo objectForKey: other_key], &pos0);
					// send AI messages about the contact
					int	temp_id = primaryTarget;
					primaryTarget = other->universalID;
					if ((pos0.x < 0.0)&&(pos1.x > 0.0))
						[shipAI reactToMessage:@"POSITIVE X TRAVERSE"];
					if ((pos0.x > 0.0)&&(pos1.x < 0.0))
						[shipAI reactToMessage:@"NEGATIVE X TRAVERSE"];
					if ((pos0.y < 0.0)&&(pos1.y > 0.0))
						[shipAI reactToMessage:@"POSITIVE Y TRAVERSE"];
					if ((pos0.y > 0.0)&&(pos1.y < 0.0))
						[shipAI reactToMessage:@"NEGATIVE Y TRAVERSE"];
					if ((pos0.z < 0.0)&&(pos1.z > 0.0))
						[shipAI reactToMessage:@"POSITIVE Z TRAVERSE"];
					if ((pos0.z > 0.0)&&(pos1.z < 0.0))
						[shipAI reactToMessage:@"NEGATIVE Z TRAVERSE"];
					primaryTarget = temp_id;
					[closeContactsInfo removeObjectForKey: other_key];
				}
			}
			else
				[closeContactsInfo removeObjectForKey: other_key];
		}
	}
	
	// think!
	if (brain)
		[brain update:delta_t];

	// super update
	//
	[super update:delta_t];

	// DEBUGGING
	//
	if (reportAImessages && (debug_condition != behaviour))
	{
		OOLog(kOOLogEntityBehaviourChanged, @"%@ behaviour is now %@", self, BehaviourToString(behaviour));
		debug_condition = behaviour;
	}

	// update time between shots
	//
	shot_time +=delta_t;

	// handle radio message effects
	//
	if (message_time > 0.0)
	{
		message_time -= delta_t;
		if (message_time < 0.0)
			message_time = 0.0;
	}

	// temperature factors
	//
	double external_temp = 0.0;
	if ([UNIVERSE sun])
	{
		PlanetEntity* sun = [UNIVERSE sun];
		// set the ambient temperature here
		double  sun_zd = magnitude2(vector_between( position, sun->position));	// square of distance
		double  sun_cr = sun->collision_radius;
		double	alt1 = sun_cr * sun_cr / sun_zd;
		external_temp = SUN_TEMPERATURE * alt1;
		if ([sun goneNova])
			external_temp *= 100;
	}

	// work on the ship temperature
	//
	if (external_temp > ship_temperature)
		ship_temperature += (external_temp - ship_temperature) * delta_t * SHIP_INSULATION_FACTOR / heat_insulation;
	else
	{
		if (ship_temperature > SHIP_MIN_CABIN_TEMP)
			ship_temperature += (external_temp - ship_temperature) * delta_t * SHIP_COOLING_FACTOR / heat_insulation;
	}

	if (ship_temperature > SHIP_MAX_CABIN_TEMP)
		[self takeHeatDamage: delta_t * ship_temperature];

	// are we burning due to low energy
	if ((energy < maxEnergy * 0.20)&&(energy_recharge_rate > 0.0))	// prevents asteroid etc. from burning
		throw_sparks = YES;

	// burning effects
	//
	if (throw_sparks)
	{
		next_spark_time -= delta_t;
		if (next_spark_time < 0.0)
		{
			[self throwSparks];
			throw_sparks = NO;	// until triggered again
		}
	}

	// cloaking device
	if (has_cloaking_device)
	{
		if (cloaking_device_active)
		{
			energy -= delta_t * CLOAKING_DEVICE_ENERGY_RATE;
			if (energy < CLOAKING_DEVICE_MIN_ENERGY)
				[self deactivateCloakingDevice];
		}
		else
		{
			if (energy < maxEnergy)
			{
				energy += delta_t * CLOAKING_DEVICE_ENERGY_RATE;
				if (energy > maxEnergy)
				{
					energy = maxEnergy;
					[shipAI message:@"ENERGY_FULL"];
				}
			}
		}
	}

	// military_jammer
	if (has_military_jammer)
	{
		if (military_jammer_active)
		{
			energy -= delta_t * MILITARY_JAMMER_ENERGY_RATE;
			if (energy < MILITARY_JAMMER_MIN_ENERGY)
				military_jammer_active = NO;
		}
		else
		{
			if (energy > 1.5 * MILITARY_JAMMER_MIN_ENERGY)
				military_jammer_active = YES;
		}
	}

	// check outside factors
	//
	aegis_status = [self checkForAegis];   // is a station or something nearby??

	//scripting
	if (launch_actions != nil && status == STATUS_IN_FLIGHT)
	{
		[[PlayerEntity sharedPlayer] setScript_target:self];
		[[PlayerEntity sharedPlayer] scriptActions:launch_actions forTarget:self];
		[launch_actions release];
		launch_actions = nil;
	}

	// behaviours according to status and behaviour
    //
	if (status == STATUS_LAUNCHING)
	{
		if ([UNIVERSE getTime] > launch_time + LAUNCH_DELAY)		// move for while before thinking
		{
			status = STATUS_IN_FLIGHT;
			[shipAI reactToMessage: @"LAUNCHED OKAY"];
			//accepts_escorts = YES;
		}
		else
		{
			// ignore behaviour just keep moving...
			[self applyRoll:delta_t*flight_roll andClimb:delta_t*flight_pitch];
			[self applyThrust:delta_t];
			if (energy < maxEnergy)
			{
				energy += energy_recharge_rate * delta_t;
				if (energy > maxEnergy)
				{
					energy = maxEnergy;
					[shipAI message:@"ENERGY_FULL"];
				}
			}
			if (sub_entities)
			{
				int i;
				for (i = 0; i < [sub_entities count]; i++)
					[(Entity *)[sub_entities objectAtIndex:i] update:delta_t];
			}
			return;
		}
	}
	//
	// double check scooped behaviour
	//
	if (status == STATUS_BEING_SCOOPED)
	{
		if (behaviour != BEHAVIOUR_TRACTORED)
		{
			// escaped tractor beam
			status = STATUS_IN_FLIGHT;	// should correct 'uncollidable objects' bug
			behaviour = BEHAVIOUR_IDLE;
			frustration = 0.0;
		}
	}
	//
	if (status == STATUS_COCKPIT_DISPLAY)
    {
		[self applyRoll: delta_t * flight_roll andClimb: delta_t * flight_pitch];
		GLfloat range2 = 0.1 * distance2( position, destination) / (collision_radius * collision_radius);
		if ((range2 > 1.0)||(velocity.z > 0.0))	range2 = 1.0;
		position.x += range2 * delta_t * velocity.x;
		position.y += range2 * delta_t * velocity.y;
		position.z += range2 * delta_t * velocity.z;
//		return;	// here's our problem!
    }
	else
	{
		double  target_speed = max_flight_speed;

		ShipEntity*	target = (ShipEntity*)[UNIVERSE entityForUniversalID:primaryTarget];

		if ((target == nil)||(target->scanClass == CLASS_NO_DRAW)||(!target->isShip)||([target isCloaked]))
		{
			 // It's no longer a parrot, it has ceased to be, it has joined the choir invisible...
			if (primaryTarget != NO_TARGET)
			{
				[shipAI reactToMessage:@"TARGET_LOST"];
				primaryTarget = NO_TARGET;
			}
			else
			{
				target_speed = [(ShipEntity *)[UNIVERSE entityForUniversalID:primaryTarget] flight_speed];
				if (target_speed < max_flight_speed)
				{
					target_speed += max_flight_speed;
					target_speed /= 2.0;
				}
			}
		}

		switch (behaviour)
		{
			case BEHAVIOUR_TUMBLE :
				[self behaviour_tumble: delta_t];
				break;

			case BEHAVIOUR_STOP_STILL :
			case BEHAVIOUR_STATION_KEEPING :
				[self behaviour_stop_still: delta_t];
				break;

			case BEHAVIOUR_IDLE :
				[self behaviour_idle: delta_t];
				break;

			case BEHAVIOUR_TRACTORED :
				[self behaviour_tractored: delta_t];
				break;

			case BEHAVIOUR_TRACK_TARGET :
				[self behaviour_track_target: delta_t];
				break;

			case BEHAVIOUR_INTERCEPT_TARGET :
			case BEHAVIOUR_COLLECT_TARGET :
				[self behaviour_intercept_target: delta_t];
				break;

			case BEHAVIOUR_ATTACK_TARGET :
				[self behaviour_attack_target: delta_t];
				break;

			case BEHAVIOUR_ATTACK_FLY_TO_TARGET_SIX :
			case BEHAVIOUR_ATTACK_FLY_TO_TARGET_TWELVE :
				[self behaviour_fly_to_target_six: delta_t];
				break;

			case BEHAVIOUR_ATTACK_MINING_TARGET :
				[self behaviour_attack_mining_target: delta_t];
				break;

			case BEHAVIOUR_ATTACK_FLY_TO_TARGET :
				[self behaviour_attack_fly_to_target: delta_t];
				break;

			case BEHAVIOUR_ATTACK_FLY_FROM_TARGET :
				[self behaviour_attack_fly_from_target: delta_t];
				break;

			case BEHAVIOUR_RUNNING_DEFENSE :
				[self behaviour_running_defense: delta_t];
				break;

			case BEHAVIOUR_FLEE_TARGET :
				[self behaviour_flee_target: delta_t];
				break;

			case BEHAVIOUR_FLY_RANGE_FROM_DESTINATION :
				[self behaviour_fly_range_from_destination: delta_t];
				break;

			case BEHAVIOUR_FACE_DESTINATION :
				[self behaviour_face_destination: delta_t];
				break;

			case BEHAVIOUR_FORMATION_FORM_UP :
				[self behaviour_formation_form_up: delta_t];
				break;

			case BEHAVIOUR_FLY_TO_DESTINATION :
				[self behaviour_fly_to_destination: delta_t];
				break;

			case BEHAVIOUR_FLY_FROM_DESTINATION :
			case BEHAVIOUR_FORMATION_BREAK :
				[self behaviour_fly_from_destination: delta_t];
				break;

			case BEHAVIOUR_AVOID_COLLISION :
				[self behaviour_avoid_collision: delta_t];
				break;

			case BEHAVIOUR_TRACK_AS_TURRET :
				[self behaviour_track_as_turret: delta_t];
				break;

			case BEHAVIOUR_EXPERIMENTAL :
				[self behaviour_experimental: delta_t];
				break;

			case BEHAVIOUR_FLY_THRU_NAVPOINTS :
				[self behaviour_fly_thru_navpoints: delta_t];
				break;

			case BEHAVIOUR_ENERGY_BOMB_COUNTDOWN:
				// Do nothing
				break;
		}
		//
		// manage energy
		//
		if (energy < maxEnergy)
		{
			energy += energy_recharge_rate * delta_t;
			if (energy > maxEnergy)
			{
				energy = maxEnergy;
				[shipAI message:@"ENERGY_FULL"];
			}
		}

		//
		// update destination position for escorts
		if (n_escorts > 0)
		{
			int i;
			for (i = 0; i < n_escorts; i++)
			{
				ShipEntity *escorter = (ShipEntity *)[UNIVERSE entityForUniversalID:escort_ids[i]];
				// check it's still an escort ship
				BOOL escorter_okay = YES;
				if (!escorter)
					escorter_okay = NO;
				else
					escorter_okay = escorter->isShip;
				if (escorter_okay)
					[escorter setDestination:[self getCoordinatesForEscortPosition:i]];	// update its destination
				else
					escort_ids[i--] = escort_ids[--n_escorts];	// remove the escort
			}
		}
    }

	//
	// subentity rotation
	//
	if ((subentityRotationalVelocity.x)||(subentityRotationalVelocity.y)||(subentityRotationalVelocity.z)||(subentityRotationalVelocity.w != 1.0))
	{
		Quaternion qf = subentityRotationalVelocity;
		qf.w *= (1.0 - delta_t);
		qf.x *= delta_t;
		qf.y *= delta_t;
		qf.z *= delta_t;
		q_rotation = quaternion_multiply( qf, q_rotation);
	}
	
	//
	//	reset totalBoundingBox
	//
	totalBoundingBox = boundingBox;
	

	//
	// update subentities
	//
	if (sub_entities)
	{
		int i;
		for (i = 0; i < [sub_entities count]; i++)
//			[(Entity *)[sub_entities objectAtIndex:i] update:delta_t];
		{
			ShipEntity* se = (ShipEntity *)[sub_entities objectAtIndex:i];
			[se update:delta_t];
			if (se->isShip)
			{
				BoundingBox sebb = [se findSubentityBoundingBox];
				bounding_box_add_vector(&totalBoundingBox, sebb.max);
				bounding_box_add_vector(&totalBoundingBox, sebb.min);
			}
		}
	}
	
}


// override Entity version...
//
- (double) speed
{
	return sqrt(velocity.x * velocity.x + velocity.y * velocity.y + velocity.z * velocity.z + flight_speed * flight_speed);
}


////////////////
//            //
// behaviours //
//            //
- (void) behaviour_stop_still:(double) delta_t
{
	double		damping = 0.5 * delta_t;
	// damp roll
	if (flight_roll < 0)
		flight_roll += (flight_roll < -damping) ? damping : -flight_roll;
	if (flight_roll > 0)
		flight_roll -= (flight_roll > damping) ? damping : flight_roll;
	// damp pitch
	if (flight_pitch < 0)
		flight_pitch += (flight_pitch < -damping) ? damping : -flight_pitch;
	if (flight_pitch > 0)
		flight_pitch -= (flight_pitch > damping) ? damping : flight_pitch;
	[self applyRoll:delta_t*flight_roll andClimb:delta_t*flight_pitch];
	[self applyThrust:delta_t];
}
//            //
- (void) behaviour_idle:(double) delta_t
{
	double		damping = 0.5 * delta_t;
	if ((!isStation)&&(scanClass != CLASS_BUOY))
	{
		// damp roll
		if (flight_roll < 0)
			flight_roll += (flight_roll < -damping) ? damping : -flight_roll;
		if (flight_roll > 0)
			flight_roll -= (flight_roll > damping) ? damping : flight_roll;
	}
	if (scanClass != CLASS_BUOY)
	{
		// damp pitch
		if (flight_pitch < 0)
			flight_pitch += (flight_pitch < -damping) ? damping : -flight_pitch;
		if (flight_pitch > 0)
			flight_pitch -= (flight_pitch > damping) ? damping : flight_pitch;
	}
	[self applyRoll:delta_t*flight_roll andClimb:delta_t*flight_pitch];
	[self applyThrust:delta_t];
}
//            //
- (void) behaviour_tumble:(double) delta_t
{
	[self applyRoll:delta_t*flight_roll andClimb:delta_t*flight_pitch];
	[self applyThrust:delta_t];
}
//            //
- (void) behaviour_tractored:(double) delta_t
{
	double  distance = [self rangeToDestination];
	desired_range = collision_radius * 2.0;
	ShipEntity* hauler = (ShipEntity*)[self owner];
	if ((hauler)&&(hauler->isShip))
	{
		if (distance < desired_range)
		{
			behaviour = BEHAVIOUR_TUMBLE;
			status = STATUS_IN_FLIGHT;
			[hauler scoopUp:self];
			return;
		}
		GLfloat tf = TRACTOR_FORCE / mass;
		destination = [hauler absoluteTractorPosition];
		// adjust for difference in velocity (spring rule)
		Vector dv = vector_between( [self velocity], [hauler velocity]);
		GLfloat moment = delta_t * 0.25 * tf;
		velocity.x += moment * dv.x;
		velocity.y += moment * dv.y;
		velocity.z += moment * dv.z;
		// acceleration = force / mass
		// force proportional to distance (spring rule)
		Vector dp = vector_between( position, destination);
		moment = delta_t * 0.5 * tf;
		velocity.x += moment * dp.x;
		velocity.y += moment * dp.y;
		velocity.z += moment * dp.z;
		// force inversely proportional to distance
		GLfloat d2 = magnitude2(dp);
		moment = (d2 > 0.0)? delta_t * 5.0 * tf / d2 : 0.0;
		if (d2 > 0.0)
		{
			velocity.x += moment * dp.x;
			velocity.y += moment * dp.y;
			velocity.z += moment * dp.z;
		}
		//
		if (status == STATUS_BEING_SCOOPED)
		{
			BOOL lost_contact = (distance > hauler->collision_radius + collision_radius + 250.0f);	// 250m range for tractor beam
			if (hauler->isPlayer)
			{
				switch ([(PlayerEntity*)hauler dial_fuelscoops_status])
				{
					case SCOOP_STATUS_NOT_INSTALLED :
					case SCOOP_STATUS_FULL_HOLD :
						lost_contact = YES;	// don't draw
						break;
				}
			}
			//
			if (lost_contact)	// 250m range for tractor beam
			{
				// escaped tractor beam
				status = STATUS_IN_FLIGHT;
				behaviour = BEHAVIOUR_IDLE;
				frustration = 0.0;
				[shipAI exitStateMachine];	// exit nullAI.plist
			}
			else if (hauler->isPlayer)
			{
				[(PlayerEntity*)hauler setScoopsActive];
			}
		}
	}
	[self applyRoll:delta_t*flight_roll andClimb:delta_t*flight_pitch];
	desired_speed = 0.0;
	thrust = 25.0;	// used to damp velocity (must be less than hauler thrust)
	[self applyThrust:delta_t];
	thrust = 0.0;	// must reset thrust now
}
//            //
- (void) behaviour_track_target:(double) delta_t
{
	[self trackPrimaryTarget:delta_t:NO];
	if ((proximity_alert != NO_TARGET)&&(proximity_alert != primaryTarget))
		[self avoidCollision];
	[self applyRoll:delta_t*flight_roll andClimb:delta_t*flight_pitch];
	[self applyThrust:delta_t];
}
//            //
- (void) behaviour_intercept_target:(double) delta_t
{
	double  range = [self rangeToPrimaryTarget];
	if (behaviour == BEHAVIOUR_INTERCEPT_TARGET)
	{
		desired_speed = max_flight_speed;
		if (range < desired_range)
			[shipAI reactToMessage:@"DESIRED_RANGE_ACHIEVED"];
		desired_speed = max_flight_speed * [self trackPrimaryTarget:delta_t:NO];
	}
	else
	{
		ShipEntity*	target = (ShipEntity*)[UNIVERSE entityForUniversalID:primaryTarget];
		double target_speed = [target speed];
		double eta = range / (flight_speed - target_speed);
		double last_success_factor = success_factor;
		double last_distance = last_success_factor;
		double  distance = [self rangeToDestination];
		success_factor = distance;
		//
		double slowdownTime = 96.0 / thrust;	// more thrust implies better slowing
		double minTurnSpeedFactor = 0.005 * max_flight_pitch * max_flight_roll;	// faster turning implies higher speeds

		if ((eta < slowdownTime)&&(flight_speed > max_flight_speed * minTurnSpeedFactor))
			desired_speed = flight_speed * 0.75;   // cut speed by 50% to a minimum minTurnSpeedFactor of speed
		else
			desired_speed = max_flight_speed;

		if (desired_speed < target_speed)
		{
			desired_speed += target_speed;
			if (target_speed > max_flight_speed)
				[shipAI reactToMessage:@"TARGET_LOST"];
		}
		//
		if (target)	// check introduced to stop crash at next line
		{
			destination = target->position;		/* HEISENBUG crash here */
			desired_range = 0.5 * target->actual_radius;
			[self trackDestination: delta_t : NO];
		}
		//
		if (distance < last_distance)	// improvement
		{
			frustration -= delta_t;
			if (frustration < 0.0)
				frustration = 0.0;
		}
		else
		{
			frustration += delta_t;
			if (frustration > 10.0)	// 10s of frustration
			{
				[shipAI reactToMessage:@"FRUSTRATED"];
				frustration -= 5.0;	//repeat after another five seconds' frustration
			}
		}
	}
	if ((proximity_alert != NO_TARGET)&&(proximity_alert != primaryTarget))
		[self avoidCollision];
	[self applyRoll:delta_t*flight_roll andClimb:delta_t*flight_pitch];
	[self applyThrust:delta_t];
}
//            //
- (void) behaviour_attack_target:(double) delta_t
{
	BOOL	canBurn = has_fuel_injection && (fuel > 1);	// was &&(fuel > 0)
	double	max_available_speed = (canBurn)? max_flight_speed * AFTERBURNER_FACTOR : max_flight_speed;
	double  range = [self rangeToPrimaryTarget];
	[self activateCloakingDevice];
	desired_speed = max_available_speed;
	if (range < 0.035 * weapon_range)
		behaviour = BEHAVIOUR_ATTACK_FLY_FROM_TARGET;
	else
		if (universalID & 1)	// 50% of ships are smart S.M.R.T. smart!
		{
			if (randf() < 0.75)
				behaviour = BEHAVIOUR_ATTACK_FLY_TO_TARGET_SIX;
			else
				behaviour = BEHAVIOUR_ATTACK_FLY_TO_TARGET_TWELVE;
		}
		else
		{
			behaviour = BEHAVIOUR_ATTACK_FLY_TO_TARGET;
		}
	frustration = 0.0;	// behaviour changed, so reset frustration
	[self applyRoll:delta_t*flight_roll andClimb:delta_t*flight_pitch];
	[self applyThrust:delta_t];
}
//            //
- (void) behaviour_fly_to_target_six:(double) delta_t
{
	BOOL canBurn = has_fuel_injection && (fuel > 1);	// was &&(fuel > 0)
	double max_available_speed = (canBurn)? max_flight_speed * AFTERBURNER_FACTOR : max_flight_speed;
	double  range = [self rangeToPrimaryTarget];
	// deal with collisions and lost targets
	//
	if (proximity_alert != NO_TARGET)
		[self avoidCollision];
	if (range > SCANNER_MAX_RANGE)
	{
		behaviour = BEHAVIOUR_IDLE;
		frustration = 0.0;
		[shipAI reactToMessage:@"TARGET_LOST"];
	}

	// control speed
	//
	BOOL isUsingAfterburner = canBurn && (flight_speed > max_flight_speed);
	double	slow_down_range = weapon_range * COMBAT_WEAPON_RANGE_FACTOR * ((isUsingAfterburner)? 3.0 * AFTERBURNER_FACTOR : 1.0);
	ShipEntity*	target = (ShipEntity*)[UNIVERSE entityForUniversalID:primaryTarget];
	double target_speed = [target speed];
	double distance = [self rangeToDestination];
	if (range < slow_down_range)
	{
		desired_speed = OOMax_d(target_speed, 0.25 * max_flight_speed);
		// avoid head-on collision
		//
		if ((range < 0.5 * distance)&&(behaviour == BEHAVIOUR_ATTACK_FLY_TO_TARGET_SIX))
			behaviour = BEHAVIOUR_ATTACK_FLY_TO_TARGET_TWELVE;
	}
	else
		desired_speed = max_available_speed; // use afterburner to approach


	// if within 0.75km of the target's six or twelve then vector in attack
	//
	if (distance < 750.0)
	{
		behaviour = BEHAVIOUR_ATTACK_FLY_TO_TARGET;
		frustration = 0.0;
		desired_speed = OOMax_d(target_speed, 0.25 * max_flight_speed);   // within the weapon's range don't use afterburner
	}

	// target-six
	if (behaviour == BEHAVIOUR_ATTACK_FLY_TO_TARGET_SIX)
	{
		// head for a point weapon-range * 0.5 to the six of the target
		//
		destination = [target distance_six:0.5 * weapon_range];
	}
	// target-twelve
	if (behaviour == BEHAVIOUR_ATTACK_FLY_TO_TARGET_TWELVE)
	{
		// head for a point 1.25km above the target
		//
		destination = [target distance_twelve:1250];
	}

	[self trackDestination:delta_t :NO];

	// use weaponry
	//
	int missile_chance = 0;
	int rhs = 3.2 / delta_t;
	if (rhs)	missile_chance = 1 + (ranrot_rand() % rhs);

	double hurt_factor = 16 * pow(energy/maxEnergy, 4.0);
	if (missiles > missile_chance * hurt_factor)
	{
		//NSLog(@"]==> firing missile : missiles %d, missile_chance %d, hurt_factor %.3f", missiles, missile_chance, hurt_factor);
		[self fireMissile];
	}
	[self activateCloakingDevice];
	[self fireMainWeapon:range];
	[self applyRoll:delta_t*flight_roll andClimb:delta_t*flight_pitch];
	[self applyThrust:delta_t];
}
//            //
- (void) behaviour_attack_mining_target:(double) delta_t
{
	double  range = [self rangeToPrimaryTarget];
	if ((range < 650)||(proximity_alert != NO_TARGET))
	{
		if (proximity_alert == NO_TARGET)
		{
			desired_speed = range * max_flight_speed / (650.0 * 16.0);
		}
		else
		{
			[self avoidCollision];
		}
	}
	else
	{
		if (range > SCANNER_MAX_RANGE)
		{
			behaviour = BEHAVIOUR_IDLE;
			[shipAI reactToMessage:@"TARGET_LOST"];
		}
		desired_speed = max_flight_speed * 0.375;
	}
	[self trackPrimaryTarget:delta_t:NO];
	[self fireMainWeapon:range];
	[self applyRoll:delta_t*flight_roll andClimb:delta_t*flight_pitch];
	[self applyThrust:delta_t];
}
//            //
- (void) behaviour_attack_fly_to_target:(double) delta_t
{
	BOOL canBurn = has_fuel_injection && (fuel > 1);	// was &&(fuel > 0)
	double max_available_speed = (canBurn)? max_flight_speed * AFTERBURNER_FACTOR : max_flight_speed;
	double  range = [self rangeToPrimaryTarget];
	if ((range < COMBAT_IN_RANGE_FACTOR * weapon_range)||(proximity_alert != NO_TARGET))
	{
		if (proximity_alert == NO_TARGET)
		{
			if (aft_weapon_type == WEAPON_NONE)
			{
				jink.x = (ranrot_rand() % 256) - 128.0;
				jink.y = (ranrot_rand() % 256) - 128.0;
				jink.z = 1000.0;
				behaviour = BEHAVIOUR_ATTACK_FLY_FROM_TARGET;
				frustration = 0.0;
				desired_speed = max_available_speed;
			}
			else
			{
				// entering running defense mode
				jink = kZeroVector;
				behaviour = BEHAVIOUR_RUNNING_DEFENSE;
				frustration = 0.0;
				desired_speed = max_flight_speed;
			}
		}
		else
		{
			[self avoidCollision];
		}
	}
	else
	{
		if (range > SCANNER_MAX_RANGE)
		{
			behaviour = BEHAVIOUR_IDLE;
			frustration = 0.0;
			[shipAI reactToMessage:@"TARGET_LOST"];
		}
	}

	// control speed
	//
	BOOL isUsingAfterburner = canBurn && (flight_speed > max_flight_speed);
	double slow_down_range = weapon_range * COMBAT_WEAPON_RANGE_FACTOR * ((isUsingAfterburner)? 3.0 * AFTERBURNER_FACTOR : 1.0);
	ShipEntity*	target = (ShipEntity*)[UNIVERSE entityForUniversalID:primaryTarget];
	double target_speed = [target speed];
	if (range <= slow_down_range)
		desired_speed = OOMax_d(target_speed, 0.25 * max_flight_speed);   // within the weapon's range match speed
	else
		desired_speed = max_available_speed; // use afterburner to approach

	double last_success_factor = success_factor;
	success_factor = [self trackPrimaryTarget:delta_t:NO];	// do the actual piloting
	if ((success_factor > 0.999)||(success_factor > last_success_factor))
	{
		frustration -= delta_t;
		if (frustration < 0.0)
			frustration = 0.0;
	}
	else
	{
		frustration += delta_t;
		if (frustration > 3.0)	// 3s of frustration
		{
			[shipAI reactToMessage:@"FRUSTRATED"];
			// THIS IS HERE AS A TEST ONLY
			// BREAK OFF
			jink.x = (ranrot_rand() % 256) - 128.0;
			jink.y = (ranrot_rand() % 256) - 128.0;
			jink.z = 1000.0;
			behaviour = BEHAVIOUR_ATTACK_FLY_FROM_TARGET;
			frustration = 0.0;
			desired_speed = max_flight_speed;
		}
	}

	int missile_chance = 0;
	int rhs = 3.2 / delta_t;
	if (rhs)	missile_chance = 1 + (ranrot_rand() % rhs);

	double hurt_factor = 16 * pow(energy/maxEnergy, 4.0);
	if (missiles > missile_chance * hurt_factor)
	{
		//NSLog(@"]==> firing missile : missiles %d, missile_chance %d, hurt_factor %.3f", missiles, missile_chance, hurt_factor);
		[self fireMissile];
	}
	[self activateCloakingDevice];
	[self fireMainWeapon:range];
	[self applyRoll:delta_t*flight_roll andClimb:delta_t*flight_pitch];
	[self applyThrust:delta_t];
}
//            //
- (void) behaviour_attack_fly_from_target:(double) delta_t
{
	double  range = [self rangeToPrimaryTarget];
	if (range > COMBAT_OUT_RANGE_FACTOR * weapon_range + 15.0 * jink.x)
	{
		jink.x = 0.0;
		jink.y = 0.0;
		jink.z = 0.0;
		behaviour = BEHAVIOUR_ATTACK_TARGET;
		frustration = 0.0;
	}
	[self trackPrimaryTarget:delta_t:YES];

	int missile_chance = 0;
	int rhs = 3.2 / delta_t;
	if (rhs)	missile_chance = 1 + (ranrot_rand() % rhs);

	double hurt_factor = 16 * pow(energy/maxEnergy, 4.0);
	if (missiles > missile_chance * hurt_factor)
	{
		//NSLog(@"]==> firing missile : missiles %d, missile_chance %d, hurt_factor %.3f", missiles, missile_chance, hurt_factor);
		[self fireMissile];
	}
	[self activateCloakingDevice];
	[self applyRoll:delta_t*flight_roll andClimb:delta_t*flight_pitch];
	[self applyThrust:delta_t];
}
//            //
- (void) behaviour_running_defense:(double) delta_t
{
	double  range = [self rangeToPrimaryTarget];
	if (range > weapon_range)
	{
		jink.x = 0.0;
		jink.y = 0.0;
		jink.z = 0.0;
		behaviour = BEHAVIOUR_ATTACK_FLY_TO_TARGET;
		frustration = 0.0;
	}
	[self trackPrimaryTarget:delta_t:YES];
	[self fireAftWeapon:range];
	[self activateCloakingDevice];
	[self applyRoll:delta_t*flight_roll andClimb:delta_t*flight_pitch];
	[self applyThrust:delta_t];
}
//            //
- (void) behaviour_flee_target:(double) delta_t
{
	BOOL canBurn = has_fuel_injection && (fuel > 1);	// was &&(fuel > 0)
	double max_available_speed = (canBurn)? max_flight_speed * AFTERBURNER_FACTOR : max_flight_speed;
	double  range = [self rangeToPrimaryTarget];
	if (range > desired_range)
		[shipAI message:@"REACHED_SAFETY"];
	else
		desired_speed = max_available_speed;
	[self trackPrimaryTarget:delta_t:YES];

	int missile_chance = 0;
	int rhs = 3.2 / delta_t;
	if (rhs)	missile_chance = 1 + (ranrot_rand() % rhs);

	if ((has_energy_bomb) && (range < 10000.0))
	{
		float	qbomb_chance = 0.01 * delta_t;
		if (randf() < qbomb_chance)
		{
			[self launchEnergyBomb];
		}
	}

	double hurt_factor = 16 * pow(energy/maxEnergy, 4.0);
	if (([(ShipEntity *)[self getPrimaryTarget] getPrimaryTarget] == self)&&(missiles > missile_chance * hurt_factor))
		[self fireMissile];
	[self activateCloakingDevice];
	[self applyRoll:delta_t*flight_roll andClimb:delta_t*flight_pitch];
	[self applyThrust:delta_t];
}
//            //
- (void) behaviour_fly_range_from_destination:(double) delta_t
{
	double distance = [self rangeToDestination];
	if (distance < desired_range)
		behaviour = BEHAVIOUR_FLY_FROM_DESTINATION;
	else
		behaviour = BEHAVIOUR_FLY_TO_DESTINATION;
	frustration = 0.0;
	[self applyRoll:delta_t*flight_roll andClimb:delta_t*flight_pitch];
	[self applyThrust:delta_t];
}
//            //
- (void) behaviour_face_destination:(double) delta_t
{
	double max_cos = 0.995;
	double distance = [self rangeToDestination];
	desired_speed = 0.0;
	if (desired_range > 1.0)
		max_cos = sqrt(1 - desired_range*desired_range/(distance * distance));
	else
		max_cos = 0.995;	// 0.995 - cos(5 degrees) is close enough
	double confidenceFactor = [self trackDestination:delta_t:NO];
	if (confidenceFactor > max_cos)
	{
		// desired facing achieved
		[shipAI message:@"FACING_DESTINATION"];
		behaviour = BEHAVIOUR_IDLE;
		frustration = 0.0;
	}
	if ((proximity_alert != NO_TARGET)&&(proximity_alert != primaryTarget))
		[self avoidCollision];
	[self applyRoll:delta_t*flight_roll andClimb:delta_t*flight_pitch];
	[self applyThrust:delta_t];
}
//            //
- (void) behaviour_formation_form_up:(double) delta_t
{
	// get updated destination from owner
	ShipEntity* leadShip = (ShipEntity *)[UNIVERSE entityForUniversalID:owner];
	double distance = [self rangeToDestination];
	double eta = (distance - desired_range) / flight_speed;
	if ((eta < 5.0)&&(leadShip)&&(leadShip->isShip))
		desired_speed = [leadShip flight_speed] * 1.25;
	else
		desired_speed = max_flight_speed;
	[self behaviour_fly_to_destination: delta_t];
}
//            //
- (void) behaviour_fly_to_destination:(double) delta_t
{
	double distance = [self rangeToDestination];
	if (distance < desired_range)// + collision_radius)
	{
		// desired range achieved
		[shipAI message:@"DESIRED_RANGE_ACHIEVED"];
		behaviour = BEHAVIOUR_IDLE;
		frustration = 0.0;
		desired_speed = 0.0;
	}
	else
	{
		double last_success_factor = success_factor;
		double last_distance = last_success_factor;
		success_factor = distance;

		// do the actual piloting!!
		[self trackDestination:delta_t: NO];
		
		GLfloat eta = (distance - desired_range) / (0.51 * flight_speed);	// 2% safety margin assuming an average of half current speed
		GLfloat slowdownTime = (thrust > 0.0)? flight_speed / thrust : 4.0;
		GLfloat minTurnSpeedFactor = 0.05 * max_flight_pitch * max_flight_roll;	// faster turning implies higher speeds

		if ((eta < slowdownTime)&&(flight_speed > max_flight_speed * minTurnSpeedFactor))
			desired_speed = flight_speed * 0.50;   // cut speed by 50% to a minimum minTurnSpeedFactor of speed

		if (distance < last_distance)	// improvement
		{
			frustration -= 0.25 * delta_t;
			if (frustration < 0.0)
				frustration = 0.0;
		}
		else
		{
			frustration += delta_t;
			if ((frustration > slowdownTime * 10.0)||(frustration > 15.0))	// 10x slowdownTime or 15s of frustration
			{
				[shipAI reactToMessage:@"FRUSTRATED"];
				frustration -= slowdownTime * 5.0;	//repeat after another five units of frustration
			}
		}
	}
	if ((proximity_alert != NO_TARGET)&&(proximity_alert != primaryTarget))
		[self avoidCollision];
	[self applyRoll:delta_t*flight_roll andClimb:delta_t*flight_pitch];
	[self applyThrust:delta_t];
}
//            //
- (void) behaviour_fly_from_destination:(double) delta_t
{
	double distance = [self rangeToDestination];
	if (distance > desired_range)
	{
		// desired range achieved
		[shipAI message:@"DESIRED_RANGE_ACHIEVED"];
		behaviour = BEHAVIOUR_IDLE;
		frustration = 0.0;
		desired_speed = 0.0;
	}
	else
	{
		desired_speed = max_flight_speed;
	}
	[self trackDestination:delta_t:YES];
	if ((proximity_alert != NO_TARGET)&&(proximity_alert != primaryTarget))
		[self avoidCollision];
	[self applyRoll:delta_t*flight_roll andClimb:delta_t*flight_pitch];
	[self applyThrust:delta_t];
}
//            //
- (void) behaviour_avoid_collision:(double) delta_t
{
	double distance = [self rangeToDestination];
	if (distance > desired_range)
	{
		[self resumePostProximityAlert];
	}
	else
	{
		ShipEntity* prox_ship = [self proximity_alert];
		if (prox_ship)
		{
			desired_range = prox_ship->collision_radius * PROXIMITY_AVOID_DISTANCE;
			destination = prox_ship->position;
		}
		double dq = [self trackDestination:delta_t:YES];
		if (dq >= 0)
			dq = 0.5 * dq + 0.5;
		else
			dq = 0.0;
		desired_speed = max_flight_speed * dq;
	}
	[self applyRoll:delta_t*flight_roll andClimb:delta_t*flight_pitch];
	[self applyThrust:delta_t];
}
//            //
- (void) behaviour_track_as_turret:(double) delta_t
{
	double aim = [self ballTrackLeadingTarget:delta_t];
	ShipEntity* turret_owner = (ShipEntity *)[self owner];
	ShipEntity* turret_target = (ShipEntity *)[turret_owner getPrimaryTarget];
	//
	if ((turret_owner)&&(turret_target)&&[turret_owner hasHostileTarget])
	{
		Vector p1 = turret_target->position;
		Vector p0 = turret_owner->position;
		double cr = turret_owner->collision_radius;
		p1.x -= p0.x;	p1.y -= p0.y;	p1.z -= p0.z;
		if (aim > .95)
			[self fireTurretCannon: sqrt( magnitude2( p1)) - cr];
	}
}
//            //
- (void) behaviour_fly_thru_navpoints:(double) delta_t
{
	int navpoint_plus_index = (next_navpoint_index + 1) % number_of_navpoints;
	Vector d1 = navpoints[ next_navpoint_index];		// head for this one
	Vector d2 = navpoints[ navpoint_plus_index];	// but be facing this one
	
	Vector rel = vector_between(d1, position);	// vector from d1 to position 
	Vector ref = vector_between(d2, d1);		// vector from d2 to d1
	ref = unit_vector(&ref);
	
	Vector xp = make_vector( ref.y * rel.z - ref.z * rel.y, ref.z * rel.x - ref.x * rel.z, ref.x * rel.y - ref.y * rel.x);	
	
	GLfloat v0 = 0.0;
	
	GLfloat	r0 = dot_product( rel, ref);	// proportion of rel in direction ref
	
	// if r0 is negative then we're the wrong side of things
	
	GLfloat	r1 = sqrtf(magnitude2( xp));	// distance of position from line
	
	BOOL in_cone = (r0 > 0.5 * r1);
	
	if (!in_cone)	// are we in the approach cone ?
		r1 = 25.0 * flight_speed;	// aim a few km out!
	else
		r1 *= 2.0;
	
	GLfloat dist2 = magnitude2(rel);
	
	if (dist2 < desired_range * desired_range)
	{
		// desired range achieved
		[shipAI reactToMessage:@"NAVPOINT_REACHED"];
		if (navpoint_plus_index == 0)
		{
			[shipAI reactToMessage:@"ENDPOINT_REACHED"];
			behaviour = BEHAVIOUR_IDLE;
		}
		next_navpoint_index = navpoint_plus_index;	// loop as required
	}
	else
	{
		double last_success_factor = success_factor;
		double last_dist2 = last_success_factor;
		success_factor = dist2;

		// set destination spline point from r1 and ref
		destination = make_vector( d1.x + r1 * ref.x, d1.y + r1 * ref.y, d1.z + r1 * ref.z);

		// do the actual piloting!!
		//
		// aim to within 1m
		GLfloat temp = desired_range;
		if (in_cone)
			desired_range = 1.0;
		else
			desired_range = 100.0;
		v0 = [self trackDestination:delta_t: NO];
		desired_range = temp;
		
		if (dist2 < last_dist2)	// improvement
		{
			frustration -= 0.25 * delta_t;
			if (frustration < 0.0)
				frustration = 0.0;
		}
		else
		{
			frustration += delta_t;
			if (frustration > 15.0)	// 15s of frustration
			{
				[shipAI reactToMessage:@"FRUSTRATED"];
				frustration -= 15.0;	//repeat after another 15s of frustration
			}
		}
	}
	
	[self applyRoll:delta_t*flight_roll andClimb:delta_t*flight_pitch];
	GLfloat temp = desired_speed;
	desired_speed *= v0 * v0;
	[self applyThrust:delta_t];
	desired_speed = temp;
}
//            //
- (void) behaviour_experimental:(double) delta_t
{
	double aim = [self ballTrackTarget:delta_t];
	if (aim > .95)
	{
		NSLog(@"DEBUG BANG! BANG! BANG!");
	}
}
//            //
////////////////

// override Entity saveToLastFrame
//
- (void) saveToLastFrame
{
	double t_now = [UNIVERSE getTime];
	if (t_now >= trackTime + 0.1)		// update every 1/10 of a second
	{
		// save previous data
		Quaternion qrot = q_rotation;
		if (isPlayer)	qrot.w = -qrot.w;	// correct player's q_rotation
		trackTime = t_now;
		track[trackIndex].position =	position;
		track[trackIndex].q_rotation =	qrot;
		track[trackIndex].timeframe =	trackTime;
		track[trackIndex].k =	v_forward;
		//
		if (sub_entities)
		{
//			NSLog(@"DEBUG %@'s subentities ...", self);
			int i;
			int n = [sub_entities count];
			Frame thisFrame;
			thisFrame.q_rotation = qrot;
			thisFrame.timeframe = trackTime;
			thisFrame.k = v_forward;
			for (i = 0; i < n; i++)
			{
				Entity* se = (Entity*)[sub_entities objectAtIndex:i];
				Vector	sepos = se->position;
				if ((se->isParticle)&&([(ParticleEntity*)se particleType] == PARTICLE_EXHAUST))
				{
					thisFrame.position = make_vector(
						position.x + v_right.x * sepos.x + v_up.x * sepos.y + v_forward.x * sepos.z,
						position.y + v_right.y * sepos.x + v_up.y * sepos.y + v_forward.y * sepos.z,
						position.z + v_right.z * sepos.x + v_up.z * sepos.y + v_forward.z * sepos.z);
					[se saveFrame:thisFrame atIndex:trackIndex];	// syncs subentity trackIndex to this entity
//					NSLog(@"DEBUG ... %@ %@ [%.2f %.2f %.2f]", self, se, thisFrame.position.x - position.x, thisFrame.position.y - position.y, thisFrame.position.z - position.z);
				}
			}
		}
		//
		trackIndex = (trackIndex + 1 ) & 0xff;
		//
	}
}

// reset position tracking
//
- (void) resetTracking
{
	Quaternion	qrot = q_rotation;
	if (isPlayer)	qrot.w = -qrot.w;	// correct player's q_rotation
	Vector		vi = vector_right_from_quaternion(qrot);
	Vector		vj = vector_up_from_quaternion(qrot);
	Vector		vk = vector_forward_from_quaternion(qrot);
	Frame resetFrame;
	resetFrame.position = position;
	resetFrame.q_rotation = qrot;
	resetFrame.k = vk;
	Vector vel = make_vector( vk.x * flight_speed, vk.y * flight_speed, vk.z * flight_speed);
	
	if ((isPlayer)&&(debug))
		NSLog(@"DEBUG resetting tracking for %@", self);
	
	[self resetFramesFromFrame:resetFrame withVelocity:vel];
	if (sub_entities)
	{
		int i;
		int n = [sub_entities count];
		for (i = 0; i < n; i++)
		{
			Entity* se = (Entity*)[sub_entities objectAtIndex:i];
			Vector	sepos = se->position;
			if ((se->isParticle)&&([(ParticleEntity*)se particleType] == PARTICLE_EXHAUST))
			{
			
				if ((isPlayer)&&(debug))
					NSLog(@"DEBUG resetting tracking for subentity %@ of %@", se, self);
			
				resetFrame.position = make_vector(
					position.x + vi.x * sepos.x + vj.x * sepos.y + vk.x * sepos.z,
					position.y + vi.y * sepos.x + vj.y * sepos.y + vk.y * sepos.z,
					position.z + vi.z * sepos.x + vj.z * sepos.y + vk.z * sepos.z);
				[se resetFramesFromFrame:resetFrame withVelocity:vel];
			}
		}
	}
}

// return a point 36u back from the front of the ship
// this equates with the centre point of a cobra mk3
//
- (Vector) viewpointPosition
{
	Vector	viewpoint = position;
	float	nose = boundingBox.max.z - 36.0;
	viewpoint.x += nose * v_forward.x;	viewpoint.y += nose * v_forward.y;	viewpoint.z += nose * v_forward.z;
	return viewpoint;
}

#ifndef NO_SHADERS
BOOL shaders_supported = YES;
BOOL testForShaderSupport = YES;
#else
BOOL shaders_supported = NO;
BOOL testForShaderSupport = NO;
#endif

void testForShaders()
{
#ifndef NO_SHADERS
	testForShaderSupport = NO;
	NSString* version_info = [NSString stringWithCString: (const char *)glGetString(GL_VERSION)];
	NSScanner* vscan = [NSScanner scannerWithString:version_info];
	int major = 0;
	int minor = 0;
	NSString* temp;
	if ([vscan scanUpToCharactersFromSet:[NSCharacterSet characterSetWithCharactersInString:@". "] intoString:&temp])
		major = [temp intValue];
	[vscan scanCharactersFromSet:[NSCharacterSet characterSetWithCharactersInString:@". "] intoString:(NSString**)nil];
	if ([vscan scanUpToCharactersFromSet:[NSCharacterSet characterSetWithCharactersInString:@". "] intoString:&temp])
		minor = [temp intValue];

	OOLog(kOOLogOpenGLVersion, @"OpenGL renderer version: %d.%d ('%@')", major, minor, version_info);

	if ((major < 2)&&(minor < 5))
	{
		shaders_supported = NO;
		NSLog(@"INFORMATION: Oolite does not use shaders for OpenGL drivers before OpenGL 1.5");
		return;
	}
	
	// check for the necessary extensions
	NSString* extension_info = [NSString stringWithCString: (const char *)glGetString(GL_EXTENSIONS)];

	OOLog(kOOLogOpenGLExtensions, @"OPENGL EXTENSIONS:\n%@", extension_info);
	
	shaders_supported &= ([extension_info rangeOfString:@"GL_ARB_multitexture"].location != NSNotFound);
	if (!shaders_supported)
	{
		OOLog(kOOLogOpenGLShaderSupport, @"INFORMATION: shaders require the GL_ARB_multitexture OpenGL extension, which is not present.");
		return;
	}
	
	shaders_supported &= ([extension_info rangeOfString:@"GL_ARB_shader_objects"].location != NSNotFound);
	if (!shaders_supported)
	{
		OOLog(kOOLogOpenGLShaderSupport, @"INFORMATION: shaders require the GL_ARB_multitexture OpenGL extension, which is not present.");
		return;
	}
		
	shaders_supported &= ([extension_info rangeOfString:@"GL_ARB_shading_language_100"].location != NSNotFound);
	if (!shaders_supported)
	{
		OOLog(kOOLogOpenGLShaderSupport, @"INFORMATION: shaders require the GL_ARB_shading_language_100 OpenGL extension, which is not present.");
		return;
	}
	
	shaders_supported &= ([extension_info rangeOfString:@"GL_ARB_fragment_program"].location != NSNotFound);
	if (!shaders_supported)
	{
		OOLog(kOOLogOpenGLShaderSupport, @"INFORMATION: shaders require the GL_ARB_fragment_program OpenGL extension, which is not present.");
		return;
	}
	
	shaders_supported &= ([extension_info rangeOfString:@"GL_ARB_fragment_shader"].location != NSNotFound);
	if (!shaders_supported)
	{
		OOLog(kOOLogOpenGLShaderSupport, @"INFORMATION: shaders require the GL_ARB_fragment_shader OpenGL extension, which is not present.");
		return;
	}
	
	shaders_supported &= ([extension_info rangeOfString:@"GL_ARB_vertex_program"].location != NSNotFound);
	if (!shaders_supported)
	{
		OOLog(kOOLogOpenGLShaderSupport, @"INFORMATION: shaders require the GL_ARB_vertex_program OpenGL extension, which is not present.");
		return;
	}
	
	shaders_supported &= ([extension_info rangeOfString:@"GL_ARB_vertex_shader"].location != NSNotFound);
	if (!shaders_supported)
	{
		OOLog(kOOLogOpenGLShaderSupport, @"INFORMATION: shaders require the GL_ARB_vertex_shader OpenGL extension, which is not present.");
		return;
	}

#ifdef GNUSTEP
	// I am assuming none of the extensions will be used before this call because they have only just been checked for.
	// Note this this won't be called unless everything required is available because all the checks about return immediately
	// if a required extension is not found.
	loadOpenGLFunctions();
#endif
#endif
}

- (void) initialiseTextures
{
    [super initialiseTextures];
	
	if (testForShaderSupport)
		testForShaders();
	if ([shipinfoDictionary objectForKey:@"shaders"] && shaders_supported)
	{
#ifndef NO_SHADERS
		// initialise textures in shaders
		
		if (!shader_info)
			shader_info = [[NSMutableDictionary dictionary] retain];
					
		OOLog(kOOLogShaderInit, @"Initialising shaders for %@", self);
		OOLogIndentIf(kOOLogShaderInit);
		
		NSDictionary	*shaders = [shipinfoDictionary objectForKey:@"shaders"];
		NSEnumerator	*shaderEnum = nil;
		NSString		*shaderKey = nil;
		
		for (shaderEnum = [shaders keyEnumerator]; (shaderKey = [shaderEnum nextObject]); )
		{
			NSDictionary* shader = [shaders objectForKey:shaderKey];
			NSArray* shader_textures = [shader objectForKey:@"textures"];
			NSMutableArray* textureNames = [NSMutableArray array];
			
			OOLog(kOOLogShaderInitDumpShader, @"Shader: initialising shader for %@ : %@", shaderKey, shader);
			int ti;
			for (ti = 0; ti < [shader_textures count]; ti ++)
			{
				GLuint tn = [TextureStore getTextureNameFor: (NSString*)[shader_textures objectAtIndex:ti]];
				[textureNames addObject:[NSNumber numberWithUnsignedInt:tn]];
				OOLog(kOOLogShaderInitDumpTexture, @"Shader: initialised texture: %@", [shader_textures objectAtIndex:ti]);
			}
			
			GLhandleARB shaderProgram = [TextureStore shaderProgramFromDictionary:shader];
			if (shaderProgram)
			{
				[shader_info setObject:[NSDictionary dictionaryWithObjectsAndKeys:
						textureNames, @"textureNames",
						[NSValue valueWithPointer:shaderProgram], @"shaderProgram",
						[shader objectForKey:@"uniforms"], @"uniforms",
						nil]
					forKey: shaderKey];
			}
		}
		
		OOLog(kOOLogShaderInitDumpShaderInfo, @"TESTING: shader_info = %@", shader_info);
		OOLogOutdentIf(kOOLogShaderInit);
#endif
	}
	else
	{
		if (shader_info)
			[shader_info release];
		shader_info = nil;
	}
}

- (void) drawEntity:(BOOL) immediate :(BOOL) translucent
{
	if (testForShaderSupport)
		testForShaders();
	
	if (zero_distance > no_draw_distance)	return;	// TOO FAR AWAY

	if ([UNIVERSE breakPatternHide])	return;	// DON'T DRAW

	if (cloaking_device_active && (randf() > 0.10))			return;	// DON'T DRAW

	if (!translucent)
	{
		if (!shaders_supported)
		{
			[super drawEntity:immediate:translucent];
		}
		else
		{
			// draw the thing - code take from Entity drawEntity::
			//
			int ti;
			GLfloat mat_ambient[] = { 1.0, 1.0, 1.0, 1.0 };
			GLfloat mat_no[] =		{ 0.0, 0.0, 0.0, 1.0 };

			NS_DURING

				if (isSmoothShaded)
					glShadeModel(GL_SMOOTH);
				else
					glShadeModel(GL_FLAT);

				if (!translucent)
				{
					if (basefile)
					{
						// calls moved here because they are unsupported in display lists
						//
						glDisableClientState(GL_COLOR_ARRAY);
						glDisableClientState(GL_INDEX_ARRAY);
						glDisableClientState(GL_EDGE_FLAG_ARRAY);
						//
						glEnableClientState(GL_VERTEX_ARRAY);
						glEnableClientState(GL_NORMAL_ARRAY);
						glEnableClientState(GL_TEXTURE_COORD_ARRAY);

						glVertexPointer( 3, GL_FLOAT, 0, entityData.vertex_array);
						glNormalPointer( GL_FLOAT, 0, entityData.normal_array);
						glTexCoordPointer( 2, GL_FLOAT, 0, entityData.texture_uv_array);
						
						ShipEntity *propertyEntity;
						if (!isSubentity)  propertyEntity = self;
						else  propertyEntity = (ShipEntity *)[self owner];
						
						GLfloat utime = (GLfloat)[UNIVERSE getTime];
						GLfloat engine_level = [propertyEntity speed_factor];
						GLfloat laser_heat_level = [propertyEntity laserHeatLevel];
						GLfloat hull_heat_level = [propertyEntity hullHeatLevel];
						int entity_personality_int = propertyEntity->entity_personality;
						
						laser_heat_level = OOClamp_0_1_f(laser_heat_level);
						
						if (immediate)
						{
							//
							// gap removal (draws flat polys)
							//
							glDisable(GL_TEXTURE_2D);
							GLfloat amb_diff0[] = { 0.5, 0.5, 0.5, 1.0};
							glMaterialfv( GL_FRONT_AND_BACK, GL_AMBIENT_AND_DIFFUSE, amb_diff0);
							glMaterialfv( GL_FRONT_AND_BACK, GL_EMISSION, mat_no);
							glColor4f( 0.25, 0.25, 0.25, 1.0);	// gray
							glDepthMask(GL_FALSE); // don't write to depth buffer
							glDrawArrays( GL_TRIANGLES, 0, entityData.n_triangles);	// draw in gray to mask the edges
							glDepthMask(GL_TRUE);

							//
							// now the textures ...
							//
							glEnable(GL_TEXTURE_2D);
							glTexEnvf(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_MODULATE);
							glMaterialfv( GL_FRONT_AND_BACK, GL_AMBIENT_AND_DIFFUSE, mat_ambient);
							glMaterialfv( GL_FRONT_AND_BACK, GL_EMISSION, mat_no);

							for (ti = 1; ti <= n_textures; ti++)
							{
								NSString* textureKey = [TextureStore getNameOfTextureWithGLuint: texture_name[ti]];
#ifndef NO_SHADERS
								if ((shader_info) && [shader_info objectForKey: textureKey])
								{
									NSDictionary	*shader = [shader_info objectForKey:textureKey];
									GLhandleARB		shaderProgram = [[shader objectForKey:@"shaderProgram"] pointerValue];
									GLint			variable_location;
									//
									// set up texture units
									//
									glUseProgramObjectARB(shaderProgram);
									//
									NSArray *texture_units = [shader objectForKey:@"textureNames"];
									int n_tu = [texture_units count];
									int i;
									for (i = 0; i < n_tu; i++)
									{
										// set up each texture unit in turn
										// associating texN with each texture
										GLuint textureN = [[texture_units objectAtIndex:i] intValue];
										
										glActiveTextureARB( GL_TEXTURE0_ARB + i);
										glBindTexture( GL_TEXTURE_2D, textureN);
										
										NSString* texdname = [NSString stringWithFormat:@"tex%d", i];
										const char* cname = [texdname UTF8String];
										variable_location = glGetUniformLocationARB(shaderProgram, cname);
										if (variable_location == -1)
											OOLog(kOOLogShaderTextureNameMissing, @"GLSL ERROR couldn't find location of %@ in shaderProgram %d", texdname, shaderProgram);
										else
											glUniform1iARB(variable_location, i);	// associate texture unit number i with tex%d
									}
									
									NSDictionary *uniforms = [shader objectForKey:@"uniforms"];
									if (uniforms != nil)
									{
										ApplyConstantUniforms([shader objectForKey:@"uniforms"], shaderProgram);
									}
									
									// other uniform variables
									variable_location = glGetUniformLocationARB( shaderProgram, "time");
									if (variable_location != -1)
									{
										OOLog(@"rendering.opengl.shader.uniform.time", @"Binding time: %g", time);
										glUniform1fARB(variable_location, utime);
									}
									
									variable_location = glGetUniformLocationARB( shaderProgram, "engine_level");
									if (variable_location != -1)
									{
										OOLog(@"rendering.opengl.shader.uniform.engineLevel", @"Binding engine_level: %g", engine_level);
										glUniform1fARB(variable_location, engine_level);
									}
									
									variable_location = glGetUniformLocationARB( shaderProgram, "laser_heat_level");
									if (variable_location != -1)
									{
										OOLog(@"rendering.opengl.shader.uniform.laserHeatLevel", @"Binding laser_heat_level: %g", laser_heat_level);
										glUniform1fARB(variable_location, laser_heat_level);
									}
									
									variable_location = glGetUniformLocationARB( shaderProgram, "hull_heat_level");
									if (variable_location != -1)
									{
										OOLog(@"rendering.opengl.shader.uniform.hullHeatLevel", @"Binding hull_heat_level: %g", hull_heat_level);
										glUniform1fARB(variable_location, hull_heat_level);
									}
									
									variable_location = glGetUniformLocationARB( shaderProgram, "entity_personality_int");
									if (variable_location != -1)
									{
										OOLog(@"rendering.opengl.shader.uniform.entityPersonality.int", @"Binding entity_personality_int: %i", entity_personality_int);
										glUniform1iARB(variable_location, entity_personality_int);
									}
									
									variable_location = glGetUniformLocationARB( shaderProgram, "entity_personality");
									if (variable_location != -1)
									{
										OOLog(@"rendering.opengl.shader.uniform.entityPersonality.float", @"Binding entity_personality: %g", entity_personality_int / (float)0x7FFF);
										glUniform1fARB(variable_location, entity_personality_int / (float)0x7FFF);
									}
								}
								else
#endif
									glBindTexture(GL_TEXTURE_2D, texture_name[ti]);

								glDrawArrays( GL_TRIANGLES, triangle_range[ti].location, triangle_range[ti].length);

#ifndef NO_SHADERS
								// switch off shader
								if ((shader_info) && [shader_info objectForKey: textureKey])
								{
									glUseProgramObjectARB(0);
									glActiveTextureARB( GL_TEXTURE0_ARB);
								}
#endif
							}
						}
						else
						{
							if (displayListName != 0)
							{
								[self drawEntity: YES : translucent];
							}
							else
							{
								[self initialiseTextures];

#ifdef GNUSTEP
								// TODO: Find out what these APPLE functions can be replaced with
#else
								if (usingVAR)
									glBindVertexArrayAPPLE(gVertexArrayRangeObjects[0]);
#endif

								[self generateDisplayList];
							}
						}
					}
					else
					{
						OOLog(kOOLogFileNotFound, @"ERROR no basefile for entity %@");
					}
				}
				glShadeModel(GL_SMOOTH);
				CheckOpenGLErrors([NSString stringWithFormat:@"Entity after drawing %@", self]);

			NS_HANDLER

				OOLog(kOOLogException, @"***** [Entity drawEntity::] encountered exception: %@ : %@ *****",[localException name], [localException reason]);
				OOLog(kOOLogException, @"***** Removing entity %@ from UNIVERSE *****", self);
				[UNIVERSE removeEntity:self];
				if ([[localException name] hasPrefix:@"Oolite"])
					[UNIVERSE handleOoliteException:localException];	// handle these ourself
				else
					[localException raise];	// pass these on

			NS_ENDHANDLER
		}
	}
	else
	{
		if ((status == STATUS_COCKPIT_DISPLAY)&&((debug | debug_flag) & (DEBUG_COLLISIONS | DEBUG_OCTREE)))
			[octree drawOctree];
	
		if ((debug | debug_flag) & (DEBUG_COLLISIONS | DEBUG_OCTREE))
			[octree drawOctreeCollisions];
	
		if ((isSubentity)&&[self owner])
		{
			if (([self owner]->status == STATUS_COCKPIT_DISPLAY)&&((debug | debug_flag) & (DEBUG_COLLISIONS | DEBUG_OCTREE)))
				[octree drawOctree];
			if ((debug | debug_flag) & (DEBUG_COLLISIONS | DEBUG_OCTREE))
				[octree drawOctreeCollisions];
		}
	}
	//
	CheckOpenGLErrors([NSString stringWithFormat:@"ShipEntity after drawing Entity (main) %@", self]);
	//

	if (immediate)
		return;		// don't draw sub-entities when constructing a displayList

	if (sub_entities)
	{
		int i;
		for (i = 0; i < [sub_entities count]; i++)
		{
			Entity  *se = (Entity *)[sub_entities objectAtIndex:i];
			[se setOwner:self]; // refresh ownership
			[se drawSubEntity:immediate:translucent];
		}
	}

	//
	CheckOpenGLErrors([NSString stringWithFormat:@"ShipEntity after drawing Entity (subentities) %@", self]);
	//
}

- (void) drawSubEntity:(BOOL) immediate :(BOOL) translucent
{
	Entity* my_owner = [UNIVERSE entityForUniversalID:owner];
	if (my_owner)
	{
		// this test provides an opportunity to do simple LoD culling
		//
		zero_distance = my_owner->zero_distance;
		if (zero_distance > no_draw_distance)
		{
			return; // TOO FAR AWAY
		}
	}
	if (status == STATUS_ACTIVE)
	{
		Vector abspos = position;  // STATUS_ACTIVE means it is in control of it's own orientation
		Entity*		last = nil;
		Entity*		father = my_owner;
		GLfloat*	r_mat = [father drawRotationMatrix];
		while ((father)&&(father != last))
		{
			mult_vector_gl_matrix(&abspos, r_mat);
			Vector pos = father->position;
			abspos.x += pos.x;	abspos.y += pos.y;	abspos.z += pos.z;
			last = father;
			father = [father owner];
			r_mat = [father drawRotationMatrix];
		}
		glPopMatrix();  // one down
		glPushMatrix();
				// position and orientation is absolute
		glTranslated( abspos.x, abspos.y, abspos.z);

		glMultMatrixf(rotMatrix);

		[self drawEntity:immediate :translucent];

	}
	else
	{
		glPushMatrix();

		glTranslated( position.x, position.y, position.z);
		glMultMatrixf(rotMatrix);

		[self drawEntity:immediate :translucent];

		glPopMatrix();
	}
}

static GLfloat cargo_color[4] =		{ 0.9, 0.9, 0.9, 1.0};	// gray
static GLfloat hostile_color[4] =	{ 1.0, 0.25, 0.0, 1.0};	// red/orange
static GLfloat neutral_color[4] =	{ 1.0, 1.0, 0.0, 1.0};	// yellow
static GLfloat friendly_color[4] =	{ 0.0, 1.0, 0.0, 1.0};	// green
static GLfloat missile_color[4] =	{ 0.0, 1.0, 1.0, 1.0};	// cyan
static GLfloat police_color1[4] =	{ 0.5, 0.0, 1.0, 1.0};	// purpley-blue
static GLfloat police_color2[4] =	{ 1.0, 0.0, 0.5, 1.0};	// purpley-red
static GLfloat jammed_color[4] =	{ 0.0, 0.0, 0.0, 0.0};	// clear black
static GLfloat mascem_color1[4] =	{ 0.3, 0.3, 0.3, 1.0};	// dark gray
static GLfloat mascem_color2[4] =	{ 0.4, 0.1, 0.4, 1.0};	// purple

- (GLfloat *) scannerDisplayColorForShip:(ShipEntity*)otherShip :(BOOL)isHostile :(BOOL)flash
{

	if (has_military_jammer && military_jammer_active)
	{
		if (![otherShip hasMilitaryScannerFilter])
			return jammed_color;
		else
		{
			if (flash)
				return mascem_color1;
			else
			{
				if (isHostile)
					return hostile_color;
				else
					return mascem_color2;
			}
		}
	}

	switch (scanClass)
	{
		case CLASS_ROCK :
		case CLASS_CARGO :
			return cargo_color;
		case CLASS_THARGOID :
			if (flash)
				return hostile_color;
			else
				return friendly_color;
		case CLASS_MISSILE :
			return missile_color;
		case CLASS_STATION :
			return friendly_color;
		case CLASS_BUOY :
			if (flash)
				return friendly_color;
			else
				return neutral_color;
		case CLASS_POLICE :
		case CLASS_MILITARY :
			if ((isHostile)&&(flash))
				return police_color2;
			else
				return police_color1;
		case CLASS_MINE :
			if (flash)
				return neutral_color;
			else
				return hostile_color;
		default :
			if (isHostile)
				return hostile_color;
	}
	return neutral_color;
}

- (BOOL) isJammingScanning
{
	return (has_military_jammer && military_jammer_active);
}

- (BOOL) hasMilitaryScannerFilter
{
	return has_military_scanner_filter;
}

- (void) addExhaust:(ParticleEntity *)exhaust
{
	if (!exhaust)
		return;
	if (sub_entities == nil)
		sub_entities = [[NSArray arrayWithObject:exhaust] retain];
	else
	{
		NSMutableArray *temp = [NSMutableArray arrayWithArray:sub_entities];
		[temp addObject:exhaust];
		[sub_entities release];
		sub_entities = [[NSArray arrayWithArray:temp] retain];
	}
}

- (void) addExhaustAt:(Vector) ex_position withScale:(Vector) ex_scale
{
	ParticleEntity *exhaust = [[ParticleEntity alloc] initExhaustFromShip:self offsetVector:ex_position scaleVector:ex_scale];  //retained
	[exhaust setStatus:STATUS_EFFECT];
	[self addExhaust:exhaust];
	[exhaust release];  // released
}


- (void) applyThrust:(double) delta_t
{
	GLfloat dt_thrust = thrust * delta_t;
	GLfloat max_available_speed = (has_fuel_injection && (fuel > 1))? max_flight_speed * AFTERBURNER_FACTOR : max_flight_speed;

	position.x += delta_t*velocity.x;
	position.y += delta_t*velocity.y;
	position.z += delta_t*velocity.z;

	//
	if (thrust)
	{
		GLfloat velmag = sqrtf(magnitude2(velocity));
		if (velmag)
		{
			GLfloat vscale = (velmag - dt_thrust) / velmag;
			if (vscale < 0.0)
				vscale = 0.0;
			scale_vector(&velocity, vscale);
		}
	}

	if (behaviour == BEHAVIOUR_TUMBLE)  return;

	// check for speed
	if (desired_speed > max_available_speed)
		desired_speed = max_available_speed;

	if (flight_speed > desired_speed)
	{
		[self decrease_flight_speed: dt_thrust];
		if (flight_speed < desired_speed)   flight_speed = desired_speed;
	}
	if (flight_speed < desired_speed)
	{
		[self increase_flight_speed: dt_thrust];
		if (flight_speed > desired_speed)   flight_speed = desired_speed;
	}
	[self moveForward: delta_t*flight_speed];

	// burn fuel at the appropriate rate
	if ((flight_speed > max_flight_speed) && has_fuel_injection && (fuel > 0))
	{
		fuel_accumulator -= delta_t * AFTERBURNER_NPC_BURNRATE;
		while (fuel_accumulator < 0.0)
		{
			if (fuel-- < 1)
				max_available_speed = max_flight_speed;
			fuel_accumulator += 1.0;
		}
	}
}

- (void) applyRoll:(GLfloat) roll1 andClimb:(GLfloat) climb1
{
	Quaternion q1 = kIdentityQuaternion;

	if (!roll1 && !climb1 && !hasRotated)  return;

	if (roll1)  quaternion_rotate_about_z( &q1, -roll1);
	if (climb1)  quaternion_rotate_about_x( &q1, -climb1);

	q_rotation = quaternion_multiply( q1, q_rotation);
	quaternion_normalize(&q_rotation);	// probably not strictly necessary but good to do to keep q_rotation sane
    quaternion_into_gl_matrix(q_rotation, rotMatrix);

	v_forward   = vector_forward_from_quaternion(q_rotation);
	v_up		= vector_up_from_quaternion(q_rotation);
	v_right		= vector_right_from_quaternion(q_rotation);
}


- (void) avoidCollision
{
	if (scanClass == CLASS_MISSILE)
		return;						// missiles are SUPPOSED to collide!
	
	ShipEntity* prox_ship = [self proximity_alert];

	if (prox_ship)
	{
		if (previousCondition)
		{
			[previousCondition release];
			previousCondition = nil;
		}

		previousCondition = [(NSMutableDictionary *)[NSMutableDictionary alloc] initWithCapacity:16];

		[previousCondition setObject:[NSNumber numberWithInt:behaviour] forKey:@"behaviour"];
		[previousCondition setObject:[NSNumber numberWithInt:primaryTarget] forKey:@"primaryTarget"];
		[previousCondition setObject:[NSNumber numberWithFloat:desired_range] forKey:@"desired_range"];
		[previousCondition setObject:[NSNumber numberWithFloat:desired_speed] forKey:@"desired_speed"];
		[previousCondition setObject:[NSNumber numberWithFloat:destination.x] forKey:@"destination.x"];
		[previousCondition setObject:[NSNumber numberWithFloat:destination.y] forKey:@"destination.y"];
		[previousCondition setObject:[NSNumber numberWithFloat:destination.z] forKey:@"destination.z"];

		destination = prox_ship->position;
		destination.x += position.x;	destination.y += position.y;	destination.z += position.z;
		destination.x *= 0.5;	destination.y *= 0.5;	destination.z *= 0.5;	// point between us and them

		desired_range = prox_ship->collision_radius * PROXIMITY_AVOID_DISTANCE;

		behaviour = BEHAVIOUR_AVOID_COLLISION;
	}
}

- (void) resumePostProximityAlert
{
	if (!previousCondition)
		return;
	
	behaviour =		[(NSNumber*)[previousCondition objectForKey:@"behaviour"] intValue];
	primaryTarget =	[(NSNumber*)[previousCondition objectForKey:@"primaryTarget"] intValue];
	desired_range =	[(NSNumber*)[previousCondition objectForKey:@"desired_range"] floatValue];
	desired_speed =	[(NSNumber*)[previousCondition objectForKey:@"desired_speed"] floatValue];
	destination.x =	[(NSNumber*)[previousCondition objectForKey:@"destination.x"] floatValue];
	destination.y =	[(NSNumber*)[previousCondition objectForKey:@"destination.y"] floatValue];
	destination.z =	[(NSNumber*)[previousCondition objectForKey:@"destination.z"] floatValue];

	[previousCondition release];
	previousCondition = nil;
	frustration = 0.0;

	proximity_alert = NO_TARGET;

	//[shipAI message:@"RESTART_DOCKING"];	// if docking, start over, other AIs will ignore this message
}

- (double) message_time
{
	return message_time;
}

- (void) setMessage_time:(double) value
{
	message_time = value;
}

- (int) group_id
{
	return group_id;
}

- (void) setGroup_id:(int) value
{
	group_id = value;
}

- (int) n_escorts
{
	return n_escorts;
}

- (void) setN_escorts:(int) value
{
	n_escorts = value;
	escortsAreSetUp = (n_escorts == 0);
}

- (ShipEntity*) proximity_alert
{
	return (ShipEntity*)[UNIVERSE entityForUniversalID:proximity_alert];
}

- (void) setProximity_alert:(ShipEntity*) other
{
	if (!other)
	{
		proximity_alert = NO_TARGET;
		return;
	}

	if (isStation||(other->isStation))	// don't be alarmed close to stations
		return;

	if ((scanClass == CLASS_CARGO)||(scanClass == CLASS_BUOY)||(scanClass == CLASS_MISSILE)||(scanClass == CLASS_ROCK))	// rocks and stuff don't get alarmed easily
		return;

	// check vectors
	Vector vdiff = vector_between( position, other->position);
	GLfloat d_forward = dot_product( vdiff, v_forward);
	GLfloat d_up = dot_product( vdiff, v_up);
	GLfloat d_right = dot_product( vdiff, v_right);
	if ((d_forward > 0.0)&&(flight_speed > 0.0))	// it's ahead of us and we're moving forward
		d_forward *= 0.25 * max_flight_speed / flight_speed;	// extend the collision zone forward up to 400%
	double d2 = d_forward * d_forward + d_up * d_up + d_right * d_right;
	double cr2 = collision_radius * 2.0 + other->collision_radius;	cr2 *= cr2;	// check with twice the combined radius

	if (d2 > cr2) // we're okay
		return;

	if (behaviour == BEHAVIOUR_AVOID_COLLISION)	//	already avoiding something
	{
		ShipEntity* prox = (ShipEntity*)[UNIVERSE entityForUniversalID:proximity_alert];
		if ((prox)&&(prox != other))
		{
			// check which subtends the greatest angle
			GLfloat sa_prox = prox->collision_radius * prox->collision_radius / distance2(position, prox->position);
			GLfloat sa_other = other->collision_radius *  other->collision_radius / distance2(position, other->position);
			if (sa_prox < sa_other)  return;
		}
	}
	proximity_alert = [other universalID];
	other->proximity_alert = universalID;
}

- (NSString *) name
{
	return name;
}

- (NSString *) identFromShip:(ShipEntity*) otherShip
{
	if (has_military_jammer && military_jammer_active && (![otherShip hasMilitaryScannerFilter]))
		return @"Unknown Target";
	return name;
}

- (NSString *) roles
{
	return roles;
}

- (void) setRoles:(NSString *) value
{
	if (roles)
		[roles release];
	roles = [[NSString stringWithString:value] retain];
}

- (BOOL) hasHostileTarget
{
	if (primaryTarget == NO_TARGET)
		return NO;
	if ((behaviour == BEHAVIOUR_AVOID_COLLISION)&&(previousCondition))
	{
		int old_behaviour = [(NSNumber*)[previousCondition objectForKey:@"behaviour"] intValue];
		return IsBehaviourHostile(old_behaviour);
	}
	return IsBehaviourHostile(behaviour);
}


- (GLfloat) weapon_range
{
	return weapon_range;
}

- (void) setWeaponRange: (GLfloat) value
{
	weapon_range = value;
}

- (void) set_weapon_data_from_type: (int) weapon_type
{
	switch (weapon_type)
	{
		case WEAPON_PLASMA_CANNON :
			weapon_energy =			6.0;
			weapon_recharge_rate =	0.25;
			weapon_range =			5000;
			break;
		case WEAPON_PULSE_LASER :
			weapon_energy =			15.0;
			weapon_recharge_rate =	0.33;
			weapon_range =			12500;
			break;
		case WEAPON_BEAM_LASER :
			weapon_energy =			15.0;
			weapon_recharge_rate =	0.25;
			weapon_range =			15000;
			break;
		case WEAPON_MINING_LASER :
			weapon_energy =			50.0;
			weapon_recharge_rate =	0.5;
			weapon_range =			12500;
			break;
		case WEAPON_THARGOID_LASER :		// omni directional lasers FRIGHTENING!
			weapon_energy =			12.5;
			weapon_recharge_rate =	0.5;
			weapon_range =			17500;
			break;
		case WEAPON_MILITARY_LASER :
			weapon_energy =			23.0;
			weapon_recharge_rate =	0.20;
			weapon_range =			30000;
			break;
		case WEAPON_NONE :
			weapon_energy =			0.0;	// indicating no weapon!
			weapon_recharge_rate =	0.20;	// maximum rate
			weapon_range =			32000;
			break;
	}
}

- (GLfloat) scanner_range
{
	return scanner_range;
}

- (void) setScannerRange: (GLfloat) value
{
	scanner_range = value;
}

- (Vector) reference
{
	return reference;
}

- (void) setReference:(Vector) v
{
	reference.x = v.x;	reference.y = v.y;	reference.z = v.z;
}

- (BOOL) reportAImessages
{
	return reportAImessages;
}

- (void) setReportAImessages:(BOOL) yn
{
	reportAImessages = yn;
}


- (OOAegisStatus) checkForAegis
{
	PlanetEntity* the_planet = [UNIVERSE planet];

	if (!the_planet)
	{
		if (aegis_status != AEGIS_NONE)
			[shipAI message:@"AEGIS_NONE"];
		return AEGIS_NONE;
	}

	// check planet
	Vector p1 = the_planet->position;
	double cr = the_planet->collision_radius;
	double cr2 = cr * cr;
	OOAegisStatus result = AEGIS_NONE;
	p1.x -= position.x;	p1.y -= position.y;	p1.z -= position.z;
	double d2 = p1.x*p1.x + p1.y*p1.y + p1.z*p1.z;
	
	// check if nearing surface
	BOOL wasNearPlanetSurface = isNearPlanetSurface;
	isNearPlanetSurface = (d2 - cr2 < 3600000.0);
	if ((!wasNearPlanetSurface)&&(isNearPlanetSurface))
		[shipAI reactToMessage:@"APPROACHING_SURFACE"];
	if ((wasNearPlanetSurface)&&(!isNearPlanetSurface))
		[shipAI reactToMessage:@"LEAVING_SURFACE"];
	//
	d2 -= cr2 * 9.0; // to 3x radius of planet
	if (d2 < 0.0)
		result = AEGIS_CLOSE_TO_PLANET;
	// check station
	StationEntity* the_station = [UNIVERSE station];
	if (!the_station)
	{
		if (aegis_status != AEGIS_NONE)
			[shipAI message:@"AEGIS_NONE"];
		return AEGIS_NONE;
	}
	p1 = the_station->position;
	p1.x -= position.x;	p1.y -= position.y;	p1.z -= position.z;
	d2 = p1.x*p1.x + p1.y*p1.y + p1.z*p1.z - SCANNER_MAX_RANGE2*4.0; // double scanner range
	if (d2 < 0.0)
		result = AEGIS_IN_DOCKING_RANGE;

	// ai messages on change in status
	// approaching..
	if ((aegis_status == AEGIS_NONE)&&(result == AEGIS_CLOSE_TO_PLANET))
		[shipAI message:@"AEGIS_CLOSE_TO_PLANET"];
	if (((aegis_status == AEGIS_CLOSE_TO_PLANET)||(aegis_status == AEGIS_NONE))&&(result == AEGIS_IN_DOCKING_RANGE))
		[shipAI message:@"AEGIS_IN_DOCKING_RANGE"];
	// leaving..
	if ((aegis_status == AEGIS_IN_DOCKING_RANGE)&&(result == AEGIS_CLOSE_TO_PLANET))
		[shipAI message:@"AEGIS_LEAVING_DOCKING_RANGE"];
	if ((aegis_status != AEGIS_NONE)&&(result == AEGIS_NONE))
		[shipAI message:@"AEGIS_NONE"];

	aegis_status = result;	// put this here

	return result;
}


- (BOOL) within_station_aegis
{
	return aegis_status == AEGIS_IN_DOCKING_RANGE;
}


- (void) setStatus:(int) stat
{
	status = stat;
	if ((status == STATUS_LAUNCHING)&&(UNIVERSE))
		launch_time = [UNIVERSE getTime];
}

- (NSArray*) crew
{
	return crew;
}

- (void) setCrew: (NSArray*) crewArray
{
[crew autorelease];
	crew = [crewArray copy];
}

- (void) setStateMachine:(NSString *) ai_desc
{
	[shipAI setStateMachine: ai_desc];
}

- (void) setAI:(AI *) ai
{
	[ai retain];
	if (shipAI)
	{
		[shipAI clearAllData];
		[shipAI autorelease];
	}
	shipAI = ai;
}

- (AI *) getAI
{
	return shipAI;
}

- (int) fuel
{
	return fuel;
}

- (void) setFuel:(int) amount
{
	fuel = amount;
	if (fuel < 0)
		fuel = 0;
	if (fuel > PLAYER_MAX_FUEL)
		fuel = PLAYER_MAX_FUEL;
}

- (void) setRoll:(double) amount
{
	flight_roll = amount * M_PI / 2.0;
}

- (void) setPitch:(double) amount
{
	flight_pitch = amount * M_PI / 2.0;
}


- (void) setThrust:(double) amount
{
	thrust = amount;
}


- (void) setBounty:(OOCreditsQuantity) amount
{
	bounty = amount;
}

- (OOCreditsQuantity) getBounty
{
	return bounty;
}

- (int) legal_status
{
	if (scanClass == CLASS_THARGOID)
		return 5 * collision_radius;
	if (scanClass == CLASS_ROCK)
		return 0;
	return bounty;
}

- (void) setCommodity:(int) co_type andAmount:(int) co_amount;
{
	commodity_type = co_type;
	commodity_amount = co_amount;
}
- (int) getCommodityType
{
	return commodity_type;
}
- (int) getCommodityAmount
{
	return commodity_amount;
}

- (OOCargoQuantity) getMaxCargo
{
	return max_cargo;
}

- (OOCargoType) getCargoType
{
	return cargo_type;
}

- (NSMutableArray*) cargo
{
	return cargo;
}

- (void) setCargo:(NSArray *) some_cargo
{
	[cargo removeAllObjects];
	[cargo addObjectsFromArray:some_cargo];
}

- (OOCargoFlag) cargoFlag
{
	return cargo_flag;
}

- (void) setCargoFlag:(OOCargoFlag) flag
{
	cargo_flag = flag;
}

- (void) setSpeed:(double) amount
{
	flight_speed = amount;
}

- (void) setDesiredSpeed:(double) amount
{
	desired_speed = amount;
}

- (void) increase_flight_speed:(double) delta
{
	double factor = ((desired_speed > max_flight_speed)&&(has_fuel_injection)&&(fuel > 0)) ? AFTERBURNER_FACTOR : 1.0;

	if (flight_speed < max_flight_speed * factor)
		flight_speed += delta * factor;
	else
		flight_speed = max_flight_speed * factor;
}

- (void) decrease_flight_speed:(double) delta
{
	if (flight_speed > -max_flight_speed)
		flight_speed -= delta;
	else
		flight_speed = -max_flight_speed;
}


- (void) increase_flight_roll:(double) delta
{
	if (flight_roll < max_flight_roll)
		flight_roll += delta;
	if (flight_roll > max_flight_roll)
		flight_roll = max_flight_roll;
}

- (void) decrease_flight_roll:(double) delta
{
	if (flight_roll > -max_flight_roll)
		flight_roll -= delta;
	if (flight_roll < -max_flight_roll)
		flight_roll = -max_flight_roll;
}


- (void) increase_flight_pitch:(double) delta
{
	if (flight_pitch < max_flight_pitch)
		flight_pitch += delta;
	if (flight_pitch > max_flight_pitch)
		flight_pitch = max_flight_pitch;
}


- (void) decrease_flight_pitch:(double) delta
{
	if (flight_pitch > -max_flight_pitch)
		flight_pitch -= delta;
	if (flight_pitch < -max_flight_pitch)
		flight_pitch = -max_flight_pitch;
}

- (void) increase_flight_yaw:(double) delta
{
	if (flight_yaw < max_flight_yaw)
		flight_yaw += delta;
	if (flight_yaw > max_flight_yaw)
		flight_yaw = max_flight_yaw;
}

- (void) decrease_flight_yaw:(double) delta
{
	if (flight_yaw > -max_flight_yaw)
		flight_yaw -= delta;
	if (flight_yaw < -max_flight_yaw)
		flight_yaw = -max_flight_yaw;
}

- (GLfloat) flight_roll
{
	return flight_roll;
}

- (GLfloat) flight_pitch
{
	return flight_pitch;
}

- (GLfloat) flight_yaw
{
	return flight_yaw;
}

- (GLfloat) flight_speed
{
	return flight_speed;
}

- (GLfloat) max_flight_speed
{
	return max_flight_speed;
}

- (GLfloat) speed_factor
{
	if (max_flight_speed <= 0.0)
		return 0.0;
	return flight_speed / max_flight_speed;
}

- (void) setTemperature:(GLfloat) value
{
	ship_temperature = value;
}

- (void) setHeatInsulation:(GLfloat) value
{
	heat_insulation = value;
}


- (int) damage
{
	return (int)(100 - (100 * energy / maxEnergy));
}


- (void) dealEnergyDamageWithinDesiredRange
{
	NSArray* targets = [UNIVERSE getEntitiesWithinRange:desired_range ofEntity:self];
	if ([targets count] > 0)
	{
		int i;
		for (i = 0; i < [targets count]; i++)
		{
			Entity *e2 = [targets objectAtIndex:i];
			Vector p2 = e2->position;
			double ecr = e2->collision_radius;
			p2.x -= position.x;	p2.y -= position.y;	p2.z -= position.z;
			double d2 = p2.x*p2.x + p2.y*p2.y + p2.z*p2.z - ecr*ecr;
			double damage = weapon_energy*desired_range/d2;
			[e2 takeEnergyDamage:damage from:self becauseOf:[self owner]];
		}
	}
}

- (void) dealMomentumWithinDesiredRange:(double)amount
{
	NSArray* targets = [UNIVERSE getEntitiesWithinRange:desired_range ofEntity:self];
	if ([targets count] > 0)
	{
		int i;
		for (i = 0; i < [targets count]; i++)
		{
			ShipEntity *e2 = (ShipEntity*)[targets objectAtIndex:i];
			if (e2->isShip)
			{
				Vector p2 = e2->position;
				double ecr = e2->collision_radius;
				p2.x -= position.x;	p2.y -= position.y;	p2.z -= position.z;
				double d2 = p2.x*p2.x + p2.y*p2.y + p2.z*p2.z - ecr*ecr;
				while (d2 <= 0.0)
				{
					p2 = make_vector( randf() - 0.5, randf() - 0.5, randf() - 0.5);
					d2 = p2.x*p2.x + p2.y*p2.y + p2.z*p2.z;
				}
				double moment = amount*desired_range/d2;
				[e2 addImpactMoment:unit_vector(&p2) fraction:moment];
			}
		}
	}
}


- (BOOL) isHulk
{
	return is_hulk;
}

- (void) becomeExplosion
{
	OOCargoQuantity cargo_to_go;
	
	// check if we're destroying a subentity
	ShipEntity* parent = (ShipEntity*)[self owner];
	if ((parent)&&(parent != self)&&(parent->isShip)&&[parent->sub_entities containsObject:self])
	{
		ShipEntity* this_ship = [self retain];
		Vector this_pos = [self absolutePositionForSubentity];
		// remove this ship from its parent's subentity list
		NSMutableArray *temp = [NSMutableArray arrayWithArray:parent->sub_entities];
		[temp removeObject:this_ship];
		[parent->sub_entities autorelease];
		parent->sub_entities = [[NSArray arrayWithArray:temp] retain];
		[UNIVERSE addEntity:this_ship];
		this_ship->position = this_pos;
		[this_ship release];
	}

	Vector	xposition = position;
	ParticleEntity  *fragment;
	int i;
	Vector v;
	Quaternion q;
	int speed_low = 200;
	int n_alloys = floor(sqrtf(sqrtf(mass / 25000.0)));

	if (status == STATUS_DEAD)
	{
		[UNIVERSE removeEntity:self];
		return;
	}
	status = STATUS_DEAD;
	
	//scripting
	if (death_actions != nil)
	{
		PlayerEntity* player = [PlayerEntity sharedPlayer];

		[player setScript_target:self];
		[player scriptActions:death_actions forTarget:self];
		
		[death_actions release];
		death_actions = nil;
	}


	if ([roles isEqual:@"thargoid"])
		[self broadcastThargoidDestroyed];

	if ((mass > 200000.0f)&&(randf() < 0.25f)) // big!
	{
		// draw an expanding ring
		ParticleEntity *ring = [[ParticleEntity alloc] initHyperringFromShip:self]; // retained
		Vector ring_vel = [self velocity];
		ring_vel.x *= 0.25;	ring_vel.y *= 0.25;	ring_vel.z *= 0.25;	// quarter velocity
		[ring setVelocity:ring_vel];
		[UNIVERSE addEntity:ring];
		[ring release];
	}
	
	// several parts to the explosion:
	// 1. fast sparks
	fragment = [[ParticleEntity alloc] initFragburstSize:collision_radius FromPosition:xposition];
	[UNIVERSE addEntity:fragment];
	[fragment release];
	// 2. slow clouds
	fragment = [[ParticleEntity alloc] initBurst2Size:collision_radius FromPosition:xposition];
	[UNIVERSE addEntity:fragment];
	[fragment release];
	// 3. flash
	fragment = [[ParticleEntity alloc] initFlashSize:collision_radius FromPosition:xposition];
	[UNIVERSE addEntity:fragment];
	[fragment release];

	BOOL add_more_explosion = YES;
	if (UNIVERSE)
	{
		add_more_explosion &= (UNIVERSE->n_entities < 0.95 * UNIVERSE_MAX_ENTITIES);	// 
		add_more_explosion &= ([UNIVERSE getTimeDelta] < 0.125);						// FPS > 8
	}
	// quick - check if UNIVERSE is nearing limit for entities - if it is don't add to it!
	//
	if (add_more_explosion)
	{
		// we need to throw out cargo at this point.
		NSArray *jetsam = nil;  // this will contain the stuff to get thrown out
		int cargo_chance = 10;
		if ([[name lowercaseString] rangeOfString:@"medical"].location != NSNotFound)
		{
			cargo_to_go = max_cargo * cargo_chance / 100;
			while (cargo_to_go > 15)
				cargo_to_go = ranrot_rand() % cargo_to_go;
			[self setCargo:[UNIVERSE getContainersOfDrugs:cargo_to_go]];
			cargo_chance = 100;  //  chance of any given piece of cargo surviving decompression
			cargo_flag = CARGO_FLAG_CANISTERS;
		}
		
		cargo_to_go = max_cargo * cargo_chance / 100;
		while (cargo_to_go > 15)
			cargo_to_go = ranrot_rand() % cargo_to_go;
		cargo_chance = 100;  //  chance of any given piece of cargo surviving decompression
		switch (cargo_flag)
		{
			case CARGO_FLAG_NONE:
			case CARGO_FLAG_FULL_PASSENGERS:
				break;
			
			case CARGO_FLAG_FULL_UNIFORM :
				{
					NSString* commodity_name = (NSString*)[shipinfoDictionary objectForKey:@"cargo_carried"];
					jetsam = [UNIVERSE getContainersOfCommodity:commodity_name :cargo_to_go];
				}
				break;

			case CARGO_FLAG_FULL_PLENTIFUL :
				jetsam = [UNIVERSE getContainersOfPlentifulGoods:cargo_to_go];
				break;

			case CARGO_FLAG_PIRATE :
				cargo_to_go = likely_cargo;
				while (cargo_to_go > 15)
					cargo_to_go = ranrot_rand() % cargo_to_go;
				cargo_chance = 65;	// 35% chance of spoilage
				jetsam = [UNIVERSE getContainersOfScarceGoods:cargo_to_go];
				break;

			case CARGO_FLAG_FULL_SCARCE :
				jetsam = [UNIVERSE getContainersOfScarceGoods:cargo_to_go];
				break;

			case CARGO_FLAG_CANISTERS:
				jetsam = [NSArray arrayWithArray:cargo];   // what the ship is carrying
				[cargo removeAllObjects];   // dispense with it!
				break;
		}

		//  Throw out cargo
		//
		if (jetsam)
		{
			int n_jetsam = [jetsam count];
			//
			for (i = 0; i < n_jetsam; i++)
			{
				if (ranrot_rand() % 100 < cargo_chance)  //  chance of any given piece of cargo surviving decompression
				{
					ShipEntity* container = [jetsam objectAtIndex:i];
					Vector  rpos = xposition;
					Vector	rrand = randomPositionInBoundingBox(boundingBox);
					rpos.x += rrand.x;	rpos.y += rrand.y;	rpos.z += rrand.z;
					rpos.x += (ranrot_rand() % 7) - 3;
					rpos.y += (ranrot_rand() % 7) - 3;
					rpos.z += (ranrot_rand() % 7) - 3;
					[container setPosition:rpos];
					v.x = 0.1 *((ranrot_rand() % speed_low) - speed_low / 2);
					v.y = 0.1 *((ranrot_rand() % speed_low) - speed_low / 2);
					v.z = 0.1 *((ranrot_rand() % speed_low) - speed_low / 2);
					[container setVelocity:v];
					quaternion_set_random(&q);
					[container setQRotation:q];
					[container setStatus:STATUS_IN_FLIGHT];
					[container setScanClass: CLASS_CARGO];
					[UNIVERSE addEntity:container];
					[[container getAI] setState:@"GLOBAL"];
				}
			}
		}

		//  Throw out rocks and alloys to be scooped up
		//
		if ([roles isEqual:@"asteroid"])
		{
			if ((being_mined)||(randf() < 0.20))
			{
				int n_rocks = likely_cargo;
				//
				for (i = 0; i < n_rocks; i++)
				{
					ShipEntity* rock = [UNIVERSE newShipWithRole:@"boulder"];   // retain count = 1
					if (rock)
					{
						Vector  rpos = xposition;
						int  r_speed = 20.0 * [rock max_flight_speed];
						int cr = 3 * rock->collision_radius;
						rpos.x += (ranrot_rand() % cr) - cr/2;
						rpos.y += (ranrot_rand() % cr) - cr/2;
						rpos.z += (ranrot_rand() % cr) - cr/2;
						[rock setPosition:rpos];
						v.x = 0.1 *((ranrot_rand() % r_speed) - r_speed / 2);
						v.y = 0.1 *((ranrot_rand() % r_speed) - r_speed / 2);
						v.z = 0.1 *((ranrot_rand() % r_speed) - r_speed / 2);
						[rock setVelocity:v];
						quaternion_set_random(&q);
						[rock setQRotation:q];
						[rock setStatus:STATUS_IN_FLIGHT];
						[rock setScanClass: CLASS_ROCK];
						[UNIVERSE addEntity:rock];
						[[rock getAI] setState:@"GLOBAL"];
						[rock release];
					}
				}
			}
			[UNIVERSE removeEntity:self];
			return; // don't do anything more
		}

		if ([roles isEqual:@"boulder"])
		{
			if ((being_mined)||(ranrot_rand() % 100 < 20))
			{
				int n_rocks = 2 + (ranrot_rand() % 5);
				//
				for (i = 0; i < n_rocks; i++)
				{
					ShipEntity* rock = [UNIVERSE newShipWithRole:@"splinter"];   // retain count = 1
					if (rock)
					{
						Vector  rpos = xposition;
						int  r_speed = 20.0 * [rock max_flight_speed];
						int cr = 3 * rock->collision_radius;
						rpos.x += (ranrot_rand() % cr) - cr/2;
						rpos.y += (ranrot_rand() % cr) - cr/2;
						rpos.z += (ranrot_rand() % cr) - cr/2;
						[rock setPosition:rpos];
						v.x = 0.1 *((ranrot_rand() % r_speed) - r_speed / 2);
						v.y = 0.1 *((ranrot_rand() % r_speed) - r_speed / 2);
						v.z = 0.1 *((ranrot_rand() % r_speed) - r_speed / 2);
						[rock setBounty: 0];
						[rock setCommodity:[UNIVERSE commodityForName:@"Minerals"] andAmount: 1];
						[rock setVelocity:v];
						quaternion_set_random(&q);
						[rock setQRotation:q];
						[rock setStatus:STATUS_IN_FLIGHT];
						[rock setScanClass: CLASS_CARGO];
						[UNIVERSE addEntity:rock];
						[[rock getAI] setState:@"GLOBAL"];
						[rock release];
					}
				}
			}
			[UNIVERSE removeEntity:self];
			return; // don't do anything more
		}

		// throw out burning chunks of wreckage
		//
		if (n_alloys && canFragment)
		{
			int n_wreckage = (n_alloys < 3)? n_alloys : 3;
			
			// quick - check if UNIVERSE is nearing limit for entities - if it is don't make wreckage
			//
			add_more_explosion &= (UNIVERSE->n_entities < 0.50 * UNIVERSE_MAX_ENTITIES);
			if (!add_more_explosion)
				n_wreckage = 0;
			//
			////
			
			for (i = 0; i < n_wreckage; i++)
			{
				ShipEntity* wreck = [UNIVERSE newShipWithRole:@"wreckage"];   // retain count = 1
				if (wreck)
				{
					GLfloat expected_mass = 0.1f * mass * (0.75 + 0.5 * randf());
					GLfloat wreck_mass = [wreck mass];
					GLfloat scale_factor = powf(expected_mass / wreck_mass, 0.33333333f);	// cube root of volume ratio
					[wreck rescaleBy: scale_factor];
					
					Vector r1 = randomFullNodeFrom([octree octreeDetails], kZeroVector);
					Vector rpos = make_vector ( v_right.x * r1.x + v_up.x * r1.y + v_forward.x * r1.z,
												v_right.y * r1.x + v_up.y * r1.y + v_forward.y * r1.z,
												v_right.z * r1.x + v_up.z * r1.y + v_forward.z * r1.z);
					rpos.x += xposition.x;
					rpos.y += xposition.y;
					rpos.z += xposition.z;
					[wreck setPosition:rpos];
					
					[wreck setVelocity:[self velocity]];

					quaternion_set_random(&q);
					[wreck setQRotation:q];
					
					[wreck setTemperature: 1000.0];		// take 1000e heat damage per second
					[wreck setHeatInsulation: 1.0e7];	// very large! so it won't cool down
					[wreck setEnergy: 750.0 * randf() + 250.0 * i + 100.0];	// burn for 0.25s -> 1.25s
					
					[wreck setStatus:STATUS_IN_FLIGHT];
					[UNIVERSE addEntity: wreck];
					[wreck performTumble];
					[wreck release];
				}
			}
			n_alloys = ranrot_rand() % n_alloys;
		}

		// Throw out scrap metal
		//
		for (i = 0; i < n_alloys; i++)
		{
			ShipEntity* plate = [UNIVERSE newShipWithRole:@"alloy"];   // retain count = 1
			if (plate)
			{
				Vector  rpos = xposition;
				Vector	rrand = randomPositionInBoundingBox(boundingBox);
				rpos.x += rrand.x;	rpos.y += rrand.y;	rpos.z += rrand.z;
				rpos.x += (ranrot_rand() % 7) - 3;
				rpos.y += (ranrot_rand() % 7) - 3;
				rpos.z += (ranrot_rand() % 7) - 3;
				[plate setPosition:rpos];
				v.x = 0.1 *((ranrot_rand() % speed_low) - speed_low / 2);
				v.y = 0.1 *((ranrot_rand() % speed_low) - speed_low / 2);
				v.z = 0.1 *((ranrot_rand() % speed_low) - speed_low / 2);
				[plate setVelocity:v];
				quaternion_set_random(&q);
				[plate setQRotation:q];
				[plate setScanClass: CLASS_CARGO];
				[plate setCommodity:9 andAmount:1];
				[UNIVERSE addEntity:plate];
				[plate setStatus:STATUS_IN_FLIGHT];
				[[plate getAI] setState:@"GLOBAL"];
				[plate release];
			}
		}
	}
	
	//
	if (sub_entities)
	{
		int i;
		for (i = 0; i < [sub_entities count]; i++)
		{
			Entity*		se = (Entity *)[sub_entities objectAtIndex:i];
			if (se->isShip)
			{
				Vector  origin = [(ShipEntity*)se absolutePositionForSubentity];
				[se setPosition:origin];	// is this what's messing thing up??
				[UNIVERSE addEntity:se];
				[(ShipEntity *)se becomeExplosion];
			}
		}
		[sub_entities release]; // releases each subentity too!
		sub_entities = nil;
	}

	// momentum from explosions
	desired_range = collision_radius * 2.5;
	[self dealMomentumWithinDesiredRange: 0.125 * mass];

	//
	if (self != [PlayerEntity sharedPlayer])	// was if !isPlayer - but I think this may cause ghosts
		[UNIVERSE removeEntity:self];
}

- (void) becomeEnergyBlast
{
	ParticleEntity* blast = [[ParticleEntity alloc] initEnergyMineFromShip:self];
	[UNIVERSE addEntity:blast];
	[blast setOwner: [self owner]];
	[blast release];
	[UNIVERSE removeEntity:self];
}

Vector randomPositionInBoundingBox(BoundingBox bb)
{
	Vector result;
	result.x = bb.min.x + randf() * (bb.max.x - bb.min.x);
	result.y = bb.min.y + randf() * (bb.max.y - bb.min.y);
	result.z = bb.min.z + randf() * (bb.max.z - bb.min.z);
	return result;
}

- (Vector) positionOffsetForAlignment:(NSString*) align
{
	NSString* padAlign = [NSString stringWithFormat:@"%@---", align];
	Vector result = kZeroVector;
	switch ([padAlign characterAtIndex:0])
	{
		case (unichar)'c':
		case (unichar)'C':
			result.x = 0.5 * (boundingBox.min.x + boundingBox.max.x);
			break;
		case (unichar)'M':
			result.x = boundingBox.max.x;
			break;
		case (unichar)'m':
			result.x = boundingBox.min.x;
			break;
	}
	switch ([padAlign characterAtIndex:1])
	{
		case (unichar)'c':
		case (unichar)'C':
			result.y = 0.5 * (boundingBox.min.y + boundingBox.max.y);
			break;
		case (unichar)'M':
			result.y = boundingBox.max.y;
			break;
		case (unichar)'m':
			result.y = boundingBox.min.y;
			break;
	}
	switch ([padAlign characterAtIndex:2])
	{
		case (unichar)'c':
		case (unichar)'C':
			result.z = 0.5 * (boundingBox.min.z + boundingBox.max.z);
			break;
		case (unichar)'M':
			result.z = boundingBox.max.z;
			break;
		case (unichar)'m':
			result.z = boundingBox.min.z;
			break;
	}
	return result;
}

Vector positionOffsetForShipInRotationToAlignment(ShipEntity* ship, Quaternion q, NSString* align)
{
	NSString* padAlign = [NSString stringWithFormat:@"%@---", align];
	Vector i = vector_right_from_quaternion(q);
	Vector j = vector_up_from_quaternion(q);
	Vector k = vector_forward_from_quaternion(q);
	BoundingBox arbb = [ship findBoundingBoxRelativeToPosition: make_vector(0,0,0) InVectors: i : j : k];
	Vector result = kZeroVector;
	switch ([padAlign characterAtIndex:0])
	{
		case (unichar)'c':
		case (unichar)'C':
			result.x = 0.5 * (arbb.min.x + arbb.max.x);
			break;
		case (unichar)'M':
			result.x = arbb.max.x;
			break;
		case (unichar)'m':
			result.x = arbb.min.x;
			break;
	}
	switch ([padAlign characterAtIndex:1])
	{
		case (unichar)'c':
		case (unichar)'C':
			result.y = 0.5 * (arbb.min.y + arbb.max.y);
			break;
		case (unichar)'M':
			result.y = arbb.max.y;
			break;
		case (unichar)'m':
			result.y = arbb.min.y;
			break;
	}
	switch ([padAlign characterAtIndex:2])
	{
		case (unichar)'c':
		case (unichar)'C':
			result.z = 0.5 * (arbb.min.z + arbb.max.z);
			break;
		case (unichar)'M':
			result.z = arbb.max.z;
			break;
		case (unichar)'m':
			result.z = arbb.min.z;
			break;
	}
	return result;
}

- (void) becomeLargeExplosion:(double) factor
{
	Vector xposition = position;
	ParticleEntity  *fragment;
	OOCargoQuantity n_cargo = (ranrot_rand() % (likely_cargo + 1));
	OOCargoQuantity cargo_to_go;

	if (status == STATUS_DEAD)
		return;

	status = STATUS_DEAD;
	//scripting
	if (death_actions != nil)
	{
		PlayerEntity* player = [PlayerEntity sharedPlayer];

		[player setScript_target:self];
		[player scriptActions:death_actions forTarget:self];
		
		[death_actions release];
		death_actions = nil;
	}

	// two parts to the explosion:
	// 1. fast sparks
	float how_many = factor;
	while (how_many > 0.5f)
	{
	//	fragment = [[ParticleEntity alloc] initFragburstFromPosition:xposition];
		fragment = [[ParticleEntity alloc] initFragburstSize: collision_radius FromPosition:xposition];
		[UNIVERSE addEntity:fragment];
		[fragment release];
		how_many -= 1.0f;
	}
	// 2. slow clouds
	how_many = factor;
	while (how_many > 0.5f)
	{
		fragment = [[ParticleEntity alloc] initBurst2Size: collision_radius FromPosition:xposition];
		[UNIVERSE addEntity:fragment];
		[fragment release];
		how_many -= 1.0f;
	}


	// we need to throw out cargo at this point.
	int cargo_chance = 10;
	if ([[name lowercaseString] rangeOfString:@"medical"].location != NSNotFound)
	{
		cargo_to_go = max_cargo * cargo_chance / 100;
		while (cargo_to_go > 15)
			cargo_to_go = ranrot_rand() % cargo_to_go;
		[self setCargo:[UNIVERSE getContainersOfDrugs:cargo_to_go]];
		cargo_chance = 100;  //  chance of any given piece of cargo surviving decompression
		cargo_flag = CARGO_FLAG_CANISTERS;
	}
	if (cargo_flag == CARGO_FLAG_FULL_PLENTIFUL)
	{
		cargo_to_go = max_cargo / 10;
		while (cargo_to_go > 15)
			cargo_to_go = ranrot_rand() % cargo_to_go;
		[self setCargo:[UNIVERSE getContainersOfPlentifulGoods:cargo_to_go]];
		cargo_chance = 100;
	}
	if (cargo_flag == CARGO_FLAG_FULL_SCARCE)
	{
		cargo_to_go = max_cargo / 10;
		while (cargo_to_go > 15)
			cargo_to_go = ranrot_rand() % cargo_to_go;
		[self setCargo:[UNIVERSE getContainersOfScarceGoods:cargo_to_go]];
		cargo_chance = 100;
	}
	while ([cargo count] > 0)
	{
		if (ranrot_rand() % 100 < cargo_chance)  //  10% chance of any given piece of cargo surviving decompression
		{
			ShipEntity* container = [[cargo objectAtIndex:0] retain];
			Vector  rpos = xposition;
			Vector	rrand = randomPositionInBoundingBox(boundingBox);
			rpos.x += rrand.x;	rpos.y += rrand.y;	rpos.z += rrand.z;
			rpos.x += (ranrot_rand() % 7) - 3;
			rpos.y += (ranrot_rand() % 7) - 3;
			rpos.z += (ranrot_rand() % 7) - 3;
			[container setPosition:rpos];
			[container setScanClass: CLASS_CARGO];
			[UNIVERSE addEntity:container];
			[[container getAI] setState:@"GLOBAL"];
			[container setStatus:STATUS_IN_FLIGHT];
			[container release];
			if (n_cargo > 0)
				n_cargo--;  // count down extra cargo
		}
		[cargo removeObjectAtIndex:0];
	}
	//

	if (!isPlayer)
		[UNIVERSE removeEntity:self];
}

- (void) collectBountyFor:(ShipEntity *)other
{
	if ([roles isEqual:@"pirate"])
		bounty += [other getBounty];
}

- (NSComparisonResult) compareBeaconCodeWith:(ShipEntity*) other
{
	return [[self beaconCode] compare:[other beaconCode] options: NSCaseInsensitiveSearch];
}


- (GLfloat)laserHeatLevel
{
	return (weapon_recharge_rate - shot_time) / weapon_recharge_rate;
}


- (GLfloat)hullHeatLevel
{
	return ship_temperature / (GLfloat)SHIP_MAX_CABIN_TEMP;
}

/*-----------------------------------------

	AI piloting methods

-----------------------------------------*/

BOOL	class_masslocks(int some_class)
{
	switch (some_class)
	{
		case CLASS_BUOY :
		case CLASS_ROCK :
		case CLASS_CARGO :
		case CLASS_MINE :
		case CLASS_NO_DRAW :
			return NO;
			break;
		case CLASS_THARGOID :
		case CLASS_MISSILE :
		case CLASS_STATION :
		case CLASS_POLICE :
		case CLASS_MILITARY :
		case CLASS_WORMHOLE :
		default :
			return YES;
			break;
	}
	return YES;
}

- (BOOL) checkTorusJumpClear
{
	Entity* scan;
	//
	scan = z_previous;	while ((scan)&&(!class_masslocks( scan->scanClass)))	scan = scan->z_previous;	// skip non-mass-locking
	while ((scan)&&(scan->position.z > position.z - scanner_range))
	{
		if (class_masslocks( scan->scanClass) && (distance2( position, scan->position) < SCANNER_MAX_RANGE2))
			return NO;
		scan = scan->z_previous;	while ((scan)&&(!class_masslocks( scan->scanClass)))	scan = scan->z_previous;
	}
	scan = z_next;	while ((scan)&&(!class_masslocks( scan->scanClass)))	scan = scan->z_next;	// skip non-mass-locking
	while ((scan)&&(scan->position.z < position.z + scanner_range))
	{
		if (class_masslocks( scan->scanClass) && (distance2( position, scan->position) < SCANNER_MAX_RANGE2))
			return NO;
		scan = scan->z_previous;	while ((scan)&&(!class_masslocks( scan->scanClass)))	scan = scan->z_previous;
	}
	return YES;
}

- (void) checkScanner
{
	Entity* scan;
	n_scanned_ships = 0;
	//
	scan = z_previous;	while ((scan)&&(scan->isShip == NO))	scan = scan->z_previous;	// skip non-ships
	while ((scan)&&(scan->position.z > position.z - scanner_range)&&(n_scanned_ships < MAX_SCAN_NUMBER))
	{
		if (scan->isShip)
		{
			distance2_scanned_ships[n_scanned_ships] = distance2( position, scan->position);
			if (distance2_scanned_ships[n_scanned_ships] < SCANNER_MAX_RANGE2)
				scanned_ships[n_scanned_ships++] = (ShipEntity*)scan;
		}
		scan = scan->z_previous;	while ((scan)&&(scan->isShip == NO))	scan = scan->z_previous;
	}
	//
	scan = z_next;	while ((scan)&&(scan->isShip == NO))	scan = scan->z_next;	// skip non-ships
	while ((scan)&&(scan->position.z < position.z + scanner_range)&&(n_scanned_ships < MAX_SCAN_NUMBER))
	{
		if (scan->isShip)
		{
			distance2_scanned_ships[n_scanned_ships] = distance2( position, scan->position);
			if (distance2_scanned_ships[n_scanned_ships] < SCANNER_MAX_RANGE2)
				scanned_ships[n_scanned_ships++] = (ShipEntity*)scan;
		}
		scan = scan->z_next;	while ((scan)&&(scan->isShip == NO))	scan = scan->z_next;	// skip non-ships
	}
	//
	scanned_ships[n_scanned_ships] = nil;	// terminate array
}

- (ShipEntity**) scannedShips
{
	scanned_ships[n_scanned_ships] = nil;	// terminate array
	return scanned_ships;
}

- (int) numberOfScannedShips
{
	return n_scanned_ships;
}


- (void) setFound_target:(Entity *) targetEntity
{
	if (targetEntity)
		found_target = [targetEntity universalID];
}

- (void) setPrimaryAggressor:(Entity *) targetEntity
{
	if (targetEntity)
		primaryAggressor = [targetEntity universalID];
}

- (void) addTarget:(Entity *) targetEntity
{
	if (targetEntity)
		primaryTarget = [targetEntity universalID];
	if (sub_entities)
	{
		int i;
		for (i = 0; i < [sub_entities count]; i++)
		{
			Entity* se = [sub_entities objectAtIndex:i];
			if (se->isShip)
				[(ShipEntity *)se addTarget:targetEntity];
		}
	}
}

- (void) removeTarget:(Entity *) targetEntity
{
	if (primaryTarget != NO_TARGET)
		[shipAI reactToMessage:@"TARGET_LOST"];
	primaryTarget = NO_TARGET;
	if (sub_entities)
	{
		int i;
		for (i = 0; i < [sub_entities count]; i++)
		{
			Entity* se = [sub_entities objectAtIndex:i];
			if (se->isShip)
				[(ShipEntity *)se removeTarget:targetEntity];
		}
	}
}

- (Entity *) getPrimaryTarget
{
	return [UNIVERSE entityForUniversalID:primaryTarget];
}

- (int) getPrimaryTargetID
{
	return primaryTarget;
}

- (OOBehaviour) behaviour
{
	return behaviour;
}

- (void) setBehaviour:(OOBehaviour) cond
{
	if (cond != behaviour)
	{
		frustration = 0.0;	// change is a GOOD thing
		behaviour = cond;
	}
}

- (Vector) destination
{
	return destination;
}

- (Vector) one_km_six
{
	Vector six = position;
	six.x -= 1000 * v_forward.x;	six.y -= 1000 * v_forward.y;	six.z -= 1000 * v_forward.z;
	return six;
}

- (Vector) distance_six: (GLfloat) dist
{
	Vector six = position;
	six.x -= dist * v_forward.x;	six.y -= dist * v_forward.y;	six.z -= dist * v_forward.z;
	return six;
}

- (Vector) distance_twelve: (GLfloat) dist
{
	Vector twelve = position;
	twelve.x += dist * v_up.x;	twelve.y += dist * v_up.y;	twelve.z += dist * v_up.z;
	return twelve;
}

- (double) ballTrackTarget:(double) delta_t
{
	Vector vector_to_target;
	Vector axis_to_track_by;
	Vector my_position = position;  // position relative to parent
	Vector my_aim = vector_forward_from_quaternion(q_rotation);
	Vector my_ref = reference;
	double aim_cos, ref_cos;
	
	Entity* targent = [self getPrimaryTarget];
	
	Entity*		last = nil;
	Entity*		father = [self owner];
	GLfloat*	r_mat = [father drawRotationMatrix];
	while ((father)&&(father != last))
	{
		mult_vector_gl_matrix(&my_position, r_mat);
		mult_vector_gl_matrix(&my_ref, r_mat);
		Vector pos = father->position;
		my_position.x += pos.x;	my_position.y += pos.y;	my_position.z += pos.z;
		last = father;
		father = [father owner];
		r_mat = [father drawRotationMatrix];
	}

	if (targent)
	{
		vector_to_target = targent->position;
		//
		vector_to_target.x -= my_position.x;	vector_to_target.y -= my_position.y;	vector_to_target.z -= my_position.z;
		if (vector_to_target.x||vector_to_target.y||vector_to_target.z)
			vector_to_target = unit_vector(&vector_to_target);
		else
			vector_to_target.z = 1.0;
		//
		// do the tracking!
		aim_cos = dot_product(vector_to_target, my_aim);
		ref_cos = dot_product(vector_to_target, my_ref);
	}
	else
	{
		aim_cos = 0.0;
		ref_cos = -1.0;
	}

	if (ref_cos > TURRET_MINIMUM_COS)  // target is forward of self
	{
		axis_to_track_by = cross_product(vector_to_target, my_aim);
	}
	else
	{
		aim_cos = 0.0;
		axis_to_track_by = cross_product(my_ref, my_aim);	//	return to center
	}

	quaternion_rotate_about_axis( &q_rotation, axis_to_track_by, thrust * delta_t);

	quaternion_normalize(&q_rotation);
	quaternion_into_gl_matrix(q_rotation, rotMatrix);

	status = STATUS_ACTIVE;

	return aim_cos;
}

- (void) trackOntoTarget:(double) delta_t withDForward: (GLfloat) dp
{
	Vector vector_to_target;
	Quaternion q_minarc;
	//
	Entity* targent = [self getPrimaryTarget];
	//
	if (!targent)
		return;

	vector_to_target = targent->position;
	vector_to_target.x -= position.x;	vector_to_target.y -= position.y;	vector_to_target.z -= position.z;
	//
	GLfloat range2 =		magnitude2( vector_to_target);
	GLfloat	targetRadius =	0.75 * targent->actual_radius;
	GLfloat	max_cos =		sqrt(1 - targetRadius*targetRadius/range2);
	//
	if (dp > max_cos)
		return;	// ON TARGET!
	//
	if (vector_to_target.x||vector_to_target.y||vector_to_target.z)
		vector_to_target = unit_vector(&vector_to_target);
	else
		vector_to_target.z = 1.0;
	//
	q_minarc = quaternion_rotation_between( v_forward, vector_to_target);
	//
	q_rotation = quaternion_multiply( q_minarc, q_rotation);
    quaternion_normalize(&q_rotation);
    quaternion_into_gl_matrix(q_rotation, rotMatrix);
	//
	flight_roll = 0.0;
	flight_pitch = 0.0;
}

- (double) ballTrackLeadingTarget:(double) delta_t
{
	Vector vector_to_target;
	Vector axis_to_track_by;
	Vector my_position = position;  // position relative to parent
	Vector my_aim = vector_forward_from_quaternion(q_rotation);
	Vector my_ref = reference;
	double aim_cos, ref_cos;
	//
	Entity* targent = [self getPrimaryTarget];
	//
	Vector leading = [targent velocity];
	
	Entity*		last = nil;
	Entity*		father = [self owner];
	GLfloat*	r_mat = [father drawRotationMatrix];
	while ((father)&&(father != last))
	{
		mult_vector_gl_matrix(&my_position, r_mat);
		mult_vector_gl_matrix(&my_ref, r_mat);
		Vector pos = father->position;
		my_position.x += pos.x;	my_position.y += pos.y;	my_position.z += pos.z;
		last = father;
		father = [father owner];
		r_mat = [father drawRotationMatrix];
	}

	if (targent)
	{
		vector_to_target = targent->position;
		//
		vector_to_target.x -= my_position.x;	vector_to_target.y -= my_position.y;	vector_to_target.z -= my_position.z;
		//
		float lead = sqrt(magnitude2(vector_to_target)) / TURRET_SHOT_SPEED;
		//
		vector_to_target.x += lead * leading.x;	vector_to_target.y += lead * leading.y;	vector_to_target.z += lead * leading.z;
		if (vector_to_target.x||vector_to_target.y||vector_to_target.z)
			vector_to_target = unit_vector(&vector_to_target);
		else
			vector_to_target.z = 1.0;
		//
		// do the tracking!
		aim_cos = dot_product(vector_to_target, my_aim);
		ref_cos = dot_product(vector_to_target, my_ref);
	}
	else
	{
		aim_cos = 0.0;
		ref_cos = -1.0;
	}

	if (ref_cos > TURRET_MINIMUM_COS)  // target is forward of self
	{
		axis_to_track_by = cross_product(vector_to_target, my_aim);
	}
	else
	{
		aim_cos = 0.0;
		axis_to_track_by = cross_product(my_ref, my_aim);	//	return to center
	}

	quaternion_rotate_about_axis( &q_rotation, axis_to_track_by, thrust * delta_t);

	quaternion_normalize(&q_rotation);
	quaternion_into_gl_matrix(q_rotation, rotMatrix);

	status = STATUS_ACTIVE;

	return aim_cos;
}


- (double) trackPrimaryTarget:(double) delta_t :(BOOL) retreat
{
	Entity*	target = [self getPrimaryTarget];

	if (!target)   // leave now!
	{
		[shipAI message:@"TARGET_LOST"];
		return 0.0;
	}

	if (scanClass == CLASS_MISSILE)
		return [self missileTrackPrimaryTarget: delta_t];

	GLfloat  d_forward, d_up, d_right;
	
	Vector  relPos = vector_subtract(target->position, position);
	double	range2 = magnitude2(relPos);

	if (range2 > SCANNER_MAX_RANGE2)
	{
		[shipAI message:@"TARGET_LOST"];
		return 0.0;
	}

	//jink if retreating
	if (retreat && (range2 > 250000.0))	// don't jink if closer than 500m - just RUN
	{
		Vector vx, vy, vz;
		if (target->isShip)
		{
			ShipEntity* targetShip = (ShipEntity*)target;
			vx = targetShip->v_right;
			vy = targetShip->v_up;
			vz = targetShip->v_forward;
		}
		else
		{
			Quaternion q = target->q_rotation;
			vx = vector_right_from_quaternion(q);
			vy = vector_up_from_quaternion(q);
			vz = vector_forward_from_quaternion(q);
		}
		relPos.x += jink.x * vx.x + jink.y * vy.x + jink.z * vz.x;
		relPos.y += jink.x * vx.y + jink.y * vy.y + jink.z * vz.y;
		relPos.z += jink.x * vx.z + jink.y * vy.z + jink.z * vz.z;
	}

	if (!vector_equal(relPos, kZeroVector))  relPos = vector_normal(relPos);
	else  relPos.z = 1.0;

	double	targetRadius = 0.75 * target->actual_radius;

	double	max_cos = sqrt(1 - targetRadius*targetRadius/range2);

	double  rate2 = 4.0 * delta_t;
	double  rate1 = 2.0 * delta_t;

	double stick_roll = 0.0;	//desired roll and pitch
	double stick_pitch = 0.0;

	double reverse = (retreat)? -1.0: 1.0;

	double min_d = 0.004;

	d_right		=   dot_product(relPos, v_right);
	d_up		=   dot_product(relPos, v_up);
	d_forward   =   dot_product(relPos, v_forward);	// == cos of angle between v_forward and vector to target

	if (d_forward * reverse > max_cos)	// on_target!
		return d_forward;

	// begin rule-of-thumb manoeuvres
	stick_pitch = 0.0;
	stick_roll = 0.0;


	if ((reverse * d_forward < -0.5) && !pitching_over) // we're going the wrong way!
		pitching_over = YES;

	if (pitching_over)
	{
		if (reverse * d_up > 0) // pitch up
			stick_pitch = -max_flight_pitch;
		else
			stick_pitch = max_flight_pitch;
		pitching_over = (reverse * d_forward < 0.707);
	}

	// treat missiles specially
	if ((scanClass == CLASS_MISSILE) && (d_forward > cos( delta_t * max_flight_pitch)))
	{
		NSLog(@"missile %@ in tracking mode", self);
		[self trackOntoTarget: delta_t withDForward: d_forward];
		return d_forward;
	}

	// check if we are flying toward the destination..
	if ((d_forward < max_cos)||(retreat))	// not on course so we must adjust controls..
	{
		if (d_forward < -max_cos)  // hack to avoid just flying away from the destination
		{
			d_up = min_d * 2.0;
		}

		if (d_up > min_d)
		{
			int factor = sqrt( fabs(d_right) / fabs(min_d));
			if (factor > 8)
				factor = 8;
			if (d_right > min_d)
				stick_roll = - max_flight_roll * reverse * 0.125 * factor;
			if (d_right < -min_d)
				stick_roll = + max_flight_roll * reverse * 0.125 * factor;
		}
		if (d_up < -min_d)
		{
			int factor = sqrt( fabs(d_right) / fabs(min_d));
			if (factor > 8)
				factor = 8;
			if (d_right > min_d)
				stick_roll = + max_flight_roll * reverse * 0.125 * factor;
			if (d_right < -min_d)
				stick_roll = - max_flight_roll * reverse * 0.125 * factor;
		}

		if (stick_roll == 0.0)
		{
			int factor = sqrt( fabs(d_up) / fabs(min_d));
			if (factor > 8)
				factor = 8;
			if (d_up > min_d)
				stick_pitch = - max_flight_pitch * reverse * 0.125 * factor;
			if (d_up < -min_d)
				stick_pitch = + max_flight_pitch * reverse * 0.125 * factor;
		}
	}

	// end rule-of-thumb manoeuvres

	// apply 'quick-stop' to roll and pitch adjustments
	if (((stick_roll > 0.0)&&(flight_roll < 0.0))||((stick_roll < 0.0)&&(flight_roll > 0.0)))
		rate1 *= 4.0;	// much faster correction
	if (((stick_pitch > 0.0)&&(flight_pitch < 0.0))||((stick_pitch < 0.0)&&(flight_pitch > 0.0)))
		rate2 *= 4.0;	// much faster correction

	// apply stick movement limits
	if (flight_roll < stick_roll - rate1)
		stick_roll = flight_roll + rate1;
	if (flight_roll > stick_roll + rate1)
		stick_roll = flight_roll - rate1;
	if (flight_pitch < stick_pitch - rate2)
		stick_pitch = flight_pitch + rate2;
	if (flight_pitch > stick_pitch + rate2)
		stick_pitch = flight_pitch - rate2;

	// apply stick to attitude control
	flight_roll = stick_roll;
	flight_pitch = stick_pitch;

	if (retreat)
		d_forward *= d_forward;	// make positive AND decrease granularity

	if (d_forward < 0.0)
		return 0.0;

	if ((!flight_roll)&&(!flight_pitch))	// no correction
		return 1.0;

	return d_forward;
}

- (double) missileTrackPrimaryTarget:(double) delta_t
{
	Vector  relPos;
	GLfloat  d_forward, d_up, d_right, range2;
	Entity  *target = [self getPrimaryTarget];

	if (!target)   // leave now!
		return 0.0;

	double  damping = 0.5 * delta_t;
	double  rate2 = 4.0 * delta_t;
	double  rate1 = 2.0 * delta_t;

	double stick_roll = 0.0;	//desired roll and pitch
	double stick_pitch = 0.0;

	double tolerance1 = pitch_tolerance;

	relPos = vector_subtract(target->position, position);
	range2 = magnitude2(relPos);

	if (!vector_equal(relPos, kZeroVector))  relPos = vector_normal(relPos);
	else  relPos.z = 1.0;

	d_right		=   dot_product(relPos, v_right);		// = cosine of angle between angle to target and v_right
	d_up		=   dot_product(relPos, v_up);		// = cosine of angle between angle to target and v_up
	d_forward   =   dot_product(relPos, v_forward);	// = cosine of angle between angle to target and v_forward

	// begin rule-of-thumb manoeuvres

	stick_roll = 0.0;

	if (pitching_over)
		pitching_over = (stick_pitch != 0.0);

	if ((d_forward < -tolerance1) && (!pitching_over))
	{
		pitching_over = YES;
		if (d_up >= 0)
			stick_pitch = -max_flight_pitch;
		if (d_up < 0)
			stick_pitch = max_flight_pitch;
	}

	if (pitching_over)
	{
		pitching_over = (d_forward < 0.5);
	}
	else
	{
		stick_pitch = -max_flight_pitch * d_up;
		stick_roll = -max_flight_roll * d_right;
	}

	// end rule-of-thumb manoeuvres

	// apply damping
	if (flight_roll < 0)
		flight_roll += (flight_roll < -damping) ? damping : -flight_roll;
	if (flight_roll > 0)
		flight_roll -= (flight_roll > damping) ? damping : flight_roll;
	if (flight_pitch < 0)
		flight_pitch += (flight_pitch < -damping) ? damping : -flight_pitch;
	if (flight_pitch > 0)
		flight_pitch -= (flight_pitch > damping) ? damping : flight_pitch;

	// apply stick movement limits
	if (flight_roll + rate1 < stick_roll)
		stick_roll = flight_roll + rate1;
	if (flight_roll - rate1 > stick_roll)
		stick_roll = flight_roll - rate1;
	if (flight_pitch + rate2 < stick_pitch)
		stick_pitch = flight_pitch + rate2;
	if (flight_pitch - rate2 > stick_pitch)
		stick_pitch = flight_pitch - rate2;

	// apply stick to attitude
	flight_roll = stick_roll;
	flight_pitch = stick_pitch;

	//
	//  return target confidence 0.0 .. 1.0
	//
	if (d_forward < 0.0)
		return 0.0;
	return d_forward;
}

- (double) trackDestination:(double) delta_t :(BOOL) retreat
{
	Vector  relPos;
	GLfloat  d_forward, d_up, d_right;

	BOOL	we_are_docking = (nil != dockingInstructions);

	double  rate2 = 4.0 * delta_t;
	double  rate1 = 2.0 * delta_t;

	double stick_roll = 0.0;	//desired roll and pitch
	double stick_pitch = 0.0;

	double reverse = 1.0;

	double min_d = 0.004;
	double max_cos = 0.85;

	if (retreat)
		reverse = -reverse;

	if (isPlayer)
		reverse = -reverse;

	relPos = vector_subtract(destination, position);
	double range2 = magnitude2(relPos);

	max_cos = sqrt(1 - desired_range*desired_range/range2);

	if (!vector_equal(relPos, kZeroVector))  relPos = vector_normal(relPos);
	else  relPos.z = 1.0;

	d_right		=   dot_product(relPos, v_right);
	d_up		=   dot_product(relPos, v_up);
	d_forward   =   dot_product(relPos, v_forward);	// == cos of angle between v_forward and vector to target

	// begin rule-of-thumb manoeuvres
	stick_pitch = 0.0;
	stick_roll = 0.0;
	
	// check if we are flying toward the destination..
	if ((d_forward < max_cos)||(retreat))	// not on course so we must adjust controls..
	{

		if (d_forward < -max_cos)  // hack to avoid just flying away from the destination
		{
			d_up = min_d * 2.0;
		}

		if (d_up > min_d)
		{
			int factor = sqrt( fabs(d_right) / fabs(min_d));
			if (factor > 8)
				factor = 8;
			if (d_right > min_d)
				stick_roll = - max_flight_roll * reverse * 0.125 * factor;  //roll_roll * reverse;
			if (d_right < -min_d)
				stick_roll = + max_flight_roll * reverse * 0.125 * factor; //roll_roll * reverse;
		}
		if (d_up < -min_d)
		{
			int factor = sqrt( fabs(d_right) / fabs(min_d));
			if (factor > 8)
				factor = 8;
			if (d_right > min_d)
				stick_roll = + max_flight_roll * reverse * 0.125 * factor;  //roll_roll * reverse;
			if (d_right < -min_d)
				stick_roll = - max_flight_roll * reverse * 0.125 * factor; //roll_roll * reverse;
		}

		if (stick_roll == 0.0)
		{
			int factor = sqrt( fabs(d_up) / fabs(min_d));
			if (factor > 8)
				factor = 8;
			if (d_up > min_d)
				stick_pitch = - max_flight_pitch * reverse * 0.125 * factor;  //pitch_pitch * reverse;
			if (d_up < -min_d)
				stick_pitch = + max_flight_pitch * reverse * 0.125 * factor;  //pitch_pitch * reverse;
		}
	}

	if (we_are_docking && docking_match_rotation && (d_forward > max_cos))
	{
		/* we are docking and need to consider the rotation/orientation of the docking port */
		StationEntity* station_for_docking = (StationEntity*)[UNIVERSE entityForUniversalID:targetStation];

		if ((station_for_docking)&&(station_for_docking->isStation))
		{
			stick_roll = [self rollToMatchUp:[station_for_docking portUpVectorForShipsBoundingBox: boundingBox] rotating:[station_for_docking flight_roll]];
		}
	}

	// end rule-of-thumb manoeuvres

	// apply 'quick-stop' to roll and pitch adjustments
	if (((stick_roll > 0.0)&&(flight_roll < 0.0))||((stick_roll < 0.0)&&(flight_roll > 0.0)))
		rate1 *= 4.0;	// much faster correction
	if (((stick_pitch > 0.0)&&(flight_pitch < 0.0))||((stick_pitch < 0.0)&&(flight_pitch > 0.0)))
		rate2 *= 4.0;	// much faster correction

	// apply stick movement limits
	if (flight_roll < stick_roll - rate1)
		stick_roll = flight_roll + rate1;
	if (flight_roll > stick_roll + rate1)
		stick_roll = flight_roll - rate1;
	if (flight_pitch < stick_pitch - rate2)
		stick_pitch = flight_pitch + rate2;
	if (flight_pitch > stick_pitch + rate2)
		stick_pitch = flight_pitch - rate2;
	
	// apply stick to attitude control
	flight_roll = stick_roll;
	flight_pitch = stick_pitch;

	if (retreat)
		d_forward *= d_forward;	// make positive AND decrease granularity

	if (d_forward < 0.0)
		return 0.0;

	if ((!flight_roll)&&(!flight_pitch))	// no correction
		return 1.0;

	return d_forward;
}

- (GLfloat) rollToMatchUp:(Vector) up_vec rotating:(GLfloat) match_roll;
{
	GLfloat cosTheta = dot_product(up_vec, v_up);	// == cos of angle between up vectors
	GLfloat sinTheta = dot_product(up_vec, v_right);

	if (!isPlayer)
	{
		match_roll = -match_roll;	// make necessary corrections for a different viewpoint
		sinTheta = -sinTheta;
	}

	if (cosTheta < 0.0f)
	{
		cosTheta = -cosTheta;
		sinTheta = -sinTheta;
	}

	if (sinTheta > 0.0f)
	{
		// increase roll rate
		return cosTheta * cosTheta * match_roll + sinTheta * sinTheta * max_flight_roll;
	}
	else
	{
		// decrease roll rate
		return cosTheta * cosTheta * match_roll - sinTheta * sinTheta * max_flight_roll;
	}
}

- (GLfloat) rangeToDestination
{
	return sqrtf(distance2( position, destination));
}

- (double) rangeToPrimaryTarget
{
	double dist;
	Vector delta;
	Entity  *target = [self getPrimaryTarget];
	if (target == nil)   // leave now!
		return 0.0;
	delta = target->position;
	delta.x -= position.x;
	delta.y -= position.y;
	delta.z -= position.z;
	dist = sqrt(delta.x*delta.x + delta.y*delta.y + delta.z*delta.z);
	dist -= target->collision_radius;
	dist -= collision_radius;
	return dist;
}

- (BOOL) onTarget:(BOOL) fwd_weapon
{
	GLfloat d2, radius, dq, astq;
	Vector rel_pos, urp;
	int weapon_type = (fwd_weapon)? forward_weapon_type : aft_weapon_type;
	if (weapon_type == WEAPON_THARGOID_LASER)
		return (randf() < 0.05);	// one in twenty shots on target
	Entity  *target = [self getPrimaryTarget];
	if (target == nil)   // leave now!
		return NO;
	if (target->status == STATUS_DEAD)
		return NO;
	if (isSunlit && (target->isSunlit == NO) && (randf() < 0.75))
		return NO;	// 3/4 of the time you can't see from a lit place into a darker place
	radius = target->collision_radius;
	rel_pos = target->position;
	rel_pos.x -= position.x;
	rel_pos.y -= position.y;
	rel_pos.z -= position.z;
	d2 = magnitude2(rel_pos);
	if (d2)
		urp = unit_vector(&rel_pos);
	else
		urp = make_vector( 0, 0, 1);
	dq = dot_product(urp, v_forward);				// cosine of angle between v_forward and unit relative position
	if (((fwd_weapon)&&(dq < 0.0)) || ((!fwd_weapon)&&(dq > 0.0)))
		return NO;

	astq = sqrt(1.0 - radius * radius / d2);	// cosine of half angle subtended by target

	return (fabs(dq) >= astq);
}

- (BOOL) fireMainWeapon:(double) range
{
	//
	// set the values for the forward weapon
	//
	[self set_weapon_data_from_type:forward_weapon_type];
	//
	if (shot_time < weapon_recharge_rate)
		return NO;
	int accuracy = 1;
	if ([shipinfoDictionary objectForKey:@"accuracy"])
		accuracy = [(NSNumber *)[shipinfoDictionary objectForKey:@"accuracy"] intValue];
	if (accuracy < 1)
		accuracy = 1;
	if (range > randf() * weapon_range * accuracy)
		return NO;
	if (range > weapon_range)
		return NO;
	if (![self onTarget:YES])
		return NO;
	//
	BOOL fired = NO;
	switch (forward_weapon_type)
	{
		case WEAPON_PLASMA_CANNON :
			[self firePlasmaShot: 0.0: 1500.0: [OOColor yellowColor]];
			fired = YES;
			break;
		
		case WEAPON_PULSE_LASER :
		case WEAPON_BEAM_LASER :
		case WEAPON_MINING_LASER :
		case WEAPON_MILITARY_LASER :
			[self fireLaserShotInDirection: VIEW_FORWARD];
			fired = YES;
			break;
		
		case WEAPON_THARGOID_LASER :
			[self fireDirectLaserShot];
			fired = YES;
			break;
		
		case WEAPON_NONE:
			// Do nothing
			break;
	}

	//can we fire lasers from our subentities?
	int n_subs = [sub_entities count];
	if (n_subs)
	{
		int i = 0;
		for (i = 0; i < n_subs; i++)
		{
			ShipEntity* subent = (ShipEntity*)[sub_entities objectAtIndex:i];
			if ((subent)&&(subent->isShip))
				fired |= [subent fireSubentityLaserShot: range];
		}
	}

	return fired;
}

- (BOOL) fireAftWeapon:(double) range
{
	BOOL result = YES;
	//
	// save the existing weapon values
	//
	double weapon_energy1 = weapon_energy;
	double weapon_recharge_rate1 = weapon_recharge_rate;
	double weapon_range1 = weapon_range;
	//
	// set new values from aft_weapon_type
	//
	[self set_weapon_data_from_type:aft_weapon_type];

	if (shot_time < weapon_recharge_rate)
		return NO;
	if (![self onTarget:NO])
		return NO;
	if (range > randf() * weapon_range)
		return NO;

	if (result)
	{
		switch (aft_weapon_type)
		{
			case WEAPON_PULSE_LASER :
			case WEAPON_BEAM_LASER :
			case WEAPON_MINING_LASER :
			case WEAPON_MILITARY_LASER :
				[self fireLaserShotInDirection:VIEW_AFT];
				break;
			case WEAPON_THARGOID_LASER :
				[self fireDirectLaserShot];
				return YES;
				break;
			
			case WEAPON_PLASMA_CANNON:	// FIXME: NPCs can't have rear plasma cannons, for no obvious reason.
			case WEAPON_NONE:
				// do nothing
				break;
		}
	}
	//
	// restore previous values
	//
	weapon_energy = weapon_energy1;
	weapon_recharge_rate = weapon_recharge_rate1;
	weapon_range = weapon_range1;
	//
	return result;
}

- (BOOL) fireTurretCannon:(double) range
{
	if (shot_time < weapon_recharge_rate)
		return NO;
	if (range > 5000)
		return NO;

	ParticleEntity *shot;
	Vector  origin = position;
	Entity*		last = nil;
	Entity*		father = [self owner];
	GLfloat*	r_mat = [father drawRotationMatrix];
	Vector		vel = vector_forward_from_quaternion(q_rotation);
	while ((father)&&(father != last))
	{
		mult_vector_gl_matrix(&origin, r_mat);
		Vector pos = father->position;
		origin.x += pos.x;	origin.y += pos.y;	origin.z += pos.z;
		last = father;
		father = [father owner];
		r_mat = [father drawRotationMatrix];
	}
	double  start = collision_radius + 0.5;
	double  speed = TURRET_SHOT_SPEED;
	OOColor* color = laser_color;

	origin.x += vel.x * start;
	origin.y += vel.y * start;
	origin.z += vel.z * start;

	vel.x *= speed;
	vel.y *= speed;
	vel.z *= speed;

	shot = [[ParticleEntity alloc] init];	// alloc retains!
	[shot setPosition:origin]; // directly ahead
	[shot setScanClass: CLASS_NO_DRAW];
	[shot setVelocity: vel];
	[shot setDuration: 3.0];
	[shot setCollisionRadius: 2.0];
	[shot setEnergy: weapon_energy];
	[shot setParticleType: PARTICLE_SHOT_PLASMA];
	[shot setColor:color];
	[shot setSize:NSMakeSize(12,12)];
	[UNIVERSE addEntity:shot];

	[shot setOwner:[self owner]];	// has to be done AFTER adding shot to the UNIVERSE

	[shot release]; //release

	shot_time = 0.0;
	return YES;
}

- (void) setLaserColor:(OOColor *) color
{
	if (color)
	{
		[laser_color release];
		laser_color = [color retain];
	}
}


- (BOOL) fireSubentityLaserShot: (double) range
{
	ParticleEntity  *shot;
	int				direction = VIEW_FORWARD;
	GLfloat			hit_at_range;
	target_laser_hit = NO_TARGET;

	if (forward_weapon_type == WEAPON_NONE)
		return NO;
	[self set_weapon_data_from_type:forward_weapon_type];

	ShipEntity* parent = (ShipEntity*)[self owner];

	if (shot_time < weapon_recharge_rate)
		return NO;

	if (range > weapon_range)
		return NO;

	hit_at_range = weapon_range;
	target_laser_hit = [UNIVERSE getFirstEntityHitByLaserFromEntity:self inView:direction offset: make_vector(0,0,0) rangeFound: &hit_at_range];

	shot = [[ParticleEntity alloc] initLaserFromSubentity:self view:direction];	// alloc retains!
	[shot setColor:laser_color];
	[shot setScanClass: CLASS_NO_DRAW];
	ShipEntity *victim = (ShipEntity*)[UNIVERSE entityForUniversalID:target_laser_hit];
	if ((victim)&&(victim->isShip))
	{
		ShipEntity* subent = victim->subentity_taking_damage;
		if ((subent) && (subent->isShip) && [victim->sub_entities containsObject:subent])
		{
			if ([victim isFrangible])
			{
				// do 1% bleed-through damage...
				[victim takeEnergyDamage: 0.01 * weapon_energy from:subent becauseOf: parent];
				victim = subent;
			}
		}

		if (hit_at_range < weapon_range)
		{
			[victim takeEnergyDamage:weapon_energy from:self becauseOf: parent];	// a very palpable hit

			[shot setCollisionRadius: hit_at_range];
			Vector flash_pos = shot->position;
			Vector vd = vector_forward_from_quaternion(shot->q_rotation);
			flash_pos.x += vd.x * hit_at_range;	flash_pos.y += vd.y * hit_at_range;	flash_pos.z += vd.z * hit_at_range;
			ParticleEntity* laserFlash = [[ParticleEntity alloc] initFlashSize:1.0 FromPosition: flash_pos Color:laser_color];
			[laserFlash setVelocity:[victim velocity]];
			[UNIVERSE addEntity:laserFlash];
			[laserFlash release];
		}
	}
	[UNIVERSE addEntity:shot];
	[shot release]; //release

	shot_time = 0.0;

	return YES;
}

- (BOOL) fireDirectLaserShot
{
	GLfloat			hit_at_range;
	Entity*	my_target = [self getPrimaryTarget];
	if (!my_target)
		return NO;
	ParticleEntity*	shot;
	double			range_limit2 = weapon_range*weapon_range;
	Vector			r_pos = my_target->position;
	r_pos.x -= position.x;	r_pos.y -= position.y;	r_pos.z -= position.z;
	if (r_pos.x||r_pos.y||r_pos.z)
		r_pos = unit_vector(&r_pos);
	else
		r_pos.z = 1.0;

	Quaternion		q_laser = quaternion_rotation_between(r_pos, make_vector(0.0f,0.0f,1.0f));
	q_laser.x += 0.01 * (randf() - 0.5);	// randomise aim a little (+/- 0.005)
	q_laser.y += 0.01 * (randf() - 0.5);
	q_laser.z += 0.01 * (randf() - 0.5);
	quaternion_normalize(&q_laser);

	Quaternion q_save = q_rotation;	// save rotation
	q_rotation = q_laser;			// face in direction of laser
	target_laser_hit = [UNIVERSE getFirstEntityHitByLaserFromEntity:self inView:VIEW_FORWARD offset: make_vector(0,0,0) rangeFound: &hit_at_range];
	q_rotation = q_save;			// restore rotation

	Vector  vel = make_vector( v_forward.x * flight_speed, v_forward.y * flight_speed, v_forward.z * flight_speed);

	// do special effects laser line
	shot = [[ParticleEntity alloc] initLaserFromShip:self view:VIEW_FORWARD];	// alloc retains!
	[shot setColor:laser_color];
	[shot setScanClass: CLASS_NO_DRAW];
	[shot setPosition: position];
	[shot setQRotation: q_laser];
	[shot setVelocity: vel];
	ShipEntity *victim = (ShipEntity*)[UNIVERSE entityForUniversalID:target_laser_hit];
	if ((victim)&&(victim->isShip))
	{
		ShipEntity* subent = victim->subentity_taking_damage;
		if ((subent) && (subent->isShip) && [victim->sub_entities containsObject:subent])
		{
			if ([victim isFrangible])
			{
				// do 1% bleed-through damage...
				[victim takeEnergyDamage: 0.01 * weapon_energy from:subent becauseOf:self];
				victim = subent;
			}
		}

		if (hit_at_range * hit_at_range < range_limit2)
		{
			[victim takeEnergyDamage:weapon_energy from:self becauseOf:self];	// a very palpable hit

			[shot setCollisionRadius: hit_at_range];
			Vector flash_pos = shot->position;
			Vector vd = vector_forward_from_quaternion(shot->q_rotation);
			flash_pos.x += vd.x * hit_at_range;	flash_pos.y += vd.y * hit_at_range;	flash_pos.z += vd.z * hit_at_range;
			ParticleEntity* laserFlash = [[ParticleEntity alloc] initFlashSize:1.0 FromPosition: flash_pos Color:laser_color];
			[laserFlash setVelocity:[victim velocity]];
			[UNIVERSE addEntity:laserFlash];
			[laserFlash release];
		}
	}
	[UNIVERSE addEntity:shot];
	[shot release]; //release

	shot_time = 0.0;

	// random laser over-heating for AI ships
	if ((!isPlayer)&&((ranrot_rand() & 255) < weapon_energy)&&(![self isMining]))
		shot_time -= (randf() * weapon_energy);

	return YES;
}

- (BOOL) fireLaserShotInDirection: (int) direction
{
	ParticleEntity  *shot;
	double			range_limit2 = weapon_range*weapon_range;
	GLfloat			hit_at_range;
	Vector  vel;
	target_laser_hit = NO_TARGET;

	vel.x = v_forward.x * flight_speed;
	vel.y = v_forward.y * flight_speed;
	vel.z = v_forward.z * flight_speed;

	Vector	laserPortOffset = forwardWeaponOffset;

	switch(direction)
	{
		case VIEW_AFT:
			laserPortOffset = aftWeaponOffset;
			break;
		case VIEW_PORT:
			laserPortOffset = portWeaponOffset;
			break;
		case VIEW_STARBOARD:
			laserPortOffset = starboardWeaponOffset;
			break;
		default:
			laserPortOffset = forwardWeaponOffset;
	}

	target_laser_hit = [UNIVERSE getFirstEntityHitByLaserFromEntity:self inView:direction offset:laserPortOffset rangeFound: &hit_at_range];
	
	shot = [[ParticleEntity alloc] initLaserFromShip:self view:direction offset:laserPortOffset];	// alloc retains!

	[shot setColor:laser_color];
	[shot setScanClass: CLASS_NO_DRAW];
	[shot setVelocity: vel];
	ShipEntity *victim = (ShipEntity*)[UNIVERSE entityForUniversalID:target_laser_hit];
	if ((victim)&&(victim->isShip))
	{
		ShipEntity* subent = victim->subentity_taking_damage;
		if ((subent) && (subent->isShip) && [victim->sub_entities containsObject:subent])
		{
			if ([victim isFrangible])
			{
				// do 1% bleed-through damage...
				[victim takeEnergyDamage: 0.01 * weapon_energy from:subent becauseOf:self];
				victim = subent;
			}
		}

		if (hit_at_range * hit_at_range < range_limit2)
		{
			[victim takeEnergyDamage:weapon_energy from:self becauseOf:self];	// a very palpable hit

			[shot setCollisionRadius: hit_at_range];
			Vector flash_pos = shot->position;
			Vector vd = vector_forward_from_quaternion(shot->q_rotation);
			flash_pos.x += vd.x * hit_at_range;	flash_pos.y += vd.y * hit_at_range;	flash_pos.z += vd.z * hit_at_range;
			ParticleEntity* laserFlash = [[ParticleEntity alloc] initFlashSize:1.0 FromPosition: flash_pos Color:laser_color];
			[laserFlash setVelocity:[victim velocity]];
			[UNIVERSE addEntity:laserFlash];
			[laserFlash release];
		}
	}
	[UNIVERSE addEntity:shot];
	[shot release]; //release

	shot_time = 0.0;

	// random laser over-heating for AI ships
	if ((!isPlayer)&&((ranrot_rand() & 255) < weapon_energy)&&(![self isMining]))
		shot_time -= (randf() * weapon_energy);

	return YES;
}

- (void) throwSparks
{
	ParticleEntity*	spark;
	Vector  vel;
	Vector  origin = position;

	GLfloat lr	= randf() * (boundingBox.max.x - boundingBox.min.x) + boundingBox.min.x;
	GLfloat ud	= randf() * (boundingBox.max.y - boundingBox.min.y) + boundingBox.min.y;
	GLfloat fb	= randf() * boundingBox.max.z + boundingBox.min.z;	// rear section only

	origin.x += fb * v_forward.x;
	origin.y += fb * v_forward.y;
	origin.z += fb * v_forward.z;

	origin.x += ud * v_up.x;
	origin.y += ud * v_up.y;
	origin.z += ud * v_up.z;

	origin.x += lr * v_right.x;
	origin.y += lr * v_right.y;
	origin.z += lr * v_right.z;

	float	w = boundingBox.max.x - boundingBox.min.x;
	float	h = boundingBox.max.y - boundingBox.min.y;
	float	m = (w < h) ? 0.25 * w: 0.25 * h;

	float	sz = m * (1 + randf() + randf());	// half minimum dimension on average

	vel = make_vector( 2.0 * (origin.x - position.x), 2.0 * (origin.y - position.y), 2.0 * (origin.z - position.z));

	spark = [[ParticleEntity alloc] init];	// alloc retains!
	[spark setPosition:origin]; // directly ahead
	[spark setScanClass: CLASS_NO_DRAW];
	[spark setVelocity: vel];
	[spark setDuration: 2.0 + 3.0 * randf()];
	[spark setCollisionRadius: 2.0];
	[spark setSize:NSMakeSize( sz, sz)];
	[spark setEnergy: 0.0];
	[spark setParticleType: PARTICLE_SPARK];
	[spark setColor:[OOColor colorWithCalibratedHue:0.08 + 0.17 * randf() saturation:1.0 brightness:1.0 alpha:1.0]];
	[spark setOwner:self];
	[UNIVERSE addEntity:spark];
	[spark release]; //release

	next_spark_time = randf();
}

- (BOOL) firePlasmaShot:(double) offset :(double) speed :(OOColor *) color
{
	ParticleEntity *shot;
	Vector  vel, rt;
	Vector  origin = position;
	double  start = collision_radius + 0.5;

	speed += flight_speed;

	if (++shot_counter % 2)
		offset = -offset;

	vel = v_forward;
	rt = v_right;

	if (isPlayer)					// player can fire into multiple views!
	{
		switch ([UNIVERSE viewDir])
		{
			case VIEW_AFT :
				vel = v_forward;
				vel.x = -vel.x; vel.y = -vel.y; vel.z = -vel.z; // reverse
				rt = v_right;
				rt.x = -rt.x;   rt.y = -rt.y;   rt.z = -rt.z; // reverse
				break;
			case VIEW_STARBOARD :
				vel = v_right;
				rt = v_forward;
				rt.x = -rt.x;   rt.y = -rt.y;   rt.z = -rt.z; // reverse
				break;
			case VIEW_PORT :
				vel = v_right;
				vel.x = -vel.x; vel.y = -vel.y; vel.z = -vel.z; // reverse
				rt = v_forward;
				break;
		}
	}

	origin.x += vel.x * start;
	origin.y += vel.y * start;
	origin.z += vel.z * start;

	origin.x += rt.x * offset;
	origin.y += rt.y * offset;
	origin.z += rt.z * offset;

	vel.x *= speed;
	vel.y *= speed;
	vel.z *= speed;

	shot = [[ParticleEntity alloc] init];	// alloc retains!
	[shot setPosition:origin]; // directly ahead
	[shot setScanClass: CLASS_NO_DRAW];
	[shot setVelocity: vel];
	[shot setDuration: 5.0];
	[shot setCollisionRadius: 2.0];
	[shot setEnergy: weapon_energy];
	[shot setParticleType: PARTICLE_SHOT_GREEN_PLASMA];
	[shot setColor:color];
	[shot setOwner:self];
	[UNIVERSE addEntity:shot];
	[shot release]; //release

	shot_time = 0.0;

	return YES;
}

- (BOOL) fireMissile
{
	ShipEntity *missile = nil;
	Vector  vel;
	Vector  origin = position;
	Vector  start, v_eject;

	// default launching position
	start.x = 0.0;						// in the middle
	start.y = boundingBox.min.y - 4.0;	// 4m below bounding box
	start.z = boundingBox.max.z + 1.0;	// 1m ahead of bounding box
	// custom launching position
	ScanVectorFromString([shipinfoDictionary objectForKey:@"missile_launch_position"], &start);

	double  throw_speed = 250.0;
	Quaternion q1 = q_rotation;
	Entity  *target = [self getPrimaryTarget];

	if	((missiles <= 0)||(target == nil)||(target->scanClass == CLASS_NO_DRAW))	// no missile lock!
		return NO;

	if (target->isShip)
	{
		ShipEntity* target_ship = (ShipEntity*)target;
		if ([target_ship isCloaked])  return NO;
		if ((!has_military_scanner_filter)&&[target_ship isJammingScanning])  return NO;
	}

	// custom missiles
	if ([shipinfoDictionary objectForKey:@"missile_role"])
		missile = [UNIVERSE newShipWithRole:(NSString*)[shipinfoDictionary objectForKey:@"missile_role"]];
	if (!missile)	// no custom role
	{
		if (randf() < 0.90)	// choose a standard missile 90% of the time
			missile = [UNIVERSE newShipWithRole:@"EQ_MISSILE"];   // retained
		else				// otherwise choose any with the role 'missile' - which may include alternative weapons
			missile = [UNIVERSE newShipWithRole:@"missile"];   // retained
	}

	if (!missile)
		return NO;

	missiles--;

	double mcr = missile->collision_radius;

	v_eject = unit_vector( &start);

	vel = kZeroVector;	// starting velocity

	// check if start is within bounding box...
	while (	(start.x > boundingBox.min.x - mcr)&&(start.x < boundingBox.max.x + mcr)&&
			(start.y > boundingBox.min.y - mcr)&&(start.y < boundingBox.max.y + mcr)&&
			(start.z > boundingBox.min.z - mcr)&&(start.z < boundingBox.max.z + mcr))
	{
		start.x += mcr * v_eject.x;	start.y += mcr * v_eject.y;	start.z += mcr * v_eject.z;
		vel.x += 10.0f * mcr * v_eject.x;	vel.y += 10.0f * mcr * v_eject.y;	vel.z += 10.0f * mcr * v_eject.z;	// throw it outward a bit harder
	}

	if (isPlayer)
		q1.w = -q1.w;   // player view is reversed remember!

	vel.x += (flight_speed + throw_speed) * v_forward.x;
	vel.y += (flight_speed + throw_speed) * v_forward.y;
	vel.z += (flight_speed + throw_speed) * v_forward.z;

	origin.x = position.x + v_right.x * start.x + v_up.x * start.y + v_forward.x * start.z;
	origin.y = position.y + v_right.y * start.x + v_up.y * start.y + v_forward.y * start.z;
	origin.z = position.z + v_right.z * start.x + v_up.z * start.y + v_forward.z * start.z;

	[missile addTarget:		target];
	[missile setOwner:		self];
	[missile setGroup_id:	group_id];
	[missile setPosition:	origin];
	[missile setQRotation:	q1];
	[missile setVelocity:	vel];
	[missile setSpeed:		150.0];
	[missile setDistanceTravelled:	0.0];
	[missile setStatus:		STATUS_IN_FLIGHT];  // necessary to get it going!
	//
	[UNIVERSE addEntity:	missile];
	//
	[missile release]; //release

	if ([missile scanClass] == CLASS_MISSILE)
	{
		[(ShipEntity *)target setPrimaryAggressor:self];
		[[(ShipEntity *)target getAI] reactToMessage:@"INCOMING_MISSILE"];
	}

	return YES;
}

- (BOOL) fireECM
{
	if (!has_ecm)
		return NO;
	else
	{
		ParticleEntity  *ecmDevice = [[ParticleEntity alloc] initECMMineFromShip:self]; // retained
		[UNIVERSE addEntity:ecmDevice];
		[ecmDevice release];
	}
	return YES;
}

- (BOOL) activateCloakingDevice
{
	if (!has_cloaking_device)
		return NO;
	if (!cloaking_device_active)
		cloaking_device_active = (energy > CLOAKING_DEVICE_START_ENERGY * maxEnergy);
	return cloaking_device_active;
}

- (void) deactivateCloakingDevice
{
	cloaking_device_active = NO;
}

- (BOOL) launchEnergyBomb
{
	if (!has_energy_bomb)
		return NO;
	has_energy_bomb = NO;
	[self setSpeed: max_flight_speed + 300];
	ShipEntity*	bomb = [UNIVERSE newShipWithRole:@"energy-bomb"];
	if (!bomb)
		return NO;
	double  start = collision_radius + bomb->collision_radius;
	double  eject_speed = -800.0;
	Quaternion  random_direction;
	Vector  vel;
	Vector  rpos = position;
	double random_roll =	randf() - 0.5;  //  -0.5 to +0.5
	double random_pitch = 	randf() - 0.5;  //  -0.5 to +0.5
	quaternion_set_random(&random_direction);
	rpos.x -= v_forward.x * start;
	rpos.y -= v_forward.y * start;
	rpos.z -= v_forward.z * start;
	vel.x = v_forward.x * (flight_speed + eject_speed);
	vel.y = v_forward.y * (flight_speed + eject_speed);
	vel.z = v_forward.z * (flight_speed + eject_speed);
	eject_speed *= 0.5 * (randf() - 0.5);   //  -0.25x .. +0.25x
	vel.x += v_up.x * eject_speed;
	vel.y += v_up.y * eject_speed;
	vel.z += v_up.z * eject_speed;
	eject_speed *= 0.5 * (randf() - 0.5);   //  -0.0625x .. +0.0625x
	vel.x += v_right.x * eject_speed;
	vel.y += v_right.y * eject_speed;
	vel.z += v_right.z * eject_speed;
	[bomb setPosition:rpos];
	[bomb setQRotation:random_direction];
	[bomb setRoll:random_roll];
	[bomb setPitch:random_pitch];
	[bomb setVelocity:vel];
	[bomb setScanClass: CLASS_MINE];	// TODO should be CLASS_ENERGY_BOMB
	[bomb setStatus: STATUS_IN_FLIGHT];
	[bomb setEnergy: 5.0];	// 5 second countdown
	[bomb setBehaviour: BEHAVIOUR_ENERGY_BOMB_COUNTDOWN];
	[bomb setOwner: self];
	[UNIVERSE addEntity:bomb];
	[[bomb getAI] setState:@"GLOBAL"];
	[bomb release];
	if (self != [PlayerEntity sharedPlayer])	// get the heck out of here
	{
		[self addTarget:bomb];
		behaviour = BEHAVIOUR_FLEE_TARGET;
		frustration = 0.0;
	}
	return YES;
}

- (int) launchEscapeCapsule
{
	// check number of pods aboard
	//
	int n_pods = [[shipinfoDictionary objectForKey:@"has_escape_pod"] intValue];
	if (n_pods < 1)
		n_pods = 1;
	
	int result = NO_TARGET;
	ShipEntity *pod = (ShipEntity*)nil;
	
	// check for custom escape pod
	//
	if ([shipinfoDictionary objectForKey:@"escape_pod_model"])
		pod = [UNIVERSE newShipWithRole: (NSString*)[shipinfoDictionary objectForKey:@"escape_pod_model"]];
	//
	// if not found - use standard escape pod
	//
	if (!pod)
		pod = [UNIVERSE newShipWithRole:@"escape-capsule"];   // retain count = 1

	if (pod)
	{
		[pod setOwner:self];
		[pod setScanClass: CLASS_CARGO];
		[pod setCommodity:[UNIVERSE commodityForName:@"Slaves"] andAmount:1];
		if (crew)	// transfer crew
		{
			// make sure crew inherit any legal_status
			int i;
			for (i = 0; i < [crew count]; i++)
			{
				OOCharacter *ch = (OOCharacter*)[crew objectAtIndex:i];
				[ch setLegalStatus: [self legal_status] | [ch legalStatus]];
			}
			[pod setCrew: crew];
			[self setCrew: nil];
		}
		[[pod getAI] setStateMachine:@"homeAI.plist"];
		[self dumpItem:pod];
		[[pod getAI] setState:@"GLOBAL"];
		[pod release]; //release
		result = [pod universalID];
	}
	// launch other pods (passengers)
	int i;
	for (i = 1; i < n_pods; i++)
	{
		pod = [UNIVERSE newShipWithRole:@"escape-capsule"];
		if (pod)
		{
			Random_Seed orig = [UNIVERSE systemSeedForSystemNumber:gen_rnd_number()];
			[pod setOwner:self];
			[pod setScanClass: CLASS_CARGO];
			[pod setCommodity:[UNIVERSE commodityForName:@"Slaves"] andAmount:1];
			[pod setCrew:[NSArray arrayWithObject:[OOCharacter randomCharacterWithRole:@"passenger" andOriginalSystem:orig]]];
			[[pod getAI] setStateMachine:@"homeAI.plist"];
			[self dumpItem:pod];
			[[pod getAI] setState:@"GLOBAL"];
			[pod release]; //release
		}
	}
	
	return result;
}

- (int) dumpCargo
{
	if (status == STATUS_DEAD)
		return 0;

	int result = CARGO_NOT_CARGO;
	if (([cargo count] > 0)&&([UNIVERSE getTime] - cargo_dump_time > 0.5))  // space them 0.5s or 10m apart
	{
		ShipEntity* jetto = [cargo objectAtIndex:0];
		if (!jetto)
			return 0;
		result = [jetto getCommodityType];
		[self dumpItem:jetto];
		[cargo removeObjectAtIndex:0];
		cargo_dump_time = [UNIVERSE getTime];
	}
	return result;
}

- (int) dumpItem: (ShipEntity*) jetto
{
	if (!jetto)
		return 0;
	int result = [jetto getCargoType];
	Vector start;

	double  eject_speed = 20.0;
	double  eject_reaction = -eject_speed * [jetto mass] / [self mass];
	double	jcr = jetto->collision_radius;

	Quaternion  random_direction;
	Vector  vel, v_eject;
	Vector  rpos = position;
	double random_roll =	((ranrot_rand() % 1024) - 512.0)/1024.0;  //  -0.5 to +0.5
	double random_pitch =   ((ranrot_rand() % 1024) - 512.0)/1024.0;  //  -0.5 to +0.5
	quaternion_set_random(&random_direction);

	// default launching position
	start.x = 0.0;						// in the middle
	start.y = 0.0;						//
	start.z = boundingBox.min.z - jcr;	// 1m behind of bounding box

	// custom launching position
	ScanVectorFromString([shipinfoDictionary objectForKey:@"aft_eject_position"], &start);

	v_eject = unit_vector(&start);

	// check if start is within bounding box...
	while (	(start.x > boundingBox.min.x - jcr)&&(start.x < boundingBox.max.x + jcr)&&
			(start.y > boundingBox.min.y - jcr)&&(start.y < boundingBox.max.y + jcr)&&
			(start.z > boundingBox.min.z - jcr)&&(start.z < boundingBox.max.z + jcr))
	{
		start.x += jcr * v_eject.x;	start.y += jcr * v_eject.y;	start.z += jcr * v_eject.z;
	}

	v_eject = make_vector(	v_right.x * start.x +	v_up.x * start.y +	v_forward.x * start.z,
							v_right.y * start.x +	v_up.y * start.y +	v_forward.y * start.z,
							v_right.z * start.x +	v_up.z * start.y +	v_forward.z * start.z);

	rpos.x +=	v_eject.x;
	rpos.y +=	v_eject.y;
	rpos.z +=	v_eject.z;

	v_eject = unit_vector( &v_eject);

	v_eject.x += (randf() - randf())/eject_speed;
	v_eject.y += (randf() - randf())/eject_speed;
	v_eject.z += (randf() - randf())/eject_speed;

	vel.x =	v_forward.x * flight_speed + v_eject.x * eject_speed;
	vel.y = v_forward.y * flight_speed + v_eject.y * eject_speed;
	vel.z = v_forward.z * flight_speed + v_eject.z * eject_speed;

	velocity.x += v_eject.x * eject_reaction;
	velocity.y += v_eject.y * eject_reaction;
	velocity.z += v_eject.z * eject_reaction;

	[jetto setPosition:rpos];
	[jetto setQRotation:random_direction];
	[jetto setRoll:random_roll];
	[jetto setPitch:random_pitch];
	[jetto setVelocity:vel];
	[jetto setScanClass: CLASS_CARGO];
	[jetto setStatus: STATUS_IN_FLIGHT];
	[UNIVERSE addEntity:jetto];
	[[jetto getAI] setState:@"GLOBAL"];
	cargo_dump_time = [UNIVERSE getTime];
	return result;
}

- (void) manageCollisions
{
	// deal with collisions
	//
	Entity*		ent;
	ShipEntity* other_ship;

	while ([collidingEntities count] > 0)
	{
		ent = [(Entity *)[collidingEntities objectAtIndex:0] retain];
		[collidingEntities removeObjectAtIndex:0];
		if (ent)
		{
			if (ent->isShip)
			{
				other_ship = (ShipEntity *)ent;
				[self collideWithShip:other_ship];
			}
			if (ent->isPlanet)
			{
				if (isPlayer)
				{
					[(PlayerEntity *)self getDestroyed];
					return;
				}
				[self becomeExplosion];
			}
			if (ent->isWormhole)
			{
				WormholeEntity* whole = (WormholeEntity*)ent;
				if (isPlayer)
				{
					[(PlayerEntity*)self enterWormhole: whole];
					return;
				}
				else
				{
					[whole suckInShip: self];
				}
			}
			[ent release];
		}
	}
}

- (BOOL) collideWithShip:(ShipEntity *)other
{
	Vector  loc, opos, pos;
	double  inc1, dam1, dam2;
	
	if (!other)
		return NO;
	
	ShipEntity* otherParent = (ShipEntity*)[other owner];
	BOOL otherIsSubentity = ((otherParent)&&(otherParent != other)&&([otherParent->sub_entities containsObject:other]));

	// calculate line of centers using centres
	if (otherIsSubentity)
		opos = [other absolutePositionForSubentity];
	else
		opos = other->position;
	loc = opos;
	loc.x -= position.x;	loc.y -= position.y;	loc.z -= position.z;

	if (loc.x||loc.y||loc.z)
		loc = unit_vector(&loc);
	else
		loc.z = 1.0;

	inc1 = (v_forward.x*loc.x)+(v_forward.y*loc.y)+(v_forward.z*loc.z);

	if ([self canScoop:other])
	{
		[self scoopIn:other];
		return NO;
	}
	if ([other canScoop:self])
	{
		[other scoopIn:self];
		return NO;
	}
	if (universalID == NO_TARGET)
		return NO;
	if (other->universalID == NO_TARGET)
		return NO;

	// find velocity along line of centers
	//
	// momentum = mass x velocity
	// ke = mass x velocity x velocity
	//
	GLfloat m1 = mass;			// mass of self
	GLfloat m2 = [other mass];	// mass of other

	// starting velocities:
	Vector	vel1b =	[self velocity];
	// calculate other's velocity relative to self
	Vector	v =	[other velocity];
	if (otherIsSubentity)
	{
		if (otherParent)
		{
			v = [otherParent velocity];
			// if the subentity is rotating (subentityRotationalVelocity is not 1 0 0 0)
			// we should calculate the tangential velocity from the other's position
			// relative to our absolute position and add that in. For now this is a TODO
		}
		else
			v = kZeroVector;
	}

	//
	v = make_vector( vel1b.x - v.x, vel1b.y - v.y, vel1b.z - v.z);	// velocity of self relative to other

	//
	GLfloat	v2b = dot_product( v, loc);			// velocity of other along loc before collision
	//
	GLfloat v1a = sqrt(v2b * v2b * m2 / m1);	// velocity of self along loc after elastic collision
	if (v2b < 0.0f)	v1a = -v1a;					// in same direction as v2b


	// are they moving apart at over 1m/s already?
	if (v2b < 0.0f)
	{
		if (v2b < -1.0f)  return NO;
		else
		{
			position = make_vector( position.x - loc.x, position.y - loc.y, position.z - loc.z);	// adjust self position
			v = kZeroVector;	// go for the 1m/s solution
		}
	}

	// convert change in velocity into damage energy (KE)
	//
	dam1 = m2 * v2b * v2b / 50000000;
	dam2 = m1 * v2b * v2b / 50000000;

	// calculate adjustments to velocity after collision
	Vector vel1a = make_vector( -v1a * loc.x, -v1a * loc.y, -v1a * loc.z);
	Vector vel2a = make_vector( v2b * loc.x, v2b * loc.y, v2b * loc.z);

	if (magnitude2(v) <= 0.1)	// virtually no relative velocity - we must provide at least 1m/s to avoid conjoined objects
	{
			vel1a = make_vector( -loc.x, -loc.y, -loc.z);
			vel2a = make_vector( loc.x, loc.y, loc.z);
	}

	// apply change in velocity
	if ((otherIsSubentity)&&(otherParent))
		[otherParent adjustVelocity:vel1a];	// move the otherParent not the subentity
	else
		[self adjustVelocity:vel1a];
	[other adjustVelocity:vel2a];

	//
	//
	BOOL selfDestroyed = (dam1 > energy);
	BOOL otherDestroyed = (dam2 > [other energy]);
	//
	if (dam1 > 0.05)
	{
		[self	takeScrapeDamage: dam1 from:other];
		if (selfDestroyed)	// inelastic! - take xplosion velocity damage instead
		{
			vel2a.x = -vel2a.x;	vel2a.y = -vel2a.y;	vel2a.z = -vel2a.z;
			[other adjustVelocity:vel2a];
		}
	}
	//
	if (dam2 > 0.05)
	{
		if ((otherIsSubentity) && (otherParent) && !([otherParent isFrangible]))
			[otherParent takeScrapeDamage: dam2 from:self];
		else
			[other	takeScrapeDamage: dam2 from:self];
		if (otherDestroyed)	// inelastic! - take explosion velocity damage instead
		{
			vel1a.x = -vel1a.x;	vel1a.y = -vel1a.y;	vel1a.z = -vel1a.z;
			[other adjustVelocity:vel1a];
		}
	}
	
	if ((!selfDestroyed)&&(!otherDestroyed))
	{
		float t = 10.0 * [UNIVERSE getTimeDelta];	// 10 ticks
		//
		pos = self->position;
		opos = other->position;
		//
		Vector pos1a = make_vector(pos.x + t * v1a * loc.x, pos.y + t * v1a * loc.y, pos.z + t * v1a * loc.z);
		Vector pos2a = make_vector(opos.x - t * v2b * loc.x, opos.y - t * v2b * loc.y, opos.z - t * v2b * loc.z);
		//
		[self setPosition:pos1a];
		[other setPosition:pos2a];
	}

	//
	// remove self from other's collision list
	//
	[[other collisionArray] removeObject:self];
	//
	////

	[shipAI reactToMessage:@"COLLISION"];

	return YES;
}

- (Vector) velocity	// overrides Entity velocity
{
	Vector v = velocity;
	v.x += flight_speed * v_forward.x;	v.y += flight_speed * v_forward.y;	v.z += flight_speed * v_forward.z;
	return v;
}

- (void) adjustVelocity:(Vector) xVel
{
	velocity.x += xVel.x;
	velocity.y += xVel.y;
	velocity.z += xVel.z;
}

- (void) addImpactMoment:(Vector) moment fraction:(GLfloat) howmuch
{
	velocity.x += howmuch * moment.x / mass;
	velocity.y += howmuch * moment.y / mass;
	velocity.z += howmuch * moment.z / mass;
}

- (BOOL) canScoop:(ShipEntity*)other
{
	if (!other)										return NO;
	if (!has_scoop)									return NO;
	if ([cargo count] >= max_cargo)					return NO;
	if (scanClass == CLASS_CARGO)					return NO;	// we have no power so we can't scoop
	if (other->scanClass != CLASS_CARGO)			return NO;
	if ([other getCargoType] == CARGO_NOT_CARGO)	return NO;

	if (other->isStation)
		return NO;

	Vector  loc = vector_between( position, other->position);

	GLfloat inc1 = (v_forward.x*loc.x)+(v_forward.y*loc.y)+(v_forward.z*loc.z);
	if (inc1 < 0.0f)									return NO;
	GLfloat inc2 = (v_up.x*loc.x)+(v_up.y*loc.y)+(v_up.z*loc.z);
	if ((inc2 > 0.0f)&&(isPlayer))	return NO;	// player has to scoop ro underside, give more flexibility to NPCs
	return YES;
}

- (void) getTractoredBy:(ShipEntity *)other
{
	desired_speed = 0.0;
	[self setAITo:@"nullAI.plist"];	// prevent AI from changing status or behaviour
	behaviour = BEHAVIOUR_TRACTORED;
	status = STATUS_BEING_SCOOPED;
	[self addTarget: other];
	[self setOwner: other];
}

- (void) scoopIn:(ShipEntity *)other
{
	[other getTractoredBy:self];
}

- (void) scoopUp:(ShipEntity *)other
{
	if (!other)
		return;
	int		co_type,co_amount;
	switch ([other getCargoType])
	{
		case	CARGO_RANDOM :
			co_type = [other getCommodityType];
			co_amount = [other getCommodityAmount];
			break;
		case	CARGO_SLAVES :
			co_amount = 1;
			co_type = [UNIVERSE commodityForName:@"Slaves"];
			if (co_type == NSNotFound)  // No 'Slaves' in this game, get something else instead...
			{
				co_type = [UNIVERSE getRandomCommodity];
				co_amount = [UNIVERSE getRandomAmountOfCommodity:co_type];
			}
			break;
		case	CARGO_ALLOY :
			co_amount = 1;
			co_type = [UNIVERSE commodityForName:@"Alloys"];
			break;
		case	CARGO_MINERALS :
			co_amount = 1;
			co_type = [UNIVERSE commodityForName:@"Minerals"];
			break;
		case	CARGO_THARGOID :
			co_amount = 1;
			co_type = [UNIVERSE commodityForName:@"Alien Items"];
			break;
		case	CARGO_SCRIPTED_ITEM :
			{
				NSArray* actions = other->script_actions;
				//scripting
				if (actions != nil)
				{
					PlayerEntity* player = [PlayerEntity sharedPlayer];
					
					[player setScript_target:self];
					[player scriptActions:actions forTarget:other];

				}
				if (isPlayer)
				{
					NSString* scoopedMS = [NSString stringWithFormat:ExpandDescriptionForCurrentSystem(@"[@-scooped]"), [other name]];
					[UNIVERSE clearPreviousMessage];
					[UNIVERSE addMessage:scoopedMS forCount:4];
				}
			}
		default :
			co_amount = 0;
			co_type = 0;
			break;
	}
	if (co_amount > 0)
	{
		[other setCommodity:co_type andAmount:co_amount];   // belt and braces setting this!
		cargo_flag = CARGO_FLAG_CANISTERS;
		
		if (isPlayer)
		{
			[UNIVERSE clearPreviousMessage];
			if ([other crew])
			{
				int i;
				for (i = 0; i < [[other crew] count]; i++)
				{
					OOCharacter* rescuee = (OOCharacter*)[[other crew] objectAtIndex:i];
					if ([rescuee legalStatus])
					{
						[UNIVERSE addMessage: [NSString stringWithFormat:ExpandDescriptionForCurrentSystem(@"[scoop-captured-@]"), [rescuee name]] forCount: 4.5];
					}
					else if ([rescuee insuranceCredits])
					{
						[UNIVERSE addMessage: [NSString stringWithFormat:ExpandDescriptionForCurrentSystem(@"[scoop-rescued-@]"), [rescuee name]] forCount: 4.5];
					}
					else
					{
						[UNIVERSE addMessage: ExpandDescriptionForCurrentSystem(@"[scoop-got-slave]") forCount: 4.5];
					}
					[UNIVERSE playCustomSound:@"[escape-pod-scooped]"];
				}
			}
			else
			{
				[UNIVERSE addMessage:[UNIVERSE describeCommodity:co_type amount:co_amount] forCount:4.5];
			}
		}
		[cargo insertObject: other atIndex: 0];	// places most recently scooped object at eject position
		[other setStatus:STATUS_IN_HOLD];
		[other setBehaviour:BEHAVIOUR_TUMBLE];
		[shipAI message:@"CARGO_SCOOPED"];
		if ([cargo count] == max_cargo)  [shipAI message:@"HOLD_FULL"];
	}
	[[other collisionArray] removeObject:self];			// so it can't be scooped twice!
	if (isPlayer)  [(PlayerEntity*)self suppressTargetLost];
	[UNIVERSE removeEntity:other];
}


- (void) takeEnergyDamage:(double)amount from:(Entity *)ent becauseOf:(Entity *)other
{
	if (status == STATUS_DEAD)  return;
	if (amount == 0.0)  return;
	
	// If it's an energy mine...
	if (ent && ent->isParticle && ent->scanClass == CLASS_MINE)
	{
		// ...start a chain reaction, if we're dying and have a non-trivial amount of energy.
		if (energy < amount && energy > 10)
		{
			ParticleEntity *chainReaction = [[ParticleEntity alloc] initEnergyMineFromShip:self];
			[UNIVERSE addEntity:chainReaction];
			[chainReaction setOwner:[ent owner]];
			[chainReaction release];
		}
	}
	
	BOOL iAmTheLaw = (scanClass == CLASS_POLICE);
	BOOL uAreTheLaw = ((other)&&(other->scanClass == CLASS_POLICE));
	//
	energy -= amount;
	being_mined = NO;
	//
	if ((other)&&(other->isShip))
	{
		ShipEntity* hunter = (ShipEntity *)other;
		if ([hunter isCloaked])  other = nil;	// lose it!
	}
	//
	// if the other entity is a ship note it as an aggressor
	if ((other)&&(other->isShip))
	{
		ShipEntity* hunter = (ShipEntity *)other;
		//
		last_escort_target = NO_TARGET;	// we're being attacked, escorts can scramble!
		//
		primaryAggressor = [hunter universalID];
		found_target = primaryAggressor;

		// firing on an innocent ship is an offence
		[self broadcastHitByLaserFrom: hunter];

		// tell ourselves we've been attacked
		if (energy > 0)
			[shipAI reactToMessage:@"ATTACKED"];	// note use the reactToMessage: method NOT the think-delayed message: method

		// firing on an innocent ship is an offence
		[self broadcastHitByLaserFrom:(ShipEntity*) other];

		// tell our group we've been attacked
		if (group_id != NO_TARGET)
		{
			if ([roles isEqual:@"escort"]||[roles isEqual:@"trader"])
			{
				ShipEntity *group_leader = (ShipEntity *)[UNIVERSE entityForUniversalID:group_id];
				if ((group_leader)&&(group_leader->isShip))
				{
					[group_leader setFound_target:hunter];
					[group_leader setPrimaryAggressor:hunter];
					[[group_leader getAI] reactToMessage:@"ATTACKED"];
				}
				else
					group_id = NO_TARGET;
			}
			if ([roles isEqual:@"pirate"])
			{
				NSArray	*fellow_pirates = [self shipsInGroup:group_id];
				int i;
				for (i = 0; i < [fellow_pirates count]; i++)
				{
					ShipEntity *other_pirate = (ShipEntity *)[fellow_pirates objectAtIndex:i];
					if (randf() < 0.5)	// 50% chance they'll help
					{
						[other_pirate setFound_target:hunter];
						[other_pirate setPrimaryAggressor:hunter];
						[[other_pirate getAI] reactToMessage:@"ATTACKED"];
					}
				}
			}
			if (iAmTheLaw)
			{
				NSArray	*fellow_police = [self shipsInGroup:group_id];
				int i;
				for (i = 0; i < [fellow_police count]; i++)
				{
					ShipEntity *other_police = (ShipEntity *)[fellow_police objectAtIndex:i];
					[other_police setFound_target:hunter];
					[other_police setPrimaryAggressor:hunter];
					[[other_police getAI] reactToMessage:@"ATTACKED"];
				}
			}
		}

		// if I'm a copper and you're not, then mark the other as an offender!
		if ((iAmTheLaw)&&(!uAreTheLaw))
			[hunter markAsOffender:64];

		// avoid shooting each other
		if (([hunter group_id] == group_id)||(iAmTheLaw && uAreTheLaw))
		{
			if ([hunter behaviour] == BEHAVIOUR_ATTACK_FLY_TO_TARGET)	// avoid me please!
			{
				[hunter setBehaviour:BEHAVIOUR_ATTACK_FLY_FROM_TARGET];
				[hunter setDesiredSpeed:[hunter max_flight_speed]];
			}
		}

		if ((other)&&(other->isShip))
			being_mined = [(ShipEntity *)other isMining];
	}
	// die if I'm out of energy
	if (energy <= 0.0)
	{
		if ((other)&&(other->isShip))
		{
			ShipEntity* hunter = (ShipEntity *)other;
			[hunter collectBountyFor:self];
			if ([hunter getPrimaryTarget] == (Entity *)self)
			{
				[hunter removeTarget:(Entity *)self];
				[[hunter getAI] message:@"TARGET_DESTROYED"];
			}
		}

		[self becomeExplosion];
	}
	else
	{
		// warn if I'm low on energy
		if (energy < maxEnergy *0.25)
			[shipAI reactToMessage:@"ENERGY_LOW"];
		if ((energy < maxEnergy *0.125)&&(has_escape_pod)&&((ranrot_rand() & 3) == 0))  // 25% chance he gets to an escape pod
		{
			has_escape_pod = NO;
			
			[shipAI setStateMachine:@"nullAI.plist"];
			[shipAI setState:@"GLOBAL"];
			behaviour = BEHAVIOUR_IDLE;
			frustration = 0.0;
			[self launchEscapeCapsule];
			[self setScanClass: CLASS_CARGO];			// we're unmanned now!
			thrust = thrust * 0.5;
			desired_speed = 0.0;
			max_flight_speed = 0.0;
			is_hulk = YES;
		}
	}
}


- (void) takeScrapeDamage:(double) amount from:(Entity *) ent
{
	if (status == STATUS_DEAD)  return;

	if (status == STATUS_LAUNCHING)					// no collisions during launches please
		return;
	if (ent && ent->status == STATUS_LAUNCHING)		// no collisions during launches please
		return;
	
	energy -= amount;
	// oops we hit too hard!!!
	if (energy <= 0.0)
	{
		being_mined = YES;  // same as using a mining laser
		if ((ent)&&(ent->isShip))
		{
			ShipEntity* hunter = (ShipEntity *)ent;
			[hunter collectBountyFor:self];
			if ([hunter getPrimaryTarget] == (Entity *)self)
			{
				[hunter removeTarget:(Entity *)self];
				[[hunter getAI] message:@"TARGET_DESTROYED"];
			}
		}
		[self becomeExplosion];
	}
	else
	{
		// warn if I'm low on energy
		if (energy < maxEnergy *0.25)
			[shipAI message:@"ENERGY_LOW"];
	}
}

- (void) takeHeatDamage:(double) amount
{
	if (status == STATUS_DEAD)					// it's too late for this one!
		return;

	if (amount < 0.0)
		return;

	energy -= amount;

	throw_sparks = YES;

	// oops we're burning up!
	if (energy <= 0.0)
		[self becomeExplosion];
	else
	{
		// warn if I'm low on energy
		if (energy < maxEnergy *0.25)
			[shipAI message:@"ENERGY_LOW"];
	}
}

- (void) enterDock:(StationEntity *)station
{
	// throw these away now we're docked...
	if (dockingInstructions)
		[dockingInstructions autorelease];
	dockingInstructions = nil;

	[shipAI message:@"DOCKED"];
	[station noteDockedShip:self];
	[UNIVERSE removeEntity:self];
}

- (void) leaveDock:(StationEntity *)station
{
	if (station)
	{
		Vector launchPos = station->position;
		Vector stat_f = vector_forward_from_quaternion(station->q_rotation);
		launchPos.x += 500.0*stat_f.x;
		launchPos.y += 500.0*stat_f.y;
		launchPos.z += 500.0*stat_f.z;
		position = launchPos;
		q_rotation = station->q_rotation;
		flight_roll = [station flight_roll];
	}
	flight_pitch = 0.0;
	flight_speed = max_flight_speed * 0.5;
	status = STATUS_LAUNCHING;
	[shipAI message:@"LAUNCHED"];
	[UNIVERSE addEntity:self];
}

- (void) enterWormhole:(WormholeEntity *) w_hole
{
	if (![[UNIVERSE sun] willGoNova])				// if the sun's not going nova
		[UNIVERSE witchspaceShipWithRole:roles];	// then add a new ship like this one leaving!

	[w_hole suckInShip: self];	// removes ship from UNIVERSE
}

- (void) enterWitchspace
{
	// witchspace entry effects here
	ParticleEntity *ring1 = [[ParticleEntity alloc] initHyperringFromShip:self]; // retained
	[UNIVERSE addEntity:ring1];
	[ring1 release];
	ParticleEntity *ring2 = [[ParticleEntity alloc] initHyperringFromShip:self]; // retained
	[ring2 setSize:NSMakeSize([ring2 size].width * -2.5 ,[ring2 size].height * -2.0 )]; // shrinking!
	[UNIVERSE addEntity:ring2];
	[ring2 release];

	[shipAI message:@"ENTERED_WITCHSPACE"];

	if (![[UNIVERSE sun] willGoNova])				// if the sun's not going nova
		[UNIVERSE witchspaceShipWithRole:roles];	// then add a new ship like this one leaving!

	[UNIVERSE removeEntity:self];
}

int w_space_seed = 1234567;
- (void) leaveWitchspace
{
	Vector		pos = [UNIVERSE getWitchspaceExitPosition];
	Quaternion  q_rtn = [UNIVERSE getWitchspaceExitRotation];
	
	// try to ensure healthy random numbers
	//
	ranrot_srand(w_space_seed);
	w_space_seed = ranrot_rand();
	
	position = pos;
	double		d1 = SCANNER_MAX_RANGE * (randf() - randf());
	if (abs(d1) < 500.0)	// no closer than 500m
		d1 += ((d1 > 0.0)? 500.0: -500.0);
	Quaternion	q1 = q_rtn;
	quaternion_set_random(&q1);
	Vector		v1 = vector_forward_from_quaternion(q1);
	position.x += v1.x * d1; // randomise exit position
	position.y += v1.y * d1;
	position.z += v1.z * d1;
	q_rotation = q_rtn;
	flight_roll = 0.0;
	flight_pitch = 0.0;
	flight_speed = max_flight_speed * 0.25;
	status = STATUS_LAUNCHING;
	[shipAI message:@"EXITED_WITCHSPACE"];
	[UNIVERSE addEntity:self];

	// witchspace exit effects here
	ParticleEntity *ring1 = [[ParticleEntity alloc] initHyperringFromShip:self]; // retained
	[UNIVERSE addEntity:ring1];
	[ring1 release];
	ParticleEntity *ring2 = [[ParticleEntity alloc] initHyperringFromShip:self]; // retained
	[ring2 setSize:NSMakeSize([ring2 size].width * -2.5 ,[ring2 size].height * -2.0 )]; // shrinking!
	[UNIVERSE addEntity:ring2];
	[ring2 release];
}

- (void) markAsOffender:(int)offence_value
{
	if (scanClass != CLASS_POLICE)  bounty |= offence_value;
}

- (void) switchLightsOn
{
	if (!sub_entities) return;
	int i;
	for (i = 0; i < [sub_entities count]; i++)
	{
		Entity* subent = (Entity*)[sub_entities objectAtIndex:i];
		if (subent->isParticle)
		{
			if ([(ParticleEntity*)subent particleType] == PARTICLE_FLASHER)
				[subent setStatus:STATUS_EFFECT];
		}
	}
}

- (void) switchLightsOff
{
	if (!sub_entities) return;
	int i;
	for (i = 0; i < [sub_entities count]; i++)
	{
		Entity* subent = (Entity*)[sub_entities objectAtIndex:i];
		if (subent->isParticle)
		{
			if ([(ParticleEntity*)subent particleType] == PARTICLE_FLASHER)
				[subent setStatus:STATUS_INACTIVE];
		}
	}
}

- (void) setDestination:(Vector) dest
{
	destination = dest;
	frustration = 0.0;	// new destination => no frustration!
}

inline BOOL pairOK(NSString* my_role, NSString* their_role)
{
	BOOL pairing_okay = NO;

	pairing_okay |= (![my_role isEqual:@"escort"] && ![my_role isEqual:@"wingman"] && [their_role isEqual:@"escort"]);
	pairing_okay |= (([my_role isEqual:@"police"]||[my_role isEqual:@"interceptor"]) && [their_role isEqual:@"wingman"]);

	return pairing_okay;
}

- (BOOL) acceptAsEscort:(ShipEntity *) other_ship
{
	// can't pair with self
	if (self == other_ship)  return NO;

	// if not in standard ai mode reject approach
	if ([shipAI ai_stack_depth] > 1)
		return NO;

	if (pairOK( roles, [other_ship roles]))
	{
		// check total number acceptable
		int max_escorts = [(NSNumber *)[shipinfoDictionary objectForKey:@"escorts"] intValue];

		// check it's not already been accepted
		int i;
		for (i = 0; i < n_escorts; i++)
		{
			if (escort_ids[i] == [other_ship universalID])
			{
				[other_ship setGroup_id:universalID];
				[self setGroup_id:universalID];		// make self part of same group
				return YES;
			}
		}

		if ((n_escorts < MAX_ESCORTS)&&(n_escorts < max_escorts))
		{
			escort_ids[n_escorts] = [other_ship universalID];
			[other_ship setGroup_id:universalID];
			[self setGroup_id:universalID];		// make self part of same group
			n_escorts++;

			return YES;
		}
	}
	return NO;
}

- (Vector) getCoordinatesForEscortPosition:(int) f_pos
{
	int f_hi = 1 + (f_pos >> 2);
	int f_lo = f_pos & 3;

	int fp = f_lo * 3;
	int escort_positions[12] = {	-2,0,-1,   2,0,-1,  -3,0,-3,	3,0,-3  };
	Vector pos = position;
	double spacing = collision_radius * ESCORT_SPACING_FACTOR;
	double xx = f_hi * spacing * escort_positions[fp++];
	double yy = f_hi * spacing * escort_positions[fp++];
	double zz = f_hi * spacing * escort_positions[fp];
	pos.x += v_right.x * xx;	pos.y += v_right.y * xx;	pos.z += v_right.z * xx;
	pos.x += v_up.x * yy;		pos.y += v_up.y * yy;		pos.z += v_up.z * yy;
	pos.x += v_forward.x * zz;	pos.y += v_forward.y * zz;	pos.z += v_forward.z * zz;

	return pos;
}

- (void) deployEscorts
{
	if (n_escorts < 1)
		return;

	if (![self getPrimaryTarget])
		return;

	if (primaryTarget == last_escort_target)
	{
		// already deployed escorts onto this target!
		return;
	}

	last_escort_target = primaryTarget;

	int n_deploy = ranrot_rand() % n_escorts;
	if (n_deploy == 0)
		n_deploy = 1;

	int i_deploy = n_escorts - 1;
	while ((n_deploy > 0)&&(n_escorts > 0))
	{
		int escort_id = escort_ids[i_deploy];
		ShipEntity  *escorter = (ShipEntity *)[UNIVERSE entityForUniversalID:escort_id];
		// check it's still an escort ship
		BOOL escorter_okay = YES;
		if (!escorter)
			escorter_okay = NO;
		else
			escorter_okay = escorter->isShip;
		if (escorter_okay)
		{
			[escorter setGroup_id:NO_TARGET];	// act individually now!
			[escorter addTarget:[self getPrimaryTarget]];
			[[escorter getAI] setStateMachine:@"interceptAI.plist"];
			[[escorter getAI] setState:@"GLOBAL"];

			escort_ids[i_deploy] = NO_TARGET;
			i_deploy--;
			n_deploy--;
			n_escorts--;
		}
		else
		{
			escort_ids[i_deploy--] = escort_ids[--n_escorts];	// remove the escort
		}
	}

}

- (void) dockEscorts
{
	if (n_escorts < 1)
		return;

	int i;
	for (i = 0; i < n_escorts; i++)
	{
		int escort_id = escort_ids[i];
		ShipEntity  *escorter = (ShipEntity *)[UNIVERSE entityForUniversalID:escort_id];
		// check it's still an escort ship
		BOOL escorter_okay = YES;
		if (!escorter)
			escorter_okay = NO;
		else
			escorter_okay = escorter->isShip;
		if (escorter_okay)
		{
			SEL _setSM =	@selector(setStateMachine:);
			SEL _setSt =	@selector(setState:);
			float delay = i * 3.0 + 1.5;		// send them off at three second intervals
			[escorter setGroup_id:NO_TARGET];	// act individually now!
			[[escorter getAI] performSelector:_setSM withObject:@"dockingAI.plist" afterDelay:delay];
			[[escorter getAI] performSelector:_setSt withObject:@"ABORT" afterDelay:delay + 0.25];
		}
		escort_ids[i] = NO_TARGET;
	}
	n_escorts = 0;

}

- (void) setTargetToStation
{
	// check if the group_id (parent ship) points to a station...
	Entity* mother = [UNIVERSE entityForUniversalID:group_id];
	if ((mother)&&(mother->isStation))
	{
		primaryTarget = group_id;
		targetStation = primaryTarget;
		return;	// head for mother!
	}

	/*- selects the nearest station it can find -*/
	if (!UNIVERSE)
		return;
	int			ent_count =		UNIVERSE->n_entities;
	Entity**	uni_entities =	UNIVERSE->sortedEntities;	// grab the public sorted list
	Entity*		my_entities[ent_count];
	int i;
	int station_count = 0;
	for (i = 0; i < ent_count; i++)
		if (uni_entities[i]->isStation)
			my_entities[station_count++] = [uni_entities[i] retain];		//	retained
	//
	StationEntity* station =  nil;
	double nearest2 = SCANNER_MAX_RANGE2 * 1000000.0; // 1000x scanner range (25600 km), squared.
	for (i = 0; i < station_count; i++)
	{
		StationEntity* thing = (StationEntity*)my_entities[i];
		double range2 = distance2( position, thing->position);
		if (range2 < nearest2)
		{
			station = (StationEntity *)thing;
			nearest2 = range2;
		}
	}
	for (i = 0; i < station_count; i++)
		[my_entities[i] release];		//	released
	//
	if (station)
	{
		primaryTarget = [station universalID];
		targetStation = primaryTarget;
	}
}

- (void) setTargetToSystemStation
{
	StationEntity* system_station = [UNIVERSE station];
	
	if (!system_station)
	{
		[shipAI message:@"NOTHING_FOUND"];
		primaryTarget = NO_TARGET;
		targetStation = NO_TARGET;
		return;
	}
	
	if (!system_station->isStation)
	{
		[shipAI message:@"NOTHING_FOUND"];
		primaryTarget = NO_TARGET;
		targetStation = NO_TARGET;
		return;
	}
	
	primaryTarget = [system_station universalID];
	targetStation = primaryTarget;
	return;
}

- (PlanetEntity *) findNearestLargeBody
{
	/*- selects the nearest planet it can find -*/
	if (!UNIVERSE)
		return nil;
	int			ent_count =		UNIVERSE->n_entities;
	Entity**	uni_entities =	UNIVERSE->sortedEntities;	// grab the public sorted list
	Entity*		my_entities[ent_count];
	int i;
	int planet_count = 0;
	for (i = 0; i < ent_count; i++)
		if (uni_entities[i]->isPlanet)
			my_entities[planet_count++] = [uni_entities[i] retain];		//	retained
	//
	PlanetEntity	*the_planet =  nil;
	double nearest2 = SCANNER_MAX_RANGE2 * 10000000000.0; // 100 000x scanner range (2 560 000 km), squared.
	for (i = 0; i < planet_count; i++)
	{
		PlanetEntity  *thing = (PlanetEntity*)my_entities[i];
		double range2 = distance2( position, thing->position);
		if ((!the_planet)||(range2 < nearest2))
		{
			the_planet = (PlanetEntity *)thing;
			nearest2 = range2;
		}
	}
	for (i = 0; i < planet_count; i++)
		[my_entities[i] release];		//	released
	//
	return the_planet;
}

- (void) abortDocking
{
	if (!UNIVERSE)
		return;
	int			ent_count =		UNIVERSE->n_entities;
	Entity**	uni_entities =	UNIVERSE->sortedEntities;	// grab the public sorted list
	int i;
	for (i = 0; i < ent_count; i++)
		if (uni_entities[i]->isStation)
			[(StationEntity *)uni_entities[i] abortDockingForShip:self];	// action
}

- (void) broadcastThargoidDestroyed
{
	/*-- Locates all tharglets in range and tells them you've gone --*/
	if (!UNIVERSE)
		return;
	int			ent_count =		UNIVERSE->n_entities;
	Entity**	uni_entities =	UNIVERSE->sortedEntities;	// grab the public sorted list
	Entity*		my_entities[ent_count];
	int i;
	int ship_count = 0;
	for (i = 0; i < ent_count; i++)
		if (uni_entities[i]->isShip)
			my_entities[ship_count++] = [uni_entities[i] retain];		//	retained
	//
	double d2;
	double found_d2 = SCANNER_MAX_RANGE2;
	for (i = 0; i < ship_count ; i++)
	{
		ShipEntity* ship = (ShipEntity *)my_entities[i];
		d2 = distance2( position, ship->position);
		if ((d2 < found_d2)&&([[ship roles] isEqual:@"tharglet"]))
			[[ship getAI] message:@"THARGOID_DESTROYED"];
	}
	for (i = 0; i < ship_count; i++)
		[my_entities[i] release];		//	released
}

- (void) broadcastHitByLaserFrom:(ShipEntity*) aggressor_ship
{
	/*-- If you're clean, locates all police and stations in range and tells them OFFENCE_COMMITTED --*/
	if (!UNIVERSE)
		return;
	if (bounty)
		return;
	if (!aggressor_ship)
		return;
	if (	(scanClass == CLASS_NEUTRAL)||
			(scanClass == CLASS_STATION)||
			(scanClass == CLASS_BUOY)||
			(scanClass == CLASS_POLICE)||
			(scanClass == CLASS_MILITARY)||
			(scanClass == CLASS_PLAYER))	// only for active ships...
	{
		int			ent_count =		UNIVERSE->n_entities;
		Entity**	uni_entities =	UNIVERSE->sortedEntities;	// grab the public sorted list
		Entity*		my_entities[ent_count];
		int i;
		int ship_count = 0;
		StationEntity* mainStation = [UNIVERSE station];
		for (i = 0; i < ent_count; i++)
			if ((uni_entities[i]->isShip)&&((uni_entities[i]->scanClass == CLASS_POLICE)||(uni_entities[i] == mainStation)))
				my_entities[ship_count++] = [uni_entities[i] retain];		//	retained
		//
		for (i = 0; i < ship_count ; i++)
		{
			ShipEntity* ship = (ShipEntity *)my_entities[i];
			if (((ship == mainStation) && ([self within_station_aegis])) || (distance2( position, ship->position) < SCANNER_MAX_RANGE2))
			{
				[ship setFound_target: aggressor_ship];
				[[ship getAI] reactToMessage: @"OFFENCE_COMMITTED"];
			}
			[my_entities[i] release];		//	released
		}
	}
}
- (NSArray *) shipsInGroup:(int) ship_group_id
{
	//-- Locates all the ships with this particular group id --//
	NSMutableArray* result = [NSMutableArray array];	// is autoreleased
	if (!UNIVERSE)
		return (NSArray *)result;
	int			ent_count =		UNIVERSE->n_entities;
	Entity**	uni_entities =	UNIVERSE->sortedEntities;	// grab the public sorted list
	int i;
	for (i = 0; i < ent_count; i++)
	{
		if (uni_entities[i]->isShip)
		{
			ShipEntity* ship = (ShipEntity*)uni_entities[i];
			if ([ship group_id] == ship_group_id)
				[result addObject: ship];
		}
	}
	return (NSArray *)result;
}

- (void) sendExpandedMessage:(NSString *) message_text toShip:(ShipEntity*) other_ship
{
	if (!other_ship)
		return;
	if (!crew)
		return;	// nobody to send the signal
	if ((lastRadioMessage) && (message_time > 0.0) && [message_text isEqual:lastRadioMessage])
		return;	// don't send the same message too often
	[lastRadioMessage autorelease];
	lastRadioMessage = [message_text retain];
	Vector delta = other_ship->position;
	delta.x -= position.x;  delta.y -= position.y;  delta.z -= position.z;
	double d2 = delta.x*delta.x + delta.y*delta.y + delta.z*delta.z;
	if (d2 > scanner_range * scanner_range)
		return;					// out of comms range
	if (!other_ship)
		return;
	NSMutableString* localExpandedMessage = [NSMutableString stringWithString:message_text];
	[localExpandedMessage	replaceOccurrencesOfString:@"[self:name]"
							withString:name
							options:NSLiteralSearch range:NSMakeRange( 0, [localExpandedMessage length])];
	[localExpandedMessage	replaceOccurrencesOfString:@"[target:name]"
							withString:[other_ship identFromShip: self]
							options:NSLiteralSearch range:NSMakeRange( 0, [localExpandedMessage length])];

	Random_Seed very_random_seed;
	very_random_seed.a = rand() & 255;
	very_random_seed.b = rand() & 255;
	very_random_seed.c = rand() & 255;
	very_random_seed.d = rand() & 255;
	very_random_seed.e = rand() & 255;
	very_random_seed.f = rand() & 255;
	seed_RNG_only_for_planet_description(very_random_seed);
	NSString* expandedMessage = ExpandDescriptionForCurrentSystem(localExpandedMessage);
	[self setCommsMessageColor];
	[other_ship receiveCommsMessage:[NSString stringWithFormat:@"%@:\n %@", name, expandedMessage]];
	if (other_ship->isPlayer)
		message_time = 6.0;
	[UNIVERSE resetCommsLogColor];
}

- (void) broadcastAIMessage:(NSString *) ai_message
{
	NSString* expandedMessage = ExpandDescriptionForCurrentSystem(ai_message);

	[self checkScanner];
	int i;
	for (i = 0; i < n_scanned_ships ; i++)
	{
		ShipEntity* ship = scanned_ships[i];
		[[ship getAI] message: expandedMessage];
	}
}

- (void) broadcastMessage:(NSString *) message_text
{
	NSString* expandedMessage = [NSString stringWithFormat:@"%@:\n %@", name, ExpandDescriptionForCurrentSystem(message_text)];

	if (!crew)
		return;	// nobody to send the signal

	[self setCommsMessageColor];
	[self checkScanner];
	int i;
	for (i = 0; i < n_scanned_ships ; i++)
	{
		ShipEntity* ship = scanned_ships[i];
		[ship receiveCommsMessage: expandedMessage];
		if (ship->isPlayer)
			message_time = 6.0;
	}
	[UNIVERSE resetCommsLogColor];
}

- (void) setCommsMessageColor
{
	float hue = 0.0625 * (universalID & 15);
	[[UNIVERSE comm_log_gui] setTextColor:[OOColor colorWithCalibratedHue:hue saturation:0.375 brightness:1.0 alpha:1.0]];
	if (scanClass == CLASS_THARGOID)
		[[UNIVERSE comm_log_gui] setTextColor:[OOColor greenColor]];
	if (scanClass == CLASS_POLICE)
		[[UNIVERSE comm_log_gui] setTextColor:[OOColor cyanColor]];
}

- (void) receiveCommsMessage:(NSString *) message_text
{
	// ignore messages for now
}

- (BOOL) markForFines
{
	if (being_fined)
		return NO;	// can't mark twice
	being_fined = ([self legal_status] > 0);
	return being_fined;
}

- (BOOL) isMining
{
	return ((behaviour == BEHAVIOUR_ATTACK_MINING_TARGET)&&(forward_weapon_type == WEAPON_MINING_LASER));
}

- (void) setNumberOfMinedRocks:(int) value
{
	if (![roles isEqual:@"asteroid"])
		return;
	likely_cargo = value;
}

- (void) interpretAIMessage:(NSString *)ms
{
	if ([ms hasPrefix:AIMS_AGGRESSOR_SWITCHED_TARGET])
	{
		// if I'm under attack send a thank-you message to the rescuer
		//
		NSArray* tokens = ScanTokensFromString(ms);
		int switcher_id = [(NSString*)[tokens objectAtIndex:1] intValue];
		Entity* switcher = [UNIVERSE entityForUniversalID:switcher_id];
		int rescuer_id = [(NSString*)[tokens objectAtIndex:2] intValue];
		Entity* rescuer = [UNIVERSE entityForUniversalID:rescuer_id];
		if ((switcher_id == primaryAggressor)&&(switcher_id == primaryTarget)&&(switcher)&&(rescuer)&&(rescuer->isShip)&&(thanked_ship_id != rescuer_id)&&(scanClass != CLASS_THARGOID))
		{
			if (scanClass == CLASS_POLICE)
				[self sendExpandedMessage:@"[police-thanks-for-assist]" toShip:(ShipEntity*)rescuer];
			else
				[self sendExpandedMessage:@"[thanks-for-assist]" toShip:(ShipEntity*)rescuer];
			thanked_ship_id = rescuer_id;
			[(ShipEntity*)switcher setBounty:[(ShipEntity*)switcher getBounty] + 5 + (ranrot_rand() & 15)];	// reward
		}
	}
}

- (BoundingBox) findBoundingBoxRelativeTo:(Entity *)other InVectors:(Vector) _i :(Vector) _j :(Vector) _k
{
	Vector  opv = (other)? other->position : position;
	return [self findBoundingBoxRelativeToPosition:opv InVectors:_i :_j :_k];
}

- (BoundingBox) findBoundingBoxRelativeToPosition:(Vector)opv InVectors:(Vector) _i :(Vector) _j :(Vector) _k
{
	Vector	pv, rv;
	Vector  rpos = position;
	rpos.x -= opv.x;	rpos.y -= opv.y;	rpos.z -= opv.z;	// model origin relative to opv
	rv.x = dot_product(_i,rpos);
	rv.y = dot_product(_j,rpos);
	rv.z = dot_product(_k,rpos);	// model origin rel to opv in ijk
	BoundingBox result;
	if (n_vertices < 1)
		bounding_box_reset_to_vector(&result,rv);
	else
	{
		pv.x = rpos.x + v_right.x * vertices[0].x + v_up.x * vertices[0].y + v_forward.x * vertices[0].z;
		pv.y = rpos.y + v_right.y * vertices[0].x + v_up.y * vertices[0].y + v_forward.y * vertices[0].z;
		pv.z = rpos.z + v_right.z * vertices[0].x + v_up.z * vertices[0].y + v_forward.z * vertices[0].z;	// vertices[0] position rel to opv
		rv.x = dot_product(_i,pv);
		rv.y = dot_product(_j,pv);
		rv.z = dot_product(_k,pv);	// vertices[0] position rel to opv in ijk
		bounding_box_reset_to_vector(&result,rv);
    }
	int i;
    for (i = 1; i < n_vertices; i++)
    {
		pv.x = rpos.x + v_right.x * vertices[i].x + v_up.x * vertices[i].y + v_forward.x * vertices[i].z;
		pv.y = rpos.y + v_right.y * vertices[i].x + v_up.y * vertices[i].y + v_forward.y * vertices[i].z;
		pv.z = rpos.z + v_right.z * vertices[i].x + v_up.z * vertices[i].y + v_forward.z * vertices[i].z;
		rv.x = dot_product(_i,pv);
		rv.y = dot_product(_j,pv);
		rv.z = dot_product(_k,pv);
		bounding_box_add_vector(&result,rv);
    }

	return result;
}

- (void) spawn:(NSString *)roles_number
{
	NSArray*	tokens = ScanTokensFromString(roles_number);
	NSString*   roleString = nil;
	NSString*	numberString = nil;

	if ([tokens count] != 2)
	{
		OOLog(kOOLogSyntaxAddShips, @"***** Could not spawn: '%@' (must be two tokens, role and number)",roles_number);
		return;
	}

	roleString = (NSString *)[tokens objectAtIndex:0];
	numberString = (NSString *)[tokens objectAtIndex:1];

	int number = [numberString intValue];

	OOLog(kOOLogNoteAddShips, @"Spawning %d x '%@' near %@ %d", number, roleString, name, universalID);

	while (number--)
		[UNIVERSE spawnShipWithRole:roleString near:self];
}

- (int) checkShipsInVicinityForWitchJumpExit
{
	// checks if there are any large masses close by
	// since we want to place the space station at least 10km away
	// the formula we'll use is K x m / d2 < 1.0
	// (m = mass, d2 = distance squared)
	// coriolis station is mass 455,223,200
	// 10km is 10,000m,
	// 10km squared is 100,000,000
	// therefore K is 0.22 (approx)

	int result = NO_TARGET;

	GLfloat k = 0.1;

	int			ent_count =		UNIVERSE->n_entities;
	Entity**	uni_entities =	UNIVERSE->sortedEntities;	// grab the public sorted list
	ShipEntity*	my_entities[ent_count];
	int i;

	int ship_count = 0;
	for (i = 0; i < ent_count; i++)
		if ((uni_entities[i]->isShip)&&(uni_entities[i] != self))
			my_entities[ship_count++] = (ShipEntity*)[uni_entities[i] retain];		//	retained
	//
	for (i = 0; (i < ship_count)&&(result == NO_TARGET) ; i++)
	{
		ShipEntity* ship = my_entities[i];
		Vector delta = vector_between( position, ship->position);
		GLfloat d2 = magnitude2(delta);
		if ((k * [ship mass] > d2)&&(d2 < SCANNER_MAX_RANGE2))	// if you go off scanner from a blocker - it ceases to block
			result = [ship universalID];
	}
	for (i = 0; i < ship_count; i++)
		[my_entities[i] release];	//		released

	return result;
}

- (void) setTrackCloseContacts:(BOOL) value
{
	if (value == trackCloseContacts)
		return;
	trackCloseContacts = value;
	if (trackCloseContacts)
	{
		if (closeContactsInfo)
			[closeContactsInfo removeAllObjects];
		else
			closeContactsInfo = [[NSMutableDictionary alloc] init];
	}
	else
	{
		[closeContactsInfo release];
		closeContactsInfo = nil;
	}
}

- (void) claimAsSalvage
{
	// Create a bouy and beacon where the hulk is.
	// Get the main GalCop station to launch a pilot boat to deliver a pilot to the hulk.
	NSLog(@"claimAsSalvage called on %@ %@", [self name], [self roles]);
/*
	// Won't work in interstellar space because there is no GalCop station
	if ([[self planet_number] intValue] < 0)
	{
		NSLog(@"claimAsSalvage failed because in intersteller space");
		return;
	}
*/
	// Not an abandoned hulk, so don't allow the salvage
	if (is_hulk != YES)
	{
		NSLog(@"claimAsSalvage failed because not a hulk");
		return;
	}

	// Set target to main station, and return now if it can't be found
	[self setTargetToSystemStation];
	if (primaryTarget == NO_TARGET)
	{
		NSLog(@"claimAsSalvage failed because did not find a station");
		return;
	}

	// Get the station to launch a pilot boat to bring a pilot out to the hulk (use a viper for now)
	StationEntity *station = (StationEntity *)[UNIVERSE entityForUniversalID:primaryTarget];
	NSLog(@"claimAsSalvage asking station to launch a pilot boat");
	[station launchShipWithRole:@"pilot"];
	[self setReportAImessages:YES];
	NSLog(@"claimAsSalvage setting own state machine to capturedShipAI.plist");
	[self setStateMachine:@"capturedShipAI.plist"];
}

- (void) sendCoordinatesToPilot
{
	Entity		*scan;
	ShipEntity	*scanShip, *pilot;
	
	n_scanned_ships = 0;
	scan = z_previous;
	NSLog(@"searching for pilot boat");
	while (scan &&(scan->isShip == NO))
		scan = scan->z_previous;	// skip non-ships

	pilot = nil;
	while (scan)
	{
		if (scan->isShip)
		{
			scanShip = (ShipEntity *)scan;
			NSArray *scanRoles = ScanTokensFromString([scanShip roles]);
			
			if ([scanRoles containsObject:@"pilot"] == YES)
			{
				if ([scanShip getPrimaryTargetID] == NO_TARGET)
				{
					NSLog(@"found pilot boat with no target, will use this one");
					pilot = scanShip;
					break;
				}
			}
		}
		scan = scan->z_previous;
		while (scan && (scan->isShip == NO))
			scan = scan->z_previous;
	}

	if (pilot != nil)
	{
		NSLog(@"becoming pilot target and setting AI");
		[pilot setReportAImessages:YES];
		[pilot addTarget:self];
		[pilot setStateMachine:@"pilotAI.plist"];
		[[self getAI] reactToMessage:@"FOUND_PILOT"];
	}
}

- (void) pilotArrived
{
	[[self getAI] reactToMessage:@"PILOT_ARRIVED"];
}

#ifdef WIN32
// No over-ride of Entity's version of the method is required for non-Win32 platforms.
- (void) reloadTextures
{
	int i;
	for (i = 0; i < [sub_entities count]; i++)
	{
		Entity *e = (Entity *)[sub_entities objectAtIndex:i];
		[e reloadTextures];
	}

	// Reset the entity display list.
	[super reloadTextures];
}

#endif


- (void)dumpSelfState
{
	NSMutableArray		*flags = nil;
	NSString			*flagsString = nil;
	
	[super dumpSelfState];
	
	OOLog(@"dumpState.shipEntity", @"Name: %@", name);
	OOLog(@"dumpState.shipEntity", @"Roles: %@", roles);
	if (sub_entities != nil)  OOLog(@"dumpState.shipEntity", @"Subentity count: %u", [sub_entities count]);
	OOLog(@"dumpState.shipEntity", @"Time since shot: %g", shot_time);
	OOLog(@"dumpState.shipEntity", @"Behaviour: %@", BehaviourToString(behaviour));
	if (primaryTarget != NO_TARGET)  OOLog(@"dumpState.shipEntity", @"Target: %@", [self getPrimaryTarget]);
	OOLog(@"dumpState.shipEntity", @"Destination: %@", VectorDescription(destination));
	OOLog(@"dumpState.shipEntity", @"Other destination: %@", VectorDescription(coordinates));
	OOLog(@"dumpState.shipEntity", @"Waypoint count: %u", number_of_navpoints);
	OOLog(@"dumpState.shipEntity", @"Desired speed: %g", desired_speed);
	if (n_escorts != 0)  OOLog(@"dumpState.shipEntity", @"Escort count: %u", n_escorts);
	OOLog(@"dumpState.shipEntity", @"Fuel: %i", fuel);
	OOLog(@"dumpState.shipEntity", @"Fuel accumulator: %g", fuel_accumulator);
	OOLog(@"dumpState.shipEntity", @"Missile count: %u", missiles);
	if (brain != nil && OOLogWillDisplayMessagesInClass(@"dumpState.shipEntity.brain"))
	{
		OOLog(@"dumpState.shipEntity.brain", @"Brain:");
		OOLogPushIndent();
		OOLogIndent();
		NS_DURING
			[brain dumpState];
		NS_HANDLER
		NS_ENDHANDLER
		OOLogPopIndent();
	}
	if (shipAI != nil && OOLogWillDisplayMessagesInClass(@"dumpState.shipEntity.ai"))
	{
		OOLog(@"dumpState.shipEntity.ai", @"AI:");
		OOLogPushIndent();
		OOLogIndent();
		NS_DURING
			[shipAI dumpState];
		NS_HANDLER
		NS_ENDHANDLER
		OOLogPopIndent();
	}
	OOLog(@"dumpState.shipEntity", @"Frustration: %g", frustration);
	OOLog(@"dumpState.shipEntity", @"Success factor: %g", success_factor);
	OOLog(@"dumpState.shipEntity", @"Shots fired: %u", shot_counter);
	if (beaconChar != '\0')
	{
		OOLog(@"dumpState.shipEntity", @"Beacon character: '%c'", beaconChar);
	}
	OOLog(@"dumpState.shipEntity", @"Hull temperature: %g", ship_temperature);
	OOLog(@"dumpState.shipEntity", @"Heat insulation: %g", heat_insulation);
	
	flags = [NSMutableArray array];
	#define ADD_FLAG_IF_SET(x)		if (x) { [flags addObject:@#x]; }
	ADD_FLAG_IF_SET(has_ecm);
	ADD_FLAG_IF_SET(has_scoop);
	ADD_FLAG_IF_SET(has_escape_pod);
	ADD_FLAG_IF_SET(has_energy_bomb);
	ADD_FLAG_IF_SET(has_cloaking_device);
	ADD_FLAG_IF_SET(has_military_jammer);
	ADD_FLAG_IF_SET(military_jammer_active);
	ADD_FLAG_IF_SET(has_military_scanner_filter);
	ADD_FLAG_IF_SET(has_fuel_injection);
	ADD_FLAG_IF_SET(docking_match_rotation);
	ADD_FLAG_IF_SET(escortsAreSetUp);
	ADD_FLAG_IF_SET(pitching_over);
	ADD_FLAG_IF_SET(reportAImessages);
	ADD_FLAG_IF_SET(being_mined);
	ADD_FLAG_IF_SET(being_fined);
	ADD_FLAG_IF_SET(is_hulk);
	ADD_FLAG_IF_SET(trackCloseContacts);
	ADD_FLAG_IF_SET(isNearPlanetSurface);
	ADD_FLAG_IF_SET(isFrangible);
	ADD_FLAG_IF_SET(cloaking_device_active);
	ADD_FLAG_IF_SET(canFragment);
	ADD_FLAG_IF_SET(proximity_alert);
	flagsString = [flags count] ? [flags componentsJoinedByString:@", "] : @"none";
	OOLog(@"dumpState.shipEntity", @"Flags: %@", flagsString);
	
	OOLog(@"dumpState.shipEntity.glsl", @"engine_level: %g", [self speed_factor]);
	OOLog(@"dumpState.shipEntity.glsl", @"laser_heat_level: %g", OOClamp_0_1_f([self laserHeatLevel]));
	OOLog(@"dumpState.shipEntity.glsl", @"hull_heat_level: %g", [self hullHeatLevel]);
	OOLog(@"dumpState.shipEntity.glsl", @"entity_personality: %g", entity_personality / (float)0x7FFF);
	OOLog(@"dumpState.shipEntity.glsl", @"entity_personality_int: %i", entity_personality);
}

@end


static NSString * const kOOCacheOctrees = @"octrees";

@implementation OOCacheManager (Octree)

+ (Octree *)octreeForModel:(NSString *)inKey
{
	NSDictionary		*dict = nil;
	Octree				*result = nil;
	
	dict = [[self sharedCache] objectForKey:inKey inCache:kOOCacheOctrees];
	if (dict != nil)
	{
		result = [[Octree alloc] initWithDictionary:dict];
		[result autorelease];
	}
	
	return result;
}


+ (void)setOctree:(Octree *)inOctree forModel:(NSString *)inKey
{
	[[self sharedCache] setObject:[inOctree dict] forKey:inKey inCache:kOOCacheOctrees];
}

@end


// This could be more efficient.
static void ApplyConstantUniforms(NSDictionary *uniforms, GLhandleARB shaderProgram)
{
	// Shipdata-defined uniforms. 
	NSEnumerator	*uniformEnum = nil;
	NSString		*name = nil;
	id				definition = nil;
	id				value = nil;
	NSString		*type = nil;
	GLint			variableLocation;
	GLfloat			floatValue;
	GLint			intValue;
	BOOL			gotValue;
	
	for (uniformEnum = [uniforms keyEnumerator]; (name = [uniformEnum nextObject]); )
	{
		variableLocation = glGetUniformLocationARB(shaderProgram, [name UTF8String]);
		if (variableLocation == -1)  continue;
		
		definition = [uniforms objectForKey:name];
		if ([definition isKindOfClass:[NSDictionary class]])
		{
			value = [definition objectForKey:@"value"];
			type = [definition objectForKey:@"type"];
		}
		else
		{
			value = definition;
			type = @"float";
		}
		
		if ([type isEqualToString:@"float"])
		{
			gotValue = YES;
			if ([value respondsToSelector:@selector(floatValue)])  floatValue = [value floatValue];
			else if ([value respondsToSelector:@selector(doubleValue)])  floatValue = [value doubleValue];
			else if ([value respondsToSelector:@selector(intValue)])  floatValue = [value intValue];
			else gotValue = NO;
			
			if (gotValue)
			{
				glUniform1fARB(variableLocation, floatValue);
			}
		}
		else if ([type isEqualToString:@"int"])
		{
			if ([value respondsToSelector:@selector(intValue)])
			{
				intValue = [value intValue];
				glUniform1iARB(variableLocation, intValue);
			}
		}
	}
}