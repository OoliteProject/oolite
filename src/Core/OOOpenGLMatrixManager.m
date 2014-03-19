/*

OOOpenGLMatrixManager.m

Manages OpenGL Model, View, etc. matrices.

Oolite
Copyright (C) 2004-2014 Giles C Williams and contributors

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

#import "OOOpenGLMatrixManager.h"

const NSString *ooliteStandardMatrixUniforms[] =
{
	@"ooliteModelView",
	@"ooliteProjection",
	@"ooliteModelViewProjection",
	@"ooliteNormalMatrix"
};

static OOOpenGLMatrixManager * sharedMatrixManager = nil;

@implementation OOOpenGLMatrixStack

- (id) init
{
	if ((self = [super init]))
	{
		stack = [[NSMutableArray alloc] init];
	}
	return self;
}

- (void) dealloc
{
	[stack release];
	[super dealloc];
}

- (void) push: (OOMatrix) matrix
{
	[stack addObject: [NSValue valueWithBytes: &matrix objCType: @encode(OOMatrix)]];
}

- (OOMatrix) pop
{
	if ([stack count] == 0)
	{
		return kIdentityMatrix;
	}
	OOMatrix matrix;
	[[stack lastObject] getValue: &matrix];
	[stack removeLastObject];
	return matrix;
}

@end

@interface OOOpenGLMatrixManager(Private)

- (void) updateModelView;
- (void) updateProjection;

@end

@implementation OOOpenGLMatrixManager(Private)

- (void) updateModelView
{
	valid[OOLITE_GL_MATRIX_MODELVIEW_PROJECTION] = NO;
	valid[OOLITE_GL_MATRIX_NORMAL] = NO;
}

- (void) updateProjection
{
	valid[OOLITE_GL_MATRIX_MODELVIEW_PROJECTION] = NO;
}

@end

@implementation OOOpenGLMatrixManager

- (id) init
{
	if ((self = [super init]))
	{
		int i;
		for (i = 0; i < OOLITE_GL_MATRIX_END; i++)
		{
			switch(i)
			{
			case OOLITE_GL_MATRIX_MODELVIEW:
			case OOLITE_GL_MATRIX_PROJECTION:
				matrices[i] = kIdentityMatrix;
				valid[i] = YES;
				break;

			default:
				valid[i] = NO;
				break;
			}
		}
		modelViewStack = [[OOOpenGLMatrixStack alloc] init];
		projectionStack = [[OOOpenGLMatrixStack alloc] init];
	}
	return self;
}

+ (OOOpenGLMatrixManager *) sharedOpenGLMatrixManager
{
	if (!sharedMatrixManager)
	{
		sharedMatrixManager = [[OOOpenGLMatrixManager alloc] init];
	}
	return sharedMatrixManager;
}

- (void) dealloc
{
	[modelViewStack release];
	[projectionStack release];
	[super dealloc];
}

- (void) loadModelView: (OOMatrix) matrix
{
	matrices[OOLITE_GL_MATRIX_MODELVIEW] = matrix;
	[self updateModelView];
	return;
}

- (void) resetModelView
{
	matrices[OOLITE_GL_MATRIX_MODELVIEW] = kIdentityMatrix;
	[self updateModelView];
}

- (void) multModelView: (OOMatrix) matrix
{
	matrices[OOLITE_GL_MATRIX_MODELVIEW] = OOMatrixMultiply(matrix, matrices[OOLITE_GL_MATRIX_MODELVIEW]);
	[self updateModelView];
}

- (void) translateModelView: (Vector) vector
{
	OOMatrix matrix = kIdentityMatrix;
	matrix.m[3][0] = vector.x;
	matrix.m[3][1] = vector.y;
	matrix.m[3][2] = vector.z;
	[self multModelView: matrix];
}

- (void) rotateModelView: (GLfloat) angle axis: (Vector) axis
{
	[self multModelView: OOMatrixForRotation(axis, angle)];
}

- (void) scaleModelView: (Vector) scale
{
	[self multModelView: OOMatrixForScale(scale.x, scale.y, scale.z)];
}

- (void) lookAtWithEye: (Vector) eye center: (Vector) center up: (Vector) up
{
	Vector z = vector_normal(vector_subtract(eye, center));
	Vector x = vector_normal(cross_product(up, z));
	Vector y = cross_product(z, x);
	OOLog( @"kja",@"x:{%g,%g,%g} y:{%g,%g,%g} z:{%g,%g,%g}", x.x, x.y, x.z, y.x, y.y, y.z, z.x, z.y, z.z);
	OOMatrix m1 = OOMatrixConstruct
	(
		x.x + eye.x,	x.y + eye.y,	x.z + eye.z,	1.0,
		y.x + eye.x,	y.y + eye.y,	y.z + eye.z,	1.0,
		z.x + eye.x,	z.y + eye.y,	z.z + eye.z,	1.0,
		eye.x,		eye.y,		eye.z,		1.0
	);
	OOMatrix m2 = OOMatrixConstruct
	(
		1.0,	0.0,	0.0,	1.0,
		0.0,	1.0,	0.0,	1.0,
		0.0,	0.0,	1.0,	1.0,
		0.0,	0.0,	0.0,	1.0
	);
	[self multModelView: OOMatrixRightTransform(m1, m2)];
	return;
}


- (void) pushModelView
{
	[modelViewStack push: matrices[OOLITE_GL_MATRIX_MODELVIEW]];
}

- (OOMatrix) popModelView
{
	matrices[OOLITE_GL_MATRIX_MODELVIEW] = [modelViewStack pop];
	[self updateModelView];
	return matrices[OOLITE_GL_MATRIX_MODELVIEW];
}

- (OOMatrix) getModelView
{
	return matrices[OOLITE_GL_MATRIX_MODELVIEW];
}

- (void) loadProjection: (OOMatrix) matrix
{
	matrices[OOLITE_GL_MATRIX_PROJECTION] = matrix;
	[self updateProjection];
	return;
}

- (void) multProjection: (OOMatrix) matrix
{
	matrices[OOLITE_GL_MATRIX_PROJECTION] = OOMatrixMultiply(matrix, matrices[OOLITE_GL_MATRIX_PROJECTION]);
	[self updateProjection];
}

- (void) translateProjection: (Vector) vector
{
	OOMatrix matrix = kIdentityMatrix;
	matrix.m[0][3] = vector.x;
	matrix.m[1][3] = vector.y;
	matrix.m[2][3] = vector.z;
	[self multProjection: matrix];
}

- (void) rotateProjection: (GLfloat) angle axis: (Vector) axis
{
	[self multProjection: OOMatrixForRotation(axis, angle)];
}

- (void) scaleProjection: (Vector) scale
{
	[self multProjection: OOMatrixForScale(scale.x, scale.y, scale.z)];
}

- (void) frustumLeft: (double) l right: (double) r top: (double) t bottom: (double) b near: (double) n far: (double) f
{
	if (l == r || t == b || n == f || n <= 0 || f <= 0 ) return;
	[self multProjection: OOMatrixConstruct
	(
		  2*n/(l+f),		0.0,		 0.0,	 0.0,
			0.0,	  2*n/(t+b),		 0.0,	 0.0,
		(r+l)/(r-l),	(t+b)/(t-b),	-(f+n)/(f-n),	-1.0,
			0.0,		0.0,	-2*f*n/(f-n),	 0.0
	)];
}

- (void) resetProjection
{
	matrices[OOLITE_GL_MATRIX_PROJECTION] = kIdentityMatrix;
	[self updateProjection];
}

- (void) pushProjection
{
	[projectionStack push: matrices[OOLITE_GL_MATRIX_PROJECTION]];
}

- (OOMatrix) popProjection
{
	matrices[OOLITE_GL_MATRIX_PROJECTION] = [projectionStack pop];
	[self updateProjection];
	return matrices[OOLITE_GL_MATRIX_PROJECTION];
}

- (OOMatrix) getProjection
{
	return matrices[OOLITE_GL_MATRIX_PROJECTION];
}

- (OOMatrix) getMatrix: (int) which
{
	if (which < 0 || which >= OOLITE_GL_MATRIX_END) return kIdentityMatrix;
	if (valid[which]) return matrices[which];
	switch(which)
	{
	case OOLITE_GL_MATRIX_MODELVIEW_PROJECTION:
		matrices[which] = OOMatrixMultiply(matrices[OOLITE_GL_MATRIX_MODELVIEW], matrices[OOLITE_GL_MATRIX_PROJECTION]);
		break;
	case OOLITE_GL_MATRIX_NORMAL:
		matrices[which] = matrices[OOLITE_GL_MATRIX_MODELVIEW];
		matrices[which].m[3][0] = 0.0;
		matrices[which].m[3][1] = 0.0;
		matrices[which].m[3][2] = 0.0;
		matrices[which].m[0][3] = 0.0;
		matrices[which].m[1][3] = 0.0;
		matrices[which].m[2][3] = 0.0;
		matrices[which].m[3][3] = 1.0;
		matrices[which] = OOMatrixTranspose(OOMatrixInverse(matrices[which]));
		break;
	}
	valid[which] = YES;
	return matrices[which];
}

@end

