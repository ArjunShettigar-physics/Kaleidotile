//  KaleidoTileHelpView.swift
//
//	© 2025 by Jeff Weeks
//	See TermsOfUse.txt

import SwiftUI


let headingColor = Color.blue

struct HelpSection: ViewModifier {

	var title: String

	func body(content: Content) -> some View {

		VStack(alignment: .leading, spacing: 8.0) {
		
			Text(title)
				.foregroundStyle(headingColor)
			
			content
				.padding(EdgeInsets(top: 0.0, leading: 16.0, bottom: 0.0, trailing: 4.0))
		}
		.frame(maxWidth: .infinity, alignment: .leading)
	}
}


struct KaleidoTileHelpView: View {

	var body: some View {
	
		ScrollView() {
		
			VStack(alignment: .leading, spacing: 16.0) {
			
				VStack(alignment: .center) {
					Text("*KaleidoTile*")
					Text(verbatim: "Tilings and Symmetry")
						.font(.title3)
				}
				.foregroundStyle(headingColor)
				.frame(maxWidth: .infinity, alignment: .center)
				
				WarmUpView()
				.modifier(HelpSection(title: "Warm-Up"))
				
				QuestionOneView()
				.modifier(HelpSection(title: "Question #1"))
				
				QuestionTwoView()
				.modifier(HelpSection(title: "Question #2"))
				
				QuestionThreeView()
				.modifier(HelpSection(title: "Question #3"))
				
				QuestionFourView()
				.modifier(HelpSection(title: "Question #4"))
				
				QuestionFiveView()
				.modifier(HelpSection(title: "Question #5"))
				
				QuestionSixView()
				.modifier(HelpSection(title: "Question #6"))
				
				BonusQuestionView()
				.modifier(HelpSection(title: "Bonus Question"))
			}
		}
		.frame(maxWidth: 320.0, maxHeight: 320.0)
		.padding(geometryGamesPanelPadding)
		.background(gSystemBackgroundColor)
		.cornerRadius(geometryGamesCornerRadius)
	}
}

struct WarmUpView: View {

	var body: some View {
	
		Text("Play with KaleidoTile. Experiment with different symmetries and different colors or pictures. Go to the \(Image(systemName: PanelType.facesPanel.iconName)) menu to take a photo or select an existing photo from your Photo Library, to apply to the polyhedron's faces.")
	}
}

struct QuestionOneView: View {

	var body: some View {
	
		Text("Go to the \(Image(systemName: PanelType.optionsPanel.iconName)) menu and experiment with *Show Plain Images*, *Show Reflected Images* and *Cut Along Mirror Lines*. What's the relationship between the polyhedron or tiling (in the main view) and the base triangle that you see when you call up the \(Image(systemName: PanelType.triplePointPanel.iconName)) panel?")
	}
}

struct QuestionTwoView: View {

	var body: some View {
	
		Text("Select \(Image(systemName: PanelType.optionsPanel.iconName)) > *Cut Along Mirror Lines* and \(Image(systemName: PanelType.symmetryAndStylePanel.iconName)) > *Style* > *Tiling of…* to clearly see the triangles that comprise the tiling. Each symmetry pattern — or *symmetry group* — is then named according to the base triangle’s angles. Say, for example, the base triangle is a 30–60–90 right triangle. Each angle evenly divides 180°:")

		VStack() {
			Text("90° = 180° / **2**")
			Text("60° = 180° / **3**")
			Text("30° = 180° / **6**")
		}
		.monospacedDigit()
		.frame(maxWidth: .infinity, alignment: .center)
		
		Text("and so the symmetry group is called a △(2,3,6) triangle group (pronounced *two-three-six triangle group*, the △ symbol being silent). You can call up the △(2,3,6) triangle group in KaleidoTile from the \(Image(systemName: PanelType.symmetryAndStylePanel.iconName)) menu.")
	
		Text("**Definition.**  If you start with a triangle with angles ( 180°/*p*, 180°/*q*, 180°/*r* ), the resulting symmetry group is called a △(*p*, *q*, *r*) *triangle group*.")
	
		Text("If the base triangle is a 45–45–90 right triangle, what’s the name of the triangle group? Can you see how to call that group up in KaleidoTile?")
	}
}

struct QuestionThreeView: View {

	var body: some View {
	
		Text("Sometimes KaleidoTile produces a tiling of a sphere, sometimes a tiling of a Euclidean plane, and sometimes a tiling of a hyperbolic plane. Find a simple rule that lets you predict which it will be for a given △(*p*, *q*, *r*) triangle group.")
	
		Text("*Hint:* Which sets of angles ( 180°/*p*, 180°/*q*, 180°/*r* ) can be the angles of a Euclidean triangle?")
	}
}

struct QuestionFourView: View {

	var body: some View {
	
		Text("Make a list of all possible △(*p*, *q*, *r*) triangle groups that tile the Euclidean plane.")
	
		Text("Make a list of all possible △(*p*, *q*, *r*) triangle groups that tile the sphere. To make your sphere look nice and round, go to the \(Image(systemName: PanelType.symmetryAndStylePanel.iconName)) menu and choose *Style* > *Tiling of sphere*.")
	
		Text("List three different △(*p*, *q*, *r*) triangle groups that tile the hyperbolic plane. Altogether, how many different △(*p*, *q*, *r*) triangle groups tile the hyperbolic plane?")
	}
}

struct QuestionFiveView: View {

	var body: some View {
	
		Text("Make a soccer ball using KaleidoTile. Which △(*p*, *q*, *r*) triangle group did you use?")
	}
}

struct QuestionSixView: View {

	var body: some View {
	
		Text("Open the \(Image(systemName: PanelType.triplePointPanel.iconName)) panel and experiment with the little round *control point*, where the three colors meet.")
	
		Text("Which control point positions give tilings with all regular faces? A *regular face* is a face whose sides all have the same length and whose angles are all equal.")
	
		Text("Can you position the control point so that the faces of one color are regular, while the faces of the other two colors are not? If so, do it. If not, explain why not.")
	
		Text("Can you position the control point so that two sets of faces (of different colors) are regular, while the remaining set of faces is not? If so, do it. If not, explain why not.")
	}
}

struct BonusQuestionView: View {

	var body: some View {
	
		Text("The only legal angles for the base triangle are")
		
		Grid() {
			GridRow() {
				Text("=").hidden()
				Text("180°/2")
				Text("180°/3")
				Text("180°/4")
				Text("180°/5")
				Text("180°/6")
				Text("…")
			}
			GridRow() {
				Text("=")
				Text("90°")
				Text("60°")
				Text("45°")
				Text("36°")
				Text("30°")
				Text("…")
			}
		}
		.font(.caption)
		.frame(maxWidth: .infinity, alignment: .center)

		Text("What would happen if you took a base triangle with illegal angles, say 37°, 42°, and 101°, and started reflecting it across its sides to make a tiling?")
	}
}
