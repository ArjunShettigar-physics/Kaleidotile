//	KaleidoTileApp.swift
//
//	© 2025 by Jeff Weeks
//	See TermsOfUse.txt

import SwiftUI

@main
struct KaleidoTileApp: App {

	init() {

		//	Create a fallback set of user defaults (the "factory settings").
		//	These will get used if and only if the user has not provided his/her own values.
		UserDefaults.standard.register(defaults: ["sound effects" : true])
		
		//	Initialize the audio.
#if os(iOS)
		setUpAudio()
#endif
	}
	
	var body: some Scene {
#if os(iOS)
		WindowGroup {
			KaleidoTileContentView()
		}
#endif
#if os(macOS)
		WindowGroup {
			KaleidoTileContentView()
			.windowToolbarFullScreenVisibility(.onHover)
		}
		.defaultSize(
			width:  gMakeAppStoreScreenshots ? 1280.0 : 1024.0,
			height: gMakeAppStoreScreenshots ?  800.0 :  768.0)
#endif
	}
}
