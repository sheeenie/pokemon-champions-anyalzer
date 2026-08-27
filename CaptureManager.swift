import Foundation
import AVFoundation
import CoreMediaIO

class CaptureManager: ObservableObject {
    @Published var session = AVCaptureSession()
    @Published var deviceName: String = "Starting..."
    
    init() {
        DispatchQueue.global(qos: .userInitiated).async {
            self.setupSession()
        }
    }
    
    func setupSession() {
        // 1. Enable iOS Screen Capture explicitly in CoreMediaIO
        var prop = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyAllowScreenCaptureDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMaster)
        )
        var allow: UInt32 = 1
        let size = UInt32(MemoryLayout<UInt32>.size)
        CMIOObjectSetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &prop, 0, nil, size, &allow)
        
        session.beginConfiguration()
        
        // 2. Discover Devices
        var types: [AVCaptureDevice.DeviceType] = [.externalUnknown]
        if #available(macOS 14.0, *) {
            types.append(.external)
        }
        
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: types,
            mediaType: .muxed,
            position: .unspecified
        )
        
        // 3. Find iOS device screen (wait for it if necessary)
        var foundDevice: AVCaptureDevice? = nil
        var retryCount = 0
        while retryCount < 15 {
            if let device = discoverySession.devices.first(where: { $0.modelID == "iOS Device" }) {
                foundDevice = device
                break
            }
            Thread.sleep(forTimeInterval: 0.2)
            retryCount += 1
        }
        
        guard let device = foundDevice else {
            DispatchQueue.main.async {
                self.deviceName = "Error: No iPhone Screen Found"
            }
            print("No external iOS device found for screen capture.")
            session.commitConfiguration()
            return
        }
        
        DispatchQueue.main.async {
            self.deviceName = "Connected: \(device.localizedName)"
        }
        print("Using capture device: \(device.localizedName) (ID: \(device.uniqueID))")
        
        // 4. Add input
        do {
            let input = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(input) {
                session.addInput(input)
            }
        } catch {
            print("Failed to add input: \(error.localizedDescription)")
        }
        
        session.commitConfiguration()
        
        // 5. Start session in background
        DispatchQueue.global(qos: .userInitiated).async {
            self.session.startRunning()
        }
    }
}
