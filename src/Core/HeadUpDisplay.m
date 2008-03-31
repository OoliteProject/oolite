/*

HeadUpDisplay.m

Oolite
Copyright (C) 2004-2008 Giles C Williams and contributors

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

#import "HeadUpDisplay.h"
#import "ResourceManager.h"
#import "PlayerEntity.h"
#import "PlanetEntity.h"
#import "StationEntity.h"
#import "Universe.h"
#import "OOTrumble.h"
#import "OOColor.h"
#import "GuiDisplayGen.h"
#import "OOTexture.h"
#import "OpenGLSprite.h"
#import "OOCollectionExtractors.h"
#import "OOEncodingConverter.h"

#define kOOLogUnconvertedNSLog @"unclassified.HeadUpDisplay"


#define ONE_SIXTEENTH			0.0625
#define ONE_SIXTYFOURTH			0.015625
#define DEFAULT_OVERALL_ALPHA	0.75


static void DrawSpecialOval(GLfloat x, GLfloat y, GLfloat z, NSSize siz, GLfloat step, GLfloat* color4v);

static void GetRGBAArrayFromInfo(NSDictionary *info, GLfloat ioColor[4]);

void hudDrawIndicatorAt(GLfloat x, GLfloat y, GLfloat z, NSSize siz, double amount);
void hudDrawMarkerAt(GLfloat x, GLfloat y, GLfloat z, NSSize siz, double amount);
void hudDrawBarAt(GLfloat x, GLfloat y, GLfloat z, NSSize siz, double amount);
void hudDrawSurroundAt(GLfloat x, GLfloat y, GLfloat z, NSSize siz);
void hudDrawSpecialIconAt(NSArray* ptsArray, int x, int y, int z, NSSize siz);
void hudDrawMineIconAt(int x, int y, int z, NSSize siz);
void hudDrawMissileIconAt(int x, int y, int z, NSSize siz);
void hudDrawStatusIconAt(int x, int y, int z, NSSize siz);
void hudDrawReticleOnTarget(Entity* target, PlayerEntity* player1, GLfloat z1, GLfloat overallAlpha);


static OOTexture			*sFontTexture = nil;
static OOEncodingConverter	*sEncodingCoverter = nil;


enum
{
	kFontTextureOptions = kOOTextureMinFilterMipMap | kOOTextureMagFilterLinear | kOOTextureNoShrink | kOOTextureAlphaMask
};


@implementation HeadUpDisplay

GLfloat red_color[4] =		{1.0, 0.0, 0.0, 1.0};
GLfloat redplus_color[4] =  {1.0, 0.0, 0.5, 1.0};
GLfloat yellow_color[4] =   {1.0, 1.0, 0.0, 1.0};
GLfloat green_color[4] =	{0.0, 1.0, 0.0, 1.0};
GLfloat darkgreen_color[4] ={0.0, 0.75, 0.0, 1.0};
GLfloat blue_color[4] =		{0.0, 0.0, 1.0, 1.0};

static float sGlyphWidths[256];


static double drawCharacterQuad(uint8_t chr, double x, double y, double z, NSSize siz);

static void InitTextEngine(void);


OOINLINE void GLColorWithOverallAlpha(GLfloat *color, GLfloat alpha)
{
	glColor4f(color[0], color[1], color[2], color[3] * alpha);
}


- (id) initWithDictionary:(NSDictionary *) hudinfo
{
	unsigned		i;
	BOOL			areTrumblesToBeDrawn = NO;
	
	self = [super init];
		
	line_width = 1.0;
	
	if (sFontTexture == nil)  InitTextEngine();
			
	// init arrays
	dialArray = [[NSMutableArray alloc] initWithCapacity:16];   // alloc retains
	legendArray = [[NSMutableArray alloc] initWithCapacity:16]; // alloc retains
	
	// populate arrays
	NSArray *dials = [hudinfo arrayForKey:DIALS_KEY];
	for (i = 0; i < [dials count]; i++)
	{
		NSDictionary	*dial_info = [dials dictionaryAtIndex:i];
		if (!areTrumblesToBeDrawn && [[dial_info stringForKey:SELECTOR_KEY] isEqualToString:@"drawTrumbles:"])  areTrumblesToBeDrawn = YES;
		[self addDial:dial_info];
	}
	
	if (!areTrumblesToBeDrawn)	// naughty - a hud with no built-in drawTrumbles: - one must be added!
	{
		NSDictionary	*trumble_dial_info = [NSDictionary dictionaryWithObjectsAndKeys: @"drawTrumbles:", SELECTOR_KEY, nil];
		[self addDial:trumble_dial_info];
	}
	
	NSArray *legends = [hudinfo arrayForKey:LEGENDS_KEY];
	for (i = 0; i < [legends count]; i++)
	{
		[self addLegend:[legends dictionaryAtIndex:i]];
	}
	
	overallAlpha = [hudinfo floatForKey:@"overall_alpha" defaultValue:DEFAULT_OVERALL_ALPHA];
	
	last_transmitter = NO_TARGET;
	
	return self;
}


- (void) dealloc
{
	[legendArray release];
	[dialArray release];

    [super dealloc];
}

//------------------------------------------------------------------------------------//


- (void) resizeGuis:(NSDictionary*) info
{
	// check for entries in hud plist for comm_log_gui and message_gui
	// resize and reposition them accordingly
	
	GuiDisplayGen* message_gui = [UNIVERSE message_gui];
	if ((message_gui)&&([info objectForKey:@"message_gui"]))
	{
		NSDictionary* gui_info = (NSDictionary*)[info objectForKey:@"message_gui"];
		Vector pos = [message_gui drawPosition];
		if ([gui_info objectForKey:X_KEY])
			pos.x = [[gui_info objectForKey:X_KEY] floatValue];
		if ([gui_info objectForKey:Y_KEY])
			pos.y = [[gui_info objectForKey:Y_KEY] floatValue];
		[message_gui setDrawPosition:pos];
		NSSize		siz =	[message_gui	size];
		int			rht =	[message_gui	rowHeight];
		NSString*	title =	[message_gui	title];
		if ([gui_info objectForKey:WIDTH_KEY])
			siz.width = [[gui_info objectForKey:WIDTH_KEY] floatValue];
		if ([gui_info objectForKey:HEIGHT_KEY])
			siz.height = [[gui_info objectForKey:HEIGHT_KEY] floatValue];
		if ([gui_info objectForKey:ROW_HEIGHT_KEY])
			rht = [[gui_info objectForKey:ROW_HEIGHT_KEY] intValue];
		if ([gui_info objectForKey:TITLE_KEY])
			title = [NSString stringWithFormat:@"%@", [gui_info objectForKey:TITLE_KEY]];
		[message_gui resizeTo:siz characterHeight:rht title:title];
		if ([gui_info objectForKey:ALPHA_KEY])
			[message_gui setAlpha: [[gui_info objectForKey:ALPHA_KEY] floatValue]];
		else
			[message_gui setAlpha: 1.0];
		if ([gui_info objectForKey:BACKGROUND_RGBA_KEY])
			[message_gui setBackgroundColor:[OOColor colorFromString:[gui_info stringForKey:BACKGROUND_RGBA_KEY]]];
	}
	
	GuiDisplayGen* comm_log_gui = [UNIVERSE comm_log_gui];
	if ((comm_log_gui)&&([info objectForKey:@"comm_log_gui"]))
	{
		NSDictionary* gui_info = (NSDictionary*)[info objectForKey:@"comm_log_gui"];
		Vector pos = [comm_log_gui drawPosition];
		if ([gui_info objectForKey:X_KEY])
			pos.x = [[gui_info objectForKey:X_KEY] floatValue];
		if ([gui_info objectForKey:Y_KEY])
			pos.y = [[gui_info objectForKey:Y_KEY] floatValue];
		[comm_log_gui setDrawPosition:pos];
		NSSize		siz =	[comm_log_gui	size];
		int			rht =	[comm_log_gui	rowHeight];
		NSString*	title =	[comm_log_gui	title];
		if ([gui_info objectForKey:WIDTH_KEY])
			siz.width = [[gui_info objectForKey:WIDTH_KEY] floatValue];
		if ([gui_info objectForKey:HEIGHT_KEY])
			siz.height = [[gui_info objectForKey:HEIGHT_KEY] floatValue];
		if ([gui_info objectForKey:ROW_HEIGHT_KEY])
			rht = [[gui_info objectForKey:ROW_HEIGHT_KEY] intValue];
		if ([gui_info objectForKey:TITLE_KEY])
			title = [NSString stringWithFormat:@"%@", [gui_info objectForKey:TITLE_KEY]];
		[comm_log_gui resizeTo:siz characterHeight:rht title:title];
		if ([gui_info objectForKey:ALPHA_KEY])
			[comm_log_gui setAlpha: [[gui_info objectForKey:ALPHA_KEY] floatValue]];
		else
			[comm_log_gui setAlpha: 1.0];
		if ([gui_info objectForKey:BACKGROUND_RGBA_KEY])
			[comm_log_gui setBackgroundColor:[OOColor colorFromString:[gui_info stringForKey:BACKGROUND_RGBA_KEY]]];
	}
	
	
}


- (double) scanner_zoom
{
	return scanner_zoom;
}


- (void) setScannerZoom:(double) value
{
	scanner_zoom = value;
}

- (GLfloat) overallAlpha
{
	return overallAlpha;
}


- (void) addLegend:(NSDictionary *) info
{
	NSString			*imageName = nil;
	OOTexture			*texture = nil;
	NSSize				imageSize;
	OpenGLSprite		*legendSprite = nil;
	NSMutableDictionary	*legendDict = nil;
	
	imageName = [info stringForKey:IMAGE_KEY];
	if (imageName != nil)
	{
		texture = [OOTexture textureWithName:imageName inFolder:@"Images"];
		if (texture == nil)
		{
			OOLog(kOOLogFileNotFound, @"***** ERROR: HeadUpDisplay couldn't get an image texture name for %@", imageName);
			return;
		}
		
		imageSize = [texture dimensions];
		imageSize.width = [info floatForKey:WIDTH_KEY defaultValue:imageSize.width];
		imageSize.height = [info floatForKey:HEIGHT_KEY defaultValue:imageSize.height];
		
 		legendSprite = [[OpenGLSprite alloc] initWithTexture:texture size:imageSize];
		
		legendDict = [info mutableCopy];
		[legendDict setObject:legendSprite forKey:SPRITE_KEY];
		[legendArray addObject:legendDict];																	
		[legendDict release];
		[legendSprite release];
	}
	else if ([info stringForKey:TEXT_KEY] != nil)
	{
		[legendArray addObject:info];
	}
}


- (void) addDial:(NSDictionary *) info
{
	if ([info stringForKey:SELECTOR_KEY] != nil)
	{
		SEL _selector = NSSelectorFromString([info stringForKey:SELECTOR_KEY]);
		if ([self respondsToSelector:_selector])  [dialArray addObject:info];
	}
}


- (void) drawLegends
{
	unsigned		i;
	
	z1 = [[UNIVERSE gameView] display_z];
	for (i = 0; i < [legendArray count]; i++)
		[self drawLegend:[legendArray dictionaryAtIndex:i]];
	
	CheckOpenGLErrors(@"HeadUpDisplay after drawLegends");
}


// SLOW_CODE - HUD drawing is taking up a ridiculous 30%-40% of frame time. Much of this seems to be spent in string processing. String caching is needed. -- ahruman
- (void) drawDials
{
	unsigned		i;
	
	z1 = [[UNIVERSE gameView] display_z];
	for (i = 0; i < [dialArray count]; i++)
		[self drawHUDItem:[dialArray dictionaryAtIndex:i]];
	
	CheckOpenGLErrors(@"HeadUpDisplay after drawDials");
}


- (void) drawLegend:(NSDictionary *) info
{
	OpenGLSprite				*legendSprite = nil;
	NSString					*legendText = nil;
	float						x, y;
	NSSize						size;
	
	x = [info floatForKey:X_KEY];
	y = [info floatForKey:Y_KEY];
	
	legendSprite = [info objectForKey:SPRITE_KEY];
	if (legendSprite != nil)
	{
		float alpha = [info floatForKey:ALPHA_KEY];
		[legendSprite blitCentredToX:x Y:y Z:z1 alpha:alpha];
	}
	else
	{
		legendText = [info stringForKey:TEXT_KEY];
		if (legendText != nil)
		{
			size.width = [info floatForKey:WIDTH_KEY];
			size.height = [info floatForKey:HEIGHT_KEY];
			GLColorWithOverallAlpha(green_color, overallAlpha);
			drawString(legendText, x, y, z1, size);
		}
	}
}


- (void) drawHUDItem:(NSDictionary *) info
{
	NSString *equipment = [info stringForKey:EQUIPMENT_REQUIRED_KEY];
	if (equipment != nil && ![[PlayerEntity sharedPlayer] hasEquipmentItem:equipment])
		return;
	
	if ([info stringForKey:SELECTOR_KEY] != nil)
	{
		SEL _selector = NSSelectorFromString([info stringForKey:SELECTOR_KEY]);
		if ([self respondsToSelector:_selector])
			[self performSelector:_selector withObject:info];
		else
			OOLog(@"hud.unknownSelector", @"DEBUG HeadUpDisplay does not respond to '%@'",[info objectForKey:SELECTOR_KEY]);
	}
	
	CheckOpenGLErrors(@"HeadUpDisplay after drawHUDItem %@", info);
}

//---------------------------------------------------------------------//

static BOOL hostiles;
- (void) drawScanner:(NSDictionary *) info
{
    int				x;
	int				y;
	NSSize			siz;
    GLfloat			scanner_color[4] = { 1.0, 0.0, 0.0, 1.0 };
	
	x = [info intForKey:X_KEY defaultValue:SCANNER_CENTRE_X];
	y = [info intForKey:Y_KEY defaultValue:SCANNER_CENTRE_Y];
	siz.width = [info nonNegativeFloatForKey:WIDTH_KEY defaultValue:SCANNER_WIDTH];
	siz.height = [info nonNegativeFloatForKey:HEIGHT_KEY defaultValue:SCANNER_HEIGHT];
	GetRGBAArrayFromInfo(info, scanner_color);
	
	scanner_color[3] *= overallAlpha;
	float alpha = scanner_color[3];
	
	double z_factor = siz.height / siz.width;	// approx 1/4
	double y_factor = 1.0 - sqrt(z_factor);	// approx 1/2
	
	int				i;
    int				scanner_cx = x;
	int				scanner_cy = y;
	double			mass_lock_range2 = 25600.0*25600.0;

	int				scanner_scale = SCANNER_MAX_RANGE * 2.5 / siz.width;

	double			max_zoomed_range2 = SCANNER_SCALE*SCANNER_SCALE*10000.0/(scanner_zoom*scanner_zoom);
	
	GLfloat			max_zoomed_range = sqrtf(max_zoomed_range2);
	
	BOOL			isHostile = NO;
	BOOL			foundHostiles = NO;
	BOOL			mass_locked = NO;
	
	Vector			position, relativePosition;
	OOMatrix		rotMatrix;
	int				flash = ((int)([UNIVERSE getTime] * 4))&1;

	Universe		*uni			= UNIVERSE;
	PlayerEntity	*player = [PlayerEntity sharedPlayer];
	if (player == nil)  return;
	
	// use a non-mutable copy so this can't be changed under us.
	int				ent_count		= uni->n_entities;
	Entity			**uni_entities	= uni->sortedEntities;	// grab the public sorted list
	Entity			*my_entities[ent_count];
	
	for (i = 0; i < ent_count; i++)
	{
		my_entities[i] = [uni_entities[i] retain];	// retained
	}
	
	Entity	*drawthing = nil;
	
	GLfloat col[4] =	{ 1.0, 1.0, 1.0, overallAlpha };	// can be manipulated
	
	position = [player position];
	rotMatrix = [player rotationMatrix];
	
	glColor4fv(scanner_color);
	drawScannerGrid(x, y, z1, siz, [UNIVERSE viewDirection], line_width, scanner_zoom);
	
	GLfloat off_scope2 = (siz.width > siz.height) ? siz.width * siz.width : siz.height * siz.height;
	
	OOEntityStatus p_status = [player status];

	if ((p_status == STATUS_IN_FLIGHT)||(p_status == STATUS_AUTOPILOT_ENGAGED)||(p_status == STATUS_LAUNCHING)||(p_status == STATUS_WITCHSPACE_COUNTDOWN))
	{
		double upscale = scanner_zoom*1.25/scanner_scale;
		off_scope2 /= upscale * upscale;
		double max_blip = 0.0;
		
		for (i = 0; i < ent_count; i++)  // scanner lollypops
		{
			drawthing = my_entities[i];
			
			int drawClass = drawthing->scanClass;
			if (drawClass == CLASS_PLAYER)	drawClass = CLASS_NO_DRAW;
			if (drawthing->isShip)
			{
				ShipEntity* ship = (ShipEntity*)drawthing;
				if ([ship isCloaked])  drawClass = CLASS_NO_DRAW;
			}
			
			// consider large bodies for mass_lock
			if (drawthing->isPlanet)
			{
				PlanetEntity* planet = (PlanetEntity *)drawthing;
				double dist =   planet->zero_distance;
				double rad =	planet->collision_radius;
				double factor = ([planet planetType] == PLANET_TYPE_SUN) ? 2.0 : 4.0;
				if (dist < rad*rad*factor)
				{
					mass_locked = YES;
				}
			}
			
			if (drawClass != CLASS_NO_DRAW)
			{
				GLfloat x1,y1,y2;
				float	ms_blip = 0.0;

				if (drawthing->zero_distance <= mass_lock_range2)
				{
					switch (drawClass)
					{
						case CLASS_BUOY :
						case CLASS_ROCK :
						case CLASS_CARGO :
						case CLASS_MINE :
							break;
						case CLASS_THARGOID :
						case CLASS_MISSILE :
						case CLASS_STATION :
						case CLASS_POLICE :
						case CLASS_MILITARY :
						case CLASS_WORMHOLE :
						default :
							mass_locked = YES;
							break;
					}
				}
				
				[player setAlertFlag:ALERT_FLAG_MASS_LOCK to:mass_locked];
				
				if (isnan(drawthing->zero_distance))
					continue;
				
				// exit if it's too far away
				GLfloat	act_dist = sqrtf(drawthing->zero_distance);
				GLfloat	lim_dist = act_dist - drawthing->collision_radius;
				
				if (lim_dist > max_zoomed_range)
					continue;
				
				// has it sent a recent message
				//
				if (drawthing->isShip) 
					ms_blip = 2.0 * [(ShipEntity *)drawthing messageTime];
				if (ms_blip > max_blip)
				{
					max_blip = ms_blip;
					last_transmitter = [drawthing universalID];
				}
				ms_blip -= floor(ms_blip);
				
				relativePosition = drawthing->relativePosition;
				Vector rp = relativePosition;
				
				if (act_dist > max_zoomed_range)
					scale_vector(&relativePosition, max_zoomed_range / act_dist);

				// rotate the view
				relativePosition = OOVectorMultiplyMatrix(relativePosition, rotMatrix);
				// scale the view
				scale_vector(&relativePosition, upscale);
				
				x1 = relativePosition.x;
				y1 = z_factor * relativePosition.z;
				y2 = y1 + y_factor * relativePosition.y;
				
				isHostile = NO;
				if ([drawthing isShip])
				{
					ShipEntity* ship = (ShipEntity *)drawthing;
					double wr = [ship weaponRange];
					isHostile = (([ship hasHostileTarget])&&([ship primaryTarget] == player)&&(drawthing->zero_distance < wr*wr));
					GLfloat* base_col = [ship scannerDisplayColorForShip:player :isHostile :flash];
					col[0] = base_col[0];	col[1] = base_col[1];	col[2] = base_col[2];	col[3] = alpha * base_col[3];
				}
				
				if ([drawthing isWormhole])
				{
					col[0] = blue_color[0];	col[1] = (flash)? 1.0 : blue_color[1];	col[2] = blue_color[2];	col[3] = alpha * blue_color[3];
				}
				
				// position the scanner
				x1 += scanner_cx;   y1 += scanner_cy;   y2 += scanner_cy;
				
				switch (drawClass)
				{
					case CLASS_THARGOID :
						foundHostiles = YES;
						break;
					case CLASS_ROCK :
					case CLASS_CARGO :
					case CLASS_MISSILE :
					case CLASS_STATION :
					case CLASS_BUOY :
					case CLASS_POLICE :
					case CLASS_MILITARY :
					case CLASS_MINE :
					case CLASS_WORMHOLE :
					default :
						if (isHostile)
							foundHostiles = YES;
						break;
				}

				if ([drawthing isShip])
				{
					ShipEntity* ship = (ShipEntity*)drawthing;
					if (ship->collision_radius * upscale > 4.5)
					{
						Vector bounds[6];
						BoundingBox bb = ship->totalBoundingBox;
						bounds[0] = ship->v_forward;	scale_vector(&bounds[0], bb.max.z);
						bounds[1] = ship->v_forward;	scale_vector(&bounds[1], bb.min.z);
						bounds[2] = ship->v_right;		scale_vector(&bounds[2], bb.max.x);
						bounds[3] = ship->v_right;		scale_vector(&bounds[3], bb.min.x);
						bounds[4] = ship->v_up;			scale_vector(&bounds[4], bb.max.y);
						bounds[5] = ship->v_up;			scale_vector(&bounds[5], bb.min.y);
						// rotate the view
						int i;
						for (i = 0; i < 6; i++)
						{
							bounds[i] = OOVectorMultiplyMatrix(vector_add(bounds[i], rp), rotMatrix);
							scale_vector(&bounds[i], upscale);
							bounds[i] = make_vector(bounds[i].x + scanner_cx, bounds[i].z * z_factor + bounds[i].y * y_factor + scanner_cy, z1 );
						}
						// draw the diamond
						//
						glBegin(GL_QUADS);
						glColor4f(col[0], col[1], col[2], 0.33333 * col[3]);
							glVertex3f(bounds[0].x, bounds[0].y, bounds[0].z);	glVertex3f(bounds[4].x, bounds[4].y, bounds[4].z);
							glVertex3f(bounds[1].x, bounds[1].y, bounds[1].z);	glVertex3f(bounds[5].x, bounds[5].y, bounds[5].z);
							glVertex3f(bounds[2].x, bounds[2].y, bounds[2].z);	glVertex3f(bounds[4].x, bounds[4].y, bounds[4].z);
							glVertex3f(bounds[3].x, bounds[3].y, bounds[3].z);	glVertex3f(bounds[5].x, bounds[5].y, bounds[5].z);
							glVertex3f(bounds[2].x, bounds[2].y, bounds[2].z);	glVertex3f(bounds[0].x, bounds[0].y, bounds[0].z);
							glVertex3f(bounds[3].x, bounds[3].y, bounds[3].z);	glVertex3f(bounds[1].x, bounds[1].y, bounds[1].z);
						glEnd();
					}
				}


				if (ms_blip > 0.0)
				{
					DrawSpecialOval(x1 - 0.5, y2 + 1.5, z1, NSMakeSize(16.0 * (1.0 - ms_blip), 8.0 * (1.0 - ms_blip)), 30, col);
				}
				if ((drawthing->isParticle)&&(drawClass == CLASS_MINE))
				{
					double r1 = 2.5 + drawthing->collision_radius * upscale;
					double l2 = r1*r1 - relativePosition.y*relativePosition.y;
					double r0 = (l2 > 0)? sqrt(l2): 0;
					if (r0 > 0)
					{
						glColor4f(1.0, 0.5, 1.0, alpha);
						GLDrawOval(x1  - 0.5, y1 + 1.5, z1, NSMakeSize(r0, r0 * siz.height / siz.width), 20);
					}
					glColor4f(0.5, 0.0, 1.0, 0.33333 * alpha);
					GLDrawFilledOval(x1  - 0.5, y2 + 1.5, z1, NSMakeSize(r1, r1), 15);
				}
				else
				{
					glBegin(GL_QUADS);
					glColor4fv(col);
					glVertex3f(x1-3, y2, z1);	glVertex3f(x1+2, y2, z1);	glVertex3f(x1+2, y2+3, z1);	glVertex3f(x1-3, y2+3, z1);	
					col[3] *= 0.3333; // one third the alpha
					glColor4fv(col);
					glVertex3f(x1, y1, z1);	glVertex3f(x1+2, y1, z1);	glVertex3f(x1+2, y2, z1);	glVertex3f(x1, y2, z1);
					glEnd();
				}
			}
		}
		
		[player setAlertFlag:ALERT_FLAG_HOSTILES to:foundHostiles];
			
		if ((foundHostiles)&&(!hostiles))
		{
			hostiles = YES;
		}
		if ((!foundHostiles)&&(hostiles))
		{
			hostiles = NO;					// there are now no hostiles on scope, relax
		}
	}
	
	for (i = 0; i < ent_count; i++)
		[my_entities[i] release];	//	released

}


- (void) refreshLastTransmitter
{
	Entity* lt = [UNIVERSE entityForUniversalID:last_transmitter];
	if ((lt == nil)||(!(lt->isShip)))
		return;
	ShipEntity* st = (ShipEntity*)lt;
	if ([st messageTime] <= 0.0)
		[st setMessageTime:2.5];
}


- (void) drawScannerZoomIndicator:(NSDictionary *) info
{
    int				x;
	int				y;
	NSSize			siz;
    GLfloat			zoom_color[] = { 1.0f, 0.1f, 0.0f, 1.0f };
	
	x = [info intForKey:X_KEY defaultValue:ZOOM_INDICATOR_CENTRE_X];
	y = [info intForKey:Y_KEY defaultValue:ZOOM_INDICATOR_CENTRE_Y];
	siz.width = [info nonNegativeFloatForKey:WIDTH_KEY defaultValue:ZOOM_INDICATOR_WIDTH];
	siz.height = [info nonNegativeFloatForKey:HEIGHT_KEY defaultValue:ZOOM_INDICATOR_HEIGHT];
	GetRGBAArrayFromInfo(info, zoom_color);
	
	GLfloat cx = x - 0.3 * siz.width;
	GLfloat cy = y - 0.75 * siz.height;

	int zl = scanner_zoom;
	if (zl < 1) zl = 1;
	if (zl > SCANNER_ZOOM_LEVELS) zl = SCANNER_ZOOM_LEVELS;
	if (zl == 1) zoom_color[3] *= 0.75;
	GLColorWithOverallAlpha(zoom_color, overallAlpha);
	glEnable(GL_TEXTURE_2D);
	glTexEnvf(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_MODULATE);
	[sFontTexture apply];
	glBegin(GL_QUADS);
	drawCharacterQuad(48 + zl, cx - 0.4 * siz.width, cy, z1, siz);
	drawCharacterQuad(58, cx, cy, z1, siz);
	drawCharacterQuad(49, cx + 0.3 * siz.width, cy, z1, siz);
	glEnd();
	[OOTexture applyNone];
	glDisable(GL_TEXTURE_2D);
}


- (void) drawCompass:(NSDictionary *) info
{
    int				x;
	int				y;
	NSSize			siz;
	float			alpha;
	
	x = [info intForKey:X_KEY defaultValue:COMPASS_CENTRE_X];
	y = [info intForKey:Y_KEY defaultValue:COMPASS_CENTRE_Y];
	siz.width = [info nonNegativeFloatForKey:WIDTH_KEY defaultValue:COMPASS_HALF_SIZE];
	siz.height = [info nonNegativeFloatForKey:HEIGHT_KEY defaultValue:COMPASS_HALF_SIZE];
	alpha = [info nonNegativeFloatForKey:ALPHA_KEY defaultValue:1.0] * overallAlpha;
	
	// draw the compass
	OOMatrix		rotMatrix;
	PlayerEntity	*player = [PlayerEntity sharedPlayer];
	Vector			position = [player position];
	
	rotMatrix = [player rotationMatrix];
	
	GLfloat h1 = siz.height * 0.125;
	GLfloat h3 = siz.height * 0.375;
	GLfloat w1 = siz.width * 0.125;
	GLfloat w3 = siz.width * 0.375;
	glLineWidth(2.0 * line_width);	// thicker
	glColor4f(0.0f, 0.0f, 1.0f, alpha);
	GLDrawOval(x, y, z1, siz, 12);	
	glColor4f(0.0f, 0.0f, 1.0f, 0.5f * alpha);
	glBegin(GL_LINES);
		glVertex3f(x - w1, y, z1);	glVertex3f(x - w3, y, z1);
		glVertex3f(x + w1, y, z1);	glVertex3f(x + w3, y, z1);
		glVertex3f(x, y - h1, z1);	glVertex3f(x, y - h3, z1);
		glVertex3f(x, y + h1, z1);	glVertex3f(x, y + h3, z1);
	glEnd();
	glLineWidth(line_width);	// thinner
	
	PlanetEntity*	the_sun = [UNIVERSE sun];
	PlanetEntity*	the_planet = [UNIVERSE planet];
	StationEntity*	the_station = [UNIVERSE station];
	Entity*			the_target = [player primaryTarget];
	Entity*			the_next_beacon = [UNIVERSE entityForUniversalID:[player nextBeaconID]];
	int				p_status = player->status;
	if	(((p_status == STATUS_IN_FLIGHT)
		||(p_status == STATUS_AUTOPILOT_ENGAGED)
		||(p_status == STATUS_LAUNCHING)
		||(p_status == STATUS_WITCHSPACE_COUNTDOWN))	// be in the right mode
		&&(the_sun)
		&&(the_planet))									// and be in a system
	{
		Entity *reference = nil;
		
		switch ([player compassMode])
		{
			case COMPASS_MODE_BASIC:
				
				if ([player checkForAegis] != AEGIS_NONE && the_station)
				{
					reference = the_station;
				}
				else
				{
					reference = the_planet;
				}
				break;
			
			case COMPASS_MODE_PLANET:
				reference = the_planet;
				break;
				
			case COMPASS_MODE_STATION:
				reference = the_station;
				break;
				
			case COMPASS_MODE_SUN:
				reference = the_sun;
				break;
				
			case COMPASS_MODE_TARGET:
				reference = the_target;
				break;
				
			case COMPASS_MODE_BEACONS:
				reference = the_next_beacon;
				break;
		}
		
		if (reference == nil)
		{
			[player setCompassMode:COMPASS_MODE_PLANET];
			reference = the_planet;
		}
		
		// translate and rotate the view
		Vector relativePosition = vector_subtract([reference position], position);
		relativePosition = OOVectorMultiplyMatrix(relativePosition, rotMatrix);
		relativePosition = vector_normal_or_fallback(relativePosition, kBasisZVector);
		
		relativePosition.x *= siz.width * 0.4;
		relativePosition.y *= siz.height * 0.4;
		relativePosition.x += x;
		relativePosition.y += y;

		NSSize sz = siz;
		sz.width *= 0.2;
		sz.height *= 0.2;
		glLineWidth(2.0);
		switch ([player compassMode])
		{
			case COMPASS_MODE_BASIC:
				[self drawCompassPlanetBlipAt:relativePosition Size:NSMakeSize(6, 6) Alpha:alpha];
				break;
			
			case COMPASS_MODE_PLANET:
				[self drawCompassPlanetBlipAt:relativePosition Size:sz Alpha:alpha];
				break;
			case COMPASS_MODE_STATION:
				[self drawCompassStationBlipAt:relativePosition Size:sz Alpha:alpha];
				break;
			case COMPASS_MODE_SUN:
				[self drawCompassSunBlipAt:relativePosition Size:sz Alpha:alpha];
				break;
			case COMPASS_MODE_TARGET:
				[self drawCompassTargetBlipAt:relativePosition Size:sz Alpha:alpha];
				break;
			case COMPASS_MODE_BEACONS:
				[self drawCompassBeaconBlipAt:relativePosition Size:sz Alpha:alpha];
				drawString(	[NSString stringWithFormat:@"%c", [(ShipEntity*)the_next_beacon beaconChar]],
							x - 2.5 * sz.width, y - 3.0 * sz.height, z1, NSMakeSize(sz.width * 2, sz.height * 2));
				break;
		}
	}
}


- (void) drawCompassPlanetBlipAt:(Vector) relativePosition Size:(NSSize) siz Alpha:(GLfloat) alpha
{
	if (relativePosition.z >= 0)
	{
		glColor4f(0.0,1.0,0.0,0.75 * alpha);
		GLDrawFilledOval(relativePosition.x, relativePosition.y, z1, siz, 30);
		glColor4f(0.0,1.0,0.0,alpha);
		GLDrawOval(relativePosition.x, relativePosition.y, z1, siz, 30);
	}
	else
	{
		glColor4f(1.0,0.0,0.0,alpha);
		GLDrawOval(relativePosition.x, relativePosition.y, z1, siz, 30);
	}
}


- (void) drawCompassStationBlipAt:(Vector) relativePosition Size:(NSSize) siz Alpha:(GLfloat) alpha
{
	if (relativePosition.z >= 0)
	{
		glColor4f(0.0,1.0,0.0,alpha);
	}
	else
	{
		glColor4f(1.0,0.0,0.0,alpha);
	}
	glBegin(GL_LINE_LOOP);
	glVertex3f(relativePosition.x - 0.5 * siz.width, relativePosition.y - 0.5 * siz.height, z1);
	glVertex3f(relativePosition.x + 0.5 * siz.width, relativePosition.y - 0.5 * siz.height, z1);
	glVertex3f(relativePosition.x + 0.5 * siz.width, relativePosition.y + 0.5 * siz.height, z1);
	glVertex3f(relativePosition.x - 0.5 * siz.width, relativePosition.y + 0.5 * siz.height, z1);
	glEnd();
}


- (void) drawCompassSunBlipAt:(Vector) relativePosition Size:(NSSize) siz Alpha:(GLfloat) alpha
{
	glColor4f(1.0,1.0,0.0,0.75 * alpha);
	GLDrawFilledOval(relativePosition.x, relativePosition.y, z1, siz, 30);
	if (relativePosition.z >= 0)
	{
		glColor4f(0.0,1.0,0.0,alpha);
		GLDrawOval(relativePosition.x, relativePosition.y, z1, siz, 30);
	}
	else
	{
		glColor4f(1.0,0.0,0.0,alpha);
		GLDrawOval(relativePosition.x, relativePosition.y, z1, siz, 30);
	}
}


- (void) drawCompassTargetBlipAt:(Vector) relativePosition Size:(NSSize) siz Alpha:(GLfloat) alpha
{
	if (relativePosition.z >= 0)
	{
		glColor4f(0.0,1.0,0.0,alpha);
	}
	else
	{
		glColor4f(1.0,0.0,0.0,alpha);
	}
	glBegin(GL_LINES);
	glVertex3f(relativePosition.x - siz.width, relativePosition.y, z1);
	glVertex3f(relativePosition.x + siz.width, relativePosition.y, z1);
	glVertex3f(relativePosition.x, relativePosition.y - siz.height, z1);
	glVertex3f(relativePosition.x, relativePosition.y + siz.height, z1);
	glEnd();
	GLDrawOval(relativePosition.x, relativePosition.y, z1, siz, 30);
}


- (void) drawCompassWitchpointBlipAt:(Vector) relativePosition Size:(NSSize) siz Alpha:(GLfloat) alpha
{
	if (relativePosition.z >= 0)
	{
		glColor4f(0.0,1.0,0.0,alpha);
	}
	else
	{
		glColor4f(1.0,0.0,0.0,alpha);
	}
	glBegin(GL_LINES);
	
	glVertex3f(relativePosition.x - 0.5 * siz.width, relativePosition.y + 0.5 * siz.height, z1);
	glVertex3f(relativePosition.x - 0.25 * siz.width, relativePosition.y - 0.5 * siz.height, z1);
	
	glVertex3f(relativePosition.x - 0.25 * siz.width, relativePosition.y - 0.5 * siz.height, z1);
	glVertex3f(relativePosition.x, relativePosition.y, z1);
	
	glVertex3f(relativePosition.x, relativePosition.y, z1);
	glVertex3f(relativePosition.x + 0.25 * siz.width, relativePosition.y - 0.5 * siz.height, z1);
	
	glVertex3f(relativePosition.x + 0.25 * siz.width, relativePosition.y - 0.5 * siz.height, z1);
	glVertex3f(relativePosition.x + 0.5 * siz.width, relativePosition.y + 0.5 * siz.height, z1);
	glEnd();
}


- (void) drawCompassBeaconBlipAt:(Vector) relativePosition Size:(NSSize) siz Alpha:(GLfloat) alpha
{
	if (relativePosition.z >= 0)
	{
		glColor4f(0.0,1.0,0.0,alpha);
	}
	else
	{
		glColor4f(1.0,0.0,0.0,alpha);
	}
	glBegin(GL_LINES);
	
	glVertex3f(relativePosition.x - 0.5 * siz.width, relativePosition.y - 0.5 * siz.height, z1);
	glVertex3f(relativePosition.x, relativePosition.y + 0.5 * siz.height, z1);
	
	glVertex3f(relativePosition.x + 0.5 * siz.width, relativePosition.y - 0.5 * siz.height, z1);
	glVertex3f(relativePosition.x, relativePosition.y + 0.5 * siz.height, z1);
	
	glVertex3f(relativePosition.x - 0.5 * siz.width, relativePosition.y - 0.5 * siz.height, z1);
	glVertex3f(relativePosition.x + 0.5 * siz.width, relativePosition.y - 0.5 * siz.height, z1);
	
	glEnd();
}


- (void) drawAegis:(NSDictionary *) info
{
	if (([UNIVERSE viewDirection] == VIEW_GUI_DISPLAY)||([UNIVERSE sun] == nil)||([[PlayerEntity sharedPlayer] checkForAegis] != AEGIS_IN_DOCKING_RANGE))
		return;	// don't draw
	
    int				x;
	int				y;
	NSSize			siz;
	GLfloat			alpha = 0.5f;
	
	x = [info intForKey:X_KEY defaultValue:AEGIS_CENTRE_X];
	y = [info intForKey:Y_KEY defaultValue:AEGIS_CENTRE_Y];
	siz.width = [info nonNegativeFloatForKey:WIDTH_KEY defaultValue:AEGIS_WIDTH];
	siz.height = [info nonNegativeFloatForKey:HEIGHT_KEY defaultValue:AEGIS_HEIGHT];
	siz.height = [info nonNegativeFloatForKey:HEIGHT_KEY defaultValue:AEGIS_HEIGHT];
	alpha *= [info nonNegativeFloatForKey:ALPHA_KEY defaultValue:1.0f] * overallAlpha;

	// draw the aegis indicator
	//
	GLfloat	w = siz.width / 16.0;
	GLfloat	h = siz.height / 16.0;
	
	GLfloat strip[] = { -7,8, -6,5, 5,8, 3,5, 7,2, 4,2, 6,-1, 4,2, -4,-1, -6,2, -4,-1, -7,-1, -3,-4, -5,-7, 6,-4, 7,-7 };
	
	glColor4f(0.0f, 1.0f, 0.0f, alpha);
	glBegin(GL_QUAD_STRIP);
	int i;
	for (i = 0; i < 32; i += 2)
		glVertex3f(x + w * strip[i], y - h * strip[i + 1], z1);
	glEnd();
	
}


- (void) drawSpeedBar:(NSDictionary *) info
{
	PlayerEntity	*player = [PlayerEntity sharedPlayer];
    int				x;
	int				y;
	NSSize			siz;
	BOOL			draw_surround;
	
	x = [info intForKey:X_KEY defaultValue:SPEED_BAR_CENTRE_X];
	y = [info intForKey:Y_KEY defaultValue:SPEED_BAR_CENTRE_Y];
	siz.width = [info nonNegativeFloatForKey:WIDTH_KEY defaultValue:SPEED_BAR_WIDTH];
	siz.height = [info nonNegativeFloatForKey:HEIGHT_KEY defaultValue:SPEED_BAR_HEIGHT];
	draw_surround = [info boolForKey:DRAW_SURROUND_KEY defaultValue:SPEED_BAR_DRAW_SURROUND];
	
    double ds = [player dialSpeed];

	if (draw_surround)
	{
		// draw speed surround
		GLColorWithOverallAlpha(green_color, overallAlpha);
		hudDrawSurroundAt(x, y, z1, siz);
	}
	// draw speed bar
	if (ds > .25)
		GLColorWithOverallAlpha(yellow_color, overallAlpha);
	if (ds > .80)
		GLColorWithOverallAlpha(red_color, overallAlpha);
	hudDrawBarAt(x, y, z1, siz, ds);
	
}


- (void) drawRollBar:(NSDictionary *) info
{
	PlayerEntity	*player = [PlayerEntity sharedPlayer];
    int				x;
	int				y;
	NSSize			siz;
	BOOL			draw_surround;
	
	x = [info intForKey:X_KEY defaultValue:ROLL_BAR_CENTRE_X];
	y = [info intForKey:Y_KEY defaultValue:ROLL_BAR_CENTRE_Y];
	siz.width = [info nonNegativeFloatForKey:WIDTH_KEY defaultValue:ROLL_BAR_WIDTH];
	siz.height = [info nonNegativeFloatForKey:HEIGHT_KEY defaultValue:ROLL_BAR_HEIGHT];
	draw_surround = [info boolForKey:DRAW_SURROUND_KEY defaultValue:ROLL_BAR_DRAW_SURROUND];

	if (draw_surround)
	{
		// draw ROLL surround
		GLColorWithOverallAlpha(green_color, overallAlpha);
		hudDrawSurroundAt(x, y, z1, siz);
	}
	// draw ROLL bar
	GLColorWithOverallAlpha(yellow_color, overallAlpha);
	hudDrawIndicatorAt(x, y, z1, siz, [player dialRoll]);
}


- (void) drawPitchBar:(NSDictionary *) info
{
	PlayerEntity	*player = [PlayerEntity sharedPlayer];
    int				x;
	int				y;
	NSSize			siz;
	BOOL			draw_surround;
	
	x = [info intForKey:X_KEY defaultValue:PITCH_BAR_CENTRE_X];
	y = [info intForKey:Y_KEY defaultValue:PITCH_BAR_CENTRE_Y];
	siz.width = [info nonNegativeFloatForKey:WIDTH_KEY defaultValue:PITCH_BAR_WIDTH];
	siz.height = [info nonNegativeFloatForKey:HEIGHT_KEY defaultValue:PITCH_BAR_HEIGHT];
	draw_surround = [info boolForKey:DRAW_SURROUND_KEY defaultValue:PITCH_BAR_DRAW_SURROUND];

	if (draw_surround)
	{
		// draw PITCH surround
		GLColorWithOverallAlpha(green_color, overallAlpha);
		hudDrawSurroundAt(x, y, z1, siz);
	}
	// draw PITCH bar
	GLColorWithOverallAlpha(yellow_color, overallAlpha);
	hudDrawIndicatorAt(x, y, z1, siz, [player dialPitch]);
}


- (void) drawEnergyGauge:(NSDictionary *) info
{
	PlayerEntity	*player = [PlayerEntity sharedPlayer];
    int				x;
	int				y;
	NSSize			siz;
	BOOL			draw_surround, labelled;
	
	x = [info intForKey:X_KEY defaultValue:ENERGY_GAUGE_CENTRE_X];
	y = [info intForKey:Y_KEY defaultValue:ENERGY_GAUGE_CENTRE_Y];
	siz.width = [info nonNegativeFloatForKey:WIDTH_KEY defaultValue:ENERGY_GAUGE_WIDTH];
	siz.height = [info nonNegativeFloatForKey:HEIGHT_KEY defaultValue:ENERGY_GAUGE_HEIGHT];
	draw_surround = [info boolForKey:DRAW_SURROUND_KEY defaultValue:ENERGY_GAUGE_DRAW_SURROUND];
	labelled = [info boolForKey:LABELLED_KEY defaultValue:YES];
	
	int n_bars = [player dialMaxEnergy]/64.0;
	n_bars = [info unsignedIntForKey:N_BARS_KEY defaultValue:n_bars];
	if (n_bars < 1)  n_bars = 1;
	if (n_bars > 8)  labelled = NO;
	
	if (draw_surround)
	{
		// draw energy surround
		GLColorWithOverallAlpha(yellow_color, overallAlpha);
		hudDrawSurroundAt(x, y, z1, siz);
	}

	// draw energy banks
	{
		int qy = siz.height / n_bars;
		NSSize dial_size = NSMakeSize(siz.width,qy - 2);
		int cy = y - (n_bars - 1) * qy / 2;
		double energy = [player dialEnergy]*n_bars;
		[player setAlertFlag:ALERT_FLAG_ENERGY to:((energy < 1.0)&&([player status] == STATUS_IN_FLIGHT))];
		int i;
		for (i = 0; i < n_bars; i++)
		{
			GLColorWithOverallAlpha(yellow_color, overallAlpha);
			if (energy > 1.0)
				hudDrawBarAt(x, cy, z1, dial_size, 1.0);
			if ((energy > 0.0)&&(energy <= 1.0))
				hudDrawBarAt(x, cy, z1, dial_size, energy);
			if (labelled)
			{
				GLColorWithOverallAlpha(green_color, overallAlpha);
				drawString([NSString stringWithFormat:@"E%x",n_bars - i], x + 0.5 * dial_size.width + 2, cy - 0.5 * qy, z1, NSMakeSize(9, (qy < 18)? qy : 18 ));
			}
			energy -= 1.0;
			cy += qy;
		}
	}

}


- (void) drawForwardShieldBar:(NSDictionary *) info
{
	PlayerEntity	*player = [PlayerEntity sharedPlayer];
    int				x;
	int				y;
	NSSize			siz;
	BOOL			draw_surround;
	
	x = [info intForKey:X_KEY defaultValue:FORWARD_SHIELD_BAR_CENTRE_X];
	y = [info intForKey:Y_KEY defaultValue:FORWARD_SHIELD_BAR_CENTRE_Y];
	siz.width = [info nonNegativeFloatForKey:WIDTH_KEY defaultValue:FORWARD_SHIELD_BAR_WIDTH];
	siz.height = [info nonNegativeFloatForKey:HEIGHT_KEY defaultValue:FORWARD_SHIELD_BAR_HEIGHT];
	draw_surround = [info boolForKey:DRAW_SURROUND_KEY defaultValue:FORWARD_SHIELD_BAR_DRAW_SURROUND];

	double shield = [player dialForwardShield];
	if (draw_surround)
	{
		// draw forward_shield surround
		GLColorWithOverallAlpha(green_color, overallAlpha);
		hudDrawSurroundAt(x, y, z1, siz);
	}
	// draw forward_shield bar
	GLColorWithOverallAlpha(green_color, overallAlpha);
	if (shield < .80)
		GLColorWithOverallAlpha(yellow_color, overallAlpha);
	if (shield < .25)
		GLColorWithOverallAlpha(red_color, overallAlpha);
	hudDrawBarAt(x, y, z1, siz, shield);
}


- (void) drawAftShieldBar:(NSDictionary *) info
{
	PlayerEntity	*player = [PlayerEntity sharedPlayer];
    int				x;
	int				y;
	NSSize			siz;
	BOOL			draw_surround;
	
	x = [info intForKey:X_KEY defaultValue:AFT_SHIELD_BAR_CENTRE_X];
	y = [info intForKey:Y_KEY defaultValue:AFT_SHIELD_BAR_CENTRE_Y];
	siz.width = [info nonNegativeFloatForKey:WIDTH_KEY defaultValue:AFT_SHIELD_BAR_WIDTH];
	siz.height = [info nonNegativeFloatForKey:HEIGHT_KEY defaultValue:AFT_SHIELD_BAR_HEIGHT];
	draw_surround = [info boolForKey:DRAW_SURROUND_KEY defaultValue:AFT_SHIELD_BAR_DRAW_SURROUND];

	double shield = [player dialAftShield];
	if (draw_surround)
	{
		// draw aft_shield surround
		GLColorWithOverallAlpha(green_color, overallAlpha);
		hudDrawSurroundAt(x, y, z1, siz);
	}
	// draw aft_shield bar
	GLColorWithOverallAlpha(green_color, overallAlpha);
	if (shield < .80)
		GLColorWithOverallAlpha(yellow_color, overallAlpha);
	if (shield < .25)
		GLColorWithOverallAlpha(red_color, overallAlpha);
	hudDrawBarAt(x, y, z1, siz, shield);
}


- (void) drawFuelBar:(NSDictionary *) info
{
	PlayerEntity	*player = [PlayerEntity sharedPlayer];
    int				x;
	int				y;
	NSSize			siz;
	float			fu, hr;
	
	x = [info intForKey:X_KEY defaultValue:FUEL_BAR_CENTRE_X];
	y = [info intForKey:Y_KEY defaultValue:FUEL_BAR_CENTRE_Y];
	siz.width = [info nonNegativeFloatForKey:WIDTH_KEY defaultValue:FUEL_BAR_WIDTH];
	siz.height = [info nonNegativeFloatForKey:HEIGHT_KEY defaultValue:FUEL_BAR_HEIGHT];
	
    fu = [player dialFuel];
	hr = [player dialHyperRange];

	// draw fuel bar
	GLColorWithOverallAlpha(yellow_color, overallAlpha);
	hudDrawBarAt(x, y, z1, siz, fu);
	
	// draw range indicator
	if ((hr > 0)&&(hr <= 1.0))
	{
		glColor4fv((fu < hr)? red_color : green_color);
		hudDrawMarkerAt(x, y, z1, siz, hr);
	}
}


- (void) drawCabinTempBar:(NSDictionary *) info
{
	PlayerEntity	*player = [PlayerEntity sharedPlayer];
    int				x;
	int				y;
	NSSize			siz;
	
	x = [info intForKey:X_KEY defaultValue:CABIN_TEMP_BAR_CENTRE_X];
	y = [info intForKey:Y_KEY defaultValue:CABIN_TEMP_BAR_CENTRE_Y];
	siz.width = [info nonNegativeFloatForKey:WIDTH_KEY defaultValue:CABIN_TEMP_BAR_WIDTH];
	siz.height = [info nonNegativeFloatForKey:HEIGHT_KEY defaultValue:CABIN_TEMP_BAR_HEIGHT];
	
	double temp = [player hullHeatLevel];
	int flash = (int)([UNIVERSE getTime] * 4);
	flash &= 1;
	// draw ship_temperature bar
	GLColorWithOverallAlpha(green_color, overallAlpha);
	if (temp > .25)
		GLColorWithOverallAlpha(yellow_color, overallAlpha);
	if (temp > .80)
		GLColorWithOverallAlpha(red_color, overallAlpha);
	if ((flash)&&(temp > .90))
		GLColorWithOverallAlpha(redplus_color, overallAlpha);
	[player setAlertFlag:ALERT_FLAG_TEMP to:((temp > .90)&&(player->status == STATUS_IN_FLIGHT))];
	hudDrawBarAt(x, y, z1, siz, temp);
}


- (void) drawWeaponTempBar:(NSDictionary *) info
{
	PlayerEntity	*player = [PlayerEntity sharedPlayer];
    int				x;
	int				y;
	NSSize			siz;
	
	x = [info intForKey:X_KEY defaultValue:WEAPON_TEMP_BAR_CENTRE_X];
	y = [info intForKey:Y_KEY defaultValue:WEAPON_TEMP_BAR_CENTRE_Y];
	siz.width = [info nonNegativeFloatForKey:WIDTH_KEY defaultValue:WEAPON_TEMP_BAR_WIDTH];
	siz.height = [info nonNegativeFloatForKey:HEIGHT_KEY defaultValue:WEAPON_TEMP_BAR_HEIGHT];

	double temp = [player laserHeatLevel];
	// draw weapon_temp bar
	GLColorWithOverallAlpha(green_color, overallAlpha);
	if (temp > .25)
		GLColorWithOverallAlpha(yellow_color, overallAlpha);
	if (temp > .80)
		GLColorWithOverallAlpha(red_color, overallAlpha);
	hudDrawBarAt(x, y, z1, siz, temp);
}


- (void) drawAltitudeBar:(NSDictionary *) info
{
	PlayerEntity	*player = [PlayerEntity sharedPlayer];
    int				x;
	int				y;
	NSSize			siz;
	
	x = [info intForKey:X_KEY defaultValue:ALTITUDE_BAR_CENTRE_X];
	y = [info intForKey:Y_KEY defaultValue:ALTITUDE_BAR_CENTRE_Y];
	siz.width = [info nonNegativeFloatForKey:WIDTH_KEY defaultValue:ALTITUDE_BAR_WIDTH];
	siz.height = [info nonNegativeFloatForKey:HEIGHT_KEY defaultValue:ALTITUDE_BAR_HEIGHT];
	
	GLfloat alt = [player dialAltitude];
	int flash = (int)([UNIVERSE getTime] * 4);
	flash &= 1;
	
	// draw altitude bar
	if (alt < .75)  GLColorWithOverallAlpha(yellow_color, overallAlpha);
	else if (alt < .25)  GLColorWithOverallAlpha(red_color, overallAlpha);
	else if ((flash)&&(alt < .10))  GLColorWithOverallAlpha(redplus_color, overallAlpha);
	else GLColorWithOverallAlpha(green_color, overallAlpha);
	hudDrawBarAt(x, y, z1, siz, alt);
	
	[player setAlertFlag:ALERT_FLAG_ALT to:((alt < .10)&&(player->status == STATUS_IN_FLIGHT))];
}


- (void) drawMissileDisplay:(NSDictionary *) info
{
	PlayerEntity	*player = [PlayerEntity sharedPlayer];
    int				x;
	int				y;
	NSSize			siz;
	int				sp;
	
	x = [info intForKey:X_KEY defaultValue:MISSILES_DISPLAY_X];
	y = [info intForKey:Y_KEY defaultValue:MISSILES_DISPLAY_Y];
	sp = [info unsignedIntForKey:SPACING_KEY defaultValue:MISSILES_DISPLAY_SPACING];
	siz.width = [info nonNegativeFloatForKey:WIDTH_KEY defaultValue:MISSILE_ICON_WIDTH];
	siz.height = [info nonNegativeFloatForKey:HEIGHT_KEY defaultValue:MISSILE_ICON_HEIGHT];
	
	if (![player dialIdentEngaged])
	{
		unsigned n_mis = [player dialMaxMissiles];
		unsigned i;
		for (i = 0; i < n_mis; i++)
		{
			if ([player missileForStation:i])
			{
				// TODO: copy icon data into missile object instead of looking it up each time. Possibly make weapon stores a ShipEntity subclass?
				NSString	*miss_roles = [[player missileForStation:i] primaryRole];
				NSArray		*miss_icon = [[UNIVERSE descriptions] arrayForKey:miss_roles];
				if (i == [player activeMissile])
				{
					GLColorWithOverallAlpha(yellow_color, overallAlpha);
					glBegin(GL_POLYGON);
					if (miss_icon)
					{
						hudDrawSpecialIconAt(miss_icon, x + i * sp + 2, y + 1, z1, NSMakeSize(siz.width + 4, siz.height + 4));
					}
					else
					{
						if ([miss_roles hasSuffix:@"MISSILE"])
							hudDrawMissileIconAt(x + i * sp + 2, y + 1, z1, NSMakeSize(siz.width + 4, siz.height + 4));
						if ([miss_roles hasSuffix:@"MINE"])
							hudDrawMineIconAt(x + i * sp + 2, y + 1, z1, NSMakeSize(siz.width + 4, siz.height + 4));
					}
					glEnd();
					
					// Draw black backing, so outline colour isn’t blended into missile colour.
					glColor4f(0.0, 0.0, 0.0, 1.0);
					glBegin(GL_POLYGON);
					if (miss_icon)
					{
						hudDrawSpecialIconAt(miss_icon, x + i * sp, y, z1, siz);
					}
					else
					{
						if ([miss_roles hasSuffix:@"MISSILE"])
							hudDrawMissileIconAt(x + i * sp, y, z1, siz);
						if ([miss_roles hasSuffix:@"MINE"])
							hudDrawMineIconAt(x + i * sp, y, z1, siz);
					}
					glEnd();
					
					switch ([player dialMissileStatus])
					{
						case MISSILE_STATUS_SAFE :
							GLColorWithOverallAlpha(green_color, overallAlpha);		break;
						case MISSILE_STATUS_ARMED :
							GLColorWithOverallAlpha(yellow_color, overallAlpha);	break;
						case MISSILE_STATUS_TARGET_LOCKED :
							GLColorWithOverallAlpha(red_color, overallAlpha);		break;
					}
				}
				else
				{
					if ([[player missileForStation:i] primaryTarget])
						GLColorWithOverallAlpha(red_color, overallAlpha);
					else
						GLColorWithOverallAlpha(green_color, overallAlpha);
				}
				glBegin(GL_POLYGON);
				if (miss_icon)
				{
					hudDrawSpecialIconAt(miss_icon, x + i * sp, y, z1, siz);
				}
				else
				{
					if ([miss_roles hasSuffix:@"MISSILE"])
						hudDrawMissileIconAt(x + i * sp, y, z1, siz);
					if ([miss_roles hasSuffix:@"MINE"])
						hudDrawMineIconAt(x + i * sp, y, z1, siz);
				}
				glEnd();
				if (i != [player activeMissile])
				{
					GLColorWithOverallAlpha(green_color, overallAlpha);
					glBegin(GL_LINE_LOOP);
					if (miss_icon)
					{
						hudDrawSpecialIconAt(miss_icon, x + i * sp, y, z1, siz);
					}
					else
					{
						if ([miss_roles hasSuffix:@"MISSILE"])
							hudDrawMissileIconAt(x + i * sp, y, z1, siz);
						if ([miss_roles hasSuffix:@"MINE"])
							hudDrawMineIconAt(x + i * sp, y, z1, siz);
					}
					glEnd();
				}
			}
			else
			{
				glColor4f(0.25, 0.25, 0.25, 0.5);
				glBegin(GL_LINE_LOOP);
				hudDrawMissileIconAt(x + i * sp, y, z1, siz);
				glEnd();
			}
		}
	}
	else
	{
		x -= siz.width;
		y -= siz.height * 0.75;
		siz.width *= 0.80;
		sp *= 0.75;
		switch ([player dialMissileStatus])
		{
			case MISSILE_STATUS_SAFE :
				GLColorWithOverallAlpha(green_color, overallAlpha);	break;
			case MISSILE_STATUS_ARMED :
				GLColorWithOverallAlpha(yellow_color, overallAlpha);	break;
			case MISSILE_STATUS_TARGET_LOCKED :
				GLColorWithOverallAlpha(red_color, overallAlpha);	break;
		}
		glBegin(GL_QUADS);
		glVertex3i(x , y, z1);
		glVertex3i(x + siz.width, y, z1);
		glVertex3i(x + siz.width, y + siz.height, z1);
		glVertex3i(x , y + siz.height, z1);
		glEnd();
		GLColorWithOverallAlpha(green_color, overallAlpha);
		drawString([player dialTargetName], x + sp, y, z1, NSMakeSize(siz.width, siz.height));
	}
	
}


- (void) drawTargetReticle:(NSDictionary *) info
{
	PlayerEntity *player = [PlayerEntity sharedPlayer];
	
	if ([player dialMissileStatus] == MISSILE_STATUS_TARGET_LOCKED)
	{
		hudDrawReticleOnTarget([player primaryTarget], player, z1, overallAlpha);
		[self drawDirectionCue:info];
	}
}


- (void) drawStatusLight:(NSDictionary *) info
{
	PlayerEntity	*player = [PlayerEntity sharedPlayer];
    int				x;
	int				y;
	NSSize			siz;
	
	x = [info intForKey:X_KEY defaultValue:STATUS_LIGHT_CENTRE_X];
	y = [info intForKey:Y_KEY defaultValue:STATUS_LIGHT_CENTRE_Y];
	siz.width = [info nonNegativeFloatForKey:WIDTH_KEY defaultValue:STATUS_LIGHT_HEIGHT];
	siz.height = [info nonNegativeFloatForKey:HEIGHT_KEY defaultValue:STATUS_LIGHT_HEIGHT];
	
	GLfloat status_color[4] = { 0.25, 0.25, 0.25, 1.0};
	int alertCondition = [player alertCondition];
	double flash_alpha = 0.333 * (2.0 + sin([UNIVERSE getTime] * 2.5 * alertCondition));
	
	switch(alertCondition)
	{
		case ALERT_CONDITION_RED :
			status_color[0] = red_color[0];
			status_color[1] = red_color[1];
			status_color[2] = red_color[2];
			break;
		case ALERT_CONDITION_GREEN :
			status_color[0] = green_color[0];
			status_color[1] = green_color[1];
			status_color[2] = green_color[2];
			break;
		case ALERT_CONDITION_YELLOW :
			status_color[0] = yellow_color[0];
			status_color[1] = yellow_color[1];
			status_color[2] = yellow_color[2];
			break;
		default :
		case ALERT_CONDITION_DOCKED :
			break;
	}
	status_color[3] = flash_alpha;
	GLColorWithOverallAlpha(status_color, overallAlpha);
	glBegin(GL_POLYGON);
	hudDrawStatusIconAt(x, y, z1, siz);
	glEnd();
	glColor4f(0.25, 0.25, 0.25, overallAlpha);
	glBegin(GL_LINE_LOOP);
	hudDrawStatusIconAt(x, y, z1, siz);
	glEnd();
}


- (void) drawDirectionCue:(NSDictionary *) info
{
	PlayerEntity	*player = [PlayerEntity sharedPlayer];
	NSString		*equipment = nil;
	
 	// the direction cue is an advanced option
	// so we need to check for its extra equipment flag first
	equipment = [info stringForKey:EQUIPMENT_REQUIRED_KEY];
	if (equipment != nil && ![player hasEquipmentItem:equipment])
		return;
	
	if ([UNIVERSE displayGUI])
		return;
	
	if ([player dialMissileStatus] == MISSILE_STATUS_TARGET_LOCKED)
	{
		GLfloat		clear_color[4] = {0.0, 1.0, 0.0, 0.0};
		Entity		*target = [player primaryTarget];
		if (!target)
			return;
		
		// draw the direction cue
		OOMatrix	rotMatrix;
		Vector		position = [player position];
		
		rotMatrix = [player rotationMatrix];
		
		if ([UNIVERSE viewDirection] != VIEW_GUI_DISPLAY)
		{
			GLfloat siz1 = CROSSHAIR_SIZE * (1.0 - ONE_EIGHTH);
			GLfloat siz0 = CROSSHAIR_SIZE * ONE_EIGHTH;
			GLfloat siz2 = CROSSHAIR_SIZE * (1.0 + ONE_EIGHTH);
			
			// Transform the view
			Vector rpn = vector_subtract([target position], position);
			rpn = OOVectorMultiplyMatrix(rpn, rotMatrix);
			
			switch ([UNIVERSE viewDirection])
			{
				case VIEW_AFT:
					rpn.x = - rpn.x;
					break;
				case VIEW_PORT:
					rpn.x = rpn.z;
					break;
				case VIEW_STARBOARD:
					rpn.x = -rpn.z;
					break;
				case VIEW_CUSTOM:
					rpn = OOVectorMultiplyMatrix(rpn, [player customViewMatrix]);
					break;
				
				default:
					break;
			}
			rpn.z = 0;	// flatten vector
			if (rpn.x||rpn.y)
			{
				rpn = unit_vector(&rpn);
				glBegin(GL_LINES);
					glColor4fv(clear_color);
					glVertex3f(rpn.x * siz1 - rpn.y * siz0, rpn.y * siz1 + rpn.x * siz0, z1);
					GLColorWithOverallAlpha(green_color, overallAlpha);
					glVertex3f(rpn.x * siz2, rpn.y * siz2, z1);
					glColor4fv(clear_color);
					glVertex3f(rpn.x * siz1 + rpn.y * siz0, rpn.y * siz1 - rpn.x * siz0, z1);
					GLColorWithOverallAlpha(green_color, overallAlpha);
					glVertex3f(rpn.x * siz2, rpn.y * siz2, z1);
				glEnd();
			}
		}
	}
}


- (void) drawClock:(NSDictionary *) info
{
	PlayerEntity	*player = [PlayerEntity sharedPlayer];
    int				x;
	int				y;
	NSSize			siz;
	
	x = [info intForKey:X_KEY defaultValue:CLOCK_DISPLAY_X];
	y = [info intForKey:Y_KEY defaultValue:CLOCK_DISPLAY_Y];
	siz.width = [info nonNegativeFloatForKey:WIDTH_KEY defaultValue:CLOCK_DISPLAY_WIDTH];
	siz.height = [info nonNegativeFloatForKey:HEIGHT_KEY defaultValue:CLOCK_DISPLAY_HEIGHT];
	
	GLColorWithOverallAlpha(green_color, overallAlpha);
	drawString([player dial_clock], x, y, z1, siz);
}


- (void) drawFPSInfoCounter:(NSDictionary *) info
{
	if (![UNIVERSE displayFPS])  return;

	PlayerEntity	*player = [PlayerEntity sharedPlayer];
    int				x;
	int				y;
	NSSize			siz;
	
	x = [info intForKey:X_KEY defaultValue:FPSINFO_DISPLAY_X];
	y = [info intForKey:Y_KEY defaultValue:FPSINFO_DISPLAY_Y];
	siz.width = [info nonNegativeFloatForKey:WIDTH_KEY defaultValue:FPSINFO_DISPLAY_WIDTH];
	siz.height = [info nonNegativeFloatForKey:HEIGHT_KEY defaultValue:FPSINFO_DISPLAY_HEIGHT];
	
	NSString* positionInfo = [UNIVERSE expressPosition:player->position inCoordinateSystem:@"pwm"];
	NSString* collDebugInfo = [NSString stringWithFormat:@"%@ - %@", [player dial_objinfo], [UNIVERSE collisionDescription]];
	
	NSSize siz08 = NSMakeSize(0.8 * siz.width, 0.8 * siz.width);

	glColor4f(0.0, 1.0, 0.0, 1.0);
	drawString([player dial_fpsinfo], x, y, z1, siz);
	drawString(collDebugInfo, x, y - siz.height, z1, siz);
	
	drawString(positionInfo, x, y - 1.8 * siz.height, z1, siz08);
}


- (void) drawScoopStatus:(NSDictionary *) info
{
	PlayerEntity	*player = [PlayerEntity sharedPlayer];
    int				x;
	int				y;
	NSSize			siz;
	GLfloat			alpha;
	
	x = [info intForKey:X_KEY defaultValue:SCOOPSTATUS_CENTRE_X];
	y = [info intForKey:Y_KEY defaultValue:SCOOPSTATUS_CENTRE_Y];
	siz.width = [info nonNegativeFloatForKey:WIDTH_KEY defaultValue:SCOOPSTATUS_WIDTH];
	siz.height = [info nonNegativeFloatForKey:HEIGHT_KEY defaultValue:SCOOPSTATUS_HEIGHT];
	alpha = [info nonNegativeFloatForKey:ALPHA_KEY defaultValue:0.75f];

	GLfloat* s0_color = red_color;
	GLfloat	s1c[4] = { 0.0f, 0.0f, 0.0f, 0.0f };
	GLfloat	s2c[4] = { 0.0f, 0.0f, 0.0f, 0.0f };
	GLfloat	s3c[4] = { 0.0f, 0.0f, 0.0f, 0.0f };
	int scoop_status = [player dialFuelScoopStatus];
	double t = [UNIVERSE getTime];
	GLfloat a1 = alpha * 0.5f * (1.0f + sin(t * 8.0f));
	GLfloat a2 = alpha * 0.5f * (1.0f + sin(t * 8.0f - 1.0f));
	GLfloat a3 = alpha * 0.5f * (1.0f + sin(t * 8.0f - 2.0f));
		
	switch (scoop_status)
	{
		case SCOOP_STATUS_NOT_INSTALLED :
			return;	// don't draw
		case SCOOP_STATUS_FULL_HOLD :
			s0_color = darkgreen_color;
			alpha *= 0.75;
			break;
		case SCOOP_STATUS_ACTIVE :
		case SCOOP_STATUS_OKAY :
			s0_color = green_color;
			break;
	}
	int i;
	for (i = 0; i < 3; i++)
	{
		s1c[i] = s0_color[i];
		s2c[i] = s0_color[i];
		s3c[i] = s0_color[i];
	}
	if (scoop_status == SCOOP_STATUS_FULL_HOLD)
	{
		s3c[0] = red_color[0];
		s3c[1] = red_color[1];
		s3c[2] = red_color[2];
	}
	if (scoop_status == SCOOP_STATUS_ACTIVE)
	{
		s1c[3] = alpha * a1;
		s2c[3] = alpha * a2;
		s3c[3] = alpha * a3;
	}
	else
	{
		s1c[3] = alpha;
		s2c[3] = alpha;
		s3c[3] = alpha;
	}
	
	GLfloat w1 = siz.width / 8.0;
	GLfloat w2 = 2.0 * w1;
//	GLfloat w3 = 3.0 * w1;
	GLfloat w4 = 4.0 * w1;
	GLfloat h1 = siz.height / 8.0;
	GLfloat h2 = 2.0 * h1;
	GLfloat h3 = 3.0 * h1;
	GLfloat h4 = 4.0 * h1;
	
	glDisable(GL_TEXTURE_2D);
	glBegin(GL_QUADS);
	// section 1
		glColor4fv(s1c);
		glVertex3f(x, y + h1, z1);	glVertex3f(x - w2, y + h2, z1);	glVertex3f(x, y + h3, z1);	glVertex3f(x + w2, y + h2, z1);
	// section 2
		glColor4fv(s2c);
		glVertex3f(x, y - h1, z1);	glVertex3f(x - w4, y + h1, z1);	glVertex3f(x - w4, y + h2, z1);	glVertex3f(x, y, z1);
		glVertex3f(x, y - h1, z1);	glVertex3f(x + w4, y + h1, z1);	glVertex3f(x + w4, y + h2, z1);	glVertex3f(x, y, z1);
	// section 3
		glColor4fv(s3c);
		glVertex3f(x, y - h4, z1);	glVertex3f(x - w2, y - h2, z1);	glVertex3f(x - w2, y - h1, z1);	glVertex3f(x, y - h2, z1);
		glVertex3f(x, y - h4, z1);	glVertex3f(x + w2, y - h2, z1);	glVertex3f(x + w2, y - h1, z1);	glVertex3f(x, y - h2, z1);
	glEnd();
	
}


- (void) drawSurround:(NSDictionary *)info color:(GLfloat[4])color
{
    int				x;
	int				y;
	NSSize			siz;
	
	x = [info intForKey:X_KEY defaultValue:NSNotFound];
	y = [info intForKey:Y_KEY defaultValue:NSNotFound];
	siz.width = [info nonNegativeFloatForKey:WIDTH_KEY defaultValue:NAN];
	siz.height = [info nonNegativeFloatForKey:HEIGHT_KEY defaultValue:NAN];
	
	if (x == NSNotFound || y == NSNotFound || isnan(siz.width) || isnan(siz.height))  return;
	
	// draw green surround
	GLColorWithOverallAlpha(color, overallAlpha);
	hudDrawSurroundAt(x, y, z1, siz);
}


- (void) drawGreenSurround:(NSDictionary *) info
{
	[self drawSurround:info color:green_color];
}


- (void) drawYellowSurround:(NSDictionary *) info
{
	[self drawSurround:info color:yellow_color];
}


- (void) drawTrumbles:(NSDictionary *) info
{
	PlayerEntity *player = [PlayerEntity sharedPlayer];
	
	OOTrumble** trumbles = [player trumbleArray];
	int i;
	for (i = [player trumbleCount]; i > 0; i--)
	{
		OOTrumble* trum = trumbles[i - 1];
		[trum drawTrumble: z1];
	}
}

//---------------------------------------------------------------------//

void hudDrawIndicatorAt(GLfloat x, GLfloat y, GLfloat z, NSSize siz, double amount)
{
	if (siz.width > siz.height)
	{
		GLfloat dial_oy =   y - siz.height/2;
		GLfloat position =  x + amount * siz.width / 2;
		glBegin(GL_QUADS);
			glVertex3f(position, dial_oy, z);
			glVertex3f(position+2, y, z);
			glVertex3f(position, dial_oy+siz.height, z);
			glVertex3f(position-2, y, z);
		glEnd();
	}
	else
	{
		GLfloat dial_ox =   x - siz.width/2;
		GLfloat position =  y + amount * siz.height / 2;
		glBegin(GL_QUADS);
			glVertex3f(dial_ox, position, z);
			glVertex3f(x, position+2, z);
			glVertex3f(dial_ox + siz.width, position, z);
			glVertex3f(x, position-2, z);
		glEnd();
	}
}


void hudDrawMarkerAt(GLfloat x, GLfloat y, GLfloat z, NSSize siz, double amount)
{
	if (siz.width > siz.height)
	{
		GLfloat dial_oy =   y - siz.height/2;
		GLfloat position =  x + amount * siz.width - siz.width/2;
		glBegin(GL_QUADS);
			glVertex3f(position+1, dial_oy+1, z);
			glVertex3f(position+1, dial_oy+siz.height-1, z);
			glVertex3f(position-1, dial_oy+siz.height-1, z);
			glVertex3f(position-1, dial_oy+1, z);
		glEnd();
	}
	else
	{
		GLfloat dial_ox =   x - siz.width/2;
		GLfloat position =  y + amount * siz.height - siz.height/2;
		glBegin(GL_QUADS);
			glVertex3f(dial_ox+1, position+1, z);
			glVertex3f(dial_ox + siz.width-1, position+1, z);
			glVertex3f(dial_ox + siz.width-1, position-1, z);
			glVertex3f(dial_ox+1, position-1, z);
		glEnd();
	}
}


void hudDrawBarAt(GLfloat x, GLfloat y, GLfloat z, NSSize siz, double amount)
{
	GLfloat dial_ox =   x - siz.width/2;
	GLfloat dial_oy =   y - siz.height/2;
	if (fabs(siz.width) > fabs(siz.height))
	{
		GLfloat position =  dial_ox + amount * siz.width;
		
		glBegin(GL_QUADS);
			glVertex3f(dial_ox, dial_oy, z);
			glVertex3f(position, dial_oy, z);
			glVertex3f(position, dial_oy+siz.height, z);
			glVertex3f(dial_ox, dial_oy+siz.height, z);
		glEnd();
	}
	else
	{
		GLfloat position =  dial_oy + amount * siz.height;
		
		glBegin(GL_QUADS);
			glVertex3f(dial_ox, dial_oy, z);
			glVertex3f(dial_ox, position, z);
			glVertex3f(dial_ox+siz.width, position, z);
			glVertex3f(dial_ox+siz.width, dial_oy, z);
		glEnd();
	}
}


void hudDrawSurroundAt(GLfloat x, GLfloat y, GLfloat z, NSSize siz)
{
	GLfloat dial_ox = x - siz.width/2;
	GLfloat dial_oy = y - siz.height/2;

	glBegin(GL_LINE_LOOP);
		glVertex3f(dial_ox-2, dial_oy-2, z);
		glVertex3f(dial_ox+siz.width+2, dial_oy-2, z);
		glVertex3f(dial_ox+siz.width+2, dial_oy+siz.height+2, z);
		glVertex3f(dial_ox-2, dial_oy+siz.height+2, z);
	glEnd();
}


void hudDrawSpecialIconAt(NSArray* ptsArray, int x, int y, int z, NSSize siz)
{
	if (!ptsArray)
		return;
	int ox = x - siz.width / 2.0;
	int oy = y - siz.height / 2.0;
	int w = siz.width / 4.0;
	int h = siz.height / 4.0; 
	int i = 0;
	int npts = [ptsArray count] & 0xfffe;	// make sure it's an even number
	while (i < npts)
	{
		int x = [ptsArray intAtIndex:i++];
		int y = [ptsArray intAtIndex:i++];
		glVertex3i(ox + x * w, oy + y * h, z);
	}
}


void hudDrawMissileIconAt(int x, int y, int z, NSSize siz)
{
	int ox = x - siz.width / 2.0;
	int oy = y - siz.height / 2.0;
	int w = siz.width / 4.0;
	int h = siz.height / 4.0; 

	glVertex3i(ox, oy + 3 * h, z);
	glVertex3i(ox + 2 * w, oy, z);
	glVertex3i(ox + w, oy, z);
	glVertex3i(ox + w, oy - 2 * h, z);
	glVertex3i(ox - w, oy - 2 * h, z);
	glVertex3i(ox - w, oy, z);
	glVertex3i(ox - 2 * w, oy, z);
}


void hudDrawMineIconAt(int x, int y, int z, NSSize siz)
{
	int ox = x - siz.width / 2.0;
	int oy = y - siz.height / 2.0;
	int w = siz.width / 4.0;
	int h = siz.height / 4.0; 

	glVertex3i(ox, oy + 2 * h, z);
	glVertex3i(ox + w, oy + h, z);
	glVertex3i(ox + w, oy - h, z);
	glVertex3i(ox, oy - 2 * h, z);
	glVertex3i(ox - w, oy - h, z);
	glVertex3i(ox - w, oy + h, z);
}


void hudDrawStatusIconAt(int x, int y, int z, NSSize siz)
{
	int ox = x - siz.width / 2.0;
	int oy = y - siz.height / 2.0;
	int w = siz.width / 4.0;
	int h = siz.height / 4.0; 

	glVertex3i(ox, oy + h, z);
	glVertex3i(ox, oy + 3 * h, z);
	glVertex3i(ox + w, oy + 4 * h, z);
	glVertex3i(ox + 3 * w, oy + 4 * h, z);
	glVertex3i(ox + 4 * w, oy + 3 * h, z);
	glVertex3i(ox + 4 * w, oy + h, z);
	glVertex3i(ox + 3 * w, oy, z);
	glVertex3i(ox + w, oy, z);
}


void hudDrawReticleOnTarget(Entity* target, PlayerEntity* player1, GLfloat z1, GLfloat overallAlpha)
{
	ShipEntity		*target_ship = (ShipEntity *)target;
	NSString		*legal_desc = nil;
	if ((!target)||(!player1))
		return;

	if ([target_ship isCloaked])  return;
	
	switch ([target_ship scanClass])
	{
		case CLASS_NEUTRAL:
			{
				int target_legal = [target_ship legalStatus];
				int legal_i = 0;
				if (target_legal > 0)
					legal_i =  (target_legal <= 50) ? 1 : 2;
				legal_desc = [[[UNIVERSE descriptions] arrayForKey:@"legal_status"] stringAtIndex:legal_i];
			}
			break;
	
		case CLASS_THARGOID:
			legal_desc = DESC(@"legal-desc-alien");
			break;
		
		case CLASS_POLICE:
			legal_desc = DESC(@"legal-desc-system-vessel");
			break;
		
		case CLASS_MILITARY:
			legal_desc = DESC(@"legal-desc-military-vessel");
			break;
		
		default:
			break;
	}
	
	if ([player1 guiScreen] != GUI_SCREEN_MAIN)	// don't draw on text screens
		return;
	
	if (!target)
		return;
	
	OOMatrix		back_mat;
    Quaternion		back_q = [player1 orientation];
	back_q.w = -back_q.w;   // invert
	Vector			v1 = vector_up_from_quaternion(back_q);
	Vector			p1;
	
	p1 = vector_subtract([target position], [player1 viewpointPosition]);
	
	double			rdist = fast_magnitude(p1);
	double			rsize = [target collisionRadius];
	
	if (rsize < rdist * ONE_SIXTYFOURTH)
		rsize = rdist * ONE_SIXTYFOURTH;
	
	GLfloat			rs0 = rsize;
	GLfloat			rs2 = rsize * 0.50;
	
	glPushMatrix();
	
	// deal with view directions
	Vector view_dir, view_up = kBasisYVector;
	switch ([UNIVERSE viewDirection])
	{
		default:
		case VIEW_FORWARD :
			view_dir.x = 0.0;   view_dir.y = 0.0;   view_dir.z = 1.0;
			break;
		case VIEW_AFT :
			view_dir.x = 0.0;   view_dir.y = 0.0;   view_dir.z = -1.0;
			quaternion_rotate_about_axis(&back_q, v1, M_PI);
			break;
		case VIEW_PORT :
			view_dir.x = -1.0;   view_dir.y = 0.0;   view_dir.z = 0.0;
			quaternion_rotate_about_axis(&back_q, v1, 0.5 * M_PI);
			break;
		case VIEW_STARBOARD :
			view_dir.x = 1.0;   view_dir.y = 0.0;   view_dir.z = 0.0;
			quaternion_rotate_about_axis(&back_q, v1, -0.5 * M_PI);
			break;
		case VIEW_CUSTOM :
			view_dir = [player1 customViewForwardVector];
			view_up = [player1 customViewUpVector];
			back_q = quaternion_multiply([player1 customViewQuaternion], back_q);
			break;
	}
	gluLookAt(view_dir.x, view_dir.y, view_dir.z, 0.0, 0.0, 0.0, view_up.x, view_up.y, view_up.z);
	
	back_mat = OOMatrixForQuaternionRotation(back_q);
	
	// rotate the view
	GLMultOOMatrix([player1 rotationMatrix]);
	// translate the view
	glTranslatef(p1.x, p1.y, p1.z);
	//rotate to face player1
	GLMultOOMatrix(back_mat);
	// draw the reticle	
	GLColorWithOverallAlpha(green_color, overallAlpha);
	glBegin(GL_LINES);
		glVertex2f(rs0,rs2);	glVertex2f(rs0,rs0);
		glVertex2f(rs0,rs0);	glVertex2f(rs2,rs0);

		glVertex2f(rs0,-rs2);	glVertex2f(rs0,-rs0);
		glVertex2f(rs0,-rs0);	glVertex2f(rs2,-rs0);

		glVertex2f(-rs0,rs2);	glVertex2f(-rs0,rs0);
		glVertex2f(-rs0,rs0);	glVertex2f(-rs2,rs0);

		glVertex2f(-rs0,-rs2);	glVertex2f(-rs0,-rs0);
		glVertex2f(-rs0,-rs0);	glVertex2f(-rs2,-rs0);
	
	glEnd();
	
	// add text for reticle here
	float range = (sqrtf(target->zero_distance) - target->collision_radius) * 0.001f;
	NSSize textsize = NSMakeSize(rdist * ONE_SIXTYFOURTH, rdist * ONE_SIXTYFOURTH);
	float line_height = rdist * ONE_SIXTYFOURTH;
	NSString*	info1 = [target_ship identFromShip: player1];
	NSString*	info2 = (legal_desc == nil)? [NSString stringWithFormat:@"%0.3f km", range] : [NSString stringWithFormat:@"%0.3f km (%@)", range, legal_desc];
	// no need to set color - tis green already!
	drawString(info1, rs0, 0.5 * rs2, 0, textsize);
	drawString(info2, rs0, 0.5 * rs2 - line_height, 0, textsize);
	
	glPopMatrix();
}


static void InitTextEngine(void)
{
	NSDictionary			*fontSpec = nil;
	NSArray					*widths = nil;
	NSString				*texName = nil;
	unsigned				i, count;
	
	fontSpec = [ResourceManager dictionaryFromFilesNamed:@"oolite-font.plist"
												inFolder:@"Config"
												andMerge:NO];
	
	texName = [fontSpec stringForKey:@"texture" defaultValue:@"oolite-font.png"];
	sFontTexture = [OOTexture textureWithName:texName
									 inFolder:@"Textures"
									  options:kFontTextureOptions
								   anisotropy:0.0f
									  lodBias:-0.75f];
	[sFontTexture retain];
	
	sEncodingCoverter = [[OOEncodingConverter alloc] initWithFontPList:fontSpec];
	widths = [fontSpec arrayForKey:@"widths"];
	count = [widths count];
	if (count > 256)  count = 256;
	for (i = 0; i != count; ++i)
	{
		sGlyphWidths[i] = [widths floatAtIndex:i] * 0.13; // 0.13 is an inherited magic number
	}
}


static double drawCharacterQuad(uint8_t chr, double x, double y, double z, NSSize siz)
{
	GLfloat texture_x = ONE_SIXTEENTH * (chr & 0x0f);
	GLfloat texture_y = ONE_SIXTEENTH * (chr >> 4);
	if (chr > 32)  y += ONE_EIGHTH * siz.height;	// Adjust for baseline offset change in 1.71 (needed to keep accented characters in box)
	
	glTexCoord2f(texture_x, texture_y + ONE_SIXTEENTH);
	glVertex3f(x, y, z);
	glTexCoord2f(texture_x + ONE_SIXTEENTH, texture_y + ONE_SIXTEENTH);
	glVertex3f(x + siz.width, y, z);
	glTexCoord2f(texture_x + ONE_SIXTEENTH, texture_y);
	glVertex3f(x + siz.width, y + siz.height, z);
	glTexCoord2f(texture_x, texture_y);
	glVertex3f(x, y + siz.height, z);
	
	return siz.width * sGlyphWidths[chr];
}


void drawString(NSString *text, double x, double y, double z, NSSize siz)
{
	unsigned		i;
	double			cx = x;
	unsigned		length;
	NSData			*data = nil;
	const uint8_t	*bytes = NULL;
	
	glEnable(GL_TEXTURE_2D);
	glTexEnvf(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_MODULATE);
	[sFontTexture apply];
	
	data = [sEncodingCoverter convertString:text];
	length = [data length];
	bytes = [data bytes];
	
	glBegin(GL_QUADS);
	for (i = 0; i < length; i++)
	{
		cx += drawCharacterQuad(bytes[i], cx, y, z, siz);
	}
	glEnd();
	
	[OOTexture applyNone];
	glDisable(GL_TEXTURE_2D);
}


void drawPlanetInfo(int gov, int eco, int tec, double x, double y, double z, NSSize siz)
{
	GLfloat govcol[] = {	0.5, 0.0, 0.7,
							0.7, 0.5, 0.3,
							0.0, 1.0, 0.3,
							1.0, 0.8, 0.1,
							1.0, 0.0, 0.0,
							0.1, 0.5, 1.0,
							0.7, 0.7, 0.7,
							0.7, 1.0, 1.0};

	double cx = x;
	int tl = tec + 1;
	GLfloat ce1 = 1.0 - 0.125 * eco;
	
	glEnable(GL_TEXTURE_2D);
	glTexEnvf(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_MODULATE);
	[sFontTexture apply];

	glBegin(GL_QUADS);
	
	glColor4f(ce1, 1.0, 0.0, 1.0);
	cx += drawCharacterQuad(23 - eco, cx, y, z, siz);	// characters 16..23 are economy symbols
	glColor3fv(&govcol[gov * 3]);
	cx += drawCharacterQuad(gov, cx, y, z, siz) - 1.0;		// charcters 0..7 are government symbols
	glColor4f(0.5, 1.0, 1.0, 1.0);
	if (tl > 9)
		cx += drawCharacterQuad(49, cx, y - 2, z, siz) - 2.0;
	cx += drawCharacterQuad(48 + (tl % 10), cx, y - 2, z, siz);
	glEnd();
	
	[OOTexture applyNone];
	glDisable(GL_TEXTURE_2D);
		
}


NSRect rectForString(NSString *text, double x, double y, NSSize siz)
{
	unsigned			i;
	double				w = 0;
	NSData				*data = nil;
	const uint8_t		*bytes = NULL;
	unsigned			length;
	
	data = [sEncodingCoverter convertString:text];
	bytes = [data bytes];
	length = [data length];
	
	for (i = 0; i < length; i++)
	{
		w += siz.width * sGlyphWidths[bytes[i]];
	}
	
	return NSMakeRect(x, y, w, siz.height);
}


void drawScannerGrid(double x, double y, double z, NSSize siz, int v_dir, GLfloat thickness, double zoom)
{
	GLfloat w1, h1;
	GLfloat ww = 0.5 * siz.width;
	GLfloat hh = 0.5 * siz.height;

	GLfloat w2 = 0.250 * siz.width;
	GLfloat h2 = 0.250 * siz.height;

	GLfloat km_scan = 0.001 * SCANNER_MAX_RANGE / zoom;	// calculate kilometer divisions
	GLfloat hdiv = 0.5 * siz.height / km_scan;
	GLfloat wdiv = 0.25 * siz.width / km_scan;
	
	int i, ii;
	
	if (wdiv < 4.0)
	{
		wdiv *= 2.0;
		ii = 5;
	}
	else
	{
		ii = 1;
	}
	
	glLineWidth(2.0 * thickness);
	
	GLDrawOval(x, y, z, siz, 4);	
	
	glLineWidth(thickness);
	
	glBegin(GL_LINES);
		glVertex3f(x, y - hh, z);	glVertex3f(x, y + hh, z);
		glVertex3f(x - ww, y, z);	glVertex3f(x + ww, y, z);

		for (i = ii; 2.0 * hdiv * i < siz.height; i += ii)
		{
			h1 = i * hdiv;
			w1 = wdiv;
			if (i % 5 == 0)
				w1 = w1 * 2.5;
			if (i % 10 == 0)
				w1 = w1 * 2.0;
			if (w1 > 3.5)	// don't draw tiny marks
			{
				glVertex3f(x - w1, y + h1, z);	glVertex3f(x + w1, y + h1, z);
				glVertex3f(x - w1, y - h1, z);	glVertex3f(x + w1, y - h1, z);
			}
		}

		switch (v_dir)
		{
			case VIEW_BREAK_PATTERN :
			case VIEW_GUI_DISPLAY :
			case VIEW_FORWARD :
			case VIEW_NONE :
				glVertex3f(x, y, z); glVertex3f(x - w2, y + hh, z);
				glVertex3f(x, y, z); glVertex3f(x + w2, y + hh, z);
				break;
			case VIEW_AFT :
				glVertex3f(x, y, z); glVertex3f(x - w2, y - hh, z);
				glVertex3f(x, y, z); glVertex3f(x + w2, y - hh, z);
				break;
			case VIEW_PORT :
				glVertex3f(x, y, z); glVertex3f(x - ww, y + h2, z);
				glVertex3f(x, y, z); glVertex3f(x - ww, y - h2, z);
				break;
			case VIEW_STARBOARD :
				glVertex3f(x, y, z); glVertex3f(x + ww, y + h2, z);
				glVertex3f(x, y, z); glVertex3f(x + ww, y - h2, z);
				break;
		}
	glEnd();
}


static void DrawSpecialOval(GLfloat x, GLfloat y, GLfloat z, NSSize siz, GLfloat step, GLfloat* color4v)
{
	GLfloat			ww = 0.5 * siz.width;
	GLfloat			hh = 0.5 * siz.height;
	GLfloat			theta;
	GLfloat			delta;
	GLfloat			s;
	
	delta = step * M_PI / 180.0f;
	
	glEnable(GL_LINE_SMOOTH);
	glBegin(GL_LINE_LOOP);
	for (theta = 0.0f; theta < (2.0f * M_PI); theta += delta)
	{
		s = sinf(theta);
		glColor4f(color4v[0], color4v[1], color4v[2], fabsf(s * color4v[3]));
		glVertex3f(x + ww * s, y + hh * cosf(theta), z);
	}
	glEnd();
}


- (void) setLine_width:(GLfloat) value
{
	line_width = value;
}


- (GLfloat) line_width
{
	return line_width;
}

@end


@implementation NSString (OODisplayEncoding)

- (const char *) cStringUsingOoliteEncoding
{
	if (sEncodingCoverter == nil)  InitTextEngine();
	
	// Note: the data will be autoreleased, so the bytes behave as though they're autoreleased too.
	return [[self dataUsingEncoding:[sEncodingCoverter encoding] allowLossyConversion:YES] bytes];
}


- (const char *) cStringUsingOoliteEncodingAndRemapping
{
	if (sEncodingCoverter == nil)  InitTextEngine();
	
	// Note: the data will be autoreleased, so the bytes behave as though they're autoreleased too.
	return [[sEncodingCoverter convertString:self] bytes];
}

@end


static void GetRGBAArrayFromInfo(NSDictionary *info, GLfloat ioColor[4])
{
	id						colorDesc = nil;
	OOColor					*color = nil;
	
	// First, look for general colour specifier.
	colorDesc = [info objectForKey:RGB_COLOR_KEY];
	if (colorDesc != nil)
	{
		color = [OOColor colorWithDescription:colorDesc];
		if (color != nil)
		{
			[color getRed:&ioColor[0] green:&ioColor[1] blue:&ioColor[2] alpha:&ioColor[3]];
			return;
		}
	}
	
	// Failing that, look for rgb_color and alpha.
	colorDesc = [info arrayForKey:RGB_COLOR_KEY];
	if (colorDesc != nil && [colorDesc count] == 3)
	{
		ioColor[0] = [colorDesc nonNegativeFloatAtIndex:0];
		ioColor[1] = [colorDesc nonNegativeFloatAtIndex:1];
		ioColor[2] = [colorDesc nonNegativeFloatAtIndex:2];
	}
	ioColor[3] = [info nonNegativeFloatForKey:ALPHA_KEY defaultValue:ioColor[3]];
}
