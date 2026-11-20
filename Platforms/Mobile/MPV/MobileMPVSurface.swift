import SwiftUI
import UIKit

/// Hosts the CAMetalLayer mpv renders into.
struct MobileMPVSurface: UIViewRepresentable {
    let engine: MobileMPVEngine

    final class HostView: UIView {
        override func layoutSubviews() {
            super.layoutSubviews()
            guard let layer = self.layer.sublayers?.first as? CAMetalLayer else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.frame = bounds
            layer.drawableSize = CGSize(width: bounds.width * layer.contentsScale,
                                        height: bounds.height * layer.contentsScale)
            CATransaction.commit()
        }
    }

    func makeUIView(context: Context) -> HostView {
        let view = HostView()
        view.backgroundColor = .black
        view.layer.addSublayer(engine.metalLayer)
        return view
    }

    func updateUIView(_ uiView: HostView, context: Context) {
        uiView.setNeedsLayout()
    }
}
