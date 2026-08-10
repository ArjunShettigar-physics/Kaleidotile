//	GeometryGames-Common.h
//
//	© 2023 by Jeff Weeks
//	See TermsOfUse.txt

#pragma once

#include <stdbool.h>			//	for bool, true and false
#include <stdlib.h>				//	for NULL, malloc() and free()
#include <stdint.h>				//	for uint8_t, uint16_t, etc.
#include <TargetConditionals.h>	//	for TARGET_OS_IOS, TARGET_OS_OSX, TARGET_OS_MACCATALYST

//	Acknowledge unused parameters.
#define UNUSED_PARAMETER(x)	((void)(x))


//	Define SAVE_FOUR_SIZES_WITH_MAGENTA_TOOLBAR_AREA to
//
//		2	to allow for a navigation bar (and a slightly different size toolbar),
//	or
//		any other value (or nothing) to allow for a toolbar only.
//
//#define SAVE_FOUR_SIZES_WITH_MAGENTA_TOOLBAR_AREA	2
#ifdef SAVE_FOUR_SIZES_WITH_MAGENTA_TOOLBAR_AREA
#warning SAVE_FOUR_SIZES_WITH_MAGENTA_TOOLBAR_AREA is enabled.
//	Automatically saves the current image at the display sizes
//	of the iPhone 8 Plus, iPhone XS Max and iPad Pro,
//	to provide Metal-generated content for use in simulating iOS screenshots.
//	Replaces the toolbar area with pure magenta,
//	to be overlaid with non-Metal output from the iOS simulator.
//	If the iOS Simulator eventually supports Metal, I'll be able to create
//	screenshots directly, and this code may be permanently removed.
#endif


//	Define a byte.
typedef uint8_t		Byte;

//	Define our own UTF-16 type.
//	Our Char16 corresponds to a WCHAR on Win32 or to a UniChar on macOS.
//	We do not support surrogate pairs — in fact we often pass a character
//	as a single Char16 — so really this is more like UCS-2 than UTF-16.
//	I'd replace Char16 with the standard type char16_t if I could,
//	but the latter doesn't seem to be part of Xcode's C11, only C++11.
typedef uint16_t	Char16;

//	BUFFER_LENGTH() measures the number of items in an array,
//	not the number of bytes, and automatically adjusts to changes
//	in the number of elements or the size of each element.
#define BUFFER_LENGTH(a)	( sizeof(a) / sizeof((a)[0]) )

//	The ModelData will be different for each application.
//	All the shared code needs to know is that the ModelData is a structure.
typedef struct ModelData ModelData;

//	Internal functions pass error messages as pointers
//	to zero-terminated UTF-16 strings.  The strings are defined
//	statically, so the caller need not (must not!) free them.
typedef const Char16	*ErrorText;
typedef struct
{
	ErrorText	itsMessage,
				itsTitle;
} TitledErrorMessage;


//	Represent colors as (αR, αG, αB, α) instead of the traditional (R,G,B,α)
//	to facilitate blending and mipmap generation.
//
//	1.	Rigorously correct blending requires
//
//					   αs*(Rs,Gs,Bs) + (1 - αs)*αd*(Rd,Gd,Bd)
//			(R,G,B) = ----------------------------------------
//							 αs      +      (1 - αs)*αd
//
//				  α = αs + (1 - αs)*αd
//
//		Replacing the traditional (R,G,B,α) with the premultiplied (αR,αG,αB,α)
//		simplifies the formula to 
//
//			(αR, αG, αB) = (αs*Rs, αs*Gs, αs*Bs) + (1 - αs)*(αd*Rd, αd*Gd, αd*Bd)
//
//					   α = αs + (1 - αs)*αd
//
//		Because they share the same coefficients, 
//		we may merge the RGB and α parts into a single formula
//
//			(αR, αG, αB, α)
//				=     1    * (αs*Rs, αs*Gs, αs*Bs, αs)
//				+ (1 - αs) * (αd*Rd, αd*Gd, αd*Bd, αd)
//
//
//	2.	When generating mipmaps, to average two (or more) pixels correctly
//		we must weight them according to their alpha values.
//		With traditional (R,G,B,α) the formula is a bit messy
//
//								 α0*(R0,G0,B0) + α1*(R1,G1,B1)
//			(Ravg, Gavg, Bavg) = -----------------------------
//								            α0 + α1
//
//								 α0 + α1
//						  αavg = -------
//									2
//
//		With premultiplied (αR,αG,αB,α) the formula becomes a simple average
//
//			(αavg*Ravg, αavg*Gavg, αavg*Bavg, αavg)
//
//				  (α0*R0, α0*G0, α0*B0, α0) + (α1*R1, α1*G1, α1*B1, α1)
//				= -----------------------------------------------------
//											2
//
//
#define PREMULTIPLY_RGBA(r,g,b,a)	{(a)*(r), (a)*(g), (a)*(b), (a)}


//	ColorP3Linear
//
//		Note:  It's more convenient to work in the Display P3 gamut
//		and later convert to Extended-Range sRGB coordinates
//		for that same Display P3 gamut (or to clamp colors for use
//		on non-P3 devices) than to work in Extended Range sRGB
//		from the beginning and have to fuss around with where
//		the Display P3 gamut's corners and edges sit.
//
typedef struct
{
	float	r,	//	linear P3 red,   premultiplied by α
			g,	//	linear P3 green, premultiplied by α
			b,	//	linear P3 blue,  premultiplied by α
			a;	//	linear α = opacity
} ColorP3Linear;


//	When the platform-dependent code passes the mouse or touch location
//	to the platform-independent code, it passes the view dimensions along with it.
typedef struct
{
	//	The horizontal coordinate runs left-to-right, from 0 to itsViewWidth.
	//	The  vertical  coordinate runs bottom-to-top, from 0 to itsViewHeight.
	//
	//	Measurements may be in pixels or points;
	//	either is fine just so they're consistent.
	
	double	itsX,
			itsY,
			itsViewWidth,
			itsViewHeight;
	
} DisplayPointInC;

//	A DisplayPointMotionInC is just like a DisplayPointInC,
//	except that it stores a relative motion instead of an absolute position.
typedef struct
{
	//	Measurements may be in pixels or points;
	//	either is fine just so they're consistent.
	
	double	itsDeltaX,		//	left-to-right motion is positive
			itsDeltaY,		//	bottom-to-top motion is positive
			itsViewWidth,
			itsViewHeight;

} DisplayPointMotionInC;


//	Platform-independent global functions

//	in <ProgramName>Init.c
extern unsigned int		SizeOfModelData(void);
extern void				SetUpModelData(ModelData *md);
extern void				ShutDownModelData(ModelData *md);

//	in <ProgramName>Simulation.c
extern bool				SimulationWantsUpdates(ModelData *md);
extern void				SimulationUpdate(ModelData *md, double aFramePeriod);
extern uint64_t			GetContentChangeCount(ModelData *md);
extern uint64_t			GetDisplayChangeCount(ModelData *md);

//	in <ProgramName>Drawing.c  (portfolio-based app only)
extern bool				ContentIsLocked(ModelData *md);
extern void				SetContentIsLocked(ModelData *md, bool aContentIsLocked);

//	in <ProgramName>FileIO.c
extern void				SaveDrawing(ModelData *md, const char *aPathName);
extern bool				OpenDrawing(ModelData *md, const char *aPathName);

