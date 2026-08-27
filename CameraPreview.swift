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
