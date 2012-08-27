/*

HeadUpDisplay.m

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

#import "HeadUpDisplay.h"
#import "ResourceManager.h"
#import "PlayerEntity.h"
#import "OOSunEntity.h"
#import "OOPlanetEntity.h"
#import "StationEntity.h"
#import "OOVisualEffectEntity.h"
#import "OOQuiriumCascadeEntity.h"
#import "Universe.h"
#import "OOTrumble.h"
#import "OOColor.h"
#import "GuiDisplayGen.h"
#import "OOTexture.h"
#import "OOTextureSprite.h"
#import "OOPolygonSprite.h"
#import "OOCollectionExtractors.h"
#import "OOEncodingConverter.h"
#import "OOCrosshairs.h"
#import "OOConstToString.h"
#import "OOStringParsing.h"
#import "OOJoystickManager.h"
#import "OOJavaScriptEngine.h"


#define kOOLogUnconvertedNSLog @"unclassified.HeadUpDisplay"


#define ONE_SIXTEENTH			0.0625
#define ONE_SIXTYFOURTH			0.015625
#define DEFAULT_OVERALL_ALPHA	0.75
#define GLYPH_SCALE_FACTOR		0.13		//  // 0.13 is an inherited magic number
#define IDENTIFY_SCANNER_LOLLIPOPS	(	0	&& !defined(NDEBUG))


static void DrawSpecialOval(GLfloat x, GLfloat y, GLfloat z, NSSize siz, GLfloat step, GLfloat* color4v);

static void GetRGBAArrayFromInfo(NSDictionary *info, GLfloat ioColor[4]);

static void hudDrawIndicatorAt(GLfloat x, GLfloat y, GLfloat z, NSSize siz, double amount);
static void hudDrawMarkerAt(GLfloat x, GLfloat y, GLfloat z, NSSize siz, double amount);
static void hudDrawBarAt(GLfloat x, GLfloat y, GLfloat z, NSSize siz, double amount);
static void hudDrawSurroundAt(GLfloat x, GLfloat y, GLfloat z, NSSize siz);
static void hudDrawStatusIconAt(int x, int y, int z, NSSize siz);
static void hudDrawReticleOnTarget(Entity* target, PlayerEntity* player1, GLfloat z1, GLfloat alpha, BOOL reticleTargetSensitive, NSMutableDictionary* propertiesReticleTargetSensitive);
static void drawScannerGrid(double x, double y, double z, NSSize siz, int v_dir, GLfloat thickness, double zoom);


static OOTexture			*sFontTexture = nil;
static OOEncodingConverter	*sEncodingCoverter = nil;


enum
{
	kFontTextureOptions = kOOTextureMinFilterMipMap | kOOTextureMagFilterLinear | kOOTextureNoShrink | kOOTextureAlphaMask
};


@interface HeadUpDisplay (Private)

- (void) drawCrosshairs;
- (void) drawLegends;
- (void) drawDials;

- (void) drawLegend:(NSDictionary *)info;
- (void) drawHUDItem:(NSDictionary *)info;

- (void) drawScanner:(NSDictionary *)info;
- (void) drawScannerZoomIndicator:(NSDictionary *)info;

- (void) drawCompass:(NSDictionary *)info;
- (void) drawCompassPlanetBlipAt:(Vector) relativePosition Size:(NSSize) siz Alpha:(GLfloat) alpha;
- (void) drawCompassStationBlipAt:(Vector) relativePosition Size:(NSSize) siz Alpha:(GLfloat) alpha;
- (void) drawCompassSunBlipAt:(Vector) relativePosition Size:(NSSize) siz Alpha:(GLfloat) alpha;
- (void) drawCompassTargetBlipAt:(Vector) relativePosition Size:(NSSize) siz Alpha:(GLfloat) alpha;
- (void) drawCompassBeaconBlipAt:(Vector) relativePosition Size:(NSSize) siz Alpha:(GLfloat) alpha;

- (void) drawAegis:(NSDictionary *)info;
- (void) drawSpeedBar:(NSDictionary *)info;
- (void) drawRollBar:(NSDictionary *)info;
- (void) drawPitchBar:(NSDictionary *)info;
- (void) drawYawBar:(NSDictionary *)info;
- (void) drawEnergyGauge:(NSDictionary *)info;
- (void) drawForwardShieldBar:(NSDictionary *)info;
- (void) drawAftShieldBar:(NSDictionary *)info;
- (void) drawFuelBar:(NSDictionary *)info;
- (void) drawCabinTempBar:(NSDictionary *)info;
- (void) drawWeaponTempBar:(NSDictionary *)info;
- (void) drawAltitudeBar:(NSDictionary *)info;
- (void) drawMissileDisplay:(NSDictionary *)info;
- (void) drawTargetReticle:(NSDictionary *)info;
- (void) drawStatusLight:(NSDictionary *)info;
- (void) drawDirectionCue:(NSDictionary *)info;
- (void) drawClock:(NSDictionary *)info;
- (void) drawWeaponsOfflineText:(NSDictionary *)info;
- (void) drawFPSInfoCounter:(NSDictionary *)info;
- (void) drawScoopStatus:(NSDictionary *)info;
- (void) drawStickSenitivityIndicator:(NSDictionary *)info;

- (void) drawGreenSurround:(NSDictionary *)info;
- (void) drawYellowSurround:(NSDictionary *)info;

- (void) drawTrumbles:(NSDictionary *)info;

- (NSArray *) crosshairDefinitionForWeaponType:(OOWeaponType)weapon;

@end


@implementation HeadUpDisplay

static const GLfloat red_color[4] =			{1.0, 0.0, 0.0, 1.0};
static const GLfloat redplus_color[4] =		{1.0, 0.0, 0.5, 1.0};
static const GLfloat yellow_color[4] =  	{1.0, 1.0, 0.0, 1.0};
static const GLfloat green_color[4] =		{0.0, 1.0, 0.0, 1.0};
static const GLfloat darkgreen_color[4] =	{0.0, 0.75, 0.0, 1.0};
static const GLfloat cyan_color[4] =		{0.0, 1.0, 1.0, 1.0};
static const GLfloat blue_color[4] =		{0.0, 0.0, 1.0, 1.0};
static const GLfloat black_color[4] =		{0.0, 0.0, 0.0, 1.0};
static const GLfloat lightgray_color[4] =	{0.25, 0.25, 0.25, 1.0};

static float sGlyphWidths[256];


static double drawCharacterQuad(uint8_t chr, double x, double y, double z, NSSize siz);

static void InitTextEngine(void);


OOINLINE void GLColorWithOverallAlpha(const GLfloat *color, GLfloat alpha)
{
	// NO OOGL(), this is called within immediate mode blocks.
	glColor4f(color[0], color[1], color[2], color[3] * alpha);
}


- (id) initWithDictionary:(NSDictionary *)hudinfo
{
	return [self initWithDictionary:hudinfo inFile:nil];
}


- (id) initWithDictionary:(NSDictionary *)hudinfo inFile:(NSString *)hudFileName
{
	unsigned		i;
	BOOL			areTrumblesToBeDrawn = NO;
	BOOL			isScannerToBeDrawn = NO;
	
	self = [super init];
	
	lineWidth = 1.0;
	
	if (sFontTexture == nil)  InitTextEngine();
	
	deferredHudName = nil;	// if not nil, it means that we have a deferred HUD which is to be drawn at first available opportunity
	hudName = [hudFileName copy];
	
	// init arrays
	dialArray = [[NSMutableArray alloc] initWithCapacity:16];   // alloc retains
	legendArray = [[NSMutableArray alloc] initWithCapacity:16]; // alloc retains
	
	// populate arrays
	NSArray *dials = [hudinfo oo_arrayForKey:DIALS_KEY];
	for (i = 0; i < [dials count]; i++)
	{
		NSDictionary	*dial_info = [dials oo_dictionaryAtIndex:i];
		if (!areTrumblesToBeDrawn && [[dial_info oo_stringForKey:SELECTOR_KEY] isEqualToString:@"drawTrumbles:"])  areTrumblesToBeDrawn = YES;
		if (!isScannerToBeDrawn && [[dial_info oo_stringForKey:SELECTOR_KEY] isEqualToString:@"drawScanner:"])  isScannerToBeDrawn = YES;
		[self addDial:dial_info];
	}
	
	if (!areTrumblesToBeDrawn)	// naughty - a hud with no built-in drawTrumbles: - one must be added!
	{
		NSDictionary	*trumble_dial_info = [NSDictionary dictionaryWithObjectsAndKeys: @"drawTrumbles:", SELECTOR_KEY, nil];
		[self addDial:trumble_dial_info];
	}
	
	/* 
	   Nikos 20110611: The scanner is very important and has to be drawn because mass locking depends on it. If we are using
	   an OXP HUD which doesn't include the scanner definition, make sure we draw the scanner with full transparency.
	   This will simulate scanner absence from the HUD, without messing up mass lock behaviour. The dictionary passed to
	   drawScanner: is the same as the one in the default hud.plist. TODO post-1.76: Separate mass lock from scanner drawing.
	*/
	if (EXPECT_NOT(!isScannerToBeDrawn))
	{
		NSDictionary	*scanner_dial_info = [NSDictionary dictionaryWithObjectsAndKeys:@"drawScanner:", SELECTOR_KEY,
																						@"0.0", ALPHA_KEY,
																						@"0.0", X_KEY,
																						@"60.0", Y_KEY,
																						@"-1.0", Y_ORIGIN_KEY,
																						@"72.0", HEIGHT_KEY,
																						@"288.0", WIDTH_KEY,
																						nil];
		[self addDial:scanner_dial_info];
	}
	
	NSArray *legends = [hudinfo oo_arrayForKey:LEGENDS_KEY];
	for (i = 0; i < [legends count]; i++)
	{
		[self addLegend:[legends oo_dictionaryAtIndex:i]];
	}
	
	hudHidden = NO;
	
	hudUpdating = NO;
	
	overallAlpha = [hudinfo oo_floatForKey:@"overall_alpha" defaultValue:DEFAULT_OVERALL_ALPHA];
	
	reticleTargetSensitive = [hudinfo oo_boolForKey:@"reticle_target_sensitive" defaultValue:NO];
	propertiesReticleTargetSensitive = [[NSMutableDictionary alloc] initWithObjectsAndKeys:
										[NSNumber numberWithBool:YES], @"isAccurate", 
										[NSNumber numberWithDouble:[UNIVERSE getTime]], @"timeLastAccuracyProbabilityCalculation", 
										nil];

	cloakIndicatorOnStatusLight = [hudinfo oo_boolForKey:@"cloak_indicator_on_status_light" defaultValue:YES];
	
	last_transmitter = NO_TARGET;

	[crosshairDefinition release];

	NSString *crossfile = [[hudinfo oo_stringForKey:@"crosshair_file"] retain];
	if (crossfile == nil)
	{
		_crosshairOverrides = [[hudinfo oo_dictionaryForKey:@"crosshairs"] retain];
		crosshairDefinition = nil;
	}
	else
	{
		[self setCrosshairDefinition:crossfile];
	}
	[crossfile release];

	id crosshairColor = [hudinfo oo_objectForKey:@"crosshair_color" defaultValue:@"greenColor"];
	_crosshairColor = [[OOColor colorWithDescription:crosshairColor] retain];
	_crosshairScale = [hudinfo oo_floatForKey:@"crosshair_scale" defaultValue:32.0f];
	_crosshairWidth = [hudinfo oo_floatForKey:@"crosshair_width" defaultValue:1.5f];

	

	return self;
}


- (void) dealloc
{
	DESTROY(legendArray);
	DESTROY(dialArray);
	DESTROY(hudName);
	DESTROY(deferredHudName);
	DESTROY(propertiesReticleTargetSensitive);
	DESTROY(_crosshairOverrides);
	DESTROY(crosshairDefinition);
	
	[super dealloc];
}

//------------------------------------------------------------------------------------//


- (void) resetGui:(GuiDisplayGen*)gui withInfo:(NSDictionary *)gui_info
{
	Vector pos = [gui drawPosition];
	if ([gui_info objectForKey:X_KEY])
		pos.x = [gui_info oo_floatForKey:X_KEY] +
			[[UNIVERSE gameView] x_offset] *
			[gui_info oo_floatForKey:X_ORIGIN_KEY defaultValue:0.0];
	if ([gui_info objectForKey:Y_KEY])
		pos.y = [gui_info oo_floatForKey:Y_KEY] + 
			[[UNIVERSE gameView] y_offset] *
			[gui_info oo_floatForKey:Y_ORIGIN_KEY defaultValue:0.0];
	[gui setDrawPosition:pos];
	NSSize		siz =	[gui	size];
	int			rht =	[gui	rowHeight];
	NSString*	title =	[gui	title];
	if ([gui_info objectForKey:WIDTH_KEY])
		siz.width = [gui_info oo_floatForKey:WIDTH_KEY];
	if ([gui_info objectForKey:HEIGHT_KEY])
		siz.height = [gui_info oo_floatForKey:HEIGHT_KEY];
	if ([gui_info objectForKey:ROW_HEIGHT_KEY])
		rht = [gui_info oo_floatForKey:ROW_HEIGHT_KEY];
	if ([gui_info objectForKey:TITLE_KEY])
		title = [gui_info oo_stringForKey:TITLE_KEY];
	[gui resizeTo:siz characterHeight:rht title:title];
	if ([gui_info objectForKey:BACKGROUND_RGBA_KEY])
		[gui setBackgroundColor:[OOColor colorFromString:[gui_info oo_stringForKey:BACKGROUND_RGBA_KEY]]];
	if ([gui_info objectForKey:ALPHA_KEY])
		[gui setMaxAlpha: OOClamp_0_max_f([gui_info oo_floatForKey:ALPHA_KEY],1.0f)];
	else
		[gui setMaxAlpha: 1.0f];
}


