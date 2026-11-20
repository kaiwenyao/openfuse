import SwiftUI

@main
struct OpenFuseMobileApp: App {
    @StateObject private var model = MobileLibraryModel()

    var body: some Scene {
        WindowGroup {
            MobileRootView()
                .environmentObject(model)
                .preferredColorScheme(.dark)
        }
    }
}
