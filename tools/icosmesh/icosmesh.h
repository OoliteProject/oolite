#import <Foundation/Foundation.h>
#import <math.h>


#define OUTPUT_BINORMALS	0


typedef struct
{
	double				x, y, z;
} Vector;


typedef struct
{
	Vector				v;
#if OUTPUT_BINORMALS
	Vector				binormal;
#endif
	double				s, t;	// Lat/long texture coordinates
} Vertex;



//	Convert vector to latitude and longitude (or θ and φ).
void VectorToCoordsRad(Vector vc, double *latitude, double *longitude);
void VectorToCoords0_1(Vector vc, double *latitude, double *longitude);


static inline Vector VectorAdd(Vector u, Vector v)
{
	return (Vector){ u.x + v.x, u.y + v.y, u.z + v.z };
}


static inline Vector VectorSubtract(Vector u, Vector v)
{
	return (Vector){ u.x - v.x, u.y - v.y, u.z - v.z };
}


static inline double VectorDot(Vector u, Vector v)
{
	return u.x * v.x + u.y * v.y + u.z * v.z;
}


static inline Vector VectorCross(Vector u, Vector v)
{
	return (Vector)
	{
		u.y * v.z - v.y * u.z,
		u.z * v.x - v.z * u.x,
		u.x * v.y - v.x * u.y
	};
}


static inline double VectorMagnitude(Vector v)
{
	return sqrt(VectorDot(v, v));
}


static inline Vector VectorScale(Vector v, double s)
{
	return (Vector){ v.x * s, v.y * s, v.z * s };
}


static inline Vector VectorScaleReciprocal(Vector v, double s)
{
	return (Vector){ v.x / s, v.y / s, v.z / s };
}


static inline Vector VectorNormal(Vector v)
{
	return VectorScaleReciprocal(v, VectorMagnitude(v));
}
