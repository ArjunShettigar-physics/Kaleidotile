//	GeometryGamesUtilities-SIMD.c
//
//	© 2023 by Jeff Weeks
//	See TermsOfUse.txt

#include "GeometryGamesUtilities-SIMD.h"
#include "GeometryGamesUtilities-Common.h"	//	for GEOMETRY_GAMES_ASSERT()


simd_float3x3	ConvertMatrix33ToSIMD(
	const double	aMatrix[3][3])
{
	simd_float3x3	theMatrix	= matrix_identity_float3x3;	//	initialize to suppress compiler warning
	unsigned int	i,
					j;
	
	//	aMatrix is stored in row-major order and acts as
	//
	//		(row vector)(aMatrix)
	//
	//	while theMatrix is stored in column-major order and acts as
	//
	//		(theMatrix)(column vector)
	//
	//	Thus we can simply copy the [i][j] element of one
	//	to the [i][j] element of the other, without transposing.
	
	for (i = 0; i < 3; i++)
		for (j = 0; j < 3; j++)
			theMatrix.columns[i][j] = (float) aMatrix[i][j];

	return theMatrix;
}

simd_float4x4	ConvertMatrix44ToSIMD(
	const double	aMatrix[4][4])
{
	simd_float4x4	theMatrix	= matrix_identity_float4x4;	//	initialize to suppress compiler warning
	unsigned int	i,
					j;
	
	//	aMatrix is stored in row-major order and acts as
	//
	//		(row vector)(aMatrix)
	//
	//	while theMatrix is stored in column-major order and acts as
	//
	//		(theMatrix)(column vector)
	//
	//	Thus we can simply copy the [i][j] element of one
	//	to the [i][j] element of the other, without transposing.
	
	//	Performance note:  On macOS 10.13.6 (and maybe other versions of macOS
	//	and/or iOS), assigning elements to a simd_float4x4 is very slow.
	//	I don't know why.  However, I did some testing and found that
	//	(1)	the double→float conversion was not to blame,
	//	(2) returning the result by reference (using a parameter
	//		simd_float4x4 *aResult) doesn't solve the problem,
	//	(3) making the function inline doesn't solve the problem.
	
	for (i = 0; i < 4; i++)
		for (j = 0; j < 4; j++)
			theMatrix.columns[i][j] = (float) aMatrix[i][j];

	return theMatrix;
}

simd_float4x4 ConvertMatrix44fToSIMD(
	const float	aMatrix[4][4])
{
	simd_float4x4	theMatrix	= matrix_identity_float4x4;	//	initialize to suppress compiler warning
	unsigned int	i,
					j;
	
	//	aMatrix is stored in row-major order and acts as
	//
	//		(row vector)(aMatrix)
	//
	//	while theMatrix is stored in column-major order and acts as
	//
	//		(theMatrix)(column vector)
	//
	//	Thus we can simply copy the [i][j] element of one
	//	to the [i][j] element of the other, without transposing.
	
	for (i = 0; i < 4; i++)
		for (j = 0; j < 4; j++)
			theMatrix.columns[i][j] = aMatrix[i][j];

	return theMatrix;
}

simd_float2 ConvertVector2toSIMD(
	const double	aVector[2])
{
	simd_float2	theVector;
	
	theVector[0] = (float) aVector[0];
	theVector[1] = (float) aVector[1];
	
	return theVector;
}

simd_float2 ConvertVector2ftoSIMD(
	const float	aVector[2])
{
	simd_float2	theVector;
	
	theVector[0] = aVector[0];
	theVector[1] = aVector[1];
		
	return theVector;
}

simd_float3 ConvertVector3toSIMD(
	const double	aVector[3])
{
	simd_float3	theVector;
	
	theVector[0] = (float) aVector[0];
	theVector[1] = (float) aVector[1];
	theVector[2] = (float) aVector[2];
	
	return theVector;
}

simd_float3 ConvertVector3ftoSIMD(
	const float	aVector[3])
{
	simd_float3	theVector;
	
	theVector[0] = aVector[0];
	theVector[1] = aVector[1];
	theVector[2] = aVector[2];
	
	return theVector;
}

simd_float4 ConvertVector4toSIMD(
	const double	aVector[4])
{
	simd_float4	theVector;
	
	theVector[0] = (float) aVector[0];
	theVector[1] = (float) aVector[1];
	theVector[2] = (float) aVector[2];
	theVector[3] = (float) aVector[3];
	
	return theVector;
}

simd_half4 ConvertVector4toSIMDHalf(
	const double	aVector[4])
{
	simd_half4	theVector;
	
	theVector[0] = (__fp16) aVector[0];
	theVector[1] = (__fp16) aVector[1];
	theVector[2] = (__fp16) aVector[2];
	theVector[3] = (__fp16) aVector[3];
	
	return theVector;
}

simd_float4 ConvertVector4ftoSIMD(
	const float	aVector[4])
{
	simd_float4	theVector;
	
	theVector[0] = (float) aVector[0];
	theVector[1] = (float) aVector[1];
	theVector[2] = (float) aVector[2];
	theVector[3] = (float) aVector[3];
	
	return theVector;
}

simd_half4 ConvertVector4ftoSIMDHalf(
	const float	aVector[4])
{
	simd_half4	theVector;
	
	theVector[0] = (__fp16) aVector[0];
	theVector[1] = (__fp16) aVector[1];
	theVector[2] = (__fp16) aVector[2];
	theVector[3] = (__fp16) aVector[3];
	
	return theVector;
}

simd_half4 ConvertLinearDisplayP3ToSIMDHalf(
	double	r,
	double	g,
	double	b,
	double	a)
{
	simd_half4	theVector;
	
	theVector[0] = (__fp16) r;
	theVector[1] = (__fp16) g;
	theVector[2] = (__fp16) b;
	theVector[3] = (__fp16) a;
	
	return theVector;
}


float EuclideanDeterminantSIMD(
	simd_float4x4	*m)
{
	float	theDeterminant;
	
	//	Because the last column of m is always (0, 0, 0, 1) ...
	GEOMETRY_GAMES_ASSERT(	m->columns[0][3] == 0.0
						 && m->columns[1][3] == 0.0
						 && m->columns[2][3] == 0.0
						 && m->columns[3][3] == 1.0,
		"matrix m is not a Euclidean motion");
	
	//	...we may simplify the computation by computing the determinant
	//	of the upper-left 3×3 submatrix alone.
	//
	theDeterminant	= m->columns[0][0] * m->columns[1][1] * m->columns[2][2]
					+ m->columns[0][1] * m->columns[1][2] * m->columns[2][0]
					+ m->columns[0][2] * m->columns[1][0] * m->columns[2][1]
					- m->columns[0][2] * m->columns[1][1] * m->columns[2][0]
					- m->columns[0][0] * m->columns[1][2] * m->columns[2][1]
					- m->columns[0][1] * m->columns[1][0] * m->columns[2][2];

	return theDeterminant;
}
