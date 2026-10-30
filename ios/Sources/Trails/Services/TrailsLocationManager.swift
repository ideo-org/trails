import Foundation
import CoreLocation
import Combine

@MainActor
final class TrailsLocationManager: NSObject, ObservableObject {
    public static let shared = TrailsLocationManager()

    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var currentLocation: CLLocation?
    @Published private(set) var currentHeading: Double?

    public var lastKnownLocation: CLLocation? {
        currentLocation
    }

    private let manager = CLLocationManager()

    override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.headingFilter = 3.0
    }

    var statusDescription: String {
        switch authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            return currentLocation == nil ? "Acquiring GPS" : "GPS Locked"
        case .notDetermined:
            return "GPS Ready"
        case .denied, .restricted:
            return "GPS Off"
        @unknown default:
            return "GPS Unknown"
        }
    }

    func requestAccessIfNeeded() {
        switch authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            manager.startUpdatingLocation()
            if CLLocationManager.headingAvailable() {
                manager.startUpdatingHeading()
            }
        case .denied, .restricted:
            break
        @unknown default:
            break
        }
    }
}

extension TrailsLocationManager: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            authorizationStatus = manager.authorizationStatus
            if authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse {
                manager.startUpdatingLocation()
                if CLLocationManager.headingAvailable() {
                    manager.startUpdatingHeading()
                }
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            currentLocation = locations.last
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        Task { @MainActor in
            let heading = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
            currentHeading = heading
        }
    }
}
