import SwiftUI
import AVFoundation

class PreviewView: NSView {
    var previewLayer: AVCaptureVideoPreviewLayer
    
    init(session: AVCaptureSession) {
        self.previewLayer = AVCaptureVideoPreviewLayer(session: session)
        super.init(frame: .zero)
        
        self.wantsLayer = true
        self.previewLayer.videoGravity = .resizeAspect
        self.layer?.addSublayer(self.previewLayer)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layout() {
        super.layout()
        self.previewLayer.frame = self.bounds
    }
}

struct CameraPreview: NSViewRepresentable {
    var session: AVCaptureSession
    
    func makeNSView(context: Context) -> PreviewView {
        return PreviewView(session: session)
    }
    
    func updateNSView(_ nsView: PreviewView, context: Context) {
        nsView.previewLayer.session = session
    }
}


/// Hosts a layer someone else keeps filled, and keeps it the size of the view.
///
/// The resizing has to happen in `layout`, as the capture preview above does
/// it. Doing it from `updateNSView` looks equivalent and is not: SwiftUI calls
/// that when its state changes, not when the view is laid out, so the layer
/// kept whatever size it had when the view was built - zero - and the mirror
/// stayed black however many frames arrived.
class HostedLayerView: NSView {
    private let hosted: CALayer

    init(layer: CALayer) {
        hosted = layer
        super.init(frame: .zero)
        wantsLayer = true
        self.layer?.addSublayer(hosted)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        // Without this the layer animates every resize, which on a mirror that
        // is redrawn ten times a second reads as a smear.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        hosted.frame = bounds
        CATransaction.commit()
    }
}

/// Shows a layer someone else keeps filled. The Android path has no capture
/// session to hang a preview layer off, only frames, so the mirror draws the
/// same layer those frames land on.
struct LayerPreview: NSViewRepresentable {
    let layer: CALayer

    func makeNSView(context: Context) -> HostedLayerView { HostedLayerView(layer: layer) }

    func updateNSView(_ view: HostedLayerView, context: Context) {
        view.needsLayout = true
    }
}
