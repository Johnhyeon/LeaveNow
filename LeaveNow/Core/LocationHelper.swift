import CoreLocation
import MapKit

/// 한 번만 현재 위치를 받아오는 도우미 ("앱 사용 중" 권한)
@MainActor
final class LocationHelper: NSObject, CLLocationManagerDelegate {
    static let shared = LocationHelper()
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation?, Never>?
    private var authContinuation: CheckedContinuation<Void, Never>?

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    }

    var isAuthorized: Bool {
        [.authorizedWhenInUse, .authorizedAlways].contains(manager.authorizationStatus)
    }

    func currentLocation() async -> CLLocation? {
        if manager.authorizationStatus == .notDetermined {
            await withCheckedContinuation { cont in
                authContinuation = cont
                manager.requestWhenInUseAuthorization()
            }
        }
        guard isAuthorized else { return nil }
        return await withCheckedContinuation { cont in
            continuation = cont
            manager.requestLocation()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            if manager.authorizationStatus != .notDetermined {
                authContinuation?.resume()
                authContinuation = nil
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            continuation?.resume(returning: locations.last)
            continuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            continuation?.resume(returning: nil)
            continuation = nil
        }
    }

    /// 걸어서 몇 분. 지도 경로를 쓰고, 실패하면 직선거리로 어림한다
    static func walkingMinutes(from: CLLocation, to: CLLocation) async -> Int {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: from.coordinate))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: to.coordinate))
        request.transportType = .walking
        if let eta = try? await MKDirections(request: request).calculateETA() {
            return max(1, Int((eta.expectedTravelTime / 60).rounded(.up)))
        }
        let meters = from.distance(from: to) * 1.3
        return max(1, Int((meters / 75).rounded(.up)))
    }
}
