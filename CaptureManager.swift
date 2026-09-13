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

    init() {
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
