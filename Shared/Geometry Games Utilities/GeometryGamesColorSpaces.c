//	GeometryGamesColorSpaces.c
//
//	© 2023 by Jeff Weeks
//	See TermsOfUse.txt


#include "GeometryGamesColorSpaces.h"
#include <stdbool.h>	//	for bool, true and false
#include <math.h>


typedef struct
{
	//	The CIE 1931 x and y values are the "source of truth" for a chromaticity.
	double	x,
			y;
			
	//	The CIE 1931 z value follows easily as z = 1 - (x + y).
	double	z;
	
	//	The CIE 1931 (X,Y,Z) vector is a multiple of (x,y,z).
	//	The length depends not on a single chromaticity alone,
	//	but on a set of colors {Red, Green, Green, WhitePoint},
	//	with lengths chosen so that
	//
	//		Red + Green + Green = WhitePoint
	//	and
	//		the WhitePoint's Y component is 1.
	//
	double	X,
			Y,
			Z;
} Color;

typedef struct
{
	Color	red,
			green,
			blue,
			white;
} ColorProfile;


//	The following matrices serve to convert between Linear sRGB
//	and Linear Display P3.  Although it would work fine to simply
//	hard code these two matrices, for future reference and flexibility
//	I'm including the code that produces these matrices, and indeed
//	am letting that code re-create the matrices each time the app is run.
//
//		gP3toSRGB[3][3] =
//		{
//			{ 1.2249401762805587, -0.0420569547096881, -0.0196375545903344},
//			{-0.2249401762805597,  1.0420569547096874, -0.0786360455506319},
//			{ 0.0000000000000001,  0.0000000000000000,  1.0982736001409661}
//		};
//
//		gSRGBtoP3[3][3] =
//		{
//			{ 0.8224619687143629,  0.0331941988509616,  0.0170826307211200},
//			{ 0.1775380312856378,  0.9668058011490389,  0.0723974406639635},
//			{ 0.0000000000000000,  0.0000000000000000,  0.9105199286149166}
//		};
//
static bool		gColorConversionMatricesHaveBeenInitialized	= false;
static double	gP3toSRGB[3][3],
				gSRGBtoP3[3][3];


static void	InitializeColorConversionMatrices(void);
static void	MakeColorProfile(ColorProfile *p);
static void	Compute_z(Color *c);
static void	ComputeXYZ(Color *c, double m);
static void	DoGaussianEliminationOnColumns(double aTableau[6][3]);


double GammaEncode(
	double	aLinearValue)
{
	double	theGammaEncodedValue;
	
	//	The encoding curve for negative values is
	//	symmetrical with the curve for positive values.
	//
	if (aLinearValue < 0.0)
		return - GammaEncode( - aLinearValue );
	
	//	The sRGB transfer function begins with a short linear segment
	//	(to avoid an infinite slope near zero), followed by a gamma curve
	//	with power 1/2.4 thereafter.  The overall curve closely follows
	//	a traditional gamma curve (with no linear segment) with power 1/2.2.
	//
	//	My understanding is that the following numerical values are exact
	//	(defined in the IEC standard), they're not approximations.
	//
	if (aLinearValue < 0.0031308)
		theGammaEncodedValue = 12.92 * aLinearValue;
	else
		theGammaEncodedValue = 1.055 * pow(aLinearValue, 1.0/2.4) - 0.055;

	return theGammaEncodedValue;
}

double GammaDecode(
	double	aGammaEncodedValue)
{
	double	theLinearValue;

	//	The decoding curve for negative values is
	//	symmetrical with the curve for positive values.
	//
	if (aGammaEncodedValue < 0.0)
		return - GammaDecode( - aGammaEncodedValue );

	//	The sRGB transfer function begins with a short linear segment
	//	(to avoid zero slope near zero), followed by a gamma curve
	//	with power 2.4 thereafter.  The overall curve closely follows
	//	a traditional gamma curve (with no linear segment) with power 2.2.
	//
	//	My understanding is that the following numerical values are exact
	//	(defined in the IEC standard), they're not approximations.
	//
	if (aGammaEncodedValue < 0.04045)
		theLinearValue = (1.0 / 12.92) * aGammaEncodedValue;
	else
		theLinearValue = pow((1.0/1.055) * aGammaEncodedValue + (0.055/1.055), 2.4);

	return theLinearValue;
}


