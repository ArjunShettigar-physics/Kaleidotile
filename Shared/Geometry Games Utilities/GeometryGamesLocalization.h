//	GeometryGamesLocalization.h
//
//	© 2023 by Jeff Weeks
//	See TermsOfUse.txt

#pragma once

#include "GeometryGamesUtilities-Common.h"


//	Each app must provide implement GetLanguageFileBaseName()
//	to tell the methods in GeometryGamesLocalization.c where
//	to find the language file.
extern const Char16	*GetLanguageFileBaseName(void);	//	Just u"BaseName", not u"BaseName-xx.txt"

//	in GeometryGamesLocalization.c
extern void			SetCurrentLanguage(const Char16 aTwoLetterLanguageCode[3]);
extern const Char16	*GetCurrentLanguage(void);
extern bool			IsCurrentLanguage(const Char16 aTwoLetterLanguageCode[3]);
extern bool			CurrentLanguageReadsLeftToRight(void);
extern bool			CurrentLanguageReadsRightToLeft(void);
extern const Char16	*GetLocalizedText(const Char16 *aKey);
extern const Char16	*GetEndonym(const Char16 aTwoLetterLanguageCode[3]);
extern bool			SameTwoLetterLanguageCode(const Char16 *aStringA, const Char16 *aStringB);
