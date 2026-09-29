import CoreLocation
import Foundation
import Observation
import UserNotifications

/// 0단계 위험 요소 2: 역 출구 위치 경계에서 앱이 몇 초 오차로 깨어나는지 기록한다.
/// 앱이 꺼져 있어도 경계 이벤트로 다시 깨어나므로, 앱 시작 시 반드시 만들어져 있어야 한다.
@Observable
final class GeofenceSpike: NSObject, CLLocationManagerDelegate {
    static let shared = GeofenceSpike()

    struct LogEntry: Codable, Identifiable {
        var id = UUID()
        let date: Date
        let kind: String      // "진입", "이탈", "실제 도착(직접)", "설정" 등
        let detail: String
    }

    private(set) var log: [LogEntry] = []
    private(set) var authorization: CLAuthorizationStatus = .notDetermined
    private(set) var monitoring = false
    var center = CLLocationCoordinate2D(latitude: 37.561391, longitude: 126.854456)   // 가양역 (역사 마스터 좌표)
    var radius: Double = 100
    private(set) var lastLocation: CLLocation?

    private let manager = CLLocationManager()
    private let regionId = "spike-station-exit"
    private let logKey = "geofenceSpikeLog"
    private let centerKey = "geofenceSpikeCenter"
    private var pendingSetCenter = false

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        authorization = manager.authorizationStatus
        if let data = UserDefaults.standard.data(forKey: logKey),
           let saved = try? JSONDecoder().decode([LogEntry].self, from: data) {
            log = saved
        }
        if let arr = UserDefaults.standard.array(forKey: centerKey) as? [Double], arr.count == 3 {
            center = CLLocationCoordinate2D(latitude: arr[0], longitude: arr[1])
            radius = arr[2]
        }
        monitoring = manager.monitoredRegions.contains { $0.identifier == regionId }
    }

    // MARK: 조작

    func requestAlways() {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else {
            manager.requestAlwaysAuthorization()
        }
    }

    func start() {
        let region = CLCircularRegion(center: center, radius: radius, identifier: regionId)
        region.notifyOnEntry = true
        region.notifyOnExit = true
        manager.startMonitoring(for: region)
        monitoring = true
        saveCenter()
        append("설정", String(format: "감시 시작 · 반경 %.0fm · %.6f, %.6f", radius, center.latitude, center.longitude))
    }

    func stop() {
        for r in manager.monitoredRegions where r.identifier == regionId { manager.stopMonitoring(for: r) }
        monitoring = false
        append("설정", "감시 중지")
    }

    /// 지금 서 있는 곳을 출구로 저장 (출구 앞에서 누른다)
    func useCurrentLocationAsCenter() {
        pendingSetCenter = true
        manager.requestLocation()
    }

    /// 실제로 출구에 도착한 순간 직접 누르는 기준값
    func markGroundTruth() {
        append("실제 도착(직접)", "사용자가 누름")
    }

    func clearLog() {
        log = []
        persist()
    }

    // MARK: 델리게이트

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorization = manager.authorizationStatus
        if authorization == .authorizedWhenInUse {
            manager.requestAlwaysAuthorization()
        }
    }

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        record("진입", region)
    }

    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        record("이탈", region)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        lastLocation = loc
        if pendingSetCenter {
            pendingSetCenter = false
            center = loc.coordinate
            saveCenter()
            append("설정", String(format: "현재 위치를 출구로 저장 · 정확도 %.0fm", loc.horizontalAccuracy))
            if monitoring { start() }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        append("오류", error.localizedDescription)
    }

    func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        append("오류", "감시 실패: \(error.localizedDescription)")
    }

    // MARK: 내부

    private func record(_ kind: String, _ region: CLRegion) {
        let app = UIApplicationStateText.current()
        append(kind, "앱 상태: \(app)")
        let content = UNMutableNotificationContent()
        content.title = "위치 감지 시험 · \(kind)"
        content.body = "\(Fmt.timeWithSeconds.string(from: .now)) · 실제 도착한 순간과 비교해 보세요"
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    private func append(_ kind: String, _ detail: String) {
        log.insert(LogEntry(date: .now, kind: kind, detail: detail), at: 0)
        if log.count > 200 { log.removeLast(log.count - 200) }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(log) {
            UserDefaults.standard.set(data, forKey: logKey)
        }
    }

    private func saveCenter() {
        UserDefaults.standard.set([center.latitude, center.longitude, radius], forKey: centerKey)
    }
}

import UIKit

enum UIApplicationStateText {
    static func current() -> String {
        guard Thread.isMainThread else { return "알 수 없음" }
        switch UIApplication.shared.applicationState {
        case .active: return "켜짐"
        case .inactive: return "전환 중"
        case .background: return "백그라운드"
        @unknown default: return "알 수 없음"
        }
    }
}
