//	GeometryGamesMatrix44.c
//
//	© 2023 by Jeff Weeks
//	See TermsOfUse.txt

#include "GeometryGamesMatrix44.h"
#include "GeometryGamesUtilities-Common.h"	//	for GEOMETRY_GAMES_ASSERT()


void Matrix44Identity(double m[4][4])
{
	unsigned int	i,
					j;

	for (i = 0; i < 4; i++)
		for (j = 0; j < 4; j++)
			m[i][j] = (i == j ? 1.0 : 0.0);
}

void Matrix44Zero(double m[4][4])
{
	unsigned int	i,
					j;

	for (i = 0; i < 4; i++)
		for (j = 0; j < 4; j++)
			m[i][j] = 0.0;
}

void Matrix44Copy(
	          double	dst[4][4],	//	output destination matrix
	/*const*/ double	src[4][4])	//	input  source matrix
{
	unsigned int	i,
					j;

	for (i = 0; i < 4; i++)
		for (j = 0; j < 4; j++)
			dst[i][j] = src[i][j];
}

void Matrix44Product(
	/*const*/ double	m1[4][4],		//	input first  factor
	/*const*/ double	m2[4][4],		//	input second factor
	          double	product[4][4])	//	output product, which may coincide with either or both inputs
{
	unsigned int	i,
					j,
					k;
	double			temp[4][4];

	for (i = 0; i < 4; i++)
	{
		for (j = 0; j < 4; j++)
		{
			temp[i][j] =  0.0;
			for (k = 0; k < 4; k++)
				temp[i][j] += m1[i][k] * m2[k][j];
		}
	}

	for (i = 0; i < 4; i++)
		for (j = 0; j < 4; j++)
			product[i][j] = temp[i][j];
}

void Matrix44GeometricInverse(
	/*const*/ double	m[4][4],		//	input
	          double	mInverse[4][4])	//	output (may coincide with input)
{
	//	Invert a matrix in O(4), Isom(E³) or O(3,1).
	//	Work geometrically for better precision than
	//	row-reduction methods would provide.

	double			theInverse[4][4];
	unsigned int	i,
					j;

	//	Spherical case O(4)
	if (m[3][3] < 1.0)
	{
		//	The inverse is the transpose.
		for (i = 0; i < 4; i++)
			for (j = 0; j < 4; j++)
				theInverse[i][j] = m[j][i];
	}
	else
	//	Flat case Isom(E³)
	//	(Also works for elements of O(4) and O(3,1) that fix the origin.)
	if (m[3][3] == 1.0)
	{
		//	The upper-left 3×3 block is the transpose of the original.
		for (i = 0; i < 3; i++)
			for (j = 0; j < 3; j++)
				theInverse[i][j] = m[j][i];

		//	The right-most column is mostly zeros.
		for (i = 0; i < 3; i++)
			theInverse[i][3] = 0.0;

		//	The bottom row is the negative of a matrix product.
		for (i = 0; i < 3; i++)
		{
			theInverse[3][i] = 0.0;
			for (j = 0; j < 3; j++)
				theInverse[3][i] -= m[3][j] * m[i][j];
		}

		//	The bottom right entry is 1.
		theInverse[3][i] = 1.0;
	}
	else
	//	Hyperbolic case O(3,1)
	if (m[3][3] > 1.0)
	{
		//	The inverse is the transpose,
		//	but with a few minus signs thrown in.
		for (i = 0; i < 4; i++)
			for (j = 0; j < 4; j++)
				theInverse[i][j] = ((i == 3) == (j == 3)) ? m[j][i] : -m[j][i];
	}
	else
	//	Can never occur.
	{
		Matrix44Identity(theInverse);
	}

	//	Copy the result to the output variable.
	for (i = 0; i < 4; i++)
		for (j = 0; j < 4; j++)
			mInverse[i][j] = theInverse[i][j];
}

void Matrix44RowVectorTimesMatrix(
	  const   double	v[4],		//	input
	/*const*/ double	m[4][4],	//	input
	          double	vm[4])		//	output, OK to pass same array as v
{
	unsigned int	i,
					j;
	double			temp[4];
	
	for (i = 0; i < 4; i++)
	{
		temp[i] = 0.0;
		for (j = 0; j < 4; j++)
			temp[i] += v[j] * m[j][i];
	}

	for (i = 0; i < 4; i++)
		vm[i] = temp[i];
}

void Matrix44TimesColumnVector(
	/*const*/ double	m[4][4],	//	input
	  const   double	v[4],		//	input
	          double	mv[4])		//	output, OK to pass same array as v
{
	unsigned int	i,
					j;
	double			temp[4];
	
	for (i = 0; i < 4; i++)
	{
		temp[i] = 0.0;
		for (j = 0; j < 4; j++)
			temp[i] += m[i][j] * v[j];
	}

	for (i = 0; i < 4; i++)
		mv[i] = temp[i];
}

double Matrix44EuclideanDeterminant(
	/*const*/ double	m[4][4])
{
	double	theDeterminant;
	
	//	Because the last column of m is always (0, 0, 0, 1) ...
	GEOMETRY_GAMES_ASSERT(	m[0][3] == 0.0
						 && m[1][3] == 0.0
						 && m[2][3] == 0.0
						 && m[3][3] == 1.0,
		"matrix m is not a Euclidean motion");
	
	//	...we may simplify the computation by computing the determinant
	//	of the upper-left 3×3 submatrix alone.
	//
	theDeterminant	= m[0][0] * m[1][1] * m[2][2]
					+ m[0][1] * m[1][2] * m[2][0]
					+ m[0][2] * m[1][0] * m[2][1]
					- m[0][2] * m[1][1] * m[2][0]
					- m[0][0] * m[1][2] * m[2][1]
					- m[0][1] * m[1][0] * m[2][2];

	return theDeterminant;
}


void Matrix44ExtendingMatrix33(
	double	s[3][3],	//	3×3 source matrix
	double	d[4][4])	//	4×4 destination matrix
{
	d[0][0] = s[0][0];   d[0][1] = s[0][1];   d[0][2] = s[0][2];   d[0][3] = 0.0;
	d[1][0] = s[1][0];   d[1][1] = s[1][1];   d[1][2] = s[1][2];   d[1][3] = 0.0;
	d[2][0] = s[2][0];   d[2][1] = s[2][1];   d[2][2] = s[2][2];   d[2][3] = 0.0;
	d[3][0] = 0.0;       d[3][1] = 0.0;       d[3][2] = 0.0;       d[3][3] = 1.0;
}

void Matrix44DoubleToFloat(
	/*const*/ double	aSrc[4][4],
			  float		aDst[4][4])
{
	unsigned int	i,
					j;

	for (i = 0; i < 4; i++)
		for (j = 0; j < 4; j++)
			aDst[i][j] = (float) aSrc[i][j];
}
