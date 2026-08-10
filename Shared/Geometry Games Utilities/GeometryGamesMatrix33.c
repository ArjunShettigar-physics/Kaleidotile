//	GeometryGamesMatrix33.c
//
//	© 2021 by Jeff Weeks
//	See TermsOfUse.txt

#include "GeometryGamesMatrix33.h"
#include <math.h>


void Matrix33Identity(double m[3][3])
{
	m[0][0] = 1.0;  m[0][1] = 0.0;  m[0][2] = 0.0;
	m[1][0] = 0.0;  m[1][1] = 1.0;  m[1][2] = 0.0;
	m[2][0] = 0.0;  m[2][1] = 0.0;  m[2][2] = 1.0;
}

void Matrix33Copy(
	double	dst[3][3],	//	output destination matrix
	double	src[3][3])	//	input  source matrix
{
	unsigned int	i,
					j;

	for (i = 0; i < 3; i++)
		for (j = 0; j < 3; j++)
			dst[i][j] = src[i][j];
}

void Matrix33Product(
	/*const*/ double	m1[3][3],		//	input first  factor
	/*const*/ double	m2[3][3],		//	input second factor
	          double	product[3][3])	//	output product, which may coincide with either or both inputs
{
	unsigned int	i,
					j,
					k;
	double			temp[3][3];

	for (i = 0; i < 3; i++)
	{
		for (j = 0; j < 3; j++)
		{
			temp[i][j] =  0.0;
			for (k = 0; k < 3; k++)
				temp[i][j] += m1[i][k] * m2[k][j];
		}
	}

	for (i = 0; i < 3; i++)
		for (j = 0; j < 3; j++)
			product[i][j] = temp[i][j];
}

double Matrix33Determinant(double m[3][3])
{
	return m[0][0] * m[1][1] * m[2][2]
		 + m[0][1] * m[1][2] * m[2][0]
		 + m[0][2] * m[1][0] * m[2][1]
		 - m[0][0] * m[1][2] * m[2][1]
		 - m[0][1] * m[1][0] * m[2][2]
		 - m[0][2] * m[1][1] * m[2][0];
}

void Matrix33CramersRule(
	//	Uses Cramer's Rule to solve 
	//	the matrix equation a x = b.
	double	a[3][3],	//	input
	double	x[3][3],	//	output
	double	b[3][3])	//	input
{
	double			theDeterminant,
					theModifiedMatrix[3][3],
					theModifiedMatrixDeterminant;
	unsigned int	i,
					j,
					k,
					l;
	
	//	Pre-compute the determinant.
	theDeterminant = Matrix33Determinant(a);

	//	The caller should have already tested for zero determinant.
	//	Nevertheless, just to be safe...
	if (theDeterminant == 0.0)	//	Could use an epsilon tolerance in other contexts.
	{
		//	This code should never get called,
		//	but just to be safe set the output to the identity matrix.
		Matrix33Identity(x);

		return;
	}

	//	Use Cramer's Rule to solve ax=b for x.
	for (i = 0; i < 3; i++)
	{
		for (j = 0; j < 3; j++)
		{
			//	Make a copy of 'a'.
			for (k = 0; k < 3; k++)
				for (l = 0; l < 3; l++)
					theModifiedMatrix[k][l] = a[k][l];
		
			//	Replace the i-th column of theModifiedMatrix
			//	with j-th column of 'b'.
			for (k = 0; k < 3; k++)
				theModifiedMatrix[k][i] = b[k][j];
			
			//	Compute the determinant of theModifiedMatrix.
			theModifiedMatrixDeterminant = Matrix33Determinant(theModifiedMatrix);
			
			//	Apply Cramer's Rule.
			x[i][j] = theModifiedMatrixDeterminant / theDeterminant;
		}
	}
}


