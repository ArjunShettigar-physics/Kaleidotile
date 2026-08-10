//	GeometryGamesMatrix33.h
//
//	© 2021 by Jeff Weeks
//	See TermsOfUse.txt

extern void		Matrix33Identity(double m[3][3]);
extern void		Matrix33Copy(double dst[3][3], double src[3][3]);
extern void		Matrix33Product(/*const*/ double m1[3][3], /*const*/ double m2[3][3], double product[3][3]);
extern double	Matrix33Determinant(double m[3][3]);
extern void		Matrix33CramersRule(double a[3][3], double x[3][3], double b[3][3]);
extern void		Matrix33ForRotationAboutAxis(double anAxis[3], double anAngle, double aRotation[3][3]);
extern void		Matrix33FastGramSchmidt(double m[3][3]);
extern void		Matrix33RowVectorTimesMatrix(double v[3], double m[3][3], double vm[3]);

extern void		Matrix33DoubleToFloat(/*const*/ double aSrc[3][3], float aDst[3][3]);
