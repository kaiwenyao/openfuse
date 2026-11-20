import SwiftUI

@main
struct OpenFuseTVApp: App {
    @StateObject private var model = MobileLibraryModel()

    var body: some Scene {
        WindowGroup {
            TVRootView()
                .environmentObject(model)
                .preferredColorScheme(.dark)
        }
    }
}
