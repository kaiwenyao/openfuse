import SwiftUI

@main
struct OpenFuseVisionApp: App {
    @StateObject private var model = MobileLibraryModel()
    @StateObject private var playback = VisionImmersiveModel()

    var body: some Scene {
        WindowGroup(id: "main") {
            VisionRootView()
                .environmentObject(model)
                .environmentObject(playback)
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 1100, height: 760)

        ImmersiveSpace(id: VisionImmersiveModel.spaceID) {
            VisionImmersiveView()
                .environmentObject(model)
                .environmentObject(playback)
        }
        .immersionStyle(selection: .constant(.full), in: .full)
    }
}
