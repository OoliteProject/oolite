/*

HeadUpDisplay.m

Oolite
Copyright (C) 2004-2013 Giles C Williams and contributors

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
#import "OOWaypointEntity.h"
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


#define ONE_SIXTEENTH				0.0625
#define ONE_SIXTYFOURTH				0.015625
#define DEFAULT_OVERALL_ALPHA		0.75
#define GLYPH_SCALE_FACTOR			0.13		// 0.13 is an inherited magic number
#define IDENTIFY_SCANNER_LOLLIPOPS	(	0	&& !defined(NDEBUG))


#define NOT_DEFINED					INFINITY
#define WIDGET_INFO					0
#define WIDGET_CACHE				1
#define	WIDGET_SELECTOR				2
#define	WIDGET_SELECTOR_NAME		3

/* Convenience macros to make set-colour-or-default quicker. 'info' must be the NSDictionary and 'alpha' must be the overall alpha or these won't work */
#define DO_SET_COLOR(t,d)		SetGLColourFromInfo(info,t,d,alpha)
#define SET_COLOR(d)			DO_SET_COLOR(COLOR_KEY,d)
#define SET_COLOR_LOW(d)		DO_SET_COLOR(COLOR_KEY_LOW,d)
#define SET_COLOR_MEDIUM(d)		DO_SET_COLOR(COLOR_KEY_MEDIUM,d)
#define SET_COLOR_HIGH(d)		DO_SET_COLOR(COLOR_KEY_HIGH,d)
#define SET_COLOR_CRITICAL(d)	DO_SET_COLOR(COLOR_KEY_CRITICAL,d)
#define SET_COLOR_SURROUND(d)	DO_SET_COLOR(COLOR_KEY_SURROUND,d)

struct CachedInfo
{
	float x, y, x0, y0;
	float width, height, alpha;
};

static NSArray *sCurrentDrawItem;

OOINLINE float useDefined(float val, float validVal) 
{
	return (val == NOT_DEFINED) ? validVal : val;
}


static void DrawSpecialOval(GLfloat x, GLfloat y, GLfloat z, NSSize siz, GLfloat step, GLfloat* color4v);

static void SetGLColourFromInfo(NSDictionary *info, NSString *key, const GLfloat defaultColor[4], GLfloat alpha);
static void GetRGBAArrayFromInfo(NSDictionary *info, GLfloat ioColor[4]);

static void hudDrawIndicatorAt(GLfloat x, GLfloat y, GLfloat z, NSSize siz, GLfloat amount);
static void hudDrawMarkerAt(GLfloat x, GLfloat y, GLfloat z, NSSize siz, GLfloat amount);
static void hudDrawBarAt(GLfloat x, GLfloat y, GLfloat z, NSSize siz, GLfloat amount);
static void hudDrawSurroundAt(GLfloat x, GLfloat y, GLfloat z, NSSize siz);
static void hudDrawStatusIconAt(int x, int y, int z, NSSize siz);
static void hudDrawReticleOnTarget(Entity* target, PlayerEntity* player1, GLfloat z1, GLfloat alpha, BOOL reticleTargetSensitive, NSMutableDictionary *propertiesReticleTargetSensitive, BOOL colourFromScannerColour, BOOL showText, NSDictionary *info);
static void hudDrawWaypoint(OOWaypointEntity *waypoint, PlayerEntity *player1, GLfloat z1, GLfloat alpha, BOOL selected, GLfloat scale);
static void hudRotateViewpointForVirtualDepth(PlayerEntity * player1, Vector p1);
static void drawScannerGrid(GLfloat x, GLfloat y, GLfloat z, NSSize siz, int v_dir, GLfloat thickness, GLfloat zoom, BOOL nonlinear);
static GLfloat nonlinearScannerFunc(GLfloat distance, GLfloat zoom, GLfloat scale);
static void GLDrawNonlinearCascadeWeapon( GLfloat x, GLfloat y, GLfloat z, NSSize siz, Vector centre, GLfloat radius, GLfloat zoom, GLfloat alpha );

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
- (void) drawMFDs;

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
- (void) drawSecondaryTargetReticle:(NSDictionary *)info;
- (void) drawWaypoints:(NSDictionary *)info;
- (void) drawStatusLight:(NSDictionary *)info;
- (void) drawDirectionCue:(NSDictionary *)info;
- (void) drawClock:(NSDictionary *)info;
- (void) drawPrimedEquipmentText:(NSDictionary *)info;
- (void) drawASCTarget:(NSDictionary *)info;
- (void) drawWeaponsOfflineText:(NSDictionary *)info;
- (void) drawMultiFunctionDisplay:(NSDictionary *)info withText:(NSString *)text asIndex:(NSUInteger)index;
- (void) drawFPSInfoCounter:(NSDictionary *)info;
- (void) drawScoopStatus:(NSDictionary *)info;
- (void) drawStickSenitivityIndicator:(NSDictionary *)info;

- (void) drawGreenSurround:(NSDictionary *)info;
- (void) drawYellowSurround:(NSDictionary *)info;

- (void) drawTrumbles:(NSDictionary *)info;

- (NSArray *) crosshairDefinitionForWeaponType:(OOWeaponType)weapon;

- (void) checkMassLock;
- (BOOL) checkEntityForMassLock:(Entity *)ent withScanClass:(int)scanClass;
- (BOOL) checkPlayerInFlight;
- (BOOL) checkPlayerInSystemFlight;

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

static float	sGlyphWidths[256];
static BOOL		_scannerUpdated;
static BOOL		_compassUpdated;
static BOOL 	hostiles;


static GLfloat drawCharacterQuad(uint8_t chr, GLfloat x, GLfloat y, GLfloat z, NSSize siz);

static void InitTextEngine(void);

static void prefetchData(NSDictionary *info, struct CachedInfo *data);


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
	BOOL			isCompassToBeDrawn = NO;
	BOOL			areTrumblesToBeDrawn = NO;
	
	self = [super init];
	
	lineWidth = 1.0;
	
	if (sFontTexture == nil)  InitTextEngine();
	
	deferredHudName = nil;	// if not nil, it means that we have a deferred HUD which is to be drawn at first available opportunity
	hudName = [hudFileName copy];
	
	// init arrays
	dialArray = [[NSMutableArray alloc] initWithCapacity:16];   // alloc retains
	legendArray = [[NSMutableArray alloc] initWithCapacity:16]; // alloc retains
	mfdArray = [[NSMutableArray alloc] initWithCapacity:4]; // alloc retains
	
	// populate arrays
	NSArray *dials = [hudinfo oo_arrayForKey:DIALS_KEY];
	for (i = 0; i < [dials count]; i++)
	{
		NSDictionary	*dial_info = [dials oo_dictionaryAtIndex:i];
		if (!areTrumblesToBeDrawn && [[dial_info oo_stringForKey:SELECTOR_KEY] isEqualToString:@"drawTrumbles:"])  areTrumblesToBeDrawn = YES;
		if (!isCompassToBeDrawn && [[dial_info oo_stringForKey:SELECTOR_KEY] isEqualToString:@"drawCompass:"])  isCompassToBeDrawn = YES;
		[self addDial:dial_info];
	}
	
	if (!areTrumblesToBeDrawn)	// naughty - a hud with no built-in drawTrumbles: - one must be added!
	{
		NSDictionary	*trumble_dial_info = [NSDictionary dictionaryWithObjectsAndKeys: @"drawTrumbles:", SELECTOR_KEY, nil];
		[self addDial:trumble_dial_info];
	}
	
	_compassActive = isCompassToBeDrawn;
	
	NSArray *legends = [hudinfo oo_arrayForKey:LEGENDS_KEY];
	for (i = 0; i < [legends count]; i++)
	{
		[self addLegend:[legends oo_dictionaryAtIndex:i]];
	}

	NSArray *mfds = [hudinfo oo_arrayForKey:MFDS_KEY];
	for (i = 0; i < [mfds count]; i++)
	{
		[self addMFD:[mfds oo_dictionaryAtIndex:i]];
	}

	
	hudHidden = NO;
	
	_hiddenSelectors = [[NSMutableSet alloc] initWithCapacity:16];

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
	
	nonlinear_scanner = [hudinfo oo_boolForKey:@"scanner_non_linear" defaultValue:NO];
	scanner_ultra_zoom = [hudinfo oo_boolForKey:@"scanner_ultra_zoom" defaultValue:NO];
	
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
	DESTROY(_hiddenSelectors);

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
		NSUInteger i, commCount = [cLog count];
		
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
		[gui setBackgroundColor:[OOColor colorWithRed:0.0 green:0.05 blue:0.45 alpha:0.5]];
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


- (GLfloat) scannerZoom
{
	return scanner_zoom;
}


- (void) setScannerZoom:(GLfloat)value
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


- (BOOL) hasHidden:(NSString *)selectorName
{
	if (selectorName == nil)
	{
		return NO;
	}
	return [_hiddenSelectors containsObject:selectorName];
}


- (void) setHiddenSelector:(NSString *)selectorName hidden:(BOOL)hide
{
	if (hide)
	{
		[_hiddenSelectors addObject:selectorName];
	}
	else
	{
		[_hiddenSelectors removeObject:selectorName];
	}
}


- (void) clearHiddenSelectors
{
	[_hiddenSelectors removeAllObjects];
}


- (BOOL) isCompassActive
{
	return _compassActive;
}


- (void) setCompassActive:(BOOL)newValue
{
	_compassActive = !!newValue;
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
	struct CachedInfo	cache;
	
	// prefetch data associated with this legend
	prefetchData(info, &cache);
	
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
			OOLogERR(kOOLogFileNotFound, @"HeadUpDisplay couldn't get an image texture name for %@", imageName);
			return;
		}
		
		imageSize = [texture dimensions];
		imageSize.width = [info oo_floatForKey:WIDTH_KEY defaultValue:imageSize.width];
		imageSize.height = [info oo_floatForKey:HEIGHT_KEY defaultValue:imageSize.height];
		
 		legendSprite = [[OOTextureSprite alloc] initWithTexture:texture size:imageSize];
		
		legendDict = [info mutableCopy];
		[legendDict setObject:legendSprite forKey:SPRITE_KEY];
		// add WIDGET_INFO, WIDGET_CACHE to array
		[legendArray addObject:[NSArray arrayWithObjects:legendDict, [NSValue valueWithBytes:&cache objCType:@encode(struct CachedInfo)], nil]];																	
		[legendDict release];
		[legendSprite release];
	}
	else if ([info oo_stringForKey:TEXT_KEY] != nil)
	{
		// add WIDGET_INFO, WIDGET_CACHE to array
		[legendArray addObject:[NSArray arrayWithObjects:info, [NSValue valueWithBytes:&cache objCType:@encode(struct CachedInfo)], nil]];

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
	
	NSString *selectorString = [info oo_stringForKey:SELECTOR_KEY];
	if (selectorString == nil)
	{
		OOLogERR(@"hud.dial.noSelector", @"HUD dial in %@ is missing selector.", hudName);
		return;
	}
	
	if (![allowedSelectors containsObject:selectorString])
	{
		OOLogERR(@"hud.dial.invalidSelector", @"HUD dial in %@ uses selector \"%@\" which is not in whitelist, and will be ignored.", hudName, selectorString);
		return;
	}
	
	SEL selector = NSSelectorFromString(selectorString);
	
	NSAssert2([self respondsToSelector:selector], @"HUD dial in %@ uses selector \"%@\" which is in whitelist, but not implemented.", hudName, selectorString);
	
	//  handle the case above with NS_BLOCK_ASSERTIONS too.
	if (![self respondsToSelector:selector])
	{
		OOLogERR(@"hud.dial.invalidSelector", @"HUD dial in %@ uses selector \"%@\"  which is in whitelist, but not implemented, and will be ignored.", hudName, selectorString);
		return;
	}
	
	// valid dial, now prefetch data
	struct CachedInfo cache;
	prefetchData(info, &cache);
	// add WIDGET_INFO, WIDGET_CACHE, WIDGET_SELECTOR, WIDGET_SELECTOR_NAME to array
	[dialArray addObject:[NSArray arrayWithObjects:info, [NSValue valueWithBytes:&cache objCType:@encode(struct CachedInfo)],
						 [NSValue valueWithPointer:selector], selectorString, nil]];
}


- (void) addMFD:(NSDictionary *)info
{
	struct CachedInfo cache;
	prefetchData(info, &cache);
	[mfdArray addObject:[NSArray arrayWithObjects:info, [NSValue valueWithBytes:&cache objCType:@encode(struct CachedInfo)],nil]];
}


- (NSUInteger) mfdCount
{
	return [mfdArray count];
}

