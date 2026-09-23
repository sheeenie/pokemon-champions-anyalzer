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

                        // An iPhone hands over a capture session to preview;
                        // Android hands over frames, which land on a layer.
                        Group {
                            if captureManager.usingAndroid {
                                LayerPreview(layer: captureManager.android.previewLayer)
                            } else {
                                CameraPreview(session: captureManager.session)
                            }
                        }
                            .frame(width: ContentView.mirrorWidth,
                                   height: ContentView.mirrorWidth / captureManager.mirrorAspect)
                            .background(Color.black)
                            .cornerRadius(7)
                            .overlay(
                                RoundedRectangle(cornerRadius: 7)
                                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
                            )
                            .shadow(color: .black.opacity(0.5), radius: 8, y: 3)
                    }
                }

                // Only when it is the thing standing in the way: an Android
                // phone is mirrored on screen but macOS will not let the app
                // read the window yet.
                if captureManager.needsScreenRecording, !captureManager.usingAndroid {
                    Button {
                        captureManager.android.requestPermission()
                    } label: {
                        Label("Use Android (scrcpy)", systemImage: "rectangle.on.rectangle")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white.opacity(0.8))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(Color.white.opacity(0.12))
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .help("Allow screen recording so the app can read the scrcpy window")
                }

                Button {
                    showMirror.toggle()
                } label: {
                    Label(L10n.text(showMirror ? .hideMirror : .showMirror, lang),
                          systemImage: showMirror ? "eye.slash" : "eye")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.8))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.12))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
            .padding(14)
        }
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
