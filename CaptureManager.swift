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
        start()
    }

    /// Starts capturing, but only once the camera permission that gates the
    /// iPhone's screen is actually granted.
    ///
    /// Without it AVFoundation hands over no frames at all - no error, no black
    /// frames, nothing - and the app used to start the session anyway and show
    /// an empty mirror, which looks exactly like an unplugged phone. Nothing
    /// asked for the permission either: the prompt only ever appeared as a side
    /// effect of adding the input. That matters because rebuilding the app
    /// changes its ad-hoc signature, and macOS stops honouring the grant given
    /// to the previous build without saying so.
    private func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            Diagnostics.log("[capture] camera access already granted")
            run()
        case .notDetermined:
            Diagnostics.log("[capture] camera access not yet decided; asking")
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Diagnostics.log("[capture] camera access \(granted ? "granted" : "refused")")
                granted ? self?.run() : self?.reportDenied()
            }
        case .denied, .restricted:
            Diagnostics.log("[capture] camera access denied: no frames will arrive")
            reportDenied()
        @unknown default:
            run()
        }
    }

    private func run() {
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

    /// Said out loud, because the alternative is a black rectangle that blames
    /// the cable. Observation never starts, so nothing overwrites this.
    private func reportDenied() {
        DispatchQueue.main.async {
            self.deviceName = "No camera access - allow it in System Settings, Privacy & Security, Camera"
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
            Diagnostics.log("[capture] could not add the analysis output")
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
            Diagnostics.log("[capture] attached \(device.localizedName)")
        } catch {
            Diagnostics.log("[capture] could not attach \(device.localizedName): \(error.localizedDescription)")
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
