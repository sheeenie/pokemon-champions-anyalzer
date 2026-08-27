import Foundation
import AVFoundation
import CoreMediaIO

var prop = CMIOObjectPropertyAddress(
    mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyAllowScreenCaptureDevices),
    mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
    mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
)
var allow: UInt32 = 1
let size = UInt32(MemoryLayout<UInt32>.size)
CMIOObjectSetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &prop, 0, nil, size, &allow)

let discoverySession = AVCaptureDevice.DiscoverySession(
    deviceTypes: [.external, .builtInWideAngleCamera, .externalUnknown],
    mediaType: .muxed,
    position: .unspecified
)

print("Devices found: \(discoverySession.devices.count)")
for device in discoverySession.devices {
    print("Muxed: \(device.localizedName), ModelID: \(device.modelID)")
}
