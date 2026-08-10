//	GeometryGamesMeshes.c
//
//	© 2023 by Jeff Weeks
//	See TermsOfUse.txt

#include "GeometryGamesMeshes.h"
#include "GeometryGamesUtilities-Common.h"
#include <math.h>


#define PI	3.14159265358979323846	//	π


#pragma mark -
#pragma mark sphere

//	An icosahedron is the most efficient starting point
//	for a triangulation of a sphere, so let's start with that.
//	Each successive subdivision quadruples the number of facets:
//
//		level 0		   20 facets (icosahedron)
//		level 1		   80 facets
//		level 2		  320 facets
//		level 3		 1280 facets
//		level 4		 5120 facets
//		level 5		20480 facets
//
//	Allow for up to three subdivisions of the icosahedron,
//	which realizes the sphere as a polyhedron with 1280 facets.
//
//	Note:  If we pushed the refinement level too ridiculously high,
//	the vertex indices would overflow the 16-bit ints that our
//	usual GPU functions use to store them and we'd have to use 32-bit ints instead.
//	Large numbers of vertices would also require an unreasonable amount
//	of memory for theNewVertexTable[][] in SubdivideMesh().
//
#define MAX_SPHERE_REFINEMENT_LEVEL		3

//	The number of facets quadruples from one refinement level to the next.
#define MAX_NUM_REFINED_SPHERE_FACETS	(20 << (2 * MAX_SPHERE_REFINEMENT_LEVEL))

//	Each facet sees three edges, but each edge gets seen twice.
#define MAX_NUM_REFINED_SPHERE_EDGES	(3 * MAX_NUM_REFINED_SPHERE_FACETS / 2)

//	Each facet sees three vertices, and -- except for the twelve original vertices --
//	each vertex gets seen six times.  To compensate for the twelve original vertices,
//	each of which gets seen only five times, but must add in a correction factor
//	of 12*(6 - 5) = 12 "missing" vertex sightings.
#define MAX_NUM_REFINED_SPHERE_VERTICES	((3 * MAX_NUM_REFINED_SPHERE_FACETS + 12*(6 - 5)) / 6)


static void InitIcosahedronOfRadiusOne(
	unsigned int *anIcosahedronNumVertices, double anIcosahedronVertices[MAX_NUM_REFINED_SPHERE_VERTICES][4],
	unsigned int *anIcosahedronNumFacets, unsigned int anIcosahedronFacets[MAX_NUM_REFINED_SPHERE_FACETS][3]);
static void SubdivideMeshOfRadiusOne(
	unsigned int aSrcNumVertices, double aSrcVertices[MAX_NUM_REFINED_SPHERE_VERTICES][4],
	unsigned int aSrcNumFacets, unsigned int aSrcFacets[MAX_NUM_REFINED_SPHERE_FACETS][3],
	unsigned int *aSubdivisionNumVertices, double aSubdivisionVertices[MAX_NUM_REFINED_SPHERE_VERTICES][4],
	unsigned int *aSubdivisionNumFacets, unsigned int aSubdivisionFacets[MAX_NUM_REFINED_SPHERE_FACETS][3]);


void GetUnitSphereMeshSize(
	unsigned int	aRefinementLevel,	//	input
	unsigned int	*aNumMeshVertices,	//	output
	unsigned int	*aNumMeshFacets)	//	output
{
	unsigned int	v[MAX_SPHERE_REFINEMENT_LEVEL + 1],	//	number of vertices at each refinement level
					e[MAX_SPHERE_REFINEMENT_LEVEL + 1],	//	number of  edges   at each refinement level
					f[MAX_SPHERE_REFINEMENT_LEVEL + 1],	//	number of  faces   at each refinement level
					i;

	GEOMETRY_GAMES_ASSERT(
		aRefinementLevel <= MAX_SPHERE_REFINEMENT_LEVEL,
		"Invalid unit sphere refinement level");

	//	MakeUnitSphereMesh() starts with an icosahedron...
	v[0] = 12;
	e[0] = 30;
	f[0] = 20;
	
	//	...and then repeatedly subdivides the mesh,
	//	replacing each old facet with four new ones.
	//
	//		  /\		//
	//		 /__\		//
	//		/_\/_\		//
	//
	for (i = 1; i <= aRefinementLevel; i++)
	{
		v[i] = v[i-1] + e[i-1];
		e[i] = 2*e[i-1] + 3*f[i-1];
		f[i] = 4*f[i-1];
	}
	
	*aNumMeshVertices	= v[aRefinementLevel];
	*aNumMeshFacets		= f[aRefinementLevel];
}

