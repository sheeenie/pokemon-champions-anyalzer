import SwiftUI
import AppKit

@main
struct iPhoneMirrorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        // Unbuffer stdout so diagnostics appear immediately when the app is
        // launched from a terminal with its output piped to a file.
        setvbuf(stdout, nil, _IONBF, 0)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 700, minHeight: 400)
                .background(Color.black)
        }
        .windowStyle(.hiddenTitleBar)
    }
}

struct ContentView: View {
    @StateObject private var captureManager = CaptureManager()
    
    var body: some View {
        HStack(spacing: 0) {
            ZStack(alignment: .top) {
                CameraPreview(session: captureManager.session)
                    .edgesIgnoringSafeArea(.all)

                Text(captureManager.deviceName)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.8))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(6)
                    .padding(8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            StatsPanel(battle: captureManager.battle)
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
