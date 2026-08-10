//	GeometryGamesContactView.swift
//
//	© 2025 by Jeff Weeks
//	See TermsOfUse.txt

import SwiftUI


struct GeometryGamesHelpMenuContactItemLabel: View {

	var body: some View {

		Label(
			Bundle.main.localizedString(
				forKey: "Contact",
				value: nil,
				table: "GeometryGamesLocalizable"
			),
			systemImage: "square.and.pencil"
		)
	}
}


struct GeometryGamesContactView: View {

	let itsBackgroundColor: Color

	init(
		//	Used only in 4D Maze and 4D Draw to provide
		//	a dark background color that's not pure black.
		modifiedBackgroundColor: Color? = nil
	) {
	
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
	
		let theQuestionsPreString = Bundle.main.localizedString(
			forKey: "Contact-QuestionsPre",
			value: nil,
			table: "GeometryGamesLocalizable")

		let theQuestionsContactString = Bundle.main.localizedString(
			forKey: "Contact-Questions",
			value: nil,
			table: "GeometryGamesLocalizable")

		let theQuestionsPostString = Bundle.main.localizedString(
			forKey: "Contact-QuestionsPost",
			value: nil,
			table: "GeometryGamesLocalizable")

		let theMoreAppsPreLine = Bundle.main.localizedString(
			forKey: "Contact-MoreAppsPre",
			value: nil,
			table: "GeometryGamesLocalizable")

		let theMoreAppsPostLine = Bundle.main.localizedString(
			forKey: "Contact-MoreAppsPost",
			value: nil,
			table: "GeometryGamesLocalizable")

		VStack(spacing: 4.0) {
		
			if theQuestionsPreString.count > 0 {
				Text(theQuestionsPreString)
					.font(.body)
					.multilineTextAlignment(.center)
			}
		
			if let theContactURL = URL(string: "https://www.geometrygames.org/contact.html") {
				Link(theQuestionsContactString, destination: theContactURL)
					.font(.title3)
					.modifier(applyForegroundAccentColorOnMacOS())
					.multilineTextAlignment(.center)
			} else {	//	should never occur
				Text("www.geometrygames.org/contact.html")
					.font(.title3)
			}
			
			if theQuestionsPostString.count > 0 {
				Text(theQuestionsPostString)
					.font(.body)
					.multilineTextAlignment(.center)
			}
		
			Spacer(minLength: 8.0)

			Text(theMoreAppsPreLine)
				.font(.body)
				.multilineTextAlignment(.center)

			if let thGeometryGamesURL = URL(string: "https://www.geometrygames.org") {
			
				//	If the link is labeled
				//
				//		geometrygames.org
				//
				//	SwiftUI will respect the accent color.
				//	But if the link is labeled
				//
				//		www.geometrygames.org
				//
				//	SwiftUI will override the accent color. (?!)
				//
				Link("geometrygames.org", destination: thGeometryGamesURL)
					.font(.title3)
					.modifier(applyForegroundAccentColorOnMacOS())
					.multilineTextAlignment(.center)
					
			} else {	//	should never occur
				Text(verbatim: "www.geometrygames.org")
					.font(.body)
			}
			
			if theMoreAppsPostLine.count > 0 {
				Text(theMoreAppsPostLine)
					.font(.body)
					.multilineTextAlignment(.center)
			}
		}
		.fixedSize()
		.padding(geometryGamesPanelPadding)
		.background(itsBackgroundColor)
		.cornerRadius(geometryGamesCornerRadius)
	}
}