void MakeUnitSphereMesh(
	unsigned int	aRefinementLevel,		//	input
	double			(*aVertexBuffer)[4],	//	buffer to receive output
	unsigned int	aVertexBufferByteCount,	//	buffer size
	unsigned int	(*aFacetBuffer)[3],		//	buffer to receive output
	unsigned int	aFacetBufferByteCount)	//	buffer size
{
	unsigned int	theSphereNumVertices[MAX_SPHERE_REFINEMENT_LEVEL + 1];
	double			theSphereVertices[MAX_SPHERE_REFINEMENT_LEVEL + 1][MAX_NUM_REFINED_SPHERE_VERTICES][4];
	unsigned int	theSphereNumFacets[MAX_SPHERE_REFINEMENT_LEVEL + 1],
					theSphereFacets[MAX_SPHERE_REFINEMENT_LEVEL + 1][MAX_NUM_REFINED_SPHERE_FACETS][3],
					i,
					j,
					theRequiredVertexBufferByteCount,
					theRequiredFacetBufferByteCount;

	//	Design note:  In apps like Crystal Flight that use
	//	a level-of-detail approach, this code is "inefficient"
	//	in that for each successive refinement level
	//	it redundantly re-computes all previous levels.
	//	But we don't mind the inefficiency, because this code
	//	gets called only when the user creates the meshes.
	//	The simplicity of the code is more important
	//	than trivial runtime optimizations.

	GEOMETRY_GAMES_ASSERT(
			aVertexBuffer != NULL
		 && aFacetBuffer != NULL,
		"Output pointers must not be NULL");

	//	Construct an icosahedron for the base level.
	InitIcosahedronOfRadiusOne(
		&theSphereNumVertices[0],
		theSphereVertices[0],
		&theSphereNumFacets[0],
		theSphereFacets[0]);

	//	Subdivide each mesh to get the next one in the series.
	for (i = 0; i < MAX_SPHERE_REFINEMENT_LEVEL; i++)
	{
		SubdivideMeshOfRadiusOne
		(
			//	input mesh
			theSphereNumVertices[i],
			theSphereVertices[i],
			theSphereNumFacets[i],
			theSphereFacets[i],
			
			//	output mesh
			&theSphereNumVertices[i+1],
			theSphereVertices[i+1],
			&theSphereNumFacets[i+1],
			theSphereFacets[i+1]
		);
	}
	
	//	Make sure that the requested number of subdivisions isn't too large.
	GEOMETRY_GAMES_ASSERT(
		aRefinementLevel <= MAX_SPHERE_REFINEMENT_LEVEL,
		"aRefinementLevel exceeds the maximum supported level.  You may increase MAX_SPHERE_REFINEMENT_LEVEL if desired.");

	//	Make sure the caller has passed output buffers of the correct length.
	theRequiredVertexBufferByteCount = theSphereNumVertices[aRefinementLevel] * sizeof(double [4]);
	theRequiredFacetBufferByteCount  = theSphereNumFacets[aRefinementLevel]   * sizeof(unsigned int [3]);
	GEOMETRY_GAMES_ASSERT(
		aVertexBufferByteCount == theRequiredVertexBufferByteCount
	 && aFacetBufferByteCount  == theRequiredFacetBufferByteCount,
		"Output pointers have wrong size");

	//	Copy the requested subdivision to the output buffers.
	
	for (i = 0; i < theSphereNumVertices[aRefinementLevel]; i++)
		for (j = 0; j < 4; j++)
			aVertexBuffer[i][j] = theSphereVertices[aRefinementLevel][i][j];

	for (i = 0; i < theSphereNumFacets[aRefinementLevel]; i++)
		for (j = 0; j < 3; j++)
			aFacetBuffer[i][j]	= theSphereFacets[aRefinementLevel][i][j];
}

