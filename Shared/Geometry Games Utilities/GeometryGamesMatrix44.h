//	GeometryGamesMatrix44.h
//
//	© 2023 by Jeff Weeks
//	See TermsOfUse.txt

extern void		Matrix44Identity(double m[4][4]);
extern void		Matrix44Zero(double m[4][4]);
extern void		Matrix44Copy(double dst[4][4], /*const*/ double src[4][4]);
extern void		Matrix44Product(/*const*/ double m1[4][4], /*const*/ double m2[4][4], double product[4][4]);
extern void		Matrix44GeometricInverse(/*const*/ double m[4][4], double mInverse[4][4]);
extern void		Matrix44RowVectorTimesMatrix(const double v[4], /*const*/ double m[4][4], double vm[4]);
extern void		Matrix44TimesColumnVector(/*const*/ double m[4][4], const double v[4], double mv[4]);
extern double	Matrix44EuclideanDeterminant(/*const*/ double m[4][4]);

extern void		Matrix44ExtendingMatrix33(double s[3][3], double d[4][4]);
extern void		Matrix44DoubleToFloat(/*const*/ double aSrc[4][4], float aDst[4][4]);