- (void) resetGuis:(NSDictionary *)info
{
	// check for entries in hud.plist for message_gui and comm_log_gui
	// then resize and reposition them accordingly.
	
	GuiDisplayGen*	gui = [UNIVERSE messageGUI];
	NSDictionary*	gui_info = [info oo_dictionaryForKey:@"message_gui"];
	if (gui && [gui_info count] > 0)
	{
		/*
			If switching message guis, remember the last 2 message lines.
			Present GUI limitations make it impractical to transfer anything
			more...
			
			TODO: a more usable GUI code! - Kaks 2011.11.05
		*/
		
		NSArray*	lastLines = [gui getLastLines];	// text, colour, fade time - text, colour, fade time
		BOOL		line1 = ![[lastLines oo_stringAtIndex:0] isEqualToString:@""];
		[self resetGui:gui withInfo:gui_info];
		
		if (line1)
		{
			[gui printLongText:[lastLines oo_stringAtIndex:0] align:GUI_ALIGN_CENTER
						 color:[OOColor colorFromString:[lastLines oo_stringAtIndex:1]] 
					  fadeTime:[lastLines oo_floatAtIndex:2] key:nil addToArray:nil];
		}
		if ([lastLines count] > 3 && (line1 || ![[lastLines oo_stringAtIndex:3] isEqualToString:@""]))
		{
			[gui printLongText:[lastLines oo_stringAtIndex:3] align:GUI_ALIGN_CENTER
						 color:[OOColor colorFromString:[lastLines oo_stringAtIndex:4]] 
					  fadeTime:[lastLines oo_floatAtIndex:5] key:nil addToArray:nil];
		}
	}
	
	if (gui_info != nil && [gui_info count] == 0)
	{
		// exists and it's empty. complete reset.
		[gui setCurrentRow:8];
		[gui setDrawPosition: make_vector(0.0, -40.0, 640.0)];
		[gui resizeTo:NSMakeSize(480, 160) characterHeight:19 title:nil];
		[gui setCharacterSize:NSMakeSize(16,20)];	// narrow characters
	}
	
	[gui setAlpha: 1.0];	// message_gui is always visible.
	
	// And now set up the comms log
	
	gui = [UNIVERSE commLogGUI];
	gui_info = [info oo_dictionaryForKey:@"comm_log_gui"];
	
	if (gui && [gui_info count] > 0)
	{
		[UNIVERSE setAutoCommLog:[gui_info oo_boolForKey:@"automatic" defaultValue:YES]];
		[UNIVERSE setPermanentCommLog:[gui_info oo_boolForKey:@"permanent" defaultValue:NO]];
		
		/*
			We need to repopulate the comms log after resetting it.
			
			At the moment the colour information is set on a per-line basis, rather than a per-text basis.
			A comms message can span multiple lines, and two consecutive messages can share the same colour,
			so trying to match the colour information from the GUI with each message won't work.
			
			Bottom line: colour information is lost on comms log gui reset.
			And yes, this is yet another reason for the following
			
			TODO: a more usable GUI code! - Kaks 2011.11.05
		*/
		
		NSArray *cLog = [PLAYER commLog];
		OOUInteger i, commCount = [cLog count];
		
		[self resetGui:gui withInfo:gui_info];
		
		for (i = 0; i < commCount; i++)
		{
			[gui printLongText:[cLog oo_stringAtIndex:i] align:GUI_ALIGN_LEFT color:nil
					  fadeTime:0.0 key:nil addToArray:nil];
		}
	}
	
	if (gui_info != nil && [gui_info count] == 0)
	{
		// exists and it's empty. complete reset.
		[UNIVERSE setAutoCommLog:YES];
		[UNIVERSE setPermanentCommLog:NO];
		[gui setCurrentRow:9];
		[gui setDrawPosition: make_vector(0.0, 180.0, 640.0)];
		[gui resizeTo:NSMakeSize(360, 120) characterHeight:12 title:nil];
		[gui setBackgroundColor:[OOColor colorWithCalibratedRed:0.0 green:0.05 blue:0.45 alpha:0.5]];
		[gui setTextColor:[OOColor whiteColor]];
		[gui printLongText:DESC(@"communications-log-string") align:GUI_ALIGN_CENTER color:[OOColor yellowColor] fadeTime:0 key:nil addToArray:nil];
	}
	
	if ([UNIVERSE permanentCommLog])
	{
		[gui stopFadeOuts];
		[gui setAlpha:1.0];
	}
	else
	{
		[gui setAlpha:0.0];
	}
}


- (NSString *) hudName
{
	return hudName;
}


- (void) setHudName:(NSString *)newHudName
{
	if (newHudName != nil)
	{
		[hudName release];
		hudName = [newHudName copy];
	}
}


- (double) scannerZoom
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


- (void) setOverallAlpha:(GLfloat) newAlphaValue
{
	overallAlpha = OOClamp_0_1_f(newAlphaValue);
}


- (BOOL) reticleTargetSensitive
{
	return reticleTargetSensitive;
}


- (void) setReticleTargetSensitive:(BOOL) newReticleTargetSensitiveValue
{
	reticleTargetSensitive = !!newReticleTargetSensitiveValue; // ensure YES or NO.
}


- (NSMutableDictionary *) propertiesReticleTargetSensitive
{
	return propertiesReticleTargetSensitive;
}


- (BOOL) isHidden
{
	return hudHidden;
}


- (void) setHidden:(BOOL)newValue
{
	hudHidden = !!newValue;	// ensure YES or NO
}


- (BOOL) isUpdating
{
	return hudUpdating;
}


- (void) setDeferredHudName:(NSString *)newDeferredHudName
{
	[deferredHudName release];
	deferredHudName = [newDeferredHudName copy];
}


- (NSString *) deferredHudName
{
	return deferredHudName;
}


- (void) addLegend:(NSDictionary *)info
{
	NSString			*imageName = nil;
	OOTexture			*texture = nil;
	NSSize				imageSize;
	OOTextureSprite		*legendSprite = nil;
	NSMutableDictionary	*legendDict = nil;
	
	imageName = [info oo_stringForKey:IMAGE_KEY];
	if (imageName != nil)
	{
		texture = [OOTexture textureWithName:imageName
									inFolder:@"Images"
									 options:kOOTextureDefaultOptions | kOOTextureNoShrink
								  anisotropy:kOOTextureDefaultAnisotropy
									 lodBias:kOOTextureDefaultLODBias];
		if (texture == nil)
		{
			OOLog(kOOLogFileNotFound, @"***** ERROR: HeadUpDisplay couldn't get an image texture name for %@", imageName);
			return;
		}
		
		imageSize = [texture dimensions];
		imageSize.width = [info oo_floatForKey:WIDTH_KEY defaultValue:imageSize.width];
		imageSize.height = [info oo_floatForKey:HEIGHT_KEY defaultValue:imageSize.height];
		
 		legendSprite = [[OOTextureSprite alloc] initWithTexture:texture size:imageSize];
		
		legendDict = [info mutableCopy];
		[legendDict setObject:legendSprite forKey:SPRITE_KEY];
		[legendArray addObject:legendDict];																	
		[legendDict release];
		[legendSprite release];
	}
	else if ([info oo_stringForKey:TEXT_KEY] != nil)
	{
		[legendArray addObject:info];
	}
}


- (void) addDial:(NSDictionary *)info
{
	static NSSet *allowedSelectors = nil;
	if (allowedSelectors == nil)
	{
		NSDictionary *whitelist = [ResourceManager whitelistDictionary];
		allowedSelectors = [[NSSet alloc] initWithArray:[whitelist oo_arrayForKey:@"hud_dial_methods"]];
	}
	
	NSString *dialSelector = [info oo_stringForKey:SELECTOR_KEY];
	if (dialSelector == nil)
	{
		OOLogERR(@"hud.dial.noSelector", @"HUD dial in %@ is missing selector.", hudName);
		return;
	}
	
	if (![allowedSelectors containsObject:dialSelector])
	{
		OOLogERR(@"hud.dial.invalidSelector", @"HUD dial in %@ uses selector \"%@\" which is not in whitelist, and will be ignored.", hudName, dialSelector);
		return;
	}
	
	NSAssert2([self respondsToSelector:NSSelectorFromString(dialSelector)], @"HUD dial in %@ uses selector \"%@\" which is in whitelist, but not implemented.", hudName, dialSelector);
	
	[dialArray addObject:info];
}


- (void) renderHUD
{
	hudUpdating = YES;
	
	if (_crosshairWidth * lineWidth > 0)
	{
		OOGL(glLineWidth(_crosshairWidth * lineWidth));
		[self drawCrosshairs];
	}
	
	if (lineWidth > 0)
	{
		OOGL(glLineWidth(lineWidth));
		[self drawLegends];
	}
	
	[self drawDials];
	CheckOpenGLErrors(@"After drawing HUD");
	
	hudUpdating = NO;
}


- (void) drawLegends
{
	unsigned		i;
	
	z1 = [[UNIVERSE gameView] display_z];
	for (i = 0; i < [legendArray count]; i++)
	{
		[self drawLegend:[legendArray oo_dictionaryAtIndex:i]];
	}
}


// SLOW_CODE - HUD drawing is taking up a ridiculous 30%-40% of frame time. Much of this seems to be spent in string processing. String caching is needed. -- ahruman
- (void) drawDials
{
	unsigned		i;
	
	z1 = [[UNIVERSE gameView] display_z];
	for (i = 0; i < [dialArray count]; i++)
	{
		[self drawHUDItem:[dialArray oo_dictionaryAtIndex:i]];
	}
}


- (void) drawCrosshairs
{
	PlayerEntity				*player = PLAYER;
	OOViewID					viewID = [UNIVERSE viewDirection];
	OOWeaponType				weapon = [player currentWeapon];
	BOOL						weaponsOnline = [player weaponsOnline];
	NSArray						*points = nil;
	
	if (viewID == VIEW_CUSTOM ||
		overallAlpha == 0.0f ||
		!([player status] == STATUS_IN_FLIGHT || [player status] == STATUS_WITCHSPACE_COUNTDOWN) ||
		[UNIVERSE displayGUI]
		)
	{
		// Don't draw crosshairs
		return;
	}
	
	if (weapon != _lastWeaponType || overallAlpha != _lastOverallAlpha || weaponsOnline != _lastWeaponsOnline)
	{
		DESTROY(_crosshairs);
	}
	
	if (_crosshairs == nil)
	{
		GLfloat useAlpha = weaponsOnline ? overallAlpha : overallAlpha * 0.5f;
		
		// Make new crosshairs object
		points = [self crosshairDefinitionForWeaponType:weapon];
		
		_crosshairs = [[OOCrosshairs alloc] initWithPoints:points
													 scale:_crosshairScale
													 color:_crosshairColor
											  overallAlpha:useAlpha];
		_lastWeaponType = weapon;
		_lastOverallAlpha = useAlpha;
		_lastWeaponsOnline = weaponsOnline;
	}
	
	[_crosshairs render];
}


- (NSString *) crosshairDefinition
{
	return crosshairDefinition;
}


- (BOOL) setCrosshairDefinition:(NSString *)newDefinition
{
	// force crosshair redraw
	[_crosshairs release];
	_crosshairs = nil;

	[_crosshairOverrides release];
	_crosshairOverrides = [[ResourceManager dictionaryFromFilesNamed:newDefinition
																												 inFolder:@"Config"
																												 andMerge:YES] retain];
	if (_crosshairOverrides == nil || [_crosshairOverrides count] == 0)
	{ // invalid file
		[_crosshairOverrides release];
		_crosshairOverrides = [[ResourceManager dictionaryFromFilesNamed:@"crosshairs.plist"
																													 inFolder:@"Config"
																													 andMerge:YES] retain];
		crosshairDefinition = @"crosshairs.plist";
		return NO;
	}
	crosshairDefinition = [newDefinition copy];
	return YES;
}


- (NSArray *) crosshairDefinitionForWeaponType:(OOWeaponType)weapon
{
	NSString					*weaponName = nil;
	static						NSDictionary *crosshairDefs = nil;
	NSArray						*result = nil;
	
	/*	Search order:
	 (hud.plist).crosshairs.WEAPON_NAME
	 (hud.plist).crosshairs.OTHER
	 (crosshairs.plist).WEAPON_NAME
	 (crosshairs.plist).OTHER
	 */
	
	weaponName = OOStringFromWeaponType(weapon);
	result = [_crosshairOverrides oo_arrayForKey:weaponName];
	if (result == nil)  result = [_crosshairOverrides oo_arrayForKey:@"OTHER"];
	if (result == nil)
	{
		if (crosshairDefs == nil)
		{
			crosshairDefs = [ResourceManager dictionaryFromFilesNamed:@"crosshairs.plist"
															 inFolder:@"Config"
															 andMerge:YES];
			[crosshairDefs retain];
		}
		
		result = [crosshairDefs oo_arrayForKey:weaponName];
		if (result == nil)  result = [crosshairDefs oo_arrayForKey:@"OTHER"];
	}
	
	return result;
}


- (void) drawLegend:(NSDictionary *)info
{
	OOTextureSprite				*legendSprite = nil;
	NSString					*legendText = nil;
	float						x, y;
	NSSize						size;
	GLfloat					alpha = overallAlpha;
	
// Feature request 5359 - equipment_required for HUD legends	
	NSString *equipmentRequired = [info oo_stringForKey:EQUIPMENT_REQUIRED_KEY];
	if (equipmentRequired != nil && ![PLAYER hasEquipmentItem:equipmentRequired])
		return;
	
	x = [info oo_floatForKey:X_KEY] + [[UNIVERSE gameView] x_offset] *
		[info oo_floatForKey:X_ORIGIN_KEY defaultValue:0.0];
	y = [info oo_floatForKey:Y_KEY] + [[UNIVERSE gameView] y_offset] *
		[info oo_floatForKey:Y_ORIGIN_KEY defaultValue:0.0];
	alpha *= [info oo_nonNegativeFloatForKey:ALPHA_KEY defaultValue:1.0f];
	
	legendSprite = [info objectForKey:SPRITE_KEY];
	if (legendSprite != nil)
	{
		[legendSprite blitCentredToX:x Y:y Z:z1 alpha:alpha];
	}
	else
	{
		legendText = [info oo_stringForKey:TEXT_KEY];
		if (legendText != nil)
		{
			size.width = [info oo_floatForKey:WIDTH_KEY];
			size.height = [info oo_floatForKey:HEIGHT_KEY];
			GLColorWithOverallAlpha(green_color, alpha);
			OODrawString(legendText, x, y, z1, size);
		}
	}
}


- (void) drawHUDItem:(NSDictionary *)info
{
	NSString *equipment = [info oo_stringForKey:EQUIPMENT_REQUIRED_KEY];
	if (equipment != nil && ![PLAYER hasEquipmentItem:equipment])
		return;
	
	if ([info oo_stringForKey:SELECTOR_KEY] != nil)
	{
		SEL _selector = NSSelectorFromString([info oo_stringForKey:SELECTOR_KEY]);
		if ([self respondsToSelector:_selector])
			[self performSelector:_selector withObject:info];
		else
			OOLog(@"hud.unknownSelector", @"DEBUG HeadUpDisplay does not respond to '%@'",[info objectForKey:SELECTOR_KEY]);
	}
	
	CheckOpenGLErrors(@"HeadUpDisplay after drawHUDItem %@", info);
}

//---------------------------------------------------------------------//