static void InitIcosahedronOfRadiusOne(
	unsigned int	*anIcosahedronNumVertices,
	double			anIcosahedronVertices[MAX_NUM_REFINED_SPHERE_VERTICES][4],
	unsigned int	*anIcosahedronNumFacets,
	unsigned int	anIcosahedronFacets[MAX_NUM_REFINED_SPHERE_FACETS][3])
{
	unsigned int	i,
					j;
	
	//	The icosahedron's (unnormalized) vertices sit at
	//
	//			( 0, ±1, ±φ)
	//			(±1, ±φ,  0)
	//			(±φ,  0, ±1)
	//
	//	where φ is the golden ratio.  The golden ratio is a root
	//	of the irreducible polynomial φ² - φ - 1,
	//	with numerical value φ = (1 + √5)/2 ≈ 1.6180339887…

#define GR	1.61803398874989484820
#define NF	0.52573111211913360603	//	inverse length of unnormalized vertex = 1/√(φ² + 1)
#define A	( 1.0 * NF )
#define B	( GR  * NF )

	//	The icosahedron's 12 vertices, normalized to unit length
	static const double			v[12][3] =
								{
									{0.0,  -A,  -B},
									{0.0,  +A,  -B},
									{0.0,  -A,  +B},
									{0.0,  +A,  +B},

									{ -A,  -B, 0.0},
									{ +A,  -B, 0.0},
									{ -A,  +B, 0.0},
									{ +A,  +B, 0.0},

									{ -B, 0.0,  -A},
									{ -B, 0.0,  +A},
									{ +B, 0.0,  -A},
									{ +B, 0.0,  +A}
								};

	//	The icosahedron's 20 faces
	static const unsigned int	f[20][3] =
								{
									//	Winding order is clockwise when viewed
									//	from outside the icosahedron in a left-handed coordinate system.

									//	side-based faces

									{ 0,  8,  1},
									{ 1, 10,  0},
									{ 2, 11,  3},
									{ 3,  9,  2},

									{ 4,  0,  5},
									{ 5,  2,  4},
									{ 6,  3,  7},
									{ 7,  1,  6},

									{ 8,  4,  9},
									{ 9,  6,  8},
									{10,  7, 11},
									{11,  5, 10},

									//	corner-based faces
									{ 0,  4,  8},
									{ 2,  9,  4},
									{ 1,  8,  6},
									{ 3,  6,  9},
									{ 0, 10,  5},
									{ 2,  5, 11},
									{ 1,  7, 10},
									{ 3, 11,  7}
								};

	//	vertices

	*anIcosahedronNumVertices = 12;

	for (i = 0; i < 12; i++)
	{
		for (j = 0; j < 3; j++)
			anIcosahedronVertices[i][j] = v[i][j];

		anIcosahedronVertices[i][3] = 1.0;
	}

	//	facets
	
	*anIcosahedronNumFacets = 20;

	for (i = 0; i < 20; i++)
	{
		for (j = 0; j < 3; j++)
			anIcosahedronFacets[i][j] = f[i][j];
	}
}

