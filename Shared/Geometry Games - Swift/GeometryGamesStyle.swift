//	GeometryGamesStyle.swift
//
//	© 2025 by Jeff Weeks
//	See TermsOfUse.txt

import SwiftUI

let geometryGamesControlPadding: CGFloat = 8.0	//	Amount to expand the tappable area of each individual Button or Slider
let geometryGamesControlInset: CGFloat = 8.0	//	Amount to inset the control area as a whole, from the edges of the window
let geometryGamesPanelMargin: CGFloat = 8.0		//	Amount to inset a supplementary panel, from the edge of the window
let geometryGamesPanelPadding: CGFloat = 16.0	//	Amount to inset a supplementary panel's contents, from the edge of the panel itself
let geometryGamesCornerRadius: CGFloat = 16.0	//	Corner radius of a supplementary panel

//	The systemBackground color could change on the fly,
//	if the player switches between light mode and dark mode.
#if os(iOS)
var gSystemBackgroundColor: Color {
	Color(UIColor.systemBackground)
}
#endif
#if os(macOS)
var gSystemBackgroundColor: Color {
	Color(NSColor.textBackgroundColor)
}
#endif

//	A small mystery:  Starter Code's ExportButton responds
//	properly to taps in its padding, but 4D Draw's ExportButton
//	does not.  In 4D Draw, when the user taps in the padding
//	the button image dims as expected, but doesn't trigger
//	the ExportButton's action.  To trigger the action,
//	the user must tap on the button image itself.
//	The ExportButton code is *identical* in StarterCode
//	and 4D Draw — the only difference is that in StarterCode
//	the ExportButton sits directly in the content view,
//	while in 4D Draw it's embedded in a toolbar.
//
//	The workaround is to give the padding a tiny amount
//	of opacity.  Then taps in the padding trigger
//	the button action as expected.
//
//		Note:  .contentShape(Rectangle()) makes no difference
//		to the behavior described above.
//
//		Historical note:  At one point in the past
//		a transparent red background responded to taps,
//		while a transparent black background did not.
//		But that no longer seems to be a factor.
//
let geometryGamesTappableClearColor = Color(
					.displayP3,
					red: 0.0,
					green: 0.0,
					blue: 0.0,
					opacity: 0.0001)

//	I'd been writing code to manually choose an HStack or a VStack
//	each time such a choice needs to be made.  But Paul Hudson's page
//
//	https://www.hackingwithswift.com/quick-start/swiftui/how-to-automatically-switch-between-hstack-and-vstack-based-on-size-class
//
//	suggests writing a wrapper to encapsulate this effect.
//	Until I read that, I hadn't realized that I could pass content so easily.
//
struct AdaptiveStack<Content: View>: View {

	@Environment(\.horizontalSizeClass) var horizontalSizeClass

	let itsHorizontalAlignment: HorizontalAlignment
	let itsVerticalAlignment: VerticalAlignment
	let itsSpacing: CGFloat?
	let itsContent: () -> Content
	
	init(
		horizontalAlignment: HorizontalAlignment = .center,
		verticalAlignment: VerticalAlignment = .center,
		spacing: CGFloat? = nil,
		@ViewBuilder content: @escaping () -> Content
	) {
		itsHorizontalAlignment = horizontalAlignment
		itsVerticalAlignment = verticalAlignment
		itsSpacing = spacing
		itsContent = content
	}
	
	var body: some View {
	
		Group() {
		
			if horizontalSizeClass == .regular {
			
				HStack(
					alignment: itsVerticalAlignment,
					spacing: itsSpacing,
					content: itsContent)
					
			} else {
						
				VStack(
					alignment: itsHorizontalAlignment,
					spacing: itsSpacing,
					content: itsContent)

			}
		}
	}
}

struct buttonStyleOnMacOS: ViewModifier {

	func body(content: Content) -> some View {

#if os(iOS)
		content
#endif
#if os(macOS)
		//	On macOS we need to specify PlainButtonStyle()
		//	to get the buttons to have a reasonable shape.
		//
		//		Caution: One side effect of PlainButtonStyle()
		//		is that the foreground color becomes black.
		//		So for clickable buttons (but not for other elements
		//		that might be included in a view!) we'll also
		//		need to apply applyForegroundAccentColorOnMacOS.
		//
		content
		.buttonStyle(PlainButtonStyle())
#endif
	}
}

struct applyForegroundAccentColorOnMacOS: ViewModifier {

	func body(content: Content) -> some View {

#if os(iOS)
		content
#endif
#if os(macOS)
		//	buttonStyleOnMacOS sets the foreground color
		//	to black, so we'll need to manually set
		//	the color of clickable buttons to the accent color.
		content
		.foregroundStyle(Color.accentColor)
#endif
	}
}

struct helpMenuStyle: ViewModifier {

	func body(content: Content) -> some View {

		content
		.font(.body)
		.modifier(buttonStyleOnMacOS())
		.modifier(applyForegroundAccentColorOnMacOS())
		.padding(geometryGamesPanelPadding)
		.background(gSystemBackgroundColor)
		.cornerRadius(geometryGamesCornerRadius)
	}
}
