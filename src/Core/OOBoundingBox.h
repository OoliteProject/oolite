/*

OOBoundingBox.h

Mathematical framework for Oolite.

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


#ifndef INCLUDED_OOMATHS_h
	#error Do not include OOBoundingBox.h directly; include OOMaths.h.
#else


typedef struct
{
	Vector		min;
	Vector		max;
} BoundingBox;


extern const BoundingBox kZeroBoundingBox;		/* (0, 0, 0), (0, 0, 0) */


/* Extend bounding box to contain specified point. */
OOINLINE void bounding_box_add_vector(BoundingBox *box, Vector vec) ALWAYS_INLINE_FUNC NONNULL_FUNC;
OOINLINE void bounding_box_add_xyz(BoundingBox *box, GLfloat x, GLfloat y, GLfloat z) ALWAYS_INLINE_FUNC NONNULL_FUNC;

/* Reset bounding box to kZeroBoundingBox. */
OOINLINE void bounding_box_reset(BoundingBox *box) NONNULL_FUNC;

/* Reset bounding box to a zero-sized box surrounding specified vector. */
OOINLINE void bounding_box_reset_to_vector(BoundingBox *box, Vector vec) ALWAYS_INLINE_FUNC NONNULL_FUNC;

OOINLINE void bounding_box_get_dimensions(BoundingBox bb, GLfloat *xSize, GLfloat *ySize, GLfloat *zSize) ALWAYS_INLINE_FUNC;

OOINLINE Vector OOBoundingBoxCenter(BoundingBox bb) INLINE_CONST_FUNC;

Vector OORandomPositionInBoundingBox(BoundingBox bb);



/*** Only inline definitions beyond this point ***/

OOINLINE void bounding_box_add_vector(BoundingBox *box, Vector vec)
{
	assert(box != NULL);
	box->min.x = fmin(box->min.x, vec.x);
	box->max.x = fmax(box->max.x, vec.x);
	box->min.y = fmin(box->min.y, vec.y);
	box->max.y = fmax(box->max.y, vec.y);
	box->min.z = fmin(box->min.z, vec.z);
	box->max.z = fmax(box->max.z, vec.z);
}


OOINLINE void bounding_box_add_xyz(BoundingBox *box, GLfloat x, GLfloat y, GLfloat z)
{
	assert(box != NULL);
	box->min.x = fmin(box->min.x, x);
	box->max.x = fmax(box->max.x, x);
	box->min.y = fmin(box->min.y, y);
	box->max.y = fmax(box->max.y, y);
	box->min.z = fmin(box->min.z, z);
	box->max.z = fmax(box->max.z, z);
}


OOINLINE void bounding_box_reset(BoundingBox *box)
{
	assert(box != NULL);
	*box = kZeroBoundingBox;
}


OOINLINE void bounding_box_reset_to_vector(BoundingBox *box, Vector vec)
{
	assert(box != NULL);
	box->min = vec;
	box->max = vec;
}


OOINLINE void bounding_box_get_dimensions(BoundingBox bb, GLfloat *xSize, GLfloat *ySize, GLfloat *zSize)
{
	if (xSize != NULL)  *xSize = bb.max.x - bb.min.x;
	if (ySize != NULL)  *ySize = bb.max.y - bb.min.y;
	if (zSize != NULL)  *zSize = bb.max.z - bb.min.z;
}


OOINLINE Vector OOBoundingBoxCenter(BoundingBox bb)
{
	return vector_multiply_scalar(vector_add(bb.min, bb.max), 0.5f);
}

#endif