static void SubdivideMeshOfRadiusOne(

	//	the source mesh (input)
	unsigned int	aSrcNumVertices,
	double			aSrcVertices[MAX_NUM_REFINED_SPHERE_VERTICES][4],
	unsigned int	aSrcNumFacets,
	unsigned int	aSrcFacets[MAX_NUM_REFINED_SPHERE_FACETS][3],
	
	//	the subdivided mesh (output)
	unsigned int	*aSubdivisionNumVertices,
	double			aSubdivisionVertices[MAX_NUM_REFINED_SPHERE_VERTICES][4],
	unsigned int	*aSubdivisionNumFacets,
	unsigned int	aSubdivisionFacets[MAX_NUM_REFINED_SPHERE_FACETS][3])
{
	unsigned int	theVertexCount,
					i,
					j,
					k,
					(*theNewVertexTable)[MAX_NUM_REFINED_SPHERE_VERTICES],
					v0,
					v1;
	double			theLengthSquared,
					theFactor;
	unsigned int	*v,
					vv[3];

	GEOMETRY_GAMES_ASSERT(
		aSrcNumVertices <= MAX_NUM_REFINED_SPHERE_VERTICES,
		"too many source vertices");
	GEOMETRY_GAMES_ASSERT(
		aSrcNumFacets   <= MAX_NUM_REFINED_SPHERE_FACETS,
		"too many source facets"  );

	//	We'll subdivide the mesh, replacing each old facet with four new ones.
	//
	//		  /\		//
	//		 /__\		//
	//		/_\/_\		//
	//
	*aSubdivisionNumFacets = 4 * aSrcNumFacets;

	//	Each facet sees three vertices, and -- except for the twelve original vertices --
	//	each vertex gets seen six times.  To compensate for the twelve original vertices,
	//	each of which gets seen only five times, but must add in a correction factor
	//	of 12*(6 - 5) = 12 "missing" vertex sightings.
	*aSubdivisionNumVertices = (3*(*aSubdivisionNumFacets) + 12*(6 - 5)) / 6;

	GEOMETRY_GAMES_ASSERT(
		*aSubdivisionNumVertices <= MAX_NUM_REFINED_SPHERE_VERTICES,
		"too many subdivision vertices");
	GEOMETRY_GAMES_ASSERT(
		*aSubdivisionNumFacets   <= MAX_NUM_REFINED_SPHERE_FACETS,
		"too many subdivision facets"  );

	
	//	First copy the source mesh vertex positions to the destination mesh...
	for (i = 0; i < aSrcNumVertices; i++)
		for (j = 0; j < 4; j++)
			aSubdivisionVertices[i][j]	= aSrcVertices[i][j];
	theVertexCount = aSrcNumVertices;

	//	...and then create one new vertex on each edge.
	//
	//	Use theNewVertexTable[][] to index them,
	//	so two facets sharing an edge can share the same vertex.
	//
	//	theNewVertexTable[v0][v1] takes the indices v0 and v1 of two old vertices,
	//	and gives the index of the new vertex that sits at the midpoint of the edge
	//	that connects v0 and v1.
	//
	//	The size of theNewVertexTable grows as the square of the number of source vertices.
	//	For modest meshes this won't be a problem.  For larger meshes a fancier algorithm,
	//	with linear rather than quadratic memory demands, could be used.
	//
	theNewVertexTable = (unsigned int (*)[MAX_NUM_REFINED_SPHERE_VERTICES])
			malloc( aSrcNumVertices * sizeof(unsigned int [MAX_NUM_REFINED_SPHERE_VERTICES]) );
	GEOMETRY_GAMES_ASSERT(
		theNewVertexTable != NULL,
		"failed to allocate memory for theNewVertexTable");

	//	Initialize theNewVertexTable[][] to all 0xFFFF,
	//	to indicate that no new vertices have yet been created.
	for (i = 0; i < aSrcNumVertices; i++)
		for (j = 0; j < aSrcNumVertices; j++)
			theNewVertexTable[i][j] = 0xFFFF;

	//	For each edge in the source mesh, create a new vertex at its midpoint.
	for (i = 0; i < aSrcNumFacets; i++)
	{
		for (j = 0; j < 3; j++)
		{
			v0 = aSrcFacets[i][   j   ];
			v1 = aSrcFacets[i][(j+1)%3];

			if (theNewVertexTable[v0][v1] == 0xFFFF)
			{
				GEOMETRY_GAMES_ASSERT(
					theVertexCount < *aSubdivisionNumVertices,
					"Internal error #1 in SubdivideMesh()");
				
				//	The new vertex will be midway between vertices v0 and v1.
				for (k = 0; k < 3; k++)
				{
					aSubdivisionVertices[theVertexCount][k]
						= 0.5 * (aSubdivisionVertices[v0][k] + aSubdivisionVertices[v1][k]);
				}
				theLengthSquared = 0.0;
				for (k = 0; k < 3; k++)
				{
					theLengthSquared += aSubdivisionVertices[theVertexCount][k]
									  * aSubdivisionVertices[theVertexCount][k];
				}
				GEOMETRY_GAMES_ASSERT(
					theLengthSquared >= 0.5,
					"Impossibly short interpolated normal vector");
				theFactor = 1.0 / sqrt(theLengthSquared);
				for (k = 0; k < 3; k++)
				{
					aSubdivisionVertices[theVertexCount][k] *= theFactor;
				}
				aSubdivisionVertices[theVertexCount][3] = 1.0;	//	last coordinate is always 1.0

				//	Record the new vertex at [v1][v0] as well as [v0][v1],
				//	so only one new vertex will get created for each edge.
				theNewVertexTable[v0][v1] = theVertexCount;
				theNewVertexTable[v1][v0] = theVertexCount;

				theVertexCount++;
			}
		}
	}
	GEOMETRY_GAMES_ASSERT(
		theVertexCount == *aSubdivisionNumVertices,
		"Internal error #2 in SubdivideMesh()");

	//	For each facet in the source mesh,
	//	create four smaller facets in the subdivision.
	for (i = 0; i < aSrcNumFacets; i++)
	{
		//	The old vertices incident to this facet will be v[0], v[1] and v[2].
		v = aSrcFacets[i];

		//	The new vertices -- which sit at the midpoints of the old edges --
		//	will be vv[0], vv[1], and vv[2].
		//	Each vv[j] sits opposite the corresponding v[j].
		for (j = 0; j < 3; j++)
			vv[j] = theNewVertexTable[ v[(j+1)%3] ][ v[(j+2)%3] ];

		//	Create the new facets.

		aSubdivisionFacets[4*i + 0][0] = vv[0];
		aSubdivisionFacets[4*i + 0][1] = vv[1];
		aSubdivisionFacets[4*i + 0][2] = vv[2];

		aSubdivisionFacets[4*i + 1][0] = v[0];
		aSubdivisionFacets[4*i + 1][1] = vv[2];
		aSubdivisionFacets[4*i + 1][2] = vv[1];

		aSubdivisionFacets[4*i + 2][0] = v[1];
		aSubdivisionFacets[4*i + 2][1] = vv[0];
		aSubdivisionFacets[4*i + 2][2] = vv[2];

		aSubdivisionFacets[4*i + 3][0] = v[2];
		aSubdivisionFacets[4*i + 3][1] = vv[1];
		aSubdivisionFacets[4*i + 3][2] = vv[0];
	}
	
	free(theNewVertexTable);
}


