import SwiftUI
import AppKit

@main
struct PokemonChampionsAnalyzerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        // Unbuffer stdout so diagnostics appear immediately when the app is
        // launched from a terminal with its output piped to a file.
        setvbuf(stdout, nil, _IONBF, 0)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 720, minHeight: 640)
                .background(Color.black)
        }
        .windowStyle(.hiddenTitleBar)
    }
}

struct ContentView: View {
    @StateObject private var captureManager = CaptureManager()
    @AppStorage("language") private var lang: Lang = .en
    /// Shown on every launch; hiding it is for the current session only.
    @State private var showMirror = true

    /// The mirror is a reference, not the point of the app - the stats are.
    /// It floats small in the corner so the panel gets the whole window.
    private static let mirrorWidth: CGFloat = 200
    private static let mirrorAspect: CGFloat = 2622.0 / 1206.0

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            StatsPanel(battle: captureManager.battle)

            VStack(alignment: .trailing, spacing: 6) {
                // Hiding removes only the preview. Identification reads frames
                // from its own output on the capture session, so it keeps
                // running while the mirror is hidden.
                if showMirror {
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(captureManager.deviceName)
                            .font(.system(size: 9))
                            .foregroundColor(.white.opacity(0.45))

                        CameraPreview(session: captureManager.session)
                            .frame(width: ContentView.mirrorWidth,
                                   height: ContentView.mirrorWidth / ContentView.mirrorAspect)
                            .background(Color.black)
                            .cornerRadius(7)
                            .overlay(
                                RoundedRectangle(cornerRadius: 7)
                                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
                            )
                            .shadow(color: .black.opacity(0.5), radius: 8, y: 3)
                    }
                }

                HStack(spacing: 6) {
                    CornerButton(title: L10n.text(captureManager.soundOn ? .muteSound : .unmuteSound, lang),
                                 systemImage: captureManager.soundOn ? "speaker.slash" : "speaker.wave.2") {
                        captureManager.soundOn.toggle()
                    }
                    CornerButton(title: L10n.text(showMirror ? .hideMirror : .showMirror, lang),
                                 systemImage: showMirror ? "eye.slash" : "eye") {
                        showMirror.toggle()
                    }
                }
            }
            .padding(14)
        }
    }
}

/// Small labelled button for the bottom-right corner controls.
struct CornerButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(0.8))
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.12))
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Apply custom styling to the main window
        if let window = NSApplication.shared.windows.first {
            window.level = .normal // Standard level is required for Chrome screen sharing
            window.title = "Pokémon Champions Analyzer"
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
