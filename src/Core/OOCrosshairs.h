//
//  OOCrosshairs.h
//  Oolite
//
//  Created by Jens Ayton on 2008-12-16.
//  Copyright 2008 Jens Ayton. All rights reserved.
//

#import "OOCocoa.h"
#import "OOOpenGL.h"

@class OOColor;


@interface OOCrosshairs: NSObject
{
@private
	unsigned					_count;
	GLfloat						*_data;
}

- (id) initWithPoints:(NSArray *)points
				scale:(GLfloat)scale
				color:(OOColor *)color
		 overallAlpha:(GLfloat)alpha;

- (void) render;

@end