#pragma mark -
#pragma mark cylinder

//	At the coarsest level, triangulate the cylinder as a triangular antiprism,
//	with 3 vertices at each end and 3 triangles pointing in each direction.
#define COARSEST_N	3

//	For each successive refinement level, double the numbers of vertices and faces:
//
//		level 0		    6 facets (triangular antiprism)
//		level 1		   12 facets (hexagonal antiprism)
//		level 2		   24 facets
//		level 3		   48 facets
//
//	Allow for up to refinement level 3.
//
#define MAX_CYLINDER_REFINEMENT_LEVEL		3
#define MAX_NUM_REFINED_CYLINDER_VERTICES	((2 * COARSEST_N) << MAX_CYLINDER_REFINEMENT_LEVEL)
#define MAX_NUM_REFINED_CYLINDER_FACETS		MAX_NUM_REFINED_CYLINDER_VERTICES


void GetUnitCylinderMeshSize(
	unsigned int	aRefinementLevel,	//	input
	unsigned int	*aNumMeshVertices,	//	output
	unsigned int	*aNumMeshFacets)	//	output
{
	unsigned int	v,	//	number of vertices
					e,	//	number of edges (unused here, but included for clarity)
					f,	//	number of faces
					i;

	GEOMETRY_GAMES_ASSERT(
		aRefinementLevel <= MAX_CYLINDER_REFINEMENT_LEVEL,
		"Invalid unit cylinder refinement level");

	//	MakeUnitCylinderMesh() starts with a triangular antiprism...
	v =  6;
	e = 12;
	f =  6;
	
	//	...and then for each successive refinement level,
	//	doubles the numbers of vertices and faces,
	//	to give a hexagonal antiprism, a dodecagonal antiprism, etc.
	//
	for (i = 1; i <= aRefinementLevel; i++)
	{
		v *= 2;
		e *= 2;
		f *= 2;
	}
	
	*aNumMeshVertices	= v;
	*aNumMeshFacets		= f;
}