void ConvertXRsRGBLinearToDisplayP3Linear(
	const double	anXRsRGBColor[3],	//	input,  linear Extended sRGB
	double			aDisplayP3Color[3])	//	output, linear Display P3
{
	unsigned int	i,
					j;
	
	//	One-time initialization
	if ( ! gColorConversionMatricesHaveBeenInitialized )
	{
		InitializeColorConversionMatrices();
		gColorConversionMatricesHaveBeenInitialized = true;
	}

	for (i = 0; i < 3; i++)
	{
		aDisplayP3Color[i] = 0.0;
		
		for (j = 0; j < 3; j++)
			aDisplayP3Color[i] += anXRsRGBColor[j] * gSRGBtoP3[j][i];

		//	Just to be safe, clamp to [0.0, 1.0].
		if (aDisplayP3Color[i] < 0.0)
			aDisplayP3Color[i] = 0.0;
		if (aDisplayP3Color[i] > 1.0)
			aDisplayP3Color[i] = 1.0;
	}
}

void ConvertDisplayP3LinearToXRsRGBLinear(
	const double	aDisplayP3Color[3],	//	input,  linear Display P3
	double			anXRsRGBColor[3])	//	output, linear Extended sRGB
{
	unsigned int	i,
					j;
	
	//	One-time initialization
	if ( ! gColorConversionMatricesHaveBeenInitialized )
	{
		InitializeColorConversionMatrices();
		gColorConversionMatricesHaveBeenInitialized = true;
	}

	for (i = 0; i < 3; i++)
	{
		anXRsRGBColor[i] = 0.0;
		
		for (j = 0; j < 3; j++)
			anXRsRGBColor[i] += aDisplayP3Color[j] * gP3toSRGB[j][i];
	}
}


void ClampExtendedSRGBLinearToNonExtended(
	const double	aColorXRsRGBLinear[4],	//	input, premultiplied alpha
	double			aClampedColor[4])		//	output, premultiplied alpha,
											//		OK to pass same array for input and output
{
	unsigned int	i;
	double			theColor[4],
					theMaxRGBComponent,
					theAlpha,
					theFactor;

	//	Make a copy of the input vector.
	for (i = 0; i < 4; i++)
		theColor[i] = aColorXRsRGBLinear[i];

	//	Clamp all negative color components to zero.
	//
	//		(This simple approach seem works better in practice
	//		than the seemingly more sophisticated approach
	//		of desaturating towards grey.)
	//
	for (i = 0; i < 4; i++)
	{
		if (theColor[i] < 0.0)
			theColor[i] = 0.0;
	}
	
	//	Clamp alpha to be less than 1.0, just to be safe.
	if (theColor[3] > 1.0)
		theColor[3] = 1.0;

	//	Now that all components are non-negative,
	//	let's adjust the brightness to make sure no components
	//	are greater than alpha.
	//	Recall that we're working with premultiplied alpha,
	//	so the components look like (Rα, Gα, Bα, α).

	theMaxRGBComponent = 0.0;
	for (i = 0; i < 3; i++)
	{
		if (theMaxRGBComponent < theColor[i])
			theMaxRGBComponent = theColor[i];
	}
	theAlpha = theColor[3];

	if (theMaxRGBComponent > theAlpha)
	{
		theFactor = theAlpha / theMaxRGBComponent;
		
		for (i = 0; i < 3; i++)
		{
			theColor[i] *= theFactor;
			
			//	Guard against numerical errors leaving us
			//	with something like 1.000000000001 α.
			if (theColor[i] > theAlpha)
				theColor[i] = theAlpha;
		}
	}
	
	//	Copy theColor to the output vector.
	for (i = 0; i < 4; i++)
		aClampedColor[i] = theColor[i];
}


#pragma mark -
#pragma mark Color conversion matrices

