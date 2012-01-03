/*

OOFastArithmetic.m

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


#include "OOMaths.h"


#if OO_PPC

#ifndef __llvm__
/*	OOInvSqrtf()
	Based on G3-otimized fsqrtf() by Conn Clark. The only difference is that
	it does not store and multiply by the original value to go from reciprocal
	square root to square root.
	The original is documented as having full precision if frsqrte has at
	least 1/59 precision as on the G3, and an error of no more than 1/4.22e+06
	if frsqrte has 1/32 (the minimum allowable precision) as on the G5.
	Informal testing shows errors up to 1.2e-07 on a G5 for this version, at
	about an 18% speed increase over 1.0f/sqrtf(x); the performance advantage
	is expected to be more significant on G4 and G3 processors (the G5 has
	a sqare root instruction).
	
	The original was found here:
	http://sources.redhat.com/ml/libc-alpha/2006-12/txt00004.txt
	and is LGPL-licensed. This version may also be distributed under the GNU
	Lesser General Public License, in addition the GPL as specified in the
	file header.
	
	This may not build under Linux-PPC; it may need to be modified to use
	GCC's crazy asm syntax.
*/
asm float OOInvSqrtf(float x)
{
	/* start loading some constants for integer comparison */
	lis     r3,0x3f00			/* 0.5F equiv as an integer */
	lis     r4,0x3FC0			/* 1.5F equiv as an integer */
	stfsu   f1,-12(r1)			/* store original and get 12 bytes of stack space. */
	stw     r3,4(r1)			/* store 0.5F on the stack to be loaded by fpu */
	mffs    f6					/* store fpu configuration */
	stw     r4,8(r1)			/* store 1.5F on the stack to be loaded by fpu */
	lis     r7, 0x7F80			/* load NAN for testing */
	lfs     f2,4(r1)			/* load 0.5F into fpu reg 2 */
	lwz     r5,0(r1)			/* load original value as an int for testing */
	fmr     f9,f1				/* copy original value into fpu reg 9 */
	cmpi    0,r5,0x0000			/* test for positive zero */
	rlwinm  r12,r5,0,0,1		/* mask off sign bit and store in reg 12*/
	lfs     f7,8(r1)			/* load 1.5F into fpu reg 7 */
	cmpl    1,r12,r7			/* test for NAN results in cr1 */
	ble     neg_number_or_zero	/* branch if less than or equal to zero */
	frsqrte f1,f1				/* get recip sqrt estimate (does no harm if input is NaN */
	beq     cr1, not_a_number	/* branch if original value was not a number */
	fmul    f2,f2,f9			/* begin Goldschmidt */
	fmuls   f3,f1,f1			/* single-precision saves one clock without affecting accuracy */
	fmul    f4,f2,f3
	fnmsubs f3,f2,f3,f7			/* single-precision saves one clock without affecting accuracy */
	fmul    f5,f3,f3
	fmul    f1,f3,f1
	fnmsubs f3,f4,f5,f7			/* single-precision saves one clock without affecting accuracy */
	fmul    f4,f4,f5
	fmul    f1,f3,f1
	fmul    f5,f3,f3
	fnmsub  f3,f4,f5,f7
	fmul    f1,f3,f1
	addi    r1,r1,12			/* clean up stack */
	mtfsf   0xff,f6				/* restore fpu state */
	frsp    f1,f1				/* round result to a float */
	blr							/* return */
	
neg_number_or_zero:
	lis     r9,0x3F80			/* load up equiv of 1.0F */
	stw     r9,8(r1)			/* store 1.0F to where fpu can load it */
	lis     r6, 0x8000			/* negative */
	lfs     f2,8(r1)			/* load 1.0F into fpu reg 2 */
	beq     its_zero			/* branch if zero */
	
	/* This bit sets FPU status bits for negative number case, and isn't strictly needed for Oolite. */
	cmpl    0,r5,r6				/* test for negative zero */
	beq     its_zero			/* branch if zero */
	stfs    f6,0(r1)			/* store fpu status */
	lis     r3,0x7FC0			/* load aNaN        */
	lis     r4,0x2000			/* load FE_INVALID flag */
	lwz     r5,0(r1)			/* load fpu status in gp register */
	ori     r4,r4,0x0200		/* load INV_SQRT flag */
	or      r5,r5,r4			/* or FE_INVALID and INV_SQRT flags with fpu status */
	stw     r3,4(r1)			/* store aNaN on stack */
	stw     r5,0(r1)			/* store fpu status */
	lfs     f6,0(r1)			/* load new fpu status */
	lfs     f1,4(r1)			/* load aNaN to be returned */
	mtfsf   0xff,f6				/* update fpu status to new value */
	
its_zero:
	fmuls   f1,f1,f2			/* multiply by 1.0 to set appropriate status bits */
	addi    r1,r1,12			/* clean up stack */
	blr							/* return */
	
not_a_number:
	lis     r6,0x3F80			/* load up equiv of 1.0F */
	stw     r6,8(r1)			/* store 1.0F to where fpu can load it */
	lfs     f2,8(r1)			/* load 1.0F into fpu reg 2 */
	mtfsf   0xff,f6				/* restore fpu status */
	fmuls   f1,f1,f2			/* multiply by 1.0 to set appropriate status bits */
	addi    r1,r1,12			/* clean up stack */
	blr							/* return */
}

#else

#include <math.h>

// LLVM-GCC doesn't support asm at the moment.
float OOInvSqrtf(float x)
{
	return 1.0 / sqrtf(x);
}

#endif
#endif