static BOOL hostiles;
- (void) drawScanner:(NSDictionary *)info
{
	int				x;
	int				y;
	NSSize			siz;
	GLfloat			scanner_color[4] = { 1.0, 0.0, 0.0, 1.0 };
	
	x = [info oo_intForKey:X_KEY defaultValue:SCANNER_CENTRE_X] + 
		[[UNIVERSE gameView] x_offset] *
		[info oo_floatForKey:X_ORIGIN_KEY defaultValue:0.0];
	y = [info oo_intForKey:Y_KEY defaultValue:SCANNER_CENTRE_Y] +
		[[UNIVERSE gameView] y_offset] *
		[info oo_floatForKey:Y_ORIGIN_KEY defaultValue:0.0];
	siz.width = [info oo_nonNegativeFloatForKey:WIDTH_KEY defaultValue:SCANNER_WIDTH];
	siz.height = [info oo_nonNegativeFloatForKey:HEIGHT_KEY defaultValue:SCANNER_HEIGHT];
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
	
	GLfloat			max_zoomed_range = sqrt(max_zoomed_range2);
	
	BOOL			isHostile = NO;
	BOOL			foundHostiles = NO;
	BOOL			mass_locked = NO;
	
	Vector			relativePosition;
	OOMatrix		rotMatrix;
	int				flash = ((int)([UNIVERSE getTime] * 4))&1;
	
	Universe		*uni			= UNIVERSE;
	PlayerEntity	*player = PLAYER;
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
	
	GLfloat col[4] =	{ 1.0, 1.0, 1.0, alpha };	// can be manipulated
	
	rotMatrix = [player rotationMatrix];
	
	OOGL(glColor4fv(scanner_color));
	drawScannerGrid(x, y, z1, siz, [UNIVERSE viewDirection], lineWidth, scanner_zoom);
	
	OOEntityStatus p_status = [player status];
	
	if ((p_status == STATUS_IN_FLIGHT)||(p_status == STATUS_AUTOPILOT_ENGAGED)||(p_status == STATUS_LAUNCHING)||(p_status == STATUS_WITCHSPACE_COUNTDOWN))
	{
		double upscale = scanner_zoom*1.25/scanner_scale;
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
			if ([drawthing isStellarObject])
			{
				Entity<OOStellarBody> *stellar = (Entity<OOStellarBody> *)drawthing;
				if ([stellar planetType] != STELLAR_TYPE_MINIATURE)
				{
					double dist =   stellar->zero_distance;
					double rad =	stellar->collision_radius;
					double factor = ([stellar isSun]) ? 2.0 : 4.0;
					// mass lock when 25 km or less from the surface - dist is a square distance so needs to be compared to (rad+25000) * (rad+25000)!
					if (dist< rad*rad +50000*rad+625000000 || dist < rad*rad*factor) 
					{
						mass_locked = YES;
					}
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
						case CLASS_BUOY:
						case CLASS_ROCK:
						case CLASS_CARGO:
						case CLASS_MINE:
						case CLASS_VISUAL_EFFECT:
							break;
							
						case CLASS_THARGOID:
						case CLASS_MISSILE:
						case CLASS_STATION:
						case CLASS_POLICE:
						case CLASS_MILITARY:
						case CLASS_WORMHOLE:
						default:
							mass_locked = YES;
							break;
					}
				}
				
				[player setAlertFlag:ALERT_FLAG_MASS_LOCK to:mass_locked];
				
				if (isnan(drawthing->zero_distance))
					continue;
				
				// exit if it's too far away
				GLfloat	act_dist = sqrt(drawthing->zero_distance);
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
				
				relativePosition = vector_subtract([drawthing position], [PLAYER position]);
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
					GLfloat* base_col = [ship scannerDisplayColorForShip:player :isHostile :flash :[ship scannerDisplayColor1] :[ship scannerDisplayColor2]];
					col[0] = base_col[0];	col[1] = base_col[1];	col[2] = base_col[2];	col[3] = alpha * base_col[3];
				}
				else if ([drawthing isVisualEffect])
				{
					OOVisualEffectEntity *vis = (OOVisualEffectEntity *)drawthing;
					GLfloat* base_col = [vis scannerDisplayColorForShip:flash :[vis scannerDisplayColor1] :[vis scannerDisplayColor2]];
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
					case CLASS_VISUAL_EFFECT:
						break;

					case CLASS_THARGOID:
						foundHostiles = YES;
						break;

					case CLASS_ROCK:
					case CLASS_CARGO:
					case CLASS_MISSILE:
					case CLASS_STATION:
					case CLASS_BUOY:
					case CLASS_POLICE:
					case CLASS_MILITARY:
					case CLASS_MINE:
					case CLASS_WORMHOLE:
					default:
						foundHostiles |= isHostile;
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
						OOGLBEGIN(GL_QUADS);
							glColor4f(col[0], col[1], col[2], 0.33333 * col[3]);
							glVertex3f(bounds[0].x, bounds[0].y, bounds[0].z);	glVertex3f(bounds[4].x, bounds[4].y, bounds[4].z);
							glVertex3f(bounds[1].x, bounds[1].y, bounds[1].z);	glVertex3f(bounds[5].x, bounds[5].y, bounds[5].z);
							glVertex3f(bounds[2].x, bounds[2].y, bounds[2].z);	glVertex3f(bounds[4].x, bounds[4].y, bounds[4].z);
							glVertex3f(bounds[3].x, bounds[3].y, bounds[3].z);	glVertex3f(bounds[5].x, bounds[5].y, bounds[5].z);
							glVertex3f(bounds[2].x, bounds[2].y, bounds[2].z);	glVertex3f(bounds[0].x, bounds[0].y, bounds[0].z);
							glVertex3f(bounds[3].x, bounds[3].y, bounds[3].z);	glVertex3f(bounds[1].x, bounds[1].y, bounds[1].z);
						OOGLEND();
					}
				}
				
				if (ms_blip > 0.0)
				{
					DrawSpecialOval(x1 - 0.5, y2 + 1.5, z1, NSMakeSize(16.0 * (1.0 - ms_blip), 8.0 * (1.0 - ms_blip)), 30, col);
				}
				if ([drawthing isCascadeWeapon])
				{
					double r1 = 2.5 + drawthing->collision_radius * upscale;
					double l2 = r1*r1 - relativePosition.y*relativePosition.y;
					double r0 = (l2 > 0)? sqrt(l2): 0;
					if (r0 > 0)
					{
						OOGL(glColor4f(1.0, 0.5, 1.0, alpha));
						GLDrawOval(x1  - 0.5, y1 + 1.5, z1, NSMakeSize(r0, r0 * siz.height / siz.width), 20);
					}
					OOGL(glColor4f(0.5, 0.0, 1.0, 0.33333 * alpha));
					GLDrawFilledOval(x1  - 0.5, y2 + 1.5, z1, NSMakeSize(r1, r1), 15);
				}
				else
				{

#if IDENTIFY_SCANNER_LOLLIPOPS
					if ([drawthing isShip])
					{
						glColor4f(1.0, 1.0, 0.5, alpha);
						OODrawString([(ShipEntity *)drawthing displayName], x1 + 2, y2 + 2, z1, NSMakeSize(8, 8));
					}
#endif
					OOGLBEGIN(GL_QUADS);
						glColor4fv(col);
						glVertex3f(x1-3, y2, z1);	glVertex3f(x1+2, y2, z1);	glVertex3f(x1+2, y2+3, z1);	glVertex3f(x1-3, y2+3, z1);	
						col[3] *= 0.3333; // one third the alpha
						glColor4fv(col);
						glVertex3f(x1, y1, z1);	glVertex3f(x1+2, y1, z1);	glVertex3f(x1+2, y2, z1);	glVertex3f(x1, y2, z1);
					OOGLEND();
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


- (void) drawScannerZoomIndicator:(NSDictionary *)info
{
	int				x;
	int				y;
	NSSize			siz;
	GLfloat			alpha;
	GLfloat			zoom_color[4] = { 1.0f, 0.1f, 0.0f, 1.0f };
	
	x = [info oo_intForKey:X_KEY defaultValue:ZOOM_INDICATOR_CENTRE_X] +
		[[UNIVERSE gameView] x_offset] *
		[info oo_floatForKey:X_ORIGIN_KEY defaultValue:0.0];
	y = [info oo_intForKey:Y_KEY defaultValue:ZOOM_INDICATOR_CENTRE_Y] +
		[[UNIVERSE gameView] y_offset] *
		[info oo_floatForKey:Y_ORIGIN_KEY defaultValue:0.0];
	siz.width = [info oo_nonNegativeFloatForKey:WIDTH_KEY defaultValue:ZOOM_INDICATOR_WIDTH];
	siz.height = [info oo_nonNegativeFloatForKey:HEIGHT_KEY defaultValue:ZOOM_INDICATOR_HEIGHT];
	
	GetRGBAArrayFromInfo(info, zoom_color);
	zoom_color[3] *= overallAlpha;
	alpha = zoom_color[3];
	
	GLfloat cx = x - 0.3 * siz.width;
	GLfloat cy = y - 0.75 * siz.height;
	
	int zl = scanner_zoom;
	if (zl < 1) zl = 1;
	if (zl > SCANNER_ZOOM_LEVELS) zl = SCANNER_ZOOM_LEVELS;
	if (zl == 1) zoom_color[3] *= 0.75;
	GLColorWithOverallAlpha(zoom_color, alpha);
	OOGL(glEnable(GL_TEXTURE_2D));
	[sFontTexture apply];
	
	OOGLBEGIN(GL_QUADS);
		drawCharacterQuad(48 + zl, cx - 0.4 * siz.width, cy, z1, siz);
		drawCharacterQuad(58, cx, cy, z1, siz);
		drawCharacterQuad(49, cx + 0.3 * siz.width, cy, z1, siz);
	OOGLEND();
	
	[OOTexture applyNone];
	OOGL(glDisable(GL_TEXTURE_2D));
}


- (void) drawCompass:(NSDictionary *)info
{
	int				x;
	int				y;
	NSSize			siz;
	GLfloat			alpha;
	GLfloat			compass_color[4] = { 0.0f, 0.0f, 1.0f, 1.0f };
	
	x = [info oo_intForKey:X_KEY defaultValue:COMPASS_CENTRE_X] +
		[[UNIVERSE gameView] x_offset] *
		[info oo_floatForKey:X_ORIGIN_KEY defaultValue:0.0];
	y = [info oo_intForKey:Y_KEY defaultValue:COMPASS_CENTRE_Y] +
		[[UNIVERSE gameView] y_offset] *
		[info oo_floatForKey:Y_ORIGIN_KEY defaultValue:0.0];
	siz.width = [info oo_nonNegativeFloatForKey:WIDTH_KEY defaultValue:COMPASS_HALF_SIZE];
	siz.height = [info oo_nonNegativeFloatForKey:HEIGHT_KEY defaultValue:COMPASS_HALF_SIZE];
	
	GetRGBAArrayFromInfo(info, compass_color);
	compass_color[3] *= overallAlpha;
	alpha = compass_color[3];
	
	// draw the compass
	OOMatrix		rotMatrix;
	PlayerEntity	*player = PLAYER;
	Vector			position = [player position];
	
	rotMatrix = [player rotationMatrix];
	
	GLfloat h1 = siz.height * 0.125;
	GLfloat h3 = siz.height * 0.375;
	GLfloat w1 = siz.width * 0.125;
	GLfloat w3 = siz.width * 0.375;
	OOGL(glLineWidth(2.0 * lineWidth));	// thicker
	OOGL(glColor4f(compass_color[0], compass_color[1], compass_color[2], alpha));
	GLDrawOval(x, y, z1, siz, 12);	
	OOGL(glColor4f(compass_color[0], compass_color[1], compass_color[2], 0.5f * alpha));
	OOGLBEGIN(GL_LINES);
		glVertex3f(x - w1, y, z1);	glVertex3f(x - w3, y, z1);
		glVertex3f(x + w1, y, z1);	glVertex3f(x + w3, y, z1);
		glVertex3f(x, y - h1, z1);	glVertex3f(x, y - h3, z1);
		glVertex3f(x, y + h1, z1);	glVertex3f(x, y + h3, z1);
	OOGLEND();
	OOGL(glLineWidth(lineWidth));	// thinner
	
	OOSunEntity		*the_sun = [UNIVERSE sun];
	OOPlanetEntity	*the_planet = [UNIVERSE planet];
	StationEntity	*the_station = [UNIVERSE station];
	Entity			*the_target = [player primaryTarget];
	ShipEntity		*beacon = [player nextBeacon];
	OOEntityStatus	p_status = [player status];
	if	(((p_status == STATUS_IN_FLIGHT)
		||(p_status == STATUS_AUTOPILOT_ENGAGED)
		||(p_status == STATUS_LAUNCHING)
		||(p_status == STATUS_WITCHSPACE_COUNTDOWN))	// be in the right mode
		&&(the_sun)
		&&(the_planet)					// and be in a system
		&& ![the_sun goneNova])				// and the system has not been novabombed
	{
		Entity *reference = nil;
		OOAegisStatus	aegis = AEGIS_NONE;
		
		switch ([player compassMode])
		{
			case COMPASS_MODE_BASIC:
				
				aegis = [player checkForAegis];
				if ((aegis == AEGIS_CLOSE_TO_MAIN_PLANET || aegis == AEGIS_IN_DOCKING_RANGE) && the_station)
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
				reference = beacon;
				break;
		}
		
		if (reference == nil)
		{
			[player setCompassMode:COMPASS_MODE_PLANET];
			reference = the_planet;
		}
		
		if (reference != [player compassTarget])
		{
			[player setCompassTarget:reference];
			[player doScriptEvent:OOJSID("compassTargetChanged") withArguments:[NSArray arrayWithObjects:reference, OOStringFromCompassMode([player compassMode]), nil]];
		}
		
		// translate and rotate the view
		Vector relativePosition = vector_subtract([reference position], position);
		relativePosition = OOVectorMultiplyMatrix(relativePosition, rotMatrix);
		relativePosition = vector_normal_or_fallback(relativePosition, kBasisZVector);
		
		relativePosition.x *= siz.width * 0.4;
		relativePosition.y *= siz.height * 0.4;
		relativePosition.x += x;
		relativePosition.y += y;
		
		siz.width *= 0.2;
		siz.height *= 0.2;
		OOGL(glLineWidth(2.0));
		switch ([player compassMode])
		{
			case COMPASS_MODE_BASIC:
				[self drawCompassPlanetBlipAt:relativePosition Size:NSMakeSize(6, 6) Alpha:alpha];
				break;
				
			case COMPASS_MODE_PLANET:
				[self drawCompassPlanetBlipAt:relativePosition Size:siz Alpha:alpha];
				break;
				
			case COMPASS_MODE_STATION:
				[self drawCompassStationBlipAt:relativePosition Size:siz Alpha:alpha];
				break;
				
			case COMPASS_MODE_SUN:
				[self drawCompassSunBlipAt:relativePosition Size:siz Alpha:alpha];
				break;
				
			case COMPASS_MODE_TARGET:
				[self drawCompassTargetBlipAt:relativePosition Size:siz Alpha:alpha];
				break;
				
			case COMPASS_MODE_BEACONS:
				[self drawCompassBeaconBlipAt:relativePosition Size:siz Alpha:alpha];
				[[beacon beaconDrawable] oo_drawHUDBeaconIconAt:NSMakePoint(x, y) size:siz alpha:alpha z:z1];
				break;
		}
	}
}


OOINLINE void SetCompassBlipColor(GLfloat relativeZ, GLfloat alpha)
{
	if (relativeZ >= 0.0f)
	{
		OOGL(glColor4f(0.0f, 1.0f, 0.0f, alpha));
	}
	else
	{
		OOGL(glColor4f(1.0f, 0.0f, 0.0f, alpha));
	}
}


- (void) drawCompassPlanetBlipAt:(Vector)relativePosition Size:(NSSize)siz Alpha:(GLfloat)alpha
{
	if (relativePosition.z >= 0)
	{
		OOGL(glColor4f(0.0,1.0,0.0,0.75 * alpha));
		GLDrawFilledOval(relativePosition.x, relativePosition.y, z1, siz, 30);
		OOGL(glColor4f(0.0,1.0,0.0,alpha));
		GLDrawOval(relativePosition.x, relativePosition.y, z1, siz, 30);
	}
	else
	{
		OOGL(glColor4f(1.0,0.0,0.0,alpha));
		GLDrawOval(relativePosition.x, relativePosition.y, z1, siz, 30);
	}
}


- (void) drawCompassStationBlipAt:(Vector) relativePosition Size:(NSSize) siz Alpha:(GLfloat) alpha
{
	SetCompassBlipColor(relativePosition.z, alpha);
	
	OOGLBEGIN(GL_LINE_LOOP);
		glVertex3f(relativePosition.x - 0.5 * siz.width, relativePosition.y - 0.5 * siz.height, z1);
		glVertex3f(relativePosition.x + 0.5 * siz.width, relativePosition.y - 0.5 * siz.height, z1);
		glVertex3f(relativePosition.x + 0.5 * siz.width, relativePosition.y + 0.5 * siz.height, z1);
		glVertex3f(relativePosition.x - 0.5 * siz.width, relativePosition.y + 0.5 * siz.height, z1);
	OOGLEND();
}


- (void) drawCompassSunBlipAt:(Vector) relativePosition Size:(NSSize) siz Alpha:(GLfloat) alpha
{
	OOGL(glColor4f(1.0, 1.0, 0.0, 0.75 * alpha));
	GLDrawFilledOval(relativePosition.x, relativePosition.y, z1, siz, 30);
	
	SetCompassBlipColor(relativePosition.z, alpha);
	
	GLDrawOval(relativePosition.x, relativePosition.y, z1, siz, 30);
}


- (void) drawCompassTargetBlipAt:(Vector) relativePosition Size:(NSSize) siz Alpha:(GLfloat) alpha
{
	SetCompassBlipColor(relativePosition.z, alpha);
	
	OOGLBEGIN(GL_LINES);
		glVertex3f(relativePosition.x - siz.width, relativePosition.y, z1);
		glVertex3f(relativePosition.x + siz.width, relativePosition.y, z1);
		glVertex3f(relativePosition.x, relativePosition.y - siz.height, z1);
		glVertex3f(relativePosition.x, relativePosition.y + siz.height, z1);
	OOGLEND();
	
	GLDrawOval(relativePosition.x, relativePosition.y, z1, siz, 30);
}


- (void) drawCompassBeaconBlipAt:(Vector) relativePosition Size:(NSSize) siz Alpha:(GLfloat) alpha
{
	SetCompassBlipColor(relativePosition.z, alpha);
	
	OOGLBEGIN(GL_LINES);
	/*		glVertex3f(relativePosition.x - 0.5 * siz.width, relativePosition.y - 0.5 * siz.height, z1);
		glVertex3f(relativePosition.x, relativePosition.y + 0.5 * siz.height, z1);
		
		glVertex3f(relativePosition.x + 0.5 * siz.width, relativePosition.y - 0.5 * siz.height, z1);
		glVertex3f(relativePosition.x, relativePosition.y + 0.5 * siz.height, z1);
		
		glVertex3f(relativePosition.x - 0.5 * siz.width, relativePosition.y - 0.5 * siz.height, z1);
		glVertex3f(relativePosition.x + 0.5 * siz.width, relativePosition.y - 0.5 * siz.height, z1); */
	glVertex3f(relativePosition.x + 0.6 * siz.width, relativePosition.y, z1);
	glVertex3f(relativePosition.x, relativePosition.y + 0.6 * siz.height, z1);

	glVertex3f(relativePosition.x - 0.6 * siz.width, relativePosition.y, z1);
	glVertex3f(relativePosition.x, relativePosition.y + 0.6 * siz.height, z1);

	glVertex3f(relativePosition.x + 0.6 * siz.width, relativePosition.y, z1);
	glVertex3f(relativePosition.x, relativePosition.y - 0.6 * siz.height, z1);

	glVertex3f(relativePosition.x - 0.6 * siz.width, relativePosition.y, z1);
	glVertex3f(relativePosition.x, relativePosition.y - 0.6 * siz.height, z1);

	OOGLEND();
}


- (void) drawAegis:(NSDictionary *)info
{
	if (([UNIVERSE viewDirection] == VIEW_GUI_DISPLAY)||([UNIVERSE sun] == nil)||([PLAYER checkForAegis] != AEGIS_IN_DOCKING_RANGE))
		return;	// don't draw
	
	int				x;
	int				y;
	NSSize			siz;
	GLfloat			alpha = 0.5f;
	
	x = [info oo_intForKey:X_KEY defaultValue:AEGIS_CENTRE_X] +
		[[UNIVERSE gameView] x_offset] *
		[info oo_floatForKey:X_ORIGIN_KEY defaultValue:0.0];
	y = [info oo_intForKey:Y_KEY defaultValue:AEGIS_CENTRE_Y] +
		[[UNIVERSE gameView] y_offset] *
		[info oo_floatForKey:Y_ORIGIN_KEY defaultValue:0.0];
	siz.width = [info oo_nonNegativeFloatForKey:WIDTH_KEY defaultValue:AEGIS_WIDTH];
	siz.height = [info oo_nonNegativeFloatForKey:HEIGHT_KEY defaultValue:AEGIS_HEIGHT];
	siz.height = [info oo_nonNegativeFloatForKey:HEIGHT_KEY defaultValue:AEGIS_HEIGHT];
	alpha *= [info oo_nonNegativeFloatForKey:ALPHA_KEY defaultValue:1.0f] * overallAlpha;
	
	// draw the aegis indicator
	//
	GLfloat	w = siz.width / 16.0;
	GLfloat	h = siz.height / 16.0;
	
	GLfloat strip[] = { -7,8, -6,5, 5,8, 3,5, 7,2, 4,2, 6,-1, 4,2, -4,-1, -6,2, -4,-1, -7,-1, -3,-4, -5,-7, 6,-4, 7,-7 };
	
#if 1
	OOGL(glColor4f(0.0f, 1.0f, 0.0f, alpha));
	OOGLBEGIN(GL_QUAD_STRIP);
		int i;
		for (i = 0; i < 32; i += 2)
		{
			glVertex3f(x + w * strip[i], y - h * strip[i + 1], z1);
		}
	OOGLEND();
#else
	OOGL(glPushMatrix());
	OOGL(glTranslatef(x, y, z1));
	OOGL(glScalef(w, -h, 1.0f));
	
	OOGL(glColor4f(0.0f, 1.0f, 0.0f, alpha));
	OOGL(glVertexPointer(2, GL_FLOAT, 0, strip));
	OOGL(glEnableClientState(GL_VERTEX_ARRAY));
	OOGL(glDisableClientState(GL_COLOR_ARRAY));
	
	OOGL(glDrawArrays(GL_QUAD_STRIP, 0, sizeof strip / sizeof *strip / 2));
	OOGL(glDisableClientState(GL_VERTEX_ARRAY));
	
	OOGL(glPopMatrix());
#endif
}


- (void) drawSpeedBar:(NSDictionary *)info
{
	PlayerEntity	*player = PLAYER;
	int				x;
	int				y;
	NSSize			siz;
	BOOL			draw_surround;
	GLfloat			alpha = overallAlpha;
	
	x = [info oo_intForKey:X_KEY defaultValue:SPEED_BAR_CENTRE_X] +
		[[UNIVERSE gameView] x_offset] *
		[info oo_floatForKey:X_ORIGIN_KEY defaultValue:0.0];
	y = [info oo_intForKey:Y_KEY defaultValue:SPEED_BAR_CENTRE_Y] +
		[[UNIVERSE gameView] y_offset] *
		[info oo_floatForKey:Y_ORIGIN_KEY defaultValue:0.0];
	siz.width = [info oo_nonNegativeFloatForKey:WIDTH_KEY defaultValue:SPEED_BAR_WIDTH];
	siz.height = [info oo_nonNegativeFloatForKey:HEIGHT_KEY defaultValue:SPEED_BAR_HEIGHT];
	draw_surround = [info oo_boolForKey:DRAW_SURROUND_KEY defaultValue:SPEED_BAR_DRAW_SURROUND];
	alpha *= [info oo_nonNegativeFloatForKey:ALPHA_KEY defaultValue:1.0f];
	
	double ds = [player dialSpeed];
	
	GLColorWithOverallAlpha(green_color, alpha);
	if (draw_surround)
	{
		// draw speed surround
		hudDrawSurroundAt(x, y, z1, siz);
	}
	// draw speed bar
	if (ds > .80)
		GLColorWithOverallAlpha(red_color, alpha);
	else if (ds > .25)
		GLColorWithOverallAlpha(yellow_color, alpha);

	hudDrawBarAt(x, y, z1, siz, ds);
	
}


- (void) drawRollBar:(NSDictionary *)info
{
	PlayerEntity	*player = PLAYER;
	int				x;
	int				y;
	NSSize			siz;
	BOOL			draw_surround;
	GLfloat			alpha = overallAlpha;
	
	x = [info oo_intForKey:X_KEY defaultValue:ROLL_BAR_CENTRE_X] +
		[[UNIVERSE gameView] x_offset] *
		[info oo_floatForKey:X_ORIGIN_KEY defaultValue:0.0];
	y = [info oo_intForKey:Y_KEY defaultValue:ROLL_BAR_CENTRE_Y] +
		[[UNIVERSE gameView] y_offset] *
		[info oo_floatForKey:Y_ORIGIN_KEY defaultValue:0.0];
	siz.width = [info oo_nonNegativeFloatForKey:WIDTH_KEY defaultValue:ROLL_BAR_WIDTH];
	siz.height = [info oo_nonNegativeFloatForKey:HEIGHT_KEY defaultValue:ROLL_BAR_HEIGHT];
	draw_surround = [info oo_boolForKey:DRAW_SURROUND_KEY defaultValue:ROLL_BAR_DRAW_SURROUND];
	alpha *= [info oo_nonNegativeFloatForKey:ALPHA_KEY defaultValue:1.0f];
	
	if (draw_surround)
	{
		// draw ROLL surround
		GLColorWithOverallAlpha(green_color, alpha);
		hudDrawSurroundAt(x, y, z1, siz);
	}
	// draw ROLL bar
	GLColorWithOverallAlpha(yellow_color, alpha);
	hudDrawIndicatorAt(x, y, z1, siz, [player dialRoll]);
}


- (void) drawPitchBar:(NSDictionary *)info
{
	PlayerEntity	*player = PLAYER;
	int				x;
	int				y;
	NSSize			siz;
	BOOL			draw_surround;
	GLfloat			alpha = overallAlpha;
	
	x = [info oo_intForKey:X_KEY defaultValue:PITCH_BAR_CENTRE_X] +
		[[UNIVERSE gameView] x_offset] *
		[info oo_floatForKey:X_ORIGIN_KEY defaultValue:0.0];
	y = [info oo_intForKey:Y_KEY defaultValue:PITCH_BAR_CENTRE_Y] +
		+ [[UNIVERSE gameView] y_offset] *
		[info oo_floatForKey:Y_ORIGIN_KEY defaultValue:0.0];
	siz.width = [info oo_nonNegativeFloatForKey:WIDTH_KEY defaultValue:PITCH_BAR_WIDTH];
	siz.height = [info oo_nonNegativeFloatForKey:HEIGHT_KEY defaultValue:PITCH_BAR_HEIGHT];
	draw_surround = [info oo_boolForKey:DRAW_SURROUND_KEY defaultValue:PITCH_BAR_DRAW_SURROUND];
	alpha *= [info oo_nonNegativeFloatForKey:ALPHA_KEY defaultValue:1.0f];
	
	if (draw_surround)
	{
		// draw PITCH surround
		GLColorWithOverallAlpha(green_color, alpha);
		hudDrawSurroundAt(x, y, z1, siz);
	}
	// draw PITCH bar
	GLColorWithOverallAlpha(yellow_color, alpha);
	hudDrawIndicatorAt(x, y, z1, siz, [player dialPitch]);
}


- (void) drawYawBar:(NSDictionary *)info
{
	PlayerEntity	*player = PLAYER;
	int				x;
	int				y;
	NSSize			siz;
	BOOL			draw_surround;
	GLfloat			alpha = overallAlpha;
	
	// YAW does not exist in strict mode
	if ([UNIVERSE strict])  return;
	
	x = [info oo_intForKey:X_KEY defaultValue:PITCH_BAR_CENTRE_X] +
		[[UNIVERSE gameView] x_offset] *
		[info oo_floatForKey:X_ORIGIN_KEY defaultValue:0.0];
	y = [info oo_intForKey:Y_KEY defaultValue:PITCH_BAR_CENTRE_Y] +
		[[UNIVERSE gameView] y_offset] *
		[info oo_floatForKey:Y_ORIGIN_KEY defaultValue:0.0];
	siz.width = [info oo_nonNegativeFloatForKey:WIDTH_KEY defaultValue:PITCH_BAR_WIDTH];
	siz.height = [info oo_nonNegativeFloatForKey:HEIGHT_KEY defaultValue:PITCH_BAR_HEIGHT];
	draw_surround = [info oo_boolForKey:DRAW_SURROUND_KEY defaultValue:PITCH_BAR_DRAW_SURROUND];
	alpha *= [info oo_nonNegativeFloatForKey:ALPHA_KEY defaultValue:1.0f];
	
	if (draw_surround)
	{
		// draw YAW surround
		GLColorWithOverallAlpha(green_color, alpha);
		hudDrawSurroundAt(x, y, z1, siz);
	}
	// draw YAW bar
	GLColorWithOverallAlpha(yellow_color, alpha);
	hudDrawIndicatorAt(x, y, z1, siz, [player dialYaw]);
}


- (void) drawEnergyGauge:(NSDictionary *)info
{
	PlayerEntity	*player = PLAYER;
	int				x;
	int				y;
	NSSize			siz;
	BOOL			draw_surround, labelled;
	GLfloat			alpha = overallAlpha;
	
	x = [info oo_intForKey:X_KEY defaultValue:ENERGY_GAUGE_CENTRE_X] +
		[[UNIVERSE gameView] x_offset] *
		[info oo_floatForKey:X_ORIGIN_KEY defaultValue:0.0];
	y = [info oo_intForKey:Y_KEY defaultValue:ENERGY_GAUGE_CENTRE_Y] +
		[[UNIVERSE gameView] y_offset] *
		[info oo_floatForKey:Y_ORIGIN_KEY defaultValue:0.0];
	siz.width = [info oo_nonNegativeFloatForKey:WIDTH_KEY defaultValue:ENERGY_GAUGE_WIDTH];
	siz.height = [info oo_nonNegativeFloatForKey:HEIGHT_KEY defaultValue:ENERGY_GAUGE_HEIGHT];
	draw_surround = [info oo_boolForKey:DRAW_SURROUND_KEY defaultValue:ENERGY_GAUGE_DRAW_SURROUND];
	alpha *= [info oo_nonNegativeFloatForKey:ALPHA_KEY defaultValue:1.0f];
	labelled = [info oo_boolForKey:LABELLED_KEY defaultValue:YES];
	
	int n_bars = [player dialMaxEnergy]/64.0;
	n_bars = [info oo_unsignedIntForKey:N_BARS_KEY defaultValue:n_bars];
	if (n_bars < 1)  n_bars = 1;
	if (n_bars > 8)  labelled = NO;
	
	if (draw_surround)
	{
		// draw energy surround
		GLColorWithOverallAlpha(yellow_color, alpha);
		hudDrawSurroundAt(x, y, z1, siz);
	}
	
	// draw energy banks
	{
		int qy = siz.height / n_bars;
		NSSize dial_size = NSMakeSize(siz.width,qy - 2);
		int cy = y - (n_bars - 1) * qy / 2;
		double energy = [player dialEnergy]*n_bars;
		// MKW - ensure we don't alert the player every time they use energy if they only have 1 energybank
		//[player setAlertFlag:ALERT_FLAG_ENERGY to:((energy < 1.0)&&([player status] == STATUS_IN_FLIGHT))];
		bool energyCritical = false;
		if( [player status] == STATUS_IN_FLIGHT )
		{
			if( n_bars > 1 )
				energyCritical = energy < 1.0 ;
			else
				energyCritical = energy < 0.8; 
		}
		[player setAlertFlag:ALERT_FLAG_ENERGY to:energyCritical];
		int i;
		for (i = 0; i < n_bars; i++)
		{
			if( energyCritical )
				GLColorWithOverallAlpha(red_color, alpha);
			else
				GLColorWithOverallAlpha(yellow_color, alpha);
			if (energy > 1.0)
				hudDrawBarAt(x, cy, z1, dial_size, 1.0);
			if ((energy > 0.0)&&(energy <= 1.0))
				hudDrawBarAt(x, cy, z1, dial_size, energy);
			if (labelled)
			{
				GLColorWithOverallAlpha(green_color, alpha);
				OODrawString([NSString stringWithFormat:@"E%x",n_bars - i], x + 0.5 * dial_size.width + 2, cy - 0.5 * qy, z1, NSMakeSize(9, (qy < 18)? qy : 18 ));
			}
			energy -= 1.0;
			cy += qy;
		}
	}
	
}


- (void) drawForwardShieldBar:(NSDictionary *)info
{
	PlayerEntity	*player = PLAYER;
	int				x;
	int				y;
	NSSize			siz;
	BOOL			draw_surround;
	GLfloat			alpha = overallAlpha;
	
	x = [info oo_intForKey:X_KEY defaultValue:FORWARD_SHIELD_BAR_CENTRE_X] +
		[[UNIVERSE gameView] x_offset] *
		[info oo_floatForKey:X_ORIGIN_KEY defaultValue:0.0];
	y = [info oo_intForKey:Y_KEY defaultValue:FORWARD_SHIELD_BAR_CENTRE_Y] +
		[[UNIVERSE gameView] y_offset] *
		[info oo_floatForKey:Y_ORIGIN_KEY defaultValue:0.0];
	siz.width = [info oo_nonNegativeFloatForKey:WIDTH_KEY defaultValue:FORWARD_SHIELD_BAR_WIDTH];
	siz.height = [info oo_nonNegativeFloatForKey:HEIGHT_KEY defaultValue:FORWARD_SHIELD_BAR_HEIGHT];
	draw_surround = [info oo_boolForKey:DRAW_SURROUND_KEY defaultValue:FORWARD_SHIELD_BAR_DRAW_SURROUND];
	alpha *= [info oo_nonNegativeFloatForKey:ALPHA_KEY defaultValue:1.0f];
	
	double shield = [player dialForwardShield];
	if (draw_surround)
	{
		// draw forward_shield surround
		GLColorWithOverallAlpha(green_color, alpha);
		hudDrawSurroundAt(x, y, z1, siz);
	}
	// draw forward_shield bar
	GLColorWithOverallAlpha(green_color, alpha);
	if (shield < .80)
		GLColorWithOverallAlpha(yellow_color, alpha);
	if (shield < .25)
		GLColorWithOverallAlpha(red_color, alpha);
	hudDrawBarAt(x, y, z1, siz, shield);
}


- (void) drawAftShieldBar:(NSDictionary *)info
{
	PlayerEntity	*player = PLAYER;
	int				x;
	int				y;
	NSSize			siz;
	BOOL			draw_surround;
	GLfloat			alpha = overallAlpha;
	
	x = [info oo_intForKey:X_KEY defaultValue:AFT_SHIELD_BAR_CENTRE_X] +
		[[UNIVERSE gameView] x_offset] *
		[info oo_floatForKey:X_ORIGIN_KEY defaultValue:0.0];
	y = [info oo_intForKey:Y_KEY defaultValue:AFT_SHIELD_BAR_CENTRE_Y] +
		[[UNIVERSE gameView] y_offset] *
		[info oo_floatForKey:Y_ORIGIN_KEY defaultValue:0.0];
	siz.width = [info oo_nonNegativeFloatForKey:WIDTH_KEY defaultValue:AFT_SHIELD_BAR_WIDTH];
	siz.height = [info oo_nonNegativeFloatForKey:HEIGHT_KEY defaultValue:AFT_SHIELD_BAR_HEIGHT];
	draw_surround = [info oo_boolForKey:DRAW_SURROUND_KEY defaultValue:AFT_SHIELD_BAR_DRAW_SURROUND];
	alpha *= [info oo_nonNegativeFloatForKey:ALPHA_KEY defaultValue:1.0f];
	
	double shield = [player dialAftShield];
	if (draw_surround)
	{
		// draw aft_shield surround
		GLColorWithOverallAlpha(green_color, alpha);
		hudDrawSurroundAt(x, y, z1, siz);
	}
	// draw aft_shield bar
	GLColorWithOverallAlpha(green_color, alpha);
	if (shield < .80)
		GLColorWithOverallAlpha(yellow_color, alpha);
	if (shield < .25)
		GLColorWithOverallAlpha(red_color, alpha);
	hudDrawBarAt(x, y, z1, siz, shield);
}


- (void) drawFuelBar:(NSDictionary *)info
{
	PlayerEntity	*player = PLAYER;
	int				x;
	int				y;
	NSSize			siz;
	float			fu, hr;
	GLfloat			alpha = overallAlpha;
	
	x = [info oo_intForKey:X_KEY defaultValue:FUEL_BAR_CENTRE_X] +
		[[UNIVERSE gameView] x_offset] *
		[info oo_floatForKey:X_ORIGIN_KEY defaultValue:0.0];
	y = [info oo_intForKey:Y_KEY defaultValue:FUEL_BAR_CENTRE_Y] +
		[[UNIVERSE gameView] y_offset] *
		[info oo_floatForKey:Y_ORIGIN_KEY defaultValue:0.0];
	siz.width = [info oo_nonNegativeFloatForKey:WIDTH_KEY defaultValue:FUEL_BAR_WIDTH];
	siz.height = [info oo_nonNegativeFloatForKey:HEIGHT_KEY defaultValue:FUEL_BAR_HEIGHT];
	alpha *= [info oo_nonNegativeFloatForKey:ALPHA_KEY defaultValue:1.0f];
	
	fu = [player dialFuel];
	hr = [player dialHyperRange];

	// draw fuel bar
	GLColorWithOverallAlpha(yellow_color, alpha);
	hudDrawBarAt(x, y, z1, siz, fu);
	
	// draw range indicator
	if (hr > 0 && hr <= 1.0)
	{
		GLColorWithOverallAlpha([PLAYER hasSufficientFuelForJump] ? green_color : red_color, alpha);
		hudDrawMarkerAt(x, y, z1, siz, hr);
	}
}


- (void) drawCabinTempBar:(NSDictionary *)info
{
	PlayerEntity	*player = PLAYER;
	int				x;
	int				y;
	NSSize			siz;
	GLfloat			alpha = overallAlpha;
	
	x = [info oo_intForKey:X_KEY defaultValue:CABIN_TEMP_BAR_CENTRE_X] +
		[[UNIVERSE gameView] x_offset] *
		[info oo_floatForKey:X_ORIGIN_KEY defaultValue:0.0];
	y = [info oo_intForKey:Y_KEY defaultValue:CABIN_TEMP_BAR_CENTRE_Y] +
		[[UNIVERSE gameView] y_offset] *
		[info oo_floatForKey:Y_ORIGIN_KEY defaultValue:0.0];
	siz.width = [info oo_nonNegativeFloatForKey:WIDTH_KEY defaultValue:CABIN_TEMP_BAR_WIDTH];
	siz.height = [info oo_nonNegativeFloatForKey:HEIGHT_KEY defaultValue:CABIN_TEMP_BAR_HEIGHT];
	alpha *= [info oo_nonNegativeFloatForKey:ALPHA_KEY defaultValue:1.0f];
	
	double temp = [player hullHeatLevel];
	int flash = (int)([UNIVERSE getTime] * 4);
	flash &= 1;
	// draw ship_temperature bar (only need to call GLColor() once!)
	if (temp > .80)
	{
		if (temp > .90 && flash)
			GLColorWithOverallAlpha(redplus_color, alpha);
		else
			GLColorWithOverallAlpha(red_color, alpha);
	}
	else
	{
		if (temp > .25)
			GLColorWithOverallAlpha(yellow_color, alpha);
		else
			GLColorWithOverallAlpha(green_color, alpha);
	}

	[player setAlertFlag:ALERT_FLAG_TEMP to:((temp > .90)&&([player status] == STATUS_IN_FLIGHT))];
	hudDrawBarAt(x, y, z1, siz, temp);
}


- (void) drawWeaponTempBar:(NSDictionary *)info
{
	PlayerEntity	*player = PLAYER;
	int				x;
	int				y;
	NSSize			siz;
	GLfloat			alpha = overallAlpha;
	
	x = [info oo_intForKey:X_KEY defaultValue:WEAPON_TEMP_BAR_CENTRE_X] +
		[[UNIVERSE gameView] x_offset] *
		[info oo_floatForKey:X_ORIGIN_KEY defaultValue:0.0];	
	y = [info oo_intForKey:Y_KEY defaultValue:WEAPON_TEMP_BAR_CENTRE_Y] +
		[[UNIVERSE gameView] y_offset] *
		[info oo_floatForKey:Y_ORIGIN_KEY defaultValue:0.0];
	siz.width = [info oo_nonNegativeFloatForKey:WIDTH_KEY defaultValue:WEAPON_TEMP_BAR_WIDTH];
	siz.height = [info oo_nonNegativeFloatForKey:HEIGHT_KEY defaultValue:WEAPON_TEMP_BAR_HEIGHT];
	alpha *= [info oo_nonNegativeFloatForKey:ALPHA_KEY defaultValue:1.0f];
	
	double temp = [player laserHeatLevel];
	// draw weapon_temp bar (only need to call GLColor() once!)
	if (temp > .80)
		GLColorWithOverallAlpha(red_color, alpha);
	else if (temp > .25)
		GLColorWithOverallAlpha(yellow_color, alpha);
	else
		GLColorWithOverallAlpha(green_color, alpha);
	hudDrawBarAt(x, y, z1, siz, temp);
}


- (void) drawAltitudeBar:(NSDictionary *)info
{
	PlayerEntity	*player = PLAYER;
	int				x;
	int				y;
	NSSize			siz;
	GLfloat			alpha = overallAlpha;
	
	x = [info oo_intForKey:X_KEY defaultValue:ALTITUDE_BAR_CENTRE_X] +
		[[UNIVERSE gameView] x_offset] *
		[info oo_floatForKey:X_ORIGIN_KEY defaultValue:0.0];
	y = [info oo_intForKey:Y_KEY defaultValue:ALTITUDE_BAR_CENTRE_Y] +
		[[UNIVERSE gameView] y_offset] *
		[info oo_floatForKey:Y_ORIGIN_KEY defaultValue:0.0];
	siz.width = [info oo_nonNegativeFloatForKey:WIDTH_KEY defaultValue:ALTITUDE_BAR_WIDTH];
	siz.height = [info oo_nonNegativeFloatForKey:HEIGHT_KEY defaultValue:ALTITUDE_BAR_HEIGHT];
	alpha *= [info oo_nonNegativeFloatForKey:ALPHA_KEY defaultValue:1.0f];
	
	GLfloat alt = [player dialAltitude];
	int flash = (int)([UNIVERSE getTime] * 4);
	flash &= 1;
	
	// draw altitude bar (evaluating the least amount of ifs per go)
	if (alt < .25)
	{
		if (alt < .10 && flash)
			GLColorWithOverallAlpha(redplus_color, alpha);
		else
			GLColorWithOverallAlpha(red_color, alpha);
	}
	else
	{
		if (alt < .75)
			GLColorWithOverallAlpha(yellow_color, alpha);
		else
			GLColorWithOverallAlpha(green_color, alpha);
	}
	
	hudDrawBarAt(x, y, z1, siz, alt);
	
	[player setAlertFlag:ALERT_FLAG_ALT to:((alt < .10)&&([player status] == STATUS_IN_FLIGHT))];
}


static NSString * const kDefaultMissileIconKey = @"oolite-default-missile-icon";
static NSString * const kDefaultMineIconKey = @"oolite-default-mine-icon";
static const GLfloat kOutlineWidth = 0.5f;


static OOPolygonSprite *IconForMissileRole(NSString *role)
{
	static NSMutableDictionary	*sIcons = nil;
	OOPolygonSprite				*result = nil;
	
	result = [sIcons objectForKey:role];
	if (result == nil)
	{
		NSString *key = role;
		NSArray *iconDef = [[UNIVERSE descriptions] oo_arrayForKey:key];
		if (iconDef != nil)  result = [[OOPolygonSprite alloc] initWithDataArray:iconDef outlineWidth:kOutlineWidth name:key];
		if (result == nil)	// No custom icon or bad data
		{
			/*	Backwards compatibility note:
				The old implementation used suffixes "MISSILE" and "MINE" (without
				the underscore), and didn't draw anything if neither was found. I
				believe any difference in practical behavour due to the change here
				will be positive.
				-- Ahruman 2009-10-09
			*/
			if ([role hasSuffix:@"_MISSILE"])  key = kDefaultMissileIconKey;
			else  key = kDefaultMineIconKey;
			
			iconDef = [[UNIVERSE descriptions] oo_arrayForKey:key];
			result = [[OOPolygonSprite alloc] initWithDataArray:iconDef outlineWidth:kOutlineWidth name:key];
		}
		
		if (result != nil)
		{
			if (sIcons == nil)  sIcons = [[NSMutableDictionary alloc] init];
			[sIcons setObject:result forKey:role];
			[result release];	// Balance alloc
		}
	}
	
	return result;
}


- (void) drawIconForMissile:(ShipEntity *)missile
				   selected:(BOOL)selected
					 status:(OOMissileStatus)status
						  x:(int)x y:(int)y
					  width:(GLfloat)width height:(GLfloat)height alpha:(GLfloat)alpha
{
	OOPolygonSprite *sprite = IconForMissileRole([missile primaryRole]);
	
	if (selected)
	{
		// Draw yellow outline.
		OOGL(glPushMatrix());
		OOGL(glTranslatef(x - width * 2.0f, y - height * 2.0f, z1));
		OOGL(glScalef(width, height, 1.0f));
		GLColorWithOverallAlpha(yellow_color, alpha);
		[sprite drawOutline];
		OOGL(glPopMatrix());
		
		// Draw black backing, so outline colour isn’t blended into missile colour.
		OOGL(glPushMatrix());
		OOGL(glTranslatef(x - width * 2.0f, y - height * 2.0f, z1));
		OOGL(glScalef(width, height, 1.0f));
		GLColorWithOverallAlpha(black_color, alpha);
		[sprite drawFilled];
		OOGL(glPopMatrix());
		
		switch (status)
		{
			case MISSILE_STATUS_SAFE:
				GLColorWithOverallAlpha(green_color, alpha);	break;
			case MISSILE_STATUS_ARMED:
				GLColorWithOverallAlpha(yellow_color, alpha);	break;
			case MISSILE_STATUS_TARGET_LOCKED:
				GLColorWithOverallAlpha(red_color, alpha);		break;
		}
	}
	else
	{
		if ([missile primaryTarget] == nil)  GLColorWithOverallAlpha(green_color, alpha);
		else  GLColorWithOverallAlpha(red_color, alpha);
	}
	
	OOGL(glPushMatrix());
	OOGL(glTranslatef(x - width * 2.0f, y - height * 2.0f, z1));
	OOGL(glScalef(width, height, 1.0f));
	[sprite drawFilled];
	OOGL(glPopMatrix());
}



- (void) drawIconForEmptyPylonAtX:(int)x y:(int)y
							width:(GLfloat)width height:(GLfloat)height alpha:(GLfloat)alpha
{
	OOPolygonSprite *sprite = IconForMissileRole(kDefaultMissileIconKey);
	
	// Draw gray outline.
	OOGL(glPushMatrix());
	OOGL(glTranslatef(x - width * 2.0f, y - height * 2.0f, z1));
	OOGL(glScalef(width, height, 1.0f));
	GLColorWithOverallAlpha(lightgray_color, alpha);
	[sprite drawOutline];
	OOGL(glPopMatrix());
}


- (void) drawMissileDisplay:(NSDictionary *)info
{
	PlayerEntity	*player = PLAYER;
	int				x;
	int				y;
	NSSize			siz;
	int				sp;
	GLfloat			alpha = overallAlpha;
	
	x = [info oo_intForKey:X_KEY defaultValue:MISSILES_DISPLAY_X] +
		[[UNIVERSE gameView] x_offset] *
		[info oo_floatForKey:X_ORIGIN_KEY defaultValue:0.0];
	y = [info oo_intForKey:Y_KEY defaultValue:MISSILES_DISPLAY_Y] +
		[[UNIVERSE gameView] y_offset] *
		[info oo_floatForKey:Y_ORIGIN_KEY defaultValue:0.0];
	sp = [info oo_unsignedIntForKey:SPACING_KEY defaultValue:MISSILES_DISPLAY_SPACING];
	siz.width = [info oo_nonNegativeFloatForKey:WIDTH_KEY defaultValue:MISSILE_ICON_WIDTH];
	siz.height = [info oo_nonNegativeFloatForKey:HEIGHT_KEY defaultValue:MISSILE_ICON_HEIGHT];
	alpha *= [info oo_nonNegativeFloatForKey:ALPHA_KEY defaultValue:1.0f];
	
	BOOL weaponsOnline = [player weaponsOnline];
	if (!weaponsOnline)  alpha *= 0.2f;	// darken missile display if weapons are offline
	
	if (![player dialIdentEngaged])
	{
		OOMissileStatus status = [player dialMissileStatus];
		OOUInteger i, n_mis = [player dialMaxMissiles];
		for (i = 0; i < n_mis; i++)
		{
			ShipEntity *missile = [player missileForPylon:i];
			if (missile)
			{
				[self drawIconForMissile:missile
								selected:weaponsOnline && i == [player activeMissile]
								  status:status
									   x:x + (int)i * sp + 2 y:y
								   width:siz.width * 0.25f height:siz.height * 0.25f
								   alpha:alpha];
			}
			else
			{
				[self drawIconForEmptyPylonAtX:x + (int)i * sp + 2 y:y
									width:siz.width * 0.25f height:siz.height * 0.25f alpha:alpha];
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
			case MISSILE_STATUS_SAFE:
				GLColorWithOverallAlpha(green_color, alpha);	break;
			case MISSILE_STATUS_ARMED:
				GLColorWithOverallAlpha(yellow_color, alpha);	break;
			case MISSILE_STATUS_TARGET_LOCKED:
				GLColorWithOverallAlpha(red_color, alpha);		break;
		}
		OOGLBEGIN(GL_QUADS);
			glVertex3i(x , y, z1);
			glVertex3i(x + siz.width, y, z1);
			glVertex3i(x + siz.width, y + siz.height, z1);
			glVertex3i(x , y + siz.height, z1);
		OOGLEND();
		GLColorWithOverallAlpha(green_color, alpha);
		OODrawString([player dialTargetName], x + sp, y, z1, NSMakeSize(siz.width, siz.height));
	}
	
}


- (void) drawTargetReticle:(NSDictionary *)info
{
	PlayerEntity *player = PLAYER;
	GLfloat alpha = [info oo_nonNegativeFloatForKey:ALPHA_KEY defaultValue:1.0f] * overallAlpha;
	
	if ([player primaryTarget] != nil)
	{
		hudDrawReticleOnTarget([player primaryTarget], player, z1, alpha, reticleTargetSensitive, propertiesReticleTargetSensitive);
		[self drawDirectionCue:info];
	}
}


- (void) drawStatusLight:(NSDictionary *)info
{
	PlayerEntity	*player = PLAYER;
	int				x;
	int				y;
	NSSize			siz;
	BOOL			blueAlert = cloakIndicatorOnStatusLight && [player isCloaked];
	GLfloat			alpha = overallAlpha;
	
	x = [info oo_intForKey:X_KEY defaultValue:STATUS_LIGHT_CENTRE_X] +
		[[UNIVERSE gameView] x_offset] *
		[info oo_floatForKey:X_ORIGIN_KEY defaultValue:0.0];
	y = [info oo_intForKey:Y_KEY defaultValue:STATUS_LIGHT_CENTRE_Y] +
		[[UNIVERSE gameView] y_offset] *
		[info oo_floatForKey:Y_ORIGIN_KEY defaultValue:0.0];
	siz.width = [info oo_nonNegativeFloatForKey:WIDTH_KEY defaultValue:STATUS_LIGHT_HEIGHT];
	siz.height = [info oo_nonNegativeFloatForKey:HEIGHT_KEY defaultValue:STATUS_LIGHT_HEIGHT];
	alpha *= [info oo_nonNegativeFloatForKey:ALPHA_KEY defaultValue:1.0f];
	
	GLfloat status_color[4] = { 0.25, 0.25, 0.25, 1.0};
	int alertCondition = [player alertCondition];
	double flash_alpha = 0.333 * (2.0 + sin([UNIVERSE getTime] * 2.5 * alertCondition));
	
	switch(alertCondition)
	{
		case ALERT_CONDITION_RED:
			status_color[0] = red_color[0];
			status_color[1] = red_color[1];
			status_color[2] = blueAlert ? blue_color[2] : red_color[2];
			break;
			
		case ALERT_CONDITION_GREEN:
			status_color[0] = green_color[0];
			status_color[1] = green_color[1];
			status_color[2] = blueAlert ? blue_color[2] : green_color[2];
			break;
			
		case ALERT_CONDITION_YELLOW:
			status_color[0] = yellow_color[0];
			status_color[1] = yellow_color[1];
			status_color[2] = blueAlert ? blue_color[2] : yellow_color[2];
			break;
			
		default:
		case ALERT_CONDITION_DOCKED:
			break;
	}
	status_color[3] = flash_alpha;
	GLColorWithOverallAlpha(status_color, alpha);
	OOGLBEGIN(GL_POLYGON);
	hudDrawStatusIconAt(x, y, z1, siz);
	OOGLEND();
	OOGL(glColor4f(0.25, 0.25, 0.25, alpha));
	OOGLBEGIN(GL_LINE_LOOP);
		hudDrawStatusIconAt(x, y, z1, siz);
	OOGLEND();
}


- (void) drawDirectionCue:(NSDictionary *)info
{
	PlayerEntity	*player = PLAYER;
	NSString		*equipment = nil;
	GLfloat			alpha = overallAlpha;
	
 	// the direction cue is an advanced option
	// so we need to check for its extra equipment flag first
	equipment = [info oo_stringForKey:EQUIPMENT_REQUIRED_KEY];
	if (equipment != nil && ![player hasEquipmentItem:equipment])  return;
	
	alpha *= [info oo_nonNegativeFloatForKey:ALPHA_KEY defaultValue:1.0f];
	
	if ([UNIVERSE displayGUI])  return;
	
	GLfloat		clear_color[4] = {0.0f, 1.0f, 0.0f, 0.0f};
	Entity		*target = [player primaryTarget];
	if (target == nil)  return;
	
	// draw the direction cue
	OOMatrix	rotMatrix;
	Vector		position = [player position];
	
	rotMatrix = [player rotationMatrix];
	
	if ([UNIVERSE viewDirection] != VIEW_GUI_DISPLAY)
	{
		const GLfloat innerSize = CROSSHAIR_SIZE;
		const GLfloat width = CROSSHAIR_SIZE * ONE_EIGHTH;
		const GLfloat outerSize = CROSSHAIR_SIZE * (1.0f + ONE_EIGHTH + ONE_EIGHTH);
		const float visMin = 0.994521895368273f;	// cos(6 degrees)
		const float visMax = 0.984807753012208f;	// cos(10 degrees)
		
		// Transform the view
		Vector rpn = vector_subtract([target position], position);
		rpn = OOVectorMultiplyMatrix(rpn, rotMatrix);
		Vector drawPos = rpn;
		Vector forward = kZeroVector;
		
		switch ([UNIVERSE viewDirection])
		{
			case VIEW_FORWARD:
				forward = kBasisZVector;
				break;
			case VIEW_AFT:
				drawPos.x = - drawPos.x;
				forward = vector_flip(kBasisZVector);
				break;
			case VIEW_PORT:
				drawPos.x = drawPos.z;
				forward = vector_flip(kBasisXVector);
				break;
			case VIEW_STARBOARD:
				drawPos.x = -drawPos.z;
				forward = kBasisXVector;
				break;
			case VIEW_CUSTOM:
				return;
			
			default:
				break;
		}
		
		float cosAngle = dot_product(vector_normal(rpn), forward);
		float visibility = 1.0f - ((visMax - cosAngle) * (1.0f / (visMax - visMin)));
		alpha *= OOClamp_0_1_f(visibility);
		
		if (alpha > 0.0f)
		{
			drawPos.z = 0.0f;	// flatten vector
			drawPos = vector_normal(drawPos);
			OOGLBEGIN(GL_LINE_STRIP);
				glColor4fv(clear_color);
				glVertex3f(drawPos.x * innerSize - drawPos.y * width, drawPos.y * innerSize + drawPos.x * width, z1);
				GLColorWithOverallAlpha(green_color, alpha);
				glVertex3f(drawPos.x * outerSize, drawPos.y * outerSize, z1);
				glColor4fv(clear_color);
				glVertex3f(drawPos.x * innerSize + drawPos.y * width, drawPos.y * innerSize - drawPos.x * width, z1);
			OOGLEND();
		}
	}
}


- (void) drawClock:(NSDictionary *)info
{
	PlayerEntity	*player = PLAYER;
	int				x;
	int				y;
	NSSize			siz;
	GLfloat			alpha = overallAlpha;
	
	x = [info oo_intForKey:X_KEY defaultValue:CLOCK_DISPLAY_X] +
		[[UNIVERSE gameView] x_offset] *
		[info oo_floatForKey:X_ORIGIN_KEY defaultValue:0.0];
	y = [info oo_intForKey:Y_KEY defaultValue:CLOCK_DISPLAY_Y] +
		[[UNIVERSE gameView] y_offset] *
		[info oo_floatForKey:Y_ORIGIN_KEY defaultValue:0.0];
	siz.width = [info oo_nonNegativeFloatForKey:WIDTH_KEY defaultValue:CLOCK_DISPLAY_WIDTH];
	siz.height = [info oo_nonNegativeFloatForKey:HEIGHT_KEY defaultValue:CLOCK_DISPLAY_HEIGHT];
	alpha *= [info oo_nonNegativeFloatForKey:ALPHA_KEY defaultValue:1.0f];
	
	GLColorWithOverallAlpha(green_color, alpha);
	OODrawString([player dial_clock], x, y, z1, siz);
}


- (void) drawWeaponsOfflineText:(NSDictionary *)info
{
	PlayerEntity	*player = PLAYER;
	
	if (![player weaponsOnline])
	{
		int				x;
		int				y;
		NSSize			siz;
		GLfloat			alpha = overallAlpha;
		
		x = [info oo_intForKey:X_KEY defaultValue:WEAPONSOFFLINETEXT_DISPLAY_X] +
			[[UNIVERSE gameView] x_offset] *
			[info oo_floatForKey:X_ORIGIN_KEY defaultValue:0.0];
		y = [info oo_intForKey:Y_KEY defaultValue:WEAPONSOFFLINETEXT_DISPLAY_Y] +
			[[UNIVERSE gameView] y_offset] *
			[info oo_floatForKey:Y_ORIGIN_KEY defaultValue:0.0];
		siz.width = [info oo_nonNegativeFloatForKey:WIDTH_KEY defaultValue:WEAPONSOFFLINETEXT_WIDTH];
		siz.height = [info oo_nonNegativeFloatForKey:HEIGHT_KEY defaultValue:WEAPONSOFFLINETEXT_HEIGHT];
		alpha *= [info oo_nonNegativeFloatForKey:ALPHA_KEY defaultValue:1.0f];
	
		GLColorWithOverallAlpha(green_color, alpha);
		OODrawString(DESC(@"weapons-systems-offline"), x, y, z1, siz);
	}
}


- (void) drawFPSInfoCounter:(NSDictionary *)info
{
	if (![UNIVERSE displayFPS])  return;
	
	PlayerEntity	*player = PLAYER;
	int				x;
	int				y;
	NSSize			siz;
	
	x = [info oo_intForKey:X_KEY defaultValue:FPSINFO_DISPLAY_X] +
		[[UNIVERSE gameView] x_offset] *
		[info oo_floatForKey:X_ORIGIN_KEY defaultValue:0.0];
	y = [info oo_intForKey:Y_KEY defaultValue:FPSINFO_DISPLAY_Y] +
		[[UNIVERSE gameView] y_offset] *
		[info oo_floatForKey:Y_ORIGIN_KEY defaultValue:0.0];
	siz.width = [info oo_nonNegativeFloatForKey:WIDTH_KEY defaultValue:FPSINFO_DISPLAY_WIDTH];
	siz.height = [info oo_nonNegativeFloatForKey:HEIGHT_KEY defaultValue:FPSINFO_DISPLAY_HEIGHT];
	
	Vector playerPos = [player position];
	NSString *positionInfo = [UNIVERSE expressPosition:playerPos inCoordinateSystem:@"pwm"];
	positionInfo = [NSString stringWithFormat:@"abs %.2f %.2f %.2f / %@", playerPos.x, playerPos.y, playerPos.z, positionInfo];
	
	// We would normally set a variable alpha value here, but in this case we don't.
	// We prefer the FPS counter to be always visible - Nikos 20100405
	OOGL(glColor4f(0.0, 1.0, 0.0, 1.0));
	OODrawString([player dial_fpsinfo], x, y, z1, siz);
	
#ifndef NDEBUG
	NSSize siz08 = NSMakeSize(0.8 * siz.width, 0.8 * siz.width);
	NSString *collDebugInfo = [NSString stringWithFormat:@"%@ - %@", [player dial_objinfo], [UNIVERSE collisionDescription]];
	OODrawString(collDebugInfo, x, y - siz.height, z1, siz);
	
	OODrawString(positionInfo, x, y - 1.8 * siz.height, z1, siz08);
	
	NSString *timeAccelerationFactorInfo = [NSString stringWithFormat:@"TAF: %@%.2f", DESC(@"multiplication-sign"), [UNIVERSE timeAccelerationFactor]];
	OODrawString(timeAccelerationFactorInfo, x, y - 3.2 * siz08.height, z1, siz08);
#endif
}


- (void) drawScoopStatus:(NSDictionary *)info
{
	PlayerEntity	*player = PLAYER;
	int				x;
	int				y;
	NSSize			siz;
	GLfloat			alpha;
	
	x = [info oo_intForKey:X_KEY defaultValue:SCOOPSTATUS_CENTRE_X] +
		[[UNIVERSE gameView] x_offset] *
		[info oo_floatForKey:X_ORIGIN_KEY defaultValue:0.0];
	y = [info oo_intForKey:Y_KEY defaultValue:SCOOPSTATUS_CENTRE_Y] +
		[[UNIVERSE gameView] y_offset] *
		[info oo_floatForKey:Y_ORIGIN_KEY defaultValue:0.0];
	siz.width = [info oo_nonNegativeFloatForKey:WIDTH_KEY defaultValue:SCOOPSTATUS_WIDTH];
	siz.height = [info oo_nonNegativeFloatForKey:HEIGHT_KEY defaultValue:SCOOPSTATUS_HEIGHT];
	alpha = [info oo_nonNegativeFloatForKey:ALPHA_KEY defaultValue:0.75f];
	
	const GLfloat* s0_color = red_color;
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
		case SCOOP_STATUS_NOT_INSTALLED:
			return;	// don't draw
			
		case SCOOP_STATUS_FULL_HOLD:
			s0_color = darkgreen_color;
			alpha *= 0.75;
			break;
			
		case SCOOP_STATUS_ACTIVE:
		case SCOOP_STATUS_OKAY:
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
	
	OOGL(glDisable(GL_TEXTURE_2D));
	OOGLBEGIN(GL_QUADS);
	// section 1
		GLColorWithOverallAlpha(s1c, overallAlpha);
		glVertex3f(x, y + h1, z1);	glVertex3f(x - w2, y + h2, z1);	glVertex3f(x, y + h3, z1);	glVertex3f(x + w2, y + h2, z1);
	// section 2
		GLColorWithOverallAlpha(s2c, overallAlpha);
		glVertex3f(x, y - h1, z1);	glVertex3f(x - w4, y + h1, z1);	glVertex3f(x - w4, y + h2, z1);	glVertex3f(x, y, z1);
		glVertex3f(x, y - h1, z1);	glVertex3f(x + w4, y + h1, z1);	glVertex3f(x + w4, y + h2, z1);	glVertex3f(x, y, z1);
	// section 3
		GLColorWithOverallAlpha(s3c, overallAlpha);
		glVertex3f(x, y - h4, z1);	glVertex3f(x - w2, y - h2, z1);	glVertex3f(x - w2, y - h1, z1);	glVertex3f(x, y - h2, z1);
		glVertex3f(x, y - h4, z1);	glVertex3f(x + w2, y - h2, z1);	glVertex3f(x + w2, y - h1, z1);	glVertex3f(x, y - h2, z1);
	OOGLEND();
}


- (void) drawStickSensitivityIndicator:(NSDictionary *)info
{
	GLfloat			x, y;
	NSSize			siz;
	BOOL			mouse;
	OOJoystickManager	*stickHandler = [OOJoystickManager sharedStickHandler];
	GLfloat			alpha = overallAlpha;
	
	mouse = [PLAYER isMouseControlOn];
	x = [info oo_intForKey:X_KEY defaultValue:STATUS_LIGHT_CENTRE_X] +
		[[UNIVERSE gameView] x_offset] *
		[info oo_floatForKey:X_ORIGIN_KEY defaultValue:0.0];
	y = [info oo_intForKey:Y_KEY defaultValue:STATUS_LIGHT_CENTRE_Y] +
		[[UNIVERSE gameView] y_offset] *
		[info oo_floatForKey:Y_ORIGIN_KEY defaultValue:0.0];
	siz.width = [info oo_nonNegativeFloatForKey:WIDTH_KEY defaultValue:STATUS_LIGHT_HEIGHT];
	siz.height = [info oo_nonNegativeFloatForKey:HEIGHT_KEY defaultValue:STATUS_LIGHT_HEIGHT];
	alpha *= [info oo_nonNegativeFloatForKey:ALPHA_KEY defaultValue:1.0f];
	
	GLfloat div = [stickHandler getSensitivity];
	
	GLColorWithOverallAlpha(black_color, alpha / 4);
	GLDrawFilledOval(x, y, z1, siz, 10);
	
	GLColorWithOverallAlpha((div < 1.0 || mouse) ? lightgray_color : green_color, alpha);
	OOGL(glLineWidth(_crosshairWidth * lineWidth));
	
	if (div >= 1.0)
	{
		if (!mouse)
		{
			NSSize siz8th = { siz.width / 8, siz.height / 8 };
			GLDrawFilledOval(x, y, z1, siz8th, 30);
			
			if (div == 1.0) // normal mode
				GLColorWithOverallAlpha(lightgray_color, alpha);
		}
		
		if ([stickHandler joystickCount])
		{
			siz.width -= _crosshairWidth * lineWidth / 2;
			siz.height -= _crosshairWidth * lineWidth / 2;
			GLDrawOval(x, y, z1, siz, 10);
		}
	}
	else if (div < 1.0) // insensitive mode (shouldn't happen)
		GLDrawFilledOval(x, y, z1, siz, 10);
}


- (void) drawSurround:(NSDictionary *)info color:(const GLfloat[4])color
{
	OOInteger		x;
	OOInteger		y;
	NSSize			siz;
	GLfloat			alpha = overallAlpha;
	
	x = [info oo_integerForKey:X_KEY defaultValue:NSNotFound];
	y = [info oo_integerForKey:Y_KEY defaultValue:NSNotFound];
	siz.width = [info oo_nonNegativeFloatForKey:WIDTH_KEY defaultValue:NAN];
	siz.height = [info oo_nonNegativeFloatForKey:HEIGHT_KEY defaultValue:NAN];
	alpha *= [info oo_nonNegativeFloatForKey:ALPHA_KEY defaultValue:1.0f];
	
	if (x == NSNotFound || y == NSNotFound || isnan(siz.width) || isnan(siz.height))  return;
	
	// draw green surround
	GLColorWithOverallAlpha(color, alpha);
	hudDrawSurroundAt(x + [[UNIVERSE gameView] x_offset] *
					  [info oo_floatForKey:X_ORIGIN_KEY defaultValue:0.0],
					  y + [[UNIVERSE gameView] y_offset] *
					  [info oo_floatForKey:Y_ORIGIN_KEY defaultValue:0.0], 
					  z1, siz);
}


- (void) drawGreenSurround:(NSDictionary *)info
{
	[self drawSurround:info color:green_color];
}


- (void) drawYellowSurround:(NSDictionary *)info
{
	[self drawSurround:info color:yellow_color];
}


- (void) drawTrumbles:(NSDictionary *)info
{
	PlayerEntity *player = PLAYER;
	
	OOTrumble** trumbles = [player trumbleArray];
	OOUInteger i;
	for (i = [player trumbleCount]; i > 0; i--)
	{
		OOTrumble* trum = trumbles[i - 1];
		[trum drawTrumble: z1];
	}
}


- (void) drawWatermarkString:(NSString *) watermarkString
{
	NSSize watermarkStringSize = OORectFromString(watermarkString, 0.0f, 0.0f, NSMakeSize(10, 10)).size;
	
	OOGL(glColor4f(0.0, 1.0, 0.0, 1.0));
	// position the watermark string on the top right hand corner of the game window and right-align it
	OODrawString(watermarkString, MAIN_GUI_PIXEL_WIDTH / 2 - watermarkStringSize.width + 80,
						MAIN_GUI_PIXEL_HEIGHT / 2 - watermarkStringSize.height, z1, NSMakeSize(10,10));
}

//---------------------------------------------------------------------//

static void hudDrawIndicatorAt(GLfloat x, GLfloat y, GLfloat z, NSSize siz, double amount)
{
	if (siz.width > siz.height)
	{
		GLfloat dial_oy =   y - siz.height/2;
		GLfloat position =  x + amount * siz.width / 2;
		OOGLBEGIN(GL_QUADS);
			glVertex3f(position, dial_oy, z);
			glVertex3f(position+2, y, z);
			glVertex3f(position, dial_oy+siz.height, z);
			glVertex3f(position-2, y, z);
		OOGLEND();
	}
	else
	{
		GLfloat dial_ox =   x - siz.width/2;
		GLfloat position =  y + amount * siz.height / 2;
		OOGLBEGIN(GL_QUADS);
			glVertex3f(dial_ox, position, z);
			glVertex3f(x, position+2, z);
			glVertex3f(dial_ox + siz.width, position, z);
			glVertex3f(x, position-2, z);
		OOGLEND();
	}
}


static void hudDrawMarkerAt(GLfloat x, GLfloat y, GLfloat z, NSSize siz, double amount)
{
	if (siz.width > siz.height)
	{
		GLfloat dial_oy =   y - siz.height/2;
		GLfloat position =  x + amount * siz.width - siz.width/2;
		OOGLBEGIN(GL_QUADS);
			glVertex3f(position+1, dial_oy+1, z);
			glVertex3f(position+1, dial_oy+siz.height-1, z);
			glVertex3f(position-1, dial_oy+siz.height-1, z);
			glVertex3f(position-1, dial_oy+1, z);
		OOGLEND();
	}
	else
	{
		GLfloat dial_ox =   x - siz.width/2;
		GLfloat position =  y + amount * siz.height - siz.height/2;
		OOGLBEGIN(GL_QUADS);
			glVertex3f(dial_ox+1, position+1, z);
			glVertex3f(dial_ox + siz.width-1, position+1, z);
			glVertex3f(dial_ox + siz.width-1, position-1, z);
			glVertex3f(dial_ox+1, position-1, z);
		OOGLEND();
	}
}


static void hudDrawBarAt(GLfloat x, GLfloat y, GLfloat z, NSSize siz, double amount)
{
	GLfloat dial_ox =   x - siz.width/2;
	GLfloat dial_oy =   y - siz.height/2;
	if (fabs(siz.width) > fabs(siz.height))
	{
		GLfloat position =  dial_ox + amount * siz.width;
		
		OOGLBEGIN(GL_QUADS);
			glVertex3f(dial_ox, dial_oy, z);
			glVertex3f(position, dial_oy, z);
			glVertex3f(position, dial_oy+siz.height, z);
			glVertex3f(dial_ox, dial_oy+siz.height, z);
		OOGLEND();
	}
	else
	{
		GLfloat position =  dial_oy + amount * siz.height;
		
		OOGLBEGIN(GL_QUADS);
			glVertex3f(dial_ox, dial_oy, z);
			glVertex3f(dial_ox, position, z);
			glVertex3f(dial_ox+siz.width, position, z);
			glVertex3f(dial_ox+siz.width, dial_oy, z);
		OOGLEND();
	}
}


static void hudDrawSurroundAt(GLfloat x, GLfloat y, GLfloat z, NSSize siz)
{
	GLfloat dial_ox = x - siz.width/2;
	GLfloat dial_oy = y - siz.height/2;
	
	OOGLBEGIN(GL_LINE_LOOP);
		glVertex3f(dial_ox-2, dial_oy-2, z);
		glVertex3f(dial_ox+siz.width+2, dial_oy-2, z);
		glVertex3f(dial_ox+siz.width+2, dial_oy+siz.height+2, z);
		glVertex3f(dial_ox-2, dial_oy+siz.height+2, z);
	OOGLEND();
}


static void hudDrawStatusIconAt(int x, int y, int z, NSSize siz)
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


static void hudDrawReticleOnTarget(Entity* target, PlayerEntity* player1, GLfloat z1, GLfloat alpha, BOOL reticleTargetSensitive, NSMutableDictionary* propertiesReticleTargetSensitive)
{
	ShipEntity		*target_ship = nil;
	NSString		*legal_desc = nil;
	if ((!target)||(!player1))
		return;

	if ([target isShip])
		target_ship = (ShipEntity*)target;

	if ([target_ship isCloaked])  return;
	
	switch ([target scanClass])
	{
		case CLASS_NEUTRAL:
			{
				int target_legal = [target_ship legalStatus];
				int legal_i = 0;
				if (target_legal > 0)
					legal_i =  (target_legal <= 50) ? 1 : 2;
				legal_desc = [[[UNIVERSE descriptions] oo_arrayForKey:@"legal_status"] oo_stringAtIndex:legal_i];
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
	
	OOMatrix		back_mat;
	Quaternion		back_q = [player1 orientation];
	back_q.w = -back_q.w;   // invert
	Vector			v1 = vector_up_from_quaternion(back_q);
	Vector			p1;
	
	p1 = vector_subtract([target position], [player1 viewpointPosition]);
	
	double			rdist = magnitude(p1);
	double			rsize = [target collisionRadius];
	
	if (rsize < rdist * ONE_SIXTYFOURTH)
		rsize = rdist * ONE_SIXTYFOURTH;
	
	GLfloat			rs0 = rsize;
	GLfloat			rs2 = rsize * 0.50;
	
	OOGL(glPushMatrix());
	
	// deal with view directions
	Vector view_dir, view_up = kBasisYVector;
	switch ([UNIVERSE viewDirection])
	{
		default:
		case VIEW_FORWARD:
			view_dir.x = 0.0;   view_dir.y = 0.0;   view_dir.z = 1.0;
			break;
			
		case VIEW_AFT:
			view_dir.x = 0.0;   view_dir.y = 0.0;   view_dir.z = -1.0;
			quaternion_rotate_about_axis(&back_q, v1, M_PI);
			break;
			
		case VIEW_PORT:
			view_dir.x = -1.0;   view_dir.y = 0.0;   view_dir.z = 0.0;
			quaternion_rotate_about_axis(&back_q, v1, 0.5 * M_PI);
			break;
			
		case VIEW_STARBOARD:
			view_dir.x = 1.0;   view_dir.y = 0.0;   view_dir.z = 0.0;
			quaternion_rotate_about_axis(&back_q, v1, -0.5 * M_PI);
			break;
			
		case VIEW_CUSTOM:
			view_dir = [player1 customViewForwardVector];
			view_up = [player1 customViewUpVector];
			back_q = quaternion_multiply([player1 customViewQuaternion], back_q);
			break;
	}
	OOGL(gluLookAt(view_dir.x, view_dir.y, view_dir.z, 0.0, 0.0, 0.0, view_up.x, view_up.y, view_up.z));
	
	back_mat = OOMatrixForQuaternionRotation(back_q);
	
	// rotate the view
	GLMultOOMatrix([player1 rotationMatrix]);
	// translate the view
	OOGL(glTranslatef(p1.x, p1.y, p1.z));
	//rotate to face player1
	GLMultOOMatrix(back_mat);
	// draw the reticle
	float range = sqrt(target->zero_distance) - target->collision_radius;
	
	// Draw reticle cyan for Wormholes
	if ([target isWormhole])
	{
		GLColorWithOverallAlpha(cyan_color, alpha);
	}
	else
	{
		// Reticle sensitivity accuracy calculation
		BOOL			isTargeted = NO;
		GLfloat			probabilityAccuracy;
		
		// Only if target is within player's weapon range, we mind for reticle accuracy
		if (range < [player1 weaponRange])
		{
			// After MAX_ACCURACY_RANGE km start decreasing high accuracy probability by ACCURACY_PROBABILITY_DECREASE_FACTOR%
			if (range > MAX_ACCURACY_RANGE)   
			{
				// Every one second re-evaluate accuracy
				if ([UNIVERSE getTime] > [propertiesReticleTargetSensitive oo_doubleForKey:@"timeLastAccuracyProbabilityCalculation"] + 1) 
				{
					probabilityAccuracy = 1-(range-MAX_ACCURACY_RANGE)*ACCURACY_PROBABILITY_DECREASE_FACTOR; 
					// Make sure probability does not go below a minimum
					probabilityAccuracy = probabilityAccuracy < MIN_PROBABILITY_ACCURACY ? MIN_PROBABILITY_ACCURACY : probabilityAccuracy;
					[propertiesReticleTargetSensitive setObject:[NSNumber numberWithBool:((randf() < probabilityAccuracy) ? YES : NO)] forKey:@"isAccurate"];
			
					// Store the time the last accuracy probability has been performed
					[propertiesReticleTargetSensitive setObject:[NSNumber numberWithDouble:[UNIVERSE getTime]] forKey:@"timeLastAccuracyProbabilityCalculation"];
				}			
				if ([propertiesReticleTargetSensitive oo_boolForKey:@"isAccurate"])
				{
					// high accuracy reticle
					isTargeted = ([UNIVERSE firstEntityTargetedByPlayerPrecisely] == target);
				}
				else
				{
					// low accuracy reticle
					isTargeted = ([UNIVERSE firstEntityTargetedByPlayer] == target);
				}
			}
			else
			{
				// high accuracy reticle
				isTargeted = ([UNIVERSE firstEntityTargetedByPlayerPrecisely] == target);
			}
		}
		
		// If reticle is target sensitive, draw target box in red 
		// when target passes through laser hit-point(with decreasing accuracy) 
		// and is within hit-range.
		//
		// NOTE: The following condition also considers (indirectly) the player's weapon range.
		//       'isTargeted' is initialised to FALSE. Only if target is within the player's weapon range,
		//       it might change value. Therefore, it is not necessary to add '&& range < [player1 weaponRange]'
		//       to the following condition.
		if (reticleTargetSensitive && isTargeted)
		{
			GLColorWithOverallAlpha(red_color, alpha);
		}
		else
		{
			GLColorWithOverallAlpha(green_color, alpha);
		}
	}
	OOGLBEGIN(GL_LINES);
		glVertex2f(rs0,rs2);	glVertex2f(rs0,rs0);
		glVertex2f(rs0,rs0);	glVertex2f(rs2,rs0);
		
		glVertex2f(rs0,-rs2);	glVertex2f(rs0,-rs0);
		glVertex2f(rs0,-rs0);	glVertex2f(rs2,-rs0);
		
		glVertex2f(-rs0,rs2);	glVertex2f(-rs0,rs0);
		glVertex2f(-rs0,rs0);	glVertex2f(-rs2,rs0);
		
		glVertex2f(-rs0,-rs2);	glVertex2f(-rs0,-rs0);
		glVertex2f(-rs0,-rs0);	glVertex2f(-rs2,-rs0);
	OOGLEND();
	
	// add text for reticle here
	range *= 0.001f;
	if (range < 0.001f) range = 0.0f;	// avoids the occasional -0.001 km distance.
	NSSize textsize = NSMakeSize(rdist * ONE_SIXTYFOURTH, rdist * ONE_SIXTYFOURTH);
	float line_height = rdist * ONE_SIXTYFOURTH;
	NSString*	info = [NSString stringWithFormat:@"%0.3f km", range];
	if (legal_desc != nil) info = [NSString stringWithFormat:@"%@ (%@)", info, legal_desc];
	// no need to set colour here
	OODrawString([player1 dialTargetName], rs0, 0.5 * rs2, 0, textsize);
	OODrawString(info, rs0, 0.5 * rs2 - line_height, 0, textsize);
	
	if ([target isWormhole])
	{
		// Note: No break statements in the following switch() since every case
		//       falls through to the next.  Cases arranged in reverse order.
		switch([(WormholeEntity *)target scanInfo])
		{
			case WH_SCANINFO_SHIP:
				// TOOD: Render anything on the HUD for this?
			case WH_SCANINFO_DESTINATION:
				// Rendered above in dialTargetName, so no need to do anything here
				// unless we want a separate line Destination: XXX ?
			case WH_SCANINFO_ARRIVAL_TIME:
			{
				NSString *wormholeETA = [NSString stringWithFormat:DESC(@"wormhole-ETA-@"), ClockToString([(WormholeEntity *)target estimatedArrivalTime], NO)];
				OODrawString(wormholeETA, rs0, 0.5 * rs2 - 3 * line_height, 0, textsize);
			}
			case WH_SCANINFO_COLLAPSE_TIME:
			{
				double timeForCollapsing = [(WormholeEntity *)target expiryTime] - [player1 clockTimeAdjusted];
				int minutesToCollapse = floor (timeForCollapsing / 60.0);
				int secondsToCollapse = (int)timeForCollapsing % 60;
				
				NSString *wormholeExpiringIn = [NSString stringWithFormat:DESC(@"wormhole-collapsing-in-mm:ss"), minutesToCollapse, secondsToCollapse];
				OODrawString(wormholeExpiringIn, rs0, 0.5 * rs2 - 2 * line_height, 0, textsize);
			}
			case WH_SCANINFO_SCANNED:
			case WH_SCANINFO_NONE:
				break;
		}
	}
	
	OOGL(glPopMatrix());
}


static void InitTextEngine(void)
{
	NSDictionary			*fontSpec = nil;
	NSArray					*widths = nil;
	NSString				*texName = nil;
	OOUInteger				i, count;
	
	fontSpec = [ResourceManager dictionaryFromFilesNamed:@"oolite-font.plist"
												inFolder:@"Config"
												andMerge:NO];
	
	texName = [fontSpec oo_stringForKey:@"texture" defaultValue:@"oolite-font.png"];
	sFontTexture = [OOTexture textureWithName:texName
									 inFolder:@"Textures"
									  options:kFontTextureOptions
								   anisotropy:0.0f
									  lodBias:-0.75f];
	[sFontTexture retain];
	
	sEncodingCoverter = [[OOEncodingConverter alloc] initWithFontPList:fontSpec];
	widths = [fontSpec oo_arrayForKey:@"widths"];
	count = [widths count];
	if (count > 256)  count = 256;
	for (i = 0; i != count; ++i)
	{
		sGlyphWidths[i] = [widths oo_floatAtIndex:i] * GLYPH_SCALE_FACTOR;
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


NSRect OORectFromString(NSString *text, double x, double y, NSSize siz)
{
	double				w = 0;
	NSData				*data = nil;
	const uint8_t		*bytes = NULL;
	OOUInteger			i, length;
	
	data = [sEncodingCoverter convertString:text];
	bytes = [data bytes];
	length = [data length];
	
	for (i = 0; i < length; i++)
	{
		w += siz.width * sGlyphWidths[bytes[i]];
	}
	
	return NSMakeRect(x, y, w, siz.height);
}


OOCGFloat OOStringWidthInEm(NSString *text)
{
	return OORectFromString(text, 0, 0, NSMakeSize(1.0 / (GLYPH_SCALE_FACTOR * 8.0), 1.0)).size.width;
}


void drawHighlight(double x, double y, double z, NSSize siz, double alpha)
{
	// Rounded corners, fading 'shadow' version
	OOGL(glColor4f(0.0f, 0.0f, 0.0f, alpha * 0.4f));	// dark translucent shadow
	
	OOGLBEGIN(GL_POLYGON);
	// thin 'halo' around the 'solid' highlight
	glVertex3f(x , y + siz.height + 3.0f, z);
	glVertex3f(x + siz.width + 4.0f, y + siz.height + 3.0f, z);
	glVertex3f(x + siz.width + 5.0f, y + siz.height + 1.0f, z);
	glVertex3f(x + siz.width + 5.0f, y + 3.0f, z);
	glVertex3f(x + siz.width + 4.0f, y + 1.0f, z);
	glVertex3f(x, y + 1.0f, z);
	glVertex3f(x - 1.0f, y + 3.0f, z);
	glVertex3f(x - 1.0f, y + siz.height + 1.0f, z);
	OOGLEND();
	
	OOGLBEGIN(GL_POLYGON);
	glVertex3f(x + 1.0f, y + siz.height + 2.0f, z);
	glVertex3f(x + siz.width + 3.0f, y + siz.height + 2.0f, z);
	glVertex3f(x + siz.width + 4.0f, y + siz.height + 1.0f, z);
	glVertex3f(x + siz.width + 4.0f, y + 3.0f, z);
	glVertex3f(x + siz.width + 3.0f, y + 2.0f, z);
	glVertex3f(x + 1.0f, y + 2.0f, z);
	glVertex3f(x, y + 3.0f, z);
	glVertex3f(x, y + siz.height + 1.0f, z);
	OOGLEND();

}

void OODrawString(NSString *text, double x, double y, double z, NSSize siz)
{
	double			cx = x;
	OOUInteger		i, length;
	NSData			*data = nil;
	const uint8_t	*bytes = NULL;
	
	OOGL(glEnable(GL_TEXTURE_2D));
	[sFontTexture apply];
	
	data = [sEncodingCoverter convertString:text];
	length = [data length];
	bytes = [data bytes];
	
	OOGLBEGIN(GL_QUADS);
	for (i = 0; i < length; i++)
	{
		cx += drawCharacterQuad(bytes[i], cx, y, z, siz);
	}
	OOGLEND();
	
	[OOTexture applyNone];
	OOGL(glDisable(GL_TEXTURE_2D));
}


void OODrawHilightedString(NSString *text, double x, double y, double z, NSSize siz)
{
	float color[4];
	
	// get the physical dimensions of the string
	NSSize strsize = OORectFromString(text, 0.0f, 0.0f, siz).size;
	strsize.width += 0.5f;
	
	OOGL(glPushAttrib(GL_CURRENT_BIT));	// save the text colour
	OOGL(glGetFloatv(GL_CURRENT_COLOR, color));	// we need the original colour's alpha.
	
	drawHighlight(x, y, z, strsize, color[3]);
	
	OOGL(glPopAttrib());	//restore the colour
	
	OODrawString(text, x, y, z, siz);
}


void OODrawPlanetInfo(int gov, int eco, int tec, double x, double y, double z, NSSize siz)
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
	
	OOGL(glEnable(GL_TEXTURE_2D));
	[sFontTexture apply];
	
	OOGLBEGIN(GL_QUADS);
		glColor4f(ce1, 1.0, 0.0, 1.0);
		// see OODrawHilightedPlanetInfo
		cx += drawCharacterQuad(23 - eco, cx, y, z, siz);	// characters 16..23 are economy symbols
		glColor3fv(&govcol[gov * 3]);
		cx += drawCharacterQuad(gov, cx, y, z, siz) - 1.0;		// charcters 0..7 are government symbols
		glColor4f(0.5, 1.0, 1.0, 1.0);
		if (tl > 9)
		{
			// display TL clamped between 1..16, this must be a '1'!
			cx += drawCharacterQuad(49, cx, y - 2, z, siz) - 2.0;
		}
		cx += drawCharacterQuad(48 + (tl % 10), cx, y - 2, z, siz);
	OOGLEND();
	
	(void)cx;	// Suppress "value not used" analyzer issue.
	
	[OOTexture applyNone];
	OOGL(glDisable(GL_TEXTURE_2D));
}


void OODrawHilightedPlanetInfo(int gov, int eco, int tec, double x, double y, double z, NSSize siz)
{
	float	color[4];
	int		tl = tec + 1;
	
	NSSize	hisize;
	
	// get the physical dimensions
	hisize.height = siz.height;
	hisize.width = 0.0f;
	
	// see OODrawPlanetInfo
	hisize.width += siz.width * sGlyphWidths[23 - eco];
	hisize.width += siz.width * sGlyphWidths[gov] - 1.0;
	if (tl > 9) hisize.width += siz.width * sGlyphWidths[49] - 2.0;
	hisize.width += siz.width * sGlyphWidths[48 + (tl % 10)];
	
	OOGL(glPushAttrib(GL_CURRENT_BIT));	// save the text colour
	OOGL(glGetFloatv(GL_CURRENT_COLOR, color));	// we need the original colour's alpha.
	
	drawHighlight(x, y - 2.0f, z, hisize, color[3]);
	
	OOGL(glPopAttrib());	//restore the colour
	
	OODrawPlanetInfo(gov, eco, tec, x, y, z, siz);
}


static void drawScannerGrid(double x, double y, double z, NSSize siz, int v_dir, GLfloat thickness, double zoom)
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
	
	OOGL(glLineWidth(2.0 * thickness));
	GLDrawOval(x, y, z, siz, 4);	
	OOGL(glLineWidth(thickness));
	
	OOGLBEGIN(GL_LINES);
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
			case VIEW_BREAK_PATTERN:
			case VIEW_GUI_DISPLAY:
			case VIEW_FORWARD:
			case VIEW_NONE:
				glVertex3f(x, y, z); glVertex3f(x - w2, y + hh, z);
				glVertex3f(x, y, z); glVertex3f(x + w2, y + hh, z);
				break;
				
			case VIEW_AFT:
				glVertex3f(x, y, z); glVertex3f(x - w2, y - hh, z);
				glVertex3f(x, y, z); glVertex3f(x + w2, y - hh, z);
				break;
				
			case VIEW_PORT:
				glVertex3f(x, y, z); glVertex3f(x - ww, y + h2, z);
				glVertex3f(x, y, z); glVertex3f(x - ww, y - h2, z);
				break;
				
			case VIEW_STARBOARD:
				glVertex3f(x, y, z); glVertex3f(x + ww, y + h2, z);
				glVertex3f(x, y, z); glVertex3f(x + ww, y - h2, z);
				break;
		}
	OOGLEND();
}


static void DrawSpecialOval(GLfloat x, GLfloat y, GLfloat z, NSSize siz, GLfloat step, GLfloat* color4v)
{
	GLfloat			ww = 0.5 * siz.width;
	GLfloat			hh = 0.5 * siz.height;
	GLfloat			theta;
	GLfloat			delta;
	GLfloat			s;
	
	delta = step * M_PI / 180.0f;
	
	OOGLBEGIN(GL_LINE_LOOP);
		for (theta = 0.0f; theta < (2.0f * M_PI); theta += delta)
		{
			s = sin(theta);
			glColor4f(color4v[0], color4v[1], color4v[2], fabs(s * color4v[3]));
			glVertex3f(x + ww * s, y + hh * cos(theta), z);
		}
	OOGLEND();
}


- (void) setLineWidth:(GLfloat) value
{
	lineWidth = value;
}


- (GLfloat) lineWidth
{
	return lineWidth;
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


@implementation OOPolygonSprite (OOHUDBeaconIcon)

- (void) oo_drawHUDBeaconIconAt:(NSPoint)where size:(NSSize)size alpha:(GLfloat)alpha z:(GLfloat)z
{
	GLfloat x = where.x - size.width;
	GLfloat y = where.y - 1.5 * size.height;
	
	GLfloat ox = x - size.width * 0.5;
	GLfloat oy = y - size.height * 0.5;
	GLfloat width = size.width * (1.0f / 6.0f);
	GLfloat height = size.height * (1.0f / 6.0f);
	
	OOGL(glPushMatrix());
	OOGL(glTranslatef(ox, oy, z));
	OOGL(glScalef(width, height, 1.0f));
	[self drawFilled];
	glColor4f(0.0, 0.0, 0.0, 0.5 * alpha);
	[self drawOutline];
	OOGL(glPopMatrix());
}

@end


@implementation NSString (OOHUDBeaconIcon)

- (void) oo_drawHUDBeaconIconAt:(NSPoint)where size:(NSSize)size alpha:(GLfloat)alpha z:(GLfloat)z
{
	OODrawString(self, where.x - 2.5 * size.width, where.y - 3.0 * size.height, z, NSMakeSize(size.width * 2, size.height * 2));
}

@end


static void GetRGBAArrayFromInfo(NSDictionary *info, GLfloat ioColor[4])
{
	id						colorDesc = nil;
	OOColor					*color = nil;
	
	// First, look for general colour specifier.
	colorDesc = [info objectForKey:RGB_COLOR_KEY];
	if (colorDesc != nil && ![info objectForKey:ALPHA_KEY])
	{
		color = [OOColor colorWithDescription:colorDesc];
		if (color != nil)
		{
			[color getGLRed:&ioColor[0] green:&ioColor[1] blue:&ioColor[2] alpha:&ioColor[3]];
			return;
		}
	}
	
	// Failing that, look for rgb_color and alpha.
	colorDesc = [info oo_arrayForKey:RGB_COLOR_KEY];
	if (colorDesc != nil && [colorDesc count] == 3)
	{
		ioColor[0] = [colorDesc oo_nonNegativeFloatAtIndex:0];
		ioColor[1] = [colorDesc oo_nonNegativeFloatAtIndex:1];
		ioColor[2] = [colorDesc oo_nonNegativeFloatAtIndex:2];
	}
	ioColor[3] = [info oo_nonNegativeFloatForKey:ALPHA_KEY defaultValue:ioColor[3]];
}
