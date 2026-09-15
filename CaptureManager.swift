import Foundation
import AVFoundation
import CoreMediaIO

class CaptureManager: ObservableObject {
    @Published var session = AVCaptureSession()
    @Published var deviceName: String = "Waiting for iPhone..."

    private var discoverySession: AVCaptureDevice.DiscoverySession!
    private var devicesObservation: NSKeyValueObservation?
    private var currentInput: AVCaptureDeviceInput?
    private var currentDeviceID: String?

    /// What the analyzer currently believes is on the field.
    let battle: BattleStateTracker
    private let analyzer: BattleAnalyzer
    private let videoOutput = AVCaptureVideoDataOutput()

    /// Plays the iPhone's sound on the Mac. While it's being captured the iPhone
    /// sends its audio to the Mac instead of playing it, so without this the game
    /// is silent.
    private let audioOutput = AVCaptureAudioPreviewOutput()

    /// Mac playback of the iPhone's sound. Off mutes it without affecting capture.
    @Published var soundOn = true {
        didSet { audioOutput.volume = soundOn ? 1 : 0 }
    }

    init() {
        let tracker = BattleStateTracker()
        battle = tracker
        analyzer = BattleAnalyzer(tracker: tracker)

        // Enable iOS Screen Capture explicitly in CoreMediaIO
        var prop = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyAllowScreenCaptureDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMaster)
        )
        var allow: UInt32 = 1
        let size = UInt32(MemoryLayout<UInt32>.size)
        CMIOObjectSetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &prop, 0, nil, size, &allow)

        var types: [AVCaptureDevice.DeviceType] = [.externalUnknown]
        if #available(macOS 14.0, *) {
            types.append(.external)
        }

        discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: types,
            mediaType: .muxed,
            position: .unspecified
        )

        configureVideoOutput()
        configureAudioOutput()

        DispatchQueue.global(qos: .userInitiated).async {
            self.session.startRunning()
        }

        // React any time the set of available devices changes, so plugging
        // in the iPhone after the app is already running still connects.
        devicesObservation = discoverySession.observe(\.devices, options: [.initial, .new]) { [weak self] _, change in
            guard let self, let devices = change.newValue else { return }
            self.reconcile(devices: devices)
        }
    }

    /// Adds the frame tap the analyzer reads from. The preview layer keeps its own
    /// connection to the session, so this is purely additive to the mirroring path.
    private func configureVideoOutput() {
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoOutput.setSampleBufferDelegate(analyzer, queue: analyzer.queue)

        session.beginConfiguration()
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
        } else {
            print("Failed to add video data output")
        }
        session.commitConfiguration()
    }

    /// Adds Mac playback of the iPhone's audio. Like the video output, it connects
    /// to the iPhone's input automatically once that is added.
    private func configureAudioOutput() {
        audioOutput.volume = 1
        session.beginConfiguration()
        if session.canAddOutput(audioOutput) {
            session.addOutput(audioOutput)
        } else {
            print("Failed to add audio preview output")
        }
        session.commitConfiguration()
    }

    private func reconcile(devices: [AVCaptureDevice]) {
        let device = devices.first(where: { $0.modelID == "iOS Device" })

        if let device, device.uniqueID != currentDeviceID {
            attach(device: device)
        } else if device == nil, currentDeviceID != nil {
            detachCurrentInput()
        }
    }

    private func attach(device: AVCaptureDevice) {
        detachCurrentInput()

        do {
            let input = try AVCaptureDeviceInput(device: device)
            session.beginConfiguration()
            if session.canAddInput(input) {
                session.addInput(input)
                currentInput = input
                currentDeviceID = device.uniqueID
            }
            session.commitConfiguration()

            DispatchQueue.main.async {
                self.deviceName = "Connected: \(device.localizedName)"
            }
            print("Using capture device: \(device.localizedName) (ID: \(device.uniqueID))")
            let ports = input.ports.map { $0.mediaType.rawValue }.joined(separator: ", ")
            let audioConnected = audioOutput.connections.contains { $0.isEnabled && $0.isActive }
            analyzer.note("[capture] \(device.localizedName): input ports \(ports); "
                          + "audio playback connected: \(audioConnected)")
        } catch {
            print("Failed to add input: \(error.localizedDescription)")
        }
    }

    private func detachCurrentInput() {
        guard let input = currentInput else { return }
        session.beginConfiguration()
        session.removeInput(input)
        session.commitConfiguration()
        currentInput = nil
        currentDeviceID = nil

        DispatchQueue.main.async {
            self.deviceName = "Waiting for iPhone..."
        }
    }
}
