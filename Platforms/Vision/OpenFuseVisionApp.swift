import SwiftUI

@main
struct OpenFuseVisionApp: App {
    @StateObject private var model = MobileLibraryModel()

    var body: some Scene {
        WindowGroup {
            VisionRootView()
                .environmentObject(model)
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 1100, height: 760)
    }
}