/*
	SLOW_CODE
	As of 2012-09-13 (r5320), HUD rendering is taking 25%-30% of rendering time,
	or 15%-20% of game tick time, as tested on a couple of Macs using the
	default HUD and models. This could be worse - there used to be a note here
	saying 30%-40% of tick time - but could still improve.
	
	In a top-down perspective, of HUD rendering time, 67% is in -drawDials and
	27% is in -drawLegends.
	
	Bottom-up, one profile shows:
	21.2%	OODrawString()
			(Caching the glyph conversion here was a win, but caching geometry
			in vertex arrays/VBOs would be better.)
	8.9%	-[HeadUpDisplay drawHudItem:]
	5.1%	OOFloatFromObject
			(Reifying HUD info instead of parsing plists each frame would be
			a win.)
	4.4%	hudDrawBarAt()
			(Using fixed geometery and a vertex shader could help here,
			especially if bars are grouped together and drawn at once if
			possible.)
	4.3%	-[OOCrosshairs render]
			(Uses vertex arrays, but does more GL state manipulation than
			strictly necessary.)
	
*/
- (void) renderHUD
{
	hudUpdating = YES;
	
	OOVerifyOpenGLState();
	
	if (_crosshairWidth * lineWidth > 0)
	{
		OOGL(GLScaledLineWidth(_crosshairWidth * lineWidth));
		[self drawCrosshairs];
	}
	
	if (lineWidth > 0)
	{
		OOGL(GLScaledLineWidth(lineWidth));
		[self drawLegends];
	}
	
	[self drawDials];
	[self drawMFDs];
	OOCheckOpenGLErrors(@"After drawing HUD");
	
	OOVerifyOpenGLState();
	
	hudUpdating = NO;
}


- (void) drawLegends
{
	/* Since the order of legend drawing is significant, this loop must be kept
	 * as an incrementing one for compatibility with previous Oolite versions.
	 * CIM: 28/9/12 */
	z1 = [[UNIVERSE gameView] display_z];
	NSUInteger i, nLegends = [legendArray count];
	for (i = 0; i < nLegends; i++)
	{
		sCurrentDrawItem = [legendArray oo_arrayAtIndex:i];
		[self drawLegend:[sCurrentDrawItem oo_dictionaryAtIndex:WIDGET_INFO]];
	}
}


- (void) drawDials
{	
	z1 = [[UNIVERSE gameView] display_z];
	// reset drawScanner flag.
	_scannerUpdated = NO;
	_compassUpdated = NO;
	
	// tight loop, we assume dialArray doesn't change in mid-draw.
	NSUInteger i, nDials = [dialArray count];
	for (i = 0; i < nDials; i++)
	{
		sCurrentDrawItem = [dialArray oo_arrayAtIndex:i];
		[self drawHUDItem:[sCurrentDrawItem oo_dictionaryAtIndex:WIDGET_INFO]];
	}
	
	if (EXPECT_NOT(!_compassUpdated && _compassActive && [self checkPlayerInSystemFlight]))	// compass gone / broken / disabled ?
	{
		// trigger the targetChanged event with whom == null
		_compassActive = NO;
		[PLAYER doScriptEvent:OOJSID("compassTargetChanged") withArguments:[NSArray arrayWithObjects:[NSNull null], OOStringFromCompassMode([PLAYER compassMode]), nil]];
	}
	
	// We always need to check the mass lock status. It's normally checked inside drawScanner,
	// but if drawScanner wasn't called, we can check mass lock explicitly.
	if (!_scannerUpdated)  [self checkMassLock];
}


- (void) drawMFDs
{
	NSUInteger i, nMFDs = [mfdArray count];
	NSString *text = nil;
	for (i = 0; i < nMFDs; i++)
	{
		text = [PLAYER multiFunctionText:i];
		if (text != nil)
		{
			sCurrentDrawItem = [mfdArray oo_arrayAtIndex:i];
			[self drawMultiFunctionDisplay:[sCurrentDrawItem oo_dictionaryAtIndex:WIDGET_INFO] withText:text asIndex:i];
		}
	}
}


- (void) drawCrosshairs
{
	OOViewID					viewID = [UNIVERSE viewDirection];
	OOWeaponType				weapon = [PLAYER currentWeapon];
	BOOL						weaponsOnline = [PLAYER weaponsOnline];
	NSArray						*points = nil;
	
	if (viewID == VIEW_CUSTOM ||
		overallAlpha == 0.0f ||
		!([PLAYER status] == STATUS_IN_FLIGHT || [PLAYER status] == STATUS_WITCHSPACE_COUNTDOWN) ||
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
	// check if equipment is required
	NSString *equipmentRequired = [info oo_stringForKey:EQUIPMENT_REQUIRED_KEY];
	if (equipmentRequired != nil && ![PLAYER hasEquipmentItem:equipmentRequired])
	{
		return;
	}

	// check alert condition
	NSUInteger alertMask = [info oo_unsignedIntForKey:ALERT_CONDITIONS_KEY defaultValue:15];
	// 1=docked, 2=green, 4=yellow, 8=red
	if (alertMask < 15)
	{
		OOAlertCondition alertCondition = [PLAYER alertCondition];
		/* Because one of the items here is the scanner, which changes
		 * the alert condition, this may give inconsistent results
		 * mid-frame. This is unlikely to be crucial, but it's yet
		 * another reason to get around to separating out scanner
		 * display and alert level calculation - CIM */
		if (~alertMask & (1 << alertCondition)) {
			return;
		}
	}

	// check association with hidden dials
	if ([self hasHidden:[info oo_stringForKey:DIAL_REQUIRED_KEY defaultValue:nil]])
	{
		return;
	}

	OOTextureSprite				*legendSprite = nil;
	NSString					*legendText = nil;
	float						x, y;
	NSSize						size;
	GLfloat						alpha = overallAlpha;
	struct CachedInfo			cached;
	
	[(NSValue *)[sCurrentDrawItem objectAtIndex:WIDGET_CACHE] getValue:&cached];
	
	// if either x or y is missing, use 0 instead
	
	x = useDefined(cached.x, 0.0f) + [[UNIVERSE gameView] x_offset] * cached.x0;
	y = useDefined(cached.y, 0.0f) + [[UNIVERSE gameView] y_offset] * cached.y0;
	alpha *= cached.alpha;
	
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
			// randomly chosen default width & height
			size.width = useDefined(cached.width, 14.0f);
			size.height = useDefined(cached.height, 8.0f);
			GLColorWithOverallAlpha(green_color, alpha);
			OODrawString(legendText, x, y, z1, size);
		}
	}
}


- (void) drawHUDItem:(NSDictionary *)info
{
	NSString	*equipment = [info oo_stringForKey:EQUIPMENT_REQUIRED_KEY];
	
	if (equipment != nil && ![PLAYER hasEquipmentItem:equipment])
	{
		return;
	}

	// check alert condition
	NSUInteger alertMask = [info oo_unsignedIntForKey:ALERT_CONDITIONS_KEY defaultValue:15];
	// 1=docked, 2=green, 4=yellow, 8=red
	if (alertMask < 15)
	{
		OOAlertCondition alertCondition = [PLAYER alertCondition];
		/* Because one of the items here is the scanner, which changes
		 * the alert condition, this may give inconsistent results
		 * mid-frame. This is unlikely to be crucial, but it's yet
		 * another reason to get around to separating out scanner
		 * display and alert level calculation - CIM */
		if (~alertMask & (1 << alertCondition)) {
			return;
		}
	}

	if (EXPECT_NOT([self hasHidden:[sCurrentDrawItem objectAtIndex:WIDGET_SELECTOR_NAME]]))
	{
		return;
	}

	// use the selector value stored during init.
	[self performSelector:[(NSValue *)[sCurrentDrawItem objectAtIndex:WIDGET_SELECTOR] pointerValue] withObject:info];
	OOCheckOpenGLErrors(@"HeadUpDisplay after drawHUDItem %@", info);
	
	OOVerifyOpenGLState();
}


- (BOOL) checkPlayerInFlight
{
	return [PLAYER isInSpace] && [PLAYER status] != STATUS_DOCKING;
}


- (BOOL) checkPlayerInSystemFlight
{
	OOSunEntity		*the_sun = [UNIVERSE sun];
	OOPlanetEntity	*the_planet = [UNIVERSE planet];
	
	return [self checkPlayerInFlight]		// be in the right mode
		&& the_sun && the_planet		// and be in a system
		&& ![the_sun goneNova];
}


- (void) checkMassLock
{	
	if ([self checkPlayerInFlight])
	{
		int				i, scanClass, ent_count = UNIVERSE->n_entities;
		Entity			**uni_entities	= UNIVERSE->sortedEntities;	// grab the public sorted list
		Entity			*my_entities[ent_count];
		Entity			*scannedEntity = nil;
		BOOL			massLocked = NO;
		
		for (i = 0; i < ent_count; i++)
		{
			my_entities[i] = [uni_entities[i] retain];	// retained
		}
	
		for (i = 0; i < ent_count && !massLocked; i++)
		{
			scannedEntity = my_entities[i];
			scanClass = [scannedEntity scanClass];
			
			massLocked = [self checkEntityForMassLock:scannedEntity withScanClass:scanClass];
		}
		[PLAYER setAlertFlag:ALERT_FLAG_MASS_LOCK to:massLocked];

		for (i = 0; i < ent_count; i++)
		{
			[my_entities[i] release];	//	released
		}
	}
}


- (BOOL) checkEntityForMassLock:(Entity *)ent withScanClass:(int)scanClass
{
	BOOL massLocked = NO;
	
	if (EXPECT_NOT([ent isStellarObject]))
	{
		Entity<OOStellarBody> *stellar = (Entity<OOStellarBody> *)ent;
		if (EXPECT([stellar planetType] != STELLAR_TYPE_MINIATURE))
		{
			double dist = stellar->zero_distance;
			double rad = stellar->collision_radius;
			double factor = ([stellar isSun]) ? 2.0 : 4.0;
			// plus ensure mass lock when 25 km or less from the surface of small stellar bodies
			// dist is a square distance so it needs to be compared to (rad+25000) * (rad+25000)!
			if (dist < rad*rad*factor || dist < rad*rad + 50000*rad + 625000000 ) 
			{
				massLocked = YES;
			}
		}
	}
	else if (scanClass != CLASS_NO_DRAW)
	{
		// cloaked ships do not mass lock!
		if (EXPECT_NOT ([ent isShip] && [(ShipEntity *)ent isCloaked]))
		{
			scanClass = CLASS_NO_DRAW;
		}
	}

	if (!massLocked && ent->zero_distance <= SCANNER_MAX_RANGE2)
	{
		switch (scanClass)
		{
			case CLASS_NO_DRAW:
			case CLASS_PLAYER:
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
				massLocked = YES;
				break;
		}
	}
	
	return massLocked;
}


static void prefetchData(NSDictionary *info, struct CachedInfo *data)
{
	data->x = [info oo_floatForKey:X_KEY defaultValue:NOT_DEFINED];
	data->x0 = [info oo_floatForKey:X_ORIGIN_KEY defaultValue:0.0];
	data->y = [info oo_floatForKey:Y_KEY defaultValue:NOT_DEFINED];
	data->y0 = [info oo_floatForKey:Y_ORIGIN_KEY defaultValue:0.0];
	data->width = [info oo_nonNegativeFloatForKey:WIDTH_KEY defaultValue:NOT_DEFINED];
	data->height = [info oo_nonNegativeFloatForKey:HEIGHT_KEY defaultValue:NOT_DEFINED];
	data->alpha = [info oo_nonNegativeFloatForKey:ALPHA_KEY defaultValue:1.0f];	
}

//---------------------------------------------------------------------//

