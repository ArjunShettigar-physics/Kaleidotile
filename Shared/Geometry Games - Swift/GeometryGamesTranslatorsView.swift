//	GeometryGamesTranslatorsView.swift
//
//	© 2025 by Jeff Weeks
//	See TermsOfUse.txt

import SwiftUI


struct GeometryGamesHelpMenuTranslatorsItemLabel: View {

	var body: some View {

		Label(
			Bundle.main.localizedString(
				forKey: "Translators",
				value: nil,
				table: "GeometryGamesLocalizable"
			),
			systemImage: "globe"
		)
	}
}


struct GeometryGamesTranslatorThanks: Hashable {

	//	In some languages the thanks go
	//	before the translator's name, like this
	//
	//		pre:  merci à
	//		name: Jean-Philippe Uzan
	//		post:
	//
	//	while in others the thanks go
	//	after the name, like this
	//
	//		pre:
	//		name: 竹内建氏に  (Mr. Tatsu Takeuchi)
	//		post: 感謝します  (make thanks)
	//
	let pre: String?
	let name: String
	let post: String?
	let lang: String	//	for example, "ar", "en", "ja", "zh-Hans" or "zh-Hant"

	//	Simplified Chinese, traditional Chinese, and Japanese writing
	//	use characters that, in spite of their common origins,
	//	often differ from each other in small ways.
	//	The creators of the first universal character set,
	//	in order to squeeze all desired characters
	//	into the 2¹⁶ = 65536 values available for a 16-bit integer,
	//	adopted the compromise of assigning two (or three) separate values
	//	to each character whose appearance differs greatly between
	//	simplified Chinese, traditional Chinese and Japanese,
	//	but in cases where the differences are small,
	//	they assigned only a single value, to be shared
	//	by the three writing systems.  Their intention was
	//	that different language-specific fonts could be used
	//	to provide an appropriate glyph in each writing system.
	//	For more information on this "Han unification", see
	//
	//		https://en.wikipedia.org/wiki/Han_unification
	//
	
	//	I had hoped that code like
	//
	//		Text("入 海 蔥")
	//			.environment(\.locale, .init(identifier:"ja"     ))
	//
	//		Text("入 海 蔥")
	//			.environment(\.locale, .init(identifier:"zh-Hans"))
	//
	//		Text("入 海 蔥")
	//			.environment(\.locale, .init(identifier:"zh-Hant"))
	//
	//	would serve to conjure up the required font in SwiftUI,
	//	so that a Japanese translator could be thanked
	//	using the Japanese version of the characters,
	//	while a Chinese translator gets thanked
	//	using a Chinese version.
	//	Alas those .environment() modifiers have no effect.
	//	So as a workaround, I've asked for a specific font in each case.
	//	The good news:  These fonts scale correctly with Dynamic Type.
	//	The bad news:  If Apple ever drops support for these fonts,
	//	this code will fail.  Nothing too terrible will happen,
	//	but the font will revert to what the default is on the user's device.

	var smallFont: Font {

		switch lang {
		
		case "ja":
			return Font.custom("Hiragino Sans", size: 16.0, relativeTo: .body)
		
		case "zh-Hans":
			return Font.custom("PingFang SC",   size: 16.0, relativeTo: .body)
		
		case "zh-Hant":
			return Font.custom("PingFang TC",   size: 16.0, relativeTo: .body)
		
		default:
			return Font.system(.body, design: Font.Design.serif)
					.italic()
		}
	}
	var largeFont: Font {

		switch lang {
		
		case "ja":
			return Font.custom("Hiragino Sans", size: 20.0, relativeTo: .title3)
		
		case "zh-Hans":
			return Font.custom("PingFang SC",   size: 20.0, relativeTo: .title3)
		
		case "zh-Hant":
			return Font.custom("PingFang TC",   size: 20.0, relativeTo: .title3)
		
		default:
			return Font.title3
		}
	}
}

struct GeometryGamesTranslatorsView: View {

	let itsTranslatorThanks: [GeometryGamesTranslatorThanks]

	let itsBackgroundColor: Color
	
	//	The ScrollView should be tall enough
	//	to hold its content view, but no taller.
	//	Alas achieving this result seems to require
	//	a bit of a kludge.  Here we imitate the method
	//	given on the blog page
	//
	//		https://github.com/onmyway133/blog/issues/769#issue-802788982
	//
	@State private var itsScrollViewContentHeight: CGFloat = 0.0
	
	init(
		_ translatorThanks: [GeometryGamesTranslatorThanks],
		
		//	Used only in 4D Maze and 4D Draw to provide
		//	a dark background color that's not pure black.
		modifiedBackgroundColor: Color? = nil
	) {
	
		itsTranslatorThanks = translatorThanks

		if let theModifiedBackgroundColor = modifiedBackgroundColor {
			//	In 4D Maze and 4D Draw
			self.itsBackgroundColor = theModifiedBackgroundColor
		} else {
			//	In all other Geometry Games apps
#if os(iOS)
			self.itsBackgroundColor = Color(UIColor.systemBackground)
#endif
#if os(macOS)
			self.itsBackgroundColor = Color(NSColor.textBackgroundColor)
#endif
		}
	}

	var body: some View {
	
		let theItemPadding: CGFloat = 4.0
		
		ScrollView() {
			
			ForEach(itsTranslatorThanks, id: \.self) { creditLine in
			
				VStack() {
				
					if let thePreText = creditLine.pre {
						Text(thePreText)
							.font(creditLine.smallFont)
					}

					Text(creditLine.name)
						.font(creditLine.largeFont)
						.multilineTextAlignment(.center)

					if let thePostText = creditLine.post {
						Text(thePostText)
							.font(creditLine.smallFont)
					}
				}
				.padding(theItemPadding)
			}
			.background(
				//	This is a kludge.  See comments
				//	accompanying itsScrollViewContentHeight above.
				GeometryReader { geometryProxy -> Color in
					//	We can't modify a state variable while
					//	re-computing body, so modify it later instead.
					Task {
						itsScrollViewContentHeight = geometryProxy.size.height
					}
					return Color.clear
				}
			)
		}
		.frame(maxHeight: itsScrollViewContentHeight)
		.padding(geometryGamesPanelPadding)
		.background(itsBackgroundColor)
		.cornerRadius(geometryGamesCornerRadius)
	}
}