static void InitializeColorConversionMatrices(void)
{
	ColorProfile	sRGB,
					P3;
	
	//	Initialize the sRGB and P3 profiles
	//	using specs found on Wikipedia.
	
	//	sRGB gamut from
	//
	//		https://en.wikipedia.org/wiki/SRGB#The_sRGB_gamut
	//
	
	sRGB.red.x		= 0.64;	//	exact numbers, by definition (I hope!)
	sRGB.red.y		= 0.33;

	sRGB.green.x	= 0.30;
	sRGB.green.y	= 0.60;

	sRGB.blue.x		= 0.15;
	sRGB.blue.y		= 0.06;

	sRGB.white.x	= 0.3127;
	sRGB.white.y	= 0.3290;
	
	//	P3
	//
	//	From
	//		https://en.wikipedia.org/wiki/DCI-P3#System_colorimetry
	//
	
	P3.red.x		= 0.680;
	P3.red.y		= 0.320;

	P3.green.x		= 0.265;
	P3.green.y		= 0.690;

	P3.blue.x		= 0.150;	//	same blue as in sRGB
	P3.blue.y		= 0.060;

	P3.white.x		= 0.3127;
	P3.white.y		= 0.3290;
	
	//	Fill out the remaining fields to make complete, consistent, correct ColorProfiles.
	MakeColorProfile(&sRGB);
	MakeColorProfile(&P3);

	//	Each color profile defines the transformation matrix
	//	from its color space to CIE XYZ coordinates.
	//
	//	sRGB-to-XYZ
	//		{ sRGB.red.X,   sRGB.red.Y,   sRGB.red.Z   },
	//		{ sRGB.green.X, sRGB.green.Y, sRGB.green.Z },
	//		{ sRGB.blue.X,  sRGB.blue.Y,  sRGB.blue.Z  },
	//
	//	P3-to-XYZ
	//		{ P3.red.X,     P3.red.Y,     P3.red.Z     },
	//		{ P3.green.X,   P3.green.Y,   P3.green.Z   },
	//		{ P3.blue.X,    P3.blue.Y,    P3.blue.Z    }
	//
	
	//	In the matrix equation
	//
	//		(  P3  )( sRGB ) = ( P3  )
	//		(  to  )(  to  ) = ( to  )
	//		( sRGB )( XYZ  )   ( XYZ )
	//
	//	we know sRGB-to-XYZ and P3-to-XYZ,
	//	so we may solve for P3-to-sRGB.
	//
	//	The easiest way to do this is, I think, by Gaussian elimination,
	//	but with column operations instead of row operations.
	//	To convince yourself that this is valid,
	//	note that each column operation may be thought of
	//	as right-multiplying both sides of the equation
	//	by an appropriate matrix.
	
	double	theTableauA[6][3] =
			{
				//	sRGB-to-XYZ
				{ sRGB.red.X,   sRGB.red.Y,   sRGB.red.Z   },
				{ sRGB.green.X, sRGB.green.Y, sRGB.green.Z },
				{ sRGB.blue.X,  sRGB.blue.Y,  sRGB.blue.Z  },
			
				//	P3-to-XYZ
				{ P3.red.X,     P3.red.Y,     P3.red.Z     },
				{ P3.green.X,   P3.green.Y,   P3.green.Z   },
				{ P3.blue.X,    P3.blue.Y,    P3.blue.Z    }
			};

	DoGaussianEliminationOnColumns(theTableauA);
	
	for (unsigned int i = 0; i < 3; i++)
		for (unsigned int j = 0; j < 3; j++)
			gP3toSRGB[i][j] = theTableauA[3+i][j];
			
	
	//	Repeat the same procedure, with the roles of sRGB and P3 swapped,
	//	to get the sRGB-to-P3 conversion.
	
	double	theTableauB[6][3] =
			{
				//	P3-to-XYZ
				{ P3.red.X,     P3.red.Y,     P3.red.Z     },
				{ P3.green.X,   P3.green.Y,   P3.green.Z   },
				{ P3.blue.X,    P3.blue.Y,    P3.blue.Z    },
			
				//	sRGB-to-XYZ
				{ sRGB.red.X,   sRGB.red.Y,   sRGB.red.Z   },
				{ sRGB.green.X, sRGB.green.Y, sRGB.green.Z },
				{ sRGB.blue.X,  sRGB.blue.Y,  sRGB.blue.Z  }
			};
	
	DoGaussianEliminationOnColumns(theTableauB);
	
	for (unsigned int i = 0; i < 3; i++)
		for (unsigned int j = 0; j < 3; j++)
			gSRGBtoP3[i][j] = theTableauB[3+i][j];


	//	Note:  The results found here are completely consistent
	//	with Wikipedia's summary of the standards,
	//	including the sRGB Y values shown in the table at
	//
	//		https://en.wikipedia.org/wiki/SRGB#The_sRGB_gamut
	//
	//	Moreover, they almost agree to 4 decimal places
	//	with results obtained from explicit color conversions
	//	performed in macOS's built-in ColorSync Utility.
	//	But they disagree significantly with results obtained
	//	from the color profiles available in ColorSync Utility.
	//	(ColorSync Utility's profiles are inconsistent
	//	with its own color conversion feature, so our results here
	//	can't possibly agree with both.)
}

