import AVKit
import SwiftUI

/// AVRoutePickerView wrapper for the macOS player control bar. Opens the
/// system AirPlay picker; actual routing requires an AirPlay receiver.
struct AirPlayRoutePicker: NSViewRepresentable {
    func makeNSView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.isRoutePickerButtonBordered = false
        return view
    }

    func updateNSView(_ nsView: AVRoutePickerView, context: Context) {}
}
