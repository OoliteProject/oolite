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

#import "OOOpenGLExtensionManager.h"
#import "OOOpenGLMatrixManager.h"
#import "MyOpenGLView.h"
#import "Universe.h"
#import "OOMacroOpenGL.h"

const char* ooliteStandardMatrixUniforms[] =
{
	"ooliteModelView",
	"ooliteProjection",
	"ooliteModelViewProjection",
	"ooliteNormalMatrix",
	"ooliteModelViewInverse",
	"ooliteProjectionInverse",
	"ooliteModelViewProjectionInverse",
	"ooliteModelViewTranspose",
	"ooliteProjectionTracnspose",
	"ooliteModelViewProjectionTranspose",
	"ooliteModelViewInverseTraspose",
	"ooliteProjectionInverseTranspose",
	"ooliteModelViewProjectionInverseTranspose"
};

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
	valid[OOLITE_GL_MATRIX_MODELVIEW_INVERSE] = NO;
	valid[OOLITE_GL_MATRIX_PROJECTION_INVERSE] = NO;
	valid[OOLITE_GL_MATRIX_MODELVIEW_PROJECTION_INVERSE] = NO;
	valid[OOLITE_GL_MATRIX_MODELVIEW_TRANSPOSE] = NO;
	valid[OOLITE_GL_MATRIX_PROJECTION_TRANSPOSE] = NO;
	valid[OOLITE_GL_MATRIX_MODELVIEW_PROJECTION_TRANSPOSE] = NO;
	valid[OOLITE_GL_MATRIX_MODELVIEW_INVERSE_TRANSPOSE] = NO;
	valid[OOLITE_GL_MATRIX_PROJECTION_INVERSE_TRANSPOSE] = NO;
	valid[OOLITE_GL_MATRIX_MODELVIEW_PROJECTION_INVERSE_TRANSPOSE] = NO;
}

