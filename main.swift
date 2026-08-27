import SwiftUI
import AppKit

@main
struct iPhoneMirrorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 200, minHeight: 400)
                .background(Color.black)
        }
        .windowStyle(.hiddenTitleBar)
    }
}

struct ContentView: View {
    @StateObject private var captureManager = CaptureManager()
    
    var body: some View {
        ZStack {
            CameraPreview(session: captureManager.session)
                .edgesIgnoringSafeArea(.all)
            
            VStack {
                Text(captureManager.deviceName)
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(8)
                    .padding()
                Spacer()
            }
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Apply custom styling to the main window
        if let window = NSApplication.shared.windows.first {
            window.level = .normal // Standard level is required for Chrome screen sharing
            window.title = "iPhone Mirror"
            window.isOpaque = true
            window.backgroundColor = .black
            window.sharingType = .readOnly // Explicitly allow screen sharing
            
            // Standard window style
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.titleVisibility = .visible
            window.titlebarAppearsTransparent = false
        }
    }
}
