#import "OOFunctionAttributes.h"
#include <tgmath.h>


// Utilities for working with NSPoints as 2D vectors.
OOINLINE NSPoint PtAdd(NSPoint a, NSPoint b)
{
	return NSMakePoint(a.x + b.x, a.y + b.y);
}

OOINLINE NSPoint PtSub(NSPoint a, NSPoint b)
{
	return NSMakePoint(a.x - b.x, a.y - b.y);
}

OOINLINE NSPoint PtScale(NSPoint p, OOCGFloat scale)
{
	return NSMakePoint(p.x * scale, p.y * scale);
}

OOINLINE OOCGFloat PtDot(NSPoint a, NSPoint b)
{
	return a.x * b.x + a.y * b.y;
}

OOINLINE OOCGFloat PtCross(NSPoint a, NSPoint b)
{
	return a.x * b.y - b.x * a.y;
}

OOINLINE NSPoint PtRotCW(NSPoint p)
{
	// Rotate 90 degrees clockwise.
	return NSMakePoint(p.y, -p.x);
}

OOINLINE NSPoint PtRotACW(NSPoint p)
{
	// Rotate 90 degrees anticlockwise.
	return NSMakePoint(-p.y, p.x);
}

OOINLINE NSPoint PtNormal(NSPoint p)
{
	return PtScale(p, 1.0f / sqrt(PtDot(p, p)));
}