- (void) drawScanner:(NSDictionary *)info
{
	//	if (_scannerUpdated)  return;		// there's never the need to draw the scanner twice per frame!
	// apparently there are HUDs out there that do this. CIM 6/12/12
	
	int				i, x, y;
	NSSize			siz;
	GLfloat			scanner_color[4] = { 1.0, 0.0, 0.0, 1.0 };
	
	BOOL			emptyDial = ([info oo_floatForKey:ALPHA_KEY] == 0.0f);
		
	BOOL			isHostile = NO;
	BOOL			foundHostiles = NO;
	BOOL			massLocked = NO;
	
	if (emptyDial)
	{
		// we can skip a lot of code.
		x = y = 0;
		scanner_color[3] = 0.0;			// nothing to see!
		siz = NSMakeSize(1.0, 1.0);		// avoid divide by 0s
	}
	else
	{
		struct CachedInfo	cached;
	
		[(NSValue *)[sCurrentDrawItem objectAtIndex:WIDGET_CACHE] getValue:&cached];
		
		x = useDefined(cached.x, SCANNER_CENTRE_X) + [[UNIVERSE gameView] x_offset] * cached.x0;
		y = useDefined(cached.y, SCANNER_CENTRE_Y) + [[UNIVERSE gameView] y_offset] * cached.y0;
		siz.width = useDefined(cached.width, SCANNER_WIDTH);
		siz.height = useDefined(cached.height, SCANNER_HEIGHT);

		GetRGBAArrayFromInfo(info, scanner_color);
		
		scanner_color[3] *= overallAlpha;
	}
	
	GLfloat			alpha = scanner_color[3];
	GLfloat			col[4] = { 1.0, 1.0, 1.0, alpha };	// temporary colour variable
	
	GLfloat			z_factor = siz.height / siz.width;	// approx 1/4
	GLfloat			y_factor = 1.0 - sqrt(z_factor);	// approx 1/2
	
	int				scanner_cx = x;
	int				scanner_cy = y;
	
	int				scannerFootprint = SCANNER_MAX_RANGE * 2.5 / siz.width;
	
	GLfloat			zoom = scanner_zoom;
	if (scanner_ultra_zoom)
		zoom = pow(2, zoom - 1.0);
	GLfloat			max_zoomed_range2 = SCANNER_SCALE * SCANNER_SCALE * 10000.0;
	if (!nonlinear_scanner)
	{
		max_zoomed_range2 /= zoom * zoom;
	}
	GLfloat			max_zoomed_range = sqrt(max_zoomed_range2);
	
	if (PLAYER == nil)  return;
	
	OOMatrix		rotMatrix = [PLAYER rotationMatrix];
	Vector			relativePosition;
	int				flash = ((int)([UNIVERSE getTime] * 4))&1;
	
	// use a non-mutable copy so this can't be changed under us.
	int				ent_count		= UNIVERSE->n_entities;
	Entity			**uni_entities	= UNIVERSE->sortedEntities;	// grab the public sorted list
	Entity			*my_entities[ent_count];
	Entity			*scannedEntity = nil;
	
	for (i = 0; i < ent_count; i++)
	{
		my_entities[i] = [uni_entities[i] retain];	// retained
	}
	
	if (!emptyDial)
	{
		OOGL(glColor4fv(scanner_color));
		drawScannerGrid(x, y, z1, siz, [UNIVERSE viewDirection], lineWidth, zoom, nonlinear_scanner);
	}
	
	if ([self checkPlayerInFlight])
	{
		GLfloat upscale = zoom * 1.25 / scannerFootprint;
		GLfloat max_blip = 0.0;
		int drawClass;
		
		OOVerifyOpenGLState();
		
		// Debugging code for nonlinear scanner - draws three fake cascade weapons, which looks pretty and enables me
		// to debug the code without the mass slaughter of innocent civillians.
		//if (nonlinear_scanner)
		//{
		//	Vector p = OOVectorMultiplyMatrix(make_vector(10000.0, 0.0, 0.0), rotMatrix);
		//	GLDrawNonlinearCascadeWeapon( scanner_cx, scanner_cy, z1, siz, p, 5000, zoom, alpha );
		//	p = OOVectorMultiplyMatrix(make_vector(10000.0, 4500.0, 0.0), rotMatrix);
		//	GLDrawNonlinearCascadeWeapon( scanner_cx, scanner_cy, z1, siz, p, 2000, zoom, alpha );
		//	p = OOVectorMultiplyMatrix(make_vector(0.0, 0.0, 20000.0), rotMatrix);
		//	GLDrawNonlinearCascadeWeapon( scanner_cx, scanner_cy, z1, siz, p, 6000, zoom, alpha );
		//}
		for (i = 0; i < ent_count; i++)  // scanner lollypops
		{
			scannedEntity = my_entities[i];
			
			drawClass = [scannedEntity scanClass];
			
			// cloaked ships - and your own one - don't show up on the scanner.
			if (EXPECT_NOT(drawClass == CLASS_PLAYER || ([scannedEntity isShip] && [(ShipEntity *)scannedEntity isCloaked])))
			{
				drawClass = CLASS_NO_DRAW;
			}
			
			massLocked |= [self checkEntityForMassLock:scannedEntity withScanClass:drawClass];	// we just need one masslocker..
			
			if (drawClass != CLASS_NO_DRAW)
			{
				GLfloat x1,y1,y2;
				float	ms_blip = 0.0;
				
				if (emptyDial)  continue;
				
				if (isnan(scannedEntity->zero_distance))
					continue;
				
				// exit if it's too far away
				GLfloat	act_dist = sqrt(scannedEntity->zero_distance);
				GLfloat	lim_dist = act_dist - scannedEntity->collision_radius;
				
				if (lim_dist > max_zoomed_range)
					continue;
				
				// has it sent a recent message
				//
				if ([scannedEntity isShip]) 
					ms_blip = 2.0 * [(ShipEntity *)scannedEntity messageTime];
				if (ms_blip > max_blip)
				{
					max_blip = ms_blip;
					last_transmitter = [scannedEntity universalID];
				}
				ms_blip -= floor(ms_blip);
				
				relativePosition = [PLAYER vectorTo:scannedEntity];
				Vector rp = relativePosition;
				
				if (act_dist > max_zoomed_range)
					scale_vector(&relativePosition, max_zoomed_range / act_dist);
				
				// rotate the view
				relativePosition = OOVectorMultiplyMatrix(relativePosition, rotMatrix);
				Vector rrp = relativePosition;
				// scale the view
				if (nonlinear_scanner)
				{
					relativePosition = [HeadUpDisplay nonlinearScannerScale: relativePosition Zoom: zoom Scale: 0.5*siz.width];
				}
				else
				{
					scale_vector(&relativePosition, upscale);
				}
				
				x1 = relativePosition.x;
				y1 = z_factor * relativePosition.z;
				y2 = y1 + y_factor * relativePosition.y;
				
				isHostile = NO;
				if ([scannedEntity isShip])
				{
					ShipEntity *ship = (ShipEntity *)scannedEntity;
					isHostile = (([ship hasHostileTarget])&&([ship primaryTarget] == PLAYER));
					GLfloat *base_col = [ship scannerDisplayColorForShip:PLAYER :isHostile :flash :[ship scannerDisplayColor1] :[ship scannerDisplayColor2]];
					col[0] = base_col[0];	col[1] = base_col[1];	col[2] = base_col[2];	col[3] = alpha * base_col[3];
				}
				else if ([scannedEntity isVisualEffect])
				{
					OOVisualEffectEntity *vis = (OOVisualEffectEntity *)scannedEntity;
					GLfloat* base_col = [vis scannerDisplayColorForShip:flash :[vis scannerDisplayColor1] :[vis scannerDisplayColor2]];
					col[0] = base_col[0];	col[1] = base_col[1];	col[2] = base_col[2];	col[3] = alpha * base_col[3];
				}

				if ([scannedEntity isWormhole])
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
				
				if ([scannedEntity isShip])
				{
					ShipEntity* ship = (ShipEntity*)scannedEntity;
					if ((!nonlinear_scanner && ship->collision_radius * upscale > 4.5) ||
						(nonlinear_scanner && nonlinearScannerFunc(act_dist, zoom, siz.width) - nonlinearScannerFunc(lim_dist, zoom, siz.width) > 4.5 ))
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
							if (nonlinear_scanner)
							{
								bounds[i] = [HeadUpDisplay nonlinearScannerScale:bounds[i] Zoom: zoom Scale: 0.5*siz.width];
							}
							else
							{
								scale_vector(&bounds[i], upscale);
							}
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
				if ([scannedEntity isCascadeWeapon])
				{
					if (nonlinear_scanner)
					{
						GLDrawNonlinearCascadeWeapon( scanner_cx, scanner_cy, z1, siz, rrp, scannedEntity->collision_radius, zoom, alpha );
					}
					else
					{
						GLfloat r1 = 2.5 + scannedEntity->collision_radius * upscale;
						GLfloat l2 = r1 * r1 - relativePosition.y * relativePosition.y;
						GLfloat r0 = (l2 > 0)? sqrt(l2): 0;
						if (r0 > 0)
						{
							OOGL(glColor4f(1.0, 0.5, 1.0, alpha));
							GLDrawOval(x1  - 0.5, y1 + 1.5, z1, NSMakeSize(r0, r0 * siz.height / siz.width), 20);
						}
						OOGL(glColor4f(0.5, 0.0, 1.0, 0.33333 * alpha));
						GLDrawFilledOval(x1  - 0.5, y2 + 1.5, z1, NSMakeSize(r1, r1), 15);
					}
				}
				else
				{

#if IDENTIFY_SCANNER_LOLLIPOPS
					if ([scannedEntity isShip])
					{
						glColor4f(1.0, 1.0, 0.5, alpha);
						OODrawString([(ShipEntity *)scannedEntity displayName], x1 + 2, y2 + 2, z1, NSMakeSize(8, 8));
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
		
		[PLAYER setAlertFlag:ALERT_FLAG_MASS_LOCK to:massLocked];
		
		[PLAYER setAlertFlag:ALERT_FLAG_HOSTILES to:foundHostiles];
		
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
	{
		[my_entities[i] release];	//	released
	}
	
	OOVerifyOpenGLState();
	
	_scannerUpdated = YES;
}

+ (Vector) nonlinearScannerScale: (Vector) V Zoom:(GLfloat)zoom Scale:(double) scale
{
	OOScalar mag = magnitude(V);
	Vector unit = vector_normal(V);
	return vector_multiply_scalar(unit, nonlinearScannerFunc(mag, zoom, scale));
}


- (BOOL) nonlinearScanner
{
	return nonlinear_scanner;
}


- (void) setNonlinearScanner: (BOOL) newValue
{
	nonlinear_scanner = !!newValue;
}


- (BOOL) scannerUltraZoom
{
	return scanner_ultra_zoom;
}


- (void) setScannerUltraZoom: (BOOL) newValue
{
	scanner_ultra_zoom = !!newValue;
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
	int					x, y;
	NSSize				siz;
	GLfloat				alpha;
	GLfloat				zoom_color[4] = { 1.0f, 0.1f, 0.0f, 1.0f };
	struct CachedInfo	cached;
	
	[(NSValue *)[sCurrentDrawItem objectAtIndex:WIDGET_CACHE] getValue:&cached];
	
	x = useDefined(cached.x, ZOOM_INDICATOR_CENTRE_X) + [[UNIVERSE gameView] x_offset] * cached.x0;
	y = useDefined(cached.y, ZOOM_INDICATOR_CENTRE_Y) + [[UNIVERSE gameView] y_offset] * cached.y0;
	siz.width = useDefined(cached.width, ZOOM_INDICATOR_WIDTH);
	siz.height = useDefined(cached.height, ZOOM_INDICATOR_HEIGHT);
	
	GetRGBAArrayFromInfo(info, zoom_color);
	zoom_color[3] *= overallAlpha;
	alpha = zoom_color[3];
	
	GLfloat cx = x - 0.3 * siz.width;
	GLfloat cy = y - 0.75 * siz.height;
	
	int zl = scanner_zoom;
	if (zl < 1) zl = 1;
	if (zl > SCANNER_ZOOM_LEVELS) zl = SCANNER_ZOOM_LEVELS;
	if (zl == 1) zoom_color[3] *= 0.75;
	if (scanner_ultra_zoom)
		zl = pow(2, zl - 1);
	GLColorWithOverallAlpha(zoom_color, alpha);
	OOGL(glEnable(GL_TEXTURE_2D));
	[sFontTexture apply];
	
	OOGLBEGIN(GL_QUADS);
		if (zl / 10 > 0)
			drawCharacterQuad(48 + zl / 10, cx - 0.8 * siz.width, cy, z1, siz);
		drawCharacterQuad(48 + zl % 10, cx - 0.4 * siz.width, cy, z1, siz);
		drawCharacterQuad(58, cx, cy, z1, siz);
		drawCharacterQuad(49, cx + 0.3 * siz.width, cy, z1, siz);
	OOGLEND();
	
	[OOTexture applyNone];
	OOGL(glDisable(GL_TEXTURE_2D));
}


- (void) drawCompass:(NSDictionary *)info
{
	int					x, y;
	NSSize				siz;
	GLfloat				alpha;
	GLfloat				compass_color[4] = { 0.0f, 0.0f, 1.0f, 1.0f };
	struct CachedInfo	cached;
	
	[(NSValue *)[sCurrentDrawItem objectAtIndex:WIDGET_CACHE] getValue:&cached];
	
	x = useDefined(cached.x, COMPASS_CENTRE_X) + [[UNIVERSE gameView] x_offset] * cached.x0;
	y = useDefined(cached.y, COMPASS_CENTRE_Y) + [[UNIVERSE gameView] y_offset] * cached.y0;
	siz.width = useDefined(cached.width, COMPASS_HALF_SIZE);
	siz.height = useDefined(cached.height, COMPASS_HALF_SIZE);
	
	GetRGBAArrayFromInfo(info, compass_color);
	compass_color[3] *= overallAlpha;
	alpha = compass_color[3];
	
	// draw the compass
	OOMatrix		rotMatrix = [PLAYER rotationMatrix];
	
	GLfloat h1 = siz.height * 0.125;
	GLfloat h3 = siz.height * 0.375;
	GLfloat w1 = siz.width * 0.125;
	GLfloat w3 = siz.width * 0.375;
	OOGL(GLScaledLineWidth(2.0 * lineWidth));	// thicker
	OOGL(glColor4f(compass_color[0], compass_color[1], compass_color[2], alpha));
	GLDrawOval(x, y, z1, siz, 12);	
	OOGL(glColor4f(compass_color[0], compass_color[1], compass_color[2], 0.5f * alpha));
	OOGLBEGIN(GL_LINES);
		glVertex3f(x - w1, y, z1);	glVertex3f(x - w3, y, z1);
		glVertex3f(x + w1, y, z1);	glVertex3f(x + w3, y, z1);
		glVertex3f(x, y - h1, z1);	glVertex3f(x, y - h3, z1);
		glVertex3f(x, y + h1, z1);	glVertex3f(x, y + h3, z1);
	OOGLEND();
	OOGL(GLScaledLineWidth(lineWidth));	// thinner
	
	if ([self checkPlayerInSystemFlight] && [PLAYER status] != STATUS_LAUNCHING) // normal system
	{
		Entity *reference = [PLAYER compassTarget];
		
		// translate and rotate the view

		Vector relativePosition = [PLAYER vectorTo:reference];
		relativePosition = OOVectorMultiplyMatrix(relativePosition, rotMatrix);
		relativePosition = vector_normal_or_fallback(relativePosition, kBasisZVector);
		
		relativePosition.x *= siz.width * 0.4;
		relativePosition.y *= siz.height * 0.4;
		relativePosition.x += x;
		relativePosition.y += y;
		
		siz.width *= 0.2;
		siz.height *= 0.2;
		OOGL(GLScaledLineWidth(2.0));
		switch ([PLAYER compassMode])
		{
			case COMPASS_MODE_INACTIVE:
				break;
			
			case COMPASS_MODE_BASIC:
				[self drawCompassPlanetBlipAt:relativePosition Size:siz Alpha:alpha];
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
				Entity <OOBeaconEntity>		*beacon = [PLAYER nextBeacon];
				[[beacon beaconDrawable] oo_drawHUDBeaconIconAt:NSMakePoint(x, y) size:siz alpha:alpha z:z1];
				break;
		}
		OOGL(GLScaledLineWidth(lineWidth));	// reset

		_compassUpdated = YES;
		_compassActive = YES;
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
	
	int					x, y;
	NSSize				siz;
	GLfloat				alpha = 0.5f * overallAlpha;
	struct CachedInfo	cached;
	
	[(NSValue *)[sCurrentDrawItem objectAtIndex:WIDGET_CACHE] getValue:&cached];
	
	x = useDefined(cached.x, AEGIS_CENTRE_X) + [[UNIVERSE gameView] x_offset] * cached.x0;
	y = useDefined(cached.y, AEGIS_CENTRE_Y) + [[UNIVERSE gameView] y_offset] * cached.y0;
	siz.width = useDefined(cached.width, AEGIS_WIDTH);
	siz.height = useDefined(cached.height, AEGIS_HEIGHT);
	alpha *= cached.alpha;
	
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
	int					x, y;
	NSSize				siz;
	BOOL				draw_surround;
	GLfloat				alpha = overallAlpha;
	GLfloat				ds = [PLAYER dialSpeed];
	struct CachedInfo	cached;
	
	[(NSValue *)[sCurrentDrawItem objectAtIndex:WIDGET_CACHE] getValue:&cached];
	
	x = useDefined(cached.x, SPEED_BAR_CENTRE_X) + [[UNIVERSE gameView] x_offset] * cached.x0;
	y = useDefined(cached.y, SPEED_BAR_CENTRE_Y) + [[UNIVERSE gameView] y_offset] * cached.y0;
	siz.width = useDefined(cached.width, SPEED_BAR_WIDTH);
	siz.height = useDefined(cached.height, SPEED_BAR_HEIGHT);
	alpha *= cached.alpha;
	
	draw_surround = [info oo_boolForKey:DRAW_SURROUND_KEY defaultValue:SPEED_BAR_DRAW_SURROUND];
	
	
	SET_COLOR_SURROUND(green_color);
	if (draw_surround)
	{
		// draw speed surround
		hudDrawSurroundAt(x, y, z1, siz);
	}
	// draw speed bar
	if (ds > .80)
	{
		SET_COLOR_HIGH(red_color);
	}
	else if (ds > .25)
	{
		SET_COLOR_MEDIUM(yellow_color);
	}
	else
	{
		SET_COLOR_LOW(green_color);
	}

	hudDrawBarAt(x, y, z1, siz, ds);
}


- (void) drawRollBar:(NSDictionary *)info
{
	int					x, y;
	NSSize				siz;
	BOOL				draw_surround;
	GLfloat				alpha = overallAlpha;
	struct CachedInfo	cached;
	
	[(NSValue *)[sCurrentDrawItem objectAtIndex:WIDGET_CACHE] getValue:&cached];
	
	x = useDefined(cached.x, ROLL_BAR_CENTRE_X) + [[UNIVERSE gameView] x_offset] * cached.x0;
	y = useDefined(cached.y, ROLL_BAR_CENTRE_Y) + [[UNIVERSE gameView] y_offset] * cached.y0;
	siz.width = useDefined(cached.width, ROLL_BAR_WIDTH);
	siz.height = useDefined(cached.height, ROLL_BAR_HEIGHT);
	alpha *= cached.alpha;
	draw_surround = [info oo_boolForKey:DRAW_SURROUND_KEY defaultValue:ROLL_BAR_DRAW_SURROUND];
	
	if (draw_surround)
	{
		// draw ROLL surround
		SET_COLOR_SURROUND(green_color);
		hudDrawSurroundAt(x, y, z1, siz);
	}
	// draw ROLL bar
	SET_COLOR(yellow_color);
	hudDrawIndicatorAt(x, y, z1, siz, [PLAYER dialRoll]);
}


- (void) drawPitchBar:(NSDictionary *)info
{
	int					x, y;
	NSSize				siz;
	BOOL				draw_surround;
	GLfloat				alpha = overallAlpha;
	struct CachedInfo	cached;
	
	[(NSValue *)[sCurrentDrawItem objectAtIndex:WIDGET_CACHE] getValue:&cached];
	
	x = useDefined(cached.x, PITCH_BAR_CENTRE_X) + [[UNIVERSE gameView] x_offset] * cached.x0;
	y = useDefined(cached.y, PITCH_BAR_CENTRE_Y) + [[UNIVERSE gameView] y_offset] * cached.y0;
	siz.width = useDefined(cached.width, PITCH_BAR_WIDTH);
	siz.height = useDefined(cached.height, PITCH_BAR_HEIGHT);
	alpha *= cached.alpha;
	draw_surround = [info oo_boolForKey:DRAW_SURROUND_KEY defaultValue:PITCH_BAR_DRAW_SURROUND];
	
	if (draw_surround)
	{
		// draw PITCH surround
		SET_COLOR_SURROUND(green_color);
		hudDrawSurroundAt(x, y, z1, siz);
	}
	// draw PITCH bar
	SET_COLOR(yellow_color);
	hudDrawIndicatorAt(x, y, z1, siz, [PLAYER dialPitch]);
}


- (void) drawYawBar:(NSDictionary *)info
{
	int					x, y;
	NSSize				siz;
	BOOL				draw_surround;
	GLfloat				alpha = overallAlpha;
	struct CachedInfo	cached;
	
	[(NSValue *)[sCurrentDrawItem objectAtIndex:WIDGET_CACHE] getValue:&cached];
	
	// No standard YAW definitions - using PITCH ones instead.
	x = useDefined(cached.x, PITCH_BAR_CENTRE_X) + [[UNIVERSE gameView] x_offset] * cached.x0;
	y = useDefined(cached.y, PITCH_BAR_CENTRE_Y) + [[UNIVERSE gameView] y_offset] * cached.y0;
	siz.width = useDefined(cached.width, PITCH_BAR_WIDTH);
	siz.height = useDefined(cached.height, PITCH_BAR_HEIGHT);
	alpha *= cached.alpha;
	draw_surround = [info oo_boolForKey:DRAW_SURROUND_KEY defaultValue:PITCH_BAR_DRAW_SURROUND];
	
	if (draw_surround)
	{
		// draw YAW surround
		SET_COLOR_SURROUND(green_color);
		hudDrawSurroundAt(x, y, z1, siz);
	}
	// draw YAW bar
	SET_COLOR(yellow_color);
	hudDrawIndicatorAt(x, y, z1, siz, [PLAYER dialYaw]);
}


- (void) drawEnergyGauge:(NSDictionary *)info
{
	int					x, y;
	unsigned			i;
	NSSize				siz;
	BOOL				drawSurround, labelled, energyCritical = NO;
	GLfloat				alpha = overallAlpha;
	GLfloat				bankHeight, bankY;
	PlayerEntity *player = PLAYER;

	unsigned n_bars = [player dialMaxEnergy]/64.0;
	n_bars = [info oo_unsignedIntForKey:N_BARS_KEY defaultValue:n_bars];
	if (n_bars < 1)
	{
		n_bars = 1;
	}
	GLfloat				energy = [player dialEnergy] * n_bars;
	struct CachedInfo	cached;
	
	[(NSValue *)[sCurrentDrawItem objectAtIndex:WIDGET_CACHE] getValue:&cached];
	
	x = useDefined(cached.x, ENERGY_GAUGE_CENTRE_X) + [[UNIVERSE gameView] x_offset] * cached.x0;
	y = useDefined(cached.y, ENERGY_GAUGE_CENTRE_Y) + [[UNIVERSE gameView] y_offset] * cached.y0;
	siz.width = useDefined(cached.width, ENERGY_GAUGE_WIDTH);
	siz.height = useDefined(cached.height, ENERGY_GAUGE_HEIGHT);
	alpha *= cached.alpha;
	drawSurround = [info oo_boolForKey:DRAW_SURROUND_KEY defaultValue:ENERGY_GAUGE_DRAW_SURROUND];
	labelled = [info oo_boolForKey:LABELLED_KEY defaultValue:YES];
	if (n_bars > 8)  labelled = NO;
	
	// MKW - ensure we don't alert the player every time they use energy if they only have 1 energybank
	//[player setAlertFlag:ALERT_FLAG_ENERGY to:((energy < 1.0)&&([player status] == STATUS_IN_FLIGHT))];
	if(EXPECT([self checkPlayerInFlight]))
	{
		if(n_bars > 1)
		{
			energyCritical = energy < 1.0 ;
		}
		else
		{
			energyCritical = energy < 0.8;
		}
		[player setAlertFlag:ALERT_FLAG_ENERGY to:energyCritical];
	}
	
	if (drawSurround)
	{
		// draw energy surround
		SET_COLOR_SURROUND(yellow_color);
		hudDrawSurroundAt(x, y, z1, siz);
	}
	
	bankHeight = siz.height / n_bars;
	// draw energy banks	
	NSSize barSize = NSMakeSize(siz.width, bankHeight - 2.0);		// leave a gap between bars
	GLfloat midBank = bankHeight / 2.0f;
	bankY = y - (n_bars - 1) * midBank - 1.0;
	
	// avoid constant colour switching...
	if (labelled)
	{
		GLColorWithOverallAlpha(green_color, alpha);
		GLfloat labelStartX = x + 0.5f * barSize.width + 3.0f;
		NSSize labelSize = NSMakeSize(9.0, (bankHeight < 18.0)? bankHeight : 18.0);
		for (i = 0; i < n_bars; i++)
		{
			OODrawString([NSString stringWithFormat:@"E%x", n_bars - i], labelStartX, bankY - midBank, z1, labelSize);
			bankY += bankHeight;
		}
	}
	
	if (energyCritical)
	{
		SET_COLOR_LOW(red_color);
	}
	else
	{
		SET_COLOR_MEDIUM(yellow_color);
	}
	bankY = y - (n_bars - 1) * midBank;
	for (i = 0; i < n_bars; i++)
	{
		if (energy > 1.0)
		{
			hudDrawBarAt(x, bankY, z1, barSize, 1.0);
		}
		else if (energy > 0.0)
		{
			hudDrawBarAt(x, bankY, z1, barSize, energy);
		}
		
		energy -= 1.0;
		bankY += bankHeight;
	}
}


- (void) drawForwardShieldBar:(NSDictionary *)info
{
	int					x, y;
	NSSize				siz;
	BOOL				draw_surround;
	GLfloat				alpha = overallAlpha;
	GLfloat				shield = [PLAYER dialForwardShield];
	struct CachedInfo	cached;
	
	[(NSValue *)[sCurrentDrawItem objectAtIndex:WIDGET_CACHE] getValue:&cached];
	
	x = useDefined(cached.x, FORWARD_SHIELD_BAR_CENTRE_X) + [[UNIVERSE gameView] x_offset] * cached.x0;
	y = useDefined(cached.y, FORWARD_SHIELD_BAR_CENTRE_Y) + [[UNIVERSE gameView] y_offset] * cached.y0;
	siz.width = useDefined(cached.width, FORWARD_SHIELD_BAR_WIDTH);
	siz.height = useDefined(cached.height, FORWARD_SHIELD_BAR_HEIGHT);
	alpha *= cached.alpha;
	draw_surround = [info oo_boolForKey:DRAW_SURROUND_KEY defaultValue:FORWARD_SHIELD_BAR_DRAW_SURROUND];
	
	if (draw_surround)
	{
		// draw forward_shield surround
		SET_COLOR_SURROUND(green_color);
		hudDrawSurroundAt(x, y, z1, siz);
	}
	// draw forward_shield bar
	if (shield < .25)
	{
		SET_COLOR_LOW(red_color);
	}
	else if (shield < .80)
	{
		SET_COLOR_MEDIUM(yellow_color);
	} 
	else
	{
		SET_COLOR_HIGH(green_color);
	}
	hudDrawBarAt(x, y, z1, siz, shield);
}


- (void) drawAftShieldBar:(NSDictionary *)info
{
	int					x, y;
	NSSize				siz;
	BOOL				draw_surround;
	GLfloat				alpha = overallAlpha;
	GLfloat				shield = [PLAYER dialAftShield];
	struct CachedInfo	cached;
	
	[(NSValue *)[sCurrentDrawItem objectAtIndex:WIDGET_CACHE] getValue:&cached];
	
	x = useDefined(cached.x, AFT_SHIELD_BAR_CENTRE_X) + [[UNIVERSE gameView] x_offset] * cached.x0;
	y = useDefined(cached.y, AFT_SHIELD_BAR_CENTRE_Y) + [[UNIVERSE gameView] y_offset] * cached.y0;
	siz.width = useDefined(cached.width, AFT_SHIELD_BAR_WIDTH);
	siz.height = useDefined(cached.height, AFT_SHIELD_BAR_HEIGHT);
	alpha *= cached.alpha;
	draw_surround = [info oo_boolForKey:DRAW_SURROUND_KEY defaultValue:AFT_SHIELD_BAR_DRAW_SURROUND];
	
	if (draw_surround)
	{
		// draw forward_shield surround
		SET_COLOR_SURROUND(green_color);
		hudDrawSurroundAt(x, y, z1, siz);
	}
	// draw forward_shield bar
	if (shield < .25)
	{
		SET_COLOR_LOW(red_color);
	}
	else if (shield < .80)
	{
		SET_COLOR_MEDIUM(yellow_color);
	} 
	else
	{
		SET_COLOR_HIGH(green_color);
	}
	hudDrawBarAt(x, y, z1, siz, shield);
}


- (void) drawFuelBar:(NSDictionary *)info
{
	int					x, y;
	NSSize				siz;
	BOOL				draw_surround;
	float				fu, hr;
	GLfloat				alpha = overallAlpha;
	struct CachedInfo	cached;
	
	[(NSValue *)[sCurrentDrawItem objectAtIndex:WIDGET_CACHE] getValue:&cached];
	
	x = useDefined(cached.x, FUEL_BAR_CENTRE_X) + [[UNIVERSE gameView] x_offset] * cached.x0;
	y = useDefined(cached.y, FUEL_BAR_CENTRE_Y) + [[UNIVERSE gameView] y_offset] * cached.y0;
	siz.width = useDefined(cached.width, FUEL_BAR_WIDTH);
	siz.height = useDefined(cached.height, FUEL_BAR_HEIGHT);
	alpha *= cached.alpha;
	draw_surround = [info oo_boolForKey:DRAW_SURROUND_KEY defaultValue:NO];
	
	if (draw_surround)
	{
		SET_COLOR_SURROUND(green_color);
		hudDrawSurroundAt(x, y, z1, siz);
	}
	
	fu = [PLAYER dialFuel];
	hr = [PLAYER dialHyperRange];
	
	// draw fuel bar
	SET_COLOR_MEDIUM(yellow_color);
	hudDrawBarAt(x, y, z1, siz, fu);
	
	// draw range indicator
	if (hr > 0.0f && hr <= 1.0f)
	{
		if ([PLAYER hasSufficientFuelForJump])
		{
			SET_COLOR_HIGH(green_color);
		}
		else
		{
			SET_COLOR_LOW(red_color);
		}
		hudDrawMarkerAt(x, y, z1, siz, hr);
	}
}


- (void) drawCabinTempBar:(NSDictionary *)info
{
	int					x, y;
	NSSize				siz;
	BOOL				draw_surround;
	GLfloat				temp = [PLAYER hullHeatLevel];
	GLfloat				alpha = overallAlpha;
	struct CachedInfo	cached;
	
	[(NSValue *)[sCurrentDrawItem objectAtIndex:WIDGET_CACHE] getValue:&cached];
	
	x = useDefined(cached.x, CABIN_TEMP_BAR_CENTRE_X) + [[UNIVERSE gameView] x_offset] * cached.x0;
	y = useDefined(cached.y, CABIN_TEMP_BAR_CENTRE_Y) + [[UNIVERSE gameView] y_offset] * cached.y0;
	siz.width = useDefined(cached.width, CABIN_TEMP_BAR_WIDTH);
	siz.height = useDefined(cached.height, CABIN_TEMP_BAR_HEIGHT);
	alpha *= cached.alpha;
	draw_surround = [info oo_boolForKey:DRAW_SURROUND_KEY defaultValue:NO];
	
	if (draw_surround)
	{
		SET_COLOR_SURROUND(green_color);
		hudDrawSurroundAt(x, y, z1, siz);
	}
	
	int flash = (int)([UNIVERSE getTime] * 4);
	flash &= 1;
	// what color are we?
	if (temp > .80)
	{
		if (temp > .90 && flash)
			SET_COLOR_CRITICAL(redplus_color);
		else
			SET_COLOR_HIGH(red_color);
	}
	else
	{
		if (temp > .25)
			SET_COLOR_MEDIUM(yellow_color);
		else
			SET_COLOR_LOW(green_color);
	}

	[PLAYER setAlertFlag:ALERT_FLAG_TEMP to:((temp > .90)&&([self checkPlayerInFlight]))];
	hudDrawBarAt(x, y, z1, siz, temp);
}


- (void) drawWeaponTempBar:(NSDictionary *)info
{
	int					x, y;
	NSSize				siz;
	BOOL				draw_surround;
	GLfloat				temp = [PLAYER laserHeatLevel];
	GLfloat				alpha = overallAlpha;
	struct CachedInfo	cached;
	
	[(NSValue *)[sCurrentDrawItem objectAtIndex:WIDGET_CACHE] getValue:&cached];
	
	x = useDefined(cached.x, WEAPON_TEMP_BAR_CENTRE_X) + [[UNIVERSE gameView] x_offset] * cached.x0;
	y = useDefined(cached.y, WEAPON_TEMP_BAR_CENTRE_Y) + [[UNIVERSE gameView] y_offset] * cached.y0;
	siz.width = useDefined(cached.width, WEAPON_TEMP_BAR_WIDTH);
	siz.height = useDefined(cached.height, WEAPON_TEMP_BAR_HEIGHT);
	alpha *= cached.alpha;
	draw_surround = [info oo_boolForKey:DRAW_SURROUND_KEY defaultValue:NO];
	
	if (draw_surround)
	{
		SET_COLOR_SURROUND(green_color);
		hudDrawSurroundAt(x, y, z1, siz);
	}
	
	// draw weapon_temp bar (only need to call GLColor() once!)
	if (temp > .80)
		SET_COLOR_HIGH(red_color);
	else if (temp > .25)
		SET_COLOR_MEDIUM(yellow_color);
	else
		SET_COLOR_LOW(green_color);
	hudDrawBarAt(x, y, z1, siz, temp);
}


- (void) drawAltitudeBar:(NSDictionary *)info
{
	int					x, y;
	NSSize				siz;
	BOOL				draw_surround;
	GLfloat				alt = [PLAYER dialAltitude];
	GLfloat				alpha = overallAlpha;
	struct CachedInfo	cached;
	
	[(NSValue *)[sCurrentDrawItem objectAtIndex:WIDGET_CACHE] getValue:&cached];
	
	x = useDefined(cached.x, ALTITUDE_BAR_CENTRE_X) + [[UNIVERSE gameView] x_offset] * cached.x0;
	y = useDefined(cached.y, ALTITUDE_BAR_CENTRE_Y) + [[UNIVERSE gameView] y_offset] * cached.y0;
	siz.width = useDefined(cached.width, ALTITUDE_BAR_WIDTH);
	siz.height = useDefined(cached.height, ALTITUDE_BAR_HEIGHT);
	alpha *= cached.alpha;
	draw_surround = [info oo_boolForKey:DRAW_SURROUND_KEY defaultValue:NO];
	
	if (draw_surround)
	{
		SET_COLOR_SURROUND(yellow_color);
		hudDrawSurroundAt(x, y, z1, siz);
	}
	
	int flash = (int)([UNIVERSE getTime] * 4);
	flash &= 1;
	
	// draw altitude bar (evaluating the least amount of ifs per go)
	if (alt < .25)
	{
		if (alt < .10 && flash)
			SET_COLOR_CRITICAL(redplus_color);
		else
			SET_COLOR_HIGH(red_color);
	}
	else
	{
		if (alt < .75)
			SET_COLOR_MEDIUM(yellow_color);
		else
			SET_COLOR_LOW(green_color);
	}
	
	hudDrawBarAt(x, y, z1, siz, alt);
	
	[PLAYER setAlertFlag:ALERT_FLAG_ALT to:((alt < .10)&&([self checkPlayerInFlight]))];
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
	int					x, y, sp;
	NSSize				siz;
	GLfloat				alpha = overallAlpha;
	struct CachedInfo	cached;
	
	[(NSValue *)[sCurrentDrawItem objectAtIndex:WIDGET_CACHE] getValue:&cached];
	
	x = useDefined(cached.x, MISSILES_DISPLAY_X) + [[UNIVERSE gameView] x_offset] * cached.x0;
	y = useDefined(cached.y, MISSILES_DISPLAY_Y) + [[UNIVERSE gameView] y_offset] * cached.y0;
	siz.width = useDefined(cached.width, MISSILE_ICON_WIDTH);
	siz.height = useDefined(cached.height, MISSILE_ICON_HEIGHT);
	alpha *= cached.alpha;
	sp = [info oo_unsignedIntForKey:SPACING_KEY defaultValue:MISSILES_DISPLAY_SPACING];
	
	BOOL weaponsOnline = [PLAYER weaponsOnline];
	if (!weaponsOnline)  alpha *= 0.2f;	// darken missile display if weapons are offline
	
	if (![PLAYER dialIdentEngaged])
	{
		OOMissileStatus status = [PLAYER dialMissileStatus];
		NSUInteger i, n_mis = [PLAYER dialMaxMissiles];
		for (i = 0; i < n_mis; i++)
		{
			ShipEntity *missile = [PLAYER missileForPylon:i];
			if (missile)
			{
				[self drawIconForMissile:missile
								selected:weaponsOnline && i == [PLAYER activeMissile]
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
		switch ([PLAYER dialMissileStatus])
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
		OODrawString([PLAYER dialTargetName], x + sp, y - 1, z1, NSMakeSize(siz.width, siz.height));
	}
	
}


- (void) drawTargetReticle:(NSDictionary *)info
{
	GLfloat alpha = [info oo_nonNegativeFloatForKey:ALPHA_KEY defaultValue:1.0f] * overallAlpha;
	
	if ([PLAYER primaryTarget] != nil)
	{
		hudDrawReticleOnTarget([PLAYER primaryTarget], PLAYER, z1, alpha, reticleTargetSensitive, propertiesReticleTargetSensitive, NO, YES, info);
		[self drawDirectionCue:info];
	}
	// extra feature if extra equipment installed
	if ([PLAYER hasEquipmentItem:@"EQ_INTEGRATED_TARGETING_SYSTEM"])
	{
		[self drawSecondaryTargetReticle:info];
	}
}


- (void) drawSecondaryTargetReticle:(NSDictionary *)info
{
	GLfloat alpha = [info oo_nonNegativeFloatForKey:ALPHA_KEY defaultValue:1.0f] * overallAlpha * 0.4;
	
	PlayerEntity *player = PLAYER;
	if ([player hasEquipmentItem:@"EQ_TARGET_MEMORY"])
	{
		// needs target memory to be working in addition to any other equipment
		// this item may be bound to
		NSMutableArray *targetMemory = [player targetMemory];
		ShipEntity *primary = [player primaryTarget];
		for (unsigned i = 0; i < PLAYER_TARGET_MEMORY_SIZE; i++)
		{
			id sec_id = [targetMemory objectAtIndex:i];
			// isProxy = weakref ; not = NSNull (in this case...)
			// can't use isKindOfClass because that throws
			// NSInvalidArgumentException when called on a weakref
			// with a dropped object.
			// TODO: fix OOWeakReference so isKindOfClass works
			if (sec_id != nil && [sec_id isProxy])
			{
				ShipEntity *secondary = [(OOWeakReference *)sec_id weakRefUnderlyingObject];
				if (secondary != nil && secondary != primary)
				{
					if ([secondary zeroDistance] <= SCANNER_MAX_RANGE2 && [secondary isInSpace])
					{
						hudDrawReticleOnTarget(secondary, PLAYER, z1, alpha, NO, nil, YES, NO, info);	
					}			
				}
			}
		}
	}
}


- (void) drawWaypoints:(NSDictionary *)info
{
	GLfloat alpha = [info oo_nonNegativeFloatForKey:ALPHA_KEY defaultValue:1.0f] * overallAlpha;
	GLfloat scale = [info oo_floatForKey:@"reticle_scale" defaultValue:ONE_SIXTYFOURTH];

	NSEnumerator *waypoints = [[UNIVERSE currentWaypoints] objectEnumerator];
	OOWaypointEntity *waypoint = nil;
	Entity *compass = [PLAYER compassTarget];
	
	while ((waypoint = [waypoints nextObject]))
	{
		hudDrawWaypoint(waypoint, PLAYER, z1, alpha, waypoint==compass, scale);
	}

}


- (void) drawStatusLight:(NSDictionary *)info
{
	int					x, y;
	NSSize				siz;
	GLfloat				alpha = overallAlpha;
	BOOL				blueAlert = cloakIndicatorOnStatusLight && [PLAYER isCloaked];
	struct CachedInfo	cached;
	
	[(NSValue *)[sCurrentDrawItem objectAtIndex:WIDGET_CACHE] getValue:&cached];
	
	x = useDefined(cached.x, STATUS_LIGHT_CENTRE_X) + [[UNIVERSE gameView] x_offset] * cached.x0;
	y = useDefined(cached.y, STATUS_LIGHT_CENTRE_Y) + [[UNIVERSE gameView] y_offset] * cached.y0;
	siz.width = useDefined(cached.width, STATUS_LIGHT_HEIGHT);
	siz.height = useDefined(cached.height, STATUS_LIGHT_HEIGHT);
	alpha *= cached.alpha;
	
	GLfloat status_color[4] = { 0.25, 0.25, 0.25, 1.0};
	int alertCondition = [PLAYER alertCondition];
	GLfloat flash_alpha = 0.333 * (2.0f + sin((GLfloat)[UNIVERSE getTime] * 2.5f * alertCondition));
	
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
	GLfloat				alpha = overallAlpha;
	struct CachedInfo	cached;
	
	[(NSValue *)[sCurrentDrawItem objectAtIndex:WIDGET_CACHE] getValue:&cached];
	
	alpha *= cached.alpha;
	
	if ([UNIVERSE displayGUI])  return;
	
	GLfloat		clear_color[4] = {0.0f, 1.0f, 0.0f, 0.0f};
	Entity		*target = [PLAYER primaryTarget];
	if (target == nil)  return;
	
	// draw the direction cue
	OOMatrix	rotMatrix;
	
	rotMatrix = [PLAYER rotationMatrix];
	
	if ([UNIVERSE viewDirection] != VIEW_GUI_DISPLAY)
	{
		const GLfloat innerSize = CROSSHAIR_SIZE;
		const GLfloat width = CROSSHAIR_SIZE * ONE_EIGHTH;
		const GLfloat outerSize = CROSSHAIR_SIZE * (1.0f + ONE_EIGHTH + ONE_EIGHTH);
		const float visMin = 0.994521895368273f;	// cos(6 degrees)
		const float visMax = 0.984807753012208f;	// cos(10 degrees)
		
		// Transform the view
		Vector rpn = [PLAYER vectorTo:target];
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
	int					x, y;
	NSSize				siz;
	GLfloat				itemColor[4] = { 0.0f, 1.0f, 0.0f, 1.0f };
	struct CachedInfo	cached;
	
	[(NSValue *)[sCurrentDrawItem objectAtIndex:WIDGET_CACHE] getValue:&cached];
	
	x = useDefined(cached.x, CLOCK_DISPLAY_X) + [[UNIVERSE gameView] x_offset] * cached.x0;
	y = useDefined(cached.y, CLOCK_DISPLAY_Y) + [[UNIVERSE gameView] y_offset] * cached.y0;
	siz.width = useDefined(cached.width, CLOCK_DISPLAY_WIDTH);
	siz.height = useDefined(cached.height, CLOCK_DISPLAY_HEIGHT);
	
	GetRGBAArrayFromInfo(info, itemColor);
	itemColor[3] *= overallAlpha;
	
	OOGL(glColor4f(itemColor[0], itemColor[1], itemColor[2], itemColor[3]));
	OODrawString([PLAYER dial_clock], x, y, z1, siz);
}


- (void) drawPrimedEquipment:(NSDictionary *)info
{
	if ([PLAYER status] == STATUS_DOCKED)
	{
		// Can't activate equipment while docked
		return;
	}
	
	GLfloat				itemColor[4] = { 0.0f, 1.0f, 0.0f, 1.0f };
	struct CachedInfo	cached;
	
	NSUInteger lines = [info oo_intForKey:@"n_bars" defaultValue:1];
	NSInteger pec = (NSInteger)[PLAYER primedEquipmentCount];

	[(NSValue *)[sCurrentDrawItem objectAtIndex:WIDGET_CACHE] getValue:&cached];
	
	NSInteger x = useDefined(cached.x, PRIMED_DISPLAY_X) + [[UNIVERSE gameView] x_offset] * cached.x0;
	NSInteger y = useDefined(cached.y, PRIMED_DISPLAY_Y) + [[UNIVERSE gameView] y_offset] * cached.y0;
	
	NSSize size =
	{
		.width = useDefined(cached.width, PRIMED_DISPLAY_WIDTH),
		.height = useDefined(cached.height, PRIMED_DISPLAY_HEIGHT)
	};

	if (pec == 0)
	{
		// Don't display if no primed equipment fitted
		return;
	}

	GetRGBAArrayFromInfo(info, itemColor);
	itemColor[3] *= overallAlpha;

	if (lines == 1)
	{
		OOGL(glColor4f(itemColor[0], itemColor[1], itemColor[2], itemColor[3]));
		OODrawString([NSString stringWithFormat:DESC(@"equipment-primed-hud-@"), [PLAYER primedEquipmentName:0]], x, y, z1, size);
	}
	else
	{
		NSInteger negative = (lines % 2) ? (lines - 1) / 2 : lines / 2;
		NSInteger positive = lines / 2;
		for (NSInteger i = -negative; i <= positive; i++)
		{
			if (i >= -(pec) / 2 && i <= (pec + 1) / 2)
			{
				// don't display loops if we have more equipment than lines
				// instead compact the display towards its centre
				GLfloat alphaScale = 1.0/((i<0)?(1.0-i):(1.0+i));
				OOGL(glColor4f(itemColor[0], itemColor[1], itemColor[2], itemColor[3]*alphaScale));
				OODrawString([PLAYER primedEquipmentName:i], x, y, z1, size);
			}
			y -= size.height;
		}	
	}
}


- (void) drawASCTarget:(NSDictionary *)info
{
	if ([PLAYER status] == STATUS_DOCKED || [PLAYER compassMode] != COMPASS_MODE_BEACONS)
	{
		// Can't have compass target when docked, and only needed in beacon mode
		return;
	}
	
	GLfloat				itemColor[4] = { 0.0f, 0.0f, 1.0f, 1.0f };
	struct CachedInfo	cached;
	
	[(NSValue *)[sCurrentDrawItem objectAtIndex:WIDGET_CACHE] getValue:&cached];

	NSInteger x = useDefined(cached.x, ASCTARGET_DISPLAY_X) + [[UNIVERSE gameView] x_offset] * cached.x0;
	NSInteger y = useDefined(cached.y, ASCTARGET_DISPLAY_Y) + [[UNIVERSE gameView] y_offset] * cached.y0;
	
	NSSize size =
	{
		.width = useDefined(cached.width, ASCTARGET_DISPLAY_WIDTH),
		.height = useDefined(cached.height, ASCTARGET_DISPLAY_HEIGHT)
	};

	GetRGBAArrayFromInfo(info, itemColor);
	itemColor[3] *= overallAlpha;

	OOGL(glColor4f(itemColor[0], itemColor[1], itemColor[2], itemColor[3]));
	if ([info oo_intForKey:@"align"] == 1)
	{
		OODrawStringAligned([PLAYER compassTargetLabel], x, y, z1, size,YES);
	}
	else
	{
		OODrawStringAligned([PLAYER compassTargetLabel], x, y, z1, size,NO);
	}
	
}


- (void) drawWeaponsOfflineText:(NSDictionary *)info
{
	OOViewID					viewID = [UNIVERSE viewDirection];

	if (viewID == VIEW_CUSTOM ||
		overallAlpha == 0.0f ||
		!([PLAYER status] == STATUS_IN_FLIGHT || [PLAYER status] == STATUS_WITCHSPACE_COUNTDOWN) ||
		[UNIVERSE displayGUI]
		)
	{
		// Don't draw weapons offline text
		return;
	}

	if (![PLAYER weaponsOnline])
	{
		int					x, y;
		NSSize				siz;
		GLfloat				alpha = overallAlpha;
		struct CachedInfo	cached;
	
		[(NSValue *)[sCurrentDrawItem objectAtIndex:WIDGET_CACHE] getValue:&cached];
		
		x = useDefined(cached.x, WEAPONSOFFLINETEXT_DISPLAY_X) + [[UNIVERSE gameView] x_offset] * cached.x0;
		y = useDefined(cached.y, WEAPONSOFFLINETEXT_DISPLAY_Y) + [[UNIVERSE gameView] y_offset] * cached.y0;
		siz.width = useDefined(cached.width, WEAPONSOFFLINETEXT_WIDTH);
		siz.height = useDefined(cached.height, WEAPONSOFFLINETEXT_HEIGHT);
		alpha *= cached.alpha;
		
		GLColorWithOverallAlpha(green_color, alpha);
		// TODO: some caching required...
		OODrawString(DESC(@"weapons-systems-offline"), x, y, z1, siz);
	}
}


- (void) drawFPSInfoCounter:(NSDictionary *)info
{
	if (![UNIVERSE displayFPS])  return;
	
	int					x, y;
	NSSize				siz;
	struct CachedInfo	cached;
	
	[(NSValue *)[sCurrentDrawItem objectAtIndex:WIDGET_CACHE] getValue:&cached];
	
	x = useDefined(cached.x, FPSINFO_DISPLAY_X) + [[UNIVERSE gameView] x_offset] * cached.x0;
	y = useDefined(cached.y, FPSINFO_DISPLAY_Y) + [[UNIVERSE gameView] y_offset] * cached.y0;
	siz.width = useDefined(cached.width, FPSINFO_DISPLAY_WIDTH);
	siz.height = useDefined(cached.height, FPSINFO_DISPLAY_HEIGHT);
	
	HPVector playerPos = [PLAYER position];
	NSString *positionInfo = [UNIVERSE expressPosition:playerPos inCoordinateSystem:@"pwm"];
	positionInfo = [NSString stringWithFormat:@"abs %.2f %.2f %.2f / %@", playerPos.x, playerPos.y, playerPos.z, positionInfo];
	
	// We would normally set a variable alpha value here, but in this case we don't.
	// We prefer the FPS counter to be always visible - Nikos 20100405
	OOGL(glColor4f(0.0, 1.0, 0.0, 1.0));
	OODrawString([PLAYER dial_fpsinfo], x, y, z1, siz);
	
#ifndef NDEBUG
	NSSize siz08 = NSMakeSize(0.8 * siz.width, 0.8 * siz.width);
	NSString *collDebugInfo = [NSString stringWithFormat:@"%@ - %@", [PLAYER dial_objinfo], [UNIVERSE collisionDescription]];
	OODrawString(collDebugInfo, x, y - siz.height, z1, siz);
	
	OODrawString(positionInfo, x, y - 1.8 * siz.height, z1, siz08);
	
	NSString *timeAccelerationFactorInfo = [NSString stringWithFormat:@"TAF: %@%.2f", DESC(@"multiplication-sign"), [UNIVERSE timeAccelerationFactor]];
	OODrawString(timeAccelerationFactorInfo, x, y - 3.2 * siz08.height, z1, siz08);
#endif
}


- (void) drawScoopStatus:(NSDictionary *)info
{
	int					i, x, y;
	NSSize				siz;
	GLfloat				alpha;
	struct CachedInfo	cached;
	
	[(NSValue *)[sCurrentDrawItem objectAtIndex:WIDGET_CACHE] getValue:&cached];
	
	x = useDefined(cached.x, SCOOPSTATUS_CENTRE_X) + [[UNIVERSE gameView] x_offset] * cached.x0;
	y = useDefined(cached.y, SCOOPSTATUS_CENTRE_Y) + [[UNIVERSE gameView] y_offset] * cached.y0;
	siz.width = useDefined(cached.width, SCOOPSTATUS_WIDTH);
	siz.height = useDefined(cached.height, SCOOPSTATUS_HEIGHT);
	// default alpha value different from all others, won't use cached.alpha
	alpha = [info oo_nonNegativeFloatForKey:ALPHA_KEY defaultValue:0.75f];
	
	const GLfloat* s0_color = red_color;
	GLfloat	s1c[4] = { 0.0f, 0.0f, 0.0f, 0.0f };
	GLfloat	s2c[4] = { 0.0f, 0.0f, 0.0f, 0.0f };
	GLfloat	s3c[4] = { 0.0f, 0.0f, 0.0f, 0.0f };
	int scoop_status = [PLAYER dialFuelScoopStatus];
	GLfloat t = [UNIVERSE getTime];
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
	GLfloat				x, y;
	NSSize				siz;
	GLfloat				alpha = overallAlpha;
	BOOL				mouse = [PLAYER isMouseControlOn];
	OOJoystickManager	*stickHandler = [OOJoystickManager sharedStickHandler];
	struct CachedInfo	cached;
	
	if (![stickHandler joystickCount])
	{
		return; // no need to draw if no joystick fitted
	}

	[(NSValue *)[sCurrentDrawItem objectAtIndex:WIDGET_CACHE] getValue:&cached];
	
	x = useDefined(cached.x, STATUS_LIGHT_CENTRE_X) + [[UNIVERSE gameView] x_offset] * cached.x0;
	y = useDefined(cached.y, STATUS_LIGHT_CENTRE_Y) + [[UNIVERSE gameView] y_offset] * cached.y0;
	siz.width = useDefined(cached.width, STATUS_LIGHT_HEIGHT);
	siz.height = useDefined(cached.height, STATUS_LIGHT_HEIGHT);
	alpha *= cached.alpha;
	
	GLfloat div = [stickHandler getSensitivity];
	
	GLColorWithOverallAlpha(black_color, alpha / 4);
	GLDrawFilledOval(x, y, z1, siz, 10);
	
	GLColorWithOverallAlpha((div < 1.0 || mouse) ? lightgray_color : green_color, alpha);
	OOGL(GLScaledLineWidth(_crosshairWidth * lineWidth));
	
	if (div >= 1.0)
	{
		if (!mouse)
		{
			NSSize siz8th = { siz.width / 8, siz.height / 8 };
			GLDrawFilledOval(x, y, z1, siz8th, 30);
			
			if (div == 1.0) // normal mode
				GLColorWithOverallAlpha(lightgray_color, alpha);
		}
		
		siz.width -= _crosshairWidth * lineWidth / 2;
		siz.height -= _crosshairWidth * lineWidth / 2;
		GLDrawOval(x, y, z1, siz, 10);
	}
	else if (div < 1.0) // insensitive mode (shouldn't happen)
		GLDrawFilledOval(x, y, z1, siz, 10);

	OOGL(GLScaledLineWidth(lineWidth)); // reset
}


- (void) drawSurround:(NSDictionary *)info color:(const GLfloat[4])color
{
	NSInteger			x, y;
	NSSize				siz;
	GLfloat				alpha = overallAlpha;
	struct CachedInfo	cached;
	
	[(NSValue *)[sCurrentDrawItem objectAtIndex:WIDGET_CACHE] getValue:&cached];
	
	if (cached.x == NOT_DEFINED || cached.y == NOT_DEFINED || cached.width == NOT_DEFINED || cached.height == NOT_DEFINED)
	{
		return;
	}
		
	x = cached.x + [[UNIVERSE gameView] x_offset] * cached.x0;
	y = cached.y + [[UNIVERSE gameView] y_offset] * cached.y0;
	siz.width = useDefined(cached.width, WEAPONSOFFLINETEXT_WIDTH);
	siz.height = useDefined(cached.height, WEAPONSOFFLINETEXT_HEIGHT);
	alpha *= cached.alpha;
	
	// draw the surround
	GLColorWithOverallAlpha(color, alpha);
	hudDrawSurroundAt(x, y, z1, siz);
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
	OOTrumble** trumbles = [PLAYER trumbleArray];
	NSUInteger i;
	for (i = [PLAYER trumbleCount]; i > 0; i--)
	{
		OOTrumble* trum = trumbles[i - 1];
		[trum drawTrumble: z1];
	}
}


- (void) drawMultiFunctionDisplay:(NSDictionary *)info withText:(NSString *)text asIndex:(NSUInteger)index
{
	PlayerEntity		*player1 = PLAYER;
	struct CachedInfo	cached;
	NSInteger			i, x, y;
	NSSize				siz, tmpsiz;
	if ([player1 guiScreen] != GUI_SCREEN_MAIN)	// don't draw on text screens
	{
		return;
	}
	GLfloat alpha = [info oo_nonNegativeFloatForKey:ALPHA_KEY defaultValue:1.0f] * overallAlpha;
	
	// TODO: reduce alpha for non-selected MFDs
	GLfloat mfd_color[4] =		{0.0, 1.0, 0.0, 0.9*alpha};
	if (index != [player1 activeMFD])
	{
		mfd_color[3] *= 0.75;
	}
	[self drawSurround:info color:mfd_color];

	[(NSValue *)[sCurrentDrawItem objectAtIndex:WIDGET_CACHE] getValue:&cached];
	x = cached.x + [[UNIVERSE gameView] x_offset] * cached.x0;
	y = cached.y + [[UNIVERSE gameView] y_offset] * cached.y0;
	
	siz.width = useDefined(cached.width / 15, MFD_TEXT_WIDTH);
	siz.height = useDefined(cached.height / 10, MFD_TEXT_HEIGHT);

	GLfloat x0 = (GLfloat)(x - cached.width/2);
	GLfloat y0 = (GLfloat)(y + cached.height/2);
	GLfloat x1 = (GLfloat)(x + cached.width/2);
	GLfloat y1 = (GLfloat)(y - cached.height/2);
	GLColorWithOverallAlpha(mfd_color, alpha*0.3);
	OOGLBEGIN(GL_QUADS);
		glVertex3f(x0-2,y0+2,z1);
		glVertex3f(x0-2,y1-2,z1);
		glVertex3f(x1+2,y1-2,z1);
		glVertex3f(x1+2,y0+2,z1);
	OOGLEND();

	NSString *line = nil;
	NSArray *lines = [text componentsSeparatedByString:@"\n"];
	// text at full opacity
	GLColorWithOverallAlpha(mfd_color, alpha);
	for (i = 0; i < 10 ; i++)
	{
		line = [lines oo_stringAtIndex:i defaultValue:nil];
		if (line != nil)
		{
			y0 -= siz.height;
			// all lines should be shorter than the size of the MFD
			GLfloat textwidth = OORectFromString(line, 0.0f, 0.0f, siz).size.width;
			if (textwidth <= cached.width)
			{
				OODrawString(line, x0, y0, z1, siz);
			}
			else
			{
				// compress it so it fits
				tmpsiz.height = siz.height;
				tmpsiz.width = siz.width * cached.width / textwidth;
				OODrawString(line, x0, y0, z1, tmpsiz);
			}
		}
		else
		{
			break;
		}
	}
}

//---------------------------------------------------------------------//

static void hudDrawIndicatorAt(GLfloat x, GLfloat y, GLfloat z, NSSize siz, GLfloat amount)
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


static void hudDrawMarkerAt(GLfloat x, GLfloat y, GLfloat z, NSSize siz, GLfloat amount)
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


static void hudDrawBarAt(GLfloat x, GLfloat y, GLfloat z, NSSize siz, GLfloat amount)
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


static void hudDrawReticleOnTarget(Entity *target, PlayerEntity *player1, GLfloat z1, GLfloat alpha, BOOL reticleTargetSensitive, NSMutableDictionary *propertiesReticleTargetSensitive, BOOL colourFromScannerColour, BOOL showText, NSDictionary *info)
{
	ShipEntity		*target_ship = nil;
	NSString		*legal_desc = nil;
	
	GLfloat			scale = [info oo_floatForKey:@"reticle_scale" defaultValue:ONE_SIXTYFOURTH];

	if (target == nil || player1 == nil)  return;

	if ([target isShip])
	{
		target_ship = (ShipEntity *)target;
	}

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
	
	Vector			p1;
	
	// by definition close enough that single precision is fine
	p1 = HPVectorToVector(HPvector_subtract([target position], [player1 viewpointPosition]));
	
	GLfloat			rdist = magnitude(p1);
	GLfloat			rsize = [target collisionRadius];
	
	if (rsize < rdist * scale)
		rsize = rdist * scale;
	
	GLfloat			rs0 = rsize;
	GLfloat			rs2 = rsize * 0.50;
	
	hudRotateViewpointForVirtualDepth(player1,p1);

	// draw the reticle
	float range = sqrt(target->zero_distance) - target->collision_radius;
	
	int flash = (int)([UNIVERSE getTime] * 4);
	flash &= 1;

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
		
		if (propertiesReticleTargetSensitive != nil)
		{
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
		}
		
		// If reticle is target sensitive, draw target box in red 
		// when target passes through laser hit-point(with decreasing accuracy) 
		// and is within hit-range.
		//
		// NOTE: The following condition also considers (indirectly) the player's weapon range.
		//       'isTargeted' is initialised to FALSE. Only if target is within the player's weapon range,
		//       it might change value. Therefore, it is not necessary to add '&& range < [player1 weaponRange]'
		//       to the following condition.
		if (colourFromScannerColour)
		{
			if ([target isShip])
			{
				ShipEntity *ship = (ShipEntity *)target;
				BOOL isHostile = (([ship hasHostileTarget])&&([ship primaryTarget] == PLAYER));
				GLColorWithOverallAlpha([ship scannerDisplayColorForShip:PLAYER :isHostile :flash :[ship scannerDisplayColor1] :[ship scannerDisplayColor2]],alpha);
			}
			else if ([target isVisualEffect])
			{
				OOVisualEffectEntity *vis = (OOVisualEffectEntity *)target;
				GLColorWithOverallAlpha([vis scannerDisplayColorForShip:flash :[vis scannerDisplayColor1] :[vis scannerDisplayColor2]],alpha);
			}
			else
			{
				GLColorWithOverallAlpha(green_color, alpha);
			}
		}
		else
		{
			if (reticleTargetSensitive && isTargeted)
			{
				GLColorWithOverallAlpha(red_color, alpha);
			}
			else
			{
				GLColorWithOverallAlpha(green_color, alpha);
			}
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
	
	if (showText)
	{
		// add text for reticle here
		range *= 0.001f;
		if (range < 0.001f) range = 0.0f;	// avoids the occasional -0.001 km distance.
		NSSize textsize = NSMakeSize(rdist * scale, rdist * scale);
		float line_height = rdist * scale;
		NSString*	infoline = [NSString stringWithFormat:@"%0.3f km", range];
		if (legal_desc != nil) infoline = [NSString stringWithFormat:@"%@ (%@)", infoline, legal_desc];
		// no need to set colour here
		OODrawString([player1 dialTargetName], rs0, 0.5 * rs2, 0, textsize);
		OODrawString(infoline, rs0, 0.5 * rs2 - line_height, 0, textsize);
	
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
				OOTimeDelta timeForCollapsing = [(WormholeEntity *)target expiryTime] - [player1 clockTimeAdjusted];
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
	}
	
	OOGL(glPopMatrix());
}


static void hudDrawWaypoint(OOWaypointEntity *waypoint, PlayerEntity *player1, GLfloat z1, GLfloat alpha, BOOL selected, GLfloat scale)
{
	if ([player1 guiScreen] != GUI_SCREEN_MAIN)	// don't draw on text screens
	{
		return;
	}

	Vector	p1 = HPVectorToVector(HPvector_subtract([waypoint position], [player1 viewpointPosition]));

	hudRotateViewpointForVirtualDepth(player1,p1);
	
	// either close enough that single precision is fine or far enough
	// away that precision is irrelevant
	
	GLfloat	rdist = magnitude(p1);
	GLfloat	rsize = rdist * scale;
	
	GLfloat	rs0 = rsize;
	GLfloat	rs2 = rsize * 0.50;

	if (selected)
	{
		GLColorWithOverallAlpha(blue_color, alpha);
	}
	else
	{
		GLColorWithOverallAlpha(blue_color, alpha*0.25);
	}

	OOGLBEGIN(GL_LINES);
		glVertex2f(rs0,rs2);	glVertex2f(rs2,rs2);
		glVertex2f(rs2,rs0);	glVertex2f(rs2,rs2);

		glVertex2f(-rs0,rs2);	glVertex2f(-rs2,rs2);
		glVertex2f(-rs2,rs0);	glVertex2f(-rs2,rs2);

		glVertex2f(-rs0,-rs2);	glVertex2f(-rs2,-rs2);
		glVertex2f(-rs2,-rs0);	glVertex2f(-rs2,-rs2);

		glVertex2f(rs0,-rs2);	glVertex2f(rs2,-rs2);
		glVertex2f(rs2,-rs0);	glVertex2f(rs2,-rs2);

//		glVertex2f(0,-rs2);	glVertex2f(0,rs2);
//		glVertex2f(rs2,0);	glVertex2f(-rs2,0);
	OOGLEND();
	
	if (selected)
	{
		GLfloat range = HPdistance([player1 position],[waypoint position]) * 0.001f;
		if (range < 0.001f) range = 0.0f;	// avoids the occasional -0.001 km distance.
		NSSize textsize = NSMakeSize(rdist * scale, rdist * scale);
		float line_height = rdist * scale;
		NSString*	infoline = [NSString stringWithFormat:@"%0.3f km", range];
		OODrawString(infoline, rs0 * 0.5, -rs2 - line_height, 0, textsize);
	}

	OOGL(glPopMatrix());
}

static void hudRotateViewpointForVirtualDepth(PlayerEntity * player1, Vector p1)
{
	OOMatrix		back_mat;
	Quaternion		back_q = [player1 orientation];
	back_q.w = -back_q.w;   // invert
	Vector			v1 = vector_up_from_quaternion(back_q);

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
	// draw the waypoint

}


static void InitTextEngine(void)
{
	NSDictionary			*fontSpec = nil;
	NSArray					*widths = nil;
	NSString				*texName = nil;
	NSUInteger				i, count;
	
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


static GLfloat drawCharacterQuad(uint8_t chr, GLfloat x, GLfloat y, GLfloat z, NSSize siz)
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


NSRect OORectFromString(NSString *text, GLfloat x, GLfloat y, NSSize siz)
{
	GLfloat				w = 0;
	NSData				*data = nil;
	const uint8_t		*bytes = NULL;
	NSUInteger			i, length;
	
	data = [sEncodingCoverter convertString:text];
	bytes = [data bytes];
	length = [data length];
	
	for (i = 0; i < length; i++)
	{
		w += siz.width * sGlyphWidths[bytes[i]];
	}
	
	return NSMakeRect(x, y, w, siz.height);
}


CGFloat OOStringWidthInEm(NSString *text)
{
	return OORectFromString(text, 0, 0, NSMakeSize(1.0 / (GLYPH_SCALE_FACTOR * 8.0), 1.0)).size.width;
}


void drawHighlight(GLfloat x, GLfloat y, GLfloat z, NSSize siz, GLfloat alpha)
{
	// Rounded corners, fading 'shadow' version
	OOGL(glColor4f(0.0f, 0.0f, 0.0f, alpha * 0.4f));	// dark translucent shadow
	
	OOGLBEGIN(GL_POLYGON);
		// thin 'halo' around the 'solid' highlight
		glVertex3f(x + 1.0f , y + siz.height + 2.5f, z);
		glVertex3f(x + siz.width + 3.0f, y + siz.height + 2.5f, z);
		glVertex3f(x + siz.width + 4.5f, y + siz.height + 1.0f, z);
		glVertex3f(x + siz.width + 4.5f, y + 3.0f, z);
		glVertex3f(x + siz.width + 3.0f, y + 1.5f, z);
		glVertex3f(x + 1.0f, y + 1.5f, z);
		glVertex3f(x - 0.5f, y + 3.0f, z);
		glVertex3f(x - 0.5f, y + siz.height + 1.0f, z);
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


void OODrawString(NSString *text, GLfloat x, GLfloat y, GLfloat z, NSSize siz)
{
	OODrawStringAligned(text,x,y,z,siz,NO);
}


void OODrawStringAligned(NSString *text, GLfloat x, GLfloat y, GLfloat z, NSSize siz, BOOL rightAlign)
{
	GLfloat			cx = x;
	NSInteger		i, length;
	NSData			*data = nil;
	const uint8_t	*bytes = NULL;
	
	OOSetOpenGLState(OPENGL_STATE_OVERLAY);
	
	OOGL(glEnable(GL_TEXTURE_2D));
	[sFontTexture apply];
	
	data = [sEncodingCoverter convertString:text];
	length = [data length];
	bytes = [data bytes];

	if (EXPECT_NOT(rightAlign))
	{
		cx -= OORectFromString(text, 0.0f, 0.0f, siz).size.width;
	}
	
	OOGLBEGIN(GL_QUADS);
	for (i = 0; i < length; i++)
	{
		cx += drawCharacterQuad(bytes[i], cx, y, z, siz);
	}
	OOGLEND();
	
	[OOTexture applyNone];
	OOGL(glDisable(GL_TEXTURE_2D));
	
	OOVerifyOpenGLState();
}


void OODrawHilightedString(NSString *text, GLfloat x, GLfloat y, GLfloat z, NSSize siz)
{
	GLfloat color[4];
	
	// get the physical dimensions of the string
	NSSize strsize = OORectFromString(text, 0.0f, 0.0f, siz).size;
	strsize.width += 0.5f;
	
	OOSetOpenGLState(OPENGL_STATE_OVERLAY);
	
	OOGL(glPushAttrib(GL_CURRENT_BIT));	// save the text colour
	OOGL(glGetFloatv(GL_CURRENT_COLOR, color));	// we need the original colour's alpha.
	
	drawHighlight(x, y, z, strsize, color[3]);
	
	OOGL(glPopAttrib());	//restore the colour
	
	OODrawString(text, x, y, z, siz);
	
	OOVerifyOpenGLState();
}


void OODrawPlanetInfo(int gov, int eco, int tec, GLfloat x, GLfloat y, GLfloat z, NSSize siz)
{
	GLfloat govcol[] = {	0.5, 0.0, 0.7,
							0.7, 0.5, 0.3,
							0.0, 1.0, 0.3,
							1.0, 0.8, 0.1,
							1.0, 0.0, 0.0,
							0.1, 0.5, 1.0,
							0.7, 0.7, 0.7,
							0.7, 1.0, 1.0};
	
	GLfloat cx = x;
	int tl = tec + 1;
	GLfloat ce1 = 1.0f - 0.125f * eco;
	
	OOSetOpenGLState(OPENGL_STATE_OVERLAY);
	
	OOGL(glEnable(GL_TEXTURE_2D));
	[sFontTexture apply];
	
	OOGLBEGIN(GL_QUADS);
		glColor4f(ce1, 1.0f, 0.0f, 1.0f);
		// see OODrawHilightedPlanetInfo
		cx += drawCharacterQuad(23 - eco, cx, y, z, siz);	// characters 16..23 are economy symbols
		glColor3fv(&govcol[gov * 3]);
		cx += drawCharacterQuad(gov, cx, y, z, siz) - 1.0f;		// charcters 0..7 are government symbols
		glColor4f(0.5f, 1.0f, 1.0f, 1.0f);
		if (tl > 9)
		{
			// display TL clamped between 1..16, this must be a '1'!
			cx += drawCharacterQuad(49, cx, y - 2, z, siz) - 2.0f;
		}
		cx += drawCharacterQuad(48 + (tl % 10), cx, y - 2.0f, z, siz);
	OOGLEND();
	
	(void)cx;	// Suppress "value not used" analyzer issue.
	
	[OOTexture applyNone];
	OOGL(glDisable(GL_TEXTURE_2D));
	
	OOVerifyOpenGLState();
}


void OODrawHilightedPlanetInfo(int gov, int eco, int tec, GLfloat x, GLfloat y, GLfloat z, NSSize siz)
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
	
	OOSetOpenGLState(OPENGL_STATE_OVERLAY);
	
	OOGL(glPushAttrib(GL_CURRENT_BIT));	// save the text colour
	OOGL(glGetFloatv(GL_CURRENT_COLOR, color));	// we need the original colour's alpha.
	
	drawHighlight(x, y - 2.0f, z, hisize, color[3]);
	
	OOGL(glPopAttrib());	//restore the colour
	
	OODrawPlanetInfo(gov, eco, tec, x, y, z, siz);
	
	OOVerifyOpenGLState();
}

static void GLDrawNonlinearCascadeWeapon( GLfloat x, GLfloat y, GLfloat z, NSSize siz, Vector centre, GLfloat radius, GLfloat zoom, GLfloat alpha )
{
	Vector spacepos, scannerpos;
	GLfloat theta, phi;
	GLfloat z_factor = siz.height / siz.width;	// approx 1/4
	GLfloat y_factor = 1.0 - sqrt(z_factor);	// approx 1/2
	OOGLVector *points = malloc(sizeof(OOGLVector)*25);
	int i, j;
	
	if (radius*radius > centre.y*centre.y)
	{
		GLfloat r0 = sqrt(radius*radius-centre.y*centre.y);
		OOGL(glColor4f(1.0, 0.5, 1.0, alpha));
		spacepos.y = 0;
		for (i = 0; i < 24; i++)
		{
			theta = i*2*M_PI/24;
			spacepos.x = centre.x + r0 * cos(theta);
			spacepos.z = centre.z + r0 * sin(theta);
			scannerpos = [HeadUpDisplay nonlinearScannerScale: spacepos Zoom: zoom Scale: 0.5*siz.width];
			points[i].x = x + scannerpos.x;
			points[i].y = y + scannerpos.z * z_factor + scannerpos.y * y_factor;
			points[i].z = z;
		}
		spacepos.x = centre.x + r0;
		spacepos.y = 0;
		spacepos.z = centre.z;
		scannerpos = [HeadUpDisplay nonlinearScannerScale: spacepos Zoom: zoom Scale: 0.5*siz.width];
		points[24].x = x + scannerpos.x;
		points[24].y = y + scannerpos.z * z_factor + scannerpos.y * y_factor;
		points[24].z = z;
		GLDrawPoints(points,25);
	}
	OOGL(glColor4f(0.5, 0.0, 1.0, 0.33333 * alpha));
	free(points);
	// Here, we draw a sphere distorted by the nonlinear function. We draw the sphere as a set of horizontal strips
	// The even indices of points are the points on the upper edge of the strip, while odd indices are points
	// on the bottom edge.
	points = malloc(sizeof(OOGLVector)*50);
	spacepos.x = centre.x;
	spacepos.y = centre.y + radius;
	spacepos.z = centre.z;
	scannerpos = [HeadUpDisplay nonlinearScannerScale: spacepos Zoom: zoom Scale: 0.5*siz.width];
	for (i = 0; i <= 24; i++)
	{
		points[2*i+1].x = x + scannerpos.x;
		points[2*i+1].y = y + scannerpos.y * y_factor + scannerpos.z * z_factor;
		points[2*i+1].z = z;
	}
	for (i = 1; i <= 24; i++)
	{
		theta = i*M_PI/24;
		for (j = 0; j <= 24; j++)
		{
			phi = j*M_PI/12;
			// copy point from bottom edge of previous strip into top edge position
			points[2*j] = points[2*j+1];

			spacepos.x = centre.x + radius * sin(theta) * cos(phi);
			spacepos.y = centre.y + radius * cos(theta);
			spacepos.z = centre.z + radius * sin(theta) * sin(phi);
			scannerpos = [HeadUpDisplay nonlinearScannerScale: spacepos Zoom: zoom Scale: 0.5*siz.width];
			points[2*j+1].x = x + scannerpos.x;
			points[2*j+1].y = y + scannerpos.y * y_factor + scannerpos.z * z_factor;
			points[2*j+1].z = z;
		}
		GLDrawQuadStrip(points, 50);
	}
	free(points);
	return;
}

static GLfloat nonlinearScannerFunc( GLfloat distance, GLfloat zoom, GLfloat scale )
{
	GLfloat x = fabs(distance / SCANNER_MAX_RANGE);
	if (x >= 1.0)
		return scale;
	if (zoom <= 1.0)
		return scale * x;
	GLfloat c = 1 / ( zoom - 1 );
	GLfloat b = c * ( c + 1 );
	GLfloat a = c + 1;
	return scale * ( a - b / ( x + c ) );
}


static void drawScannerGrid(GLfloat x, GLfloat y, GLfloat z, NSSize siz, int v_dir, GLfloat thickness, GLfloat zoom, BOOL nonlinear)
{
	OOSetOpenGLState(OPENGL_STATE_OVERLAY);
	
	GLfloat w1, h1;
	GLfloat ww = 0.5 * siz.width;
	GLfloat hh = 0.5 * siz.height;
	
	GLfloat w2 = 0.250 * siz.width;
	GLfloat h2 = 0.250 * siz.height;
	
	GLfloat km_scan;
	GLfloat hdiv;
	GLfloat wdiv;
	BOOL drawdiv = NO, drawdiv1 = NO, drawdiv5 = NO;
	
	int i, ii;
	
	OOGL(GLScaledLineWidth(2.0 * thickness));
	GLDrawOval(x, y, z, siz, 4);
	OOGL(GLScaledLineWidth(thickness));
	
	OOGLBEGIN(GL_LINES);
		glVertex3f(x, y - hh, z);	glVertex3f(x, y + hh, z);
		glVertex3f(x - ww, y, z);	glVertex3f(x + ww, y, z);

		if (nonlinear)
		{
			if (nonlinearScannerFunc(4000.0, zoom, hh)-nonlinearScannerFunc(3000.0, zoom ,hh) > 2) drawdiv1 = YES;
			if (nonlinearScannerFunc(10000.0, zoom, hh)-nonlinearScannerFunc(5000.0, zoom, hh) > 2) drawdiv5 = YES;
			wdiv = ww/(0.001*SCANNER_MAX_RANGE);
			for (i = 1; 1000.0*i < SCANNER_MAX_RANGE; i++)
			{
				drawdiv = drawdiv1;
				w1 = wdiv;
				if (i % 10 == 0)
				{
					w1 = wdiv*4;
					drawdiv = YES;
					if (nonlinearScannerFunc((i+5)*1000,zoom,hh) - nonlinearScannerFunc(i*1000.0,zoom,hh)>2)
					{
						drawdiv5 = YES;
					}
					else
					{
						drawdiv5 = NO;
					}
				}
				else if (i % 5 == 0)
				{
					w1 = wdiv*2;
					drawdiv = drawdiv5;
					if (nonlinearScannerFunc((i+1)*1000,zoom,hh) - nonlinearScannerFunc(i*1000.0,zoom,hh)>2)
					{
						drawdiv1 = YES;
					}
					else
					{
						drawdiv1 = NO;
					}
				}
				if (drawdiv)
				{
					h1 = nonlinearScannerFunc(i*1000.0,zoom,hh);
					glVertex3f(x - w1, y + h1, z);	glVertex3f(x + w1, y + h1, z);
					glVertex3f(x - w1, y - h1, z);	glVertex3f(x + w1, y - h1, z);
				}
			}
		}
		else
		{
			km_scan = 0.001 * SCANNER_MAX_RANGE / zoom;	// calculate kilometer divisions
			hdiv = 0.5 * siz.height / km_scan;
			wdiv = 0.25 * siz.width / km_scan;
			if (wdiv < 4.0)
			{
				wdiv *= 2.0;
				ii = 5;
			}
			else
			{
				ii = 1;
			}
	
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
	
	OOVerifyOpenGLState();
}


static void DrawSpecialOval(GLfloat x, GLfloat y, GLfloat z, NSSize siz, GLfloat step, GLfloat *color4v)
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


static void SetGLColourFromInfo(NSDictionary *info, NSString *key, const GLfloat defaultColor[4], GLfloat alpha)
{
	id			colorDesc = nil;
	OOColor		*color = nil;
	colorDesc = [info objectForKey:key];
	if (colorDesc != nil)
	{
		color = [OOColor colorWithDescription:colorDesc];
		if (color != nil)
		{
			GLfloat ioColor[4];
			[color getRed:&ioColor[0] green:&ioColor[1] blue:&ioColor[2] alpha:&ioColor[3]];
			GLColorWithOverallAlpha(ioColor,alpha);
			return;
		}	
	}	
	GLColorWithOverallAlpha(defaultColor,alpha);
}


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
			[color getRed:&ioColor[0] green:&ioColor[1] blue:&ioColor[2] alpha:&ioColor[3]];
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