- (void) updateProjection
{
	valid[OOLITE_GL_MATRIX_MODELVIEW_PROJECTION] = NO;
	valid[OOLITE_GL_MATRIX_PROJECTION_INVERSE] = NO;
	valid[OOLITE_GL_MATRIX_MODELVIEW_PROJECTION_INVERSE] = NO;
	valid[OOLITE_GL_MATRIX_PROJECTION_TRANSPOSE] = NO;
	valid[OOLITE_GL_MATRIX_MODELVIEW_PROJECTION_TRANSPOSE] = NO;
	valid[OOLITE_GL_MATRIX_PROJECTION_INVERSE_TRANSPOSE] = NO;
	valid[OOLITE_GL_MATRIX_MODELVIEW_PROJECTION_INVERSE_TRANSPOSE] = NO;
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

- (void) syncModelView
{
	OO_ENTER_OPENGL();
	OOGL(glMatrixMode(GL_MODELVIEW));
	GLLoadOOMatrix([self getModelView]);
	return;
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

- (void) frustumLeft: (double) l right: (double) r bottom: (double) b top: (double) t near: (double) n far: (double) f
{
	if (l == r || t == b || n == f || n <= 0 || f <= 0) return;
	[self multProjection: OOMatrixConstruct
	(
		  2*n/(r-l),		0.0,		 0.0,	 0.0,
			0.0,	  2*n/(t-b),		 0.0,	 0.0,
		(r+l)/(r-l),	(t+b)/(t-b),	-(f+n)/(f-n),	-1.0,
			0.0,		0.0,	-2*f*n/(f-n),	 0.0
	)];
}

- (void) orthoLeft: (double) l right: (double) r bottom: (double) b top: (double) t near: (double) n far: (double) f
{
	if (l == r || t == b || n == f) return;
	[self multProjection: OOMatrixConstruct
	(
		2/(r-l),	0.0,		0.0,		0.0,
		0.0,		2/(t-b),	0.0,		0.0,
		0.0,		0.0,		2/(n-f),	0.0,
		(l+r)/(l-r),	(b+t)/(b-t),	(n+f)/(n-f),	1.0
	)];
}

- (void) perspectiveFovy: (double) fovy aspect: (double) aspect zNear: (double) zNear zFar: (double) zFar
{
	if (aspect == 0.0 || zNear == zFar) return;
	double f = 1.0/tan(M_PI * fovy / 360);
	[self multProjection: OOMatrixConstruct
	(
		f/aspect,	0.0,	0.0,				0.0,
		0.0,		f,	0.0,				0.0,
		0.0,		0.0,	(zFar + zNear)/(zNear - zFar),	-1.0,
		0.0,		0.0,	2*zFar*zNear/(zNear - zFar),	0.0
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

- (void) syncProjection
{
	OO_ENTER_OPENGL();
	OOGL(glMatrixMode(GL_PROJECTION));
	GLLoadOOMatrix([self getProjection]);
	return;
}

- (OOMatrix) getMatrix: (int) which
{
	if (which < 0 || which >= OOLITE_GL_MATRIX_END) return kIdentityMatrix;
	if (valid[which]) return matrices[which];
	OOScalar d;
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
		matrices[which] = OOMatrixTranspose(OOMatrixInverseWithDeterminant(matrices[which], &d));
		if (d != 0.0)
		{
			d = pow(fabs(d), 1.0/3);
			for (int i = 0; i < 3; i++)
			{
				for (int j = 0; j < 3; j++)
				{
					matrices[which].m[i][j] /= d;
				}
			}
		}
		break;
	case OOLITE_GL_MATRIX_MODELVIEW_INVERSE:
		matrices[which] = OOMatrixInverse(matrices[OOLITE_GL_MATRIX_MODELVIEW]);
		break;
	case OOLITE_GL_MATRIX_PROJECTION_INVERSE:
		matrices[which] = OOMatrixInverse(matrices[OOLITE_GL_MATRIX_PROJECTION]);
		break;
	case OOLITE_GL_MATRIX_MODELVIEW_PROJECTION_INVERSE:
		matrices[which] = OOMatrixInverse([self getMatrix: OOLITE_GL_MATRIX_MODELVIEW_PROJECTION]);
		break;
	case OOLITE_GL_MATRIX_MODELVIEW_TRANSPOSE:
		matrices[which] = OOMatrixTranspose(matrices[OOLITE_GL_MATRIX_MODELVIEW]);
		break;
	case OOLITE_GL_MATRIX_PROJECTION_TRANSPOSE:
		matrices[which] = OOMatrixTranspose(matrices[OOLITE_GL_MATRIX_PROJECTION]);
		break;
	case OOLITE_GL_MATRIX_MODELVIEW_PROJECTION_TRANSPOSE:
		matrices[which] = OOMatrixTranspose([self getMatrix: OOLITE_GL_MATRIX_MODELVIEW_PROJECTION]);
		break;
	case OOLITE_GL_MATRIX_MODELVIEW_INVERSE_TRANSPOSE:
		matrices[which] = OOMatrixTranspose([self getMatrix: OOLITE_GL_MATRIX_MODELVIEW_INVERSE]);
		break;
	case OOLITE_GL_MATRIX_PROJECTION_INVERSE_TRANSPOSE:
		matrices[which] = OOMatrixTranspose([self getMatrix: OOLITE_GL_MATRIX_PROJECTION_INVERSE]);
		break;
	case OOLITE_GL_MATRIX_MODELVIEW_PROJECTION_INVERSE_TRANSPOSE:
		matrices[which] = OOMatrixTranspose([self getMatrix: OOLITE_GL_MATRIX_MODELVIEW_PROJECTION_INVERSE]);
		break;
	}
	valid[which] = YES;
	return matrices[which];
}

- (NSArray*) standardMatrixUniformLocations: (GLuint) program
{
	GLint location;
	NSUInteger i;
	NSMutableArray *locationSet = [[[NSMutableArray alloc] init] autorelease];
	
	for (i = 0; i < OOLITE_GL_MATRIX_END; i++) {
		location = glGetUniformLocationARB(program, ooliteStandardMatrixUniforms[i]);
		if (location >= 0) {
			if (i == OOLITE_GL_MATRIX_NORMAL)
			{
				[locationSet addObject:
					[NSArray arrayWithObjects:
						[NSNumber numberWithInt: location],
						[NSNumber numberWithInt: i],
						@"mat3",
						nil]];
			}
			else
			{
				[locationSet addObject:
					[NSArray arrayWithObjects:
						[NSNumber numberWithInt: location],
						[NSNumber numberWithInt: i],
						@"mat4",
						nil]];
			}
		}
	}
	return [[NSArray arrayWithArray: locationSet] retain];
}

@end

void OOGLPushModelView()
{
	OOOpenGLMatrixManager *matrixManager = [[UNIVERSE gameView] getOpenGLMatrixManager];
	[matrixManager pushModelView];
	[matrixManager syncModelView];
}

OOMatrix OOGLPopModelView()
{
	OOOpenGLMatrixManager *matrixManager = [[UNIVERSE gameView] getOpenGLMatrixManager];
	OOMatrix matrix = [matrixManager popModelView];
	[matrixManager syncModelView];
	return matrix;
}

OOMatrix OOGLGetModelView()
{
	OOOpenGLMatrixManager *matrixManager = [[UNIVERSE gameView] getOpenGLMatrixManager];
	OOMatrix matrix = [matrixManager getModelView];
	return matrix;
}

void OOGLResetModelView()
{
	OOOpenGLMatrixManager *matrixManager = [[UNIVERSE gameView] getOpenGLMatrixManager];
	[matrixManager resetModelView];
	[matrixManager syncModelView];
}

void OOGLLoadModelView(OOMatrix matrix)
{
	OOOpenGLMatrixManager *matrixManager = [[UNIVERSE gameView] getOpenGLMatrixManager];
	[matrixManager loadModelView: matrix];
	[matrixManager syncModelView];
}

void OOGLMultModelView(OOMatrix matrix)
{
	OOOpenGLMatrixManager *matrixManager = [[UNIVERSE gameView] getOpenGLMatrixManager];
	[matrixManager multModelView: matrix];
	[matrixManager syncModelView];
}

void OOGLTranslateModelView(Vector vector)
{
	OOOpenGLMatrixManager *matrixManager = [[UNIVERSE gameView] getOpenGLMatrixManager];
	[matrixManager translateModelView: vector];
	[matrixManager syncModelView];
}

void OOGLRotateModelView(GLfloat angle, Vector axis)
{
	OOOpenGLMatrixManager *matrixManager = [[UNIVERSE gameView] getOpenGLMatrixManager];
	[matrixManager rotateModelView: angle axis: axis];
	[matrixManager syncModelView];
}

void OOGLScaleModelView(Vector scale)
{
	OOOpenGLMatrixManager *matrixManager = [[UNIVERSE gameView] getOpenGLMatrixManager];
	[matrixManager scaleModelView: scale];
	[matrixManager syncModelView];
}

void OOGLLookAt(Vector eye, Vector center, Vector up)
{
	OOOpenGLMatrixManager *matrixManager = [[UNIVERSE gameView] getOpenGLMatrixManager];
	[matrixManager lookAtWithEye: eye center: center up: up];
	[matrixManager syncModelView];
}

void OOGLResetProjection()
{
	OOOpenGLMatrixManager *matrixManager = [[UNIVERSE gameView] getOpenGLMatrixManager];
	[matrixManager resetProjection];
	[matrixManager syncProjection];
}

void OOGLPushProjection()
{
	OOOpenGLMatrixManager *matrixManager = [[UNIVERSE gameView] getOpenGLMatrixManager];
	[matrixManager pushProjection];
	[matrixManager syncProjection];
}

OOMatrix OOGLPopProjection()
{
	OOOpenGLMatrixManager *matrixManager = [[UNIVERSE gameView] getOpenGLMatrixManager];
	OOMatrix matrix = [matrixManager popProjection];
	[matrixManager syncProjection];
	return matrix;
}

OOMatrix OOGLGetProjection()
{
	OOOpenGLMatrixManager *matrixManager = [[UNIVERSE gameView] getOpenGLMatrixManager];
	OOMatrix matrix = [matrixManager getProjection];
	return matrix;
}

void OOGLLoadProjection(OOMatrix matrix)
{
	OOOpenGLMatrixManager *matrixManager = [[UNIVERSE gameView] getOpenGLMatrixManager];
	[matrixManager loadProjection: matrix];
	[matrixManager syncProjection];
}

void OOGLMultProjection(OOMatrix matrix)
{
	OOOpenGLMatrixManager *matrixManager = [[UNIVERSE gameView] getOpenGLMatrixManager];
	[matrixManager multProjection: matrix];
	[matrixManager syncProjection];
}

void OOGLTranslateProjection(Vector vector)
{
	OOOpenGLMatrixManager *matrixManager = [[UNIVERSE gameView] getOpenGLMatrixManager];
	[matrixManager translateProjection: vector];
	[matrixManager syncProjection];
}

void OOGLRotateProjection(GLfloat angle, Vector axis)
{
	OOOpenGLMatrixManager *matrixManager = [[UNIVERSE gameView] getOpenGLMatrixManager];
	[matrixManager rotateProjection: angle axis: axis];
	[matrixManager syncProjection];
}

void OOGLScaleProjection(Vector scale)
{
	OOOpenGLMatrixManager *matrixManager = [[UNIVERSE gameView] getOpenGLMatrixManager];
	[matrixManager scaleProjection: scale];
	[matrixManager syncProjection];
}

void OOGLFrustum(double left, double right, double bottom, double top, double near, double far)
{
	OOOpenGLMatrixManager *matrixManager = [[UNIVERSE gameView] getOpenGLMatrixManager];
	[matrixManager frustumLeft: left right: right bottom: bottom top: top near: near far: far];
	[matrixManager syncProjection];
}

void OOGLOrtho(double left, double right, double bottom, double top, double near, double far)
{
	OOOpenGLMatrixManager *matrixManager = [[UNIVERSE gameView] getOpenGLMatrixManager];
	[matrixManager orthoLeft: left right: right bottom: bottom top: top near: near far: far];
	[matrixManager syncProjection];
}

void OOGLPerspective(double fovy, double aspect, double zNear, double zFar)
{
	OOOpenGLMatrixManager *matrixManager = [[UNIVERSE gameView] getOpenGLMatrixManager];
	[matrixManager perspectiveFovy: fovy aspect: aspect zNear: zNear zFar: zFar];
	[matrixManager syncProjection];
}

OOMatrix OOGLGetModelViewProjection()
{
	OOOpenGLMatrixManager *matrixManager = [[UNIVERSE gameView] getOpenGLMatrixManager];
	return [matrixManager getMatrix: OOLITE_GL_MATRIX_MODELVIEW_PROJECTION];
}

