import WebKit

extension SitePermission {
    init(_ captureType: WKMediaCaptureType) {
        switch captureType {
        case .camera:
            self = .camera
        case .microphone:
            self = .microphone
        case .cameraAndMicrophone:
            self = .cameraAndMicrophone
        @unknown default:
            self = .cameraAndMicrophone
        }
    }
}