//	This function applies only to rotations of Euclidean space or,
//	equivalently, isometries of a 2-sphere.  The function
//	MatrixForTranslationAlongGeodesic() in the Hyperbolic Games
//	handles isometries of the hyperbolic and Euclideans planes as well,
//	at least in the case of translations along geodesics.
//
void Matrix33ForRotationAboutAxis(
	double	anAxis[3],			//	input;  unit-length rotation axis
	double	anAngle,			//	input
	double	aRotation[3][3])	//	output
{
	double			*u,
					theSine,
					theCosine,
					id[3][3],
					k[3][3],
					kk[3][3];
	unsigned int	i,
					j;

	//	For brevity...
	u = anAxis;

	//	For efficiency...
	theSine		= sin(anAngle);
	theCosine	= cos(anAngle);

	//	Rodrigues's rotation formula
	//
	//	First consider the task of rotating an arbitrary vector v
	//	through an angle θ about the axis u.  (Don't think
	//	about matrices just yet!)  The vector v naturally decomposes
	//	into components parallel and perpendicular to u:
	//
	//		v = v∥ + v⟂
	//
	//	The component v∥ is easily obtained as
	//
	//		v∥ = (v·u)u
	//
	//	(but we won't need to use that fact).
	//
	//	For v⟂ we must resist the temptation to write v⟂ = v - v∥,
	//	and instead note that
	//
	//		u × v		has the same magnitude as v⟂
	//						but is rotated 90° around u
	//
	//		u × (u × v)	has the same magnitude as v⟂
	//						but is rotated 180° around u
	//
	//	and thus
	//
	//		v⟂ = - u × (u × v)
	//
	//	The rotation through an angle θ about the axis u maps
	//
	//		v∥	↦	v∥
	//
	//		v⟂	↦	cos(θ) v⟂  +  sin(θ) u × v
	//
	//	Hence
	//
	//		v  =  v∥  +  v⟂
	//		   ↦  v∥  +  cos(θ) v⟂  +  sin(θ) u × v
	//		   =  (v - v⟂)  +  cos(θ) v⟂  +  sin(θ) u × v
	//		   =  v  +  (cos(θ) - 1) v⟂  +  sin(θ) u × v
	//		   =  v  +  (cos(θ) - 1)( - u × (u × v) )  +  sin(θ) u × v
	//		   =  v  +  (1 - cos(θ))( u × (u × v) )  +  sin(θ) u × v
	//
	//	My source for these ideas was
	//
	//		en.wikipedia.org/wiki/Rodrigues'_rotation_formula
	//
	//	which includes a nice figure illustrating these relationships.

	//	The operation of "taking a cross product with u" is linear,
	//	and may be expressed as the following matrix.  That is,
	//
	//		u × v = v k
	//
	//	(Note:  Here we use left-to-right matrix conventions,
	//	in contrast to the right-to-left conventions used on that
	//	Wikipedia page, so our matrices are transposes of theirs.)
	//
	k[0][0] =  0.0;		k[0][1] =  u[2];	k[0][2] = -u[1];
	k[1][0] = -u[2];	k[1][1] =  0.0;		k[1][2] =  u[0];
	k[2][0] =  u[1];	k[2][1] = -u[0];	k[2][2] =  0.0;

	//	To take the cross product with u twice in a row,
	//	square the matrix k.  That is,
	//
	//		u × (u × v) = v k²
	//
	Matrix33Product(k, k, kk);

	//	Prepare an identity matrix.
	Matrix33Identity(id);

	//	Applying the matrices k and k² converts the vector formula
	//
	//		v  ↦  v  +  (1 - cos(θ))( u × (u × v) )  +  sin(θ) u × v
	//
	//	into a matrix formula
	//
	//		v  ↦  v + (1 - cos(θ)) v k² + sin(θ) v k
	//		   =  v ( I + (1 - cos(θ)) k² + sin(θ) k )
	//
	//	Evaluate that matrix
	//
	//		I + (1 - cos(θ)) k² + sin(θ) k
	//
	for (i = 0; i < 3; i++)
		for (j = 0; j < 3; j++)
			aRotation[i][j] = id[i][j] + (1.0 - theCosine)*kk[i][j] + theSine*k[i][j];
}

//	This function applies only to elements of O(3).
//	The function MatrixFastGramSchmidt() in the Hyperbolic Games
//	handles matrices in O(2,1) and Isom(E²) as well.
//
void Matrix33FastGramSchmidt(
	double	m[3][3])
{
	unsigned int	i,
					j,
					k;
	double			*theRow,
					theInnerProduct,
					theFactor;

	//	Numerical errors can accumulate and force a matrix "out of round",
	//	in the sense that its rows are no longer orthonormal.
	//	This effect is small in spherical and flat spaces,
	//	but can be significant in hyperbolic spaces.

	//	The Gram-Schmidt process consists of rescaling each row to restore
	//	unit length, and subtracting small multiples of one row from another
	//	to restore orthogonality.  Here we carry out a first-order approximation
	//	to the Gram-Schmidt process.  That is, we normalize each row
	//	to unit length, but then assume that the subsequent orthogonalization step
	//	doesn't spoil the unit length.  This assumption will be well satisfied
	//	because small first order changes orthogonal to a given vector affect
	//	its length only to second order.

	//	Normalize each row to unit length.
	for (i = 0; i < 3; i++)
	{
		theRow = m[i];

		theInnerProduct = 0.0;
		for (j = 0; j < 3; j++)
			theInnerProduct += theRow[j] * theRow[j];
		
		if (theInnerProduct < 0.5)	//	theInnerProduct should always be close to 1.0, so...
		{
			Matrix33Identity(m);		//	...this code should never get called.
			return;
		}

		theFactor = 1.0 / sqrt(theInnerProduct);
		for (j = 0; j < 3; j++)
			theRow[j] *= theFactor;
	}

	//	Make the rows orthogonal.
	for (i = 3; i-- > 0; )	//	leaves the last row untouched
	{
		for (j = i; j-- > 0; )
		{
			theInnerProduct = 0.0;
			for (k = 0; k < 3; k++)
				theInnerProduct += m[i][k] * m[j][k];

			for (k = 0; k < 3; k++)
				m[j][k] -= theInnerProduct * m[i][k];
		}
	}
}


void Matrix33RowVectorTimesMatrix(
	double	v[3],		//	input
	double	m[3][3],	//	input
	double	vm[3])		//	output, OK to pass same array as v
{
	unsigned int	i,
					j;
	double			temp[3];
	
	for (i = 0; i < 3; i++)
	{
		temp[i] = 0.0;
		for (j = 0; j < 3; j++)
			temp[i] += v[j] * m[j][i];
	}

	for (i = 0; i < 3; i++)
		vm[i] = temp[i];
}


void Matrix33DoubleToFloat(
	/*const*/ double	aSrc[3][3],
			  float		aDst[3][3])
{
	unsigned int	i,
					j;

	for (i = 0; i < 3; i++)
		for (j = 0; j < 3; j++)
			aDst[i][j] = (float) aSrc[i][j];
}
