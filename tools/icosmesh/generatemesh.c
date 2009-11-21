#import "OOPlanetData.h"
#import "OOMaths.h"
#import <stdio.h>
#import <assert.h>

#define kScale		500
#define	UNWRAP		0		// Generate flat "unwrapped" mesh, demonstrating texture map construction.


#if !UNWRAP
static Vector GetVector(GLuint idx)
{
	return make_vector(kOOPlanetVertices[idx * 3], kOOPlanetVertices[idx * 3 + 1], kOOPlanetVertices[idx * 3 + 2]);
}

static Vector GetNormal(GLuint a, GLuint b, GLuint c)
{
	Vector va = GetVector(a);
	Vector vb = GetVector(b);
	Vector vc = GetVector(c);
	return vector_normal(vector_add(va, vector_add(vb, vc)));
}
#else
static Vector GetVector(GLuint idx)
{
	return make_vector(1.0 - kOOPlanetTexCoords[idx * 2] * 2.0f, 0.5 - kOOPlanetTexCoords[idx * 2 + 1], 0);
}

static Vector GetNormal(GLuint a, GLuint b, GLuint c)
{
	return kBasisZVector;
}
#endif


static void WriteDAT(unsigned i);


int main (int argc, const char * argv[])
{
	unsigned i;
	for (i = 0; i < kOOPlanetDataLevels; i++)
	{
		WriteDAT(i);
	}
	
	return EXIT_SUCCESS;
}


static void WriteDAT(unsigned level)
{
	const OOPlanetDataLevel *data = &kPlanetData[level];
	
	char name[20];
	snprintf(name, 20, "level_%u.dat", level);
	FILE *file = fopen(name, "w");
	
	fprintf(file, "# Planet mesh export (level %u)\n\nNVERTS %u\nNFACES %u\n\nVERTEX\n", level, data->vertexCount, data->faceCount);
	
	unsigned i;
	for (i = 0; i < data->vertexCount; i++)
	{
		Vector v = vector_multiply_scalar(GetVector(i), kScale);
		fprintf(file, "%g, %g, %g\n", v.x, v.y, v.z);
	}
	
	fprintf(file, "\nFACES\n");
	for (i = 0; i < data->faceCount; i++)
	{
		GLuint a = data->indices[i * 3];
		GLuint b = data->indices[i * 3 + 1];
		GLuint c = data->indices[i * 3 + 2];
		
		Vector n = GetNormal(a, b, c);
		
		fprintf(file, "1,0,0,   %+.5f, %+.5f, %+.5f,   3, %u,%u,%u\n", n.x, n.y, n.z, a, b, c);
	}
	
	fprintf(file, "\nTEXTURES\n");
	for (i = 0; i < data->faceCount; i++)
	{
		GLuint a = data->indices[i * 3];
		GLuint b = data->indices[i * 3 + 1];
		GLuint c = data->indices[i * 3 + 2];
		
		fprintf(file, "world.png   1 1   %.5f %.5f   %.5f %.5f   %.5f %.5f\n", kOOPlanetTexCoords[a * 2], kOOPlanetTexCoords[a * 2 + 1], kOOPlanetTexCoords[b * 2], kOOPlanetTexCoords[b * 2 + 1], kOOPlanetTexCoords[c * 2], kOOPlanetTexCoords[c * 2 + 1]);
	}
	
	fprintf(file, "\nEND\n");
	fclose(file);
}