static void MakeColorProfile(
	ColorProfile	*p)
{
	double	mR,
			mG,
			mB;
	
	//	Fill in the z values.  This is easy!
	Compute_z(&p->red	);
	Compute_z(&p->green	);
	Compute_z(&p->blue	);
	Compute_z(&p->white	);
	
	//	Let the white point's (X,Y,Z) = (x/y, y/y, z/y),
	//	to satisfy the convention that Y = 1 for the white point.
	p->white.X = p->white.x / p->white.y;
	p->white.Y = 1.0;
	p->white.Z = p->white.z / p->white.y;
	
	//	We now need to find what multiples (mR, mG, mB)
	//	of the red, green and blue primitives, that is
	//
	//		(Xr, Yr, Zr) = mR * (xr, yr, zr)
	//		(Xg, Yg, Zg) = mG * (xg, yg, zg)
	//		(Xb, Yb, Zb) = mB * (xb, yb, zb)
	//
	//	are required to get the red, green and blue (X,Y,Z) vectors
	//	to sum to the (X,Y,Z) vector of the white point.
	//	That is, we need to solve
	//
	//		           (xr yr zr)
	//		(mR mG mB) (xg yg zg) = (Xw Yw Zw)
	//		           (xb yb zb)
	//
	//	The easiest way to do this is to call
	//	the function DoGaussianEliminationOnColumns()
	//	with two dummy rows at the end.
	
	double	theTableau[6][3] =
			{
				{p->red.x,   p->red.y,   p->red.z  },
				{p->green.x, p->green.y, p->green.z},
				{p->blue.x,  p->blue.y,	 p->blue.z },
				{p->white.x, p->white.y, p->white.z},
				{0.0,        0.0,        0.0       },
				{0.0,        0.0,        0.0       }
			};

	DoGaussianEliminationOnColumns(theTableau);
	
	mR = theTableau[3][0];
	mG = theTableau[3][1];
	mB = theTableau[3][2];

	//	Finally, use the multiples (mR, mG, mB)
	//	to compute the (X,Y,Z) primitive for each color.
	ComputeXYZ(&p->red,   mR);
	ComputeXYZ(&p->green, mG);
	ComputeXYZ(&p->blue,  mB);
}

static void Compute_z(
	Color	*c)
{
	c->z = 1.0 - (c->x + c->y);
}

static void ComputeXYZ(
	Color	*c,
	double	m)	//	a multiple
{
	c->X = m * c->x;
	c->Y = m * c->y;
	c->Z = m * c->z;
}

static void	DoGaussianEliminationOnColumns(
	double	aTableau[6][3])
{
	unsigned int	i,
					theRow,
					theCol;
	double			theFactor,
					theMultiple;

	//	The caller will in all cases pass some sort
	//	of color matrix in the upper half of the tableau.
	//	Such color matrices are all very roughly comparable
	//	to the identity matrix, in the sense that their
	//	diagonal entries are larger than their off-diagonal entries,
	//	so no pivoting is required.
	//
	//		Caution:  Because we know that no pivoting
	//		is required, we don't check for degenerate situations.
	//		This code would require modifications
	//		if used for other purposes.
	//
	
	//	Forward elimination
	for (i = 0; i < 3; i++)
	{
		theFactor = 1.0 / aTableau[i][i];
		for (theRow = i; theRow < 6; theRow++)
			aTableau[theRow][i] *= theFactor;
		
		for (theCol = i + 1; theCol < 3; theCol++)
		{
			theMultiple = - aTableau[i][theCol];
			for (theRow = i; theRow < 6; theRow++)
				aTableau[theRow][theCol] += theMultiple * aTableau[theRow][i];
		}
	}
	
	//	Back substitution
	for (i = 2; i > 0; i--)
	{
		for (theCol = 0; theCol < i; theCol++)
		{
			theMultiple = - aTableau[i][theCol];
			
			aTableau[i][theCol] = 0.0;	//	aTableau[i][theCol] += theMultiple * aTableau[i][i]
			
			for (theRow = 3; theRow < 6; theRow++)
				aTableau[theRow][theCol] += theMultiple * aTableau[theRow][i];
		}
	}
}
