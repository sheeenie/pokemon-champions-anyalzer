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


/// Shows a layer someone else keeps filled. The Android path has no capture
/// session to hang a preview layer off, only frames, so the mirror draws the
/// same layer those frames land on.
struct LayerPreview: NSViewRepresentable {
    let layer: CALayer

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.addSublayer(layer)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.frame = view.bounds
        CATransaction.commit()
    }
}