void MakeUnitCylinderMesh(
	unsigned int	aRefinementLevel,		//	input
	double			(*aVertexBuffer)[4],	//	buffer to receive output
	unsigned int	aVertexBufferByteCount,	//	buffer size
	unsigned int	(*aFacetBuffer)[3],		//	buffer to receive output
	unsigned int	aFacetBufferByteCount)	//	buffer size
{
	unsigned int	n,
					theNumMeshVertices,
					theNumMeshFacets,
					theRequiredVertexBufferByteCount,
					theRequiredFacetBufferByteCount,
					i;
	double			theAngle;

	GEOMETRY_GAMES_ASSERT(
			aVertexBuffer != NULL
		 && aFacetBuffer  != NULL,
		"Output pointers must not be NULL");

	//	Make sure that the refinement level isn't too large.
	GEOMETRY_GAMES_ASSERT(
		aRefinementLevel <= MAX_CYLINDER_REFINEMENT_LEVEL,
		"aRefinementLevel exceeds the maximum supported level.  You may increase MAX_CYLINDER_REFINEMENT_LEVEL if desired.");

	//	Let n be the number of vertices at each end of the cylinder,
	//	which also equals the number of facets pointing in each direction.
	n = (COARSEST_N << aRefinementLevel);

	//	We know that with
	//
	//		aRefinementLevel <= MAX_CYLINDER_REFINEMENT_LEVEL
	//
	//	the preceding bitshift
	//
	//		COARSEST_N << aRefinementLevel
	//
	//	will never overflow, but Xcode's static analyzer doesn't
	//	get the message unless we explicitly say that 2*n != 0.
	GEOMETRY_GAMES_ASSERT(2*n != 0, "n should always be non-zero");

	//	Note the number of vertices and facets.
	theNumMeshVertices	= 2 * n;
	theNumMeshFacets	= 2 * n;

	//	Make sure the caller has passed output buffers of the correct length.
	theRequiredVertexBufferByteCount = theNumMeshVertices * sizeof(double [4]);
	theRequiredFacetBufferByteCount  = theNumMeshFacets   * sizeof(unsigned int [3]);
	GEOMETRY_GAMES_ASSERT(
		aVertexBufferByteCount == theRequiredVertexBufferByteCount
	 && aFacetBufferByteCount  == theRequiredFacetBufferByteCount,
		"Output pointers have wrong size");

	//	Let the vertices sit on a cylinder whose cross section
	//	is a unit circle in the xy plane, and whose ends sit at z = ±1.
	for (i = 0; i < 2*n; i++)
	{
		theAngle = 2.0 * PI * (double)i / (double)(2*n);

		aVertexBuffer[i][0] = cos(theAngle);
		aVertexBuffer[i][1] = sin(theAngle);
		aVertexBuffer[i][2] = (i & 1) ? +1.0 : -1.0;
		aVertexBuffer[i][3] = 1.0;
	}

	//	Let the facets wind clockwise when viewed from the outside
	//	in a left-handed coordinate system.
	for (i = 0; i < n; i++)
	{
		aFacetBuffer[2*i + 0][0] = (2*i + 0) % (2*n);
		aFacetBuffer[2*i + 0][1] = (2*i + 2) % (2*n);
		aFacetBuffer[2*i + 0][2] = (2*i + 1) % (2*n);

		aFacetBuffer[2*i + 1][0] = (2*i + 1) % (2*n);
		aFacetBuffer[2*i + 1][1] = (2*i + 2) % (2*n);
		aFacetBuffer[2*i + 1][2] = (2*i + 3) % (2*n);
	}
}
