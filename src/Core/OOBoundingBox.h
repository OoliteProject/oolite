/*

OOBoundingBox.h

Mathematical framework for Oolite.

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
OOINLINE void bounding_box_add_vector(BoundingBox *box, Vector vec) NONNULL_FUNC;
OOINLINE void bounding_box_add_xyz(BoundingBox *box, GLfloat x, GLfloat y, GLfloat z) NONNULL_FUNC;

/* Reset bounding box to kZeroBoundingBox. */
OOINLINE void bounding_box_reset(BoundingBox *box) NONNULL_FUNC;

/* Reset bounding box to a zero-sized box surrounding specified vector. */
OOINLINE void bounding_box_reset_to_vector(BoundingBox *box, Vector vec) NONNULL_FUNC;

/* Find distance from origin to furthest side of bounding box. NOTE: this is less than the radius of a bounding sphere! Should check how this is used... */
OOINLINE GLfloat bounding_box_max_radius(BoundingBox bb) CONST_FUNC;



/*** Only inline definitions beyond this point ***/

OOINLINE void bounding_box_add_vector(BoundingBox *box, Vector vec)
{
	box->min.x = MIN(box->min.x, vec.x);
	box->max.x = MAX(box->max.x, vec.x);
	box->min.y = MIN(box->min.y, vec.y);
	box->max.y = MAX(box->max.y, vec.y);
	box->min.z = MIN(box->min.z, vec.z);
	box->max.z = MAX(box->max.z, vec.z);
}


void bounding_box_add_xyz(BoundingBox *box, GLfloat x, GLfloat y, GLfloat z)
{
	box->min.x = MIN(box->min.x, x);
	box->max.x = MAX(box->max.x, x);
	box->min.y = MIN(box->min.y, y);
	box->max.y = MAX(box->max.y, y);
	box->min.z = MIN(box->min.z, z);
	box->max.z = MAX(box->max.z, z);
}


OOINLINE void bounding_box_reset(BoundingBox *box)
{
	*box = kZeroBoundingBox;
}


OOINLINE void bounding_box_reset_to_vector(BoundingBox *box, Vector vec)
{
	box->min = vec;
	box->max = vec;
}


OOINLINE GLfloat bounding_box_max_radius(BoundingBox bb)
{
	GLfloat x = MAX(bb.max.x, -bb.min.x);
	GLfloat y = MAX(bb.max.y, -bb.min.y);
	GLfloat z = MAX(bb.max.z, -bb.min.z);
	return MAX(MAX(x, y), z);
}

#endif
